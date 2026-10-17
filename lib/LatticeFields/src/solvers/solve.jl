# Solver vocabulary (§5.6), `inner = :auto`, launch plans and the driver (§6.3–§6.4). The
# driver only builds `Launch` objects and hands them to an executor through the protocol
# below (`alloc`, `launch!`, `fetch`); the CPU host runner of the tests and Exec implement it.

"""
A V-cycle with `nu1` pre- and `nu2` post-smoothing Chebyshev steps.
"""
struct V
    nu1::Int
    nu2::Int
end

"""
    Multigrid(; cycle = V(2, 2), cycles = nothing, rtol = 1e-6, budget = nothing, warn_tol)

Stationary multigrid. `cycles = k` runs exactly k cycles (no early exit; the sentinel warns
above `warn_tol`, default 1e-3); otherwise cycles stop on device when
`‖r‖∞ ≤ rtol·max(‖b‖∞, floor)`, within `budget` (default 8, 12 on a masked group).
"""
struct Multigrid
    cycle::V
    cycles::Union{Nothing, Int}
    rtol::Float64
    budget::Union{Nothing, Int}
    warn_tol::Float64
end
function Multigrid(; cycle = V(2, 2), cycles = nothing, rtol = 1e-6, budget = nothing,
        warn_tol = cycles === nothing ? rtol : 1e-3)
    Multigrid(cycle, cycles, rtol, budget, warn_tol)
end

"""
    DevicePCG(; precond = Multigrid(), budget = 8, rtol = 1e-6)

Preconditioned CG on device scalars; the preconditioner is one fixed V-cycle from zero
(a fixed linear SPD operator). K2 computes the true residual every iteration (fused with
`x += αp`), and `done` is set on it (N-13).
"""
Base.@kwdef struct DevicePCG
    precond::Multigrid = Multigrid()
    budget::Int = 8
    rtol::Float64 = 1e-6
end

"""
`inner = :auto` (§5.6, provisional D-C7b): every group gets `DevicePCG` (budget 8), with the
constant mode deflated on an unanchored group with a constant shift. Stationary V(2, 2)
needs 12 cycles or more on unanchored periodic groups (per256, per300), so it is used only
when asked for. An explicit stationary `Multigrid` defaults to budget 12 on a group with a
mask, a Dirichlet face or a non-constant face coefficient, else 8.
"""
function resolve_inner(op::CellOperator, inner)
    inner === :auto && return DevicePCG()
    if inner isa DevicePCG
        c = inner.precond
        c.cycle.nu1 == c.cycle.nu2 ||
            irerror("DevicePCG needs a symmetric preconditioner V(ν, ν), not V(",
                c.cycle.nu1, ", ", c.cycle.nu2, ")")
        c.cycles === nothing || c.cycles == 1 ||
            irerror("DevicePCG applies one preconditioner cycle; got cycles = ", c.cycles)
        return inner
    end
    inner isa Multigrid || irerror("unknown inner solver ", inner)
    b = inner.cycles !== nothing ? inner.cycles :
        inner.budget !== nothing ? inner.budget : jumpy(op) ? 12 : 8
    return Multigrid(inner.cycle, inner.cycles, inner.rtol, b, inner.warn_tol)
end

const COARSE_DEGREE = 8     # fixed Chebyshev degree on the coarsest level
const FLOOR = 1e-30         # ‖b‖∞ floor of the stop test

# ---- executor protocol ----------------------------------------------------------------------
"""
    alloc(exec, T, n)

A zeroed array of `n` elements of `T` on the executor's device.
"""
function alloc end
"""
    launch!(exec, l::Launch)

Enqueue launch `l` (no wait). `l.wg == 0`: `l.body(i, l.S, l.P, l.G)` for `i ∈ 1:l.n`.
Otherwise a workgroup launch (contract item 5): `l.n` workgroups of `l.wg` items run
`l.phases` barrier-separated phases `l.body(ph, g, t, lds, l.S, l.P, l.G)` with `l.ldslen`
elements of workgroup memory (`l.lds` is that memory for a host executor;
`Schedule.host_workgroups!` is the host form, `Schedule.workgroups!` the device wrapper).
"""
function launch! end
"""
    fetch(exec, A)

A host copy of device array `A` (a declared host pass: a sync).
"""
function fetch end

"""
The geometry object of the contract (item 4).
"""
struct SolverGeom{N, L, R, I, T}
    n::I
    dims::NTuple{L, NTuple{N, Int32}}
    rt::NTuple{R, T}
end

"""
One prepared launch: body, size, arrays, parameters and geometry (built once per plan);
`wg > 0` marks a workgroup launch of `n` groups (`phases`, `ldslen`, host memory `lds`).
"""
struct Launch{B, S, P, G, A}
    body::B
    n::Int
    S::S
    P::P
    G::G
    key::String
    wg::Int
    phases::Int
    ldslen::Int
    lds::A
end
Launch(body, n, S, P, G, key) = Launch(body, n, S, P, G, key, 0, 0, 0, nothing)
function Launch(exec, T, body, ngroups, S, P, G, key; phases, ldslen)
    Launch(body, ngroups, S, P, G, key, WG, phases, ldslen, alloc(exec, T, ldslen))
end

"""
A solve plan: segments of launches (setup, then one per cycle or iteration), the
two-buffer slots after each segment, and per segment the epilogue run after it when it is
the last segment that ran (bound to that segment's slots).
"""
struct SolvePlan
    segments::Vector{Vector{Any}}
    slots::Vector{Dict{Int32, Int}}
    epilogue::Vector{Vector{Any}}
end
nlaunches(sp::SolvePlan, seg) = length(sp.segments[seg])

mutable struct FieldSolver{N, E}
    exec::E
    op::CellOperator{N}
    alg::Union{Multigrid, DevicePCG}
    deflate::Bool
    prog::Program{N}
    ctx::Any
    T::Type                               # solver_T: the solver's number type
    state::Type                           # T: the caller-facing arrays' number type
    rule::RuleWeights
    bufs::Dict{Int32, Vector{Any}}
    slot::Dict{Int32, Int}
    tables::Dict{Int32, Any}
    bodies::Dict{String, Any}
    plans::Dict{Any, SolvePlan}
    auto::Bool                            # solver_T was :auto
    warned::Bool                          # the set_coefficients! solver_T warning was given
end

"""
    FieldSolver(exec, op::CellOperator; inner = :auto, T = Float32, solver_T = :auto,
        rule = RULE_M, stages, deflate = :auto)

Build the solver group of `op`: the program, its compiled bodies and its arrays on `exec`.

Number types, one per role (`*_T`, `:auto` by default; a later `precond_T` would join them):

  - `T`, the state type: the element type of the caller-facing arrays, the inputs
    (`"in.f"`, input coefficient fields) and the solution (`solution_key`). It never
    depends on `solver_T`; the solver converts at the boundary.
  - `solver_T`, the solver's arithmetic and working arrays (vectors, hierarchy,
    reductions, deflation, device scalars), `sv.T`. `:auto` (`resolve_solver_T`): Float64
    for a group in the Float32 floor regime (`floor_regime`: unanchored, reaction below
    `FLOOR_SHIFT`) when `supports(exec, Float64)`, else `T`. A type uses that type.

Lowered number types: Float32 and Float64; any other type is refused with an error naming
it. `deflate` (`:auto`: PCG on a `deflatable` group) solves for the zero-mean part in
`pcg.x` and carries the constant-mode coefficient `c = mean(b)/s` as a device scalar; the
solution `pcg.x − mean(pcg.x) + c` is written to `pcg.u` after every solve.
`deflate = false` is the undeflated reference form. A Float32 solution array limits its own
true residual (upper bound `eps(Float32)·|c|·‖A‖∞` relative to ‖b‖∞, D-C7b), whatever the
solver precision.
"""
function FieldSolver(exec, op::CellOperator{N}; inner = :auto, T::Type = Float32,
        solver_T = :auto, rule::RuleWeights = RULE_M, stages = LOWERING,
        deflate = :auto) where {N}
    state = lowered_type(exec, T, "state")
    T = resolve_solver_T(exec, op, state, solver_T)
    alg = resolve_inner(op, inner)
    cyc = alg isa DevicePCG ? alg.precond.cycle : alg.cycle
    (cyc.nu1 >= 1 && cyc.nu2 >= 1) || irerror("a V-cycle needs ν₁, ν₂ ≥ 1")
    dfl = deflate === :auto ? alg isa DevicePCG && deflatable(op) : Bool(deflate)
    lane(t) = t == Float64 ? F64 : F32
    p, ctx = solver_program(op, alg isa DevicePCG; lane = lane(T), state = lane(state),
        deflate = dfl)
    s = semantic(p)
    o = CompileOptions(; T)
    bodies = Dict{String, Any}()
    praw = coef_values(op)                # coefficients are runtime parameters (P5 C7b-2)
    for k in s.kernels
        ck = compile_kernel(s, k, o; stages)
        d = derive_function(ck)
        ck.timed && irerror("solver kernel `", k.key, "` derives parameters from t")
        # compute type sv.T; t is never read (check_no_time), so its value is irrelevant
        bodies[k.key] = (ck, body_function(ck), d(praw, zero(T), 0.0), d)
    end
    bufs, slot = Dict{Int32, Vector{Any}}(), Dict{Int32, Int}()
    for (i, f) in enumerate(s.fields)
        n = nsites(s, f.levels[1]) * ncomp(f)
        bufs[Int32(i)] = [alloc(exec, juliatype(f.storage), n) for _ in 1:(f.buffers)]
        slot[Int32(i)] = 1
    end
    nb = reduction_blocks(nsites(s, 0))
    tlen(k) = k == "solve.scal" ? SCALARS : k == "solve.gb" ? 2 : nb
    tables = Dict{Int32, Any}(Int32(i) => alloc(exec, T, tlen(t.key))
    for (i, t) in enumerate(s.tables))
    return FieldSolver{N, typeof(exec)}(
        exec, op, alg, dfl, s, ctx, T, state, rule, bufs, slot, tables, bodies,
        Dict{Any, SolvePlan}(), solver_T === :auto, false)
end

"""
The number types the solver lowers (lanes): any other is refused, naming the type and the
role.
"""
const LOWERED_TYPES = (Float32, Float64)

"""
    lowered_type(exec, S, role)

`S` if the solver lowers it and the executor supports it (`supports(exec, S)`, asked only
for types other than Float32), else an error naming `S`.
"""
function lowered_type(exec, S, role)
    S isa Type || irerror(role, " expects ", role == "solver_T" ? ":auto or " : "",
        "a number type; got ", repr(S))
    S in LOWERED_TYPES ||
        irerror("number type ", S, " (", role, ") is not lowered for this solver; ",
            "lowered: ", join(LOWERED_TYPES, ", "))
    S === Float32 || supports(exec, S) ||
        irerror("number type ", S, " (", role, ") is not supported by this executor ",
            "(supports(exec, ", S, ") is false)")
    return S
end

"""
    resolve_solver_T(exec, op, state, solver_T)

The solver's number type (provisional D-C7b): `:auto` is Float64 for a group in the
Float32 floor regime (`floor_regime(op)`) when `supports(exec, Float64)` (asked only
then), else the state type; on a backend without Float64 such a group stays in Float32,
ends `:floor` and the sentinel names it. A type is checked by `lowered_type`.
"""
function resolve_solver_T(exec, op::CellOperator, state::Type, solver_T)
    solver_T === :auto || return lowered_type(exec, solver_T, "solver_T")
    state === Float32 && floor_regime(op) && supports(exec, Float64) && return Float64
    return state
end

fid(sv::FieldSolver, key) = fieldid(sv.prog, key)
tid(sv::FieldSolver, key) = Int32(findfirst(t -> t.key == key, sv.prog.tables))
"""
The current array of field `key` (two-buffer fields: the current slot).
"""
function field(sv::FieldSolver, key)
    (id = fid(sv, key); sv.bufs[id][sv.slot[id]])
end
"""
The solution field, an array of the state type: `pcg.u` under deflation, `out.u` when the
solver type differs from the state type, else `pcg.x` under PCG or the finest level's `x`.
"""
function solution_key(sv::FieldSolver)
    sv.deflate ? "pcg.u" :
    sv.T != sv.state ? "out.u" :
    sv.alg isa DevicePCG ? "pcg.x" : lkey(0, "x")
end
"""
The working field a solve starts from (`steady!` zeroes it).
"""
working_key(sv::FieldSolver) = sv.alg isa DevicePCG ? "pcg.x" : lkey(0, "x")

"""
    set_coefficients!(sv, op)

Replace the numeric coefficients of the group (face, shift, value, Dirichlet values) by
those of `op`, which must have the same structure (dims, periodicity, mask, field keys, the
same coefficients numeric): new parameter values for every body, no recompile. The cached
plans are dropped; the next `rebuild!`/`lift!` (or `steady!`) uses the new values. The solver
number type (`solver_T = :auto`) stays as resolved at build.
"""
function set_coefficients!(sv::FieldSolver, op::CellOperator)
    o = sv.op
    same = op.dims == o.dims && op.periodic == o.periodic && op.mask == o.mask &&
           coef_slots(op) == coef_slots(o) &&
           all(map((x, y) -> x isa Real || x == y, op.face, o.face)) &&
           (op.shift isa Real || op.shift == o.shift) &&
           (op.value isa Real || op.value == o.value)
    same || irerror("set_coefficients!: the operator's structure differs from the group's")
    check_coefficients(op.face, op.shift, op.value, op.dirichlet)
    if sv.auto && !sv.warned && resolve_solver_T(sv.exec, op, sv.state, :auto) != sv.T
        sv.warned = true
        @warn string("set_coefficients!: solver_T = :auto would now resolve to ",
            resolve_solver_T(sv.exec, op, sv.state, :auto), ", but the group keeps ", sv.T,
            " (resolved at build; changing it recompiles). Pass solver_T explicitly or ",
            "rebuild the FieldSolver to change it.")
    end
    empty!(sv.plans)                      # bound the cache: plans are keyed by values
    return _set_values!(sv, op)
end
function _set_values!(sv::FieldSolver, op::CellOperator)
    praw = coef_values(op)
    for (k, (ck, fn, _, d)) in sv.bodies
        sv.bodies[k] = (ck, fn, d(praw, zero(sv.T), 0.0), d)
    end
    sv.op = op
    return sv
end

"""
    tangent!(sv, u, coef; homogeneous = true, maxiter = 64) -> u̇

The derivative of the solution `u` of the group's operator `A(θ) u = b(θ)` with respect to
one numeric coefficient `θ` (`coef`: `:shift`, `:value`, `(:face, a)` or
`(:dirichlet, a, k)`), by a tangent solve with the same solver (no Dual enters PCG or
multigrid, P5 §3.4): `A u̇ = ∂b/∂θ − (∂A/∂θ) u` with homogeneous boundary values. `u` is the
primal solution in solver precision (`solver_solution`). The right-hand side is exact
because `A` and `b` are affine in each coefficient: `r(θ + 1, u) − r(θ, u)`, both residuals
computed on the device by the `tangent.*` kernels after rebuilding the operator, and
written straight into the solver's right-hand side (the boundary data of `lift` is left
out: homogeneous). The coefficients, the right-hand side, the working field and the
solution array are restored afterwards, so a warm re-solve continues from the primal
state; `u̇` is only returned (a host copy). `homogeneous = false` keeps the primal boundary
values (the negative control of the tests).
"""
function tangent!(sv::FieldSolver, u::AbstractVector, coef; homogeneous::Bool = true,
        maxiter::Int = 64)
    op = sv.op
    θ1 = collect(coef_values(op))
    j = _coef_slot(coef_slots(op), coef)
    j == 0 && irerror("tangent!: ", coef, " is not a numeric coefficient of the group")
    θ1[j] += 1
    slot0 = copy(sv.slot)                 # the primal working state (warm starts)
    wid, sk = fid(sv, working_key(sv)), solution_key(sv)
    w = sv.bufs[wid][sv.slot[wid]]
    w0 = fetch(sv.exec, w)
    s0 = sk == working_key(sv) ? nothing : fetch(sv.exec, field(sv, sk))
    copyto!(w, convert(Vector{eltype(w0)}, u))
    rebuild!(sv)                          # r(θ, u) into d
    lift!(sv)
    _run_one!(sv, "tangent.r0")
    _set_values!(sv, _with_values(op, θ1))
    rebuild!(sv)                          # r(θ + 1, u) − r(θ, u) into d
    lift!(sv)
    _run_one!(sv, "tangent.dr")
    _set_values!(sv, op)
    rebuild!(sv)
    lift!(sv)
    _run_one!(sv, "tangent.rhs"; rt = (homogeneous ? 0.0 : 1.0, 0.0))
    foreach(A -> fill!(A, zero(eltype(A))), sv.bufs[wid])
    solve!(sv; host = true, budget = maxiter)
    du = solver_solution(sv)
    lift!(sv)                             # restore b, the working state and the solution
    merge!(sv.slot, slot0)
    copyto!(sv.bufs[wid][sv.slot[wid]], w0)
    s0 === nothing || copyto!(field(sv, sk), s0)
    return du
end

function _run_one!(sv::FieldSolver, key; rt = (0.0, 0.0))
    sp = _plan(sv, (key, rt)) do s
        pl = PlanBuilder(s)
        gen!(pl, key; rt)
        SolvePlan(pl)
    end
    run!(sv, sp)
    return sv
end

function _coef_slot(cs, coef)
    coef === :shift && return cs.shift
    coef === :value && return cs.value
    coef isa Tuple && length(coef) == 2 && coef[1] === :face && return cs.face[coef[2]]
    coef isa Tuple && length(coef) == 3 && coef[1] === :dirichlet &&
        return cs.dirichlet[coef[2]][coef[3]]
    irerror("tangent!: unknown coefficient ", coef)
end

"""
`op` with its numeric coefficients replaced by `v` (slot order, `coef_slots`).
"""
function _with_values(op::CellOperator{N}, v) where {N}
    cs = coef_slots(op)
    pick(x, s) = s > 0 ? v[s] : x
    face = ntuple(a -> pick(op.face[a], cs.face[a]), N)
    dir = ntuple(a -> ntuple(k -> pick(op.dirichlet[a][k], cs.dirichlet[a][k]), 2), N)
    return CellOperator(op.dims; periodic = op.periodic, face,
        shift = pick(op.shift, cs.shift), mask = op.mask,
        value = pick(op.value, cs.value), dirichlet = dir)
end

"""
The group's solution in the solver's own precision on the host (a sync): under deflation
`pcg.x − mean(pcg.x) + c`, else the working field.
"""
function solver_solution(sv::FieldSolver)
    x = fetch(sv.exec, field(sv, working_key(sv)))
    sv.deflate || return x
    return x .- sum(x) / length(x) .+ sv.T(scalars(sv).mean)
end

# ---- plan building --------------------------------------------------------------------------
struct PlanBuilder
    sv::Any
    budget::Int
    slot::Dict{Int32, Int}
    segments::Vector{Vector{Any}}
    slots::Vector{Dict{Int32, Int}}
    epilogue::Vector{Vector{Any}}
end
function PlanBuilder(sv; budget = sv.alg.budget)
    PlanBuilder(sv, budget, copy(sv.slot), [Any[]], Dict{Int32, Int}[], Vector{Any}[])
end
function segment!(pl::PlanBuilder)
    _epilogue!(pl)
    push!(pl.slots, copy(pl.slot))
    push!(pl.segments, Any[])
    return pl
end
function SolvePlan(pl::PlanBuilder)
    _epilogue!(pl)
    SolvePlan(pl.segments, [pl.slots; copy(pl.slot)], pl.epilogue)
end
"""
The epilogue after the current segment: the solution in the state type, `pcg.out` under
deflation, else `solve.out` when the solver type differs from the state type.
"""
function _epilogue!(pl::PlanBuilder)
    sv = pl.sv
    ep = Any[]
    key = sv.deflate && sv.alg isa DevicePCG ? "pcg.out" :
          sv.T != sv.state ? "solve.out" : nothing
    if key !== nothing
        gen!(pl, key)
        push!(ep, pop!(pl.segments[end]))
    end
    push!(pl.epilogue, ep)
    return pl
end

function _arr(pl::PlanBuilder, id, role)
    sv = pl.sv
    role == :table && return sv.tables[id]
    b = sv.bufs[id]
    length(b) == 1 && return b[1]
    return b[role == :cur ? pl.slot[id] : 3 - pl.slot[id]]
end

"""
The runtime slots of a solver launch: the two solver scalars `rt` at `SOLVER_RT`, and 0 at
the reserved time slot (never read by a solver kernel).
"""
function _rt(T, rt)
    ntuple(i -> T(i == TIME_SLOT ? 0.0 : rt[findfirst(==(i), SOLVER_RT)]),
        max(TIME_SLOT, SOLVER_RT...))
end

"""
Append the generated kernel `key` (runtime values `rt`) with the current slot binding.
"""
function gen!(pl::PlanBuilder, key; rt = (0.0, 0.0))
    sv = pl.sv
    ck, fn, P = sv.bodies[key]
    k = ck.kernel
    S = Tuple(Tuple(_arr(pl, id, role) for (id, role) in lane) for lane in ck.args)
    n = nsites(sv.prog, k.space.level)
    dims = Tuple(map(Int32, leveldims(sv.prog, lv)) for lv in ck.levels)
    if isempty(k.reductions)
        G = SolverGeom(ck.I(n), dims, _rt(sv.T, rt))
        push!(pl.segments[end], Launch(fn, n, S, P, G, key))
    else                                  # workgroup form: one group per 256-site block
        nb = reduction_blocks(n)
        G = SolverGeom(ck.I(WG * nb), dims, _rt(sv.T, rt))
        push!(pl.segments[end],
            Launch(sv.exec, sv.T, fn, nb, S, P, G, key; phases = REDUCE_PHASES,
                ldslen = reduce_lds(ck)))
    end
    for s in k.stores
        f = s.access.field
        length(sv.bufs[f]) == 2 && (pl.slot[f] = 3 - pl.slot[f])
    end
    return pl
end

const INIT, SETUP, NORM, FIN_RZ, FIN_ALPHA, FIN_IT, FIN_MEAN = Int32.(1:7)

function fin!(pl::PlanBuilder, op)
    sv = pl.sv
    T = sv.T
    alg = sv.alg
    budget = pl.budget                    # the plan's budget, not the algorithm's
    rtol, warn = alg isa DevicePCG ? (alg.rtol, alg.rtol) :
                 (alg.cycles === nothing ? alg.rtol : 0.0, alg.warn_tol)
    tk = ("solve.scal", "solve.pr", "solve.pb", "solve.pd",
        sv.deflate ? "solve.ps" : "solve.pd", sv.deflate ? "solve.pq" : "solve.pd",
        "solve.px")
    S = Tuple(sv.tables[tid(sv, k)] for k in tk)
    red, sum = _combos(op, sv.deflate)
    G = (; op, red, sum, wg = Int32(WG), n = Int32(length(S[2])), rtol = T(rtol),
        floor = T(FLOOR),
        budget = Int32(budget), warn = T(warn),
        nsite = T(nsites(sv.prog, 0)), shift = T(sv.op.shift isa Real ? sv.op.shift : 0),
        deflate = sv.deflate, stall = !(alg isa Multigrid && alg.cycles !== nothing),
        diverge = alg isa Multigrid)
    push!(pl.segments[end],
        Launch(sv.exec, T, finish!, 1, S, (), G, "finish.$op"; phases = REDUCE_PHASES,
            ldslen = NCOMBO * WG))
    return pl
end

const NCOMBO = 5                          # partial tables a finishing pass combines

"""
The partials a finishing op combines: up to `NCOMBO` `(table, sum?)` pairs, the table an
index into `(scal, pr, pb, pd, ps, pq, px)` (0: unused). `px` is the rounding scale.
"""
function _combos(op, deflate)
    c = op == FIN_MEAN ? ((5, true), (6, true)) :
        op == SETUP ? ((2, false), (3, false), (7, false)) :
        op == NORM ? ((2, false), (7, false)) :
        op == FIN_RZ ? (deflate ? ((4, true), (5, true), (6, true)) : ((4, true),)) :
        op == FIN_ALPHA ? ((4, true),) :
        op == FIN_IT ?
        (deflate ? ((2, false), (7, false), (4, true), (5, true), (6, true)) :
         ((2, false), (7, false), (4, true))) :
        ()
    red = ntuple(q -> q <= length(c) ? Int32(c[q][1]) : Int32(0), NCOMBO)
    sum = ntuple(q -> q <= length(c) ? c[q][2] : true, NCOMBO)
    return red, sum
end

function _levelarrays(pl, F::LevelFields)
    (_arr(pl, F.active, :cur), map(w -> _arr(pl, w, :cur), F.w),
        _arr(pl, F.s, :cur), _arr(pl, F.sbox, :cur), _arr(pl, F.sint, :cur))
end

function _bottom!(pl::PlanBuilder, ν)
    sv, ctx = pl.sv, pl.sv.ctx
    ls = ctx.lv[(ctx.lb + 1):(ctx.L + 1)]
    get(f) = Tuple(_arr(pl, f(F), :cur) for F in ls)
    N = length(sv.op.dims)                # faces per axis: `ws[a][l]` (no tuple of tuples)
    S = (get(F -> F.active), ntuple(a -> Tuple(_arr(pl, F.w[a], :cur) for F in ls), N),
        get(F -> F.s), get(F -> F.sbox), get(F -> F.sint), get(F -> F.x), get(F -> F.b),
        get(F -> F.r), get(F -> F.d), sv.tables[tid(sv, "solve.scal")],
        sv.tables[tid(sv, "solve.gb")])
    G = (; dims = Tuple(map(Int32, Tuple(ctx.dims[l + 1])) for l in (ctx.lb):(ctx.L)),
        per = sv.op.periodic, wg = Int32(WG), nu1 = Int32(ν.nu1), nu2 = Int32(ν.nu2),
        degree = Int32(COARSE_DEGREE))
    nph = bottom_phases(length(ls), ν.nu1, ν.nu2, COARSE_DEGREE)
    push!(pl.segments[end],
        Launch(sv.exec, sv.T, bottom!, 1, S, (), G, "bottom"; phases = nph, ldslen = 1))
    return pl
end

"""
Chebyshev coefficients `(c₁, c₂)` of step `k` on `[λ/4, λ]`, λ = 2 (the Gershgorin bound of
D⁻¹A for any weakly diagonally dominant row).
"""
function cheb_coefs(ν)
    θ, δ = 1.25, 0.75
    σ = θ / δ
    out, ρ = [(0.0, 1 / θ)], 1 / σ
    for _ in 2:ν
        ρn = 1 / (2σ - ρ)
        push!(out, (ρn * ρ, 2ρn / δ))
        ρ = ρn
    end
    return out
end

"""
One V-cycle on the finest level's `x` with right-hand side `b` (`zero_fine`: from x = 0, the
preconditioner form); `rz` fuses the partial `r·z` into the last finest-level kernel.
"""
function vcycle!(pl::PlanBuilder, ν::V; zero_fine::Bool, rz::Bool = false)
    ctx = pl.sv.ctx
    pre, post = cheb_coefs(ν.nu1), cheb_coefs(ν.nu2)
    for l in 0:(ctx.lb - 1)
        for k in 1:(ν.nu1)
            z = k == 1 && (l > 0 || zero_fine)
            gen!(pl, string(z ? "zstep" : "step", ".", lkey(l, "")); rt = pre[k])
        end
        gen!(pl, string("restrict.", lkey(l + 1, "")))
    end
    _bottom!(pl, ν)
    for l in (ctx.lb - 1):-1:0
        last(k) = rz && l == 0 && k == ν.nu2 ? ".rz" : ""
        gen!(pl, string("prolong", last(1), ".", lkey(l, "")); rt = post[1])
        for k in 2:(ν.nu2)
            gen!(pl, string("step", last(k), ".", lkey(l, "")); rt = post[k])
        end
    end
    return pl
end

"""
The hierarchy rebuild (after every σ-moving entry): fill the finest coefficients, then the
rule-M build of every coarser level.
"""
function rebuild_plan(sv::FieldSolver)
    pl = PlanBuilder(sv)
    gen!(pl, "fill")
    ctx, r = sv.ctx, sv.rule
    for l in 1:(ctx.L)
        F, C = ctx.lv[l], ctx.lv[l + 1]
        S = (_levelarrays(pl, F), _levelarrays(pl, C))
        P = map(sv.T, (r.inside, r.plane, r.inherited, r.box))
        G = (; n = Int32(nsites(sv.prog, l)), dimsf = Int32.(Tuple(ctx.dims[l])),
            dimsc = Int32.(Tuple(ctx.dims[l + 1])), n0 = Int32.(sv.op.dims),
            level = Int32(l), per = sv.op.periodic, majority = r.majority)
        push!(pl.segments[end], Launch(build_site!, nsites(sv.prog, l), S, P, G, "build"))
    end
    C = ctx.lv[ctx.L + 1]                 # the coarsest Gershgorin interval for the bottom
    S = (_levelarrays(pl, C)..., sv.tables[tid(sv, "solve.gb")])
    G = (; dims = Int32.(Tuple(ctx.dims[ctx.L + 1])), per = sv.op.periodic, wg = Int32(WG))
    push!(pl.segments[end],
        Launch(sv.exec, sv.T, gershgorin!, 1, S, (), G, "gershgorin";
            phases = REDUCE_PHASES, ldslen = 2WG))
    return SolvePlan(pl)
end

"""
The budgeted solve: a setup segment, then `budget` segments (cycles or PCG iterations).
"""
function solve_plan(sv::FieldSolver, budget::Int)
    pl = PlanBuilder(sv; budget)
    fin!(pl, INIT)
    if sv.alg isa Multigrid
        gen!(pl, "resid")
        fin!(pl, SETUP)
        for _ in 1:budget
            segment!(pl)
            vcycle!(pl, sv.alg.cycle; zero_fine = false)
            gen!(pl, "resid")
            fin!(pl, NORM)
        end
    else
        ν = sv.alg.precond.cycle
        if sv.deflate
            gen!(pl, "pcg.center")
            fin!(pl, FIN_MEAN)
        end
        gen!(pl, "pcg.true")
        fin!(pl, SETUP)
        vcycle!(pl, ν; zero_fine = true, rz = true)
        fin!(pl, FIN_RZ)
        for _ in 1:budget
            segment!(pl)
            gen!(pl, "pcg.k1")
            fin!(pl, FIN_ALPHA)
            gen!(pl, "pcg.k2")
            vcycle!(pl, ν; zero_fine = true, rz = true)
            fin!(pl, FIN_IT)
        end
    end
    return SolvePlan(pl)
end

"""
One preconditioner application `z = M r` (finest `b` → finest `x`), for the symmetry test.
"""
function precond_plan(sv::FieldSolver)
    pl = PlanBuilder(sv)
    fin!(pl, INIT)
    ν = sv.alg isa DevicePCG ? sv.alg.precond.cycle : sv.alg.cycle
    vcycle!(pl, ν; zero_fine = true)
    return SolvePlan(pl)
end

function _plan(f::F, sv::FieldSolver, name) where {F}
    key = (name, sort!(collect(sv.slot)), coef_values(sv.op))   # P and G hold the values
    return get!(() -> f(sv), sv.plans, key)
end

"""
Run plan `sp`; with `host = true` read the `done` flag after every segment and stop when it
is set (a declared host pass). Returns the number of segments run.
"""
function run!(sv::FieldSolver, sp::SolvePlan; host::Bool = false)
    scal = sv.tables[tid(sv, "solve.scal")]
    nseg = length(sp.segments)
    for (k, seg) in enumerate(sp.segments)
        foreach(l -> launch!(sv.exec, l), seg)
        if host && k < nseg && fetch(sv.exec, scal)[DONE] != 0
            nseg = k
            break
        end
    end
    foreach(l -> launch!(sv.exec, l), sp.epilogue[nseg])
    merge!(sv.slot, sp.slots[nseg])
    return nseg
end

rebuild!(sv::FieldSolver) = (run!(sv, _plan(rebuild_plan, sv, :rebuild)); sv)
lift!(sv::FieldSolver) = (run!(sv, _plan(s -> lift_plan(s), sv, :lift)); sv)
lift_plan(sv) = (pl = PlanBuilder(sv); gen!(pl, "lift"); SolvePlan(pl))

"""
    solve!(sv; host = false, budget)

The inner solve from the current solution. Device mode enqueues the whole budgeted plan
(no sync). Host mode stops at `done` and returns the iteration count.
"""
function solve!(sv::FieldSolver; host::Bool = false,
        budget::Int = sv.alg.budget)
    sp = _plan(s -> solve_plan(s, budget), sv, (:solve, budget))
    run!(sv, sp; host)
    return host ? iterations(sv) : nothing
end

"""
Device scalars on the host (a sync): `(; status, done, iter, rnorm, bnorm, tol, warn, mean, best, scale)` (`best`: the best true residual; `scale`: the rounding scale max(|b| + |A||x|)
of the last check). `status` is `:done` (converged), `:floor` (stagnated at rounding level
above the tolerance), `:diverged` (the residual grew) or `:budget`.
"""
function scalars(sv::FieldSolver)
    s = fetch(sv.exec, sv.tables[tid(sv, "solve.scal")])
    status = (:budget, :done, :floor, :diverged)[Int(s[DONE]) + 1]
    return (; status, done = status === :done, iter = Int(s[ITER]),
        rnorm = Float64(s[RNORM]), bnorm = Float64(s[BNORM]), tol = Float64(s[TOL]),
        warn = s[WARN] != 0, mean = Float64(s[MEAN]), best = Float64(s[BEST]),
        scale = Float64(s[SCALE]))
end
iterations(sv::FieldSolver) = scalars(sv).iter

"""
The residual sentinel, read at an existing sync: warns (once per call) when the last
budgeted solve ended above its tolerance; returns whether it fired.
"""
function sentinel(sv::FieldSolver)
    s = scalars(sv)
    s.warn || return false
    hint = sv.alg isa Multigrid ? " Stationary multigrid: use DevicePCG (inner = :auto)." :
           s.status === :floor && sv.T == Float32 && floor_regime(sv.op) ?
           " Float32 floor of an unanchored group at weak reaction: solve in Float64 " *
           "(solver_T; a backend with Float64)." :
           ""
    what = s.status === :floor ? "stagnated (floor)" :
           s.status === :diverged ? "diverged" : "ended"
    @warn string("field solve ", what, " at ‖r‖∞ = ", s.rnorm, " > tolerance after ",
        s.iter, " iterations.", hint)
    return true
end

"""
    steady!(sv; maxiter = 64)

`init = :steady` (§6.4): rebuild, lift, solve from zero with the group's inner solver to
`rtol = 1e-6`, host-checked. Returns the iteration count.
"""
function steady!(sv::FieldSolver; maxiter::Int = 64)
    rebuild!(sv)
    lift!(sv)
    id = fid(sv, working_key(sv))
    foreach(A -> fill!(A, zero(eltype(A))), sv.bufs[id])
    fixed = sv.alg isa Multigrid && sv.alg.cycles !== nothing
    return solve!(sv; host = true, budget = fixed ? sv.alg.cycles : maxiter)
end

# ---- the finishing pass (device scalars; one workgroup) -------------------------------------
"""
    finish!(ph, g, t, lds, S, P, G)

One workgroup in 9 phases. Phase 1: item `t` combines the partials `t, t + 256, …` of each
table of `G.red` (sum or max, in order; coalesced); phases 2–9: the halving tree; item 1
then updates the device scalars (`G.op`): INIT, FIN_MEAN (means of `b` and `x`,
`c = mean(b)/s`), SETUP (‖b‖∞, tolerance, `done`), NORM (stationary cycle), FIN_RZ (`β`;
under deflation `r·(z − z̄)` and `z̄`), FIN_ALPHA (`α`), FIN_IT (the true residual of K2:
iteration count, `done`, floor, sentinel; then FIN_RZ).
"""
function finish!(ph, g, t, lds, S, P, G)
    T = eltype(S[1])
    W = Int32(G.wg)
    n = Int32(G.n)
    if ph == one(ph)
        for q in 1:NCOMBO
            @inbounds src, add = G.red[q], G.sum[q]                 # q ≤ NCOMBO
            acc = add ? zero(T) : typemin(T)
            if src > 0
                @inbounds A = S[src]                                # src ≤ 7 = length(S)
                for i in t:W:n
                    @inbounds acc = add ? acc + A[i] : max(acc, A[i])   # i ≤ n = length(A)
                end
            end
            @inbounds lds[t + W * Int32(q - 1)] = acc               # lds has NCOMBO·W
        end
    else
        stride = W >> (ph - one(ph))
        if t <= stride
            for q in 1:NCOMBO
                o = W * Int32(q - 1)
                @inbounds a, b = lds[t + o], lds[t + stride + o]    # t + stride ≤ W
                @inbounds lds[t + o] = G.sum[q] ? a + b : max(a, b)
            end
        end
        if (ph == Int32(9)) & (t == one(t))
            @inbounds v = (lds[1], lds[1 + W], lds[1 + 2W], lds[1 + 3W], lds[1 + 4W])   # NCOMBO = 5
            _update!(S[1], G, v)
        end
    end
    return nothing
end

"""
The scalar update of `finish!` from the combined partials `v` (in `G.red` order).
"""
function _update!(scal, G, v)
    T = eltype(scal)
    op = G.op
    @inbounds begin                       # scal has SCALARS entries
        if op == INIT
            for i in 1:SCALARS
                scal[i] = zero(T)
            end
            return nothing
        end
        done = scal[DONE] != zero(T)
        if op == FIN_MEAN
            bm, xm = v[1] / G.nsite, v[2] / G.nsite
            scal[BMEAN], scal[XMEAN] = bm, xm
            scal[MEAN] = G.shift == zero(T) ? zero(T) : bm / G.shift   # s = 0: the zero-mean solution
        elseif op == SETUP
            rn, bn = v[1], v[2]
            tol = G.rtol * max(bn, G.floor)
            scal[RNORM], scal[BNORM], scal[TOL], scal[BEST] = rn, bn, tol, floatmax(T)
            scal[SCALE], scal[PREV], scal[GROW] = v[3], rn, zero(T)
            scal[DONE] = rn <= tol ? one(T) : zero(T)
        elseif done
            return nothing
        elseif op == NORM
            scal[RNORM] = v[1]
            scal[ITER] += one(T)
            _stop!(scal, G, v[1], v[2])
            _sentinel!(scal, G, v[1])
        elseif op == FIN_RZ
            _beta!(scal, G, v[1], v[2], v[3])
        elseif op == FIN_ALPHA
            scal[ALPHA] = v[1] == zero(T) ? zero(T) : scal[RZ] / v[1]
        elseif op == FIN_IT
            scal[RNORM] = v[1]
            scal[ITER] += one(T)
            _stop!(scal, G, v[1], v[2])
            _sentinel!(scal, G, v[1])
            scal[DONE] == zero(T) && _beta!(scal, G, v[3], v[4], v[5])
        end
    end
    return nothing
end

"""
`β` and `r·z` from the partial sums `Σ r·z` (`rz`), and under deflation `Σ z`, `Σ r`:
`r·(z − z̄) = Σ r·z − z̄ Σ r`.
"""
@inline function _beta!(scal, G, rz, sz, sr)
    T = eltype(scal)
    @inbounds begin                                                  # scal has SCALARS entries
        if G.deflate
            zm = sz / G.nsite
            rz -= zm * sr
            scal[ZMEAN] = zm
        end
        scal[BETA] = scal[ITER] == zero(T) || scal[RZ] == zero(T) ? zero(T) : rz / scal[RZ]
        scal[RZ] = rz
    end
    return nothing
end

"""
The stop test on a true residual `rn` with rounding scale `sc = max(|b| + |A||x|)`:

  - `done` (1) at the tolerance;
  - floor (2): `STALL_CHECKS` consecutive checks without a `STALL_GAIN` improvement on the
    best residual of the earlier checks (the setup residual is not one: the max-norm
    residual may first grow), and the best residual at rounding level,
    `best ≤ FLOOR_ULPS·eps(T)·sc`; a slow solve above that level runs on to its budget;
  - diverged (3), stationary multigrid only (`G.diverge`): `GROW_CHECKS` consecutive
    checks that grew, and `rn > GROW_FACTOR·best`. PCG with an SPD preconditioner cannot
    diverge in the A-norm, and its max-norm residual may wander far above its best on a
    slow solve that still converges.

A stopped solve never reports `done`; fixed-cycle solves never stop early.
"""
@inline function _stop!(scal, G, rn, sc)
    T = eltype(scal)
    @inbounds begin                                                  # scal has SCALARS entries
        stalled = rn > T(STALL_GAIN) * scal[BEST]
        scal[STALL] = stalled ? scal[STALL] + one(T) : zero(T)
        scal[GROW] = rn > scal[PREV] ? scal[GROW] + one(T) : zero(T)
        scal[PREV], scal[SCALE] = rn, sc
        scal[BEST] = min(scal[BEST], rn)
        atfloor = (scal[STALL] >= T(STALL_CHECKS)) &
                  (scal[BEST] <= T(FLOOR_ULPS) * eps(T) * sc)
        diverged = (scal[GROW] >= T(GROW_CHECKS)) & (rn > T(GROW_FACTOR) * scal[BEST])
        scal[DONE] = rn <= scal[TOL] ? one(T) :
                     G.stall & atfloor ? T(2) :
                     G.stall & G.diverge & diverged ? T(3) : zero(T)
    end
    return nothing
end
const STALL_GAIN = 0.9
const STALL_CHECKS = 3
const FLOOR_ULPS = 4          # measured floors: best = 0.11–0.48 ε·scale (D-C7b)
const GROW_CHECKS = 3
const GROW_FACTOR = 2

@inline function _sentinel!(scal, G, rn)
    T = eltype(scal)
    @inbounds if scal[DONE] == one(T)                               # scal has SCALARS entries
        scal[WARN] = zero(T)
    elseif scal[DONE] >= T(2) || scal[ITER] >= T(G.budget)
        scal[WARN] = rn > G.warn * max(scal[BNORM], G.floor) ? one(T) : zero(T)
    end
    return nothing
end

# Solver vocabulary (§5.6), `linsolve = :auto`, launch plans and the driver (§6.3–§6.4). The
# driver only builds `Launch` objects and hands them to an executor through the protocol
# below (`alloc`, `launch!`, `to_host`); the CPU host runner of the tests and Exec implement it.

"""
    VCycle(nu1, nu2)

A V-cycle with `nu1` pre- and `nu2` post-smoothing Chebyshev steps, integers ≥ 1. A
`LatticeMultigrid`'s `cycle` also takes the pair `(nu1, nu2)`, which is how it prints.
"""
struct VCycle
    nu1::Int
    nu2::Int
    function VCycle(nu1::Integer, nu2::Integer)
        (nu1 >= 1 && nu2 >= 1 && !(nu1 isa Bool) && !(nu2 isa Bool)) || throw(
            ArgumentError(
                string(
                    "`VCycle(", nu1, ", ", nu2,
                    ")`: a V-cycle (the `cycle` of a `LatticeMultigrid`) needs ν₁, ν₂ ≥ 1 smoothing steps, pre and post; ",
                    "for example `VCycle(2, 2)`",
                )
            )
        )
        return new(nu1, nu2)
    end
end
VCycle(nu1, nu2) = throw(
    ArgumentError(
        string(
            "`VCycle(", repr(nu1), ", ", repr(nu2), ")`: a V-cycle's smoothing steps ν₁, ν₂ ",
            "(pre and post) are integers ≥ 1; for example `VCycle(2, 2)`"
        )
    )
)

_positive(x) = x isa Real && !(x isa Bool) && isfinite(x) && x > 0
_count(x) = x isa Integer && !(x isa Bool) && x >= 1
# a `cycle` keyword: a `VCycle`, or the pair `(ν₁, ν₂)`
_cycle(c::VCycle) = c
_cycle(c::Tuple{Any, Any}) = VCycle(c...)
_cycle(c) = throw(
    ArgumentError(
        string(
            "`LatticeMultigrid(; cycle = ", repr(c), ")`: `cycle` is the V-cycle's smoothing ",
            "steps, `(ν₁, ν₂)` or `VCycle(ν₁, ν₂)` (integers ≥ 1); for example `cycle = (2, 2)`"
        )
    )
)

"""
    LatticeMultigrid(; cycle = VCycle(2, 2), cycles = nothing, reltol = nothing, maxiters = nothing, warn_tol = nothing)

The lattice multigrid, both as a LinearSolve algorithm (stationary multigrid solve) and as a
LinearSolve `precs` function (`precs(A, p) -> (Pl, Pr)`):

  - As a stationary linear solver (`linsolve = LatticeMultigrid(…)`): `cycles = k` runs
    exactly `k` cycles (no early exit; the sentinel warns above `warn_tol`, default `1e-3`).
    With `cycles = nothing`, cycles stop on device when `‖r‖∞ ≤ reltol * max(‖b‖∞, floor)`
    within `maxiters` (when unset: `reltol` and `maxiters` come from `solve`, or `1e-6` and
    `8`/`12` on the owned steppers and unset standalone solves).
  - As a `precs` preconditioner (`precs = LatticeMultigrid(…)`):
    - Given a lattice field's operator (`BoundOperator`), it returns the V-cycle that
      [`LatticePCG`](@ref) fuses into its iteration (`cycle` symmetric, `cycles` unset or `1`)
      and applies `cycles` V-cycles from zero through `ldiv!` for generic Krylov methods.
    - Given the `W = J − M/γ` of an implicit SciML solver on a problem `discretize` returned
      (or the operator of a linear system with no time), it binds the owned implicit runtime
      of the problem at the solver's state and applies `something(cycles, 1)` V-cycles per
      field as `ldiv!`.

`cycle` is `(ν₁, ν₂)` or `VCycle(ν₁, ν₂)`, `cycles` and `maxiters` are integers ≥ 1 (or left
out), `reltol` and `warn_tol` finite and > 0; any other value is an `ArgumentError` naming the
keyword.
"""
struct LatticeMultigrid <: LinearSolve.SciMLLinearSolveAlgorithm
    cycle::VCycle
    cycles::Union{Nothing, Int}
    reltol::Union{Nothing, Float64}
    maxiters::Union{Nothing, Int}
    warn_tol::Union{Nothing, Float64}
    engines::Dict{Any, Any}
    lock::ReentrantLock
    function LatticeMultigrid(cycle::VCycle, cycles, reltol, maxiters, warn_tol, engines, lock)
        bad(k, v, want) = throw(ArgumentError(string("`LatticeMultigrid(; ", k, " = ", repr(v), ")`: `", k, "` ", want)))
        cycles === nothing || _count(cycles) ||
            bad(:cycles, cycles, "is the exact number of cycles, an integer ≥ 1 (leave it out to stop on `reltol`)")
        reltol === nothing || _positive(reltol) ||
            bad(:reltol, reltol, "is the relative residual a solve stops at, finite and > 0")
        maxiters === nothing || _count(maxiters) ||
            bad(:maxiters, maxiters, "is the most cycles per solve, an integer ≥ 1 (leave it out for the default)")
        warn_tol === nothing || _positive(warn_tol) ||
            bad(:warn_tol, warn_tol, "is the residual the sentinel warns above, finite and > 0")
        return new(
            cycle,
            cycles === nothing ? nothing : Int(cycles),
            reltol === nothing ? nothing : Float64(reltol),
            maxiters === nothing ? nothing : Int(maxiters),
            warn_tol === nothing ? nothing : Float64(warn_tol),
            engines,
            lock,
        )
    end
end
function LatticeMultigrid(;
        cycle = VCycle(2, 2), cycles = nothing, reltol = nothing, maxiters = nothing,
        warn_tol = nothing,
    )
    return LatticeMultigrid(_cycle(cycle), cycles, reltol, maxiters, warn_tol, Dict{Any, Any}(), ReentrantLock())
end
LatticeMultigrid(cycle::VCycle, cycles, reltol, maxiters, warn_tol) =
    LatticeMultigrid(cycle, cycles, reltol, maxiters, warn_tol, Dict{Any, Any}(), ReentrantLock())
Base.:(==)(a::LatticeMultigrid, b::LatticeMultigrid) =
    a.cycle == b.cycle && a.cycles == b.cycles && a.reltol == b.reltol &&
    a.maxiters == b.maxiters && a.warn_tol == b.warn_tol
Base.hash(a::LatticeMultigrid, h::UInt) =
    hash((a.cycle.nu1, a.cycle.nu2, a.cycles, a.reltol, a.maxiters, a.warn_tol), hash(:LatticeMultigrid, h))

"""
    FusedPCG(precond::LatticeMultigrid, maxiters, reltol)

The resolved form of a [`LatticePCG`](@ref) that a `FieldSolver` runs: preconditioned CG on
device scalars, the preconditioner one fixed V-cycle (`precond.cycle`) from zero (a fixed
linear SPD operator), fused into the iteration. K2 computes the true residual every iteration
(fused with `x += αp`), and `done` is set on it. `maxiters` is an integer ≥ 1 and `reltol`
finite and > 0.
"""
struct FusedPCG
    precond::LatticeMultigrid
    maxiters::Int
    reltol::Float64
end

# Keyword display (no module path; only the keywords that differ from their defaults), so a
# message that quotes a solver reads as the user wrote it, and the text runs where the solvers
# are bound (`using Potts` or `using LatticePDE`: a cycle prints as the pair `(ν₁, ν₂)`).
# `canonical` is the hashed text.
Base.show(io::IO, v::VCycle) = print(io, "VCycle(", v.nu1, ", ", v.nu2, ")")
function _show_kw(io::IO, name, kws)
    print(io, name, "(")
    isempty(kws) || print(io, "; ", join((string(k, " = ", repr(v)) for (k, v) in kws), ", "))
    print(io, ")")
end
function Base.show(io::IO, m::LatticeMultigrid)
    kws = Pair{Symbol, Any}[]
    m.cycle.nu1 == 2 && m.cycle.nu2 == 2 || push!(kws, :cycle => (m.cycle.nu1, m.cycle.nu2))
    m.cycles === nothing || push!(kws, :cycles => m.cycles)
    m.reltol === nothing || push!(kws, :reltol => m.reltol)
    m.maxiters === nothing || push!(kws, :maxiters => m.maxiters)
    m.warn_tol === nothing || push!(kws, :warn_tol => m.warn_tol)
    return _show_kw(io, "LatticeMultigrid", kws)
end
function Base.show(io::IO, d::FusedPCG)
    kws = Pair{Symbol, Any}[]
    c = d.precond.cycle
    c.nu1 == 2 && c.nu2 == 2 || push!(kws, :precs => LatticeMultigrid(; cycle = c))
    d.maxiters == 8 || push!(kws, :maxiters => d.maxiters)
    d.reltol == 1.0e-6 || push!(kws, :reltol => d.reltol)
    return _show_kw(io, "LatticePCG", kws)
end

"""
`linsolve = :auto`: every group gets `LatticePCG` (maxiters 8), with the constant mode deflated
on an unanchored group with a constant shift. Stationary V(2, 2) needs 12 cycles or more on
unanchored periodic groups, so it is used only when asked for. An explicit stationary
`LatticeMultigrid` defaults to maxiters 12 on a group with a mask, a Dirichlet face or a
non-constant face coefficient, else 8. A `LatticePCG` is resolved to the fused form a
`FieldSolver` runs (`FusedPCG`): its `precs` must be a `LatticeMultigrid` with a symmetric cycle
and one cycle per iteration, and an unset `maxiters` or `reltol` takes 8 or 1e-6.
"""
function resolve_inner(op::CellOperator, inner)
    inner === :auto && return FusedPCG(LatticeMultigrid(), 8, 1.0e-6)
    inner isa FusedPCG && return inner
    if inner isa LatticePCG
        c = inner.precs
        c isa LatticeMultigrid || _refuse(
            op, "a lattice field's `LatticePCG` applies the V-cycles of `precs = LatticeMultigrid(…)` inside its ",
            "fused iteration; got `precs = ", repr(c), "`: leave `precs` out, or give `precs = LatticeMultigrid(; cycle = (ν, ν))`"
        )
        c.cycle.nu1 == c.cycle.nu2 ||
            _refuse(
            op, "`LatticePCG` needs a symmetric preconditioner cycle `(ν, ν)`; got `(",
            c.cycle.nu1, ", ", c.cycle.nu2, ")`: use `LatticePCG(; precs = LatticeMultigrid(; cycle = (",
                max(c.cycle.nu1, c.cycle.nu2), ", ", max(c.cycle.nu1, c.cycle.nu2),
            ")))`, or the stationary `LatticeMultigrid(; cycle = (", c.cycle.nu1, ", ", c.cycle.nu2, "))`"
        )
        (c.cycles === nothing || c.cycles == 1) ||
            _refuse(
            op, "`LatticePCG` applies one preconditioner cycle per iteration; got `cycles = ",
            c.cycles, "` in its `precs`: drop `cycles`, or use the stationary `LatticeMultigrid(; cycles = ",
                c.cycles, ")`")
        return FusedPCG(LatticeMultigrid(; cycle = c.cycle), something(inner.maxiters, 8), something(inner.reltol, 1.0e-6))
    end
    inner isa LatticeGMRES && _refuse(
        op, "`linsolve = ", repr(inner), "` solves an implicit group's fields together; ",
        "a `FieldSolver` solves one field: give it the `LatticeGMRES`'s per-field solver, `linsolve = ", repr(gmres_precond(inner)), "`"
    )
    inner isa LatticeMultigrid || _refuse(
        op, "`linsolve` takes `:auto`, a `LatticePCG(…)` or a `LatticeMultigrid(…)`; got ",
        repr(inner))
    b = inner.cycles !== nothing ? inner.cycles :
        inner.maxiters !== nothing ? inner.maxiters : jumpy(op) ? 12 : 8
    r = something(inner.reltol, 1.0e-6)
    w = something(inner.warn_tol, inner.cycles === nothing ? r : 1.0e-3)
    return LatticeMultigrid(inner.cycle, inner.cycles, r, b, w)
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
    to_host(exec, A)

A host copy of device array `A` (a declared host pass: a sync).
"""
function to_host end

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
`tree`: the body is a reducing kernel's workgroup form (site phase, then the halving tree:
`Schedule.host_reduce!` may run it); `lds` then holds `lds_regions(exec)` regions of
`ldslen` elements, one per host chunk.
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
    tree::Bool
end
Launch(body, n, S, P, G, key) = Launch(body, n, S, P, G, key, 0, 0, 0, nothing, false)
function Launch(exec, T, body, ngroups, S, P, G, key; phases, ldslen, tree::Bool = false)
    nl = tree ? ldslen * lds_regions(exec) : ldslen
    Launch(body, ngroups, S, P, G, key, WG, phases, ldslen, alloc(exec, T, nl), tree)
end

"""
    lds_regions(exec)

Workgroup-memory regions a tree launch allocates on `exec`: one per host chunk of the host
reduction (`Schedule.host_reduce!`, the threads of a host executor), else 1.
"""
lds_regions(exec) = 1

"""
A solve plan: segments of launches (setup, then one per cycle or iteration), the
two-buffer slots after each segment, and per segment the epilogue run after it when it is
the last segment that ran (bound to that segment's slots). `stop[k]`: the host executor may
stop after segment `k` when the solve is done (its slots are the last segment's, so the held
plans see one rotation however many iterations ran).
"""
struct SolvePlan
    segments::Vector{Vector{Any}}
    slots::Vector{Dict{Int32, Int}}
    epilogue::Vector{Vector{Any}}
    stop::Vector{Bool}
end
SolvePlan(segments, slots, epilogue) = SolvePlan(segments, slots, epilogue, [s == slots[end] for s in slots])
nlaunches(sp::SolvePlan, seg) = length(sp.segments[seg])

mutable struct FieldSolver{N, E}
    exec::E
    op::CellOperator{N}
    alg::Union{LatticeMultigrid, FusedPCG}
    deflate::Bool
    prog::Program{N}
    ctx::Any
    T::Type                               # solver_type: the solver's number type
    state::Type                           # T: the caller-facing arrays' number type
    rule::RuleWeights
    bufs::Dict{Int32, Vector{Any}}
    slot::Dict{Int32, Int}
    tables::Dict{Int32, Any}
    bodies::Dict{String, Any}
    plans::Dict{Tuple{Symbol, Int, UInt64}, SolvePlan}   # (kind, budget or flag, rotation)
    rot::Vector{Int32}                    # the two-buffer fields, in id order (the rotation)
    vals::Tuple                           # the coefficient slot values the bodies hold
    auto::Bool                            # solver_type was :auto
    warned::Bool                          # the set_coefficients! solver_type warning was given
    rhs::Int32                            # the right-hand side's field (`"in.f"`)
    xid::Int32                            # the solution's field (`solution_key`)
    scal::Any                             # the device scalars (`"solve.scal"`)
    bound::Any                            # the `BoundOperator` a LinearSolve cache built it from, or nothing
end

"""
    FieldSolver(exec, op::CellOperator; linsolve = :auto, T = Float32, solver_type = :auto,
        rule = RULE_M, stages, deflate = :auto, inputs = ())

Build the solver group of `op`: the program, its compiled bodies and its arrays on `exec`.

`inputs` binds input fields to the caller's arrays, with no copy: `key => A` for the
right-hand side `"in.f"` and for each input key of `op` (mask, mask value, shift, faces). The
solver then reads `A` itself: a write into `A` enters the next `lift!` (the right-hand side,
mask values) or `rebuild!` (mask, shift, faces). `A` holds one value per site, in the
lattice's linear order (axis 1 fastest; a `Vector` or an array of size `op.dims`), of the
state type `T` (`UInt8` for the mask), on the executor's device. An input not bound is
allocated by the solver (zeros) and reached by `field(sv, key)`.

Number types, one per role (`T` and `solver_type`; a later `precond_type` would join them):

  - `T`, the state type: the element type of the caller-facing arrays, the inputs
    (`"in.f"`, input coefficient fields) and the solution (`solution_key`). It never
    depends on `solver_type`; the solver converts at the boundary.
  - `solver_type`, the solver's arithmetic and working arrays (vectors, hierarchy,
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
function FieldSolver(
        exec, op::CellOperator{N}; linsolve = :auto, T = Float32,
        solver_type = :auto, rule::RuleWeights = RULE_M, stages = LOWERING,
        deflate = :auto, inputs = (), bound = nothing
    ) where {N}
    state = lowered_type(exec, T, "state"; op)
    T = resolve_solver_T(exec, op, state, solver_type)
    alg = resolve_inner(op, linsolve)
    dfl = deflate === :auto ? alg isa FusedPCG && deflatable(op) : Bool(deflate)
    lane(t) = t == Float64 ? F64 : F32
    p, ctx = solver_program(
        op, alg isa FusedPCG; lane = lane(T), state = lane(state),
        deflate = dfl)
    s = semantic(p)
    # a Float64 solver on a device whose default float is Float32 (an explicit `solver_type`, or
    # `:auto` in the floor regime, D-C7b): its kernels are registered (D-157 carve-out, R-F3c)
    declared = T === Float64 && Exec.default_float(exec) !== Float64
    # (a solver launch passes the linear site index: a hexagonal lattice's diagonal reads would
    # otherwise select the Cartesian index form)
    o = ishex(op) ? CompileOptions(; T, declared, index = :linear) : CompileOptions(; T, declared)
    declared && foreach(f -> Exec.register_float64!(string(typeof(f)), Exec.FLOAT64_ARRAY), (finish!, bottom!, gershgorin!, ishex(op) ? build_hex! : build_site!))
    bodies = Dict{String, Any}()
    praw = coef_values(op)                # coefficients are runtime parameters (P5 C7b-2)
    for k in s.kernels
        ck = compile_kernel(s, k, o; stages)
        d = derive_function(ck)
        ck.timed && irerror("solver kernel `", k.key, "` derives parameters from t")
        # compute type sv.T; t is never read (check_no_time), so its value is irrelevant
        bodies[k.key] = (ck, body_function(ck), d(praw, zero(T), 0.0, nothing), d)
    end
    bufs, slot = Dict{Int32, Vector{Any}}(), Dict{Int32, Int}()
    for (i, f) in enumerate(s.fields)
        n = nsites(s, f.levels[1]) * ncomp(f)
        bufs[Int32(i)] = [alloc(exec, juliatype(f.storage), n) for _ in 1:(f.buffers)]
        slot[Int32(i)] = 1
    end
    _bind_inputs!(bufs, exec, op, s, inputs)
    nb = reduction_blocks(nsites(s, 0))
    tlen(k) = k == "solve.scal" ? SCALARS : k == "solve.gb" ? 2 : nb
    tables = Dict{Int32, Any}(Int32(i) => alloc(exec, T, tlen(t.key))
    for (i, t) in enumerate(s.tables))
    sv = FieldSolver{N, typeof(exec)}(
        exec, op, alg, dfl, s, ctx, T, state, rule, bufs, slot, tables, bodies,
        Dict{Tuple{Symbol, Int, UInt64}, SolvePlan}(), _rotation_fields(bufs), praw,
        solver_type === :auto, false, Int32(0), Int32(0), nothing, bound
    )
    sv.rhs = fid(sv, "in.f")
    sv.xid = fid(sv, solution_key(sv))
    sv.scal = sv.tables[tid(sv, "solve.scal")]
    return sv
end

function _rotation_fields(bufs)
    r = sort!([id for (id, b) in bufs if length(b) == 2])
    length(r) <= 64 || irerror("more than 64 two-buffer solver fields")
    return r
end

"""
Bind the caller's arrays to input fields (`FieldSolver(…; inputs)`): each `key => A` replaces
the solver's own array of input `key`, after the checks (an input key of the program, one
value per site of the field's number type, on the executor's device).
"""
function _bind_inputs!(bufs, exec, op, p, inputs)
    keys_in = [f.key for f in p.fields if f.role === :input]
    for (k, A) in inputs
        key = string(k)
        key in keys_in || _refuse(op, "`inputs`: `", key, "` is not an input of this solver; its inputs are ",
            join(("`" * x * "`" for x in sort(keys_in)), ", "))
        id = fieldid(p, key)
        f = p.fields[id]
        S, n = juliatype(f.storage), nsites(p, f.levels[1])
        A isa AbstractArray || _refuse(op, "`inputs`: `", key, "` takes an array; got ", typeof(A))
        eltype(A) === S || _refuse(op, "`inputs`: `", key, "` holds ", eltype(A), " values; this solver's ",
            key == op.mask ? "mask is `UInt8`" : string("state type is `", S, "` (`T = ", S, "`)"),
            ": pass an array of ", S, key == op.mask ? "" : string(", or build the solver with `T = ", eltype(A), "`"),
            inputs isa AbstractVector ? " (a vector `[k => A, …]` converts its arrays to one element type: pass the pairs as a tuple or a `Dict`)" : "")
        (length(A) == n && (ndims(A) == 1 || size(A) == op.dims)) ||
            _refuse(op, "`inputs`: `", key, "` has size ", size(A), "; this solver needs one value per site: ",
                "a vector of ", n, " or an array of size ", op.dims)
        _same_device(exec, A) || _refuse(op, "`inputs`: `", key, "` is not on the solver's device (",
            exec, "): allocate it there (`KernelAbstractions.allocate(backend, ", S, ", ", n, ")`)")
        bufs[id] = Any[vec(A)]
    end
    return bufs
end
_same_device(exec, A) = true
_same_device(exec::KA.Backend, A) = KA.get_backend(A) == exec

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
function lowered_type(exec, S, role; op = nothing)
    who = op === nothing ? "the solver group" : _who(op)
    bad(msg...) = throw(ArgumentError(string(who, ": ", msg...)))
    S isa Type || bad(
        role, " expects ", role == "solver_type" ? ":auto or " : "",
        "a number type; got ", repr(S))
    S in LOWERED_TYPES ||
        bad("number type ", S, " (", role, ") is not lowered for this solver; ",
            "lowered: ", join(LOWERED_TYPES, ", "),
            S <: AbstractFloat ? "" : " (a Dual or BigFloat implicit solve is planned after the paper, FE-26)")
    S === Float32 || supports(exec, S) ||
        bad("number type ", S, " (", role, ") is not supported by this executor ",
            "(supports(exec, ", S, ") is false: the device has no ", S, "); use Float32")
    return S
end

"""
    resolve_solver_T(exec, op, state, solver_type)

The solver's number type (provisional D-C7b): `:auto` is Float64 for a group in the
Float32 floor regime (`floor_regime(op)`) when `supports(exec, Float64)` (asked only
then), else the state type; on a backend without Float64 such a group stays in Float32,
ends `:floor` and the sentinel names it. A type is checked by `lowered_type`.
"""
function resolve_solver_T(exec, op::CellOperator, state::Type, solver_type)
    solver_type === :auto || return lowered_type(exec, solver_type, "solver_type"; op)
    state === Float32 && floor_regime(op) && supports(exec, Float64) && return Float64
    return state
end

function fid(sv::FieldSolver, key)
    i = findfirst(f -> f.key == key, sv.prog.fields)
    i === nothing && _refuse(sv.op, "`", key, "` is not a field of this solver; its inputs are ",
        join(("`" * f.key * "`" for f in sv.prog.fields if f.role === :input), ", "),
        " and its solution is `", solution_key(sv), "`")
    return fieldid(sv.prog, key)
end
tid(sv::FieldSolver, key) = Int32(findfirst(t -> t.key == key, sv.prog.tables))
"""
    field(sv, key)

The current array of the solver's field `key` (two-buffer fields: the current slot): an
input (`"in.f"`, the operator's input keys) or the solution (`solution_key(sv)`).
"""
function field(sv::FieldSolver, key)
    (id = fid(sv, key); sv.bufs[id][sv.slot[id]])
end
"""
    solution_key(sv)

The solution field, an array of the state type: `pcg.u` under deflation, `out.u` when the
solver type differs from the state type, else `pcg.x` under PCG or the finest level's `x`.
"""
function solution_key(sv::FieldSolver)
    sv.deflate ? "pcg.u" :
    sv.T != sv.state ? "out.u" :
        sv.alg isa FusedPCG ? "pcg.x" : lkey(0, "x")
end
"""
The working field a solve starts from (`steady!` zeroes it).
"""
working_key(sv::FieldSolver) = sv.alg isa FusedPCG ? "pcg.x" : lkey(0, "x")

"""
    set_coefficients!(sv, op)

Replace the numeric coefficients of the group (face, shift, value, Dirichlet values) by
those of `op`, which must have the same structure (dims, periodicity, mask, field keys, the
same coefficients numeric): new parameter values for every body, no recompile. The held
plans are dropped and rebuilt at their next use (the set keeps its size: one plan per
kind, budget and rotation); the next `rebuild!`/`lift!` (or `steady!`) uses the new values. The solver
number type (`solver_type = :auto`) stays as resolved at build.
"""
function set_coefficients!(sv::FieldSolver, op::CellOperator)
    o = sv.op
    diff = op.dims != o.dims ? "the lattice size" : op.periodic != o.periodic ? "the periodic axes" :
           ishex(op) != ishex(o) ? "the lattice geometry (hexagonal or not)" :
           op.mask != o.mask ? "the mask" : op.name != o.name ? "the field name" :
           op.robin_full != o.robin_full ? "where a Robin face's negative part goes (`robin_full`)" :
           coef_slots(op) != coef_slots(o) ? "which coefficients are numbers, fields or absent" :
           !all(map((x, y) -> x isa Real || x == y, faces(op), faces(o))) ? "a face coefficient field" :
           !(op.shift isa Real || op.shift == o.shift) ? "the shift field" :
           !(op.value isa Real || op.value == o.value) ? "the mask value field" : nothing
    diff === nothing || _refuse(o, "set_coefficients! takes new values for the same structure; ",
        diff, " differs: build a new FieldSolver for the new structure")
    check_coefficients(op)
    if sv.auto && !sv.warned && resolve_solver_T(sv.exec, op, sv.state, :auto) != sv.T
        sv.warned = true
        Exec.VERBOSE[] && @warn string(
            _who(op), ": set_coefficients!: solver_type = :auto would now resolve to ",
            resolve_solver_T(sv.exec, op, sv.state, :auto), ", but the group keeps ", sv.T,
            " (resolved at build; changing it recompiles). Pass solver_type explicitly or ",
            "rebuild the FieldSolver to change it.")
    end
    return _set_values!(sv, op)          # drops the held plans (`_set_raw!`)
end
function _set_values!(sv::FieldSolver, op::CellOperator)
    _set_raw!(sv, coef_values(op))
    sv.op = op
    return sv
end
"""
The bodies' parameter values from the slot values `praw` (`coef_slots` order); `sv.op` is
not changed (the tangent solves perturb slots this way).
"""
function _set_raw!(sv::FieldSolver, praw)
    for (k, (ck, fn, _, d)) in sv.bodies
        sv.bodies[k] = (ck, fn, d(praw, zero(sv.T), 0.0, nothing), d)
    end
    sv.vals = Tuple(praw)
    empty!(sv.plans)                      # the held plans' parameters are rebuilt on next use
    return sv
end

"""
    tangent!(sv, u, coef; homogeneous = true, maxiter = 64) -> u̇

The derivative of the solution `u` of the group's operator `A(θ) u = b(θ)` with respect to
one numeric coefficient `θ` (`coef`: `:shift`, `:value`, `(:face, a)` (`a = 3`: the diagonal face of
a hexagonal lattice), `(:dirichlet, a, k)`
or `(:robin, a, k, :alpha | :beta | :g)`), by a tangent solve with the same solver (no Dual
enters PCG or multigrid, P5 §3.4): `A u̇ = ∂b/∂θ − (∂A/∂θ) u` with homogeneous boundary
values. `u` is the primal solution in solver precision (`solver_solution`). The right-hand
side is exact because `A` and `b` are affine in each coefficient slot: `r(θ + v, u) − r(θ, u)`
with `v` the slots' derivative in `θ` (one slot, or a Robin face's `(d⁺, d⁻, q)`, which are
affine together), both residuals computed on the device by the `tangent.*` kernels after
rebuilding the operator, and written straight into the solver's right-hand side (the
boundary data of `lift` is left out: homogeneous). A Robin face's negative part is iterated
as in `steady!`. The coefficients, the right-hand side, the working field and the solution
array are restored afterwards, so a warm re-solve continues from the primal state; `u̇` is
only returned (a host copy). `homogeneous = false` keeps the primal boundary values (the
negative control of the tests).
"""
function tangent!(sv::FieldSolver, u::AbstractVector, coef; homogeneous::Bool = true,
        maxiter::Int = 64)
    op = sv.op
    θ = collect(coef_values(op))
    v = _direction(op, coef)
    slot0 = copy(sv.slot)                 # the primal working state (warm starts)
    wid, sk = fid(sv, working_key(sv)), solution_key(sv)
    w = sv.bufs[wid][sv.slot[wid]]
    w0 = to_host(sv.exec, w)
    s0 = sk == working_key(sv) ? nothing : to_host(sv.exec, field(sv, sk))
    copyto!(w, convert(Vector{eltype(w0)}, u))
    rebuild!(sv)                          # r(θ, u) into d
    lift!(sv)
    _run_one!(sv, "tangent.r0")
    _set_raw!(sv, θ .+ v)
    rebuild!(sv)                          # r(θ + v, u) − r(θ, u) into d
    lift!(sv)
    _run_one!(sv, "tangent.dr")
    _set_raw!(sv, θ)
    rebuild!(sv)
    lift!(sv)
    _run_one!(sv, "tangent.rhs"; rt = (homogeneous ? 0.0 : 1.0, 0.0))
    foreach(A -> fill!(A, zero(eltype(A))), sv.bufs[wid])
    has_robin(op) && _run_one!(sv, "robin.b")     # the defect term at x = 0
    _defect_solve!(sv, maxiter)
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

"""
The derivative of the slot values (`coef_values` order) in coefficient `coef` (`tangent!`).
"""
function _direction(op::CellOperator, coef)
    cs = coef_slots(op)
    v = zeros(cs.n)
    j = _coef_slot(op, cs, coef)
    if j isa Integer
        j == 0 && _refuse(op, "tangent!: ", repr(coef), " is not a numeric coefficient of the group ",
            "(it is an input field or absent)")
        v[j] = 1
        return v
    end
    a, k, which = j
    α, β, g = op.robin[a][k]
    den = α / 2 + β
    dd, dq = which === :alpha ? (β / den^2, -g / (2den^2)) :
             which === :beta ? (-α / den^2, -g / den^2) : (0.0, 1 / den)
    s = cs.robin[a][k]
    v[op.robin_full || α / den >= 0 ? s[1] : s[2]] = dd     # d's sign picks its part (one-sided at d = 0)
    v[s[3]] = dq
    return v
end

function _coef_slot(op, cs, coef)
    coef === :shift && return cs.shift
    coef === :value && return cs.value
    coef isa Tuple && length(coef) == 2 && coef[1] === :face && return cs.face[coef[2]]
    coef isa Tuple && length(coef) == 3 && coef[1] === :dirichlet &&
        return cs.dirichlet[coef[2]][coef[3]]
    if coef isa Tuple && length(coef) == 4 && coef[1] === :robin && coef[4] in (:alpha, :beta, :g)
        a, k = coef[2], coef[3]
        op.robin[a][k] === nothing && _refuse(op, "tangent!: ", _face_words(op, a, k),
            " has no Robin condition")
        return (a, k, coef[4])
    end
    _refuse(op, "tangent!: unknown coefficient ", repr(coef), "; give `:shift`, `:value`, `(:face, a)`, ",
        "`(:dirichlet, a, k)` or `(:robin, a, k, :alpha | :beta | :g)` (axis `a`, side `k` = 1 low, 2 high)")
end

"""
    solver_solution(sv)

The group's solution in the solver's own precision on the host (a sync): under deflation
`pcg.x − mean(pcg.x) + c`, else the working field.
"""
function solver_solution(sv::FieldSolver)
    x = to_host(sv.exec, field(sv, working_key(sv)))
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
function PlanBuilder(sv; budget = sv.alg.maxiters)
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
    key = sv.deflate && sv.alg isa FusedPCG ? "pcg.out" :
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
                ldslen = reduce_lds(ck), tree = true))
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
    r0 = alg isa LatticeMultigrid ? something(alg.reltol, 1.0e-6) : alg.reltol
    w0 = alg isa LatticeMultigrid ? something(alg.warn_tol, alg.cycles === nothing ? r0 : 1.0e-3) : alg.reltol
    rtol, warn = alg isa FusedPCG ? (alg.reltol, alg.reltol) :
        (alg.cycles === nothing ? r0 : 0.0, w0)
    tk = ("solve.scal", "solve.pr", "solve.pb", "solve.pd",
        sv.deflate ? "solve.ps" : "solve.pd", sv.deflate ? "solve.pq" : "solve.pd",
        "solve.px")
    S = Tuple(sv.tables[tid(sv, k)] for k in tk)
    red, sum = _combos(op, sv.deflate)
    G = (; op, red, sum, wg = Int32(WG), n = Int32(length(S[2])), rtol = T(rtol),
        floor = T(FLOOR),
        budget = Int32(budget), warn = T(warn),
        nsite = T(nsites(sv.prog, 0)), shift = T(sv.op.shift isa Real ? sv.op.shift : 0),
        deflate = sv.deflate, stall = !(alg isa LatticeMultigrid && alg.cycles !== nothing),
        diverge = alg isa LatticeMultigrid,
    )
    push!(pl.segments[end],
        Launch(sv.exec, T, finish!, 1, S, (), G, "finish.$op"; phases = REDUCE_PHASES,
            ldslen = NCOMBO * WG, tree = true))
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
    nf = length(faces(sv.op))             # faces per direction: `ws[a][l]` (no tuple of tuples)
    S = (get(F -> F.active), ntuple(a -> Tuple(_arr(pl, F.w[a], :cur) for F in ls), nf),
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
function vcycle!(pl::PlanBuilder, ν::VCycle; zero_fine::Bool, rz::Bool = false)
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
    hex = ishex(sv.op)
    for l in 1:(ctx.L)
        F, C = ctx.lv[l], ctx.lv[l + 1]
        S = (_levelarrays(pl, F), _levelarrays(pl, C))
        G = (; n = Int32(nsites(sv.prog, l)), dimsf = Int32.(Tuple(ctx.dims[l])),
            dimsc = Int32.(Tuple(ctx.dims[l + 1])), n0 = Int32.(sv.op.dims),
            level = Int32(l), per = sv.op.periodic, majority = r.majority)
        # (a hexagonal lattice's build behind a barrier: a Cartesian solver never compiles it)
        push!(pl.segments[end], hex ? Base.inferencebarrier(_hex_build)(sv.T, r, nsites(sv.prog, l), S, G) :
                                Launch(build_site!, nsites(sv.prog, l), S, map(sv.T, (r.inside, r.plane, r.inherited, r.box)), G, "build"))
    end
    C = ctx.lv[ctx.L + 1]                 # the coarsest Gershgorin interval for the bottom
    S = (_levelarrays(pl, C)..., sv.tables[tid(sv, "solve.gb")])
    G = (; dims = Int32.(Tuple(ctx.dims[ctx.L + 1])), per = sv.op.periodic, wg = Int32(WG))
    push!(pl.segments[end],
        Launch(sv.exec, sv.T, gershgorin!, 1, S, (), G, "gershgorin";
            phases = REDUCE_PHASES, ldslen = 2WG, tree = true))
    return SolvePlan(pl)
end

_hex_build(T, r, n, S, G) = Launch(build_hex!, n, S, map(T, (r.inside, r.plane, r.inherited, r.box, r.diagonal)), G, "build")

"""
The budgeted solve: a setup segment, then `budget` segments (cycles or PCG iterations).
"""
function solve_plan(sv::FieldSolver, budget::Int)
    pl = PlanBuilder(sv; budget)
    fin!(pl, INIT)
    if sv.alg isa LatticeMultigrid
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
        # (a segment of its own: a solve converged at its setup stops before the first cycle)
        segment!(pl)
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
    ν = sv.alg isa FusedPCG ? sv.alg.precond.cycle : sv.alg.cycle
    vcycle!(pl, ν; zero_fine = true)
    return SolvePlan(pl)
end

"""
The held plan `name` (`:rebuild`, `:lift`, `(:solve, budget)`, `(kernel key, rt)`) for the
current rotation (the slots of the two-buffer fields), built by `f(sv)` at its first use.
Plans are held per kind, budget and rotation: no values in the key (a value change drops
the set, `_set_raw!`), and the warm lookup builds no heap key.
"""
function _plan(f::F, sv::FieldSolver, name) where {F}
    key = (_kind(name)..., _rotation(sv))
    p = get(sv.plans, key, nothing)
    p === nothing || return p
    p = f(sv)
    sv.plans[key] = p
    return p
end
_kind(name::Symbol) = (name, 0)
_kind(name::Tuple{Symbol, Int}) = name
_kind(name::Tuple{String, NTuple{2, Float64}}) = (Symbol(name[1]), name[2] == (0.0, 0.0) ? 0 : 1 + _rtcode(name[2]))
_rtcode(rt) = rt == (1.0, 0.0) ? 0 : irerror("solver run with runtime values ", rt)
"""
The rotation: bit `i` set when the `i`-th two-buffer field's current slot is 2.
"""
function _rotation(sv::FieldSolver)
    m = zero(UInt64)
    for (i, id) in enumerate(sv.rot)
        sv.slot[id] == 2 && (m |= one(UInt64) << (i - 1))
    end
    return m
end

"""
Run plan `sp`; with `host = true` read the `done` flag after every segment and stop when it
is set (a declared host pass). On a host executor (`host_scalars`) the device mode stops there
too, after the segments whose slots are the plan's last (`sp.stop`): its scalars are host
memory, so the read is free (R1 of the F3-06 review: a solve that is done, at its setup or
after an iteration, skips the gated launches that would follow, about 4.9 ms of a
0-iteration solve at 256² on 8 threads); the result is the same, every later launch being
gated off, and the solve ends in the plan's last rotation. Returns the number of segments run.
"""
function run!(sv::FieldSolver, sp::SolvePlan; host::Bool = false)
    scal = sv.tables[tid(sv, "solve.scal")]
    free = host_scalars(sv.exec, scal)           # a plain read: no sync, no copy
    nseg = length(sp.segments)
    for (k, seg) in enumerate(sp.segments)
        _run_seg!(sv, seg)
        k < nseg || break
        if free
            @inbounds sp.stop[k] && _isdone(scal) && (nseg = k; break)     # (k ≤ nseg = length(sp.stop))
        elseif host && to_host(sv.exec, scal)[DONE] != 0
            nseg = k
            break
        end
    end
    _run_seg!(sv, sp.epilogue[nseg])
    merge!(sv.slot, sp.slots[nseg])
    return nseg
end
"""
    host_scalars(exec, scal) -> Bool

Whether the solver's scalars `scal` are host memory that the driver reads for free (the host
executors: a plain `Array`), so `run!` stops at `done` with no sync.
"""
host_scalars(exec, scal) = false
# (a function barrier: `scal` is untyped in the solver's tables)
_isdone(scal::Array) = @inbounds scal[DONE] != 0          # DONE ≤ SCALARS = length(scal)
host_scalars(b::KA.Backend, scal) = Exec.ishost(b) && scal isa Array
# The launches of a plan are untyped (`Vector{Any}`): the dynamic call takes the solver (a heap
# object), not its executor, which an isbits executor would box (16 B per launch).
_launch!(sv::FieldSolver, l::Launch) = launch!(sv.exec, l)
function _run_seg!(sv::FieldSolver, seg::Vector{Any})
    for l in seg
        _launch!(sv, l)
    end
    return nothing
end

"""
    rebuild!(sv)

Fill the finest level's coefficients from the operator and its input fields (mask, shift,
faces) and rebuild the hierarchy (rule M). Run it after any of these changes. Device mode:
no sync.
"""
rebuild!(sv::FieldSolver) = (run!(sv, _plan(rebuild_plan, sv, :rebuild)); sv)
"""
    lift!(sv)

The solve's right-hand side from `"in.f"`, the mask values and the face conditions; with a
Robin face whose diagonal is negative, its defect term at the current iterate. Run it after
a change of any of these. Device mode: no sync.
"""
lift!(sv::FieldSolver) = (run!(sv, _plan(s -> lift_plan(s), sv, :lift)); sv)
function lift_plan(sv)
    pl = PlanBuilder(sv)
    gen!(pl, "lift")
    has_robin(sv.op) && gen!(pl, "robin.b")   # the defect term at the current iterate
    return SolvePlan(pl)
end

"""
    solve!(sv; host = false, maxiters)

The inner solve from the current solution, at most `maxiters` iterations (default the
algorithm's). Device mode enqueues the whole plan (no sync). Host mode stops at `done` and
returns the iteration count.
"""
function solve!(sv::FieldSolver; host::Bool = false,
        maxiters::Int = sv.alg.maxiters
    )
    sp = _plan(s -> solve_plan(s, maxiters), sv, (:solve, maxiters))
    run!(sv, sp; host)
    return host ? iterations(sv) : nothing
end

"""
    scalars(sv)

Device scalars on the host (a sync): `(; status, done, iter, rnorm, bnorm, tol, warn, mean, best, scale)` (`best`: the best true residual; `scale`: the rounding scale max(|b| + |A||x|)
of the last check). `status` is `:done` (converged), `:floor` (stagnated at rounding level
above the tolerance), `:diverged` (the residual grew) or `:budget`.
"""
function scalars(sv::FieldSolver)
    s = to_host(sv.exec, sv.tables[tid(sv, "solve.scal")])
    status = (:budget, :done, :floor, :diverged)[Int(s[DONE]) + 1]
    return (; status, done = status === :done, iter = Int(s[ITER]),
        rnorm = Float64(s[RNORM]), bnorm = Float64(s[BNORM]), tol = Float64(s[TOL]),
        warn = s[WARN] != 0, mean = Float64(s[MEAN]), best = Float64(s[BEST]),
        scale = Float64(s[SCALE]))
end
"""
    iterations(sv)

The iteration (or cycle) count of the last solve (a sync).
"""
iterations(sv::FieldSolver) = scalars(sv).iter

"""
    sentinel(sv)

The residual sentinel, read at an existing sync: warns (once per call) when the last
budgeted solve ended above its tolerance; returns whether it fired.
"""
function sentinel(sv::FieldSolver)
    s = scalars(sv)
    s.warn || return false
    hint = sv.alg isa LatticeMultigrid ? " Stationary multigrid: use LatticePCG (linsolve = :auto)." :
           s.status === :floor && sv.T == Float32 && floor_regime(sv.op) ?
           " Float32 floor of an unanchored group at weak reaction: solve in Float64 " *
        "(solver_type; a backend with Float64)." :
           ""
    what = s.status === :floor ? "stagnated (floor)" :
           s.status === :diverged ? "diverged" : "ended"
    Exec.VERBOSE[] && @warn string(
        _who(sv.op), ": the field solve ", what, " at ‖r‖∞ = ", s.rnorm,
        " > tolerance after ", s.iter, " iterations.", hint)
    return true
end

"""
    steady!(sv; maxiter = 64)

`init = :steady` (§6.4): rebuild, lift, solve from zero with the group's inner solver to
`reltol = 1e-6`, host-checked. Returns the iteration count.
"""
function steady!(sv::FieldSolver; maxiter::Int = 64)
    rebuild!(sv)
    lift!(sv)
    id = fid(sv, working_key(sv))
    foreach(A -> fill!(A, zero(eltype(A))), sv.bufs[id])
    has_robin(sv.op) && _run_one!(sv, "robin.b")   # the defect term at x = 0
    return _defect_solve!(sv, maxiter)
end

"""
The host-checked solve of `steady!` and `tangent!`; with a Robin face's negative part (the
sign rule, `CellOperator`), the defect correction around it: `robin.b` takes the right-hand
side at the new iterate and the inner solve runs again from it, until a solve is converged
at its setup (then the full operator's residual is at the tolerance), within `maxiter` outer
passes. A correction that does not converge warns, naming the field, the faces and the route.
Returns the total inner iteration count.
"""
function _defect_solve!(sv::FieldSolver, maxiter::Int)
    fixed = sv.alg isa LatticeMultigrid && sv.alg.cycles !== nothing
    budget = fixed ? sv.alg.cycles : maxiter
    k = solve!(sv; host = true, maxiters = budget)
    has_defect(sv.op) || return k
    for _ in 1:maxiter
        _run_one!(sv, "robin.b")
        j = solve!(sv; host = true, maxiters = budget)
        k += j
        (j == 0 && scalars(sv).done) && return k
    end
    Exec.VERBOSE[] && @warn string(
        _who(sv.op), ": the defect correction of the Robin faces with a negative diagonal ",
        "(α and β of opposite sign, |β| > α/2) did not converge in ", maxiter, " passes: the face ",
        "condition is too strong for this operator; a larger `α/2 + β`, or a larger shift or face ",
        "coefficient, makes it converge")
    return k
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

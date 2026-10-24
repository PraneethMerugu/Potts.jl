# The implicit runtime (F3 design §3.3, §3.4): the substep loop of `BackwardEuler` on the
# group layer, for both front ends. A group's store holds the arrays of its stepped program
# (the state's two slots, the inputs, the masks); the runtime's own programs alias them:
#
# - the residual program (`fuse_residual`): each `rate:c` kernel stores
#   `G = (uⁿ − u_k)/h + r(u_k)` into `res:c`, `u_k` the iterate (slot `p` at the first Newton
#   iteration, the other slot after it), `uⁿ` the substep's start (slot `p`, `c__n`), at the
#   substep's end time `tⁿ⁺¹`;
# - the operator program (the front end's `jac:` kernels, `OperatorSpec.jac`), for the rows
#   whose operator varies by site;
# - one `Solvers.FieldSolver` per row with diffusion, its inputs bound to these arrays (no
#   copy): `(I/h − J̃) δ = G`, δ from 0, homogeneous face values;
#
# then the update `u_{k+1} = u_k + δ` into the other slot (masked sites take their value; the
# clip `lower` after the last iteration) and the status word. Rows (the group's fields) are
# solved in the topological order of the reads among them, each from the residual at the
# fields solved before it (exact for an acyclic group; a cycle is block Gauss–Seidel).

"""
    residual_rule(alg)

The residual of implicit algorithm `alg` for [`fuse_residual`](@ref
LatticeFields.Compile.fuse_residual): `rule(kb, c, r, cn)` from the iterate `c`, the rate `r`
and the substep's start `cn`. `BackwardEuler`: `(cn − c)/h + r`, `h = G.rt[2]`.
"""
residual_rule(::BackwardEuler) = BERule()
struct BERule end
(::BERule)(kb, c, r, cn) = (cn - c) / Ex(kb, runtime!(kb, RT_DT)) + r
residual_key(::BackwardEuler) = :be
# the γ of the algorithm's shift `1/(γh)` (Backward Euler: 1)
_gamma(::BackwardEuler) = 1.0

"""
    residual_program(g, alg) -> Program

The semantic residual program of group `g` for implicit algorithm `alg` (`fuse_residual` of
its rate program, once per residual key; thread-safe).
"""
residual_program(g::FieldGroup, alg::ImplicitAlgorithm) =
    lock(() -> get!(() -> semantic(fuse_residual(g.spec.rate, residual_rule(alg))), g.programs, (:residual, residual_key(alg))),
        _PLANS_LOCK)
# the semantic operator program of `g` (`nothing`: every row numeric)
function _jac_program(g::FieldGroup, op::OperatorSpec)
    op.jac === nothing && return nothing
    return lock(() -> get!(() -> semantic(op.jac), g.programs, :jac), _PLANS_LOCK)
end
# a plan of the kernels `ids` of program `s` (cached in the group's plans by `tag`)
function _implicit_plan(g::FieldGroup, s::Program, tag, ids::Vector{Int}, ::Type{V}, backend, o::CompileOptions) where {V}
    return lock(_PLANS_LOCK) do
        first(get!(g.plans, (tag, V, Int[], ids)) do
            p = plan(s, ids; options = _options(o, V, backend; clock = clock_slot(g.spec)))
            (p, p)
        end)
    end
end

# The status word's update after one solve (one work item; F3 design §3.3): [4] solves, [5]
# budget hits (`done` still 0), [6] floors (`done` 2: `StalledSuccess`), and a failure
# (`done` 3, diverged; or a residual that is not finite) into [1] code 2, [3] its cause and [2]
# the window when none is recorded yet
function _be_status_body!(i, w, scal, window)
    @inbounds begin                             # i = 1; w has 8 entries, scal SCALARS ≥ 6
        d, rn = scal[Solvers.DONE], scal[Solvers.RNORM]
        w[STATUS_SOLVES] += UInt32(1)
        fail = UInt32(0)
        if !isfinite(rn)
            fail = UInt32(4)
        elseif d == 0
            w[STATUS_BUDGET] += UInt32(1)
        elseif d == 2
            w[STATUS_FLOOR] += UInt32(1)
            w[STATUS_CODE] = max(w[STATUS_CODE], UInt32(1))
        elseif d == 3
            fail = UInt32(1)
        end
        if fail != 0
            w[STATUS_CODE] = UInt32(2)
            w[STATUS_CAUSE] |= fail
            w[STATUS_WINDOW] == 0 && (w[STATUS_WINDOW] = UInt32(window))
        end
    end
    return nothing
end
_zero_body!(i, a) = (@inbounds a[i] = zero(eltype(a)); nothing)      # i ≤ length(a)

_at(x::Number, i) = x
_at(x::AbstractArray, i) = @inbounds x[i]                              # i ≤ length(x) (one value per site)
_at(::Nothing, i) = false

# The update of one row at site `i` (F3 design §3.3 step 5): δ from the solver's solution `x`
# (or, at a row solved on its own, the value `v`; a row with no diffusion: `res/s`), `dst =
# src + δ`; a masked site takes its value (`mval`, times its value field `mvf`), and the clip
# `lower` (or `nothing`). Every array has one value per site (i ≤ length(dst)).
function _be_update_body!(i, dst, src, x, smask, v, res, s, mask, mval, mvf, lower, clip)
    @inbounds begin
        δ = res !== nothing ? res[i] / _at(s, i) :
            (v !== nothing && smask[i] != 0) ? v[i] : x[i]
        u = src[i] + δ
        if mask !== nothing && mask[i] != 0
            u = mvf === nothing ? mval : mval * mvf[i]
        end
        (clip && lower !== nothing) && (u = max(u, lower))
        dst[i] = u
    end
    return nothing
end

# The shift of a row whose operator varies by site (`OperatorSpec` field mode): `s =
# max(1/(γh) − J, 1/(2γh))/m + d` (the clamp keeps the solve positive definite where the
# local Jacobian grows faster than the step: F3 design §3.4 Positivity; it sets the status
# word's cause bit 8, counted, not a failure), and the solver's mask: a masked site, a site
# outside the domain, a site with multiplier `m = 0` (solved on its own)
function _be_shift_body!(i, s, j, d, m, smask, rmask, dom, ih, ih2, w, window)
    @inbounds begin                             # (w has 9 entries: STATUS_CAUSE = 3, STATUS_CLAMP = 9)
        s0 = ih - _jat(j, i, ih)
        # (every site that clamps writes the same bit and window, and no other launch writes
        # the word meanwhile: the race is benign)
        if s0 < ih2
            w[STATUS_CAUSE] |= UInt32(8)
            w[STATUS_CLAMP] == 0 && (w[STATUS_CLAMP] = UInt32(window))
        end
        base = max(s0, ih2)
        scaled = m === nothing ? base : (m[i] > 0 ? base / m[i] : ih)
        s[i] = d === nothing ? scaled : scaled + d[i]
        if smask !== nothing
            off = (rmask !== nothing && rmask[i] != 0) || (dom !== nothing && dom[i] == 0) || (m !== nothing && !(m[i] > 0))
            smask[i] = off ? 0x01 : 0x00
        end
    end
    return nothing
end
_jat(::Nothing, i, ih) = zero(ih)
_jat(j::AbstractArray, i, ih) = @inbounds j[i]                         # i ≤ length(j)
# The right side of a scaled row (`m Δ(c)`): `G/m` where `m > 0`, and at a row with `m = 0`
# (inside the domain, not masked) its own `δ = G/max(1/(γh) − J, 1/(2γh))` as the solver's
# mask value (the two-stage solve, M3)
function _be_rhs_body!(i, f, v, res, j, m, smask, rmask, dom, ih, ih2)
    @inbounds begin
        g = res[i]
        if smask[i] != 0
            f[i] = zero(eltype(f))
            own = !(m[i] > 0) && !(rmask !== nothing && rmask[i] != 0) && !(dom !== nothing && dom[i] == 0)
            v[i] = own ? g / max(ih - _jat(j, i, ih), ih2) : zero(eltype(v))
        else
            f[i] = g / m[i]
            v[i] = zero(eltype(v))
        end
    end
    return nothing
end

"""
One row of an implicit runtime: its residual launches per slot parity and iteration kind, its
state buffers, its solver (or `nothing`: a row with no diffusion, solved site by site) with
the arrays its solve reads and writes, and its update's mask and clip.
"""
mutable struct ImplicitRow{R, U, A, SV, X, W, SC, SM, V, S, MK, MV, MF, LO, F, J, M, D, RM, DM}
    key::String
    res::NTuple{4, R}                   # (parity 1 first iteration, parity 2 first, parity 1 later, parity 2 later)
    bufs::NTuple{2, U}                  # the row's two state slots
    resarr::A                           # `res:c`
    solver::SV
    xs::NTuple{2, X}                    # the solver's solution array in each of its slots
    xid::Int32
    work::Vector{W}                     # the solver's working buffers (zeroed before each solve)
    scal::SC                            # the solver's scalars
    smask::SM                           # field mode: the solver's mask (cache-owned, U8) or nothing
    v::V                                # scaled rows: the solver's mask value (`δ` of an `m = 0` row)
    s::S                                # the shift: a number (numeric, or a row with no diffusion) or an array
    mask::MK                            # the row's own mask (`c ~ masked(…)`), or nothing
    mval::MV                            # … its value (a number in the state type), times
    mvf::MF                             # … its value field, or nothing
    lo::LO                              # the clip `lower` in the state type, or nothing
    f::F                                # scaled rows: the solver's right side `G/m`
    j::J                                # field mode: the local Jacobian, boundary diagonal, multiplier,
    m::M                                #   domain indicator (`jac:` arrays) or nothing
    d::D
    rmask::RM
    dom::DM
    op::RowOperator
    numeric::Union{Nothing, Solvers.CellOperator}   # the numeric operator the solver holds (numeric rows)
end

"""
    ImplicitCache

The cache of an implicit runtime (F3 design §3.3): its rows in solve order
([`ImplicitRow`](@ref)), the operator program's launches per slot parity (or `nothing`), the
Newton count, the step `h` the coefficients hold, the `stale` flag (the hierarchy is rebuilt
before the next window: set at bind and by [`reset!`](@ref)), the `moving` flag (the
operator reads data that change every window: it is rebuilt each window), the `timed` flag
(the operator reads the time: it is rebuilt at each substep's end time), the `iterate` flag
(a row's local Jacobian reads its own field, a local nonlinear term or a switch: that row's
operator is rebuilt at every Newton iteration, at the iterate), the status word and the
operator spec.
"""
mutable struct ImplicitCache{RS, WK, JL, W, BK}
    rows::RS
    walk::WK
    jac::JL
    newton::Int
    h::Float64
    stale::Bool
    moving::Bool
    word::W
    op::OperatorSpec
    exact::Bool
    iterate::Bool                       # a row's operator reads its iterate: rebuilt every Newton iteration
    rebuilds::Int                       # hierarchy rebuilds so far (a test reads it)
    rebind::Any                         # `p -> (residual launches per row, operator launches)` (a rebind)
    backend::BK
end
status_word(c::ImplicitCache) = c.word
reset_cache!(c::ImplicitCache) = (c.stale = true; nothing)
step_retcode!(::ImplicitCache, rt) = SciMLBase.ReturnCode.Success   # (the status word carries the code)

"""
    bind_cache(alg, group, store, p; fields, n, dt, c, backend, options, V) -> cache

The algorithm's cache bound to `store` at parameters `p` (`alg_cache` for the explicit
algorithms; an [`ImplicitCache`](@ref) for the implicit ones).
"""
bind_cache(alg, g, st, p; kw...) = alg_cache(alg, g, st)

# the state type of a row's arrays (a lowered float type for the solver), with the refusal of
# the others (FE-26, R-F3f)
function _implicit_eltype(u, key)
    T = eltype(u)
    T in (Float32, Float64) || throw(ArgumentError(string("BackwardEuler: the field `", key, "` is stored as ", T,
        "; an implicit solve runs in Float32 or Float64 (a Dual or BigFloat implicit solve is planned after the ",
        "paper, FE-26): give the field a Float32 or Float64 state, or step it with `ExplicitEuler`")))
    return T
end

# the face conditions of field `id` of program `s` on axis `a` side `k` (1 low, 2 high), at
# parameters `p`, in the solver's homogeneous form: `(:none,)`, `(:dirichlet,)` or
# `(:robin, α, β)` (lattice units)
function _face_kind(s::Program, id, a, k, p)
    r = findfirst(x -> x isa FaceRule && x.field == id && x.axis == a && x.side == (k == 1 ? -1 : 1), s.rules)
    r === nothing && return (:none, 0.0, 0.0)
    f = s.rules[r]::FaceRule
    α, β = _coefval(f.alpha, p), _coefval(f.beta, p)
    α == 0 && return (:none, 0.0, 0.0)
    β == 0 && return (:dirichlet, α, 0.0)
    return (:robin, α, β)
end

# the numeric operator of a row at parameters `p` and step `h`: faces, shift, face conditions
# (homogeneous: δ has zero boundary data), the row's mask with value 0 (its update writes the
# value). Whether the shift was clamped (a growth the count rule did not cover) is returned too.
function _numeric_operator(s::Program{N}, r::RowOperator, id, p, h, γ, mask::Bool) where {N}
    dims = Tuple(Int.(leveldims(s, 0)))
    face = ntuple(a -> _coefsum(r.faces[a], p), N)
    ih = 1 / (γ * h)
    s0 = ih - _coefsum(r.jloc, p)
    shift = max(s0, ih / 2)
    dir = ntuple(a -> s.periodic[a] ? (nothing, nothing) :
                      ntuple(k -> _face_kind(s, id, a, k, p)[1] === :dirichlet ? 0.0 : nothing, 2), N)
    rob = ntuple(a -> s.periodic[a] ? (nothing, nothing) :
                      ntuple(k -> (f = _face_kind(s, id, a, k, p); f[1] === :robin ? (f[2], f[3], 0.0) : nothing), 2), N)
    op = Solvers.CellOperator(dims; periodic = s.periodic, face, shift, mask = mask ? "mask" : nothing, value = 0.0,
        dirichlet = dir, robin = rob, name = r.key)
    return op, shift > s0
end
# the parameters the bounds of `inexact_bounds` read: with the store's tables when a row has a
# bound that reads them (`bounds`), else `p` itself (no copy)
function _bound_params(st::FieldStore, s::Program, op::OperatorSpec, keys, p)
    any(r -> r.key in keys && !isempty(r.bounds), op.rows) || return p
    return ParamsTables(p, Pair{String, Vector{Float64}}[s.tables[j].key => _primal64(Array(st.tables[j])) for j in eachindex(s.tables)])
end
# The Robin faces with a negative diagonal of the rows `keys` at `p` (their part `w_a d⁻` stays
# out of the operator: a defect correction, S1): whether there is one (`neg`), the bound of the
# part left out, `ρ = Σ_a max_side w_a |d⁻|` over the numeric rows (`w_a` the row's face
# coefficient `K/h_a²`), and whether a field row has one (`unseen`: its face coefficient varies
# by site, no bound sees it)
function _robin_bounds(s::Program{N}, op::OperatorSpec, keys, p) where {N}
    neg, unseen, ρ = false, false, 0.0
    for r in op.rows
        r.key in keys || continue
        id = fieldid(s, r.key)
        q = 0.0
        for a in 1:N
            m = 0.0
            for k in 1:2
                f = _face_kind(s, id, a, k, p)
                f[1] === :robin || continue
                dm = Solvers.robin_parts(f[2], f[3], 0.0)[2]
                dm < 0 || continue
                neg = true
                r.field ? (unseen = true) : (m = max(m, abs(_coefsum(r.faces[a], p)) * abs(dm)))
            end
            q += m
        end
        ρ = max(ρ, q)
    end
    return (; neg, ρ, unseen)
end

# the rows of the group's fields `keys` in solve order: topological in the reads among them
# (the `rate:` kernels of the stepped program `s`), cycles in state order
function _solve_order(s::Program, keys::Vector{String})
    ids = Dict(k => fieldid(s, k) for k in keys)
    deps = Dict{String, Set{String}}()
    for k in keys
        i = findfirst(x -> x.key == "rate:" * k, s.kernels)
        rd = i === nothing ? Int32[] : unique!([a.field for a in s.kernels[i].accesses])
        deps[k] = Set(q for q in keys if q != k && ids[q] in rd)
    end
    out, left = String[], copy(keys)
    while !isempty(left)
        j = findfirst(k -> all(d -> d in out, deps[k]), left)
        j === nothing && (j = 1)                # a cycle: the next in state order (Gauss–Seidel)
        push!(out, popat!(left, j))
    end
    cyclic = any(k -> any(d -> findfirst(==(d), out) > findfirst(==(k), out), deps[k]), out)
    return out, cyclic
end

# the store of program `prog` whose fields alias the arrays of `st` (the stepped program `s`)
# by id up to `length(s.fields)` and by key after it: `res:c` gets its own array, `c__n` the
# two slots of `c`, and the operator program's `jac:` outputs come from `own`
function _alias_store(st::FieldStore, s::Program, prog::Program; own = Dict{String, Vector{Any}}(), byid::Bool)
    bufs = Vector{Vector{Any}}(undef, length(prog.fields))
    for (i, f) in enumerate(prog.fields)
        j = byid && i <= length(s.fields) ? i : findfirst(x -> x.key == f.key, s.fields)
        if j !== nothing
            bufs[i] = st.bufs[j]
        elseif haskey(own, f.key)
            bufs[i] = own[f.key]
        elseif endswith(f.key, "__n") && (c = findfirst(x -> x.key == f.key[1:(end - 3)], s.fields)) !== nothing
            bufs[i] = st.bufs[c]
        elseif startswith(f.key, "res:")
            u = st.bufs[fieldid(s, f.key[5:end])][1]
            bufs[i] = Any[_zeros(st.backend, eltype(u), length(u))]
        else
            throw(ArgumentError("the implicit program's field `$(f.key)` has no array in the group's store"))
        end
    end
    tables = Any[(j = findfirst(x -> x.key == t.key, s.tables); j === nothing ? _zeros(st.backend, Float64, 1) : st.tables[j])
                 for t in prog.tables]
    return FieldStore(st.backend, bufs, ones(Int, length(bufs)), tables)
end

# the kernels of the residual program for row `key`: its `rate:` kernel and every kernel that
# writes no state field and no residual (aux fields and face values, read by the rate), never
# the masks (they run at the window's start)
function _row_kernels(rs::Program, key, init)
    st = Set(i for (i, f) in enumerate(rs.fields) if f.buffers == 2)
    out = Int[]
    for (i, k) in enumerate(rs.kernels)
        k.key in init && continue
        w = writes(k)
        k.key == "rate:" * key || (!any(f -> f in st || startswith(rs.fields[f].key, "res:"), w) &&
                                   !startswith(k.key, "rate:")) || continue
        push!(out, i)
    end
    return out
end

# The `ImplicitCache` of the implicit algorithm `alg` for the fields `fields` of group `g` on
# store `st` at raw parameters `p`, `n` substeps of `dt / n`
function bind_cache(alg::ImplicitAlgorithm, g::FieldGroup, st::FieldStore, p; fields, n, dt, c, backend, options, V)
    op = operator_spec(g.spec)
    s = group_program(g, alg)                       # the stepped program: the store's
    rs = residual_program(g, alg)
    keys = collect(String, fields)
    order, cyclic = _solve_order(s, keys)
    swaps = Set(fieldid(s, k) for k in keys)
    all_state = issubset(Set(fieldid(s, k) for k in g.spec.state), swaps)
    γ = _gamma(alg)
    h = n == 0 ? Float64(dt) : Float64(dt) / n
    # the operator program, bound to the store and to the `jac:` outputs it owns
    jp = _jac_program(g, op)
    own = Dict{String, Vector{Any}}()
    jac = nothing
    if jp !== nothing
        for f in jp.fields
            startswith(f.key, "jac:") || continue
            own[f.key] = Any[_zeros(st.backend, juliatype(f.storage) === UInt8 ? UInt8 : _eltype(f.storage, eltype(st.bufs[fieldid(s, keys[1])][1])), nsites(jp, 0))]
        end
        jst = _alias_store(st, s, jp; own, byid = false)
        jids = collect(eachindex(jp.kernels))
        jplan = _implicit_plan(g, jp, :jac, jids, V, backend, options)
        # per slot parity and Newton iteration (first: the iterate is the substep's start, slot
        # `par`; later: the other slot), as the residual's
        jcur(par, first) = [(k = findfirst(x -> x.key == f.key, s.fields)) === nothing ? 1 :
                            k in swaps ? (first ? par : 3 - par) : st.cur[k] for f in jp.fields]
        jcurs = (jcur(1, true), jcur(2, true), jcur(1, false), jcur(2, false))
        mkjac = q -> ntuple(i -> BoundStep(backend, jp, jplan, jst, q; cur = jcurs[i], c), 4)
        jac = mkjac(p)
    end
    # the residual store: the stepped program's arrays by id, the residuals and the histories
    rst = _alias_store(st, s, rs; byid = true)
    rows = Any[]
    mkres = Any[]
    exact = !cyclic
    for (ri, key) in enumerate(order)
        r = op.rows[findfirst(x -> x.key == key, op.rows)]
        exact &= r.exact
        id = fieldid(s, key)
        u = st.bufs[id]
        T = _implicit_eltype(u[1], key)
        sp = _implicit_plan(g, rs, (:residual, residual_key(alg), key), _row_kernels(rs, key, g.spec.init), V, backend, options)
        before = Set(fieldid(s, q) for q in order[1:(ri - 1)])
        function rcur(par, first)
            cur = ones(Int, length(rs.fields))
            for (i, f) in enumerate(rs.fields)
                if i <= length(s.fields)
                    cur[i] = i in swaps ? (first && !(i in before) ? par : 3 - par) : (all_state ? par : st.cur[i])
                elseif endswith(f.key, "__n")
                    cur[i] = par
                end
            end
            return cur
        end
        rcurs = (rcur(1, true), rcur(2, true), rcur(1, false), rcur(2, false))
        mk = q -> ntuple(i -> BoundStep(backend, rs, sp, rst, q; cur = rcurs[i], c), 4)
        push!(mkres, mk)
        res = mk(p)
        resarr = rst.bufs[fieldid(rs, "res:" * key)][1]
        # the row's own mask (`c ~ masked(pred, v)`) and its value
        nv = findfirst(x -> x isa NodeValueRule && x.field == id, s.rules)
        mask = nv === nothing ? nothing : array(st, s.masks[s.rules[nv].mask].field, :cur)
        mval = nv === nothing ? zero(T) : T(_coefval(s.rules[nv].value, p))
        mvf = nv === nothing || s.rules[nv].vfield == 0 ? nothing : array(st, s.rules[nv].vfield, :cur)
        lo = alg.lower === nothing ? nothing : T(alg.lower)
        jarr(k) = haskey(own, "jac:$key.$k") ? own["jac:$key.$k"][1] : nothing
        nsite = length(u[1])
        if r.local_only
            sv, numeric = nothing, nothing
            sh = r.field ? _zeros(st.backend, T, nsite) : T(max(1 / (γ * h) - _coefsum(r.jloc, p), 1 / (2γ * h)))
            row = ImplicitRow(key, res, (u[1], u[2]), resarr, nothing, (u[1], u[1]), Int32(0), typeof(u[1])[], nothing,
                nothing, nothing, sh, mask, mval, mvf, lo, nothing, jarr("j"), nothing, nothing, nothing, r.field && r.domain ? jarr("dom") : nothing,
                r, nothing)
            push!(rows, row)
            continue
        end
        inner = alg.inner
        solver_T = alg.solver_T === :auto ? T : alg.solver_T
        if !r.field
            numeric, _ = _numeric_operator(s, r, id, p, h, γ, mask !== nothing)
            ins = mask === nothing ? ("in.f" => resarr,) : ("in.f" => resarr, "mask" => mask)
            sv = Solvers.FieldSolver(backend, numeric; inner, T, solver_T, inputs = ins)
            smask, v, f, sh, jj, mm, dd, dm = nothing, nothing, nothing, numeric.shift, nothing, nothing, nothing, nothing
        else
            numeric = nothing
            N = length(s.periodic)
            dims = Tuple(Int.(leveldims(s, 0)))
            sh = _zeros(st.backend, T, nsite)
            usemask = mask !== nothing || r.domain || r.scaled
            smask = usemask ? _zeros(st.backend, UInt8, nsite) : nothing
            v = r.scaled ? _zeros(st.backend, T, nsite) : nothing
            f = r.scaled ? _zeros(st.backend, T, nsite) : nothing
            jj, mm, dd, dm = jarr("j"), r.scaled ? jarr("m") : nothing, jarr("d"), r.domain ? jarr("dom") : nothing
            cop = Solvers.CellOperator(dims; periodic = s.periodic, face = ntuple(a -> "w$a", N), shift = "s",
                mask = usemask ? "mask" : nothing, value = r.scaled ? "v" : 0.0, name = key)
            ins = Any["in.f" => (r.scaled ? f : resarr), "s" => sh]
            for a in 1:N
                push!(ins, "w$a" => jarr("w$a"))
            end
            usemask && push!(ins, "mask" => smask)
            r.scaled && push!(ins, "v" => v)
            sv = Solvers.FieldSolver(backend, cop; inner, T, solver_T, inputs = Tuple(ins))
        end
        xid = Solvers.fid(sv, Solvers.solution_key(sv))
        xb = sv.bufs[xid]
        wid = Solvers.fid(sv, Solvers.working_key(sv))
        work = [w for w in sv.bufs[wid]]
        row = ImplicitRow(key, res, (u[1], u[2]), resarr, sv, (xb[1], xb[end]), xid, work,
            sv.tables[Solvers.tid(sv, "solve.scal")], smask, v, sh, mask, mval, mvf, lo, f, jj, mm, dd, mask, dm, r, numeric)
        push!(rows, row)
    end
    # a Robin face with a negative diagonal leaves its part out of the operator (a defect correction)
    exact &= !any(r -> _negative_robin(s, fieldid(s, r.key), p), rows)
    # one Newton step for an exact operator, two with a switch (one flip pass, S1), four for a
    # defect correction (F3-09b sets it from the bound)
    switch = any(r -> r.op.switch, rows)
    newton = alg.newton !== nothing ? alg.newton : exact ? (switch ? 2 : 1) : 4
    iterate = any(r -> r.op.iterate, rows)
    # the operator moves when it reads the time, the clock, a filled input or a field of the state
    # (rebuilt each window), or the solver reads a mask that moves
    moving = _jac_moving(jp, g.spec) || any(r -> r.mask !== nothing || r.dom !== nothing, rows) && _masks_moving(s, g.spec)
    word = _zeros(st.backend, UInt32, 8)
    rt = Tuple(rows)
    mkjac0 = jp === nothing ? (q -> nothing) : mkjac
    rebind = q -> ([m(q) for m in mkres], mkjac0(q))
    return ImplicitCache(rt, each(length(rt)), jac, newton, h, true, moving, word, op, exact, iterate, 0, rebind, backend)
end

# whether the kernels of program `p` read data that change every window: the time, the clock's
# slot, a filled input, or a field the group steps
function _reads_moving(p::Program, ks, spec::GroupSpec)
    filled = Set(i.key for i in spec.inputs if i.filled)
    cs = clock_slot(spec)
    for k in ks, n in k.nodes
        n.op == RUNTIME && n.imm == RT_T && return true
        n.op == PARAM && cs != 0 && n.imm == cs && return true
    end
    for k in ks, n in k.nodes                   # (the loads: an `INSIDE_OP` test reads no value)
        n.op == LOAD || continue
        f = p.fields[k.accesses[n.imm].field]
        (f.key in filled || f.key in spec.state || f.key in spec.external) && return true
    end
    return false
end
# whether the operator program reads the time (its value changes within a window: each
# substep's operator is built at that substep's end time)
_reads_time(p::Program) = any(n -> n.op == RUNTIME && n.imm == RT_T, (n for k in p.kernels for n in k.nodes))
_jac_moving(::Nothing, spec) = false
_jac_moving(jp::Program, spec) = _reads_moving(jp, jp.kernels, spec)
_masks_moving(s::Program, spec) = _reads_moving(s, [k for k in s.kernels if k.key in spec.init], spec)

# the step `h` of the coefficients (a count change, a rebind): the numeric shifts follow; the
# hierarchy is rebuilt before the next solve
function _set_step!(c::ImplicitCache, rt::GroupRuntime, h::Float64)
    γ = _gamma(rt.alg)
    s = group_program_of(rt)
    for r in c.rows
        _set_row_step!(r, s, rt.p, h, γ)
    end
    c.h = h
    c.stale = true
    return nothing
end
group_program_of(rt::GroupRuntime) = rt.program
function _set_row_step!(r::ImplicitRow, s, p, h, γ)
    if r.solver === nothing
        r.s isa Number && (r.s = oftype(r.s, max(1 / (γ * h) - _coefsum(r.op.jloc, p), 1 / (2γ * h))))
        return nothing
    end
    r.numeric === nothing && return nothing
    op, _ = _numeric_operator(s, r.op, fieldid(s, r.key), p, h, γ, r.mask !== nothing)
    Solvers.set_coefficients!(r.solver, op)
    r.numeric = op
    r.s = op.shift
    return nothing
end

# Rebuild the operator before a window's solves (stale or moving): the operator program at the
# substep's end time, each field row's shift and solver mask, then each solver's hierarchy
function _rebuild!(c::ImplicitCache, rt::GroupRuntime, par::Int, t1::Float64, h::Float64, k::Int)
    c.jac === nothing || c.jac[par]((t1, h, k))
    c.walk(c.rows, _Rebuild(c.backend, h, _gamma(rt.alg), c.word, false, rt.totals.windows % Int32))     # (each row: the rows' types differ)
    c.stale = false
    c.rebuilds += 1
    return nothing
end
# … and at a Newton iteration of a group whose operator reads the iterate (`c.iterate`): the
# operator program at the iterate (slot `par` at the first iteration, the other slot after),
# then the rows that read it
function _rebuild_iterate!(c::ImplicitCache, rt::GroupRuntime, par::Int, first::Bool, t1::Float64, h::Float64, k::Int)
    c.jac[(first ? 0 : 2) + par]((t1, h, k))
    c.walk(c.rows, _Rebuild(c.backend, h, _gamma(rt.alg), c.word, true, rt.totals.windows % Int32))
    return nothing
end
struct _Rebuild{B, W}
    backend::B
    h::Float64
    γ::Float64
    word::W
    iterate::Bool                       # only the rows whose operator reads the iterate
end
(r::ImplicitRow)(a::_Rebuild) = (a.iterate && !r.op.iterate) ? nothing : _rebuild_row!(r, a.backend, a.h, a.γ, a.word)
function _rebuild_row!(r::ImplicitRow, backend, h, γ, word)
    if r.s isa AbstractArray
        T = eltype(r.s)
        Exec.launch!(backend, _be_shift_body!, length(r.s), (r.s, r.j, r.d, r.m, r.smask, r.rmask, r.dom,
            T(1 / (γ * h)), T(1 / (2γ * h)), word))
    end
    r.solver === nothing || Solvers.rebuild!(r.solver)
    return nothing
end

# One Newton iteration of one row (`a = (parity, first, t1, h, k, last, window, backend, γ, word)`):
# the residual at `tⁿ⁺¹`, the solve, the status, the update into the other slot
function (r::ImplicitRow)(a)
    par, first, t1, h, k, last, window, backend, γ, word = a
    r.res[(first ? 0 : 2) + par]((t1, h, k))
    dst = r.bufs[3 - par]
    src = first ? r.bufs[par] : dst
    n = length(dst)
    if r.solver === nothing
        Exec.launch!(backend, _be_update_body!, n, (dst, src, nothing, nothing, nothing, r.resarr, r.s, r.mask, r.mval,
            r.mvf, r.lo, last))
        return nothing
    end
    sv = r.solver
    if r.f !== nothing                          # a scaled row: the right side `G/m` and the own rows' δ
        T = eltype(r.f)
        Exec.launch!(backend, _be_rhs_body!, n, (r.f, r.v, r.resarr, r.j, r.m, r.smask, r.rmask, r.dom, T(1 / (γ * h)),
            T(1 / (2γ * h))))
    end
    for w in r.work                             # δ from 0
        Exec.launch!(backend, _zero_body!, length(w), (w,))
    end
    Solvers.lift!(sv)
    Solvers.solve!(sv)
    Exec.launch!(backend, _be_status_body!, 1, (word, r.scal, Int32(window)))
    x = sv.slot[r.xid] == 1 ? r.xs[1] : r.xs[2]
    Exec.launch!(backend, _be_update_body!, n, (dst, src, x, r.smask, r.v, nothing, nothing, r.mask, r.mval, r.mvf,
        r.lo, last))
    return nothing
end

# The substeps of a window (F3 design §3.3): the operator rebuilt when stale or moving, then per
# substep the Newton iterations over the rows in solve order, the slot swap at the end
function _substeps!(c::ImplicitCache, rt::GroupRuntime, t::Float64, h::Float64, k::Int, n::Integer)
    # a window of length 0 (front end A's at-init clamp: the masks, and the aux fields of the
    # state as it is) and a group with no state step as the explicit program does (`h = 0`
    # leaves the state unchanged)
    (n == 0 || h == 0) && return _substeps!(nothing, rt, t, h, k, n)
    st = rt.store
    h == c.h || _set_step!(c, rt, h)
    fresh = c.stale || c.moving
    fresh && _rebuild!(c, rt, _parity(rt), t + h, h, k)
    γ = _gamma(rt.alg)
    w = rt.totals.windows % Int32
    for j in 1:n
        par = _parity(rt)
        t1 = t + j * h
        for it in 1:(c.newton)
            # (the window's rebuild is the first iteration's of its first substep)
            c.iterate && !(fresh && j == 1 && it == 1) && _rebuild_iterate!(c, rt, par, it == 1, t1, h, k)
            c.walk(c.rows, (par, it == 1, t1, h, k, it == c.newton, w, c.backend, γ, c.word))
        end
        _swap!(st.cur, rt.swaps)
    end
    return nothing
end

# a rebind (new parameter values): the residual and operator launches bound again, the numeric
# rows' coefficients set (`set_coefficients!`, no recompile); the hierarchy rebuilds at the
# next window. In two parts as `rebind_launches`/`install_launches!`: the first may throw.
function rebind_launches(rt::GroupRuntime{<:FieldStore, <:ImplicitAlgorithm}, p)
    steps = (_bind_steps(rt.backend, rt.program, rt.step, rt.store, p, rt.swaps, rt.all_state, rt.c),
        _bind_masks(rt.backend, rt.program, rt.init, rt.store, p, rt.swaps, rt.all_state, rt.c,
            Set(fieldid(rt.program, k) for k in rt.keys)))
    c = rt.cache::ImplicitCache
    res, jac = c.rebind(p)
    γ = _gamma(rt.alg)
    ops = Any[r.numeric === nothing ? nothing :
              first(_numeric_operator(rt.program, r.op, fieldid(rt.program, r.key), p, c.h, γ, r.mask !== nothing))
              for r in c.rows]
    shifts = Any[r.solver === nothing && r.s isa Number ? oftype(r.s, max(1 / (γ * c.h) - _coefsum(r.op.jloc, p), 1 / (2γ * c.h))) :
                 nothing for r in c.rows]
    return (steps[1], steps[2], (res, jac, ops, shifts))
end
function install_launches!(rt::GroupRuntime{<:FieldStore, <:ImplicitAlgorithm}, (steps, masks, (res, jac, ops, shifts)))
    rt.steps, rt.masks = steps, masks
    c = rt.cache::ImplicitCache
    for (i, r) in enumerate(c.rows)
        r.res = res[i]
        if ops[i] !== nothing
            Solvers.set_coefficients!(r.solver, ops[i])
            r.numeric = ops[i]
            r.s = ops[i].shift
        end
        shifts[i] === nothing || (r.s = shifts[i])
    end
    c.jac = jac
    reset!(rt)
    return rt
end

"""
    substeps(spec::GroupSpec, alg::ImplicitAlgorithm, dt, pp; fields = spec.state, stability = spec.stability,
             key = identity, texts = ProblemTexts(spec.texts.route)) -> Int

The substep count of an implicit algorithm (F3 design §3.7), the same policy as the explicit
one with the implicit rule: the parameter refusals first (a negative diffusion coefficient, a
coefficient that is not finite where the inputs reach), then `n = max(m, ⌈2 dt g⌉)`, `m` the
user's count (1 when left out) and `g` the largest positive local derivative the operator sees
([`growth`](@ref)): the shift `1/h − g` stays at least half of `1/h`. No stability bound is
needed: an unknown bound is no refusal.
"""
function substeps(spec::GroupSpec, alg::ImplicitAlgorithm, dt::Real, pp; fields = spec.state, stability = spec.stability,
        key = identity, texts::PolicyTexts = ProblemTexts(spec.texts.route))
    isempty(fields) && return 0
    dt = Float64(dt)
    r = bound_report(stability, pp)
    ctx = (; stability, pp, r, fields = collect(String, fields), dt, least = alg.substeps)
    (isempty(r.negative) && !any(x -> x[3] isa Tuple, r.nonfinite)) || refuse_parameters(texts, ctx)
    g = growth(operator_spec(spec), collect(String, fields), pp)
    return max(something(alg.substeps, 1), ceil(Int, 2 * dt * g))
end
substeps(g::FieldGroup, alg::ImplicitAlgorithm, dt::Real, pp; kw...) = substeps(g.spec, alg, dt, pp; kw...)

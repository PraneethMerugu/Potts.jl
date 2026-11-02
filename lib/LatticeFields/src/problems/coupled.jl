# The coupled solve of an implicit group (F3-12d): a QuasiSteady group whose fields read one
# another, or given `inner = DeviceGMRES(…)`, solves its rows together. Each
# Newton iteration solves `A δ = G(u_k)` over every field of the group at once, `A` the whole
# Jacobian of the residual (`A v = −(G(u_k + εv) − G(u_k))/ε`: the residual kernels themselves,
# every term of every row, the cross terms included; exact at any ε for a group that is linear
# in its state, so ε is then as large as the iterate, else `√eps` of it), by Krylov.jl's restarted
# flexible GMRES, preconditioned block by block (each field's own operator `J̃_ii`, solved by its
# `FieldSolver` with the `DeviceGMRES`'s `precond`). The update, the clip, the Newton check and
# the status word are the per-row path's.
#
# Krylov.jl runs on the host and keeps the Hessenberg matrix there; the vectors are a
# [`CoupledVector`](@ref): the group's fields one after another in one array of the backend,
# whose dot products are fixed-order block reductions (a partial per 256-site block written by
# one work item, then one item sums them in block order; no atomics, no BLAS). The same backend
# therefore repeats a run bit for bit, and the host and a device run the same arithmetic in the
# same order. On a device each dot product is one wait for its value: the coupled steady groups'
# exception to D-101 (user ruling 2026-11-01); every other field path waits for nothing.

# the scalars of a coupled solve (`K[GM_SCALARS]`): the solver scalars that the status body reads
# (`Solvers.DONE` 1: 0 a budget hit, 1 converged, 3 diverged; `ITER` 2, `RNORM` 6, `BNORM` 7,
# `TOL` 8), the difference step (`GM_EPS`) and the iterate's size (`GM_UN`)
const GM_EPS, GM_UN, GM_SCALARS = 10, 11, 16
const _GM_DONE, _GM_ITER, _GM_RNORM, _GM_BNORM, _GM_TOL = Solvers.DONE, Solvers.ITER, Solvers.RNORM, Solvers.BNORM, Solvers.TOL

# a site of a row that the solve holds at 0 (its mask, or outside the domain)
@inline _cs_fixed(mask, dom, i) = @inbounds (mask !== nothing && mask[i] != 0) || (dom !== nothing && dom[i] == 0)

# the right side `b = G(u_k)` (0 at the fixed sites; `b` at offset `off`)
function _cs_load_body!(i, b, off, res, mask, dom)
    @inbounds b[off + i] = _cs_fixed(mask, dom, i) ? zero(eltype(b)) : eltype(b)(res[i])
    return nothing
end
# block partials (`b ≤ cld(n, NB)`, `off + b ≤ length(part)`): the largest magnitude of `a`
# (offset `aoff`; a NaN stays) …
function _cs_max_body!(b, part, off, a, aoff, n)
    @inbounds begin
        K = eltype(part)
        acc = zero(K)
        for i in ((b - 1) * NB + 1):min(b * NB, n)
            acc = _nanmax(acc, abs(K(a[aoff + i])))
        end
        part[off + b] = acc
    end
    return nothing
end
# … and the dot product of `x` and `y`
function _cs_dot_body!(b, part, x, y, n)
    @inbounds begin
        K = eltype(part)
        acc = zero(K)
        for i in ((b - 1) * NB + 1):min(b * NB, n)
            acc += x[i] * y[i]
        end
        part[b] = acc
    end
    return nothing
end
# the sum of the partials `1:nb` into `part[nb + 1]`, in block order (one item)
function _cs_sum_body!(i, part, nb)
    @inbounds begin
        acc = zero(eltype(part))
        for k in 1:nb
            acc += part[k]
        end
        part[nb + 1] = acc
    end
    return nothing
end
function _cs_maxsum(part, nb)
    K = eltype(part)
    acc = zero(K)
    @inbounds for k in 1:nb
        acc = _nanmax(acc, part[k])
    end
    return acc
end
# the iterate's size `‖u_k‖∞` from the rows' partials (one item)
function _cs_un_body!(i, scal, part, nb)
    @inbounds scal[GM_UN] = _cs_maxsum(part, nb)
    return nothing
end
# The difference step of a product `A z` (one item): `ε = f (1 + ‖u_k‖∞)/‖z‖∞` (`f` 1 for a
# linear group, √eps otherwise; `part` holds the partials of ‖z‖∞); a zero (or not finite) z
# takes ε = 1 (its product is then exactly 0, or not finite, which the solve detects)
function _cs_eps_body!(i, scal, part, nb, f)
    @inbounds begin
        K = eltype(scal)
        zm = _cs_maxsum(part, nb)
        scal[GM_EPS] = (zm > 0 && isfinite(zm)) ? f * (one(K) + scal[GM_UN]) / zm : one(K)
    end
    return nothing
end
# the perturbed state `u_k + ε z` (z at offset `off`; the fixed sites keep `u_k`)
function _cs_pert_body!(i, pert, u, z, off, mask, dom, scal)
    @inbounds pert[i] = _cs_fixed(mask, dom, i) ? u[i] : u[i] + scal[GM_EPS] * z[off + i]
    return nothing
end
# the product `w = A z = −(G(u_k + εz) − G(u_k))/ε` (`b` holds `G(u_k)`; all at offset `off`);
# the fixed sites map `z` to itself (their `z` is 0)
function _cs_av_body!(i, w, g2, b, z, off, mask, dom, scal)
    @inbounds begin
        K = eltype(w)
        w[off + i] = _cs_fixed(mask, dom, i) ? z[off + i] : -(K(g2[i]) - b[off + i]) / scal[GM_EPS]
    end
    return nothing
end
# the vector kernels of a [`CoupledVector`](@ref)
function _cs_axpy_body!(i, y, s, x)
    @inbounds y[i] += s * x[i]
    return nothing
end
function _cs_axpby_body!(i, y, s, x, t)
    @inbounds y[i] = s * x[i] + t * y[i]
    return nothing
end
function _cs_copy_body!(i, y, x)
    @inbounds y[i] = x[i]
    return nothing
end
function _cs_div_body!(i, y, x, s)
    @inbounds y[i] = x[i] / s
    return nothing
end
function _cs_fill_body!(i, x, v)
    @inbounds x[i] = v
    return nothing
end
# the preconditioner's input: a row's part of `v` (offset `off`) into its right side (its `res:`
# array), and its output into `z`
function _cs_pin_body!(i, dst, v, off)
    @inbounds dst[i] = v[off + i]
    return nothing
end
function _cs_pout_body!(i, z, off, x, mask, dom)
    @inbounds z[off + i] = _cs_fixed(mask, dom, i) ? zero(eltype(z)) : x[i]
    return nothing
end
# a row with no diffusion: `z = v / s` (a shift that is not positive: `z = v`)
function _cs_plocal_body!(i, z, off, v, s, mask, dom)
    @inbounds begin
        K = eltype(z)
        d = K(_at(s, i))
        z[off + i] = _cs_fixed(mask, dom, i) ? zero(K) : (d > 0 ? v[off + i] / d : v[off + i])
    end
    return nothing
end
# a scaled row's preconditioner right side (as `_be_rhs_body!`): `v/m` where `m > 0`, and at a
# row with `m = 0` its own `v/(shift)` as the solver's mask value (a shift that is not positive: v)
function _cs_rhs_body!(i, f, v, res, j, m, smask, rmask, dom, ih, ih2)
    @inbounds begin
        g = res[i]
        if smask[i] != 0
            f[i] = zero(eltype(f))
            own = !(m[i] > 0) && !(rmask !== nothing && rmask[i] != 0) && !(dom !== nothing && dom[i] == 0)
            d = max(ih - _jat(j, i, ih), ih2)
            v[i] = own ? (d > 0 ? g / d : g) : zero(eltype(v))
        else
            f[i] = g / m[i]
            v[i] = zero(eltype(v))
        end
    end
    return nothing
end
# The status after a coupled solve (one item; as `_be_status_body!`): [4] the solve, [5] a budget
# hit, a failure into [1]–[3]: a value that is not finite (4), a breakdown (128), a divergence (1
# and, steady, 64),
# a steady budget hit that did not halve its residual (64: the coupled system has no unique
# steady state, or the budget is short)
function _cs_status_body!(i, w, scal, window, steady, gate)
    @inbounds begin                             # i = 1; w has 9 entries
        (gate !== nothing && gate[1] != 0) && return nothing
        d, rn = scal[_GM_DONE], scal[_GM_RNORM]
        w[STATUS_SOLVES] += UInt32(1)
        fail = UInt32(0)
        if d == 5
            fail = UInt32(128)
        elseif d == 3
            fail = isfinite(rn) ? (steady ? UInt32(1 | 64) : UInt32(1)) : UInt32(4)
        elseif d == 0
            w[STATUS_BUDGET] += UInt32(1)
            steady && !(rn <= scal[_GM_BNORM] / 2) && (fail = UInt32(64))
        end
        if fail != 0
            w[STATUS_CODE] = UInt32(2)
            w[STATUS_CAUSE] |= fail
            w[STATUS_WINDOW] == 0 && (w[STATUS_WINDOW] = UInt32(window))
        end
    end
    return nothing
end

"""
    CoupledVector{K, A, B}

A vector of a coupled solve for Krylov.jl: the group's fields one after another in `a` (an
array of the backend `backend`, element type `K`), with the dot-product partials `part`
(`cld(length(a), 256) + 1`, shared by the vectors of one solve) and a one-entry host buffer.
Its dot product and norm are fixed-order block reductions, so a run repeats bit for bit and
the host and a device agree; the other vector operations are elementwise kernels. Krylov.jl
reaches them through its vector functions (`kdot`, `knorm`, `kaxpy!`, `kaxpby!`, `kcopy!`,
`kdivcopy!`, `kfill!`); it never indexes the vector.
"""
struct CoupledVector{K, A <: AbstractVector{K}, B} <: AbstractVector{K}
    a::A
    part::A
    host::Vector{K}
    backend::B
end
Base.size(v::CoupledVector) = size(v.a)
# (Krylov.jl reaches the vector through its vector functions only; an element access means a
# missed dispatch, which would run generic code with other rounding: an error on every backend)
Base.getindex(::CoupledVector, ::Int) = throw(ArgumentError("a `CoupledVector` is not indexed (Krylov.jl's vector functions only)"))
Base.setindex!(::CoupledVector, _, ::Int) = throw(ArgumentError("a `CoupledVector` is not indexed (Krylov.jl's vector functions only)"))
Base.similar(v::CoupledVector) = CoupledVector(similar(v.a), v.part, v.host, v.backend)
Base.similar(v::CoupledVector, n::Int) = CoupledVector(similar(v.a, n), v.part, v.host, v.backend)
Base.show(io::IO, v::CoupledVector) = print(io, "CoupledVector(", length(v.a), " × ", eltype(v.a), ")")
Base.show(io::IO, ::MIME"text/plain", v::CoupledVector) = show(io, v)
_cvec(a, part, backend) = CoupledVector(a, part, zeros(eltype(a), 1), backend)
function _cs_dot(x::CoupledVector, y::CoupledVector)
    n = length(x.a)
    nb = cld(n, NB)
    Exec.launch!(x.backend, _cs_dot_body!, nb, (x.part, x.a, y.a, n))
    Exec.launch!(x.backend, _cs_sum_body!, 1, (x.part, nb))
    copyto!(x.host, 1, x.part, nb + 1, 1)       # (on a device: the wait, D-101's exception)
    return @inbounds x.host[1]
end
_cs_n(v::CoupledVector) = length(v.a)
Krylov.kdot(n::Integer, x::CoupledVector{K}, y::CoupledVector{K}) where {K <: AbstractFloat} = _cs_dot(x, y)
Krylov.knorm(n::Integer, x::CoupledVector{K}) where {K <: AbstractFloat} = sqrt(_cs_dot(x, x))
Krylov.kaxpy!(n::Integer, s::K, x::CoupledVector{K}, y::CoupledVector{K}) where {K <: AbstractFloat} =
    (Exec.launch!(y.backend, _cs_axpy_body!, _cs_n(y), (y.a, s, x.a)); y)
Krylov.kaxpby!(n::Integer, s::K, x::CoupledVector{K}, t::K, y::CoupledVector{K}) where {K <: AbstractFloat} =
    (Exec.launch!(y.backend, _cs_axpby_body!, _cs_n(y), (y.a, s, x.a, t)); y)
Krylov.kcopy!(n::Integer, y::CoupledVector{K}, x::CoupledVector{K}) where {K <: AbstractFloat} =
    (Exec.launch!(y.backend, _cs_copy_body!, _cs_n(y), (y.a, x.a)); y)
Krylov.kdivcopy!(n::Integer, y::CoupledVector{K}, x::CoupledVector{K}, s::K) where {K <: AbstractFloat} =
    (Exec.launch!(y.backend, _cs_div_body!, _cs_n(y), (y.a, x.a, s)); y)
Krylov.kfill!(x::CoupledVector{K}, v::K) where {K <: AbstractFloat} = (Exec.launch!(x.backend, _cs_fill_body!, _cs_n(x), (x.a, v)); x)

"""
One row of a coupled solve ([`CoupledKrylov`](@ref)): its [`ImplicitRow`](@ref) (the residual
launches, the state, the preconditioner's solver), its sites `n`, its offset `voff` in the
coupled vectors, its block offset `off` and block count `nb` in the iterate's partials, the
perturbed state `pert`, its residual `g2` and the residual launches bound to them (`pres`, per
slot parity and iteration kind as the row's).
"""
mutable struct CoupledRow{IR, P, G, L}
    row::IR
    n::Int
    voff::Int
    off::Int
    nb::Int
    pert::P
    g2::G
    pres::L
end

# the operator `A` and the preconditioner of a coupled solve, as Krylov.jl takes them (`mul!`);
# `it` holds the Newton iteration's arguments `(par, first, t1, h, k)`
mutable struct CoupledOperator{RS, WK, A, S, B, K}
    rows::RS
    walk::WK
    b::A
    zpart::S
    scal::S
    f::K
    n::Int
    backend::B
    it::Tuple{Int, Bool, Float64, Float64, Int}
end
struct CoupledPrecond{RS, WK, B}
    rows::RS
    walk::WK
    backend::B
end
Base.size(A::CoupledOperator) = (A.n, A.n)
Base.eltype(::CoupledOperator{RS, WK, A, S, B, K}) where {RS, WK, A, S, B, K} = K
Base.size(P::CoupledPrecond) = (0, 0)

"""
    CoupledKrylov

The coupled solve of a `QuasiSteady` group (F3-12d, [`Solvers.DeviceGMRES`](@ref
LatticeFields.Solvers.DeviceGMRES)): its rows ([`CoupledRow`](@ref)), the operator and the
preconditioner, the Krylov.jl FGMRES workspace (restart `m`), the iterate's partials, the
scalars (device), their host copy, the `budget`, `rtol`, whether the group is linear in its
state, `mkpres`, which binds the perturbed residual launches at new parameters (a rebind), and
a nonlinear steady group's pending growth check (`pending`, `σ`, `keys`; r2 M1).
"""
mutable struct CoupledKrylov{RS, WK, OP, PC, WS, A, S, H}
    rows::RS
    walk::WK
    A::OP
    P::PC
    ws::WS
    part::A
    nbt::Int
    scal::S
    hscal::H
    m::Int
    budget::Int
    rtol::Float64
    linear::Bool
    mkpres::Any
    pending::Int            # a nonlinear steady group's growth check: 1 due after its next solve
    σ::Float64              # (its Cayley shift)
    keys::Vector{String}
end

"""
    coupled_solve(alg, op, s, keys) -> Bool

Whether the implicit group of the fields `keys` (its operator `op`, its stepped program `s`)
takes the coupled solve (F3-12d): a `QuasiSteady` group with `inner = DeviceGMRES(…)` always, or
when its rows read one another in a cycle, or a row reads another field of the group through a
term the operator does not take as a source (a cross diffusion `D Δ(o)`, a nonlinear term such
as `c²`, a term that reads its own field and another): its steady rows are then solved together,
the cross terms in the operator. Otherwise the rows are solved one by one in the order of their
reads (exact for an acyclic group with linear cross terms).
"""
function coupled_solve(alg, op::OperatorSpec, s::Program, keys)
    alg isa ImplicitAlgorithm || return false
    alg isa QuasiSteady || return false                # (a time stepper refuses `DeviceGMRES`)
    alg.inner isa Solvers.DeviceGMRES && return true
    length(keys) >= 2 || return false
    deps = _group_deps(s, keys)
    _, cyclic = _solve_order(s, keys)
    cyclic && return true
    for r in op.rows
        (r.key in keys && !isempty(deps[r.key])) || continue
        (!r.exact || !isempty(r.unseen) || any(x -> x[1] in keys && isnan(x[2].value), r.cross)) && return true
    end
    return false
end
coupled_solve(c::ImplicitCache) = c.cs !== nothing
coupled_solve(::Any) = false

# the Krylov solver of a coupled group from its `inner`: a `DeviceGMRES` as given; `:auto` (and
# the steady start's default) its defaults; a `DevicePCG` or `Multigrid` given for the group
# becomes each field's preconditioner
function _krylov(inner)
    inner isa Solvers.DeviceGMRES && return inner
    inner === :auto && return Solvers.DeviceGMRES()
    inner === STEADY_INNER && return STEADY_GMRES
    return Solvers.DeviceGMRES(; precond = inner)
end
# the per-field solver of a row of a group (its preconditioner when the group is coupled)
_row_inner(alg, coupled::Bool) = coupled ? Solvers.gmres_precond(_krylov(alg.inner)) : alg.inner
# the steady start's and the time-free solve's coupled solver (as `STEADY_INNER`, 64 PCG
# iterations to 1e-6: a larger budget, its fields' preconditioners at their default)
const STEADY_GMRES = Solvers.DeviceGMRES(; restart = 30, budget = 240)

# A coupled solve's arrays and launches for the rows `rows` (in solve order) of a group bound to
# store `st` (stepped program `s`, residual program `rs`, its store `rst`, the residual plans
# `sps`, the slot sets `rcurs` per row), `kr` its `DeviceGMRES`
function _bind_coupled(rows, kr::Solvers.DeviceGMRES, st::FieldStore, s::Program, rs::Program, rst::FieldStore, sps, rcurss,
        swaps, keys, init, backend, p, c, op::OperatorSpec, alg)
    K = mapreduce(r -> eltype(r.resarr), promote_type, rows)
    for r in rows
        eltype(r.bufs[1]) === Float16 && throw(ArgumentError(string(_algname(alg), ": the fields ", join(("`$k`" for k in keys), ", "),
            " are solved together (their rows read one another), and the field `", r.key, "` is stored in Float16, whose ",
            "rounding is too coarse for the coupled solve's difference of the residual; give it `lattice_storage = Float32`")))
    end
    # the perturbed store: the residual store's arrays, with the group's fields on the perturbed
    # states, the residuals on their own arrays and the aux fields the rows write on copies (the
    # main residual's stay as they are)
    perts = Dict{String, Any}(r.key => _zeros(st.backend, eltype(r.bufs[1]), length(r.bufs[1])) for r in rows)
    g2s = Dict{String, Any}(r.key => _zeros(st.backend, eltype(r.resarr), length(r.resarr)) for r in rows)
    pbufs = copy(rst.bufs)
    for k in keys
        pbufs[fieldid(rs, k)] = Any[perts[k], perts[k]]
        pbufs[fieldid(rs, "res:" * k)] = Any[g2s[k]]
    end
    gids = Set(fieldid(rs, k) for k in keys)
    for k in keys, i in _row_kernels(rs, k, init), w in writes(rs.kernels[i])
        (w in gids || startswith(rs.fields[w].key, "res:")) && continue
        pbufs[w] = Any[_zeros(st.backend, eltype(b), length(b)) for b in rst.bufs[w]]
    end
    pst = FieldStore(st.backend, pbufs, copy(rst.cur), rst.tables)
    mkpres = q -> Tuple(ntuple(i -> BoundStep(backend, rs, sps[ri], pst, q; cur = rcurss[ri][i], c), 4) for ri in eachindex(rows))
    pres = mkpres(p)
    off, voff = 0, 0
    crs = Any[]
    for (ri, r) in enumerate(rows)
        n = length(r.bufs[1])
        nb = cld(n, NB)
        push!(crs, CoupledRow(r, n, voff, off, nb, perts[r.key], g2s[r.key], pres[ri]))
        off += nb
        voff += n
    end
    ntot = voff
    rws, walk = Tuple(crs), each(length(crs))
    vpart = _zeros(st.backend, K, cld(ntot, NB) + 1)
    b = _cvec(_zeros(st.backend, K, ntot), vpart, st.backend)
    scal = _zeros(st.backend, K, GM_SCALARS)
    linear = all(r -> r.op.linear, rows)
    f = K(linear ? 1.0 : sqrt(Float64(eps(K))))
    A = CoupledOperator(rws, walk, b, _zeros(st.backend, K, cld(ntot, NB) + 1), scal, f, ntot, st.backend, (1, true, 0.0, 1.0, 0))
    P = CoupledPrecond(rws, walk, st.backend)
    m = min(kr.restart, kr.budget)
    ws = Krylov.FgmresWorkspace(Krylov.KrylovConstructor(b); memory = m)
    sizehint!(ws.stats.residuals, kr.budget + cld(kr.budget, m) + 2)
    return CoupledKrylov(rws, walk, A, P, ws, _zeros(st.backend, K, off), off, scal, zeros(K, GM_SCALARS), m, kr.budget,
        kr.rtol, linear, mkpres, 0, 1.0, collect(String, keys))
end

# a per-row operation of a coupled solve, `S` its name and `a` its arguments
struct _CsOp{S, A}
    a::A
end
_csop(S::Symbol, a) = _CsOp{S, typeof(a)}(a)
# the row's iterate: slot `par` at the first Newton iteration, the other slot after it
_cs_u(cr::CoupledRow, par, first) = first ? cr.row.bufs[par] : cr.row.bufs[3 - par]

# the row's residual at the iterate (gated as the row's own solve) into `b`, and the partials of
# the iterate's size
function (cr::CoupledRow)(o::_CsOp{:residual})
    (par, first, t1, h, k, b, part, backend, gate) = o.a
    r = cr.row
    r.res[(first ? 0 : 2) + par]((t1, h, k))
    gate === nothing || Exec.launch!(backend, _be_gate_body!, length(r.resarr), (r.resarr, gate))
    Exec.launch!(backend, _cs_load_body!, cr.n, (b, cr.voff, r.resarr, r.mask, r.dom))
    Exec.launch!(backend, _cs_max_body!, cr.nb, (part, cr.off, _cs_u(cr, par, first), 0, cr.n))
    return nothing
end
# the preconditioner `y = P v`: each field's own solve (its `FieldSolver`, from 0), or `v/s`
function (cr::CoupledRow)(o::_CsOp{:precond})
    (y, v, backend) = o.a
    r = cr.row
    if r.solver === nothing
        Exec.launch!(backend, _cs_plocal_body!, cr.n, (y, cr.voff, v, r.s, r.mask, r.dom))
        return nothing
    end
    Exec.launch!(backend, _cs_pin_body!, cr.n, (r.resarr, v, cr.voff))
    if r.f !== nothing
        T = eltype(r.f)
        Exec.launch!(backend, _cs_rhs_body!, cr.n, (r.f, r.v, r.resarr, r.j, r.m, r.smask, r.rmask, r.dom, zero(T), zero(T)))
    end
    for w in r.work
        Exec.launch!(backend, _zero_body!, length(w), (w,))
    end
    sv = r.solver
    Solvers.lift!(sv)
    Solvers.solve!(sv)
    x = sv.slot[r.xid] == 1 ? r.xs[1] : r.xs[2]
    Exec.launch!(backend, _cs_pout_body!, cr.n, (y, cr.voff, x, r.mask, r.dom))
    return nothing
end
# the product `w = A z`: the perturbed state, its residual at the stage's time, the difference
function (cr::CoupledRow)(o::_CsOp{:perturb})
    (z, par, first, scal, backend) = o.a
    Exec.launch!(backend, _cs_pert_body!, cr.n, (cr.pert, _cs_u(cr, par, first), z, cr.voff, cr.row.mask, cr.row.dom, scal))
    return nothing
end
function (cr::CoupledRow)(o::_CsOp{:product})
    (w, z, b, par, first, t1, h, k, scal, backend) = o.a
    cr.pres[(first ? 0 : 2) + par]((t1, h, k))
    Exec.launch!(backend, _cs_av_body!, cr.n, (w, cr.g2, b, z, cr.voff, cr.row.mask, cr.row.dom, scal))
    return nothing
end
# the update `u_{k+1} = u_k + δ` (δ the row's part of the solve's `x`) into the other slot, its
# masks and clip, and with `check` the Newton check of iteration `it` (a steady group: no real
# reduction is cause 64)
function (cr::CoupledRow)(o::_CsOp{:update})
    (x, par, first, last, check, it, hits, window, steady, word, backend) = o.a
    r = cr.row
    dst = r.bufs[3 - par]
    src = first ? r.bufs[par] : dst
    n = cr.n
    δ = view(x, (cr.voff + 1):(cr.voff + n))
    Exec.launch!(backend, _be_update_body!, n, (dst, src, δ, nothing, nothing, nothing, nothing, r.mask, r.mval, r.mvf, r.lo, last))
    check || return nothing
    nb = cld(n, NB)
    T = eltype(r.part)
    Exec.launch!(backend, _be_norms_body!, nb, (r.part, dst, r.bufs[par], δ, nothing, nothing, nothing, nothing, r.mask, n))
    fl = eltype(dst) === Float16 ? T(10 * eps(T) + 2 * eps(Float16)) : T(10 * eps(T))
    Exec.launch!(backend, _be_newton_body!, 1, (word, r.part, Int32(nb), r.hist, Int32(it), hits, T(NEWTON_EPS), fl, window,
        steady, UInt32(64)))
    return nothing
end

function LinearAlgebra.mul!(w::CoupledVector, A::CoupledOperator, z::CoupledVector)
    par, first, t1, h, k = A.it
    nb = cld(A.n, NB)
    Exec.launch!(A.backend, _cs_max_body!, nb, (A.zpart, 0, z.a, 0, A.n))
    Exec.launch!(A.backend, _cs_eps_body!, 1, (A.scal, A.zpart, nb, A.f))
    A.walk(A.rows, _csop(:perturb, (z.a, par, first, A.scal, A.backend)))
    A.walk(A.rows, _csop(:product, (w.a, z.a, A.b.a, par, first, t1, h, k, A.scal, A.backend)))
    return w
end
function LinearAlgebra.mul!(y::CoupledVector, P::CoupledPrecond, v::CoupledVector)
    P.walk(P.rows, _csop(:precond, (y.a, v.a, P.backend)))
    return y
end

# stop a solve whose residual is not finite (it cannot recover)
struct _CsStop end
(::_CsStop)(ws) = (r = ws.stats.residuals; !isempty(r) && !isfinite(@inbounds r[end]))

# One Newton iteration of a coupled group (the per-row iteration's place in `_stage!`): the
# residuals of every row at the iterate, the coupled solve `A δ = G` (Krylov.jl's FGMRES), the
# status, every row's update and check. `a` as the rows' iteration (`(par, first, t1, h, k, last,
# window, backend, γ, word, it, check, hits, gate)`).
function _coupled_iteration!(cs::CoupledKrylov, c, a)
    par, first, t1, h, k, last, window, backend, _, word, it, check, hits, gate = a
    rows, walk, A, scal, ws = cs.rows, cs.walk, cs.A, cs.scal, cs.ws
    K = eltype(scal)
    steady = isinf(h)
    A.it = (par, first, Float64(t1), Float64(h), Int(k))
    walk(rows, _csop(:residual, (par, first, t1, h, k, A.b.a, cs.part, backend, gate)))
    Exec.launch!(backend, _cs_un_body!, 1, (scal, cs.part, cs.nbt))
    if Exec.compiling()                         # (each kernel once: the launches compile)
        x = ws.x
        LinearAlgebra.mul!(x, A, A.b)
        LinearAlgebra.mul!(x, cs.P, A.b)
        Exec.launch!(backend, _cs_dot_body!, 1, (A.b.part, x.a, A.b.a, A.n))
        Exec.launch!(backend, _cs_sum_body!, 1, (A.b.part, 1))
        Krylov.kaxpy!(A.n, one(K), A.b, x)
        Krylov.kaxpby!(A.n, one(K), A.b, one(K), x)
        Krylov.kcopy!(A.n, x, A.b)
        Krylov.kdivcopy!(A.n, x, A.b, one(K))
        Krylov.kfill!(x, zero(K))
    else
        Krylov.fgmres!(ws, A, A.b; N = cs.P, restart = true, rtol = K(cs.rtol), atol = K(cs.rtol * Solvers.FLOOR),
            itmax = cs.budget, history = true, callback = _CsStop())
        st = ws.stats
        rn = st.residuals
        hs = cs.hscal
        r1 = isempty(rn) ? zero(K) : K(@inbounds rn[1])
        re = isempty(rn) ? zero(K) : K(@inbounds rn[end])
        # (1 converged; 5 a breakdown: the operator is singular on the Krylov space; 3 diverged:
        # a residual that is not finite, or an early stop; 0 a budget hit)
        hs[_GM_DONE] = st.solved ? one(K) : !isfinite(re) ? K(3) : st.inconsistent ? K(5) : st.niter < cs.budget ? K(3) : zero(K)
        hs[_GM_ITER] = K(st.niter)
        hs[_GM_RNORM] = re
        hs[_GM_BNORM] = r1
        hs[_GM_TOL] = K(cs.rtol) * max(r1, K(Solvers.FLOOR))
        copyto!(scal, 1, hs, 1, _GM_TOL)
    end
    Exec.launch!(backend, _cs_status_body!, 1, (word, scal, Int32(window), steady, gate))
    walk(rows, _csop(:update, (ws.x.a, par, first, last, check, it, hits, window, steady, word, backend)))
    return nothing
end

# The coupled steady system's modes (F3-12d, invalid input): a coupled QuasiSteady group whose
# rows are numeric (constant coefficients: faces, decay, cross reactions and cross diffusion as
# numbers or parameters), linear, on one grid, with the same face conditions per field, has the
# Laplacian's eigenvectors as its modes, so its Jacobian is block diagonal over them:
# `M(λ) = J_loc + C − λ_x D_x − …` per mode (`λ_a` the eigenvalues of the 1D operator along axis
# `a` with the faces' ghost rule, `D_a` the rows' face coefficients and the cross diffusion). An
# eigenvalue of some `M(λ)` with real part ≥ 0 is a growing or neutral mode: the steady state is
# unstable or not unique, so a steady solve does not apply. Returns nothing (no such mode, or a
# group outside this case: the device decides) or `(λ, mode)`, the eigenvalue of largest real part.
function coupled_modes(s::Program{N}, op::OperatorSpec, keys, p) where {N}
    rows = [r for r in op.rows if r.key in keys]
    R = length(rows)
    R >= 2 || return nothing
    for r in rows
        (r.field || !r.linear || r.iterate || r.switch || !isempty(r.adv) || !isempty(r.bounds) || !isempty(r.unseen)) && return nothing
        any(x -> x[1] in keys && isnan(x[2].value) && !any(cf -> cf[1] == x[1], r.crossfaces), r.cross) && return nothing
        any(x -> x isa NodeValueRule && x.field == fieldid(s, r.key), s.rules) && return nothing
    end
    ids = [fieldid(s, r.key) for r in rows]
    dims = Tuple(Int.(leveldims(s, s.fields[ids[1]].levels[1])))
    all(i -> Tuple(Int.(leveldims(s, s.fields[i].levels[1]))) == dims, ids) || return nothing
    # the face conditions per axis and side, the same for every row (as the 1D ghost rule's factor)
    ghost(id, a, k) = (f = _face_kind(s, id, a, k, p); f[1] === :none ? 0.0 : f[1] === :dirichlet ? 2.0 : f[2] / (f[2] / 2 + f[3]))
    for a in 1:N, k in 1:2
        s.periodic[a] && continue
        g0 = ghost(ids[1], a, k)
        all(i -> isapprox(ghost(i, a, k), g0; rtol = 1e-12, atol = 1e-14), ids) || return nothing
    end
    idx = Dict(r.key => i for (i, r) in enumerate(rows))
    J0 = zeros(R, R)
    Dax = [zeros(R, R) for _ in 1:N]            # per axis, the face coefficients (`w_a` units of 1/h²)
    for (i, r) in enumerate(rows)
        J0[i, i] = _coefsum(r.jloc, p)
        for a in 1:N
            Dax[a][i, i] = _coefsum(r.faces[a], p)
        end
        for (o, c, _) in r.cross
            j = get(idx, o, 0)
            (j == 0 || isnan(c.value)) && continue
            J0[i, j] += _coefsum(Coef[c], p)
        end
        for (o, fs) in r.crossfaces
            j = get(idx, o, 0)
            j == 0 && continue
            for a in 1:N
                Dax[a][i, j] += _coefsum(fs[a], p)
            end
        end
    end
    all(isfinite, J0) && all(D -> all(isfinite, D), Dax) || return nothing
    # the 1D eigenvalues per axis (unit faces: the tridiagonal 2, −1 with the ghost rule's
    # boundary diagonal `1 + g − 1`; a periodic axis `2 − 2cos(2πk/n)`)
    lam = map(1:N) do a
        n = dims[a]
        n == 1 && return [0.0]
        s.periodic[a] && return [2 - 2cos(2π * q / n) for q in 0:(n - 1)]
        d = fill(2.0, n)
        d[1] += ghost(ids[1], a, 1) - 1
        d[n] += ghost(ids[1], a, 2) - 1
        return LinearAlgebra.eigvals(LinearAlgebra.SymTridiagonal(d, fill(-1.0, n - 1)))
    end
    prod(length, lam) > 4_000_000 && return nothing
    best, mode = -Inf + 0im, ntuple(_ -> 0, N)
    M = similar(J0)
    for I in CartesianIndices(Tuple(length.(lam)))
        M .= J0
        for a in 1:N
            M .-= lam[a][I[a]] .* Dax[a]
        end
        ev = LinearAlgebra.eigvals(M)
        e = ev[argmax(real.(ev))]
        real(e) > real(best) && (best = complex(e); mode = Tuple(I))
    end
    return (best, mode)
end
# the refusal of a coupled steady system with a growing or neutral mode, in the user's words
# (`how`: where the eigenvalue comes from)
function _growth_refusal(keys, λ, scale, how)
    fs = join(("`$k`" for k in keys), ", ")
    ev = imag(λ) == 0 ? string(round(real(λ); sigdigits = 3)) :
         string(round(real(λ); sigdigits = 3), (imag(λ) < 0 ? " − " : " + "), round(abs(imag(λ)); sigdigits = 3), "i")
    sgn = real(λ) > scale ? "positive" : "zero"
    return ArgumentError(string("QuasiSteady: the fields ", fs, " read one another, and their coupled steady system has a ",
        real(λ) > scale ? "growing" : "neutral", " mode: an eigenvalue of its Jacobian with ", sgn, " real part (", ev, how,
        "), so its steady state is ", real(λ) > scale ? "unstable" : "not unique", " and no steady solve applies; step the ",
        "fields with `BackwardEuler` (a steady row `0 ~ rhs` written as the rate `D(c) ~ rhs`: a steady row takes only ",
        "`QuasiSteady`), or change the couplings or decays so that every mode decays"))
end
function _coupled_refusal(s::Program, op::OperatorSpec, keys, p)
    m = coupled_modes(s, op, keys, p)
    m === nothing && return nothing
    λ, mode = m
    scale = 1e-10 * max(1.0, maximum(r -> abs(_coefsum(r.jloc, p)), (r for r in op.rows if r.key in keys)))
    real(λ) < -scale && return nothing
    throw(_growth_refusal(keys, λ, scale, all(==(1), mode) ? ", in the slowest spatial mode" : ""))
end

# The coupled steady system's rightmost eigenvalue where `coupled_modes` cannot give it (a
# coefficient that varies by site, a mask, other faces per field): estimated through the same
# operator (r1 M2). Arnoldi with `m` steps on the Cayley transform `C = (σ − J)⁻¹(σ + J)` of the
# Jacobian `J = −A`, `σ > 0` the group's local scale: `C` maps the right half plane outside the
# unit circle and the left half plane inside it, the fast diffusive modes near −1, so its
# dominant eigenvalues are the growing modes. Each step is one product and one coupled solve of
# `(σ + A) x = (σ − A) v` (the group's FGMRES and preconditioner); the start vector is all ones
# (deterministic), the Hessenberg on the host in Float64. Returns the eigenvalue `λ = σ(μ − 1)/(μ + 1)`
# of the Ritz value `μ` of largest modulus when `|μ| > 1 + 1e-6` (a growing mode), else nothing.
# A linear group is checked at the bind and at a parameter write; a nonlinear one (its Jacobian
# depends on the state) right after its first solve after either, or after the steady start (r2 M1). Cost: `m`
# coupled solves, with their waits on a device.
struct CoupledShift{OP, K}
    A::OP
    σ::K
end
Base.size(S::CoupledShift) = size(S.A)
Base.eltype(S::CoupledShift) = eltype(S.A)
function LinearAlgebra.mul!(w::CoupledVector, S::CoupledShift, z::CoupledVector)
    LinearAlgebra.mul!(w, S.A, z)
    Krylov.kaxpy!(length(w), S.σ, z, w)
    return w
end
function coupled_growth(cs::CoupledKrylov, σ::Real, t; m = 12, par = 1)
    rows, walk, A, ws = cs.rows, cs.walk, cs.A, cs.ws
    K = eltype(cs.scal)
    backend = A.backend
    A.it = (par, true, Float64(t), Inf, 0)
    walk(rows, _csop(:residual, (par, true, t, Inf, 0, A.b.a, cs.part, backend, nothing)))
    Exec.launch!(backend, _cs_un_body!, 1, (cs.scal, cs.part, cs.nbt))
    S = CoupledShift(A, K(σ))
    V = [similar(A.b) for _ in 1:(m + 1)]
    y = similar(A.b)
    Krylov.kfill!(V[1], one(K))
    _cs_div!(V[1], K(sqrt(_cs_dot(V[1], V[1]))))
    H = zeros(m + 1, m)
    k = 0
    for j in 1:m
        LinearAlgebra.mul!(y, A, V[j])
        Krylov.kaxpby!(A.n, K(σ), V[j], -one(K), y)           # y = σ v − A v
        Krylov.fgmres!(ws, S, y; N = cs.P, restart = true, rtol = K(1e-6), atol = K(1e-6 * Solvers.FLOOR),
            itmax = cs.budget, history = true, callback = _CsStop())
        w = V[j + 1]
        Krylov.kcopy!(A.n, w, ws.x)
        for i in 1:j
            hij = _cs_dot(V[i], w)
            H[i, j] = hij
            Krylov.kaxpy!(A.n, -hij, V[i], w)
        end
        hn = sqrt(Float64(_cs_dot(w, w)))
        H[j + 1, j] = hn
        k = j
        (isfinite(hn) && hn > 1e-10) || break
        _cs_div!(w, K(hn))
    end
    μs = LinearAlgebra.eigvals(H[1:k, 1:k])
    all(isfinite, μs) || return nothing
    μ = μs[argmax(abs.(μs))]
    abs(μ) > 1 + 1e-6 || return nothing
    return complex(σ * (μ - 1) / (μ + 1))
end
_cs_div!(x::CoupledVector, s) = Krylov.kdivcopy!(length(x), x, x, s)
# the scale of the Cayley shift: the largest local and cross coefficient sum of the rows
function _growth_shift(op::OperatorSpec, keys, p)
    σ = 0.0
    for r in op.rows
        r.key in keys || continue
        v = abs(_coefsum(r.jloc, p)) + sum((abs(_coefsum(Coef[c], p)) for (o, c, _) in r.cross if o in keys && !isnan(c.value)); init = 0.0)
        isfinite(v) && (σ = max(σ, v))
    end
    return max(σ, 1.0)
end
"""
    check_coupled_growth(rt, p)

The coupled steady group of `rt` (a linear `QuasiSteady` group solved together) at parameters
`p`: refused when its Jacobian has a growing mode that `coupled_modes` cannot see (a
coefficient that varies by site), estimated by [`coupled_growth`](@ref). Nothing for any other
runtime. At the bind (both front ends) and at a parameter write of front end B.
"""
check_coupled_growth(rt, p) = nothing
# A nonlinear steady group's growth check (r2 M1, r3): right after the solve that follows its
# bind, a parameter write or the steady start, at the steady state that solve found (current
# slot `par`), when the solve converged. On a device its dot products wait (D-F3-1); no launch
# is rebuilt.
function _after_solve!(cs::CoupledKrylov, par, t, h)
    (isinf(h) && cs.pending > 0 && !Exec.compiling()) || return nothing
    @inbounds cs.hscal[_GM_DONE] == 1 || return nothing            # (pending: the next solve checks)
    λ = coupled_growth(cs, cs.σ, t; par)
    λ === nothing || throw(_growth_refusal(cs.keys, λ, 0.0, ", at the steady state its solve found"))
    cs.pending = 0                          # (cleared only by a converged solve that passes, r3 S1)
    return nothing
end
_after_solve!(::Nothing, par, t, h) = nothing
check_coupled_growth(rt::GroupRuntime{<:FieldStore, <:QuasiSteady}, p) =
    (c = rt.cache; c isa ImplicitCache && c.cs !== nothing ? _check_growth(c.cs, rt.alg, rt.program, c.op, c.keys, p) : nothing)
# the check of a bound coupled solve `cs` (algorithm `alg`, program `s`, operator `op`, fields
# `keys`) at parameters `p`
function _check_growth(cs, alg, s::Program, op::OperatorSpec, keys, p)
    (cs isa CoupledKrylov && alg isa QuasiSteady) || return nothing
    if !cs.linear                           # (at its next steady state: the window's iteration)
        cs.σ = _growth_shift(op, keys, p)
        cs.pending = 1
        return nothing
    end
    coupled_modes(s, op, keys, p) === nothing || return nothing       # (the modes decided already)
    σ = _growth_shift(op, keys, p)
    λ = coupled_growth(cs, σ, 0.0)
    λ === nothing && return nothing
    throw(_growth_refusal(keys, λ, 0.0, ", estimated through the coupled operator: a coefficient varies by site"))
end

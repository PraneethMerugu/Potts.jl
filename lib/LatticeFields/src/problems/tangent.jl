# Derivative parts through the implicit solve (F3-21a): tangent steps. A state with derivative
# parts (ForwardDiff Duals: Dual parameters, a Dual start) is solved in two parts. The primal
# solve runs on a primal copy of the store (`pst`, the value type), with the primal parameters,
# exactly as a primal run (its Newton iterations, solvers, status word and counts). After each
# stage's iterations, the tangent step of the stage: the state `uⁿ⁺¹` keeps the primal values,
# and its derivative parts solve the stage's linearization `(∂G/∂u) u̇ = −(∂G/∂uⁿ u̇ⁿ + ∂G/∂p ṗ)`
# by the defect correction `u̇ ← u̇ + J̃⁻¹ Ġ(u + ε u̇)`: `Ġ` is the derivative part of the
# residual evaluated on the Dual state and parameters (the residual program's kernels run on
# Dual arrays as the explicit path's do: the derivative of every term, the operator's parameter
# derivative `(∂A/∂p) u` and the right side's `∂b/∂p` included), and `J̃⁻¹` is one solve of the
# primal row's converged operator per derivative part (PCG or multigrid in the value type, the
# coupled solve's FGMRES on primal vectors). An exact operator gives the tangent in one
# correction; an inexact one takes the primal group's Newton count. No Dual enters a solver.

# one level of derivative parts with a float value type (nested Duals and Float16 values are
# refused in words)
function _tangent_eltype(E, key, alg)
    V = value_type(E)
    (npartials(V) == 0 && V in (Float32, Float64) && dvalue(zero(E)) isa V) && return V
    throw(ArgumentError(string(_algname(alg), ": the field `", key, "` holds ", _typetext(E), "; the implicit solve ",
        "takes derivative parts of Float32 or Float64 values, one level of them (no nested Duals: take one derivative ",
        "through the solve at a time, or step the field with `ExplicitEuler`)")))
end

_tv_body!(i, dst, src) = (@inbounds dst[i] = dvalue(src[i]); nothing)                   # i ≤ length(dst)
# the stage's iterate `uⁿ⁺¹`: the primal value, the derivative parts of `src` (the guess)
_tseed_body!(i, dst, val, src) = (@inbounds dst[i] = dreplace(src[i], val[i]); nothing)  # i ≤ length(dst)
# derivative part `j` of `res` into the primal right side `out`
_tpart_body!(i, out, res, j) = (@inbounds out[i] = dpartial(res[i], j); nothing)        # i ≤ length(out)
# the correction of derivative part `j` at site `i` (as `_be_update_body!`): δ from the solver's
# solution `x` (a row solved on its own: `v`; a row with no diffusion: `res/s`); a masked site
# takes the part of its value, a clipped site 0
function _tupdate_body!(i, dst, x, smask, v, res, s, mask, mval, mvf, lo, j)
    @inbounds begin
        d = dst[i]
        if mask !== nothing && mask[i] != 0
            q = dpartial(mvf === nothing ? mval : mval * mvf[i], j)
        elseif lo !== nothing && dvalue(d) <= lo
            q = zero(dvalue(d))
        else
            δ = res !== nothing ? res[i] / _at(s, i) : (v !== nothing && smask[i] != 0) ? v[i] : x[i]
            q = dpartial(d, j) + δ
        end
        dst[i] = dsetpartial(d, j, q)
    end
    return nothing
end
# derivative part `j` of a coupled row's residual into the right side `b` (0 at the fixed sites)
function _tcload_body!(i, b, off, res, j, mask, dom)
    @inbounds b[off + i] = _cs_fixed(mask, dom, i) ? zero(eltype(b)) : eltype(b)(dpartial(res[i], j))
    return nothing
end

"""
One row of a [`TangentCache`](@ref): the residual launches on the Dual store (per slot parity,
at the stage's iterate), the row's Dual state slots, its Dual residual, its mask with the Dual
value, its clip, and Crank–Nicolson's and BDF2's Dual right side and history.
"""
mutable struct TangentRow{R, U, A, MK, MV, MF, LO, Q, H}
    res::NTuple{2, R}
    bufs::NTuple{2, U}
    resarr::A
    mask::MK
    mval::MV
    mvf::MF
    lo::LO
    q::Q
    prev::H
end

"""
    TangentCache

The cache of an implicit runtime whose state carries derivative parts (F3-21a): the primal
[`ImplicitCache`](@ref) `pc` on the primal copy `pst` of the store (its parity vector is the
store's), the pairs of Dual and primal arrays synchronized at each window's start, the tangent
rows (in `pc`'s solve order), Crank–Nicolson's Dual right-side launches, the derivative part
count, the rebinder of the Dual launches, and a coupled group's right side.
"""
mutable struct TangentCache{PC, RS, QL, B, BT}
    pc::PC
    pst::FieldStore
    syncs::Vector{Tuple{Any, Any}}
    rows::RS
    qres::QL
    np::Int
    rebind::Any
    backend::B
    bt::BT
    lo::Any
end
status_word(c::TangentCache) = c.pc.word
newton_count(c::TangentCache) = c.pc.newton
reset_cache!(c::TangentCache) = reset_cache!(c.pc)
step_retcode!(::TangentCache, rt) = SciMLBase.ReturnCode.Success
coupled_solve(c::TangentCache) = c.pc.cs !== nothing
_count_set!(c::TangentCache, rt::GroupRuntime) = _count_set!(c.pc, rt)
_primal_cache(c::TangentCache) = c.pc

_primal_params(p::Union{AbstractVector, Tuple}) = map(primal, p)
_primal_params(p) = p
_isdual(a) = npartials(eltype(a)) > 0
# a Coef at Dual parameters (a mask's value: its derivative part)
_coefdual(c::Coef, P) = c.param == 0 ? c.value : c.value * P[c.param]

# the current slots of a launch of the residual program `prog` at the stage's iterate (the
# group's fields in the other slot, `c__n` the stage's start `par`), as the primal rows' later
# Newton iterations read them
function _tcur(prog::Program, s::Program, swaps, all_state, stcur, par)
    cur = ones(Int, length(prog.fields))
    for (i, f) in enumerate(prog.fields)
        if i <= length(s.fields)
            cur[i] = i in swaps ? 3 - par : (all_state ? par : stcur[i])
        elseif endswith(f.key, "__n")
            cur[i] = par
        end
    end
    return cur
end
# … Crank–Nicolson's right side from the substep's start (every field at slot `par`)
function _tqcur(prog::Program, s::Program, swaps, all_state, stcur, par)
    cur = ones(Int, length(prog.fields))
    for (i, f) in enumerate(prog.fields)
        if i <= length(s.fields)
            cur[i] = i in swaps ? par : (all_state ? par : stcur[i])
        elseif endswith(f.key, "__n")
            cur[i] = par
        end
    end
    return cur
end

function _bind_tangent(
        alg::AbstractImplicitFieldAlgorithm, g::FieldGroup, st::FieldStore, p; fields, n, dt, c, backend, options, V,
        shared = nothing, abstol = 1 // 10^6, reltol = 1 // 10^3
    )
    s = group_program(g, alg)
    keys = collect(String, fields)
    E = eltype(st.bufs[fieldid(s, keys[1])][1])
    for k in keys
        _tangent_eltype(eltype(st.bufs[fieldid(s, k)][1]), k, alg)
    end
    np = npartials(E)
    # the primal copy of the store: each array with derivative parts has a primal twin (the
    # parity vector is shared, so the primal cache's swaps are the store's), the others alias
    syncs = Tuple{Any, Any}[]
    if shared === nothing
        twin(a) = _isdual(a) ? (b = _zeros(st.backend, value_type(eltype(a)), length(a)); push!(syncs, (a, b)); b) : a
        pbufs = Vector{Any}[Any[twin(a) for a in b] for b in st.bufs]
        ptabs = Any[twin(a) for a in st.tables]
        pst = FieldStore(st.backend, pbufs, st.cur, ptabs)
        _tsync!(syncs, st.backend)
        pp = _primal_params(p)
        pc = bind_cache(alg, g, pst, pp; fields, n, dt, c = primal(c), backend, options, V, abstol, reltol)
    else
        # (coupled `PottsProblem`: the primal runtime's own cache and store, which solve each
        # stage once; the Dual store shares their slot parity `cur`, and the caller sets the
        # Dual values from the primal ones before each window, so there is nothing to sync)
        pc, pst = shared
        pst.cur === st.cur || throw(ArgumentError("a shared tangent needs the primal store's slot parity"))
    end
    pc isa ImplicitCache || throw(AssertionError("the primal cache of a tangent solve has derivative parts (internal error: please report it)"))
    # the Dual side: the residual launches on the store, at the stage's iterate
    rs = residual_program(g, alg)
    swaps = Set(fieldid(s, k) for k in keys)
    all_state = issubset(Set(fieldid(s, k) for k in g.spec.state), swaps)
    qs = Dict{String, Any}()
    if alg isa Union{CrankNicolson, BDF2}
        for k in keys
            u = st.bufs[fieldid(s, k)][1]
            qs[k] = _zeros(st.backend, eltype(u), length(u))
        end
    end
    qown = Dict{String, Vector{Any}}(k * "__n" => Any[q, q] for (k, q) in qs)
    rst = _alias_store(st, s, rs; own = qown, byid = true, V)
    C = compute_type(alg, V)
    curs = (_tcur(rs, s, swaps, all_state, st.cur, 1), _tcur(rs, s, swaps, all_state, st.cur, 2))
    order = [r.key for r in pc.rows]
    sps = [_implicit_plan(g, rs, (:residual, residual_key(alg), k), _row_kernels(rs, k, g.spec.init), V, backend, options; C)
           for k in order]
    mkres = q -> [ntuple(i -> BoundStep(backend, rs, sps[ri], rst, q; cur = curs[i], c), 2) for ri in eachindex(order)]
    lo = alg.lower_bound === nothing ? nothing : value_type(E)(alg.lower_bound)
    function mkrows(q, res)
        rows = Any[]
        for (ri, key) in enumerate(order)
            id = fieldid(s, key)
            u = st.bufs[id]
            T = eltype(u[1])
            nv = findfirst(x -> x isa NodeValueRule && x.field == id, s.rules)
            mask = nv === nothing ? nothing : array(st, s.masks[s.rules[nv].mask].field, :cur)
            mval = nv === nothing ? zero(T) : convert(T, _coefdual(s.rules[nv].value, q))
            mvf = nv === nothing || s.rules[nv].vfield == 0 ? nothing : array(st, s.rules[nv].vfield, :cur)
            push!(rows, TangentRow(res[ri], (u[1], u[2]), rst.bufs[fieldid(rs, "res:" * key)][1], mask, mval, mvf, lo,
                get(qs, key, nothing), alg isa BDF2 ? _zeros(st.backend, T, length(u[1])) : nothing))
        end
        return Tuple(rows)
    end
    rows = mkrows(p, mkres(p))
    qres, mkq = nothing, q -> nothing
    if alg isa CrankNicolson
        qp = _q_program(g)
        qst = _alias_store(st, s, qp; own = Dict{String, Vector{Any}}("res:" * k => Any[q] for (k, q) in qs), byid = true)
        qids = sort!(unique!(reduce(vcat, (_row_kernels(qp, k, g.spec.init) for k in keys); init = Int[])))
        qplan = _implicit_plan(g, qp, (:residual, :q, keys), qids, V, backend, options; C)
        qcurs = (_tqcur(qp, s, swaps, all_state, st.cur, 1), _tqcur(qp, s, swaps, all_state, st.cur, 2))
        mkq = q -> ntuple(i -> BoundStep(backend, qp, qplan, qst, q; cur = qcurs[i], c), 2)
        qres = mkq(p)
    end
    bt = nothing
    if pc.cs !== nothing
        K = eltype(pc.cs.scal)
        bt = _cvec(_zeros(st.backend, K, pc.cs.A.n), _zeros(st.backend, K, cld(pc.cs.A.n, NB) + 1), st.backend)
    end
    rebind = q -> (mkres(q), mkq(q), mkrows)
    _warn_tangent_newton(pc, alg)
    return TangentCache(pc, pst, syncs, rows, qres, np, rebind, backend, bt, lo)
end
# The tangent step is the derivative of the stage's solution (`G(uⁿ⁺¹) = 0`, the implicit
# function), the derivative of the run when its Newton iteration converges. A group whose stage
# takes one unchecked Newton step on a term that one step does not solve exactly (a local
# nonlinear term or a switch: one step of the linearized method) has a run that differs from
# that solution, and the derivatives differ from the run's by the derivative of that defect:
# warned once, with the route
function _warn_tangent_newton(pc::ImplicitCache, alg)
    (pc.cs === nothing && !pc.check && (pc.iterate || pc.switch || !pc.exact)) || return nothing
    _warn_once(string("implicit-tangent-newton#", join(pc.keys, ","))) || return nothing
    @warn string(_algname(alg), ": field", length(pc.keys) == 1 ? " " : "s ", join(("`$k`" for k in pc.keys), ", "),
        ": the derivative parts are those of each stage's solution (the stage's equation solved), and the run takes ",
        pc.newton, " Newton iteration", pc.newton == 1 ? "" : "s", " per stage with no convergence check, which do",
        pc.newton == 1 ? "es" : "", " not solve a local nonlinear term or a switch exactly, so the derivatives differ from ",
        "those of the run by the derivative of that defect; give `nlsolve = LatticeNewton(; max_iter = k)` (k ≥ 2: the run then iterates until the ",
        "correction meets the tolerance) for derivatives of the run")
    return nothing
end

# the primal twins take the values of the store's arrays (each window's start: the masks, the
# clamps and the other groups wrote the store)
_tsync!(syncs, backend) = (foreach(((a, b),) -> Exec.launch!(backend, _tv_body!, length(b), (b, a)), syncs); nothing)

function _substeps!(c::TangentCache, rt::GroupRuntime, t::Float64, h::Float64, k::Int, n::Integer)
    (n == 0 || h == 0) && return _substeps!(nothing, rt, t, h, k, n)
    _tsync!(c.syncs, c.backend)
    pc = c.pc
    h == pc.h || _set_step!(pc, rt, h)
    w = rt.totals.windows % Int32
    for j in 1:n
        _tsubstep!(rt.alg, c, rt, t + (j - 1) * h, h, k, w, j == 1)
    end
    return nothing
end
_tsubstep!(::BackwardEuler, c, rt, t0, h, k, w, first) = _tstage!(c, rt, t0 + h, 1.0, h, k, w, first)
_tsubstep!(::QuasiSteady, c, rt, t0, h, k, w, first) = _tstage!(c, rt, t0, Inf, h, k, w, first)
function _tsubstep!(::CrankNicolson, c, rt, t0, h, k, w, first)
    pc = c.pc
    if pc.start || (first && pc.jumps)
        _set_q!(pc, rt, nothing)
        _tset_q!(c, rt, false)
        _tstage!(c, rt, t0 + h / 2, 0.5, h, k, w, first)
        _set_q!(pc, rt, nothing)
        _tset_q!(c, rt, false)
        _tstage!(c, rt, t0 + h, 0.5, h, k, w, false)
        pc.start = false
        return nothing
    end
    pc.qres[_parity(rt)]((t0, 0.5 * h, k))
    c.qres[_parity(rt)]((t0, 0.5 * h, k))
    _tstage!(c, rt, t0 + h, 0.5, h, k, w, first)
    return nothing
end
function _tsubstep!(a::BDF2, c, rt, t0, h, k, w, first)
    pc = c.pc
    γ = pc.start ? 1.0 : _gamma(a)
    _set_q!(pc, rt, !pc.start)
    _tset_q!(c, rt, !pc.start)
    _keep_prev!(pc, rt)
    par = _parity(rt)
    for r in c.rows
        Exec.launch!(c.backend, _copy_body!, length(r.prev), (r.prev, r.bufs[par]))
    end
    _tstage!(c, rt, t0 + h, γ, h, k, w, first)
    pc.start = false
    return nothing
end
function _tset_q!(c::TangentCache, rt::GroupRuntime, bdf::Bool)
    par = _parity(rt)
    for r in c.rows
        un = r.bufs[par]
        bdf ? Exec.launch!(c.backend, _bdf2_q_body!, length(r.q), (r.q, un, r.prev)) :
              Exec.launch!(c.backend, _copy_body!, length(r.q), (r.q, un))
    end
    return nothing
end

# one stage: the primal Newton iterations, the tangent step, the swap
function _tstage!(c::TangentCache, rt::GroupRuntime, t1::Float64, γ::Float64, h::Float64, k::Int, w::Int32, first::Bool)
    pc = c.pc
    _stage_iterations!(pc, rt, t1, γ, h, k, w, first)
    Exec.compiling() || _tangent!(c, rt, t1, γ * h, k)
    _swap!(rt.store.cur, rt.swaps)
    _after_solve!(pc.cs, _parity(rt), t1, γ * h)
    return nothing
end

# the tangent step of a stage at slot parity `par` (the start in `par`, the primal iterate in the
# other slot): the iterate's derivative parts from the start's, then the corrections
function _tangent!(c::TangentCache, rt::GroupRuntime, t1::Float64, hγ::Float64, k::Int)
    pc = c.pc
    par = _parity(rt)
    for (pr, tr) in zip(pc.rows, c.rows)
        dst = tr.bufs[3 - par]
        Exec.launch!(c.backend, _tseed_body!, length(dst), (dst, pr.bufs[3 - par], tr.bufs[par]))
    end
    if pc.cs === nothing
        K = pc.exact ? 1 : max(pc.newton, 1)
        for _ in 1:K, i in eachindex(c.rows)
            _trow!(pc.rows[i], c.rows[i], c, par, t1, hγ, k)
        end
    else
        _tcoupled!(c, pc.cs, par, t1, hγ, k)
    end
    return nothing
end
function _trow!(pr::ImplicitRow, tr::TangentRow, c::TangentCache, par, t1, hγ, k)
    backend = c.backend
    tr.res[par]((t1, hγ, k))
    dst = tr.bufs[3 - par]
    n = length(dst)
    for j in 1:(c.np)
        Exec.launch!(backend, _tpart_body!, n, (pr.resarr, tr.resarr, j))
        if pr.solver === nothing && pr.lin === nothing
            Exec.launch!(backend, _tupdate_body!, n, (dst, nothing, nothing, nothing, pr.resarr, pr.s, tr.mask, tr.mval,
                tr.mvf, tr.lo, j))
        else
            x = _row_correction!(pr, backend, 1.0, hγ)
            Exec.launch!(backend, _tupdate_body!, n, (dst, x, pr.smask, pr.v, nothing, nothing, tr.mask, tr.mval, tr.mvf,
                tr.lo, j))
        end
    end
    return nothing
end
# a coupled group's tangent step: the operator at the primal iterate (its residual `b` the base of
# the difference), one FGMRES per derivative part (an exact difference for a linear group, else
# a few corrections with the Dual residual)
function _tcoupled!(c::TangentCache, cs::CoupledKrylov, par, t1, hγ, k)
    backend = c.backend
    A, ws, bt = cs.A, cs.ws, c.bt
    Kt = eltype(cs.scal)
    A.it = (par, false, Float64(t1), Float64(hγ), Int(k))
    cs.walk(cs.rows, _csop(:residual, (par, false, t1, hγ, k, A.b.a, cs.part, backend, nothing)))
    Exec.launch!(backend, _cs_un_body!, 1, (cs.scal, cs.part, cs.nbt))
    for _ in 1:(cs.linear ? 1 : 3)
        foreach(tr -> tr.res[par]((t1, hγ, k)), c.rows)
        for j in 1:(c.np)
            for (cr, tr) in zip(cs.rows, c.rows)
                Exec.launch!(backend, _tcload_body!, cr.n, (bt.a, cr.voff, tr.resarr, j, cr.row.mask, cr.row.dom))
            end
            Krylov.fgmres!(ws, A, bt; N = cs.P, restart = true, rtol = Kt(cs.rtol), atol = Kt(cs.rtol * Solvers.FLOOR),
                itmax = cs.budget, callback = _CsStop())
            for (cr, tr) in zip(cs.rows, c.rows)
                dst = tr.bufs[3 - par]
                δ = view(ws.x.a, (cr.voff + 1):(cr.voff + cr.n))
                Exec.launch!(backend, _tupdate_body!, cr.n, (dst, δ, nothing, nothing, nothing, nothing, tr.mask, tr.mval,
                    tr.mvf, tr.lo, j))
            end
        end
    end
    return nothing
end

# a parameter write: the primal cache's launches at the primal parameters, the Dual launches at `p`
function _tangent_rebind(c::TangentCache, rt::GroupRuntime, p)
    pp = _primal_params(p)
    res, qres, mkrows = c.rebind(p)
    return (_rebind_cache(c.pc, rt, pp), res, qres, mkrows(p, res))
end
function _tangent_install!(c::TangentCache, rt::GroupRuntime, (primal, res, qres, rows))
    _install_cache!(c.pc, rt, c.pst, primal)
    _warn_tangent_newton(c.pc, rt.alg)
    for (r, nr) in zip(c.rows, rows)
        r.res = nr.res
        r.mval = nr.mval
    end
    c.qres = qres
    return nothing
end

"""
    advance_shared!(rt, trt, clock, n, window) -> ReturnCode.T

One window of a coupled `PottsProblem` implicit group `rt` with derivative parts: `trt` is
the group bound to the Dual store with a [`TangentCache`](@ref) on `rt`'s own cache (`bind_group(…;
shared = (rt.cache, rt.store))`, the stores sharing their slot parity). The masks and clamps of
both stores, then each stage's primal solve (once, on `rt`'s store) and its tangent step, then the
slot-1 copies of both. The status is `rt`'s, as [`advance!`](@ref) keeps it.
"""
function advance_shared!(rt::GroupRuntime, trt::GroupRuntime, clock::Tuple{Real, Integer}, n::Integer, window::Real)
    t = Float64(clock[1])
    k = Int(clock[2])
    h = n == 0 ? Float64(window) : Float64(window) / n
    if window > 0
        tot = rt.totals
        tot.windows += 1
        tot.windows == 1 && (tot.t1 = t)
    end
    for r in (rt, trt)
        r.masks === nothing && continue
        r.masks[_parity(r)]((t, h, k))
        _clamp!(r.stepclamps, r.store, r.p)
    end
    tc = trt.cache
    if tc isa TangentCache && (n != 0 && h != 0)
        _substeps!(tc, rt, t, h, k, n)
    else
        # (a window of length 0, the at-init clamp: both stores step as the explicit program does)
        cur = copy(rt.store.cur)
        _substeps!(nothing, trt, t, h, k, n)
        copyto!(rt.store.cur, cur)
        _substeps!(rt.cache, rt, t, h, k, n)
    end
    if rt.ends_in === :slot1
        _slot1!(trt.copies, copy(rt.store.cur), trt.swaps, 1)       # (the Dual store first: the parity is shared)
        _slot1!(rt.copies, rt.store.cur, rt.swaps, 1)
    end
    code = step_retcode!(rt.cache, rt)
    rt.status = _worse(rt.status, code)
    return code
end

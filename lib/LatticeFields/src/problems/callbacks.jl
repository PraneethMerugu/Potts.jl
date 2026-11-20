# Callbacks on the owned path. They run after each window, in
# SciML's order: the continuous callbacks (an event located inside the window), then the
# discrete ones, then the saves due. A callback whose affect changes the state, the parameters
# or the data drops every group's history ([`reset!`](@ref): Crank–Nicolson damps again, BDF2
# starts again) unless the affect calls `derivative_discontinuity!(integ, false)`. On a device
# the conditions read a host copy of the state: one copy per window while a callback is active,
# and one more after an affect when another condition reads it (`sol.stats.syncs`); with no callback the windows read nothing
# back. An affect that changes nothing still drops the history, as in SciML: a callback that
# only observes calls `derivative_discontinuity!(integ, false)` to keep it.
# The callbacks are held in their `CallbackSet` (a tuple of each kind) and walked by recursion,
# so a warm window with callbacks whose conditions do not fire allocates nothing.

# the state a condition reads: the store's buffer on the host, a host copy on a device
_ustate(::FieldIntegrator{P, A, S, RT, T, PV, TB, U}) where {P, A, S, RT, T, PV, TB, U} = U
_savetype(::FieldIntegrator{P, A, S, RT, T}) where {P, A, S, RT, T} = T
# (one concrete type: the walks below dispatch statically; a mixed store's conditions read a copy)
function _cb_u(integ::FieldIntegrator)
    st = integ.store
    host = Exec.ishost(integ.prob.backend)
    host && !mixed_state(st) && !isempty(st.flat) && return st.flat[_parity(integ)]::_ustate(integ)
    host || (integ.syncs += 1)
    return convert(Vector{_savetype(integ)}, _current(integ))::Vector{_savetype(integ)}
end
# the continuous conditions at the window's start (`g0`) and end (`g1`), one entry per scalar
# callback and `len` per vector callback
mutable struct _CondBuf
    g0::Vector{Float64}
    g1::Vector{Float64}
    valid::Bool                         # `g0` holds the conditions at the window's start
end
_ncond(cb::SciMLBase.ContinuousCallback) = 1
_ncond(cb::SciMLBase.VectorContinuousCallback) = cb.len
_ncond(cbs::Tuple) = sum(_ncond, cbs; init = 0)
_conds!(g, k, ::Tuple{}, u, t, integ) = nothing
function _conds!(g, k, cbs::Tuple, u, t, integ)
    cb = first(cbs)
    if cb isa SciMLBase.VectorContinuousCallback
        cb.condition(view(g, (k + 1):(k + cb.len)), u, t, integ)
    else
        g[k + 1] = Float64(cb.condition(u, t, integ))
    end
    _conds!(g, k + _ncond(cb), Base.tail(cbs), u, t, integ)
    return nothing
end

# a callback built with SciML's defaults: its `initialize` and `finalize` (they read no state)
const _DEFAULTS = SciMLBase.DiscreteCallback((u, t, i) -> false, i -> nothing)
# `callback` at `init`: a `CallbackSet` kept on the integrator, each callback's `initialize`
# run at the start time, and the continuous conditions at the start
function _init_callbacks!(integ::FieldIntegrator, callback)
    cs = callback isa SciMLBase.CallbackSet ? callback : SciMLBase.CallbackSet(callback)
    isempty(cs.discrete_callbacks) && isempty(cs.continuous_callbacks) && return nothing
    integ.cbs = cs
    _initialize_callbacks!(integ)
    return nothing
end
_initialize_callbacks!(integ::FieldIntegrator) = _initialize_cbs!(integ, integ.cbs)
function _initialize_cbs!(integ::FieldIntegrator, cs)
    t = _time(integ)
    for cb in (cs.continuous_callbacks..., cs.discrete_callbacks...)
        # (the default `initialize` reads no state: no host copy for it)
        cb.initialize === _DEFAULTS.initialize && continue
        integ.modflag = false
        cb.initialize(cb, _cb_u(integ), t, integ)
        integ.modflag && foreach(reset!, integ.runtimes)
    end
    ccbs = cs.continuous_callbacks
    if isempty(ccbs)
        integ.cprev = nothing
    else
        n = _ncond(ccbs)
        buf = _CondBuf(zeros(n), zeros(n), true)
        _conds!(buf.g0, 0, ccbs, _cb_u(integ), t, integ)
        integ.cprev = buf
    end
    return nothing
end
_finalize_callbacks!(integ::FieldIntegrator) = _finalize_cbs!(integ, integ.cbs)
function _finalize_cbs!(integ::FieldIntegrator, cs)
    t = _time(integ)
    for cb in (cs.continuous_callbacks..., cs.discrete_callbacks...)
        cb.finalize === _DEFAULTS.finalize && continue
        cb.finalize(cb, _cb_u(integ), t, integ)
    end
    return nothing
end

# after each window (behind a barrier; one dispatch on the set's type, then type-stable): the
# continuous callbacks, then the discrete ones
_apply_callbacks!(integ::FieldIntegrator) = _apply_cbs!(integ, integ.cbs)
function _apply_cbs!(integ::FieldIntegrator, cs::SciMLBase.CallbackSet)
    u = _cb_u(integ)
    if !isempty(cs.continuous_callbacks) && _continuous!(integ, cs.continuous_callbacks, u) &&
       !isempty(cs.discrete_callbacks)
        _discrete!(integ, _cb_u(integ), cs.discrete_callbacks)   # (an event moved the state)
    else
        _discrete!(integ, u, cs.discrete_callbacks)
    end
    return nothing
end
_discrete!(integ::FieldIntegrator, u, ::Tuple{}) = nothing
function _discrete!(integ::FieldIntegrator, u, cbs::Tuple)
    _running(integ.retcode) || return nothing
    cb = first(cbs)
    rest = Base.tail(cbs)
    if cb.condition(u, _time(integ), integ)
        _fire!(integ, cb, cb.affect!)
        isempty(rest) || (u = _cb_u(integ))     # (the state the affect left, for the next condition)
    end
    _discrete!(integ, u, rest)
    return nothing
end
# one callback's affect, with its saves before and after (`save_positions`, as SciML: before,
# the saves due and the state as it is; after, the state the affect left)
function _fire!(integ::FieldIntegrator, cb, affect!, args...)
    sp = cb.save_positions
    if sp[1]
        _saves!(integ)
        (isempty(integ.ts) || integ.ts[end] != integ.tnow) && _save!(integ)
    end
    integ.modflag = true
    affect!(integ, args...)
    integ.modflag && foreach(reset!, integ.runtimes)
    sp[2] && _save!(integ)
    return nothing
end

# Continuous callbacks: each condition at the window's end against its value at
# the window's start; a sign change is an event, located by linear interpolation of the
# condition (the solution is linear between the window's ends), so its time is first-order
# accurate. The earliest event of the window fires: the integrator moves to its time with the
# interpolated state, the affect runs (`affect!` on an upcrossing, `affect_neg!` on a
# downcrossing), the groups' history is dropped, and the next window is shortened to land back
# on the window's end (and then on the grid).
# the affect of a crossing: `affect!` up, `affect_neg!` down (a vector callback has one)
_affect(cb, up::Bool) = up || !hasfield(typeof(cb), :affect_neg!) ? cb.affect! : cb.affect_neg!
# the earliest crossing: `(θ, callback, entry, up)`, callback 0 for none
_best(buf, ::Tuple{}, k, j, best) = best
function _best(buf, cbs::Tuple, k, j, best)
    cb = first(cbs)
    for q in 1:_ncond(cb)
        a, b = buf.g0[k + q], buf.g1[k + q]
        (a == 0 || sign(a) == sign(b)) && continue
        up = b > a
        _affect(cb, up) === nothing && continue
        θ = a / (a - b)
        θ < best[1] && (best = (θ, j, q, up))
    end
    return _best(buf, Base.tail(cbs), k + _ncond(cb), j + 1, best)
end
@noinline function _continuous!(integ::FieldIntegrator, ccbs::Tuple, u)
    buf = getfield(integ, :cprev)::_CondBuf
    t1 = _time(integ)
    _conds!(buf.g1, 0, ccbs, u, t1, integ)
    found = buf.valid && getfield(integ, :prevu) !== nothing
    best = found ? _best(buf, ccbs, 0, 1, (Inf, 0, 0, false)) : (Inf, 0, 0, false)
    copyto!(buf.g0, buf.g1)
    buf.valid = true
    best[2] == 0 && return false
    _event!(integ, ccbs, buf, best, t1)
    return true                                  # (an event fired: the state moved)
end
# the earliest crossing `best = (θ, callback, entry, up)` of the window ending at `t1`: the
# integrator at the event's time and state, the affect, the conditions after it
@noinline function _event!(integ::FieldIntegrator, ccbs::Tuple, buf::_CondBuf, best, t1)
    θ, j, q, up = best
    t0, tol = integ.tprev, integ.ttol
    te = t0 + θ * (t1 - t0)
    if te < t1 - tol
        cur = _current(integ)
        ue = integ.prevu .+ θ .* (cur .- integ.prevu)
        _load_state!(integ.store, ue)
        integ.tnow = te
        integ.iter = _floor_count((te - integ.t0) / integ.dt)
        t1 < integ.tend - tol && SciMLBase.add_tstop!(integ, t1)    # (the window's end again, exactly)
    end
    _fire_nth!(integ, ccbs, j, q, up)
    # the conditions after the event, the start of the next window's check
    _conds!(buf.g0, 0, ccbs, _cb_u(integ), _time(integ), integ)
    return nothing
end
_fire_nth!(integ, ::Tuple{}, j, q, up) = nothing
function _fire_nth!(integ, cbs::Tuple, j, q, up)
    j == 1 || return _fire_nth!(integ, Base.tail(cbs), j - 1, q, up)
    cb = first(cbs)
    aff = _affect(cb, up)
    cb isa SciMLBase.VectorContinuousCallback ? _fire!(integ, cb, aff, q) : _fire!(integ, cb, aff)
    return nothing
end

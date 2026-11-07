# Callbacks on the owned path (F4-05, F4-06; F4 design §3.4). They run after each window, in
# SciML's order: the continuous callbacks (an event located inside the window), then the
# discrete ones, then the saves due. A callback whose affect changes the state, the parameters
# or the data drops every group's history ([`reset!`](@ref): Crank–Nicolson damps again, BDF2
# starts again) unless the affect calls `derivative_discontinuity!(integ, false)`. On a device
# the conditions read a host copy of the state: one copy per window while a callback is active
# (`sol.stats.syncs`); with no callback the windows read nothing back.

# the state a condition reads: the store's buffer on the host, a host copy on a device
function _cb_u(integ::FieldIntegrator)
    Exec.ishost(integ.prob.backend) && return integ.u
    integ.syncs += 1
    return _current(integ)
end
_cond(cb::SciMLBase.ContinuousCallback, u, t, integ) = Float64(cb.condition(u, t, integ))
function _cond(cb::SciMLBase.VectorContinuousCallback, u, t, integ)
    out = zeros(cb.len)
    cb.condition(out, u, t, integ)
    return out
end

# `callback` at `init`: a `CallbackSet` kept on the integrator, each callback's `initialize`
# run at the start time, and the continuous conditions at the start
function _init_callbacks!(integ::FieldIntegrator, callback)
    cs = callback isa SciMLBase.CallbackSet ? callback : SciMLBase.CallbackSet(callback)
    isempty(cs.discrete_callbacks) && isempty(cs.continuous_callbacks) && return nothing
    integ.cbs = cs
    _initialize_callbacks!(integ)
    return nothing
end
function _initialize_callbacks!(integ::FieldIntegrator)
    cs = integ.cbs
    t = _time(integ)
    for cb in (cs.continuous_callbacks..., cs.discrete_callbacks...)
        integ.modflag = false
        cb.initialize(cb, _cb_u(integ), t, integ)
        integ.modflag && foreach(reset!, integ.runtimes)
    end
    integ.cprev = isempty(cs.continuous_callbacks) ? nothing :
                  Any[_cond(cb, _cb_u(integ), t, integ) for cb in cs.continuous_callbacks]
    return nothing
end
function _finalize_callbacks!(integ::FieldIntegrator)
    cs = integ.cbs
    t = _time(integ)
    for cb in (cs.continuous_callbacks..., cs.discrete_callbacks...)
        cb.finalize(cb, _cb_u(integ), t, integ)
    end
    return nothing
end

function _apply_callbacks!(integ::FieldIntegrator)
    cs = integ.cbs
    isempty(cs.continuous_callbacks) || _continuous!(integ, cs.continuous_callbacks)
    for cb in cs.discrete_callbacks
        _running(integ.retcode) || break
        cb.condition(_cb_u(integ), _time(integ), integ) || continue
        _fire!(integ, cb, cb.affect!)
    end
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

# Continuous callbacks (F4-06; Q3 (a)): each condition at the window's end against its value at
# the window's start; a sign change is an event, located by linear interpolation of the
# condition (the solution is linear between the window's ends), so its time is first-order
# accurate. The earliest event of the window fires: the integrator moves to its time with the
# interpolated state, the affect runs (`affect!` on an upcrossing, `affect_neg!` on a
# downcrossing), the groups' history is dropped, and the next window is shortened to land back
# on the window's end (and then on the grid).
# the affect of a crossing: `affect!` up, `affect_neg!` down (a vector callback has one)
_affect(cb, up::Bool) = up || !hasfield(typeof(cb), :affect_neg!) ? cb.affect! : cb.affect_neg!
function _continuous!(integ::FieldIntegrator, ccbs)
    t1 = _time(integ)
    g1 = Any[_cond(cb, _cb_u(integ), t1, integ) for cb in ccbs]
    g0 = integ.cprev
    integ.cprev = g1
    (g0 === nothing || integ.prevu === nothing) && return nothing
    best = nothing
    for (j, cb) in enumerate(ccbs)
        for q in eachindex(g1[j])
            a, b = g0[j][q], g1[j][q]
            (a == 0 || sign(a) == sign(b)) && continue
            up = b > a
            _affect(cb, up) === nothing && continue
            θ = a / (a - b)
            (best === nothing || θ < best[1]) && (best = (θ, j, q, up))
        end
    end
    best === nothing && return nothing
    θ, j, q, up = best
    cb = ccbs[j]
    t0, tol = integ.tprev, 1e-9 * integ.dt
    te = t0 + θ * (t1 - t0)
    if te < t1 - tol
        cur = _current(integ)
        ue = integ.prevu .+ θ .* (cur .- integ.prevu)
        _load_state!(integ.store, ue)
        integ.tnow = te
        integ.iter = floor(Int, (te - integ.t0) / integ.dt + 1e-9)
        t1 < integ.tend - tol && SciMLBase.add_tstop!(integ, t1)    # (the window's end again, exactly)
    end
    aff = _affect(cb, up)
    cb isa SciMLBase.VectorContinuousCallback ? _fire!(integ, cb, aff, q) : _fire!(integ, cb, aff)
    # the conditions after the event, the start of the next window's check
    integ.cprev = Any[_cond(c, _cb_u(integ), _time(integ), integ) for c in ccbs]
    return nothing
end

# Callbacks on the owned path (F4-05; F4 design §3.4). They run after each window, in SciML's
# order: the discrete callbacks, then the saves due (the continuous ones are F4-06). A callback whose affect changes the state, the parameters
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

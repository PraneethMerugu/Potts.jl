# Checkpoint and continuation (ROADMAP M2.10, INTERNALS §1.9).
#
# Every random draw is addressed by (key, mcs, entity, stream), so a checkpoint needs no
# RNG state: continuing from MCS t with the same key reproduces an uninterrupted run exactly
# (on the same backend and thread-independent algorithm).

"""
    PottsCheckpoint

Host copy of the state at MCS `t`, with the RNG key tuple, parameters, statistics and the
model fingerprint. Continue with `init(prob, alg; checkpoint = ck)`; the continuation uses
the problem's `p` (so parameters may change at a restart; `ck.p` records the old ones).
"""
struct PottsCheckpoint{S, P}
    state::S
    t::Int
    seed::UInt64
    replica::UInt32
    repeat::UInt32
    p::P
    fingerprint::UInt64
    stats::PottsStats
end

"""Checkpoint the integrator (synchronizes)."""
function checkpoint(integ::PottsIntegrator)
    prob = integ.prob
    return PottsCheckpoint(current_state(integ), integ.t, prob.seed, prob.replica,
        prob.repeat, Adapt.adapt(Array, integ.p), prob.f.fingerprint, deepcopy(integ.stats))
end

"""Write a checkpoint to `path` (Julia `Serialization`; same package versions to read)."""
save_checkpoint(path::AbstractString, ck::PottsCheckpoint) =
    open(io -> Serialization.serialize(io, ck), path, "w")
"""Read a checkpoint written by `save_checkpoint`."""
load_checkpoint(path::AbstractString) = open(Serialization.deserialize, path)

function _from_checkpoint(prob::CPMProblem, ck::PottsCheckpoint)
    ck.fingerprint == prob.f.fingerprint || throw(ArgumentError(
        "checkpoint fingerprint $(ck.fingerprint) does not match the model's $(prob.f.fingerprint)"))
    prob.tspan[1] <= ck.t <= prob.tspan[2] ||
        throw(ArgumentError("checkpoint MCS $(ck.t) is outside tspan $(prob.tspan)"))
    return remake(prob; u0 = ck.state, tspan = (ck.t, prob.tspan[2]), seed = ck.seed,
        replica = ck.replica, repeat = ck.repeat)
end

_copy_state!(dst::AbstractArray, src) = copyto!(dst, src)
_copy_state!(dst::NamedTuple, src) = foreach(k -> _copy_state!(getfield(dst, k), getfield(src, k)), keys(dst))
function _copy_state!(dst::CPMState, src::CPMState)
    foreach(f -> _copy_state!(getfield(dst, f), getfield(src, f)), fieldnames(CPMState))
    return dst
end

"""
    reinit!(integ, u0 = integ.prob.u0; t0 = integ.prob.tspan[1])

Reset the integrator in place to state `u0` at MCS `t0` (arrays are reused; no
allocation of device storage), clearing saved values, statistics and the return code.
"""
function SciMLBase.reinit!(integ::PottsIntegrator, u0 = integ.prob.u0;
        t0::Integer = integ.prob.tspan[1])
    KernelAbstractions.synchronize(integ.backend)
    u0 isa CPMState || (u0 = remake_state(integ.f.sys, integ.prob, u0))     # symbolic maps
    _same_shape(integ.state, u0) || throw(ArgumentError(
        "reinit!: the new state's arrays differ in shape from the integrator's (cell capacity " *
        "$(length(integ.state.cell.kind)), got $(length(u0.cell.kind))); use `remake` and `init`"))
    _reset_mobility!(integ.ctx.mobility, mobility(remake_frozen(integ.f.sys, integ.prob, u0), integ.prob.lattice))
    _copy_state!(integ.state, u0)
    integ.t = t0
    integ.retcode = SciMLBase.ReturnCode.Default
    empty!(integ.saved_t); empty!(integ.saved_u)
    _restore_stats!(integ.stats, PottsStats())
    integ.cache === nothing || (fill!(integ.cache.status, 0); foreach(c -> fill!(c, 0), (integ.cache.claims..., integ.cache.wclaims...)))
    integ.stats.launches += _run_phases(integ.f.phases.at_init, integ.state, integ.p, integ.ctx,
        integ.key, integ.t, integ.backend)
    for cb in integ.callbacks
        cb.initialize(cb, integ.state, integ.t, integ)
    end
    integ.save_start && _save!(integ)
    return integ
end

_same_shape(a::AbstractArray, b) = b isa AbstractArray && size(a) == size(b)
_same_shape(a::NamedTuple, b) = b isa NamedTuple && keys(a) == keys(b) && all(k -> _same_shape(a[k], b[k]), keys(a))
_same_shape(a::CPMState, b) = false
_same_shape(a::CPMState, b::CPMState) = all(f -> _same_shape(getfield(a, f), getfield(b, f)), fieldnames(CPMState))

# The mobility of a reinitialized state: storage is reused, so the frozen sites may move but
# their number must stay (it sizes the proposal draw).
_reset_mobility!(::AllMobile, ::AllMobile) = nothing
function _reset_mobility!(m::MaskMobility, new::MaskMobility)
    m.n == new.n || throw(ArgumentError("reinit!: the number of frozen sites changed; use `remake` and `init`"))
    copyto!(m.frozen, new.frozen); copyto!(m.sites, new.sites)
    return nothing
end
_reset_mobility!(m, new) = throw(ArgumentError("reinit!: the frozen sites changed; use `remake` and `init`"))

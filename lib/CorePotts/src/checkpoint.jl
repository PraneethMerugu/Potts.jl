# Checkpoint and continuation (ROADMAP M2.10, INTERNALS §1.9).
#
# Every random draw is addressed by (key, mcs, entity, stream), so a checkpoint needs no
# RNG state: continuing from MCS t with the same key reproduces an uninterrupted run exactly
# (on the same backend and thread-independent algorithm).

"""
    PottsCheckpoint

Host copy of the state at MCS `t`, with the RNG key tuple, parameters, statistics (with
`accepted_ΔH`, exact here) and the model fingerprint. Continue with `init(prob, alg; checkpoint = ck)`; the continuation uses
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
    # `current_state` is the host read point that makes `stats` exact (D-089): it runs
    # before the statistics are copied
    return PottsCheckpoint(current_state(integ), integ.t, prob.seed, prob.replica,
        prob.repeat, _adapt_host(integ.stats, integ.p), prob.f.fingerprint, deepcopy(integ.stats))
end

"""Write a checkpoint to `path` (Julia `Serialization`; same package versions to read)."""
save_checkpoint(path::AbstractString, ck::PottsCheckpoint) =
    open(io -> Serialization.serialize(io, ck), path, "w")
"""Read a checkpoint written by `save_checkpoint`."""
load_checkpoint(path::AbstractString) = open(Serialization.deserialize, path)

function _from_checkpoint(prob::PottsProblem, ck::PottsCheckpoint)
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
    _sync!(integ.stats, integ.backend)            # reset below with the statistics
    # symbolic maps; a state is laid out for the model's functions (e.g. Potts' ODE scratch)
    u0 = remake_state(integ.f.sys, integ.prob, u0)
    _same_shape(integ.state, u0) || throw(ArgumentError(
        "reinit!: the new state's arrays differ in shape from the integrator's (cell capacity " *
        "$(length(integ.state.cell.kind)), got $(length(u0.cell.kind))$(_key_difference(integ.state, u0))); " *
        "use `remake` and `init`"))
    _fold_lifecycle!(integ; report = false)     # device lifecycle counts of the old run: dropped
    _copy_state!(integ.state, u0)
    refresh_frozen!(integ)          # the frozen mask of the new state (static masks: nothing to do)
    integ.t = t0
    integ.retcode = SciMLBase.ReturnCode.Default
    empty!(integ.saved_t); empty!(integ.saved_u)
    _restore_stats!(integ.stats, _initial_stats(integ.f))      # `accepted_ΔH`: 0.0 when tracked
    _reset_cache!(integ.cache, integ)
    integ.stats.launches += _run_phases(integ.f.phases.at_init, integ.state, integ.p, integ.ctx,
        integ.key, integ.t, integ.backend, integ.stats)
    for cb in integ.callbacks
        cb.initialize(cb, integ.state, integ.t, integ)
    end
    integ.save_start && _save!(integ)
    return integ
end

# the algorithm's scratch for the new run: nothing (SequentialCPM), the checkerboard's status,
# claims, track and connectivity counters, or the boundary set of the new state (rebuilt)
_reset_cache!(::Nothing, integ) = nothing
function _reset_cache!(cache::CheckerboardCache, integ)
    fill!(cache.status, 0)
    foreach(c -> c === nothing || fill!(c, 0), (cache.claims..., cache.wclaims...))
    cache.track === nothing || fill!(cache.track.acc, 0)
    # the connectivity lists and the deferred-refusal counter (a refusal of the old run is not
    # the new run's)
    cache.conn === nothing || foreach(c -> fill!(c, 0), (cache.conn.gl.gcount, cache.conn.gl.scount, cache.conn.gl.deferred))
    return nothing
end
_reset_cache!(B::BoundaryCache, integ) =
    (_rebuild_boundary!(B, integ.state.σ, integ.ctx.mobility, integ.ctx.lattice, integ.ctx.proposal.offsets); nothing)

function _key_difference(a::CPMState, b::CPMState)
    parts = String[]
    for f in (:cell, :site, :model)
        ka, kb = keys(getfield(a, f)), keys(getfield(b, f))
        missing_ = setdiff(ka, kb); extra = setdiff(kb, ka)
        isempty(missing_) || push!(parts, "missing $f arrays $(join(missing_, ", "))")
        isempty(extra) || push!(parts, "extra $f arrays $(join(extra, ", "))")
    end
    return isempty(parts) ? "" : "; " * join(parts, "; ")
end

_same_shape(a::AbstractArray, b) = b isa AbstractArray && size(a) == size(b)
_same_shape(a::NamedTuple, b) = b isa NamedTuple && keys(a) == keys(b) && all(k -> _same_shape(a[k], b[k]), keys(a))
_same_shape(a::CPMState, b) = false
_same_shape(a::CPMState, b::CPMState) = all(f -> _same_shape(getfield(a, f), getfield(b, f)), fieldnames(CPMState))

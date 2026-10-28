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

`format` is the checkpoint format ([`CHECKPOINT_FORMAT`](@ref) when written). A checkpoint
of another format is refused at `init`.
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
    format::Int
end
PottsCheckpoint(state, t, seed, replica, repeat, p, fingerprint, stats) =
    PottsCheckpoint(state, t, seed, replica, repeat, p, fingerprint, stats, CHECKPOINT_FORMAT)

"""
    CHECKPOINT_FORMAT

The checkpoint format of this version. Format 2 starts at the field-compiler cutover (C8):
the fields of a state are stepped by the field compiler, so a checkpoint of format 1 (the
`FieldStep` path, without a `format` field) is not continued.
"""
const CHECKPOINT_FORMAT = 2

"""Checkpoint the integrator (synchronizes)."""
function checkpoint(integ::PottsIntegrator)
    prob = integ.prob
    # `current_state` is the host read point that makes `stats` exact (D-089): it runs
    # before the statistics are copied
    return PottsCheckpoint(current_state(integ), integ.t, prob.seed, prob.replica,
        prob.repeat, _adapt_host(_stats(integ), integ.p), prob.f.fingerprint, deepcopy(_stats(integ)))
end

"""Write a checkpoint to `path` (Julia `Serialization`; same package versions to read)."""
save_checkpoint(path::AbstractString, ck::PottsCheckpoint) =
    open(io -> Serialization.serialize(io, ck), path, "w")
"""Read a checkpoint written by `save_checkpoint`."""
function load_checkpoint(path::AbstractString)
    # opening the file is outside the `try`: a missing file is a `SystemError`, not a format error
    ck = open(path) do io
        try
            Serialization.deserialize(io)
        catch e
            throw(ArgumentError("$path is not a checkpoint of format $CHECKPOINT_FORMAT: a checkpoint written before " *
                "the field-compiler cutover (format 1) or by other package versions cannot be read ($(sprint(showerror, e)))"))
        end
    end
    ck isa PottsCheckpoint || throw(ArgumentError("$path holds a $(typeof(ck)), not a checkpoint of format $CHECKPOINT_FORMAT"))
    return ck
end

function _from_checkpoint(prob::PottsProblem, ck::PottsCheckpoint)
    ck.format == CHECKPOINT_FORMAT || throw(ArgumentError(
        "checkpoint format $(ck.format) is not this version's format $CHECKPOINT_FORMAT: a checkpoint written " *
        "before the field-compiler cutover cannot be continued; finish that run on the version that wrote it"))
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
    _sync!(_stats(integ), integ.backend)            # reset below with the statistics
    # symbolic maps; a state is laid out for the model's functions (e.g. Potts' ODE scratch)
    u0 = remake_state(integ.f.sys, integ.prob, u0)
    _same_shape(integ.state, u0) || throw(ArgumentError(
        "reinit!: the new state's arrays differ in shape from the integrator's ($(_shape_difference(integ.state, u0))); " *
        "use `remake` and `init`"))
    _fold_lifecycle!(integ; report = false)     # device lifecycle counts of the old run: dropped
    _copy_state!(integ.state, u0)
    refresh_frozen!(integ)          # the frozen mask of the new state (static masks: nothing to do)
    integ.t = t0
    integ.retcode = SciMLBase.ReturnCode.Default
    empty!(integ.saved_t); empty!(integ.saved_u)
    _restore_stats!(_stats(integ), _initial_stats(integ.f))      # `accepted_ΔH`: 0.0 when tracked
    _reset_cache!(integ.cache, integ)
    _clear_field_status!(integ.ctx)          # a new run: the field groups' failures and counters go
    _stats(integ).launches += _run_phases(integ.f.phases.at_init, integ.state, integ.p, integ.ctx,
        integ.key, integ.t, integ.backend, _stats(integ))
    _start_failed!(integ)
    _each(cb -> cb.initialize(cb, integ.state, integ.t, integ), integ.callbacks)
    integ.save_start && _save!(integ)
    return integ
end

# every field group's status word, totals and code, and its algorithm's history (`reset!`: the
# new state is a start; cold: a dynamic loop over the context)
function _clear_field_status!(ctx)
    for h in values(ctx)
        h isa FieldHandle || continue
        Problems.clear_status!(_runtime(h))
        Problems.reset!(_runtime(h))
    end
    return nothing
end

# the algorithm's scratch for the new run: nothing (SequentialCPM), the checkerboard's status,
# track, counts and serial list, or the boundary set of the new state (rebuilt)
_reset_cache!(::Nothing, integ) = nothing
function _reset_cache!(cache::CheckerboardCache, integ)
    fill!(cache.status, 0)
    cache.track === nothing || fill!(cache.track.acc, 0)
    fill!(cache.cnt, Int32(0))
    cache.serial === nothing || (fill!(cache.serial.count, 0); fill!(cache.serial.deferred, 0))
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

# how two states' arrays differ, in words (`reinit!`'s refusal): the cell capacity when it
# differs; else arrays missing or extra (their names), arrays in another order (the same names),
# or the first array of another size
function _shape_difference(a::CPMState, b::CPMState)
    na, nb = length(a.cell.kind), length(b.cell.kind)
    na == nb || return string("cell capacity ", na, ", got ", nb, _key_difference(a, b))
    k = _key_difference(a, b)
    isempty(k) || return k[3:end]
    for f in (:cell, :site, :model)
        ka, kb = keys(getfield(a, f)), keys(getfield(b, f))
        ka == kb || return string("the ", f, " arrays are in another order: ", join(ka, ", "), "; got ", join(kb, ", "))
    end
    for f in (:cell, :site, :model), q in keys(getfield(a, f))
        x, y = getfield(a, f)[q], getfield(b, f)[q]
        _same_shape(x, y) || return string("the ", f, " array `", q, "` has size ", _sizetext(x), ", got ", _sizetext(y))
    end
    return string("cell capacity ", na, ", got ", nb)
end
_sizetext(x::AbstractArray) = string(size(x))
_sizetext(x::NamedTuple) = string("(", join(keys(x), ", "), ")")
_sizetext(x) = string(typeof(x))
_same_shape(a::AbstractArray, b) = b isa AbstractArray && size(a) == size(b)
_same_shape(a::NamedTuple, b) = b isa NamedTuple && keys(a) == keys(b) && all(k -> _same_shape(a[k], b[k]), keys(a))
_same_shape(a::CPMState, b) = false
_same_shape(a::CPMState, b::CPMState) = all(f -> _same_shape(getfield(a, f), getfield(b, f)), fieldnames(CPMState))

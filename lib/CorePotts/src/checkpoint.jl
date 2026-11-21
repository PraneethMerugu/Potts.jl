# Checkpoint and continuation (INTERNALS §1.9).
#
# Every random draw is addressed by (key, mcs, entity, stream), so a checkpoint needs no
# RNG state: continuing from MCS t with the same key reproduces an uninterrupted run exactly
# (on the same backend and thread-independent algorithm).

"""
    PottsCheckpoint(state, t, seed, replica, repeat, p, fingerprint, stats)

A host copy of a run's state at MCS `t`, with everything needed to continue the run.

A checkpoint holds no RNG state: every random draw is addressed by the key tuple, the
MCS, the entity and the stream, so continuing from MCS `t` with the same key gives the
same run as one without the break, on the same backend and with a thread-independent
algorithm. Make one with [`checkpoint`](@ref) and continue with
`init(prob, alg; checkpoint = ck)`. `init` refuses a checkpoint of another format or
fingerprint, or one whose MCS is outside the problem's `tspan`.

# Fields
- `state`: the host copy of the state.
- `t::Int`: the MCS of the state.
- `seed::UInt64`, `replica::UInt32`, `repeat::UInt32`: the RNG key tuple.
- `p`: the parameters of the run. The continuation uses the problem's `p`, so the
  parameters can change at a restart; `p` records the old ones.
- `fingerprint::UInt64`: the model fingerprint.
- `stats::PottsStats`: the statistics, with an exact `accepted_energy_change`.
- `format::Int`: the checkpoint format, [`CHECKPOINT_FORMAT`](@ref) when written.

See also [`save_checkpoint`](@ref), [`load_checkpoint`](@ref).
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
function PottsCheckpoint(state, t, seed, replica, repeat, p, fingerprint, stats)
    return PottsCheckpoint(
        state, t, seed, replica, repeat, p, fingerprint, stats, CHECKPOINT_FORMAT
    )
end

"""
    CHECKPOINT_FORMAT

The checkpoint format that this version writes and reads (`2`).

A checkpoint of format 1 (it has no `format` field) cannot be continued.

See also [`PottsCheckpoint`](@ref).
"""
const CHECKPOINT_FORMAT = 2

"""
    checkpoint(integ) -> PottsCheckpoint

Take a checkpoint of the integrator's current state.

The call synchronizes with the device: it reads the current state to the host first, so
the copied statistics are exact. A run with derivative parts (Dual parameters) has no
checkpoint and throws an `ArgumentError`.

# Arguments
- `integ::PottsIntegrator`: the integrator.

# Returns
- `PottsCheckpoint`: a host copy of the state, the key tuple, the parameters, the
  statistics and the model fingerprint.

# Examples
```julia
integ = init(prob, alg)
step!(integ, 100, true)
ck = checkpoint(integ)
integ2 = init(prob, alg; checkpoint = ck)   # continues from the same MCS
```

See also [`save_checkpoint`](@ref), [`PottsCheckpoint`](@ref).
"""
function checkpoint(integ::PottsIntegrator)
    prob = integ.prob
    prob.tangent === nothing || throw(
        ArgumentError(
            "a run with derivative parts (Dual parameters) has no " *
                "checkpoint: its derivative parts are not part of the state; run it from " *
                "the start, or checkpoint the primal run (`remake` with plain values)"
        )
    )
    # `current_state` is the host read point that makes `stats` exact (D-089): it runs
    # before the statistics are copied
    return PottsCheckpoint(
        current_state(integ), integ.t, prob.seed, prob.replica,
        prob.repeat, adapt_host(_stats(integ), integ.p), prob.f.fingerprint,
        deepcopy(_stats(integ))
    )
end

"""
    save_checkpoint(path, ck)

Write the checkpoint `ck` to the file `path` with Julia's `Serialization`.

Reading the file needs the same package versions.

# Arguments
- `path::AbstractString`: the file to write.
- `ck::PottsCheckpoint`: the checkpoint.

# Returns
- The return value of the `open` call; call it for its effect on the file.

See also [`load_checkpoint`](@ref), [`checkpoint`](@ref).
"""
function save_checkpoint(path::AbstractString, ck::PottsCheckpoint)
    return open(io -> Serialization.serialize(io, ck), path, "w")
end
"""
    load_checkpoint(path) -> PottsCheckpoint

Read a checkpoint that [`save_checkpoint`](@ref) wrote.

A missing file throws a `SystemError`. A file that does not deserialize, or that holds
an object other than a `PottsCheckpoint`, throws an `ArgumentError`.

# Arguments
- `path::AbstractString`: the file to read.

# Returns
- `PottsCheckpoint`: the checkpoint. Its format is checked when it is given to `init`.

See also [`checkpoint`](@ref).
"""
function load_checkpoint(path::AbstractString)
    # opening the file is outside the `try`: a missing file is a `SystemError`, not a format
    # error
    ck = open(path) do io
        try
            Serialization.deserialize(io)
        catch e
            isfatal(e) && rethrow()
            throw(
                ArgumentError(
                    "$path is not a checkpoint of format $CHECKPOINT_FORMAT: a " *
                        "checkpoint written before the field-compiler cutover (format 1) \
                            or by other package versions cannot be read \
                            ($(sprint(showerror, e)))"
                )
            )
        end
    end
    ck isa PottsCheckpoint ||
        throw(ArgumentError("$path holds a $(typeof(ck)), not a checkpoint of \
            format $CHECKPOINT_FORMAT"))
    return ck
end

function _from_checkpoint(prob::PottsProblem, ck::PottsCheckpoint)
    ck.format == CHECKPOINT_FORMAT || throw(
        ArgumentError(
            "checkpoint format $(ck.format) is not this version's " *
                "format $CHECKPOINT_FORMAT: a checkpoint written before the \
                    field-compiler cutover cannot be continued; finish that run \
                    on the version that wrote it"
        )
    )
    ck.fingerprint == prob.f.fingerprint || throw(
        ArgumentError(
            "checkpoint fingerprint $(ck.fingerprint) does not match the \
                model's $(prob.f.fingerprint)"
        )
    )
    prob.tspan[1] <= ck.t <= prob.tspan[2] ||
        throw(ArgumentError("checkpoint MCS $(ck.t) is outside tspan $(prob.tspan)"))
    return remake(
        prob; u0 = ck.state, tspan = (ck.t, prob.tspan[2]), seed = ck.seed,
        replica = ck.replica, repeat = ck.repeat
    )
end

_copy_state!(dst::AbstractArray, src) = copyto!(dst, src)
function _copy_state!(dst::NamedTuple, src)
    return foreach(k -> _copy_state!(getfield(dst, k), getfield(src, k)), keys(dst))
end
function _copy_state!(dst::CPMState, src::CPMState)
    foreach(f -> _copy_state!(getfield(dst, f), getfield(src, f)), fieldnames(CPMState))
    return dst
end

"""
    reinit!(integ, u0 = integ.prob.u0; t0 = integ.prob.tspan[1], tf = integ.prob.tspan[2],
            erase_sol = true, saveat = integ.opts.saveat0, tstops = integ.opts.tstops0,
            reinit_callbacks = true, reinit_retcode = true)

Reset the integrator in place to state `u0` at MCS `t0`, to run to MCS `tf` (`t0 ≤ tf`;
arrays are reused, no device storage is allocated), clearing the statistics and the MCS
count `iter`. By default the save times and stops are those given to `init`; `saveat` and
`tstops` replace them for the new run (a number `saveat` is every that many MCS from `t0`).
Only the stops `t0 < t ≤ tf` are kept. `erase_sol = false` keeps the saved states (the new
run's saves follow them); `reinit_callbacks = false` does not run the callbacks'
`initialize` again; `reinit_retcode = false` keeps the return code.
"""
function SciMLBase.reinit!(
        integ::PottsIntegrator, u0 = integ.prob.u0;
        t0::Integer = integ.prob.tspan[1], tf::Integer = integ.prob.tspan[2],
        erase_sol::Bool = true,
        saveat = integ.opts.saveat0, tstops = integ.opts.tstops0,
        reinit_callbacks::Bool = true,
        reinit_retcode::Bool = true
    )
    t0 <= tf || throw(ArgumentError("reinit!: t0 = $t0 is after tf = $tf"))
    saves = _saveat_list(saveat, t0, tf)            # (checked before the state changes)
    stops = _in_span(_tstops_list(tstops), t0, tf)
    sync!(_stats(integ), integ.backend)            # reset below with the statistics
    # (the problem's own state: its derivative parts)
    fresh = u0 === integ.prob.u0
    # symbolic maps; a state is laid out for the model's functions (e.g. Potts' ODE scratch)
    u0 = remake_state(integ.f.sys, integ.prob, u0)
    _same_shape(integ.state, u0) || throw(
        ArgumentError(
            "reinit!: the new state's arrays differ in shape from the integrator's " *
                "($(_shape_difference(integ.state, u0))); use `remake` and `init`"
        )
    )
    # device lifecycle counts of the old run: dropped
    _fold_lifecycle!(integ; report = false)
    _copy_state!(integ.state, u0)
    # the frozen mask of the new state (static masks: nothing to do)
    refresh_frozen!(integ)
    integ.t = t0
    integ.tstop = tf
    integ.iter = 0
    integ.finished = false
    reinit_retcode && (integ.retcode = SciMLBase.ReturnCode.Default)
    append!(empty!(integ.opts.saveat), saves)
    append!(empty!(integ.opts.tstops), stops)
    erase_sol && (empty!(integ.saved_t); empty!(integ.saved_u))
    # `accepted_energy_change`: 0.0 when tracked
    _restore_stats!(_stats(integ), _initial_stats(integ.f))
    _reset_cache!(integ.cache, integ)
    # a new run: the field groups' failures and counters go
    _clear_field_status!(integ.ctx)
    # (and the derivative parts)
    tangent_reinit!(integ.ctx, fresh ? integ.prob.tangent : nothing)
    _stats(integ).launches += run_phases(
        integ.f.phases.at_init, integ.state, integ.p, integ.ctx,
        integ.key, integ.t, integ.backend, _stats(integ)
    )
    _start_failed!(integ)
    reinit_callbacks &&
        _each(cb -> cb.initialize(cb, integ.state, integ.t, integ), integ.callbacks)
    integ.opts.save_start && (isempty(integ.saved_t) || last(integ.saved_t) != integ.t) &&
        _save!(integ)
    return integ
end

# every field group's status word, totals and code, and its algorithm's history (`reset!`:
# the new state is a start; cold: a dynamic loop over the context)
function _clear_field_status!(ctx)
    for h in values(ctx)
        h isa FieldHandle || continue
        Problems.clear_status!(_runtime(h))
        Problems.reset!(_runtime(h))
    end
    return nothing
end

# the algorithm's scratch for the new run: nothing (SequentialCPM), the checkerboard's
# status, track, counts and serial list, or the boundary set of the new state (rebuilt)
_reset_cache!(::Nothing, integ) = nothing
function _reset_cache!(cache::CheckerboardCache, integ)
    fill!(cache.status, 0)
    cache.track === nothing || fill!(cache.track.acc, 0)
    fill!(cache.cnt, Int32(0))
    cache.serial === nothing ||
        (fill!(cache.serial.count, 0); fill!(cache.serial.deferred, 0))
    return nothing
end
function _reset_cache!(B::BoundaryCache, integ)
    _rebuild_boundary!(
        B, integ.state.ownership, integ.ctx.mobility,
        integ.ctx.lattice, integ.ctx.proposal.offsets
    )
    return nothing
end

function _key_difference(a::CPMState, b::CPMState)
    parts = String[]
    for f in (:cell, :site, :model)
        ka, kb = keys(getfield(a, f)), keys(getfield(b, f))
        missing_ = setdiff(ka, kb)
        extra = setdiff(kb, ka)
        isempty(missing_) || push!(parts, "missing $f arrays $(join(missing_, ", "))")
        isempty(extra) || push!(parts, "extra $f arrays $(join(extra, ", "))")
    end
    return isempty(parts) ? "" : "; " * join(parts, "; ")
end

# how two states' arrays differ, in words (`reinit!`'s refusal): the cell capacity when it
# differs; else arrays missing or extra (their names), arrays in another order (the same
# names), or the first array of another size
function _shape_difference(a::CPMState, b::CPMState)
    na, nb = length(a.cell.kind), length(b.cell.kind)
    na == nb || return string("cell capacity ", na, ", got ", nb, _key_difference(a, b))
    k = _key_difference(a, b)
    isempty(k) || return k[3:end]
    for f in (:cell, :site, :model)
        ka, kb = keys(getfield(a, f)), keys(getfield(b, f))
        ka == kb || return string(
            "the ", f, " arrays are in another order: ",
            join(ka, ", "), "; got ", join(kb, ", ")
        )
    end
    for f in (:cell, :site, :model), q in keys(getfield(a, f))
        x, y = getfield(a, f)[q], getfield(b, f)[q]
        _same_shape(x, y) || return string(
            "the ", f, " array `", q, "` has size ",
            _sizetext(x), ", got ", _sizetext(y)
        )
    end
    return string("cell capacity ", na, ", got ", nb)
end
_sizetext(x::AbstractArray) = string(size(x))
_sizetext(x::NamedTuple) = string("(", join(keys(x), ", "), ")")
_sizetext(x) = string(typeof(x))
_same_shape(a::AbstractArray, b) = b isa AbstractArray && size(a) == size(b)
function _same_shape(a::NamedTuple, b)
    return b isa NamedTuple && keys(a) == keys(b) &&
        all(k -> _same_shape(a[k], b[k]), keys(a))
end
_same_shape(a::CPMState, b) = false
function _same_shape(a::CPMState, b::CPMState)
    return all(f -> _same_shape(getfield(a, f), getfield(b, f)), fieldnames(CPMState))
end

abstract type PottsLookupError <: Exception end

struct PottsUnknownIdentityError <: PottsLookupError
    identity::Symbol
end

struct PottsKnownUnsavedError <: PottsLookupError
    identity::Symbol
    mcs::Int
end

struct PottsUnsavedTimeError <: PottsLookupError
    mcs::Int
end

Base.showerror(io::IO, error::PottsUnknownIdentityError) =
    print(io, "unknown compiled symbolic identity `", error.identity, "`")
Base.showerror(io::IO, error::PottsKnownUnsavedError) =
    print(
        io,
        "compiled observation `",
        error.identity,
        "` was not saved at MCS ",
        error.mcs,
    )
Base.showerror(io::IO, error::PottsUnsavedTimeError) =
    print(io, "MCS ", error.mcs, " is within the trajectory but was not saved")

struct PottsSavedState{O, K, G, V, S, R, Q, D, N}
    mcs::Int
    ownership::O
    cell_kinds::K
    cell_generations::G
    volumes::V
    states::S
    topology::R
    observations::Q
    declared_observations::D
    native::N
end

_copy_saved_value(value::AbstractArray) = copy(value)
_copy_saved_value(value::Tuple) = map(_copy_saved_value, value)
function _copy_saved_value(value::NamedTuple)
    mapped = map(_copy_saved_value, values(value))
    return NamedTuple{keys(value)}(mapped)
end
_copy_saved_value(value) = value

function _descriptor_saved_value(descriptor_state, entry)
    values = CorePotts.CompilerSPI.state_block(descriptor_state, entry.handle).values
    if entry.storage === :history
        axis = ndims(values)
        return ntuple(
            index -> copy(selectdim(values, axis, index)),
            size(values, axis),
        )
    elseif entry.storage in (:medium, :model)
        return only(values)
    end
    return copy(values)
end

function _descriptor_saved_states(executable, snapshot)
    entries = executable.reports.states
    values = map(
        entry -> _descriptor_saved_value(snapshot.descriptor_state, entry),
        entries,
    )
    return NamedTuple{Tuple(entry.name for entry in entries)}(values)
end

function _descriptor_saved_topology(executable, snapshot)
    entries = executable.reports.relationship_states
    isempty(entries) && return NamedTuple()
    length(entries) == length(snapshot.relationships) || throw(ArgumentError(
        "compiled topology declarations and runtime stores are misaligned"
    ))
    names = Tuple(entry.name for entry in entries)
    values = Tuple(copy(state) for state in snapshot.relationships)
    return NamedTuple{names}(values)
end

function _saved_state(
        executable,
        snapshot::CorePotts.ProgramSnapshot,
        observations,
        declared_observations = keys(observations),
        native = (),
)
    states = _descriptor_saved_states(executable, snapshot)
    topology = _descriptor_saved_topology(executable, snapshot)
    return PottsSavedState(
        snapshot.mcs,
        copy(snapshot.ownership),
        copy(snapshot.cell_kinds),
        copy(snapshot.cell_generations),
        copy(CorePotts.CompilerSPI.program_tracker_values(
            executable.core_program,
            snapshot,
            Val(:cell_volume),
        )),
        states,
        topology,
        observations,
        Tuple(declared_observations),
        Tuple(_copy_native_logical_state(state) for state in native),
    )
end

function Base.getindex(state::PottsSavedState, name::Symbol)
    name === :ownership && return state.ownership
    name === :cell_kinds && return state.cell_kinds
    name === :cell_generations && return state.cell_generations
    name === :volumes && return state.volumes
    haskey(state.states, name) && return getproperty(state.states, name)
    haskey(state.topology, name) && return getproperty(state.topology, name)
    haskey(state.observations, name) && return state.observations[name]
    name in state.declared_observations &&
        throw(PottsKnownUnsavedError(name, state.mcs))
    throw(PottsUnknownIdentityError(name))
end

function Base.getproperty(state::PottsSavedState, name::Symbol)
    name in fieldnames(typeof(state)) && return getfield(state, name)
    return getindex(state, name)
end

Base.propertynames(state::PottsSavedState) = (
    :mcs, :ownership, :cell_kinds, :cell_generations, :volumes,
    :native,
    keys(getfield(state, :states))...,
    keys(getfield(state, :topology))...,
    keys(state.observations)...,
)

function native_state(state::PottsSavedState, path)
    value = _native_state_by_path(state.native, path)
    value isa NativeCellStateSnapshot && throw(ArgumentError(
        "PerCell native state requires a generation-stamped CellIdentity"
    ))
    return _copy_native_logical_state(value)
end

function native_state(
        state::PottsSavedState, path, identity::CorePotts.CellIdentity
    )
    value = _native_state_by_path(state.native, path)
    value isa NativeCellStateSnapshot || throw(ArgumentError(
        "a CellIdentity may be supplied only for a PerCell native component"
    ))
    slot = Int(identity.slot)
    checkbounds(value.identities, slot)
    value.identities[slot] == identity || throw(ArgumentError(
        "stale CellIdentity for saved PerCell native state"
    ))
    return _copy_native_logical_state(value.states[slot])
end

struct PottsStats
    steps::Int
    candidate_attempts::UInt64
    accepted::UInt64
    rejected::UInt64
    null_attempts::UInt64
    constraint_rejections::UInt64
    energy_rejections::UInt64
    retired_cells::UInt64
end

Base.merge(left::PottsStats, right::PottsStats) = PottsStats(
    left.steps + right.steps,
    left.candidate_attempts + right.candidate_attempts,
    left.accepted + right.accepted,
    left.rejected + right.rejected,
    left.null_attempts + right.null_attempts,
    left.constraint_rejections + right.constraint_rejections,
    left.energy_rejections + right.energy_rejections,
    left.retired_cells + right.retired_cells,
)

"""Supertype of precise saved-state lookup failures."""
abstract type PottsLookupError <: Exception end

"""Lookup failure for an identity absent from the compiled system."""
struct PottsUnknownIdentityError <: PottsLookupError
    identity::Symbol
end

"""A known observation was not saved at the requested step."""
struct PottsKnownUnsavedError <: PottsLookupError
    identity::Symbol
    mcs::Int
end

"""The requested trajectory step was omitted by the save schedule."""
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

# Snapshot names support public lookup and diagnostics, but runtime author
# names do not parameterize the surrounding saved-state representation.
"""Read-only named values exposed by a saved state."""
struct PottsSavedValues{V <: Tuple}
    named::NamedTuple{N, V} where {N}

    PottsSavedValues(values::NamedTuple{N, V}) where {N, V <: Tuple} =
        new{V}(values)

    function PottsSavedValues(names, values::V) where {V <: Tuple}
        normalized = names isa Tuple{Vararg{Symbol}} ?
            names : Tuple(Symbol(name) for name in names)
        length(normalized) == length(values) || throw(ArgumentError(
            "saved-value names and values must have equal length"
        ))
        for left in eachindex(normalized), right in (left + 1):lastindex(normalized)
            normalized[left] === normalized[right] && throw(ArgumentError(
                "saved-value names must be unique"
            ))
        end
        return new{V}(NamedTuple{normalized}(values))
    end
end

_saved_value_buffer(values::PottsSavedValues) = values
_saved_value_buffer(values::NamedTuple) = PottsSavedValues(values)

_saved_value_names(buffer::PottsSavedValues) = keys(getfield(buffer, :named))
Base.keys(buffer::PottsSavedValues) = _saved_value_names(buffer)
Base.values(buffer::PottsSavedValues{V}) where {V} =
    Tuple(getfield(buffer, :named))::V
Base.Tuple(buffer::PottsSavedValues) = values(buffer)
Base.NamedTuple(buffer::PottsSavedValues) = getfield(buffer, :named)
Base.length(buffer::PottsSavedValues) = length(values(buffer))
Base.isempty(buffer::PottsSavedValues) = isempty(values(buffer))
Base.iterate(buffer::PottsSavedValues, state...) = iterate(values(buffer), state...)
Base.getindex(buffer::PottsSavedValues, index::Integer) = values(buffer)[index]
Base.propertynames(buffer::PottsSavedValues) = keys(buffer)
Base.pairs(buffer::PottsSavedValues) = pairs(getfield(buffer, :named))
Base.:(==)(left::PottsSavedValues, right::PottsSavedValues) =
    getfield(left, :named) == getfield(right, :named)
Base.:(==)(left::PottsSavedValues, right::NamedTuple) =
    getfield(left, :named) == right
Base.:(==)(left::NamedTuple, right::PottsSavedValues) = right == left
Base.isequal(left::PottsSavedValues, right::PottsSavedValues) =
    isequal(getfield(left, :named), getfield(right, :named))
Base.isequal(left::PottsSavedValues, right::NamedTuple) =
    isequal(getfield(left, :named), right)
Base.isequal(left::NamedTuple, right::PottsSavedValues) = isequal(right, left)
Base.hash(buffer::PottsSavedValues, seed::UInt) =
    hash(getfield(buffer, :named), seed)
Base.show(io::IO, buffer::PottsSavedValues) = show(io, getfield(buffer, :named))

function _saved_value_index(buffer::PottsSavedValues, name::Symbol)
    names = keys(buffer)
    for index in eachindex(names)
        @inbounds names[index] === name && return index
    end
    return nothing
end
_saved_value_haskey(buffer::PottsSavedValues, name::Symbol) =
    _saved_value_index(buffer, name) !== nothing
Base.haskey(buffer::PottsSavedValues, name::Symbol) =
    _saved_value_haskey(buffer, name)
function _saved_value(buffer::PottsSavedValues, name::Symbol)
    index = _saved_value_index(buffer, name)
    named = getfield(buffer, :named)
    index === nothing && throw(FieldError(typeof(named), name))
    return values(buffer)[index]
end
Base.getindex(buffer::PottsSavedValues, name::Symbol) = _saved_value(buffer, name)
function _saved_value(buffer::PottsSavedValues, name::Symbol, default)
    index = _saved_value_index(buffer, name)
    return index === nothing ? default : values(buffer)[index]
end
Base.get(buffer::PottsSavedValues, name::Symbol, default) =
    _saved_value(buffer, name, default)
function Base.getproperty(buffer::PottsSavedValues, name::Symbol)
    return _saved_value(buffer, name)
end

"""Immutable scientific snapshot saved at one Monte Carlo step."""
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

    function PottsSavedState(
            mcs::Int,
            ownership,
            cell_kinds,
            cell_generations,
            volumes,
            states,
            topology,
            observations,
            declared_observations,
            native,
        )
        state_buffer = _saved_value_buffer(states)
        topology_buffer = _saved_value_buffer(topology)
        observation_buffer = _saved_value_buffer(observations)
        return new{
            typeof(ownership),
            typeof(cell_kinds),
            typeof(cell_generations),
            typeof(volumes),
            typeof(state_buffer),
            typeof(topology_buffer),
            typeof(observation_buffer),
            typeof(declared_observations),
            typeof(native),
        }(
            mcs,
            ownership,
            cell_kinds,
            cell_generations,
            volumes,
            state_buffer,
            topology_buffer,
            observation_buffer,
            declared_observations,
            native,
        )
    end
end

_copy_saved_value(value::AbstractArray) = copy(value)
_copy_saved_value(value::Tuple) = map(_copy_saved_value, value)
function _copy_saved_value(value::NamedTuple)
    mapped = map(_copy_saved_value, values(value))
    return NamedTuple{keys(value)}(mapped)
end
_copy_saved_value(value) = value

function _descriptor_saved_value(descriptor_state, entry, program)
    values = CorePotts.CompilerSPI.state_block(descriptor_state, entry.handle).values
    if entry.storage === :history
        source = CorePotts.CompilerSPI.history_source(program.stage_plan, program.descriptor_plan.state_layout, entry.handle)
        axis = ndims(values)
        return ntuple(
            index -> source.schema.domain === :model ? only(selectdim(values, axis, index)) : copy(selectdim(values, axis, index)),
            size(values, axis),
        )
    elseif entry.storage in (:medium, :model)
        return only(values)
    end
    return copy(values)
end

function _descriptor_saved_states(executable, snapshot)
    entries = executable.state_manifest
    values = map(
        entry -> _descriptor_saved_value(snapshot.descriptor_state, entry, executable.core_program),
        entries,
    )
    return PottsSavedValues(Tuple(entry.name for entry in entries), values)
end

function _descriptor_saved_topology(executable, snapshot)
    entries = executable.relationship_manifest
    isempty(entries) && return PottsSavedValues((), ())
    length(entries) == length(snapshot.relationships) || throw(ArgumentError(
        "compiled topology declarations and runtime stores are misaligned"
    ))
    names = Tuple(entry.name for entry in entries)
    values = Tuple(copy(state) for state in snapshot.relationships)
    return PottsSavedValues(names, values)
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
    observation_buffer = observations isa PottsSavedValues ?
        observations : PottsSavedValues(observations)
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
        observation_buffer,
        Tuple(declared_observations),
        Tuple(_copy_native_logical_state(state) for state in native),
    )
end

function Base.getindex(state::PottsSavedState, name::Symbol)
    name === :ownership && return state.ownership
    name === :cell_kinds && return state.cell_kinds
    name === :cell_generations && return state.cell_generations
    name === :volumes && return state.volumes
    states = getfield(state, :states)
    topology = getfield(state, :topology)
    observations = getfield(state, :observations)
    index = _saved_value_index(states, name)
    index === nothing || return values(states)[index]
    index = _saved_value_index(topology, name)
    index === nothing || return values(topology)[index]
    index = _saved_value_index(observations, name)
    index === nothing || return values(observations)[index]
    name in state.declared_observations &&
        throw(PottsKnownUnsavedError(name, state.mcs))
    throw(PottsUnknownIdentityError(name))
end

function Base.getproperty(state::PottsSavedState, name::Symbol)
    name === :states && return getfield(state, :states)
    name === :topology && return getfield(state, :topology)
    name === :observations && return getfield(state, :observations)
    name in fieldnames(typeof(state)) && return getfield(state, name)
    return getindex(state, name)
end

Base.propertynames(state::PottsSavedState) = (
    :mcs, :ownership, :cell_kinds, :cell_generations, :volumes,
    :native,
    _saved_value_names(getfield(state, :states))...,
    _saved_value_names(getfield(state, :topology))...,
    _saved_value_names(getfield(state, :observations))...,
)

"""Return a copied native logical state from a saved state or solution."""
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

"""Aggregated proposal and lifecycle counters for a solve."""
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

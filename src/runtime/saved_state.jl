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

struct PottsSavedState{O, K, G, V, A, F, H, S, R, Q, D}
    mcs::Int
    ownership::O
    cell_kinds::K
    cell_generations::G
    volumes::V
    activity::A
    field::F
    history::H
    stored_states::S
    relationships::R
    observations::Q
    declared_observations::D
end

_copy_saved_value(value::AbstractArray) = copy(value)
_copy_saved_value(value::Tuple) = map(_copy_saved_value, value)
function _copy_saved_value(value::NamedTuple)
    mapped = map(_copy_saved_value, values(value))
    return NamedTuple{keys(value)}(mapped)
end
_copy_saved_value(value) = value

function _saved_state(
        snapshot::CorePotts.ProgramSnapshot,
        observations,
        declared_observations = keys(observations),
    )
    return PottsSavedState(
        snapshot.mcs,
        copy(snapshot.ownership),
        copy(snapshot.cell_kinds),
        copy(snapshot.cell_generations),
        copy(snapshot.volumes),
        snapshot.activity === nothing ? nothing : copy(snapshot.activity),
        snapshot.field === nothing ? nothing : copy(snapshot.field),
        snapshot.history === nothing ? nothing :
        Tuple(copy(entry) for entry in snapshot.history),
        _copy_saved_value(snapshot.stored_states),
        snapshot.relationships === nothing ? nothing : copy(snapshot.relationships),
        observations,
        Tuple(declared_observations),
    )
end

function Base.getindex(state::PottsSavedState, name::Symbol)
    name === :ownership && return state.ownership
    name === :cell_kinds && return state.cell_kinds
    name === :cell_generations && return state.cell_generations
    name === :volumes && return state.volumes
    name === :activity && return state.activity
    name === :field && return state.field
    name === :history && return state.history
    haskey(state.stored_states, name) && return getproperty(state.stored_states, name)
    name === :relationships && return state.relationships
    haskey(state.observations, name) && return state.observations[name]
    name in state.declared_observations &&
        throw(PottsKnownUnsavedError(name, state.mcs))
    throw(PottsUnknownIdentityError(name))
end

Base.propertynames(state::PottsSavedState) = (
    :mcs, :ownership, :cell_kinds, :cell_generations, :volumes,
    :activity, :field, :history, keys(state.stored_states)...,
    :relationships,
    keys(state.observations)...,
)

struct PottsStats
    steps::Int
    accepted::Int
    rejected::Int
    null_attempts::Int
end

Base.merge(left::PottsStats, right::PottsStats) = PottsStats(
    left.steps + right.steps,
    left.accepted + right.accepted,
    left.rejected + right.rejected,
    left.null_attempts + right.null_attempts,
)

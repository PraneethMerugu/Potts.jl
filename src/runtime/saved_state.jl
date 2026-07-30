struct PottsSavedState{O, K, V, A, F, Q}
    mcs::Int
    ownership::O
    cell_kinds::K
    volumes::V
    activity::A
    field::F
    observations::Q
end

function _saved_state(snapshot::CorePotts.ProgramSnapshot, observations)
    return PottsSavedState(
        snapshot.mcs,
        copy(snapshot.ownership),
        copy(snapshot.cell_kinds),
        copy(snapshot.volumes),
        snapshot.activity === nothing ? nothing : copy(snapshot.activity),
        snapshot.field === nothing ? nothing : copy(snapshot.field),
        observations,
    )
end

function Base.getindex(state::PottsSavedState, name::Symbol)
    name === :ownership && return state.ownership
    name === :cell_kinds && return state.cell_kinds
    name === :volumes && return state.volumes
    name === :activity && return state.activity
    name === :field && return state.field
    haskey(state.observations, name) && return state.observations[name]
    throw(KeyError(name))
end

Base.propertynames(state::PottsSavedState) = (
    :mcs, :ownership, :cell_kinds, :volumes, :activity, :field,
    keys(state.observations)...,
)

struct PottsStats
    steps::Int
    accepted::Int
    rejected::Int
    null_attempts::Int
end


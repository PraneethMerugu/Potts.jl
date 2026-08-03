# Fixed-capacity lifecycle status and reusable transaction storage.

@enum LifecycleStatusCode::UInt8 begin
    LifecycleStatusSuccess = 0x00
    LifecycleStatusInadmissible = 0x01
    LifecycleStatusConflict = 0x02
    LifecycleStatusCellCapacity = 0x03
    LifecycleStatusRelationshipCapacity = 0x04
    LifecycleStatusStaleGeneration = 0x05
    LifecycleStatusGenerationOverflow = 0x06
    LifecycleStatusEvaluator = 0x07
    LifecycleStatusFootprint = 0x08
    LifecycleStatusInvariant = 0x09
    LifecycleStatusBackend = 0x0a
end

abstract type AbstractLifecycleFailure <: Exception end

struct LifecycleInadmissibilityFailure <: AbstractLifecycleFailure
    source::Int32
    anchor::Int32
    reason::Symbol
end
struct LifecycleConflictFailure <: AbstractLifecycleFailure
    first_source::Int32
    second_source::Int32
    anchor::Int32
end
struct CellCapacityFailure <: AbstractLifecycleFailure
    max_cells::Int32
    requested::Int32
    available::Int32
end
struct RelationshipCapacityFailure <: AbstractLifecycleFailure
    relationship_slot::Int32
end
struct StaleGenerationFailure <: AbstractLifecycleFailure
    cell::Int32
end
struct GenerationOverflowFailure <: AbstractLifecycleFailure
    cell::Int32
end
struct LifecycleEvaluatorFailure <: AbstractLifecycleFailure
    source::Int32
    anchor::Int32
    reason::Symbol
end
struct LifecycleFootprintFailure <: AbstractLifecycleFailure
    source::Int32
    anchor::Int32
    reason::Symbol
end
struct LifecycleInvariantFailure <: AbstractLifecycleFailure
    source::Int32
    anchor::Int32
    reason::Symbol
end
struct LifecycleBackendFailure{E} <: AbstractLifecycleFailure
    cause::E
end

function Base.showerror(io::IO, failure::CellCapacityFailure)
    print(
        io,
        "cell capacity exhausted: transaction requested ",
        failure.requested,
        " new identities with ",
        failure.available,
        " available (max_cells=",
        failure.max_cells,
        ")",
    )
end
function Base.showerror(io::IO, failure::AbstractLifecycleFailure)
    print(io, nameof(typeof(failure)), "(")
    for (index, field) in enumerate(fieldnames(typeof(failure)))
        index > 1 && print(io, ", ")
        print(io, field, "=", repr(getfield(failure, field)))
    end
    print(io, ")")
end

struct NoLifecycleWorkspace end

mutable struct LifecycleWorkspace{
        V32 <: AbstractVector{Int32},
        VU32 <: AbstractVector{UInt32},
        VB <: AbstractVector{Bool},
        M32 <: AbstractMatrix{Int32},
        M8 <: AbstractMatrix{UInt8},
        O <: AbstractArray{Int32},
        K <: AbstractVector{Int16},
        G <: AbstractVector{UInt32},
        TS,
        R,
        D,
    }
    request_count::Int32
    descriptor::V32
    anchor::V32
    generation::VU32
    occurrence::V32
    active::VB
    selected::VB
    filtered::VB
    planned_site_count::V32
    planned_sites::M32
    partition_labels::M8
    allocation::V32
    canonical_order::V32
    conflict_seen::VB
    site_seen::VB
    site_queue::V32
    free_slots::V32
    representative_site::V32
    staged_ownership::O
    staged_cell_kinds::K
    staged_cell_generations::G
    staged_trackers::TS
    staged_relationships::R
    staged_descriptor_state::D
    status::LifecycleStatusCode
    status_source::Int32
    status_anchor::Int32
    status_detail::Int32
end

function allocate_lifecycle_workspace(
        ::NoLifecycleExecutionPlan,
        program,
        ownership,
        cell_kinds,
        cell_generations,
        trackers,
        relationships,
        descriptor_state,
    )
    return NoLifecycleWorkspace()
end

function allocate_lifecycle_workspace(
        plan::LifecycleExecutionPlan{N, T},
        program,
        ownership,
        cell_kinds,
        cell_generations,
        trackers,
        relationships,
        descriptor_state,
    ) where {N, T}
    length(cell_kinds) == plan.cell_capacity || throw(ArgumentError(
        "cell table does not match compiled max_cells"
    ))
    length(cell_generations) == plan.cell_capacity || throw(ArgumentError(
        "generation table does not match compiled max_cells"
    ))
    request_bound = Int(plan.maximum_requests)
    placement_bound = Int(plan.maximum_placement_sites)
    site_count = length(ownership)
    return LifecycleWorkspace(
        Int32(0),
        zeros(Int32, request_bound),
        zeros(Int32, request_bound),
        zeros(UInt32, request_bound),
        zeros(Int32, request_bound),
        zeros(Bool, request_bound),
        zeros(Bool, request_bound),
        zeros(Bool, request_bound),
        zeros(Int32, request_bound),
        zeros(Int32, placement_bound, request_bound),
        zeros(UInt8, site_count, request_bound),
        zeros(Int32, request_bound),
        zeros(Int32, request_bound),
        zeros(Bool, request_bound),
        zeros(Bool, site_count),
        zeros(Int32, site_count),
        zeros(Int32, Int(plan.cell_capacity)),
        zeros(Int32, Int(plan.cell_capacity)),
        copy(ownership),
        copy(cell_kinds),
        copy(cell_generations),
        copy_tracker_state(trackers),
        copy(relationships),
        copy_auxiliary_state(program.descriptor_plan.state_layout, descriptor_state),
        LifecycleStatusSuccess,
        Int32(0),
        Int32(0),
        Int32(0),
    )
end

function _reset_lifecycle_workspace!(workspace::LifecycleWorkspace)
    workspace.request_count = 0
    fill!(workspace.active, false)
    fill!(workspace.selected, false)
    fill!(workspace.filtered, false)
    fill!(workspace.planned_site_count, 0)
    fill!(workspace.allocation, 0)
    fill!(workspace.conflict_seen, false)
    fill!(workspace.representative_site, 0)
    workspace.status = LifecycleStatusSuccess
    workspace.status_source = 0
    workspace.status_anchor = 0
    workspace.status_detail = 0
    return workspace
end

Adapt.@adapt_structure LifecycleWorkspace
Adapt.@adapt_structure NoLifecycleWorkspace

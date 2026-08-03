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

@enum LifecycleStatusDetailCode::UInt16 begin
    LifecycleDetailNone = 0x0000
    LifecycleDetailOwnershipExceedsCellCapacity = 0x0001
    LifecycleDetailCellSiteIndexExceedsLattice = 0x0002
    LifecycleDetailCellSiteIndexMissingOwnedSite = 0x0003
    LifecycleDetailNonfiniteResult = 0x0004
    LifecycleDetailEvaluationError = 0x0005
    LifecycleDetailRequestBoundExceeded = 0x0006
    LifecycleDetailTriggerNotBoolean = 0x0007
    LifecycleDetailPlacementSelectionInvalid = 0x0008
    LifecycleDetailPlacementNotIntegral = 0x0009
    LifecycleDetailPlacementOutOfBounds = 0x000a
    LifecycleDetailPlacementSelectionEmpty = 0x000b
    LifecycleDetailPlacementEmissionBoundExceeded = 0x000c
    LifecycleDetailPlacementBoundExceeded = 0x000d
    LifecycleDetailDuplicatePlacementSite = 0x000e
    LifecycleDetailPlacementSiteUnavailable = 0x000f
    LifecycleDetailEmptySourceCell = 0x0010
    LifecycleDetailPartitionLabelInvalid = 0x0011
    LifecycleDetailPartitionGeometryInvalid = 0x0012
    LifecycleDetailPartitionEmptyDescendant = 0x0013
    LifecycleDetailPartitionParentDisconnected = 0x0014
    LifecycleDetailPartitionDaughterDisconnected = 0x0015
    LifecycleDetailRetireNonempty = 0x0016
    LifecycleDetailUnknownEffect = 0x0017
    LifecycleDetailRelationshipPolicyRejected = 0x0018
    LifecycleDetailUnknownDistribution = 0x0019
    LifecycleDetailSplitFractionOutOfBounds = 0x001a
    LifecycleDetailUnsupportedStatePolicy = 0x001b
    LifecycleDetailTrackerPlanStateMisalignment = 0x001c
    LifecycleDetailActiveOccupancyMismatch = 0x001d
    LifecycleDetailForbiddenExtinction = 0x001e
    LifecycleDetailDivisionPlanMissing = 0x001f
    LifecycleDetailStateValueInvalid = 0x0020
    LifecycleDetailTrackerStorageInvalid = 0x0021
    LifecycleDetailRelationshipIntegrityInvalid = 0x0022
    LifecycleDetailTrackerCommitInvalid = 0x0023
    LifecycleDetailRelationshipCommitInvalid = 0x0024
end

@enum LifecycleExecutionStage::UInt8 begin
    LifecycleStageNone = 0x00
    LifecycleStageIndex = 0x01
    LifecycleStageEmission = 0x02
    LifecycleStagePlanning = 0x03
    LifecycleStageSelection = 0x04
    LifecycleStageStructure = 0x05
    LifecycleStageRelationships = 0x06
    LifecycleStageState = 0x07
    LifecycleStageValidation = 0x08
    LifecycleStagePublication = 0x09
end

"""One fixed-size engine status; host exceptions are derived only at the boundary."""
struct LifecycleStatusPayload
    code::LifecycleStatusCode
    mcs::Int32
    stage::LifecycleExecutionStage
    source::Int32
    action_identity::UInt64
    secondary_source::Int32
    anchor::Int32
    detail::LifecycleStatusDetailCode
    required::Int32
    available::Int32
    maximum::Int32
end

LifecycleStatusPayload() = LifecycleStatusPayload(
    LifecycleStatusSuccess,
    Int32(0),
    LifecycleStageNone,
    Int32(0),
    UInt64(0),
    Int32(0),
    Int32(0),
    LifecycleDetailNone,
    Int32(0),
    Int32(0),
    Int32(0),
)

LifecycleStatusPayload(
    code::LifecycleStatusCode,
    source::Int32,
    secondary_source::Int32,
    anchor::Int32,
    detail::LifecycleStatusDetailCode,
    required::Int32,
    available::Int32,
    maximum::Int32,
) = LifecycleStatusPayload(
    code,
    Int32(0),
    LifecycleStageNone,
    source,
    UInt64(0),
    secondary_source,
    anchor,
    detail,
    required,
    available,
    maximum,
)

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
    first_possible_mcs::Int
    last_possible_mcs::Int
end

LifecycleBackendFailure(cause) = LifecycleBackendFailure(cause, 0, 0)

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

function lifecycle_workspace_layout(
        plan::LifecycleExecutionPlan, site_count::Integer
    )
    site_count >= 0 || throw(ArgumentError("site count must be nonnegative"))
    requests = Int(plan.maximum_requests)
    placements = Int(plan.maximum_placement_sites)
    cells = Int(plan.cell_capacity)
    policy = Int(plan.maximum_policy_workspace)
    return (
        allocation_model = :fixed_preallocated,
        cell_capacity = cells,
        request_capacity = requests,
        placement_capacity = placements,
        request_slots = requests,
        planned_site_slots = requests * placements,
        partition_label_slots = Int(site_count),
        cell_index_slots = 6 * cells,
        site_index_slots = 6 * Int(site_count),
        policy_workspace_slots = requests * policy,
        policy_workspace_capacity = policy,
        free_cell_slots = cells,
    )
end

lifecycle_workspace_layout(::NoLifecycleExecutionPlan, site_count::Integer) = (
    allocation_model = :none,
    cell_capacity = 0,
    request_capacity = 0,
    placement_capacity = 0,
    request_slots = 0,
    planned_site_slots = 0,
    partition_label_slots = 0,
    cell_index_slots = 0,
    site_index_slots = 0,
    policy_workspace_slots = 0,
    policy_workspace_capacity = 0,
    free_cell_slots = 0,
)

struct LifecycleWorkspace{
        V32 <: AbstractVector{Int32},
        VU32 <: AbstractVector{UInt32},
        VB <: AbstractVector{Bool},
        VS <: AbstractVector{LifecycleStatusDetailCode},
        M32 <: AbstractMatrix{Int32},
        V8 <: AbstractVector{UInt8},
        PW <: AbstractMatrix,
        O <: AbstractArray{Int32},
        K <: AbstractVector{Int16},
        G <: AbstractVector{UInt32},
        LS <: AbstractVector{LifecycleStatusPayload},
        TS,
        R,
        D,
    }
    request_count::V32
    descriptor::V32
    anchor::V32
    generation::VU32
    occurrence::V32
    active::VB
    selected::VB
    filtered::VB
    filtered_detail::VS
    planned_site_count::V32
    planned_sites::M32
    partition_labels::V8
    partition_scratch::V8
    partition_owner::V32
    cell_site_starts::V32
    cell_site_counts::V32
    cell_site_cursor::V32
    cell_sites::V32
    site_position::V32
    policy_workspace::PW
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
    status::LS
end

@inline lifecycle_request_count(workspace::LifecycleWorkspace) =
    @inbounds workspace.request_count[1]

@inline function set_lifecycle_request_count!(workspace::LifecycleWorkspace, value)
    @inbounds workspace.request_count[1] = Int32(value)
    return workspace
end

@inline lifecycle_workspace_status(workspace::LifecycleWorkspace) =
    @inbounds workspace.status[1]

function lifecycle_workspace_conforms(
        workspace::LifecycleWorkspace,
        plan::LifecycleExecutionPlan,
        site_count::Integer,
    )
    layout = lifecycle_workspace_layout(plan, site_count)
    requests = layout.request_capacity
    cells = layout.cell_capacity
    sites = Int(site_count)
    request_vectors = (
        workspace.descriptor,
        workspace.anchor,
        workspace.generation,
        workspace.occurrence,
        workspace.active,
        workspace.selected,
        workspace.filtered,
        workspace.filtered_detail,
        workspace.planned_site_count,
        workspace.allocation,
        workspace.canonical_order,
        workspace.conflict_seen,
    )
    cell_vectors = (
        workspace.cell_site_starts,
        workspace.cell_site_counts,
        workspace.cell_site_cursor,
        workspace.free_slots,
        workspace.representative_site,
        workspace.partition_owner,
    )
    site_vectors = (
        workspace.partition_labels,
        workspace.partition_scratch,
        workspace.cell_sites,
        workspace.site_position,
        workspace.site_seen,
        workspace.site_queue,
    )
    return all(value -> length(value) == requests, request_vectors) &&
        length(workspace.request_count) == 1 &&
        length(workspace.status) == 1 &&
        all(value -> length(value) == cells, cell_vectors) &&
        all(value -> length(value) == sites, site_vectors) &&
        size(workspace.planned_sites) ==
            (layout.placement_capacity, requests) &&
        size(workspace.policy_workspace) ==
            (layout.policy_workspace_capacity, requests) &&
        length(workspace.staged_ownership) == sites &&
        length(workspace.staged_cell_kinds) == cells &&
        length(workspace.staged_cell_generations) == cells
end

lifecycle_workspace_conforms(
    ::NoLifecycleWorkspace, ::NoLifecycleExecutionPlan, site_count::Integer
) = site_count >= 0

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
    layout = lifecycle_workspace_layout(plan, site_count)
    return LifecycleWorkspace(
        zeros(Int32, 1),
        zeros(Int32, request_bound),
        zeros(Int32, request_bound),
        zeros(UInt32, request_bound),
        zeros(Int32, request_bound),
        zeros(Bool, request_bound),
        zeros(Bool, request_bound),
        zeros(Bool, request_bound),
        fill(LifecycleDetailNone, request_bound),
        zeros(Int32, request_bound),
        zeros(Int32, placement_bound, request_bound),
        zeros(UInt8, site_count),
        zeros(UInt8, site_count),
        zeros(Int32, Int(plan.cell_capacity)),
        zeros(Int32, Int(plan.cell_capacity)),
        zeros(Int32, Int(plan.cell_capacity)),
        zeros(Int32, Int(plan.cell_capacity)),
        zeros(Int32, site_count),
        zeros(Int32, site_count),
        zeros(T, layout.policy_workspace_capacity, request_bound),
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
        LifecycleStatusPayload[LifecycleStatusPayload()],
    )
end

function _reset_lifecycle_workspace!(workspace::LifecycleWorkspace)
    set_lifecycle_request_count!(workspace, 0)
    fill!(workspace.active, false)
    fill!(workspace.selected, false)
    fill!(workspace.filtered, false)
    fill!(workspace.filtered_detail, LifecycleDetailNone)
    fill!(workspace.planned_site_count, 0)
    fill!(workspace.partition_owner, 0)
    fill!(workspace.policy_workspace, zero(eltype(workspace.policy_workspace)))
    fill!(workspace.allocation, 0)
    fill!(workspace.conflict_seen, false)
    fill!(workspace.representative_site, 0)
    @inbounds workspace.status[1] = LifecycleStatusPayload()
    return workspace
end

Adapt.@adapt_structure LifecycleWorkspace
Adapt.@adapt_structure NoLifecycleWorkspace

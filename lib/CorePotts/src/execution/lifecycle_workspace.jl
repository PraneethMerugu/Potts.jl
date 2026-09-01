# Fixed-capacity reusable lifecycle transaction storage.

struct NoLifecycleWorkspace end

"""Compute fixed lifecycle workspace capacities and representation layout."""
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
        request_index_slots = 11 * requests + 1,
        planned_site_slots = requests * placements,
        partition_label_slots = Int(site_count),
        cell_index_slots = cells + 2,
        site_index_slots = 5 * Int(site_count),
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
    request_index_slots = 0,
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
        VS <: AbstractVector{ProgramStatusDetailCode},
        M32 <: AbstractMatrix{Int32},
        V8 <: AbstractVector{UInt8},
        PW <: AbstractMatrix,
        O <: AbstractArray{Int32},
        K <: AbstractVector{Int16},
        G <: AbstractVector{UInt32},
        LS <: AbstractVector{ProgramStatus},
        TS,
        R,
        D,
        SI,
        RI,
        SEL,
    }
    request_count::V32
    descriptor::V32
    anchor::V32
    generation::VU32
    request_priority::V32
    request_source_high::VU32
    request_source_low::VU32
    request_action_high::VU32
    request_action_low::VU32
    occurrence::V32
    active::VB
    filtered::VB
    filtered_detail::VS
    planned_site_count::V32
    planned_sites::M32
    partition_labels::V8
    partition_scratch::V8
    partition_owner::V32
    site_index::SI
    request_index::RI
    selection::SEL
    planned_site_request::V32
    policy_workspace::PW
    site_seen::VB
    site_queue::V32
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
        workspace.request_priority,
        workspace.request_source_high,
        workspace.request_source_low,
        workspace.request_action_high,
        workspace.request_action_low,
        workspace.occurrence,
        workspace.active,
        workspace.filtered,
        workspace.filtered_detail,
        workspace.planned_site_count,
    )
    cell_vectors = (
        workspace.partition_owner,
    )
    site_vectors = (
        workspace.partition_labels,
        workspace.partition_scratch,
        workspace.planned_site_request,
        workspace.site_seen,
        workspace.site_queue,
    )
    return all(value -> length(value) == requests, request_vectors) &&
        length(workspace.request_count) == 1 &&
        length(workspace.status) == 1 &&
        length(workspace.site_index.count) == 1 &&
        length(workspace.site_index.records) == sites &&
        length(workspace.site_index.segment_starts) == cells + 1 &&
        length(workspace.site_index.source_item) == sites &&
        length(workspace.site_index.source_lane) == sites &&
        length(workspace.site_index.source_position) == sites &&
        length(workspace.request_index.count) == 1 &&
        length(workspace.request_index.records) == requests &&
        workspace.request_index.segment_starts === nothing &&
        length(workspace.request_index.source_item) == requests &&
        length(workspace.request_index.source_lane) == requests &&
        length(workspace.request_index.source_position) == requests &&
        _lifecycle_selection_storage_conforms(workspace.selection, plan) &&
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
    selection = _allocate_lifecycle_selection_storage(
        plan, ownership, relationships
    )
    site_index, request_index = _allocate_lifecycle_compaction_results(
        plan, ownership, selection
    )
    return LifecycleWorkspace(
        zeros(Int32, 1),
        zeros(Int32, request_bound),
        zeros(Int32, request_bound),
        zeros(UInt32, request_bound),
        zeros(Int32, request_bound),
        zeros(UInt32, request_bound),
        zeros(UInt32, request_bound),
        zeros(UInt32, request_bound),
        zeros(UInt32, request_bound),
        zeros(Int32, request_bound),
        zeros(Bool, request_bound),
        zeros(Bool, request_bound),
        fill(LifecycleDetailNone, request_bound),
        zeros(Int32, request_bound),
        zeros(Int32, placement_bound, request_bound),
        zeros(UInt8, site_count),
        zeros(UInt8, site_count),
        zeros(Int32, Int(plan.cell_capacity)),
        site_index,
        request_index,
        selection,
        zeros(Int32, site_count),
        zeros(T, layout.policy_workspace_capacity, request_bound),
        zeros(Bool, site_count),
        zeros(Int32, site_count),
        copy(ownership),
        copy(cell_kinds),
        copy(cell_generations),
        copy_tracker_state(trackers),
        copy(relationships),
        copy_auxiliary_state(program.descriptor_plan.state_layout, descriptor_state),
        StructArrays.StructArray(ProgramStatus[ProgramStatus()]),
    )
end

function _reset_lifecycle_workspace!(workspace::LifecycleWorkspace)
    set_lifecycle_request_count!(workspace, 0)
    @inbounds begin
        workspace.selection.open[1] = false
        workspace.selection.ready[1] = false
    end
    fill!(workspace.active, false)
    fill!(workspace.filtered, false)
    fill!(workspace.filtered_detail, LifecycleDetailNone)
    fill!(workspace.planned_site_count, 0)
    fill!(workspace.partition_owner, 0)
    fill!(workspace.planned_site_request, 0)
    fill!(workspace.policy_workspace, zero(eltype(workspace.policy_workspace)))
    @inbounds workspace.status[1] = ProgramStatus()
    return workspace
end

Adapt.@adapt_structure LifecycleWorkspace
Adapt.@adapt_structure NoLifecycleWorkspace

# Backend-resident lifecycle transaction control and portable launch storage.

struct NoLifecycleBackendControl end

"""Fixed backend storage needed to enqueue one lifecycle transaction without host polling."""
struct LifecycleBackendControl{
        O <: AbstractVector{Int32},
        C <: AbstractVector{Int32},
        S <: AbstractVector{LifecycleStatusPayload},
        K <: AbstractVector{UInt64},
        U <: AbstractVector{UInt64},
    }
    request_offsets::O
    counters::C
    request_scan::C
    request_scan_scratch::C
    candidate_status::S
    site_keys::K
    site_keys_scratch::K
    statistics::U
end

Adapt.@adapt_structure LifecycleBackendControl
Adapt.@adapt_structure NoLifecycleBackendControl

struct _LifecycleStatusSlot{S} <: AbstractVector{LifecycleStatusPayload}
    values::S
    slot::Int32
end

Base.IndexStyle(::Type{<:_LifecycleStatusSlot}) = IndexLinear()
Base.size(::_LifecycleStatusSlot) = (1,)
@inline Base.getindex(status::_LifecycleStatusSlot, index::Integer) =
    @inbounds status.values[Int(status.slot)]
@inline function Base.setindex!(
        status::_LifecycleStatusSlot, value, index::Integer
    )
    @inbounds status.values[Int(status.slot)] = value
    return value
end

@inline function _lifecycle_workspace_with_status(
        workspace::LifecycleWorkspace, status
    )
    return LifecycleWorkspace(
        workspace.request_count,
        workspace.descriptor,
        workspace.anchor,
        workspace.generation,
        workspace.occurrence,
        workspace.active,
        workspace.selected,
        workspace.filtered,
        workspace.filtered_detail,
        workspace.planned_site_count,
        workspace.planned_sites,
        workspace.partition_labels,
        workspace.partition_scratch,
        workspace.partition_owner,
        workspace.cell_site_starts,
        workspace.cell_site_counts,
        workspace.cell_site_cursor,
        workspace.cell_sites,
        workspace.site_position,
        workspace.policy_workspace,
        workspace.allocation,
        workspace.canonical_order,
        workspace.conflict_seen,
        workspace.site_seen,
        workspace.site_queue,
        workspace.free_slots,
        workspace.representative_site,
        workspace.staged_ownership,
        workspace.staged_cell_kinds,
        workspace.staged_cell_generations,
        workspace.staged_trackers,
        workspace.staged_relationships,
        workspace.staged_descriptor_state,
        status,
    )
end

@inline function _lifecycle_workspace_with_staged_state(
        workspace::LifecycleWorkspace, state
    )
    return LifecycleWorkspace(
        workspace.request_count,
        workspace.descriptor,
        workspace.anchor,
        workspace.generation,
        workspace.occurrence,
        workspace.active,
        workspace.selected,
        workspace.filtered,
        workspace.filtered_detail,
        workspace.planned_site_count,
        workspace.planned_sites,
        workspace.partition_labels,
        workspace.partition_scratch,
        workspace.partition_owner,
        workspace.cell_site_starts,
        workspace.cell_site_counts,
        workspace.cell_site_cursor,
        workspace.cell_sites,
        workspace.site_position,
        workspace.policy_workspace,
        workspace.allocation,
        workspace.canonical_order,
        workspace.conflict_seen,
        workspace.site_seen,
        workspace.site_queue,
        workspace.free_slots,
        workspace.representative_site,
        state.ownership,
        state.cell_kinds,
        state.cell_generations,
        state.trackers,
        state.relationships,
        state.descriptor_state,
        workspace.status,
    )
end

const _LIFECYCLE_CONTROL_DUE = 1
const _LIFECYCLE_CONTROL_SELECTED = 2
const _LIFECYCLE_CONTROL_RETIRED = 3
const _LIFECYCLE_CONTROL_RETIRED_TOTAL = 4
const _LIFECYCLE_CONTROL_ACTIVE_BANK = 5
const _LIFECYCLE_CONTROL_COMMITTED_MCS = 6
const _PROGRAM_STAT_ACCEPTED = 1
const _PROGRAM_STAT_REJECTED = 2
const _PROGRAM_STAT_NULL = 3
const _PROGRAM_STAT_CONSTRAINT = 4
const _PROGRAM_STAT_ENERGY = 5
const _PROGRAM_STAT_RETIRED = 6

_lifecycle_backend_similar(prototype, ::Type{T}, dimensions...) where {T} =
    similar(prototype, T, dimensions...)

function _lifecycle_backend_filled(
        prototype, ::Type{T}, value, dimensions...
    ) where {T}
    storage = _lifecycle_backend_similar(prototype, T, dimensions...)
    fill!(storage, convert(T, value))
    return storage
end

function _lifecycle_request_offsets(plan::LifecycleExecutionPlan)
    offsets = Vector{Int32}(undef, length(plan.descriptors))
    next_offset = 1
    for index in eachindex(plan.descriptors)
        descriptor = @inbounds plan.descriptors[index]
        offsets[index] = Int32(next_offset)
        next_offset += descriptor.domain === ModelLifecycleDomain ?
            1 : Int(plan.cell_capacity)
    end
    next_offset - 1 == Int(plan.maximum_requests) || throw(ArgumentError(
        "lifecycle request offsets do not cover the compiled request bound"
    ))
    return offsets
end

function allocate_lifecycle_backend_control(
        ::NoLifecycleExecutionPlan, prototype, site_count::Integer
    )
    site_count >= 0 || throw(ArgumentError("site count must be nonnegative"))
    return NoLifecycleBackendControl()
end

function allocate_lifecycle_backend_control(
        plan::LifecycleExecutionPlan,
        prototype,
        site_count::Integer,
    )
    site_count >= 0 || throw(ArgumentError("site count must be nonnegative"))
    status_slots = max(
        1,
        Int(plan.maximum_requests),
        Int(plan.cell_capacity),
        Int(site_count),
    )
    counters = _lifecycle_backend_filled(prototype, Int32, 0, 6)
    @inbounds counters[_LIFECYCLE_CONTROL_ACTIVE_BANK] = Int32(1)
    return LifecycleBackendControl(
        _lifecycle_request_offsets(plan),
        counters,
        _lifecycle_backend_filled(
            prototype, Int32, 0, Int(plan.maximum_requests)
        ),
        _lifecycle_backend_filled(
            prototype, Int32, 0, max(1, Int(plan.maximum_requests))
        ),
        _lifecycle_backend_filled(
            prototype,
            LifecycleStatusPayload,
            LifecycleStatusPayload(),
            status_slots,
        ),
        _lifecycle_backend_filled(
            prototype, UInt64, typemax(UInt64), Int(site_count)
        ),
        _lifecycle_backend_filled(
            prototype, UInt64, typemax(UInt64), Int(site_count)
        ),
        _lifecycle_backend_filled(prototype, UInt64, 0, 6),
    )
end

function lifecycle_backend_status(workspace::LifecycleWorkspace)
    backend = KernelAbstractions.get_backend(workspace.status)
    backend isa KernelAbstractions.CPU || throw(ArgumentError(
        "device lifecycle status is host-visible only through settle_program!"
    ))
    return lifecycle_workspace_status(workspace)
end

@inline _lifecycle_backend_open(workspace::LifecycleWorkspace) =
    (@inbounds workspace.status[1]).code === LifecycleStatusSuccess
@inline _lifecycle_backend_open(::NoLifecycleWorkspace) = true

function _enqueue_lifecycle_array_copy!(destination, source, backend)
    length(destination) == length(source) || throw(ArgumentError(
        "lifecycle staging arrays have incompatible lengths"
    ))
    AcceleratedKernels.foreachindex(destination, backend) do index
        @inbounds destination[index] = source[index]
    end
    return nothing
end

_enqueue_lifecycle_tuple_copy!(::Tuple{}, ::Tuple{}, backend) = nothing
function _enqueue_lifecycle_tuple_copy!(destination, source, backend)
    _enqueue_lifecycle_storage_copy!(
        first(destination), first(source), backend
    )
    _enqueue_lifecycle_tuple_copy!(
        Base.tail(destination), Base.tail(source), backend
    )
    return nothing
end

_enqueue_lifecycle_storage_copy!(destination::AbstractArray, source, backend) =
    _enqueue_lifecycle_array_copy!(destination, source, backend)

function _enqueue_lifecycle_storage_copy!(
        destination::AbstractVector{<:ProgramRelationshipState},
        source::AbstractVector{<:ProgramRelationshipState},
        backend,
    )
    backend isa KernelAbstractions.CPU || throw(ArgumentError(
        "unpacked relationship state cannot cross a device boundary"
    ))
    length(destination) == length(source) || throw(ArgumentError(
        "relationship staging banks have incompatible lengths"
    ))
    for index in eachindex(destination)
        copyto!(destination[index], source[index])
    end
    return nothing
end

function _enqueue_lifecycle_storage_copy!(
        destination::CellMomentsState, source::CellMomentsState, backend
    )
    _enqueue_lifecycle_array_copy!(destination.first, source.first, backend)
    _enqueue_lifecycle_array_copy!(destination.second, source.second, backend)
    return nothing
end

function _enqueue_lifecycle_storage_copy!(
        destination::TrackerState, source::TrackerState, backend
    )
    _enqueue_lifecycle_tuple_copy!(
        destination.values, source.values, backend
    )
    return nothing
end

function _enqueue_lifecycle_storage_copy!(
        destination::AuxiliaryState, source::AuxiliaryState, backend
    )
    _enqueue_lifecycle_tuple_copy!(
        destination.banks, source.banks, backend
    )
    return nothing
end

function _enqueue_lifecycle_storage_copy!(
        destination::BlockBank, source::BlockBank, backend
    )
    _enqueue_lifecycle_array_copy!(
        destination.values, source.values, backend
    )
    return nothing
end

function _enqueue_lifecycle_storage_copy!(
        destination::PackedRelationshipBank,
        source::PackedRelationshipBank,
        backend,
    )
    for field in (
            :active,
            :endpoint_a,
            :endpoint_b,
            :generation_a,
            :generation_b,
            :degree,
            :incident_edges,
        )
        _enqueue_lifecycle_array_copy!(
            getfield(destination, field), getfield(source, field), backend
        )
    end
    _enqueue_lifecycle_tuple_copy!(
        destination.payload, source.payload, backend
    )
    return nothing
end

function _enqueue_lifecycle_storage_copy!(
        destination::RelationshipStorage,
        source::RelationshipStorage,
        backend,
    )
    _enqueue_lifecycle_tuple_copy!(
        destination.banks, source.banks, backend
    )
    return nothing
end

function _enqueue_lifecycle_storage_copy!(destination, source, backend)
    backend isa KernelAbstractions.CPU || throw(ArgumentError(
        "lifecycle staging storage has no backend-resident copy protocol"
    ))
    copyto!(destination, source)
    return nothing
end

function _enqueue_lifecycle_staging_copy!(state, backend)
    workspace = state.lifecycle_workspace
    _enqueue_lifecycle_array_copy!(
        workspace.staged_ownership, state.ownership, backend
    )
    _enqueue_lifecycle_array_copy!(
        workspace.staged_cell_kinds, state.cell_kinds, backend
    )
    _enqueue_lifecycle_array_copy!(
        workspace.staged_cell_generations, state.cell_generations, backend
    )
    _enqueue_lifecycle_storage_copy!(
        workspace.staged_trackers, state.trackers, backend
    )
    _enqueue_lifecycle_storage_copy!(
        workspace.staged_relationships, state.relationships, backend
    )
    _enqueue_lifecycle_storage_copy!(
        workspace.staged_descriptor_state, state.descriptor_state, backend
    )
    return nothing
end

@kernel function _lifecycle_gated_copy_kernel!(
        destination, source, workspace, control, mode
    )
    index = @index(Global, Linear)
    open = _lifecycle_backend_open(workspace)
    enabled = mode === Val(:open) ? open :
        open && _lifecycle_backend_due(control) &&
        @inbounds(control.counters[_LIFECYCLE_CONTROL_SELECTED]) > 0
    if index <= length(destination) && enabled
        @inbounds destination[index] = source[index]
    end
end

function _enqueue_lifecycle_gated_array_copy!(
        destination, source, backend, workspace, control,
        mode = Val(:selected),
    )
    length(destination) == length(source) || throw(ArgumentError(
        "lifecycle transaction arrays have incompatible lengths"
    ))
    _lifecycle_gated_copy_kernel!(backend)(
        destination,
        source,
        workspace,
        control,
        mode;
        ndrange = length(destination),
    )
    return nothing
end

_enqueue_lifecycle_gated_tuple_copy!(
    ::Tuple{}, ::Tuple{}, backend, workspace, control, mode = Val(:selected)
) = nothing

function _enqueue_lifecycle_gated_tuple_copy!(
        destination, source, backend, workspace, control,
        mode = Val(:selected),
    )
    _enqueue_lifecycle_gated_storage_copy!(
        first(destination), first(source), backend, workspace, control, mode
    )
    _enqueue_lifecycle_gated_tuple_copy!(
        Base.tail(destination),
        Base.tail(source),
        backend,
        workspace,
        control,
        mode,
    )
    return nothing
end

_enqueue_lifecycle_gated_storage_copy!(
    destination::AbstractArray, source, backend, workspace, control,
    mode = Val(:selected),
) = _enqueue_lifecycle_gated_array_copy!(
    destination, source, backend, workspace, control, mode
)

function _enqueue_lifecycle_gated_storage_copy!(
        destination::CellMomentsState,
        source::CellMomentsState,
        backend,
        workspace,
        control,
        mode = Val(:selected),
    )
    _enqueue_lifecycle_gated_array_copy!(
        destination.first, source.first, backend, workspace, control, mode
    )
    _enqueue_lifecycle_gated_array_copy!(
        destination.second, source.second, backend, workspace, control, mode
    )
    return nothing
end

function _enqueue_lifecycle_gated_storage_copy!(
        destination::TrackerState,
        source::TrackerState,
        backend,
        workspace,
        control,
        mode = Val(:selected),
    )
    _enqueue_lifecycle_gated_tuple_copy!(
        destination.values, source.values, backend, workspace, control, mode
    )
    return nothing
end

function _enqueue_lifecycle_gated_storage_copy!(
        destination::AuxiliaryState,
        source::AuxiliaryState,
        backend,
        workspace,
        control,
        mode = Val(:selected),
    )
    _enqueue_lifecycle_gated_tuple_copy!(
        destination.banks, source.banks, backend, workspace, control, mode
    )
    return nothing
end

function _enqueue_lifecycle_gated_storage_copy!(
        destination::BlockBank,
        source::BlockBank,
        backend,
        workspace,
        control,
        mode = Val(:selected),
    )
    _enqueue_lifecycle_gated_array_copy!(
        destination.values, source.values, backend, workspace, control, mode
    )
    return nothing
end

function _enqueue_lifecycle_gated_storage_copy!(
        destination::PackedRelationshipBank,
        source::PackedRelationshipBank,
        backend,
        workspace,
        control,
        mode = Val(:selected),
    )
    for field in (
            :active,
            :endpoint_a,
            :endpoint_b,
            :generation_a,
            :generation_b,
            :degree,
            :incident_edges,
        )
        _enqueue_lifecycle_gated_array_copy!(
            getfield(destination, field),
            getfield(source, field),
            backend,
            workspace,
            control,
            mode,
        )
    end
    _enqueue_lifecycle_gated_tuple_copy!(
        destination.payload,
        source.payload,
        backend,
        workspace,
        control,
        mode,
    )
    return nothing
end

function _enqueue_lifecycle_gated_storage_copy!(
        destination::RelationshipStorage,
        source::RelationshipStorage,
        backend,
        workspace,
        control,
        mode = Val(:selected),
    )
    _enqueue_lifecycle_gated_tuple_copy!(
        destination.banks, source.banks, backend, workspace, control, mode
    )
    return nothing
end

function _enqueue_lifecycle_gated_state_copy!(
        destination, source, backend, workspace, control,
        mode = Val(:selected),
    )
    _enqueue_lifecycle_gated_array_copy!(
        destination.ownership,
        source.ownership,
        backend,
        workspace,
        control,
        mode,
    )
    _enqueue_lifecycle_gated_array_copy!(
        destination.cell_kinds,
        source.cell_kinds,
        backend,
        workspace,
        control,
        mode,
    )
    _enqueue_lifecycle_gated_array_copy!(
        destination.cell_generations,
        source.cell_generations,
        backend,
        workspace,
        control,
        mode,
    )
    _enqueue_lifecycle_gated_storage_copy!(
        destination.trackers,
        source.trackers,
        backend,
        workspace,
        control,
        mode,
    )
    _enqueue_lifecycle_gated_storage_copy!(
        destination.relationships,
        source.relationships,
        backend,
        workspace,
        control,
        mode,
    )
    _enqueue_lifecycle_gated_storage_copy!(
        destination.descriptor_state,
        source.descriptor_state,
        backend,
        workspace,
        control,
        mode,
    )
    return nothing
end

function _enqueue_program_state_copy!(destination, source)
    workspace = destination.lifecycle_workspace
    control = destination.lifecycle_control
    backend = KernelAbstractions.get_backend(destination.ownership)
    KernelAbstractions.get_backend(source.ownership) == backend || throw(
        ArgumentError("program state banks must share one execution backend")
    )
    _enqueue_lifecycle_gated_state_copy!(
        destination,
        source,
        backend,
        workspace,
        control,
        Val(:open),
    )
    return destination
end

@kernel function _publish_program_bank_kernel!(
        workspace, control, report, bank::Int32, committed_mcs::Int32
    )
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace)
        @inbounds begin
            control.counters[_LIFECYCLE_CONTROL_ACTIVE_BANK] = bank
            control.counters[_LIFECYCLE_CONTROL_COMMITTED_MCS] = committed_mcs
            control.statistics[_PROGRAM_STAT_ACCEPTED] += report[1]
            control.statistics[_PROGRAM_STAT_REJECTED] += report[2]
            control.statistics[_PROGRAM_STAT_NULL] += report[3]
            control.statistics[_PROGRAM_STAT_CONSTRAINT] += report[4]
            control.statistics[_PROGRAM_STAT_ENERGY] += report[5]
        end
    end
end

function _enqueue_program_bank_publication!(state, report, bank, committed_mcs)
    backend = KernelAbstractions.get_backend(state.ownership)
    _publish_program_bank_kernel!(backend, 1)(
        state.lifecycle_workspace,
        state.lifecycle_control,
        report,
        Int32(bank),
        Int32(committed_mcs);
        ndrange = 1,
    )
    return state
end

@inline function _lifecycle_backend_status(
        code::LifecycleStatusCode;
        mcs::Int32 = Int32(0),
        stage::LifecycleExecutionStage = LifecycleStageNone,
        source::Int32 = Int32(0),
        action_identity::UInt64 = UInt64(0),
        secondary_source::Int32 = Int32(0),
        anchor::Int32 = Int32(0),
        detail::LifecycleStatusDetailCode = LifecycleDetailNone,
        required::Int32 = Int32(0),
        available::Int32 = Int32(0),
        maximum::Int32 = Int32(0),
    )
    return LifecycleStatusPayload(
        code,
        mcs,
        stage,
        source,
        action_identity,
        secondary_source,
        anchor,
        detail,
        required,
        available,
        maximum,
    )
end

@inline function _lifecycle_backend_due(control)
    return @inbounds control.counters[_LIFECYCLE_CONTROL_DUE] != Int32(0)
end

@inline function _lifecycle_failure_descriptor(plan, workspace, status)
    if status.source > 0
        for descriptor in plan.descriptors
            descriptor.source_handle == status.source && return descriptor
        end
    end
    count = Int(lifecycle_request_count(workspace))
    for position in 1:count
        request = Int(@inbounds workspace.canonical_order[position])
        descriptor_index = Int(@inbounds workspace.descriptor[request])
        1 <= descriptor_index <= length(plan.descriptors) || continue
        descriptor = @inbounds plan.descriptors[descriptor_index]
        status.anchor == 0 || @inbounds(workspace.anchor[request]) == status.anchor ||
            continue
        return descriptor
    end
    return nothing
end

@kernel function _stamp_lifecycle_failure_kernel!(
        plan, workspace, next_mcs::Int32, stage::LifecycleExecutionStage
    )
    index = @index(Global, Linear)
    if index == 1
        status = @inbounds workspace.status[1]
        if status.code !== LifecycleStatusSuccess && status.mcs == 0
            descriptor = _lifecycle_failure_descriptor(
                plan, workspace, status
            )
            source = descriptor === nothing ? status.source :
                     descriptor.source_handle
            action_identity = descriptor === nothing ? status.action_identity :
                              descriptor.action_identity
            @inbounds workspace.status[1] = LifecycleStatusPayload(
                status.code,
                next_mcs,
                stage,
                source,
                action_identity,
                status.secondary_source,
                status.anchor,
                status.detail,
                status.required,
                status.available,
                status.maximum,
            )
        end
    end
end

function _enqueue_lifecycle_failure_stamp!(state, stage)
    backend = KernelAbstractions.get_backend(state.ownership)
    _stamp_lifecycle_failure_kernel!(backend, 1)(
        state.program.lifecycle_plan,
        state.lifecycle_workspace,
        Int32(state.mcs + 1),
        stage;
        ndrange = 1,
    )
    return nothing
end

@kernel function _reset_lifecycle_backend_kernel!(
        plan, workspace, control, next_mcs
    )
    index = @index(Global, Linear)
    success = LifecycleStatusPayload()
    open = _lifecycle_backend_open(workspace)
    open && index <= length(control.candidate_status) &&
        (@inbounds control.candidate_status[index] = success)
    open && index == 1 && begin
        @inbounds workspace.request_count[1] = Int32(0)
        @inbounds control.counters[_LIFECYCLE_CONTROL_DUE] = Int32(0)
        @inbounds control.counters[_LIFECYCLE_CONTROL_SELECTED] = Int32(0)
        @inbounds control.counters[_LIFECYCLE_CONTROL_RETIRED] = Int32(0)
        due = false
        for descriptor in plan.descriptors
            due |= _lifecycle_due(descriptor, Int(next_mcs))
        end
        @inbounds control.counters[_LIFECYCLE_CONTROL_DUE] = Int32(due)
    end
    open && index <= length(control.site_keys) &&
        (@inbounds control.site_keys[index] = typemax(UInt64))
    open && index <= length(control.request_scan) &&
        (@inbounds control.request_scan[index] = Int32(0))
    open && index <= length(workspace.active) && @inbounds begin
        workspace.active[index] = false
        workspace.selected[index] = false
        workspace.filtered[index] = false
        workspace.filtered_detail[index] = LifecycleDetailNone
        workspace.planned_site_count[index] = Int32(0)
        workspace.allocation[index] = Int32(0)
        workspace.canonical_order[index] = Int32(0)
        workspace.conflict_seen[index] = false
    end
    open && index <= length(workspace.cell_site_starts) && @inbounds begin
        workspace.cell_site_starts[index] = Int32(0)
        workspace.cell_site_counts[index] = Int32(0)
        workspace.cell_site_cursor[index] = Int32(0)
        workspace.free_slots[index] = Int32(0)
        workspace.representative_site[index] = Int32(0)
        workspace.partition_owner[index] = Int32(0)
    end
    open && index <= length(workspace.site_position) && @inbounds begin
        workspace.partition_labels[index] = UInt8(0)
        workspace.partition_scratch[index] = UInt8(0)
        workspace.cell_sites[index] = Int32(0)
        workspace.site_position[index] = Int32(0)
        workspace.site_seen[index] = false
        workspace.site_queue[index] = Int32(0)
    end
end

@kernel function _mark_lifecycle_requests_kernel!(workspace, control)
    request = @index(Global, Linear)
    if request <= length(control.request_scan)
        @inbounds control.request_scan[request] =
            Int32(workspace.active[request])
    end
end

@kernel function _compact_lifecycle_requests_kernel!(workspace, control)
    request = @index(Global, Linear)
    if request <= length(control.request_scan)
        position = @inbounds control.request_scan[request]
        if @inbounds(workspace.active[request])
            @inbounds workspace.canonical_order[position] = Int32(request)
        end
        if request == length(control.request_scan)
            @inbounds workspace.request_count[1] = position
        end
    end
end

@kernel function _sort_lifecycle_backend_kernel!(state, workspace, control)
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        _sort_lifecycle_requests!(
            BackendLifecycleExecution(),
            state,
            state.program.lifecycle_plan,
            workspace,
        )
    end
end


@kernel function _plan_lifecycle_effect_backend_kernel!(
        state, workspace, control, plan_class
    )
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        plan = state.program.lifecycle_plan
        count = Int(lifecycle_request_count(workspace))
        for position in 1:count
            request = Int(@inbounds workspace.canonical_order[position])
            @inbounds workspace.active[request] || continue
            descriptor = @inbounds plan.descriptors[
                Int(workspace.descriptor[request])
            ]
            _lifecycle_plan_matches(descriptor, plan_class) || continue
            request_workspace = _lifecycle_workspace_with_status(
                workspace,
                _LifecycleStatusSlot(
                    control.candidate_status, Int32(request)
                ),
            )
            reason = _plan_lifecycle_request_effect!(
                BackendLifecycleExecution(),
                state,
                plan,
                request_workspace,
                request,
                plan_class,
            )
            _record_lifecycle_planning_reason!(
                workspace,
                request_workspace,
                request,
                descriptor,
                reason,
            )
        end
    end
end

@inline function _record_lifecycle_planning_reason!(
        workspace, request_workspace, request, descriptor, reason
    )
    reason === :status_failure && return nothing
    reason === :ok && return nothing
    if descriptor.on_inadmissible === FilterLifecycleInadmissible
        @inbounds begin
            workspace.active[request] = false
            workspace.filtered[request] = true
            workspace.filtered_detail[request] =
                _lifecycle_detail_code(reason)
        end
    else
        _set_lifecycle_status!(
            request_workspace,
            LifecycleStatusInadmissible;
            source = descriptor.source_handle,
            anchor = @inbounds(workspace.anchor[request]),
            detail = _lifecycle_detail_code(reason),
        )
    end
    return nothing
end

@inline function _lifecycle_request_generation_current(
        state, workspace, request
    )
    anchor = @inbounds workspace.anchor[request]
    generation = @inbounds workspace.generation[request]
    return anchor <= 0 || (
        1 <= anchor <= length(state.cell_kinds) &&
        @inbounds(state.cell_generations[anchor]) == generation &&
        @inbounds(state.cell_kinds[anchor]) != 0
    )
end

@kernel function _plan_lifecycle_division_backend_kernel!(
        state, workspace, control, plan_class
    )
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        plan = state.program.lifecycle_plan
        count = Int(lifecycle_request_count(workspace))
        for position in 1:count
            request = Int(@inbounds workspace.canonical_order[position])
            @inbounds workspace.active[request] || continue
            descriptor = @inbounds plan.descriptors[
                Int(workspace.descriptor[request])
            ]
            _lifecycle_plan_matches(descriptor, plan_class) || continue
            request_workspace = _lifecycle_workspace_with_status(
                workspace,
                _LifecycleStatusSlot(
                    control.candidate_status, Int32(request)
                ),
            )
            reason = if _lifecycle_request_generation_current(
                    state, workspace, request
                )
                _plan_division!(
                    BackendLifecycleExecution(),
                    state,
                    plan,
                    request_workspace,
                    request,
                    descriptor,
                    plan_class.partition,
                    plan_class.side,
                )
            else
                _set_lifecycle_status!(
                    request_workspace,
                    LifecycleStatusStaleGeneration;
                    anchor = @inbounds(workspace.anchor[request]),
                )
                :status_failure
            end
            _record_lifecycle_planning_reason!(
                workspace,
                request_workspace,
                request,
                descriptor,
                reason,
            )
        end
    end
end

@kernel function _validate_lifecycle_division_relationships_backend_kernel!(
        state, workspace, control
    )
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        plan = state.program.lifecycle_plan
        count = Int(lifecycle_request_count(workspace))
        for position in 1:count
            request = Int(@inbounds workspace.canonical_order[position])
            @inbounds workspace.active[request] || continue
            descriptor = @inbounds plan.descriptors[
                Int(workspace.descriptor[request])
            ]
            descriptor.effect === DivideCellLifecycleEffect || continue
            @inbounds(control.candidate_status[request].code) ===
                LifecycleStatusSuccess || continue
            anchor = @inbounds workspace.anchor[request]
            _lifecycle_relationships_admissible(
                state, plan, descriptor, anchor
            ) && continue
            request_workspace = _lifecycle_workspace_with_status(
                workspace,
                _LifecycleStatusSlot(
                    control.candidate_status, Int32(request)
                ),
            )
            _record_lifecycle_planning_reason!(
                workspace,
                request_workspace,
                request,
                descriptor,
                :relationship_policy_rejected,
            )
        end
    end
end

@kernel function _replan_selected_lifecycle_division_backend_kernel!(
        state, workspace, control, plan_class
    )
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        plan = state.program.lifecycle_plan
        selected = Int(@inbounds control.counters[
            _LIFECYCLE_CONTROL_SELECTED
        ])
        for position in 1:selected
            request = Int(@inbounds workspace.canonical_order[position])
            descriptor = @inbounds plan.descriptors[
                Int(workspace.descriptor[request])
            ]
            _lifecycle_plan_matches(descriptor, plan_class) || continue
            request_workspace = _lifecycle_workspace_with_status(
                workspace,
                _LifecycleStatusSlot(
                    control.candidate_status, Int32(request)
                ),
            )
            reason = _plan_division!(
                BackendLifecycleExecution(),
                state,
                plan,
                request_workspace,
                request,
                descriptor,
                plan_class.partition,
                plan_class.side,
            )
            reason === :ok || reason === :status_failure ||
                _set_lifecycle_status!(
                    request_workspace,
                    LifecycleStatusInvariant;
                    source = descriptor.source_handle,
                    anchor = @inbounds(workspace.anchor[request]),
                    detail = _lifecycle_detail_code(reason),
                )
        end
    end
end

@kernel function _clear_selected_division_workspace_backend_kernel!(
        plan, workspace, control
    )
    index = @index(Global, Linear)
    capacity = size(workspace.policy_workspace, 1)
    request = capacity == 0 ? 0 : div(index - 1, capacity) + 1
    slot = capacity == 0 ? 0 : rem(index - 1, capacity) + 1
    if request <= length(workspace.selected) && slot <= capacity &&
            _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control) &&
            @inbounds(workspace.selected[request])
        descriptor = @inbounds plan.descriptors[
            Int(workspace.descriptor[request])
        ]
        descriptor.effect === DivideCellLifecycleEffect &&
            @inbounds(workspace.policy_workspace[slot, request] =
                zero(eltype(workspace.policy_workspace)))
    end
end

@kernel function _reduce_lifecycle_planning_status_kernel!(workspace, control)
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        count = Int(lifecycle_request_count(workspace))
        for position in 1:count
            request = Int(@inbounds workspace.canonical_order[position])
            status = @inbounds control.candidate_status[request]
            if status.code !== LifecycleStatusSuccess
                @inbounds workspace.status[1] = status
                break
            end
        end
    end
end

@kernel function _select_lifecycle_backend_kernel!(state, workspace, control)
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        plan = state.program.lifecycle_plan
        selected = if _resolve_lifecycle_conflicts!(
                state, plan, workspace
            )
            _preflight_lifecycle_capacity!(state, plan, workspace)
        else
            -1
        end
        @inbounds control.counters[_LIFECYCLE_CONTROL_SELECTED] =
            Int32(max(selected, 0))
    end
end

@kernel function _stage_lifecycle_structure_backend_kernel!(
        state, workspace, control, plan_class
    )
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        selected = Int(@inbounds control.counters[
            _LIFECYCLE_CONTROL_SELECTED
        ])
        failed = false
        for position in 1:selected
            if !failed
                request = Int(@inbounds workspace.canonical_order[position])
                descriptor = @inbounds state.program.lifecycle_plan.descriptors[
                    Int(workspace.descriptor[request])
                ]
                _lifecycle_plan_matches(descriptor, plan_class) || continue
                failed = !_stage_lifecycle_effect_base!(
                    BackendLifecycleExecution(),
                    state,
                    state.program.lifecycle_plan,
                    workspace,
                    request,
                    descriptor,
                    plan_class,
                )
            end
        end
    end
end

@kernel function _stage_lifecycle_relationships_backend_kernel!(
        state, workspace, control
    )
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        selected = Int(@inbounds control.counters[
            _LIFECYCLE_CONTROL_SELECTED
        ])
        failed = false
        for position in 1:selected
            if !failed
                request = Int(@inbounds workspace.canonical_order[position])
                failed = !_stage_lifecycle_request_relationships!(
                    BackendLifecycleExecution(),
                    state,
                    state.program.lifecycle_plan,
                    workspace,
                    request,
                )
            end
        end
    end
end

@kernel function _stage_lifecycle_state_backend_kernel!(
        state, workspace, control, plan_class, action
    )
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        selected = Int(@inbounds control.counters[
            _LIFECYCLE_CONTROL_SELECTED
        ])
        failed = false
        for position in 1:selected
            if !failed
                request = Int(@inbounds workspace.canonical_order[position])
                descriptor = @inbounds state.program.lifecycle_plan.descriptors[
                    Int(workspace.descriptor[request])
                ]
                _lifecycle_plan_matches(descriptor, plan_class) || continue
                failed = !_apply_lifecycle_effect_state!(
                    BackendLifecycleExecution(),
                    state,
                    state.program.lifecycle_plan,
                    workspace,
                    request,
                    descriptor,
                    plan_class,
                    action,
                )
            end
        end
    end
end

@kernel function _finalize_lifecycle_effect_backend_kernel!(
        state, workspace, control, plan_class
    )
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        selected = Int(@inbounds control.counters[
            _LIFECYCLE_CONTROL_SELECTED
        ])
        retired = Int32(0)
        for position in 1:selected
            request = Int(@inbounds workspace.canonical_order[position])
            descriptor = @inbounds state.program.lifecycle_plan.descriptors[
                Int(workspace.descriptor[request])
            ]
            _lifecycle_plan_matches(descriptor, plan_class) || continue
            retired += Int32(_finalize_lifecycle_effect!(
                workspace, request, descriptor, plan_class
            ))
        end
        @inbounds control.counters[_LIFECYCLE_CONTROL_RETIRED] += retired
    end
end

@kernel function _validate_lifecycle_backend_kernel!(state, workspace, control)
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control) &&
            @inbounds(control.counters[_LIFECYCLE_CONTROL_SELECTED]) > 0
        _validate_staged_lifecycle!(
            BackendLifecycleExecution(),
            state,
            state.program.lifecycle_plan,
            workspace,
        )
    end
end

@kernel function _finalize_lifecycle_backend_kernel!(workspace, control)
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        @inbounds control.statistics[_PROGRAM_STAT_RETIRED] += UInt64(
            control.counters[_LIFECYCLE_CONTROL_RETIRED]
        )
    end
end

@kernel function _lifecycle_site_key_kernel!(keys, ownership, control, capacity)
    site = @index(Global, Linear)
    if site <= length(ownership) && _lifecycle_backend_due(control)
        owner = @inbounds ownership[site]
        if owner > capacity
            @inbounds control.candidate_status[site] = _lifecycle_backend_status(
                LifecycleStatusInvariant;
                anchor = owner,
                detail = LifecycleDetailOwnershipExceedsCellCapacity,
                maximum = capacity,
            )
        end
        key = if 0 < owner <= capacity
            (UInt64(UInt32(owner)) << 32) | UInt64(UInt32(site))
        else
            typemax(UInt64)
        end
        @inbounds keys[site] = key
    end
end

@kernel function _reduce_lifecycle_status_kernel!(workspace, control, count)
    index = @index(Global, Linear)
    if index == 1 && _lifecycle_backend_open(workspace)
        result = LifecycleStatusPayload()
        found = false
        for candidate in 1:Int(count)
            status = @inbounds control.candidate_status[candidate]
            if !found && status.code !== LifecycleStatusSuccess
                result = status
                found = true
            end
        end
        found && @inbounds(workspace.status[1] = result)
    end
end

@inline function _lifecycle_owner_lower_bound(keys, owner::UInt32)
    target = UInt64(owner) << 32
    lower = 1
    upper = length(keys) + 1
    while lower < upper
        middle = lower + ((upper - lower) >>> 1)
        value = @inbounds keys[middle]
        if value < target
            lower = middle + 1
        else
            upper = middle
        end
    end
    return lower
end

@kernel function _index_lifecycle_sites_kernel!(workspace, control, capacity)
    cell = @index(Global, Linear)
    if cell <= capacity && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        first_position = _lifecycle_owner_lower_bound(
            control.site_keys, UInt32(cell)
        )
        next_position = cell == capacity ?
            _lifecycle_owner_lower_bound(control.site_keys, UInt32(cell) + UInt32(1)) :
            _lifecycle_owner_lower_bound(control.site_keys, UInt32(cell + 1))
        count = next_position - first_position
        @inbounds begin
            workspace.cell_site_starts[cell] = Int32(first_position)
            workspace.cell_site_counts[cell] = Int32(count)
            workspace.cell_site_cursor[cell] = Int32(next_position)
            workspace.representative_site[cell] = count > 0 ?
                Int32(control.site_keys[first_position] & UInt64(typemax(UInt32))) :
                Int32(0)
        end
        for position in first_position:(next_position - 1)
            site = Int(control.site_keys[position] & UInt64(typemax(UInt32)))
            @inbounds begin
                workspace.cell_sites[position] = Int32(site)
                workspace.site_position[site] = Int32(position)
            end
        end
    end
end

@inline function _lifecycle_descriptor_for_request(offsets, request::Int32)
    lower = 1
    upper = length(offsets)
    while lower < upper
        middle = lower + ((upper - lower + 1) >>> 1)
        if @inbounds(offsets[middle]) <= request
            lower = middle
        else
            upper = middle - 1
        end
    end
    return lower
end

@inline function _evaluate_lifecycle_backend(
        plan, evaluator::Int32, context, descriptor, control, slot
    )
    value = evaluate_lifecycle(plan.evaluators, evaluator, context)
    if value isa AbstractFloat && !isfinite(value)
        @inbounds control.candidate_status[slot] = _lifecycle_backend_status(
            LifecycleStatusEvaluator;
            source = descriptor.source_handle,
            anchor = context.anchor,
            detail = LifecycleDetailNonfiniteResult,
        )
        return LifecycleEvaluationFailed()
    end
    return value
end

@inline function _emit_lifecycle_backend_one!(
        request,
        state, workspace, control, next_mcs
    )
    request <= length(workspace.active) || return
    _lifecycle_backend_open(workspace) || return
    descriptor_index = _lifecycle_descriptor_for_request(
        control.request_offsets, Int32(request)
    )
    descriptor = @inbounds state.program.lifecycle_plan.descriptors[
        descriptor_index
    ]
    _lifecycle_due(descriptor, Int(next_mcs)) || return
    first_request = @inbounds control.request_offsets[descriptor_index]
    lane = Int32(request) - first_request + Int32(1)
    anchor = descriptor.domain === ModelLifecycleDomain ? Int32(0) : lane
    descriptor.domain === ModelLifecycleDomain && lane != 1 && return
    if anchor > 0
        kind = @inbounds state.cell_kinds[anchor]
        kind == descriptor.domain_kind || return
    end
    generation = anchor > 0 ? @inbounds(state.cell_generations[anchor]) : UInt32(0)
    if anchor > 0 && iszero(generation)
        @inbounds control.candidate_status[request] = _lifecycle_backend_status(
            LifecycleStatusStaleGeneration; anchor
        )
        return
    end
    context = _LifecycleTriggerContext(
        state,
        descriptor.source_identity,
        descriptor.action_identity,
        descriptor.trigger_workspace_maximum,
        Int32(0),
        Int32(request),
        anchor,
        generation,
        _lifecycle_context_site(state, workspace, anchor),
        Int32(0),
        UInt16(descriptor.source_handle),
    )
    enabled = _evaluate_lifecycle_backend(
        state.program.lifecycle_plan,
        descriptor.trigger_evaluator,
        context,
        descriptor,
        control,
        request,
    )
    enabled isa LifecycleEvaluationFailed && return
    if !(enabled isa Bool)
        @inbounds control.candidate_status[request] = _lifecycle_backend_status(
            LifecycleStatusEvaluator;
            source = descriptor.source_handle,
            anchor,
            detail = LifecycleDetailTriggerNotBoolean,
        )
        return
    end
    enabled || return
    @inbounds begin
        workspace.descriptor[request] = Int32(descriptor_index)
        workspace.anchor[request] = anchor
        workspace.generation[request] = generation
        workspace.occurrence[request] = Int32(0)
        workspace.active[request] = true
    end
end

@kernel function _emit_lifecycle_backend_kernel!(
        state, workspace, control, next_mcs
    )
    request = @index(Global, Linear)
    if request <= length(workspace.active) && _lifecycle_backend_open(workspace) &&
            _lifecycle_backend_due(control)
        _emit_lifecycle_backend_one!(
            request, state, workspace, control, next_mcs
        )
    end
end

function enqueue_lifecycle_backend_index!(
        state;
        workgroup_size::Union{Nothing, Integer} = nothing,
    )
    control = state.lifecycle_control
    control isa NoLifecycleBackendControl && return state
    workspace = state.lifecycle_workspace
    backend = KernelAbstractions.get_backend(state.ownership)
    workgroup_size === nothing || workgroup_size > 0 || throw(ArgumentError(
        "lifecycle workgroup size must be positive"
    ))
    launch(kernel) = workgroup_size === nothing ? kernel(backend) :
                     kernel(backend, Int(workgroup_size))
    reset = launch(_reset_lifecycle_backend_kernel!)
    site_keys = launch(_lifecycle_site_key_kernel!)
    reduce_status = _reduce_lifecycle_status_kernel!(backend, 1)
    index_sites = launch(_index_lifecycle_sites_kernel!)
    emit = launch(_emit_lifecycle_backend_kernel!)
    mark_requests = launch(_mark_lifecycle_requests_kernel!)
    compact_requests = launch(_compact_lifecycle_requests_kernel!)
    sort_requests = _sort_lifecycle_backend_kernel!(backend, 1)
    plan_effect = _plan_lifecycle_effect_backend_kernel!(backend, 1)
    plan_division = _plan_lifecycle_division_backend_kernel!(backend, 1)
    validate_division_relationships =
        _validate_lifecycle_division_relationships_backend_kernel!(backend, 1)
    replan_selected_division =
        _replan_selected_lifecycle_division_backend_kernel!(backend, 1)
    clear_selected_division_workspace =
        launch(_clear_selected_division_workspace_backend_kernel!)
    reduce_planning_status =
        _reduce_lifecycle_planning_status_kernel!(backend, 1)
    select_requests = _select_lifecycle_backend_kernel!(backend, 1)
    stage_structure = _stage_lifecycle_structure_backend_kernel!(backend, 1)
    stage_relationships =
        _stage_lifecycle_relationships_backend_kernel!(backend, 1)
    stage_state = _stage_lifecycle_state_backend_kernel!(backend, 1)
    finalize_effect = _finalize_lifecycle_effect_backend_kernel!(backend, 1)
    validate_requests = _validate_lifecycle_backend_kernel!(backend, 1)
    finalize_requests = _finalize_lifecycle_backend_kernel!(backend, 1)
    @debug "enqueue lifecycle backend stage" stage = :clear_policy_workspace
    AcceleratedKernels.foreachindex(workspace.policy_workspace, backend) do index
        @inbounds workspace.policy_workspace[index] =
            zero(eltype(workspace.policy_workspace))
    end
    @debug "enqueue lifecycle backend stage" stage = :reset
    reset(
        state.program.lifecycle_plan,
        workspace,
        control,
        Int32(state.mcs + 1);
        ndrange = length(control.candidate_status),
    )
    @debug "enqueue lifecycle backend stage" stage = :site_keys
    site_keys(
        control.site_keys,
        state.ownership,
        control,
        Int32(length(state.cell_kinds));
        ndrange = length(state.ownership),
    )
    @debug "enqueue lifecycle backend stage" stage = :sort_site_keys
    AcceleratedKernels.sort!(
        control.site_keys,
        backend;
        temp = control.site_keys_scratch,
    )
    @debug "enqueue lifecycle backend stage" stage = :reduce_site_status
    reduce_status(
        workspace, control, Int32(length(state.ownership)); ndrange = 1
    )
    _enqueue_lifecycle_failure_stamp!(state, LifecycleStageIndex)
    @debug "enqueue lifecycle backend stage" stage = :index_sites
    index_sites(
        workspace,
        control,
        Int32(length(state.cell_kinds));
        ndrange = length(state.cell_kinds),
    )
    @debug "enqueue lifecycle backend stage" stage = :emit_requests
    emit(
        state,
        workspace,
        control,
        Int32(state.mcs + 1);
        ndrange = length(workspace.active),
    )
    @debug "enqueue lifecycle backend stage" stage = :reduce_emission_status
    reduce_status(
        workspace, control, Int32(length(workspace.active)); ndrange = 1
    )
    _enqueue_lifecycle_failure_stamp!(state, LifecycleStageEmission)
    @debug "enqueue lifecycle backend stage" stage = :mark_requests
    mark_requests(
        workspace, control; ndrange = length(control.request_scan)
    )
    @debug "enqueue lifecycle backend stage" stage = :scan_requests
    AcceleratedKernels.accumulate!(
        +,
        control.request_scan,
        backend;
        init = Int32(0),
        temp = control.request_scan_scratch,
        alg = AcceleratedKernels.ScanPrefixes(),
    )
    @debug "enqueue lifecycle backend stage" stage = :compact_requests
    compact_requests(
        workspace, control; ndrange = length(control.request_scan)
    )
    @debug "enqueue lifecycle backend stage" stage = :sort_requests
    sort_requests(state, workspace, control; ndrange = 1)
    effect_mask = state.program.lifecycle_plan.effect_mask
    for plan_class in (
            _CreateLifecyclePlan(),
            _RetireLifecyclePlan(),
            _RemoveLifecyclePlan(),
            _TransitionLifecyclePlan(),
        )
        iszero(
            effect_mask & _lifecycle_effect_bit(
                _lifecycle_plan_effect(plan_class)
            )
        ) && continue
        @debug "enqueue lifecycle effect planner" plan_class
        plan_effect(
            state, workspace, control, plan_class; ndrange = 1
        )
    end
    division_variant_mask = state.program.lifecycle_plan.division_variant_mask
    division_variants = (
            _DivideLifecycleVariantPlan(
                _RandomPlanePartitionPlan(), _CanonicalSidePlan()
            ),
            _DivideLifecycleVariantPlan(
                _RandomPlanePartitionPlan(), _StableRandomSidePlan()
            ),
            _DivideLifecycleVariantPlan(
                _PrincipalMajorPartitionPlan(), _CanonicalSidePlan()
            ),
            _DivideLifecycleVariantPlan(
                _PrincipalMajorPartitionPlan(), _StableRandomSidePlan()
            ),
            _DivideLifecycleVariantPlan(
                _PrincipalMinorPartitionPlan(), _CanonicalSidePlan()
            ),
            _DivideLifecycleVariantPlan(
                _PrincipalMinorPartitionPlan(), _StableRandomSidePlan()
            ),
            _DivideLifecycleVariantPlan(
                _SpecifiedNormalPartitionPlan(), _CanonicalSidePlan()
            ),
            _DivideLifecycleVariantPlan(
                _SpecifiedNormalPartitionPlan(), _StableRandomSidePlan()
            ),
            _DivideLifecycleVariantPlan(
                _ExternalPartitionPlan(), _CanonicalSidePlan()
            ),
            _DivideLifecycleVariantPlan(
                _ExternalPartitionPlan(), _StableRandomSidePlan()
            ),
        )
    for plan_class in division_variants
        iszero(
            division_variant_mask & _lifecycle_division_variant_bit(
                _lifecycle_partition_code(plan_class.partition),
                _lifecycle_side_code(plan_class.side),
            )
        ) && continue
        @debug "enqueue lifecycle division planner" plan_class
        plan_division(
            state, workspace, control, plan_class; ndrange = 1
        )
    end
    @debug "enqueue lifecycle backend stage" stage = :validate_division_relationships
    validate_division_relationships(
        state, workspace, control; ndrange = 1
    )
    @debug "enqueue lifecycle backend stage" stage = :reduce_planning_status
    reduce_planning_status(workspace, control; ndrange = 1)
    _enqueue_lifecycle_failure_stamp!(state, LifecycleStagePlanning)
    @debug "enqueue lifecycle backend stage" stage = :select_requests
    select_requests(state, workspace, control; ndrange = 1)
    _enqueue_lifecycle_failure_stamp!(state, LifecycleStageSelection)
    policy_workspace_length = length(workspace.policy_workspace)
    if policy_workspace_length > 0
        @debug "enqueue lifecycle backend stage" stage = :clear_selected_division_workspace
        clear_selected_division_workspace(
            state.program.lifecycle_plan,
            workspace,
            control;
            ndrange = policy_workspace_length,
        )
    end
    for plan_class in division_variants
        iszero(
            division_variant_mask & _lifecycle_division_variant_bit(
                _lifecycle_partition_code(plan_class.partition),
                _lifecycle_side_code(plan_class.side),
            )
        ) && continue
        @debug "enqueue selected lifecycle division planner" plan_class
        replan_selected_division(
            state, workspace, control, plan_class; ndrange = 1
        )
    end
    @debug "enqueue lifecycle backend stage" stage = :reduce_selected_planning_status
    reduce_planning_status(workspace, control; ndrange = 1)
    _enqueue_lifecycle_failure_stamp!(state, LifecycleStagePlanning)
    staged_state = (
        ownership = workspace.staged_ownership,
        cell_kinds = workspace.staged_cell_kinds,
        cell_generations = workspace.staged_cell_generations,
        trackers = workspace.staged_trackers,
        relationships = workspace.staged_relationships,
        descriptor_state = workspace.staged_descriptor_state,
    )
    @debug "enqueue lifecycle backend stage" stage = :stage_state
    _enqueue_lifecycle_gated_state_copy!(
        staged_state, state, backend, workspace, control
    )
    effect_classes = (
            _CreateLifecyclePlan(),
            _RetireLifecyclePlan(),
            _RemoveLifecyclePlan(),
            _TransitionLifecyclePlan(),
            _DivideLifecyclePlan(),
        )
    for plan_class in effect_classes
        iszero(
            effect_mask & _lifecycle_effect_bit(
                _lifecycle_plan_effect(plan_class)
            )
        ) && continue
        @debug "enqueue lifecycle structural staging" plan_class
        stage_structure(
            state, workspace, control, plan_class; ndrange = 1
        )
    end
    _enqueue_lifecycle_failure_stamp!(state, LifecycleStageStructure)
    @debug "enqueue lifecycle relationship staging"
    stage_relationships(state, workspace, control; ndrange = 1)
    _enqueue_lifecycle_failure_stamp!(state, LifecycleStageRelationships)
    state_action_mask = state.program.lifecycle_plan.state_rules.action_mask
    state_actions = (
        Val(:initialize),
        Val(:retire_to),
        Val(:preserve),
        Val(:reset),
        Val(:transform),
        Val(:copy_daughters),
        Val(:preserve_parent_reset_daughter),
        Val(:reset_both),
        Val(:split_conservatively),
        Val(:transform_daughters),
        Val(:redraw_daughters),
    )
    for action_value in state_actions
        action = _lifecycle_state_action_value(action_value)
        iszero(
            state_action_mask & _lifecycle_state_action_bit(action)
        ) && continue
        for plan_class in effect_classes
            iszero(
                effect_mask & _lifecycle_effect_bit(
                    _lifecycle_plan_effect(plan_class)
                )
            ) && continue
            @debug "enqueue lifecycle state staging" plan_class action
            stage_state(
                state,
                workspace,
                control,
                plan_class,
                action_value;
                ndrange = 1,
            )
        end
    end
    _enqueue_lifecycle_failure_stamp!(state, LifecycleStageState)
    for plan_class in effect_classes
        iszero(
            effect_mask & _lifecycle_effect_bit(
                _lifecycle_plan_effect(plan_class)
            )
        ) && continue
        @debug "enqueue lifecycle effect finalization" plan_class
        finalize_effect(
            state, workspace, control, plan_class; ndrange = 1
        )
    end
    @debug "enqueue lifecycle backend stage" stage = :validate_staged_state
    validate_requests(state, workspace, control; ndrange = 1)
    _enqueue_lifecycle_failure_stamp!(state, LifecycleStageValidation)
    @debug "enqueue lifecycle backend stage" stage = :publish_state
    _enqueue_lifecycle_gated_state_copy!(
        state, staged_state, backend, workspace, control
    )
    @debug "enqueue lifecycle backend stage" stage = :finalize
    finalize_requests(workspace, control; ndrange = 1)
    return state
end

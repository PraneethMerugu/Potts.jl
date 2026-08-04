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
    statistics::U
end

Adapt.@adapt_structure LifecycleBackendControl
Adapt.@adapt_structure NoLifecycleBackendControl

struct _LifecycleStateDescriptorPlan{R}
    domain_resources::R
end

struct _LifecycleStateRelationshipPlan{R}
    relationship_rules::R
end

struct _LifecycleStateProgram{N, TP, D, L}
    shape::NTuple{N, Int}
    periodic::NTuple{N, Bool}
    medium_kind::Int16
    tracker_plan::TP
    descriptor_plan::D
    lifecycle_plan::L
end

struct _LifecycleStateEvaluatorPlan{E, S}
    evaluators::E
    state_rules::S
end

struct _LifecycleStatePolicyWorkspace{P}
    policy_workspace::P
end

struct _LifecycleStateRuntime{
        P, O, K, G, T, R, D, W, A,
    }
    program::P
    ownership::O
    cell_kinds::K
    cell_generations::G
    trackers::T
    relationships::R
    descriptor_state::D
    lifecycle_workspace::W
    parameters::A
    seed::UInt64
    replica::UInt32
    repeat::UInt32
    mcs::Int
end

Adapt.@adapt_structure _LifecycleStateDescriptorPlan
Adapt.@adapt_structure _LifecycleStateRelationshipPlan
Adapt.@adapt_structure _LifecycleStateProgram
Adapt.@adapt_structure _LifecycleStateEvaluatorPlan
Adapt.@adapt_structure _LifecycleStatePolicyWorkspace
Adapt.@adapt_structure _LifecycleStateRuntime

function _lifecycle_state_launch_payload(state, workspace)
    lifecycle = state.program.lifecycle_plan
    program = _LifecycleStateProgram(
        state.program.shape,
        state.program.periodic,
        state.program.medium_kind,
        state.program.tracker_plan,
        _LifecycleStateDescriptorPlan(
            state.program.descriptor_plan.domain_resources
        ),
        _LifecycleStateRelationshipPlan(lifecycle.relationship_rules),
    )
    runtime = _LifecycleStateRuntime(
        program,
        state.ownership,
        state.cell_kinds,
        state.cell_generations,
        state.trackers,
        state.relationships,
        state.descriptor_state,
        _LifecycleStatePolicyWorkspace(workspace.policy_workspace),
        state.parameters,
        state.seed,
        state.replica,
        state.repeat,
        state.mcs,
    )
    plan = _LifecycleStateEvaluatorPlan(
        lifecycle.evaluators, lifecycle.state_rules
    )
    return runtime, lifecycle.descriptors, plan
end

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
        workspace.planned_site_request,
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
        workspace.planned_site_request,
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
    key_capacity = max(1, nextpow(2, max(1, Int(site_count))))
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
            prototype, UInt64, typemax(UInt64), key_capacity
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
        mode === Val(:due) ? open && _lifecycle_backend_due(control) :
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

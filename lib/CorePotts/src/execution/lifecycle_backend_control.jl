# Backend-resident lifecycle transaction control and portable launch storage.

struct NoLifecycleBackendControl{
        C <: AbstractVector{Int32}, U <: AbstractVector{UInt64},
    }
    counters::C
    statistics::U
end

"""Fixed backend storage needed to enqueue one lifecycle transaction without host polling."""
struct LifecycleBackendControl{
        O <: AbstractVector{Int32},
        C <: AbstractVector{Int32},
        S <: AbstractVector{ProgramStatus},
        U <: AbstractVector{UInt64},
        E <: AbstractVector{ProgramStatusCode},
        D <: AbstractVector{ProgramStatusDetailCode},
    }
    request_offsets::O
    counters::C
    candidate_status::S
    state_rule_failure_rank::C
    statistics::U
    emission_status_code::E
    emission_status_detail::D
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
            state.program.domain_resources
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

struct _ProgramStatusSlot{S} <: AbstractVector{ProgramStatus}
    values::S
    slot::Int32
end

struct _LifecycleRankedStatusSlot{S, R} <: AbstractVector{ProgramStatus}
    values::S
    ranks::R
    slot::Int32
    rank::Int32
end

Base.IndexStyle(::Type{<:_LifecycleRankedStatusSlot}) = IndexLinear()
Base.size(::_LifecycleRankedStatusSlot) = (1,)
@inline Base.getindex(status::_LifecycleRankedStatusSlot, index::Integer) =
    @inbounds status.values[Int(status.slot)]
@inline function Base.setindex!(
        status::_LifecycleRankedStatusSlot,
        value::ProgramStatus,
        index::Integer,
    )
    slot = Int(status.slot)
    if value.code !== ProgramStatusSuccess &&
            status.rank < @inbounds(status.ranks[slot])
        @inbounds begin
            status.ranks[slot] = status.rank
            status.values[slot] = value
        end
    end
    return value
end

Base.IndexStyle(::Type{<:_ProgramStatusSlot}) = IndexLinear()
Base.size(::_ProgramStatusSlot) = (1,)
@inline Base.getindex(status::_ProgramStatusSlot, index::Integer) =
    @inbounds status.values[Int(status.slot)]
@inline function Base.setindex!(
        status::_ProgramStatusSlot, value, index::Integer
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
        workspace.planned_sites,
        workspace.partition_labels,
        workspace.partition_scratch,
        workspace.partition_owner,
        workspace.site_index,
        workspace.request_index,
        workspace.selection,
        workspace.planned_site_request,
        workspace.policy_workspace,
        workspace.site_seen,
        workspace.site_queue,
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
        workspace.planned_sites,
        workspace.partition_labels,
        workspace.partition_scratch,
        workspace.partition_owner,
        workspace.site_index,
        workspace.request_index,
        workspace.selection,
        workspace.planned_site_request,
        workspace.policy_workspace,
        workspace.site_seen,
        workspace.site_queue,
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
const _LIFECYCLE_CONTROL_RETIRED = 2
const _LIFECYCLE_CONTROL_ACTIVE_BANK = 3
const _LIFECYCLE_CONTROL_COMMITTED_MCS = 4
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

function _lifecycle_backend_filled(
        prototype, ::Type{ProgramStatus}, value, dimensions...
    )
    host = StructArrays.StructArray(
        fill(convert(ProgramStatus, value), dimensions...)
    )
    return Adapt.adapt(KernelAbstractions.get_backend(prototype), host)
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
    return NoLifecycleBackendControl(
        _lifecycle_backend_filled(prototype, Int32, 0, 4),
        _lifecycle_backend_filled(prototype, UInt64, 0, 6),
    )
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
    counters = _lifecycle_backend_filled(prototype, Int32, 0, 4)
    @inbounds counters[_LIFECYCLE_CONTROL_ACTIVE_BANK] = Int32(1)
    return LifecycleBackendControl(
        _lifecycle_request_offsets(plan),
        counters,
        _lifecycle_backend_filled(
            prototype,
            ProgramStatus,
            ProgramStatus(),
            status_slots,
        ),
        _lifecycle_backend_filled(
            prototype, Int32, typemax(Int32), status_slots
        ),
        _lifecycle_backend_filled(prototype, UInt64, 0, 6),
        _lifecycle_backend_filled(
            prototype,
            ProgramStatusCode,
            ProgramStatusSuccess,
            Int(plan.maximum_requests),
        ),
        _lifecycle_backend_filled(
            prototype,
            ProgramStatusDetailCode,
            LifecycleDetailNone,
            Int(plan.maximum_requests),
        ),
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
    (@inbounds workspace.status[1]).code === ProgramStatusSuccess
@inline _lifecycle_backend_open(::NoLifecycleWorkspace) = true

@inline function _lifecycle_copy_enabled(workspace, control, mode)
    open = _lifecycle_backend_open(workspace)
    return mode === Val(:open) ? open :
        mode === Val(:due) ? open && _lifecycle_backend_due(control) :
        open && _lifecycle_backend_due(control) &&
            _lifecycle_selected_count(workspace) > 0
end

@kernel function _publish_program_bank_kernel!(
        workspace, control, program_status, report, bank::Int32, committed_mcs::Int32
    )
    index = @index(Global, Linear)
    if index == 1 &&
            (@inbounds program_status[1]).code === ProgramStatusSuccess &&
            _lifecycle_backend_open(workspace)
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
        state.program_status,
        report,
        Int32(bank),
        Int32(committed_mcs);
        ndrange = 1,
    )
    return state
end

@inline function _lifecycle_backend_status(
        code::ProgramStatusCode;
        mcs::Int32 = Int32(0),
        stage::ProgramExecutionStage = ProgramStageNone,
        source::Int32 = Int32(0),
        action_identity::UInt64 = UInt64(0),
        secondary_source::Int32 = Int32(0),
        anchor::Int32 = Int32(0),
        detail::ProgramStatusDetailCode = LifecycleDetailNone,
        required::Int32 = Int32(0),
        available::Int32 = Int32(0),
        maximum::Int32 = Int32(0),
    )
    return ProgramStatus(
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
    count = Int(_lifecycle_canonical_request_count(workspace))
    for position in 1:count
        request = Int(_lifecycle_canonical_request_slot(workspace, position))
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
        plan, workspace, next_mcs::Int32, stage::ProgramExecutionStage
    )
    index = @index(Global, Linear)
    if index == 1
        status = @inbounds workspace.status[1]
        if status.code !== ProgramStatusSuccess && status.mcs == 0
            descriptor = _lifecycle_failure_descriptor(
                plan, workspace, status
            )
            source = descriptor === nothing ? status.source :
                     descriptor.source_handle
            action_identity = descriptor === nothing ? status.action_identity :
                              descriptor.action_identity
            @inbounds workspace.status[1] = ProgramStatus(
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

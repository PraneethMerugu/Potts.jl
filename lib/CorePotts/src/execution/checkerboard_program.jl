# Portable checkerboard candidate, deterministic claim, evaluation, and commit.

const _PROGRAM_CHECKERBOARD_PENDING = UInt8(0)
const _PROGRAM_CHECKERBOARD_NULL = UInt8(1)
const _PROGRAM_CHECKERBOARD_CONFLICT = UInt8(2)
const _PROGRAM_CHECKERBOARD_CONSTRAINT = UInt8(3)
const _PROGRAM_CHECKERBOARD_ENERGY = UInt8(4)
const _PROGRAM_CHECKERBOARD_ACCEPTED = UInt8(5)

struct NoCheckerboardStageBuffers end

struct CheckerboardKernelProgram{T, N, O, R, TP, D, S, H, C}
    shape::NTuple{N, Int}
    periodic::NTuple{N, Bool}
    proposal_offsets::O
    medium_kind::Int16
    temperature::CompiledScalar{T}
    attempts_per_site::Int32
    relationships::R
    tracker_plan::TP
    descriptor_plan::D
    stage_plan::S
    ownership_change_handles::H
    checkerboard_plan::C
end

struct CheckerboardExecutionState{
        P, O, K, G, TS, R, D, W, S, A,
    }
    program::P
    ownership::O
    cell_kinds::K
    cell_generations::G
    trackers::TS
    relationships::R
    descriptor_state::D
    descriptor_workspaces::W
    stage_buffers::S
    parameters::A
    seed::UInt64
    replica::UInt32
    repeat::UInt32
    mcs::Int
end

Adapt.@adapt_structure CheckerboardKernelProgram
Adapt.@adapt_structure CheckerboardExecutionState

struct CheckerboardContributionColumn{
        T <: AbstractFloat,
        A <: AbstractMatrix{ProposalEvaluation{T}},
    } <: AbstractVector{ProposalEvaluation{T}}
    values::A
    column::Int32
    rows::Int32
end

Base.IndexStyle(::Type{<:CheckerboardContributionColumn}) = IndexLinear()
Base.size(column::CheckerboardContributionColumn) = (Int(column.rows),)
Base.length(column::CheckerboardContributionColumn) = Int(column.rows)
@inline Base.getindex(column::CheckerboardContributionColumn, index::Int) =
    @inbounds column.values[index, Int(column.column)]
@inline function Base.setindex!(
        column::CheckerboardContributionColumn, value, index::Int
    )
    @inbounds column.values[index, Int(column.column)] = value
    return value
end
@inline function Base.fill!(
        column::CheckerboardContributionColumn, value
    )
    for index in 1:Int(column.rows)
        @inbounds column.values[index, Int(column.column)] = value
    end
    return column
end

struct CheckerboardWorkspace{
        S, C, E, T, O, N, P, D, M, I, R, Q, U, Z, X,
    }
    state::S
    contributions::C
    accepted_copy_evaluations::E
    target_sites::T
    source_sites::O
    old_owners::N
    new_owners::P
    priorities::D
    semantic_ids::M
    dispositions::I
    cell_max_priority::R
    cell_min_identity::Q
    report::U
    color_sizes::Z
    source_table::X
end

function _checkerboard_kernel_program(program, to)
    ownership_change_handles = if program isa CheckerboardKernelProgram
        program.ownership_change_handles
    else
        Tuple(
            entry.handle
            for entry in program.descriptor_plan.state_layout.entries
            if begin
                lifecycle = entry.schema.lifecycle
                declared = lifecycle isa NamedTuple &&
                           haskey(lifecycle, :declared) ?
                           lifecycle.declared : nothing
                declared === :ClearOnOwnershipChange
            end
        )
    end
    tracker_kernel = to === nothing ?
                     tracker_kernel_plan(program.tracker_plan) :
                     adapt_tracker_kernel_plan(to, program.tracker_plan)
    stage_kernel = stage_kernel_plan(program.stage_plan)
    return CheckerboardKernelProgram(
        program.shape,
        program.periodic,
        to === nothing ? program.proposal_offsets :
        Adapt.adapt(to, program.proposal_offsets),
        program.medium_kind,
        program.temperature,
        program.attempts_per_site,
        to === nothing ? program.relationships :
        Adapt.adapt(to, program.relationships),
        tracker_kernel,
        adapt_descriptor_kernel_plan(to, program.descriptor_plan),
        to === nothing ? stage_kernel : Adapt.adapt(to, stage_kernel),
        to === nothing ? ownership_change_handles :
        Adapt.adapt(to, ownership_change_handles),
        to === nothing ? program.checkerboard_plan :
        Adapt.adapt(to, program.checkerboard_plan),
    )
end

_checkerboard_adapt(to, value) =
    to === nothing ? value : Adapt.adapt(to, value)

function _checkerboard_execution_state(
        program,
        ownership,
        cell_kinds,
        cell_generations,
        trackers,
        relationships,
        descriptor_state,
        stage_buffers,
        parameters,
        seed,
        replica,
        repeat,
        to = nothing,
    )
    descriptor_workspaces = allocate_runtime_workspaces(
        program.descriptor_plan.workspace_layout
    )
    return CheckerboardExecutionState(
        _checkerboard_kernel_program(program, to),
        _checkerboard_adapt(to, ownership),
        _checkerboard_adapt(to, cell_kinds),
        _checkerboard_adapt(to, cell_generations),
        _checkerboard_adapt(to, trackers),
        _checkerboard_adapt(to, relationships),
        _checkerboard_adapt(to, descriptor_state),
        _checkerboard_adapt(to, descriptor_workspaces),
        _checkerboard_adapt(to, stage_buffers),
        _checkerboard_adapt(to, parameters),
        UInt64(seed),
        UInt32(replica),
        UInt32(repeat),
        0,
    )
end

function _checkerboard_state_at_mcs(state::CheckerboardExecutionState, mcs)
    return CheckerboardExecutionState(
        state.program,
        state.ownership,
        state.cell_kinds,
        state.cell_generations,
        state.trackers,
        state.relationships,
        state.descriptor_state,
        state.descriptor_workspaces,
        state.stage_buffers,
        state.parameters,
        state.seed,
        state.replica,
        state.repeat,
        Int(mcs),
    )
end

function _checkerboard_similar(prototype, ::Type{T}, dimensions...) where {T}
    values = similar(prototype, T, dimensions...)
    return values
end

function _checkerboard_color_sizes(plan::CheckerboardPlan)
    return Int32[
        plan.color_offsets[color + 1] - plan.color_offsets[color]
        for color in 1:Int(plan.color_count)
    ]
end

function _allocate_checkerboard_workspace(
        state::CheckerboardExecutionState;
        color_sizes = _checkerboard_color_sizes(
            state.program.checkerboard_plan
        ),
        source_table = (),
    )
    plan = state.program.checkerboard_plan
    plan isa CheckerboardPlan || error(
        "checkerboard workspace requires a realized-domain plan"
    )
    maximum_batch = Int(plan.maximum_color_size) *
                    Int(state.program.attempts_per_site)
    maximum_batch > 0 || error("checkerboard schedule has no candidates")
    source_count = _descriptor_source_count(state.program.descriptor_plan)
    contribution_rows = max(1, source_count)
    neutral = _neutral_proposal_evaluation(eltype(state.parameters))
    contributions = _checkerboard_similar(
        state.parameters,
        typeof(neutral),
        contribution_rows,
        maximum_batch,
    )
    fill!(contributions, neutral)
    accepted_copy_evaluations = _checkerboard_similar(
        state.parameters,
        StageEvaluation{eltype(state.parameters)},
        max(1, Int(state.program.stage_plan.accepted_count)),
        maximum_batch,
    )
    fill!(
        accepted_copy_evaluations,
        StageEvaluation(false, zero(eltype(state.parameters))),
    )
    target_sites = _checkerboard_similar(
        state.parameters, Int32, maximum_batch
    )
    source_sites = similar(target_sites)
    old_owners = similar(target_sites)
    new_owners = similar(target_sites)
    priorities = _checkerboard_similar(
        state.parameters, UInt32, maximum_batch
    )
    semantic_ids = _checkerboard_similar(
        state.parameters, Int32, maximum_batch
    )
    dispositions = _checkerboard_similar(
        state.parameters, UInt8, maximum_batch
    )
    cell_max_priority = _checkerboard_similar(
        state.parameters, UInt32, length(state.cell_kinds)
    )
    cell_min_identity = similar(cell_max_priority)
    report = _checkerboard_similar(state.parameters, UInt64, 5)
    return CheckerboardWorkspace(
        state,
        contributions,
        accepted_copy_evaluations,
        target_sites,
        source_sites,
        old_owners,
        new_owners,
        priorities,
        semantic_ids,
        dispositions,
        cell_max_priority,
        cell_min_identity,
        report,
        color_sizes,
        source_table,
    )
end

function allocate_program_engine_workspace(
        program,
        ownership,
        cell_kinds,
        cell_generations,
        trackers,
        relationships,
        descriptor_state,
        stage_buffers,
        parameters,
        seed,
        replica,
        repeat,
    )
    program.engine isa CheckerboardProgramEngine || return nothing
    state = _checkerboard_execution_state(
        program,
        ownership,
        cell_kinds,
        cell_generations,
        trackers,
        relationships,
        descriptor_state,
        stage_buffers,
        parameters,
        seed,
        replica,
        repeat,
    )
    return _allocate_checkerboard_workspace(
        state; source_table = program.descriptor_plan.source_table
    )
end

function _validate_gpu_descriptor_plan(
        plan::AbstractDescriptorEvaluationPlan, source_table
    )
    for group in plan.groups
        for descriptor in group.launch.instances
            support = descriptor_support(descriptor)
            support isa DescriptorSupport || throw(ArgumentError(
                "descriptor support must be a DescriptorSupport value"
            ))
            source_handle = Int(descriptor_source_handle(descriptor))
            qualified_source = 1 <= source_handle <= length(source_table) ?
                repr(source_table[source_handle]) :
                "<missing qualified source for handle $source_handle>"
            support.gpu || throw(ArgumentError(
                "descriptor source $qualified_source " *
                "does not declare GPU support (reason code " *
                "$(support.reason_code))"
            ))
        end
    end
    return nothing
end

function adapt_checkerboard_workspace(to, workspace::CheckerboardWorkspace)
    state = workspace.state
    state.program.stage_plan.accepted_count == 0 || throw(ArgumentError(
        "accepted-copy checkerboard stages are not qualified on device backends"
    ))
    isempty(state.program.stage_plan.after_mcs) || throw(ArgumentError(
        "after-MCS checkerboard stages are not qualified on device backends"
    ))
    isempty(state.program.ownership_change_handles) || throw(ArgumentError(
        "ownership-cleared checkerboard state is not qualified on device backends"
    ))
    _validate_gpu_descriptor_plan(
        state.program.descriptor_plan, workspace.source_table
    )
    adapted = CheckerboardExecutionState(
        _checkerboard_kernel_program(state.program, to),
        Adapt.adapt(to, state.ownership),
        Adapt.adapt(to, state.cell_kinds),
        Adapt.adapt(to, state.cell_generations),
        Adapt.adapt(to, state.trackers),
        Adapt.adapt(to, state.relationships),
        Adapt.adapt(to, state.descriptor_state),
        Adapt.adapt(to, state.descriptor_workspaces),
        NoCheckerboardStageBuffers(),
        Adapt.adapt(to, state.parameters),
        state.seed,
        state.replica,
        state.repeat,
        state.mcs,
    )
    return _allocate_checkerboard_workspace(
        adapted;
        color_sizes = workspace.color_sizes,
        source_table = workspace.source_table,
    )
end

include("checkerboard_kernels.jl")

function _clear_checkerboard_bulk!(workspace::CheckerboardWorkspace)
    maximums = workspace.cell_max_priority
    identities = workspace.cell_min_identity
    backend = KernelAbstractions.get_backend(maximums)
    AcceleratedKernels.foreachindex(maximums, backend) do index
        @inbounds begin
            maximums[index] = UInt32(0)
            identities[index] = typemax(UInt32)
        end
    end
    report = workspace.report
    report_backend = KernelAbstractions.get_backend(report)
    AcceleratedKernels.foreachindex(report, report_backend) do index
        @inbounds report[index] = UInt64(0)
    end
    KernelAbstractions.synchronize(backend)
    report_backend == backend || KernelAbstractions.synchronize(report_backend)
    return nothing
end

function _checkerboard_requires_accepted_commit(state)
    state.program.stage_plan.accepted_count > 0 && return true
    return !isempty(state.program.ownership_change_handles)
end

@inline function _checkerboard_proposal_context(state, workspace, candidate, color)
    target = CartesianIndices(state.ownership)[Int(
        @inbounds workspace.target_sites[candidate]
    )]
    source = CartesianIndices(state.ownership)[Int(
        @inbounds workspace.source_sites[candidate]
    )]
    return _ProposalEvaluationContext(
        state,
        source,
        target,
        @inbounds(workspace.old_owners[candidate]),
        @inbounds(workspace.new_owners[candidate]),
        Int(@inbounds(workspace.semantic_ids[candidate])),
        Int(color),
    )
end

@inline function _store_checkerboard_stage_evaluations!(
        storage, ::Tuple{}, requests, candidate
    )
    return storage
end

@inline function _store_checkerboard_stage_evaluations!(
        storage, groups::Tuple, requests, candidate
    )
    for descriptor in first(groups).instances
        slot = Int(descriptor.buffer_slot)
        @inbounds storage[slot, candidate] = requests[slot]
    end
    return _store_checkerboard_stage_evaluations!(
        storage, Base.tail(groups), requests, candidate
    )
end

function _prepare_checkerboard_accepted_stage!(
        workspace::CheckerboardWorkspace,
        state,
        color::Integer,
        batch_size::Integer,
    )
    buffers = state.stage_buffers
    _reset_relationship_transactions!(
        buffers.relationship_transactions, state.relationships
    )
    for candidate in 1:batch_size
        @inbounds(workspace.dispositions[candidate]) ==
            _PROGRAM_CHECKERBOARD_ACCEPTED || continue
        context = _checkerboard_proposal_context(
            state, workspace, candidate, color
        )
        _emit_accepted_copy_groups!(
            buffers.accepted_copy,
            state.program.stage_plan.accepted_copy,
            context,
        )
        _store_checkerboard_stage_evaluations!(
            workspace.accepted_copy_evaluations,
            state.program.stage_plan.accepted_copy,
            buffers.accepted_copy,
            candidate,
        )
    end
    _prepare_relationship_transactions!(
        buffers.relationship_transactions,
        state.cell_kinds,
        state.cell_generations,
        state.program.relationships,
    )
    return nothing
end

@inline function _apply_checkerboard_accepted_groups!(
        runtime, ::Tuple{}, evaluations, candidate, context
    )
    return runtime
end

@inline function _apply_checkerboard_accepted_groups!(
        runtime, groups::Tuple, evaluations, candidate, context
    )
    for descriptor in first(groups).instances
        evaluation = @inbounds evaluations[
            Int(descriptor.buffer_slot), candidate
        ]
        descriptor_apply_stage!(descriptor, evaluation, runtime, context)
    end
    return _apply_checkerboard_accepted_groups!(
        runtime,
        Base.tail(groups),
        evaluations,
        candidate,
        context,
    )
end

function _publish_checkerboard_accepted_stage!(
        workspace::CheckerboardWorkspace,
        state,
        color::Integer,
        batch_size::Integer,
    )
    for candidate in 1:batch_size
        @inbounds(workspace.dispositions[candidate]) ==
            _PROGRAM_CHECKERBOARD_ACCEPTED || continue
        context = _checkerboard_proposal_context(
            state, workspace, candidate, color
        )
        _clear_ownership_changed_handles!(
            state.program.ownership_change_handles,
            state.descriptor_state,
            context.target,
        )
        _apply_checkerboard_accepted_groups!(
            state,
            state.program.stage_plan.accepted_copy,
            workspace.accepted_copy_evaluations,
            candidate,
            context,
        )
    end
    _publish_relationship_transactions!(
        state.relationships,
        state.stage_buffers.relationship_transactions,
    )
    return nothing
end

function execute_checkerboard_mcs!(
        workspace::CheckerboardWorkspace,
        mcs::Integer = workspace.state.mcs,
        ;
        workgroup_size::Union{Nothing, Integer} = nothing,
    )
    state = _checkerboard_state_at_mcs(workspace.state, mcs)
    plan = state.program.checkerboard_plan
    backend = KernelAbstractions.get_backend(workspace.dispositions)
    staged_commit = _checkerboard_requires_accepted_commit(state)
    staged_commit && !(backend isa KernelAbstractions.CPU) && throw(
        ArgumentError(
            "accepted-copy checkerboard stages are not qualified on this backend"
        )
    )
    _clear_checkerboard_bulk!(workspace)
    workgroup_size === nothing || workgroup_size > 0 || throw(ArgumentError(
        "checkerboard workgroup size must be positive"
    ))
    launch(kernel) = workgroup_size === nothing ? kernel(backend) :
                     kernel(backend, Int(workgroup_size))
    candidate_kernel = launch(_checkerboard_candidates_kernel!)
    claim_priority_kernel = launch(_checkerboard_claim_priorities_kernel!)
    claim_identity_kernel = launch(_checkerboard_claim_identities_kernel!)
    select_kernel = launch(_checkerboard_select_kernel!)
    evaluate_kernel = launch(_checkerboard_evaluate_kernel!)
    commit_kernel = launch(_checkerboard_commit_kernel!)
    report_kernel = _checkerboard_report_kernel!(backend)
    # Attempts-per-site are semantic sweep rounds. Finish every color in one
    # round before constructing candidates for the next round so a target is
    # never represented by multiple concurrent candidates and later rounds
    # observe the committed state of earlier rounds.
    for attempt_round in 1:Int(state.program.attempts_per_site)
        for color in 1:Int(plan.color_count)
            color_size = Int(@inbounds workspace.color_sizes[color])
            batch_size = color_size
            candidate_kernel(
                workspace.target_sites,
                workspace.source_sites,
                workspace.old_owners,
                workspace.new_owners,
                workspace.priorities,
                workspace.semantic_ids,
                workspace.dispositions,
                state,
                Int32(color),
                Int32(attempt_round);
                ndrange = batch_size,
            )
            KernelAbstractions.synchronize(backend)
            evaluate_kernel(
                workspace.contributions,
                workspace.target_sites,
                workspace.source_sites,
                workspace.old_owners,
                workspace.new_owners,
                workspace.semantic_ids,
                workspace.dispositions,
                state,
                Int32(color),
                Int32(batch_size);
                ndrange = batch_size,
            )
            KernelAbstractions.synchronize(backend)
            _clear_checkerboard_claims!(workspace)
            claim_priority_kernel(
                workspace.old_owners,
                workspace.new_owners,
                workspace.priorities,
                workspace.dispositions,
                workspace.cell_max_priority,
                Int32(batch_size);
                ndrange = batch_size,
            )
            KernelAbstractions.synchronize(backend)
            claim_identity_kernel(
                workspace.old_owners,
                workspace.new_owners,
                workspace.priorities,
                workspace.semantic_ids,
                workspace.dispositions,
                workspace.cell_max_priority,
                workspace.cell_min_identity,
                Int32(batch_size);
                ndrange = batch_size,
            )
            KernelAbstractions.synchronize(backend)
            select_kernel(
                workspace.old_owners,
                workspace.new_owners,
                workspace.priorities,
                workspace.semantic_ids,
                workspace.dispositions,
                workspace.cell_max_priority,
                workspace.cell_min_identity,
                Int32(batch_size);
                ndrange = batch_size,
            )
            KernelAbstractions.synchronize(backend)
            staged_commit && _prepare_checkerboard_accepted_stage!(
                workspace, state, color, batch_size
            )
            commit_kernel(
                workspace.target_sites,
                workspace.old_owners,
                workspace.new_owners,
                workspace.dispositions,
                state,
                Int32(batch_size);
                ndrange = batch_size,
            )
            KernelAbstractions.synchronize(backend)
            staged_commit && _publish_checkerboard_accepted_stage!(
                workspace, state, color, batch_size
            )
            report_kernel(
                workspace.report,
                workspace.dispositions,
                Int32(batch_size);
                ndrange = 1,
            )
            KernelAbstractions.synchronize(backend)
        end
    end
    return workspace
end

function _clear_checkerboard_claims!(workspace::CheckerboardWorkspace)
    maximums = workspace.cell_max_priority
    identities = workspace.cell_min_identity
    backend = KernelAbstractions.get_backend(maximums)
    AcceleratedKernels.foreachindex(maximums, backend) do index
        @inbounds begin
            maximums[index] = UInt32(0)
            identities[index] = typemax(UInt32)
        end
    end
    KernelAbstractions.synchronize(backend)
    return nothing
end

function _checkerboard_report(workspace::CheckerboardWorkspace, to_host = Array)
    values = to_host(workspace.report)
    return (
        accepted = Int(values[1]),
        rejected = Int(values[2]),
        null_attempts = Int(values[3]),
        constraint_rejections = Int(values[4]),
        energy_rejections = Int(values[5]),
    )
end

function copy_checkerboard_state!(runtime, workspace, to_host = Array)
    copyto!(runtime.ownership, to_host(workspace.state.ownership))
    copyto_tracker_state!(
        runtime.trackers, workspace.state.trackers, to_host
    )
    report = _checkerboard_report(workspace, to_host)
    runtime.accepted += report.accepted
    runtime.rejected += report.rejected
    runtime.null_attempts += report.null_attempts
    runtime.constraint_rejections += report.constraint_rejections
    runtime.energy_rejections += report.energy_rejections
    return runtime
end

function _advance_checkerboard!(runtime::ProgramRuntime)
    workspace = runtime.engine_workspace
    workspace isa CheckerboardWorkspace || error(
        "checkerboard runtime has no portable execution workspace"
    )
    execute_checkerboard_mcs!(workspace, runtime.mcs)
    report = _checkerboard_report(workspace, identity)
    runtime.accepted += report.accepted
    runtime.rejected += report.rejected
    runtime.null_attempts += report.null_attempts
    runtime.constraint_rejections += report.constraint_rejections
    runtime.energy_rejections += report.energy_rejections
    return nothing
end

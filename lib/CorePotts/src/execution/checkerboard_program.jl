# Portable checkerboard candidate, deterministic claim, evaluation, and commit.

const _PROGRAM_CHECKERBOARD_PENDING = UInt8(0)
const _PROGRAM_CHECKERBOARD_NULL = UInt8(1)
const _PROGRAM_CHECKERBOARD_CONFLICT = UInt8(2)
const _PROGRAM_CHECKERBOARD_CONSTRAINT = UInt8(3)
const _PROGRAM_CHECKERBOARD_ENERGY = UInt8(4)
const _PROGRAM_CHECKERBOARD_ACCEPTED = UInt8(5)

struct CheckerboardKernelProgram{T, N, O, D, C}
    shape::NTuple{N, Int}
    periodic::NTuple{N, Bool}
    proposal_offsets::O
    medium_kind::Int16
    temperature::CompiledScalar{T}
    attempts_per_site::Int32
    descriptor_plan::D
    checkerboard_plan::C
end

struct CheckerboardExecutionState{
        P, O, K, G, V, R, D, W, A,
    }
    program::P
    ownership::O
    cell_kinds::K
    cell_generations::G
    volumes::V
    relationships::R
    descriptor_state::D
    descriptor_workspaces::W
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
        S, C, T, O, N, P, D, M, I, R, Q, U, Z,
    }
    state::S
    contributions::C
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
end

function _checkerboard_kernel_program(program, to)
    return CheckerboardKernelProgram(
        program.shape,
        program.periodic,
        to === nothing ? program.proposal_offsets :
        Adapt.adapt(to, program.proposal_offsets),
        program.medium_kind,
        program.temperature,
        program.attempts_per_site,
        adapt_descriptor_kernel_plan(to, program.descriptor_plan),
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
        volumes,
        relationships,
        descriptor_state,
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
        _checkerboard_adapt(to, volumes),
        _checkerboard_adapt(to, relationships),
        _checkerboard_adapt(to, descriptor_state),
        _checkerboard_adapt(to, descriptor_workspaces),
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
        state.volumes,
        state.relationships,
        state.descriptor_state,
        state.descriptor_workspaces,
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
    )
end

function allocate_program_engine_workspace(
        program,
        ownership,
        cell_kinds,
        cell_generations,
        volumes,
        relationships,
        descriptor_state,
        parameters,
        seed,
        replica,
        repeat,
    )
    program.engine isa CheckerboardProgramEngine || return nothing
    program.stage_plan.accepted_count == 0 || throw(ArgumentError(
        "G4 checkerboard execution does not yet admit accepted-copy stages"
    ))
    program.stage_plan.after_mcs_count == 0 || throw(ArgumentError(
        "G4 checkerboard execution does not yet admit after-MCS stages"
    ))
    all(program.descriptor_plan.state_layout.entries) do entry
        lifecycle = entry.schema.lifecycle
        declared = lifecycle isa NamedTuple && haskey(lifecycle, :declared) ?
                   lifecycle.declared : nothing
        declared !== :ClearOnOwnershipChange
    end || throw(ArgumentError(
        "G4 checkerboard execution does not yet admit ownership-cleared auxiliary state"
    ))
    state = _checkerboard_execution_state(
        program,
        ownership,
        cell_kinds,
        cell_generations,
        volumes,
        relationships,
        descriptor_state,
        parameters,
        seed,
        replica,
        repeat,
    )
    return _allocate_checkerboard_workspace(state)
end

function adapt_checkerboard_workspace(to, workspace::CheckerboardWorkspace)
    state = workspace.state
    adapted = CheckerboardExecutionState(
        _checkerboard_kernel_program(state.program, to),
        Adapt.adapt(to, state.ownership),
        Adapt.adapt(to, state.cell_kinds),
        Adapt.adapt(to, state.cell_generations),
        Adapt.adapt(to, state.volumes),
        Adapt.adapt(to, state.relationships),
        Adapt.adapt(to, state.descriptor_state),
        Adapt.adapt(to, state.descriptor_workspaces),
        Adapt.adapt(to, state.parameters),
        state.seed,
        state.replica,
        state.repeat,
        state.mcs,
    )
    return _allocate_checkerboard_workspace(
        adapted; color_sizes = workspace.color_sizes
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

function execute_checkerboard_mcs!(
        workspace::CheckerboardWorkspace,
        mcs::Integer = workspace.state.mcs,
    )
    state = _checkerboard_state_at_mcs(workspace.state, mcs)
    plan = state.program.checkerboard_plan
    backend = KernelAbstractions.get_backend(workspace.dispositions)
    _clear_checkerboard_bulk!(workspace)
    maximum_batch = length(workspace.dispositions)
    candidate_kernel = _checkerboard_candidates_kernel!(backend)
    claim_priority_kernel = _checkerboard_claim_priorities_kernel!(backend)
    claim_identity_kernel = _checkerboard_claim_identities_kernel!(backend)
    select_kernel = _checkerboard_select_kernel!(backend)
    evaluate_kernel = _checkerboard_evaluate_kernel!(backend)
    commit_kernel = _checkerboard_commit_kernel!(backend)
    report_kernel = _checkerboard_report_kernel!(backend)
    for color in 1:Int(plan.color_count)
        color_size = Int(@inbounds workspace.color_sizes[color])
        batch_size = color_size * Int(state.program.attempts_per_site)
        candidate_kernel(
            workspace.target_sites,
            workspace.source_sites,
            workspace.old_owners,
            workspace.new_owners,
            workspace.priorities,
            workspace.semantic_ids,
            workspace.dispositions,
            state,
            Int32(color);
            ndrange = maximum_batch,
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
            ndrange = maximum_batch,
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
            ndrange = maximum_batch,
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
            ndrange = maximum_batch,
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
            ndrange = maximum_batch,
        )
        KernelAbstractions.synchronize(backend)
        commit_kernel(
            workspace.target_sites,
            workspace.old_owners,
            workspace.new_owners,
            workspace.dispositions,
            state,
            Int32(batch_size);
            ndrange = maximum_batch,
        )
        KernelAbstractions.synchronize(backend)
        report_kernel(
            workspace.report,
            workspace.dispositions,
            Int32(batch_size);
            ndrange = 1,
        )
        KernelAbstractions.synchronize(backend)
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
    converted_volumes = Int.(to_host(workspace.state.volumes))
    copyto!(runtime.volumes, converted_volumes)
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

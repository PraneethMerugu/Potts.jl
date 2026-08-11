# Portable checkerboard candidate, deterministic claim, evaluation, and commit.

const _PROGRAM_CHECKERBOARD_PENDING = UInt8(0)
const _PROGRAM_CHECKERBOARD_NULL = UInt8(1)
const _PROGRAM_CHECKERBOARD_CONFLICT = UInt8(2)
const _PROGRAM_CHECKERBOARD_CONSTRAINT = UInt8(3)
const _PROGRAM_CHECKERBOARD_ENERGY = UInt8(4)
const _PROGRAM_CHECKERBOARD_ACCEPTED = UInt8(5)
const _PROGRAM_CHECKERBOARD_NONFINITE = UInt8(6)
const _PROGRAM_CHECKERBOARD_ZERO_T_DRIVE = UInt8(7)

struct NoCheckerboardStageBuffers end

mutable struct ProgramExecutionPosition
    submitted_mcs::Int
    drained_mcs::Int
    committed_mcs::Int
    materialized_mcs::Int
    settlement_count::Int
    synchronization_count::Int
    control_transfer_count::Int
    snapshot_transfer_count::Int
    lifecycle_transfer_count::Int
end

ProgramExecutionPosition(initial_mcs::Integer = 0) = ProgramExecutionPosition(
    Int(initial_mcs), Int(initial_mcs), Int(initial_mcs), Int(initial_mcs),
    0, 0, 0, 0, 0,
)

struct CheckerboardKernelProgram{T, N, O, R, TP, D, S, L, H, C}
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
    lifecycle_plan::L
    ownership_change_handles::H
    checkerboard_plan::C
end

struct CheckerboardExecutionState{
        P, O, K, G, TS, R, D, W, S, L, C, PS, A,
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
    lifecycle_workspace::L
    lifecycle_control::C
    program_status::PS
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
        S, C, E, T, O, N, P, D, M, I, R, Q, U, A, Z, CO, X, EP,
    }
    state::S
    alternate_state::S
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
    capability_report::A
    color_sizes::Z
    color_order::CO
    source_table::X
    execution::EP
end

abstract type _AbstractCheckerboardClaimExecution end
struct _DirectCheckerboardClaimExecution <:
       _AbstractCheckerboardClaimExecution end

"""Read-only device projection of the exact Core program/lifecycle open state."""
struct _CheckerboardOpenGate{P, L} <: AbstractVector{Bool}
    program_status::P
    lifecycle_status::L
end

"""Read-only device projection for a checkerboard with no lifecycle workspace."""
struct _CheckerboardNoLifecycleOpenGate{P} <: AbstractVector{Bool}
    program_status::P
end

Base.IndexStyle(::Type{<:_CheckerboardOpenGate}) = IndexLinear()
Base.IndexStyle(::Type{<:_CheckerboardNoLifecycleOpenGate}) = IndexLinear()
Base.size(::_CheckerboardOpenGate) = (1,)
Base.size(::_CheckerboardNoLifecycleOpenGate) = (1,)
Base.length(::_CheckerboardOpenGate) = 1
Base.length(::_CheckerboardNoLifecycleOpenGate) = 1
Base.strides(::_CheckerboardOpenGate) = (1,)
Base.strides(::_CheckerboardNoLifecycleOpenGate) = (1,)

@inline function Base.getindex(gate::_CheckerboardOpenGate, index::Int)
    @boundscheck index == 1 || throw(BoundsError(gate, index))
    return (@inbounds gate.program_status[1]).code === ProgramStatusSuccess &&
           (@inbounds gate.lifecycle_status[1]).code === ProgramStatusSuccess
end

@inline function Base.getindex(
        gate::_CheckerboardNoLifecycleOpenGate, index::Int
    )
    @boundscheck index == 1 || throw(BoundsError(gate, index))
    return (@inbounds gate.program_status[1]).code === ProgramStatusSuccess
end

function KernelAbstractions.get_backend(gate::_CheckerboardOpenGate)
    backend = KernelAbstractions.get_backend(gate.program_status)
    KernelAbstractions.get_backend(gate.lifecycle_status) == backend ||
        throw(ArgumentError(
            "checkerboard open-gate parents belong to different backends"
        ))
    return backend
end


KernelAbstractions.get_backend(gate::_CheckerboardNoLifecycleOpenGate) =
    KernelAbstractions.get_backend(gate.program_status)

function Adapt.adapt_structure(to, gate::_CheckerboardOpenGate)
    return _CheckerboardOpenGate(
        Adapt.adapt(to, gate.program_status),
        Adapt.adapt(to, gate.lifecycle_status),
    )
end

function Adapt.adapt_structure(to, gate::_CheckerboardNoLifecycleOpenGate)
    return _CheckerboardNoLifecycleOpenGate(
        Adapt.adapt(to, gate.program_status)
    )
end

function _checkerboard_open_gate(state::CheckerboardExecutionState)
    workspace = state.lifecycle_workspace
    workspace isa NoLifecycleWorkspace &&
        return _CheckerboardNoLifecycleOpenGate(state.program_status)
    workspace isa LifecycleWorkspace || throw(ArgumentError(
        "checkerboard state has an unsupported lifecycle gate"
    ))
    return _CheckerboardOpenGate(state.program_status, workspace.status)
end

mutable struct _LocalWorksetsTrustedAdapter
    trusted_world::UInt
    run_method::Method
    wait_method::Method
end

function _prepare_localworksets_trusted_adapter()
    run_signature = Tuple{LocalWorksets.PreparedWork, NamedTuple}
    run_method = which(LocalWorksets.run!, run_signature)
    run_method.module === LocalWorksets || throw(ArgumentError(
        "LocalWorksets.run! is not owned by LocalWorksets"
    ))
    wait_signature = Tuple{LocalWorksets.WorkEvent}
    wait_method = which(Base.wait, wait_signature)
    wait_method.module === LocalWorksets || throw(ArgumentError(
        "Base.wait(::LocalWorksets.WorkEvent) is not owned by LocalWorksets"
    ))
    return _LocalWorksetsTrustedAdapter(
        Base.get_world_counter(), run_method, wait_method
    )
end

function _validate_localworksets_trusted_adapter!(
        adapter::_LocalWorksetsTrustedAdapter
    )
    world = Base.get_world_counter()
    world == adapter.trusted_world && return nothing
    which(
        LocalWorksets.run!,
        Tuple{LocalWorksets.PreparedWork, NamedTuple},
    ) === adapter.run_method || throw(ArgumentError(
        "the trusted LocalWorksets.run! adapter changed after preparation"
    ))
    which(
        Base.wait, Tuple{LocalWorksets.WorkEvent}
    ) === adapter.wait_method || throw(ArgumentError(
        "the trusted LocalWorksets WorkEvent wait adapter changed after preparation"
    ))
    adapter.trusted_world = world
    return nothing
end

function _run_localworksets_trusted!(
        adapter::_LocalWorksetsTrustedAdapter,
        prepared::LocalWorksets.PreparedWork,
        submission::NamedTuple,
    )
    invoke(
        _validate_localworksets_trusted_adapter!,
        Tuple{_LocalWorksetsTrustedAdapter},
        adapter,
    )
    return invoke(
        LocalWorksets.run!,
        Tuple{LocalWorksets.PreparedWork, NamedTuple},
        prepared,
        submission,
    )
end

function _wait_localworksets_trusted!(
        adapter::_LocalWorksetsTrustedAdapter,
        event::LocalWorksets.WorkEvent,
    )
    invoke(
        _validate_localworksets_trusted_adapter!,
        Tuple{_LocalWorksetsTrustedAdapter},
        adapter,
    )
    return invoke(
        Base.wait,
        Tuple{LocalWorksets.WorkEvent},
        event,
    )
end

mutable struct _LocalWorksetsCheckerboardWorkspace{W, P, G, A} <:
               _AbstractCheckerboardClaimExecution
    direct::W
    prepared::P
    gates::G
    lease_capacity::Int
    last_event::Union{Nothing, LocalWorksets.WorkEvent}
    execution::ProgramExecutionPosition
    mechanism_identity::Symbol
    trusted_adapter::A
end

function _validate_checkerboard_identity_order(plan::CheckerboardPlan)
    for color in 1:Int(plan.color_count)
        first_index = Int(plan.color_offsets[color])
        stop_index = Int(plan.color_offsets[color + 1]) - 1
        sites = @view plan.sites[first_index:stop_index]
        issorted(sites; lt = <) && all(>(Int32(0)), sites) ||
            throw(ArgumentError(
                "LocalWorksets candidate requires canonical increasing color sites"
            ))
    end
    return nothing
end

function _prepare_localworksets_checkerboard_candidate(
        workspace::CheckerboardWorkspace;
        queue_mcs_capacity::Integer = 12,
        canonical_plan = nothing,
    )
    queue_mcs_capacity >= 12 || throw(ArgumentError(
        "the reviewed LocalWorksets candidate requires capacity for twelve MCSs"
    ))
    state = workspace.state
    state.program.stage_plan.accepted_count == 0 || throw(ArgumentError(
        "accepted-copy checkerboard stages remain on the direct path"
    ))
    state.program.attempts_per_site == 1 || throw(ArgumentError(
        "the LocalWorksets checkerboard candidate admits one attempt per site"
    ))
    plan = state.program.checkerboard_plan
    plan isa CheckerboardPlan || throw(ArgumentError(
        "the LocalWorksets checkerboard candidate requires a realized plan"
    ))
    host_plan = canonical_plan === nothing ? plan : canonical_plan
    host_plan isa CheckerboardPlan || throw(ArgumentError(
        "the LocalWorksets checkerboard candidate requires a host canonical plan"
    ))
    _validate_checkerboard_identity_order(host_plan)
    host_plan.shape == plan.shape &&
        host_plan.periodic == plan.periodic &&
        host_plan.color_count == plan.color_count &&
        host_plan.maximum_color_size == plan.maximum_color_size ||
        throw(ArgumentError(
            "host and adapted checkerboard plan capacities disagree"
        ))
    maximum_batch = Int(plan.maximum_color_size)
    destination_count = length(state.cell_kinds)
    output = LocalWorksets.resolved(
        (:old_owners, :new_owners);
        empty = _PROGRAM_CHECKERBOARD_CONFLICT,
        rank = (
            type = UInt32,
            order = :max,
            lower = UInt32(0),
            upper = typemax(UInt32),
        ),
        tie_break = (
            input_type = Int32,
            type = UInt32,
            order = :min,
            transform = :checked_unsigned,
            proof = :strictly_increasing_active_prefix,
        ),
        capacity = maximum_batch,
        key_type = Int32,
        value_type = UInt8,
        skipped_keys = :nonpositive,
        result = (
            layout = :items,
            selection = :all,
            zero_claim = :selected,
            selected = :preserve,
            ineligible = :preserve,
        ),
    )
    work = LocalWorksets.localwork(
        (
            family = :resolved_conjunctive_selection,
            eligible = _PROGRAM_CHECKERBOARD_ACCEPTED,
        ),
        1:maximum_batch;
        read = (
            key_a = :old_owners,
            key_b = :new_owners,
            rank = :priorities,
            identity = :semantic_ids,
            value = :dispositions,
            gate = :execution_open,
        ),
        outputs = (; dispositions = output),
        active = :active_count,
    )
    topology = (
        item_count = Int32(maximum_batch),
        destination_count = Int32(destination_count),
        epoch = UInt64(1),
    )
    backend = KernelAbstractions.get_backend(workspace.dispositions)
    workplan = LocalWorksets.plan(work, topology; backend)
    gates = (
        _checkerboard_open_gate(workspace.state),
        _checkerboard_open_gate(workspace.alternate_state),
    )
    storage = (
        old_owners = workspace.old_owners,
        new_owners = workspace.new_owners,
        priorities = workspace.priorities,
        semantic_ids = workspace.semantic_ids,
        dispositions = workspace.dispositions,
    )
    lease_capacity = queue_mcs_capacity *
                     Int(state.program.attempts_per_site) *
                     Int(plan.color_count)
    local_workspace = (
        winner_ranks = workspace.cell_max_priority,
        winner_identities = workspace.cell_min_identity,
        leases = Any[nothing for _ in 1:lease_capacity],
    )
    submission = (
        execution_open = LocalWorksets.storage_slot(
            first(gates); access = :read
        ),
        active_count = LocalWorksets.value_slot(
            Int32; bounds = Int32(0):Int32(maximum_batch)
        ),
    )
    prepared = LocalWorksets.prepare(
        workplan, storage; workspace = local_workspace, submission
    )
    return _LocalWorksetsCheckerboardWorkspace(
        workspace,
        prepared,
        gates,
        lease_capacity,
        nothing,
        workspace.execution,
        :corepotts_checkerboard_conjunctive_localworksets_v1,
        _prepare_localworksets_trusted_adapter(),
    )
end

@inline function _checkerboard_state_with_science(
        state,
        ownership,
        cell_kinds,
        cell_generations,
        trackers,
        relationships,
        descriptor_state,
        lifecycle_workspace,
    )
    program_status = lifecycle_workspace isa LifecycleWorkspace ?
                     lifecycle_workspace.status : state.program_status
    return CheckerboardExecutionState(
        state.program,
        ownership,
        cell_kinds,
        cell_generations,
        trackers,
        relationships,
        descriptor_state,
        state.descriptor_workspaces,
        state.stage_buffers,
        lifecycle_workspace,
        state.lifecycle_control,
        program_status,
        state.parameters,
        state.seed,
        state.replica,
        state.repeat,
        state.mcs,
    )
end

function _checkerboard_state_banks(state::CheckerboardExecutionState)
    workspace = state.lifecycle_workspace
    if workspace isa NoLifecycleWorkspace
        alternate = _checkerboard_state_with_science(
            state,
            copy(state.ownership),
            copy(state.cell_kinds),
            copy(state.cell_generations),
            copy_tracker_state(state.trackers),
            copy(state.relationships),
            copy_auxiliary_state(state.descriptor_state),
            NoLifecycleWorkspace(),
        )
        return state, alternate
    end
    primary_workspace = _lifecycle_workspace_with_staged_state(
        workspace, state
    )
    primary = _checkerboard_state_with_science(
        state,
        state.ownership,
        state.cell_kinds,
        state.cell_generations,
        state.trackers,
        state.relationships,
        state.descriptor_state,
        primary_workspace,
    )
    secondary_science = (
        ownership = workspace.staged_ownership,
        cell_kinds = workspace.staged_cell_kinds,
        cell_generations = workspace.staged_cell_generations,
        trackers = workspace.staged_trackers,
        relationships = workspace.staged_relationships,
        descriptor_state = workspace.staged_descriptor_state,
    )
    secondary_workspace = _lifecycle_workspace_with_staged_state(
        workspace, secondary_science
    )
    secondary = _checkerboard_state_with_science(
        state,
        secondary_science.ownership,
        secondary_science.cell_kinds,
        secondary_science.cell_generations,
        secondary_science.trackers,
        secondary_science.relationships,
        secondary_science.descriptor_state,
        secondary_workspace,
    )
    return primary, secondary
end

function _checkerboard_kernel_program(program, to)
    ownership_change_handles = program.ownership_change_handles
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
        to === nothing ? program.lifecycle_plan :
        Adapt.adapt(to, program.lifecycle_plan),
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
        initial_mcs = 0,
        to = nothing,
    )
    descriptor_workspaces = allocate_runtime_workspaces(
        program.descriptor_plan.workspace_layout
    )
    kernel_program = _checkerboard_kernel_program(program, to)
    lifecycle_workspace = allocate_lifecycle_workspace(
        program.lifecycle_plan,
        program,
        ownership,
        cell_kinds,
        cell_generations,
        trackers,
        relationships,
        descriptor_state,
    )
    lifecycle_control = allocate_lifecycle_backend_control(
        program.lifecycle_plan, parameters, length(ownership)
    )
    @inbounds begin
        lifecycle_control.counters[_LIFECYCLE_CONTROL_ACTIVE_BANK] =
            iseven(initial_mcs) ? Int32(1) : Int32(2)
        lifecycle_control.counters[_LIFECYCLE_CONTROL_COMMITTED_MCS] =
            Int32(initial_mcs)
    end
    program_status = if lifecycle_workspace isa LifecycleWorkspace
        lifecycle_workspace.status
    else
        values = similar(parameters, ProgramStatus, 1)
        fill!(values, ProgramStatus())
        values
    end
    return CheckerboardExecutionState(
        kernel_program,
        _checkerboard_adapt(to, ownership),
        _checkerboard_adapt(to, cell_kinds),
        _checkerboard_adapt(to, cell_generations),
        _checkerboard_adapt(to, trackers),
        _checkerboard_adapt(to, relationships),
        _checkerboard_adapt(to, descriptor_state),
        _checkerboard_adapt(to, descriptor_workspaces),
        _checkerboard_adapt(to, stage_buffers),
        _checkerboard_adapt(to, lifecycle_workspace),
        _checkerboard_adapt(to, lifecycle_control),
        _checkerboard_adapt(to, program_status),
        _checkerboard_adapt(to, parameters),
        UInt64(seed),
        UInt32(replica),
        UInt32(repeat),
        Int(initial_mcs),
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
        state.lifecycle_workspace,
        state.lifecycle_control,
        state.program_status,
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

const _CHECKERBOARD_COLOR_ORDER_OPERATION = UInt16(5)

"""Fill one preallocated unbiased semantic-RNG permutation of realized colors."""
function _checkerboard_color_order!(
        order::Vector{Int32}, state, attempt_round::Integer
    )
    color_count = Int(state.program.checkerboard_plan.color_count)
    length(order) == color_count || throw(ArgumentError(
        "checkerboard color-order workspace has the wrong size"
    ))
    0 <= state.mcs < typemax(Int) || throw(ArgumentError(
        "checkerboard MCS is outside the semantic RNG domain"
    ))
    1 <= attempt_round <= typemax(UInt8) || throw(ArgumentError(
        "checkerboard attempt round is outside the semantic RNG domain"
    ))
    for color in 1:color_count
        @inbounds order[color] = Int32(color)
    end
    seed = _trajectory_seed(state.seed, state.replica, state.repeat)
    for position in color_count:-1:2
        address = RNGAddress(
            stream = CheckerboardColorOrderStream,
            mcs = state.mcs + 1,
            subround = attempt_round,
            operation = _CHECKERBOARD_COLOR_ORDER_OPERATION,
            entity_kind = GlobalEntity,
            entity = position,
        )
        selected = Int(bounded_uint(
            Philox4x32x10V1(), seed, address, UInt32(position)
        )) + 1
        @inbounds order[position], order[selected] =
            order[selected], order[position]
    end
    return order
end

function _allocate_checkerboard_workspace(
        state::CheckerboardExecutionState;
        capability_report,
        color_sizes = _checkerboard_color_sizes(
            state.program.checkerboard_plan
        ),
        color_order = collect(
            Int32, 1:Int(state.program.checkerboard_plan.color_count)
        ),
        source_table = (),
        alternate_state = nothing,
        execution = ProgramExecutionPosition(state.mcs),
    )
    if alternate_state === nothing
        state, alternate_state = _checkerboard_state_banks(state)
    end
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
        alternate_state,
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
        capability_report,
        color_sizes,
        color_order,
        source_table,
        execution,
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
        initial_mcs = 0,
    )
    program.engine isa SequentialProgramEngine && return (
        allocate_sequential_transaction_workspace(
            program,
            ownership,
            cell_kinds,
            cell_generations,
            trackers,
            relationships,
            descriptor_state,
        )
    )
    program.engine isa CheckerboardProgramEngine || error(
        "unreachable program engine"
    )
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
        initial_mcs,
    )
    return _allocate_checkerboard_workspace(
        state;
        capability_report = program_capability_report(program),
        source_table = program.descriptor_plan.source_table,
    )
end

function initialize_program_execution_statistics!(
        workspace::CheckerboardWorkspace,
        accepted,
        rejected,
        null_attempts,
        constraint_rejections,
        energy_rejections,
        retired_cells,
    )
    control = workspace.state.lifecycle_control
    values = (
        accepted,
        rejected,
        null_attempts,
        constraint_rejections,
        energy_rejections,
        retired_cells,
    )
    for (index, value) in enumerate(values)
        value >= 0 || throw(ArgumentError(
            "program execution statistics must be nonnegative"
        ))
        @inbounds control.statistics[index] = UInt64(value)
    end
    return workspace
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
    _validate_gpu_descriptor_plan(
        state.program.descriptor_plan, workspace.source_table
    )
    primary_science = (
        ownership = Adapt.adapt(to, state.ownership),
        cell_kinds = Adapt.adapt(to, state.cell_kinds),
        cell_generations = Adapt.adapt(to, state.cell_generations),
        trackers = Adapt.adapt(to, state.trackers),
        relationships = Adapt.adapt(to, state.relationships),
        descriptor_state = Adapt.adapt(to, state.descriptor_state),
    )
    execution = ProgramExecutionPosition(
        workspace.execution.submitted_mcs,
        workspace.execution.drained_mcs,
        workspace.execution.committed_mcs,
        workspace.execution.materialized_mcs,
        workspace.execution.settlement_count,
        workspace.execution.synchronization_count,
        workspace.execution.control_transfer_count,
        workspace.execution.snapshot_transfer_count,
        workspace.execution.lifecycle_transfer_count,
    )
    capability_report = _adapted_program_capability_report(
        workspace.capability_report, to
    )
    if state.lifecycle_workspace isa NoLifecycleWorkspace
        alternate_source = workspace.alternate_state
        program_status = Adapt.adapt(to, state.program_status)
        adapted = CheckerboardExecutionState(
            _checkerboard_kernel_program(state.program, to),
            primary_science.ownership,
            primary_science.cell_kinds,
            primary_science.cell_generations,
            primary_science.trackers,
            primary_science.relationships,
            primary_science.descriptor_state,
            Adapt.adapt(to, state.descriptor_workspaces),
            NoCheckerboardStageBuffers(),
            NoLifecycleWorkspace(),
            Adapt.adapt(to, state.lifecycle_control),
            program_status,
            Adapt.adapt(to, state.parameters),
            state.seed,
            state.replica,
            state.repeat,
            state.mcs,
        )
        alternate = _checkerboard_state_with_science(
            adapted,
            Adapt.adapt(to, alternate_source.ownership),
            Adapt.adapt(to, alternate_source.cell_kinds),
            Adapt.adapt(to, alternate_source.cell_generations),
            Adapt.adapt(to, alternate_source.trackers),
            Adapt.adapt(to, alternate_source.relationships),
            Adapt.adapt(to, alternate_source.descriptor_state),
            NoLifecycleWorkspace(),
        )
        return _allocate_checkerboard_workspace(
            adapted;
            capability_report,
            color_sizes = workspace.color_sizes,
            color_order = copy(workspace.color_order),
            source_table = workspace.source_table,
            alternate_state = alternate,
            execution,
        )
    end
    shared_workspace = Adapt.adapt(
        to,
        _lifecycle_workspace_with_staged_state(
            state.lifecycle_workspace, workspace.alternate_state
        ),
    )
    secondary_science = (
        ownership = shared_workspace.staged_ownership,
        cell_kinds = shared_workspace.staged_cell_kinds,
        cell_generations = shared_workspace.staged_cell_generations,
        trackers = shared_workspace.staged_trackers,
        relationships = shared_workspace.staged_relationships,
        descriptor_state = shared_workspace.staged_descriptor_state,
    )
    primary_workspace = _lifecycle_workspace_with_staged_state(
        shared_workspace, primary_science
    )
    secondary_workspace = _lifecycle_workspace_with_staged_state(
        shared_workspace, secondary_science
    )
    adapted = CheckerboardExecutionState(
        _checkerboard_kernel_program(state.program, to),
        primary_science.ownership,
        primary_science.cell_kinds,
        primary_science.cell_generations,
        primary_science.trackers,
        primary_science.relationships,
        primary_science.descriptor_state,
        Adapt.adapt(to, state.descriptor_workspaces),
        NoCheckerboardStageBuffers(),
        primary_workspace,
        Adapt.adapt(to, state.lifecycle_control),
        primary_workspace.status,
        Adapt.adapt(to, state.parameters),
        state.seed,
        state.replica,
        state.repeat,
        state.mcs,
    )
    alternate = _checkerboard_state_with_science(
        adapted,
        secondary_science.ownership,
        secondary_science.cell_kinds,
        secondary_science.cell_generations,
        secondary_science.trackers,
        secondary_science.relationships,
        secondary_science.descriptor_state,
        secondary_workspace,
    )
    return _allocate_checkerboard_workspace(
        adapted;
        capability_report,
        color_sizes = workspace.color_sizes,
        color_order = copy(workspace.color_order),
        source_table = workspace.source_table,
        alternate_state = alternate,
        execution,
    )
end

include("checkerboard_kernels.jl")

function _clear_checkerboard_bulk!(workspace::CheckerboardWorkspace, state)
    maximums = workspace.cell_max_priority
    identities = workspace.cell_min_identity
    backend = KernelAbstractions.get_backend(maximums)
    report = workspace.report
    report_backend = KernelAbstractions.get_backend(report)
    report_backend == backend || throw(ArgumentError(
        "checkerboard report storage must share the execution backend"
    ))
    _checkerboard_clear_mcs_kernel!(backend)(
        maximums,
        identities,
        report,
        state;
        ndrange = max(length(maximums), length(report)),
    )
    return nothing
end

function _checkerboard_requires_accepted_commit(state)
    return state.program.stage_plan.accepted_count > 0
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

function _prepare_checkerboard_claim_runtime(
        ::_DirectCheckerboardClaimExecution, backend, launch
    )
    return (
        priority = launch(_checkerboard_claim_priorities_kernel!),
        identity = launch(_checkerboard_claim_identities_kernel!),
        select = launch(_checkerboard_select_kernel!),
    )
end

_prepare_checkerboard_claim_runtime(
    ::_LocalWorksetsCheckerboardWorkspace, backend, launch
) = nothing

function _execute_checkerboard_claim_block!(
        ::_DirectCheckerboardClaimExecution,
        runtime,
        workspace,
        state,
        batch_size,
    )
    _clear_checkerboard_claims!(workspace, state)
    runtime.priority(
        workspace.old_owners,
        workspace.new_owners,
        workspace.priorities,
        workspace.dispositions,
        workspace.cell_max_priority,
        state,
        Int32(batch_size);
        ndrange = batch_size,
    )
    runtime.identity(
        workspace.old_owners,
        workspace.new_owners,
        workspace.priorities,
        workspace.semantic_ids,
        workspace.dispositions,
        workspace.cell_max_priority,
        workspace.cell_min_identity,
        state,
        Int32(batch_size);
        ndrange = batch_size,
    )
    runtime.select(
        workspace.old_owners,
        workspace.new_owners,
        workspace.priorities,
        workspace.semantic_ids,
        workspace.dispositions,
        workspace.cell_max_priority,
        workspace.cell_min_identity,
        state,
        Int32(batch_size);
        ndrange = batch_size,
    )
    return nothing
end

function _checkerboard_candidate_gate(candidate, state)
    if state.program_status === candidate.direct.state.program_status
        return candidate.gates[1]
    elseif state.program_status ===
            candidate.direct.alternate_state.program_status
        return candidate.gates[2]
    end
    throw(ArgumentError(
        "checkerboard state does not belong to the candidate's prepared banks"
    ))
end

function _execute_checkerboard_claim_block!(
        candidate::_LocalWorksetsCheckerboardWorkspace,
        runtime,
        workspace,
        state,
        batch_size,
    )
    gate = _checkerboard_candidate_gate(candidate, state)
    try
        candidate.last_event = invoke(
            _run_localworksets_trusted!,
            Tuple{
                _LocalWorksetsTrustedAdapter,
                LocalWorksets.PreparedWork,
                NamedTuple,
            },
            candidate.trusted_adapter,
            candidate.prepared,
            (
                execution_open = gate,
                active_count = Int32(batch_size),
            ),
        )
    catch error
        error isa LifecycleBackendFailure && rethrow()
        throw(LifecycleBackendFailure(error, state.mcs + 1, state.mcs + 1))
    end
    return nothing
end

function _execute_checkerboard_mcs!(
        workspace::CheckerboardWorkspace,
        mcs::Integer = workspace.state.mcs,
        state_bank::CheckerboardExecutionState = workspace.state,
        claims::_AbstractCheckerboardClaimExecution =
            _DirectCheckerboardClaimExecution(),
        ;
        workgroup_size::Union{Nothing, Integer} = nothing,
    )
    _require_program_execution_capability(
        workspace.capability_report;
        operation = :backend_execute_checkerboard_mcs,
    )
    authorized_bank = any((workspace.state, workspace.alternate_state)) do bank
        state_bank.ownership === bank.ownership &&
            state_bank.parameters === bank.parameters &&
            state_bank.program === bank.program
    end
    authorized_bank || throw(ArgumentError(
        "checkerboard execution state is not owned by the authorized workspace"
    ))
    state = _checkerboard_state_at_mcs(state_bank, mcs)
    plan = state.program.checkerboard_plan
    backend = KernelAbstractions.get_backend(workspace.dispositions)
    staged_commit = _checkerboard_requires_accepted_commit(state)
    staged_commit && !(backend isa KernelAbstractions.CPU) && throw(
        ArgumentError(
            "accepted-copy checkerboard stages are not qualified on this backend"
        )
    )
    _clear_checkerboard_bulk!(workspace, state)
    workgroup_size === nothing || workgroup_size > 0 || throw(ArgumentError(
        "checkerboard workgroup size must be positive"
    ))
    launch(kernel) = workgroup_size === nothing ? kernel(backend) :
                     kernel(backend, Int(workgroup_size))
    candidate_kernel = launch(_checkerboard_candidates_kernel!)
    claim_runtime = _prepare_checkerboard_claim_runtime(
        claims, backend, launch
    )
    evaluate_kernel = launch(_checkerboard_evaluate_kernel!)
    acceptance_status_kernel = _checkerboard_acceptance_status_kernel!(backend)
    commit_kernel = launch(_checkerboard_commit_kernel!)
    report_kernel = _checkerboard_report_kernel!(backend)
    # The accepted CheckerboardSweep process uses one normalized sweep. Its
    # realized colors execute in an unbiased semantic-RNG permutation. The
    # preallocated host order is safe for queued CPU/Metal launches because
    # each kernel receives its color as a copied scalar argument.
    for attempt_round in 1:Int(state.program.attempts_per_site)
        color_order = _checkerboard_color_order!(
            workspace.color_order, state, attempt_round
        )
        for color_position in 1:Int(plan.color_count)
            color = Int(@inbounds color_order[color_position])
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
            acceptance_status_kernel(
                workspace.dispositions,
                workspace.semantic_ids,
                state,
                Int32(batch_size);
                ndrange = 1,
            )
            _execute_checkerboard_claim_block!(
                claims,
                claim_runtime,
                workspace,
                state,
                batch_size,
            )
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
            staged_commit && _publish_checkerboard_accepted_stage!(
                workspace, state, color, batch_size
            )
            report_kernel(
                workspace.report,
                workspace.dispositions,
                state,
                Int32(batch_size);
                ndrange = 1,
            )
        end
    end
    return workspace
end

function execute_checkerboard_mcs!(
        workspace::CheckerboardWorkspace,
        mcs::Integer = workspace.state.mcs,
        state_bank::CheckerboardExecutionState = workspace.state;
        workgroup_size::Union{Nothing, Integer} = nothing,
    )
    return _execute_checkerboard_mcs!(
        workspace,
        mcs,
        state_bank,
        _DirectCheckerboardClaimExecution();
        workgroup_size,
    )
end


function execute_checkerboard_mcs!(
        candidate::_LocalWorksetsCheckerboardWorkspace,
        mcs::Integer = candidate.direct.state.mcs,
        state_bank::CheckerboardExecutionState = candidate.direct.state;
        workgroup_size::Union{Nothing, Integer} = nothing,
    )
    _execute_checkerboard_mcs!(
        candidate.direct,
        mcs,
        state_bank,
        candidate;
        workgroup_size,
    )
    return candidate
end

@inline function _checkerboard_transaction_banks(
        workspace::CheckerboardWorkspace, current_mcs::Integer
    )
    if iseven(current_mcs)
        return workspace.state, workspace.alternate_state, Int32(2)
    end
    return workspace.alternate_state, workspace.state, Int32(1)
end

function enqueue_checkerboard_mcs!(
        workspace::CheckerboardWorkspace,
        current_mcs::Integer;
        workgroup_size::Union{Nothing, Integer} = nothing,
    )
    _require_program_execution_capability(
        workspace.capability_report;
        operation = :backend_enqueue_checkerboard_mcs,
    )
    current_mcs >= 0 || throw(ArgumentError(
        "current MCS must be nonnegative"
    ))
    current_mcs == workspace.execution.submitted_mcs || throw(ArgumentError(
        "checkerboard submission must be contiguous: expected current MCS " *
        "$(workspace.execution.submitted_mcs), received $current_mcs"
    ))
    source, destination, destination_bank = _checkerboard_transaction_banks(
        workspace, current_mcs
    )
    destination = _checkerboard_state_at_mcs(destination, current_mcs)
    _enqueue_program_state_copy!(destination, source)
    execute_checkerboard_mcs!(
        workspace,
        current_mcs,
        destination;
        workgroup_size,
    )
    enqueue_lifecycle_backend_index!(destination; workgroup_size)
    _enqueue_program_bank_publication!(
        destination, workspace.report, destination_bank, current_mcs + 1
    )
    workspace.execution.submitted_mcs = Int(current_mcs) + 1
    return destination
end

function _require_candidate_mcs_lease_capacity(
        candidate::_LocalWorksetsCheckerboardWorkspace
    )
    required = Int(
        candidate.direct.state.program.attempts_per_site
    ) * Int(candidate.direct.state.program.checkerboard_plan.color_count)
    position = candidate.execution
    outstanding_mcs = position.submitted_mcs - position.drained_mcs
    available = candidate.lease_capacity - outstanding_mcs * required
    available >= required || throw(ArgumentError(
        "LocalWorksets checkerboard lease capacity cannot encode one complete MCS"
    ))
    return nothing
end

function enqueue_checkerboard_mcs!(
        candidate::_LocalWorksetsCheckerboardWorkspace,
        current_mcs::Integer;
        workgroup_size::Union{Nothing, Integer} = nothing,
    )
    workspace = candidate.direct
    _require_program_execution_capability(
        workspace.capability_report;
        operation = :backend_enqueue_checkerboard_mcs,
    )
    current_mcs >= 0 || throw(ArgumentError(
        "current MCS must be nonnegative"
    ))
    current_mcs == workspace.execution.submitted_mcs || throw(ArgumentError(
        "checkerboard submission must be contiguous: expected current MCS " *
        "$(workspace.execution.submitted_mcs), received $current_mcs"
    ))
    _require_candidate_mcs_lease_capacity(candidate)
    source, destination, destination_bank = _checkerboard_transaction_banks(
        workspace, current_mcs
    )
    destination = _checkerboard_state_at_mcs(destination, current_mcs)
    _enqueue_program_state_copy!(destination, source)
    execute_checkerboard_mcs!(
        candidate,
        current_mcs,
        destination;
        workgroup_size,
    )
    enqueue_lifecycle_backend_index!(destination; workgroup_size)
    _enqueue_program_bank_publication!(
        destination, workspace.report, destination_bank, current_mcs + 1
    )
    workspace.execution.submitted_mcs = Int(current_mcs) + 1
    return destination
end

function _clear_checkerboard_claims!(workspace::CheckerboardWorkspace, state)
    maximums = workspace.cell_max_priority
    identities = workspace.cell_min_identity
    backend = KernelAbstractions.get_backend(maximums)
    _checkerboard_clear_claims_kernel!(backend)(
        maximums, identities, state; ndrange = length(maximums)
    )
    return nothing
end

function _advance_checkerboard!(runtime::ProgramRuntime)
    workspace = runtime.engine_workspace
    workspace isa CheckerboardWorkspace || error(
        "checkerboard runtime has no portable execution workspace"
    )
    execute_checkerboard_mcs!(workspace, runtime.mcs)
    values = workspace.report
    runtime.accepted += UInt64(values[1])
    runtime.rejected += UInt64(values[2])
    runtime.null_attempts += UInt64(values[3])
    runtime.constraint_rejections += UInt64(values[4])
    runtime.energy_rejections += UInt64(values[5])
    return nothing
end

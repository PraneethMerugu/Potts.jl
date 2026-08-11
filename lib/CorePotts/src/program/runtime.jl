# Logical snapshots, checkpoints, initialization, and runtime ownership.

struct ProgramSnapshot{T <: AbstractFloat, N, R, D, TS}
    mcs::Int
    ownership::Array{Int32, N}
    cell_kinds::Vector{Int16}
    cell_generations::Vector{UInt32}
    trackers::TS
    relationships::R
    descriptor_state::D
end

"""
Return an independently owned copy of a logical snapshot's descriptor state.

The returned state may be inspected or transformed by a backend integration
without mutating the settled logical snapshot from which it was derived.
"""
function program_snapshot_descriptor_state(snapshot::ProgramSnapshot)
    state = snapshot.descriptor_state
    state isa AuxiliaryState || throw(ArgumentError(
        "the program snapshot descriptor state is not a CorePotts AuxiliaryState"
    ))
    return copy_auxiliary_state(state)
end

struct ProgramCheckpoint{S, P, E}
    schema::VersionNumber
    program_fingerprint::String
    snapshot::S
    parameters::P
    seed::UInt64
    replica::UInt32
    repeat::UInt32
    accepted::UInt64
    rejected::UInt64
    null_attempts::UInt64
    constraint_rejections::UInt64
    energy_rejections::UInt64
    retired_cells::UInt64
    extensions::E
    checksum::String
end

const _CORE_CHECKPOINT_CAPABILITY_SCHEMA = v"1.1.0"

function _core_checkpoint_capability_block(program::CompiledPottsProgram)
    key = program_capability_report(program).key
    return (
        schema = _CORE_CHECKPOINT_CAPABILITY_SCHEMA,
        capability_fingerprint = _capability_key_fingerprint(key),
        rng = (
            contract_version = RNG_CONTRACT_VERSION,
            lowering_identity = RNG_LOWERING_IDENTITY,
        ),
        environment = key.environment,
    )
end

_checkpoint_execution_block(runtime) = nothing
_runtime_uses_experimental_capability(runtime) = false

function _owned_checkpoint_extensions(
        program, extensions, execution_block = nothing
    )
    extensions isa NamedTuple || throw(ArgumentError(
        "checkpoint extensions must be a named tuple"
    ))
    hasproperty(extensions, :CorePotts) && throw(ArgumentError(
        "checkpoint extension owner `CorePotts` is reserved"
    ))
    core_block = _core_checkpoint_capability_block(program)
    execution_block === nothing ||
        (core_block = merge(
            core_block, (; execution_lowering = execution_block)
        ))
    return merge(
        (CorePotts = core_block,),
        deepcopy(extensions),
    )
end

function _validate_checkpoint_capability(
        program::CompiledPottsProgram, extensions
    )
    extensions isa NamedTuple || throw(ArgumentError(
        "checkpoint extensions must be a named tuple"
    ))
    hasproperty(extensions, :CorePotts) || throw(ArgumentError(
        "checkpoint is missing its CorePotts exact-configuration identity"
    ))
    block = getproperty(extensions, :CorePotts)
    block isa NamedTuple &&
        all(
            name -> hasproperty(block, name),
            (:schema, :capability_fingerprint, :rng, :environment),
        ) || throw(ArgumentError(
            "checkpoint has an incomplete CorePotts capability block"
        ))
    block.schema == _CORE_CHECKPOINT_CAPABILITY_SCHEMA || throw(ArgumentError(
        "unsupported CorePotts checkpoint capability schema"
    ))
    key = program_capability_report(program).key
    expected_rng = (
        contract_version = key.mechanisms.rng_contract_version,
        lowering_identity = key.mechanisms.rng_lowering_identity,
    )
    block.rng == expected_rng || throw(ArgumentError(
        "checkpoint RNG contract version or lowering identity mismatch"
    ))
    block.environment == key.environment || throw(ArgumentError(
        "checkpoint exact-configuration execution environment mismatch"
    ))
    block.capability_fingerprint == _capability_key_fingerprint(key) ||
        throw(ArgumentError(
            "checkpoint exact-configuration capability fingerprint mismatch"
        ))
    return block
end

function _checkpoint_extension_payload(value::NamedTuple)
    return string(
        "named(",
        join((
            string(
                repr(name), "=>",
                _checkpoint_extension_payload(getproperty(value, name)),
            ) for name in keys(value)
        ), ','),
        ')',
    )
end

function _checkpoint_extension_payload(value::Tuple)
    return string(
        "tuple(",
        join((_checkpoint_extension_payload(item) for item in value), ','),
        ')',
    )
end

function _checkpoint_extension_payload(value::Pair)
    return string(
        "pair(",
        _checkpoint_extension_payload(first(value)), ',',
        _checkpoint_extension_payload(last(value)),
        ')',
    )
end

function _checkpoint_extension_payload(value::AbstractArray)
    return string(
        "array(", repr(typeof(value)), ';', repr(size(value)), ';',
        join((_checkpoint_extension_payload(item) for item in value), ','),
        ')',
    )
end

_checkpoint_extension_payload(value::Nothing) = "nothing"
_checkpoint_extension_payload(value::Missing) = "missing"
function _checkpoint_extension_payload(
        value::Union{Bool, Integer, AbstractFloat, Symbol, AbstractString,
                     VersionNumber, Enum}
    )
    return string(repr(typeof(value)), '(', repr(value), ')')
end

function _checkpoint_extension_payload(value)
    throw(ArgumentError(
        "checkpoint extension payloads must use deterministic logical values; " *
        "unsupported value type $(typeof(value))"
    ))
end

function _relationship_checkpoint_payload(state::ProgramRelationshipState)
    return string(
        join(state.active, ','),
        ';', join(state.endpoint_a, ','),
        ';', join(state.endpoint_b, ','),
        ';', join(state.generation_a, ','),
        ';', join(state.generation_b, ','),
        ';', join((join(values, ',') for values in state.payload), '|'),
        ';', join(state.degree, ','),
        ';', join(vec(state.incident_edges), ','),
    )
end

_relationship_checkpoint_payload(states::RelationshipStorage) =
    join((_relationship_checkpoint_payload(state) for state in states), "||")

function _validate_runtime_relationships!(runtime)
    length(runtime.relationships) == length(runtime.program.relationships) ||
        throw(ArgumentError(
            "runtime relationship state and compiled schemas are misaligned"
        ))
    for slot in eachindex(runtime.relationships)
        validate_relationship_integrity(
            runtime.relationships[slot],
            runtime.program.relationships[slot],
            runtime.cell_kinds,
            runtime.cell_generations,
        )
    end
    return runtime
end

function _program_checkpoint_checksum(
        schema,
        fingerprint,
        snapshot,
        parameters,
        seed,
        replica,
        repeat,
        accepted,
        rejected,
        null_attempts,
        constraint_rejections,
        energy_rejections,
        retired_cells,
        extensions,
    )
    payload = string(
        schema, '\n',
        fingerprint, '\n',
        snapshot.mcs, '\n',
        size(snapshot.ownership), '\n',
        join(vec(snapshot.ownership), ','), '\n',
        join(snapshot.cell_kinds, ','), '\n',
        join(snapshot.cell_generations, ','), '\n',
        repr(snapshot.trackers), '\n',
        repr(snapshot.descriptor_state), '\n',
        _relationship_checkpoint_payload(snapshot.relationships), '\n',
        join(parameters, ','), '\n',
        seed, '\n',
        replica, '\n',
        repeat, '\n',
        accepted, '\n',
        rejected, '\n',
        null_attempts, '\n',
        constraint_rejections, '\n',
        energy_rejections, '\n',
        retired_cells, '\n',
        _checkpoint_extension_payload(extensions),
    )
    return bytes2hex(SHA.sha256(codeunits(payload)))
end

function program_checkpoint(runtime; extensions = NamedTuple())
    runtime.settled || throw(ArgumentError(
        "a checkpoint requires a settled complete-MCS boundary"
    ))
    program_failed(runtime) && throw(ArgumentError(
        "a terminal failed runtime cannot be checkpointed"
    ))
    _validate_compiled_program_integrity(runtime.program)
    _require_program_replay_capability(
        runtime.capability_report;
        operation = :checkpoint,
        experimental = _runtime_uses_experimental_capability(runtime),
    )
    schema = v"2.0.0"
    logical_snapshot = program_snapshot(runtime)
    trackers = encode_tracker_checkpoint(
        runtime.program.tracker_plan, runtime.trackers
    )
    descriptor_state = encode_auxiliary_state_checkpoint(
        runtime.program.descriptor_plan.state_layout,
        runtime.descriptor_state,
    )
    snapshot = ProgramSnapshot{
        eltype(runtime.parameters),
        ndims(runtime.ownership),
        typeof(logical_snapshot.relationships),
        typeof(descriptor_state),
        typeof(trackers),
    }(
        logical_snapshot.mcs,
        logical_snapshot.ownership,
        logical_snapshot.cell_kinds,
        logical_snapshot.cell_generations,
        trackers,
        logical_snapshot.relationships,
        descriptor_state,
    )
    parameters = copy(runtime.parameters)
    # Extension owners provide logical values, never functions or live solver
    # objects.  Validate before copying so one outer checksum owns the complete
    # cross-package checkpoint rather than layering a second codec around Core.
    _checkpoint_extension_payload(extensions)
    owned_extensions = _owned_checkpoint_extensions(
        runtime.program,
        extensions,
        _checkpoint_execution_block(runtime),
    )
    checksum = _program_checkpoint_checksum(
        schema,
        runtime.program.fingerprint,
        snapshot,
        parameters,
        runtime.seed,
        runtime.replica,
        runtime.repeat,
        runtime.accepted,
        runtime.rejected,
        runtime.null_attempts,
        runtime.constraint_rejections,
        runtime.energy_rejections,
        runtime.retired_cells,
        owned_extensions,
    )
    return ProgramCheckpoint(
        schema,
        runtime.program.fingerprint,
        snapshot,
        parameters,
        runtime.seed,
        runtime.replica,
        runtime.repeat,
        runtime.accepted,
        runtime.rejected,
        runtime.null_attempts,
        runtime.constraint_rejections,
        runtime.energy_rejections,
        runtime.retired_cells,
        owned_extensions,
        checksum,
    )
end

function _validate_checkpoint_execution_lowering(
        extensions, expected_execution
    )
    block = getproperty(extensions, :CorePotts)
    has_execution = hasproperty(block, :execution_lowering)
    if expected_execution === nothing
        has_execution && throw(ArgumentError(
            "candidate checkpoint cannot restore into direct execution"
        ))
        return nothing
    end
    has_execution || throw(ArgumentError(
        "direct checkpoint cannot restore into candidate execution"
    ))
    execution = block.execution_lowering
    execution isa NamedTuple &&
        hasproperty(execution, :mechanism_identity) &&
        execution.mechanism_identity === expected_execution ||
        throw(ArgumentError(
            "checkpoint execution-lowering identity mismatch"
        ))
    return execution
end

function _validate_program_checkpoint(
        program::CompiledPottsProgram,
        checkpoint::ProgramCheckpoint,
        expected_execution,
    )
    _validate_compiled_program_integrity(program)
    _require_program_replay_capability(
        program; operation = :checkpoint_restore
    )
    checkpoint.schema == v"2.0.0" ||
        throw(ArgumentError("unsupported CorePotts checkpoint schema"))
    checkpoint.program_fingerprint == program.fingerprint ||
        throw(ArgumentError("checkpoint executable identity does not match"))
    expected = _program_checkpoint_checksum(
        checkpoint.schema,
        checkpoint.program_fingerprint,
        checkpoint.snapshot,
        checkpoint.parameters,
        checkpoint.seed,
        checkpoint.replica,
        checkpoint.repeat,
        checkpoint.accepted,
        checkpoint.rejected,
        checkpoint.null_attempts,
        checkpoint.constraint_rejections,
        checkpoint.energy_rejections,
        checkpoint.retired_cells,
        checkpoint.extensions,
    )
    expected == checkpoint.checksum ||
        throw(ArgumentError("checkpoint integrity checksum mismatch"))
    _validate_checkpoint_capability(program, checkpoint.extensions)
    _validate_checkpoint_execution_lowering(
        checkpoint.extensions, expected_execution
    )
    return checkpoint
end

function validate_program_checkpoint(
        program::CompiledPottsProgram, checkpoint::ProgramCheckpoint
    )
    return _validate_program_checkpoint(program, checkpoint, nothing)
end

function _restore_validated_program_checkpoint(
        program::CompiledPottsProgram, checkpoint::ProgramCheckpoint
    )
    descriptor_state = reconstruct_auxiliary_state(
        program.descriptor_plan.state_layout,
        checkpoint.snapshot.descriptor_state,
    )
    initial = ProgramInitialState(
        checkpoint.snapshot.ownership,
        checkpoint.snapshot.cell_kinds;
        scalar_type = eltype(program.parameter_defaults),
        cell_generations = checkpoint.snapshot.cell_generations,
        relationships = collect(checkpoint.snapshot.relationships),
        descriptor_state,
    )
    return _materialize_program(
        program,
        initial,
        checkpoint.parameters,
        checkpoint.seed,
        checkpoint.replica;
        repeat = checkpoint.repeat,
        initial_mcs = checkpoint.snapshot.mcs,
        tracker_checkpoint = checkpoint.snapshot.trackers,
        counters = (
            accepted = checkpoint.accepted,
            rejected = checkpoint.rejected,
            null_attempts = checkpoint.null_attempts,
            constraint_rejections = checkpoint.constraint_rejections,
            energy_rejections = checkpoint.energy_rejections,
            retired_cells = checkpoint.retired_cells,
        ),
    )
end

function restore_program_checkpoint(
        program::CompiledPottsProgram, checkpoint::ProgramCheckpoint
    )
    validate_program_checkpoint(program, checkpoint)
    return _restore_validated_program_checkpoint(program, checkpoint)
end

function _accepted_copy_batch_bound(program::CompiledPottsProgram)
    plan = program.checkerboard_plan
    return plan isa CheckerboardPlan ?
           Int(plan.maximum_color_size) * Int(program.attempts_per_site) : 1
end

mutable struct ProgramRuntime{T <: AbstractFloat, N, P, C, R, TS, D, SB, EW, LW}
    program::P
    capability_report::C
    ownership::Array{Int32, N}
    cell_kinds::Vector{Int16}
    cell_generations::Vector{UInt32}
    trackers::TS
    relationships::R
    descriptor_state::D
    proposal_contributions::Vector{ProposalEvaluation{T}}
    stage_buffers::SB
    engine_workspace::EW
    lifecycle_workspace::LW
    parameters::Vector{T}
    seed::UInt64
    replica::UInt32
    repeat::UInt32
    mcs::Int
    accepted::UInt64
    rejected::UInt64
    null_attempts::UInt64
    constraint_rejections::UInt64
    energy_rejections::UInt64
    retired_cells::UInt64
    settled::Bool
    failure_status::ProgramStatus
    last_lifecycle_receipt::MaybeLifecycleReceipt
end

function _materialize_program(
        program::CompiledPottsProgram{T, N},
        initial::ProgramInitialState,
        parameters::AbstractVector{<:Real},
        seed::UInt64,
        replica::UInt32;
        repeat::UInt32 = UInt32(1),
        initial_mcs::Integer = 0,
        tracker_checkpoint = nothing,
        counters = (
            accepted = UInt64(0),
            rejected = UInt64(0),
            null_attempts = UInt64(0),
            constraint_rejections = UInt64(0),
            energy_rejections = UInt64(0),
            retired_cells = UInt64(0),
        ),
    ) where {T, N}
    _validate_compiled_program_integrity(program)
    capability_report = _require_program_execution_capability(
        program; operation = :initialize_program
    )
    # A runtime owns its executable independently of the compiler-facing
    # artifact.  This is a cold-path copy: later caller mutation of the source
    # program cannot change an initialized or ensemble runtime.
    program = deepcopy(program)
    initial_ownership = _program_initial_field(initial, :ownership)
    initial_cell_kinds = _program_initial_field(initial, :cell_kinds)
    initial_cell_generations = _program_initial_field(
        initial, :cell_generations
    )
    initial_relationships = _program_initial_field(initial, :relationships)
    initial_descriptor_state = _program_initial_field(
        initial, :descriptor_state
    )
    size(initial_ownership) == program.shape ||
        throw(ArgumentError("initial ownership shape does not match the program"))
    runtime_parameters = _validated_program_parameters(program, parameters)
    lifecycle_plan = program.lifecycle_plan
    cell_capacity = lifecycle_plan isa LifecycleExecutionPlan ?
        Int(lifecycle_plan.cell_capacity) : length(initial_cell_kinds)
    length(initial_cell_kinds) <= cell_capacity || throw(ArgumentError(
        "initial finite-cell count exceeds compiled max_cells=$cell_capacity"
    ))
    maximum(initial_ownership; init = Int32(0)) <= length(initial_cell_kinds) ||
        throw(ArgumentError("initial ownership references an unknown cell label"))
    minimum(initial_ownership; init = Int32(0)) >= -program.kind_count ||
        throw(ArgumentError("initial ownership references an unknown medium kind"))
    all(initial_ownership) do owner
        owner >= 0 || @inbounds(program.medium_kinds[-owner])
    end || throw(ArgumentError(
        "initial ownership uses a non-medium kind as a medium domain"
    ))
    all(kind -> kind == 0 || 1 <= kind <= program.kind_count, initial_cell_kinds) ||
        throw(ArgumentError("initial cell kind is outside the compiled kind table"))
    all(kind -> kind == 0 || !program.medium_kinds[kind], initial_cell_kinds) ||
        throw(ArgumentError("a finite cell cannot use a medium kind"))
    length(initial_cell_generations) == length(initial_cell_kinds) ||
        throw(ArgumentError("initial cell generation table has the wrong length"))
    all(eachindex(initial_cell_kinds)) do index
        @inbounds initial_cell_kinds[index] == 0 ||
            !iszero(initial_cell_generations[index])
    end || throw(ArgumentError("active cell generations must be positive"))
    initial_mcs >= 0 || throw(ArgumentError("initial MCS must be nonnegative"))
    repeat > 0 || throw(ArgumentError("ensemble repeat identity must be positive"))

    runtime_ownership = copy(initial_ownership)
    runtime_cell_kinds = zeros(Int16, cell_capacity)
    runtime_cell_generations = zeros(UInt32, cell_capacity)
    copyto!(
        runtime_cell_kinds,
        1,
        initial_cell_kinds,
        1,
        length(initial_cell_kinds),
    )
    copyto!(
        runtime_cell_generations,
        1,
        initial_cell_generations,
        1,
        length(initial_cell_generations),
    )
    trackers = tracker_checkpoint === nothing ? initialize_tracker_state(
        program.tracker_plan, runtime_ownership, runtime_cell_kinds, program
    ) : reconstruct_tracker_checkpoint(
        program.tracker_plan,
        tracker_checkpoint,
        runtime_ownership,
        runtime_cell_kinds,
        program,
    )
    validate_tracker_state!(
        program.tracker_plan,
        trackers,
        runtime_ownership,
        runtime_cell_kinds,
        program,
    )
    volumes = tracker_values(
        program.tracker_plan, trackers, Val(:cell_volume)
    )
    all(eachindex(volumes)) do cell
        active = runtime_cell_kinds[cell] != 0
        occupied = volumes[cell] != 0
        active == occupied
    end || throw(ArgumentError(
        "every active finite cell must own at least one site and inactive slots " *
        "must not appear in ownership"
    ))
    length(initial_relationships) == length(program.relationships) || throw(
        ArgumentError(
            "initial relationship values must align with compiled schemas"
        )
    )
    relationship_values = Any[]
    for relationship_slot in eachindex(program.relationships)
        schema = program.relationships[relationship_slot]
        entries = initial_relationships[relationship_slot]
        state = if entries isa ProgramRelationshipState
            value = copy(entries)
            validate_relationship_integrity(
                value,
                schema,
                runtime_cell_kinds,
                runtime_cell_generations,
            )
            value
        else
            initialize_program_relationships(
                schema,
                runtime_cell_kinds,
                runtime_cell_generations,
                runtime_parameters,
                entries,
            )
        end
        push!(relationship_values, state)
    end
    relationships = RelationshipStorage(relationship_values)
    descriptor_state = if initial_descriptor_state === nothing
        allocate_auxiliary_state(program.descriptor_plan.state_layout)
    elseif initial_descriptor_state isa AuxiliaryState
        copy_auxiliary_state(
            program.descriptor_plan.state_layout,
            initial_descriptor_state,
        )
    else
        throw(ArgumentError(
            "descriptor state must be a CorePotts AuxiliaryState"
        ))
    end
    stage_buffers = allocate_stage_runtime_buffers(
        program.stage_plan,
        T,
        program.shape,
        relationships,
        accepted_batch_bound = _accepted_copy_batch_bound(program),
    )
    engine_workspace = allocate_program_engine_workspace(
        program,
        runtime_ownership,
        runtime_cell_kinds,
        runtime_cell_generations,
        trackers,
        relationships,
        descriptor_state,
        stage_buffers,
        runtime_parameters,
        seed,
        replica,
        repeat,
        initial_mcs,
    )
    lifecycle_workspace = allocate_lifecycle_workspace(
        program.lifecycle_plan,
        program,
        runtime_ownership,
        runtime_cell_kinds,
        runtime_cell_generations,
        trackers,
        relationships,
        descriptor_state,
    )
    if lifecycle_workspace isa LifecycleWorkspace &&
            engine_workspace isa SequentialTransactionWorkspace
        lifecycle_workspace = _lifecycle_workspace_with_staged_state(
            lifecycle_workspace, engine_workspace
        )
    end
    runtime = ProgramRuntime{
        T, N, typeof(program), typeof(capability_report),
        typeof(relationships), typeof(trackers),
        typeof(descriptor_state),
        typeof(stage_buffers),
        typeof(engine_workspace),
        typeof(lifecycle_workspace),
    }(
        program,
        capability_report,
        runtime_ownership,
        runtime_cell_kinds,
        runtime_cell_generations,
        trackers,
        relationships,
        descriptor_state,
        fill(
            _neutral_proposal_evaluation(T),
            length(program.descriptor_plan.source_table),
        ),
        stage_buffers,
        engine_workspace,
        lifecycle_workspace,
        runtime_parameters,
        seed,
        replica,
        repeat,
        Int(initial_mcs),
        UInt64(counters.accepted),
        UInt64(counters.rejected),
        UInt64(counters.null_attempts),
        UInt64(counters.constraint_rejections),
        UInt64(counters.energy_rejections),
        UInt64(counters.retired_cells),
        true,
        ProgramStatus(),
        nothing,
    )
    runtime.engine_workspace isa CheckerboardWorkspace &&
        initialize_program_execution_statistics!(
            runtime.engine_workspace,
            runtime.accepted,
            runtime.rejected,
            runtime.null_attempts,
            runtime.constraint_rejections,
            runtime.energy_rejections,
            runtime.retired_cells,
        )
    return runtime
end

function initialize_program(
        program::CompiledPottsProgram,
        initial::ProgramInitialState,
        parameters::AbstractVector{<:Real},
        seed::UInt64,
        replica::UInt32;
        repeat::UInt32 = UInt32(1),
        initial_mcs::Integer = 0,
    )
    return _materialize_program(
        program,
        initial,
        parameters,
        seed,
        replica;
        repeat,
        initial_mcs,
    )
end

function adapt_program_runtime(to, runtime::ProgramRuntime{T, N}) where {T, N}
    runtime.settled || throw(ArgumentError(
        "program runtime adaptation requires a settled boundary"
    ))
    runtime.engine_workspace isa CheckerboardWorkspace || throw(ArgumentError(
        "only checkerboard runtimes have a portable accelerator execution path"
    ))
    engine_workspace = adapt_checkerboard_workspace(
        to, runtime.engine_workspace
    )
    capability_report = engine_workspace.capability_report
    return ProgramRuntime{
        T,
        N,
        typeof(runtime.program),
        typeof(capability_report),
        typeof(runtime.relationships),
        typeof(runtime.trackers),
        typeof(runtime.descriptor_state),
        typeof(runtime.stage_buffers),
        typeof(engine_workspace),
        typeof(runtime.lifecycle_workspace),
    }(
        runtime.program,
        capability_report,
        runtime.ownership,
        runtime.cell_kinds,
        runtime.cell_generations,
        runtime.trackers,
        runtime.relationships,
        runtime.descriptor_state,
        runtime.proposal_contributions,
        runtime.stage_buffers,
        engine_workspace,
        runtime.lifecycle_workspace,
        runtime.parameters,
        runtime.seed,
        runtime.replica,
        runtime.repeat,
        runtime.mcs,
        runtime.accepted,
        runtime.rejected,
        runtime.null_attempts,
        runtime.constraint_rejections,
        runtime.energy_rejections,
        runtime.retired_cells,
        runtime.settled,
        runtime.failure_status,
        runtime.last_lifecycle_receipt,
    )
end

@inline program_failed(runtime::ProgramRuntime) =
    runtime.failure_status.code !== ProgramStatusSuccess

@inline program_failure_report(runtime::ProgramRuntime) =
    program_failed(runtime) ? ProgramFailureReport(runtime.failure_status) : nothing

"""Return the most recently published lifecycle receipt, if any."""
@inline program_lifecycle_receipt(runtime::ProgramRuntime) =
    runtime.last_lifecycle_receipt

function _materialize_program_state_snapshot(
        runtime::ProgramRuntime{T, N}, state, mcs::Integer
    ) where {T, N}
    length(state.relationships) == length(runtime.program.relationships) ||
        throw(ArgumentError(
            "runtime relationship state and compiled schemas are misaligned"
        ))
    for slot in eachindex(state.relationships)
        validate_relationship_integrity(
            state.relationships[slot],
            runtime.program.relationships[slot],
            state.cell_kinds,
            state.cell_generations,
        )
    end
    validate_tracker_state!(
        runtime.program.tracker_plan,
        state.trackers,
        state.ownership,
        state.cell_kinds,
        runtime.program,
    )
    relationships = copy(state.relationships)
    descriptor_state = copy_auxiliary_state(
        runtime.program.descriptor_plan.state_layout,
        state.descriptor_state,
    )
    return ProgramSnapshot{
        T, N, typeof(relationships), typeof(descriptor_state),
        typeof(state.trackers),
    }(
        Int(mcs),
        copy(state.ownership),
        copy(state.cell_kinds),
        copy(state.cell_generations),
        copy_tracker_state(state.trackers),
        relationships,
        descriptor_state,
    )
end

function _materialize_runtime_snapshot(
        runtime::ProgramRuntime, mcs::Integer
    )
    return _materialize_program_state_snapshot(runtime, runtime, mcs)
end

function program_snapshot(runtime::ProgramRuntime)
    runtime.settled || throw(ArgumentError(
        "a program snapshot requires a settled complete-MCS boundary"
    ))
    return _materialize_runtime_snapshot(runtime, runtime.mcs)
end

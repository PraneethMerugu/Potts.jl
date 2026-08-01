# Logical snapshots, checkpoints, initialization, and runtime ownership.

struct ProgramSnapshot{T <: AbstractFloat, N, R, D}
    mcs::Int
    ownership::Array{Int32, N}
    cell_kinds::Vector{Int16}
    cell_generations::Vector{UInt32}
    volumes::Vector{Int}
    relationships::R
    descriptor_state::D
end

struct ProgramCheckpoint{S, P}
    schema::VersionNumber
    program_fingerprint::String
    snapshot::S
    parameters::P
    seed::UInt64
    replica::UInt32
    repeat::UInt32
    accepted::Int
    rejected::Int
    null_attempts::Int
    constraint_rejections::Int
    energy_rejections::Int
    retired_cells::Int
    checksum::String
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
    )
    payload = string(
        schema, '\n',
        fingerprint, '\n',
        snapshot.mcs, '\n',
        size(snapshot.ownership), '\n',
        join(vec(snapshot.ownership), ','), '\n',
        join(snapshot.cell_kinds, ','), '\n',
        join(snapshot.cell_generations, ','), '\n',
        join(snapshot.volumes, ','), '\n',
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
        retired_cells,
    )
    return bytes2hex(SHA.sha256(codeunits(payload)))
end

function program_checkpoint(runtime)
    runtime.settled || throw(ArgumentError(
        "a checkpoint requires a settled complete-MCS boundary"
    ))
    schema = v"1.0.0"
    snapshot = program_snapshot(runtime)
    parameters = copy(runtime.parameters)
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
        checksum,
    )
end

function restore_program_checkpoint(
        program::CompiledPottsProgram, checkpoint::ProgramCheckpoint
    )
    checkpoint.schema == v"1.0.0" ||
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
    )
    expected == checkpoint.checksum ||
        throw(ArgumentError("checkpoint integrity checksum mismatch"))
    initial = ProgramInitialState(
        checkpoint.snapshot.ownership,
        checkpoint.snapshot.cell_kinds;
        scalar_type = eltype(program.parameter_defaults),
        cell_generations = checkpoint.snapshot.cell_generations,
        relationships = fill(nothing, length(program.relationships)),
        descriptor_state = checkpoint.snapshot.descriptor_state,
    )
    runtime = initialize_program(
        program,
        initial,
        checkpoint.parameters,
        checkpoint.seed,
        checkpoint.replica;
        repeat = checkpoint.repeat,
        initial_mcs = checkpoint.snapshot.mcs,
    )
    runtime.volumes == checkpoint.snapshot.volumes ||
        throw(ArgumentError("checkpoint logical volume invariant failed"))
    runtime.relationships = copy(checkpoint.snapshot.relationships)
    runtime.stage_buffers = allocate_stage_runtime_buffers(
        program.stage_plan,
        eltype(runtime.parameters),
        program.shape,
        runtime.relationships,
    )
    runtime.engine_workspace = allocate_program_engine_workspace(
        program,
        runtime.ownership,
        runtime.cell_kinds,
        runtime.cell_generations,
        runtime.volumes,
        runtime.relationships,
        runtime.descriptor_state,
        runtime.parameters,
        runtime.seed,
        runtime.replica,
        runtime.repeat,
    )
    runtime.accepted = checkpoint.accepted
    runtime.rejected = checkpoint.rejected
    runtime.null_attempts = checkpoint.null_attempts
    runtime.constraint_rejections = checkpoint.constraint_rejections
    runtime.energy_rejections = checkpoint.energy_rejections
    runtime.retired_cells = checkpoint.retired_cells
    return runtime
end

mutable struct ProgramRuntime{T <: AbstractFloat, N, P, R, D, SB, EW}
    program::P
    ownership::Array{Int32, N}
    cell_kinds::Vector{Int16}
    cell_generations::Vector{UInt32}
    volumes::Vector{Int}
    relationships::R
    descriptor_state::D
    proposal_contributions::Vector{ProposalEvaluation{T}}
    stage_buffers::SB
    engine_workspace::EW
    parameters::Vector{T}
    seed::UInt64
    replica::UInt32
    repeat::UInt32
    mcs::Int
    accepted::Int
    rejected::Int
    null_attempts::Int
    constraint_rejections::Int
    energy_rejections::Int
    retired_cells::Int
    settled::Bool
end

function initialize_program(
        program::CompiledPottsProgram{T, N},
        initial::ProgramInitialState,
        parameters::AbstractVector{<:Real},
        seed::UInt64,
        replica::UInt32;
        repeat::UInt32 = UInt32(1),
        initial_mcs::Integer = 0,
    ) where {T, N}
    size(initial.ownership) == program.shape ||
        throw(ArgumentError("initial ownership shape does not match the program"))
    length(parameters) == length(program.parameter_defaults) ||
        throw(ArgumentError("runtime parameter buffer has the wrong length"))
    maximum(initial.ownership; init = Int32(0)) <= length(initial.cell_kinds) ||
        throw(ArgumentError("initial ownership references an unknown cell label"))
    minimum(initial.ownership; init = Int32(0)) >= -program.kind_count ||
        throw(ArgumentError("initial ownership references an unknown medium kind"))
    all(initial.ownership) do owner
        owner >= 0 || @inbounds(program.medium_kinds[-owner])
    end || throw(ArgumentError(
        "initial ownership uses a non-medium kind as a medium domain"
    ))
    all(kind -> kind == 0 || 1 <= kind <= program.kind_count, initial.cell_kinds) ||
        throw(ArgumentError("initial cell kind is outside the compiled kind table"))
    all(kind -> kind == 0 || !program.medium_kinds[kind], initial.cell_kinds) ||
        throw(ArgumentError("a finite cell cannot use a medium kind"))
    length(initial.cell_generations) == length(initial.cell_kinds) ||
        throw(ArgumentError("initial cell generation table has the wrong length"))
    all(!iszero, initial.cell_generations) ||
        throw(ArgumentError("active cell generations must be positive"))
    initial_mcs >= 0 || throw(ArgumentError("initial MCS must be nonnegative"))
    repeat > 0 || throw(ArgumentError("ensemble repeat identity must be positive"))

    runtime_ownership = copy(initial.ownership)
    runtime_cell_kinds = copy(initial.cell_kinds)
    runtime_cell_generations = copy(initial.cell_generations)
    volumes = zeros(Int, length(runtime_cell_kinds))
    for owner in runtime_ownership
        owner > 0 && (volumes[owner] += 1)
    end
    all(eachindex(volumes)) do cell
        active = runtime_cell_kinds[cell] != 0
        occupied = volumes[cell] != 0
        active == occupied
    end || throw(ArgumentError(
        "every active finite cell must own at least one site and inactive slots " *
        "must not appear in ownership"
    ))
    length(initial.relationships) == length(program.relationships) || throw(
        ArgumentError(
            "initial relationship values must align with compiled schemas"
        )
    )
    relationship_values = Any[]
    for relationship_slot in eachindex(program.relationships)
        schema = program.relationships[relationship_slot]
        entries = initial.relationships[relationship_slot]
        push!(relationship_values, initialize_program_relationships(
            schema,
            initial.cell_kinds,
            initial.cell_generations,
            T.(parameters),
            entries,
        ))
    end
    relationships = RelationshipStorage(relationship_values)
    descriptor_state = if initial.descriptor_state === nothing
        allocate_auxiliary_state(program.descriptor_plan.state_layout)
    elseif initial.descriptor_state isa AuxiliaryState
        copy_auxiliary_state(
            program.descriptor_plan.state_layout,
            initial.descriptor_state,
        )
    else
        throw(ArgumentError(
            "descriptor state must be a CorePotts AuxiliaryState"
        ))
    end
    runtime_parameters = T.(parameters)
    stage_buffers = allocate_stage_runtime_buffers(
        program.stage_plan,
        T,
        program.shape,
        relationships,
    )
    engine_workspace = allocate_program_engine_workspace(
        program,
        runtime_ownership,
        runtime_cell_kinds,
        runtime_cell_generations,
        volumes,
        relationships,
        descriptor_state,
        runtime_parameters,
        seed,
        replica,
        repeat,
    )
    return ProgramRuntime{
        T, N, typeof(program), typeof(relationships),
        typeof(descriptor_state),
        typeof(stage_buffers),
        typeof(engine_workspace),
    }(
        program,
        runtime_ownership,
        runtime_cell_kinds,
        runtime_cell_generations,
        volumes,
        relationships,
        descriptor_state,
        fill(
            _neutral_proposal_evaluation(T),
            length(program.descriptor_plan.source_table),
        ),
        stage_buffers,
        engine_workspace,
        runtime_parameters,
        seed,
        replica,
        repeat,
        Int(initial_mcs),
        0,
        0,
        0,
        0,
        0,
        0,
        true,
    )
end

function program_snapshot(runtime::ProgramRuntime{T, N}) where {T, N}
    runtime.settled || throw(ArgumentError(
        "a program snapshot requires a settled complete-MCS boundary"
    ))
    relationships = copy(runtime.relationships)
    descriptor_state = copy_auxiliary_state(
        runtime.program.descriptor_plan.state_layout,
        runtime.descriptor_state,
    )
    return ProgramSnapshot{
        T, N, typeof(relationships), typeof(descriptor_state),
    }(
        runtime.mcs,
        copy(runtime.ownership),
        copy(runtime.cell_kinds),
        copy(runtime.cell_generations),
        copy(runtime.volumes),
        relationships,
        descriptor_state,
    )
end

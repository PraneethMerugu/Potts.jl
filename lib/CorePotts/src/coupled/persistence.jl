const COUPLED_EXTENSION_BLOCK_VERSION = v"1.0.0"
const _COUPLED_PHASE_COMPLETED = UInt8(1)

struct CoupledCheckpointBlock{M <: NamedTuple, P}
    family::Symbol
    name::Symbol
    contract::Symbol
    version::VersionNumber
    metadata::M
    payload::P
    required::Bool
    checksum::NTuple{32, UInt8}
end

struct CoupledCheckpointExtension{B <: Tuple, P <: NamedTuple,
        O <: NamedTuple}
    version::VersionNumber
    blocks::B
    protocol_position::P
    observation_schedule::O
end

struct CoupledCheckpoint{C <: CanonicalCheckpoint,
        E <: CoupledCheckpointExtension}
    schema_version::VersionNumber
    complete::Bool
    mcs::UInt64
    phase::UInt8
    base::C
    extension::E
    coupled_model_fingerprint::NTuple{32, UInt8}
    state_schema_fingerprint::NTuple{32, UInt8}
    initial_state_fingerprint::NTuple{32, UInt8}
    ancestry_fingerprint::NTuple{32, UInt8}
    state_fingerprint::NTuple{32, UInt8}
    warnings::Tuple
    checksum::NTuple{32, UInt8}
end

function _semantic_record(value::DirectLaw)
    return (kind = :direct_law, name = value.name, version = value.version)
end
_semantic_record(value::Function) = throw(ArgumentError(
    "anonymous functions require a DirectLaw semantic identity"))
_semantic_record(value::NamedTuple) = NamedTuple{keys(value)}(
    Tuple(_semantic_record(item) for item in values(value)))
_semantic_record(value::Tuple) =
    Tuple(_semantic_record(item) for item in value)
_semantic_record(value::Pair) =
    _semantic_record(first(value)) => _semantic_record(last(value))
_semantic_record(value::AbstractArray) =
    map(_semantic_record, Adapt.adapt(Array, value))
_semantic_record(value::Union{Nothing, Number, Symbol, AbstractString,
    VersionNumber, Type, Enum}) = value
function _semantic_record(value)
    if hasmethod(component_identity, Tuple{typeof(value)})
        identity = component_identity(value)
        data = component_semantic_data(value)
        payload = data === value ? NamedTuple() : _semantic_record(data)
        return (key = identity.key, version = identity.version,
            category = identity.category, payload)
    end
    isstructtype(typeof(value)) && !ismutabletype(typeof(value)) ||
        throw(ArgumentError(
            "$(typeof(value)) has no durable coupled semantic encoding"))
    names = fieldnames(typeof(value))
    values = Tuple(_semantic_record(getfield(value, name)) for name in names)
    return (type = Symbol(nameof(typeof(value))),
        fields = NamedTuple{names}(values))
end

semantic_model_fingerprint(model::SemanticModel) =
    _canonical_digest(_semantic_record(model))

function _block_checksum(family, name, contract, version, metadata, payload,
        required)
    return _canonical_digest(family, name, contract, version,
        metadata, payload, required)
end

function _checkpoint_block(family::Symbol, name::Symbol, contract::Symbol,
        metadata::NamedTuple, payload; required::Bool = true,
        version::VersionNumber = COUPLED_EXTENSION_BLOCK_VERSION)
    checksum = _block_checksum(
        family, name, contract, version, metadata, payload, required)
    return CoupledCheckpointBlock(family, name, contract, version,
        metadata, payload, required, checksum)
end

_declaration_record(declaration) = _semantic_record(declaration)

function _state_block(state::SitePropertyState)
    declaration = state.declaration
    metadata = (declaration = _declaration_record(declaration),
        dims = size(state.values), value_type = string(eltype(state.values)))
    payload = (values = copy(Adapt.adapt(Array, state.values)),
        semantic_time = state.semantic_time)
    return _checkpoint_block(:site_property, declaration.name,
        :site_property, metadata, payload)
end

function _state_block(state::CellHistoryState)
    declaration = state.declaration
    metadata = (declaration = _declaration_record(declaration),
        capacity = length(state.generations),
        history_length = size(state.values, 2),
        value_type = string(eltype(state.values)))
    payload = (
        values = copy(Adapt.adapt(Array, state.values)),
        heads = copy(Adapt.adapt(Array, state.heads)),
        fills = copy(Adapt.adapt(Array, state.fills)),
        generations = copy(Adapt.adapt(Array, state.generations)),
        latest_sample_mcs = state.latest_sample_mcs)
    return _checkpoint_block(:cell_history, declaration.name,
        :cell_history, metadata, payload)
end

function _state_block(state::RelationshipState)
    declaration = state.declaration
    metadata = (declaration = _declaration_record(declaration),
        realized_capacity = declaration.capacity.value,
        storage = :canonical_soa)
    count = _relationship_count(state)
    payload = (
        endpoint_a = copy(Adapt.adapt(Array, @view(state.endpoint_a[1:count]))),
        generation_a = copy(Adapt.adapt(Array, @view(state.generation_a[1:count]))),
        endpoint_b = copy(Adapt.adapt(Array, @view(state.endpoint_b[1:count]))),
        generation_b = copy(Adapt.adapt(Array, @view(state.generation_b[1:count]))),
        edge_payload = copy(Adapt.adapt(Array, @view(state.payload[1:count]))),
        count = UInt32(count),
        publication_epoch = copy(
            Adapt.adapt(Array, state.publication_epoch)))
    return _checkpoint_block(:relationship_set, declaration.name,
        :relationship_set, metadata, payload)
end

function _state_block(state::EvolvingFieldState)
    metadata = (
        dims = size(state.values),
        value_type = string(eltype(state.values)),
        spacing = state.spacing,
        boundary = _semantic_record(state.boundary))
    payload = (
        values = copy(Adapt.adapt(Array, state.values)),
        forcing = copy(Adapt.adapt(Array, state.forcing)),
        time = state.time,
        diagnostics = state.diagnostics,
        publication_epoch = copy(Adapt.adapt(Array, state.publication_epoch)))
    return _checkpoint_block(:evolving_field, state.name,
        :evolving_field, metadata, payload)
end

function _state_block(state::ContinuousSystemState)
    declaration = state.declaration
    metadata = (declaration = _declaration_record(declaration),)
    payload = (values = state.values, time = state.time,
        diagnostics = state.diagnostics)
    return _checkpoint_block(:continuous_system, declaration.name,
        :continuous_system, metadata, payload)
end

function _state_block(state::GlobalPropertyState)
    declaration = state.declaration
    metadata = (declaration = _declaration_record(declaration),
        value_type = string(typeof(state.value)))
    payload = (
        value = state.value, semantic_time = state.semantic_time)
    return _checkpoint_block(:global_property, declaration.name,
        :global_property, metadata, payload)
end

function _state_block(state::FieldExchangeState)
    metadata = (
        value_type = string(eltype(state.value)),
        accumulator_type = string(eltype(state.workspace.raw_totals)),
        capacity = length(state.workspace.raw_totals))
    payload = (
        value = copy(Adapt.adapt(Array, state.value)),
        initialized = copy(Adapt.adapt(Array, state.initialized)),
        publication_epoch = copy(Adapt.adapt(Array, state.publication_epoch)))
    return _checkpoint_block(:field_exchange_state, state.name,
        :field_exchange_state, metadata, payload)
end

function _state_block(state::AffineCellRuntime)
    payload = (
        publication_epoch = copy(Adapt.adapt(
            Array, state.workspace.publication_epoch)),)
    metadata = (
        capacity = length(state.workspace.candidate_state),
        state_type = string(eltype(state.workspace.candidate_state)),
        time_type = string(eltype(state.workspace.candidate_time)))
    return _checkpoint_block(
        :affine_cell_runtime, state.name,
        :affine_cell_runtime, metadata, payload)
end

function _state_block(state::MembranePropertyState)
    declaration = state.declaration
    metadata = (declaration = _declaration_record(declaration),
        capacity = size(state.values, 1),
        resolution = size(state.values, 2),
        value_type = string(eltype(state.values)))
    payload = (
        values = copy(state.values),
        generations = copy(state.generations),
        active = copy(state.active),
        semantic_time = state.semantic_time)
    return _checkpoint_block(:membrane_property, declaration.name,
        :membrane_property, metadata, payload)
end

function _state_block(state::DelayStateStorage)
    declaration = state.declaration
    metadata = (declaration = _declaration_record(declaration),
        capacity = state.capacity)
    payload = (times = copy(state.times), values = copy(state.values),
        latest_time = state.latest_time)
    return _checkpoint_block(:delay_state, declaration.name,
        :delay_state, metadata, payload)
end

function _state_block(state::EventRuntimeState)
    declaration = state.declaration
    metadata = (declaration = _declaration_record(declaration),)
    payload = (
        previous_condition = state.previous_condition,
        latched = state.latched,
        queue = Tuple(state.queue),
        lifecycle_requests = Tuple(state.lifecycle_requests))
    return _checkpoint_block(:continuous_event, declaration.name,
        :continuous_event, metadata, payload)
end

function _state_block(state)
    throw(ArgumentError(
        "authoritative coupled state $(typeof(state)) has no registered checkpoint block"))
end

function _coupled_blocks(state::CoupledState)
    blocks = CoupledCheckpointBlock[]
    for family in (
            state.site_states, state.histories, state.relationships,
            state.fields, state.globals, state.membranes, state.delays)
        append!(blocks, map(_state_block, family))
    end
    sort!(blocks; by = block -> (String(block.family), String(block.name)))
    identities = Tuple((block.family, block.name) for block in blocks)
    length(unique(identities)) == length(identities) || throw(ArgumentError(
        "coupled checkpoint block identities must be unique"))
    return Tuple(blocks)
end

_checkpoint_arrays(state::SitePropertyState) = (state.values,)
_checkpoint_arrays(state::CellHistoryState) = (
    state.values, state.heads, state.fills, state.generations)
_checkpoint_arrays(::RelationshipState) = ()
_checkpoint_arrays(state::EvolvingFieldState) = (
    state.values, state.forcing, state.publication_epoch)
_checkpoint_arrays(::ContinuousSystemState) = ()
_checkpoint_arrays(::GlobalPropertyState) = ()
_checkpoint_arrays(state::FieldExchangeState) = (
    state.value, state.initialized, state.publication_epoch)
_checkpoint_arrays(state::AffineCellRuntime) =
    (state.workspace.publication_epoch,)
_checkpoint_arrays(state::MembranePropertyState) = (
    state.values, state.generations, state.active)
_checkpoint_arrays(::DelayStateStorage) = ()
_checkpoint_arrays(::EventRuntimeState) = ()

function _record_coupled_checkpoint_transfers!(
        plan::ExecutionPlan, state::CoupledState)
    plan.backend isa KernelAbstractions.CPU && return plan
    for family in (
            state.site_states, state.histories, state.relationships,
            state.fields, state.globals, state.membranes, state.delays)
        for item in family, array in _checkpoint_arrays(item)
            record_transfer!(plan, :device_to_host)
        end
    end
    return plan
end

function _coupled_initial_state_fingerprint(state::CoupledState)
    blocks = _coupled_blocks(state)
    return _canonical_digest(Tuple((
        block.family, block.name, block.metadata, block.payload)
        for block in blocks))
end

function _coupled_model_fingerprint(integrator::CoupledIntegrator, blocks)
    integrator.semantic_model === nothing || return _canonical_digest(
        integrator.potts |> scientific_model_fingerprint,
        _semantic_record(integrator.semantic_model))
    return _canonical_digest(
        integrator.potts |> scientific_model_fingerprint,
        _semantic_record(integrator.plan),
        _semantic_record(integrator.protocol),
        Tuple((block.family, block.name, block.contract,
            block.version, block.metadata) for block in blocks))
end

function _protocol_position(integrator::CoupledIntegrator)
    return (
        stage = integrator.stage,
        stage_local_mcs = integrator.stage_local_mcs,
        completed_mcs = integrator.mcs,
        global_time = global_time(integrator),
        plan = _semantic_record(integrator.plan),
        protocol = _semantic_record(integrator.protocol))
end

function _observation_schedule(integrator::CoupledIntegrator)
    return (
        completed_mcs = integrator.observations.completed_mcs,
        last_published = Tuple(sort!(collect(
            integrator.observations.last_published);
            by = pair -> String(first(pair)))),
        publication_epochs = Tuple(sort!(collect(
            integrator.observations.publication_epochs);
            by = pair -> String(first(pair)))))
end

function _coupled_state_digest(blocks, protocol, observation)
    return _canonical_digest(
        Tuple(block.checksum for block in blocks), protocol, observation)
end

function _coupled_envelope_digest(checkpoint::CoupledCheckpoint)
    return _canonical_digest(
        checkpoint.schema_version, checkpoint.complete,
        checkpoint.mcs, checkpoint.phase, checkpoint.base.checksum,
        checkpoint.extension.version,
        Tuple(block.checksum for block in checkpoint.extension.blocks),
        checkpoint.extension.protocol_position,
        checkpoint.extension.observation_schedule,
        checkpoint.coupled_model_fingerprint,
        checkpoint.state_schema_fingerprint,
        checkpoint.initial_state_fingerprint,
        checkpoint.ancestry_fingerprint,
        checkpoint.state_fingerprint,
        checkpoint.warnings)
end

function capture_checkpoint(integrator::CoupledIntegrator;
        ancestry::Union{Nothing, CoupledCheckpoint} = nothing)
    integrator.checkpoint_stable || throw(ArgumentError(
        "a partial target MCS is not a stable coupled checkpoint boundary"))
    integrator.terminal_error === nothing || throw(ArgumentError(
        "a failed target MCS is not a stable coupled checkpoint boundary"))
    integrator.potts.mcs == integrator.mcs || throw(ArgumentError(
        "coupled and Potts completed-MCS clocks disagree"))
    integrator.observations.completed_mcs == integrator.mcs || throw(
        ArgumentError(
            "coupled checkpoint requires a completed ObservationPhase"))
    base_ancestry = ancestry === nothing ? nothing : ancestry.base
    base = capture_checkpoint(integrator.potts; ancestry = base_ancestry)
    base.mcs == integrator.mcs || throw(ArgumentError(
        "base and coupled checkpoint MCS values disagree"))
    _record_coupled_checkpoint_transfers!(
        integrator.potts.plan, integrator.state)
    blocks = _coupled_blocks(integrator.state)
    protocol = _protocol_position(integrator)
    observation = _observation_schedule(integrator)
    extension = CoupledCheckpointExtension(
        COUPLED_EXTENSION_BLOCK_VERSION, blocks, protocol, observation)
    model_fingerprint = _coupled_model_fingerprint(integrator, blocks)
    schema_fingerprint = _canonical_digest(Tuple((
        block.family, block.name, block.contract,
        block.version, block.metadata, block.required) for block in blocks))
    state_fingerprint =
        _coupled_state_digest(blocks, protocol, observation)
    ancestry_fingerprint = ancestry === nothing ?
        _ZERO_DIGEST : ancestry.checksum
    provisional = CoupledCheckpoint(
        COUPLED_CHECKPOINT_SCHEMA_VERSION, true, integrator.mcs,
        _COUPLED_PHASE_COMPLETED, base, extension,
        model_fingerprint, schema_fingerprint,
        integrator.initial_state_fingerprint, ancestry_fingerprint,
        state_fingerprint, (), _ZERO_DIGEST)
    checkpoint = CoupledCheckpoint(
        provisional.schema_version, provisional.complete,
        provisional.mcs, provisional.phase, provisional.base,
        provisional.extension, provisional.coupled_model_fingerprint,
        provisional.state_schema_fingerprint,
        provisional.initial_state_fingerprint,
        provisional.ancestry_fingerprint,
        provisional.state_fingerprint, provisional.warnings,
        _coupled_envelope_digest(provisional))
    return validate_checkpoint(checkpoint)
end

function validate_checkpoint(checkpoint::CoupledCheckpoint)
    checkpoint.schema_version == COUPLED_CHECKPOINT_SCHEMA_VERSION || throw(
        CheckpointCompatibilityError(:coupled_schema,
            string(COUPLED_CHECKPOINT_SCHEMA_VERSION),
            string(checkpoint.schema_version)))
    checkpoint.complete || throw(IncompleteCheckpointError("coupled envelope"))
    checkpoint.phase == _COUPLED_PHASE_COMPLETED || throw(
        CheckpointIntegrityError("coupled checkpoint phase is not completed"))
    validate_checkpoint(checkpoint.base)
    checkpoint.base.mcs == checkpoint.mcs || throw(
        CheckpointIntegrityError(
            "base and coupled checkpoint MCS values differ"))
    identities = Tuple((block.family, block.name)
        for block in checkpoint.extension.blocks)
    issorted(identities; by = item ->
        (String(first(item)), String(last(item)))) || throw(
        CheckpointIntegrityError(
            "coupled checkpoint blocks are not canonically ordered"))
    length(unique(identities)) == length(identities) || throw(
        CheckpointIntegrityError(
            "coupled checkpoint contains duplicate block identities"))
    for block in checkpoint.extension.blocks
        expected = _block_checksum(block.family, block.name,
            block.contract, block.version, block.metadata,
            block.payload, block.required)
        block.checksum == expected || throw(CheckpointIntegrityError(
            "coupled checkpoint block $(block.family)/$(block.name) failed integrity validation"))
    end
    expected_state = _coupled_state_digest(
        checkpoint.extension.blocks,
        checkpoint.extension.protocol_position,
        checkpoint.extension.observation_schedule)
    checkpoint.state_fingerprint == expected_state || throw(
        CheckpointIntegrityError(
            "coupled checkpoint state fingerprint failed integrity validation"))
    checkpoint.checksum == _coupled_envelope_digest(checkpoint) || throw(
        CheckpointIntegrityError(
            "coupled checkpoint envelope checksum failed integrity validation"))
    return checkpoint
end

function _find_state(state::CoupledState, block::CoupledCheckpointBlock)
    family = block.family
    states = family === :site_property ? state.site_states :
        family === :cell_history ? state.histories :
        family === :relationship_set ? state.relationships :
        family === :evolving_field ? state.fields :
        family in (:continuous_system, :global_property,
            :field_exchange_state, :affine_cell_runtime) ?
            state.globals :
        family === :membrane_property ? state.membranes :
        family in (:delay_state, :continuous_event) ? state.delays :
        throw(CheckpointCompatibilityError(:block_family,
            "registered target family", String(family)))
    return _state_by_name(states, block.name)
end

function _restore_block!(state::SitePropertyState, block)
    size(state.values) == size(block.payload.values) || throw(
        CheckpointCompatibilityError(:site_property_dims,
            string(size(state.values)), string(size(block.payload.values))))
    copyto!(state.values, block.payload.values)
    state.semantic_time = block.payload.semantic_time
end
function _restore_block!(state::CellHistoryState, block)
    size(state.values) == size(block.payload.values) || throw(
        CheckpointCompatibilityError(:history_capacity,
            string(size(state.values)), string(size(block.payload.values))))
    copyto!(state.values, block.payload.values)
    copyto!(state.heads, block.payload.heads)
    copyto!(state.fills, block.payload.fills)
    copyto!(state.generations, block.payload.generations)
    state.latest_sample_mcs = block.payload.latest_sample_mcs
end
function _restore_block!(state::RelationshipState, block)
    count = Int(block.payload.count)
    count <= length(state.endpoint_a) || throw(
        CheckpointCompatibilityError(:relationship_capacity,
            string(length(state.endpoint_a)), string(count)))
    clear_relationships!(state)
    count > 0 && begin
        copyto!(@view(state.endpoint_a[1:count]), block.payload.endpoint_a)
        copyto!(@view(state.generation_a[1:count]), block.payload.generation_a)
        copyto!(@view(state.endpoint_b[1:count]), block.payload.endpoint_b)
        copyto!(@view(state.generation_b[1:count]), block.payload.generation_b)
        copyto!(@view(state.payload[1:count]), block.payload.edge_payload)
        fill!(@view(state.active[1:count]), UInt8(1))
    end
    state.count[1] = UInt32(count)
    copyto!(state.publication_epoch, block.payload.publication_epoch)
end
function _restore_block!(state::EvolvingFieldState, block)
    size(state.values) == size(block.payload.values) || throw(
        CheckpointCompatibilityError(:field_dims,
            string(size(state.values)), string(size(block.payload.values))))
    copyto!(state.values, block.payload.values)
    copyto!(state.forcing, block.payload.forcing)
    state.time = block.payload.time
    state.diagnostics = block.payload.diagnostics
    copyto!(state.publication_epoch, block.payload.publication_epoch)
end
function _restore_block!(state::ContinuousSystemState, block)
    propertynames(state.values) == propertynames(block.payload.values) || throw(
        CheckpointCompatibilityError(:continuous_state_schema,
            string(propertynames(state.values)),
            string(propertynames(block.payload.values))))
    state.values = block.payload.values
    state.time = block.payload.time
    state.diagnostics = block.payload.diagnostics
end
function _restore_block!(state::GlobalPropertyState, block)
    set_global_property!(
        state, block.payload.value;
        semantic_time = block.payload.semantic_time)
end
function _restore_block!(state::FieldExchangeState, block)
    length(state.workspace.raw_totals) == block.metadata.capacity || throw(
        CheckpointCompatibilityError(:field_exchange_capacity,
            string(length(state.workspace.raw_totals)),
            string(block.metadata.capacity)))
    copyto!(state.value, block.payload.value)
    copyto!(state.initialized, block.payload.initialized)
    copyto!(state.publication_epoch, block.payload.publication_epoch)
end
function _restore_block!(state::AffineCellRuntime, block)
    length(state.workspace.candidate_state) == block.metadata.capacity || throw(
        CheckpointCompatibilityError(:affine_cell_capacity,
            string(length(state.workspace.candidate_state)),
            string(block.metadata.capacity)))
    copyto!(state.workspace.publication_epoch,
        block.payload.publication_epoch)
end
function _restore_block!(state::MembranePropertyState, block)
    size(state.values) == size(block.payload.values) || throw(
        CheckpointCompatibilityError(:membrane_schema,
            string(size(state.values)),
            string(size(block.payload.values))))
    copyto!(state.values, block.payload.values)
    copyto!(state.generations, block.payload.generations)
    copyto!(state.active, block.payload.active)
    state.semantic_time = block.payload.semantic_time
end
function _restore_block!(state::DelayStateStorage, block)
    empty!(state.times)
    append!(state.times, block.payload.times)
    empty!(state.values)
    append!(state.values, block.payload.values)
    state.latest_time = block.payload.latest_time
end
function _restore_block!(state::EventRuntimeState, block)
    state.previous_condition = block.payload.previous_condition
    state.latched = block.payload.latched
    empty!(state.queue)
    append!(state.queue, block.payload.queue)
    empty!(state.lifecycle_requests)
    append!(state.lifecycle_requests, block.payload.lifecycle_requests)
end

function _accepted_copy_effects(plan::MCSPlan)
    if plan.timeline === nothing
        return only(entry.on_accept for entry in plan.entries
            if entry isa PottsAttempts)
    end
    return only(entry.entry.on_accept for entry in plan.timeline.entries
        if entry isa ScheduledPotts)
end

function restore_checkpoint(checkpoint::CoupledCheckpoint,
        prototype::CoupledIntegrator; adaptor = Array)
    validate_checkpoint(checkpoint)
    checkpoint.initial_state_fingerprint ==
            prototype.initial_state_fingerprint || throw(
        CheckpointCompatibilityError(:coupled_initial_state,
            bytes2hex(collect(prototype.initial_state_fingerprint)),
            bytes2hex(collect(checkpoint.initial_state_fingerprint))))
    candidate_state = deepcopy(prototype.state)
    candidate_blocks = _coupled_blocks(candidate_state)
    candidate_schema = _canonical_digest(Tuple((
        block.family, block.name, block.contract,
        block.version, block.metadata, block.required)
        for block in candidate_blocks))
    checkpoint.state_schema_fingerprint == candidate_schema || throw(
        CheckpointCompatibilityError(:coupled_state_schema,
            bytes2hex(collect(candidate_schema)),
            bytes2hex(collect(checkpoint.state_schema_fingerprint))))
    for block in checkpoint.extension.blocks
        _restore_block!(_find_state(candidate_state, block), block)
    end
    effects = _accepted_copy_effects(prototype.plan)
    transaction_effects = rebuild_accepted_copy_effects(
        prototype.potts.algorithm_workspace, candidate_state)
    workspace = isempty(effects) && isempty(transaction_effects) ?
        NoAlgorithmWorkspace() :
        CoupledAttemptWorkspace(
            candidate_state.site_states, effects, transaction_effects)
    restored_potts = _restore_checkpoint(
        checkpoint.base, prototype.potts, adaptor;
        exact = true, algorithm_workspace = workspace)
    expected_model = _coupled_model_fingerprint(prototype, candidate_blocks)
    checkpoint.coupled_model_fingerprint == expected_model || throw(
        CheckpointCompatibilityError(:coupled_model,
            bytes2hex(collect(expected_model)),
            bytes2hex(collect(checkpoint.coupled_model_fingerprint))))
    position = checkpoint.extension.protocol_position
    observation_position = checkpoint.extension.observation_schedule
    observation = CoupledObservationState(
        checkpoint.mcs, Any[], Dict{Symbol, UInt64}(
            observation_position.last_published),
        Dict{Symbol, UInt64}(
            observation_position.publication_epochs))
    restored = CoupledIntegrator(
        restored_potts, prototype.plan, candidate_state,
        prototype.lifecycle, observation, prototype.protocol,
        prototype.semantic_model, prototype.execution_mode,
        checkpoint.mcs, position.stage, position.stage_local_mcs,
        nothing, true, checkpoint.initial_state_fingerprint)
    _protocol_position(restored) == position || throw(
        CheckpointCompatibilityError(:protocol_position,
            string(position), string(_protocol_position(restored))))
    return restored
end

mutable struct CoupledMemoryCheckpointStore
    records::Dict{String, CoupledCheckpoint}
end
CoupledMemoryCheckpointStore() =
    CoupledMemoryCheckpointStore(Dict{String, CoupledCheckpoint}())

function write_checkpoint!(store::CoupledMemoryCheckpointStore, key,
        checkpoint::CoupledCheckpoint; fail_after = nothing)
    name = String(key)
    staged = deepcopy(validate_checkpoint(checkpoint))
    fail_after === :payload && throw(ErrorException(
        "injected coupled checkpoint failure after staged payload"))
    store.records[name] = staged
    return store
end

function read_checkpoint(store::CoupledMemoryCheckpointStore, key)
    name = String(key)
    haskey(store.records, name) || throw(KeyError(name))
    return deepcopy(validate_checkpoint(store.records[name]))
end

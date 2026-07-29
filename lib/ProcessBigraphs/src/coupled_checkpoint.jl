const COUPLED_CHECKPOINT_FORMAT_VERSION = "3.0.0"
const COUPLED_CHECKPOINT_SCHEMA = "process-bigraph-logical-checkpoint-v3"

struct CheckpointComponent
    owner::String
    schema_version::String
    replay_class::Symbol
    payload::NamedTuple
    fingerprint::String
end

function CheckpointComponent(
    owner::AbstractString,
    schema_version::AbstractString,
    replay_class::Symbol,
    payload::NamedTuple,
)
    isempty(owner) &&
        _fail(:empty_checkpoint_component_owner,
            "checkpoint component owner cannot be empty")
    isempty(schema_version) &&
        _fail(:empty_checkpoint_component_version,
            "checkpoint component version cannot be empty")
    replay_class in ENGINE_REPLAY_CLASSES ||
        _fail(:unknown_replay_class,
            "checkpoint component has an unknown replay class";
            replay_class)
    owned = deepcopy(payload)
    encode_logical_value(owned)
    fingerprint = canonical_fingerprint((
        :process_bigraph_checkpoint_component_v1,
        String(owner),
        String(schema_version),
        replay_class,
        owned,
    ))
    CheckpointComponent(
        String(owner),
        String(schema_version),
        replay_class,
        owned,
        fingerprint,
    )
end

struct CoupledLogicalCheckpoint{P}
    format_version::String
    payload::P
    payload_bytes::Vector{UInt8}
    integrity::String
end

struct RestoredLogicalCheckpoint{R,S,E}
    runtime::R
    structural_epoch::S
    engines::E
    replay_class::Symbol
    identity_maps::Tuple
end

abstract type AbstractLegacyCheckpointConverter end

engine_checkpoint_payload(
    ::AbstractEngineInstance,
    declaration::EngineDeclaration,
) = _fail(:missing_engine_checkpoint,
    "engine instance does not implement a logical checkpoint payload";
    engine=declaration.id)

restore_engine_checkpoint(
    ::AbstractEngineAdapter,
    declaration::EngineDeclaration,
    ::NamedTuple,
) = _fail(:missing_engine_checkpoint_restore,
    "engine adapter does not implement logical checkpoint restore";
    engine=declaration.id)

legacy_source_fingerprint(
    ::AbstractLegacyCheckpointConverter,
    source,
) = _fail(:missing_legacy_checkpoint_fingerprint,
    "legacy converter does not implement source fingerprinting";
    source=string(typeof(source)))

legacy_checkpoint_component(
    ::AbstractLegacyCheckpointConverter,
    source,
) = _fail(:missing_legacy_checkpoint_conversion,
    "legacy converter does not implement pure conversion";
    source=string(typeof(source)))

_component_payload(component::CheckpointComponent) = (
    owner=component.owner,
    schema_version=component.schema_version,
    replay_class=component.replay_class,
    payload=component.payload,
    fingerprint=component.fingerprint,
)

function _restore_component(payload)
    component = CheckpointComponent(
        payload.owner,
        payload.schema_version,
        payload.replay_class,
        payload.payload,
    )
    component.fingerprint == payload.fingerprint ||
        _fail(:checkpoint_component_integrity_failure,
            "checkpoint component fingerprint does not match";
            owner=payload.owner)
    component
end

_identity_payload(record::StructuralIdentityRecord) = (
    kind=record.identity.kind,
    id=record.identity.id,
    generation=record.identity.generation,
    status=record.status,
    birth_epoch=record.birth_epoch,
    retired_epoch=record.retired_epoch,
)

_lineage_payload(record::StructuralLineage) = (
    child_kind=record.child.kind,
    child_id=record.child.id,
    child_generation=record.child.generation,
    parent=isnothing(record.parent) ? nothing : (
        kind=record.parent.kind,
        id=record.parent.id,
        generation=record.parent.generation,
    ),
    birth_event=record.birth_event,
    birth_epoch=record.birth_epoch,
)

function _structural_checkpoint_payload(epoch::DynamicStructuralEpoch)
    (
        contract_version=epoch.contract_version,
        ordinal=epoch.ordinal,
        fingerprint=epoch.fingerprint,
        topology_fingerprint=structural_fingerprint(epoch.structure),
        topology=tuple((
            (
                object=object,
                rows=tuple((
                    NamedTuple{(layout.attrs..., layout.homs...)}(tuple((
                        deepcopy(_attr(epoch.structure, row, property))
                        for property in (layout.attrs..., layout.homs...)
                    )...))
                    for row in _rows(epoch.structure, object)
                )...),
            )
            for (object, layout) in pairs(_STRUCTURAL_LAYOUT)
        )...),
        identities=tuple((_identity_payload(record)
            for record in epoch.identities)...),
        lineage=tuple((_lineage_payload(record)
            for record in epoch.lineage)...),
        capacity=(
            composites=epoch.capacity.composites,
            total_parts=epoch.capacity.total_parts,
        ),
    )
end

function _restore_structural_identity(payload)
    StructuralIdentity(
        payload.kind, payload.id, payload.generation)
end

function _restore_structural_identity_record(payload)
    StructuralIdentityRecord(
        _restore_structural_identity(payload),
        payload.status,
        payload.birth_epoch,
        payload.retired_epoch,
    )
end

function _restore_structural_lineage(payload)
    StructuralLineage(
        _restore_structural_identity((
            kind=payload.child_kind,
            id=payload.child_id,
            generation=payload.child_generation,
        )),
        isnothing(payload.parent) ? nothing :
            _restore_structural_identity(payload.parent),
        payload.birth_event,
        payload.birth_epoch,
    )
end

function _restore_structural_topology(payload)
    expected_objects = tuple(keys(_STRUCTURAL_LAYOUT)...)
    tuple((value.object for value in payload)...) == expected_objects ||
        _fail(:checkpoint_topology_schema_mismatch,
            "logical checkpoint topology object order is incompatible")
    structure = ProcessBigraphACSet()
    for object_payload in payload
        layout = _STRUCTURAL_LAYOUT[object_payload.object]
        expected_properties = (layout.attrs..., layout.homs...)
        for row in object_payload.rows
            keys(row) == expected_properties ||
                _fail(:checkpoint_topology_row_mismatch,
                    "logical checkpoint topology row has incompatible fields";
                    object=object_payload.object)
            ACSets.add_part!(
                structure, object_payload.object; row...)
        end
    end
    _validate_structure_shape(structure)
    structure
end

function _managed_checkpoint_component(runtime::ManagedEngineRuntime)
    runtime.is_settled ||
        _fail(:unsettled_checkpoint,
            "managed engine checkpoints require a settled boundary";
            engine=runtime.declaration.id)
    runtime.last_failure === nothing ||
        _fail(:failed_engine_checkpoint,
            "failed managed engine must be reconstructed before checkpoint";
            engine=runtime.declaration.id)
    engine = engine_checkpoint_payload(
        runtime.instance, runtime.declaration)
    engine isa CheckpointComponent ||
        _fail(:invalid_engine_checkpoint_component,
            "engine checkpoint method must return CheckpointComponent";
            engine=runtime.declaration.id, actual=string(typeof(engine)))
    CheckpointComponent(
        runtime.declaration.id,
        "managed-engine-component-v1",
        engine.replay_class,
        (
            runtime=_managed_engine_payload(runtime),
            engine=_component_payload(engine),
        ),
    )
end

function capture_logical_checkpoint(
    runtime::SerialRuntime;
    structural_epoch::Union{Nothing,DynamicStructuralEpoch}=nothing,
    managed_engines=(),
    components=(),
    identity_maps=(),
)
    runtime.is_settled ||
        _fail(:unsettled_checkpoint,
            "logical checkpoints require a settled serial runtime")
    base = logical_checkpoint(runtime)
    blocks = CheckpointComponent[]
    append!(blocks, CheckpointComponent[components...])
    append!(blocks, CheckpointComponent[
        _managed_checkpoint_component(engine) for engine in managed_engines])
    owners = String[component.owner for component in blocks]
    length(owners) == length(unique(owners)) ||
        _fail(:duplicate_checkpoint_component,
            "logical checkpoint contains duplicate component owners")
    sort!(blocks; by=component -> component.owner)
    maps = tuple(sort!(Pair{String,String}[
        String(first(pair)) => String(last(pair))
        for pair in identity_maps
    ]; by=first)...)
    replay_classes = Symbol[:exact]
    append!(replay_classes, Symbol[
        component.replay_class for component in blocks])
    payload = (
        schema=COUPLED_CHECKPOINT_SCHEMA,
        format_version=COUPLED_CHECKPOINT_FORMAT_VERSION,
        logical_value_codec=LOGICAL_VALUE_CODEC_VERSION,
        base_checkpoint=encode_checkpoint(base),
        structural=isnothing(structural_epoch) ?
            nothing : _structural_checkpoint_payload(structural_epoch),
        components=tuple((_component_payload(component)
            for component in blocks)...),
        identity_maps=maps,
        aggregate_replay=aggregate_replay_class(replay_classes),
    )
    payload_bytes = encode_logical_value(payload)
    CoupledLogicalCheckpoint(
        COUPLED_CHECKPOINT_FORMAT_VERSION,
        payload,
        payload_bytes,
        bytes2hex(sha256(payload_bytes)),
    )
end

function _validate_logical_checkpoint(checkpoint::CoupledLogicalCheckpoint)
    checkpoint.format_version == COUPLED_CHECKPOINT_FORMAT_VERSION ||
        _fail(:unsupported_checkpoint_version,
            "logical checkpoint format is unsupported";
            version=checkpoint.format_version)
    payload_bytes = encode_logical_value(checkpoint.payload)
    payload_bytes == checkpoint.payload_bytes ||
        _fail(:checkpoint_payload_mismatch,
            "logical checkpoint cached bytes differ from its payload")
    integrity = bytes2hex(sha256(payload_bytes))
    integrity == checkpoint.integrity ||
        _fail(:checkpoint_integrity_failure,
            "logical checkpoint integrity hash does not match";
            expected=checkpoint.integrity, actual=integrity)
    checkpoint.payload.schema == COUPLED_CHECKPOINT_SCHEMA &&
        checkpoint.payload.format_version == COUPLED_CHECKPOINT_FORMAT_VERSION ||
        _fail(:unsupported_checkpoint_schema,
            "logical checkpoint payload schema is unsupported")
    components = CheckpointComponent[
        _restore_component(value) for value in checkpoint.payload.components]
    aggregate_replay_class(Symbol[
        :exact, (component.replay_class for component in components)...
    ]) == checkpoint.payload.aggregate_replay ||
        _fail(:checkpoint_replay_mismatch,
            "logical checkpoint aggregate replay classification is invalid")
    true
end

function encode_checkpoint(checkpoint::CoupledLogicalCheckpoint)
    _validate_logical_checkpoint(checkpoint)
    encode_logical_value((
        schema=COUPLED_CHECKPOINT_SCHEMA,
        format_version=checkpoint.format_version,
        payload=checkpoint.payload,
        integrity=checkpoint.integrity,
    ))
end

function decode_logical_checkpoint(bytes::AbstractVector{UInt8})
    envelope = decode_logical_value(bytes)
    envelope isa NamedTuple &&
        hasproperty(envelope, :schema) &&
        hasproperty(envelope, :format_version) &&
        hasproperty(envelope, :payload) &&
        hasproperty(envelope, :integrity) ||
        _fail(:invalid_checkpoint_envelope,
            "decoded logical checkpoint has an invalid envelope")
    envelope.schema == COUPLED_CHECKPOINT_SCHEMA ||
        _fail(:unsupported_checkpoint_schema,
            "checkpoint is not a logical envelope";
            schema=envelope.schema)
    payload_bytes = encode_logical_value(envelope.payload)
    checkpoint = CoupledLogicalCheckpoint(
        envelope.format_version,
        envelope.payload,
        payload_bytes,
        envelope.integrity,
    )
    _validate_logical_checkpoint(checkpoint)
    checkpoint
end

checkpoint_fingerprint(checkpoint::CoupledLogicalCheckpoint) =
    checkpoint.integrity

function _validate_structural_restore(
    payload,
    epoch::Union{Nothing,DynamicStructuralEpoch},
)
    isnothing(payload) && return nothing
    payload.contract_version == STRUCTURAL_TRANSACTION_VERSION ||
        _fail(:checkpoint_structure_version_mismatch,
            "logical checkpoint structural contract is incompatible";
            expected=STRUCTURAL_TRANSACTION_VERSION,
            actual=payload.contract_version)
    structure = _restore_structural_topology(payload.topology)
    payload.topology_fingerprint == structural_fingerprint(structure) ||
        _fail(:checkpoint_structure_mismatch,
            "logical checkpoint structural topology fingerprint is invalid")
    identities = tuple((_restore_structural_identity_record(value)
        for value in payload.identities)...)
    lineage = tuple((_restore_structural_lineage(value)
        for value in payload.lineage)...)
    capacity = StructuralCapacity(
        composites=payload.capacity.composites,
        total_parts=payload.capacity.total_parts,
    )
    _validate_capacity(structure, capacity)
    restored = DynamicStructuralEpoch(
        payload.contract_version,
        payload.ordinal,
        structure,
        payload.fingerprint,
        identities,
        lineage,
        capacity,
    )
    expected = _structural_epoch_fingerprint(
        restored.ordinal,
        restored.structure,
        restored.identities,
        restored.lineage,
        restored.capacity,
    )
    expected == restored.fingerprint ||
        _fail(:checkpoint_structure_fingerprint_mismatch,
            "logical checkpoint structural epoch fingerprint is invalid";
            expected, actual=restored.fingerprint)
    if !isnothing(epoch)
        epoch.fingerprint == restored.fingerprint &&
            structural_fingerprint(epoch.structure) ==
                structural_fingerprint(restored.structure) ||
            _fail(:checkpoint_structure_prototype_mismatch,
                "supplied structural prototype disagrees with checkpoint")
    end
    restored
end

function _restore_managed_engine(
    payload,
    declaration::EngineDeclaration,
)
    payload.runtime.declaration_id == declaration.id &&
        payload.runtime.declaration_fingerprint ==
            declaration.fingerprint ||
        _fail(:checkpoint_engine_declaration_mismatch,
            "managed engine declaration changed";
            engine=declaration.id)
    engine_component = _restore_component(payload.engine)
    instance = restore_engine_checkpoint(
        declaration.adapter, declaration, engine_component.payload)
    ManagedEngineRuntime(
        declaration,
        instance,
        payload.runtime.logical_time,
        payload.runtime.structural_epoch,
        payload.runtime.invocation_ordinal,
        payload.runtime.publication_version,
        true,
        nothing,
        nothing,
    )
end

function restore_logical_checkpoint(
    composite::CompiledComposite,
    executor::SerialExecutor,
    checkpoint::CoupledLogicalCheckpoint;
    structural_epoch::Union{Nothing,DynamicStructuralEpoch}=nothing,
    engine_declarations=(),
)
    _validate_logical_checkpoint(checkpoint)
    base = decode_checkpoint(checkpoint.payload.base_checkpoint)
    runtime = restore(composite, executor, base)
    structure = _validate_structural_restore(
        checkpoint.payload.structural, structural_epoch)
    declarations = Dict(declaration.id => declaration
        for declaration in engine_declarations)
    engines = Pair{String,Any}[]
    for value in checkpoint.payload.components
        component = _restore_component(value)
        if component.schema_version == "managed-engine-component-v1"
            haskey(declarations, component.owner) ||
                _fail(:checkpoint_engine_declaration_missing,
                    "checkpoint engine declaration was not supplied";
                    engine=component.owner)
            push!(engines, component.owner =>
                _restore_managed_engine(
                    component.payload, declarations[component.owner]))
        end
    end
    RestoredLogicalCheckpoint(
        runtime,
        structure,
        tuple(sort!(engines; by=first)...),
        checkpoint.payload.aggregate_replay,
        checkpoint.payload.identity_maps,
    )
end

function convert_legacy_checkpoint(
    runtime::SerialRuntime,
    converter::AbstractLegacyCheckpointConverter,
    source;
    structural_epoch::Union{Nothing,DynamicStructuralEpoch}=nothing,
    managed_engines=(),
    identity_maps=(),
)
    before = legacy_source_fingerprint(converter, source)
    component = legacy_checkpoint_component(converter, source)
    component isa CheckpointComponent ||
        _fail(:invalid_legacy_checkpoint_component,
            "legacy converter must return CheckpointComponent")
    after = legacy_source_fingerprint(converter, source)
    before == after ||
        _fail(:destructive_legacy_conversion,
            "legacy conversion mutated its source checkpoint")
    provenance = CheckpointComponent(
        string(component.owner, ":conversion"),
        "legacy-conversion-v1",
        component.replay_class,
        (
            source_fingerprint=before,
            converted_component=component.fingerprint,
        ),
    )
    capture_logical_checkpoint(
        runtime;
        structural_epoch,
        managed_engines,
        components=(component, provenance),
        identity_maps,
    )
end

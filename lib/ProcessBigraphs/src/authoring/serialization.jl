const SEMANTIC_MODEL_FORMAT_VERSION = "1.0.0"
const SEMANTIC_MODEL_FORMAT_ID = "process-bigraph-semantic-model-v1"

function _component_contract(law)
    (
        type=string(typeof(law)),
        semantic_version=semantic_version(law),
        semantic_parameters=semantic_parameters(law),
        ports=tuple(ports(law)...),
        capabilities=capabilities(law),
    )
end

function _encoded_component(law, encode_component)
    record = encode_component(law)
    record isa NamedTuple &&
        (:id in keys(record)) &&
        (:version in keys(record)) &&
        (:payload in keys(record)) ||
        _fail(:invalid_semantic_component_encoding,
            "component encoder must return (id, version, payload)")
    id = String(record.id)
    version = String(record.version)
    isempty(id) &&
        _fail(:empty_semantic_component_codec,
            "component codec identity cannot be empty")
    isempty(version) &&
        _fail(:empty_semantic_component_codec_version,
            "component codec version cannot be empty"; id)
    encode_logical_value(record.payload)
    (
        id=id,
        version=version,
        payload=deepcopy(record.payload),
        contract_fingerprint=canonical_fingerprint(
            _component_contract(law)),
    )
end

function _schedule_payload(schedule)
    schedule isa FixedSchedule && return (
        kind=:fixed,
        cadence=schedule.cadence,
        first_due=schedule.first_due,
        supports_partial=schedule.supports_partial,
    )
    schedule isa AdaptiveSchedule && return (
        kind=:adaptive,
        first_due=schedule.first_due,
        supports_partial=schedule.supports_partial,
    )
    schedule isa At && return (
        kind=:at,
        times=schedule.times,
    )
    _fail(:unsupported_semantic_schedule_codec,
        "semantic model serialization does not support this schedule";
        schedule=string(typeof(schedule)))
end

function _decode_schedule(payload)
    payload.kind === :fixed && return FixedSchedule(
        payload.cadence;
        first_due=payload.first_due,
        supports_partial=payload.supports_partial)
    payload.kind === :adaptive && return AdaptiveSchedule(
        payload.first_due;
        supports_partial=payload.supports_partial)
    payload.kind === :at && return At(payload.times)
    _fail(:unknown_semantic_schedule_codec,
        "semantic model archive contains an unknown schedule kind";
        kind=payload.kind)
end

function _model_payload(model::CompositeModel, encode_component)
    (
        contract_version=model.contract_version,
        name=model.name,
        scale=model.scale,
        stores=tuple((
            (
                name=store.name,
                target=store.target,
                schema=store.schema,
                has_initial=store.has_initial,
                initial=store.has_initial ? store.initial : nothing,
            )
            for store in model.stores
        )...),
        actors=tuple((
            (
                name=actor.name,
                kind=actor.kind,
                component=_encoded_component(
                    actor.law, encode_component),
                schedule=isnothing(actor.schedule) ?
                    nothing : _schedule_payload(actor.schedule),
                dependencies=actor.dependencies,
                domain=actor.domain,
                continuation=actor.continuation,
                continuation_version=actor.continuation_version,
            )
            for actor in model.actors
        )...),
        bindings=tuple((
            (
                component=binding.component,
                port=binding.port,
                target=binding.target,
                transfer=binding.transfer,
            )
            for binding in model.bindings
        )...),
        iterations=tuple((
            (
                id=region.id,
                steps=region.steps,
                mode=region.mode,
                max_iterations=region.max_iterations,
                watch_paths=region.watch_paths,
            )
            for region in model.iterations
        )...),
        endpoints=tuple((
            (
                name=endpoint.name,
                target=endpoint.target,
                role=endpoint.role,
                transfer=endpoint.transfer,
            )
            for endpoint in model.endpoints
        )...),
        parameters=tuple((
            (
                name=parameter.name,
                default=parameter.default,
                units=parameter.units,
                description=parameter.description,
            )
            for parameter in getfield(model, :parameters)
        )...),
        observables=tuple((
            (
                name=observable.name,
                target=observable.target,
                schema=observable.schema,
                description=observable.description,
            )
            for observable in getfield(model, :observables)
        )...),
        templates=tuple((
            (
                name=template.name,
                definition_id=template.definition_id,
                model=_model_payload(
                    template.model, encode_component),
                capacity=template.capacity,
            )
            for template in model.templates
        )...),
        mounts=tuple((
            (
                name=mount.name,
                model=_model_payload(
                    mount.model, encode_component),
            )
            for mount in model.mounts
        )...),
        mounted_bindings=tuple((
            (
                mount=binding.mount,
                endpoint=binding.endpoint,
                target=binding.target,
            )
            for binding in model.mounted_bindings
        )...),
        profile=model.profile,
        semantic_fingerprint=model.fingerprint,
    )
end

"""
Encode a semantic model with an explicit domain-owned component encoder.

The callback returns `(id, version, payload)` for each component law. Its
payload must be admitted by the logical value codec. No closure, decoder,
runtime cache, or global registry is serialized.
"""
function encode_semantic_model(
    model::CompositeModel;
    encode_component,
)
    payload = (
        format_id=SEMANTIC_MODEL_FORMAT_ID,
        format_version=SEMANTIC_MODEL_FORMAT_VERSION,
        authoring_contract=AUTHORING_CONTRACT_VERSION,
        model=_model_payload(model, encode_component),
    )
    encode_logical_value(payload)
end

function _decoded_component(record, decode_component, kind::Symbol)
    law = decode_component(
        String(record.id),
        String(record.version),
        deepcopy(record.payload))
    if kind === :process
        law isa AbstractProcess ||
            _fail(:semantic_component_kind_mismatch,
                "component decoder did not return an AbstractProcess";
                codec=record.id, actual=string(typeof(law)))
    elseif kind === :step
        law isa AbstractStep ||
            _fail(:semantic_component_kind_mismatch,
                "component decoder did not return an AbstractStep";
                codec=record.id, actual=string(typeof(law)))
    else
        _fail(:unknown_semantic_component_kind,
            "semantic model archive contains an unknown component kind";
            kind)
    end
    canonical_fingerprint(_component_contract(law)) ==
            record.contract_fingerprint ||
        _fail(:semantic_component_contract_mismatch,
            "decoded component does not match its archived semantic contract";
            codec=record.id)
    law
end

function _model_from_payload(payload, decode_component)
    stores = tuple((
        SemanticStore(
            record.name,
            record.target,
            record.schema,
            record.has_initial,
            record.has_initial ? deepcopy(record.initial) : nothing)
        for record in payload.stores
    )...)
    actors = tuple((
        SemanticActor(
            record.name,
            _decoded_component(
                record.component, decode_component, record.kind),
            record.kind,
            isnothing(record.schedule) ?
                nothing : _decode_schedule(record.schedule),
            tuple(record.dependencies...),
            record.domain,
            deepcopy(record.continuation),
            String(record.continuation_version))
        for record in payload.actors
    )...)
    bindings = tuple((
        SemanticBinding(
            record.component,
            record.port,
            record.target,
            record.transfer)
        for record in payload.bindings
    )...)
    iterations = tuple((
        IterationRegion(
            record.id,
            record.steps;
            mode=record.mode,
            max_iterations=record.max_iterations,
            watch_paths=record.watch_paths)
        for record in payload.iterations
    )...)
    endpoints = tuple((
        SemanticEndpoint(
            record.name,
            record.target,
            record.role,
            record.transfer)
        for record in payload.endpoints
    )...)
    parameters = tuple((
        SemanticParameter(
            record.name,
            deepcopy(record.default),
            record.units,
            record.description)
        for record in payload.parameters
    )...)
    observables = tuple((
        SemanticObservable(
            record.name,
            record.target,
            record.schema,
            record.description)
        for record in payload.observables
    )...)
    templates = tuple((
        SemanticTemplate(
            record.name,
            record.definition_id,
            _model_from_payload(record.model, decode_component),
            record.capacity)
        for record in payload.templates
    )...)
    mounts = tuple((
        SemanticMount(
            record.name,
            _model_from_payload(record.model, decode_component))
        for record in payload.mounts
    )...)
    mounted_bindings = tuple((
        SemanticMountedBinding(
            record.mount,
            record.endpoint,
            record.target)
        for record in payload.mounted_bindings
    )...)
    fingerprint = _composite_identity(
        payload.name,
        payload.scale,
        stores,
        actors,
        bindings,
        iterations,
        endpoints,
        parameters,
        observables,
        templates,
        mounts,
        mounted_bindings,
        payload.profile)
    fingerprint == payload.semantic_fingerprint ||
        _fail(:semantic_model_fingerprint_mismatch,
            "decoded semantic model does not match its archived fingerprint";
            expected=payload.semantic_fingerprint,
            actual=fingerprint)
    model = CompositeModel(
        String(payload.contract_version),
        payload.name,
        payload.scale,
        stores,
        actors,
        bindings,
        iterations,
        endpoints,
        parameters,
        observables,
        templates,
        mounts,
        mounted_bindings,
        payload.profile,
        fingerprint)
    report = validate(model)
    isempty(report) || throw(ModelValidationError(report))
    model
end

function migrate_semantic_model_payload(payload)
    payload.format_id == SEMANTIC_MODEL_FORMAT_ID ||
        _fail(:semantic_model_format_id,
            "archive is not a ProcessBigraphs semantic model";
            actual=payload.format_id)
    payload.format_version == SEMANTIC_MODEL_FORMAT_VERSION ||
        _fail(:unsupported_semantic_model_version,
            "semantic model archive requires an explicit registered migration";
            actual=payload.format_version,
            supported=SEMANTIC_MODEL_FORMAT_VERSION)
    payload.authoring_contract == AUTHORING_CONTRACT_VERSION ||
        _fail(:semantic_model_contract_mismatch,
            "semantic model archive uses another authoring contract";
            actual=payload.authoring_contract,
            supported=AUTHORING_CONTRACT_VERSION)
    payload
end

"""
Decode a semantic model using an explicit domain-owned component decoder.

The callback receives `(id, version, payload)` and must reconstruct a component
whose complete semantic contract matches the archive.
"""
function decode_semantic_model(
    bytes::AbstractVector{UInt8};
    decode_component,
)
    payload = migrate_semantic_model_payload(
        decode_logical_value(bytes))
    _model_from_payload(payload.model, decode_component)
end

function describe(model::CompositeModel)
    (
        name=model.name,
        contract_version=model.contract_version,
        profile=model.profile,
        stores=tuple((store.name for store in model.stores)...),
        components=tuple((actor.name for actor in model.actors)...),
        mounts=tuple((mount.name for mount in model.mounts)...),
        parameters=tuple((parameter.name
            for parameter in getfield(model, :parameters))...),
        observables=tuple((observable.name
            for observable in getfield(model, :observables))...),
        semantic_fingerprint=model.fingerprint,
    )
end

function explain(model::CompositeModel, handle::AbstractAuthoringHandle)
    name = getfield(handle, :name)
    (
        model=model.name,
        subject=name,
        semantic_fingerprint=model.fingerprint,
        lowering=tuple((origin for origin in origin_map(lower(model))
            if origin.name === name)...),
    )
end

function explain(model::CompositeModel)
    lowered = lower(model)
    (
        model=model.name,
        semantic_fingerprint=model.fingerprint,
        ir_fingerprint=ir_fingerprint(lowered),
        attachments=tuple((
            (
                component=binding.component,
                port=binding.port,
                store=only(store.name for store in model.stores
                    if store.target == binding.target),
                transfer=binding.transfer,
            )
            for binding in model.bindings
        )...),
        mounted_connections=tuple((
            (
                mount=binding.mount,
                endpoint=binding.endpoint,
                store=only(store.name for store in model.stores
                    if store.target == binding.target),
            )
            for binding in model.mounted_bindings
        )...),
        origins=origin_map(lowered),
    )
end

explain(report::AttachmentReport) = (
    component=report.component,
    connected=report.connected,
    missing_required=report.missing_required,
    extra=report.extra,
    exact=isempty(report.missing_required) && isempty(report.extra),
)


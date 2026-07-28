function _diagnostic(
    code::Symbol,
    message::AbstractString;
    severity::Symbol=:error,
    subject=nothing,
    location=nothing,
    related=(),
    expected=nothing,
    actual=nothing,
    suggestion::AbstractString="Correct the identified declaration and run validate again.",
    context...,
)
    normalized_subject = isnothing(subject) ? nothing : Symbol(subject)
    normalized_location = isnothing(location) ?
        (isnothing(normalized_subject) ? () : (normalized_subject,)) :
        tuple(location...)
    ValidationDiagnostic(
        code, severity, String(message),
        normalized_subject,
        normalized_location,
        tuple(related...),
        deepcopy(expected),
        deepcopy(actual),
        String(suggestion),
        (; context...))
end

function validate(model::CompositeModel; profile::Symbol=model.profile)
    diagnostics = ValidationDiagnostic[]
    actor_names = Set(actor.name for actor in model.actors)
    store_paths = Set(store.target for store in model.stores)
    mount_names = Set(mount.name for mount in model.mounts)
    declared_parameters = Set(parameter.name
        for parameter in getfield(model, :parameters))
    binding_keys = Set{Tuple{Symbol,Symbol}}()

    isempty(model.stores) && isempty(model.mounts) &&
        push!(diagnostics, _diagnostic(
            :empty_composite,
            "a model must declare stores or mount an open composite";
            subject=model.name))

    for actor in model.actors
        required_parameters = tuple(Symbol.(parameter_names(actor.law))...)
        length(required_parameters) == length(unique(required_parameters)) ||
            push!(diagnostics, _diagnostic(
                :duplicate_component_parameter,
                "component parameter_names repeats one declaration";
                subject=actor.name))
        for parameter in required_parameters
            parameter in declared_parameters ||
                push!(diagnostics, _diagnostic(
                    :unknown_component_parameter,
                    "component requires an undeclared model parameter";
                    subject=actor.name, parameter))
        end
        if actor.kind === :process && isnothing(actor.schedule)
            push!(diagnostics, _diagnostic(
                :missing_process_schedule,
                "temporal components require an explicit schedule";
                subject=actor.name))
        elseif actor.kind === :step && !isnothing(actor.schedule)
            push!(diagnostics, _diagnostic(
                :invalid_step_schedule,
                "reactive components use On/After dependencies, not temporal schedules";
                subject=actor.name))
        end
        for dependency in actor.dependencies
            dependency in actor_names ||
                push!(diagnostics, _diagnostic(
                    :unknown_step_dependency,
                    "reactive dependency names an unknown component";
                    subject=actor.name, dependency))
        end
        declared = Dict(port.name => port for port in ports(actor.law))
        for binding in model.bindings
            binding.component === actor.name || continue
            key = (binding.component, binding.port)
            key in binding_keys &&
                push!(diagnostics, _diagnostic(
                    :duplicate_port_binding,
                    "one component port is connected more than once";
                    subject=actor.name, port=binding.port))
            push!(binding_keys, key)
            haskey(declared, binding.port) ||
                push!(diagnostics, _diagnostic(
                    :unknown_bound_port,
                    "connection names an unknown component port";
                    subject=actor.name, port=binding.port))
            binding.target in store_paths ||
                push!(diagnostics, _diagnostic(
                    :unknown_store_path,
                    "connection targets an undeclared store";
                    subject=actor.name, target=binding.target))
        end
        for (name, contract) in declared
            !contract.optional && !((actor.name, name) in binding_keys) &&
                push!(diagnostics, _diagnostic(
                    :unbound_required_port,
                    "required component port has no connection";
                    subject=actor.name, port=name))
        end
    end

    for binding in model.bindings
        binding.component in actor_names ||
            push!(diagnostics, _diagnostic(
                :unknown_binding_owner,
                "connection names an unknown component";
                subject=binding.component))
    end

    store_by_path = Dict(store.target => store for store in model.stores)
    actor_by_name = Dict(actor.name => actor for actor in model.actors)
    for binding in model.bindings
        haskey(actor_by_name, binding.component) || continue
        haskey(store_by_path, binding.target) || continue
        actor = actor_by_name[binding.component]
        port_position = findfirst(port -> port.name === binding.port,
            ports(actor.law))
        isnothing(port_position) && continue
        contract = ports(actor.law)[port_position]
        store = store_by_path[binding.target]
        if !(store.schema isa LeafSchema)
            push!(diagnostics, _diagnostic(
                :port_targets_branch,
                "component ports must connect to leaf stores";
                subject=actor.name, port=binding.port,
                target=binding.target))
            continue
        end
        _port_matches(contract, store.schema) ||
            push!(diagnostics, _diagnostic(
                :port_schema_mismatch,
                "component port type does not match the connected store";
                subject=actor.name, port=binding.port,
                target=binding.target))
        if contract.direction === :output &&
                contract.update_law != store.schema.update_law
            push!(diagnostics, _diagnostic(
                :port_update_law_mismatch,
                "output port update law does not match the connected store";
                subject=actor.name, port=binding.port,
                target=binding.target,
                expected=store.schema.update_law,
                actual=contract.update_law))
        end
    end

    mounted_keys = Set{Tuple{Symbol,Symbol}}()
    for binding in model.mounted_bindings
        binding.mount in mount_names ||
            push!(diagnostics, _diagnostic(
                :unknown_mount,
                "mounted endpoint connection names an unknown mount";
                subject=binding.mount))
        binding.target in store_paths ||
            push!(diagnostics, _diagnostic(
                :unknown_store_path,
                "mounted endpoint connection targets an undeclared store";
                subject=binding.mount, target=binding.target))
        key = (binding.mount, binding.endpoint)
        key in mounted_keys &&
            push!(diagnostics, _diagnostic(
                :duplicate_mounted_endpoint_binding,
                "mounted endpoint is connected more than once";
                subject=binding.mount, endpoint=binding.endpoint))
        push!(mounted_keys, key)
        mount_position = findfirst(mount -> mount.name === binding.mount,
            model.mounts)
        if !isnothing(mount_position)
            child = model.mounts[mount_position].model
            binding.endpoint in _endpoint_names(child) ||
                push!(diagnostics, _diagnostic(
                    :unknown_mounted_endpoint,
                    "mounted endpoint is not exposed by the child model";
                    subject=binding.mount, endpoint=binding.endpoint))
            endpoint_position = findfirst(
                endpoint -> endpoint.name === binding.endpoint,
                child.endpoints)
            parent_position = findfirst(
                store -> store.target == binding.target, model.stores)
            if !isnothing(endpoint_position) && !isnothing(parent_position)
                endpoint = child.endpoints[endpoint_position]
                child_store = only(filter(
                    store -> store.target == endpoint.target,
                    child.stores))
                parent_store = model.stores[parent_position]
                canonical_fingerprint(child_store.schema) ==
                        canonical_fingerprint(parent_store.schema) ||
                    push!(diagnostics, _diagnostic(
                        :junction_schema_mismatch,
                        "mounted endpoint and parent store schemas differ";
                        subject=binding.mount,
                        endpoint=binding.endpoint,
                        target=binding.target))
            end
        end
    end
    for mount in model.mounts, endpoint in _endpoint_names(mount.model)
        (mount.name, endpoint) in mounted_keys ||
            push!(diagnostics, _diagnostic(
                :unbound_mounted_endpoint,
                "every mounted endpoint requires an explicit parent junction";
                subject=mount.name, endpoint))
    end

    for endpoint in model.endpoints
        endpoint.target in store_paths ||
            push!(diagnostics, _diagnostic(
                :unknown_endpoint_store,
                "exposed endpoint targets an undeclared store";
                subject=endpoint.name, target=endpoint.target))
    end

    if profile in (:reproducible, :portable)
        for actor in model.actors
            version = semantic_version(actor.law)
            isempty(version) &&
                push!(diagnostics, _diagnostic(
                    :missing_semantic_version,
                    "reproducible components require a semantic version";
                    subject=actor.name))
            try
                canonical_bytes(semantic_parameters(actor.law))
            catch error
                push!(diagnostics, _diagnostic(
                    :noncanonical_semantic_parameters,
                    "component semantic parameters are not canonically encodable";
                    subject=actor.name, cause=sprint(showerror, error)))
            end
        end
    end

    if !any(diagnostic -> diagnostic.severity === :error, diagnostics) &&
            isempty(model.mounts)
        try
            static = _static_ir(model)
            identities = _validate_identities(static)
            layers = _step_layers(static, identities)
            _validate_bindings(static, layers)
            preflight(static)
        catch error
            code = error isa ProcessBigraphError ?
                error.code : :authoring_preflight_failure
            context = error isa ProcessBigraphError ?
                error.context : (; cause=sprint(showerror, error))
            push!(diagnostics, _diagnostic(
                code,
                error isa ProcessBigraphError ?
                    error.message :
                    "semantic model failed declaration preflight";
                subject=model.name,
                context...))
        end
    end

    ordered = tuple(sort!(diagnostics;
        by=diagnostic -> (
            diagnostic.severity,
            String(diagnostic.code),
            isnothing(diagnostic.subject) ? "" : String(diagnostic.subject),
            diagnostic.message,
        ))...)
    ValidationReport(profile, ordered,
        canonical_fingerprint((
            :authoring_validation_v1,
            profile,
            tuple(((diagnostic.code, diagnostic.severity,
                diagnostic.message, diagnostic.subject,
                diagnostic.location, diagnostic.related,
                diagnostic.expected, diagnostic.actual,
                diagnostic.suggestion,
                diagnostic.context) for diagnostic in ordered)...),
        )))
end

function _complete_composition(
    f::Function,
    builder::CompositeBuilder,
    arguments...,
)
    try
        f(builder, arguments...)
    catch
        builder.closed = true
        rethrow()
    end
    builder.closed = true
    model = _freeze(builder)
    report = validate(model; profile=builder.profile)
    isempty(report) || throw(ModelValidationError(report))
    model
end

function compose(
    f::Function,
    name::Union{Symbol,AbstractString};
    scale::TimeScale,
    profile::Symbol=:interactive,
)
    _complete_composition(
        f, CompositeBuilder(name; scale, profile))
end

"""
Schema-seeded ordinary Julia composition convenience.

This is useful while migrating an existing typed `BranchSchema`: every root
leaf is declared through `store!`, and the callback receives both the builder
and a typed store namespace. Nested schemas use explicit `store!` calls so
their author-facing hierarchy remains intentional.
"""
function compose(
    f::Function,
    name::Union{Symbol,AbstractString},
    schema::BranchSchema;
    scale::TimeScale,
    initial=Dict(),
    profile::Symbol=:interactive,
)
    builder = CompositeBuilder(name; scale, profile)
    supplied = _normalize_values(initial)
    handles = StoreHandle[]
    for (child_name, child_schema) in schema.children
        child_schema isa LeafSchema ||
            _fail(:nested_seeded_schema,
                "schema-seeded compose accepts root leaf children; declare nested hierarchy explicitly";
                child=child_name)
        target = path(child_name)
        push!(handles, store!(
            builder, Symbol(child_name), child_schema;
            initial=get(supplied, target, nothing),
            has_initial=haskey(supplied, target)))
    end
    unknown = setdiff(Set(keys(supplied)),
        Set(getfield(handle, :target) for handle in handles))
    isempty(unknown) ||
        _fail(:unknown_store_path,
            "schema-seeded initial values contain undeclared stores";
            paths=tuple(sort!(collect(unknown))...))
    _complete_composition(f, builder, HandleNamespace(tuple(handles...)))
end

semantic_fingerprint(model::CompositeModel) = model.fingerprint

function Base.show(io::IO, model::CompositeModel)
    print(io, "CompositeModel(:", model.name,
        "; stores=", length(model.stores),
        ", components=", length(model.actors),
        ", mounts=", length(model.mounts),
        ", fingerprint=\"", first(model.fingerprint, 12), "…\")")
end

function Base.show(
    io::IO,
    ::MIME"text/plain",
    model::CompositeModel,
)
    summary = describe(model)
    println(io, "CompositeModel :", summary.name)
    println(io, "  contract:   ", summary.contract_version)
    println(io, "  profile:    ", summary.profile)
    println(io, "  stores:     ", summary.stores)
    println(io, "  components: ", summary.components)
    println(io, "  mounts:     ", summary.mounts)
    println(io, "  parameters: ", summary.parameters)
    println(io, "  observables:", summary.observables)
    print(io, "  fingerprint:", summary.semantic_fingerprint)
end

function Base.getproperty(model::CompositeModel, name::Symbol)
    scope = String(getfield(model, :fingerprint))
    name === :state && return HandleNamespace(tuple((
        StoreHandle(scope, store.name, store.target, store.schema)
        for store in getfield(model, :stores))...))
    name === :components && return HandleNamespace(tuple((
        ComponentHandle(scope, actor.name, actor.law)
        for actor in getfield(model, :actors))...))
    name === :parameters && return HandleNamespace(tuple((
        ParameterHandle(scope, parameter.name, parameter.default)
        for parameter in getfield(model, :parameters))...))
    name === :observables && return HandleNamespace(tuple((
        ObservableHandle(scope, observable.name, observable.target)
        for observable in getfield(model, :observables))...))
    name in fieldnames(typeof(model)) && return getfield(model, name)
    getfield(model, name)
end

Base.propertynames(model::CompositeModel; private::Bool=false) =
    tuple(fieldnames(typeof(model))...,
        :state, :components, :parameters, :observables)


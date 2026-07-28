mutable struct CompositeBuilder
    scope::AuthoringScope
    name::Symbol
    scale::TimeScale
    profile::Symbol
    stores::Vector{SemanticStore}
    actors::Vector{SemanticActor}
    bindings::Vector{SemanticBinding}
    iterations::Vector{IterationRegion}
    endpoints::Vector{SemanticEndpoint}
    parameters::Vector{SemanticParameter}
    observables::Vector{SemanticObservable}
    templates::Vector{SemanticTemplate}
    mounts::Vector{SemanticMount}
    mounted_bindings::Vector{SemanticMountedBinding}
    closed::Bool
end

function CompositeBuilder(
    name::Union{Symbol,AbstractString};
    scale::TimeScale,
    profile::Symbol=:interactive,
)
    profile in (:interactive, :reproducible, :portable) ||
        _fail(:invalid_authoring_profile,
            "authoring profile must be interactive, reproducible, or portable";
            profile)
    identity = Symbol(name)
    isempty(String(identity)) &&
        _fail(:empty_composite_identity,
            "composite identity cannot be empty")
    CompositeBuilder(
        AuthoringScope(), identity, scale, profile,
        SemanticStore[], SemanticActor[], SemanticBinding[],
        IterationRegion[], SemanticEndpoint[], SemanticParameter[],
        SemanticObservable[], SemanticTemplate[], SemanticMount[],
        SemanticMountedBinding[], false)
end

function _ensure_open(builder::CompositeBuilder)
    builder.closed &&
        _fail(:closed_authoring_transaction,
            "a completed composition builder cannot be mutated";
            model=builder.name)
    nothing
end

function _same_scope(builder::CompositeBuilder, handle::AbstractAuthoringHandle)
    getfield(handle, :owner) === builder.scope ||
        _fail(:foreign_authoring_handle,
            "a handle belongs to another composition transaction")
    nothing
end

_names(values) = Symbol[getfield(value, :name) for value in values]

function _unique_name(
    builder::CompositeBuilder,
    name::Symbol,
    namespace::Symbol,
)
    values = if namespace === :store
        builder.stores
    elseif namespace === :component
        vcat(builder.actors, builder.mounts)
    elseif namespace === :parameter
        builder.parameters
    elseif namespace === :observable
        builder.observables
    elseif namespace === :template
        builder.templates
    else
        _fail(:invalid_authoring_namespace,
            "unknown semantic authoring namespace"; namespace)
    end
    name in _names(values) &&
        _fail(:duplicate_authoring_name,
            "semantic names must be unique within their typed namespace";
            name, namespace)
    nothing
end

function store!(
    builder::CompositeBuilder,
    name::Union{Symbol,AbstractString},
    schema::S;
    initial=nothing,
    has_initial::Bool=!isnothing(initial),
) where {S<:AbstractSchema}
    _ensure_open(builder)
    identity = Symbol(name)
    _unique_name(builder, identity, :store)
    target = path(identity)
    has_initial && validate_value(schema, initial)
    push!(builder.stores,
        SemanticStore(identity, target, deepcopy(schema), has_initial,
            has_initial ? deepcopy(initial) : nothing))
    StoreHandle(builder.scope, identity, target, deepcopy(schema))
end

function mount!(
    builder::CompositeBuilder,
    name::Union{Symbol,AbstractString},
    law::L;
    domain::Symbol=:cpu,
    continuation=nothing,
    continuation_version::AbstractString="1",
) where {L<:Union{AbstractProcess,AbstractStep}}
    _ensure_open(builder)
    identity = Symbol(name)
    _unique_name(builder, identity, :component)
    kind = law isa AbstractProcess ? :process : :step
    push!(builder.actors, SemanticActor(
        identity, deepcopy(law), kind, nothing, (), domain,
        deepcopy(continuation), String(continuation_version)))
    ComponentHandle(builder.scope, identity, law)
end

function _endpoint_names(model::CompositeModel)
    tuple((endpoint.name for endpoint in model.endpoints)...)
end

function mount!(
    builder::CompositeBuilder,
    name::Union{Symbol,AbstractString},
    model::CompositeModel,
)
    _ensure_open(builder)
    identity = Symbol(name)
    _unique_name(builder, identity, :component)
    isempty(model.endpoints) &&
        _fail(:closed_composite_mount,
            "a nested composite must expose at least one endpoint";
            mount=identity)
    push!(builder.mounts, SemanticMount(identity, model))
    MountedCompositeHandle(builder.scope, identity, _endpoint_names(model))
end

function connect!(
    builder::CompositeBuilder,
    port::PortHandle,
    store::StoreHandle;
    transfer=nothing,
)
    _ensure_open(builder)
    _same_scope(builder, port)
    _same_scope(builder, store)
    any(binding -> binding.component === port.component &&
            binding.port === port.name, builder.bindings) &&
        _fail(:duplicate_port_binding,
            "a component port can connect to only one store";
            component=port.component, port=port.name)
    push!(builder.bindings,
        SemanticBinding(port.component, port.name, store.target, transfer))
    store
end

function connect!(
    builder::CompositeBuilder,
    endpoint::MountedEndpointHandle,
    store::StoreHandle,
)
    _ensure_open(builder)
    _same_scope(builder, endpoint)
    _same_scope(builder, store)
    any(binding -> binding.mount === endpoint.mount &&
            binding.endpoint === endpoint.name,
        builder.mounted_bindings) &&
        _fail(:duplicate_mounted_endpoint_binding,
            "a mounted endpoint can join only one parent store";
            mount=endpoint.mount, endpoint=endpoint.name)
    push!(builder.mounted_bindings,
        SemanticMountedBinding(endpoint.mount, endpoint.name, store.target))
    store
end

"""
Join one named store junction to one or more compatible component or mounted
ports. This relationship-style spelling is equivalent to explicit pairwise
`connect!` calls and never infers endpoints.
"""
function connect!(
    builder::CompositeBuilder,
    store::StoreHandle,
    endpoints::Union{PortHandle,MountedEndpointHandle}...,
)
    isempty(endpoints) &&
        _fail(:empty_connection,
            "a store connection requires at least one explicit endpoint";
            store=getfield(store, :name))
    for endpoint in endpoints
        connect!(builder, endpoint, store)
    end
    store
end

function attach!(
    builder::CompositeBuilder,
    component::ComponentHandle,
    mapping;
    exact::Bool=true,
)
    _ensure_open(builder)
    _same_scope(builder, component)
    pairs_value = mapping isa NamedTuple ? collect(pairs(mapping)) :
        mapping isa AbstractDict ? collect(mapping) :
        mapping isa Tuple || mapping isa AbstractVector ? collect(mapping) :
        _fail(:invalid_attachment_map,
            "attach! requires a NamedTuple, dictionary, or collection of pairs")
    declared = Dict(port.name => port
        for port in ports(getfield(component, :law)))
    supplied = Symbol[Symbol(first(pair)) for pair in pairs_value]
    extra = sort!(collect(setdiff(Set(supplied), Set(keys(declared)))))
    required = Set(name for (name, port) in declared if !port.optional)
    missing = sort!(collect(setdiff(required, Set(supplied))))
    if exact && (!isempty(extra) || !isempty(missing))
        _fail(:inexact_component_attachment,
            "exact attachment must name every required port and no unknown port";
            component=getfield(component, :name),
            missing=tuple(missing...), extra=tuple(extra...))
    end
    for entry in pairs_value
        entry isa Pair ||
            _fail(:invalid_attachment_entry,
                "every attachment entry must be a pair")
        port_name = Symbol(first(entry))
        haskey(declared, port_name) || continue
        target = last(entry)
        target isa StoreHandle ||
            _fail(:invalid_attachment_target,
                "component ports attach to StoreHandle values";
                component=getfield(component, :name), port=port_name)
        connect!(builder, _component_port(component, port_name), target)
    end
    AttachmentReport(getfield(component, :name),
        tuple(sort!(intersect(supplied, collect(keys(declared))))...),
        tuple(missing...), tuple(extra...))
end

function _replace_actor!(
    builder::CompositeBuilder,
    handle::ComponentHandle;
    schedule=nothing,
    dependencies=nothing,
)
    _same_scope(builder, handle)
    position = findfirst(actor -> actor.name === getfield(handle, :name),
        builder.actors)
    isnothing(position) &&
        _fail(:unknown_component_handle,
            "component handle is not registered in this builder")
    actor = builder.actors[position]
    builder.actors[position] = SemanticActor(
        actor.name, actor.law, actor.kind,
        isnothing(schedule) ? actor.schedule : schedule,
        isnothing(dependencies) ? actor.dependencies :
            tuple(Symbol.(dependencies)...),
        actor.domain, actor.continuation, actor.continuation_version)
    handle
end

schedule!(
    builder::CompositeBuilder,
    component::ComponentHandle{<:AbstractProcess},
    schedule::AbstractSchedule,
) = _replace_actor!(builder, component; schedule)

schedule!(
    builder::CompositeBuilder,
    component::ComponentHandle{<:AbstractProcess},
    schedule::Every,
) = _replace_actor!(builder, component;
    schedule=FixedSchedule(schedule.cadence;
        first_due=schedule.first_due,
        supports_partial=schedule.supports_partial))

function schedule!(
    builder::CompositeBuilder,
    component::ComponentHandle{<:AbstractStep},
    after::After,
)
    _replace_actor!(builder, component; dependencies=after.components)
end

schedule!(
    builder::CompositeBuilder,
    component::ComponentHandle{<:AbstractStep},
    on::On{<:StoreHandle},
) = begin
    _same_scope(builder, on.trigger)
    trigger_path = getfield(on.trigger, :target)
    actor_name = getfield(component, :name)
    input_bindings = [
        binding for binding in builder.bindings
        if binding.component === actor_name &&
            binding.target == trigger_path
    ]
    any(binding -> begin
        port = only(filter(
            candidate -> candidate.name === binding.port,
            ports(getfield(component, :law))))
        port.direction === :input
    end, input_bindings) ||
        _fail(:unbound_on_trigger,
            "On(store) requires the reactive component to read that store";
            component=actor_name, store=getfield(on.trigger, :name))
    component
end

function schedule!(
    builder::CompositeBuilder,
    component::ComponentHandle{<:AbstractStep},
    on::On{<:ComponentHandle},
)
    _same_scope(builder, on.trigger)
    _fail(:unsupported_component_event_trigger,
        "On(component) requires an explicit typed event channel; connect that channel as state and use On(store)";
        component=getfield(component, :name),
        trigger=getfield(on.trigger, :name))
end

function schedule!(
    builder::CompositeBuilder,
    component::ComponentHandle{<:AbstractProcess},
    at::At,
)
    for time in at.times
        time.scale == builder.scale ||
            _fail(:time_scale_mismatch,
                "At schedule times must use the model scale";
                component=getfield(component, :name), time)
        time.tick > 0 ||
            _fail(:nonpositive_deadline,
                "process At schedules must occur after the initial boundary";
                component=getfield(component, :name), tick=time.tick)
        time.tick < typemax(Int64) ||
            _fail(:schedule_time_overflow,
                "process At schedule leaves no representable terminal deadline";
                component=getfield(component, :name), tick=time.tick)
    end
    _replace_actor!(builder, component; schedule=at)
end

function iteration!(
    builder::CompositeBuilder,
    name::Union{Symbol,AbstractString},
    components;
    mode::Symbol=:convergent,
    max_iterations::Integer=32,
    watch=(),
)
    _ensure_open(builder)
    actor_names = tuple((
        component isa ComponentHandle ?
            (_same_scope(builder, component);
                String(getfield(component, :name))) :
            String(component)
        for component in components
    )...)
    watch_paths = tuple((
        item isa StoreHandle ?
            (_same_scope(builder, item); getfield(item, :target)) :
            item isa Path ? item : path(item)
        for item in watch
    )...)
    push!(builder.iterations,
        IterationRegion(String(name), actor_names;
            mode, max_iterations, watch_paths))
    nothing
end

function expose!(
    builder::CompositeBuilder,
    name::Union{Symbol,AbstractString},
    store::StoreHandle;
    role::Symbol,
    transfer=nothing,
)
    _ensure_open(builder)
    _same_scope(builder, store)
    endpoint_name = Symbol(name)
    endpoint_name in _names(builder.endpoints) &&
        _fail(:duplicate_endpoint_name,
            "one composite cannot expose an endpoint twice";
            name=endpoint_name)
    push!(builder.endpoints,
        SemanticEndpoint(endpoint_name, store.target, role, transfer))
    nothing
end

function parameter!(
    builder::CompositeBuilder,
    name::Union{Symbol,AbstractString},
    default::T;
    units=nothing,
    description::AbstractString="",
) where {T}
    _ensure_open(builder)
    identity = Symbol(name)
    _unique_name(builder, identity, :parameter)
    canonical_bytes(default)
    parameter = SemanticParameter(identity, deepcopy(default),
        isnothing(units) ? nothing : String(units), String(description))
    push!(builder.parameters, parameter)
    ParameterHandle(builder.scope, identity, deepcopy(default))
end

function observable!(
    builder::CompositeBuilder,
    name::Union{Symbol,AbstractString},
    store::StoreHandle;
    description::AbstractString="",
)
    _ensure_open(builder)
    _same_scope(builder, store)
    identity = Symbol(name)
    _unique_name(builder, identity, :observable)
    push!(builder.observables,
        SemanticObservable(
            identity,
            getfield(store, :target),
            deepcopy(getfield(store, :schema)),
            String(description)))
    ObservableHandle(builder.scope, identity, getfield(store, :target))
end

function allow_instances!(
    builder::CompositeBuilder,
    name::Union{Symbol,AbstractString},
    model::CompositeModel;
    capacity::Integer,
)
    _ensure_open(builder)
    identity = Symbol(name)
    _unique_name(builder, identity, :template)
    capacity > 0 ||
        _fail(:invalid_template_capacity,
            "structural template capacity must be positive";
            template=identity, capacity)
    isempty(model.endpoints) &&
        _fail(:closed_structural_template,
            "a structural template must expose its coupling surface";
            template=identity)
    push!(builder.templates,
        SemanticTemplate(identity, String(model.name), model, Int(capacity)))
    TemplateHandle(builder.scope, identity, String(model.name), Int(capacity))
end

function _semantic_actor_identity(actor::SemanticActor)
    (
        actor.name,
        actor.kind,
        string(typeof(actor.law)),
        semantic_version(actor.law),
        semantic_parameters(actor.law),
        ports(actor.law),
        capabilities(actor.law),
        actor.schedule,
        actor.dependencies,
        actor.domain,
        actor.continuation_version,
        canonical_fingerprint(actor.continuation),
    )
end

function _composite_identity(
    name,
    scale,
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
    profile,
)
    canonical_fingerprint((
        AUTHORING_CONTRACT_VERSION,
        name,
        scale,
        tuple(((store.name, store.target, store.schema,
            store.has_initial,
            store.has_initial ? canonical_fingerprint(store.initial) : nothing)
            for store in stores)...),
        tuple((_semantic_actor_identity(actor) for actor in actors)...),
        bindings,
        iterations,
        endpoints,
        parameters,
        observables,
        tuple(((template.name, template.definition_id,
            semantic_fingerprint(template.model), template.capacity)
            for template in templates)...),
        tuple(((mount.name, semantic_fingerprint(mount.model))
            for mount in mounts)...),
        mounted_bindings,
        profile,
    ))
end

function _freeze(builder::CompositeBuilder)
    stores = tuple(sort!(deepcopy(builder.stores); by=store -> store.name)...)
    actors = tuple(sort!(deepcopy(builder.actors); by=actor -> actor.name)...)
    bindings = tuple(sort!(deepcopy(builder.bindings);
        by=binding -> (binding.component, binding.port, binding.target))...)
    iterations = tuple(sort!(deepcopy(builder.iterations);
        by=region -> region.id)...)
    endpoints = tuple(sort!(deepcopy(builder.endpoints);
        by=endpoint -> endpoint.name)...)
    parameters = tuple(sort!(deepcopy(builder.parameters);
        by=parameter -> parameter.name)...)
    observables = tuple(sort!(deepcopy(builder.observables);
        by=observable -> observable.name)...)
    templates = tuple(sort!(deepcopy(builder.templates);
        by=template -> template.name)...)
    mounts = tuple(sort!(deepcopy(builder.mounts);
        by=mount -> mount.name)...)
    mounted_bindings = tuple(sort!(deepcopy(builder.mounted_bindings);
        by=binding -> (binding.target, binding.mount, binding.endpoint))...)
    fingerprint = _composite_identity(
        builder.name, builder.scale, stores, actors, bindings, iterations,
        endpoints, parameters, observables, templates, mounts,
        mounted_bindings, builder.profile)
    CompositeModel(
        AUTHORING_CONTRACT_VERSION,
        builder.name,
        builder.scale,
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
        builder.profile,
        fingerprint,
    )
end


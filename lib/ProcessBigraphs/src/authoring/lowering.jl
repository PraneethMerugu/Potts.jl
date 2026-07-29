function _lowered_actor_ids(actor::SemanticActor)
    schedule = actor.schedule
    if actor.kind === :process && schedule isa At &&
            length(schedule.times) > 1
        return tuple((
            string(actor.name, "@at[", time.tick, "]")
            for time in schedule.times
        )...)
    end
    (String(actor.name),)
end

function _lowered_schedule(schedule, id::AbstractString)
    schedule isa At || return schedule
    length(schedule.times) == 1 ||
        _fail(:ambiguous_at_lowering,
            "each lowered At process must represent exactly one deadline"; id)
    time = only(schedule.times)
    OneShotSchedule(Duration(time.tick, time.scale))
end

function _static_ir(model::CompositeModel)
    schema = BranchSchema(tuple((
        String(store.name) => deepcopy(store.schema)
        for store in model.stores
    )...))
    initial_values = Dict(
        store.target => deepcopy(store.initial)
        for store in model.stores if store.has_initial)
    processes = ProcessDeclaration[]
    steps = StepDeclaration[]
    actor_by_name = Dict(actor.name => actor for actor in model.actors)
    lowered_ids = Dict(
        actor.name => _lowered_actor_ids(actor)
        for actor in model.actors)
    for actor in model.actors
        if actor.kind === :process
            schedules = actor.schedule isa At ?
                tuple((At(time) for time in actor.schedule.times)...) :
                ntuple(_ -> actor.schedule, length(lowered_ids[actor.name]))
            for (id, schedule) in zip(lowered_ids[actor.name], schedules)
                push!(processes, ProcessDeclaration(
                    id, actor.law, _lowered_schedule(schedule, id);
                    domain=actor.domain,
                    continuation=actor.continuation,
                    continuation_version=actor.continuation_version))
            end
        else
            dependencies = String[]
            for dependency in actor.dependencies
                if haskey(actor_by_name, dependency)
                    append!(dependencies, lowered_ids[dependency])
                else
                    push!(dependencies, String(dependency))
                end
            end
            push!(steps, StepDeclaration(
                String(actor.name), actor.law;
                dependencies=tuple(dependencies...),
                domain=actor.domain,
                continuation=actor.continuation,
                continuation_version=actor.continuation_version))
        end
    end
    bindings = PortBinding[]
    for binding in model.bindings
        ids = get(lowered_ids, binding.component, (String(binding.component),))
        for id in ids
            push!(bindings, PortBinding(
                id, binding.port, binding.target;
                transfer=binding.transfer))
        end
    end
    StaticComposite(schema, initial_values, model.scale;
        processes=tuple(processes...),
        steps=tuple(steps...),
        bindings=tuple(bindings...),
        iteration_regions=model.iterations)
end

function _open_model(model::CompositeModel)
    static = _static_ir(model)
    isempty(model.endpoints) &&
        return _open_from_model(canonical_model(static))
    open_composite(String(model.name), static;
        endpoints=tuple((
            BoundaryEndpoint(endpoint.name, endpoint.target;
                role=endpoint.role, transfer=endpoint.transfer)
            for endpoint in model.endpoints
        )...))
end

function _lower_hierarchy(model::CompositeModel)
    semantic_mounts = collect(model.mounts)
    mounted_bindings = collect(model.mounted_bindings)
    if !isempty(model.actors)
        local_name = Symbol(String(model.name) * ".local")
        local_endpoints = tuple((
            SemanticEndpoint(store.name, store.target, :bidirectional, nothing)
            for store in model.stores
        )...)
        local_fingerprint = _composite_identity(
            local_name, model.scale, model.stores, model.actors,
            model.bindings, model.iterations, local_endpoints,
            getfield(model, :parameters), getfield(model, :observables),
            model.templates, (), (), model.profile)
        local_model = CompositeModel(
            model.contract_version,
            local_name,
            model.scale,
            model.stores,
            model.actors,
            model.bindings,
            model.iterations,
            local_endpoints,
            getfield(model, :parameters),
            getfield(model, :observables),
            model.templates,
            (),
            (),
            model.profile,
            local_fingerprint,
        )
        local_mount = Symbol("__local__")
        push!(semantic_mounts, SemanticMount(local_mount, local_model))
        append!(mounted_bindings, (
            SemanticMountedBinding(local_mount, store.name, store.target)
            for store in model.stores))
    end

    mounts = tuple((
        CompositeMount(mount.name, _open_model(mount.model))
        for mount in semantic_mounts
    )...)
    grouped = Dict{Path,Vector{EndpointRef}}()
    for binding in mounted_bindings
        push!(get!(grouped, binding.target, EndpointRef[]),
            EndpointRef(binding.mount, binding.endpoint))
    end
    junctions = tuple((
        JunctionSpec(
            "junction:" * canonical_fingerprint(target),
            target,
            tuple(sort!(references;
                by=reference -> (reference.mount, reference.endpoint))...))
        for (target, references) in sort!(collect(grouped); by=first)
    )...)
    target_to_junction = Dict(junction.target => junction.id
        for junction in junctions)
    exports = tuple((
        CompositeExport(endpoint.name,
            target_to_junction[endpoint.target];
            role=endpoint.role, transfer=endpoint.transfer)
        for endpoint in model.endpoints
    )...)
    initial_values = Dict(
        store.target => deepcopy(store.initial)
        for store in model.stores if store.has_initial)
    canonical_model(compose_open(CompositionSpec(
        String(model.name);
        mounts,
        junctions,
        exports,
        initial_values)))
end

_origin_segment(segment::NameSegment) = Symbol(segment.value)
_origin_segment(segment::IndexSegment) =
    Symbol("[", string(segment.value), "]")
_origin_location(path_value::Path) =
    tuple((_origin_segment(segment) for segment in path_value)...)

function _semantic_actor_name(local_id::AbstractString)
    Symbol(replace(String(local_id), r"@at\[[0-9]+\]$" => ""))
end

function _composite_origin_locations(structure)
    root = _root_composite(structure)
    locations = Dict{Int,Tuple}(root => ())
    remaining = collect(_rows(structure, :CompositeContainment))
    while !isempty(remaining)
        progress = false
        next_remaining = Int[]
        for row in remaining
            parent = Int(_attr(structure, row, :composite_parent))
            child_row = Int(_attr(structure, row, :composite_child))
            if !haskey(locations, parent)
                push!(next_remaining, row)
                continue
            end
            key = Symbol(_attr(structure, row, :mount_key))
            locations[child_row] = key === :__local__ ?
                locations[parent] : (locations[parent]..., key)
            progress = true
        end
        progress ||
            _fail(:origin_containment_cycle,
                "canonical composite containment cannot be mapped to author locations")
        remaining = next_remaining
    end
    length(locations) == length(_rows(structure, :Composite)) ||
        _fail(:origin_disconnected_composite,
            "every canonical composite requires an author location")
    locations
end

function _origin_map(model::CompositeModel, canonical::CanonicalModel)
    structure = canonical.structure
    composite_locations = _composite_origin_locations(structure)
    origins = AuthorOrigin[]

    function add_origin(kind, name, location, identity; path_value=nothing)
        push!(origins, AuthorOrigin(
            Symbol(kind),
            Symbol(name),
            tuple(location...),
            String(identity),
            isnothing(path_value) ? nothing : path_value))
    end

    actor_locations = Dict{Int,Tuple}()
    actor_names = Dict{Int,Symbol}()
    for row in _rows(structure, :Composite)
        location = composite_locations[row]
        name = isempty(location) ? model.name : last(location)
        add_origin(
            :composite, name, location,
            string("composite:",
                _attr(structure, row, :composite_id)))
    end

    store_locations = Dict{Int,Tuple}()
    store_names = Dict{Int,Symbol}()
    store_paths = Dict{Int,Path}()
    for row in _rows(structure, :StoreNode)
        composite = Int(_attr(structure, row, :store_composite))
        local_path = _attr(structure, row, :store_local_path)
        location = (
            composite_locations[composite]...,
            _origin_location(local_path)...,
        )
        name = isempty(location) ?
            model.name : last(location)
        target = _attr(structure, row, :store_path)
        store_locations[row] = location
        store_names[row] = name
        store_paths[row] = target
        add_origin(
            :store, name, location,
            _attr(structure, row, :store_id);
            path_value=target)
    end

    for row in _rows(structure, :StoreContainment)
        child_row = Int(_attr(structure, row, :containment_child))
        add_origin(
            :store_containment,
            store_names[child_row],
            store_locations[child_row],
            _attr(structure, row, :containment_id);
            path_value=store_paths[child_row])
    end

    for row in _rows(structure, :CompositeContainment)
        child_row = Int(_attr(structure, row, :composite_child))
        location = composite_locations[child_row]
        name = isempty(location) ? model.name : last(location)
        add_origin(
            :mount, name, location,
            _attr(structure, row, :composite_containment_id))
    end

    for row in _rows(structure, :Actor)
        composite = Int(_attr(structure, row, :actor_composite))
        name = _semantic_actor_name(
            String(_attr(structure, row, :actor_local_id)))
        location = (composite_locations[composite]..., name)
        actor_locations[row] = location
        actor_names[row] = name
        add_origin(
            :component, name, location,
            string("actor:",
                _attr(structure, row, :actor_id)))
    end

    for row in _rows(structure, :Process)
        actor = Int(_attr(structure, row, :process_actor))
        add_origin(
            :process,
            actor_names[actor],
            actor_locations[actor],
            string("actor:",
                _attr(structure, actor, :actor_id)))
    end
    for row in _rows(structure, :Step)
        actor = Int(_attr(structure, row, :step_actor))
        add_origin(
            :step,
            actor_names[actor],
            actor_locations[actor],
            string("actor:",
                _attr(structure, actor, :actor_id)))
    end

    port_locations = Dict{Int,Tuple}()
    port_names = Dict{Int,Symbol}()
    for row in _rows(structure, :Port)
        actor = Int(_attr(structure, row, :port_actor))
        name = Symbol(_attr(structure, row, :port_name))
        location = (actor_locations[actor]..., name)
        port_locations[row] = location
        port_names[row] = name
        add_origin(
            :port, name, location,
            _attr(structure, row, :port_id))
    end

    for row in _rows(structure, :Binding)
        port = Int(_attr(structure, row, :binding_port))
        store = Int(_attr(structure, row, :binding_store))
        add_origin(
            :binding,
            port_names[port],
            port_locations[port],
            _attr(structure, row, :binding_id);
            path_value=store_paths[store])
    end

    for row in _rows(structure, :StepDependency)
        after = Int(_attr(structure, row, :dependency_after))
        actor = Int(_attr(structure, after, :step_actor))
        add_origin(
            :dependency,
            actor_names[actor],
            actor_locations[actor],
            _attr(structure, row, :dependency_id))
    end

    endpoint_locations = Dict{Int,Tuple}()
    endpoint_names = Dict{Int,Symbol}()
    for row in _rows(structure, :Endpoint)
        name = Symbol(_attr(structure, row, :endpoint_name))
        boundary_rows = ACSets.incident(
            structure, row, :boundary_map_endpoint)
        isempty(boundary_rows) &&
            _fail(:origin_missing_boundary_map,
                "canonical endpoint has no boundary map";
                endpoint=_attr(structure, row, :endpoint_id))
        store_rows = unique(Int(
            _attr(structure, boundary, :boundary_map_store))
            for boundary in boundary_rows)
        length(store_rows) == 1 ||
            _fail(:origin_ambiguous_boundary_store,
                "canonical endpoint maps to more than one store";
                endpoint=_attr(structure, row, :endpoint_id))
        store_row = only(store_rows)
        base = store_locations[store_row]
        location = (base..., name)
        endpoint_locations[row] = location
        endpoint_names[row] = name
        add_origin(
            :endpoint, name, location,
            _attr(structure, row, :endpoint_id);
            path_value=store_paths[store_row])
    end

    for row in _rows(structure, :BoundaryMap)
        endpoint = Int(_attr(structure, row, :boundary_map_endpoint))
        store = Int(_attr(structure, row, :boundary_map_store))
        add_origin(
            :boundary,
            endpoint_names[endpoint],
            endpoint_locations[endpoint],
            _attr(structure, row, :boundary_map_id);
            path_value=store_paths[store])
    end

    junction_locations = Dict{Int,Tuple}()
    junction_names = Dict{Int,Symbol}()
    for row in _rows(structure, :Junction)
        composite = Int(_attr(structure, row, :junction_composite))
        store = Int(_attr(structure, row, :junction_store))
        name = store_names[store]
        location = (
            composite_locations[composite]...,
            name,
        )
        junction_locations[row] = location
        junction_names[row] = name
        add_origin(
            :junction, name, location,
            _attr(structure, row, :junction_id);
            path_value=store_paths[store])
    end

    for row in _rows(structure, :JunctionEndpoint)
        junction =
            Int(_attr(structure, row, :junction_endpoint_junction))
        add_origin(
            :junction_endpoint,
            junction_names[junction],
            junction_locations[junction],
            _attr(structure, row, :junction_endpoint_id))
    end

    tuple(sort!(origins;
        by=origin -> (
            join(String.(origin.location), "/"),
            String(origin.kind),
            String(origin.name),
            origin.canonical_identity))...)
end

function lower(model::CompositeModel)
    report = validate(model)
    isempty(report) || throw(ModelValidationError(report))
    canonical = isempty(model.mounts) ?
        canonical_model(_open_model(model)) : _lower_hierarchy(model)
    origins = _origin_map(model, canonical)
    LoweredModel(
        AUTHORING_CONTRACT_VERSION,
        model.fingerprint,
        canonical,
        origins,
        structural_fingerprint(canonical))
end

canonical_model(model::LoweredModel) =
    CanonicalModel(model.canonical.structure, model.canonical.payloads)
canonical_structure(model::LoweredModel) =
    canonical_structure(model.canonical)
structural_fingerprint(model::LoweredModel) = model.fingerprint
ir_fingerprint(model::LoweredModel) = model.fingerprint
origin_map(model::LoweredModel) = deepcopy(model.origins)

function compile(
    model::Union{CompositeModel,LoweredModel};
    backend::Symbol=:serial,
)
    backend === :serial ||
        _fail(:unsupported_execution_backend,
            "authoring compilation currently admits the serial orchestrator";
            backend)
    lowered = model isa CompositeModel ? lower(model) : model
    compiled = compile_composite(lowered.canonical)
    CompiledComposite(
        compiled.epoch,
        compiled.plan,
        compiled.initial,
        compiled.preflight_report,
        compiled.fingerprint,
        lowered.origins)
end

plan_fingerprint(model::CompiledComposite) =
    execution_plan_fingerprint(model)
origin_map(model::CompiledComposite) =
    isempty(model.author_origins) ?
        deepcopy(structural_provenance(model).entries) :
        deepcopy(model.author_origins)
diagram(model::CompositeModel) =
    annotated_wiring_diagram(lower(model).canonical)

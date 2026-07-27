_store_identity(target::Path) =
    string("store:", canonical_fingerprint((:process_bigraph_store_v1, target)))
_port_identity(owner::AbstractString, name::Symbol) =
    string("port:", owner, ":", name)
_binding_identity(owner::AbstractString, name::Symbol) =
    string("binding:", owner, ":", name)
_containment_identity(target::Path) =
    string("containment:", canonical_fingerprint((:process_bigraph_containment_v1, target)))
_dependency_identity(before::AbstractString, after::AbstractString) =
    string("dependency:", before, ":", after)

function _schema_nodes(
    schema::AbstractSchema,
    prefix::Path=Path(),
    result=Tuple{Path,Symbol,Any}[],
)
    if schema isa LeafSchema
        push!(result, (prefix, :leaf, deepcopy(schema)))
    else
        push!(result, (prefix, :branch, nothing))
        for (name, child_schema) in schema.children
            _schema_nodes(child_schema, child(prefix, name), result)
        end
    end
    result
end

function _ordered(values; reverse_insertion::Bool)
    ordered = collect(values)
    reverse_insertion && reverse!(ordered)
    ordered
end

function _lower_static_to_structure(
    composite::StaticComposite;
    reverse_insertion::Bool=false,
)
    structure = ProcessBigraphACSet()
    root = ACSets.add_part!(structure, :Composite;
        composite_id="root",
        composite_definition_id="root",
        scale_numerator=composite.scale.numerator,
        scale_denominator=composite.scale.denominator,
        scale_unit=composite.scale.unit)

    schema_nodes = sort!(_schema_nodes(composite.schema); by=entry -> entry[1])
    store_rows = Dict{Path,Int}()
    for (target, kind, payload) in _ordered(schema_nodes; reverse_insertion)
        store_rows[target] = ACSets.add_part!(structure, :StoreNode;
            store_composite=root,
            store_id=_store_identity(target),
            store_path=target,
            store_local_path=target,
            schema_kind=kind,
            schema_payload=payload)
    end
    nonroot = [entry for entry in schema_nodes if !isempty(first(entry))]
    for (target, _, _) in _ordered(nonroot; reverse_insertion)
        ACSets.add_part!(structure, :StoreContainment;
            containment_child=store_rows[target],
            containment_parent=store_rows[parentpath(target)],
            containment_id=_containment_identity(target))
    end

    owners = sort!(collect(_owners(composite)); by=declaration -> declaration.id)
    actor_rows = Dict{String,Int}()
    process_rows = Dict{String,Int}()
    step_rows = Dict{String,Int}()
    port_rows = Dict{Tuple{String,Symbol},Int}()
    for declaration in _ordered(owners; reverse_insertion)
        id = declaration.id
        actor = ACSets.add_part!(structure, :Actor;
            actor_composite=root,
            actor_id=id,
            actor_local_id=id,
            law_type=string(typeof(declaration.law)),
            law_version=semantic_version(declaration.law),
            law_parameters=semantic_parameters(declaration.law),
            capability_payload=capabilities(declaration.law),
            actor_domain=declaration.domain,
            continuation_version=declaration.continuation_version)
        actor_rows[id] = actor
        if declaration isa ProcessDeclaration
            process_rows[id] = ACSets.add_part!(structure, :Process;
                process_actor=actor,
                cadence_tick=declaration.schedule.cadence.tick,
                first_due_tick=declaration.schedule.first_due.tick,
                supports_partial=declaration.schedule.supports_partial)
        else
            step_rows[id] = ACSets.add_part!(structure, :Step; step_actor=actor)
        end
        declared_ports = sort!(collect(ports(declaration.law)); by=port -> port.name)
        for port in _ordered(declared_ports; reverse_insertion)
            port_rows[(id, port.name)] = ACSets.add_part!(structure, :Port;
                port_actor=actor,
                port_id=_port_identity(id, port.name),
                port_name=port.name,
                port_value_type=string(typeof(port).parameters[1]),
                port_direction=port.direction,
                port_effect=port.effect,
                port_interval_behavior=port.interval_behavior,
                port_optional=port.optional,
                port_cardinality=port.cardinality,
                port_residency=port.residency,
                port_update_law=port.update_law)
        end
    end

    sorted_bindings = sort!(collect(composite.bindings);
        by=binding -> (binding.owner, binding.port, binding.target))
    for binding in _ordered(sorted_bindings; reverse_insertion)
        ACSets.add_part!(structure, :Binding;
            binding_port=port_rows[(binding.owner, binding.port)],
            binding_store=store_rows[binding.target],
            binding_id=_binding_identity(binding.owner, binding.port),
            transfer_payload=deepcopy(binding.transfer))
    end

    dependencies = sort!([
        (before, step.id)
        for step in composite.steps
        for before in step.dependencies
    ])
    for (before, after) in _ordered(dependencies; reverse_insertion)
        ACSets.add_part!(structure, :StepDependency;
            dependency_before=step_rows[before],
            dependency_after=step_rows[after],
            dependency_id=_dependency_identity(before, after))
    end
    structure
end

function _canonical_model(
    composite::StaticComposite;
    reverse_insertion::Bool=false,
)
    owners = sort!(collect(_owners(composite)); by=declaration -> declaration.id)
    payloads = ModelPayloads(
        composite.initial_values,
        (declaration.id => declaration.law for declaration in owners);
        continuations=(declaration.id => declaration.continuation
            for declaration in owners))
    CanonicalModel(
        _lower_static_to_structure(composite; reverse_insertion),
        payloads,
    )
end

canonical_model(composite::StaticComposite) = _canonical_model(composite)

function canonical_model(
    structure::ConcreteProcessBigraphACSet;
    initial_values=Dict(),
    laws,
    continuations=(),
)
    CanonicalModel(structure,
        ModelPayloads(initial_values, laws; continuations))
end

canonical_structure(composite::StaticComposite) =
    canonical_structure(canonical_model(composite))

function _root_composite(structure)
    rows = _rows(structure, :Composite)
    isempty(rows) &&
        _fail(:missing_root_composite, "canonical structure has no composite")
    parents = Dict{Int,Int}()
    mount_keys = Dict{Int,Set{Symbol}}()
    children = Dict{Int,Vector{Int}}(row => Int[] for row in rows)
    for row in _rows(structure, :CompositeContainment)
        child_row = Int(_attr(structure, row, :composite_child))
        parent_row = Int(_attr(structure, row, :composite_parent))
        child_row == parent_row &&
            _fail(:composite_cycle, "a composite cannot contain itself";
                composite=String(_attr(structure, child_row, :composite_id)))
        haskey(parents, child_row) &&
            _fail(:multiple_composite_parents, "a composite has multiple parents";
                composite=String(_attr(structure, child_row, :composite_id)))
        key = _attr(structure, row, :mount_key)
        key isa Symbol ||
            _fail(:invalid_mount_key, "canonical mount keys must be symbols";
                actual=string(typeof(key)))
        key in get!(mount_keys, parent_row, Set{Symbol}()) &&
            _fail(:duplicate_mount_key, "one parent contains duplicate mount keys";
                parent=String(_attr(structure, parent_row, :composite_id)), mount_key=key)
        push!(mount_keys[parent_row], key)
        parents[child_row] = parent_row
        push!(children[parent_row], child_row)
    end
    roots = [row for row in rows if !haskey(parents, row)]
    length(roots) == 1 ||
        _fail(:composite_root_cardinality,
            "canonical hierarchy must contain exactly one root composite";
            count=length(roots))
    root = only(roots)
    visited = Set{Int}()
    active = Set{Int}()
    function visit(row)
        row in active &&
            _fail(:composite_cycle, "composite containment contains a cycle";
                composite=String(_attr(structure, row, :composite_id)))
        row in visited && return
        push!(active, row)
        foreach(visit, children[row])
        delete!(active, row)
        push!(visited, row)
    end
    visit(root)
    length(visited) == length(rows) ||
        _fail(:orphan_composite, "composite hierarchy is disconnected")
    root_scale = (
        _attr(structure, root, :scale_numerator),
        _attr(structure, root, :scale_denominator),
        _attr(structure, root, :scale_unit),
    )
    for row in rows
        isempty(String(_attr(structure, row, :composite_id))) &&
            _fail(:empty_composite_identity, "composite identity cannot be empty")
        isempty(String(_attr(structure, row, :composite_definition_id))) &&
            _fail(:empty_composite_definition_identity,
                "composite definition identity cannot be empty")
        scale = (
            _attr(structure, row, :scale_numerator),
            _attr(structure, row, :scale_denominator),
            _attr(structure, row, :scale_unit),
        )
        scale == root_scale ||
            _fail(:time_scale_mismatch,
                "all composites in one immutable hierarchy must share one time scale";
                composite=String(_attr(structure, row, :composite_id)))
    end
    root
end

function _reconstruct_schema(structure)
    store_rows = _rows(structure, :StoreNode)
    paths = Dict{Path,Int}()
    for row in store_rows
        target = _attr(structure, row, :store_path)
        target isa Path ||
            _fail(:invalid_store_path, "canonical store path must be a Path";
                actual=string(typeof(target)))
        local_target = _attr(structure, row, :store_local_path)
        local_target isa Path ||
            _fail(:invalid_store_local_path, "canonical local store path must be a Path";
                actual=string(typeof(local_target)))
        haskey(paths, target) &&
            _fail(:duplicate_store_path, "canonical structure repeats a store path";
                target)
        paths[target] = row
    end
    haskey(paths, Path()) ||
        _fail(:missing_root_store, "canonical structure has no root store node")

    children = Dict{Int,Vector{Int}}(row => Int[] for row in store_rows)
    child_parent = Dict{Int,Int}()
    for row in _rows(structure, :StoreContainment)
        child_row = Int(_attr(structure, row, :containment_child))
        parent_row = Int(_attr(structure, row, :containment_parent))
        haskey(child_parent, child_row) &&
            _fail(:multiple_store_parents, "store node has multiple parents";
                store=String(_attr(structure, child_row, :store_id)))
        child_parent[child_row] = parent_row
        push!(children[parent_row], child_row)
    end
    root_row = paths[Path()]
    for (target, row) in paths
        if row == root_row
            haskey(child_parent, row) &&
                _fail(:root_store_has_parent, "root store cannot have a parent")
            continue
        end
        haskey(child_parent, row) ||
            _fail(:orphan_store_node, "non-root store node has no parent"; target)
        expected = parentpath(target)
        actual = _attr(structure, child_parent[row], :store_path)
        actual == expected ||
            _fail(:store_path_parent_mismatch,
                "store containment does not agree with canonical paths";
                target, expected, actual)
    end

    function build(row)
        kind = _attr(structure, row, :schema_kind)
        payload = _attr(structure, row, :schema_payload)
        target = _attr(structure, row, :store_path)
        if kind === :leaf
            payload isa LeafSchema ||
                _fail(:invalid_leaf_schema_payload,
                    "leaf store node must contain one LeafSchema"; target)
            isempty(children[row]) ||
                _fail(:leaf_has_children, "leaf store node cannot contain children";
                    target)
            return deepcopy(payload)
        elseif kind === :branch
            isnothing(payload) ||
                _fail(:branch_schema_payload,
                    "branch structure is expressed by containment, not an embedded schema";
                    target)
            pairs = Pair{String,AbstractSchema}[]
            sorted_children = sort!(children[row];
                by=child_row -> _attr(structure, child_row, :store_path))
            for child_row in sorted_children
                child_path = _attr(structure, child_row, :store_path)
                tail = last(segments(child_path))
                tail isa NameSegment ||
                    _fail(:schema_path_mismatch,
                        "schema branches require NameSegment children";
                        child_path)
                push!(pairs, tail.value => build(child_row))
            end
            return BranchSchema(pairs)
        end
        _fail(:invalid_schema_kind, "store node has an unknown schema kind";
            target, kind)
    end
    build(root_row)
end

function _law_port_record(port::PortSpec)
    (
        value_type=string(typeof(port).parameters[1]),
        direction=port.direction,
        effect=port.effect,
        interval_behavior=port.interval_behavior,
        optional=port.optional,
        cardinality=port.cardinality,
        residency=port.residency,
        update_law=port.update_law,
    )
end

function _structure_port_record(structure, row)
    (
        value_type=String(_attr(structure, row, :port_value_type)),
        direction=_attr(structure, row, :port_direction),
        effect=_attr(structure, row, :port_effect),
        interval_behavior=_attr(structure, row, :port_interval_behavior),
        optional=_attr(structure, row, :port_optional),
        cardinality=_attr(structure, row, :port_cardinality),
        residency=_attr(structure, row, :port_residency),
        update_law=_attr(structure, row, :port_update_law),
    )
end

function _materialize_static(structure, payloads)
    composite_row = _root_composite(structure)
    scale = TimeScale(
        _attr(structure, composite_row, :scale_numerator),
        _attr(structure, composite_row, :scale_denominator),
        _attr(structure, composite_row, :scale_unit))
    schema = _reconstruct_schema(structure)

    laws = Dict{String,Any}(payloads.laws)
    continuations = Dict{String,Any}(payloads.continuations)
    actor_rows = _id_rows(structure, :Actor, :actor_id)
    Set(keys(laws)) == Set(keys(actor_rows)) ||
        _fail(:law_payload_mismatch,
            "executable law payloads must exactly match canonical actors";
            expected=sort!(collect(keys(actor_rows))),
            actual=sort!(collect(keys(laws))))
    Set(keys(continuations)) == Set(keys(actor_rows)) ||
        _fail(:continuation_payload_mismatch,
            "initial continuations must exactly match canonical actors")
    actor_kinds = _actor_kinds(structure)
    length(actor_kinds) == length(actor_rows) ||
        _fail(:missing_actor_kind,
            "every canonical actor must be exactly one Process or Step")

    ports_by_actor = Dict{Int,Vector{Int}}()
    for row in _rows(structure, :Port)
        push!(get!(ports_by_actor, Int(_attr(structure, row, :port_actor)), Int[]), row)
    end
    process_rows = Dict(Int(_attr(structure, row, :process_actor)) => row
        for row in _rows(structure, :Process))
    step_rows = Dict(Int(_attr(structure, row, :step_actor)) => row
        for row in _rows(structure, :Step))
    actor_to_step = Dict(actor => row for (actor, row) in step_rows)
    step_to_actor = Dict(row => actor for (actor, row) in actor_to_step)

    dependencies = Dict{String,Vector{String}}(id => String[]
        for (id, actor) in actor_rows if actor_kinds[actor] === :step)
    for row in _rows(structure, :StepDependency)
        before_step = Int(_attr(structure, row, :dependency_before))
        after_step = Int(_attr(structure, row, :dependency_after))
        before_actor = step_to_actor[before_step]
        after_actor = step_to_actor[after_step]
        before_id = String(_attr(structure, before_actor, :actor_id))
        after_id = String(_attr(structure, after_actor, :actor_id))
        push!(dependencies[after_id], before_id)
    end

    processes = ProcessDeclaration[]
    steps = StepDeclaration[]
    for id in sort!(collect(keys(actor_rows)))
        actor = actor_rows[id]
        law = laws[id]
        expected_type = actor_kinds[actor] === :process ? AbstractProcess : AbstractStep
        law isa expected_type ||
            _fail(:law_kind_mismatch, "law payload has the wrong actor kind";
                id, expected=string(expected_type), actual=string(typeof(law)))
        string(typeof(law)) == _attr(structure, actor, :law_type) ||
            _fail(:law_type_mismatch, "law type disagrees with canonical structure"; id)
        semantic_version(law) == _attr(structure, actor, :law_version) ||
            _fail(:law_version_mismatch,
                "law semantic version disagrees with canonical structure"; id)
        semantic_parameters(law) == _attr(structure, actor, :law_parameters) ||
            _fail(:law_parameter_mismatch,
                "law parameters disagree with canonical structure"; id)
        capabilities(law) == _attr(structure, actor, :capability_payload) ||
            _fail(:law_capability_mismatch,
                "law capabilities disagree with canonical structure"; id)

        actual_ports = Dict(port.name => port for port in ports(law))
        structure_ports = get(ports_by_actor, actor, Int[])
        Set(keys(actual_ports)) ==
            Set(Symbol(_attr(structure, row, :port_name)) for row in structure_ports) ||
            _fail(:port_payload_mismatch,
                "law ports disagree with canonical structure"; id)
        for row in structure_ports
            name = Symbol(_attr(structure, row, :port_name))
            _law_port_record(actual_ports[name]) == _structure_port_record(structure, row) ||
                _fail(:port_metadata_mismatch,
                    "law port metadata disagrees with canonical structure";
                    id, port=name)
        end

        domain = _attr(structure, actor, :actor_domain)
        continuation_version =
            String(_attr(structure, actor, :continuation_version))
        if actor_kinds[actor] === :process
            row = process_rows[actor]
            schedule = FixedSchedule(
                Duration(_attr(structure, row, :cadence_tick), scale);
                first_due=Duration(_attr(structure, row, :first_due_tick), scale),
                supports_partial=_attr(structure, row, :supports_partial))
            push!(processes, ProcessDeclaration(id, law, schedule;
                domain, continuation=continuations[id], continuation_version))
        else
            push!(steps, StepDeclaration(id, law;
                dependencies=tuple(sort!(unique!(dependencies[id]))...),
                domain, continuation=continuations[id], continuation_version))
        end
    end

    port_owner = Dict(row => String(_attr(structure,
        Int(_attr(structure, row, :port_actor)), :actor_id))
        for row in _rows(structure, :Port))
    store_path = Dict(row => _attr(structure, row, :store_path)
        for row in _rows(structure, :StoreNode))
    bindings = PortBinding[]
    for row in _rows(structure, :Binding)
        port_row = Int(_attr(structure, row, :binding_port))
        owner = port_owner[port_row]
        name = Symbol(_attr(structure, port_row, :port_name))
        target = store_path[Int(_attr(structure, row, :binding_store))]
        transfer = _attr(structure, row, :transfer_payload)
        (isnothing(transfer) || transfer isa TransferDeclaration) ||
            _fail(:invalid_transfer_payload,
                "binding transfer must be nothing or TransferDeclaration";
                owner, port=name)
        push!(bindings, PortBinding(owner, name, target; transfer))
    end
    sort!(bindings; by=binding -> (binding.owner, binding.port, binding.target))
    StaticComposite(schema, payloads.initial_values, scale;
        processes=tuple(processes...),
        steps=tuple(steps...),
        bindings=tuple(bindings...))
end

function _validate_open_structure(structure)
    endpoint_rows = _rows(structure, :Endpoint)
    endpoint_ids = Set(String(_attr(structure, row, :endpoint_id))
        for row in endpoint_rows)
    endpoint_maps = Dict{Int,Int}()
    endpoint_composites = Dict{Int,Int}()
    for row in _rows(structure, :BoundaryMap)
        endpoint = Int(_attr(structure, row, :boundary_map_endpoint))
        haskey(endpoint_maps, endpoint) &&
            _fail(:multiple_boundary_maps,
                "an endpoint must map to exactly one canonical store";
                endpoint=String(_attr(structure, endpoint, :endpoint_id)))
        endpoint_maps[endpoint] = Int(_attr(structure, row, :boundary_map_store))
        endpoint_composites[endpoint] =
            Int(_attr(structure, row, :boundary_map_composite))
    end
    Set(keys(endpoint_maps)) == Set(endpoint_rows) ||
        _fail(:missing_boundary_map,
            "every declared endpoint must map to one canonical store")

    endpoint_names = Set{Tuple{Int,Symbol}}()
    for endpoint in endpoint_rows
        role = _attr(structure, endpoint, :endpoint_role)
        role in (:import, :export, :bidirectional) ||
            _fail(:invalid_endpoint_role, "unknown open-composite endpoint role";
                endpoint=String(_attr(structure, endpoint, :endpoint_id)), role)
        name = _attr(structure, endpoint, :endpoint_name)
        name isa Symbol ||
            _fail(:invalid_endpoint_name, "endpoint names must be symbols";
                endpoint=String(_attr(structure, endpoint, :endpoint_id)))
        key = (endpoint_composites[endpoint], name)
        key in endpoint_names &&
            _fail(:duplicate_endpoint_name,
                "one composite contains duplicate endpoint names";
                composite=String(_attr(structure, first(key), :composite_id)), name)
        push!(endpoint_names, key)
        store = endpoint_maps[endpoint]
        _attr(structure, store, :schema_kind) === :leaf ||
            _fail(:endpoint_targets_branch,
                "open-composite endpoints must map to leaf stores";
                endpoint=String(_attr(structure, endpoint, :endpoint_id)))
        schema = _attr(structure, store, :schema_payload)
        contract = _validated_endpoint_contract(
            _attr(structure, endpoint, :endpoint_schema_payload))
        canonical_fingerprint(schema) ==
            canonical_fingerprint(contract.schema) ||
            _fail(:endpoint_schema_mismatch,
                "endpoint schema metadata disagrees with its mapped store";
                endpoint=String(_attr(structure, endpoint, :endpoint_id)))
        local_path = _attr(structure, endpoint, :endpoint_local_path)
        local_path isa Path ||
            _fail(:invalid_endpoint_local_path,
                "endpoint local paths must be canonical Path values")
        isempty(String(_attr(structure, endpoint, :endpoint_origin_store_id))) &&
            _fail(:empty_endpoint_origin,
                "endpoint provenance must retain an originating store identity")
    end

    junction_rows = _rows(structure, :Junction)
    endpoints_by_junction = Dict{Int,Vector{Int}}(row => Int[] for row in junction_rows)
    relation_keys = Set{Tuple{Int,Int}}()
    for row in _rows(structure, :JunctionEndpoint)
        junction = Int(_attr(structure, row, :junction_endpoint_junction))
        endpoint = Int(_attr(structure, row, :junction_endpoint_endpoint))
        key = (junction, endpoint)
        key in relation_keys &&
            _fail(:duplicate_junction_endpoint,
                "a junction repeats one endpoint")
        push!(relation_keys, key)
        push!(endpoints_by_junction[junction], endpoint)
    end
    junction_ids = Set{String}()
    for junction in junction_rows
        id = String(_attr(structure, junction, :junction_id))
        isempty(id) &&
            _fail(:empty_junction_identity, "junction identity cannot be empty")
        id in junction_ids &&
            _fail(:duplicate_junction_identity, "junction identities must be unique"; id)
        push!(junction_ids, id)
        endpoints = endpoints_by_junction[junction]
        isempty(endpoints) &&
            _fail(:empty_junction, "a junction must connect at least one endpoint"; id)
        store = Int(_attr(structure, junction, :junction_store))
        composite = Int(_attr(structure, junction, :junction_composite))
        schema = _attr(structure, store, :schema_payload)
        _attr(structure, store, :schema_kind) === :leaf ||
            _fail(:junction_targets_branch,
                "junctions must resolve to leaf stores"; junction=id)
        contracts = [_validated_endpoint_contract(
            _attr(structure, endpoint, :endpoint_schema_payload))
            for endpoint in endpoints]
        all(contract -> canonical_fingerprint(contract.schema) ==
                canonical_fingerprint(schema), contracts) ||
            _fail(:junction_schema_mismatch,
                "all joined endpoints must have exactly compatible schemas"; junction=id)
        all(contract -> canonical_fingerprint(contract) ==
                canonical_fingerprint(first(contracts)), contracts) ||
            _fail(:junction_schema_mismatch,
                "all joined endpoints must have exactly compatible transfer metadata";
                junction=id)

        internal = [endpoint for endpoint in endpoints
            if endpoint_composites[endpoint] != composite]
        parent = [endpoint for endpoint in endpoints
            if endpoint_composites[endpoint] == composite]
        providers = any(endpoint ->
            _attr(structure, endpoint, :endpoint_role) in (:export, :bidirectional),
            internal)
        consumers = any(endpoint ->
            _attr(structure, endpoint, :endpoint_role) in (:import, :bidirectional),
            internal)
        external_providers = any(endpoint ->
            _attr(structure, endpoint, :endpoint_role) in (:import, :bidirectional),
            parent)
        external_consumers = any(endpoint ->
            _attr(structure, endpoint, :endpoint_role) in (:export, :bidirectional),
            parent)
        (providers || external_providers) ||
            _fail(:junction_missing_provider,
                "junction has no provider-capable endpoint"; junction=id)
        (consumers || external_consumers) ||
            _fail(:junction_missing_consumer,
                "junction has no consumer-capable endpoint"; junction=id)
    end
    endpoint_ids
end

function _validate_canonical_structure(structure, payloads)
    root = _root_composite(structure)
    composite_rows = Set(_rows(structure, :Composite))
    all(row -> Int(_attr(structure, row, :store_composite)) in composite_rows,
        _rows(structure, :StoreNode)) ||
        _fail(:unknown_store_composite,
            "a store belongs to an unknown composite")
    all(row -> Int(_attr(structure, row, :actor_composite)) in composite_rows,
        _rows(structure, :Actor)) ||
        _fail(:unknown_actor_composite,
            "an actor belongs to an unknown composite")
    _validate_open_structure(structure)
    composite = _materialize_static(structure, payloads)
    ids = _validate_identities(composite)
    all(process -> process.schedule.cadence.scale == composite.scale &&
        process.schedule.first_due.scale == composite.scale, composite.processes) ||
        _fail(:time_scale_mismatch,
            "every process schedule must use the composite scale")
    layers = _step_layers(composite, ids)
    _validate_bindings(composite, layers)
    preflight(composite)
    true
end

function _routes(declaration, bindings)
    route_map = Dict((binding.owner, binding.port) => binding.target
        for binding in bindings)
    inputs = Pair{Symbol,Path}[]
    outputs = Pair{Symbol,Path}[]
    for port in sort!(collect(ports(declaration.law)); by=port -> port.name)
        target = route_map[(declaration.id, port.name)]
        push!(port.direction === :input ? inputs : outputs, port.name => target)
    end
    tuple(inputs...), tuple(outputs...)
end

function _process_plan_entry(declaration, bindings)
    inputs, outputs = _routes(declaration, bindings)
    ProcessPlanEntry(declaration, inputs, outputs)
end

function _step_plan_entry(declaration, bindings)
    inputs, outputs = _routes(declaration, bindings)
    StepPlanEntry(declaration, inputs, outputs)
end

function _provenance(model, composite)
    records = Pair{String,Any}[]
    structure = model.structure
    composite_order = sort!(_rows(structure, :Composite);
        by=row -> String(_attr(structure, row, :composite_id)))
    for (index, row) in enumerate(composite_order)
        push!(records,
            string("composite:", _attr(structure, row, :composite_id)) =>
                (:composite, index))
    end
    store_order = sort!(_rows(structure, :StoreNode);
        by=row -> _attr(structure, row, :store_path))
    for (index, row) in enumerate(store_order)
        push!(records, String(_attr(structure, row, :store_id)) => (:store, index))
    end
    for (index, declaration) in enumerate(composite.processes)
        push!(records, string("actor:", declaration.id) => (:process, index))
    end
    for (index, declaration) in enumerate(composite.steps)
        push!(records, string("actor:", declaration.id) => (:step, index))
    end
    port_order = sort!(_rows(structure, :Port);
        by=row -> String(_attr(structure, row, :port_id)))
    for (index, row) in enumerate(port_order)
        push!(records, String(_attr(structure, row, :port_id)) => (:port, index))
    end
    binding_order = sort!(_rows(structure, :Binding);
        by=row -> String(_attr(structure, row, :binding_id)))
    for (index, row) in enumerate(binding_order)
        push!(records, String(_attr(structure, row, :binding_id)) => (:binding, index))
    end
    containment_order = sort!(_rows(structure, :StoreContainment);
        by=row -> String(_attr(structure, row, :containment_id)))
    for (index, row) in enumerate(containment_order)
        push!(records,
            String(_attr(structure, row, :containment_id)) => (:containment, index))
    end
    composite_containment_order = sort!(_rows(structure, :CompositeContainment);
        by=row -> String(_attr(structure, row, :composite_containment_id)))
    for (index, row) in enumerate(composite_containment_order)
        push!(records,
            String(_attr(structure, row, :composite_containment_id)) =>
                (:composite_containment, index))
    end
    dependency_order = sort!(_rows(structure, :StepDependency);
        by=row -> String(_attr(structure, row, :dependency_id)))
    for (index, row) in enumerate(dependency_order)
        push!(records,
            String(_attr(structure, row, :dependency_id)) => (:dependency, index))
    end
    endpoint_order = sort!(_rows(structure, :Endpoint);
        by=row -> String(_attr(structure, row, :endpoint_id)))
    for (index, row) in enumerate(endpoint_order)
        push!(records,
            String(_attr(structure, row, :endpoint_id)) => (:endpoint, index))
    end
    boundary_order = sort!(_rows(structure, :BoundaryMap);
        by=row -> String(_attr(structure, row, :boundary_map_id)))
    for (index, row) in enumerate(boundary_order)
        push!(records,
            String(_attr(structure, row, :boundary_map_id)) => (:boundary_map, index))
    end
    junction_order = sort!(_rows(structure, :Junction);
        by=row -> String(_attr(structure, row, :junction_id)))
    for (index, row) in enumerate(junction_order)
        push!(records,
            String(_attr(structure, row, :junction_id)) => (:junction, index))
    end
    junction_endpoint_order = sort!(_rows(structure, :JunctionEndpoint);
        by=row -> String(_attr(structure, row, :junction_endpoint_id)))
    for (index, row) in enumerate(junction_endpoint_order)
        push!(records,
            String(_attr(structure, row, :junction_endpoint_id)) =>
                (:junction_endpoint, index))
    end
    StructuralProvenance(tuple(sort!(records; by=first)...))
end

function compile_composite(model::CanonicalModel)
    composite = _materialize_static(model.structure, model.payloads)
    ids = _validate_identities(composite)
    layers = _step_layers(composite, ids)
    _validate_bindings(composite, layers)
    report = preflight(composite)
    initial = initial_snapshot(composite.schema, composite.initial_values;
        time=LogicalTime(0, composite.scale))
    processes = tuple(sort!(collect(composite.processes);
        by=declaration -> declaration.id)...)
    steps = tuple(sort!(collect(composite.steps);
        by=declaration -> declaration.id)...)
    normalized = StaticComposite(
        composite.schema,
        composite.initial_values,
        composite.scale;
        processes,
        steps,
        bindings=composite.bindings)
    process_entries = tuple((_process_plan_entry(declaration, normalized.bindings)
        for declaration in processes)...)
    step_entries = tuple((_step_plan_entry(declaration, normalized.bindings)
        for declaration in steps)...)
    provenance = _provenance(model, normalized)
    epoch = StructuralEpoch(
        PROCESS_BIGRAPH_ACSET_VERSION,
        deepcopy(model.structure),
        model.fingerprint,
        provenance)
    plan = ExecutionPlan(
        normalized.schema,
        normalized.scale,
        process_entries,
        step_entries,
        layers,
        provenance)
    runtime_identity = (
        canonical_fingerprint(normalized.schema),
        initial.entries,
        normalized.scale,
        tuple((_declaration_identity(declaration)
            for declaration in processes)...),
        tuple((_declaration_identity(declaration)
            for declaration in steps)...),
        normalized.bindings,
        layers,
        report.fingerprint,
    )
    has_open_structure =
        length(_rows(model.structure, :Composite)) != 1 ||
        !isempty(_rows(model.structure, :Endpoint)) ||
        !isempty(_rows(model.structure, :Junction))
    fingerprint = canonical_fingerprint(has_open_structure ?
        (:open_static_composite_v1, model.fingerprint, runtime_identity) :
        (:static_composite_v1, runtime_identity...))
    CompiledComposite(epoch, plan, initial, report, fingerprint)
end

compile_composite(composite::StaticComposite) =
    compile_composite(canonical_model(composite))

function compile_composite(
    structure::ConcreteProcessBigraphACSet;
    initial_values=Dict(),
    laws,
    continuations=(),
)
    compile_composite(canonical_model(structure;
        initial_values, laws, continuations))
end

preflight(model::CanonicalModel) =
    preflight(_materialize_static(model.structure, model.payloads))

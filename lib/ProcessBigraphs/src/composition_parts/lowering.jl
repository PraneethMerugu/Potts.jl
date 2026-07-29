function compose_open(spec::CompositionSpec)
    mounts = sort!(collect(spec.mounts); by=mount -> String(mount.key))
    mount_keys = [mount.key for mount in mounts]
    length(mount_keys) == length(unique(mount_keys)) ||
        _fail(:duplicate_mount_key,
            "composition contains duplicate mount keys")
    isempty(mounts) &&
        _fail(:empty_composition,
            "a composed root must mount at least one component")
    junctions = sort!(collect(spec.junctions); by=junction -> junction.id)
    junction_ids = [junction.id for junction in junctions]
    length(junction_ids) == length(unique(junction_ids)) ||
        _fail(:duplicate_junction_identity,
            "composition contains duplicate junction identities")
    junction_targets = [junction.target for junction in junctions]
    length(junction_targets) == length(unique(junction_targets)) ||
        _fail(:duplicate_junction_store,
            "multiple junctions cannot publish the same canonical store path")
    exports = sort!(collect(spec.exports); by=endpoint -> endpoint.name)
    export_names = [endpoint.name for endpoint in exports]
    length(export_names) == length(unique(export_names)) ||
        _fail(:duplicate_endpoint_name,
            "the composed root repeats an exported endpoint name")
    Set(endpoint.junction for endpoint in exports) <= Set(junction_ids) ||
        _fail(:unknown_export_junction,
            "an exported endpoint references an unknown junction")

    scales = Set{TimeScale}()
    source_data = Dict{Symbol,Any}()
    root_endpoint_records = Dict{Tuple{Symbol,Symbol},NamedTuple}()
    for mount in mounts
        model = canonical_model(mount.component)
        structure = canonical_structure(model)
        flat = _materialize_static(structure, model.payloads)
        push!(scales, flat.scale)
        composite_ids, containments, source_root =
            _composite_hierarchy(structure, spec.root_id, mount.key)
        endpoints = _open_root_endpoints(structure)
        for (name, record) in endpoints
            root_endpoint_records[(mount.key, name)] = record
        end
        source_data[mount.key] = (;
            mount,
            model,
            structure,
            flat,
            composite_ids,
            containments,
            source_root,
            endpoints,
        )
    end
    length(scales) == 1 ||
        _fail(:time_scale_mismatch,
            "all mounted components must share one exact time scale")
    scale = only(scales)

    endpoint_to_junction = Dict{Tuple{Symbol,Symbol},JunctionSpec}()
    for junction in junctions, reference in junction.endpoints
        key = (reference.mount, reference.endpoint)
        haskey(root_endpoint_records, key) ||
            _fail(:unknown_endpoint_reference,
                "junction references an unknown mounted endpoint";
                junction=junction.id, mount=reference.mount,
                endpoint=reference.endpoint)
        haskey(endpoint_to_junction, key) &&
            _fail(:endpoint_reused_across_junctions,
                "one mounted endpoint cannot join multiple junctions";
                mount=reference.mount, endpoint=reference.endpoint)
        endpoint_to_junction[key] = junction
    end

    leaves = Dict{Path,LeafSchema}()
    contributions = Dict{Path,Vector{Any}}()
    store_owner = Dict{Path,Tuple{String,Path}}(
        Path() => (spec.root_id, Path()))
    processes = ProcessDeclaration[]
    steps = StepDeclaration[]
    bindings = PortBinding[]
    iteration_regions = IterationRegion[]
    actor_composite = Dict{String,String}()
    actor_local = Dict{String,String}()
    source_path_maps = Dict{Symbol,Dict{Path,Path}}()
    source_endpoint_maps = Dict{Symbol,Dict{Int,Int}}()

    junction_by_endpoint_path = Dict{Tuple{Symbol,Path},Path}()
    for ((mount_key, endpoint_name), junction) in endpoint_to_junction
        record = root_endpoint_records[(mount_key, endpoint_name)]
        path_key = (mount_key, record.target)
        if haskey(junction_by_endpoint_path, path_key) &&
                junction_by_endpoint_path[path_key] != junction.target
            _fail(:endpoint_store_split,
                "two endpoints exposing one local store cannot join different junctions";
                mount=mount_key, target=record.target)
        end
        junction_by_endpoint_path[path_key] = junction.target
    end

    for mount in mounts
        data = source_data[mount.key]
        flat = data.flat
        structure = data.structure
        path_map = Dict{Path,Path}()
        for (source_path, schema) in schema_leaves(flat.schema)
            source_key = (mount.key, source_path)
            target = get(junction_by_endpoint_path, source_key,
                _mount_path(mount.key, source_path))
            target in junction_targets && !haskey(junction_by_endpoint_path, source_key) &&
                _fail(:junction_path_collision,
                    "a junction target collides with unexposed mounted state";
                    mount=mount.key, source_path, target)
            path_map[source_path] = target
            if haskey(leaves, target)
                _schema_equal(leaves[target], schema) ||
                    _fail(:junction_schema_mismatch,
                        "composed stores have incompatible semantic schemas";
                        target)
            else
                leaves[target] = deepcopy(schema)
            end
            initializer = _declared_initializer(flat, source_path)
            initializer isa _NoInitializer ||
                push!(get!(contributions, target, Any[]), initializer)
            source_store = only(ACSets.incident(
                structure, source_path, :store_path))
            owner = target in junction_targets ? spec.root_id :
                data.composite_ids[
                    Int(_attr(structure, source_store, :store_composite))]
            local_path = target in junction_targets ? target :
                _attr(structure, source_store, :store_local_path)
            store_owner[target] = (owner, local_path)
        end
        source_path_maps[mount.key] = path_map

        actor_ids, mounted_processes, mounted_steps =
            _rekey_declarations(flat, structure, data.composite_ids)
        append!(processes, mounted_processes)
        append!(steps, mounted_steps)
        actor_rows = _id_rows(structure, :Actor, :actor_id)
        for (old_id, new_id) in actor_ids
            row = actor_rows[old_id]
            actor_composite[new_id] =
                data.composite_ids[Int(_attr(structure, row, :actor_composite))]
            actor_local[new_id] = String(_attr(structure, row, :actor_local_id))
        end
        for binding in flat.bindings
            push!(bindings, PortBinding(
                actor_ids[binding.owner],
                binding.port,
                path_map[binding.target];
                transfer=binding.transfer))
        end
        source_root_id = data.composite_ids[data.source_root]
        for region in flat.iteration_regions
            push!(iteration_regions, IterationRegion(
                _mounted_iteration_identity(source_root_id, region.id),
                tuple((actor_ids[id] for id in region.steps)...);
                mode=region.mode,
                max_iterations=region.max_iterations,
                watch_paths=tuple((path_map[target]
                    for target in region.watch_paths)...),
            ))
        end
    end

    junction_contracts = Dict{String,Any}()
    for junction in junctions
        records = [root_endpoint_records[(reference.mount, reference.endpoint)]
            for reference in junction.endpoints]
        contract = first(records).contract
        all(record -> canonical_fingerprint(contract) ==
                canonical_fingerprint(record.contract), records) ||
            _fail(:junction_schema_mismatch,
                "all junction endpoints must have exactly compatible schemas";
                junction=junction.id)
        haskey(leaves, junction.target) ||
            _fail(:missing_junction_store,
                "junction target was not realized by its endpoints";
                junction=junction.id, target=junction.target)
        junction_contracts[junction.id] = contract
        store_owner[junction.target] = (spec.root_id, junction.target)
    end

    schema = _schema_from_leaves(leaves)
    overrides = _normalize_values(spec.initial_values)
    unknown_overrides = setdiff(Set(keys(overrides)), Set(keys(leaves)))
    isempty(unknown_overrides) ||
        _fail(:unknown_store_path,
            "composition initializers reference undeclared stores";
            paths=sort!(collect(unknown_overrides)))
    initial_values = Dict{Path,Any}()
    for (target, leaf) in leaves
        if haskey(overrides, target)
            validate_value(leaf, overrides[target])
            initial_values[target] = deepcopy(overrides[target])
            continue
        end
        values = get(contributions, target, Any[])
        isempty(values) && continue
        reference = canonical_fingerprint(first(values))
        all(value -> canonical_fingerprint(value) == reference, values) ||
            _fail(:conflicting_initializers,
                "joined component defaults conflict without a parent override";
                target)
        initial_values[target] = deepcopy(first(values))
    end
    unresolved = sort!([
        target for target in keys(leaves)
        if !haskey(initial_values, target)
    ])
    isempty(unresolved) ||
        _fail(:unresolved_initializer,
            "every composed store needs one root-resolved initializer";
            paths=unresolved)

    aggregate = StaticComposite(
        schema,
        initial_values,
        scale;
        processes=tuple(processes...),
        steps=tuple(steps...),
        bindings=tuple(bindings...),
        iteration_regions=tuple(iteration_regions...))
    structure = _lower_static_to_structure(aggregate)
    root = _root_composite(structure)
    ACSets.set_subpart!(structure, root, :composite_id, spec.root_id)
    ACSets.set_subpart!(structure, root, :composite_definition_id, spec.root_id)

    composite_rows = Dict{String,Int}(spec.root_id => root)
    containment_records = NamedTuple[]
    for mount in mounts
        append!(containment_records, source_data[mount.key].containments)
    end
    for record in sort!(containment_records; by=record -> record.child)
        composite_rows[record.child] = ACSets.add_part!(structure, :Composite;
            composite_id=record.child,
            composite_definition_id=record.definition,
            scale_numerator=scale.numerator,
            scale_denominator=scale.denominator,
            scale_unit=scale.unit)
    end
    for record in sort!(containment_records; by=record -> record.child)
        ACSets.add_part!(structure, :CompositeContainment;
            composite_child=composite_rows[record.child],
            composite_parent=composite_rows[record.parent],
            composite_containment_id=
                _composite_containment_identity(record.parent, record.key),
            mount_key=record.key)
    end

    actor_rows = _id_rows(structure, :Actor, :actor_id)
    for (id, row) in actor_rows
        ACSets.set_subpart!(structure, row, :actor_composite,
            composite_rows[actor_composite[id]])
        ACSets.set_subpart!(structure, row, :actor_local_id, actor_local[id])
    end
    store_rows = Dict(_attr(structure, row, :store_path) => row
        for row in _rows(structure, :StoreNode))
    for (target, row) in store_rows
        owner, local_path = get(store_owner, target, (spec.root_id, target))
        ACSets.set_subpart!(structure, row, :store_composite, composite_rows[owner])
        ACSets.set_subpart!(structure, row, :store_local_path, local_path)
    end

    mounted_root_endpoint_rows = Dict{Tuple{Symbol,Symbol},Int}()
    for mount in mounts
        data = source_data[mount.key]
        source = data.structure
        path_map = source_path_maps[mount.key]
        source_boundary_store = Dict{Int,Int}()
        source_boundary_composite = Dict{Int,Int}()
        for row in _rows(source, :BoundaryMap)
            endpoint = Int(_attr(source, row, :boundary_map_endpoint))
            source_boundary_store[endpoint] =
                Int(_attr(source, row, :boundary_map_store))
            source_boundary_composite[endpoint] =
                Int(_attr(source, row, :boundary_map_composite))
        end
        endpoint_row_map = Dict{Int,Int}()
        for endpoint in sort!(_rows(source, :Endpoint);
                by=row -> String(_attr(source, row, :endpoint_id)))
            old_composite = source_boundary_composite[endpoint]
            new_composite_id = data.composite_ids[old_composite]
            name = Symbol(_attr(source, endpoint, :endpoint_name))
            new_endpoint_id = _mounted_endpoint_identity(new_composite_id, name)
            source_store = source_boundary_store[endpoint]
            source_target = _attr(source, source_store, :store_path)
            target = path_map[source_target]
            new_endpoint = ACSets.add_part!(structure, :Endpoint;
                endpoint_id=new_endpoint_id,
                endpoint_name=name,
                endpoint_role=_attr(source, endpoint, :endpoint_role),
                endpoint_origin_store_id=_mounted_origin_identity(
                    new_composite_id,
                    String(_attr(source, endpoint, :endpoint_origin_store_id))),
                endpoint_local_path=_attr(source, endpoint, :endpoint_local_path),
                endpoint_schema_payload=deepcopy(
                    _attr(source, endpoint, :endpoint_schema_payload)))
            endpoint_row_map[endpoint] = new_endpoint
            ACSets.add_part!(structure, :BoundaryMap;
                boundary_map_endpoint=new_endpoint,
                boundary_map_store=store_rows[target],
                boundary_map_composite=composite_rows[new_composite_id],
                boundary_map_id=_boundary_map_identity(new_endpoint_id))
            if old_composite == data.source_root
                mounted_root_endpoint_rows[(mount.key, name)] = new_endpoint
            end
        end
        source_endpoint_maps[mount.key] = endpoint_row_map

        junction_row_map = Dict{Int,Int}()
        for junction in sort!(_rows(source, :Junction);
                by=row -> String(_attr(source, row, :junction_id)))
            old_composite = Int(_attr(source, junction, :junction_composite))
            new_composite_id = data.composite_ids[old_composite]
            old_id = String(_attr(source, junction, :junction_id))
            new_id = _mounted_junction_identity(new_composite_id, old_id)
            source_store = Int(_attr(source, junction, :junction_store))
            target = path_map[_attr(source, source_store, :store_path)]
            junction_row_map[junction] = ACSets.add_part!(structure, :Junction;
                junction_store=store_rows[target],
                junction_composite=composite_rows[new_composite_id],
                junction_id=new_id)
        end
        for relation in sort!(_rows(source, :JunctionEndpoint);
                by=row -> String(_attr(source, row, :junction_endpoint_id)))
            old_junction =
                Int(_attr(source, relation, :junction_endpoint_junction))
            old_endpoint =
                Int(_attr(source, relation, :junction_endpoint_endpoint))
            junction = junction_row_map[old_junction]
            endpoint = endpoint_row_map[old_endpoint]
            junction_id = String(_attr(structure, junction, :junction_id))
            endpoint_id = String(_attr(structure, endpoint, :endpoint_id))
            ACSets.add_part!(structure, :JunctionEndpoint;
                junction_endpoint_junction=junction,
                junction_endpoint_endpoint=endpoint,
                junction_endpoint_id=
                    _junction_endpoint_identity(junction_id, endpoint_id))
        end
    end

    junction_rows = Dict{String,Int}()
    for junction in junctions
        junction_rows[junction.id] = ACSets.add_part!(structure, :Junction;
            junction_store=store_rows[junction.target],
            junction_composite=root,
            junction_id=junction.id)
    end
    for junction in junctions, reference in junction.endpoints
        endpoint = mounted_root_endpoint_rows[(reference.mount, reference.endpoint)]
        endpoint_id = String(_attr(structure, endpoint, :endpoint_id))
        ACSets.add_part!(structure, :JunctionEndpoint;
            junction_endpoint_junction=junction_rows[junction.id],
            junction_endpoint_endpoint=endpoint,
            junction_endpoint_id=
                _junction_endpoint_identity(junction.id, endpoint_id))
    end
    for endpoint in exports
        junction = only(filter(value -> value.id == endpoint.junction, junctions))
        junction_contract = junction_contracts[junction.id]
        export_contract = _endpoint_contract(
            junction_contract.schema, endpoint.transfer)
        canonical_fingerprint(export_contract) ==
            canonical_fingerprint(junction_contract) ||
            _fail(:junction_schema_mismatch,
                "a re-exported endpoint must preserve the junction contract";
                endpoint=endpoint.name, junction=junction.id)
        endpoint_id = _mounted_endpoint_identity(spec.root_id, endpoint.name)
        endpoint_row = ACSets.add_part!(structure, :Endpoint;
            endpoint_id,
            endpoint_name=endpoint.name,
            endpoint_role=endpoint.role,
            endpoint_origin_store_id=String(
                _attr(structure, store_rows[junction.target], :store_id)),
            endpoint_local_path=junction.target,
            endpoint_schema_payload=deepcopy(export_contract))
        ACSets.add_part!(structure, :BoundaryMap;
            boundary_map_endpoint=endpoint_row,
            boundary_map_store=store_rows[junction.target],
            boundary_map_composite=root,
            boundary_map_id=_boundary_map_identity(endpoint_id))
        ACSets.add_part!(structure, :JunctionEndpoint;
            junction_endpoint_junction=junction_rows[junction.id],
            junction_endpoint_endpoint=endpoint_row,
            junction_endpoint_id=
                _junction_endpoint_identity(junction.id, endpoint_id))
    end

    owners = sort!(collect(_owners(aggregate)); by=declaration -> declaration.id)
    payloads = ModelPayloads(
        aggregate.initial_values,
        (declaration.id => declaration.law for declaration in owners);
        continuations=(declaration.id => declaration.continuation
            for declaration in owners),
        iterations=aggregate.iteration_regions)
    _open_from_model(CanonicalModel(structure, payloads))
end

compose_open(root_id::AbstractString; kwargs...) =
    compose_open(CompositionSpec(root_id; kwargs...))

compile_composite(composite::OpenComposite) =
    compile_composite(canonical_model(composite))
preflight(composite::OpenComposite) = preflight(canonical_model(composite))
compile_composite(
    cospan::ProcessBigraphStructuredMulticospan;
    kwargs...,
) = compile_composite(canonical_model(cospan; kwargs...))
preflight(
    cospan::ProcessBigraphStructuredMulticospan;
    kwargs...,
) = preflight(canonical_model(cospan; kwargs...))

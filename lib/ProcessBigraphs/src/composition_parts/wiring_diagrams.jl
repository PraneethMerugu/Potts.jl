struct AnnotatedWiringDiagram{D}
    profile_version::String
    diagram::D
    structure::ConcreteProcessBigraphACSet
    payloads::ModelPayloads
    structure_fingerprint::String
    annotation_fingerprint::String
end

wiring_diagram(view::AnnotatedWiringDiagram) = deepcopy(view.diagram)
wiring_profile_version(view::AnnotatedWiringDiagram) = view.profile_version

function _diagram_signature(diagram)
    box_records = [
        (
            value=deepcopy(box.value),
            inputs=tuple(deepcopy(Catlab.input_ports(box))...),
            outputs=tuple(deepcopy(Catlab.output_ports(box))...),
        )
        for box in Catlab.boxes(diagram)
    ]
    wire_records = [
        (
            value=deepcopy(wire.value),
            source=(wire.source.box, Symbol(string(wire.source.kind)),
                wire.source.port),
            target=(wire.target.box, Symbol(string(wire.target.kind)),
                wire.target.port),
        )
        for wire in Catlab.wires(diagram)
    ]
    sort!(wire_records; by=canonical_fingerprint)
    (
        value=deepcopy(diagram.value),
        inputs=tuple(deepcopy(Catlab.input_ports(diagram))...),
        outputs=tuple(deepcopy(Catlab.output_ports(diagram))...),
        boxes=tuple(box_records...),
        wires=tuple(wire_records...),
    )
end

diagram_fingerprint(view::AnnotatedWiringDiagram) =
    canonical_fingerprint((
        :process_bigraph_annotated_wiring_v1,
        view.profile_version,
        _diagram_signature(view.diagram),
    ))

function _annotated_port(structure, port_row)
    actor = Int(_attr(structure, port_row, :port_actor))
    (
        kind=:actor_port,
        id=String(_attr(structure, port_row, :port_id)),
        actor=String(_attr(structure, actor, :actor_id)),
        name=Symbol(_attr(structure, port_row, :port_name)),
        direction=Symbol(_attr(structure, port_row, :port_direction)),
        value_type=String(_attr(structure, port_row, :port_value_type)),
        effect=Symbol(_attr(structure, port_row, :port_effect)),
        interval_behavior=Symbol(_attr(structure, port_row, :port_interval_behavior)),
        cardinality=Symbol(_attr(structure, port_row, :port_cardinality)),
        residency=Symbol(_attr(structure, port_row, :port_residency)),
        update_law=_attr(structure, port_row, :port_update_law),
    )
end

function _annotated_endpoint(structure, endpoint_row)
    (
        kind=:boundary_endpoint,
        id=String(_attr(structure, endpoint_row, :endpoint_id)),
        name=Symbol(_attr(structure, endpoint_row, :endpoint_name)),
        role=Symbol(_attr(structure, endpoint_row, :endpoint_role)),
        origin_store=String(
            _attr(structure, endpoint_row, :endpoint_origin_store_id)),
        local_path=_attr(structure, endpoint_row, :endpoint_local_path),
        schema_fingerprint=canonical_fingerprint(
            _attr(structure, endpoint_row, :endpoint_schema_payload)),
    )
end

function annotated_wiring_diagram(value)
    model = value isa CanonicalModel ? canonical_model(value.structure;
        initial_values=value.payloads.initial_values,
        laws=value.payloads.laws,
        continuations=value.payloads.continuations) :
        canonical_model(value)
    structure = canonical_structure(model)
    root = _root_composite(structure)
    root_endpoints = Dict{Int,Int}()
    endpoint_store = Dict{Int,Int}()
    for row in _rows(structure, :BoundaryMap)
        endpoint = Int(_attr(structure, row, :boundary_map_endpoint))
        store = Int(_attr(structure, row, :boundary_map_store))
        endpoint_store[endpoint] = store
        Int(_attr(structure, row, :boundary_map_composite)) == root &&
            (root_endpoints[endpoint] = store)
    end
    import_endpoints = sort!([endpoint for endpoint in keys(root_endpoints)
        if _attr(structure, endpoint, :endpoint_role) in (:import, :bidirectional)];
        by=endpoint -> String(_attr(structure, endpoint, :endpoint_id)))
    export_endpoints = sort!([endpoint for endpoint in keys(root_endpoints)
        if _attr(structure, endpoint, :endpoint_role) in (:export, :bidirectional)];
        by=endpoint -> String(_attr(structure, endpoint, :endpoint_id)))
    diagram = Catlab.WiringDiagram(
        [_annotated_endpoint(structure, endpoint) for endpoint in import_endpoints],
        [_annotated_endpoint(structure, endpoint) for endpoint in export_endpoints])
    diagram.value = (
        profile=PROCESS_BIGRAPH_OPEN_PROFILE_VERSION,
        structure_fingerprint=model.fingerprint,
    )

    actor_box = Dict{Int,Int}()
    actor_input_position = Dict{Int,Int}()
    actor_output_position = Dict{Int,Int}()
    actor_ports = Dict{Int,Vector{Int}}()
    for port in _rows(structure, :Port)
        actor = Int(_attr(structure, port, :port_actor))
        push!(get!(actor_ports, actor, Int[]), port)
    end
    for actor in sort!(_rows(structure, :Actor);
            by=row -> String(_attr(structure, row, :actor_id)))
        inputs = sort!([port for port in get(actor_ports, actor, Int[])
            if _attr(structure, port, :port_direction) === :input];
            by=port -> String(_attr(structure, port, :port_id)))
        outputs = sort!([port for port in get(actor_ports, actor, Int[])
            if _attr(structure, port, :port_direction) === :output];
            by=port -> String(_attr(structure, port, :port_id)))
        box = Catlab.Box((
                kind=:actor,
                id=String(_attr(structure, actor, :actor_id)),
                local_id=String(_attr(structure, actor, :actor_local_id)),
            ),
            [_annotated_port(structure, port) for port in inputs],
            [_annotated_port(structure, port) for port in outputs])
        actor_box[actor] = Catlab.add_box!(diagram, box)
        for (position, port) in enumerate(inputs)
            actor_input_position[port] = position
        end
        for (position, port) in enumerate(outputs)
            actor_output_position[port] = position
        end
    end

    bindings_by_store = Dict{Int,Vector{Int}}()
    binding_port = Dict{Int,Int}()
    for binding in _rows(structure, :Binding)
        store = Int(_attr(structure, binding, :binding_store))
        port = Int(_attr(structure, binding, :binding_port))
        push!(get!(bindings_by_store, store, Int[]), binding)
        binding_port[binding] = port
    end
    imports_by_store = Dict{Int,Vector{Int}}()
    for endpoint in import_endpoints
        push!(get!(imports_by_store, endpoint_store[endpoint], Int[]), endpoint)
    end
    exports_by_store = Dict{Int,Vector{Int}}()
    for endpoint in export_endpoints
        push!(get!(exports_by_store, endpoint_store[endpoint], Int[]), endpoint)
    end
    outer_import_position =
        Dict(endpoint => index for (index, endpoint) in enumerate(import_endpoints))
    outer_export_position =
        Dict(endpoint => index for (index, endpoint) in enumerate(export_endpoints))

    for store in sort!(_rows(structure, :StoreNode);
            by=row -> _attr(structure, row, :store_path))
        _attr(structure, store, :schema_kind) === :leaf || continue
        writer_bindings = sort!([binding for binding in get(bindings_by_store, store, Int[])
            if _attr(structure, binding_port[binding], :port_direction) === :output];
            by=binding -> String(_attr(structure, binding, :binding_id)))
        reader_bindings = sort!([binding for binding in get(bindings_by_store, store, Int[])
            if _attr(structure, binding_port[binding], :port_direction) === :input];
            by=binding -> String(_attr(structure, binding, :binding_id)))
        store_imports = sort!(get(imports_by_store, store, Int[]);
            by=endpoint -> String(_attr(structure, endpoint, :endpoint_id)))
        store_exports = sort!(get(exports_by_store, store, Int[]);
            by=endpoint -> String(_attr(structure, endpoint, :endpoint_id)))
        input_annotations = Any[
            (
                kind=:store_write,
                binding=String(_attr(structure, binding, :binding_id)),
                port=String(_attr(structure, binding_port[binding], :port_id)),
            )
            for binding in writer_bindings
        ]
        append!(input_annotations, Any[
            (
                kind=:external_import,
                endpoint=String(_attr(structure, endpoint, :endpoint_id)),
            )
            for endpoint in store_imports
        ])
        output_annotations = Any[
            (
                kind=:store_read,
                binding=String(_attr(structure, binding, :binding_id)),
                port=String(_attr(structure, binding_port[binding], :port_id)),
            )
            for binding in reader_bindings
        ]
        append!(output_annotations, Any[
            (
                kind=:external_export,
                endpoint=String(_attr(structure, endpoint, :endpoint_id)),
            )
            for endpoint in store_exports
        ])
        store_box = Catlab.add_box!(diagram, Catlab.Box((
                kind=:store,
                id=String(_attr(structure, store, :store_id)),
                path=_attr(structure, store, :store_path),
                schema_fingerprint=canonical_fingerprint(
                    _attr(structure, store, :schema_payload)),
            ), input_annotations, output_annotations))
        for (position, binding) in enumerate(writer_bindings)
            port = binding_port[binding]
            actor = Int(_attr(structure, port, :port_actor))
            Catlab.add_wire!(diagram,
                (actor_box[actor], actor_output_position[port]) =>
                    (store_box, position))
        end
        writer_offset = length(writer_bindings)
        for (index, endpoint) in enumerate(store_imports)
            Catlab.add_wire!(diagram,
                (Catlab.input_id(diagram), outer_import_position[endpoint]) =>
                    (store_box, writer_offset + index))
        end
        for (position, binding) in enumerate(reader_bindings)
            port = binding_port[binding]
            actor = Int(_attr(structure, port, :port_actor))
            Catlab.add_wire!(diagram,
                (store_box, position) =>
                    (actor_box[actor], actor_input_position[port]))
        end
        reader_offset = length(reader_bindings)
        for (index, endpoint) in enumerate(store_exports)
            Catlab.add_wire!(diagram,
                (store_box, reader_offset + index) =>
                    (Catlab.output_id(diagram), outer_export_position[endpoint]))
        end
    end

    annotation_fingerprint = canonical_fingerprint((
        :process_bigraph_annotated_wiring_v1,
        PROCESS_BIGRAPH_OPEN_PROFILE_VERSION,
        _diagram_signature(diagram),
    ))
    AnnotatedWiringDiagram(
        PROCESS_BIGRAPH_OPEN_PROFILE_VERSION,
        diagram,
        structure,
        model.payloads,
        model.fingerprint,
        annotation_fingerprint,
    )
end

function canonical_model(view::AnnotatedWiringDiagram)
    view.profile_version == PROCESS_BIGRAPH_OPEN_PROFILE_VERSION ||
        _fail(:unsupported_wiring_profile,
            "annotated wiring profile version is unsupported";
            version=view.profile_version)
    actual_structure = structural_fingerprint(view.structure)
    actual_structure == view.structure_fingerprint ||
        _fail(:wiring_structure_mismatch,
            "annotated wiring structure fingerprint is invalid";
            expected=view.structure_fingerprint, actual=actual_structure)
    actual_annotations = diagram_fingerprint(view)
    actual_annotations == view.annotation_fingerprint ||
        _fail(:wiring_annotation_mismatch,
            "annotated wiring diagram was changed or is incomplete";
            expected=view.annotation_fingerprint, actual=actual_annotations)
    CanonicalModel(view.structure, view.payloads)
end

canonical_structure(view::AnnotatedWiringDiagram) =
    canonical_structure(canonical_model(view))
structural_fingerprint(view::AnnotatedWiringDiagram) =
    structural_fingerprint(canonical_model(view))
compile_composite(view::AnnotatedWiringDiagram) =
    compile_composite(canonical_model(view))

canonical_model(::Catlab.WiringDiagram) =
    _fail(:unsupported_wiring_profile,
        "generic directed wiring diagrams are inspection-only; compilation requires the annotated ProcessBigraph profile")
compile_composite(diagram::Catlab.WiringDiagram) = compile_composite(canonical_model(diagram))

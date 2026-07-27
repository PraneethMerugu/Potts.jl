const PROCESS_BIGRAPH_OPEN_PROFILE_VERSION = "1.0.0"

struct BoundaryEndpoint
    name::Symbol
    target::Path
    role::Symbol
    transfer::Union{Nothing,TransferDeclaration}
    function BoundaryEndpoint(
        name::Symbol,
        target::Path;
        role::Symbol,
        transfer=nothing,
    )
        role in (:import, :export, :bidirectional) ||
            _fail(:invalid_endpoint_role, "unknown open-composite endpoint role";
                name, role)
        (isnothing(transfer) || transfer isa TransferDeclaration) ||
            _fail(:invalid_endpoint_transfer,
                "endpoint transfer metadata must be nothing or TransferDeclaration";
                name, actual=string(typeof(transfer)))
        new(name, target, role, deepcopy(transfer))
    end
end

struct OpenComposite{C}
    definition_id::String
    model::CanonicalModel
    cospan::C
end

struct CompositeMount{C<:OpenComposite}
    key::Symbol
    component::C
    function CompositeMount(key::Symbol, component::C) where {C<:OpenComposite}
        isempty(String(key)) &&
            _fail(:invalid_mount_key, "mount keys cannot be empty")
        new{C}(key, component)
    end
end

struct EndpointRef
    mount::Symbol
    endpoint::Symbol
end

struct JunctionSpec
    id::String
    target::Path
    endpoints::Tuple{Vararg{EndpointRef}}
    function JunctionSpec(id::AbstractString, target::Path, endpoints)
        identity = String(id)
        isempty(identity) &&
            _fail(:empty_junction_identity, "junction identity cannot be empty")
        normalized = tuple(endpoints...)
        isempty(normalized) &&
            _fail(:empty_junction, "junctions must reference at least one endpoint";
                junction=identity)
        all(reference -> reference isa EndpointRef, normalized) ||
            _fail(:invalid_endpoint_reference,
                "junction endpoints must be EndpointRef values"; junction=identity)
        length(normalized) == length(unique(normalized)) ||
            _fail(:duplicate_junction_endpoint,
                "junction repeats one endpoint reference"; junction=identity)
        new(identity, target, normalized)
    end
end

struct CompositeExport
    name::Symbol
    role::Symbol
    junction::String
    transfer::Union{Nothing,TransferDeclaration}
    function CompositeExport(
        name::Symbol,
        junction::AbstractString;
        role::Symbol,
        transfer=nothing,
    )
        role in (:import, :export, :bidirectional) ||
            _fail(:invalid_endpoint_role, "unknown parent endpoint role"; name, role)
        identity = String(junction)
        isempty(identity) &&
            _fail(:empty_junction_identity,
                "an exported endpoint must name a junction"; name)
        (isnothing(transfer) || transfer isa TransferDeclaration) ||
            _fail(:invalid_endpoint_transfer,
                "endpoint transfer metadata must be nothing or TransferDeclaration";
                name, actual=string(typeof(transfer)))
        new(name, role, identity, deepcopy(transfer))
    end
end

struct MountGroup
    mounts::Tuple{Vararg{CompositeMount}}
end

function mount_group(items...)
    result = CompositeMount[]
    function append_item(item)
        if item isa CompositeMount
            push!(result, item)
        elseif item isa MountGroup
            foreach(append_item, item.mounts)
        else
            _fail(:invalid_mount_group,
                "mount groups may contain only mounts or nested mount groups";
                actual=string(typeof(item)))
        end
    end
    foreach(append_item, items)
    MountGroup(tuple(result...))
end

struct CompositionSpec
    root_id::String
    mounts::Tuple{Vararg{CompositeMount}}
    junctions::Tuple{Vararg{JunctionSpec}}
    exports::Tuple{Vararg{CompositeExport}}
    initial_values::Any
end

function CompositionSpec(
    root_id::AbstractString;
    mounts,
    junctions=(),
    exports=(),
    initial_values=Dict(),
)
    identity = String(root_id)
    isempty(identity) &&
        _fail(:empty_composite_identity, "composed root identity cannot be empty")
    normalized_mounts = mounts isa MountGroup ? mounts.mounts : tuple(mounts...)
    all(mount -> mount isa CompositeMount, normalized_mounts) ||
        _fail(:invalid_mount_declaration,
            "composition mounts must be CompositeMount values")
    normalized_junctions = tuple(junctions...)
    all(junction -> junction isa JunctionSpec, normalized_junctions) ||
        _fail(:invalid_junction_declaration,
            "composition junctions must be JunctionSpec values")
    normalized_exports = tuple(exports...)
    all(endpoint -> endpoint isa CompositeExport, normalized_exports) ||
        _fail(:invalid_export_declaration,
            "composition exports must be CompositeExport values")
    CompositionSpec(identity, normalized_mounts, normalized_junctions,
        normalized_exports, deepcopy(initial_values))
end

canonical_model(composite::OpenComposite) =
    CanonicalModel(composite.model.structure, composite.model.payloads)
canonical_structure(composite::OpenComposite) = canonical_structure(composite.model)
structural_fingerprint(composite::OpenComposite) =
    structural_fingerprint(composite.model)
structured_cospan(composite::OpenComposite) = deepcopy(composite.cospan)

_schema_equal(left::AbstractSchema, right::AbstractSchema) =
    canonical_fingerprint(left) == canonical_fingerprint(right)

_mounted_composite_identity(parent::AbstractString, key::Symbol) =
    string("composite:",
        canonical_fingerprint((:mounted_composite_v1, String(parent), key)))
_mounted_actor_identity(composite::AbstractString, local_id::AbstractString) =
    string("actor:",
        canonical_fingerprint((:mounted_actor_v1, String(composite), String(local_id))))
_mounted_endpoint_identity(composite::AbstractString, name::Symbol) =
    string("endpoint:",
        canonical_fingerprint((:mounted_endpoint_v1, String(composite), name)))
_mounted_junction_identity(composite::AbstractString, source::AbstractString) =
    string("junction:",
        canonical_fingerprint((:mounted_junction_v1, String(composite), String(source))))
_mounted_origin_identity(composite::AbstractString, source::AbstractString) =
    string("origin:",
        canonical_fingerprint((:mounted_origin_v1, String(composite), String(source))))
_composite_containment_identity(parent::AbstractString, key::Symbol) =
    string("composite-containment:",
        canonical_fingerprint((:composite_containment_v1, String(parent), key)))
_boundary_map_identity(endpoint::AbstractString) =
    string("boundary-map:",
        canonical_fingerprint((:boundary_map_v1, String(endpoint))))
_junction_endpoint_identity(junction::AbstractString, endpoint::AbstractString) =
    string("junction-endpoint:",
        canonical_fingerprint((:junction_endpoint_v1,
            String(junction), String(endpoint))))

_mount_path(key::Symbol, local_path::Path) =
    child(Path(), String(key), segments(local_path)...)

function _open_root_endpoints(structure)
    root = _root_composite(structure)
    result = Dict{Symbol,NamedTuple}()
    for row in _rows(structure, :BoundaryMap)
        Int(_attr(structure, row, :boundary_map_composite)) == root || continue
        endpoint = Int(_attr(structure, row, :boundary_map_endpoint))
        name = Symbol(_attr(structure, endpoint, :endpoint_name))
        haskey(result, name) &&
            _fail(:duplicate_endpoint_name,
                "root composite contains duplicate endpoint names"; name)
        store = Int(_attr(structure, row, :boundary_map_store))
        result[name] = (
            endpoint_row=endpoint,
            endpoint_id=String(_attr(structure, endpoint, :endpoint_id)),
            role=Symbol(_attr(structure, endpoint, :endpoint_role)),
            store_row=store,
            target=_attr(structure, store, :store_path),
            contract=_validated_endpoint_contract(
                _attr(structure, endpoint, :endpoint_schema_payload)),
            schema=_validated_endpoint_contract(
                _attr(structure, endpoint, :endpoint_schema_payload)).schema,
        )
    end
    result
end

function _make_structured_cospan(model::CanonicalModel)
    structure = canonical_structure(model)
    root_endpoints = _open_root_endpoints(structure)
    endpoint_count = length(_rows(structure, :Endpoint))
    imports = sort!([record.endpoint_row for record in values(root_endpoints)
        if record.role in (:import, :bidirectional)])
    exports = sort!([record.endpoint_row for record in values(root_endpoints)
        if record.role in (:export, :bidirectional)])
    Cospan = ProcessBigraphStructuredMulticospan{
        String,String,Symbol,Bool,Int,Path,Any}
    Cospan(
        structure,
        Catlab.FinFunction(imports, endpoint_count),
        Catlab.FinFunction(exports, endpoint_count),
    )
end

function _foot_endpoint_ids(foot)
    Set(String(ACSets.subpart(foot, row, :endpoint_id))
        for row in ACSets.parts(foot, :Endpoint))
end

function canonical_model(
    cospan::ProcessBigraphStructuredMulticospan;
    initial_values,
    laws,
    continuations=(),
)
    structure = Catlab.apex(cospan)
    structure isa ConcreteProcessBigraphACSet ||
        _fail(:invalid_structured_cospan_apex,
            "structured cospan apex must be a ProcessBigraphACSet";
            actual=string(typeof(structure)))
    model = canonical_model(
        structure;
        initial_values,
        laws,
        continuations,
    )
    endpoints = _open_root_endpoints(model.structure)
    expected_imports = Set(record.endpoint_id for record in values(endpoints)
        if record.role in (:import, :bidirectional))
    expected_exports = Set(record.endpoint_id for record in values(endpoints)
        if record.role in (:export, :bidirectional))
    feet = Catlab.feet(cospan)
    length(feet) == 2 ||
        _fail(:invalid_structured_cospan_arity,
            "ProcessBigraph structured cospans require import and export feet";
            actual=length(feet))
    actual_imports = _foot_endpoint_ids(feet[1])
    actual_exports = _foot_endpoint_ids(feet[2])
    actual_imports == expected_imports ||
        _fail(:structured_cospan_import_mismatch,
            "structured cospan import foot disagrees with endpoint roles";
            expected=sort!(collect(expected_imports)),
            actual=sort!(collect(actual_imports)))
    actual_exports == expected_exports ||
        _fail(:structured_cospan_export_mismatch,
            "structured cospan export foot disagrees with endpoint roles";
            expected=sort!(collect(expected_exports)),
            actual=sort!(collect(actual_exports)))
    model
end

function _open_from_model(model::CanonicalModel)
    root = _root_composite(model.structure)
    definition_id =
        String(_attr(model.structure, root, :composite_definition_id))
    OpenComposite(definition_id, model, _make_structured_cospan(model))
end

function open_composite(
    definition_id::AbstractString,
    source::StaticComposite;
    endpoints,
)
    identity = String(definition_id)
    isempty(identity) &&
        _fail(:empty_composite_definition_identity,
            "open-composite definition identity cannot be empty")
    base = canonical_model(source)
    structure = canonical_structure(base)
    root = _root_composite(structure)
    ACSets.set_subpart!(structure, root, :composite_id, identity)
    ACSets.set_subpart!(structure, root, :composite_definition_id, identity)
    store_by_path = Dict(_attr(structure, row, :store_path) => row
        for row in _rows(structure, :StoreNode))
    names = Set{Symbol}()
    for endpoint in sort!(collect(endpoints); by=value -> value.name)
        endpoint isa BoundaryEndpoint ||
            _fail(:invalid_endpoint_declaration,
                "open-composite endpoints must be BoundaryEndpoint values")
        endpoint.name in names &&
            _fail(:duplicate_endpoint_name,
                "one open composite repeats an endpoint name";
                name=endpoint.name)
        push!(names, endpoint.name)
        haskey(store_by_path, endpoint.target) ||
            _fail(:unknown_endpoint_store,
                "endpoint references an unknown store";
                name=endpoint.name, target=endpoint.target)
        store = store_by_path[endpoint.target]
        _attr(structure, store, :schema_kind) === :leaf ||
            _fail(:endpoint_targets_branch,
                "open-composite endpoints must expose leaf stores";
                name=endpoint.name, target=endpoint.target)
        endpoint_id = _mounted_endpoint_identity(identity, endpoint.name)
        endpoint_row = ACSets.add_part!(structure, :Endpoint;
            endpoint_id,
            endpoint_name=endpoint.name,
            endpoint_role=endpoint.role,
            endpoint_origin_store_id=String(_attr(structure, store, :store_id)),
            endpoint_local_path=endpoint.target,
            endpoint_schema_payload=_endpoint_contract(
                _attr(structure, store, :schema_payload), endpoint.transfer))
        ACSets.add_part!(structure, :BoundaryMap;
            boundary_map_endpoint=endpoint_row,
            boundary_map_store=store,
            boundary_map_composite=root,
            boundary_map_id=_boundary_map_identity(endpoint_id))
    end
    _open_from_model(CanonicalModel(structure, base.payloads))
end

function _schema_from_leaves(leaves::Dict{Path,LeafSchema})
    isempty(leaves) && return BranchSchema(Pair{String,AbstractSchema}[])
    if haskey(leaves, Path())
        length(leaves) == 1 ||
            _fail(:schema_path_collision,
                "a root leaf cannot coexist with descendant leaves")
        return deepcopy(leaves[Path()])
    end
    tree = Dict{String,Any}()
    for (target, schema) in sort!(collect(leaves); by=first)
        current = tree
        parts = segments(target)
        isempty(parts) &&
            _fail(:schema_path_collision, "unexpected root leaf")
        for (index, segment) in enumerate(parts)
            segment isa NameSegment ||
                _fail(:schema_path_mismatch,
                    "composed BranchSchema paths require name segments"; target)
            name = segment.value
            if index == length(parts)
                haskey(current, name) &&
                    _fail(:schema_path_collision,
                        "composed stores collide at one path"; target)
                current[name] = deepcopy(schema)
            else
                if !haskey(current, name)
                    current[name] = Dict{String,Any}()
                elseif current[name] isa LeafSchema
                    _fail(:schema_path_collision,
                        "a composed path descends through a leaf"; target)
                end
                current = current[name]
            end
        end
    end
    function build(node::Dict{String,Any})
        BranchSchema([name => (value isa Dict ? build(value) : value)
            for (name, value) in sort!(collect(node); by=first)])
    end
    build(tree)
end

struct _NoInitializer end
const _NO_INITIALIZER = _NoInitializer()

function _declared_initializer(composite::StaticComposite, target::Path)
    supplied = _normalize_values(composite.initial_values)
    haskey(supplied, target) && return deepcopy(supplied[target])
    schema = schema_at(composite.schema, target)
    schema isa LeafSchema ||
        _fail(:initializer_targets_branch,
            "initializers resolve only leaf stores"; target)
    schema.default isa NoDefault ? _NO_INITIALIZER : deepcopy(schema.default)
end

function _composite_hierarchy(structure, parent_id::String, mount_key::Symbol)
    source_root = _root_composite(structure)
    children = Dict{Int,Vector{Tuple{Symbol,Int}}}(
        row => Tuple{Symbol,Int}[] for row in _rows(structure, :Composite))
    for row in _rows(structure, :CompositeContainment)
        parent = Int(_attr(structure, row, :composite_parent))
        child_row = Int(_attr(structure, row, :composite_child))
        key = Symbol(_attr(structure, row, :mount_key))
        push!(children[parent], (key, child_row))
    end
    ids = Dict{Int,String}()
    containments = NamedTuple[]
    function assign(row, new_parent::String, key::Symbol)
        id = _mounted_composite_identity(new_parent, key)
        ids[row] = id
        push!(containments, (
            child=id,
            parent=new_parent,
            key,
            definition=String(_attr(structure, row, :composite_definition_id)),
        ))
        for (child_key, child_row) in sort!(children[row]; by=first)
            assign(child_row, id, child_key)
        end
    end
    assign(source_root, parent_id, mount_key)
    ids, containments, source_root
end

function _rekey_declarations(
    source::StaticComposite,
    structure,
    composite_ids::Dict{Int,String},
)
    actor_rows = _id_rows(structure, :Actor, :actor_id)
    actor_ids = Dict{String,String}()
    for declaration in _owners(source)
        row = actor_rows[declaration.id]
        composite = Int(_attr(structure, row, :actor_composite))
        local_id = String(_attr(structure, row, :actor_local_id))
        actor_ids[declaration.id] =
            _mounted_actor_identity(composite_ids[composite], local_id)
    end
    processes = ProcessDeclaration[]
    for declaration in source.processes
        push!(processes, ProcessDeclaration(
            actor_ids[declaration.id],
            declaration.law,
            declaration.schedule;
            domain=declaration.domain,
            continuation=declaration.continuation,
            continuation_version=declaration.continuation_version))
    end
    steps = StepDeclaration[]
    for declaration in source.steps
        push!(steps, StepDeclaration(
            actor_ids[declaration.id],
            declaration.law;
            dependencies=tuple((actor_ids[id] for id in declaration.dependencies)...),
            domain=declaration.domain,
            continuation=declaration.continuation,
            continuation_version=declaration.continuation_version))
    end
    actor_ids, processes, steps
end

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
            target = get(junction_by_endpoint_path, (mount.key, source_path),
                _mount_path(mount.key, source_path))
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

    aggregate = StaticComposite(
        schema,
        initial_values,
        scale;
        processes=tuple(processes...),
        steps=tuple(steps...),
        bindings=tuple(bindings...))
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
            for declaration in owners))
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

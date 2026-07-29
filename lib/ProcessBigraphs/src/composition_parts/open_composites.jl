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
_mounted_iteration_identity(composite::AbstractString, source::AbstractString) =
    string("iteration:",
        canonical_fingerprint((:mounted_iteration_v1,
            String(composite), String(source))))
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
    iterations=(),
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
        iterations,
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

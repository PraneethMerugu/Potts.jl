const PROCESS_BIGRAPH_ACSET_VERSION = "1.1.0"

const SchProcessBigraph = BasicSchema(
    [
        :Composite,
        :StoreNode,
        :StoreContainment,
        :CompositeContainment,
        :Actor,
        :Process,
        :Step,
        :Port,
        :Binding,
        :StepDependency,
        :Endpoint,
        :BoundaryMap,
        :Junction,
        :JunctionEndpoint,
    ],
    [
        (:store_composite, :StoreNode, :Composite),
        (:containment_child, :StoreContainment, :StoreNode),
        (:containment_parent, :StoreContainment, :StoreNode),
        (:composite_child, :CompositeContainment, :Composite),
        (:composite_parent, :CompositeContainment, :Composite),
        (:actor_composite, :Actor, :Composite),
        (:process_actor, :Process, :Actor),
        (:step_actor, :Step, :Actor),
        (:port_actor, :Port, :Actor),
        (:binding_port, :Binding, :Port),
        (:binding_store, :Binding, :StoreNode),
        (:dependency_before, :StepDependency, :Step),
        (:dependency_after, :StepDependency, :Step),
        (:boundary_map_endpoint, :BoundaryMap, :Endpoint),
        (:boundary_map_store, :BoundaryMap, :StoreNode),
        (:boundary_map_composite, :BoundaryMap, :Composite),
        (:junction_store, :Junction, :StoreNode),
        (:junction_composite, :Junction, :Composite),
        (:junction_endpoint_junction, :JunctionEndpoint, :Junction),
        (:junction_endpoint_endpoint, :JunctionEndpoint, :Endpoint),
    ],
    [:SemanticID, :Text, :Kind, :Flag, :Count, :PathValue, :Value],
    [
        (:composite_id, :Composite, :SemanticID),
        (:composite_definition_id, :Composite, :SemanticID),
        (:scale_numerator, :Composite, :Count),
        (:scale_denominator, :Composite, :Count),
        (:scale_unit, :Composite, :Kind),
        (:store_id, :StoreNode, :SemanticID),
        (:store_path, :StoreNode, :PathValue),
        (:store_local_path, :StoreNode, :PathValue),
        (:schema_kind, :StoreNode, :Kind),
        (:schema_payload, :StoreNode, :Value),
        (:containment_id, :StoreContainment, :SemanticID),
        (:composite_containment_id, :CompositeContainment, :SemanticID),
        (:mount_key, :CompositeContainment, :Kind),
        (:actor_id, :Actor, :SemanticID),
        (:actor_local_id, :Actor, :SemanticID),
        (:law_type, :Actor, :Text),
        (:law_version, :Actor, :Text),
        (:law_parameters, :Actor, :Value),
        (:capability_payload, :Actor, :Value),
        (:actor_domain, :Actor, :Kind),
        (:continuation_version, :Actor, :Text),
        (:cadence_tick, :Process, :Count),
        (:first_due_tick, :Process, :Count),
        (:supports_partial, :Process, :Flag),
        (:port_id, :Port, :SemanticID),
        (:port_name, :Port, :Kind),
        (:port_value_type, :Port, :Text),
        (:port_direction, :Port, :Kind),
        (:port_effect, :Port, :Kind),
        (:port_interval_behavior, :Port, :Kind),
        (:port_optional, :Port, :Flag),
        (:port_cardinality, :Port, :Kind),
        (:port_residency, :Port, :Kind),
        (:port_update_law, :Port, :Value),
        (:binding_id, :Binding, :SemanticID),
        (:transfer_payload, :Binding, :Value),
        (:dependency_id, :StepDependency, :SemanticID),
        (:endpoint_id, :Endpoint, :SemanticID),
        (:endpoint_name, :Endpoint, :Kind),
        (:endpoint_role, :Endpoint, :Kind),
        (:endpoint_origin_store_id, :Endpoint, :SemanticID),
        (:endpoint_local_path, :Endpoint, :PathValue),
        (:endpoint_schema_payload, :Endpoint, :Value),
        (:boundary_map_id, :BoundaryMap, :SemanticID),
        (:junction_id, :Junction, :SemanticID),
        (:junction_endpoint_id, :JunctionEndpoint, :SemanticID),
    ],
)

@acset_type ProcessBigraphACSet(SchProcessBigraph,
    index=[
        :store_composite,
        :containment_child,
        :containment_parent,
        :composite_child,
        :composite_parent,
        :actor_composite,
        :process_actor,
        :step_actor,
        :port_actor,
        :binding_port,
        :binding_store,
        :dependency_before,
        :dependency_after,
        :boundary_map_endpoint,
        :boundary_map_store,
        :boundary_map_composite,
        :junction_store,
        :junction_composite,
        :junction_endpoint_junction,
        :junction_endpoint_endpoint,
    ],
    unique_index=[
        :composite_id,
        :store_id,
        :containment_id,
        :composite_containment_id,
        :actor_id,
        :port_id,
        :binding_id,
        :dependency_id,
        :endpoint_id,
        :boundary_map_id,
        :junction_id,
        :junction_endpoint_id,
    ])

const ConcreteProcessBigraphACSet =
    ProcessBigraphACSet{String,String,Symbol,Bool,Int,Path,Any}

ProcessBigraphACSet() = ConcreteProcessBigraphACSet()

const ProcessBigraphOpenOb, ProcessBigraphStructuredMulticospan =
    Catlab.OpenACSetTypes(ProcessBigraphACSet, :Endpoint)

function _endpoint_contract(schema::LeafSchema, transfer)
    (isnothing(transfer) || transfer isa TransferDeclaration) ||
        _fail(:invalid_endpoint_transfer,
            "endpoint transfer metadata must be nothing or TransferDeclaration";
            actual=string(typeof(transfer)))
    (schema=deepcopy(schema), transfer=deepcopy(transfer))
end

function _validated_endpoint_contract(value)
    value isa NamedTuple &&
        hasproperty(value, :schema) &&
        hasproperty(value, :transfer) ||
        _fail(:invalid_endpoint_contract,
            "endpoint metadata must contain schema and transfer fields")
    value.schema isa LeafSchema ||
        _fail(:invalid_endpoint_contract,
            "endpoint schema metadata must be a LeafSchema";
            actual=string(typeof(value.schema)))
    (isnothing(value.transfer) || value.transfer isa TransferDeclaration) ||
        _fail(:invalid_endpoint_transfer,
            "endpoint transfer metadata must be nothing or TransferDeclaration";
            actual=string(typeof(value.transfer)))
    value
end

struct ModelPayloads
    initial_values::Any
    laws::Tuple
    continuations::Tuple
    iterations::Tuple{Vararg{IterationRegion}}
    function ModelPayloads(initial_values, laws, continuations, iterations)
        normalized_laws = tuple(sort!(
            Pair{String,Any}[String(first(pair)) => last(pair) for pair in laws];
            by=first)...)
        normalized_continuations = tuple(sort!(
            Pair{String,Any}[String(first(pair)) => deepcopy(last(pair))
                for pair in continuations];
            by=first)...)
        normalized_iterations = tuple(sort!(
            IterationRegion[deepcopy(region) for region in iterations];
            by=region -> region.id)...)
        new(deepcopy(initial_values), normalized_laws, normalized_continuations,
            normalized_iterations)
    end
end

function ModelPayloads(initial_values, laws; continuations=(), iterations=())
    ModelPayloads(initial_values, laws, continuations, iterations)
end

ModelPayloads(initial_values, laws, continuations) =
    ModelPayloads(initial_values, laws, continuations, ())

struct CanonicalModel
    structure::ConcreteProcessBigraphACSet
    payloads::ModelPayloads
    fingerprint::String
    function CanonicalModel(
        structure::ConcreteProcessBigraphACSet,
        payloads::ModelPayloads,
    )
        frozen = deepcopy(structure)
        _validate_canonical_structure(frozen, payloads)
        new(frozen, payloads, structural_fingerprint(frozen))
    end
end

struct StructuralProvenance
    entries::Tuple
end

struct StructuralEpoch
    version::String
    structure::ConcreteProcessBigraphACSet
    fingerprint::String
    provenance::StructuralProvenance
end

struct ProcessPlanEntry
    declaration::ProcessDeclaration
    inputs::Tuple
    outputs::Tuple
end

struct StepPlanEntry
    declaration::StepDeclaration
    inputs::Tuple
    outputs::Tuple
end

struct ExecutionPlan
    schema::AbstractSchema
    scale::TimeScale
    processes::Tuple
    steps::Tuple
    layers::Tuple
    iterations::Tuple{Vararg{IterationRegion}}
    provenance::StructuralProvenance
    fingerprint::String
end

function _canonical(io::IO, provenance::StructuralProvenance)
    write(io, "PV")
    _canonical(io, provenance.entries)
end

function _canonical(io::IO, epoch::StructuralEpoch)
    write(io, "EP")
    _canonical(io, epoch.version)
    _canonical(io, epoch.fingerprint)
    _canonical(io, epoch.provenance)
end

_rows(structure, object::Symbol) = collect(ACSets.parts(structure, object))
_attr(structure, row::Integer, name::Symbol) = ACSets.subpart(structure, row, name)

function _id_rows(structure, object::Symbol, attribute::Symbol)
    Dict(String(_attr(structure, row, attribute)) => row for row in _rows(structure, object))
end

function _actor_kinds(structure)
    kinds = Dict{Int,Symbol}()
    for row in _rows(structure, :Process)
        actor = Int(_attr(structure, row, :process_actor))
        haskey(kinds, actor) &&
            _fail(:duplicate_actor_kind, "actor appears in more than one kind table";
                actor)
        kinds[actor] = :process
    end
    for row in _rows(structure, :Step)
        actor = Int(_attr(structure, row, :step_actor))
        haskey(kinds, actor) &&
            _fail(:duplicate_actor_kind, "actor appears in more than one kind table";
                actor)
        kinds[actor] = :step
    end
    kinds
end

function _semantic_records(structure::ConcreteProcessBigraphACSet)
    composite_ids = Dict(row => String(_attr(structure, row, :composite_id))
        for row in _rows(structure, :Composite))
    store_ids = Dict(row => String(_attr(structure, row, :store_id))
        for row in _rows(structure, :StoreNode))
    actor_ids = Dict(row => String(_attr(structure, row, :actor_id))
        for row in _rows(structure, :Actor))
    port_ids = Dict(row => String(_attr(structure, row, :port_id))
        for row in _rows(structure, :Port))
    process_actors = Dict(Int(_attr(structure, row, :process_actor)) => row
        for row in _rows(structure, :Process))
    step_actors = Dict(Int(_attr(structure, row, :step_actor)) => row
        for row in _rows(structure, :Step))

    composites = sort!([
        (
            id=composite_ids[row],
            definition_id=String(_attr(structure, row, :composite_definition_id)),
            numerator=_attr(structure, row, :scale_numerator),
            denominator=_attr(structure, row, :scale_denominator),
            unit=_attr(structure, row, :scale_unit),
        )
        for row in _rows(structure, :Composite)
    ]; by=record -> record.id)
    stores = sort!([
        (
            id=store_ids[row],
            composite=composite_ids[Int(_attr(structure, row, :store_composite))],
            path=_attr(structure, row, :store_path),
            local_path=_attr(structure, row, :store_local_path),
            kind=_attr(structure, row, :schema_kind),
            payload=_attr(structure, row, :schema_payload),
        )
        for row in _rows(structure, :StoreNode)
    ]; by=record -> record.id)
    containments = sort!([
        (
            id=String(_attr(structure, row, :containment_id)),
            child=store_ids[Int(_attr(structure, row, :containment_child))],
            parent=store_ids[Int(_attr(structure, row, :containment_parent))],
        )
        for row in _rows(structure, :StoreContainment)
    ]; by=record -> record.id)
    composite_containments = sort!([
        (
            id=String(_attr(structure, row, :composite_containment_id)),
            child=composite_ids[Int(_attr(structure, row, :composite_child))],
            parent=composite_ids[Int(_attr(structure, row, :composite_parent))],
            mount_key=_attr(structure, row, :mount_key),
        )
        for row in _rows(structure, :CompositeContainment)
    ]; by=record -> record.id)
    actors = sort!([
        (
            id=actor_ids[row],
            local_id=String(_attr(structure, row, :actor_local_id)),
            composite=composite_ids[Int(_attr(structure, row, :actor_composite))],
            kind=haskey(process_actors, row) ? :process :
                 haskey(step_actors, row) ? :step : :unknown,
            law_type=_attr(structure, row, :law_type),
            law_version=_attr(structure, row, :law_version),
            parameters=_attr(structure, row, :law_parameters),
            capabilities=_attr(structure, row, :capability_payload),
            domain=_attr(structure, row, :actor_domain),
            continuation_version=_attr(structure, row, :continuation_version),
            schedule=haskey(process_actors, row) ? let process = process_actors[row]
                (
                    cadence=_attr(structure, process, :cadence_tick),
                    first_due=_attr(structure, process, :first_due_tick),
                    supports_partial=_attr(structure, process, :supports_partial),
                )
            end : nothing,
        )
        for row in _rows(structure, :Actor)
    ]; by=record -> record.id)
    ports = sort!([
        (
            id=port_ids[row],
            actor=actor_ids[Int(_attr(structure, row, :port_actor))],
            name=_attr(structure, row, :port_name),
            value_type=_attr(structure, row, :port_value_type),
            direction=_attr(structure, row, :port_direction),
            effect=_attr(structure, row, :port_effect),
            interval_behavior=_attr(structure, row, :port_interval_behavior),
            optional=_attr(structure, row, :port_optional),
            cardinality=_attr(structure, row, :port_cardinality),
            residency=_attr(structure, row, :port_residency),
            update_law=_attr(structure, row, :port_update_law),
        )
        for row in _rows(structure, :Port)
    ]; by=record -> record.id)
    bindings = sort!([
        (
            id=String(_attr(structure, row, :binding_id)),
            port=port_ids[Int(_attr(structure, row, :binding_port))],
            store=store_ids[Int(_attr(structure, row, :binding_store))],
            transfer=_attr(structure, row, :transfer_payload),
        )
        for row in _rows(structure, :Binding)
    ]; by=record -> record.id)
    dependencies = sort!([
        (
            id=String(_attr(structure, row, :dependency_id)),
            before=actor_ids[Int(_attr(structure,
                Int(_attr(structure, row, :dependency_before)), :step_actor))],
            after=actor_ids[Int(_attr(structure,
                Int(_attr(structure, row, :dependency_after)), :step_actor))],
        )
        for row in _rows(structure, :StepDependency)
    ]; by=record -> record.id)
    endpoint_ids = Dict(row => String(_attr(structure, row, :endpoint_id))
        for row in _rows(structure, :Endpoint))
    endpoints = sort!([
        (
            id=endpoint_ids[row],
            name=_attr(structure, row, :endpoint_name),
            role=_attr(structure, row, :endpoint_role),
            origin_store=String(_attr(structure, row, :endpoint_origin_store_id)),
            local_path=_attr(structure, row, :endpoint_local_path),
            schema=_attr(structure, row, :endpoint_schema_payload),
        )
        for row in _rows(structure, :Endpoint)
    ]; by=record -> record.id)
    boundary_maps = sort!([
        (
            id=String(_attr(structure, row, :boundary_map_id)),
            endpoint=endpoint_ids[Int(_attr(structure, row, :boundary_map_endpoint))],
            store=store_ids[Int(_attr(structure, row, :boundary_map_store))],
            composite=composite_ids[Int(_attr(structure, row, :boundary_map_composite))],
        )
        for row in _rows(structure, :BoundaryMap)
    ]; by=record -> record.id)
    junction_ids = Dict(row => String(_attr(structure, row, :junction_id))
        for row in _rows(structure, :Junction))
    junctions = sort!([
        (
            id=junction_ids[row],
            store=store_ids[Int(_attr(structure, row, :junction_store))],
            composite=composite_ids[Int(_attr(structure, row, :junction_composite))],
        )
        for row in _rows(structure, :Junction)
    ]; by=record -> record.id)
    junction_endpoints = sort!([
        (
            id=String(_attr(structure, row, :junction_endpoint_id)),
            junction=junction_ids[
                Int(_attr(structure, row, :junction_endpoint_junction))],
            endpoint=endpoint_ids[
                Int(_attr(structure, row, :junction_endpoint_endpoint))],
        )
        for row in _rows(structure, :JunctionEndpoint)
    ]; by=record -> record.id)

    (
        composites=tuple(composites...),
        stores=tuple(stores...),
        containments=tuple(containments...),
        composite_containments=tuple(composite_containments...),
        actors=tuple(actors...),
        ports=tuple(ports...),
        bindings=tuple(bindings...),
        dependencies=tuple(dependencies...),
        endpoints=tuple(endpoints...),
        boundary_maps=tuple(boundary_maps...),
        junctions=tuple(junctions...),
        junction_endpoints=tuple(junction_endpoints...),
    )
end

function structural_fingerprint(structure::ConcreteProcessBigraphACSet)
    canonical_fingerprint((
        :process_bigraph_acset,
        PROCESS_BIGRAPH_ACSET_VERSION,
        _semantic_records(structure),
    ))
end

structural_fingerprint(model::CanonicalModel) = model.fingerprint
canonical_structure(model::CanonicalModel) = deepcopy(model.structure)

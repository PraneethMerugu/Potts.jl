const STRUCTURAL_TRANSACTION_VERSION = "process-bigraph-structural-transaction-v1"

const _STRUCTURAL_LAYOUT = (
    Composite=(
        attrs=(:composite_id, :composite_definition_id, :scale_numerator,
            :scale_denominator, :scale_unit),
        homs=(),
        id=:composite_id,
    ),
    StoreNode=(
        attrs=(:store_id, :store_path, :store_local_path, :schema_kind,
            :schema_payload),
        homs=(:store_composite,),
        id=:store_id,
    ),
    StoreContainment=(
        attrs=(:containment_id,),
        homs=(:containment_child, :containment_parent),
        id=:containment_id,
    ),
    CompositeContainment=(
        attrs=(:composite_containment_id, :mount_key),
        homs=(:composite_child, :composite_parent),
        id=:composite_containment_id,
    ),
    Actor=(
        attrs=(:actor_id, :actor_local_id, :law_type, :law_version,
            :law_parameters, :capability_payload, :actor_domain,
            :continuation_version),
        homs=(:actor_composite,),
        id=:actor_id,
    ),
    Process=(
        attrs=(:cadence_tick, :first_due_tick, :supports_partial),
        homs=(:process_actor,),
        id=nothing,
    ),
    Step=(
        attrs=(),
        homs=(:step_actor,),
        id=nothing,
    ),
    Port=(
        attrs=(:port_id, :port_name, :port_value_type, :port_direction,
            :port_effect, :port_interval_behavior, :port_optional,
            :port_cardinality, :port_residency, :port_update_law),
        homs=(:port_actor,),
        id=:port_id,
    ),
    Binding=(
        attrs=(:binding_id, :transfer_payload),
        homs=(:binding_port, :binding_store),
        id=:binding_id,
    ),
    StepDependency=(
        attrs=(:dependency_id,),
        homs=(:dependency_before, :dependency_after),
        id=:dependency_id,
    ),
    Endpoint=(
        attrs=(:endpoint_id, :endpoint_name, :endpoint_role,
            :endpoint_origin_store_id, :endpoint_local_path,
            :endpoint_schema_payload),
        homs=(),
        id=:endpoint_id,
    ),
    BoundaryMap=(
        attrs=(:boundary_map_id,),
        homs=(:boundary_map_endpoint, :boundary_map_store,
            :boundary_map_composite),
        id=:boundary_map_id,
    ),
    Junction=(
        attrs=(:junction_id,),
        homs=(:junction_store, :junction_composite),
        id=:junction_id,
    ),
    JunctionEndpoint=(
        attrs=(:junction_endpoint_id,),
        homs=(:junction_endpoint_junction, :junction_endpoint_endpoint),
        id=:junction_endpoint_id,
    ),
)

const _STRUCTURAL_HOM_TARGET = Dict{Symbol,Symbol}(
    :store_composite => :Composite,
    :containment_child => :StoreNode,
    :containment_parent => :StoreNode,
    :composite_child => :Composite,
    :composite_parent => :Composite,
    :actor_composite => :Composite,
    :process_actor => :Actor,
    :step_actor => :Actor,
    :port_actor => :Actor,
    :binding_port => :Port,
    :binding_store => :StoreNode,
    :dependency_before => :Step,
    :dependency_after => :Step,
    :boundary_map_endpoint => :Endpoint,
    :boundary_map_store => :StoreNode,
    :boundary_map_composite => :Composite,
    :junction_store => :StoreNode,
    :junction_composite => :Composite,
    :junction_endpoint_junction => :Junction,
    :junction_endpoint_endpoint => :Endpoint,
)

struct StructuralIdentity
    kind::Symbol
    id::String
    generation::UInt64
    function StructuralIdentity(
        kind::Symbol,
        id::AbstractString,
        generation::Integer=0,
    )
        kind in keys(_STRUCTURAL_LAYOUT) ||
            _fail(:invalid_structural_identity_kind,
                "structural identity kind is not in the canonical ACSet";
                kind)
        isempty(id) &&
            _fail(:empty_structural_identity,
                "structural identity cannot be empty"; kind)
        generation >= 0 ||
            _fail(:invalid_structural_generation,
                "structural identity generation cannot be negative";
                kind, generation)
        generation <= typemax(UInt64) ||
            _fail(:structural_generation_overflow,
                "structural identity generation exceeds UInt64";
                kind, generation)
        new(kind, String(id), UInt64(generation))
    end
end

struct StructuralIdentityRecord
    identity::StructuralIdentity
    status::Symbol
    birth_epoch::UInt64
    retired_epoch::Union{Nothing,UInt64}
    function StructuralIdentityRecord(
        identity::StructuralIdentity,
        status::Symbol,
        birth_epoch::Integer,
        retired_epoch,
    )
        status in (:active, :retired) ||
            _fail(:invalid_structural_identity_status,
                "structural identity status must be active or retired";
                status)
        birth_epoch >= 0 ||
            _fail(:invalid_structural_birth_epoch,
                "structural birth epoch cannot be negative"; birth_epoch)
        if status === :active
            isnothing(retired_epoch) ||
                _fail(:active_identity_has_retirement,
                    "an active identity cannot have a retirement epoch";
                    identity=identity.id)
        else
            retired_epoch isa Integer && retired_epoch >= birth_epoch ||
                _fail(:invalid_structural_retirement_epoch,
                    "a retired identity requires a valid retirement epoch";
                    identity=identity.id)
        end
        new(identity, status, UInt64(birth_epoch),
            isnothing(retired_epoch) ? nothing : UInt64(retired_epoch))
    end
end

struct StructuralLineage
    child::StructuralIdentity
    parent::Union{Nothing,StructuralIdentity}
    birth_event::String
    birth_epoch::UInt64
end

struct StructuralCapacity
    composites::Int
    total_parts::Int
    function StructuralCapacity(;
        composites::Integer=typemax(Int),
        total_parts::Integer=typemax(Int),
    )
        composites > 0 ||
            _fail(:invalid_structural_capacity,
                "composite capacity must be positive"; composites)
        total_parts > 0 ||
            _fail(:invalid_structural_capacity,
                "total structural-part capacity must be positive";
                total_parts)
        composites <= typemax(Int) && total_parts <= typemax(Int) ||
            _fail(:structural_capacity_overflow,
                "structural capacity exceeds Int")
        new(Int(composites), Int(total_parts))
    end
end

struct CompositeDivisionPolicy
    state::Symbol
    relationships::Symbol
    schedule::Symbol
    bindings::Symbol
    continuation::Symbol
    function CompositeDivisionPolicy(;
        state::Symbol=:initialize,
        relationships::Symbol=:none,
        schedule::Symbol=:next_selection,
        bindings::Symbol=:none,
        continuation::Symbol=:reconstruct,
    )
        state in (:initialize,) ||
            _fail(:unsupported_division_policy,
                "orchestration-composite division requires initialized state";
                policy=:state, value=state)
        relationships in (:none,) ||
            _fail(:unsupported_division_policy,
                "orchestration-composite division cannot implicitly copy relationships";
                policy=:relationships, value=relationships)
        schedule in (:next_selection,) ||
            _fail(:unsupported_division_policy,
                "a daughter composite first runs at the next scheduler selection";
                policy=:schedule, value=schedule)
        bindings in (:none,) ||
            _fail(:unsupported_division_policy,
                "orchestration-composite division cannot implicitly copy bindings";
                policy=:bindings, value=bindings)
        continuation in (:reconstruct,) ||
            _fail(:unsupported_division_policy,
                "a daughter composite requires reconstructed continuation";
                policy=:continuation, value=continuation)
        new(state, relationships, schedule, bindings, continuation)
    end
end

struct DynamicStructuralEpoch
    contract_version::String
    ordinal::UInt64
    structure::ConcreteProcessBigraphACSet
    fingerprint::String
    identities::Tuple
    lineage::Tuple{Vararg{StructuralLineage}}
    capacity::StructuralCapacity
end

abstract type AbstractStructuralRequest end

struct AddCompositeRequest <: AbstractStructuralRequest
    request_id::String
    source_epoch::UInt64
    parent::StructuralIdentity
    definition_id::String
    mount_key::Symbol
    dependencies::Tuple{Vararg{String}}
    priority::Int
end

struct RemoveCompositeRequest <: AbstractStructuralRequest
    request_id::String
    source_epoch::UInt64
    target::StructuralIdentity
    owned_closure::Tuple{Vararg{StructuralIdentity}}
    dependencies::Tuple{Vararg{String}}
    priority::Int
end

struct DivideCompositeRequest <: AbstractStructuralRequest
    request_id::String
    source_epoch::UInt64
    target::StructuralIdentity
    daughter_definition_id::String
    daughter_mount_key::Symbol
    policies::CompositeDivisionPolicy
    dependencies::Tuple{Vararg{String}}
    priority::Int
end

struct MoveCompositeRequest <: AbstractStructuralRequest
    request_id::String
    source_epoch::UInt64
    target::StructuralIdentity
    new_parent::StructuralIdentity
    mount_key::Symbol
    dependencies::Tuple{Vararg{String}}
    priority::Int
end

struct RewireBindingRequest <: AbstractStructuralRequest
    request_id::String
    source_epoch::UInt64
    binding::StructuralIdentity
    new_store::StructuralIdentity
    dependencies::Tuple{Vararg{String}}
    priority::Int
end

function _request_fields(
    request_id::AbstractString,
    source_epoch::Integer,
    dependencies,
    priority::Integer,
)
    isempty(request_id) &&
        _fail(:empty_structural_request_identity,
            "structural request identity cannot be empty")
    source_epoch >= 0 ||
        _fail(:invalid_structural_source_epoch,
            "structural source epoch cannot be negative"; source_epoch)
    source_epoch <= typemax(UInt64) ||
        _fail(:structural_source_epoch_overflow,
            "structural source epoch exceeds UInt64"; source_epoch)
    priority >= typemin(Int) && priority <= typemax(Int) ||
        _fail(:structural_priority_overflow,
            "structural request priority exceeds Int"; priority)
    deps = tuple(sort!(unique!(String[String(value) for value in dependencies]))...)
    any(isempty, deps) &&
        _fail(:empty_structural_dependency,
            "structural dependency identity cannot be empty";
            request_id=String(request_id))
    String(request_id), UInt64(source_epoch), deps, Int(priority)
end

function AddCompositeRequest(
    request_id::AbstractString,
    source_epoch::Integer,
    parent::StructuralIdentity,
    definition_id::AbstractString,
    mount_key::Symbol;
    dependencies=(),
    priority::Integer=0,
)
    parent.kind === :Composite ||
        _fail(:invalid_add_parent,
            "add parent must be a Composite identity";
            kind=parent.kind)
    isempty(definition_id) &&
        _fail(:empty_composite_definition,
            "added composite definition identity cannot be empty")
    rid, epoch, deps, rank =
        _request_fields(request_id, source_epoch, dependencies, priority)
    AddCompositeRequest(rid, epoch, parent, String(definition_id), mount_key,
        deps, rank)
end

function RemoveCompositeRequest(
    request_id::AbstractString,
    source_epoch::Integer,
    target::StructuralIdentity;
    owned_closure=(target,),
    dependencies=(),
    priority::Integer=0,
)
    target.kind === :Composite ||
        _fail(:invalid_remove_target,
            "remove target must be a Composite identity";
            kind=target.kind)
    closure = tuple(sort!(unique!(StructuralIdentity[owned_closure...]);
        by=value -> (String(value.kind), value.id, value.generation))...)
    all(value -> value.kind === :Composite, closure) ||
        _fail(:invalid_owned_closure,
            "remove owned closure may contain only Composite identities")
    rid, epoch, deps, rank =
        _request_fields(request_id, source_epoch, dependencies, priority)
    RemoveCompositeRequest(rid, epoch, target, closure, deps, rank)
end

function DivideCompositeRequest(
    request_id::AbstractString,
    source_epoch::Integer,
    target::StructuralIdentity,
    daughter_definition_id::AbstractString,
    daughter_mount_key::Symbol;
    policies::CompositeDivisionPolicy=CompositeDivisionPolicy(),
    dependencies=(),
    priority::Integer=0,
)
    target.kind === :Composite ||
        _fail(:invalid_divide_target,
            "divide target must be a Composite identity";
            kind=target.kind)
    isempty(daughter_definition_id) &&
        _fail(:empty_composite_definition,
            "daughter definition identity cannot be empty")
    rid, epoch, deps, rank =
        _request_fields(request_id, source_epoch, dependencies, priority)
    DivideCompositeRequest(rid, epoch, target,
        String(daughter_definition_id), daughter_mount_key, policies,
        deps, rank)
end

function MoveCompositeRequest(
    request_id::AbstractString,
    source_epoch::Integer,
    target::StructuralIdentity,
    new_parent::StructuralIdentity,
    mount_key::Symbol;
    dependencies=(),
    priority::Integer=0,
)
    target.kind === :Composite && new_parent.kind === :Composite ||
        _fail(:invalid_move_identity,
            "move target and parent must be Composite identities";
            target_kind=target.kind, parent_kind=new_parent.kind)
    rid, epoch, deps, rank =
        _request_fields(request_id, source_epoch, dependencies, priority)
    MoveCompositeRequest(rid, epoch, target, new_parent, mount_key,
        deps, rank)
end

function RewireBindingRequest(
    request_id::AbstractString,
    source_epoch::Integer,
    binding::StructuralIdentity,
    new_store::StructuralIdentity;
    dependencies=(),
    priority::Integer=0,
)
    binding.kind === :Binding && new_store.kind === :StoreNode ||
        _fail(:invalid_rewire_identity,
            "rewire requires Binding and StoreNode identities";
            binding_kind=binding.kind, store_kind=new_store.kind)
    rid, epoch, deps, rank =
        _request_fields(request_id, source_epoch, dependencies, priority)
    RewireBindingRequest(rid, epoch, binding, new_store, deps, rank)
end

struct StructuralRequestDisposition
    request_id::String
    status::Symbol
    conflicting_with::Union{Nothing,String}
end

struct StagedStructuralTransaction
    contract_version::String
    source_ordinal::UInt64
    source_fingerprint::String
    candidate_structure::ConcreteProcessBigraphACSet
    candidate_fingerprint::String
    identities::Tuple
    lineage::Tuple{Vararg{StructuralLineage}}
    dispositions::Tuple{Vararg{StructuralRequestDisposition}}
    numeric_candidate::Any
end

struct StructuralEpochCheckpoint
    contract_version::String
    ordinal::UInt64
    structure::ConcreteProcessBigraphACSet
    epoch_fingerprint::String
    identities::Tuple
    lineage::Tuple{Vararg{StructuralLineage}}
    capacity::StructuralCapacity
    checksum::String
end

function _canonical(io::IO, identity::StructuralIdentity)
    write(io, "SI")
    _canonical(io, identity.kind)
    _canonical(io, identity.id)
    _canonical(io, identity.generation)
end

function _canonical(io::IO, record::StructuralIdentityRecord)
    write(io, "IR")
    _canonical(io, record.identity)
    _canonical(io, record.status)
    _canonical(io, record.birth_epoch)
    _canonical(io, record.retired_epoch)
end

function _canonical(io::IO, lineage::StructuralLineage)
    write(io, "LN")
    _canonical(io, lineage.child)
    _canonical(io, lineage.parent)
    _canonical(io, lineage.birth_event)
    _canonical(io, lineage.birth_epoch)
end

function _structural_identity_records(
    structure::ConcreteProcessBigraphACSet,
    ordinal::UInt64,
)
    records = StructuralIdentityRecord[]
    for (object, layout) in pairs(_STRUCTURAL_LAYOUT)
        isnothing(layout.id) && continue
        for row in _rows(structure, object)
            identity = StructuralIdentity(
                object, String(_attr(structure, row, layout.id)), 0)
            push!(records,
                StructuralIdentityRecord(identity, :active, ordinal, nothing))
        end
    end
    tuple(sort!(records; by=record ->
        (String(record.identity.kind), record.identity.id,
            record.identity.generation))...)
end

function _structural_epoch_fingerprint(
    ordinal::UInt64,
    structure::ConcreteProcessBigraphACSet,
    identities,
    lineage,
    capacity::StructuralCapacity,
)
    canonical_fingerprint((
        STRUCTURAL_TRANSACTION_VERSION,
        ordinal,
        structural_fingerprint(structure),
        identities,
        lineage,
        (capacity.composites, capacity.total_parts),
    ))
end

function _validate_structure_shape(structure::ConcreteProcessBigraphACSet)
    for (object, layout) in pairs(_STRUCTURAL_LAYOUT)
        if !isnothing(layout.id)
            ids = String[
                String(_attr(structure, row, layout.id))
                for row in _rows(structure, object)
            ]
            all(id -> !isempty(id), ids) ||
                _fail(:empty_structural_identity,
                    "canonical structure contains an empty identity";
                    object)
            length(ids) == length(unique(ids)) ||
                _fail(:duplicate_structural_identity,
                    "canonical structure contains duplicate identities";
                    object)
        end
        for row in _rows(structure, object), hom in layout.homs
            target = Int(_attr(structure, row, hom))
            target in _rows(structure, _STRUCTURAL_HOM_TARGET[hom]) ||
                _fail(:dangling_structural_reference,
                    "canonical structure contains a dangling reference";
                    object, row, hom, target)
        end
    end

    composites = _rows(structure, :Composite)
    isempty(composites) &&
        _fail(:missing_root_composite,
            "dynamic structure must contain a root composite")
    parents = Dict{Int,Int}()
    mount_keys = Set{Tuple{Int,Symbol}}()
    for row in _rows(structure, :CompositeContainment)
        child_row = Int(_attr(structure, row, :composite_child))
        parent_row = Int(_attr(structure, row, :composite_parent))
        haskey(parents, child_row) &&
            _fail(:multiple_composite_parents,
                "a composite cannot have more than one parent";
                child=String(_attr(structure, child_row, :composite_id)))
        child_row == parent_row &&
            _fail(:composite_cycle,
                "a composite cannot contain itself";
                child=String(_attr(structure, child_row, :composite_id)))
        parents[child_row] = parent_row
        key = (parent_row, Symbol(_attr(structure, row, :mount_key)))
        key in mount_keys &&
            _fail(:duplicate_mount_key,
                "a composite cannot contain duplicate mount keys";
                parent=String(_attr(structure, parent_row, :composite_id)),
                mount_key=last(key))
        push!(mount_keys, key)
    end
    roots = setdiff(Set(composites), Set(keys(parents)))
    length(roots) == 1 ||
        _fail(:invalid_composite_root_count,
            "dynamic structure must contain exactly one root composite";
            count=length(roots))
    for composite in composites
        seen = Set{Int}()
        current = composite
        while haskey(parents, current)
            current in seen &&
                _fail(:composite_cycle,
                    "composite containment must be acyclic";
                    composite=String(
                        _attr(structure, composite, :composite_id)))
            push!(seen, current)
            current = parents[current]
        end
    end
    true
end

function _validate_capacity(
    structure::ConcreteProcessBigraphACSet,
    capacity::StructuralCapacity,
)
    composite_count = ACSets.nparts(structure, :Composite)
    part_count = sum(ACSets.nparts(structure, object)
        for object in keys(_STRUCTURAL_LAYOUT))
    composite_count <= capacity.composites ||
        _fail(:structural_capacity_exceeded,
            "structural transaction exceeds composite capacity";
            required=composite_count, available=capacity.composites)
    part_count <= capacity.total_parts ||
        _fail(:structural_capacity_exceeded,
            "structural transaction exceeds total-part capacity";
            required=part_count, available=capacity.total_parts)
    true
end

function dynamic_structural_epoch(
    structure::ConcreteProcessBigraphACSet;
    ordinal::Integer=0,
    capacity::StructuralCapacity=StructuralCapacity(),
)
    ordinal >= 0 ||
        _fail(:invalid_structural_epoch,
            "structural epoch ordinal cannot be negative"; ordinal)
    ordinal <= typemax(UInt64) ||
        _fail(:structural_epoch_overflow,
            "structural epoch ordinal exceeds UInt64"; ordinal)
    frozen = deepcopy(structure)
    _validate_structure_shape(frozen)
    _validate_capacity(frozen, capacity)
    value = UInt64(ordinal)
    identities = _structural_identity_records(frozen, value)
    lineage = ()
    DynamicStructuralEpoch(
        STRUCTURAL_TRANSACTION_VERSION,
        value,
        frozen,
        _structural_epoch_fingerprint(
            value, frozen, identities, lineage, capacity),
        identities,
        lineage,
        capacity,
    )
end

dynamic_structural_epoch(model::CanonicalModel; kwargs...) =
    dynamic_structural_epoch(canonical_structure(model); kwargs...)

function structural_identity(
    epoch::DynamicStructuralEpoch,
    kind::Symbol,
    id::AbstractString,
)
    position = findfirst(record ->
        record.identity.kind === kind &&
        record.identity.id == id &&
        record.status === :active,
        epoch.identities)
    isnothing(position) &&
        _fail(:unknown_structural_identity,
            "active structural identity does not exist";
            kind, id=String(id))
    epoch.identities[position].identity
end

function _identity_record(records, identity::StructuralIdentity)
    position = findfirst(record ->
        record.identity.kind === identity.kind &&
        record.identity.id == identity.id &&
        record.identity.generation == identity.generation,
        records)
    isnothing(position) ? nothing : records[position]
end

function _require_active_identity(records, identity::StructuralIdentity)
    record = _identity_record(records, identity)
    isnothing(record) &&
        _fail(:unknown_structural_identity,
            "structural request references an unknown identity";
            kind=identity.kind, id=identity.id,
            generation=identity.generation)
    record.status === :active ||
        _fail(:retired_structural_identity,
            "structural request references a retired identity";
            kind=identity.kind, id=identity.id,
            generation=identity.generation)
    record
end

function _identity_row(
    structure::ConcreteProcessBigraphACSet,
    identity::StructuralIdentity,
)
    layout = getproperty(_STRUCTURAL_LAYOUT, identity.kind)
    isnothing(layout.id) &&
        _fail(:unaddressable_structural_kind,
            "structural kind has no semantic identity attribute";
            kind=identity.kind)
    matches = collect(ACSets.incident(structure, identity.id, layout.id))
    length(matches) == 1 ||
        _fail(:structural_identity_lookup_failed,
            "structural identity must resolve to exactly one ACSet row";
            kind=identity.kind, id=identity.id, count=length(matches))
    only(matches)
end

_request_id(request::AbstractStructuralRequest) = request.request_id
_request_dependencies(request::AbstractStructuralRequest) = request.dependencies
_request_priority(request::AbstractStructuralRequest) = request.priority

function _request_footprint(
    request::AddCompositeRequest,
    structure,
)
    (
        exclusive=Set{Any}([(:mount, request.parent.id, request.mount_key)]),
        references=Set{Any}([(:composite, request.parent.id)]),
    )
end

function _request_footprint(
    request::RemoveCompositeRequest,
    structure,
)
    composite_rows = Set(_identity_row(structure, identity)
        for identity in request.owned_closure)
    store_rows = Set(row for row in _rows(structure, :StoreNode)
        if Int(_attr(structure, row, :store_composite)) in composite_rows)
    actor_rows = Set(row for row in _rows(structure, :Actor)
        if Int(_attr(structure, row, :actor_composite)) in composite_rows)
    port_rows = Set(row for row in _rows(structure, :Port)
        if Int(_attr(structure, row, :port_actor)) in actor_rows)
    binding_rows = Set(row for row in _rows(structure, :Binding)
        if Int(_attr(structure, row, :binding_port)) in port_rows ||
           Int(_attr(structure, row, :binding_store)) in store_rows)
    exclusive = Set{Any}(
        (:composite, identity.id) for identity in request.owned_closure)
    union!(exclusive, Set{Any}(
        (:store, String(_attr(structure, row, :store_id)))
        for row in store_rows))
    union!(exclusive, Set{Any}(
        (:actor, String(_attr(structure, row, :actor_id)))
        for row in actor_rows))
    union!(exclusive, Set{Any}(
        (:port, String(_attr(structure, row, :port_id)))
        for row in port_rows))
    union!(exclusive, Set{Any}(
        (:binding, String(_attr(structure, row, :binding_id)))
        for row in binding_rows))
    (
        exclusive=exclusive,
        references=Set{Any}(),
    )
end

function _request_footprint(request::DivideCompositeRequest, structure)
    target_row = _identity_row(structure, request.target)
    _, parent_row = _composite_parent_row(structure, target_row)
    parent_id = String(_attr(structure, parent_row, :composite_id))
    (
        exclusive=Set{Any}([
            (:composite, request.target.id),
            (:mount, parent_id, request.daughter_mount_key),
        ]),
        references=Set{Any}([(:composite, parent_id)]),
    )
end

_request_footprint(request::MoveCompositeRequest, structure) = (
    exclusive=Set{Any}([
        (:composite, request.target.id),
        (:mount, request.new_parent.id, request.mount_key),
    ]),
    references=Set{Any}([(:composite, request.new_parent.id)]),
)

_request_footprint(request::RewireBindingRequest, structure) = (
    exclusive=Set{Any}([(:binding, request.binding.id)]),
    references=Set{Any}([(:store, request.new_store.id)]),
)

function _footprints_conflict(left, right)
    !isempty(intersect(left.exclusive, right.exclusive)) ||
        !isempty(intersect(left.exclusive, right.references)) ||
        !isempty(intersect(left.references, right.exclusive))
end

function _select_requests(requests, structure)
    ordered = sort!(collect(requests);
        by=request -> (-_request_priority(request), _request_id(request)))
    accepted = AbstractStructuralRequest[]
    dispositions = StructuralRequestDisposition[]
    footprints = Dict{String,Any}()
    for request in ordered
        footprint = _request_footprint(request, structure)
        conflicts = AbstractStructuralRequest[
            prior for prior in accepted
            if _footprints_conflict(
                footprint, footprints[prior.request_id])
        ]
        if isempty(conflicts)
            push!(accepted, request)
            footprints[request.request_id] = footprint
            push!(dispositions,
                StructuralRequestDisposition(request.request_id, :selected,
                    nothing))
            continue
        end
        winner = first(sort!(conflicts;
            by=value -> (-value.priority, value.request_id)))
        if request.priority == winner.priority
            _fail(:unresolved_structural_conflict,
                "equal-priority structural requests have overlapping writes";
                first=winner.request_id, second=request.request_id)
        end
        push!(dispositions,
            StructuralRequestDisposition(request.request_id,
                :rejected_by_priority, winner.request_id))
    end
    accepted_ids = Set(request.request_id for request in accepted)
    for request in accepted, dependency in request.dependencies
        dependency in accepted_ids ||
            _fail(:unavailable_structural_dependency,
                "selected request depends on an absent or rejected request";
                request=request.request_id, dependency)
    end
    accepted, dispositions
end

function _topological_requests(requests)
    by_id = Dict(request.request_id => request for request in requests)
    incoming = Dict(id => Set(request.dependencies)
        for (id, request) in by_id)
    result = AbstractStructuralRequest[]
    while !isempty(incoming)
        ready = sort!(String[id for (id, deps) in incoming if isempty(deps)])
        isempty(ready) &&
            _fail(:structural_dependency_cycle,
                "structural request dependencies contain a cycle";
                requests=tuple(sort!(collect(keys(incoming)))...))
        for id in ready
            push!(result, by_id[id])
            delete!(incoming, id)
            for deps in values(incoming)
                delete!(deps, id)
            end
        end
    end
    result
end

function _fresh_identity(
    records,
    kind::Symbol,
    source_fingerprint::AbstractString,
    request_id::AbstractString,
    role::Symbol,
)
    digest = canonical_fingerprint((
        :process_bigraph_structural_identity_v1,
        source_fingerprint,
        request_id,
        role,
        kind,
    ))
    id = string("dynamic:", lowercase(String(kind)), ":", digest)
    any(record -> record.identity.kind === kind &&
        record.identity.id == id, records) &&
        _fail(:structural_identity_collision,
            "deterministic structural identity collides with a prior identity";
            kind, id, request_id=String(request_id), role)
    StructuralIdentity(kind, id, 0)
end

function _append_identity(
    records,
    identity::StructuralIdentity,
    birth_epoch::UInt64,
)
    push!(records,
        StructuralIdentityRecord(identity, :active, birth_epoch, nothing))
end

function _retire_identity!(
    records,
    identity::StructuralIdentity,
    retirement_epoch::UInt64,
)
    position = findfirst(record ->
        record.identity.kind === identity.kind &&
        record.identity.id == identity.id &&
        record.status === :active,
        records)
    isnothing(position) &&
        _fail(:unknown_structural_identity,
            "cannot retire an unknown active structural identity";
            kind=identity.kind, id=identity.id)
    record = records[position]
    records[position] = StructuralIdentityRecord(
        record.identity, :retired, record.birth_epoch, retirement_epoch)
end

function _add_composite_reference!(
    structure,
    records,
    request_id,
    parent::StructuralIdentity,
    definition_id,
    mount_key,
    source_fingerprint,
    new_epoch,
)
    parent_row = _identity_row(structure, parent)
    composite = _fresh_identity(records, :Composite,
        source_fingerprint, request_id, :composite)
    containment = _fresh_identity(records, :CompositeContainment,
        source_fingerprint, request_id, :containment)
    child_row = ACSets.add_part!(structure, :Composite;
        composite_id=composite.id,
        composite_definition_id=String(definition_id),
        scale_numerator=_attr(structure, parent_row, :scale_numerator),
        scale_denominator=_attr(structure, parent_row, :scale_denominator),
        scale_unit=_attr(structure, parent_row, :scale_unit))
    ACSets.add_part!(structure, :CompositeContainment;
        composite_child=child_row,
        composite_parent=parent_row,
        composite_containment_id=containment.id,
        mount_key)
    _append_identity(records, composite, new_epoch)
    _append_identity(records, containment, new_epoch)
    composite
end

function _composite_parent_row(structure, child_row::Int)
    rows = collect(ACSets.incident(structure, child_row, :composite_child))
    length(rows) == 1 ||
        _fail(:invalid_division_or_move_target,
            "division and movement require a non-root composite";
            child=String(_attr(structure, child_row, :composite_id)),
            parent_count=length(rows))
    row = only(rows)
    row, Int(_attr(structure, row, :composite_parent))
end

function _composite_closure(structure, target_row::Int)
    children = Dict{Int,Vector{Int}}()
    for row in _rows(structure, :CompositeContainment)
        parent = Int(_attr(structure, row, :composite_parent))
        child_row = Int(_attr(structure, row, :composite_child))
        push!(get!(children, parent, Int[]), child_row)
    end
    closure = Set{Int}()
    stack = [target_row]
    while !isempty(stack)
        current = pop!(stack)
        current in closure && continue
        push!(closure, current)
        append!(stack, get(children, current, Int[]))
    end
    closure
end

function _remove_rows!(structure, object::Symbol, rows)
    isempty(rows) || ACSets.rem_parts!(structure, object, sort!(collect(rows)))
end

function _remove_composite_closure!(
    structure,
    records,
    request::RemoveCompositeRequest,
    retirement_epoch::UInt64,
)
    target_row = _identity_row(structure, request.target)
    actual_rows = _composite_closure(structure, target_row)
    actual_ids = Set(String(_attr(structure, row, :composite_id))
        for row in actual_rows)
    declared_ids = Set(identity.id for identity in request.owned_closure)
    actual_ids == declared_ids ||
        _fail(:owned_closure_mismatch,
            "remove request must declare the exact composite owned closure";
            target=request.target.id,
            expected=tuple(sort!(collect(actual_ids))...),
            actual=tuple(sort!(collect(declared_ids))...))

    store_rows = Set(row for row in _rows(structure, :StoreNode)
        if Int(_attr(structure, row, :store_composite)) in actual_rows)
    actor_rows = Set(row for row in _rows(structure, :Actor)
        if Int(_attr(structure, row, :actor_composite)) in actual_rows)
    process_rows = Set(row for row in _rows(structure, :Process)
        if Int(_attr(structure, row, :process_actor)) in actor_rows)
    step_rows = Set(row for row in _rows(structure, :Step)
        if Int(_attr(structure, row, :step_actor)) in actor_rows)
    port_rows = Set(row for row in _rows(structure, :Port)
        if Int(_attr(structure, row, :port_actor)) in actor_rows)
    binding_rows = Set(row for row in _rows(structure, :Binding)
        if Int(_attr(structure, row, :binding_port)) in port_rows ||
           Int(_attr(structure, row, :binding_store)) in store_rows)
    dependency_rows = Set(row for row in _rows(structure, :StepDependency)
        if Int(_attr(structure, row, :dependency_before)) in step_rows ||
           Int(_attr(structure, row, :dependency_after)) in step_rows)
    boundary_rows = Set(row for row in _rows(structure, :BoundaryMap)
        if Int(_attr(structure, row, :boundary_map_composite)) in actual_rows ||
           Int(_attr(structure, row, :boundary_map_store)) in store_rows)
    endpoint_rows = Set(Int(_attr(structure, row, :boundary_map_endpoint))
        for row in boundary_rows)
    junction_rows = Set(row for row in _rows(structure, :Junction)
        if Int(_attr(structure, row, :junction_composite)) in actual_rows ||
           Int(_attr(structure, row, :junction_store)) in store_rows)
    junction_endpoint_rows = Set(row
        for row in _rows(structure, :JunctionEndpoint)
        if Int(_attr(structure, row, :junction_endpoint_junction)) in
                junction_rows ||
           Int(_attr(structure, row, :junction_endpoint_endpoint)) in
                endpoint_rows)
    store_containment_rows = Set(row
        for row in _rows(structure, :StoreContainment)
        if Int(_attr(structure, row, :containment_child)) in store_rows ||
           Int(_attr(structure, row, :containment_parent)) in store_rows)
    composite_containment_rows = Set(row
        for row in _rows(structure, :CompositeContainment)
        if Int(_attr(structure, row, :composite_child)) in actual_rows ||
           Int(_attr(structure, row, :composite_parent)) in actual_rows)

    removals = (
        JunctionEndpoint=junction_endpoint_rows,
        BoundaryMap=boundary_rows,
        Junction=junction_rows,
        Endpoint=endpoint_rows,
        Binding=binding_rows,
        Port=port_rows,
        StepDependency=dependency_rows,
        Process=process_rows,
        Step=step_rows,
        Actor=actor_rows,
        StoreContainment=store_containment_rows,
        StoreNode=store_rows,
        CompositeContainment=composite_containment_rows,
        Composite=actual_rows,
    )
    for (object, rows) in pairs(removals)
        layout = getproperty(_STRUCTURAL_LAYOUT, object)
        if !isnothing(layout.id)
            for row in rows
                identity = StructuralIdentity(
                    object, String(_attr(structure, row, layout.id)), 0)
                _retire_identity!(records, identity, retirement_epoch)
            end
        end
    end
    for (object, rows) in pairs(removals)
        _remove_rows!(structure, object, rows)
    end
    nothing
end

function _apply_reference!(
    structure,
    records,
    lineage,
    request::AddCompositeRequest,
    source_fingerprint,
    new_epoch,
)
    _require_active_identity(records, request.parent)
    child_identity = _add_composite_reference!(
        structure, records, request.request_id, request.parent,
        request.definition_id, request.mount_key, source_fingerprint,
        new_epoch)
    push!(lineage, StructuralLineage(
        child_identity, nothing, request.request_id, new_epoch))
end

function _apply_reference!(
    structure,
    records,
    lineage,
    request::RemoveCompositeRequest,
    source_fingerprint,
    new_epoch,
)
    _require_active_identity(records, request.target)
    for identity in request.owned_closure
        _require_active_identity(records, identity)
    end
    _remove_composite_closure!(structure, records, request, new_epoch)
end

function _apply_reference!(
    structure,
    records,
    lineage,
    request::DivideCompositeRequest,
    source_fingerprint,
    new_epoch,
)
    _require_active_identity(records, request.target)
    target_row = _identity_row(structure, request.target)
    _, parent_row = _composite_parent_row(structure, target_row)
    parent_identity = StructuralIdentity(
        :Composite, String(_attr(structure, parent_row, :composite_id)), 0)
    daughter = _add_composite_reference!(
        structure, records, request.request_id, parent_identity,
        request.daughter_definition_id, request.daughter_mount_key,
        source_fingerprint, new_epoch)
    push!(lineage, StructuralLineage(
        daughter, request.target, request.request_id, new_epoch))
end

function _apply_reference!(
    structure,
    records,
    lineage,
    request::MoveCompositeRequest,
    source_fingerprint,
    new_epoch,
)
    _require_active_identity(records, request.target)
    _require_active_identity(records, request.new_parent)
    target_row = _identity_row(structure, request.target)
    parent_row = _identity_row(structure, request.new_parent)
    target_row == parent_row &&
        _fail(:composite_cycle,
            "a composite cannot move beneath itself";
            target=request.target.id)
    parent_row in _composite_closure(structure, target_row) &&
        _fail(:composite_cycle,
            "a composite cannot move beneath its descendant";
            target=request.target.id, parent=request.new_parent.id)
    containment_row, _ = _composite_parent_row(structure, target_row)
    ACSets.set_subpart!(
        structure, containment_row, :composite_parent, parent_row)
    ACSets.set_subpart!(
        structure, containment_row, :mount_key, request.mount_key)
end

function _apply_reference!(
    structure,
    records,
    lineage,
    request::RewireBindingRequest,
    source_fingerprint,
    new_epoch,
)
    _require_active_identity(records, request.binding)
    _require_active_identity(records, request.new_store)
    binding_row = _identity_row(structure, request.binding)
    store_row = _identity_row(structure, request.new_store)
    previous_store = Int(_attr(structure, binding_row, :binding_store))
    canonical_fingerprint(_attr(structure, previous_store, :schema_payload)) ==
        canonical_fingerprint(_attr(structure, store_row, :schema_payload)) ||
        _fail(:rewire_schema_mismatch,
            "rewire target must preserve the bound store schema";
            binding=request.binding.id, store=request.new_store.id)
    ACSets.set_subpart!(structure, binding_row, :binding_store, store_row)
end

function _dpo_replace(
    before::ConcreteProcessBigraphACSet,
    after::ConcreteProcessBigraphACSet,
)
    empty = ProcessBigraphACSet()
    category = Catlab.ACSetCategory(empty)
    rule = AlgebraicRewriting.Rule{:DPO}(
        Catlab.create[category](before),
        Catlab.create[category](after);
        cat=category,
        monic=true,
    )
    matched = Catlab.id[category](before)
    candidate = AlgebraicRewriting.rewrite_match(rule, matched; cat=category)
    structural_fingerprint(candidate) == structural_fingerprint(after) ||
        _fail(:algebraic_rewrite_differential,
            "DPO candidate differs from the independent structural reference";
            expected=structural_fingerprint(after),
            actual=structural_fingerprint(candidate))
    candidate
end

function stage_structural_transaction(
    epoch::DynamicStructuralEpoch,
    requests;
    numeric_candidate=nothing,
    inject_failure::Union{Nothing,Symbol}=nothing,
)
    inject_failure in (nothing, :selection, :reference, :rewrite,
            :validation) ||
        _fail(:invalid_structural_failure_stage,
            "unknown structural failure-injection stage";
            inject_failure)
    supplied = AbstractStructuralRequest[requests...]
    ids = String[request.request_id for request in supplied]
    length(ids) == length(unique(ids)) ||
        _fail(:duplicate_structural_request,
            "structural batch contains duplicate request identities")
    all(request -> request.source_epoch == epoch.ordinal, supplied) ||
        _fail(:stale_structural_epoch,
            "structural request source epoch is not current";
            expected=epoch.ordinal)
    for request in supplied, dependency in request.dependencies
        dependency in ids ||
            _fail(:unknown_structural_dependency,
                "structural request dependency is absent from the batch";
                request=request.request_id, dependency)
        dependency == request.request_id &&
            _fail(:structural_dependency_cycle,
                "structural request cannot depend on itself";
                request=request.request_id)
    end
    inject_failure === :selection &&
        _fail(:injected_structural_failure,
            "deterministic structural failure requested";
            stage=:selection)
    selected, dispositions = _select_requests(supplied, epoch.structure)
    ordered = _topological_requests(selected)

    structure = deepcopy(epoch.structure)
    records = collect(deepcopy(epoch.identities))
    lineage = StructuralLineage[deepcopy(epoch.lineage)...]
    new_epoch = Base.Checked.checked_add(epoch.ordinal, UInt64(1))
    for request in ordered
        reference = deepcopy(structure)
        inject_failure === :reference &&
            _fail(:injected_structural_failure,
                "deterministic structural failure requested";
                stage=:reference, request=request.request_id)
        _apply_reference!(reference, records, lineage, request,
            epoch.fingerprint, new_epoch)
        inject_failure === :rewrite &&
            _fail(:injected_structural_failure,
                "deterministic structural failure requested";
                stage=:rewrite, request=request.request_id)
        structure = _dpo_replace(structure, reference)
    end
    inject_failure === :validation &&
        _fail(:injected_structural_failure,
            "deterministic structural failure requested";
            stage=:validation)
    _validate_structure_shape(structure)
    _validate_capacity(structure, epoch.capacity)
    normalized_records = tuple(sort!(records; by=record ->
        (String(record.identity.kind), record.identity.id,
            record.identity.generation))...)
    normalized_lineage = tuple(sort!(lineage; by=record ->
        (record.birth_epoch, record.birth_event, record.child.id))...)
    candidate_fingerprint = _structural_epoch_fingerprint(
        new_epoch, structure, normalized_records, normalized_lineage,
        epoch.capacity)
    StagedStructuralTransaction(
        STRUCTURAL_TRANSACTION_VERSION,
        epoch.ordinal,
        epoch.fingerprint,
        structure,
        candidate_fingerprint,
        normalized_records,
        normalized_lineage,
        tuple(sort!(dispositions; by=value -> value.request_id)...),
        deepcopy(numeric_candidate),
    )
end

function publish_structural_transaction(
    epoch::DynamicStructuralEpoch,
    candidate::StagedStructuralTransaction;
    validate_numeric::Function=Returns(true),
    inject_failure::Bool=false,
)
    candidate.contract_version == STRUCTURAL_TRANSACTION_VERSION ||
        _fail(:structural_transaction_version_mismatch,
            "staged structural transaction uses an incompatible version";
            expected=STRUCTURAL_TRANSACTION_VERSION,
            actual=candidate.contract_version)
    candidate.source_ordinal == epoch.ordinal &&
        candidate.source_fingerprint == epoch.fingerprint ||
        _fail(:stale_structural_candidate,
            "staged structural candidate no longer matches the source epoch";
            expected_epoch=epoch.ordinal,
            candidate_epoch=candidate.source_ordinal)
    inject_failure &&
        _fail(:injected_structural_failure,
            "deterministic structural failure requested";
            stage=:publication)
    validate_numeric(candidate.numeric_candidate) === true ||
        _fail(:numeric_structural_validation_failed,
            "numeric candidate rejected the joint publication")
    new_ordinal = Base.Checked.checked_add(epoch.ordinal, UInt64(1))
    _validate_structure_shape(candidate.candidate_structure)
    _validate_capacity(candidate.candidate_structure, epoch.capacity)
    expected = _structural_epoch_fingerprint(
        new_ordinal,
        candidate.candidate_structure,
        candidate.identities,
        candidate.lineage,
        epoch.capacity,
    )
    expected == candidate.candidate_fingerprint ||
        _fail(:structural_candidate_fingerprint_mismatch,
            "staged structural candidate failed integrity validation";
            expected, actual=candidate.candidate_fingerprint)
    DynamicStructuralEpoch(
        STRUCTURAL_TRANSACTION_VERSION,
        new_ordinal,
        deepcopy(candidate.candidate_structure),
        candidate.candidate_fingerprint,
        deepcopy(candidate.identities),
        deepcopy(candidate.lineage),
        epoch.capacity,
    )
end

structural_structure(epoch::DynamicStructuralEpoch) = deepcopy(epoch.structure)
structural_fingerprint(epoch::DynamicStructuralEpoch) = epoch.fingerprint
structural_epoch(epoch::DynamicStructuralEpoch) = epoch.ordinal
structural_lineage(epoch::DynamicStructuralEpoch) = deepcopy(epoch.lineage)

function _structural_checkpoint_checksum(
    contract_version,
    ordinal,
    structure,
    epoch_fingerprint,
    identities,
    lineage,
    capacity,
)
    canonical_fingerprint((
        :process_bigraph_structural_checkpoint_v1,
        contract_version,
        ordinal,
        structural_fingerprint(structure),
        epoch_fingerprint,
        identities,
        lineage,
        (capacity.composites, capacity.total_parts),
    ))
end

function structural_checkpoint(epoch::DynamicStructuralEpoch)
    checksum = _structural_checkpoint_checksum(
        epoch.contract_version,
        epoch.ordinal,
        epoch.structure,
        epoch.fingerprint,
        epoch.identities,
        epoch.lineage,
        epoch.capacity,
    )
    StructuralEpochCheckpoint(
        epoch.contract_version,
        epoch.ordinal,
        deepcopy(epoch.structure),
        epoch.fingerprint,
        deepcopy(epoch.identities),
        deepcopy(epoch.lineage),
        epoch.capacity,
        checksum,
    )
end

function restore_structural_checkpoint(
    checkpoint::StructuralEpochCheckpoint,
)
    checkpoint.contract_version == STRUCTURAL_TRANSACTION_VERSION ||
        _fail(:structural_checkpoint_version_mismatch,
            "structural checkpoint uses an incompatible contract version";
            expected=STRUCTURAL_TRANSACTION_VERSION,
            actual=checkpoint.contract_version)
    expected_checksum = _structural_checkpoint_checksum(
        checkpoint.contract_version,
        checkpoint.ordinal,
        checkpoint.structure,
        checkpoint.epoch_fingerprint,
        checkpoint.identities,
        checkpoint.lineage,
        checkpoint.capacity,
    )
    expected_checksum == checkpoint.checksum ||
        _fail(:structural_checkpoint_checksum_mismatch,
            "structural checkpoint checksum does not match its contents";
            expected=expected_checksum, actual=checkpoint.checksum)
    _validate_structure_shape(checkpoint.structure)
    _validate_capacity(checkpoint.structure, checkpoint.capacity)
    expected_fingerprint = _structural_epoch_fingerprint(
        checkpoint.ordinal,
        checkpoint.structure,
        checkpoint.identities,
        checkpoint.lineage,
        checkpoint.capacity,
    )
    expected_fingerprint == checkpoint.epoch_fingerprint ||
        _fail(:structural_checkpoint_fingerprint_mismatch,
            "structural checkpoint epoch fingerprint is invalid";
            expected=expected_fingerprint,
            actual=checkpoint.epoch_fingerprint)
    DynamicStructuralEpoch(
        checkpoint.contract_version,
        checkpoint.ordinal,
        deepcopy(checkpoint.structure),
        checkpoint.epoch_fingerprint,
        deepcopy(checkpoint.identities),
        deepcopy(checkpoint.lineage),
        checkpoint.capacity,
    )
end

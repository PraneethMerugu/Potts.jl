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

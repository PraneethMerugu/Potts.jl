# Host-only conservative-energy domains and finite affected-anchor proofs.

struct EnergyDomainFact
    kind::Symbol
    resource::Any
    anchor_kind::Symbol
    anchor_name::Symbol
end

struct AffectedAnchorFact
    kind::Symbol
    locality::Symbol
    maximum::Int
end

_energy_anchor_kind(::SiteBinding) = :site
_energy_anchor_kind(::CellBinding) = :cell
_energy_anchor_kind(::ContactBinding) = :contact
_energy_anchor_kind(::RelationshipBinding) = :relationship

_energy_domain_kind(::Sites) = :sites
_energy_domain_kind(::Cells) = :cells
_energy_domain_kind(::Contacts) = :contacts
_energy_domain_kind(::Edges) = :edges

_energy_domain_resource(domain::Sites) = domain.domain
_energy_domain_resource(domain::Cells) = domain.kind
_energy_domain_resource(domain::Contacts) = domain.relation
_energy_domain_resource(domain::Edges) = domain.relationship

_record_arguments(record::QualifiedStatement) = first(record.normalized_payload)
_record_options(record::QualifiedStatement) = last(record.normalized_payload)

function _resource_local_id(resource)
    resource isa Symbol && return StatementID(resource)
    resource isa StatementID && return resource
    resource isa AbstractPottsStatement && return statement_id(resource)
    return nothing
end

function _resource_record(
        source::FrozenSourceGraph,
        owner::QualifiedStatement,
        kind::Symbol,
        resource,
    )
    local_id = _resource_local_id(resource)
    local_id === nothing && return nothing
    owner_path = owner.identity.path
    best = nothing
    best_depth = -1
    for candidate in source.records
        candidate.kind === kind || continue
        candidate.identity.local_id == local_id || continue
        candidate_path = candidate.identity.path
        length(candidate_path) <= length(owner_path) || continue
        owner_path[1:length(candidate_path)] == candidate_path || continue
        if length(candidate_path) > best_depth
            best = candidate
            best_depth = length(candidate_path)
        end
    end
    return best
end

function _same_domain_resource(left, right)
    isequal(left, right) && return true
    left_id = _resource_local_id(left)
    right_id = _resource_local_id(right)
    return left_id !== nothing && right_id !== nothing && left_id == right_id
end

function _energy_domain_fact(
        source::FrozenSourceGraph,
        record::QualifiedStatement,
    )
    payload = record.normalized_payload
    payload isa Tuple && length(payload) >= 1 ||
        throw(ArgumentError("Hamiltonian record has no normalized arguments"))
    arguments = first(payload)
    arguments isa NamedTuple &&
        keys(arguments) == (:domain, :anchor, :expression) ||
        throw(ArgumentError(
            "HamiltonianTerm arguments must be `(domain, anchor, expression)`"
        ))
    domain = arguments.domain
    anchor = arguments.anchor
    valid =
        domain isa Sites && anchor isa SiteBinding ||
        domain isa Cells && anchor isa CellBinding ||
        domain isa Contacts && anchor isa ContactBinding ||
        domain isa Edges && anchor isa RelationshipBinding
    valid || throw(ArgumentError(
        "Hamiltonian energy domain and symbolic anchor have incompatible kinds"
    ))
    if domain isa Contacts
        _same_domain_resource(domain.relation, anchor.relation) ||
            throw(ArgumentError(
                "contact energy domain and bound contact use different relations"
            ))
    elseif domain isa Edges
        _same_domain_resource(domain.relationship, anchor.relationship) ||
            throw(ArgumentError(
                "relationship energy domain and bound edge use different relationships"
            ))
    end
    return EnergyDomainFact(
        _energy_domain_kind(domain),
        _energy_domain_resource(domain),
        _energy_anchor_kind(anchor),
        anchor.name,
    )
end

function _hamiltonian_forbidden_symbol(expression)
    for variable in _collect_symbolics(expression)
        name = _try_symbolic_name(variable)
        name === nothing && continue
        text = String(name)
        startswith(text, "__potts_proposal__") &&
            return (:proposal_context, name)
        startswith(text, "__potts_draw__") &&
            return (:stochastic_draw, name)
    end
    return nothing
end

function _energy_anchor_reads(expression)
    result = Pair{Symbol, Symbol}[]
    for variable in _collect_symbolics(expression)
        name = _try_symbolic_name(variable)
        name === nothing && continue
        text = String(name)
        for (prefix, kind) in (
                "__potts_energy_site__" => :site,
                "__potts_energy_cell__" => :cell,
                "__potts_energy_contact__" => :contact,
                "__potts_relationship__" => :relationship,
            )
            startswith(text, prefix) || continue
            push!(result, kind => Symbol(text[(length(prefix) + 1):end]))
            break
        end
    end
    return Tuple(unique(result))
end

function _validate_energy_anchor_reads(arguments, domain::EnergyDomainFact)
    reads = _energy_anchor_reads(arguments.expression)
    all(read -> first(read) === domain.anchor_kind &&
                last(read) === domain.anchor_name, reads) ||
        throw(ArgumentError(
            "Hamiltonian expression reads an energy anchor other than its bound anchor"
        ))
    return reads
end

function _checked_anchor_bound(value::Integer, description)
    0 <= value <= typemax(Int) || throw(ArgumentError(
        "$description exceeds the supported affected-anchor bound"
    ))
    return Int(value)
end

function _contact_relation_bound(
        source::FrozenSourceGraph,
        owner::QualifiedStatement,
        resource,
    )
    relation = _resource_record(source, owner, :SpatialRelation, resource)
    relation === nothing && throw(ArgumentError(
        "contact energy requires a declared finite SpatialRelation"
    ))
    options = _record_options(relation)
    neighborhood = haskey(options, :neighborhood) ? options.neighborhood : nothing
    neighborhood isa Union{VonNeumann, Moore} || throw(ArgumentError(
        "contact SpatialRelation must use a closed VonNeumann or Moore neighborhood"
    ))
    domain_resource = haskey(options, :domain) ? options.domain : :lattice
    lattice = _resource_record(source, owner, :LatticeDomain, domain_resource)
    lattice === nothing && throw(ArgumentError(
        "contact SpatialRelation must resolve to a finite LatticeDomain"
    ))
    lattice_options = _record_options(lattice)
    shape = get(lattice_options, :shape, nothing)
    shape isa Tuple && !isempty(shape) || throw(ArgumentError(
        "contact LatticeDomain must have a concrete nonempty shape"
    ))
    dimensions = length(shape)
    radius = neighborhood.radius
    maximum = if neighborhood isa Moore
        big(2 * radius + 1)^dimensions - 1
    else
        sum(
            big(2)^axes * binomial(big(dimensions), axes) *
            binomial(big(radius), axes)
            for axes in 1:min(dimensions, radius)
        )
    end
    return _checked_anchor_bound(maximum, "contact neighborhood")
end

function _relationship_incident_bound(
        source::FrozenSourceGraph,
        owner::QualifiedStatement,
        resource,
    )
    relationship = _resource_record(source, owner, :RelationshipState, resource)
    relationship === nothing && throw(ArgumentError(
        "relationship energy requires a declared RelationshipState"
    ))
    options = _record_options(relationship)
    maximum_degree = get(options, :maximum_degree, nothing)
    maximum_degree isa Integer && maximum_degree >= 0 || throw(ArgumentError(
        "relationship energy requires a concrete nonnegative maximum_degree"
    ))
    return _checked_anchor_bound(
        big(2) * maximum_degree,
        "relationship incident-edge set",
    )
end

function _affected_anchor_fact(
        source::FrozenSourceGraph,
        record::QualifiedStatement,
        domain::EnergyDomainFact,
        locality::Symbol,
    )
    arguments = _record_arguments(record)
    forbidden = _hamiltonian_forbidden_symbol(arguments.expression)
    forbidden === nothing || throw(ArgumentError(
        "Hamiltonian energy expressions cannot depend on $(first(forbidden)) " *
        "$(last(forbidden))"
    ))
    record.effect isa PureRead && isempty(record.writes) ||
        throw(ArgumentError("Hamiltonians must be immutable pure reads"))
    isempty(record.random_operations) ||
        throw(ArgumentError("Hamiltonians cannot contain random draws"))
    _validate_energy_anchor_reads(arguments, domain)

    if domain.kind === :sites && locality in (:scalar, :site_local)
        return AffectedAnchorFact(:target_site, locality, 1)
    elseif domain.kind === :cells && locality in (:scalar, :owner_local)
        return AffectedAnchorFact(:source_and_target_cells, locality, 2)
    elseif domain.kind === :contacts && locality in (:scalar, :contact_local)
        maximum = _contact_relation_bound(source, record, domain.resource)
        return AffectedAnchorFact(:incident_contacts, locality, maximum)
    elseif domain.kind === :edges &&
            locality in (:scalar, :owner_local, :bounded_relationship)
        maximum = _relationship_incident_bound(source, record, domain.resource)
        return AffectedAnchorFact(:incident_relationships, locality, maximum)
    end
    throw(ArgumentError(
        "Hamiltonian locality `$locality` has no compiler-proven finite affected-anchor rule " *
        "for energy domain `$(domain.kind)`"
    ))
end

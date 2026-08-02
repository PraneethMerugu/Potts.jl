# Compositional analysis of the closed host footprint algebra.

function _host_lattice_shape(source::FrozenSourceGraph)
    domains = filter(record -> record.kind === :LatticeDomain, source.records)
    length(domains) == 1 || throw(ArgumentError(
        "footprint analysis requires exactly one lattice domain"
    ))
    shape = get(_record_options(only(domains)), :shape, nothing)
    shape isa Tuple{Vararg{Int}} && !isempty(shape) || throw(ArgumentError(
        "footprint analysis requires a concrete nonempty lattice shape"
    ))
    return shape
end

function _host_neighborhood_offsets(neighborhood::VonNeumann, dimensions::Int)
    offsets = Tuple[]
    ranges = ntuple(_ -> (-neighborhood.radius):neighborhood.radius, dimensions)
    for offset in Iterators.product(ranges...)
        sum(abs, offset) <= neighborhood.radius || continue
        all(iszero, offset) && continue
        push!(offsets, Tuple(Int.(offset)))
    end
    return Tuple(sort!(unique!(offsets)))
end

function _host_neighborhood_offsets(neighborhood::Moore, dimensions::Int)
    ranges = ntuple(_ -> (-neighborhood.radius):neighborhood.radius, dimensions)
    offsets = Tuple(
        Tuple(Int.(offset))
        for offset in Iterators.product(ranges...)
        if !all(iszero, offset)
    )
    return Tuple(sort!(unique!(collect(offsets))))
end

function _prefixed_symbol(value, prefix::String)
    name = _try_symbolic_name(value)
    name === nothing && return nothing
    text = String(name)
    startswith(text, prefix) || return nothing
    return Symbol(text[(lastindex(prefix) + 1):end])
end

_zero_offsets(dimensions::Int) = (ntuple(_ -> 0, dimensions),)

function _footprint_sort_key(footprint::AbstractAnalyzedFootprint)
    if footprint isa EmptyAnalyzedFootprint
        return "0:empty"
    elseif footprint isa SpatialFootprintFact
        return "1:spatial:" * repr(footprint.anchor) * ":" * repr(footprint.offsets)
    elseif footprint isa SpatialRelationFootprintFact
        return "2:relation:" * repr(footprint.identity) * ":" * repr(footprint.offsets)
    elseif footprint isa OwnerFootprintFact
        return "3:owner:" * String(footprint.anchor)
    elseif footprint isa ContactFootprintFact
        return "4:contact:" * String(footprint.anchor)
    elseif footprint isa RelationshipReferenceFootprintFact
        return "5:relationship-reference:" * repr(footprint.identity)
    elseif footprint isa IncidentRelationshipFootprintFact
        return "6:incident-relationship:" * repr(footprint.identity)
    elseif footprint isa FootprintMinkowskiFact
        return "7:minkowski:" * _footprint_sort_key(footprint.left) * ":" *
               _footprint_sort_key(footprint.right)
    elseif footprint isa FootprintUnionFact
        return "8:union:" * join(_footprint_sort_key.(footprint.footprints), "|")
    end
    throw(ArgumentError("unknown analyzed footprint $(typeof(footprint))"))
end

_footprint_members(::EmptyAnalyzedFootprint) = ()
_footprint_members(footprint::FootprintUnionFact) = footprint.footprints
_footprint_members(footprint::AbstractAnalyzedFootprint) = (footprint,)

function _footprint_union(footprints::Tuple)
    members = AbstractAnalyzedFootprint[]
    for footprint in footprints
        footprint isa AbstractAnalyzedFootprint || throw(ArgumentError(
            "footprint union members must be analyzed footprint facts"
        ))
        append!(members, _footprint_members(footprint))
    end
    isempty(members) && return EmptyAnalyzedFootprint()
    unique_by_key = Dict{String, AbstractAnalyzedFootprint}()
    for member in members
        unique_by_key[_footprint_sort_key(member)] = member
    end
    ordered = sort!(collect(values(unique_by_key)); by = _footprint_sort_key)
    length(ordered) == 1 && return only(ordered)
    return FootprintUnionFact(Tuple(ordered))
end

_footprint_union(footprints...) = _footprint_union(Tuple(footprints))

function _collect_footprints(footprint, ::Type{T}) where {T}
    result = T[]
    function visit(value)
        value isa T && push!(result, value)
        if value isa FootprintUnionFact
            foreach(visit, value.footprints)
        elseif value isa FootprintMinkowskiFact
            visit(value.left)
            visit(value.right)
        end
        return nothing
    end
    visit(footprint)
    return result
end

function _without_operand_references(footprint)
    members = filter(
        member -> !(member isa Union{
            SpatialRelationFootprintFact,
            RelationshipReferenceFootprintFact,
        }),
        _footprint_members(footprint),
    )
    return _footprint_union(Tuple(members))
end

function _record_relationship_candidates(source, record)
    candidates = QualifiedStatement[]
    function consider(value)
        resolved = _resource_record(source, record, :RelationshipState, value)
        resolved === nothing || push!(candidates, resolved)
        if value isa NamedTuple
            foreach(consider, values(value))
        elseif value isa Tuple || value isa AbstractArray
            foreach(consider, value)
        elseif value isa Pair
            consider(first(value)); consider(last(value))
        end
        return nothing
    end
    consider(record.resources)
    unique!(candidate -> candidate.identity, candidates)
    return candidates
end

function _relationship_reference_fact(source, record, value; bound = false)
    requested = if bound
        arguments = _record_arguments(record)
        domain = arguments isa NamedTuple && haskey(arguments, :domain) ?
            arguments.domain : nothing
        domain isa Edges || throw(ArgumentError(
            "relationship anchor footprint requires a bounded edge domain"
        ))
        domain.relationship
    else
        _prefixed_symbol(value, "__potts_relationship_set__")
    end
    relationship = requested === nothing ? nothing :
        _resource_record(source, record, :RelationshipState, requested)
    if relationship === nothing
        candidates = _record_relationship_candidates(source, record)
        length(candidates) == 1 || throw(ArgumentError(
            "relationship footprint must resolve exactly one declared store"
        ))
        relationship = only(candidates)
    end
    degree = get(_record_options(relationship), :maximum_degree, nothing)
    degree === nothing && return RelationshipReferenceFootprintFact(
        relationship.identity, Int32(-1)
    )
    degree isa Integer && 0 <= degree <= typemax(Int32) || throw(ArgumentError(
        "relationship footprint maximum_degree is outside Int32 bounds"
    ))
    return RelationshipReferenceFootprintFact(
        relationship.identity, Int32(degree)
    )
end

function _leaf_footprint(source, node, record, dimensions)
    kind = node.payload_kind
    if kind === :site_anchor
        name = something(
            _prefixed_symbol(node.payload, "__potts_energy_site__"),
            :site,
        )
        return SpatialFootprintFact(
            BoundSiteAnchor(name), _zero_offsets(dimensions)
        )
    elseif kind === :cell_anchor
        name = something(
            _prefixed_symbol(node.payload, "__potts_energy_cell__"),
            :cell,
        )
        return OwnerFootprintFact(name)
    elseif kind === :contact_anchor
        name = something(
            _prefixed_symbol(node.payload, "__potts_energy_contact__"),
            :contact,
        )
        return ContactFootprintFact(name)
    elseif kind === :relationship_context
        return _relationship_reference_fact(
            source, record, node.payload; bound = true
        )
    elseif kind === :relationship_set
        return _relationship_reference_fact(source, record, node.payload)
    elseif kind === :spatial_relation
        requested = _prefixed_symbol(
            node.payload, "__potts_spatial_relation__"
        )
        requested === nothing && throw(ArgumentError(
            "spatial-relation footprint token has no qualified identity"
        ))
        relation = _resource_record(
            source, record, :SpatialRelation, requested
        )
        relation === nothing && throw(ArgumentError(
            "spatial footprint relation `$requested` is undeclared"
        ))
        neighborhood = get(_record_options(relation), :neighborhood, nothing)
        neighborhood isa Union{VonNeumann, Moore} || throw(ArgumentError(
            "spatial footprint relations require a closed finite neighborhood"
        ))
        return SpatialRelationFootprintFact(
            relation.identity,
            _host_neighborhood_offsets(neighborhood, dimensions),
        )
    end
    return EmptyAnalyzedFootprint()
end

function _spatial_anchor_fact(anchor, dimensions)
    return SpatialFootprintFact(anchor, _zero_offsets(dimensions))
end

function _neighborhood_anchors(
        ::OperandNeighborhoodAnchors, operands, dimensions
    )
    anchors = SpatialFootprintFact[]
    for operand in operands
        append!(anchors, _collect_footprints(operand, SpatialFootprintFact))
    end
    isempty(anchors) && throw(ArgumentError(
        "neighborhood operation requires an explicit spatial anchor operand"
    ))
    return anchors
end

_neighborhood_anchors(::ProposalTargetNeighborhoodAnchor, operands, dimensions) =
    [_spatial_anchor_fact(ProposalTargetAnchor(), dimensions)]
_neighborhood_anchors(
    ::ProposalSourceTargetNeighborhoodAnchor, operands, dimensions
) = [
    _spatial_anchor_fact(ProposalSourceAnchor(), dimensions),
    _spatial_anchor_fact(ProposalTargetAnchor(), dimensions),
]
_neighborhood_anchors(::IterationNeighborhoodAnchor, operands, dimensions) =
    [_spatial_anchor_fact(IterationSiteAnchor(), dimensions)]

function _apply_footprint_rule(
        ::InheritFootprintRule, operands, dimensions
    )
    return _footprint_union(operands)
end

function _apply_footprint_rule(
        ::ProposalSourceFootprintRule, operands, dimensions
    )
    return _footprint_union(
        _footprint_union(operands),
        _spatial_anchor_fact(ProposalSourceAnchor(), dimensions),
    )
end

function _apply_footprint_rule(
        ::ProposalTargetFootprintRule, operands, dimensions
    )
    return _footprint_union(
        _footprint_union(operands),
        _spatial_anchor_fact(ProposalTargetAnchor(), dimensions),
    )
end

function _apply_footprint_rule(
        ::ProposalSourceTargetFootprintRule, operands, dimensions
    )
    return _footprint_union(
        _footprint_union(operands),
        _spatial_anchor_fact(ProposalSourceAnchor(), dimensions),
        _spatial_anchor_fact(ProposalTargetAnchor(), dimensions),
    )
end

function _apply_footprint_rule(
        ::IterationSiteFootprintRule, operands, dimensions
    )
    return _footprint_union(
        _footprint_union(operands),
        _spatial_anchor_fact(IterationSiteAnchor(), dimensions),
    )
end

function _apply_footprint_rule(::OwnerFootprintRule, operands, dimensions)
    inherited = _footprint_union(operands)
    isempty(_collect_footprints(inherited, OwnerFootprintFact)) &&
        (inherited = _footprint_union(inherited, OwnerFootprintFact(:owner)))
    return inherited
end

function _apply_footprint_rule(::ContactFootprintRule, operands, dimensions)
    inherited = _footprint_union(operands)
    isempty(_collect_footprints(inherited, ContactFootprintFact)) &&
        (inherited = _footprint_union(inherited, ContactFootprintFact(:contact)))
    return inherited
end

function _apply_footprint_rule(
        ::IncidentRelationshipFootprintRule, operands, dimensions
    )
    inherited = _footprint_union(operands)
    references = _collect_footprints(
        inherited, RelationshipReferenceFootprintFact
    )
    isempty(references) && throw(ArgumentError(
        "incident-relationship operation requires a relationship operand"
    ))
    incidents = Tuple(
        IncidentRelationshipFootprintFact(
            reference.identity, reference.maximum_degree
        ) for reference in references
    )
    return _footprint_union(_without_operand_references(inherited), incidents...)
end

function _apply_footprint_rule(
        rule::NeighborhoodFootprintRule, operands, dimensions
    )
    inherited = _footprint_union(operands)
    relations = _collect_footprints(
        inherited, SpatialRelationFootprintFact
    )
    isempty(relations) && throw(ArgumentError(
        "neighborhood operation requires a finite spatial-relation operand"
    ))
    anchors = _neighborhood_anchors(rule.anchors, operands, dimensions)
    composed = Tuple(
        FootprintMinkowskiFact(anchor, relation)
        for anchor in anchors for relation in relations
    )
    return _footprint_union(_without_operand_references(inherited), composed...)
end

function _analyzed_footprint(
        source, node, record, operand_footprints, dimensions
    )
    node.transfer === nothing &&
        return _leaf_footprint(source, node, record, dimensions)
    rule = node.transfer.footprint_rule
    rule isa AbstractFootprintTransferRule || throw(ArgumentError(
        "operation footprint transfer is not a closed rule"
    ))
    return _apply_footprint_rule(rule, Tuple(operand_footprints), dimensions)
end

function _footprint_has_unresolved_reference(footprint)
    return any(
        member -> member isa Union{
            SpatialRelationFootprintFact,
            RelationshipReferenceFootprintFact,
        },
        _footprint_members(footprint),
    )
end

function _footprint_has_unbounded_relationship(footprint)
    return any(
        fact -> fact.maximum_degree < 0,
        _collect_footprints(footprint, RelationshipReferenceFootprintFact),
    ) || any(
        fact -> fact.maximum_degree < 0,
        _collect_footprints(footprint, IncidentRelationshipFootprintFact),
    )
end

function _footprint_locality(footprint)
    footprint isa EmptyAnalyzedFootprint && return :scalar
    !isempty(_collect_footprints(
        footprint, IncidentRelationshipFootprintFact
    )) && return :bounded_relationship
    !isempty(_collect_footprints(footprint, FootprintMinkowskiFact)) &&
        return :finite_spatial
    spatial = _collect_footprints(footprint, SpatialFootprintFact)
    any(item -> item.anchor isa Union{
        ProposalSourceAnchor, ProposalTargetAnchor,
    }, spatial) && return :proposal_context
    !isempty(_collect_footprints(footprint, OwnerFootprintFact)) &&
        return :owner_local
    !isempty(_collect_footprints(footprint, ContactFootprintFact)) &&
        return :contact_local
    !isempty(spatial) && return :site_local
    return :scalar
end

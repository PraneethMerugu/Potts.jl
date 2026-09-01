# Closed host-side footprint transfer rules and analyzed footprint facts.

"""Supertype of domain-neutral bounded-footprint transfer rules."""
abstract type AbstractFootprintTransferRule end

"""An operation adds no access beyond the union of its operand facts."""
struct InheritFootprintRule <: AbstractFootprintTransferRule end

"""Footprint at the proposal source site."""
struct ProposalSourceFootprintRule <: AbstractFootprintTransferRule end
"""Footprint at the proposal destination site."""
struct ProposalTargetFootprintRule <: AbstractFootprintTransferRule end
"""Union of proposal source and destination footprints."""
struct ProposalSourceTargetFootprintRule <: AbstractFootprintTransferRule end
"""Footprint at the current bounded iteration site."""
struct IterationSiteFootprintRule <: AbstractFootprintTransferRule end
"""Footprint of state owned by a finite-cell identity."""
struct OwnerFootprintRule <: AbstractFootprintTransferRule end
"""Footprint of the current canonical contact."""
struct ContactFootprintRule <: AbstractFootprintTransferRule end
"""Footprint of bounded relationships incident to an endpoint."""
struct IncidentRelationshipFootprintRule <: AbstractFootprintTransferRule end

"""Supertype of rules selecting anchors for finite neighborhoods."""
abstract type AbstractNeighborhoodAnchorRule end
"""Use spatial anchors inherited from operation operands."""
struct OperandNeighborhoodAnchors <: AbstractNeighborhoodAnchorRule end
"""Use the proposal destination as a neighborhood anchor."""
struct ProposalTargetNeighborhoodAnchor <: AbstractNeighborhoodAnchorRule end
"""Use proposal source and destination as neighborhood anchors."""
struct ProposalSourceTargetNeighborhoodAnchor <: AbstractNeighborhoodAnchorRule end
"""Use the current iteration site as a neighborhood anchor."""
struct IterationNeighborhoodAnchor <: AbstractNeighborhoodAnchorRule end

"""Compose spatial anchors with every finite relation operand by Minkowski sum."""
struct NeighborhoodFootprintRule{A <: AbstractNeighborhoodAnchorRule} <:
       AbstractFootprintTransferRule
    anchors::A
end

abstract type AbstractAnalyzedFootprint end
struct EmptyAnalyzedFootprint <: AbstractAnalyzedFootprint end

abstract type AbstractAnalyzedSpatialAnchor end
struct ProposalSourceAnchor <: AbstractAnalyzedSpatialAnchor end
struct ProposalTargetAnchor <: AbstractAnalyzedSpatialAnchor end
struct IterationSiteAnchor <: AbstractAnalyzedSpatialAnchor end
struct BoundSiteAnchor <: AbstractAnalyzedSpatialAnchor
    name::Symbol
end

struct SpatialFootprintFact{A <: AbstractAnalyzedSpatialAnchor, O <: Tuple} <:
       AbstractAnalyzedFootprint
    anchor::A
    offsets::O
end

"""A named finite relation is an operand fact until a neighborhood rule consumes it."""
struct SpatialRelationFootprintFact{O <: Tuple} <: AbstractAnalyzedFootprint
    identity::QualifiedStatementID
    offsets::O
end

struct OwnerFootprintFact <: AbstractAnalyzedFootprint
    anchor::Symbol
end

struct ContactFootprintFact <: AbstractAnalyzedFootprint
    anchor::Symbol
end

"""A relationship token is an operand fact until an incident rule consumes it."""
struct RelationshipReferenceFootprintFact <: AbstractAnalyzedFootprint
    identity::QualifiedStatementID
    maximum_degree::Int32
end

struct IncidentRelationshipFootprintFact <: AbstractAnalyzedFootprint
    identity::QualifiedStatementID
    maximum_degree::Int32
end

struct FootprintUnionFact{F <: Tuple} <: AbstractAnalyzedFootprint
    footprints::F
end

struct FootprintMinkowskiFact{
        L <: AbstractAnalyzedFootprint,
        R <: AbstractAnalyzedFootprint,
    } <: AbstractAnalyzedFootprint
    left::L
    right::R
end

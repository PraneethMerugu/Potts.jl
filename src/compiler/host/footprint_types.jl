# Closed host-side footprint transfer rules and analyzed footprint facts.

abstract type AbstractFootprintTransferRule end

"""An operation adds no access beyond the union of its operand facts."""
struct InheritFootprintRule <: AbstractFootprintTransferRule end

struct ProposalSourceFootprintRule <: AbstractFootprintTransferRule end
struct ProposalTargetFootprintRule <: AbstractFootprintTransferRule end
struct ProposalSourceTargetFootprintRule <: AbstractFootprintTransferRule end
struct IterationSiteFootprintRule <: AbstractFootprintTransferRule end
struct OwnerFootprintRule <: AbstractFootprintTransferRule end
struct ContactFootprintRule <: AbstractFootprintTransferRule end
struct IncidentRelationshipFootprintRule <: AbstractFootprintTransferRule end

abstract type AbstractNeighborhoodAnchorRule end
struct OperandNeighborhoodAnchors <: AbstractNeighborhoodAnchorRule end
struct ProposalTargetNeighborhoodAnchor <: AbstractNeighborhoodAnchorRule end
struct ProposalSourceTargetNeighborhoodAnchor <: AbstractNeighborhoodAnchorRule end
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

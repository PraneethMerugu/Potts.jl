const MERKS_LOCAL_CONNECTIVITY_VERSION =
    "merks-local-connectivity-2006-v1"

const _MERKS_CLOCKWISE_OFFSETS = (
    (-1, -1),
    (0, -1),
    (1, -1),
    (1, 0),
    (1, 1),
    (0, 1),
    (-1, 1),
    (-1, 0),
)

"""Eight-site Moore relation used by the Merks et al. 2006 assembly."""
merks_moore_relation(role::AbstractSpatialRole) =
    static_relation(role, _MERKS_CLOCKWISE_OFFSETS; symmetric=true)

"""
Paper-specific local connectivity approximation from Merks et al. (2006).

The source assigns a penalty greater than 2000 to locally disconnecting copies.
The reference assembly profiles that effectively prohibitive penalty as a hard
rejection. This is intentionally distinct from `PreserveConnectedCells`, which
performs an exact global traversal.
"""
struct MerksLocalConnectivityConstraint{
        R<:StaticCartesianRelation{<:SpatialQueryRole},
        O<:SVector{8,UInt16}} <: AbstractHardConstraint
    relation::R
    clockwise_directions::O
end

function MerksLocalConnectivityConstraint(
    relation::StaticCartesianRelation{<:SpatialQueryRole},
)
    direction_count(relation) == 8 ||
        throw(ArgumentError(
            "Merks local connectivity requires the eight-site Moore relation"))
    directions = SVector{8,UInt16}(ntuple(8) do position
        direction = findfirst(
            isequal(SVector{2,Int32}(_MERKS_CLOCKWISE_OFFSETS[position])),
            relation.offsets,
        )
        isnothing(direction) &&
            throw(ArgumentError(
                "Merks local connectivity relation omits a Moore neighbor"))
        UInt16(direction)
    end)
    MerksLocalConnectivityConstraint(relation, directions)
end

MerksLocalConnectivityConstraint() =
    MerksLocalConnectivityConstraint(
        merks_moore_relation(SpatialQueryRole()))

component_identity(::MerksLocalConnectivityConstraint) =
    ComponentIdentity(:merks_local_connectivity, v"1.0.0", :constraint)
component_semantic_data(component::MerksLocalConnectivityConstraint) = (
    contract_version=MERKS_LOCAL_CONNECTIVITY_VERSION,
    source="Merks et al. Developmental Biology 289 (2006), Eq. 7 and Fig. 3",
    relation=relation_semantics_report(component.relation),
    collision_threshold=2,
    exactly_two_cell_exception=true,
    source_penalty="E0 > 2000",
    assembly_profile=:hard_rejection,
)
required_relations(component::MerksLocalConnectivityConstraint) =
    (component.relation,)

@inline function _merks_neighbor_owner(
    state,
    domain,
    relation,
    recipient,
    direction,
)
    neighbor = _realize_neighbor_unchecked(
        domain, relation, recipient, direction)
    neighbor.kind === MutableNeighbor &&
        return _proposal_owner_at(state, neighbor.site)
    neighbor.kind in (FixedNeighbor, ExteriorNeighbor) &&
        return _fixed_owner_unchecked(neighbor)
    # Closed or invalid sites are medium-like for this local test. The sentinel
    # can never compare equal to a valid cell owner.
    _owner_ref_unchecked(UInt8(0), UInt32(0))
end

@inline function _merks_local_connectivity_allowed(
    component::MerksLocalConnectivityConstraint,
    proposal::CopyProposal,
    state,
    domain,
)
    losing = proposal.losing
    is_cell_owner(losing) || return true
    same = MVector{8,Bool}(undef)
    owners = MVector{8,OwnerRef}(undef)
    for position in 1:8
        owner = _merks_neighbor_owner(
            state,
            domain,
            component.relation,
            proposal.recipient,
            Int(component.clockwise_directions[position]),
        )
        @inbounds owners[position] = owner
        @inbounds same[position] = owner == losing
    end
    collisions = 0
    for position in 1:8
        previous = mod1(position - 1, 8)
        next = mod1(position + 1, 8)
        @inbounds same[position] || continue
        @inbounds collisions +=
            2 - Int(same[previous]) - Int(same[next])
    end
    collisions <= 2 && return true

    distinct_cells = 0
    for position in 1:8
        @inbounds owner = owners[position]
        is_cell_owner(owner) || continue
        seen = false
        for earlier in 1:(position - 1)
            @inbounds if owners[earlier] == owner
                seen = true
                break
            end
        end
        distinct_cells += !seen
    end
    distinct_cells == 2
end

is_allowed(
    component::MerksLocalConnectivityConstraint,
    proposal::CopyProposal,
    state,
    domain,
) = _merks_local_connectivity_allowed(
    component, proposal, state, domain)

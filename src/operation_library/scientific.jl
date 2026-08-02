# Scientific operation admissions owned outside the generic host compiler.

operation_transfer(::typeof(_potts_merks_local_connectivity), ::Int) =
    _transfer(
        :merks_local_connectivity,
        3,
        :boolean,
        :dimensionless;
        footprint_rule = NeighborhoodFootprintRule(
            ProposalTargetNeighborhoodAnchor()
        ),
        allowed_roles = (:constraint,),
        allowed_phases = (:Proposal,),
        required_context = :proposal,
        owner = :PottsToolkitScientificOperations,
        source_requirements = (
            LatticeRankRequirement(2),
            SpatialRelationRequirement(2, :moore, 1),
            SpatialRelationRequirement(3, :von_neumann, 1),
        ),
    )

operation_transfer(::typeof(_potts_act_energy), ::Int) =
    _transfer(
        :act_energy,
        5,
        :real,
        :declared;
        footprint_rule = NeighborhoodFootprintRule(
            ProposalSourceTargetNeighborhoodAnchor()
        ),
        gpu = false,
        allowed_roles = (:drive,),
        allowed_phases = (:Proposal,),
        required_context = :proposal,
        owner = :PottsToolkitScientificOperations,
        source_requirements = (
            SpatialRelationRequirement(3, :moore, 1),
        ),
    )

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

struct MerksLocalConnectivityCallable <: CorePotts.AbstractContextualOperation end
struct ActEnergyCallable <: CorePotts.AbstractContextualOperation end

CorePotts.operation_context_supported(
    ::MerksLocalConnectivityCallable,
    ::Type{CorePotts.AbstractProposalEvaluationContext},
) = true
CorePotts.operation_context_supported(
    ::ActEnergyCallable,
    ::Type{CorePotts.AbstractProposalEvaluationContext},
) = true

function CorePotts.operation_callable(
        ::Val{:merks_local_connectivity},
        version::VersionNumber,
    )
    version == v"1.0.0" || throw(ArgumentError(
        "unsupported Merks local-connectivity operation version $version"
    ))
    return MerksLocalConnectivityCallable()
end

function CorePotts.operation_callable(
        ::Val{:act_energy},
        version::VersionNumber,
    )
    version == v"1.0.0" || throw(ArgumentError(
        "unsupported Act-energy operation version $version"
    ))
    return ActEnergyCallable()
end

@inline function (operation::MerksLocalConnectivityCallable)(
        arguments::Tuple, context
    )
    kind = Int16(arguments[1])
    foreground = Int32(arguments[2])
    background = Int32(arguments[3])
    CorePotts.proposal_relation_count(context, foreground) == 8 || return false
    CorePotts.proposal_relation_count(context, background) == 4 || return false

    losing = CorePotts.proposal_target_owner(context)
    losing <= 0 && return true
    CorePotts.proposal_target_kind(context) == kind || return true
    owners = ntuple(Val(8)) do position
        CorePotts.proposal_relation_neighbor_owner(
            context,
            foreground,
            _MERKS_CLOCKWISE_OFFSETS[position],
        )
    end
    any(==(typemin(Int32)), owners) && return false
    same = map(owner -> owner == losing, owners)
    collisions = 0
    for position in 1:8
        same[position] || continue
        previous = position == 1 ? 8 : position - 1
        next = position == 8 ? 1 : position + 1
        collisions += 2 - Int(same[previous]) - Int(same[next])
    end
    collisions <= 2 && return true

    distinct_cells = 0
    for position in 1:8
        owner = owners[position]
        owner > 0 || continue
        seen = false
        for earlier in 1:(position - 1)
            if owners[earlier] == owner
                seen = true
                break
            end
        end
        distinct_cells += !seen
    end
    return distinct_cells == 2
end

@inline function _act_local_geomean(
        context,
        state_handle,
        relation_handle,
        center,
        owner::Int32,
        ::Type{T},
    ) where {T <: AbstractFloat}
    owner <= 0 && return zero(T)
    total = zero(T)
    count = 0
    if CorePotts.proposal_site_owner(context, center) == owner
        value = T(CorePotts.state_value(context, state_handle, center))
        total += log1p(max(zero(T), value))
        count += 1
    end
    for direction in 1:CorePotts.proposal_relation_count(
            context, relation_handle
        )
        neighbor = CorePotts.proposal_relation_neighbor_site(
            context, relation_handle, center, direction
        )
        neighbor === nothing && continue
        CorePotts.proposal_site_owner(context, neighbor) == owner || continue
        value = T(CorePotts.state_value(context, state_handle, neighbor))
        total += log1p(max(zero(T), value))
        count += 1
    end
    return iszero(count) ? zero(T) : exp(total / T(count)) - one(T)
end

@inline function (operation::ActEnergyCallable)(arguments::Tuple, context)
    kind = Int16(arguments[1])
    state_handle = arguments[2]
    relation_handle = Int32(arguments[3])
    maximum = arguments[4]
    strength = arguments[5]
    T = promote_type(typeof(maximum), typeof(strength))
    new_owner = Int32(CorePotts.proposal_source_owner(context))
    new_owner > 0 || return zero(T)
    CorePotts.proposal_source_kind(context) == kind || return zero(T)
    maximum > zero(T) || return zero(T)
    source_activity = _act_local_geomean(
        context,
        state_handle,
        relation_handle,
        CorePotts.proposal_source_site(context),
        new_owner,
        T,
    )
    old_owner = Int32(CorePotts.proposal_target_owner(context))
    target_activity = _act_local_geomean(
        context,
        state_handle,
        relation_handle,
        CorePotts.proposal_target_site(context),
        old_owner,
        T,
    )
    return -(strength / maximum) * (source_activity - target_activity)
end

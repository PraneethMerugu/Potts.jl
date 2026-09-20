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
        owner = :PottsScientificOperations,
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
        version = v"2.0.0",
        serialization_identity = "potts-operation:act_energy:v2",
        footprint_rule = NeighborhoodFootprintRule(
            ProposalSourceTargetNeighborhoodAnchor()
        ),
        gpu = false,
        allowed_roles = (:drive,),
        allowed_phases = (:Proposal,),
        required_context = :proposal,
        owner = :PottsScientificOperations,
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

struct MerksLocalConnectivityCallable <: CorePotts.CompilerSPI.AbstractContextualOperation end
struct ActEnergyCallable <: CorePotts.CompilerSPI.AbstractContextualOperation end

CorePotts.CompilerSPI.operation_context_supported(
    ::MerksLocalConnectivityCallable,
    ::Type{<:CorePotts.CompilerSPI.AbstractProposalEvaluationContext},
) = true
CorePotts.CompilerSPI.operation_context_supported(
    ::ActEnergyCallable,
    ::Type{<:CorePotts.CompilerSPI.AbstractProposalEvaluationContext},
) = true

function CorePotts.CompilerSPI.operation_callable(
        ::Val{:merks_local_connectivity},
        version::VersionNumber,
    )
    version == v"1.0.0" || throw(ArgumentError(
        "unsupported Merks local-connectivity operation version $version"
    ))
    return MerksLocalConnectivityCallable()
end

function CorePotts.CompilerSPI.operation_callable(
        ::Val{:act_energy},
        version::VersionNumber,
    )
    version == v"2.0.0" || throw(ArgumentError(
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
    CorePotts.CompilerSPI.proposal_relation_count(context, foreground) == 8 || return false
    CorePotts.CompilerSPI.proposal_relation_count(context, background) == 4 || return false

    losing = CorePotts.CompilerSPI.proposal_target_owner(context)
    losing <= 0 && return true
    CorePotts.CompilerSPI.proposal_target_kind(context) == kind || return true
    owners = ntuple(Val(8)) do position
        CorePotts.CompilerSPI.proposal_relation_neighbor_owner(
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

@inline function (operation::ActEnergyCallable)(arguments::Tuple, context)
    kind = Int16(arguments[1])
    state_handle = arguments[2]
    relation_handle = Int32(arguments[3])
    maximum = arguments[4]
    strength = arguments[5]
    T = promote_type(typeof(maximum), typeof(strength))
    new_owner = Int32(CorePotts.CompilerSPI.proposal_source_owner(context))
    old_owner = Int32(CorePotts.CompilerSPI.proposal_target_owner(context))
    source_responds = new_owner > 0 &&
        CorePotts.CompilerSPI.proposal_source_kind(context) == kind
    target_responds = old_owner > 0 &&
        CorePotts.CompilerSPI.proposal_target_kind(context) == kind
    (source_responds || target_responds) || return zero(T)
    maximum > zero(T) || return zero(T)
    source_activity = if source_responds
        CorePotts.CompilerSPI.proposal_owner_activity_mean(
            context, state_handle, relation_handle,
            CorePotts.CompilerSPI.proposal_source_site(context), new_owner, T,
        )
    else
        zero(T)
    end
    target_activity = if target_responds
        CorePotts.CompilerSPI.proposal_owner_activity_mean(
            context, state_handle, relation_handle,
            CorePotts.CompilerSPI.proposal_target_site(context), old_owner, T,
        )
    else
        zero(T)
    end
    return -(strength / maximum) * (source_activity - target_activity)
end

# Typed atomic winner primitives shared by admitted arbitration profiles. They
# implement no routing, eligibility, publication, or execution schedule.

@inline function _rank_claim!(winners, destination, rank, ::Val{:min})
    Atomix.@atomic min(winners[destination], rank)
    return nothing
end

@inline function _rank_claim!(winners, destination, rank, ::Val{:max})
    Atomix.@atomic max(winners[destination], rank)
    return nothing
end

@inline function _identity_claim!(
        ranks, identities, destination, rank, identity
    )
    if @inbounds ranks[destination] == rank
        Atomix.@atomic min(identities[destination], identity)
    end
    return nothing
end

@inline function _is_winner(
        ranks, identities, destination, rank, identity
    )
    return @inbounds ranks[destination] == rank &&
                     identities[destination] == identity
end

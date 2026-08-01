# PottsToolkit-owned relationship policies composed over CorePotts primitives.

struct RelationshipEndpointKindsCallable <:
       CorePotts.AbstractContextualOperation end

@inline function (::RelationshipEndpointKindsCallable)(arguments::Tuple, context)
    endpoint_a = Int32(arguments[1])
    endpoint_b = Int32(arguments[2])
    kind_a = Int16(arguments[3])
    kind_b = Int16(arguments[4])
    endpoint_a > 0 && endpoint_b > 0 || return false
    actual_a = CorePotts.owner_kind(context, endpoint_a)
    actual_b = CorePotts.owner_kind(context, endpoint_b)
    return (actual_a == kind_a && actual_b == kind_b) ||
           (actual_a == kind_b && actual_b == kind_a)
end

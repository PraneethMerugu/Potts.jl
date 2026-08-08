# PottsToolkit-owned relationship policies composed over CorePotts primitives.

function _potts_relationship_endpoint_kinds end

@inline function _undirected_endpoint_kinds_match(
        actual_a::Int16,
        actual_b::Int16,
        required_a::Int16,
        required_b::Int16,
    )
    return (actual_a == required_a && actual_b == required_b) ||
           (actual_a == required_b && actual_b == required_a)
end

struct RelationshipEndpointKindsCallable <:
       CorePotts.CompilerSPI.AbstractContextualOperation end

CorePotts.CompilerSPI.operation_context_supported(
    ::RelationshipEndpointKindsCallable,
    ::Type{CorePotts.CompilerSPI.AbstractProposalEvaluationContext},
) = true

operation_transfer(
    ::typeof(_potts_relationship_endpoint_kinds), ::Int
) = _transfer(
    :relationship_endpoint_kinds,
    4,
    :boolean,
    :dimensionless;
    footprint_rule = InheritFootprintRule(),
    allowed_roles = (:process, :relationship),
    allowed_phases = (:AcceptedCopy,),
    required_context = :proposal,
    owner = :PottsToolkitRelationshipOperations,
)

function CorePotts.CompilerSPI.operation_callable(
        ::Val{:relationship_endpoint_kinds},
        version::VersionNumber,
    )
    version == v"1.0.0" || throw(ArgumentError(
        "unsupported relationship endpoint-kind operation version $version"
    ))
    return RelationshipEndpointKindsCallable()
end

@inline function (::RelationshipEndpointKindsCallable)(arguments::Tuple, context)
    endpoint_a = Int32(arguments[1])
    endpoint_b = Int32(arguments[2])
    kind_a = Int16(arguments[3])
    kind_b = Int16(arguments[4])
    endpoint_a > 0 && endpoint_b > 0 || return false
    actual_a = CorePotts.CompilerSPI.owner_kind(context, endpoint_a)
    actual_b = CorePotts.CompilerSPI.owner_kind(context, endpoint_b)
    return _undirected_endpoint_kinds_match(
        actual_a, actual_b, kind_a, kind_b
    )
end

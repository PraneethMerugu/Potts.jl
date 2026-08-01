# One compiled authority for relationship storage slots and endpoint legality.

function _relationship_endpoint_declaration(
        ir::AnalyzedTermIR,
        relationship::QualifiedStatement,
        requested,
    )
    declaration = _resource_record(
        ir.source, relationship, :CellKind, requested
    )
    declaration === nothing && (declaration = _resource_record(
        ir.source, relationship, :MediumKind, requested
    ))
    declaration === nothing && throw(ArgumentError(
        "relationship endpoint kind is not declared"
    ))
    return declaration
end

function _compile_relationship_endpoint_policies(ir::AnalyzedTermIR)
    policies = CompiledRelationshipEndpointPolicy[]
    for (slot, relationship) in enumerate(
            _ordered_relationships(ir.source.records)
        )
        endpoints = _statement_option(relationship, :endpoints)
        endpoints isa Undirected || throw(ArgumentError(
            "V1 relationship storage requires Undirected endpoints"
        ))
        declaration_a = _relationship_endpoint_declaration(
            ir, relationship, endpoints.kind_a
        )
        declaration_b = _relationship_endpoint_declaration(
            ir, relationship, endpoints.kind_b
        )
        kind_a = _compiled_kind_index(
            ir, relationship, endpoints.kind_a
        )
        kind_b = _compiled_kind_index(
            ir, relationship, endpoints.kind_b
        )
        (kind_a === nothing || kind_b === nothing) && throw(ArgumentError(
            "relationship endpoint kind has no compiled kind index"
        ))
        push!(policies, CompiledRelationshipEndpointPolicy(
            _qualified_resource_identity(relationship.identity),
            Int32(slot),
            :undirected,
            kind_a,
            kind_b,
            _qualified_public_name(declaration_a.identity),
            _qualified_public_name(declaration_b.identity),
        ))
    end
    return policies
end

function _relationship_endpoint_policy(policies, identity)
    resource_identity = identity isa QualifiedStatementID ?
                        _qualified_resource_identity(identity) : identity
    index = findfirst(
        policy -> policy.identity == resource_identity, policies
    )
    index === nothing && throw(ArgumentError(
        "relationship does not resolve to a compiled endpoint policy"
    ))
    return policies[index]
end

function _relationship_policy_record(
        ir::AnalyzedTermIR,
        policy::CompiledRelationshipEndpointPolicy,
    )
    return only(filter(
        record -> record.kind === :RelationshipState &&
                  _qualified_resource_identity(record.identity) ==
                  policy.identity,
        ir.source.records,
    ))
end

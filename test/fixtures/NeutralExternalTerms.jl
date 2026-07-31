module NeutralExternalTerms

using PottsToolkit
using Symbolics

import PottsToolkit: registered_statement_lowering

const SITE_SCHEMA = :external_weighted_site_term
const PAIR_SCHEMA = :external_bounded_pair_term
const VERSION = v"1.0.0"

function registered_statement_lowering(
        ::Val{:lower_external_weighted_site_term},
        id::StatementID,
        arguments::Tuple,
        options::NamedTuple,
        source,
    )
    isempty(options) ||
        throw(ArgumentError("ExternalWeightedSiteTerm accepts no options"))
    weight, target_cell_expression = arguments
    return ProposalEnergy(
        id,
        weight * cell_volume(target_cell_expression);
        source,
    )
end

function registered_statement_lowering(
        ::Val{:lower_external_bounded_pair_term},
        id::StatementID,
        arguments::Tuple,
        options::NamedTuple,
        source,
    )
    isempty(options) ||
        throw(ArgumentError("ExternalBoundedPairTerm accepts no options"))
    weight, linked_expression = arguments
    return ProposalEnergy(
        id,
        ifelse(linked_expression, weight, zero(weight));
        source,
    )
end

function registry()
    site_contract = (
        argument_types = (Num, Num),
        result_type = Real,
        unit_constraints = :energy_from_weight,
        namespace_traversal = :map_symbolics,
        access = (reads = (1, 2), writes = ()),
        effect = :pure_read,
        rng = (),
        boundedness = (maximum = 0, basis = :read_only),
        phase = Proposal(),
        capabilities = (
            sequential = true,
            checkerboard = true,
            reason = "",
        ),
        reference_semantics = :declared_energy,
        serialization_identity = "external-weighted-site-term-v1",
        lowering_identity = :lower_external_weighted_site_term,
    )
    pair_contract = (
        argument_types = (Num, Num),
        result_type = Real,
        unit_constraints = :energy_from_weight,
        namespace_traversal = :map_symbolics,
        access = (reads = (1, 2), writes = ()),
        effect = :pure_read,
        rng = (),
        boundedness = (maximum = 0, basis = :read_only),
        phase = Proposal(),
        capabilities = (
            sequential = true,
            checkerboard = true,
            reason = "",
        ),
        reference_semantics = :bounded_pair_membership,
        serialization_identity = "external-bounded-pair-term-v1",
        lowering_identity = :lower_external_bounded_pair_term,
    )
    result = register_statement(
        default_statement_registry(), SITE_SCHEMA, VERSION, site_contract
    )
    return register_statement(result, PAIR_SCHEMA, VERSION, pair_contract)
end

function ExternalWeightedSiteTerm(
        id::Symbol,
        weight,
        proposal::ProposalContext,
    )
    return RegisteredStatement(
        id,
        SITE_SCHEMA,
        VERSION,
        weight,
        proposal.target_cell,
    )
end

function ExternalBoundedPairTerm(
        id::Symbol,
        weight,
        relationship::RelationshipState,
        proposal::ProposalContext,
    )
    membership = linked(
        relationship,
        proposal.source_cell,
        proposal.target_cell,
    )
    return RegisteredStatement(
        id,
        PAIR_SCHEMA,
        VERSION,
        weight,
        membership,
    )
end

function bounded_pair_fixture(
        endothelial,
        weight,
        proposal::ProposalContext,
    )
    relationships = RelationshipState(
        :neutral_pairs;
        endpoints = Undirected(endothelial, endothelial),
        payload = (
            strength = weight,
            target = zero(weight),
            maximum = weight,
        ),
        capacity = 8,
        maximum_degree = 2,
        lifecycle = RemoveWithEndpoint(),
    )
    edge = RelationshipBinding(:neutral_edge, relationships)
    return StatementSet((
        relationships,
        ExternalBoundedPairTerm(
            :external_bounded_pair,
            weight,
            relationships,
            proposal,
        ),
        AcceptedCopy(
            :request_neutral_pair,
            Create(
                relationships,
                proposal.source_cell,
                proposal.target_cell;
                payload = (
                    strength = weight,
                    target = zero(weight),
                    maximum = weight,
                ),
            );
            when = new_contact(
                proposal.source_cell, proposal.target_cell
            ) & !linked(
                relationships,
                proposal.source_cell,
                proposal.target_cell,
            ),
        ),
        LifecycleProcess(
            :retire_disabled_neutral_pairs;
            domain = edges(relationships),
            expression = edge.strength < zero(weight),
            effects = (Remove(relationships, edge),),
            phase = Lifecycle(),
        ),
    ))
end

end

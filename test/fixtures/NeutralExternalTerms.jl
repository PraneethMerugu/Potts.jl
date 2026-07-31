module NeutralExternalTerms

using PottsToolkit
using Symbolics

import CorePotts
import PottsToolkit: operation_transfer, registered_descriptor_payload
import PottsToolkit: registered_statement_lowering
import PottsToolkit: registered_workspace_schemas

const SITE_SCHEMA = :external_weighted_site_term
const PAIR_SCHEMA = :external_bounded_pair_term
const VERSION = v"1.0.0"

function external_site_value end
Symbolics.@register_symbolic external_site_value(state, site)::Real

function external_cpu_only_value end
Symbolics.@register_symbolic external_cpu_only_value(value)::Real

struct ExternalSiteValueCallable <: CorePotts.AbstractContextualOperation end
struct ExternalCpuOnlyValueCallable end

operation_transfer(::typeof(external_site_value), ::Int) =
    PottsToolkit.OperationTransfer(
        :neutral_external_site_value,
        VERSION,
        "neutral-external-site-value-v1",
        2:2,
        :real,
        :declared,
        :pure,
        :total,
        :site_local,
        true,
        true,
    )

CorePotts.operation_callable(
    ::Val{:neutral_external_site_value},
    version::VersionNumber,
) = version == VERSION ? ExternalSiteValueCallable() :
    throw(ArgumentError("unsupported external site operation version $version"))

operation_transfer(::typeof(external_cpu_only_value), ::Int) =
    PottsToolkit.OperationTransfer(
        :neutral_external_cpu_only_value,
        VERSION,
        "neutral-external-cpu-only-value-v1",
        1:1,
        :preserve_numeric,
        :unary,
        :pure,
        :total,
        :scalar,
        true,
        false,
    )

CorePotts.operation_callable(
    ::Val{:neutral_external_cpu_only_value},
    version::VersionNumber,
) = version == VERSION ? ExternalCpuOnlyValueCallable() :
    throw(ArgumentError(
        "unsupported external CPU-only operation version $version"
    ))

@inline (
    ::ExternalSiteValueCallable
)(
    arguments,
    context,
) = CorePotts.state_value(context, arguments[1], arguments[2])

@inline (::ExternalCpuOnlyValueCallable)(value) = value

struct ExternalWeightedSitePayload
    schema::UInt16
end

struct ExternalBoundedPairPayload
    schema::UInt16
end

struct NameParameterizedPayload{Name}
    schema::UInt16
end

for payload_type in (
        :ExternalWeightedSitePayload,
        :ExternalBoundedPairPayload,
    )
    @eval begin
        CorePotts.descriptor_payload_adapt(
            to,
            payload::$payload_type,
        ) = payload
        CorePotts.descriptor_payload_checkpoint_encode(
            payload::$payload_type
        ) = (
            schema = payload.schema,
        )
        function CorePotts.descriptor_payload_checkpoint_reconstruct(
                current::$payload_type,
                payload::NamedTuple,
            )
            payload.schema == current.schema ||
                throw(ArgumentError(
                    "external descriptor payload metadata is incompatible"
                ))
            return current
        end
        CorePotts.descriptor_payload_inspection(payload::$payload_type) = (
            family = $(QuoteNode(payload_type)),
            schema = payload.schema,
        )
    end
end

function registered_descriptor_payload(
        ::Val{:lower_external_weighted_site_term},
        context::PottsToolkit.DescriptorConstructionContext,
    )
    if startswith(
            string(context.source.identity.local_id),
            "adversarial_payload",
        )
        return CorePotts.StaticEvaluator(
            CorePotts.LiteralExpression(99.0),
        )
    elseif startswith(
            string(context.source.identity.local_id),
            "adversarial_specialization",
        )
        return NameParameterizedPayload{
            Symbol(context.source.identity.local_id)
        }(UInt16(1))
    end
    return ExternalWeightedSitePayload(UInt16(1))
end

function registered_descriptor_payload(
        ::Val{:lower_external_bounded_pair_term},
        context::PottsToolkit.DescriptorConstructionContext,
    )
    return ExternalBoundedPairPayload(UInt16(1))
end

function registered_workspace_schemas(
        ::Val{:lower_external_weighted_site_term},
        source::PottsToolkit.DescriptorSource,
        ::Type{T},
        lattice_shape::Tuple,
    ) where {T <: AbstractFloat}
    identity = CorePotts.QualifiedResourceIdentity(
        source.identity.path,
        :external_weighted_occupancy,
    )
    return (
        CorePotts.WorkspaceSchema(
            identity,
            VERSION,
            T,
            lattice_shape,
            prod(lattice_shape; init = 1),
            Array,
            :zero_before_observe,
            :observation_stage,
            :exclusive_reduction,
            :adapt_storage,
            :qualified,
            false,
        ),
    )
end

function registered_statement_lowering(
        ::Val{:lower_external_weighted_site_term},
        id::StatementID,
        arguments::Tuple,
        options::NamedTuple,
        source,
    )
    isempty(options) ||
        throw(ArgumentError("ExternalWeightedSiteTerm accepts no options"))
    weight, state, site, energy_density = arguments
    return HamiltonianTerm(
        id;
        domain = sites(:lattice),
        anchor = site,
        expression = weight * energy_density,
        source = source,
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
    weight, edge, energy_density = arguments
    return HamiltonianTerm(
        id;
        domain = edges(edge.relationship),
        anchor = edge,
        expression = energy_density,
        source = source,
    )
end

function registry(;
        site_affected_region::Symbol = :target_site,
        pair_affected_region::Symbol = :incident_relationships,
    )
    site_contract = (
        argument_types = (Num, Num, SiteBinding, Num),
        result_type = Real,
        unit_constraints = :energy_from_weight,
        namespace_traversal = :map_symbolics,
        access = (reads = (1, 2, 3, 4), writes = ()),
        effect = :pure_read,
        rng = (),
        boundedness = (maximum = 0, basis = :read_only),
        phase = Proposal(),
        capabilities = (
            sequential = true,
            checkerboard = true,
            reason = "",
        ),
        scientific_category = :hamiltonian,
        energy_domain = :sites,
        affected_region = site_affected_region,
        reference_semantics = :weighted_site_occupancy_energy,
        descriptor_payload_type = ExternalWeightedSitePayload,
        serialization_identity = "external-weighted-site-term-v1",
        lowering_identity = :lower_external_weighted_site_term,
    )
    pair_contract = (
        argument_types = (Num, RelationshipBinding, Num),
        result_type = Real,
        unit_constraints = :energy_from_weight,
        namespace_traversal = :map_symbolics,
        access = (reads = (1, 2, 3), writes = ()),
        effect = :pure_read,
        rng = (),
        boundedness = (maximum = 0, basis = :read_only),
        phase = Proposal(),
        capabilities = (
            sequential = true,
            checkerboard = true,
            reason = "",
        ),
        scientific_category = :hamiltonian,
        energy_domain = :relationships,
        affected_region = pair_affected_region,
        reference_semantics = :bounded_pair_membership,
        descriptor_payload_type = ExternalBoundedPairPayload,
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
        state,
        kind::CellKind,
        site::SiteBinding,
    )
    return RegisteredStatement(
        id,
        SITE_SCHEMA,
        VERSION,
        weight,
        state,
        site,
        external_site_value(state, anchor_value(site)) *
        occupancy(kind, site),
    )
end

function ExternalBoundedPairTerm(
        id::Symbol,
        weight,
        relationship::RelationshipState,
        edge::RelationshipBinding,
    )
    return RegisteredStatement(
        id,
        PAIR_SCHEMA,
        VERSION,
        weight,
        edge,
        weight * edge.strength,
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
            edge,
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

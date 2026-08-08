module ExternalCompilerSPIFixture

using PottsToolkit
using ModelingToolkitBase
using Symbolics

import CorePotts
import PottsToolkit: operation_transfer, registered_descriptor_payload
import PottsToolkit: registered_statement_lowering
import PottsToolkit: registered_workspace_schemas

const CompilerSPI = CorePotts.CompilerSPI
const SCHEMA = :g5h_external_site_energy
const VERSION = v"1.0.0"

function external_site_value end
Symbolics.@register_symbolic external_site_value(state, site)::Real

struct ExternalSiteValueCallable <: CompilerSPI.AbstractContextualOperation end

for context in (
        CompilerSPI.AbstractHamiltonianEvaluationContext,
        CompilerSPI.AbstractProposalEvaluationContext,
    )
    @eval CompilerSPI.operation_context_supported(
        ::ExternalSiteValueCallable,
        ::Type{$context},
    ) = true
end

function CompilerSPI.operation_callable(
        ::Val{:g5h_external_site_value}, version::VersionNumber
    )
    version == VERSION || throw(ArgumentError(
        "unsupported G5H external operation version $version"
    ))
    return ExternalSiteValueCallable()
end

@inline function (::ExternalSiteValueCallable)(arguments, context)
    return CompilerSPI.state_value(context, arguments[1], arguments[2])
end

operation_transfer(::typeof(external_site_value), ::Int) =
    PottsToolkit.OperationTransfer(
        :g5h_external_site_value,
        VERSION,
        "g5h-external-site-value-v1",
        2:2,
        :real,
        :declared,
        :pure,
        :total,
        PottsToolkit.InheritFootprintRule(),
        true,
        true;
        allowed_roles = (:hamiltonian, :constraint),
        allowed_phases = (:Proposal,),
        required_context = :proposal,
        owner = :ExternalCompilerSPIFixture,
        callable_identity =
            "ExternalCompilerSPIFixture.ExternalSiteValueCallable",
    )

struct ExternalDescriptorPayload
    schema::UInt16
end

CompilerSPI.descriptor_payload_adapt(_, payload::ExternalDescriptorPayload) =
    payload
CompilerSPI.descriptor_payload_checkpoint_encode(
    payload::ExternalDescriptorPayload
) = (schema = payload.schema,)
function CompilerSPI.descriptor_payload_checkpoint_reconstruct(
        current::ExternalDescriptorPayload, encoded::NamedTuple
    )
    encoded.schema == current.schema || throw(ArgumentError(
        "external descriptor payload metadata is incompatible"
    ))
    return current
end
CompilerSPI.descriptor_payload_inspection(
    payload::ExternalDescriptorPayload
) = (
    family = :ExternalDescriptorPayload,
    schema = payload.schema,
)

function registered_descriptor_payload(
        ::Val{:lower_g5h_external_site_energy},
        context::PottsToolkit.DescriptorConstructionContext,
    )
    context.source.identity.local_id == StatementID(:mismatched_payload) &&
        return CompilerSPI.EmptyDescriptorPayload()
    return ExternalDescriptorPayload(0x0001)
end

function registered_workspace_schemas(
        ::Val{:lower_g5h_external_site_energy},
        source::PottsToolkit.DescriptorSource,
        ::Type{T},
        lattice_shape::Tuple,
    ) where {T <: AbstractFloat}
    identity = CompilerSPI.QualifiedResourceIdentity(
        source.identity.path,
        Symbol(source.identity.local_id.value, :_workspace),
    )
    return (CompilerSPI.WorkspaceSchema(
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
    ),)
end

function registered_statement_lowering(
        ::Val{:lower_g5h_external_site_energy},
        id::StatementID,
        arguments::Tuple,
        options::NamedTuple,
        source,
    )
    isempty(options) || throw(ArgumentError(
        "ExternalSiteEnergy accepts no options"
    ))
    weight, state, anchor, density = arguments
    return HamiltonianTerm(
        id;
        domain = sites(:lattice),
        anchor,
        expression = weight * density,
        source,
    )
end

function registry()
    contract = (
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
        affected_region = :target_site,
        reference_semantics = :weighted_site_state_energy,
        descriptor_payload_type = ExternalDescriptorPayload,
        serialization_identity = "g5h-external-site-energy-v1",
        lowering_identity = :lower_g5h_external_site_energy,
    )
    return register_statement(
        default_statement_registry(), SCHEMA, VERSION, contract
    )
end

function ExternalSiteEnergy(id, weight, state, kind, anchor)
    return RegisteredStatement(
        id,
        SCHEMA,
        VERSION,
        weight,
        state,
        anchor,
        external_site_value(state, anchor_value(anchor)) *
        occupancy(kind, anchor),
    )
end

function model(term_count::Integer = 1; mismatched::Bool = false)
    term_count > 0 || throw(ArgumentError("term_count must be positive"))
    @variables external_state
    @parameters external_weight = 2.0
    cell = CellKind(:external_cell; extinction = RetireAtZero())
    medium = MediumKind(:external_medium)
    anchor = SiteBinding(:external_site)
    copy = ProposalContext(:external_copy)
    state = SiteState(
        external_state;
        name = :external_state,
        initial = 1.0,
        owner = cell,
        lifecycle = PreserveOnOwnershipChange(),
    )
    terms = ntuple(term_count) do index
        id = mismatched && index == 1 ?
            :mismatched_payload : Symbol(:external_energy_, index)
        ExternalSiteEnergy(id, external_weight, external_state, cell, anchor)
    end
    source = PottsSystem(
        name = Symbol(:external_spi_, term_count, mismatched ? :_bad : :_ok),
        statements = StatementSet((
            Lattice(
                (2, 2);
                boundary = Periodic(),
                relations = (proposal = VonNeumann(),),
            ),
            cell,
            medium,
            state,
            terms...,
            ProposalConstraint(
                :external_state_guard,
                external_site_value(
                    external_state, target_site(copy)
                ) < 0,
            ),
            Protocol(Sweep(; temperature = 1.0); name = :main),
        )),
        unknowns = [external_state],
        parameters = [external_weight],
    )
    labels = Int32[1 0; 0 1]
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels; cells = [cell], medium
        ),
        values = (external_state => ones(Float64, 2, 2),),
    )
    return (; source, initial, state = external_state, weight = external_weight)
end

end

# Universal descriptor protocol, resource access, and proposal semantics.

"""Bounded scientific resource footprint used by compiler analysis."""
abstract type AbstractFootprint end
"""Footprint declaring no spatial or model resource dependence."""
struct EmptyFootprint <: AbstractFootprint end
"""One model-scoped resource, independent of lattice coordinates."""
struct ModelFootprint <: AbstractFootprint end
abstract type AbstractSpatialFootprintAnchor end
"""Anchor finite offsets at the proposal source site."""
struct ProposalSourceFootprintAnchor <: AbstractSpatialFootprintAnchor end
"""Anchor finite offsets at the proposal target site."""
struct ProposalTargetFootprintAnchor <: AbstractSpatialFootprintAnchor end
"""Anchor finite offsets at the current stage iteration site."""
struct IterationSiteFootprintAnchor <: AbstractSpatialFootprintAnchor end
"""Anchor finite offsets at the site stored in state slot `slot`."""
struct BoundSiteFootprintAnchor <: AbstractSpatialFootprintAnchor
    slot::Int32
end
struct ProposalContextFootprint <: AbstractFootprint end
"""Footprint over the finite owners participating in a proposal."""
struct OwnerFootprint <: AbstractFootprint end
"""Footprint over the compiler-selected contact neighborhood."""
struct ContactFootprint <: AbstractFootprint end
"""Finite ordered spatial offsets relative to an explicit anchor."""
struct FiniteSpatialFootprint{
        A <: AbstractSpatialFootprintAnchor,
        O,
    } <: AbstractFootprint
    anchor::A
    offsets::O
end

BoundSiteFootprintAnchor(slot::Integer) =
    BoundSiteFootprintAnchor(Int32(slot))
"""Incident relationship footprint bounded by `maximum_degree`."""
struct IncidentRelationshipFootprint <: AbstractFootprint
    maximum_degree::Int32
end
"""Ordered union of bounded resource footprints."""
struct FootprintUnion{F <: Tuple} <: AbstractFootprint
    footprints::F
end
struct FootprintMinkowski{
        L <: AbstractFootprint,
        R <: AbstractFootprint,
    } <: AbstractFootprint
    left::L
    right::R
end

abstract type AbstractWriteAccessPolicy end
"""Declare that an operation writes no scientific resource."""
struct NoWriteAccess <: AbstractWriteAccessPolicy end
"""Require proven destination exclusivity for writes."""
struct ExclusiveWriteAccess <: AbstractWriteAccessPolicy end
"""Permit exact commutative integer aggregation."""
struct CommutativeIntegerWriteAccess <: AbstractWriteAccessPolicy end
"""Defer writes as bounded relationship requests."""
struct DeferredRequestWriteAccess <: AbstractWriteAccessPolicy end

"""Canonical read, write, footprint, and conflict contract for one descriptor."""
struct ResourceAccess{
        R,
        W,
        F <: AbstractFootprint,
        X <: AbstractFootprint,
        P <: AbstractWriteAccessPolicy,
    }
    reads::R
    writes::W
    footprint::F
    write_footprint::X
    write_policy::P
    function ResourceAccess(
            reads::R,
            writes::W,
            footprint::F,
            write_footprint::X,
            write_policy::P,
        ) where {
            R,
            W,
            F <: AbstractFootprint,
            X <: AbstractFootprint,
            P <: AbstractWriteAccessPolicy,
        }
        isempty(writes) == (write_policy isa NoWriteAccess) || throw(
            ArgumentError(
                "resource writes and the closed write policy disagree"
            )
        )
        isempty(writes) && !(write_footprint isa EmptyFootprint) && throw(
            ArgumentError(
                "read-only resource access cannot carry a write footprint"
            )
        )
        !isempty(writes) && write_policy isa ExclusiveWriteAccess &&
            write_footprint isa EmptyFootprint && throw(ArgumentError(
                "exclusive resource writes require a finite write footprint"
            ))
        return new{R, W, F, X, P}(
            reads, writes, footprint, write_footprint, write_policy
        )
    end
end

"""Qualified engine and backend support for a compiled descriptor."""
struct DescriptorSupport
    sequential::Bool
    checkerboard::Bool
    cpu::Bool
    gpu::Bool
    reason_code::UInt16
end

DescriptorSupport(
    sequential::Bool,
    checkerboard::Bool,
    cpu::Bool,
    gpu::Bool,
    reason_code::Integer = 0,
) = DescriptorSupport(
    sequential,
    checkerboard,
    cpu,
    gpu,
    UInt16(reason_code),
)

function descriptor_state_requirements end
function descriptor_workspace_requirements end
"""Return the canonical `ResourceAccess` for a compiled descriptor."""
function descriptor_resource_access end
function descriptor_stage end
function descriptor_role end
function descriptor_dependencies end
function descriptor_support end
function descriptor_emit_requests! end
function descriptor_apply_stage! end
"""Adapt a descriptor's executable payload to an execution backend."""
function descriptor_adapt end
function descriptor_evaluator_node_count end
function descriptor_source_handle end
function descriptor_checkpoint_policy end
function descriptor_checkpoint_encode end
"""Reconstruct a descriptor payload from checkpoint data."""
function descriptor_checkpoint_reconstruct end
function descriptor_checkpoint end
"""Return stable scientific and compiler facts for a descriptor."""
function descriptor_inspection end
"""Adapt an extension-owned descriptor payload to a backend."""
function descriptor_payload_adapt end
"""Encode extension-owned descriptor payload checkpoint data."""
function descriptor_payload_checkpoint_encode end
"""Reconstruct an extension-owned payload from checkpoint data."""
function descriptor_payload_checkpoint_reconstruct end
"""Return stable inspection facts for an extension-owned payload."""
function descriptor_payload_inspection end

"""Zero-state payload for descriptors needing no extension-owned data."""
struct EmptyDescriptorPayload end

descriptor_payload_adapt(to, payload) = payload
descriptor_payload_checkpoint_encode(::EmptyDescriptorPayload) = nothing
descriptor_payload_checkpoint_reconstruct(
    payload::EmptyDescriptorPayload, ::Nothing
) = payload
descriptor_payload_inspection(::EmptyDescriptorPayload) = NamedTuple()

"""One ordered proposal evaluator with bounded access and role semantics."""
struct ProposalDescriptor{
        E <: StaticEvaluator,
        A <: ResourceAccess,
        S,
        H <: Tuple,
        W <: Tuple,
        R,
        P,
    }
    evaluator::E
    access::A
    support::S
    state_handles::H
    workspace_handles::W
    role::R
    source_handle::Int32
    payload::P
end

function ProposalDescriptor(
        evaluator::E,
        access::A,
        support::S,
        state_handles::H,
        workspace_handles::W,
        role::R,
        source_handle::Integer,
        payload::P,
    ) where {
        E <: StaticEvaluator,
        A <: ResourceAccess,
        S,
        H <: Tuple,
        W <: Tuple,
        R,
        P,
    }
    source_handle > 0 ||
        throw(ArgumentError("a descriptor source handle must be positive"))
    return ProposalDescriptor{E, A, S, H, W, R, P}(
        evaluator,
        access,
        support,
        state_handles,
        workspace_handles,
        role,
        Int32(source_handle),
        payload,
    )
end

ProposalDescriptor(
    evaluator::StaticEvaluator,
    access::ResourceAccess,
    support,
    state_handles::Tuple,
    workspace_handles::Tuple,
    role,
    source_handle::Integer,
) = ProposalDescriptor(
    evaluator,
    access,
    support,
    state_handles,
    workspace_handles,
    role,
    source_handle,
    EmptyDescriptorPayload(),
)

ProposalDescriptor(
    evaluator::StaticEvaluator,
    access::ResourceAccess,
    support,
    source_handle::Integer,
) = ProposalDescriptor(
    evaluator,
    access,
    support,
    (),
    (),
    ProposalDriveRole(),
    source_handle,
    EmptyDescriptorPayload(),
)

"""Scientific role determining how a proposal evaluator contributes."""
abstract type AbstractProposalRole end
abstract type AbstractEnergyDomainPlan end
"""Evaluate Hamiltonian energy over a lattice-site domain."""
struct SiteEnergyDomainPlan <: AbstractEnergyDomainPlan end
"""Evaluate Hamiltonian energy for cells of one kind."""
struct CellEnergyDomainPlan <: AbstractEnergyDomainPlan
    kind::Int16
end
"""Evaluate energy over a compiler-bound contact relation."""
struct ContactEnergyDomainPlan <: AbstractEnergyDomainPlan
    relation_handle::Int32
end
"""Evaluate energy over a compiler-bound relationship store."""
struct RelationshipEnergyDomainPlan <: AbstractEnergyDomainPlan
    relationship_handle::Int32
end

abstract type AbstractAffectedAnchorPlan end
"""Declare target-site energy anchors affected by a proposal."""
struct TargetSiteAffectedPlan <: AbstractAffectedAnchorPlan
    maximum::Int32
end
"""Declare affected anchors through a bounded neighborhood relation."""
struct NeighborhoodSitesAffectedPlan <: AbstractAffectedAnchorPlan
    maximum::Int32
    relation_handle::Int32
end
"""Declare the proposal's source and target cells as affected anchors."""
struct SourceTargetCellsAffectedPlan <: AbstractAffectedAnchorPlan
    maximum::Int32
end
"""Declare bounded incident contacts as affected anchors."""
struct IncidentContactsAffectedPlan <: AbstractAffectedAnchorPlan
    maximum::Int32
end
"""Declare bounded incident relationships as affected anchors."""
struct IncidentRelationshipsAffectedPlan <: AbstractAffectedAnchorPlan
    maximum::Int32
end

"""Hamiltonian contribution with explicit domain and affected-anchor plans."""
struct HamiltonianRole{
        D <: AbstractEnergyDomainPlan,
        A <: AbstractAffectedAnchorPlan,
    } <: AbstractProposalRole
    domain::D
    affected::A
end
HamiltonianRole() = HamiltonianRole(
    SiteEnergyDomainPlan(), TargetSiteAffectedPlan(Int32(1))
)
"""Add a non-energy drive directly to proposal acceptance."""
struct ProposalDriveRole <: AbstractProposalRole end
"""Add a drive measured in energy units."""
struct ProposalEnergyDriveRole <: AbstractProposalRole end
"""Evaluate a Boolean proposal admissibility constraint."""
struct ProposalConstraintRole <: AbstractProposalRole end
"""Modify the accumulated proposal energy before acceptance."""
struct ProposalModifierRole <: AbstractProposalRole end

descriptor_state_requirements(descriptor::ProposalDescriptor) =
    descriptor.state_handles
descriptor_workspace_requirements(descriptor::ProposalDescriptor) =
    descriptor.workspace_handles
descriptor_resource_access(descriptor::ProposalDescriptor) = descriptor.access
descriptor_stage(::ProposalDescriptor) = :proposal
descriptor_role(descriptor::ProposalDescriptor) = descriptor.role
descriptor_dependencies(::ProposalDescriptor) = ()
descriptor_support(descriptor::ProposalDescriptor) = descriptor.support
function _compiled_descriptor_adapt(to, descriptor::ProposalDescriptor)
    payload = descriptor_payload_adapt(to, descriptor.payload)
    return ProposalDescriptor(
        descriptor.evaluator,
        descriptor.access,
        descriptor.support,
        descriptor.state_handles,
        descriptor.workspace_handles,
        descriptor.role,
        descriptor.source_handle,
        payload,
    )
end
descriptor_adapt(to, descriptor::ProposalDescriptor) =
    _compiled_descriptor_adapt(to, descriptor)
descriptor_evaluator_node_count(descriptor::ProposalDescriptor) =
    evaluator_node_count(descriptor.evaluator)
descriptor_source_handle(descriptor::ProposalDescriptor) =
    descriptor.source_handle
descriptor_checkpoint_policy(::ProposalDescriptor) =
    :reconstruct_from_executable
descriptor_checkpoint_encode(descriptor::ProposalDescriptor) =
    descriptor_payload_checkpoint_encode(descriptor.payload)
descriptor_checkpoint_reconstruct(
    descriptor::ProposalDescriptor, payload
) = _compiled_descriptor_checkpoint_reconstruct(descriptor, payload)
_compiled_descriptor_checkpoint_reconstruct(
    descriptor::ProposalDescriptor, payload
) = ProposalDescriptor(
    descriptor.evaluator,
    descriptor.access,
    descriptor.support,
    descriptor.state_handles,
    descriptor.workspace_handles,
    descriptor.role,
    descriptor.source_handle,
    descriptor_payload_checkpoint_reconstruct(
        descriptor.payload, payload
    ),
)
descriptor_checkpoint(descriptor::ProposalDescriptor) = (
    policy = descriptor_checkpoint_policy(descriptor),
    payload = descriptor_checkpoint_encode(descriptor),
)
descriptor_inspection(descriptor::ProposalDescriptor) =
    _compiled_descriptor_inspection(descriptor)
_compiled_descriptor_inspection(descriptor::ProposalDescriptor) = (
    source_handle = descriptor.source_handle,
    evaluator = nameof(typeof(descriptor.evaluator.expression)),
    stage = :proposal,
    role = nameof(typeof(descriptor.role)),
    energy_domain = descriptor.role isa HamiltonianRole ?
                    nameof(typeof(descriptor.role.domain)) : nothing,
    affected_plan = descriptor.role isa HamiltonianRole ?
                    nameof(typeof(descriptor.role.affected)) : nothing,
    state_handles = descriptor.state_handles,
    workspace_handles = descriptor.workspace_handles,
    payload = descriptor_payload_inspection(descriptor.payload),
)

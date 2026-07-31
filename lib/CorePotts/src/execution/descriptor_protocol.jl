# Universal descriptor protocol, resource access, and proposal semantics.

abstract type AbstractFootprint end
struct EmptyFootprint <: AbstractFootprint end
struct ProposalContextFootprint <: AbstractFootprint end
struct OwnerFootprint <: AbstractFootprint end
struct FiniteSpatialFootprint{O} <: AbstractFootprint
    offsets::O
end
struct IncidentRelationshipFootprint <: AbstractFootprint
    maximum_degree::Int32
end
struct FootprintUnion{F <: Tuple} <: AbstractFootprint
    footprints::F
end

struct ResourceAccess{R, W, F <: AbstractFootprint}
    reads::R
    writes::W
    footprint::F
end

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
function descriptor_resource_access end
function descriptor_stage end
function descriptor_role end
function descriptor_dependencies end
function descriptor_support end
function descriptor_evaluate_proposal end
function descriptor_emit_requests! end
function descriptor_apply_stage! end
function descriptor_adapt end
function descriptor_evaluator_node_count end
function descriptor_source_handle end
function descriptor_checkpoint_policy end
function descriptor_checkpoint_encode end
function descriptor_checkpoint_reconstruct end
function descriptor_checkpoint end
function descriptor_inspection end
function descriptor_payload_adapt end
function descriptor_payload_checkpoint_encode end
function descriptor_payload_checkpoint_reconstruct end
function descriptor_payload_inspection end

struct EmptyDescriptorPayload end

descriptor_payload_adapt(to, payload) = payload
descriptor_payload_checkpoint_encode(::EmptyDescriptorPayload) = nothing
descriptor_payload_checkpoint_reconstruct(
    payload::EmptyDescriptorPayload, ::Nothing
) = payload
descriptor_payload_inspection(::EmptyDescriptorPayload) = NamedTuple()

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
    HamiltonianRole(),
    source_handle,
    EmptyDescriptorPayload(),
)

abstract type AbstractProposalRole end
struct HamiltonianRole <: AbstractProposalRole end
struct ProposalDriveRole <: AbstractProposalRole end
struct ProposalConstraintRole <: AbstractProposalRole end
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
@inline descriptor_evaluate_proposal(descriptor::ProposalDescriptor, context) =
    evaluate_static(descriptor.evaluator, context)
function descriptor_adapt(to, descriptor::ProposalDescriptor)
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
descriptor_inspection(descriptor::ProposalDescriptor) = (
    source_handle = descriptor.source_handle,
    evaluator = nameof(typeof(descriptor.evaluator.expression)),
    stage = :proposal,
    role = nameof(typeof(descriptor.role)),
    state_handles = descriptor.state_handles,
    workspace_handles = descriptor.workspace_handles,
    payload = descriptor_payload_inspection(descriptor.payload),
)

# Descriptor launch grouping, adaptation, validation, and inspection.

struct DescriptorKernelStrategy{D, E, F, R, K} end

struct DescriptorLaunch{
        S,
        D,
        I <: AbstractVector{D},
        H <: Tuple,
        W <: Tuple,
    }
    strategy::S
    instances::I
    state_handles::H
    workspace_handles::W
end

struct DescriptorGroup{L, M}
    launch::L
    split::M
end

abstract type AbstractDescriptorEvaluationPlan end

struct KernelDescriptorGroup{L}
    launch::L
end

struct DescriptorKernelPlan{G <: Tuple, D <: HamiltonianDomainResources} <:
        AbstractDescriptorEvaluationPlan
    groups::G
    source_count::Int32
    domain_resources::D
end

descriptor_launch(group::DescriptorGroup) = group.launch

struct ParameterDomainConstraint{E <: StaticEvaluator}
    evaluator::E
    predicate::UInt8
    source_handle::Int32
end

struct ConstraintGroup{C, V <: AbstractVector{C}}
    instances::V
end

struct DescriptorExecutionPlan{
        G <: Tuple,
        C <: Tuple,
        S <: AbstractVector,
        D <: HamiltonianDomainResources,
    } <: AbstractDescriptorEvaluationPlan
    groups::G
    state_layout::StateLayout
    workspace_layout::WorkspaceLayout
    constraints::C
    source_table::S
    occurrence_count::Int32
    fingerprint::String
    domain_resources::D
    function DescriptorExecutionPlan{G, C, S, D}(
            groups::G,
            state_layout::StateLayout,
            workspace_layout::WorkspaceLayout,
            constraints::C,
            source_table::S,
            occurrence_count::Int32,
            fingerprint::String,
            domain_resources::D,
        ) where {
            G <: Tuple,
            C <: Tuple,
            S <: AbstractVector,
            D <: HamiltonianDomainResources,
        }
        all(groups) do group
            all(descriptor -> descriptor isa ProposalDescriptor,
                group.launch.instances)
        end || throw(ArgumentError(
            "descriptor execution plans admit only compiler-owned ProposalDescriptor values"
        ))
        occurrence_count >= 0 || throw(ArgumentError(
            "descriptor occurrence count cannot be negative"
        ))
        return new{G, C, S, D}(
            groups,
            state_layout,
            workspace_layout,
            constraints,
            source_table,
            occurrence_count,
            fingerprint,
            domain_resources,
        )
    end
end

function DescriptorExecutionPlan(
        groups::G,
        state_layout::StateLayout,
        workspace_layout::WorkspaceLayout,
        constraints::C,
        source_table::S,
        occurrence_count,
        fingerprint,
        domain_resources::D,
    ) where {
        G <: Tuple,
        C <: Tuple,
        S <: AbstractVector,
        D <: HamiltonianDomainResources,
    }
    return DescriptorExecutionPlan{G, C, S, D}(
        groups,
        state_layout,
        workspace_layout,
        constraints,
        source_table,
        Int32(occurrence_count),
        String(fingerprint),
        domain_resources,
    )
end

Adapt.@adapt_structure LiteralExpression
Adapt.@adapt_structure ParameterExpression
Adapt.@adapt_structure ContextExpression
Adapt.@adapt_structure StateExpression
Adapt.@adapt_structure OperationExpression
Adapt.@adapt_structure StaticEvaluator
Adapt.@adapt_structure EvaluatorProbeContext
Adapt.@adapt_structure ResourceAccess
Adapt.@adapt_structure ProposalDescriptor
Adapt.@adapt_structure DenseStateBlock
Adapt.@adapt_structure DenseWorkspaceBlock
function Adapt.adapt_structure(
        to,
        bank::BlockBank{Representation},
    ) where {Representation}
    values = Adapt.adapt(to, bank.values)
    return BlockBank{Representation, typeof(values)}(values)
end
Adapt.@adapt_structure AuxiliaryState
Adapt.@adapt_structure RuntimeWorkspaces
Adapt.@adapt_structure DescriptorLaunch
Adapt.@adapt_structure KernelDescriptorGroup
Adapt.@adapt_structure DescriptorKernelPlan
Adapt.@adapt_structure ParameterDomainConstraint
Adapt.@adapt_structure ConstraintGroup

function adapt_descriptor_launch(to, group::DescriptorGroup)
    launch = descriptor_launch(group)
    adapted_descriptors = map(
        descriptor -> begin
            descriptor isa ProposalDescriptor || throw(ArgumentError(
                "production launches require compiler-owned ProposalDescriptor values"
            ))
            _compiled_descriptor_adapt(to, descriptor)
        end,
        launch.instances,
    )
    adapted_instances = Adapt.adapt(to, adapted_descriptors)
    return DescriptorLaunch(
        launch.strategy,
        adapted_instances,
        launch.state_handles,
        launch.workspace_handles,
    )
end

function adapt_descriptor_kernel_plan(to, plan::DescriptorExecutionPlan)
    groups = map(
        group -> KernelDescriptorGroup(adapt_descriptor_launch(to, group)),
        plan.groups,
    )
    return DescriptorKernelPlan(
        groups,
        Int32(length(plan.source_table)),
        Adapt.adapt(to, plan.domain_resources),
    )
end

function adapt_descriptor_launch(to, group::KernelDescriptorGroup)
    launch = group.launch
    adapted_descriptors = map(
        descriptor -> _compiled_descriptor_adapt(to, descriptor),
        launch.instances,
    )
    return DescriptorLaunch(
        launch.strategy,
        Adapt.adapt(to, adapted_descriptors),
        launch.state_handles,
        launch.workspace_handles,
    )
end

function adapt_descriptor_kernel_plan(to, plan::DescriptorKernelPlan)
    groups = map(
        group -> KernelDescriptorGroup(adapt_descriptor_launch(to, group)),
        plan.groups,
    )
    return DescriptorKernelPlan(
        groups,
        plan.source_count,
        Adapt.adapt(to, plan.domain_resources),
    )
end

_descriptor_source_count(plan::DescriptorExecutionPlan) =
    length(plan.source_table)
_descriptor_source_count(plan::DescriptorKernelPlan) =
    Int(plan.source_count)

@kernel function descriptor_group_probe_kernel!(
        output,
        launch,
        context,
    )
    index = @index(Global, Linear)
    if index <= length(launch.instances)
        descriptor = @inbounds launch.instances[index]
        descriptor isa ProposalDescriptor || error(
            "production descriptor launches require compiler-owned ProposalDescriptor values"
        )
        @inbounds output[index] = _compiled_evaluate_static(
            getfield(descriptor, :evaluator), context
        )
    end
end

@inline function _constraint_passes(value, predicate::UInt8)
    predicate == 0x01 && return value > zero(value)
    predicate == 0x02 && return value >= zero(value)
    predicate == 0x03 && return value === true
    return false
end

function validate_parameters(plan::DescriptorExecutionPlan, parameters)
    context = EvaluatorProbeContext(parameters, NamedTuple())
    for group in plan.constraints
        for constraint in group.instances
            value = _compiled_evaluate_static(constraint.evaluator, context)
            _constraint_passes(value, constraint.predicate) || throw(
                DomainError(
                    value,
                    "runtime parameter constraint failed for source handle " *
                    string(constraint.source_handle),
                ),
            )
        end
    end
    return nothing
end

"""
Evaluate Hamiltonian descriptor groups into source-indexed contribution storage.

Group execution order is deliberately decoupled from numerical folding order.
Callers provide the buffer so a warmed proposal path does not allocate.
"""
@inline function _evaluate_hamiltonian_instances!(
        contributions,
        instances::AbstractVector{D},
        context,
        resources,
    ) where {D}
    for descriptor in instances
        descriptor isa ProposalDescriptor || throw(ArgumentError(
            "production Hamiltonian plans require compiler-owned ProposalDescriptor values"
        ))
        role = getfield(descriptor, :role)
        role isa HamiltonianRole || continue
        source = Int(getfield(descriptor, :source_handle))
        @inbounds contributions[source] = _compiled_hamiltonian_delta(
            getfield(descriptor, :evaluator), role, context, resources
        )
    end
    return contributions
end

@inline _evaluate_hamiltonian_groups!(
    contributions, ::Tuple{}, context, resources
) = contributions
@inline function _evaluate_hamiltonian_groups!(
        contributions,
        groups::Tuple,
        context,
        resources,
    )
    group = first(groups)
    _evaluate_hamiltonian_instances!(
        contributions, group.launch.instances, context, resources
    )
    return _evaluate_hamiltonian_groups!(
        contributions, Base.tail(groups), context, resources
    )
end

@inline function evaluate_hamiltonian_contributions!(
        contributions,
        plan::AbstractDescriptorEvaluationPlan,
        context,
    )
    length(contributions) >= _descriptor_source_count(plan) || throw(
        ArgumentError("Hamiltonian contribution storage is too small"),
    )
    fill!(contributions, zero(eltype(contributions)))
    return _evaluate_hamiltonian_groups!(
        contributions, plan.groups, context, plan.domain_resources
    )
end

"""Fold source-indexed Hamiltonian contributions in canonical source order."""
@inline function fold_hamiltonian_contributions(
        plan::AbstractDescriptorEvaluationPlan,
        contributions,
    )
    source_count = _descriptor_source_count(plan)
    length(contributions) >= source_count || throw(
        ArgumentError("Hamiltonian contribution storage is too small"),
    )
    total = zero(eltype(contributions))
    for source in 1:source_count
        total += @inbounds contributions[source]
    end
    return total
end

"""One source-indexed proposal contribution with scientific roles kept distinct."""
struct ProposalEvaluation{T <: AbstractFloat}
    delta_h::T
    drive_energy::T
    drive_log_bias::T
    kinetic_modifier::T
    constraints_allowed::Bool
end

ProposalEvaluation(
    delta_h::T,
    drive_log_bias::T,
    kinetic_modifier::T,
    constraints_allowed::Bool,
) where {T <: AbstractFloat} = ProposalEvaluation(
    delta_h,
    zero(T),
    drive_log_bias,
    kinetic_modifier,
    constraints_allowed,
)

@inline _neutral_proposal_evaluation(::Type{T}) where {T <: AbstractFloat} =
    ProposalEvaluation(zero(T), zero(T), zero(T), zero(T), true)

@inline function _checked_proposal_scalar(value, ::Type{T}) where {
        T <: AbstractFloat,
    }
    return T(value)
end

@inline function _compiled_proposal_evaluation(
        evaluator::StaticEvaluator,
        role::HamiltonianRole,
        context,
        resources,
        ::Type{T},
    ) where {T <: AbstractFloat}
    value = _checked_proposal_scalar(
        _compiled_hamiltonian_delta(evaluator, role, context, resources), T
    )
    return ProposalEvaluation(value, zero(T), zero(T), zero(T), true)
end

@inline function _compiled_proposal_evaluation(
        evaluator::StaticEvaluator,
        ::ProposalDriveRole,
        context,
        resources,
        ::Type{T},
    ) where {T <: AbstractFloat}
    value = _checked_proposal_scalar(
        _compiled_evaluate_static(evaluator, context), T
    )
    return ProposalEvaluation(zero(T), zero(T), value, zero(T), true)
end

@inline function _compiled_proposal_evaluation(
        evaluator::StaticEvaluator,
        ::ProposalEnergyDriveRole,
        context,
        resources,
        ::Type{T},
    ) where {T <: AbstractFloat}
    value = _checked_proposal_scalar(
        _compiled_evaluate_static(evaluator, context), T
    )
    return ProposalEvaluation(zero(T), value, zero(T), zero(T), true)
end

@inline function _compiled_proposal_evaluation(
        evaluator::StaticEvaluator,
        ::ProposalModifierRole,
        context,
        resources,
        ::Type{T},
    ) where {T <: AbstractFloat}
    value = _checked_proposal_scalar(
        _compiled_evaluate_static(evaluator, context), T
    )
    return ProposalEvaluation(zero(T), zero(T), zero(T), value, true)
end

@inline function _compiled_proposal_evaluation(
        evaluator::StaticEvaluator,
        ::ProposalConstraintRole,
        context,
        resources,
        ::Type{T},
    ) where {T <: AbstractFloat}
    value = _compiled_evaluate_static(evaluator, context)
    value isa Bool || throw(ArgumentError(
        "proposal constraint descriptor must return Bool"
    ))
    return ProposalEvaluation(zero(T), zero(T), zero(T), zero(T), value)
end

@inline function _evaluate_proposal_instances!(
        contributions::AbstractVector{ProposalEvaluation{T}},
        instances::AbstractVector{D},
        context,
        resources,
    ) where {T <: AbstractFloat, D}
    for descriptor in instances
        descriptor isa ProposalDescriptor || throw(ArgumentError(
            "production proposal plans require compiler-owned ProposalDescriptor values"
        ))
        source = Int(getfield(descriptor, :source_handle))
        @inbounds contributions[source] = _compiled_proposal_evaluation(
            getfield(descriptor, :evaluator),
            getfield(descriptor, :role),
            context,
            resources,
            T,
        )
    end
    return contributions
end

@inline _evaluate_proposal_groups!(
    contributions, ::Tuple{}, context, resources
) = contributions
@inline function _evaluate_proposal_groups!(
        contributions,
        groups::Tuple,
        context,
        resources,
    )
    group = first(groups)
    _evaluate_proposal_instances!(
        contributions, group.launch.instances, context, resources
    )
    return _evaluate_proposal_groups!(
        contributions, Base.tail(groups), context, resources
    )
end

"""Evaluate every proposal descriptor into caller-owned, source-indexed storage."""
@inline function evaluate_proposal_contributions!(
        contributions::AbstractVector{ProposalEvaluation{T}},
        plan::AbstractDescriptorEvaluationPlan,
        context,
    ) where {T <: AbstractFloat}
    length(contributions) >= _descriptor_source_count(plan) || throw(
        ArgumentError("proposal contribution storage is too small"),
    )
    fill!(contributions, _neutral_proposal_evaluation(T))
    return _evaluate_proposal_groups!(
        contributions, plan.groups, context, plan.domain_resources
    )
end

"""Fold proposal roles in canonical frozen source order."""
@inline function fold_proposal_contributions(
        plan::AbstractDescriptorEvaluationPlan,
        contributions::AbstractVector{ProposalEvaluation{T}},
    ) where {T <: AbstractFloat}
    source_count = _descriptor_source_count(plan)
    length(contributions) >= source_count || throw(
        ArgumentError("proposal contribution storage is too small"),
    )
    delta_h = zero(T)
    drive_energy = zero(T)
    drive_log_bias = zero(T)
    kinetic_modifier = zero(T)
    constraints_allowed = true
    for source in 1:source_count
        contribution = @inbounds contributions[source]
        delta_h += contribution.delta_h
        drive_energy += contribution.drive_energy
        drive_log_bias += contribution.drive_log_bias
        kinetic_modifier += contribution.kinetic_modifier
        constraints_allowed &= contribution.constraints_allowed
    end
    return ProposalEvaluation(
        delta_h,
        drive_energy,
        drive_log_bias,
        kinetic_modifier,
        constraints_allowed,
    )
end

function descriptor_plan_report(plan::DescriptorExecutionPlan)
    return (
        occurrences = Int(plan.occurrence_count),
        groups = length(plan.groups),
        instances = Tuple(
            length(group.launch.instances) for group in plan.groups
        ),
        evaluator_nodes = Tuple(
            evaluator_node_count(
                getfield(first(group.launch.instances), :evaluator)
            )
            for group in plan.groups
        ),
        descriptor_inspections = Tuple(
            [
                merge(
                    (
                        qualified_source = plan.source_table[
                            getfield(descriptor, :source_handle)
                        ],
                    ),
                    _compiled_descriptor_inspection(descriptor),
                )
                for descriptor in group.launch.instances
            ]
            for group in plan.groups
        ),
        specializations = length(plan.groups),
        state_blocks = length(plan.state_layout.schemas),
        workspaces = length(plan.workspace_layout.schemas),
        validation_groups = length(plan.constraints),
        contact_domain_resources = count(>(0), plan.domain_resources.contact_counts),
        relationship_domain_resources =
            count(>(0), plan.domain_resources.relationship_slots),
        group_splits = Tuple(group.split for group in plan.groups),
        kernel_families = Tuple(
            nameof(typeof(group.launch.strategy)) for group in plan.groups
        ),
        fingerprint = plan.fingerprint,
    )
end

_expression_node_count(::Union{LiteralExpression, ParameterExpression,
                               ContextExpression, StateExpression}) = 1
_expression_node_count(expression::OperationExpression) =
    1 + sum(_expression_node_count, expression.arguments; init = 0)
evaluator_node_count(evaluator::StaticEvaluator) =
    _expression_node_count(evaluator.expression)

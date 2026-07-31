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
    }
    groups::G
    state_layout::StateLayout
    workspace_layout::WorkspaceLayout
    constraints::C
    source_table::S
    occurrence_count::Int32
    fingerprint::String
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
    blocks = Adapt.adapt(to, bank.blocks)
    return BlockBank{Representation, typeof(blocks)}(blocks)
end
Adapt.@adapt_structure AuxiliaryState
Adapt.@adapt_structure RuntimeWorkspaces
Adapt.@adapt_structure DescriptorLaunch
Adapt.@adapt_structure ParameterDomainConstraint
Adapt.@adapt_structure ConstraintGroup

function adapt_descriptor_launch(to, group::DescriptorGroup)
    launch = descriptor_launch(group)
    adapted_descriptors = map(
        descriptor -> descriptor_adapt(to, descriptor),
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

@kernel function descriptor_group_probe_kernel!(
        output,
        launch,
        context,
    )
    index = @index(Global, Linear)
    if index <= length(launch.instances)
        descriptor = @inbounds launch.instances[index]
        @inbounds output[index] = descriptor_role(descriptor) isa HamiltonianRole ?
                                  descriptor_evaluate_energy(descriptor, context) :
                                  descriptor_evaluate_proposal(descriptor, context)
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
            value = evaluate_static(constraint.evaluator, context)
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
    ) where {D}
    for descriptor in instances
        descriptor_role(descriptor) isa HamiltonianRole || continue
        source = Int(descriptor_source_handle(descriptor))
        @inbounds contributions[source] = descriptor_evaluate_proposal(
            descriptor, context
        )
    end
    return contributions
end

@inline _evaluate_hamiltonian_groups!(
    contributions, ::Tuple{}, context
) = contributions
@inline function _evaluate_hamiltonian_groups!(
        contributions,
        groups::Tuple,
        context,
    )
    group = first(groups)
    _evaluate_hamiltonian_instances!(
        contributions, group.launch.instances, context
    )
    return _evaluate_hamiltonian_groups!(
        contributions, Base.tail(groups), context
    )
end

@inline function evaluate_hamiltonian_contributions!(
        contributions,
        plan::DescriptorExecutionPlan,
        context,
    )
    length(contributions) >= length(plan.source_table) || throw(
        ArgumentError("Hamiltonian contribution storage is too small"),
    )
    fill!(contributions, zero(eltype(contributions)))
    return _evaluate_hamiltonian_groups!(
        contributions, plan.groups, context
    )
end

"""Fold source-indexed Hamiltonian contributions in canonical source order."""
@inline function fold_hamiltonian_contributions(
        plan::DescriptorExecutionPlan,
        contributions,
    )
    length(contributions) >= length(plan.source_table) || throw(
        ArgumentError("Hamiltonian contribution storage is too small"),
    )
    total = zero(eltype(contributions))
    for source in eachindex(plan.source_table)
        total += @inbounds contributions[source]
    end
    return total
end

function descriptor_plan_report(plan::DescriptorExecutionPlan)
    return (
        occurrences = Int(plan.occurrence_count),
        groups = length(plan.groups),
        instances = Tuple(
            length(group.launch.instances) for group in plan.groups
        ),
        evaluator_nodes = Tuple(
            descriptor_evaluator_node_count(
                first(group.launch.instances)
            )
            for group in plan.groups
        ),
        descriptor_inspections = Tuple(
            [
                merge(
                    (
                        qualified_source = plan.source_table[
                            descriptor_source_handle(descriptor)
                        ],
                    ),
                    descriptor_inspection(descriptor),
                )
                for descriptor in group.launch.instances
            ]
            for group in plan.groups
        ),
        specializations = length(plan.groups),
        state_blocks = length(plan.state_layout.schemas),
        workspaces = length(plan.workspace_layout.schemas),
        validation_groups = length(plan.constraints),
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

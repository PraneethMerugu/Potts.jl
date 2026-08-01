# Generic staged-effect descriptors and their preallocated runtime buffers.

abstract type AbstractCompiledStage end
struct AcceptedCopyStage <: AbstractCompiledStage end
struct AfterMCSStage <: AbstractCompiledStage end

abstract type AbstractStageSiteSelector end
struct ProposalTargetStageSite <: AbstractStageSiteSelector end
struct IterationStageSite <: AbstractStageSiteSelector end

"""Read one declared state block at the site bound by a compiled stage."""
struct BoundStateValueOperation{S <: AbstractStageSiteSelector} <:
        AbstractContextualOperation end

function operation_callable(
        ::Val{:proposal_bound_state_value},
        version::VersionNumber,
    )
    version == v"1.0.0" || throw(ArgumentError(
        "unsupported proposal-bound-state operation version $version"
    ))
    return BoundStateValueOperation{ProposalTargetStageSite}()
end

function operation_callable(
        ::Val{:iteration_bound_state_value},
        version::VersionNumber,
    )
    version == v"1.0.0" || throw(ArgumentError(
        "unsupported iteration-bound-state operation version $version"
    ))
    return BoundStateValueOperation{IterationStageSite}()
end

function stage_site end

@inline function (operation::BoundStateValueOperation{S})(
        arguments::Tuple, context
    ) where {S <: AbstractStageSiteSelector}
    handle = only(arguments)
    return state_value(context, handle, stage_site(S(), context))
end

operation_context_supported(
    ::BoundStateValueOperation{ProposalTargetStageSite},
    ::Type{AbstractProposalEvaluationContext},
) = true

operation_context_supported(
    ::BoundStateValueOperation{IterationStageSite},
    ::Type{AbstractSiteStageEvaluationContext},
) = true

abstract type AbstractCompiledEffect end

"""Assign a scalar value to one site in a declared auxiliary-state block."""
struct SiteAssignmentEffect{H <: StateHandle} <: AbstractCompiledEffect
    target::H
end

"""Repeat a synchronous site assignment through a fixed number of substeps."""
struct IteratedSiteAssignmentEffect{H <: StateHandle} <:
        AbstractCompiledEffect
    target::H
    iterations::Int32
    function IteratedSiteAssignmentEffect(
            target::H, iterations::Integer
        ) where {H <: StateHandle}
        iterations > 0 || throw(ArgumentError(
            "an iterated site assignment requires a positive iteration count"
        ))
        return new{H}(target, Int32(iterations))
    end
end

"""Shift a dense state block along one axis and append another state block."""
struct ShiftAppendEffect{
        T <: StateHandle,
        S <: StateHandle,
    } <: AbstractCompiledEffect
    target::T
    source::S
    axis::Int32
    function ShiftAppendEffect(
            target::T,
            source::S,
            axis::Integer,
        ) where {T <: StateHandle, S <: StateHandle}
        axis > 0 || throw(ArgumentError(
            "a shift-append effect axis must be positive"
        ))
        return new{T, S}(target, source, Int32(axis))
    end
end

"""Create one bounded relationship record from compiled endpoint and payload evaluators."""
struct RelationshipCreateEffect{
        A <: StaticEvaluator,
        B <: StaticEvaluator,
        P <: Tuple,
    } <: AbstractCompiledEffect
    relationship_slot::Int32
    endpoint_a::A
    endpoint_b::B
    payload::P
    priority::Int32
end

function RelationshipCreateEffect(
        relationship_slot::Integer,
        endpoint_a::A,
        endpoint_b::B,
        payload::P,
        priority::Integer = 0,
    ) where {A <: StaticEvaluator, B <: StaticEvaluator, P <: Tuple}
    relationship_slot > 0 || throw(ArgumentError(
        "a relationship-create effect requires a positive storage slot"
    ))
    all(evaluator -> evaluator isa StaticEvaluator, payload) ||
        throw(ArgumentError(
            "relationship payload entries must be compiled evaluators"
        ))
    return RelationshipCreateEffect{A, B, P}(
        Int32(relationship_slot),
        endpoint_a,
        endpoint_b,
        payload,
        Int32(priority),
    )
end


"""Remove records selected over one bounded relationship store after an MCS."""
struct RelationshipRemoveEffect <: AbstractCompiledEffect
    relationship_slot::Int32
    function RelationshipRemoveEffect(relationship_slot::Integer)
        relationship_slot > 0 || throw(ArgumentError(
            "a relationship-remove effect requires a positive storage slot"
        ))
        new(Int32(relationship_slot))
    end
end

"""Retune one bounded relationship payload from compiled evaluators."""
struct RelationshipRetuneEffect{P <: Tuple} <: AbstractCompiledEffect
    relationship_slot::Int32
    payload::P
    function RelationshipRetuneEffect(
            relationship_slot::Integer,
            payload::P,
        ) where {P <: Tuple}
        relationship_slot > 0 || throw(ArgumentError(
            "a relationship-retune effect requires a positive storage slot"
        ))
        all(evaluator -> evaluator isa StaticEvaluator, payload) || throw(
            ArgumentError(
                "relationship-retune payload entries must be compiled evaluators"
            )
        )
        new{P}(Int32(relationship_slot), payload)
    end
end


function stage_effect_buffered end
stage_effect_buffered(::AbstractCompiledEffect) = false
stage_effect_buffered(::SiteAssignmentEffect) = true
stage_effect_buffered(::IteratedSiteAssignmentEffect) = true
stage_effect_buffered(::RelationshipCreateEffect) = true
stage_effect_buffered(::RelationshipRemoveEffect) = true
stage_effect_buffered(::RelationshipRetuneEffect) = true

struct CompiledStageDescriptor{
        C <: StaticEvaluator,
        V <: StaticEvaluator,
        E <: AbstractCompiledEffect,
        P <: AbstractCompiledStage,
        A <: ResourceAccess,
        S,
    }
    condition::C
    value::V
    effect::E
    stage::P
    access::A
    support::S
    source_handle::Int32
    buffer_slot::Int32
end

function CompiledStageDescriptor(
        condition::C,
        value::V,
        effect::E,
        stage::P,
        access::A,
        support::S,
        source_handle::Integer,
        buffer_slot::Integer,
    ) where {
        C <: StaticEvaluator,
        V <: StaticEvaluator,
        E <: AbstractCompiledEffect,
        P <: AbstractCompiledStage,
        A <: ResourceAccess,
        S,
    }
    source_handle > 0 || throw(ArgumentError(
        "a stage descriptor source handle must be positive"
    ))
    buffer_slot >= 0 || throw(ArgumentError(
        "a stage descriptor buffer slot cannot be negative"
    ))
    stage_effect_buffered(effect) == (buffer_slot > 0) ||
        throw(ArgumentError(
            "buffered stage effects require a positive slot and commit-only " *
            "effects require slot zero"
        ))
    return CompiledStageDescriptor{C, V, E, P, A, S}(
        condition,
        value,
        effect,
        stage,
        access,
        support,
        Int32(source_handle),
        Int32(buffer_slot),
    )
end

descriptor_state_requirements(descriptor::CompiledStageDescriptor) =
    descriptor.access.reads
descriptor_workspace_requirements(::CompiledStageDescriptor) = ()
descriptor_resource_access(descriptor::CompiledStageDescriptor) = descriptor.access
descriptor_stage(descriptor::CompiledStageDescriptor) = descriptor.stage
descriptor_role(descriptor::CompiledStageDescriptor) = descriptor.effect
descriptor_dependencies(::CompiledStageDescriptor) = ()
descriptor_support(descriptor::CompiledStageDescriptor) = descriptor.support
descriptor_source_handle(descriptor::CompiledStageDescriptor) =
    descriptor.source_handle
descriptor_checkpoint_policy(::CompiledStageDescriptor) =
    :reconstruct_from_executable
descriptor_checkpoint_encode(::CompiledStageDescriptor) = nothing
descriptor_checkpoint_reconstruct(
    descriptor::CompiledStageDescriptor, ::Nothing
) = descriptor
descriptor_evaluator_node_count(descriptor::CompiledStageDescriptor) =
    evaluator_node_count(descriptor.condition) + evaluator_node_count(descriptor.value)
descriptor_inspection(descriptor::CompiledStageDescriptor) = (
    source_handle = descriptor.source_handle,
    buffer_slot = descriptor.buffer_slot,
    stage = nameof(typeof(descriptor.stage)),
    effect = nameof(typeof(descriptor.effect)),
    condition = nameof(typeof(descriptor.condition.expression)),
    value = nameof(typeof(descriptor.value.expression)),
)

struct StageDescriptorGroup{D, V <: AbstractVector{D}}
    instances::V
end

struct StageExecutionPlan{A <: Tuple, M <: Tuple}
    accepted_copy::A
    after_mcs::M
    accepted_count::Int32
    after_mcs_count::Int32
    fingerprint::String
end

function StageExecutionPlan(
        accepted_copy::A,
        after_mcs::M,
        accepted_count::Integer,
        after_mcs_count::Integer,
        fingerprint,
    ) where {A <: Tuple, M <: Tuple}
    accepted_count >= 0 || throw(ArgumentError(
        "accepted-copy descriptor count cannot be negative"
    ))
    after_mcs_count >= 0 || throw(ArgumentError(
        "after-MCS descriptor count cannot be negative"
    ))
    actual_accepted = sum(
        length(group.instances) for group in accepted_copy; init = 0
    )
    actual_accepted == accepted_count || throw(ArgumentError(
        "accepted-copy descriptor count does not match its groups"
    ))
    return StageExecutionPlan{A, M}(
        accepted_copy,
        after_mcs,
        Int32(accepted_count),
        Int32(after_mcs_count),
        String(fingerprint),
    )
end

StageExecutionPlan() = StageExecutionPlan((), (), 0, 0, "empty-stage-plan-v1")

struct StageEvaluation{T <: AbstractFloat}
    enabled::Bool
    value::T
end

mutable struct StageRuntimeBuffers{T <: AbstractFloat, N, R}
    accepted_copy::Vector{StageEvaluation{T}}
    after_mcs::Vector{Array{T, N}}
    relationship_transactions::R
end

function allocate_stage_runtime_buffers(
        plan::StageExecutionPlan,
        ::Type{T},
        shape::NTuple{N, Int},
        relationships::RelationshipStorage = RelationshipStorage(()),
        ;
        accepted_batch_bound::Integer = 1,
    ) where {T <: AbstractFloat, N}
    accepted_batch_bound > 0 || throw(ArgumentError(
        "accepted-copy batch bound must be positive"
    ))
    accepted = fill(
        StageEvaluation(false, zero(T)), Int(plan.accepted_count)
    )
    after = [zeros(T, shape) for _ in 1:Int(plan.after_mcs_count)]
    transactions = Any[]
    for store_slot in eachindex(relationships)
        accepted_bound = sum((
            1
            for group in plan.accepted_copy
            for descriptor in group.instances
            if descriptor.effect isa RelationshipCreateEffect &&
               descriptor.effect.relationship_slot == store_slot
        ); init = 0)
        after_bound = sum((
            length(relationships[store_slot].active)
            for group in plan.after_mcs
            for descriptor in group.instances
            if descriptor.effect isa Union{
                RelationshipRemoveEffect, RelationshipRetuneEffect,
            } &&
               descriptor.effect.relationship_slot == store_slot
        ); init = 0)
        push!(transactions, RelationshipTransactionBuffer(
            relationships[store_slot],
            max(accepted_bound * accepted_batch_bound, after_bound),
        ))
    end
    relationship_transactions = RelationshipStorage(transactions)
    return StageRuntimeBuffers{T, N, typeof(relationship_transactions)}(
        accepted, after, relationship_transactions
    )
end

Adapt.@adapt_structure BoundStateValueOperation
Adapt.@adapt_structure SiteAssignmentEffect
Adapt.@adapt_structure IteratedSiteAssignmentEffect
Adapt.@adapt_structure ShiftAppendEffect
Adapt.@adapt_structure RelationshipCreateEffect
Adapt.@adapt_structure RelationshipRemoveEffect
Adapt.@adapt_structure RelationshipRetuneEffect
Adapt.@adapt_structure CompiledStageDescriptor
Adapt.@adapt_structure StageDescriptorGroup
Adapt.@adapt_structure StageExecutionPlan

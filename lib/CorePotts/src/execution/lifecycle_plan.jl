# Immutable, mechanism-neutral cell-lifecycle transaction descriptors.

@enum LifecycleDomainCode::UInt8 begin
    ModelLifecycleDomain = 0x01
    CellKindLifecycleDomain = 0x02
end

@enum LifecycleCadenceCode::UInt8 begin
    EveryMCSLifecycleCadence = 0x01
    AtMCSLifecycleCadence = 0x02
    PeriodicLifecycleCadence = 0x03
end

@enum LifecycleEffectCode::UInt8 begin
    CreateCellLifecycleEffect = 0x01
    RemoveCellLifecycleEffect = 0x02
    RetireCellLifecycleEffect = 0x03
    TransitionCellLifecycleEffect = 0x04
    DivideCellLifecycleEffect = 0x05
end

@enum LifecycleInadmissibilityDisposition::UInt8 begin
    FilterLifecycleInadmissible = 0x01
    ErrorLifecycleInadmissible = 0x02
end

@enum LifecycleConflictCode::UInt8 begin
    RejectLifecycleConflicts = 0x01
    StablePriorityLifecycleConflicts = 0x02
end

@enum LifecyclePlacementCode::UInt8 begin
    NoLifecyclePlacement = 0x00
    SeedAtLifecyclePlacement = 0x01
    SeedStencilLifecyclePlacement = 0x02
    ExternalLifecyclePlacement = 0x03
end

@enum LifecyclePartitionCode::UInt8 begin
    NoLifecyclePartition = 0x00
    RandomPlaneLifecyclePartition = 0x01
    PrincipalMajorLifecyclePartition = 0x02
    PrincipalMinorLifecyclePartition = 0x03
    SpecifiedNormalLifecyclePartition = 0x04
    ExternalLifecyclePartition = 0x05
end

@enum LifecycleSideCode::UInt8 begin
    CanonicalLifecycleSide = 0x01
    StableRandomLifecycleSide = 0x02
end

@enum LifecycleStateAction::UInt8 begin
    InitializeLifecycleState = 0x01
    UnsupportedLifecycleState = 0x02
    RetireToLifecycleState = 0x03
    PreserveLifecycleState = 0x04
    ResetLifecycleState = 0x05
    TransformLifecycleState = 0x06
    CopyDaughtersLifecycleState = 0x07
    PreserveParentResetDaughterLifecycleState = 0x08
    ResetBothLifecycleState = 0x09
    SplitConservativelyLifecycleState = 0x0a
    TransformDaughtersLifecycleState = 0x0b
    RedrawDaughtersLifecycleState = 0x0c
end

@enum LifecycleRoundingCode::UInt8 begin
    ExactLifecycleRounding = 0x00
    FloorLifecycleRounding = 0x01
    CeilLifecycleRounding = 0x02
    NearestLifecycleRounding = 0x03
end

@enum LifecycleRelationshipAction::UInt8 begin
    RejectWhileLinkedLifecycleRelationship = 0x01
    RemoveIncidentLifecycleRelationship = 0x02
    PreserveCompatibleLifecycleRelationship = 0x03
    RemoveIncompatibleLifecycleRelationship = 0x04
    RejectIncompatibleLifecycleRelationship = 0x05
end

@enum LifecycleOwnershipAction::UInt8 begin
    PreserveLifecycleOwnershipState = 0x01
    ClearLifecycleOwnershipState = 0x02
end

"""Value-level reference into representation-banked lifecycle evaluators."""
struct LifecycleEvaluatorSlot
    bank::Int32
    slot::Int32
end

struct LifecycleEvaluatorStorage{B <: Tuple, S <: AbstractVector{LifecycleEvaluatorSlot}}
    banks::B
    slots::S
end

function LifecycleEvaluatorStorage(values)
    entries = collect(values)
    representations = unique!(DataType[typeof(value) for value in entries])
    sort!(representations; by = string)
    bank_for = Dict(
        representation => index
        for (index, representation) in enumerate(representations)
    )
    banks = Any[Vector{representation}() for representation in representations]
    slots = Vector{LifecycleEvaluatorSlot}(undef, length(entries))
    for (index, value) in enumerate(entries)
        value isa StaticEvaluator || throw(ArgumentError(
            "lifecycle evaluator storage accepts only StaticEvaluator values"
        ))
        bank = bank_for[typeof(value)]
        push!(banks[bank], value)
        slots[index] = LifecycleEvaluatorSlot(bank, length(banks[bank]))
    end
    return LifecycleEvaluatorStorage(Tuple(banks), slots)
end

Base.length(storage::LifecycleEvaluatorStorage) = length(storage.slots)

@generated function _evaluate_lifecycle_bank(
        banks::B,
        bank::Int32,
        slot::Int32,
        context,
    ) where {B <: Tuple}
    branches = Expr(:block)
    for index in 1:fieldcount(B)
        push!(branches.args, quote
            if bank == $(Int32(index))
                evaluator = @inbounds getfield(banks, $index)[Int(slot)]
                return _compiled_evaluate_static(evaluator, context)
            end
        end)
    end
    push!(branches.args, :(throw(ArgumentError(
        "lifecycle evaluator slot is outside compiled storage"
    ))))
    return branches
end

@inline function evaluate_lifecycle(
        storage::LifecycleEvaluatorStorage,
        index::Integer,
        context,
    )
    @boundscheck checkbounds(storage.slots, index)
    location = @inbounds storage.slots[Int(index)]
    return _evaluate_lifecycle_bank(
        storage.banks, location.bank, location.slot, context
    )
end

"""One state-policy rule; state identity remains in the value-level handle."""
struct LifecycleStateRule{H <: StateHandle, T <: AbstractFloat}
    handle::H
    action::LifecycleStateAction
    evaluator_a::Int32
    evaluator_b::Int32
    evaluator_c::Int32
    evaluator_d::Int32
    fraction::T
    rounding::LifecycleRoundingCode
    parent_distribution::UInt8
    daughter_distribution::UInt8
    parent_draw::UInt16
    daughter_draw::UInt16
end

struct LifecycleStateRuleSlot
    bank::Int32
    slot::Int32
end

struct LifecycleStateRuleStorage{B <: Tuple, S <: AbstractVector{LifecycleStateRuleSlot}}
    banks::B
    slots::S
end

function LifecycleStateRuleStorage(values)
    entries = collect(values)
    representations = unique!(DataType[typeof(value) for value in entries])
    sort!(representations; by = string)
    bank_for = Dict(
        representation => index
        for (index, representation) in enumerate(representations)
    )
    banks = Any[Vector{representation}() for representation in representations]
    slots = Vector{LifecycleStateRuleSlot}(undef, length(entries))
    for (index, value) in enumerate(entries)
        value isa LifecycleStateRule || throw(ArgumentError(
            "lifecycle state-rule storage accepts only LifecycleStateRule values"
        ))
        bank = bank_for[typeof(value)]
        push!(banks[bank], value)
        slots[index] = LifecycleStateRuleSlot(bank, length(banks[bank]))
    end
    return LifecycleStateRuleStorage(Tuple(banks), slots)
end

Base.length(storage::LifecycleStateRuleStorage) = length(storage.slots)

@generated function _call_lifecycle_state_rule_bank(
        operation::F,
        banks::B,
        bank::Int32,
        slot::Int32,
        arguments::A,
    ) where {F, B <: Tuple, A <: Tuple}
    branches = Expr(:block)
    for index in 1:fieldcount(B)
        push!(branches.args, quote
            if bank == $(Int32(index))
                rule = @inbounds getfield(banks, $index)[Int(slot)]
                return operation(rule, arguments...)
            end
        end)
    end
    push!(branches.args, :(throw(ArgumentError(
        "lifecycle state-rule slot is outside compiled storage"
    ))))
    return branches
end

@inline function call_lifecycle_state_rule(
        operation,
        storage::LifecycleStateRuleStorage,
        index::Integer,
        arguments...,
    )
    @boundscheck checkbounds(storage.slots, index)
    location = @inbounds storage.slots[Int(index)]
    return _call_lifecycle_state_rule_bank(
        operation,
        storage.banks,
        location.bank,
        location.slot,
        arguments,
    )
end

struct LifecycleRelationshipRule
    relationship_slot::Int32
    action::LifecycleRelationshipAction
    kind_a::Int16
    kind_b::Int16
end

struct LifecycleOwnershipRule{H <: StateHandle}
    handle::H
    action::LifecycleOwnershipAction
end

"""
One value-level lifecycle descriptor. Arbitrary statement names and occurrence
counts do not enter its type; only lattice/scalar structure specializes.
"""
struct LifecycleDescriptor{N, T <: AbstractFloat}
    source_handle::Int32
    source_identity::UInt64
    action_identity::UInt64
    domain::LifecycleDomainCode
    domain_kind::Int16
    trigger_evaluator::Int32
    cadence::LifecycleCadenceCode
    cadence_value::Int32
    effect::LifecycleEffectCode
    priority::Int32
    on_inadmissible::LifecycleInadmissibilityDisposition
    destination_kind::Int16
    replacement_medium::Int16
    placement::LifecyclePlacementCode
    placement_evaluator::Int32
    stencil_offset::Int32
    stencil_count::Int32
    relation_slot::Int32
    partition::LifecyclePartitionCode
    partition_evaluator::Int32
    point_from_centroid::Bool
    point::NTuple{N, T}
    normal::NTuple{N, T}
    side::LifecycleSideCode
    geometry_draw::UInt16
    side_draw::UInt16
    parent_kind::Int16
    daughter_kind::Int16
    state_rule_offset::Int32
    state_rule_count::Int32
    relationship_rule_offset::Int32
    relationship_rule_count::Int32
    compiler_synthesized::Bool
end

struct LifecycleExecutionPlan{
        N,
        T <: AbstractFloat,
        D <: AbstractVector{LifecycleDescriptor{N, T}},
        E <: LifecycleEvaluatorStorage,
        S <: LifecycleStateRuleStorage,
        RR <: AbstractVector{LifecycleRelationshipRule},
        O <: Tuple,
        SO <: AbstractVector{<:NTuple{N, Int16}},
        R <: AbstractVector,
        F <: AbstractVector{Bool},
    } <: AbstractLifecycleExecutionPlan
    descriptors::D
    evaluators::E
    state_rules::S
    relationship_rules::RR
    ownership_rules::O
    stencil_offsets::SO
    relations::R
    conflict_policy::LifecycleConflictCode
    cell_capacity::Int32
    maximum_requests::Int32
    maximum_placement_sites::Int32
    forbid_extinction::F
    fingerprint::String
end

function LifecycleExecutionPlan(
        descriptors::D,
        evaluators,
        state_rules,
        relationship_rules::RR,
        ownership_rules::Tuple,
        stencil_offsets::SO,
        relations::R,
        conflict_policy::LifecycleConflictCode,
        cell_capacity::Integer,
        maximum_requests::Integer,
        maximum_placement_sites::Integer,
        forbid_extinction::F,
        fingerprint::AbstractString,
    ) where {
        N,
        T <: AbstractFloat,
        D <: AbstractVector{LifecycleDescriptor{N, T}},
        RR <: AbstractVector{LifecycleRelationshipRule},
        SO <: AbstractVector{<:NTuple{N, Int16}},
        R <: AbstractVector,
        F <: AbstractVector{Bool},
    }
    cell_capacity > 0 || throw(ArgumentError(
        "lifecycle cell capacity must be positive"
    ))
    maximum_requests >= 0 || throw(ArgumentError(
        "lifecycle request bound cannot be negative"
    ))
    maximum_requests <= typemax(Int32) || throw(ArgumentError(
        "lifecycle request bound exceeds Int32"
    ))
    maximum_placement_sites > 0 || throw(ArgumentError(
        "lifecycle placement-site bound must be positive"
    ))
    maximum_placement_sites <= typemax(Int32) || throw(ArgumentError(
        "lifecycle placement-site bound exceeds Int32"
    ))
    length(forbid_extinction) > 0 || throw(ArgumentError(
        "lifecycle extinction table cannot be empty"
    ))
    return LifecycleExecutionPlan{
        N,
        T,
        D,
        typeof(evaluators),
        typeof(state_rules),
        RR,
        typeof(ownership_rules),
        SO,
        R,
        F,
    }(
        descriptors,
        evaluators,
        state_rules,
        relationship_rules,
        ownership_rules,
        stencil_offsets,
        relations,
        conflict_policy,
        Int32(cell_capacity),
        Int32(maximum_requests),
        Int32(maximum_placement_sites),
        forbid_extinction,
        String(fingerprint),
    )
end

function lifecycle_plan_report(plan::LifecycleExecutionPlan)
    return (
        descriptors = length(plan.descriptors),
        evaluators = length(plan.evaluators),
        state_rules = length(plan.state_rules),
        relationship_rules = length(plan.relationship_rules),
        ownership_rules = length(plan.ownership_rules),
        cell_capacity = plan.cell_capacity,
        maximum_requests = plan.maximum_requests,
        maximum_placement_sites = plan.maximum_placement_sites,
        conflict_policy = Symbol(string(plan.conflict_policy)),
        fingerprint = plan.fingerprint,
    )
end

lifecycle_plan_report(::NoLifecycleExecutionPlan) = (
    descriptors = 0,
    evaluators = 0,
    state_rules = 0,
    relationship_rules = 0,
    ownership_rules = 0,
    cell_capacity = 0,
    maximum_requests = 0,
    maximum_placement_sites = 0,
    conflict_policy = :none,
    fingerprint = "none",
)

"""Read a cell-owned state value at the lifecycle anchor."""
struct LifecycleBoundStateValueOperation <: AbstractContextualOperation end

function operation_callable(
        ::Val{:lifecycle_bound_state_value}, version::VersionNumber
    )
    version == v"1.0.0" || throw(ArgumentError(
        "unsupported lifecycle-bound-state operation version $version"
    ))
    return LifecycleBoundStateValueOperation()
end

function lifecycle_anchor end

@inline function (operation::LifecycleBoundStateValueOperation)(
        arguments::Tuple, context
    )
    return state_value(context, only(arguments), lifecycle_anchor(context))
end

for context in (
        AbstractLifecycleTriggerEvaluationContext,
        AbstractLifecyclePlacementEvaluationContext,
        AbstractLifecyclePartitionEvaluationContext,
        AbstractLifecycleStateTransformEvaluationContext,
    )
    @eval operation_context_supported(
        ::LifecycleBoundStateValueOperation,
        ::Type{$context},
    ) = true
    @eval operation_context_supported(
        ::ContextOperation{:energy_anchor_cell},
        ::Type{$context},
    ) = true
end

Adapt.@adapt_structure LifecycleEvaluatorSlot
Adapt.@adapt_structure LifecycleEvaluatorStorage
Adapt.@adapt_structure LifecycleStateRule
Adapt.@adapt_structure LifecycleStateRuleSlot
Adapt.@adapt_structure LifecycleStateRuleStorage
Adapt.@adapt_structure LifecycleRelationshipRule
Adapt.@adapt_structure LifecycleOwnershipRule
Adapt.@adapt_structure LifecycleDescriptor
Adapt.@adapt_structure LifecycleExecutionPlan
Adapt.@adapt_structure NoLifecycleExecutionPlan
Adapt.@adapt_structure LifecycleBoundStateValueOperation

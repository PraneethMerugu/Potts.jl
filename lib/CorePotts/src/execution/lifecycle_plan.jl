# Immutable, mechanism-neutral cell-lifecycle transaction descriptors.

"""Scientific domain addressed by a lifecycle descriptor."""
@enum LifecycleDomainCode::UInt8 begin
    ModelLifecycleDomain = 0x01
    CellKindLifecycleDomain = 0x02
end
@doc "Apply one lifecycle descriptor to the model domain." ModelLifecycleDomain
@doc "Apply one lifecycle descriptor to a selected cell-kind domain." CellKindLifecycleDomain

"""Cadence at which a lifecycle descriptor becomes due."""
@enum LifecycleCadenceCode::UInt8 begin
    EveryMCSLifecycleCadence = 0x01
    AtMCSLifecycleCadence = 0x02
    PeriodicLifecycleCadence = 0x03
end
@doc "Run at every completed MCS." EveryMCSLifecycleCadence
@doc "Run at one specified MCS." AtMCSLifecycleCadence
@doc "Run at a fixed positive MCS cadence." PeriodicLifecycleCadence

"""Core-owned scientific lifecycle effect."""
@enum LifecycleEffectCode::UInt8 begin
    CreateCellLifecycleEffect = 0x01
    RemoveCellLifecycleEffect = 0x02
    RetireCellLifecycleEffect = 0x03
    TransitionCellLifecycleEffect = 0x04
    DivideCellLifecycleEffect = 0x05
end
@doc "Create a new finite cell." CreateCellLifecycleEffect
@doc "Remove a finite cell immediately." RemoveCellLifecycleEffect
@doc "Retire a finite cell through retirement semantics." RetireCellLifecycleEffect
@doc "Transition a finite cell to another kind." TransitionCellLifecycleEffect
@doc "Divide one finite parent into parent and daughter outcomes." DivideCellLifecycleEffect

@inline _lifecycle_effect_bit(effect::LifecycleEffectCode) =
    UInt8(1) << (UInt8(effect) - UInt8(1))

"""Policy for a lifecycle request that is scientifically inadmissible."""
@enum LifecycleInadmissibilityDisposition::UInt8 begin
    FilterLifecycleInadmissible = 0x01
    ErrorLifecycleInadmissible = 0x02
end
@doc "Filter an inadmissible lifecycle request." FilterLifecycleInadmissible
@doc "Fail the lifecycle transaction on an inadmissible request." ErrorLifecycleInadmissible

"""Policy resolving conflicts among lifecycle requests."""
@enum LifecycleConflictCode::UInt8 begin
    RejectLifecycleConflicts = 0x01
    StablePriorityLifecycleConflicts = 0x02
end
@doc "Reject conflicting lifecycle requests." RejectLifecycleConflicts
@doc "Select conflicts by stable priority and semantic identity." StablePriorityLifecycleConflicts

"""Placement policy for lifecycle effects that require lattice sites."""
@enum LifecyclePlacementCode::UInt8 begin
    NoLifecyclePlacement = 0x00
    SeedAtLifecyclePlacement = 0x01
    SeedStencilLifecyclePlacement = 0x02
    ExternalLifecyclePlacement = 0x03
end
@doc "Request no additional lifecycle placement." NoLifecyclePlacement
@doc "Place at one seed site." SeedAtLifecyclePlacement
@doc "Place over a bounded seed stencil." SeedStencilLifecyclePlacement
@doc "Delegate placement calculation to a contextual evaluator." ExternalLifecyclePlacement

"""Geometric partition policy for cell division."""
@enum LifecyclePartitionCode::UInt8 begin
    NoLifecyclePartition = 0x00
    RandomPlaneLifecyclePartition = 0x01
    PrincipalMajorLifecyclePartition = 0x02
    PrincipalMinorLifecyclePartition = 0x03
    SpecifiedNormalLifecyclePartition = 0x04
    ExternalLifecyclePartition = 0x05
end
@doc "Apply no division partition." NoLifecyclePartition
@doc "Partition by a deterministic semantic-random plane." RandomPlaneLifecyclePartition
@doc "Partition along the principal major axis." PrincipalMajorLifecyclePartition
@doc "Partition along the principal minor axis." PrincipalMinorLifecyclePartition
@doc "Partition along an explicitly evaluated normal." SpecifiedNormalLifecyclePartition
@doc "Delegate partitioning to a contextual evaluator." ExternalLifecyclePartition

"""Side-selection policy for an oriented lifecycle partition."""
@enum LifecycleSideCode::UInt8 begin
    CanonicalLifecycleSide = 0x01
    StableRandomLifecycleSide = 0x02
end
@doc "Use the canonical side of an oriented partition." CanonicalLifecycleSide
@doc "Choose the side by stable semantic randomness." StableRandomLifecycleSide

@inline function _lifecycle_division_variant_bit(
        partition::LifecyclePartitionCode, side::LifecycleSideCode
    )
    partition === NoLifecyclePartition && return UInt16(0)
    partition_index = UInt16(partition) - UInt16(RandomPlaneLifecyclePartition)
    side_index = UInt16(side) - UInt16(CanonicalLifecycleSide)
    return UInt16(1) << (partition_index * UInt16(2) + side_index)
end

"""Transaction action applied to one lifecycle-managed state block."""
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
@doc "Initialize destination state." InitializeLifecycleState
@doc "Declare the lifecycle effect unsupported for this state." UnsupportedLifecycleState
@doc "Write the configured retirement value." RetireToLifecycleState
@doc "Preserve source state." PreserveLifecycleState
@doc "Reset destination state." ResetLifecycleState
@doc "Evaluate one state transform." TransformLifecycleState
@doc "Copy source state to both daughters." CopyDaughtersLifecycleState
@doc "Preserve parent state and reset daughter state." PreserveParentResetDaughterLifecycleState
@doc "Reset both parent and daughter state." ResetBothLifecycleState
@doc "Split conserved state between parent and daughter." SplitConservativelyLifecycleState
@doc "Evaluate distinct daughter transforms." TransformDaughtersLifecycleState
@doc "Redraw both daughter states from initialization semantics." RedrawDaughtersLifecycleState

@inline _lifecycle_state_action_bit(action::LifecycleStateAction) =
    UInt16(1) << (UInt16(action) - UInt16(1))
@inline _lifecycle_state_action_value(::Val{Action}) where {Action} = Action
@inline _lifecycle_state_action_value(::Val{:initialize}) =
    InitializeLifecycleState
@inline _lifecycle_state_action_value(::Val{:retire_to}) =
    RetireToLifecycleState
@inline _lifecycle_state_action_value(::Val{:preserve}) =
    PreserveLifecycleState
@inline _lifecycle_state_action_value(::Val{:reset}) =
    ResetLifecycleState
@inline _lifecycle_state_action_value(::Val{:transform}) =
    TransformLifecycleState
@inline _lifecycle_state_action_value(::Val{:copy_daughters}) =
    CopyDaughtersLifecycleState
@inline _lifecycle_state_action_value(::Val{:preserve_parent_reset_daughter}) =
    PreserveParentResetDaughterLifecycleState
@inline _lifecycle_state_action_value(::Val{:reset_both}) =
    ResetBothLifecycleState
@inline _lifecycle_state_action_value(::Val{:split_conservatively}) =
    SplitConservativelyLifecycleState
@inline _lifecycle_state_action_value(::Val{:transform_daughters}) =
    TransformDaughtersLifecycleState
@inline _lifecycle_state_action_value(::Val{:redraw_daughters}) =
    RedrawDaughtersLifecycleState

"""Lifecycle participant whose state is addressed by a rule."""
@enum LifecycleStateRoleCode::UInt8 begin
    SourceLifecycleStateRole = 0x01
    DestinationLifecycleStateRole = 0x02
    ParentLifecycleStateRole = 0x03
    DaughterLifecycleStateRole = 0x04
end
@doc "Address the lifecycle source cell." SourceLifecycleStateRole
@doc "Address the lifecycle destination cell." DestinationLifecycleStateRole
@doc "Address the post-division parent." ParentLifecycleStateRole
@doc "Address the post-division daughter." DaughterLifecycleStateRole

"""Rounding policy for integer-valued lifecycle state transforms."""
@enum LifecycleRoundingCode::UInt8 begin
    ExactLifecycleRounding = 0x00
    FloorLifecycleRounding = 0x01
    CeilLifecycleRounding = 0x02
    NearestLifecycleRounding = 0x03
end
@doc "Require an exactly representable integer result." ExactLifecycleRounding
@doc "Round toward negative infinity." FloorLifecycleRounding
@doc "Round toward positive infinity." CeilLifecycleRounding
@doc "Round to the nearest integer." NearestLifecycleRounding

"""Action applied to relationships incident to a lifecycle participant."""
@enum LifecycleRelationshipAction::UInt8 begin
    RejectWhileLinkedLifecycleRelationship = 0x01
    RemoveIncidentLifecycleRelationship = 0x02
    PreserveCompatibleLifecycleRelationship = 0x03
    RemoveIncompatibleLifecycleRelationship = 0x04
    RejectIncompatibleLifecycleRelationship = 0x05
end
@doc "Reject the lifecycle request while matching relationships remain." RejectWhileLinkedLifecycleRelationship
@doc "Remove all matching incident relationships." RemoveIncidentLifecycleRelationship
@doc "Preserve relationships compatible with the resulting identities." PreserveCompatibleLifecycleRelationship
@doc "Remove relationships incompatible with the resulting identities." RemoveIncompatibleLifecycleRelationship
@doc "Reject when an incompatible relationship is encountered." RejectIncompatibleLifecycleRelationship

@inline _lifecycle_relationship_action_bit(
    action::LifecycleRelationshipAction
) = UInt8(1) << (UInt8(action) - UInt8(1))
@inline _lifecycle_relationship_action_value(::Val{:remove_incident}) =
    RemoveIncidentLifecycleRelationship
@inline _lifecycle_relationship_action_value(::Val{:remove_incompatible}) =
    RemoveIncompatibleLifecycleRelationship

"""Ownership-state action applied at lifecycle settlement."""
@enum LifecycleOwnershipAction::UInt8 begin
    PreserveLifecycleOwnershipState = 0x01
    ClearLifecycleOwnershipState = 0x02
end
@doc "Preserve ownership entries not otherwise changed by settlement." PreserveLifecycleOwnershipState
@doc "Clear ownership entries selected by settlement." ClearLifecycleOwnershipState

"""Closed result category for fixed-capacity lifecycle placement policies."""
abstract type AbstractLifecycleSiteSelection end

"""Fixed-capacity, allocation-free result of a lifecycle placement policy."""
struct LifecycleSiteSelection{M} <: AbstractLifecycleSiteSelection
    sites::NTuple{M, Int32}
    count::Int32
    function LifecycleSiteSelection(
            sites::NTuple{M, <:Integer}, count::Integer = M
        ) where {M}
        0 <= count <= M || throw(ArgumentError(
            "lifecycle site-selection count must lie in 0:$M"
        ))
        return new{M}(Int32.(sites), Int32(count))
    end
end

"""Value-level reference into representation-banked lifecycle evaluators."""
struct LifecycleEvaluatorSlot
    bank::Int32
    slot::Int32
end

"""One evaluator-representation bank admitted for exactly one lifecycle role."""
struct LifecycleEvaluatorBank{
        Role,
        E,
        A <: AbstractVector{E},
    } <: AbstractVector{E}
    values::A
end

function LifecycleEvaluatorBank(::Val{Role}, values::AbstractVector{E}) where {Role, E}
    Role in (:lifecycle_trigger, :lifecycle_placement, :lifecycle_partition,
        :lifecycle_state_transform) || throw(ArgumentError(
        "unsupported lifecycle evaluator role `$Role`"
    ))
    return LifecycleEvaluatorBank{Role, E, typeof(values)}(values)
end

Base.size(bank::LifecycleEvaluatorBank) = size(bank.values)
Base.length(bank::LifecycleEvaluatorBank) = length(bank.values)
Base.strides(bank::LifecycleEvaluatorBank) = strides(bank.values)
Base.getindex(bank::LifecycleEvaluatorBank, index::Int) = bank.values[index]
Base.IndexStyle(::Type{<:LifecycleEvaluatorBank}) = IndexLinear()
KernelAbstractions.get_backend(bank::LifecycleEvaluatorBank) =
    KernelAbstractions.get_backend(bank.values)

"""Representation-banked lifecycle evaluators and their ordered role slots."""
struct LifecycleEvaluatorStorage{B <: Tuple, S <: AbstractVector{LifecycleEvaluatorSlot}}
    banks::B
    slots::S
end

function LifecycleEvaluatorStorage(values, roles)
    entries = collect(values)
    entry_roles = collect(Symbol, roles)
    length(entries) == length(entry_roles) || throw(DimensionMismatch(
        "lifecycle evaluators and roles must have equal lengths"
    ))
    representations = unique!([
        (typeof(value), entry_roles[index])
        for (index, value) in enumerate(entries)
    ])
    sort!(representations; by = value -> (string(first(value)), string(last(value))))
    bank_for = Dict(
        representation => index
        for (index, representation) in enumerate(representations)
    )
    bank_values = Any[Vector{first(representation)}() for representation in representations]
    slots = Vector{LifecycleEvaluatorSlot}(undef, length(entries))
    for (index, value) in enumerate(entries)
        value isa StaticEvaluator || throw(ArgumentError(
            "lifecycle evaluator storage accepts only StaticEvaluator values"
        ))
        key = (typeof(value), entry_roles[index])
        bank = bank_for[key]
        push!(bank_values[bank], value)
        slots[index] = LifecycleEvaluatorSlot(bank, length(bank_values[bank]))
    end
    banks = Any[
        LifecycleEvaluatorBank(Val(last(representations[index])), values)
        for (index, values) in enumerate(bank_values)
    ]
    return LifecycleEvaluatorStorage(Tuple(banks), slots)
end

Base.length(storage::LifecycleEvaluatorStorage) = length(storage.slots)

@generated function _evaluate_lifecycle_bank(
        banks::B,
        bank::Int32,
        slot::Int32,
        context::C,
    ) where {B <: Tuple, C}
    branches = Expr(:block)
    for index in 1:fieldcount(B)
        bank_type = fieldtype(B, index)
        role = bank_type.parameters[1]
        admitted =
            role === :lifecycle_trigger ? C <: AbstractLifecycleTriggerEvaluationContext :
            role === :lifecycle_placement ? C <: AbstractLifecyclePlacementEvaluationContext :
            role === :lifecycle_partition ? C <: AbstractLifecyclePartitionEvaluationContext :
            role === :lifecycle_state_transform ? C <: AbstractLifecycleStateTransformEvaluationContext :
            false
        admitted || continue
        push!(branches.args, quote
            if bank == $(Int32(index))
                evaluator = @inbounds getfield(banks, $index).values[Int(slot)]
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
    source_identity::UInt64
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

"""Representation-banked lifecycle state rules and their ordered slots."""
struct LifecycleStateRuleStorage{B <: Tuple, S <: AbstractVector{LifecycleStateRuleSlot}}
    banks::B
    slots::S
    action_mask::UInt16
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
    action_mask = UInt16(0)
    for rule in entries
        action_mask |= _lifecycle_state_action_bit(rule.action)
    end
    return LifecycleStateRuleStorage(Tuple(banks), slots, action_mask)
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

@inline _lifecycle_state_rule_action(rule) = rule.action

"""Relationship-store action applied for selected lifecycle effects."""
struct LifecycleRelationshipRule
    relationship_slot::Int32
    action::LifecycleRelationshipAction
    kind_a::Int16
    kind_b::Int16
end

"""Ownership action and optional state handle for lifecycle settlement."""
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
    placement_maximum::Int32
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
    trigger_workspace_maximum::Int32
    placement_workspace_maximum::Int32
    partition_workspace_maximum::Int32
    state_workspace_maximum::Int32
    compiler_synthesized::Bool
end

"""Packed finite spatial relations used by lifecycle placement and partitioning."""
struct LifecycleRelationStorage{
        N,
        D <: AbstractVector{Int8},
        O <: AbstractVector{Int32},
    }
    data::D
    offsets::O
    counts::O
end

function LifecycleRelationStorage(relations, ::Val{N}) where {N}
    data = Int8[]
    offsets = Int32[]
    counts = Int32[]
    for relation in relations
        size(relation, 1) == N || throw(ArgumentError(
            "lifecycle relation dimensionality does not match the lattice"
        ))
        push!(offsets, Int32(length(data) + 1))
        push!(counts, Int32(size(relation, 2)))
        append!(data, vec(relation))
    end
    return LifecycleRelationStorage{N, typeof(data), typeof(offsets)}(
        data, offsets, counts
    )
end

struct LifecycleRelationView{N, D <: AbstractVector{Int8}} <:
       AbstractMatrix{Int8}
    data::D
    offset::Int32
    count::Int32
end

Base.size(view::LifecycleRelationView{N}) where {N} = (N, Int(view.count))
Base.IndexStyle(::Type{<:LifecycleRelationView}) = IndexCartesian()
@inline function Base.getindex(
        view::LifecycleRelationView{N}, dimension::Int, direction::Int
    ) where {N}
    @boundscheck checkbounds(view, dimension, direction)
    index = Int(view.offset) + (direction - 1) * N + dimension - 1
    return @inbounds view.data[index]
end

@inline function lifecycle_relation(
        storage::LifecycleRelationStorage{N}, slot::Integer
    ) where {N}
    @boundscheck checkbounds(storage.offsets, slot)
    return LifecycleRelationView{N, typeof(storage.data)}(
        storage.data,
        @inbounds(storage.offsets[slot]),
        @inbounds(storage.counts[slot]),
    )
end

"""Validated lifecycle descriptors, policies, evaluators, rules, and relations."""
struct LifecycleExecutionPlan{
        N,
        T <: AbstractFloat,
        D <: AbstractVector{LifecycleDescriptor{N, T}},
        E <: LifecycleEvaluatorStorage,
        S <: LifecycleStateRuleStorage,
        RR <: AbstractVector{LifecycleRelationshipRule},
        O <: Tuple,
        SO <: AbstractVector{<:NTuple{N, Int16}},
        R <: LifecycleRelationStorage{N},
        F <: Tuple{Vararg{Bool}},
    } <: AbstractLifecycleExecutionPlan
    descriptors::D
    evaluators::E
    state_rules::S
    relationship_rules::RR
    ownership_rules::O
    stencil_offsets::SO
    relations::R
    conflict_policy::LifecycleConflictCode
    effect_mask::UInt8
    division_variant_mask::UInt16
    relationship_action_mask::UInt8
    state_action_masks::NTuple{5, UInt16}
    cell_capacity::Int32
    maximum_requests::Int32
    maximum_placement_sites::Int32
    maximum_policy_workspace::Int32
    forbid_extinction::F
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
        maximum_policy_workspace::Integer,
        forbid_extinction::Union{
            AbstractVector{Bool}, Tuple{Vararg{Bool}}
        },
    ) where {
        N,
        T <: AbstractFloat,
        D <: AbstractVector{LifecycleDescriptor{N, T}},
        RR <: AbstractVector{LifecycleRelationshipRule},
        SO <: AbstractVector{<:NTuple{N, Int16}},
        R <: LifecycleRelationStorage{N},
    }
    cell_capacity > 0 || throw(ArgumentError(
        "lifecycle cell capacity must be positive"
    ))
    maximum_requests >= 0 || throw(ArgumentError(
        "lifecycle request bound cannot be negative"
    ))
    iszero(maximum_requests) && return NoLifecycleExecutionPlan()
    maximum_requests <= typemax(Int32) || throw(ArgumentError(
        "lifecycle request bound exceeds Int32"
    ))
    maximum_placement_sites > 0 || throw(ArgumentError(
        "lifecycle placement-site bound must be positive"
    ))
    maximum_placement_sites <= typemax(Int32) || throw(ArgumentError(
        "lifecycle placement-site bound exceeds Int32"
    ))
    maximum_policy_workspace >= 0 || throw(ArgumentError(
        "lifecycle policy-workspace bound cannot be negative"
    ))
    maximum_policy_workspace <= typemax(Int32) || throw(ArgumentError(
        "lifecycle policy-workspace bound exceeds Int32"
    ))
    length(forbid_extinction) > 0 || throw(ArgumentError(
        "lifecycle extinction table cannot be empty"
    ))
    owned_forbid_extinction = Tuple(forbid_extinction)
    effect_mask = UInt8(0)
    division_variant_mask = UInt16(0)
    relationship_action_mask = UInt8(0)
    state_action_masks = zeros(UInt16, 5)
    for descriptor in descriptors
        effect_mask |= _lifecycle_effect_bit(descriptor.effect)
        descriptor.effect === DivideCellLifecycleEffect &&
            (division_variant_mask |= _lifecycle_division_variant_bit(
                descriptor.partition, descriptor.side
            ))
        for offset in 0:(Int(descriptor.state_rule_count) - 1)
            rule_index = Int(descriptor.state_rule_offset) + offset
            action = call_lifecycle_state_rule(
                _lifecycle_state_rule_action, state_rules, rule_index
            )
            state_action_masks[Int(descriptor.effect)] |=
                _lifecycle_state_action_bit(action)
        end
    end
    for rule in relationship_rules
        relationship_action_mask |= _lifecycle_relationship_action_bit(
            rule.action
        )
    end
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
        typeof(owned_forbid_extinction),
    }(
        descriptors,
        evaluators,
        state_rules,
        relationship_rules,
        ownership_rules,
        stencil_offsets,
        relations,
        conflict_policy,
        effect_mask,
        division_variant_mask,
        relationship_action_mask,
        Tuple(state_action_masks),
        Int32(cell_capacity),
        Int32(maximum_requests),
        Int32(maximum_placement_sites),
        Int32(maximum_policy_workspace),
        owned_forbid_extinction,
    )
end

function _lifecycle_plan_fingerprint(plan::LifecycleExecutionPlan)
    payload = (
        plan.descriptors,
        plan.evaluators,
        plan.state_rules,
        plan.relationship_rules,
        plan.ownership_rules,
        plan.stencil_offsets,
        plan.relations.data,
        plan.relations.offsets,
        plan.relations.counts,
        plan.conflict_policy,
        plan.effect_mask,
        plan.division_variant_mask,
        plan.relationship_action_mask,
        plan.state_action_masks,
        plan.cell_capacity,
        plan.maximum_requests,
        plan.maximum_placement_sites,
        plan.maximum_policy_workspace,
        plan.forbid_extinction,
    )
    return bytes2hex(SHA.sha256(codeunits(repr(payload))))
end

"""Return stable structural facts for a lifecycle execution plan."""
function lifecycle_plan_report(plan::LifecycleExecutionPlan)
    return (
        descriptors = length(plan.descriptors),
        evaluators = length(plan.evaluators),
        state_rules = length(plan.state_rules),
        state_actions = count_ones(plan.state_rules.action_mask),
        relationship_rules = length(plan.relationship_rules),
        relationship_actions = count_ones(plan.relationship_action_mask),
        state_action_pairs = sum(count_ones, plan.state_action_masks),
        ownership_rules = length(plan.ownership_rules),
        cell_capacity = plan.cell_capacity,
        maximum_requests = plan.maximum_requests,
        maximum_placement_sites = plan.maximum_placement_sites,
        maximum_policy_workspace = plan.maximum_policy_workspace,
        conflict_policy = Symbol(string(plan.conflict_policy)),
        division_variants = count_ones(plan.division_variant_mask),
        fingerprint = _lifecycle_plan_fingerprint(plan),
    )
end

lifecycle_plan_report(::NoLifecycleExecutionPlan) = (
    descriptors = 0,
    evaluators = 0,
    state_rules = 0,
    state_actions = 0,
    relationship_rules = 0,
    relationship_actions = 0,
    ownership_rules = 0,
    cell_capacity = 0,
    maximum_requests = 0,
    maximum_placement_sites = 0,
    maximum_policy_workspace = 0,
    conflict_policy = :none,
    division_variants = 0,
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

"""Return the lattice anchor selected for the current lifecycle evaluation."""
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
function Adapt.adapt_structure(
        to, bank::LifecycleEvaluatorBank{Role}
    ) where {Role}
    return LifecycleEvaluatorBank(Val(Role), Adapt.adapt(to, bank.values))
end
Adapt.@adapt_structure LifecycleEvaluatorStorage
Adapt.@adapt_structure LifecycleStateRule
Adapt.@adapt_structure LifecycleStateRuleSlot
Adapt.@adapt_structure LifecycleStateRuleStorage
Adapt.@adapt_structure LifecycleRelationshipRule
Adapt.@adapt_structure LifecycleOwnershipRule
Adapt.@adapt_structure LifecycleSiteSelection
Adapt.@adapt_structure LifecycleDescriptor
function Adapt.adapt_structure(
        to, storage::LifecycleRelationStorage{N}
    ) where {N}
    data = Adapt.adapt(to, storage.data)
    offsets = Adapt.adapt(to, storage.offsets)
    counts = Adapt.adapt(to, storage.counts)
    typeof(offsets) === typeof(counts) || throw(ArgumentError(
        "adapted lifecycle relation offsets and counts must share storage"
    ))
    return LifecycleRelationStorage{
        N, typeof(data), typeof(offsets)
    }(data, offsets, counts)
end
Adapt.@adapt_structure LifecycleExecutionPlan
Adapt.@adapt_structure NoLifecycleExecutionPlan
Adapt.@adapt_structure LifecycleBoundStateValueOperation

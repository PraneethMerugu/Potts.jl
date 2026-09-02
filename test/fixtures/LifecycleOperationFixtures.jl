module LifecycleOperationFixtures

using Potts
using Symbolics

import CorePotts
import Potts: operation_transfer

const CompilerSPI = CorePotts.CompilerSPI

export external_lifecycle_trigger, external_lifecycle_placement
export external_lifecycle_partition, external_lifecycle_transform
export external_unqualified_partition
export external_unqualified_trigger, external_unqualified_transform

const VERSION = v"1.0.0"
const TRANSFER_LOOKUPS = Ref(0)
const CALLABLE_LOOKUPS = Ref(0)

function external_lifecycle_trigger end
function external_lifecycle_placement end
function external_lifecycle_partition end
function external_lifecycle_transform end
function external_unqualified_partition end
function external_unqualified_trigger end
function external_unqualified_transform end

Symbolics.@register_symbolic external_lifecycle_trigger(value)::Bool
Symbolics.@register_symbolic external_lifecycle_placement(value)::Int
Symbolics.@register_symbolic external_lifecycle_partition(value)::Int
Symbolics.@register_symbolic external_lifecycle_transform(value)::Real
Symbolics.@register_symbolic external_unqualified_partition(value)::Int
Symbolics.@register_symbolic external_unqualified_trigger(value)::Bool
Symbolics.@register_symbolic external_unqualified_transform(value)::Real

struct TriggerCallable <: CompilerSPI.AbstractContextualOperation end
struct PlacementCallable <: CompilerSPI.AbstractContextualOperation end
struct PartitionCallable <: CompilerSPI.AbstractContextualOperation end
struct TransformCallable <: CompilerSPI.AbstractContextualOperation end
struct UnqualifiedPartitionCallable <: CompilerSPI.AbstractContextualOperation end
struct UnqualifiedTriggerCallable <: CompilerSPI.AbstractContextualOperation end
struct UnqualifiedTransformCallable <: CompilerSPI.AbstractContextualOperation end

CompilerSPI.operation_context_supported(
    ::TriggerCallable,
    ::Type{CompilerSPI.AbstractLifecycleTriggerEvaluationContext},
) = true
CompilerSPI.operation_context_supported(
    ::UnqualifiedPartitionCallable,
    ::Type{CompilerSPI.AbstractLifecyclePartitionEvaluationContext},
) = true
CompilerSPI.operation_context_supported(
    ::UnqualifiedTriggerCallable,
    ::Type{CompilerSPI.AbstractLifecycleTriggerEvaluationContext},
) = true
CompilerSPI.operation_context_supported(
    ::UnqualifiedTransformCallable,
    ::Type{CompilerSPI.AbstractLifecycleStateTransformEvaluationContext},
) = true
CompilerSPI.operation_context_supported(
    ::PlacementCallable,
    ::Type{CompilerSPI.AbstractLifecyclePlacementEvaluationContext},
) = true
CompilerSPI.operation_context_supported(
    ::PartitionCallable,
    ::Type{CompilerSPI.AbstractLifecyclePartitionEvaluationContext},
) = true
CompilerSPI.operation_context_supported(
    ::TransformCallable,
    ::Type{CompilerSPI.AbstractLifecycleStateTransformEvaluationContext},
) = true

@inline function (::TriggerCallable)(arguments, context)
    return arguments[1] > 0 &&
        !iszero(CompilerSPI.lifecycle_source_identity(context)) &&
        !iszero(CompilerSPI.lifecycle_action_identity(context))
end
@inline function (::PlacementCallable)(arguments, context)
    first_site = Int32(arguments[1])
    CompilerSPI.lifecycle_workspace_capacity(context) == 4 ||
        return CompilerSPI.LifecycleSiteSelection((Int32(0), Int32(0), Int32(0), Int32(0)), 0)
    workspace_zero = CompilerSPI.lifecycle_workspace_value(context, 1)
    CompilerSPI.set_lifecycle_workspace_value!(
        context, oftype(workspace_zero, first_site), 1
    )
    stored = Int32(CompilerSPI.lifecycle_workspace_value(context, 1))
    return CompilerSPI.LifecycleSiteSelection(
        (stored, stored + Int32(1), Int32(0), Int32(0)), 2
    )
end
@inline function (::PartitionCallable)(arguments, context)
    site = CompilerSPI.lifecycle_site(context)
    index = site[1]
    previous = CompilerSPI.lifecycle_workspace_value(context, index)
    calls = previous + one(previous)
    CompilerSPI.set_lifecycle_workspace_value!(context, calls, index)
    calls == 1 || return 0
    return site[1] <= 3 ? 1 : 2
end
@inline function (::TransformCallable)(arguments, context)
    CompilerSPI.lifecycle_state_role(context) ===
        CompilerSPI.DestinationLifecycleStateRole || return Float32(NaN)
    CompilerSPI.lifecycle_destination_cell(context) > 0 ||
        return Float32(NaN)
    CompilerSPI.lifecycle_source_cell(context) == 0 ||
        return Float32(NaN)
    CompilerSPI.lifecycle_before_state_value(context) ==
        CompilerSPI.lifecycle_planned_state_value(context) ||
        return Float32(NaN)
    prior = CompilerSPI.lifecycle_workspace_value(context, 1)
    arguments[1] == 3 && prior == 2 && return Float32(NaN)
    arguments[1] < 0 && return oftype(
        CompilerSPI.lifecycle_workspace_value(context, 1), NaN
    )
    CompilerSPI.set_lifecycle_workspace_value!(
        context, oftype(prior, arguments[1]), 1
    )
    return CompilerSPI.lifecycle_workspace_value(context, 1)
end
@inline (::UnqualifiedPartitionCallable)(arguments, context) = Int(arguments[1])
@inline (::UnqualifiedTriggerCallable)(arguments, context) = arguments[1] > 0
@inline (::UnqualifiedTransformCallable)(arguments, context) = arguments[1]

function _transfer(
        identity,
        role,
        context,
        result_rule,
        result_shape,
        validator;
        emission_maximum = 0,
        workspace_maximum = 0,
        rng_entity = :none,
    )
    TRANSFER_LOOKUPS[] += 1
    return Potts.OperationTransfer(
        identity,
        VERSION,
        "lifecycle-operation-fixture:" * String(identity) * ":v1",
        1:1,
        result_rule,
        :dimensionless,
        :pure,
        :total,
        Potts.InheritFootprintRule(),
        true,
        true;
        allowed_roles = (Symbol(:lifecycle_, role === :binary_partition ?
            :partition : role),),
        allowed_phases = (:Lifecycle,),
        required_context = context,
        owner = :LifecycleOperationFixtures,
        callable_identity = "LifecycleOperationFixtures:" * String(identity) * ":v1",
        lifecycle_abi = Potts.LifecycleOperationABI(
            role;
            input_context = context,
            result_shape,
            emission_maximum,
            workspace_maximum,
            validator,
            rng_entity,
        ),
    )
end

operation_transfer(::typeof(external_lifecycle_trigger), ::Int) = _transfer(
    :external_lifecycle_trigger,
    :trigger,
    :lifecycle_trigger,
    :boolean,
    :scalar_boolean,
    :trigger_boolean,
)
operation_transfer(::typeof(external_lifecycle_placement), ::Int) = _transfer(
    :external_lifecycle_placement,
    :placement,
    :lifecycle_placement,
    :site_selection,
    :bounded_site_selection,
    :placement_selection;
    emission_maximum = 4,
    workspace_maximum = 4,
    rng_entity = :model_occurrence,
)
operation_transfer(::typeof(external_lifecycle_partition), ::Int) = _transfer(
    :external_lifecycle_partition,
    :binary_partition,
    :lifecycle_partition,
    :integer,
    :site_region_label,
    :binary_partition;
    emission_maximum = 2,
    workspace_maximum = 8,
    rng_entity = :cell_generation,
)
operation_transfer(::typeof(external_lifecycle_transform), ::Int) = _transfer(
    :external_lifecycle_transform,
    :state_transform,
    :lifecycle_state_transform,
    :real,
    :state_value,
    :state_schema;
    workspace_maximum = 1,
    rng_entity = :destination,
)

function _unqualified_transfer(identity, role, context, result_rule)
    TRANSFER_LOOKUPS[] += 1
    return Potts.OperationTransfer(
        identity,
        VERSION,
        "lifecycle-operation-fixture:" * String(identity) * ":v1",
        1:1,
        result_rule,
        :dimensionless,
        :pure,
        :total,
        Potts.InheritFootprintRule(),
        true,
        true;
        allowed_roles = (role,),
        allowed_phases = (:Lifecycle,),
        required_context = context,
        owner = :LifecycleOperationFixtures,
        callable_identity = "LifecycleOperationFixtures:" * String(identity) * ":v1",
    )
end
operation_transfer(::typeof(external_unqualified_partition), ::Int) =
    _unqualified_transfer(
        :external_unqualified_partition,
        :lifecycle_partition,
        :lifecycle_partition,
        :integer,
    )
operation_transfer(::typeof(external_unqualified_trigger), ::Int) =
    _unqualified_transfer(
        :external_unqualified_trigger,
        :lifecycle_trigger,
        :lifecycle_trigger,
        :boolean,
    )
operation_transfer(::typeof(external_unqualified_transform), ::Int) =
    _unqualified_transfer(
        :external_unqualified_transform,
        :lifecycle_state_transform,
        :lifecycle_state_transform,
        :real,
    )

function CompilerSPI.operation_callable(
        ::Val{identity}, version::VersionNumber
    ) where {identity}
    identity in (
        :external_lifecycle_trigger,
        :external_lifecycle_placement,
        :external_lifecycle_partition,
        :external_lifecycle_transform,
        :external_unqualified_partition,
        :external_unqualified_trigger,
        :external_unqualified_transform,
    ) || throw(MethodError(CompilerSPI.operation_callable, (Val(identity), version)))
    version == VERSION || throw(ArgumentError(
        "unsupported lifecycle operation fixture version $version"
    ))
    CALLABLE_LOOKUPS[] += 1
    identity === :external_lifecycle_trigger && return TriggerCallable()
    identity === :external_lifecycle_placement && return PlacementCallable()
    identity === :external_lifecycle_partition && return PartitionCallable()
    identity === :external_unqualified_partition &&
        return UnqualifiedPartitionCallable()
    identity === :external_unqualified_trigger &&
        return UnqualifiedTriggerCallable()
    identity === :external_unqualified_transform &&
        return UnqualifiedTransformCallable()
    return TransformCallable()
end

end

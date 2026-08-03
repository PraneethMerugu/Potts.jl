module G5LifecycleOperations

using PottsToolkit
using Symbolics

import CorePotts
import PottsToolkit: operation_transfer

export external_lifecycle_trigger, external_lifecycle_placement
export external_lifecycle_partition, external_lifecycle_transform
export external_unqualified_partition

const VERSION = v"1.0.0"
const TRANSFER_LOOKUPS = Ref(0)
const CALLABLE_LOOKUPS = Ref(0)

function external_lifecycle_trigger end
function external_lifecycle_placement end
function external_lifecycle_partition end
function external_lifecycle_transform end
function external_unqualified_partition end

Symbolics.@register_symbolic external_lifecycle_trigger(value)::Bool
Symbolics.@register_symbolic external_lifecycle_placement(value)::Int
Symbolics.@register_symbolic external_lifecycle_partition(value)::Int
Symbolics.@register_symbolic external_lifecycle_transform(value)::Real
Symbolics.@register_symbolic external_unqualified_partition(value)::Int

struct TriggerCallable <: CorePotts.AbstractContextualOperation end
struct PlacementCallable <: CorePotts.AbstractContextualOperation end
struct PartitionCallable <: CorePotts.AbstractContextualOperation end
struct TransformCallable <: CorePotts.AbstractContextualOperation end
struct UnqualifiedPartitionCallable <: CorePotts.AbstractContextualOperation end

CorePotts.operation_context_supported(
    ::TriggerCallable,
    ::Type{CorePotts.AbstractLifecycleTriggerEvaluationContext},
) = true
CorePotts.operation_context_supported(
    ::UnqualifiedPartitionCallable,
    ::Type{CorePotts.AbstractLifecyclePartitionEvaluationContext},
) = true
CorePotts.operation_context_supported(
    ::PlacementCallable,
    ::Type{CorePotts.AbstractLifecyclePlacementEvaluationContext},
) = true
CorePotts.operation_context_supported(
    ::PartitionCallable,
    ::Type{CorePotts.AbstractLifecyclePartitionEvaluationContext},
) = true
CorePotts.operation_context_supported(
    ::TransformCallable,
    ::Type{CorePotts.AbstractLifecycleStateTransformEvaluationContext},
) = true

@inline (::TriggerCallable)(arguments, context) = arguments[1] > 0
@inline (::PlacementCallable)(arguments, context) = Int(arguments[1])
@inline (::PartitionCallable)(arguments, context) = Int(arguments[1])
@inline (::TransformCallable)(arguments, context) = arguments[1]
@inline (::UnqualifiedPartitionCallable)(arguments, context) = Int(arguments[1])

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
    return PottsToolkit.OperationTransfer(
        identity,
        VERSION,
        "g5-lifecycle-operation:" * String(identity) * ":v1",
        1:1,
        result_rule,
        :dimensionless,
        :pure,
        :total,
        PottsToolkit.InheritFootprintRule(),
        true,
        true;
        allowed_roles = (Symbol(:lifecycle_, role === :binary_partition ?
            :partition : role),),
        allowed_phases = (:Lifecycle,),
        required_context = context,
        owner = :G5LifecycleOperations,
        callable_identity = "G5LifecycleOperations:" * String(identity) * ":v1",
        lifecycle_abi = PottsToolkit.LifecycleOperationABI(
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
    :integer,
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

function operation_transfer(::typeof(external_unqualified_partition), ::Int)
    TRANSFER_LOOKUPS[] += 1
    return PottsToolkit.OperationTransfer(
        :external_unqualified_partition,
        VERSION,
        "g5-lifecycle-operation:external_unqualified_partition:v1",
        1:1,
        :integer,
        :dimensionless,
        :pure,
        :total,
        PottsToolkit.InheritFootprintRule(),
        true,
        true;
        allowed_roles = (:lifecycle_partition,),
        allowed_phases = (:Lifecycle,),
        required_context = :lifecycle_partition,
        owner = :G5LifecycleOperations,
        callable_identity = "G5LifecycleOperations:external_unqualified_partition:v1",
    )
end

function CorePotts.operation_callable(
        ::Val{identity}, version::VersionNumber
    ) where {identity}
    identity in (
        :external_lifecycle_trigger,
        :external_lifecycle_placement,
        :external_lifecycle_partition,
        :external_lifecycle_transform,
        :external_unqualified_partition,
    ) || throw(MethodError(CorePotts.operation_callable, (Val(identity), version)))
    version == VERSION || throw(ArgumentError(
        "unsupported G5 lifecycle operation version $version"
    ))
    CALLABLE_LOOKUPS[] += 1
    identity === :external_lifecycle_trigger && return TriggerCallable()
    identity === :external_lifecycle_placement && return PlacementCallable()
    identity === :external_lifecycle_partition && return PartitionCallable()
    identity === :external_unqualified_partition &&
        return UnqualifiedPartitionCallable()
    return TransformCallable()
end

end

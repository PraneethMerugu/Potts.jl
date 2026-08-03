module LifecycleOperationFixtures

using PottsToolkit
using Symbolics

import CorePotts
import PottsToolkit: operation_transfer

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

struct TriggerCallable <: CorePotts.AbstractContextualOperation end
struct PlacementCallable <: CorePotts.AbstractContextualOperation end
struct PartitionCallable <: CorePotts.AbstractContextualOperation end
struct TransformCallable <: CorePotts.AbstractContextualOperation end
struct UnqualifiedPartitionCallable <: CorePotts.AbstractContextualOperation end
struct UnqualifiedTriggerCallable <: CorePotts.AbstractContextualOperation end
struct UnqualifiedTransformCallable <: CorePotts.AbstractContextualOperation end

CorePotts.operation_context_supported(
    ::TriggerCallable,
    ::Type{CorePotts.AbstractLifecycleTriggerEvaluationContext},
) = true
CorePotts.operation_context_supported(
    ::UnqualifiedPartitionCallable,
    ::Type{CorePotts.AbstractLifecyclePartitionEvaluationContext},
) = true
CorePotts.operation_context_supported(
    ::UnqualifiedTriggerCallable,
    ::Type{CorePotts.AbstractLifecycleTriggerEvaluationContext},
) = true
CorePotts.operation_context_supported(
    ::UnqualifiedTransformCallable,
    ::Type{CorePotts.AbstractLifecycleStateTransformEvaluationContext},
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

@inline function (::TriggerCallable)(arguments, context)
    return arguments[1] > 0 &&
        !iszero(CorePotts.lifecycle_source_identity(context)) &&
        !iszero(CorePotts.lifecycle_action_identity(context))
end
@inline function (::PlacementCallable)(arguments, context)
    first_site = Int32(arguments[1])
    CorePotts.lifecycle_workspace_capacity(context) == 4 ||
        return CorePotts.LifecycleSiteSelection((Int32(0), Int32(0), Int32(0), Int32(0)), 0)
    CorePotts.set_lifecycle_workspace_value!(context, first_site, 1)
    stored = Int32(CorePotts.lifecycle_workspace_value(context, 1))
    return CorePotts.LifecycleSiteSelection(
        (stored, stored + Int32(1), Int32(0), Int32(0)), 2
    )
end
@inline function (::PartitionCallable)(arguments, context)
    site = CorePotts.lifecycle_site(context)
    index = site[1]
    calls = CorePotts.lifecycle_workspace_value(context, index) + 1
    CorePotts.set_lifecycle_workspace_value!(context, calls, index)
    calls == 1 || return 0
    return site[1] <= 3 ? 1 : 2
end
@inline function (::TransformCallable)(arguments, context)
    CorePotts.lifecycle_state_role(context) ===
        CorePotts.DestinationLifecycleStateRole || return oftype(arguments[1], NaN)
    CorePotts.lifecycle_destination_cell(context) > 0 ||
        return oftype(arguments[1], NaN)
    CorePotts.lifecycle_source_cell(context) == 0 ||
        return oftype(arguments[1], NaN)
    CorePotts.lifecycle_before_state_value(context) ==
        CorePotts.lifecycle_planned_state_value(context) ||
        return oftype(arguments[1], NaN)
    arguments[1] < 0 && return oftype(
        CorePotts.lifecycle_workspace_value(context, 1), NaN
    )
    CorePotts.set_lifecycle_workspace_value!(context, arguments[1], 1)
    return CorePotts.lifecycle_workspace_value(context, 1)
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
    return PottsToolkit.OperationTransfer(
        identity,
        VERSION,
        "lifecycle-operation-fixture:" * String(identity) * ":v1",
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
        owner = :LifecycleOperationFixtures,
        callable_identity = "LifecycleOperationFixtures:" * String(identity) * ":v1",
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
    return PottsToolkit.OperationTransfer(
        identity,
        VERSION,
        "lifecycle-operation-fixture:" * String(identity) * ":v1",
        1:1,
        result_rule,
        :dimensionless,
        :pure,
        :total,
        PottsToolkit.InheritFootprintRule(),
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

function CorePotts.operation_callable(
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
    ) || throw(MethodError(CorePotts.operation_callable, (Val(identity), version)))
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

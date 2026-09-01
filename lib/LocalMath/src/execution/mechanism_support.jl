# Package-owned support shared by centrally lowered mechanisms. This file has
# no execution-family selection, domain semantics, launch schedule, or public
# extension registry.

function _package_owned_capability_dispatch(capability, arguments...)
    method = try
        which(capability, Base.typesof(arguments...))
    catch
        return false
    end
    return method.module === @__MODULE__
end

# Provider-lane construction is a physical execution concern shared by every
# Stage mechanism.  Keep its admission point beside the other centrally owned
# mechanism capabilities rather than in a semantic family or planner.
function _make_provider_lane(backend, storage)
    throw(LocalMathValidationError(
        "no centrally admitted provider-lane adapter exists for $(typeof(backend))"
    ))
end

function _central_make_provider_lane(backend, storage)
    signature = Tuple{typeof(backend), typeof(storage)}
    method = which(_make_provider_lane, signature)
    method.module === (@__MODULE__) || throw(LocalMathValidationError(
        "the provider-lane adapter is not centrally admitted"
    ))
    return invoke(_make_provider_lane, signature, backend, storage)
end

function _atomic_capability(backend, type, operation, address_space)
    return false
end

function _centrally_qualified_atomic_capability(
        backend, type::Type, operation::Symbol, address_space::Symbol
    )
    _package_owned_capability_dispatch(
        _atomic_capability, backend, type, operation, address_space
    ) || return false
    return _atomic_capability(
        backend,
        type,
        operation,
        address_space,
    )
end

function _value_capability(backend, type, operation, address_space)
    return false
end

function _centrally_qualified_value_capability(
        backend, type::Type, operation::Symbol, address_space::Symbol
    )
    _package_owned_capability_dispatch(
        _value_capability, backend, type, operation, address_space
    ) || return false
    return _value_capability(
        backend,
        type,
        operation,
        address_space,
    )
end

function _centrally_qualified_rank_type(backend, type::Type)
    _qualified_rank_shape(type) || return false
    fields = type <: Tuple ? type.parameters : (type,)
    return all(fields) do field
        _centrally_qualified_value_capability(
            backend, field, :load, :global,
        ) && _centrally_qualified_value_capability(
            backend, field, :store, :global,
        )
    end
end

function _record_leaf_capability(backend, ::Type{T}, operation) where {T}
    if fieldcount(T) == 0
        storage_type = _resolved_record_leaf_storage_type(T)
        storage_type === Nothing && return false
        return _centrally_qualified_value_capability(
            backend, storage_type, operation, :global,
        )
    end
    return all(1:fieldcount(T)) do index
        field = fieldtype(T, index)
        _record_leaf_capability(backend, field, operation)
    end
end

"""Admit a bounded isbits record only through the already reviewed leaf ABI.

This is deliberately narrower than accepting every Julia isbits struct: the
semantic storage predicate excludes metadata/reference shapes, the resolved
record profiles bound field count, byte size, alignment, and padding, and each
physical leaf must independently support the requested backend operation.
"""
function _centrally_qualified_stage_record(
        backend, type::Type, operation::Symbol
    )
    _storage_value_type(type) || return false
    (_centrally_qualified_resolved_record(backend, type) ||
        _centrally_qualified_wide_resolved_record(backend, type)) ||
        return false
    return _record_leaf_capability(backend, type, operation)
end

function _centrally_qualified_stage_storage_value(
        backend, type::Type, operation::Symbol
    )
    storage_type = _resolved_record_leaf_storage_type(type)
    storage_type === Nothing && return false
    return _centrally_qualified_value_capability(
        backend, storage_type, operation, :global,
    )
end

function _centrally_qualified_resolved_record(backend, type::Type)
    isconcretetype(type) && isbitstype(type) && 1 <= fieldcount(type) <= 8 ||
        return false
    sizeof(type) <= 16 && Base.datatype_alignment(type) <= 4 || return false
    offset = 0
    qualified = all(1:fieldcount(type)) do index
        field_type = fieldtype(type, index)
        packed = fieldcount(field_type) == 0 &&
            Base.fieldoffset(type, index) == offset
        offset += sizeof(field_type)
        packed &&
            _centrally_qualified_value_capability(
                backend, field_type, :load, :global,
            ) && _centrally_qualified_value_capability(
                backend, field_type, :store, :global,
            )
    end
    return qualified && offset == sizeof(type)
end

const _WIDE_RESOLVED_RECORD_MAX_FIELDS = 12
const _WIDE_RESOLVED_RECORD_MAX_BYTES = 48
const _WIDE_RESOLVED_RECORD_MAX_ALIGNMENT = 8

_requires_wide_component_record(type::Type) = fieldcount(type) > 8 ||
    sizeof(type) > 16 || Base.datatype_alignment(type) > 4

_enum_storage_type(::Val{1}) = UInt8
_enum_storage_type(::Val{2}) = UInt16
_enum_storage_type(::Val{4}) = UInt32
_enum_storage_type(::Val{8}) = UInt64
_enum_storage_type(::Val) = Nothing

function _resolved_record_leaf_storage_type(type::Type)
    type <: Enum || return type
    return _enum_storage_type(Val(sizeof(type)))
end

function _centrally_qualified_wide_resolved_record(backend, type::Type)
    isconcretetype(type) && isbitstype(type) &&
        1 <= fieldcount(type) <= _WIDE_RESOLVED_RECORD_MAX_FIELDS ||
        return false
    sizeof(type) <= _WIDE_RESOLVED_RECORD_MAX_BYTES &&
        Base.datatype_alignment(type) <=
            _WIDE_RESOLVED_RECORD_MAX_ALIGNMENT || return false

    previous_end = 0
    for index in 1:fieldcount(type)
        field_type = fieldtype(type, index)
        (isprimitivetype(field_type) || field_type <: Enum) || return false
        field_size = sizeof(field_type)
        field_size > 0 || return false
        offset = Base.fieldoffset(type, index)
        offset >= previous_end && offset + field_size <= sizeof(type) ||
            return false
        storage_type = _resolved_record_leaf_storage_type(field_type)
        storage_type === Nothing && return false
        _centrally_qualified_value_capability(
            backend, storage_type, :load, :global,
        ) && _centrally_qualified_value_capability(
            backend, storage_type, :store, :global,
        ) || return false
        previous_end = offset + field_size
    end
    return true
end

function _placeholder_value(type::Type{T}) where {T}
    isbitstype(T) || error("package-owned placeholder requires an isbits type")
    return @inbounds reinterpret(T, zeros(UInt8, sizeof(T)))[1]
end

function _storage_free_type(::Type{T}) where {T}
    T <: Union{Ptr, Core.LLVMPtr, Ref, AbstractArray} && return false
    ismutabletype(T) && return false
    return all(index -> _storage_free_type(fieldtype(T, index)), 1:fieldcount(T))
end

function _storage_free_value(value)
    _storage_free_type(typeof(value)) || return false
    return all(index -> _storage_free_value(getfield(value, index)),
        1:fieldcount(typeof(value)))
end

_pointwise_effect_capability(backend, operation, signature) = false
_centrally_qualified_pointwise_effects(backend, operation, signature) =
    _storage_free_value(operation) &&
    _package_owned_capability_dispatch(
        _pointwise_effect_capability, backend, operation, signature
    ) &&
    _pointwise_effect_capability(backend, operation, signature)

_ordered_fold_effect_analysis(backend, transition, signature) = (
    qualified = false,
    return_type = Any,
)
function _centrally_qualified_ordered_fold_analysis(
        backend, transition, signature
    )
    _storage_free_value(transition) || return (
        qualified = false,
        return_type = Any,
    )
    _package_owned_capability_dispatch(
        _ordered_fold_effect_analysis, backend, transition, signature
    ) || return (
        qualified = false,
        return_type = Any,
    )
    return _ordered_fold_effect_analysis(backend, transition, signature)
end
_ordering_effect_capability(backend, extractor, signature) = false
_centrally_qualified_ordering_effects(backend, extractor, signature) =
    _storage_free_value(extractor) &&
    _package_owned_capability_dispatch(
        _ordering_effect_capability, backend, extractor, signature
    ) &&
    _ordering_effect_capability(backend, extractor, signature)

function _device_copy(::KernelAbstractions.CPU, values)
    return copy(values)
end

function _device_copy(backend::KernelAbstractions.Backend, values)
    return Adapt.adapt(backend, values)
end

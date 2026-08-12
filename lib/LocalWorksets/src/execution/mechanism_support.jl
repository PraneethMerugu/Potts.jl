# Package-owned support shared by centrally lowered mechanisms. This file has
# no execution-family selection, domain semantics, launch schedule, or public
# extension registry.

function _atomic_capability(backend, type, operation, address_space)
    return false
end

function _centrally_qualified_atomic_capability(
        backend, type::Type, operation::Symbol, address_space::Symbol
    )
    signature = Tuple{
        typeof(backend), Core.Typeof(type), Symbol, Symbol,
    }
    method = which(_atomic_capability, signature)
    method.module === (@__MODULE__) || return false
    return invoke(
        _atomic_capability,
        signature,
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
    signature = Tuple{
        typeof(backend), Core.Typeof(type), Symbol, Symbol,
    }
    method = which(_value_capability, signature)
    method.module === (@__MODULE__) || return false
    return invoke(
        _value_capability,
        signature,
        backend,
        type,
        operation,
        address_space,
    )
end

function _slot_facts(slot::_StorageSlot{T, N}) where {T, N}
    return (
        array_type = slot.array_type,
        element_type = T,
        dimensions = N,
        size = slot.size,
        access = slot.access,
    )
end

function _binding_facts(storage, schema, name)
    if hasproperty(storage, name)
        value = getproperty(storage, name)
        return (
            element_type = eltype(value),
            dimensions = ndims(value),
            size = size(value),
            access = nothing,
        )
    end
    return invoke(
        _slot_facts, Tuple{_StorageSlot}, getproperty(schema, name)
    )
end

function _device_copy(::KernelAbstractions.CPU, values)
    return copy(values)
end

function _device_copy(backend::KernelAbstractions.Backend, values)
    return Adapt.adapt(backend, values)
end

function _centrally_owned_device_copy(backend, values)
    signature = backend isa KernelAbstractions.CPU ?
        Tuple{KernelAbstractions.CPU, Any} :
        Tuple{KernelAbstractions.Backend, Any}
    method = which(_device_copy, signature)
    method.module === (@__MODULE__) || throw(LocalWorkValidationError(
        "the topology device-copy implementation is not package-owned"
    ))
    return invoke(_device_copy, signature, backend, values)
end

function _owned_kernel_factory(kernel::Function, backend)
    signature = Tuple{Any}
    method = which(kernel, signature)
    method.module === (@__MODULE__) || throw(LocalWorkValidationError(
        "the prepared kernel factory is not package-owned"
    ))
    return invoke(kernel, signature, backend)
end

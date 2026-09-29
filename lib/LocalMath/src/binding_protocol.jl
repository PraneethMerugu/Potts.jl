# One private protocol for logical bindings whose physical storage may contain
# one array or a recursively structured set of arrays. Central validation,
# aliasing, prepared identity, and inspection use only this protocol.

abstract type _BindingProtocol end
struct _ArrayBindingProtocol <: _BindingProtocol end
struct _StructuredBindingProtocol{C, F} <: _BindingProtocol
    representation::Symbol
    components::C
    logical::F
end

mutable struct _StructuredPreparedBindingFact{L}
    representation::Symbol
    storage_type::DataType
    logical::Any
    leaves::L
end

_binding_protocol(array::AbstractArray) = _ArrayBindingProtocol()
function _binding_protocol(storage::CompactedStorage)
    return _StructuredBindingProtocol(
        :compacted_storage,
        _compacted_binding_components(storage),
        (
            element_type = eltype(storage.records),
            dimensions = 1,
            size = size(storage.records),
        ),
    )
end

_binding_representation(value) =
    _binding_representation(_binding_protocol(value), value)
_binding_representation_type(::Type{<:StructArrays.StructArray}) =
    :component_array
_binding_representation_type(::Type{<:AbstractArray}) = :global_array
_binding_representation_type(::Type{<:CompactedStorage}) = :compacted_storage
_binding_representation(::_ArrayBindingProtocol, array::StructArrays.StructArray) =
    :component_array
_binding_representation(::_ArrayBindingProtocol, array::AbstractArray) =
    :global_array
_binding_representation(protocol::_StructuredBindingProtocol, value) =
    protocol.representation

_binding_logical_facts(value) =
    _binding_logical_facts(_binding_protocol(value), value)
_binding_logical_facts(::_ArrayBindingProtocol, array) = (
    element_type = eltype(array),
    dimensions = ndims(array),
    size = size(array),
)
_binding_logical_facts(protocol::_StructuredBindingProtocol, value) =
    protocol.logical

function _flatten_binding_array(name::Symbol, array::StructArrays.StructArray)
    return _flatten_binding_components(name, StructArrays.components(array))
end
_flatten_binding_array(name::Symbol, array::AbstractArray) = (name => array,)

_flatten_binding_components(name::Symbol, components::NamedTuple{Names}) where {Names} =
    _flatten_binding_named_components(name, values(components), Val(Names))
_flatten_binding_components(name::Symbol, components::Tuple) =
    _flatten_binding_tuple_components(name, components, Val(1))

_flatten_binding_named_components(name::Symbol, ::Tuple{}, ::Val{()}) = ()
function _flatten_binding_named_components(
        name::Symbol, components::Tuple, ::Val{Names}
    ) where {Names}
    component_name = first(Names)
    return (
        _flatten_binding_array(
            Symbol(name, :_, component_name), first(components)
        )...,
        _flatten_binding_named_components(
            name, Base.tail(components), Val(Base.tail(Names))
        )...,
    )
end

_flatten_binding_tuple_components(name::Symbol, ::Tuple{}, ::Val{I}) where {I} = ()
function _flatten_binding_tuple_components(
        name::Symbol, components::Tuple, ::Val{I}
    ) where {I}
    return (
        _flatten_binding_array(
            Symbol(name, :_, string(I)), first(components)
        )...,
        _flatten_binding_tuple_components(
            name, Base.tail(components), Val(I + 1)
        )...,
    )
end

_binding_physical_leaves(name::Symbol, value) =
    _binding_physical_leaves(_binding_protocol(value), name, value)
_binding_physical_leaves(::_ArrayBindingProtocol, name::Symbol, array) =
    _flatten_binding_array(name, array)
function _binding_physical_leaves(
        protocol::_StructuredBindingProtocol, name::Symbol, value
    )
    return _flatten_binding_components(name, protocol.components)
end

function _binding_validate_backend(value, backend, name::Symbol)
    leaves = _binding_physical_leaves(name, value)
    isempty(leaves) && throw(LocalMathValidationError(
        "structured binding $name has no physical leaves";
        stage = :prepare, contract = :binding_physical_storage,
        binding = name,
    ))
    for (leaf_name, leaf) in leaves
        _validate_array_backend(leaf, backend, leaf_name)
    end
    return nothing
end

function _binding_device_identity(value)
    leaves = _binding_physical_leaves(:binding, value)
    identities = map(pair -> _array_device_identity(last(pair)), leaves)
    all(==(first(identities)), identities) || throw(LocalMathValidationError(
        "structured binding spans devices or contexts";
        stage = :prepare, contract = :device_coherence,
    ))
    return first(identities)
end

_binding_prepared_fact(value) =
    _binding_prepared_fact(_binding_protocol(value), value)
_binding_prepared_fact(::_ArrayBindingProtocol, array) =
    _prepared_array_fact(array)
function _binding_prepared_fact(
        protocol::_StructuredBindingProtocol, value
    )
    return _StructuredPreparedBindingFact(
        protocol.representation,
        typeof(value),
        protocol.logical,
        Tuple((name, leaf, _prepared_array_fact(leaf))
            for (name, leaf) in _binding_physical_leaves(:binding, value)),
    )
end

_binding_validate_prepared(value, fact, name) =
    _binding_validate_prepared(_binding_protocol(value), value, fact, name)
_binding_validate_prepared(::_ArrayBindingProtocol, value, fact, name) =
    _validate_cached_static_array_fact(value, fact, name)

@inline function _validate_structured_binding_array(
        name::Symbol, array::StructArrays.StructArray, fact, index::Int
    )
    return _validate_structured_binding_components(
        name, StructArrays.components(array), fact, index
    )
end
@inline function _validate_structured_binding_array(
        name::Symbol, array::AbstractArray, fact, index::Int
    )
    index <= length(fact.leaves) || throw(LocalMathValidationError(
        "prepared structured binding has fewer leaves than its storage"
    ))
    fact_name, leaf_fact = fact.leaves[index]
    name === fact_name || throw(LocalMathValidationError(
        "prepared structured binding leaf names changed after preparation"
    ))
    _validate_cached_static_array_fact(array, leaf_fact, name)
    return index + 1
end

@inline _validate_structured_binding_named_components(
    name::Symbol, ::Tuple{}, ::Val{()}, fact, index::Int
) = index
@inline function _validate_structured_binding_named_components(
        name::Symbol, components::Tuple, ::Val{Names}, fact, index::Int
    ) where {Names}
    component_name = first(Names)
    next = _validate_structured_binding_array(
        Symbol(name, :_, component_name), first(components), fact, index
    )
    return _validate_structured_binding_named_components(
        name, Base.tail(components), Val(Base.tail(Names)), fact, next
    )
end

@inline _validate_structured_binding_tuple_components(
    name::Symbol, ::Tuple{}, ::Val{I}, fact, index::Int
) where {I} = index
@inline function _validate_structured_binding_tuple_components(
        name::Symbol, components::Tuple, ::Val{I}, fact, index::Int
    ) where {I}
    next = _validate_structured_binding_array(
        Symbol(name, :_, string(I)), first(components), fact, index
    )
    return _validate_structured_binding_tuple_components(
        name, Base.tail(components), Val(I + 1), fact, next
    )
end

@inline _validate_structured_binding_components(
    name::Symbol, components::NamedTuple{Names}, fact, index::Int
) where {Names} = _validate_structured_binding_named_components(
    name, values(components), Val(Names), fact, index
)
@inline _validate_structured_binding_components(
    name::Symbol, components::Tuple, fact, index::Int
) = _validate_structured_binding_tuple_components(
    name, components, Val(1), fact, index
)

function _binding_validate_prepared(
        protocol::_StructuredBindingProtocol, value, fact, name
    )
    return _validate_structured_prepared_binding(value, fact, name)
end
function _validate_structured_prepared_binding(
        value, fact::_StructuredPreparedBindingFact, name
    )
    typeof(value) === fact.storage_type || throw(LocalMathValidationError(
        "prepared structured binding type $name changed after preparation"
    ))
    _validate_cached_structured_leaves(fact.leaves)
    return nothing
end

@inline _validate_cached_structured_leaves(::Tuple{}) = nothing
@inline function _validate_cached_structured_leaves(leaves::Tuple)
    leaf_name, leaf, leaf_fact = first(leaves)
    _validate_cached_static_array_fact(leaf, leaf_fact, leaf_name)
    return _validate_cached_structured_leaves(Base.tail(leaves))
end

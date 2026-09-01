# Shared semantic authority for exact bounded ordering. Mechanisms own their
# algorithms and storage; this unit owns only descriptors, extractor
# qualification, and device-inline comparison.

struct _SourceOrder end
struct _CanonicalBy{K, I}
    key::K
    identity::I
end
struct _PreparedCanonicalBy{KT,IT,K,I}
    key::K
    identity::I
end
_is_canonical_order(::_CanonicalBy) = true
_is_canonical_order(::_PreparedCanonicalBy) = true
_is_canonical_order(::_SourceOrder) = false
_prepared_order_types(::_PreparedCanonicalBy{KT,IT}) where {KT,IT} = (KT, IT)

struct _OrderingField{Name} end
@inline _ordering_extract(::_OrderingField{Name}, value) where {Name} =
    getproperty(value, Name)
@inline _ordering_extract(extractor, value) = extractor(value)
_ordering_extractor_token(name::Symbol) = _OrderingField{name}()
_ordering_extractor_token(extractor) = extractor

function _ordering_extractor(extractor, purpose)
    if extractor isa Symbol
        isempty(String(extractor)) && throw(ArgumentError(
            "$purpose field name must be nonempty"
        ))
        return extractor
    end
    type = typeof(extractor)
    isconcretetype(type) && isbitstype(type) &&
        _storage_free_value(extractor) || throw(ArgumentError(
        "$purpose must be a concrete storage-free isbits callable or field"
    ))
    isempty(methods(extractor)) && throw(ArgumentError(
        "$purpose must be callable"
    ))
    return extractor
end

function _ordering_extractor_type(
        extractor,
        ::Type{T},
        purpose;
        effects_contract::Symbol,
        extractor_contract::Symbol,
        type_contract::Symbol,
        allow_callables::Bool = false,
        analysis_cache = nothing,
    ) where {T}
    !allow_callables && !(extractor isa Symbol) && throw(
        LocalMathValidationError(
            "$purpose callable effects are not yet closed for this executable plan";
            stage = :plan,
            contract = effects_contract,
            expected = :emitted_record_field_symbol,
            actual = typeof(extractor),
            hint = "use a field Symbol; callable descriptors remain inert until exact effect qualification exists",
        )
    )
    token = _ordering_extractor_token(extractor)
    field_index = extractor isa Symbol ?
        findfirst(==(extractor), fieldnames(T)) : nothing
    extractor isa Symbol && field_index === nothing && throw(
        LocalMathValidationError(
            "$purpose names a field absent from the emitted record";
            stage = :plan,
            contract = extractor_contract,
            expected = fieldnames(T),
            actual = extractor,
        )
    )
    analysis = extractor isa Symbol || analysis_cache === nothing ? nothing :
        _cached_closed_callable_effect_analysis!(analysis_cache,
            :closed_ordering, token, Tuple{T},
            method_signature -> length(method_signature) == 2)
    analysis === nothing || analysis.qualified || throw(
        LocalMathValidationError(
            "$purpose fails its exact closed typed-IR contract";
            stage = :plan, contract = effects_contract,
            expected = :closed_storage_free_callable,
            actual = (qualified = analysis.qualified,
                return_type = analysis.return_type),
        ))
    result = extractor isa Symbol ? fieldtype(T, field_index) :
        analysis === nothing ? Core.Compiler.return_type(token, Tuple{T}) :
        analysis.return_type
    result isa DataType && isconcretetype(result) || throw(
        LocalMathValidationError(
            "$purpose must infer one concrete value type";
            stage = :plan,
            contract = type_contract,
            expected = :concrete,
            actual = result,
        )
    )
    _qualified_rank_shape(result) || throw(LocalMathValidationError(
        "$purpose must be Int32, UInt32, or a bounded flat tuple";
        stage = :plan,
        contract = type_contract,
        expected = :bounded_total_key,
        actual = result,
    ))
    return token, result
end

_ordering_token(order::_SourceOrder, ::Type; kwargs...) =
    (order, Nothing, Nothing)
function _ordering_token(
        order::_CanonicalBy,
        ::Type{T};
        key_purpose::AbstractString,
        identity_purpose::AbstractString,
        effects_contract::Symbol,
        extractor_contract::Symbol,
        type_contract::Symbol,
        allow_callables::Bool = false,
        analysis_cache = nothing,
    ) where {T}
    key, KT = _ordering_extractor_type(
        order.key, T, key_purpose;
        effects_contract, extractor_contract, type_contract, allow_callables,
        analysis_cache,
    )
    identity, IT = _ordering_extractor_type(
        order.identity, T, identity_purpose;
        effects_contract, extractor_contract, type_contract, allow_callables,
        analysis_cache,
    )
    return _CanonicalBy(key, identity), KT, IT
end

@inline function _canonical_order_compare(
        left_key, left_identity, right_key, right_identity
    )
    comparison = _rank_compare(left_key, right_key)
    comparison == 0 || return comparison
    return _rank_compare(left_identity, right_identity)
end
@inline _canonical_order_equal(
    left_key, left_identity, right_key, right_identity
) = _canonical_order_compare(
    left_key, left_identity, right_key, right_identity
) == 0

"""
    source_order()

Retain canonical logical source order after participation. This never denotes
provider or physical buffer order.
"""
source_order() = _SourceOrder()

"""
    canonical_by(key, identity)

Declare ascending canonical order by a storage-free key extractor and exact
semantic-identity extractor. Result profiles are centrally qualified by the
consuming mechanism; this descriptor exposes no comparator or algorithm.
"""
function canonical_by(key, identity)
    return _CanonicalBy(
        _ordering_extractor(key, "canonical key extractor"),
        _ordering_extractor(identity, "canonical identity extractor"),
    )
end

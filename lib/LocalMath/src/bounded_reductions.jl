const _BoundedPrimitiveNumber = Union{
    Bool,
    Int8, Int16, Int32, Int64,
    UInt8, UInt16, UInt32, UInt64,
    Float16, Float32, Float64,
}

struct _BoundedConvert{T} end
@inline (::_BoundedConvert{T})(value) where {T} = convert(T, value)

struct _BoundedResult end
@inline (::_BoundedResult)(accumulator, ::Int32) = accumulator

struct _BoundedMeanResult{T} end
@inline (::_BoundedMeanResult{T})(accumulator, count::Int32) where {T} =
    accumulator / T(count)

struct _BoundedGeometricMap end
@inline (::_BoundedGeometricMap)(value) = log(value)

struct _BoundedGeometricResult{T} end
@inline (::_BoundedGeometricResult{T})(accumulator, count::Int32) where {T} =
    exp(accumulator / T(count))

struct _BoundedPositive end
@inline (::_BoundedPositive)(value) = value > zero(value)

_bounded_sum_type(::Type{Bool}) = Int
_bounded_sum_type(::Type{T}) where {T<:Signed} = promote_type(Int, T)
_bounded_sum_type(::Type{T}) where {T<:Unsigned} = promote_type(UInt, T)
_bounded_sum_type(::Type{T}) where {T<:AbstractFloat} = T

_bounded_mean_type(::Type{T}) where {T<:Integer} = Float64
_bounded_mean_type(::Type{T}) where {T<:AbstractFloat} = T

function _unsupported_bounded_reduction(name::Symbol, ::Type{T}) where {T}
    throw(LocalMathValidationError(
        "$(name) does not support this bounded value type";
        stage = :construct,
        contract = :bounded_reduction_element_type,
        expected = _BoundedPrimitiveNumber,
        actual = T,
    ))
end

@inline function _bounded_sum_typed(values, ::Type{T}, ::Type{R}) where {T,R}
    operation = _bounded_fold(
        _BoundedConvert{R}(), +, zero(R), _BoundedResult(),
        _AllBoundedValues(), RejectInvalid(), FillEmpty(zero(R)),
        CanonicalLeftFold(),
    )
    return operation(values)
end

@inline function _bounded_minimum_typed(values, ::Type{T}) where {T}
    operation = _bounded_fold(
        identity, min, typemax(T), _BoundedResult(),
        _AllBoundedValues(), RejectInvalid(), RejectEmpty(),
        CanonicalLeftFold(),
    )
    return operation(values)
end

@inline function _bounded_maximum_typed(values, ::Type{T}) where {T}
    operation = _bounded_fold(
        identity, max, typemin(T), _BoundedResult(),
        _AllBoundedValues(), RejectInvalid(), RejectEmpty(),
        CanonicalLeftFold(),
    )
    return operation(values)
end

@inline function _bounded_mean_typed(values, ::Type{T}, ::Type{R}) where {T,R}
    operation = _bounded_fold(
        _BoundedConvert{R}(), +, zero(R), _BoundedMeanResult{R}(),
        _AllBoundedValues(), RejectInvalid(), FillEmpty(R(NaN)),
        CanonicalLeftFold(),
    )
    return operation(values)
end

@inline function _bounded_geometric_mean_typed(values, ::Type{T}) where {T}
    operation = _bounded_fold(
        _BoundedGeometricMap(), +, zero(T), _BoundedGeometricResult{T}(),
        Where(_CONSTRUCTION_TOKEN, _BoundedPositive()), RejectInvalid(),
        RejectEmpty(), CanonicalLeftFold(),
    )
    return operation(values)
end

@inline _bounded_sum(values, ::Type{T}) where {T<:_BoundedPrimitiveNumber} =
    _bounded_sum_typed(values, T, _bounded_sum_type(T))
@inline _bounded_sum(values, ::Type{T}) where {T} =
    _unsupported_bounded_reduction(:sum, T)

@inline _bounded_minimum(values, ::Type{T}) where {T<:_BoundedPrimitiveNumber} =
    _bounded_minimum_typed(values, T)
@inline _bounded_minimum(values, ::Type{T}) where {T} =
    _unsupported_bounded_reduction(:minimum, T)

@inline _bounded_maximum(values, ::Type{T}) where {T<:_BoundedPrimitiveNumber} =
    _bounded_maximum_typed(values, T)
@inline _bounded_maximum(values, ::Type{T}) where {T} =
    _unsupported_bounded_reduction(:maximum, T)

@inline _bounded_mean(values, ::Type{T}) where {T<:_BoundedPrimitiveNumber} =
    _bounded_mean_typed(values, T, _bounded_mean_type(T))
@inline _bounded_mean(values, ::Type{T}) where {T} =
    _unsupported_bounded_reduction(:mean, T)

for (operation, helper) in (
        (:sum, :_bounded_sum),
        (:minimum, :_bounded_minimum),
        (:maximum, :_bounded_maximum),
        (:mean, :_bounded_mean),
    )
    owner = operation === :mean ? Statistics : Base
    @eval begin
        @inline $owner.$operation(values::_StageRead{T}) where {T} =
            $helper(values, T)
        @inline $owner.$operation(values::_AuthoringValues{T}) where {T} =
            $helper(values, T)
        @inline $owner.$operation(values::_AuthoringSamples{T}) where {T} =
            $helper(values, T)
        @inline $owner.$operation(values::BoundedGroupView{K,T}) where {K,T} =
            $helper(values, T)
    end
end

@inline _bounded_geometric_mean(
        values, ::Type{T}) where {T<:Union{Float16,Float32,Float64}} =
    _bounded_geometric_mean_typed(values, T)
@inline _bounded_geometric_mean(values, ::Type{T}) where {T} =
    _unsupported_bounded_reduction(:geometric_mean, T)

"""
    LocalMath.geometric_mean(values)

Compute the geometric mean of a bounded floating-point gather or Collection
group in canonical lane order. Absent lanes do not participate. A nonpositive
present value or empty input rejects the containing transaction.
"""
@inline geometric_mean(values::_StageRead{T}) where {T} =
    _bounded_geometric_mean(values, T)
@inline geometric_mean(values::_AuthoringValues{T}) where {T} =
    _bounded_geometric_mean(values, T)
@inline geometric_mean(values::_AuthoringSamples{T}) where {T} =
    _bounded_geometric_mean(values, T)
@inline geometric_mean(values::BoundedGroupView{K,T}) where {K,T} =
    _bounded_geometric_mean(values, T)

include("authoring/syntax.jl")
include("authoring/preparation_syntax.jl")

# Evaluator-side facades. Their only payload is the existing bounded read
# capability, so they add no semantic or executable representation.
struct _AuthoringValues{R}
    read::R
end
struct _AuthoringSamples{R}
    read::R
end
struct _AuthoringIndices{R}
    read::R
end

@inline _authoring_values(read) = _AuthoringValues(read)
@inline _authoring_samples(read) = _AuthoringSamples(read)
@inline _authoring_indices(read) = _AuthoringIndices(read)

@inline Base.length(view::Union{
        _AuthoringValues,_AuthoringSamples,_AuthoringIndices}) =
    length(getfield(view, :read))
@inline Base.getindex(view::_AuthoringValues, lane::Integer) =
    _stage_read_required(getfield(view, :read), lane)
@inline Base.getindex(view::_AuthoringSamples, lane::Integer) =
    getfield(view, :read)[lane]
@inline Base.getindex(view::_AuthoringIndices, lane::Integer) =
    getfield(view, :read)[lane].endpoint
@inline Base.iterate(view::Union{
        _AuthoringValues,_AuthoringSamples,_AuthoringIndices}, lane::Int = 1) =
    lane > length(view) ? nothing : (view[lane], lane + 1)

@inline _authoring_required_scalar(read) = _stage_read_required(read, 1)
@inline _authoring_required_lane(read, ::Val{L}) where {L} =
    _stage_read_required(read, L)
@inline _authoring_sample_lane(read, ::Val{L}) where {L} = read[L]
@inline _authoring_index_lane(read, ::Val{L}) where {L} = read[L].endpoint

@inline _authoring_unique(value) = UniqueValue(value)
@inline _authoring_unique(values::Tuple) = map(UniqueValue, values)
@inline _authoring_unique_scalar(value) = UniqueValue(value)
@inline _authoring_reduce(value, when::Bool = true) = Contribution(value, when)
@inline _authoring_reduce(values::Tuple, when::Bool = true) =
    map(value -> Contribution(value, when), values)
@inline _authoring_reduce_scalar(value, when::Bool = true) =
    Contribution(value, when)
_authoring_reduce_order(order::Symbol) = order === :canonical ?
    CanonicalLeftFold() : order === :relaxed ? RelaxedAtomic() :
    throw(LocalMathValidationError(
        "Reduce order must be :canonical or :relaxed";
        stage = :construct, contract = :localmath_reduce_order,
        expected = (:canonical, :relaxed), actual = order))
_authoring_resolve_sense(sense::Symbol) = sense === :min ? ArgMin() :
    sense === :max ? ArgMax() : throw(LocalMathValidationError(
        "Resolve sense must be :min or :max";
        stage = :construct, contract = :localmath_resolve_sense,
        expected = (:min, :max), actual = sense))
_authoring_collect_order(order::Symbol) = order === :source ? source_order() :
    throw(LocalMathValidationError(
        "Collect order must be :source or an explicit canonical_by value";
        stage = :construct, contract = :localmath_collect_order,
        expected = (:source, :canonical_by), actual = order))
_authoring_collect_order(order) = order
_authoring_collect_projection(projection::Symbol) = projection === :none ?
    _NoPersistentProjection() : projection === :source_position ?
    persistent_source_position() : throw(LocalMathValidationError(
        "Collect projection must be :none or :source_position";
        stage = :construct, contract = :localmath_collect_projection,
        expected = (:none, :source_position), actual = projection))
@inline _authoring_resolve(score, payload, when::Bool = true) =
    ResolutionValue(score, payload, when)
@inline _authoring_resolve_tied(
        score, tie, payload, when::Bool = true) =
    ResolutionValue(score, tie, payload, when)
struct _AuthoringRecordType{T} end
@inline _authoring_record_type(::Type{T}) where {T} = _AuthoringRecordType{T}()
struct _AuthoringTypedEvaluator{Ts,F}
    evaluator::F
end

_device_evaluator_capture(operation::_AuthoringTypedEvaluator) =
    _device_evaluator_capture(operation.evaluator)

@generated function (operation::_AuthoringTypedEvaluator{Ts})(
        item, reads, parameters) where {Ts}
    markers = Expr(:tuple,
        [:(_authoring_record_type($type)) for type in Ts.parameters]...)
    return :(operation.evaluator(item, reads, parameters, $markers))
end

function _authoring_typed_evaluator(collections::Tuple, evaluator)
    types = Core.apply_type(Tuple, map(eltype, collections)...)
    return _AuthoringTypedEvaluator{types,typeof(evaluator)}(evaluator)
end

function _authoring_record_marker_types(::Type{Ts}) where {Ts}
    return Core.apply_type(Tuple,
        map(type -> Core.apply_type(_AuthoringRecordType, type),
            Ts.parameters)...)
end
@inline _authoring_collect(value::T, when::Bool,
        ::_AuthoringRecordType{T}) where {T} =
    CollectedValue(value, when)
@inline _authoring_collect(values::Tuple{Vararg{T}}, when::Bool,
        ::_AuthoringRecordType{T}) where {T} =
    map(value -> CollectedValue(value, when), values)
@inline _authoring_collect(values::Tuple{Vararg{T}}, participation::Tuple,
        ::_AuthoringRecordType{T}) where {T} =
    map(CollectedValue, values, participation)
@inline _authoring_keyed_collect(
        group::Int32, value::T, when::Bool,
        ::_AuthoringRecordType{T}) where {T} =
    GroupedCollectedValue(group, value, when)
@inline _authoring_keyed_collect(group::Int32,
        values::Tuple{Vararg{T}}, when::Bool,
        ::_AuthoringRecordType{T}) where {T} =
    map(value -> GroupedCollectedValue(group, value, when), values)
@inline _authoring_keyed_collect(group::Int32,
        values::Tuple{Vararg{T}}, participation::Tuple,
        ::_AuthoringRecordType{T}) where {T} =
    map((value, when) -> GroupedCollectedValue(group, value, when),
        values, participation)
@inline _authoring_fold(value, when::Bool = true) = FoldValue(value, when)
@inline _authoring_bounded_writes(keys, values, count::Int32) =
    BoundedWrites(keys, values, count)
@inline _authoring_fold_step(updates, halt::Bool = false) =
    FoldStep(updates; halt)

struct _AuthoringOrderKey end
struct _AuthoringOrderIdentity end
@inline (::_AuthoringOrderKey)(value) = value[1]
@inline (::_AuthoringOrderIdentity)(value) = value[2]
@inline _authoring_routed_unique(key, value, when::Bool = true) =
    ConditionalRoutedUniqueValue(key, value, when)
@inline _authoring_routed_reduce(key, value, when::Bool = true) =
    RoutedContribution(key, value, when)
@inline _authoring_routed_resolve(
        key, score, payload, when::Bool = true) =
    RoutedResolutionValue(key, score, payload, when)
@inline _authoring_routed_resolve_tied(
        key, score, tie, payload, when::Bool = true) =
    RoutedResolutionValue(key, score, tie, payload, when)

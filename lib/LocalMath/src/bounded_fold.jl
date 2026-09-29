"""A concrete predicate describing the admitted value domain of a bounded fold."""
struct Where{P}
    predicate::P
    function Where(::_ConstructionToken, predicate::P) where {P}
        new{P}(predicate)
    end
end
function Where(predicate::P) where {P}
        _bounded_fold_callable(predicate) || throw(LocalMathValidationError(
            "Where requires one concrete device-admissible predicate";
            stage = :construct, contract = :bounded_fold_domain,
            actual = P,
        ))
    return Where(_CONSTRUCTION_TOKEN, predicate)
end

struct _AllBoundedValues end

function _bounded_fold_callable(value)
    _device_law_callable(value) && return true
    T = typeof(value)
    return isconcretetype(T) && isbitstype(T) && _has_call_methods(value) &&
        _storage_free_value(value)
end

"""`RejectInvalid()` fails when a present bounded-fold input is invalid."""
struct RejectInvalid end
"""`SkipInvalid()` excludes invalid present inputs from a bounded fold."""
struct SkipInvalid end
"""`FillInvalid(value)` substitutes `value` for each invalid present input."""
struct FillInvalid{T}
    value::T
end
"""`RejectEmpty()` fails a bounded fold with no participating values."""
struct RejectEmpty end
"""Permission to reassociate a bounded fold; canonical execution remains valid."""
struct RelaxedAssociative end

"""Result of compiler-owned evaluation over a proven finite input."""
struct BoundedFoldOutcome{T}
    value::T
    valid::Bool
    reason::UInt8
end

const _BOUNDED_FOLD_VALID = UInt8(0)
const _BOUNDED_FOLD_INVALID_VALUE = UInt8(1)
const _BOUNDED_FOLD_EMPTY = UInt8(2)

"""Precise immutable compiler law for one checked bounded scalar fold."""
struct BoundedFold{M,C,S,F,D,I,E,O}
    map::M
    combine::C
    seed::S
    finish::F
    domain::D
    oninvalid::I
    onempty::E
    order::O
    function BoundedFold(
            ::_ConstructionToken,
            map::M,
            combine::C,
            seed::S,
            finish::F,
            domain::D,
            oninvalid::I,
            onempty::E,
            order::O,
        ) where {M,C,S,F,D,I,E,O}
        return new{M,C,S,F,D,I,E,O}(
            map, combine, seed, finish, domain, oninvalid, onempty, order)
    end
end

_device_type_parameter(::Type{<:BoundedFold}) = true

_device_evaluator_capture(domain::Where) =
    _bounded_fold_callable(domain.predicate)
_device_evaluator_capture(::_AllBoundedValues) = true
_device_evaluator_capture(policy::FillInvalid) =
    _device_evaluator_capture(policy.value)
_device_evaluator_capture(fold::BoundedFold) =
    _bounded_fold_callable(fold.map) &&
    _bounded_fold_callable(fold.combine) &&
    _device_evaluator_capture(fold.seed) &&
    _bounded_fold_callable(fold.finish) &&
    _device_evaluator_capture(fold.domain) &&
    _device_evaluator_capture(fold.oninvalid) &&
    _device_evaluator_capture(fold.onempty) &&
    _device_evaluator_capture(fold.order)

function _contains_bounded_fold_type(::Type{T}, seen = IdSet{Any}()) where {T}
    T <: BoundedFold && return true
    T in seen && return false
    push!(seen, T)
    isconcretetype(T) && isstructtype(T) || return false
    return any(fieldtype -> _contains_bounded_fold_type(fieldtype, seen),
        fieldtypes(T))
end

function _validate_bounded_fold_types(
        ::Type{T}, map, combine, seed, finish, oninvalid, onempty,
    ) where {T}
    isconcretetype(T) && isbitstype(T) || throw(LocalMathValidationError(
        "BoundedFold requires one concrete isbits input type";
        stage = :construct, contract = :bounded_fold_input_type,
        expected = :concrete_isbits, actual = T,
    ))
    mapped = Core.Compiler.return_type(map, Tuple{T})
    mapped isa DataType && isconcretetype(mapped) && isbitstype(mapped) ||
        throw(LocalMathValidationError(
            "BoundedFold map must infer one concrete isbits result";
            stage = :construct, contract = :bounded_fold_map_type,
            expected = :concrete_isbits, actual = mapped,
        ))
    accumulator = typeof(seed)
    combined = Core.Compiler.return_type(combine, Tuple{accumulator,mapped})
    combined === accumulator || throw(LocalMathValidationError(
        "BoundedFold combine must preserve the accumulator type";
        stage = :construct, contract = :bounded_fold_accumulator_type,
        expected = accumulator, actual = combined,
    ))
    result = Core.Compiler.return_type(finish, Tuple{accumulator,Int32})
    result isa DataType && isconcretetype(result) && isbitstype(result) ||
        throw(LocalMathValidationError(
            "BoundedFold finish must infer one concrete isbits result";
            stage = :construct, contract = :bounded_fold_result_type,
            expected = :concrete_isbits, actual = result,
        ))
    oninvalid isa FillInvalid && typeof(oninvalid.value) !== T && throw(
        LocalMathValidationError(
            "BoundedFold invalid fill must exactly match the input type";
            stage = :construct, contract = :bounded_fold_invalid_fill_type,
            expected = T, actual = typeof(oninvalid.value),
        ))
    onempty isa FillEmpty && typeof(onempty.value) !== result && throw(
        LocalMathValidationError(
            "BoundedFold empty fill must exactly match the result type";
            stage = :construct, contract = :bounded_fold_empty_fill_type,
            expected = result, actual = typeof(onempty.value),
        ))
    return result
end

function _bounded_fold(
        map, combine, seed, finish, domain, oninvalid, onempty, order,
    )
    return BoundedFold(_CONSTRUCTION_TOKEN, map, combine, seed, finish,
        domain, oninvalid, onempty, order)
end

"""
    BoundedFold(T, map, combine, init, finish;
                domain=Where(...), oninvalid=RejectInvalid(),
                onempty=RejectEmpty(), order=CanonicalLeftFold())

Construct the precise compiler law for a bounded input with element type `T`.
The map, accumulator, and result types are closed during construction. Ordinary
mathematical code uses [`LocalMath.fold`](@ref) with the bounded values first.
"""
function BoundedFold(::Type{T}, map, combine, seed, finish;
        domain = _AllBoundedValues(),
        oninvalid = RejectInvalid(),
        onempty = RejectEmpty(),
        order = CanonicalLeftFold(),
    ) where {T}
    domain isa Union{Where,_AllBoundedValues} || throw(LocalMathValidationError(
        "BoundedFold requires Where(predicate) or the default complete domain";
        stage = :construct, contract = :bounded_fold_domain,
        expected = (Where, :all), actual = typeof(domain),
    ))
    oninvalid isa Union{RejectInvalid,SkipInvalid,FillInvalid} || throw(
        LocalMathValidationError(
            "BoundedFold has an unsupported invalid-value policy";
            stage = :construct, contract = :bounded_fold_invalid_policy,
            actual = typeof(oninvalid),
        ))
    onempty isa Union{RejectEmpty,FillEmpty} || throw(LocalMathValidationError(
        "BoundedFold has an unsupported empty policy";
        stage = :construct, contract = :bounded_fold_empty_policy,
        actual = typeof(onempty),
    ))
    order isa Union{CanonicalLeftFold,RelaxedAssociative} || throw(
        LocalMathValidationError(
            "BoundedFold requires canonical or relaxed-associative order";
            stage = :construct, contract = :bounded_fold_order,
            actual = typeof(order),
        ))
    for (callable, contract) in ((map, :bounded_fold_map),
            (combine, :bounded_fold_combine), (finish, :bounded_fold_finish))
        _bounded_fold_callable(callable) || throw(LocalMathValidationError(
            "BoundedFold callables must be concrete and device-admissible";
            stage = :construct, contract, actual = typeof(callable),
        ))
    end
    _validate_bounded_fold_types(
        T, map, combine, seed, finish, oninvalid, onempty)
    return _bounded_fold(
        map, combine, seed, finish, domain, oninvalid, onempty, order)
end

@inline _bounded_fold_finish_identity(accumulator, ::Int32) = accumulator

@inline function _fold_domain(domain::Symbol)
    domain === :all && return _AllBoundedValues()
    throw(LocalMathValidationError(
        "fold domain must be :all or one concrete callable";
        stage = :construct, contract = :bounded_fold_domain,
        expected = (:all, :callable), actual = domain,
    ))
end
@inline _fold_domain(predicate) = Where(_CONSTRUCTION_TOKEN, predicate)

@inline function _fold_invalid(policy::Symbol)
    policy === :reject && return RejectInvalid()
    policy === :skip && return SkipInvalid()
    throw(LocalMathValidationError(
        "fold invalid policy must be :reject, :skip, or an exact fill value";
        stage = :construct, contract = :bounded_fold_invalid_policy,
        actual = policy,
    ))
end
@inline _fold_invalid(value) = FillInvalid(value)

@inline function _fold_empty(policy::Symbol)
    policy === :reject && return RejectEmpty()
    throw(LocalMathValidationError(
        "fold empty policy must be :reject or an exact result fill";
        stage = :construct, contract = :bounded_fold_empty_policy,
        actual = policy,
    ))
end
@inline _fold_empty(value) = FillEmpty(value)

@inline function _fold_order(order::Symbol)
    order === :canonical && return CanonicalLeftFold()
    order === :relaxed && return RelaxedAssociative()
    throw(LocalMathValidationError(
        "fold order must be :canonical or :relaxed";
        stage = :construct, contract = :bounded_fold_order,
        actual = order,
    ))
end

"""
    LocalMath.fold(values; map=identity, combine, init,
                   finish=(accumulator, count) -> accumulator,
                   domain=:all, invalid=:reject, empty=:reject,
                   order=:canonical)

Fold one bounded relation gather or collection group in canonical lane order.
Absent lanes do not participate and repeated endpoints participate repeatedly.
Invalid and empty policies are explicit; rejection fails the containing
transaction through its existing validation barrier.
"""
@inline function fold(
        values;
        map = identity,
        combine,
        init,
        finish = _bounded_fold_finish_identity,
        domain = :all,
        invalid = :reject,
        empty = :reject,
        order = :canonical,
    )
    domain_policy = _fold_domain(domain)
    invalid_policy = _fold_invalid(invalid)
    empty_policy = _fold_empty(empty)
    order_policy = _fold_order(order)
    operation = _bounded_fold(
        map, combine, init, finish, domain_policy, invalid_policy,
        empty_policy, order_policy)
    return operation(values)
end

"""
    evaluate_bounded(fold, maximum, sample_at)

Compiler-facing evaluation of `fold` over exactly `maximum` ordered lanes.
`sample_at(i)` returns `(present=..., value=...)`.  The returned outcome keeps
device code exception-free while allowing the surrounding transaction to own
failure publication.
"""
struct _BoundedSampleFunction{F}
    callable::F
end

struct _BoundedSampleSlice{I}
    input::I
    first::Int32
end

@inline _bounded_evaluation_sample(
    source::_BoundedSampleFunction, index::Int32,
) = source.callable(index)
@inline _bounded_evaluation_sample(
    source::_BoundedSampleSlice, index::Int32,
) = @inbounds source.input[Int(source.first + index - Int32(1))]

@inline function _evaluate_bounded(
        fold::BoundedFold, maximum::Integer, source,
    )
    accumulator = fold.seed
    count = Int32(0)
    reason = _BOUNDED_FOLD_VALID
    for index in Int32(1):Int32(maximum)
        sample = _bounded_evaluation_sample(source, index)
        sample.present || continue
        value = _bounded_sample_value(sample)
        if !_bounded_fold_domain_admits(fold.domain, value)
            policy = fold.oninvalid
            if policy isa SkipInvalid
                continue
            elseif policy isa FillInvalid
                value = policy.value
            else
                reason = _BOUNDED_FOLD_INVALID_VALUE
                continue
            end
        end
        accumulator = fold.combine(accumulator, fold.map(value))
        count += Int32(1)
    end
    if iszero(count)
        if fold.onempty isa FillEmpty
            return BoundedFoldOutcome(
                fold.onempty.value, reason == _BOUNDED_FOLD_VALID, reason)
        end
        reason == _BOUNDED_FOLD_VALID && (reason = _BOUNDED_FOLD_EMPTY)
    end
    return BoundedFoldOutcome(
        fold.finish(accumulator, count),
        reason == _BOUNDED_FOLD_VALID,
        reason,
    )
end

@inline evaluate_bounded(
    fold::BoundedFold, maximum::Integer, sample_at,
) = _evaluate_bounded(fold, maximum, _BoundedSampleFunction(sample_at))

"""Evaluate a bounded contiguous slice without constructing a capturing callback."""
@inline evaluate_bounded(
    fold::BoundedFold, input, first::Integer, count::Integer,
) = _evaluate_bounded(
    fold, count, _BoundedSampleSlice(input, Int32(first)))

@inline _bounded_sample_value(sample) = sample.value

@inline _bounded_fold_domain_admits(::_AllBoundedValues, value) = true
@inline _bounded_fold_domain_admits(domain::Where, value) =
    domain.predicate(value)

@inline evaluate_bounded(sample_at, fold::BoundedFold, maximum::Integer) =
    evaluate_bounded(fold, maximum, sample_at)

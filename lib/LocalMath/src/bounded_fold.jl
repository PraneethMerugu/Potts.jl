"""A concrete predicate describing the admitted value domain of a bounded fold."""
struct Where{P}
    predicate::P
    function Where(predicate::P) where {P}
        _bounded_fold_callable(predicate) || throw(LocalMathValidationError(
            "Where requires one concrete device-admissible predicate";
            stage = :construct, contract = :bounded_fold_domain,
            actual = P,
        ))
        new{P}(predicate)
    end
end

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

"""Immutable bounded fold law returned by `bounded_fold`."""
struct BoundedFold{M,C,S,F,D,I,E,O}
    map::M
    combine::C
    seed::S
    finish::F
    domain::D
    oninvalid::I
    onempty::E
    order::O
end

_device_type_parameter(::Type{<:BoundedFold}) = true

_device_evaluator_capture(domain::Where) =
    _bounded_fold_callable(domain.predicate)
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

"""
    bounded_fold(map, combine, seed, finish;
                 domain, oninvalid=RejectInvalid(),
                 onempty=RejectEmpty(), order=CanonicalLeftFold())

Construct a concrete immutable fold over a bounded relation gather or bounded
collection group. Absent lanes do not participate. Invalid and empty policies
are explicit, and rejection is reported through the containing stage's
transaction barrier.
"""
function bounded_fold(map, combine, seed, finish;
        domain,
        oninvalid = RejectInvalid(),
        onempty = RejectEmpty(),
        order = CanonicalLeftFold(),
    )
    domain isa Where || throw(LocalMathValidationError(
        "bounded_fold requires an explicit Where value domain";
        stage = :construct, contract = :bounded_fold_domain,
        expected = Where, actual = typeof(domain),
    ))
    oninvalid isa Union{RejectInvalid,SkipInvalid,FillInvalid} || throw(
        LocalMathValidationError(
            "bounded_fold has an unsupported invalid-value policy";
            stage = :construct, contract = :bounded_fold_invalid_policy,
            actual = typeof(oninvalid),
        ))
    onempty isa Union{RejectEmpty,FillEmpty} || throw(LocalMathValidationError(
        "bounded_fold has an unsupported empty policy";
        stage = :construct, contract = :bounded_fold_empty_policy,
        actual = typeof(onempty),
    ))
    order isa Union{CanonicalLeftFold,RelaxedAssociative} || throw(
        LocalMathValidationError(
            "bounded_fold requires canonical or relaxed-associative order";
            stage = :construct, contract = :bounded_fold_order,
            actual = typeof(order),
        ))
    for (callable, contract) in ((map, :bounded_fold_map),
            (combine, :bounded_fold_combine), (finish, :bounded_fold_finish))
        _bounded_fold_callable(callable) || throw(LocalMathValidationError(
            "bounded_fold callables must be concrete and device-admissible";
            stage = :construct, contract, actual = typeof(callable),
        ))
    end
    return BoundedFold(map, combine, seed, finish, domain, oninvalid,
        onempty, order)
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
        if !fold.domain.predicate(value)
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

@inline evaluate_bounded(sample_at, fold::BoundedFold, maximum::Integer) =
    evaluate_bounded(fold, maximum, sample_at)

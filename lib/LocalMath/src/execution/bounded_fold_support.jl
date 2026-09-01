struct _NoEvaluationValidation end
struct _CandidateEvaluationValidation{D}
    diagnostics::D
end
struct _OrderedFoldEvaluationValidation{S}
    status::S
end

@inline _evaluation_validation_fail!(::_NoEvaluationValidation, reason) = nothing
@inline _evaluation_validation_fail!(
        validation::_CandidateEvaluationValidation, ::Val{:invalid_value}) =
    _candidate_fail!(validation.diagnostics, _CANDIDATE_FAILURE_INVALID_VALUE)
@inline _evaluation_validation_fail!(
        validation::_CandidateEvaluationValidation, ::Val{:empty}) =
    _candidate_fail!(validation.diagnostics, _CANDIDATE_FAILURE_EMPTY_FOLD)
@inline _evaluation_validation_fail!(
        validation::_OrderedFoldEvaluationValidation, ::Val{:invalid_value}) =
    _candidate_atomic_max!(validation.status, 1,
        Int32(_ORDERED_FOLD_INVALID_VALUE))
@inline _evaluation_validation_fail!(
        validation::_OrderedFoldEvaluationValidation, ::Val{:empty}) =
    _candidate_atomic_max!(validation.status, 1,
        Int32(_ORDERED_FOLD_EMPTY_INPUT))

@inline _bounded_fold_validation(read::_StageRead) =
    getfield(read, :validation)
@inline _bounded_fold_validation(view::_AuthoringValues) =
    _bounded_fold_validation(getfield(view, :read))
@inline _bounded_fold_validation(view::_AuthoringSamples) =
    _bounded_fold_validation(getfield(view, :read))
@inline _bounded_fold_validation(view::BoundedGroupView) =
    getfield(view, :validation)

@inline _bounded_fold_input_count(input) = Int32(length(input))
@inline _bounded_fold_input_sample(input, index::Int32) = input[Int(index)]
@inline _bounded_fold_present(sample::_StageSample) = sample.present
@inline _bounded_sample_value(sample::_StageSample) = something(sample.value)
@inline _bounded_fold_present(value) = true
@inline _bounded_fold_value(value) = value
@inline _bounded_fold_evaluation_sample(sample::_StageSample) = sample
@inline _bounded_fold_evaluation_sample(value) =
    (present = true, value)

@inline _bounded_fold_reject!(input, reason::Val) =
    _evaluation_validation_fail!(_bounded_fold_validation(input), reason)

@inline function _bounded_fold_admit(fold::BoundedFold, input, value)
    fold.domain.predicate(value) && return (true, value)
    policy = fold.oninvalid
    policy isa SkipInvalid && return (false, value)
    policy isa FillInvalid && return (true, policy.value)
    _bounded_fold_reject!(input, Val(:invalid_value))
    return (false, value)
end

@inline function (fold::BoundedFold)(input)
    maximum = _bounded_fold_input_count(input)
    outcome = evaluate_bounded(fold, maximum) do index
        sample = _bounded_fold_input_sample(input, index)
        _bounded_fold_evaluation_sample(sample)
    end
    if !outcome.valid
        reason = outcome.reason == _BOUNDED_FOLD_INVALID_VALUE ?
            Val(:invalid_value) : Val(:empty)
        _bounded_fold_reject!(input, reason)
    end
    return outcome.value
end

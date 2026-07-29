module ConformanceHarness

using ..ReferenceSemantics: ReferenceState, AttemptAccounting, canonical_checksum,
    assert_valid_state, assert_reference_mcs

export ReferenceNumericalPolicy, portable_numerical_policy, validate_numerical_policy,
       AlgorithmGuaranteeProfile, validate_guarantee_profile,
       ConformanceCase, conformance_case_matrix, AbstractConformanceAdapter, reference_state,
       attempt_accounting, ReferenceStateAdapter, validate_adapter, qualify_adapter,
       ReproductionContext, ConformanceFailure,
       require_conformance, reproduction_report, StatisticalProcedure, statistical_procedure,
       assess_bernoulli, require_logical_match

"""Test-only expansion of the accepted orthogonal numerical-policy choices."""
struct ReferenceNumericalPolicy
    real::DataType
    accumulation::DataType
    math::Symbol
    reductions::Symbol
    overflow::Symbol
end

function ReferenceNumericalPolicy(; real::DataType = Float32, accumulation::DataType = real,
        math::Symbol = :accurate, reductions::Symbol = :deterministic,
        overflow::Symbol = :checked)
    policy = ReferenceNumericalPolicy(real, accumulation, math, reductions, overflow)
    validate_numerical_policy(policy)
    return policy
end

portable_numerical_policy(::Type{T} = Float32) where {T} =
    ReferenceNumericalPolicy(real = T, accumulation = T)

function validate_numerical_policy(policy::ReferenceNumericalPolicy)
    policy.real <: AbstractFloat || throw(ArgumentError("primary real type must be floating-point"))
    policy.accumulation <: AbstractFloat || throw(ArgumentError(
        "accumulation type must be floating-point"))
    policy.math in (:accurate, :qualified_fast) || throw(ArgumentError(
        "math must be :accurate or :qualified_fast"))
    policy.reductions in (:deterministic, :tolerant) || throw(ArgumentError(
        "reductions must be :deterministic or :tolerant"))
    policy.overflow in (:checked, :qualified_unchecked) || throw(ArgumentError(
        "overflow must be :checked or :qualified_unchecked"))
    return policy
end

"""Inspectable scientific guarantees for one named algorithm family."""
struct AlgorithmGuaranteeProfile
    name::Symbol
    proposal_process::Symbol
    equilibrium::Symbol
    kinetics::Symbol
    transactions::Symbol
    attempt_normalization::Symbol
    reproducibility::Symbol
    evidence::Symbol
end

function validate_guarantee_profile(profile::AlgorithmGuaranteeProfile)
    profile.name in (:sequential, :checkerboard, :lottery) || throw(ArgumentError(
        "conformance profiles must name a supported algorithm family"))
    profile.proposal_process in (:uniform_recipient_direction, :parallel_round) || throw(ArgumentError(
        "proposal_process must name the scientific proposal family"))
    profile.equilibrium in (:depends_on_acceptance_law, :unproven, :not_claimed) || throw(ArgumentError(
        "equilibrium must be a qualified claim"))
    profile.kinetics in (:reference, :parallel_distinct) || throw(ArgumentError(
        "kinetics must distinguish reference from parallel dynamics"))
    profile.transactions in (:sequential, :color_snapshot, :round_snapshot) || throw(ArgumentError(
        "transactions must name the committed transaction law"))
    profile.attempt_normalization in (:exact, :normalized, :expected) || throw(ArgumentError(
        "attempt_normalization must be :exact, :normalized, or :expected"))
    profile.reproducibility in (:strict_cpu, :profile_dependent, :statistical_only) || throw(ArgumentError(
        "reproducibility must be a qualified scope"))
    profile.evidence in (:reference, :proof_pending, :statistical_pending) || throw(ArgumentError(
        "evidence must name the current validation category"))
    profile.name === :sequential && profile.attempt_normalization !== :exact && throw(ArgumentError(
        "the sequential reference process must report exact attempt normalization"))
    profile.name === :lottery && profile.attempt_normalization !== :expected && throw(ArgumentError(
        "lottery must report expected proposal-budget normalization"))
    return profile
end

"""One logical conformance point, independent of an implementation's storage layout."""
struct ConformanceCase
    algorithm::Symbol
    numeric_type::DataType
    numerical_policy::ReferenceNumericalPolicy
    dimension::Int
    backend::Symbol
end

function ConformanceCase(; algorithm::Symbol, numeric_type::DataType, dimension::Integer,
        backend::Symbol, numerical_policy::ReferenceNumericalPolicy =
            portable_numerical_policy(numeric_type))
    dimension in (2, 3) || throw(ArgumentError(
        "transition conformance currently covers dimensions 2 and 3"))
    numerical_policy.real === numeric_type || throw(ArgumentError(
        "numeric_type must match the policy primary real type"))
    return ConformanceCase(algorithm, numeric_type, numerical_policy, Int(dimension), backend)
end

function conformance_case_matrix(; algorithms = (:sequential, :checkerboard, :lottery),
        numeric_types = (Float32, Float64), numerical_policies = nothing,
        dimensions = (2, 3), backends = (:cpu,))
    policies = numerical_policies === nothing ? portable_numerical_policy.(numeric_types) :
        collect(numerical_policies)
    return [ConformanceCase(algorithm = algorithm, numeric_type = policy.real,
        numerical_policy = policy, dimension = dimension, backend = backend)
        for algorithm in algorithms, policy in policies,
            dimension in dimensions, backend in backends]
end

"""
    AbstractConformanceAdapter

Test-only boundary through which a future CPU or GPU implementation exposes logical state and its
algorithm report. It intentionally accepts no physical arrays, workspace, or kernel detail.
"""
abstract type AbstractConformanceAdapter end

"""A complete scalar implementation adapter used to qualify the conformance boundary itself."""
struct ReferenceStateAdapter <: AbstractConformanceAdapter
    state::ReferenceState
    accounting::AttemptAccounting
end

function reference_state(adapter::AbstractConformanceAdapter)
    throw(MethodError(reference_state, (adapter,)))
end

function attempt_accounting(adapter::AbstractConformanceAdapter)
    throw(MethodError(attempt_accounting, (adapter,)))
end

reference_state(adapter::ReferenceStateAdapter) = adapter.state
attempt_accounting(adapter::ReferenceStateAdapter) = adapter.accounting

function validate_adapter(adapter::AbstractConformanceAdapter)
    state = reference_state(adapter)
    accounting = attempt_accounting(adapter)
    state isa ReferenceState || throw(ArgumentError("reference_state(adapter) must return ReferenceState"))
    accounting isa AttemptAccounting || throw(ArgumentError(
        "attempt_accounting(adapter) must return AttemptAccounting"))
    assert_valid_state(state)
    assert_reference_mcs(accounting)
    return (state_checksum = canonical_checksum(state), accounting = accounting)
end

struct ReproductionContext
    semantic_seed::UInt64
    rng_version::String
    model_fingerprint::String
    initial_state_checksum::String
    algorithm::Symbol
    numeric_type::DataType
    numerical_policy::ReferenceNumericalPolicy
    dimension::Int
    backend_report::String
    command::String
end

function ReproductionContext(; semantic_seed::Integer, rng_version::AbstractString,
        model_fingerprint::AbstractString, initial_state,
        algorithm::Symbol, numeric_type::DataType, dimension::Integer,
        backend_report::AbstractString, command::AbstractString,
        numerical_policy::ReferenceNumericalPolicy = portable_numerical_policy(numeric_type))
    semantic_seed >= 0 || throw(ArgumentError("semantic_seed must be non-negative"))
    isempty(rng_version) && throw(ArgumentError("rng_version must not be empty"))
    isempty(model_fingerprint) && throw(ArgumentError("model_fingerprint must not be empty"))
    isempty(backend_report) && throw(ArgumentError("backend_report must not be empty"))
    isempty(command) && throw(ArgumentError("reproduction command must not be empty"))
    dimension in (2, 3) || throw(ArgumentError("dimension must be 2 or 3"))
    numerical_policy.real === numeric_type || throw(ArgumentError(
        "numeric_type must match the numerical policy primary real type"))
    return ReproductionContext(UInt64(semantic_seed), String(rng_version), String(model_fingerprint),
        canonical_checksum(initial_state), algorithm, numeric_type, numerical_policy, Int(dimension),
        String(backend_report), String(command))
end

function reproduction_report(context::ReproductionContext)
    return join((
        "semantic_seed=0x$(string(context.semantic_seed; base = 16, pad = 16))",
        "rng_version=$(context.rng_version)",
        "model_fingerprint=$(context.model_fingerprint)",
        "initial_state_checksum=$(context.initial_state_checksum)",
        "algorithm=$(context.algorithm)",
        "numeric_type=$(context.numeric_type)",
        "numerical_policy=(real=$(context.numerical_policy.real), accumulation=$(context.numerical_policy.accumulation), math=$(context.numerical_policy.math), reductions=$(context.numerical_policy.reductions), overflow=$(context.numerical_policy.overflow))",
        "dimension=$(context.dimension)",
        "backend=$(context.backend_report)",
        "reproduce=$(context.command)",
    ), '\n')
end

struct ConformanceFailure <: Exception
    message::String
    context::ReproductionContext
    details::NamedTuple
end

function Base.showerror(io::IO, failure::ConformanceFailure)
    print(io, failure.message, '\n', reproduction_report(failure.context))
    isempty(failure.details) || print(io, '\n', "details=", failure.details)
end

function require_conformance(condition::Bool, message::AbstractString, context::ReproductionContext;
        details::NamedTuple = NamedTuple())
    condition || throw(ConformanceFailure(String(message), context, details))
    return nothing
end

"""Validate an implementation adapter and preserve a complete semantic reproducer on failure."""
function qualify_adapter(adapter::AbstractConformanceAdapter, context::ReproductionContext;
        expected_state::Union{Nothing, ReferenceState} = nothing)
    report = try
        validate_adapter(adapter)
    catch error
        error isa ConformanceFailure && rethrow()
        throw(ConformanceFailure("adapter invariant or accounting failure", context,
            (exception = sprint(showerror, error),)))
    end
    expected_state === nothing || require_logical_match(reference_state(adapter), expected_state, context)
    return report
end

function require_logical_match(actual::ReferenceState, expected::ReferenceState,
        context::ReproductionContext)
    actual_checksum = canonical_checksum(actual)
    expected_checksum = canonical_checksum(expected)
    require_conformance(actual_checksum == expected_checksum, "logical state differs from reference",
        context; details = (actual_checksum = actual_checksum, expected_checksum = expected_checksum))
    return nothing
end

"""Fixed statistical procedure metadata; actual draws are supplied by an algorithm adapter."""
struct StatisticalProcedure
    tier::Symbol
    minimum_trials::Int
    z_tolerance::Float64
end

function statistical_procedure(tier::Symbol)
    tier === :deterministic && return StatisticalProcedure(tier, 0, 0.0)
    tier === :ci && return StatisticalProcedure(tier, 10_000, 5.0)
    tier === :scheduled && return StatisticalProcedure(tier, 1_000_000, 5.5)
    throw(ArgumentError("tier must be :deterministic, :ci, or :scheduled"))
end

function assess_bernoulli(successes::Integer, trials::Integer, probability::Real,
        procedure::StatisticalProcedure)
    0 <= successes <= trials || throw(ArgumentError("successes must lie in 0:trials"))
    0 <= probability <= 1 || throw(ArgumentError("probability must lie in [0, 1]"))
    trials >= procedure.minimum_trials || return (
        pass = false, reason = :insufficient_trials, z_score = Inf,
        expected = trials * probability, observed = successes,
    )
    if probability == 0 || probability == 1
        expected = probability == 0 ? 0 : trials
        return (pass = successes == expected, reason = :exact_boundary, z_score = 0.0,
            expected = expected, observed = successes)
    end
    expected = trials * probability
    z_score = abs(successes - expected) / sqrt(trials * probability * (1 - probability))
    return (pass = z_score <= procedure.z_tolerance, reason = :z_score, z_score = z_score,
        expected = expected, observed = successes)
end

end

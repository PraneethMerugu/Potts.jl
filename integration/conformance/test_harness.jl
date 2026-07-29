using Test
using .ReferenceSemantics
using .ConformanceHarness

@testset "conformance harness" begin
    cases = conformance_case_matrix(backends = (:cpu, :metal))
    @test length(cases) == 24
    @test all(case -> case.dimension in (2, 3), cases)
    @test all(case -> case.numeric_type in (Float32, Float64), cases)
    @test all(case -> case.numerical_policy.reductions === :deterministic, cases)
    mixed_policy = ReferenceNumericalPolicy(real = Float32, accumulation = Float64,
        math = :qualified_fast, reductions = :tolerant, overflow = :qualified_unchecked)
    @test validate_numerical_policy(mixed_policy) === mixed_policy
    @test_throws ArgumentError ReferenceNumericalPolicy(real = Int32)
    sequential_profile = ConformanceHarness.AlgorithmGuaranteeProfile(
        :sequential, :uniform_recipient_direction,
        :depends_on_acceptance_law, :reference, :sequential, :exact, :strict_cpu, :reference)
    @test validate_guarantee_profile(sequential_profile) === sequential_profile
    lottery_profile = ConformanceHarness.AlgorithmGuaranteeProfile(
        :lottery, :parallel_round, :unproven,
        :parallel_distinct, :round_snapshot, :expected, :profile_dependent, :statistical_pending)
    @test validate_guarantee_profile(lottery_profile) === lottery_profile
    @test_throws ArgumentError validate_guarantee_profile(
        ConformanceHarness.AlgorithmGuaranteeProfile(:lottery,
        :parallel_round, :unproven, :parallel_distinct, :round_snapshot, :exact,
        :profile_dependent, :statistical_pending))

    state = ReferenceState((1, 1), Int32[0]; medium_ids = Int32[0])
    context = ReproductionContext(
        semantic_seed = 0x42,
        rng_version = "conformance-test-v1",
        model_fingerprint = "reference-fixture-v1",
        initial_state = state,
        algorithm = :sequential,
        numeric_type = Float32,
        dimension = 2,
        backend_report = "CPU scalar reference",
        command = "julia --project=integration integration/runtests.jl",
    )
    report = reproduction_report(context)
    @test occursin("semantic_seed=0x0000000000000042", report)
    @test occursin("initial_state_checksum=", report)
    @test occursin("numerical_policy=(real=Float32", report)
    failure = try
        require_conformance(false, "expected fixture failure", context; details = (attempts = 3,))
        nothing
    catch error
        error
    end
    @test failure isa ConformanceFailure
    @test occursin("reproduce=", sprint(showerror, failure))

    completed = AttemptAccounting(1)
    completed = record_attempt(completed, :no_op)
    validated = validate_adapter(ReferenceStateAdapter(state, completed))
    @test validated.state_checksum == canonical_checksum(state)
    @test require_logical_match(state, state, context) === nothing
    @test qualify_adapter(ReferenceStateAdapter(state, completed), context;
        expected_state = state).state_checksum == canonical_checksum(state)
    invalid_adapter = ReferenceStateAdapter(state, AttemptAccounting(1))
    adapter_failure = try
        qualify_adapter(invalid_adapter, context)
        nothing
    catch error
        error
    end
    @test adapter_failure isa ConformanceFailure
    @test occursin("semantic_seed=", sprint(showerror, adapter_failure))

    ci = statistical_procedure(:ci)
    @test assess_bernoulli(5_000, 10_000, 0.5, ci).pass
    @test !assess_bernoulli(5_300, 10_000, 0.5, ci).pass
    @test assess_bernoulli(0, 10_000, 0.0, ci).pass
    @test !assess_bernoulli(0, 10, 0.0, ci).pass
end

@testset "reference-layer independence" begin
    reference_source = read(joinpath(@__DIR__, "..", "reference", "ReferenceSemantics.jl"), String)
    harness_source = read(joinpath(@__DIR__, "ConformanceHarness.jl"), String)
    forbidden = r"(?m)^(using|import)\s+(CUDA|AMDGPU|Metal|KernelAbstractions|AcceleratedKernels|KernelIntrinsics)\b"
    @test !occursin(forbidden, reference_source)
    @test !occursin(forbidden, harness_source)
end

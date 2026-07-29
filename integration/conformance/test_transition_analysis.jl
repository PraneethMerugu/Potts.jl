using Test
using SparseArrays
using .TransitionKernelOracle
using .TransitionKernelAnalysis

@testset "transition-kernel transition-kernel analysis" begin
    fixture = hand_derived_1d_fixture()
    primitive = primitive_kernel(fixture.catalog, fixture.domain, fixture.model)
    normalized = sequential_mcs_kernel(fixture.catalog, fixture.domain, fixture.model)

    comparison = compare_kernels(primitive, normalized)
    @test comparison.maximum_total_variation == 1//4
    @test comparison.maximum_row in (2, 3)
    @test comparison.maximum_absolute_residual == 1//4
    @test isempty(comparison.added_support)
    @test isempty(comparison.missing_support)
    @test row_total_variation(primitive, normalized, 1) == 0

    classes = communicating_classes(normalized)
    @test classes == [[1], [2], [3], [4]]
    @test !is_irreducible(normalized)
    @test class_periods(normalized) == [(1, [1]), (1, [2]), (1, [3]), (1, [4])]
    @test is_aperiodic(normalized)

    two_state = sparse(Float64[0.8 0.2; 0.1 0.9])
    stationary = stationary_analysis(two_state)
    @test stationary.distribution ≈ [1 / 3, 2 / 3]
    @test stationary.stationarity_residual < 1e-12
    @test stationary.detailed_balance_residual < 1e-12
    @test stationary.nonnegative
    @test stationary.normalized
    currents = probability_currents(two_state, stationary.distribution)
    @test maximum(abs, currents) < 1e-12
    spectrum = spectral_analysis(two_state)
    @test spectrum.unit_eigenvalue_multiplicity == 1
    @test spectrum.spectral_gap ≈ 0.3
    @test spectrum.relaxation_time ≈ 10 / 3

    moments = observable_transition_moments(two_state, [0.0, 1.0])
    @test moments.drift ≈ [0.2, -0.1]
    @test moments.second_moment ≈ [0.2, 0.1]
    @test moments.diffusion ≈ [0.16, 0.09]

    periodic = sparse(Float64[0 1; 1 0])
    @test is_irreducible(periodic)
    @test !is_aperiodic(periodic)
    @test class_periods(periodic) == [(2, [1, 2])]
end

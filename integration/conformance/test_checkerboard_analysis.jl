using Test
using .TransitionKernelOracle
using .TransitionKernelAnalysis
using .CheckerboardOracle

@testset "checkerboard transition complete sequential-checkerboard characterization" begin
    medium = oracle_medium(1)
    cell = oracle_cell(1)
    domain = OracleDomain((3,); boundaries = (OraclePeriodic,))
    relation = von_neumann_relation(Val(1))
    model = OracleModel(relation;
        acceptance = OracleConventionalMetropolis(), temperature = 0)
    catalog = enumerate_states(domain, (medium, cell))

    sequential = sequential_mcs_kernel(catalog, domain, model)
    checkerboard = checkerboard_mcs_kernel(catalog, domain, model)
    comparison = compare_kernels(sequential, checkerboard)

    @test comparison.maximum_total_variation == 41 // 216
    @test comparison.maximum_absolute_residual == 5 // 54
    @test comparison.maximum_row == 2
    @test catalog.states[comparison.maximum_row] ==
        OracleMicrostate((cell, medium, medium))
    @test comparison.missing_support ==
        [(row, row) for row in 2:7]
    @test isempty(comparison.added_support)

    sequential_stationary = stationary_analysis(sequential)
    checkerboard_stationary = stationary_analysis(checkerboard)
    @test sequential_stationary.nonnegative
    @test checkerboard_stationary.nonnegative
    @test sequential_stationary.stationarity_residual < 1e-12
    @test checkerboard_stationary.stationarity_residual < 1e-12
    @test sequential_stationary.detailed_balance_residual < 1e-12
    @test checkerboard_stationary.detailed_balance_residual < 1e-12
    @test maximum(abs, sequential_stationary.distribution .-
        checkerboard_stationary.distribution) < 1e-12
    @test maximum(abs, probability_currents(
        sequential, sequential_stationary.distribution)) < 1e-12
    @test maximum(abs, probability_currents(
        checkerboard, checkerboard_stationary.distribution)) < 1e-12

    sequential_spectrum = spectral_analysis(sequential)
    checkerboard_spectrum = spectral_analysis(checkerboard)
    @test sequential_spectrum.unit_eigenvalue_multiplicity == 2
    @test checkerboard_spectrum.unit_eigenvalue_multiplicity == 2
    @test sequential_spectrum.spectral_gap ≈ 19 / 27
    @test checkerboard_spectrum.spectral_gap ≈ 5 / 6
    @test sequential_spectrum.relaxation_time ≈ 27 / 19
    @test checkerboard_spectrum.relaxation_time ≈ 6 / 5

    cell_volume = [count(==(cell), state.owners) for state in catalog.states]
    sequential_moments = observable_transition_moments(
        sequential, cell_volume)
    checkerboard_moments = observable_transition_moments(
        checkerboard, cell_volume)
    @test all(iszero, sequential_moments.drift)
    @test all(iszero, checkerboard_moments.drift)
    @test sequential_moments.diffusion != checkerboard_moments.diffusion
    @test sequential_moments.second_moment != checkerboard_moments.second_moment

    # This fixture proves a mechanistic kinetic difference. It does not support
    # a detailed-balance or stationary-distribution claim on the wider domain.
    @test comparison.maximum_total_variation > 3 // 20
end

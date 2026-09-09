include("fixtures/discrete_field_rhs.jl")

@testset "field clipping and late multi-site substep failure are transactional" begin
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        test_discrete_field_clipping_and_rollback(algorithm, CPUBackend())
    end
end

@testset "explicit field rates execute custom Julia expressions with physical units" begin
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        test_discrete_field_rhs(algorithm, CPUBackend())
    end
end

@testset "explicit field rates reject ambiguous formulas and incompatible units" begin
    @test_throws r"complete rate" init(discrete_field_rhs_problem(; field_options = (diffusion = 0.1,)), SequentialCPM())
    @test_throws r"field_rhs_units" init(discrete_field_rhs_problem(; rhs_override = 1.0u"m"), SequentialCPM())
    @test_throws r"positive integer, not Bool" init(discrete_field_rhs_problem(; substeps = true), SequentialCPM())
end

@testset "stochastic field substeps preserve site identity and checkpoint continuation" begin
    reference = test_discrete_field_rhs(SequentialCPM(), CPUBackend(); stochastic = true)
    @test test_discrete_field_rhs(CheckerboardSweepCPM(), CPUBackend(); stochastic = true) == reference
    @test test_discrete_field_rhs(SequentialCPM(), CPUBackend(); stochastic = true, reordered = true) == reference
    @test test_discrete_field_rhs(SequentialCPM(), CPUBackend(); stochastic = true, reordered = true, unrelated = true) == reference
    @test test_discrete_field_rhs(SequentialCPM(), CPUBackend(); stochastic = true, seed = 18) != reference
end

@testset "field substeps use fresh addressed forcing rather than a repeated whole-MCS draw" begin
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        one_step = init(discrete_field_rhs_problem(; stochastic = true, substeps = 1, loss_rate = 0.0u"s^-1", baseline = 0.0u"m/s"), algorithm; scalar_type = Float32)
        two_steps = init(discrete_field_rhs_problem(; stochastic = true, substeps = 2, loss_rate = 0.0u"s^-1", baseline = 0.0u"m/s"), algorithm; scalar_type = Float32)
        step!(one_step)
        step!(two_steps)
        # Reusing invocation zero twice would give the identical value here:
        # each half-step would apply half of the same state-independent rate.
        @test Array(one_step.u[:concentration]) != Array(two_steps.u[:concentration])
    end
end

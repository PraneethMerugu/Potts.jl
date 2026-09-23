include("fixtures/discrete_field_rhs.jl")

@testset "explicit field rates reject ambiguous formulas and incompatible units" begin
    @test_throws r"complete rate" init(discrete_field_rhs_problem(; field_options = (diffusion = 0.1,)), SequentialCPM())
    @test_throws r"field_rhs_units" init(discrete_field_rhs_problem(; rhs_override = 1.0u"m"), SequentialCPM())
    @test_throws r"positive integer, not Bool" init(discrete_field_rhs_problem(; substeps = true), SequentialCPM())
    @parameters wrapped_symbol
    wrapped = DynamicQuantities.Quantity(wrapped_symbol; length = 1, time = -1)
    @test_throws r"unsupported_symbolic_quantity" init(discrete_field_rhs_problem(; rhs_override = wrapped), SequentialCPM())
    @variables frozen_field
    for evolution in (nothing, :unsupported_evolution)
        frozen_source = PottsSystem(
            name = :unprocessed_field,
            statements = StatementSet(
                (
                    Lattice((1, 1); boundary = Closed()), MediumKind(:medium),
                    FieldState(frozen_field; initial = 0.0, evolution, rhs = draw(Uniform(), DrawKey(:unused))),
                    Protocol(Sweep(; temperature = 0.0); name = :main),
                )
            ), unknowns = (frozen_field,),
        )
        @test_throws r"illegal_random_operation_context" complete(frozen_source)
    end
    for placement in (:initial, :duration_per_mcs, :substeps, :diffusion)
        options = merge(
            (initial = 0.0, evolution = DiscreteFieldEuler(), rhs = draw(Uniform(), DrawKey(:rate))),
            NamedTuple{(placement,)}((draw(Uniform(), DrawKey(:misplaced)),)),
        )
        misplaced_source = PottsSystem(
            name = :misplaced_field_draw,
            statements = StatementSet(
                (
                    Lattice((1, 1); boundary = Closed()), MediumKind(:medium),
                    FieldState(frozen_field; options...),
                    Protocol(Sweep(; temperature = 0.0); name = :main),
                )
            ), unknowns = (frozen_field,),
        )
        @test_throws r"illegal_random_operation_context" complete(misplaced_source)
    end
end

@testset "concrete dimensional rate literals reach ordinary lowering" begin
    analysis = Potts._analyze_completed_system(discrete_field_rhs_problem(; rhs_override = 1.0u"m/s").system)
    root = only(filter(root -> root.role === :field_rhs, analysis.graph.roots))
    @test analysis.facts.result_type[root.node] === Float64
    @test analysis.facts.units[root.node] == DynamicQuantities.dimension(1.0u"m/s")
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        integrator = init(discrete_field_rhs_problem(; rhs_override = 1.0u"m/s"), algorithm; scalar_type = Float32)
        step!(integrator)
        @test Array(integrator.u[:concentration]) ≈ fill(0.5f0, 3, 2)
        @test failure_report(integrator) === nothing
    end
end

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

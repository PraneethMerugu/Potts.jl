using DynamicQuantities
using ModelingToolkitBase: complete
using Symbolics

# An ordinary Julia helper inlines symbolically; it needs no operation registration.
_local_field_rate(value, forcing, loss, noise) = forcing - loss * value + noise

function discrete_field_rhs_problem(; stochastic = false, reordered = false, unrelated = false, seed = 17, shape = (3, 2), substeps = 2, loss_rate = 0.2u"s^-1", baseline = 1.0u"m/s", rhs_override = nothing, field_options = (;))
    @variables concentration forcing extra
    @parameters loss = loss_rate amplitude = 0.25u"m/s"
    noise = stochastic ? draw(Uniform(0.5, 1.5), DrawKey(:field_forcing)) : 1.0
    rhs = rhs_override === nothing ? _local_field_rate(concentration, forcing, loss, amplitude * noise) : rhs_override
    field = FieldState(
        concentration; initial = 0.0u"m", evolution = DiscreteFieldEuler(), rhs,
        duration_per_mcs = 1.0u"s", substeps, field_options...
    )
    drive = ModelState(forcing; initial = baseline)
    medium = MediumKind(:medium)
    declarations = reordered ? (drive, field) : (field, drive)
    extras = unrelated ? (
            ModelState(extra; initial = 0.0),
            Synchronous(:unrelated_sample, Assign(extra, draw(Uniform(), DrawKey(:unrelated)))),
        ) : ()
    source = PottsSystem(
        name = :local_field_model,
        statements = StatementSet(
            (
                Lattice(shape; boundary = Closed()), medium, extras..., declarations...,
                ProposalConstraint(:fixed_ownership, false),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ), unknowns = unrelated ? (concentration, forcing, extra) : (concentration, forcing), parameters = (loss, amplitude)
    )
    completed = complete(source; reference_units = ReferenceUnits(length = 2.0u"m", time = 0.5u"s", rate = 11.0u"m/s", inverse_time = 7.0u"s^-1"))
    initial = PottsInitialState(ownership = LabelledCells(zeros(Int, shape); cells = CellKind[], medium))
    return PottsProblem(completed, initial, (0, 3); seed)
end

function test_discrete_field_rhs(algorithm, backend; stochastic = false, reordered = false, unrelated = false, shape = (3, 2), seed = 17)
    problem = discrete_field_rhs_problem(; stochastic, reordered, unrelated, shape, seed)
    integrator = init(problem, algorithm; backend, scalar_type = Float32)
    outputs = []
    restored = nothing
    lower = upper = expected = 0.0
    for boundary in 1:3
        step!(integrator)
        values = Array(integrator.u[:concentration])
        push!(outputs, values)
        # Independent physical-units Euler recurrence; stored values are metres / 2.
        for _ in 1:2
            expected += 0.5 * (1.0 - 0.2 * expected + 0.25)
            lower += 0.5 * (1.0 - 0.2 * lower + 0.25 * 0.5)
            upper += 0.5 * (1.0 - 0.2 * upper + 0.25 * 1.5)
        end
        @test failure_report(integrator) === nothing
        @test all(isfinite, values)
        @test all(iszero, Array(integrator.u.ownership))
        if stochastic
            @test all(value -> lower / 2 < value < upper / 2, values)
            @test length(unique(vec(values))) > 1
        else
            @test values ≈ fill(expected / 2, shape) rtol = 2.0e-6
        end
        if restored === nothing
            restored = init(problem, algorithm; backend, scalar_type = Float32, checkpoint = checkpoint(integrator))
        else
            step!(restored)
        end
        @test Array(restored.u[:concentration]) == values
    end
    return outputs
end

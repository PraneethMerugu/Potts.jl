include("fixtures/structured_random_continuation.jl")

@testset "structured scheduled randomness retains identity and checkpoint continuation" begin
    reference = nothing
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        values = _structured_random_continuation_contract(algorithm, CPUBackend())
        before = _structured_random_continuation_contract(
            algorithm, CPUBackend(); unrelated = :before,
        )
        after = _structured_random_continuation_contract(
            algorithm, CPUBackend(); unrelated = :after,
        )
        @test before == values
        @test after == values
        reference === nothing || @test values == reference
        reference = values
    end
end

@testset "structured assignment schemas and dimensions fail at the exact field path" begin
    function assignment_problem(value)
        @variables memory::NamedTuple{(:outer, :flat), Tuple{NamedTuple{(:distance, :duration), Tuple{Float64, Float64}}, Float64}}
        state = ModelState(memory; initial = (
            outer = (distance = 1.0, duration = 1.0), flat = 0.0,
        ))
        process = only(@statements begin
            Synchronous(:replace, Assign(memory, value))
        end)
        cell = CellKind(:cell; extinction = RetireAtZero())
        medium = MediumKind(:medium)
        source = PottsSystem(
            name = :structured_assignment_validation,
            statements = StatementSet((
                Lattice((2, 2); boundary = Closed()), cell, medium, state,
                process,
                ProposalConstraint(:fixed_ownership, false),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )),
            unknowns = (memory,),
        )
        completed = complete(source)
        initial = PottsInitialState(
            ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium),
        )
        return PottsProblem(completed, initial, (0, 1); seed = 0x517)
    end

    valid = (
        outer = (distance = 2.0, duration = 3.0), flat = 0.5,
    )
    result = solve(assignment_problem(valid), SequentialCPM(); scalar_type = Float32)
    @test result.u[end][:memory] === (
        outer = (distance = 2.0f0, duration = 3.0f0), flat = 0.5f0,
    )

    failures = (
        ((flat = 0.5,), "value", "fields (:outer, :flat)"),
        ((outer = (distance = 2.0, duration = 3.0), flat = 0.5, extra = 1.0), "value", "extra"),
        ((flat = 0.5, outer = (distance = 2.0, duration = 3.0)), "value", "declared order"),
        ((outer = (duration = 3.0, distance = 2.0), flat = 0.5), "value.outer", "declared order"),
    )
    for (value, path, detail) in failures
        error = try
            init(assignment_problem(value), SequentialCPM(); scalar_type = Float32)
            nothing
        catch caught
            caught
        end
        @test error isa Potts.PottsValidationError
        rendered = sprint(showerror, error)
        @test occursin(path, rendered)
        @test occursin(detail, rendered)
        @test occursin(@__FILE__, rendered)
    end

    function dimensional_assignment_problem(swap::Symbol)
        @variables memory::NamedTuple{(:outer,), Tuple{NamedTuple{(:distance, :duration), Tuple{Float64, Float64}}}}
        @parameters distance = 2.0u"m" duration = 3.0u"s"
        value = swap === :distance ? (outer = (distance = duration, duration = duration),) :
            (outer = (distance = distance, duration = distance),)
        process = only(@statements begin
            Synchronous(:replace, Assign(memory, value))
        end)
        cell = CellKind(:cell; extinction = RetireAtZero())
        medium = MediumKind(:medium)
        source = PottsSystem(
            name = :dimensional_assignment_validation,
            statements = StatementSet((
                Lattice((2, 2); boundary = Closed()), cell, medium,
                ModelState(memory; initial = (outer = (distance = 1.0u"m", duration = 1.0u"s"),)),
                process,
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )), unknowns = (memory,), parameters = (distance, duration),
        )
        completed = complete(
            source; reference_units = ReferenceUnits(length = 1.0u"m", time = 1.0u"s"),
        )
        initial = PottsInitialState(
            ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium),
        )
        return PottsProblem(completed, initial, (0, 1); seed = 0x518)
    end
    for (swap, path) in (
            (:distance, "value.outer.distance"),
            (:duration, "value.outer.duration"),
        )
        error = try
            init(dimensional_assignment_problem(swap), SequentialCPM(); scalar_type = Float32)
            nothing
        catch caught
            caught
        end
        @test error isa Potts.PottsValidationError
        rendered = sprint(showerror, error)
        @test occursin(path, rendered)
        @test occursin("assignment value units", rendered)
        @test occursin(@__FILE__, rendered)
    end
end

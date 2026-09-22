using Symbolics

function _structured_random_continuation_problem(; unrelated = false)
    @variables memory::NamedTuple{(:sample, :previous), Tuple{Float64, Float64}}
    @variables signal
    @variables unrelated_value
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    extras = unrelated ? (
        ModelState(unrelated_value; initial = 0.0),
        Synchronous(
            :unrelated_sample,
            Assign(unrelated_value, draw(Uniform(), DrawKey(:unrelated_sample))),
        ),
    ) : ()
    source = PottsSystem(
        name = :structured_random_continuation,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed(), max_cells = 1), cell, medium,
                ModelState(signal; initial = 0.25),
                ModelState(memory; initial = (sample = 0.25, previous = -1.0)),
                extras...,
                Synchronous(
                    :sample,
                    Assign(signal, draw(Uniform(), DrawKey(:structured_sample))),
                ),
                ProposalConstraint(:fixed_ownership, false),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = unrelated ? (signal, memory, unrelated_value) : (signal, memory),
    )
    initial = PottsInitialState(
        ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium),
    )
    return PottsProblem(source, initial, (0, 4); seed = 0x9265)
end

function _structured_random_continuation_contract(algorithm, backend; unrelated = false)
    problem = _structured_random_continuation_problem(; unrelated)
    integrator = init(problem, algorithm; backend, scalar_type = Float32)
    initial = integrator.u[:memory]
    @test initial === (sample = 0.25f0, previous = -1.0f0)

    step!(integrator)
    restored = init(
        problem, algorithm; backend, scalar_type = Float32,
        checkpoint = checkpoint(integrator),
    )
    @test 0.0f0 < integrator.u[:signal] < 1.0f0
    @test restored.u[:signal] === integrator.u[:signal]
    @test restored.u[:memory] === integrator.u[:memory]

    @test integrator.u[:memory] === initial
    values = [(signal = integrator.u[:signal], memory = integrator.u[:memory])]
    for boundary in 2:4
        prior = last(values)
        step!(integrator)
        step!(restored)
        current = (signal = integrator.u[:signal], memory = integrator.u[:memory])
        @test current === (signal = restored.u[:signal], memory = restored.u[:memory])
        @test current.memory === prior.memory === initial
        @test 0.0f0 < current.signal < 1.0f0
        @test integrator.t == restored.t == boundary
        @test failure_report(integrator) === nothing
        @test failure_report(restored) === nothing
        push!(values, current)
    end
    return values
end

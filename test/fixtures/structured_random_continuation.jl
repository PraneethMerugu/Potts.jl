using Symbolics
using DynamicQuantities
using ModelingToolkitBase

function _structured_random_continuation_problem(; unrelated = :none)
    @variables memory::NamedTuple{(:sample, :previous, :a, :a_b, :physical), Tuple{Float64, Float64, NamedTuple{(:b,), Tuple{Float64}}, Float64, NamedTuple{(:distance, :duration), Tuple{Float64, Float64}}}}
    @variables signal
    @variables unrelated_value
    @parameters distance_scale = 1.0u"m" duration_scale = 1.0u"s"
    cell = CellKind(:cell; extinction = RetireAtZero())
    medium = MediumKind(:medium)
    memory_state = ModelState(memory; initial = (
        sample = 0.25, previous = -1.0, a = (b = 0.1,), a_b = 0.2,
        physical = (distance = 1.0u"m", duration = 1.0u"s"),
    ))
    extra = (
        ModelState(unrelated_value; initial = 0.0),
        Synchronous(
            :unrelated_sample,
            Assign(unrelated_value, draw(Uniform(), DrawKey(:unrelated_sample))),
        ),
    )
    prefix = unrelated === :before ? extra : ()
    suffix = unrelated === :after ? extra : ()
    source = PottsSystem(
        name = :structured_random_continuation,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed(), max_cells = 1), cell, medium,
                ModelState(signal; initial = 0.25), memory_state, prefix...,
                Synchronous(
                    :sample,
                    Assign(signal, draw(Uniform(), DrawKey(:scalar_sample))),
                    Assign(
                        memory,
                        (
                            sample = draw(Uniform(), DrawKey(:structured_sample)),
                            previous = memory_state.sample,
                            a = (b = draw(Uniform(), DrawKey(:nested_a_b)),),
                            a_b = draw(Uniform(), DrawKey(:flat_a_b)),
                            physical = (
                                distance = draw(Uniform(), DrawKey(:distance)) * distance_scale,
                                duration = draw(Uniform(), DrawKey(:duration)) * duration_scale,
                            ),
                        ),
                    ),
                ),
                suffix...,
                ProposalConstraint(:fixed_ownership, false),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        unknowns = unrelated === :none ? (signal, memory) : (signal, memory, unrelated_value),
        parameters = (distance_scale, duration_scale),
    )
    initial = PottsInitialState(
        ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium),
    )
    completed = complete(
        source; reference_units = ReferenceUnits(length = 1.0u"m", time = 1.0u"s"),
    )
    return PottsProblem(completed, initial, (0, 4); seed = 0x9265)
end

function _structured_random_continuation_contract(algorithm, backend; unrelated = :none)
    problem = _structured_random_continuation_problem(; unrelated)
    integrator = init(problem, algorithm; backend, scalar_type = Float32)
    initial = integrator.u[:memory]
    @test initial === (
        sample = 0.25f0, previous = -1.0f0, a = (b = 0.1f0,), a_b = 0.2f0,
        physical = (distance = 1.0f0, duration = 1.0f0),
    )

    step!(integrator)
    restored = init(
        problem, algorithm; backend, scalar_type = Float32,
        checkpoint = checkpoint(integrator),
    )
    @test 0.0f0 < integrator.u[:signal] < 1.0f0
    @test restored.u[:signal] === integrator.u[:signal]
    @test restored.u[:memory] === integrator.u[:memory]
    @test integrator.u[:memory].previous === initial.sample
    @test 0.0f0 < integrator.u[:memory].sample < 1.0f0
    @test integrator.u[:memory].a.b != integrator.u[:memory].a_b
    values = [(signal = integrator.u[:signal], memory = integrator.u[:memory])]
    for boundary in 2:4
        prior = last(values)
        step!(integrator)
        step!(restored)
        current = (signal = integrator.u[:signal], memory = integrator.u[:memory])
        @test current === (signal = restored.u[:signal], memory = restored.u[:memory])
        @test current.memory.previous === prior.memory.sample
        @test current.memory.sample !== prior.memory.sample
        @test current.memory.a.b !== prior.memory.a.b
        @test current.memory.a_b !== prior.memory.a_b
        @test current.memory.a.b != current.memory.a_b
        @test 0.0f0 < current.signal < 1.0f0
        @test 0.0f0 < current.memory.sample < 1.0f0
        @test integrator.t == restored.t == boundary
        @test failure_report(integrator) === nothing
        @test failure_report(restored) === nothing
        push!(values, current)
    end
    @test length(unique(value.signal for value in values)) == length(values)
    @test length(unique(value.memory.sample for value in values)) == length(values)
    return values
end

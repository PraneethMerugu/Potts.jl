using StaticArrays

@testset "typed lag preserves symbolic samples and commutes product fields" begin
    @variables vector_memory[1:2]
    @variables product_memory::NamedTuple{(:amount, :enabled), Tuple{Float64, Bool}}
    @variables product_source::NamedTuple{(:amount, :enabled), Tuple{Float64, Bool}}
    history = HistoryState(product_memory; of = product_source, depth = 3)
    sampled = lag(vector_memory, 0)
    @test size(sampled) == (2,)
    @test Symbolics.symtype(Symbolics.unwrap(lag(product_memory, 1))) === NamedTuple{(:amount, :enabled), Tuple{Float64, Bool}}
    expression = lag(history.amount, 1) + lag(history.amount, 0)
    @test length(Symbolics.get_variables(expression)) == 1
    @test isequal(Symbolics.unwrap(only(Symbolics.get_variables(expression))), Symbolics.unwrap(product_memory))
    scoped = ModelingToolkitBase.renamespace(:sensor, product_memory)
    substituted = Symbolics.substitute(expression, Dict(product_memory => scoped))
    @test isequal(Symbolics.unwrap(only(Symbolics.get_variables(substituted))), Symbolics.unwrap(scoped))
    @test Symbolics.symtype(Symbolics.unwrap(lag(history.enabled, 0))) === Bool
end

@testset "namespaced structured samples retain units and long dense history" begin
    @variables position[1:2] position_memory[1:2] rotated[1:2]
    @variables tensor[1:2, 1:2] tensor_memory[1:2, 1:2] tensor_copy[1:2, 1:2]
    @variables product::NamedTuple{(:amount, :enabled), Tuple{Float64, Bool}}
    @variables product_memory::NamedTuple{(:amount, :enabled), Tuple{Float64, Bool}}
    @variables product_copy::NamedTuple{(:amount, :enabled), Tuple{Float64, Bool}}
    @variables amount oldest
    history = HistoryState(product_memory; of = product, depth = 257, initial = 0)
    child = PottsSystem(
        name = :sensor,
        statements = StatementSet(
            (
                ModelState(position; initial = SVector(2.0u"m", 4.0u"m")),
                HistoryState(position_memory; of = position, depth = 257, initial = 0),
                ModelState(rotated; initial = SVector(0.0u"m", 0.0u"m")),
                ModelState(tensor; initial = SMatrix{2, 2}(1.0, 2.0, 3.0, 4.0)),
                HistoryState(tensor_memory; of = tensor, depth = 2, initial = 0),
                ModelState(tensor_copy; initial = zero(SMatrix{2, 2, Float64})),
                ModelState(product; initial = (amount = 6.0u"m", enabled = true)), history,
                ModelState(product_copy; initial = (amount = 0.0u"m", enabled = false)),
                ModelState(amount; initial = 0.0u"m"),
                ModelState(oldest; initial = 0.0u"m"),
                Synchronous(
                    :sample_feedback,
                    Assign(rotated, SVector(lag(position_memory, 0)[2], -lag(position_memory, 0)[1])),
                    Assign(product_copy, lag(product_memory, 0)),
                    Assign(amount, lag(history.amount, 0) + lag(history.amount, 1)),
                    Assign(tensor_copy, lag(tensor_memory, 0)),
                    Assign(oldest, lag(position_memory, 256)[1]),
                ),
            )
        ),
        unknowns = (position, position_memory, rotated, tensor, tensor_memory, tensor_copy, product, product_memory, product_copy, amount, oldest),
    )
    cell = CellKind(:cell; extinction = ForbidExtinction())
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :structured_history,
        systems = (child,),
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed(), max_cells = 1), cell, medium,
                ProposalConstraint(:held_ownership, false),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
    )
    completed = complete(source; reference_units = ReferenceUnits(length = 2.0u"m"))
    invalid = PottsSystem(
        name = :invalid_deep_sample,
        statements = StatementSet(
            (
                ModelState(position; initial = SVector(1.0, 2.0)),
                HistoryState(position_memory; of = position, depth = 257),
                ModelState(oldest; initial = 0.0),
                Synchronous(:read, Assign(oldest, lag(position_memory, 257)[1])),
            )
        ),
    )
    @test_throws r"invalid_history_lag" mtkcompile(complete(invalid))
    initial = PottsInitialState(ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium))
    problem = PottsProblem(completed, initial, (0, 3); seed = 17)
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        integrator = init(problem, algorithm; scalar_type = Float32)
        @test length(integrator.u[:sensor₊position_memory]) == 257
        @test length(integrator.u[:sensor₊product_memory]) == 257
        step!(integrator)
        @test integrator.u[:sensor₊rotated] == SVector(0.0f0, 0.0f0)
        @test integrator.u[:sensor₊product_copy] === (amount = 0.0f0, enabled = false)
        @test integrator.u[:sensor₊amount] == 0.0f0
        @test integrator.u[:sensor₊tensor_copy] == zero(SMatrix{2, 2, Float32})
        restored = init(problem, algorithm; scalar_type = Float32, checkpoint = checkpoint(integrator))
        for current in (integrator, restored)
            step!(current)
            @test current.u[:sensor₊rotated] == SVector(2.0f0, -1.0f0)
            @test current.u[:sensor₊product_copy] === (amount = 3.0f0, enabled = true)
            @test current.u[:sensor₊amount] == 3.0f0
            @test current.u[:sensor₊tensor_copy] == SMatrix{2, 2}(1.0f0, 2.0f0, 3.0f0, 4.0f0)
            @test first(current.u[:sensor₊position_memory]) == SVector(0.0f0, 0.0f0)
            @test last(current.u[:sensor₊position_memory]) == SVector(1.0f0, 2.0f0)
            @test current.u[:sensor₊oldest] == 0.0f0
            step!(current)
            @test current.u[:sensor₊amount] == 6.0f0
            @test failure_report(current) === nothing
        end
    end
end

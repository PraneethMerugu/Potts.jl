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

include("fixtures/history_structured_samples.jl")

@testset "history sampling rejects an offset beyond retained storage" begin
    @variables position[1:2] position_memory[1:2] oldest
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
end

@testset "namespaced structured samples retain units and long dense history" begin
    test_structured_history_samples((SequentialCPM(), CheckerboardSweepCPM()))
end

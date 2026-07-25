using StaticArrays: SVector
using CorePotts: CellHistory, MissingUntilFull, Lag,
    initialize_cell_history, history_value, maybe_history_value,
    sample_history!

@testset "Phase 14 device-ready bounded cell history" begin
    declaration = CellHistory(:wang_centroid_history;
        source = :centroid, length = 5, initial = MissingUntilFull())
    generations = [CellGeneration(1), CellGeneration(1)]
    initial = [SVector(0.0f0, 0.0f0), SVector(10.0f0, 10.0f0)]
    state = initialize_cell_history(declaration, initial, generations)

    @test state.values isa AbstractMatrix{SVector{2, Float32}}
    @test size(state.values) == (2, 5)
    @test state.heads == UInt32[0, 0]
    @test state.fills == UInt32[0, 0]

    active = Bool[true, true]
    for mcs in 0:6
        samples = [
            SVector(Float32(mcs), Float32(2mcs)),
            SVector(Float32(10 + mcs), Float32(20 + mcs)),
        ]
        sample_history!(state, samples, active, generations, mcs)
    end
    @test history_value(
        state, CellID(1), CellGeneration(1), Lag(0)) == SVector(6.0f0, 12.0f0)
    # The source appends the current sample and then selects Python index -5:
    # current t=6 minus the sample four MCS intervals earlier at t=2.
    @test history_value(
        state, CellID(1), CellGeneration(1), Lag(4)) == SVector(2.0f0, 4.0f0)

    execution = CorePotts.CellHistoryExecutionState(state)
    @test maybe_history_value(
        execution, CellID(1), CellGeneration(1), Lag(4)).value ==
        SVector(2.0f0, 4.0f0)
    @test !maybe_history_value(
        execution, CellID(1), CellGeneration(2), Lag(0)).available
    @test !maybe_history_value(
        execution, CellID(3), CellGeneration(1), Lag(0)).available

    adapted = CorePotts.Adapt.adapt(Array, state)
    adapted_execution = CorePotts.Adapt.adapt(
        Array, CorePotts.CellHistoryExecutionState(adapted))
    @test adapted.values == state.values
    @test adapted.heads == state.heads
    @test adapted.fills == state.fills
    @test adapted.generations == state.generations
    @test adapted_execution.values === adapted.values
    @test fieldcount(typeof(adapted_execution)) == 4
    reusable_samples = [
        SVector(8.0f0, 16.0f0), SVector(18.0f0, 28.0f0)]
    sample_history!(state, reusable_samples, active, generations, 8)
    @test (@allocated sample_history!(
        state, reusable_samples, active, generations, 9)) == 0

    # A stale generation anywhere in the synchronous input rejects before any slot publishes.
    before = deepcopy(state)
    @test_throws ArgumentError sample_history!(
        state,
        [SVector(99.0f0, 99.0f0), SVector(99.0f0, 99.0f0)],
        active,
        [CellGeneration(1), CellGeneration(2)],
        7)
    @test state.values == before.values
    @test state.heads == before.heads
    @test state.fills == before.fills
    @test state.latest_sample_mcs == before.latest_sample_mcs
    @test_throws ArgumentError sample_history!(
        state, initial, active, generations, -1)
end

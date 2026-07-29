import ProcessBigraphs: AbstractProcess, AbstractStep, ports, invoke,
    semantic_parameters

struct PB0Increment <: AbstractProcess
    amount::Int
end
ports(::PB0Increment) = (
    InputPort(Int, :state),
    OutputPort(Int, :increment; update_law=:add),
)
semantic_parameters(law::PB0Increment) = (amount=law.amount,)
function invoke(law::PB0Increment, inputs, context)
    InvocationResult(
        (emit(context, :increment, AdditiveUpdate(), law.amount),);
        continuation=(calls=isnothing(context.continuation) ? 1 :
            context.continuation.calls + 1,),
        diagnostics=(observed=inputs[:state], elapsed=context.elapsed.tick),
    )
end

struct PB0Elapsed <: AbstractProcess end
ports(::PB0Elapsed) = (OutputPort(Int, :elapsed; update_law=:add),)
function invoke(::PB0Elapsed, inputs, context)
    InvocationResult((emit(context, :elapsed, AdditiveUpdate(),
        Int(context.elapsed.tick)),))
end

struct PB0Fail <: AbstractProcess end
ports(::PB0Fail) = (OutputPort(Int, :out; update_law=:add),)
invoke(::PB0Fail, inputs, context) =
    throw(ProcessBigraphError(:fixture_failure, "requested failure"))

struct PB0ForkStep <: AbstractStep
    port::Symbol
    amount::Int
end
ports(law::PB0ForkStep) = (OutputPort(Int, law.port; update_law=:add),)
semantic_parameters(law::PB0ForkStep) = (port=law.port, amount=law.amount)
invoke(law::PB0ForkStep, inputs, context) =
    InvocationResult((emit(context, law.port, AdditiveUpdate(), law.amount),))

struct PB0JoinStep <: AbstractStep end
ports(::PB0JoinStep) = (
    InputPort(Int, :left),
    InputPort(Int, :right),
    OutputPort(Int, :total; update_law=:add),
)
invoke(::PB0JoinStep, inputs, context) =
    InvocationResult((emit(context, :total, AdditiveUpdate(),
        inputs[:left] + inputs[:right]),))

function increment_fixture(order=("fast", "slow"))
    scale = TimeScale(1)
    schema = BranchSchema(state=LeafSchema(Int; default=0, update_law=:add))
    definitions = Dict(
        "fast" => (amount=1, cadence=1),
        "slow" => (amount=10, cadence=2),
    )
    model = compose(:PB0IncrementFixture, schema; scale) do builder, stores
        for id in order
            definition = definitions[id]
            actor = mount!(
                builder, Symbol(id), PB0Increment(definition.amount))
            schedule!(
                builder, actor,
                Every(Duration(definition.cadence, scale)))
            attach!(builder, actor, (
                state=stores.state,
                increment=stores.state,
            ))
        end
    end
    compile(model)
end

@testset "imminent events, same-time snapshot, and declaration-order invariance" begin
    compiled = increment_fixture(("fast", "slow"))
    @test model_fingerprint(compiled) ==
        "49614f983db7f29d5c19465db95f5a367211a2ddea514fbf6d653f1fbfc90e30"
    @test snapshot_fingerprint(compiled.initial) ==
        "abb28a87d163574e612fabe68ecfbc57cfb234eb312e66fba564bf71a509e573"
    left = initialize_runtime(compiled)
    right = initialize_runtime(increment_fixture(("slow", "fast")))
    run_until!(left, LogicalTime(4, TimeScale(1)))
    run_until!(right, LogicalTime(4, TimeScale(1)))
    @test current_snapshot(left)[path("state")] == 24
    @test current_snapshot(right)[path("state")] == 24
    @test materialize(current_snapshot(left)) == materialize(current_snapshot(right))
    @test snapshot_fingerprint(current_snapshot(left)) ==
        "20b33b31def9e172bc7c9a57d4915f18094689667338e0eed90b70aac9ae4a3a"
    @test event_count(left) == 4
end

@testset "actual elapsed partial interval and preflight rejection" begin
    scale = TimeScale(1)
    schema = BranchSchema(elapsed=LeafSchema(Int; default=0, update_law=:add))
    model = compose(:ElapsedFixture, schema; scale) do builder, stores
        process = mount!(builder, :elapsed, PB0Elapsed())
        schedule!(builder, process, Every(Duration(2, scale)))
        attach!(builder, process, (elapsed=stores.elapsed,))
    end
    compiled = compile(model)
    runtime = initialize_runtime(compiled)
    run_until!(runtime, LogicalTime(3, scale))
    @test current_snapshot(runtime)[path("elapsed")] == 3
    @test logical_time(current_snapshot(runtime)) == LogicalTime(3, scale)

    rejecting = compose(:RejectingElapsedFixture, schema; scale) do builder, stores
        process = mount!(builder, :elapsed, PB0Elapsed())
        schedule!(
            builder,
            process,
            Every(Duration(2, scale); supports_partial=false),
        )
        attach!(builder, process, (elapsed=stores.elapsed,))
    end
    rejected = initialize_runtime(compile(rejecting))
    before = snapshot_fingerprint(current_snapshot(rejected))
    @test_throws ProcessBigraphError run_until!(rejected, LogicalTime(3, scale))
    @test snapshot_fingerprint(current_snapshot(rejected)) == before
    @test event_count(rejected) == 0
end

@testset "fork/join steps and cycle-free layer visibility" begin
    scale = TimeScale(1)
    schema = BranchSchema(
        trigger=LeafSchema(Int; default=0, update_law=:add),
        left=LeafSchema(Int; default=0, update_law=:add),
        right=LeafSchema(Int; default=0, update_law=:add),
        joined=LeafSchema(Int; default=0, update_law=:add),
    )
    model = compose(:ForkJoinFixture, schema; scale) do builder, stores
        process = mount!(builder, :trigger, PB0Increment(1))
        schedule!(builder, process, Every(Duration(1, scale)))
        attach!(builder, process, (
            state=stores.trigger,
            increment=stores.trigger,
        ))
        fork_left = mount!(
            builder, :fork_left, PB0ForkStep(:left, 2))
        attach!(builder, fork_left, (left=stores.left,))
        fork_right = mount!(
            builder, :fork_right, PB0ForkStep(:right, 3))
        attach!(builder, fork_right, (right=stores.right,))
        join = mount!(builder, :join, PB0JoinStep())
        schedule!(builder, join, After(fork_left, fork_right))
        attach!(builder, join, (
            left=stores.left,
            right=stores.right,
            total=stores.joined,
        ))
    end
    compiled = compile(model)
    @test step_layers(compiled) == (("fork_left", "fork_right"), ("join",))
    runtime = initialize_runtime(compiled)
    run_until!(runtime, LogicalTime(1, scale))
    @test current_snapshot(runtime)[path("left")] == 2
    @test current_snapshot(runtime)[path("right")] == 3
    @test current_snapshot(runtime)[path("joined")] == 5
end

@testset "failure atomicity and settled checkpoint replay" begin
    scale = TimeScale(1)
    schema = BranchSchema(state=LeafSchema(Int; default=0, update_law=:add))
    failure_model = compose(:FailureFixture, schema; scale) do builder, stores
        good = mount!(builder, :good, PB0Increment(1))
        schedule!(builder, good, Every(Duration(1, scale)))
        attach!(builder, good, (
            state=stores.state,
            increment=stores.state,
        ))
        bad = mount!(builder, :bad, PB0Fail())
        schedule!(builder, bad, Every(Duration(1, scale)))
        attach!(builder, bad, (out=stores.state,))
    end
    compiled_failure = compile(failure_model)
    runtime = initialize_runtime(compiled_failure)
    before = snapshot_fingerprint(current_snapshot(runtime))
    error = try
        run_until!(runtime, LogicalTime(1, scale))
        nothing
    catch caught
        caught
    end
    @test error isa ProcessBigraphError
    @test error.code == :runtime_event_failed
    @test error.context.stage == :process_invoke
    @test snapshot_fingerprint(current_snapshot(runtime)) == before
    @test event_count(runtime) == 0
    @test settled(runtime)

    compiled = increment_fixture()
    uninterrupted = initialize_runtime(compiled)
    run_until!(uninterrupted, LogicalTime(4, scale))
    resumed = initialize_runtime(compiled)
    run_until!(resumed, LogicalTime(2, scale))
    saved = checkpoint(resumed)
    restored = restore(compiled, saved)
    run_until!(restored, LogicalTime(4, scale))
    @test snapshot_fingerprint(current_snapshot(restored)) ==
        snapshot_fingerprint(current_snapshot(uninterrupted))
    @test event_count(restored) == event_count(uninterrupted)
    @test checkpoint_fingerprint(saved) == checkpoint_fingerprint(checkpoint(resumed))
end

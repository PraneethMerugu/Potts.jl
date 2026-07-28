@testset "Phase 15.C strict serial scheduler" begin
    scale = TimeScale(1)
    compiled = c15_add_composite()
    runtime = initialize_runtime(compiled, SerialExecutor())
    run_until!(runtime, LogicalTime(4, scale))

    @test current_snapshot(runtime)[path("state")] == 24
    @test event_count(runtime) == 4
    @test length(event_trace(runtime)) == 4
    @test commit_id(current_snapshot(runtime)) == 4
    @test all(record -> startswith(record.event_id, "event/"),
        event_trace(runtime))
    @test all(record -> length(record.event_id) == 70,
        event_trace(runtime))
    @test event_trace(runtime)[2].due_processes == ("fast", "slow")

    reversed = initialize_runtime(
        c15_add_composite(processes=(
            "slow" => (10, 2),
            "fast" => (1, 1),
        )),
        SerialExecutor(),
    )
    run_until!(reversed, LogicalTime(4, scale))
    @test materialize(current_snapshot(reversed)) ==
        materialize(current_snapshot(runtime))
    @test event_trace(reversed) == event_trace(runtime)

    stopped = initialize_runtime(compiled, SerialExecutor())
    run_until!(stopped, LogicalTime(3, scale);
        horizon_policy=StopPrior())
    @test logical_time(current_snapshot(stopped)) == LogicalTime(3, scale)
    @test event_count(stopped) == 3

    empty_schema = BranchSchema(
        state=LeafSchema(Int; default=0, update_law=:add),
    )
    empty_model = compose(:C15Empty, empty_schema; scale) do _, _
    end
    empty = compile(empty_model)
    empty_runtime = initialize_runtime(empty, SerialExecutor())
    run_until!(empty_runtime, LogicalTime(5, scale);
        horizon_policy=ExactHorizon())
    @test logical_time(current_snapshot(empty_runtime)) ==
        LogicalTime(5, scale)
    @test event_count(empty_runtime) == 0
    @test isempty(event_trace(empty_runtime))
end

@testset "Phase 15.C adaptive schedules and horizon failures" begin
    scale = TimeScale(1)
    schema = BranchSchema(
        state=LeafSchema(Int; default=0, update_law=:add),
    )
    valid_model = compose(:C15AdaptiveValid, schema; scale) do builder, stores
        valid = mount!(builder, :adaptive, C15Adaptive(1, 2))
        schedule!(
            builder, valid,
            AdaptiveSchedule(Duration(1, scale); supports_partial=true))
        attach!(builder, valid, (out=stores.state,))
    end
    compiled = compile(valid_model)
    @test compiled.plan.processes[1].declaration.schedule isa AdaptiveSchedule
    runtime = initialize_runtime(compiled, SerialExecutor())
    run_until!(runtime, LogicalTime(5, scale))
    @test current_snapshot(runtime)[path("state")] == 3
    @test event_count(runtime) == 3
    @test runtime.process_clocks[1].next_due == LogicalTime(7, scale)

    invalid_model = compose(:C15AdaptiveInvalid, schema; scale) do builder, stores
        invalid = mount!(builder, :adaptive, C15Adaptive(1, 0))
        schedule!(
            builder, invalid, AdaptiveSchedule(Duration(1, scale)))
        attach!(builder, invalid, (out=stores.state,))
    end
    invalid_runtime = initialize_runtime(
        compile(invalid_model),
        SerialExecutor(),
    )
    before = snapshot_fingerprint(current_snapshot(invalid_runtime))
    @test_throws ProcessBigraphError run_until!(
        invalid_runtime, LogicalTime(1, scale))
    @test snapshot_fingerprint(current_snapshot(invalid_runtime)) == before
    @test event_count(invalid_runtime) == 0

    no_partial_model = compose(
        :C15AdaptiveNoPartial, schema; scale) do builder, stores
        no_partial = mount!(builder, :adaptive, C15Adaptive(1, 2))
        schedule!(
            builder,
            no_partial,
            AdaptiveSchedule(
                Duration(2, scale); supports_partial=false),
        )
        attach!(builder, no_partial, (out=stores.state,))
    end
    rejecting = initialize_runtime(
        compile(no_partial_model),
        SerialExecutor(),
    )
    @test_throws ProcessBigraphError run_until!(
        rejecting, LogicalTime(1, scale))
    @test event_count(rejecting) == 0
end

@testset "Phase 15.C multirate interval inputs" begin
    scale = TimeScale(1)
    for behavior in (:frozen, :interpolated, :event_updated,
        :continuously_callable)
        schema = BranchSchema(
            source=LeafSchema(Int; default=0, update_law=:add),
            observed=LeafSchema(Int; default=0, update_law=:replace),
        )
        model = compose(
            Symbol(:C15Multirate_, behavior), schema; scale) do builder, stores
            producer = mount!(builder, :producer, C15Producer())
            schedule!(builder, producer, Every(Duration(1, scale)))
            attach!(builder, producer, (out=stores.source,))
            probe = mount!(
                builder, :probe, C15IntervalProbe(behavior))
            schedule!(builder, probe, Every(Duration(3, scale)))
            attach!(builder, probe, (
                input=stores.source,
                observed=stores.observed,
            ))
        end
        compiled = compile(model)
        runtime = initialize_runtime(compiled, SerialExecutor())
        run_until!(runtime, LogicalTime(3, scale))
        expected = behavior === :frozen ? 0 :
            behavior === :interpolated ? 2 :
            behavior === :event_updated ? 2 : 3
        @test current_snapshot(runtime)[path("observed")] == expected
        @test runtime.input_cursors[2].since == LogicalTime(3, scale)
    end
end

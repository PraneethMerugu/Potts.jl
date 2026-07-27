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
    empty = compile_composite(StaticComposite(
        empty_schema, Dict(), scale))
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
    binding = (PortBinding("adaptive", :out, path("state")),)
    valid = ProcessDeclaration(
        "adaptive",
        C15Adaptive(1, 2),
        AdaptiveSchedule(Duration(1, scale); supports_partial=true),
    )
    compiled = compile_composite(StaticComposite(
        schema, Dict(), scale; processes=(valid,), bindings=binding))
    @test compiled.plan.processes[1].declaration.schedule isa AdaptiveSchedule
    runtime = initialize_runtime(compiled, SerialExecutor())
    run_until!(runtime, LogicalTime(5, scale))
    @test current_snapshot(runtime)[path("state")] == 3
    @test event_count(runtime) == 3
    @test runtime.process_clocks[1].next_due == LogicalTime(7, scale)

    invalid = ProcessDeclaration(
        "adaptive",
        C15Adaptive(1, 0),
        AdaptiveSchedule(Duration(1, scale)),
    )
    invalid_runtime = initialize_runtime(
        compile_composite(StaticComposite(
            schema, Dict(), scale; processes=(invalid,), bindings=binding)),
        SerialExecutor(),
    )
    before = snapshot_fingerprint(current_snapshot(invalid_runtime))
    @test_throws ProcessBigraphError run_until!(
        invalid_runtime, LogicalTime(1, scale))
    @test snapshot_fingerprint(current_snapshot(invalid_runtime)) == before
    @test event_count(invalid_runtime) == 0

    no_partial = ProcessDeclaration(
        "adaptive",
        C15Adaptive(1, 2),
        AdaptiveSchedule(Duration(2, scale); supports_partial=false),
    )
    rejecting = initialize_runtime(
        compile_composite(StaticComposite(
            schema, Dict(), scale; processes=(no_partial,), bindings=binding)),
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
        producer = ProcessDeclaration(
            "producer",
            C15Producer(),
            FixedSchedule(Duration(1, scale)),
        )
        probe = ProcessDeclaration(
            "probe",
            C15IntervalProbe(behavior),
            FixedSchedule(Duration(3, scale)),
        )
        bindings = (
            PortBinding("producer", :out, path("source")),
            PortBinding("probe", :input, path("source")),
            PortBinding("probe", :observed, path("observed")),
        )
        compiled = compile_composite(StaticComposite(
            schema, Dict(), scale;
            processes=(producer, probe), bindings))
        runtime = initialize_runtime(compiled, SerialExecutor())
        run_until!(runtime, LogicalTime(3, scale))
        expected = behavior === :frozen ? 0 :
            behavior === :interpolated ? 2 :
            behavior === :event_updated ? 2 : 3
        @test current_snapshot(runtime)[path("observed")] == expected
        @test runtime.input_cursors[2].since == LogicalTime(3, scale)
    end
end

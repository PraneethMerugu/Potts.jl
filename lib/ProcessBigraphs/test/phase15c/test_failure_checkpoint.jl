function c15_failure_composite()
    scale = TimeScale(1)
    schema = BranchSchema(
        state=LeafSchema(Int; default=0, update_law=:add),
        copied=LeafSchema(Int; default=0, update_law=:replace),
    )
    model = compose(:C15FailureFixture, schema; scale) do builder, stores
        process = mount!(builder, :producer, C15Producer())
        schedule!(builder, process, Every(Duration(1, scale)))
        attach!(builder, process, (out=stores.state,))
        step = mount!(builder, :copy, C15ReactiveCopy())
        attach!(builder, step, (
            input=stores.state,
            out=stores.copied,
        ))
    end
    compile(model)
end

function c15_runtime_boundary(runtime)
    canonical_fingerprint((
        current_snapshot(runtime),
        runtime.process_clocks,
        runtime.step_clocks,
        runtime.input_cursors,
        runtime.observer_clocks,
        event_count(runtime),
        event_trace(runtime),
        observation_records(runtime),
    ))
end

@testset "Phase 15.C transactional failure stages" begin
    scale = TimeScale(1)
    compiled = c15_failure_composite()
    observation_plan = c15_observation_plan(scale)
    clean_executor = SerialExecutor(
        root_seed=77,
        observation_plan=observation_plan,
    )
    baseline = initialize_runtime(compiled, clean_executor)
    run_until!(baseline, LogicalTime(1, scale))
    baseline_boundary = c15_runtime_boundary(baseline)

    stages = (
        :process_invocation,
        :invocation_result_validation,
        :reconciliation,
        :reactive_step_execution,
        :continuation_validation,
        :required_observation,
        :checkpoint_capture,
        :record_publication,
    )
    for stage in stages
        injected_executor = SerialExecutor(
            root_seed=77,
            observation_plan=observation_plan,
            failure_injection=FailureInjection(stage),
        )
        runtime = initialize_runtime(compiled, injected_executor)
        stable = c15_runtime_boundary(runtime)
        error = try
            run_until!(runtime, LogicalTime(1, scale))
            nothing
        catch caught
            caught
        end
        @test error isa ProcessBigraphError
        @test error.code === :runtime_event_failed
        @test c15_runtime_boundary(runtime) == stable
        @test event_count(runtime) == 0
        @test isempty(observation_records(runtime))
        @test last_diagnostic(runtime).stage === stage
        @test last_diagnostic(runtime).last_stable_fingerprint ==
            snapshot_fingerprint(current_snapshot(runtime))

        runtime.executor = clean_executor
        run_until!(runtime, LogicalTime(1, scale))
        @test c15_runtime_boundary(runtime) == baseline_boundary
        @test isnothing(last_diagnostic(runtime))
    end

    later = initialize_runtime(compiled, clean_executor)
    run_until!(later, LogicalTime(1, scale))
    first_boundary = c15_runtime_boundary(later)
    later.executor = SerialExecutor(
        root_seed=77,
        observation_plan=observation_plan,
        failure_injection=FailureInjection(:record_publication),
    )
    @test_throws ProcessBigraphError run_until!(
        later, LogicalTime(2, scale))
    @test c15_runtime_boundary(later) == first_boundary
    @test event_count(later) == 1
end

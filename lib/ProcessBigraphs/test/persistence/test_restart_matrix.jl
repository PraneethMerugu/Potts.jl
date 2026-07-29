function serial_multirate_restart_model()
    scale = TimeScale(1)
    schema = BranchSchema(
        source=LeafSchema(Int; default=0, update_law=:add),
        observed=LeafSchema(Int; default=0, update_law=:replace),
    )
    model = compose(:SerialMultirateRestart, schema; scale) do builder, stores
        producer = mount!(builder, :producer, C15Producer())
        schedule!(builder, producer, Every(Duration(1, scale)))
        attach!(builder, producer, (out=stores.source,))
        probe = mount!(
            builder, :probe, C15IntervalProbe(:event_updated))
        schedule!(builder, probe, Every(Duration(3, scale)))
        attach!(builder, probe, (
            input=stores.source,
            observed=stores.observed,
        ))
    end
    compile(model)
end

function serial_adaptive_restart_model()
    scale = TimeScale(1)
    schema = BranchSchema(
        state=LeafSchema(Int; default=0, update_law=:add))
    model = compose(:SerialAdaptiveRestart, schema; scale) do builder, stores
        adaptive = mount!(builder, :adaptive, C15Adaptive(1, 2))
        schedule!(
            builder, adaptive, AdaptiveSchedule(Duration(1, scale)))
        attach!(builder, adaptive, (out=stores.state,))
    end
    compile(model)
end

function serial_iteration_restart_model()
    scale = TimeScale(1)
    schema = BranchSchema(
        trigger=LeafSchema(Int; default=0, update_law=:add),
        copied=LeafSchema(Int; default=0, update_law=:replace),
        converged=LeafSchema(Int; default=0, update_law=:replace),
        bounded=LeafSchema(Int; default=0, update_law=:add),
    )
    model = compose(:SerialIterationRestart, schema; scale) do builder, stores
        trigger = mount!(builder, :trigger, C15Producer())
        schedule!(builder, trigger, Every(Duration(1, scale)))
        attach!(builder, trigger, (out=stores.trigger,))
        copy_step = mount!(builder, :copy, C15ReactiveCopy())
        attach!(builder, copy_step, (
            input=stores.trigger,
            out=stores.copied,
        ))
        converge = mount!(builder, :converge, C15Converge())
        schedule!(builder, converge, After(converge))
        attach!(builder, converge, (
            state=stores.converged,
            out=stores.converged,
        ))
        bounded = mount!(builder, :bounded, C15Bounded())
        attach!(builder, bounded, (out=stores.bounded,))
        iteration!(
            builder, :convergence, (converge,);
            mode=:convergent,
            max_iterations=4,
            watch=(stores.converged,))
        iteration!(
            builder, Symbol("bounded-region"), (bounded,);
            mode=:bounded,
            max_iterations=3)
    end
    compile(model)
end

function serial_random_restart_model()
    scale = TimeScale(1)
    schema = BranchSchema(
        state=LeafSchema(UInt64;
            default=UInt64(0), update_law=:replace))
    model = compose(:SerialRandomRestart, schema; scale) do builder, stores
        random = mount!(builder, :random, C15Random())
        schedule!(builder, random, Every(Duration(1, scale)))
        attach!(builder, random, (out=stores.state,))
    end
    compile(model)
end

function serial_counting_observation_plan()
    counting = ObserverSpec(
        "counting",
        C15CountingObserver(),
        (path("state"),),
        EventObservationSchedule();
        continuation=(count=0,),
        record_schema=RecordSchema(
            typeof((count=0, value=0));
            identity="counting-record",
        ),
    )
    ObservationPlan((counting,))
end

@testset "serial runtime eight-fixture restart matrix" begin
    scale = TimeScale(1)
    fixtures = (
        (
            id="same-time-accumulator",
            model=c15_add_composite(),
            executor=SerialExecutor(root_seed=101),
            horizon=4,
            cuts=(0, 1, 2, 3, 4),
        ),
        (
            id="multirate-producer-consumer",
            model=serial_multirate_restart_model(),
            executor=SerialExecutor(root_seed=102),
            horizon=3,
            cuts=(0, 1, 2, 3),
        ),
        (
            id="adaptive-pulse",
            model=serial_adaptive_restart_model(),
            executor=SerialExecutor(root_seed=103),
            horizon=5,
            cuts=(0, 1, 3, 5),
        ),
        (
            id="reactive-dag",
            model=serial_failure_composite(),
            executor=SerialExecutor(root_seed=104),
            horizon=3,
            cuts=(0, 1, 2, 3),
        ),
        (
            id="iterative-region",
            model=serial_iteration_restart_model(),
            executor=SerialExecutor(root_seed=105),
            horizon=3,
            cuts=(0, 1, 2, 3),
        ),
        (
            id="stochastic-branch",
            model=serial_random_restart_model(),
            executor=SerialExecutor(root_seed=106),
            horizon=3,
            cuts=(0, 1, 2, 3),
        ),
        (
            id="open-composite-fork-join",
            model=compile_composite(serial_open_fork_join()),
            executor=SerialExecutor(root_seed=107),
            horizon=3,
            cuts=(0, 1, 2, 3),
        ),
        (
            id="observation-failure-restart",
            model=c15_add_composite(
                processes=("observed" => (1, 1),)),
            executor=SerialExecutor(
                root_seed=108,
                observation_plan=serial_counting_observation_plan(),
            ),
            horizon=3,
            cuts=(0, 1, 2, 3),
        ),
    )
    @test length(fixtures) == 8
    @test length(unique(fixture.id for fixture in fixtures)) == 8

    for fixture in fixtures
        uninterrupted = initialize_runtime(
            fixture.model, fixture.executor)
        run_until!(uninterrupted,
            LogicalTime(fixture.horizon, scale))
        final_checkpoint = encode_checkpoint(
            logical_checkpoint(uninterrupted))
        for cut in fixture.cuts
            prefix = initialize_runtime(
                fixture.model, fixture.executor)
            run_until!(
                prefix,
                LogicalTime(cut, scale);
                horizon_policy=:stop_prior,
            )
            resumed = restore(
                fixture.model,
                fixture.executor,
                encode_checkpoint(logical_checkpoint(prefix)),
            )
            run_until!(resumed,
                LogicalTime(fixture.horizon, scale))
            @test snapshot_fingerprint(current_snapshot(resumed)) ==
                snapshot_fingerprint(current_snapshot(uninterrupted))
            @test event_trace(resumed) ==
                event_trace(uninterrupted)
            @test observation_records(resumed) ==
                observation_records(uninterrupted)
            @test encode_checkpoint(logical_checkpoint(resumed)) ==
                final_checkpoint
        end
    end
end

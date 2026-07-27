function c15_multirate_restart_model()
    scale = TimeScale(1)
    compile_composite(StaticComposite(
        BranchSchema(
            source=LeafSchema(Int; default=0, update_law=:add),
            observed=LeafSchema(Int; default=0, update_law=:replace),
        ),
        Dict(), scale;
        processes=(
            ProcessDeclaration("producer", C15Producer(),
                FixedSchedule(Duration(1, scale))),
            ProcessDeclaration("probe",
                C15IntervalProbe(:event_updated),
                FixedSchedule(Duration(3, scale))),
        ),
        bindings=(
            PortBinding("producer", :out, path("source")),
            PortBinding("probe", :input, path("source")),
            PortBinding("probe", :observed, path("observed")),
        ),
    ))
end

function c15_adaptive_restart_model()
    scale = TimeScale(1)
    compile_composite(StaticComposite(
        BranchSchema(
            state=LeafSchema(Int; default=0, update_law=:add)),
        Dict(), scale;
        processes=(
            ProcessDeclaration(
                "adaptive",
                C15Adaptive(1, 2),
                AdaptiveSchedule(Duration(1, scale))),
        ),
        bindings=(PortBinding("adaptive", :out, path("state")),),
    ))
end

function c15_iteration_restart_model()
    scale = TimeScale(1)
    schema = BranchSchema(
        trigger=LeafSchema(Int; default=0, update_law=:add),
        copied=LeafSchema(Int; default=0, update_law=:replace),
        converged=LeafSchema(Int; default=0, update_law=:replace),
        bounded=LeafSchema(Int; default=0, update_law=:add),
    )
    compile_composite(StaticComposite(
        schema, Dict(), scale;
        processes=(
            ProcessDeclaration(
                "trigger", C15Producer(),
                FixedSchedule(Duration(1, scale))),
        ),
        steps=(
            StepDeclaration("copy", C15ReactiveCopy()),
            StepDeclaration("converge", C15Converge();
                dependencies=("converge",)),
            StepDeclaration("bounded", C15Bounded()),
        ),
        bindings=(
            PortBinding("trigger", :out, path("trigger")),
            PortBinding("copy", :input, path("trigger")),
            PortBinding("copy", :out, path("copied")),
            PortBinding("converge", :state, path("converged")),
            PortBinding("converge", :out, path("converged")),
            PortBinding("bounded", :out, path("bounded")),
        ),
        iteration_regions=(
            IterationRegion(
                "convergence", ("converge",);
                mode=:convergent,
                max_iterations=4,
                watch_paths=(path("converged"),),
            ),
            IterationRegion(
                "bounded-region", ("bounded",);
                mode=:bounded,
                max_iterations=3,
            ),
        ),
    ))
end

function c15_random_restart_model()
    scale = TimeScale(1)
    compile_composite(StaticComposite(
        BranchSchema(
            state=LeafSchema(UInt64;
                default=UInt64(0), update_law=:replace)),
        Dict(), scale;
        processes=(
            ProcessDeclaration(
                "random", C15Random(),
                FixedSchedule(Duration(1, scale))),
        ),
        bindings=(PortBinding("random", :out, path("state")),),
    ))
end

function c15_counting_observation_plan()
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

@testset "Phase 15.C eight-fixture restart matrix" begin
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
            model=c15_multirate_restart_model(),
            executor=SerialExecutor(root_seed=102),
            horizon=3,
            cuts=(0, 1, 2, 3),
        ),
        (
            id="adaptive-pulse",
            model=c15_adaptive_restart_model(),
            executor=SerialExecutor(root_seed=103),
            horizon=5,
            cuts=(0, 1, 3, 5),
        ),
        (
            id="reactive-dag",
            model=c15_failure_composite(),
            executor=SerialExecutor(root_seed=104),
            horizon=3,
            cuts=(0, 1, 2, 3),
        ),
        (
            id="iterative-region",
            model=c15_iteration_restart_model(),
            executor=SerialExecutor(root_seed=105),
            horizon=3,
            cuts=(0, 1, 2, 3),
        ),
        (
            id="stochastic-branch",
            model=c15_random_restart_model(),
            executor=SerialExecutor(root_seed=106),
            horizon=3,
            cuts=(0, 1, 2, 3),
        ),
        (
            id="open-composite-fork-join",
            model=compile_composite(c15_open_fork_join()),
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
                observation_plan=c15_counting_observation_plan(),
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

@testset "Phase 15.C typed observations" begin
    scale = TimeScale(1)
    compiled = c15_add_composite(processes=("slow" => (1, 3),))

    periodic = initialize_runtime(compiled, SerialExecutor(
        observation_plan=c15_observation_plan(
            scale; schedule=PeriodicObservationSchedule(
                Duration(1, scale))),
    ))
    run_until!(periodic, LogicalTime(2, scale); horizon_policy=:stop_prior)
    @test event_count(periodic) == 0
    @test map(record -> record.time.tick,
        observation_records(periodic)) == (1, 2)
    @test all(record -> record.payload.value == 0,
        observation_records(periodic))

    at_times = initialize_runtime(compiled, SerialExecutor(
        observation_plan=c15_observation_plan(
            scale; schedule=AtTimesObservationSchedule((
                LogicalTime(0, scale),
                LogicalTime(2, scale),
                LogicalTime(4, scale),
            ))),
    ))
    run_until!(at_times, LogicalTime(4, scale); horizon_policy=:stop_prior)
    @test event_count(at_times) == 1
    @test map(record -> record.time.tick,
        observation_records(at_times)) == (0, 2, 4)
    @test map(record -> record.payload.value,
        observation_records(at_times)) == (0, 0, 1)

    required_spec = ObserverSpec(
        "required-failure",
        C15FailObserver(),
        (path("state"),),
        EventObservationSchedule(),
    )
    required = initialize_runtime(compiled, SerialExecutor(
        observation_plan=ObservationPlan((required_spec,)),
    ))
    before = current_snapshot(required)
    @test_throws ProcessBigraphError run_until!(
        required, LogicalTime(3, scale))
    @test current_snapshot(required) == before
    @test event_count(required) == 0
    @test isempty(observation_records(required))
    @test !isnothing(last_diagnostic(required))

    optional_spec = ObserverSpec(
        "optional-failure",
        C15FailObserver(),
        (path("state"),),
        EventObservationSchedule();
        required=false,
    )
    optional = initialize_runtime(compiled, SerialExecutor(
        observation_plan=ObservationPlan((optional_spec,)),
    ))
    run_until!(optional, LogicalTime(3, scale))
    @test event_count(optional) == 1
    @test current_snapshot(optional)[path("state")] == 1
    @test only(observation_records(optional)).status === :optional_failure

    omit_spec = ObserverSpec(
        "omitted-failure",
        C15FailObserver(),
        (path("state"),),
        EventObservationSchedule();
        required=false,
        optional_failure_policy=:omit_and_advance,
    )
    omitted = initialize_runtime(compiled, SerialExecutor(
        observation_plan=ObservationPlan((omit_spec,)),
    ))
    run_until!(omitted, LogicalTime(3, scale))
    @test event_count(omitted) == 1
    @test isempty(observation_records(omitted))

    plain_executor = SerialExecutor()
    observed_executor = SerialExecutor(
        observation_plan=c15_observation_plan(scale))
    @test model_fingerprint(compiled) == model_fingerprint(compiled)
    @test runtime_fingerprint(plain_executor, compiled) !=
        runtime_fingerprint(observed_executor, compiled)
end

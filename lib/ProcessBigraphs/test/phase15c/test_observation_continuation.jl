@testset "Phase 15.C typed continuation contracts" begin
    scale = TimeScale(1)
    schema = ContinuationSchema(
        "counter-state",
        CanonicalContinuationCodec{typeof((count=0,))}();
        version="1.0.0",
    )
    bound = bind_continuation(
        "counter", "1", "fixed-cadence", schema)
    value = (count=7,)
    bytes = encode_continuation(bound, value)
    @test decode_continuation(bound, bytes) == value
    @test continuation_fingerprint(bound, value) ==
        continuation_fingerprint(bound, decode_continuation(bound, bytes))
    @test alpha_eligible(bound)
    @test restore_compatible(bound, bound)
    @test_throws ProcessBigraphError validate_continuation(
        bound, "another-owner", value)
    @test_throws ProcessBigraphError validate_continuation(
        bound, "counter", (count=Int32(7),))

    schema_v2 = ContinuationSchema(
        "counter-state",
        CanonicalContinuationCodec{typeof((count=0,))}();
        version="2.0.0",
    )
    bound_v2 = bind_continuation(
        "counter", "1", "fixed-cadence", schema_v2)
    migration = IdentityContinuationMigration(
        "counter", "1.0.0", "2.0.0")
    @test migrate_continuation(migration, bound, bound_v2, value) == value
    @test_throws ProcessBigraphError migrate_continuation(
        IdentityContinuationMigration(
            "counter", "0.9.0", "2.0.0"),
        bound,
        bound_v2,
        value,
    )

    state_schema = BranchSchema(
        state=LeafSchema(Int; default=0, update_law=:add),
    )
    bad_initial_model = compose(
        :C15BadInitialContinuation, state_schema; scale) do builder, stores
        bad = mount!(
            builder, :bad, C15Counter();
            continuation="not-a-counter")
        schedule!(builder, bad, Every(Duration(1, scale)))
        attach!(builder, bad, (out=stores.state,))
    end
    bad_initial_composite = compile(bad_initial_model)
    @test_throws ProcessBigraphError initialize_runtime(
        bad_initial_composite, SerialExecutor())

    bad_proposal_model = compose(
        :C15BadProposalContinuation, state_schema; scale) do builder, stores
        bad = mount!(
            builder, :bad, C15BadContinuation();
            continuation=(count=0,))
        schedule!(builder, bad, Every(Duration(1, scale)))
        attach!(builder, bad, (out=stores.state,))
    end
    bad_proposal_runtime = initialize_runtime(
        compile(bad_proposal_model),
        SerialExecutor(),
    )
    before = snapshot_fingerprint(current_snapshot(bad_proposal_runtime))
    @test_throws ProcessBigraphError run_until!(
        bad_proposal_runtime, LogicalTime(1, scale))
    @test snapshot_fingerprint(current_snapshot(bad_proposal_runtime)) == before
    @test event_count(bad_proposal_runtime) == 0
end

@testset "Phase 15.C observer continuation and projection privacy" begin
    scale = TimeScale(1)
    compiled = c15_add_composite(processes=("producer" => (1, 1),))
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
    executor = SerialExecutor(
        root_seed=5,
        observation_plan=ObservationPlan((counting,)),
    )
    uninterrupted = initialize_runtime(compiled, executor)
    run_until!(uninterrupted, LogicalTime(4, scale))
    @test map(record -> record.payload.count,
        observation_records(uninterrupted)) == (1, 2, 3, 4)

    prefix = initialize_runtime(compiled, executor)
    run_until!(prefix, LogicalTime(2, scale))
    resumed = restore(
        compiled,
        executor,
        encode_checkpoint(logical_checkpoint(prefix)),
    )
    run_until!(resumed, LogicalTime(4, scale))
    @test observation_records(resumed) ==
        observation_records(uninterrupted)
    @test snapshot_fingerprint(current_snapshot(resumed)) ==
        snapshot_fingerprint(current_snapshot(uninterrupted))

    private_schema = BranchSchema(
        state=LeafSchema(Int; default=0, update_law=:add),
        secret=LeafSchema(Int; default=9, update_law=:replace),
    )
    private_model = compose(
        :C15PrivateObservation, private_schema; scale) do builder, stores
        process = mount!(builder, :producer, C15Producer())
        schedule!(builder, process, Every(Duration(1, scale)))
        attach!(builder, process, (out=stores.state,))
    end
    private_composite = compile(private_model)
    leaky = ObserverSpec(
        "leaky",
        C15LeakyObserver(),
        (path("state"),),
        EventObservationSchedule(),
    )
    runtime = initialize_runtime(private_composite, SerialExecutor(
        observation_plan=ObservationPlan((leaky,)),
    ))
    stable = snapshot_fingerprint(current_snapshot(runtime))
    @test_throws ProcessBigraphError run_until!(
        runtime, LogicalTime(1, scale))
    @test snapshot_fingerprint(current_snapshot(runtime)) == stable
    @test event_count(runtime) == 0
end

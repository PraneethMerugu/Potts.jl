@testset "Phase 15.C semantic RNG" begin
    @test philox4x32_10(
        (UInt32(0), UInt32(0), UInt32(0), UInt32(0)),
        (UInt32(0), UInt32(0)),
    ) == (
        UInt32(0x6627e8d5),
        UInt32(0xe169c58d),
        UInt32(0xbc57ac4c),
        UInt32(0x9b00dbd8),
    )

    scale = TimeScale(1)
    time = LogicalTime(7, scale)
    seed = NormalizedRootSeed(0x123456789abcdef)
    model = ModelRNGContext("model", seed, "owner", time, "event")
    observer = ObserverRNGContext("model", seed, "owner", time, "event")

    first_draw = semantic_bits(model, :site, 0)
    @test first_draw == semantic_bits(model, :site, 0)
    @test first_draw != semantic_bits(model, :site, 1)
    @test first_draw != semantic_bits(model, :other_site, 0)
    @test first_draw != semantic_bits(model, :site, 0; lineage="child")
    @test first_draw != semantic_bits(observer, :site, 0)
    @test 3 <= semantic_integer(model, :integer, 0, 3:11) <= 11
    @test 0.0 <= semantic_uniform(model, :uniform, 0) < 1.0
    addresses = (
        RNGAddress("model", seed, "owner", time, "event", "root", "site", 0),
        RNGAddress("model-2", seed, "owner", time, "event", "root", "site", 0),
        RNGAddress("model", NormalizedRootSeed(2), "owner", time,
            "event", "root", "site", 0),
        RNGAddress("model", seed, "owner-2", time, "event", "root", "site", 0),
        RNGAddress("model", seed, "owner", LogicalTime(8, scale),
            "event", "root", "site", 0),
        RNGAddress("model", seed, "owner", time, "event-2", "root", "site", 0),
        RNGAddress("model", seed, "owner", time, "event", "child", "site", 0),
        RNGAddress("model", seed, "owner", time, "event", "root", "site-2", 0),
        RNGAddress("model", seed, "owner", time, "event", "root", "site", 1),
        RNGAddress("model", seed, "owner", time, "event", "root", "site", 0;
            namespace=:observer),
    )
    @test length(unique(semantic_bits.(addresses))) == length(addresses)
    requested = (:alpha, :beta, :gamma)
    forward_request = Dict(site => semantic_bits(model, site, 0)
        for site in requested)
    reverse_request = Dict(site => semantic_bits(model, site, 0)
        for site in reverse(requested))
    @test forward_request == reverse_request
    @test_throws ProcessBigraphError NormalizedRootSeed(-1)
    @test_throws ProcessBigraphError RNGAddress(
        "model", seed, "owner", time, "event", "root", "site", -1)

    schema = BranchSchema(
        state=LeafSchema(UInt64; default=UInt64(0), update_law=:replace),
    )
    model = compose(:C15RandomFixture, schema; scale) do builder, stores
        process = mount!(builder, :random, C15Random())
        schedule!(builder, process, Every(Duration(1, scale)))
        attach!(builder, process, (out=stores.state,))
    end
    compiled = compile(model)
    plain = initialize_runtime(compiled, SerialExecutor(root_seed=91))
    run_until!(plain, LogicalTime(3, scale))

    random_observer = ObserverSpec(
        "random-observer",
        C15RandomObserver(),
        (path("state"),),
        EventObservationSchedule();
        record_schema=RecordSchema(
            typeof((draw=UInt64(0), state=UInt64(0)));
            identity="random-observer-record",
        ),
    )
    observed = initialize_runtime(compiled, SerialExecutor(
        root_seed=91,
        observation_plan=ObservationPlan((random_observer,)),
    ))
    run_until!(observed, LogicalTime(3, scale))

    @test current_snapshot(observed) == current_snapshot(plain)
    @test map(record -> record.after_fingerprint, event_trace(observed)) ==
        map(record -> record.after_fingerprint, event_trace(plain))
    @test length(observation_records(observed)) == 3
    @test all(record -> record.status === :success,
        observation_records(observed))
    @test first(observation_records(observed)).payload.draw !=
        current_snapshot(observed)[path("state")]

    failing = initialize_runtime(compiled, SerialExecutor(
        root_seed=91,
        failure_injection=FailureInjection(:record_publication),
    ))
    stable = snapshot_fingerprint(current_snapshot(failing))
    @test_throws ProcessBigraphError run_until!(
        failing, LogicalTime(1, scale))
    @test snapshot_fingerprint(current_snapshot(failing)) == stable
    @test event_count(failing) == 0
    retry_executor = SerialExecutor(root_seed=91)
    retry_baseline = initialize_runtime(compiled, retry_executor)
    run_until!(retry_baseline, LogicalTime(1, scale))
    failing.executor = retry_executor
    run_until!(failing, LogicalTime(1, scale))
    @test snapshot_fingerprint(current_snapshot(failing)) ==
        snapshot_fingerprint(current_snapshot(retry_baseline))
    @test event_trace(failing) == event_trace(retry_baseline)
end

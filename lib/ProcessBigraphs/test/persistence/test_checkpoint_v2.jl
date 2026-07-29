function c15_counter_composite(; cadence=1)
    scale = TimeScale(1)
    schema = BranchSchema(
        state=LeafSchema(Int; default=0, update_law=:add),
    )
    model = compose(:C15CounterFixture, schema; scale) do builder, stores
        counter = mount!(
            builder, :counter, C15Counter();
            continuation=(count=0,))
        schedule!(
            builder, counter, Every(Duration(cadence, scale)))
        attach!(builder, counter, (out=stores.state,))
    end
    compile(model)
end

@testset "serial runtime logical checkpoint v2" begin
    scale = TimeScale(1)
    compiled = c15_counter_composite()
    executor = SerialExecutor(root_seed=2026)

    uninterrupted = initialize_runtime(compiled, executor)
    run_until!(uninterrupted, LogicalTime(6, scale))

    split = initialize_runtime(compiled, executor)
    run_until!(split, LogicalTime(3, scale))
    checkpoint_value = logical_checkpoint(split)
    encoded = encode_checkpoint(checkpoint_value)
    @test encoded == encode_checkpoint(checkpoint_value)
    @test length(encoded) == 4609
    @test bytes2hex(ProcessBigraphs.sha256(encoded)) ==
        "8b28675481d06fa7ffa6389ec63e0dbb9f43408e3a71d190a040bea67bb2b929"
    @test checkpoint_fingerprint(checkpoint_value) ==
        bytes2hex(ProcessBigraphs.sha256(checkpoint_value.payload_bytes))

    decoded = decode_checkpoint(encoded)
    @test encode_checkpoint(decoded) == encoded
    resumed = restore(compiled, executor, decoded)
    @test snapshot_fingerprint(current_snapshot(resumed)) ==
        snapshot_fingerprint(current_snapshot(split))
    @test event_count(resumed) == event_count(split)
    run_until!(resumed, LogicalTime(6, scale))

    @test snapshot_fingerprint(current_snapshot(resumed)) ==
        snapshot_fingerprint(current_snapshot(uninterrupted))
    @test event_trace(resumed) == event_trace(uninterrupted)
    @test observation_records(resumed) == observation_records(uninterrupted)
    @test encode_checkpoint(logical_checkpoint(resumed)) ==
        encode_checkpoint(logical_checkpoint(uninterrupted))

    for boundary in 0:5
        prefix = initialize_runtime(compiled, executor)
        run_until!(prefix, LogicalTime(boundary, scale))
        roundtrip = restore(
            compiled,
            executor,
            encode_checkpoint(logical_checkpoint(prefix)),
        )
        run_until!(roundtrip, LogicalTime(6, scale))
        @test snapshot_fingerprint(current_snapshot(roundtrip)) ==
            snapshot_fingerprint(current_snapshot(uninterrupted))
        @test event_trace(roundtrip) == event_trace(uninterrupted)
    end

    corrupted = copy(encoded)
    corrupted[end] ⊻= 0x01
    @test_throws ProcessBigraphError decode_checkpoint(corrupted)
    @test_throws ProcessBigraphError decode_checkpoint(encoded[1:end - 1])
    @test_throws ProcessBigraphError decode_checkpoint(
        vcat(encoded, UInt8(0)))

    bad_integrity = LogicalCheckpointV2(
        checkpoint_value.format_version,
        checkpoint_value.payload,
        checkpoint_value.payload_bytes,
        repeat("0", 64),
    )
    @test_throws ProcessBigraphError encode_checkpoint(bad_integrity)
    @test_throws ProcessBigraphError restore(
        compiled, executor, bad_integrity)

    bad_bytes = LogicalCheckpointV2(
        checkpoint_value.format_version,
        checkpoint_value.payload,
        UInt8[checkpoint_value.payload_bytes..., 0x00],
        checkpoint_value.integrity,
    )
    @test_throws ProcessBigraphError encode_checkpoint(bad_bytes)

    bad_version = LogicalCheckpointV2(
        "99.0.0",
        checkpoint_value.payload,
        checkpoint_value.payload_bytes,
        checkpoint_value.integrity,
    )
    @test_throws ProcessBigraphError restore(
        compiled, executor, bad_version)
    @test_throws ProcessBigraphError restore(
        c15_counter_composite(cadence=2), executor, checkpoint_value)
    @test_throws ProcessBigraphError restore(
        compiled, SerialExecutor(root_seed=2027), checkpoint_value)
    @test_throws ProcessBigraphError logical_checkpoint(
        initialize_runtime(compiled))
end

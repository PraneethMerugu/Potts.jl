import ProcessBigraphs: ManagedEngineRuntime, managed_engine_runtime,
    managed_engine_time, managed_engine_instance, managed_engine_settled,
    advance_managed_engine!, reconstruct_managed_engine!,
    CheckpointComponent, CoupledLogicalCheckpoint, RestoredLogicalCheckpoint,
    AbstractLegacyCheckpointConverter, engine_checkpoint_payload,
    restore_engine_checkpoint, legacy_source_fingerprint,
    legacy_checkpoint_component, capture_logical_checkpoint,
    decode_logical_checkpoint, restore_logical_checkpoint,
    convert_legacy_checkpoint, DomainStructuralIdentity,
    DomainStructuralRequest, DomainStructuralSelection,
    select_domain_structural_requests, StructuralCapacity,
    dynamic_structural_epoch, structural_structure

function engine_checkpoint_payload(
    instance::EngineProtocolMockInstance,
    declaration::EngineDeclaration,
)
    CheckpointComponent(
        declaration.id,
        "logical_checkpoint-mock-engine-v1",
        :exact,
        (
            mode=instance.mode,
            published=copy(instance.published),
            discard_count=instance.discard_count,
        ),
    )
end

function restore_engine_checkpoint(
    adapter::EngineProtocolMockAdapter,
    declaration::EngineDeclaration,
    payload::NamedTuple,
)
    payload.mode == adapter.mode ||
        throw(ArgumentError("mock checkpoint mode changed"))
    EngineProtocolMockInstance(
        payload.mode,
        copy(payload.published),
        nothing,
        payload.discard_count,
    )
end

struct LogicalCheckpointLegacySource
    values::Vector{Int}
    checksum::String
end

struct LogicalCheckpointLegacyConverter <: AbstractLegacyCheckpointConverter end

function logical_checkpoint_counter_composite()
    scale = TimeScale(1)
    schema = BranchSchema(
        state=LeafSchema(Int; default=0, update_law=:add),
    )
    model = compose(:LogicalCheckpointCounter, schema; scale) do builder, stores
        counter = mount!(
            builder, Symbol("logical_checkpoint-counter"), C15Counter();
            continuation=(count=0,))
        schedule!(builder, counter, Every(Duration(1, scale)))
        attach!(builder, counter, (out=stores.state,))
    end
    compile(model)
end

function logical_checkpoint_structural_epoch()
    schema = BranchSchema(
        left=LeafSchema(Int; default=0, update_law=:add),
        right=LeafSchema(Int; default=0, update_law=:add),
    )
    scale = TimeScale(1)
    model = compose(:LogicalCheckpointStructuralEpoch, schema; scale) do _, _
    end
    composite = compile(model)
    structure = canonical_structure(composite)
    dynamic_structural_epoch(
        structure;
        capacity=StructuralCapacity(
            composites=8, total_parts=64),
    )
end

legacy_source_fingerprint(
    ::LogicalCheckpointLegacyConverter,
    source::LogicalCheckpointLegacySource,
) = canonical_fingerprint((source.values, source.checksum))

function legacy_checkpoint_component(
    ::LogicalCheckpointLegacyConverter,
    source::LogicalCheckpointLegacySource,
)
    expected = canonical_fingerprint(source.values)
    source.checksum == expected ||
        throw(ProcessBigraphError(
            :legacy_integrity_failure,
            "legacy source checksum does not match"))
    CheckpointComponent(
        "legacy-mock",
        "legacy-mock-v1",
        :exact,
        (values=copy(source.values), checksum=source.checksum),
    )
end

@testset "logical checkpoint managed authority and logical checkpoint v3" begin
    scale = TimeScale(1)
    declaration = engine_protocol_declaration()
    managed = managed_engine_runtime(
        declaration,
        LogicalTime(0, scale);
        structural_epoch="epoch-0",
    )
    result = advance_managed_engine!(
        managed,
        LogicalTime(3, scale);
        reason=:scheduled_field_advance,
        inputs=(:state => [1.0, 2.0],),
        resource_authorization=(backend=:cpu, bytes=1024),
        expected_outputs=(:state_sum,),
        expected_diagnostics=(:iterations,),
    )
    @test result.status === :published
    @test managed_engine_time(managed) == LogicalTime(3, scale)
    @test managed_engine_settled(managed)
    @test managed.publication_version == UInt64(1)
    @test managed.invocation_ordinal == UInt64(1)

    rejected = managed_engine_runtime(
        declaration,
        LogicalTime(0, scale);
        structural_epoch="epoch-0",
    )
    @test_throws ProcessBigraphError advance_managed_engine!(
        rejected,
        LogicalTime(1, scale);
        inputs=(:state => [1.0],),
        resource_authorization=(backend=:cpu, bytes=1024),
        expected_outputs=(:state_sum,),
        expected_diagnostics=(:iterations,),
        authorize=(candidate, invocation) -> false,
    )
    @test managed_engine_time(rejected) == LogicalTime(0, scale)
    @test rejected.publication_version == UInt64(0)
    @test rejected.invocation_ordinal == UInt64(0)
    @test !isnothing(rejected.last_failure)
    @test_throws ProcessBigraphError advance_managed_engine!(
        rejected,
        LogicalTime(1, scale);
        inputs=(:state => [1.0],),
    )
    reconstructed = prepare_engine(declaration)
    reconstruct_managed_engine!(rejected, reconstructed)
    @test isnothing(rejected.last_failure)

    composite = logical_checkpoint_counter_composite()
    executor = SerialExecutor(root_seed=1605)
    serial = initialize_runtime(composite, executor)
    run_until!(serial, LogicalTime(2, scale))
    structural_epoch = logical_checkpoint_structural_epoch()
    checkpoint_value = capture_logical_checkpoint(
        serial;
        structural_epoch,
        managed_engines=(managed,),
        identity_maps=("corepotts:cell:7" => "domain:cell:7",),
    )
    encoded = encode_checkpoint(checkpoint_value)
    decoded = decode_logical_checkpoint(encoded)
    @test encode_checkpoint(decoded) == encoded
    @test checkpoint_fingerprint(decoded) ==
        checkpoint_fingerprint(checkpoint_value)

    restored = restore_logical_checkpoint(
        composite,
        executor,
        decoded;
        engine_declarations=(declaration,),
    )
    @test restored isa RestoredLogicalCheckpoint
    @test restored.replay_class === :exact
    @test structural_fingerprint(restored.structural_epoch) ==
        structural_fingerprint(structural_epoch)
    @test structural_fingerprint(
        structural_structure(restored.structural_epoch)) ==
        structural_fingerprint(structural_structure(structural_epoch))
    @test restored.identity_maps ==
        ("corepotts:cell:7" => "domain:cell:7",)
    @test snapshot_fingerprint(current_snapshot(restored.runtime)) ==
        snapshot_fingerprint(current_snapshot(serial))
    restored_engine = only(restored.engines).second
    @test managed_engine_time(restored_engine) ==
        managed_engine_time(managed)
    @test managed_engine_instance(restored_engine).published ==
        managed_engine_instance(managed).published

    corrupted = copy(encoded)
    corrupted[end] ⊻= 0x01
    @test_throws ProcessBigraphError decode_logical_checkpoint(corrupted)
    @test_throws ProcessBigraphError decode_logical_checkpoint(encoded[1:end - 1])
    bad_integrity = CoupledLogicalCheckpoint(
        checkpoint_value.format_version,
        checkpoint_value.payload,
        checkpoint_value.payload_bytes,
        repeat("0", 64),
    )
    @test_throws ProcessBigraphError encode_checkpoint(bad_integrity)

    source_values = [1, 2, 3]
    source = LogicalCheckpointLegacySource(
        source_values, canonical_fingerprint(source_values))
    source_before = deepcopy(source)
    converted = convert_legacy_checkpoint(
        serial, LogicalCheckpointLegacyConverter(), source)
    @test source.values == source_before.values
    @test source.checksum == source_before.checksum
    @test length(converted.payload.components) == 2
    @test decode_logical_checkpoint(
        encode_checkpoint(converted)).integrity == converted.integrity

    invalid = LogicalCheckpointLegacySource([1, 2, 3], repeat("0", 64))
    @test_throws ProcessBigraphError convert_legacy_checkpoint(
        serial, LogicalCheckpointLegacyConverter(), invalid)
end

@testset "logical checkpoint typed domain structural requests" begin
    cell = DomainStructuralIdentity("custom-solver", :cell, "7", 2)
    other = DomainStructuralIdentity("custom-solver", :cell, "8", 1)
    divide = DomainStructuralRequest(
        "divide-7",
        "custom-solver",
        12,
        :divide,
        (cell,);
        payload=(axis=:major,),
        priority=4,
    )
    remove = DomainStructuralRequest(
        "remove-7",
        "custom-solver",
        12,
        :remove,
        (cell,);
        priority=2,
    )
    add = DomainStructuralRequest(
        "add-8",
        "custom-solver",
        12,
        :add,
        (other,);
        dependencies=("divide-7",),
        priority=1,
    )
    selection = select_domain_structural_requests(
        (remove, add, divide); maximum_selected=2)
    reordered = select_domain_structural_requests(
        (divide, remove, add); maximum_selected=2)
    @test selection isa DomainStructuralSelection
    @test selection.fingerprint == reordered.fingerprint
    @test first.(getfield.(selection.selected, :request_id)) ==
        first.(getfield.(reordered.selected, :request_id))
    @test getfield.(selection.selected, :request_id) ==
        ("add-8", "divide-7")
    statuses = Dict(value.request_id => value
        for value in selection.dispositions)
    @test statuses["divide-7"].status === :selected
    @test statuses["remove-7"].status === :conflict_rejected
    @test statuses["remove-7"].conflicting_with == "divide-7"
    @test statuses["add-8"].status === :selected

    capacity = select_domain_structural_requests(
        (divide, add); maximum_selected=1)
    capacity_statuses = Dict(value.request_id => value.status
        for value in capacity.dispositions)
    @test capacity_statuses["divide-7"] === :selected
    @test capacity_statuses["add-8"] === :capacity_rejected
    @test_throws ProcessBigraphError DomainStructuralRequest(
        "raw", "custom-solver", 12, :merge, (cell,))
    @test_throws ProcessBigraphError select_domain_structural_requests((
        divide,
        DomainStructuralRequest(
            "other-epoch", "custom-solver", 13, :remove, (other,)),
    ))
end

import ProcessBigraphs: ManagedEngineRuntime, managed_engine_runtime,
    managed_engine_time, managed_engine_instance, managed_engine_settled,
    advance_managed_engine!, reconstruct_managed_engine!,
    CheckpointComponent, LogicalCheckpointV3, RestoredPhase16Checkpoint,
    AbstractLegacyCheckpointConverter, engine_checkpoint_payload,
    restore_engine_checkpoint, legacy_source_fingerprint,
    legacy_checkpoint_component, phase16_checkpoint,
    decode_phase16_checkpoint, restore_phase16_checkpoint,
    convert_legacy_checkpoint, DomainStructuralIdentity,
    DomainStructuralRequest, DomainStructuralSelection,
    select_domain_structural_requests, StructuralCapacity,
    dynamic_structural_epoch, structural_structure

function engine_checkpoint_payload(
    instance::P16BMockInstance,
    declaration::EngineDeclaration,
)
    CheckpointComponent(
        declaration.id,
        "phase16e-mock-engine-v1",
        :exact,
        (
            mode=instance.mode,
            published=copy(instance.published),
            discard_count=instance.discard_count,
        ),
    )
end

function restore_engine_checkpoint(
    adapter::P16BMockAdapter,
    declaration::EngineDeclaration,
    payload::NamedTuple,
)
    payload.mode == adapter.mode ||
        throw(ArgumentError("mock checkpoint mode changed"))
    P16BMockInstance(
        payload.mode,
        copy(payload.published),
        nothing,
        payload.discard_count,
    )
end

struct P16ELegacySource
    values::Vector{Int}
    checksum::String
end

struct P16ELegacyConverter <: AbstractLegacyCheckpointConverter end

function p16e_counter_composite()
    scale = TimeScale(1)
    schema = BranchSchema(
        state=LeafSchema(Int; default=0, update_law=:add),
    )
    counter = ProcessDeclaration(
        "phase16e-counter",
        C15Counter(),
        FixedSchedule(Duration(1, scale));
        continuation=(count=0,),
    )
    compile_composite(StaticComposite(
        schema, Dict(), scale;
        processes=(counter,),
        bindings=(
            PortBinding("phase16e-counter", :out, path("state")),
        ),
    ))
end

function p16e_structural_epoch()
    structure = canonical_structure(canonical_model(StaticComposite(
        BranchSchema(
            left=LeafSchema(Int; default=0, update_law=:add),
            right=LeafSchema(Int; default=0, update_law=:add),
        ),
        Dict(),
        TimeScale(1),
    )))
    dynamic_structural_epoch(
        structure;
        capacity=StructuralCapacity(
            composites=8, total_parts=64),
    )
end

legacy_source_fingerprint(
    ::P16ELegacyConverter,
    source::P16ELegacySource,
) = canonical_fingerprint((source.values, source.checksum))

function legacy_checkpoint_component(
    ::P16ELegacyConverter,
    source::P16ELegacySource,
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

@testset "Phase 16.E managed authority and logical checkpoint v3" begin
    scale = TimeScale(1)
    declaration = p16b_declaration()
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

    composite = p16e_counter_composite()
    executor = SerialExecutor(root_seed=1605)
    serial = initialize_runtime(composite, executor)
    run_until!(serial, LogicalTime(2, scale))
    structural_epoch = p16e_structural_epoch()
    checkpoint_value = phase16_checkpoint(
        serial;
        structural_epoch,
        managed_engines=(managed,),
        identity_maps=("corepotts:cell:7" => "domain:cell:7",),
    )
    encoded = encode_checkpoint(checkpoint_value)
    decoded = decode_phase16_checkpoint(encoded)
    @test encode_checkpoint(decoded) == encoded
    @test checkpoint_fingerprint(decoded) ==
        checkpoint_fingerprint(checkpoint_value)

    restored = restore_phase16_checkpoint(
        composite,
        executor,
        decoded;
        engine_declarations=(declaration,),
    )
    @test restored isa RestoredPhase16Checkpoint
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
    @test_throws ProcessBigraphError decode_phase16_checkpoint(corrupted)
    @test_throws ProcessBigraphError decode_phase16_checkpoint(encoded[1:end - 1])
    bad_integrity = LogicalCheckpointV3(
        checkpoint_value.format_version,
        checkpoint_value.payload,
        checkpoint_value.payload_bytes,
        repeat("0", 64),
    )
    @test_throws ProcessBigraphError encode_checkpoint(bad_integrity)

    source_values = [1, 2, 3]
    source = P16ELegacySource(
        source_values, canonical_fingerprint(source_values))
    source_before = deepcopy(source)
    converted = convert_legacy_checkpoint(
        serial, P16ELegacyConverter(), source)
    @test source.values == source_before.values
    @test source.checksum == source_before.checksum
    @test length(converted.payload.components) == 2
    @test decode_phase16_checkpoint(
        encode_checkpoint(converted)).integrity == converted.integrity

    invalid = P16ELegacySource([1, 2, 3], repeat("0", 64))
    @test_throws ProcessBigraphError convert_legacy_checkpoint(
        serial, P16ELegacyConverter(), invalid)
end

@testset "Phase 16.E typed domain structural requests" begin
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

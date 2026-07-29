using ACSets

import ProcessBigraphs: StructuralIdentity, StructuralCapacity,
    CompositeDivisionPolicy, DynamicStructuralEpoch,
    AddCompositeRequest, RemoveCompositeRequest, DivideCompositeRequest,
    MoveCompositeRequest, RewireBindingRequest,
    dynamic_structural_epoch, structural_identity,
    stage_structural_transaction, publish_structural_transaction,
    structural_structure, structural_lineage, StructuralEpochCheckpoint,
    structural_checkpoint, restore_structural_checkpoint

function structural_base_structure(; binding=false)
    schema = BranchSchema(
        left=LeafSchema(Int; default=0, update_law=:add),
        right=LeafSchema(Int; default=0, update_law=:add),
    )
    scale = TimeScale(1)
    model = compose(:StructuralBaseStructure, schema; scale) do _, _
    end
    composite = compile(model)
    structure = canonical_structure(composite)
    binding || return structure

    root = only(ACSets.incident(structure, "root", :composite_id))
    stores = sort!(collect(ACSets.parts(structure, :StoreNode));
        by=row -> string(ACSets.subpart(structure, row, :store_path)))
    leaves = filter(row ->
        ACSets.subpart(structure, row, :schema_kind) === :leaf, stores)
    @assert length(leaves) == 2
    actor = ACSets.add_part!(structure, :Actor;
        actor_composite=root,
        actor_id="actor:rewire",
        actor_local_id="rewire",
        law_type="StructuralReferenceActor",
        law_version="1",
        law_parameters=(),
        capability_payload=CapabilitySet(),
        actor_domain=:cpu,
        continuation_version="1")
    ACSets.add_part!(structure, :Process;
        process_actor=actor,
        cadence_tick=1,
        first_due_tick=1,
        supports_partial=false)
    port = ACSets.add_part!(structure, :Port;
        port_actor=actor,
        port_id="port:rewire:value",
        port_name=:value,
        port_value_type="Int64",
        port_direction=:input,
        port_effect=:read,
        port_interval_behavior=:event_updated,
        port_optional=false,
        port_cardinality=:one,
        port_residency=:cpu,
        port_update_law=nothing)
    ACSets.add_part!(structure, :Binding;
        binding_port=port,
        binding_store=first(leaves),
        binding_id="binding:rewire:value",
        transfer_payload=nothing)
    structure
end

function structural_child(epoch, event)
    record = only(filter(value -> value.birth_event == event,
        structural_lineage(epoch)))
    record.child
end

function structural_error(f)
    try
        f()
        nothing
    catch error
        error
    end
end

function structural_shrink_conflict(structure, requests)
    reduced = collect(requests)
    changed = true
    while changed && length(reduced) > 2
        changed = false
        for index in eachindex(reduced)
            candidate = reduced[setdiff(eachindex(reduced), [index])]
            error = structural_error() do
                ProcessBigraphs._select_requests(candidate, structure)
            end
            if error isa ProcessBigraphError &&
                    error.code === :unresolved_structural_conflict
                reduced = candidate
                changed = true
                break
            end
        end
    end
    tuple(reduced...)
end

@testset "structural transaction immutable epochs and DPO-backed stable operations" begin
    source = dynamic_structural_epoch(
        structural_base_structure();
        capacity=StructuralCapacity(composites=12, total_parts=128),
    )
    root = structural_identity(source, :Composite, "root")
    source_fingerprint = structural_fingerprint(source)
    source_rows = ACSets.nparts(structural_structure(source), :Composite)

    add_a = AddCompositeRequest("add-a", 0, root, "cell", :a)
    add_b = AddCompositeRequest("add-b", 0, root, "cell", :b)
    staged = stage_structural_transaction(source, (add_b, add_a);
        numeric_candidate=(mass=2.0,))
    @test structural_fingerprint(source) == source_fingerprint
    @test ACSets.nparts(structural_structure(source), :Composite) == source_rows
    @test ACSets.nparts(staged.candidate_structure, :Composite) == 3
    @test all(value -> value.status === :selected, staged.dispositions)

    reordered = stage_structural_transaction(source, (add_a, add_b);
        numeric_candidate=(mass=2.0,))
    @test reordered.candidate_fingerprint == staged.candidate_fingerprint
    @test structural_fingerprint(reordered.candidate_structure) ==
        structural_fingerprint(staged.candidate_structure)

    epoch1 = publish_structural_transaction(source, staged;
        validate_numeric=value -> value.mass == 2.0)
    @test ProcessBigraphs.structural_epoch(epoch1) == 1
    @test structural_fingerprint(epoch1) == staged.candidate_fingerprint
    @test ACSets.nparts(structural_structure(epoch1), :Composite) == 3
    @test length(structural_lineage(epoch1)) == 2

    a = structural_child(epoch1, "add-a")
    b = structural_child(epoch1, "add-b")
    move = MoveCompositeRequest("move-a", 1, a, b, :nested)
    epoch2 = publish_structural_transaction(
        epoch1, stage_structural_transaction(epoch1, (move,)))
    structure2 = structural_structure(epoch2)
    a_row = only(ACSets.incident(structure2, a.id, :composite_id))
    b_row = only(ACSets.incident(structure2, b.id, :composite_id))
    containment = only(ACSets.incident(
        structure2, a_row, :composite_child))
    @test ACSets.subpart(structure2, containment, :composite_parent) == b_row
    @test ACSets.subpart(structure2, containment, :mount_key) === :nested
    @test structural_identity(epoch2, :Composite, a.id) == a

    cycle = MoveCompositeRequest("cycle", 2, b, a, :cycle)
    cycle_error = structural_error() do
        stage_structural_transaction(epoch2, (cycle,))
    end
    @test cycle_error isa ProcessBigraphError
    @test cycle_error.code === :composite_cycle
    @test structural_fingerprint(epoch2) ==
        structural_fingerprint(
            publish_structural_transaction(epoch1,
                stage_structural_transaction(epoch1, (move,))))

    divide = DivideCompositeRequest(
        "divide-a", 2, a, "daughter", :daughter;
        policies=CompositeDivisionPolicy(),
    )
    epoch3 = publish_structural_transaction(
        epoch2, stage_structural_transaction(epoch2, (divide,)))
    daughter = structural_child(epoch3, "divide-a")
    daughter_lineage = only(filter(value ->
        value.birth_event == "divide-a", structural_lineage(epoch3)))
    @test daughter_lineage.parent == a
    @test structural_identity(epoch3, :Composite, a.id) == a
    @test structural_identity(epoch3, :Composite, daughter.id) == daughter

    incomplete_remove = RemoveCompositeRequest(
        "remove-b-bad", 3, b; owned_closure=(b,))
    closure_error = structural_error() do
        stage_structural_transaction(epoch3, (incomplete_remove,))
    end
    @test closure_error isa ProcessBigraphError
    @test closure_error.code === :owned_closure_mismatch
    @test ACSets.nparts(structural_structure(epoch3), :Composite) == 4

    remove = RemoveCompositeRequest(
        "remove-b", 3, b; owned_closure=(b, a, daughter))
    epoch4 = publish_structural_transaction(
        epoch3, stage_structural_transaction(epoch3, (remove,)))
    @test ACSets.nparts(structural_structure(epoch4), :Composite) == 1
    @test structural_identity(epoch4, :Composite, "root") == root
    retired_error = structural_error() do
        structural_identity(epoch4, :Composite, a.id)
    end
    @test retired_error isa ProcessBigraphError
    @test retired_error.code === :unknown_structural_identity
end

@testset "structural transaction conflicts, capacity, generations, and atomic failure" begin
    source = dynamic_structural_epoch(
        structural_base_structure();
        capacity=StructuralCapacity(composites=3, total_parts=64),
    )
    root = structural_identity(source, :Composite, "root")
    baseline = structural_fingerprint(source)

    equal_left = AddCompositeRequest("same-left", 0, root, "cell", :same)
    equal_right = AddCompositeRequest("same-right", 0, root, "cell", :same)
    equal_error = structural_error() do
        stage_structural_transaction(source, (equal_right, equal_left))
    end
    @test equal_error isa ProcessBigraphError
    @test equal_error.code === :unresolved_structural_conflict
    @test structural_fingerprint(source) == baseline

    high = AddCompositeRequest(
        "high", 0, root, "cell", :same; priority=10)
    low = AddCompositeRequest(
        "low", 0, root, "cell", :same; priority=1)
    priority_candidate = stage_structural_transaction(source, (low, high))
    @test count(value -> value.status === :selected,
        priority_candidate.dispositions) == 1
    @test only(filter(value -> value.request_id == "low",
        priority_candidate.dispositions)).conflicting_with == "high"
    priority_epoch = publish_structural_transaction(source, priority_candidate)
    @test ACSets.nparts(structural_structure(priority_epoch), :Composite) == 2

    too_many = (
        AddCompositeRequest("capacity-a", 0, root, "cell", :a),
        AddCompositeRequest("capacity-b", 0, root, "cell", :b),
        AddCompositeRequest("capacity-c", 0, root, "cell", :c),
    )
    capacity_error = structural_error() do
        stage_structural_transaction(source, too_many)
    end
    @test capacity_error isa ProcessBigraphError
    @test capacity_error.code === :structural_capacity_exceeded
    @test structural_fingerprint(source) == baseline

    stale_identity = StructuralIdentity(:Composite, "root", 1)
    generation_error = structural_error() do
        stage_structural_transaction(source,
            (AddCompositeRequest(
                "generation", 0, stale_identity, "cell", :generation),))
    end
    @test generation_error isa ProcessBigraphError
    @test generation_error.code === :unknown_structural_identity

    stale_epoch_error = structural_error() do
        stage_structural_transaction(source,
            (AddCompositeRequest("stale", 1, root, "cell", :stale),))
    end
    @test stale_epoch_error isa ProcessBigraphError
    @test stale_epoch_error.code === :stale_structural_epoch

    request = AddCompositeRequest("atomic", 0, root, "cell", :atomic)
    numeric = stage_structural_transaction(source, (request,);
        numeric_candidate=(valid=false,))
    numeric_error = structural_error() do
        publish_structural_transaction(source, numeric;
            validate_numeric=value -> value.valid)
    end
    @test numeric_error isa ProcessBigraphError
    @test numeric_error.code === :numeric_structural_validation_failed
    @test structural_fingerprint(source) == baseline

    for stage in (:selection, :reference, :rewrite, :validation)
        error = structural_error() do
            stage_structural_transaction(
                source, (request,); inject_failure=stage)
        end
        @test error isa ProcessBigraphError
        @test error.code === :injected_structural_failure
        @test structural_fingerprint(source) == baseline
    end
    publication_error = structural_error() do
        publish_structural_transaction(source, numeric;
            inject_failure=true)
    end
    @test publication_error isa ProcessBigraphError
    @test publication_error.code === :injected_structural_failure
    @test structural_fingerprint(source) == baseline

    published = publish_structural_transaction(source, numeric;
        validate_numeric=value -> true)
    stale_candidate_error = structural_error() do
        publish_structural_transaction(published, numeric)
    end
    @test stale_candidate_error isa ProcessBigraphError
    @test stale_candidate_error.code === :stale_structural_candidate
end

@testset "structural transaction typed binding rewire" begin
    source = dynamic_structural_epoch(structural_base_structure(binding=true))
    binding = structural_identity(
        source, :Binding, "binding:rewire:value")
    structure = structural_structure(source)
    leaf_rows = filter(row ->
        ACSets.subpart(structure, row, :schema_kind) === :leaf,
        collect(ACSets.parts(structure, :StoreNode)))
    old_row = Int(ACSets.subpart(
        structure,
        only(ACSets.incident(structure, binding.id, :binding_id)),
        :binding_store,
    ))
    new_row = only(setdiff(Set(leaf_rows), Set([old_row])))
    new_store_id = String(ACSets.subpart(structure, new_row, :store_id))
    new_store = structural_identity(source, :StoreNode, new_store_id)
    request = RewireBindingRequest("rewire", 0, binding, new_store)
    published = publish_structural_transaction(
        source, stage_structural_transaction(source, (request,)))
    result = structural_structure(published)
    binding_row = only(ACSets.incident(result, binding.id, :binding_id))
    result_store = Int(ACSets.subpart(result, binding_row, :binding_store))
    @test ACSets.subpart(result, result_store, :store_id) == new_store.id
    @test ACSets.subpart(result, binding_row, :binding_id) == binding.id
end

@testset "structural transaction settled-boundary structural restart" begin
    epochs = DynamicStructuralEpoch[]
    source = dynamic_structural_epoch(
        structural_base_structure();
        capacity=StructuralCapacity(composites=8, total_parts=96),
    )
    push!(epochs, source)
    root = structural_identity(source, :Composite, "root")
    first_request = AddCompositeRequest(
        "restart-a", 0, root, "cell", :a)
    first_epoch = publish_structural_transaction(
        source, stage_structural_transaction(source, (first_request,)))
    push!(epochs, first_epoch)
    first_child = structural_child(first_epoch, "restart-a")
    second_request = DivideCompositeRequest(
        "restart-divide", 1, first_child, "daughter", :daughter)
    second_epoch = publish_structural_transaction(
        first_epoch,
        stage_structural_transaction(first_epoch, (second_request,)),
    )
    push!(epochs, second_epoch)

    for epoch in epochs
        restored = restore_structural_checkpoint(structural_checkpoint(epoch))
        @test ProcessBigraphs.structural_epoch(restored) ==
            ProcessBigraphs.structural_epoch(epoch)
        @test structural_fingerprint(restored) ==
            structural_fingerprint(epoch)
        @test structural_fingerprint(structural_structure(restored)) ==
            structural_fingerprint(structural_structure(epoch))
        @test structural_lineage(restored) == structural_lineage(epoch)
    end

    restored_first =
        restore_structural_checkpoint(structural_checkpoint(first_epoch))
    direct_candidate =
        stage_structural_transaction(first_epoch, (second_request,))
    restored_candidate =
        stage_structural_transaction(restored_first, (second_request,))
    @test restored_candidate.candidate_fingerprint ==
        direct_candidate.candidate_fingerprint

    checkpoint = structural_checkpoint(second_epoch)
    corrupted = StructuralEpochCheckpoint(
        checkpoint.contract_version,
        checkpoint.ordinal,
        checkpoint.structure,
        checkpoint.epoch_fingerprint,
        checkpoint.identities,
        checkpoint.lineage,
        checkpoint.capacity,
        string(checkpoint.checksum, "corrupt"),
    )
    corruption_error = structural_error() do
        restore_structural_checkpoint(corrupted)
    end
    @test corruption_error isa ProcessBigraphError
    @test corruption_error.code === :structural_checkpoint_checksum_mismatch
end

@testset "structural transaction exhaustive bounded candidate-order oracle" begin
    source = dynamic_structural_epoch(
        structural_base_structure();
        capacity=StructuralCapacity(composites=5, total_parts=96),
    )
    root = structural_identity(source, :Composite, "root")
    requests = (
        AddCompositeRequest("order-a", 0, root, "cell", :a),
        AddCompositeRequest("order-b", 0, root, "cell", :b),
        AddCompositeRequest("order-c", 0, root, "cell", :c),
    )
    orders = (
        (1, 2, 3), (1, 3, 2), (2, 1, 3),
        (2, 3, 1), (3, 1, 2), (3, 2, 1),
    )
    fingerprints = String[]
    structure_fingerprints = String[]
    for order in orders
        candidate = stage_structural_transaction(
            source, tuple((requests[index] for index in order)...))
        push!(fingerprints, candidate.candidate_fingerprint)
        push!(structure_fingerprints,
            structural_fingerprint(candidate.candidate_structure))
    end
    @test length(unique(fingerprints)) == 1
    @test length(unique(structure_fingerprints)) == 1
    @test ACSets.nparts(
        stage_structural_transaction(source, requests).candidate_structure,
        :Composite,
    ) == 4
end

@testset "structural transaction bounded conflict fuzz and shrink" begin
    source = dynamic_structural_epoch(structural_base_structure())
    root = structural_identity(source, :Composite, "root")
    structure = structural_structure(source)
    cases = 0
    expected_conflicts = 0
    for left_mount in (:a, :b, :c), right_mount in (:a, :b, :c),
            left_priority in 0:2, right_priority in 0:2
        left = AddCompositeRequest(
            "fuzz-left-$(cases)", 0, root, "cell", left_mount;
            priority=left_priority)
        right = AddCompositeRequest(
            "fuzz-right-$(cases)", 0, root, "cell", right_mount;
            priority=right_priority)
        error = structural_error() do
            ProcessBigraphs._select_requests((right, left), structure)
        end
        conflict =
            left_mount === right_mount &&
            left_priority == right_priority
        if conflict
            expected_conflicts += 1
            @test error isa ProcessBigraphError
            @test error.code === :unresolved_structural_conflict
        else
            @test isnothing(error)
        end
        cases += 1
    end
    @test cases == 81
    @test expected_conflicts == 9

    conflict_a = AddCompositeRequest(
        "shrink-a", 0, root, "cell", :collision)
    irrelevant = AddCompositeRequest(
        "shrink-independent", 0, root, "cell", :independent)
    conflict_b = AddCompositeRequest(
        "shrink-b", 0, root, "cell", :collision)
    shrunk = structural_shrink_conflict(
        structure, (conflict_a, irrelevant, conflict_b))
    @test length(shrunk) == 2
    @test Set(request.mount_key for request in shrunk) == Set([:collision])
end

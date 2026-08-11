@testset "non-CPM deterministic z-buffer drives its lowering" begin
    fixture = _zbuffer_fixture()
    declaration = LW.inspect(fixture.work)
    planned = LW.inspect(fixture.workplan)
    prepared_facts = LW.inspect(fixture.prepared)
    @test_throws Exception wait(LW.WorkEvent(
        LW._CONSTRUCTION_TOKEN, fixture.prepared, UInt64(0)
    ))
    @test_throws Exception wait(LW.WorkEvent(
        LW._CONSTRUCTION_TOKEN, fixture.prepared, UInt64(1)
    ))

    @test isimmutable(fixture.work)
    @test isimmutable(fixture.workplan)
    @test declaration.items == 1:5
    @test declaration.reads.rank == :fragment_depths
    @test keys(declaration.outputs) == (:framebuffer_color,)
    @test declaration.outputs.framebuffer_color.empty == UInt32(0)
    @test declaration.outputs.framebuffer_color.rank.order == :min
    @test declaration.outputs.framebuffer_color.mask == :fragment_coverage
    @test declaration.active == :fragment_count
    @test declaration.operation.family == :resolved_selection
    @test declaration.operation.emission.values == :value
    @test declaration.operation.emission.mask == :mask

    @test planned.lowering == :resolved_selection_min_Int32_UInt32_v1
    @test planned.workspace.total_bytes == 32
    @test planned.workspace.rank.bytes == 16
    @test planned.workspace.identity.bytes == 16
    @test planned.topology_transfer_bytes == 40
    @test planned.ports.framebuffer_color.route == :pixel_indices
    @test planned.ports.framebuffer_color.destination_count == 4
    @test planned.ports.framebuffer_color.maximum_emissions == 1
    @test planned.ports.framebuffer_color.coverage == :not_applicable
    @test planned.ports.framebuffer_color.law.kind == :resolved
    @test planned.ports.framebuffer_color.law.emission_mask == :mask
    @test planned.ports.framebuffer_color.law.mask_binding ==
        :fragment_coverage
    @test planned.ports.framebuffer_color.publication_phase == :publication
    @test planned.ports.framebuffer_color.post_launch_failure_visibility ==
        :publication_phase_is_not_transactional
    @test planned.ports.framebuffer_color.empty_destination == UInt32(0)
    @test planned.ports.framebuffer_color.determinism == planned.determinism
    literal_true = _zbuffer_declaration(; emission_mask = true)
    literal_false = _zbuffer_declaration(; emission_mask = false)
    true_plan = LW.inspect(LW.plan(
        literal_true.work, literal_true.topology; backend = KA.CPU()
    ))
    false_plan = LW.inspect(LW.plan(
        literal_false.work, literal_false.topology; backend = KA.CPU()
    ))
    @test true_plan.ports.framebuffer_color.law.emission_mask === true
    @test false_plan.ports.framebuffer_color.law.emission_mask === false
    @test true_plan.ports.framebuffer_color.law !=
        false_plan.ports.framebuffer_color.law
    @test planned.capability == (
        backend = KA.CPU,
        compiler = (
            julia = VERSION,
            kernelabstractions = Base.pkgversion(KA),
            atomix = Base.pkgversion(LW.Atomix),
            adapt = Base.pkgversion(LW.Adapt),
            backend_package_uuid =
                "63c18a36-062a-441e-b654-da1e3ab1ce7c",
            backend_package_version = Base.pkgversion(KA),
            backend_module = "KernelAbstractions",
            backend_type = "CPU",
            device_type = "Int64",
            device_value = "1",
            device_identity = (
                source = :kernelabstractions,
                type = "Int64",
                value = "1",
            ),
            runtime_identity = (;),
            provider_preferences = (;),
            kernel = Sys.KERNEL,
            architecture = Sys.ARCH,
            machine = Sys.MACHINE,
            cpu = Sys.CPU_NAME,
            word_size = Sys.WORD_SIZE,
            qualification = :centrally_reviewed_environment,
        ),
        key_type = Int32,
        rank_type = Int32,
        identity_type = UInt32,
        value_type = UInt32,
        atomic_operation = :min,
        address_space = :global,
    )
    @test prepared_facts.bindings == (
        :fragment_depths,
        :fragment_colors,
        :framebuffer_color,
        :fragment_coverage,
    )
    @test prepared_facts.lowering_detail.output_port == :framebuffer_color
    @test prepared_facts.static_binding_facts.fragment_depths == (
        identity = objectid(fixture.storage.fragment_depths),
        element_type = Int32,
        dimensions = 1,
        size = (5,),
        strides = (1,),
        backend = KA.CPU,
        device = (
            backend = KA.CPU,
            device_token_type = Int,
            device_token = 1,
            scope = :reviewed_backend_device_context,
        ),
    )
    @test prepared_facts.submission_slot_facts.fragment_count == (
        kind = :value,
        type = Int32,
        bounds = Int32(0):Int32(5),
    )
    @test keys(planned.determinism) == LW._DETERMINISM_DIMENSIONS
    expected_guarantees = (
        same_run_replay = :qualified_exact_integer_order,
        workgroup_size_invariance = :not_claimed,
        bucket_order_invariance = :not_applicable,
        scheduling_invariance = :qualified_exact_integer_order,
        same_backend_bitwise = :qualified_exact_integer_order,
        cross_backend_bitwise = :not_claimed,
        numerical_bound = :exact_for_declared_integer_order,
        rng_trajectory = :domain_owned,
    )
    for (dimension, fact) in pairs(planned.determinism)
        @test fact.backend == :CPU
        @test fact.key_type == Int32
        @test fact.rank_type == Int32
        @test fact.identity_type == UInt32
        @test fact.value_type == UInt32
        @test fact.atomic_operation == :min
        @test fact.address_space == :global
        @test fact.compiler == planned.capability.compiler
        @test fact.lowering_identity == planned.lowering
        @test fact.guarantee == getproperty(expected_guarantees, dimension)
    end

    event = LW.run!(
        fixture.prepared, (; fragment_count = Int32(5))
    )
    @test LW.inspect(fixture.prepared).wait_count == 0
    wait(event)
    @test fixture.storage.framebuffer_color == UInt32[0x22, 0x33, 0x55, 0]
    @test fixture.workspace.winner_ranks == Int32[-2, -1, 4, 100]
    @test fixture.workspace.winner_identities ==
          UInt32[10, 30, 40, typemax(UInt32)]
    @test LW.inspect(fixture.prepared).wait_count == 1
    @test LW.inspect(event).receipt_scope == :lane_tail
end

@testset "bounded two-key conjunctive resolution is exact and inspectable" begin
    fixture = _conjunctive_fixture()
    declaration = LW.inspect(fixture.work)
    planned = LW.inspect(fixture.workplan)
    prepared = LW.inspect(fixture.prepared)

    @test declaration.family == :resolved_conjunctive_selection
    @test declaration.outputs.dispositions.family == :resolved
    @test declaration.outputs.dispositions.destinations ==
          (:old_claims, :new_claims)
    @test declaration.outputs.dispositions.result.layout == :items
    @test planned.lowering ==
          :resolved_conjunctive_two_key_UInt32_UInt8_v1
    @test planned.launches == 4
    @test planned.topology_transfer_bytes == 0
    @test planned.workspace.total_bytes == 32
    @test planned.ports.dispositions.route == (:old_claims, :new_claims)
    @test planned.ports.dispositions.destination_count == 4
    @test planned.ports.dispositions.result_count == 6
    @test planned.ports.dispositions.maximum_emissions == 2
    @test planned.ports.dispositions.coverage == :not_applicable
    @test planned.ports.dispositions.law.kind == :conjunctive_resolved
    @test planned.ports.dispositions.publication_phase == :publication
    @test planned.ports.dispositions.post_launch_failure_visibility ==
        :publication_phase_is_not_transactional
    @test planned.ports.dispositions.publication_target == :item_result
    @test planned.ports.dispositions.result_layout == :items
    @test planned.ports.dispositions.empty_destination ==
        :not_published_for_private_claim_destinations
    @test planned.ports.dispositions.empty_result == UInt8(2)
    @test planned.ports.dispositions.private_key_no_winner_state == (
        rank = UInt32(0), identity = typemax(UInt32)
    )
    @test planned.ports.dispositions.determinism == planned.determinism
    @test prepared.binding_access.dispositions == :readwrite
    @test prepared.lowering_detail.profile ==
          :bounded_conjunctive_selection
    @test prepared.lowering_detail.maximum_emissions == 2
    @test prepared.lowering_detail.absent_key == :nonpositive
    @test prepared.lowering_detail.result_layout == :items
    @test prepared.lowering_detail.selection ==
          :all_emitted_destinations
    @test prepared.lowering_detail.alias_proof ==
          :proven_pointwise_readwrite

    event = LW.run!(fixture.prepared, (; active_count = Int32(6)))
    wait(event)
    @test fixture.storage.dispositions == UInt8[2, 2, 2, 5, 5, 4]
    @test fixture.workspace.winner_ranks == UInt32[10, 11, 9, 8]
    @test fixture.workspace.winner_identities == UInt32[10, 50, 20, 30]
    @test LW.inspect(fixture.prepared).submitted == UInt64(1)
    @test LW.inspect(fixture.prepared).drained == UInt64(1)

    tied = _conjunctive_fixture(
        keys_a = Int32[1, 1],
        keys_b = Int32[0, 0],
        ranks = UInt32[7, 7],
        identities = Int32[100, 200],
        values = UInt8[5, 5],
    )
    wait(LW.run!(tied.prepared, (; active_count = Int32(2))))
    @test tied.storage.dispositions == UInt8[5, 2]
    @test tied.workspace.winner_identities[1] == UInt32(100)

    closed = _conjunctive_fixture(gate = Bool[false])
    before_values = copy(closed.storage.dispositions)
    before_ranks = copy(closed.workspace.winner_ranks)
    before_identities = copy(closed.workspace.winner_identities)
    wait(LW.run!(closed.prepared, (; active_count = Int32(6))))
    @test closed.storage.dispositions == before_values
    @test closed.workspace.winner_ranks == before_ranks
    @test closed.workspace.winner_identities == before_identities

    inactive = _conjunctive_fixture()
    inactive.storage.old_claims[4] = typemax(Int32)
    inactive.storage.semantic_ids[4] = Int32(0)
    wait(LW.run!(inactive.prepared, (; active_count = Int32(3))))
    @test !LW.inspect(inactive.prepared).poisoned

    for mutate! in (
            fixture -> (fixture.storage.old_claims[2] = Int32(5)),
            fixture -> (fixture.storage.semantic_ids[2] = Int32(10)),
            fixture -> (fixture.storage.semantic_ids[1] = Int32(0)),
        )
        facts = fetch(@async begin
            failing = _conjunctive_fixture()
            mutate!(failing)
            failure = try
                event = LW.run!(
                    failing.prepared, (; active_count = Int32(6))
                )
                wait(event)
                nothing
            catch error
                error
            end
            (; failure, poisoned = LW.inspect(failing.prepared).poisoned)
        end)
        @test facts.failure !== nothing
        @test facts.poisoned
    end

    @test_throws ArgumentError LW.resolved(
        (:a, :b);
        empty = UInt8(2),
        rank = (
            type = UInt32,
            order = :max,
            lower = UInt32(0),
            upper = typemax(UInt32),
        ),
        tie_break = (
            input_type = Int32,
            type = UInt32,
            order = :min,
            transform = :checked_unsigned,
            proof = :caller_promises_unique,
        ),
        capacity = 2,
        key_type = Int32,
        value_type = UInt8,
        skipped_keys = :nonpositive,
        result = (
            layout = :items,
            selection = :all,
            zero_claim = :selected,
            selected = :preserve,
            ineligible = :preserve,
        ),
    )
end

@testset "rank sentinel, empty result, mask, and active selection execute" begin
    unsafe_payload() = error("payload evaluated eagerly")
    @test_throws ErrorException LW.masked(unsafe_payload(), false)

    max_fixture = _zbuffer_fixture(
        rank_order = :max,
        ranks = Int32[-8, -2, -4, 0, -5],
    )
    event = LW.run!(
        max_fixture.prepared, (; fragment_count = Int32(5))
    )
    wait(event)
    # Pixel 1 chooses -2; pixel 2 ignores the masked rank 0 and chooses -4.
    @test max_fixture.storage.framebuffer_color ==
          UInt32[0x22, 0x33, 0x55, 0]
    @test max_fixture.workspace.winner_ranks == Int32[-2, -4, -5, -100]

    endpoint_fixture = _zbuffer_fixture(
        ranks = Int32[-100, 0, 100, -1, 100],
    )
    event = LW.run!(
        endpoint_fixture.prepared, (; fragment_count = Int32(5))
    )
    wait(event)
    @test endpoint_fixture.storage.framebuffer_color ==
          UInt32[0x11, 0x33, 0x55, 0]
    @test endpoint_fixture.workspace.winner_identities ==
          UInt32[50, 30, 40, typemax(UInt32)]

    active_fixture = _zbuffer_fixture()
    active_fixture.storage.fragment_depths[5] = Int32(1000)
    event = LW.run!(
        active_fixture.prepared, (; fragment_count = Int32(2))
    )
    wait(event)
    @test active_fixture.storage.framebuffer_color == UInt32[0x22, 0, 0, 0]
    @test !LW.inspect(active_fixture.prepared).poisoned

    facts = fetch(@async begin
        failing = _zbuffer_fixture()
        failing.storage.fragment_depths[5] = Int32(1000)
        failure = try
            LW.run!(failing.prepared, (; fragment_count = Int32(5)))
            nothing
        catch error
            error
        end
        (; failure, poisoned = LW.inspect(failing.prepared).poisoned)
    end)
    @test facts.failure !== nothing
    @test facts.poisoned
end

@testset "logical names derive physical storage and workspace is real" begin
    fixture = _zbuffer_fixture()
    @test !hasproperty(fixture.storage, :keys)
    @test !hasproperty(fixture.storage, :priorities)
    @test !hasproperty(fixture.storage, :winner_priorities)
    @test !hasproperty(fixture.storage, :winner_identities)
    @test hasproperty(fixture.workspace, :winner_ranks)
    @test hasproperty(fixture.workspace, :winner_identities)

    short_rank_workspace = merge(
        fixture.workspace,
        (; winner_ranks = Vector{Int32}(undef, 3)),
    )
    @test_throws Exception LW.prepare(
        fixture.workplan,
        fixture.storage;
        workspace = short_rank_workspace,
        submission = fixture.submission,
    )
    short_identity_workspace = merge(
        fixture.workspace,
        (; winner_identities = Vector{UInt32}(undef, 3)),
    )
    @test_throws Exception LW.prepare(
        fixture.workplan,
        fixture.storage;
        workspace = short_identity_workspace,
        submission = fixture.submission,
    )

    facts = LW.inspect(fixture.prepared)
    rank_identity = facts.lowering_detail.workspace.rank_identity
    identity_identity = facts.lowering_detail.workspace.identity_identity
    lease_identity = facts.lease_identity
    for _ in 1:4
        LW.run!(
            fixture.prepared, (; fragment_count = Int32(5))
        )
        GC.gc(false)
        tail = LW.run!(
            fixture.prepared, (; fragment_count = Int32(5))
        )
        wait(tail)
    end
    warm = LW.inspect(fixture.prepared)
    @test warm.lowering_detail.workspace.rank_identity == rank_identity
    @test warm.lowering_detail.workspace.identity_identity == identity_identity
    @test warm.lease_identity == lease_identity
end

@testset "submission storage slots are operational" begin
    declaration = _zbuffer_declaration()
    backend = KA.CPU()
    workplan = LW.plan(
        declaration.work, declaration.topology; backend
    )
    ranks_a = Int32[0, -2, -1, -1, 4]
    colors_a = UInt32[0x11, 0x22, 0x33, 0x44, 0x55]
    output_a = fill(UInt32(0xff), 4)
    ranks_b = Int32[-3, -4, 2, 2, 1]
    colors_b = UInt32[0xaa, 0xbb, 0xcc, 0xdd, 0xee]
    output_b = fill(UInt32(0xff), 4)
    static_storage = (
        fragment_coverage = Bool[true, true, true, false, true],
    )
    workspace = (
        winner_ranks = Vector{Int32}(undef, 4),
        winner_identities = Vector{UInt32}(undef, 4),
        leases = Any[nothing, nothing],
    )
    schema = (
        fragment_count = LW.value_slot(
            Int32; bounds = Int32(0):Int32(5)
        ),
        fragment_depths = LW.storage_slot(ranks_a; access = :read),
        fragment_colors = LW.storage_slot(colors_a; access = :read),
        framebuffer_color = LW.storage_slot(output_a; access = :write),
    )
    prepared = LW.prepare(
        workplan, static_storage; workspace, submission = schema
    )
    event_a = LW.run!(prepared, (;
        fragment_count = Int32(5),
        fragment_depths = ranks_a,
        fragment_colors = colors_a,
        framebuffer_color = output_a,
    ))
    wait(event_a)
    event_b = LW.run!(prepared, (;
        framebuffer_color = output_b,
        fragment_colors = colors_b,
        fragment_depths = ranks_b,
        fragment_count = Int32(5),
    ))
    wait(event_b)
    @test output_a == UInt32[0x22, 0x33, 0x55, 0]
    @test output_b == UInt32[0xbb, 0xcc, 0xee, 0]
    @test LW.inspect(prepared).submitted == UInt64(2)
end

@testset "ordered stages retain declarations and implicit visibility" begin
    topology = (
        pixel_indices = Int32[1, 2, 3, 4],
        primitive_ids = UInt32[1, 2, 3, 4],
        item_count = Int32(4),
        destination_count = Int32(4),
        epoch = UInt64(9),
    )
    make_stage(
            value_binding,
            rank_binding,
            output_name;
            rank_order = :min,
            mask_binding = nothing,
        ) = begin
        output = LW.resolved(
            :pixel_indices;
            empty = UInt32(0),
            rank = (
                type = Int32,
                order = rank_order,
                lower = Int32(-10),
                upper = Int32(10),
            ),
            tie_break = (type = UInt32, order = :min),
            capacity = 4,
            key_type = Int32,
            value_type = UInt32,
            mask = mask_binding,
        )
        reads = (
            key = :pixel_indices,
            rank = rank_binding,
            identity = :primitive_ids,
            value = value_binding,
        )
        operation_mask = true
        if mask_binding !== nothing
            reads = merge(reads, (; mask = mask_binding))
            operation_mask = :mask
        end
        LW.localwork(
            (family = :resolved_selection,
             emission = LW.masked(:value, operation_mask)),
            1:4;
            read = reads,
            outputs = NamedTuple{(output_name,)}((output,)),
        )
    end
    first_stage = make_stage(
        :source_colors, :first_depths, :visible_colors
    )
    second_stage = make_stage(
        :visible_colors,
        :second_depths,
        :copied_colors;
        rank_order = :max,
        mask_binding = :second_coverage,
    )
    work = LW.sequence(first_stage, second_stage)
    workplan = LW.plan(work, topology; backend = KA.CPU())
    fingerprint_bypass_topology = _FingerprintBypassTopology(
        copy(topology.pixel_indices),
        copy(topology.primitive_ids),
        topology.item_count,
        topology.destination_count,
        topology.epoch,
    )
    @test_throws Exception LW.plan(
        work, fingerprint_bypass_topology; backend = KA.CPU()
    )
    storage = (
        source_colors = UInt32[1, 2, 3, 4],
        first_depths = Int32[0, 0, 0, 0],
        visible_colors = fill(UInt32(99), 4),
        second_depths = Int32[1, 1, 1, 1],
        second_coverage = Bool[true, true, true, true],
        copied_colors = fill(UInt32(88), 4),
    )
    stage_workspace() = (
        winner_ranks = Vector{Int32}(undef, 4),
        winner_identities = Vector{UInt32}(undef, 4),
    )
    workspace = (
        stages = (stage_workspace(), stage_workspace()),
        leases = Any[nothing, nothing],
    )
    prepared = LW.prepare(workplan, storage; workspace)
    @test LW.inspect(work).stages[1].reads.value == :source_colors
    @test LW.inspect(work).stages[2].reads.value == :visible_colors
    @test LW.inspect(work).stages[1].outputs.visible_colors.rank.order == :min
    @test LW.inspect(work).stages[2].outputs.copied_colors.rank.order == :max
    @test LW.inspect(work).stages[1].operation.emission.mask === true
    @test LW.inspect(work).stages[2].operation.emission.mask === :mask
    @test LW.inspect(workplan).launches == 8
    event = LW.run!(prepared)
    @test LW.inspect(prepared).wait_count == 0
    wait(event)
    @test storage.visible_colors == UInt32[1, 2, 3, 4]
    @test storage.copied_colors == UInt32[1, 2, 3, 4]
    @test LW.inspect(prepared).wait_count == 1
    @test LW.inspect(workplan).stages isa Tuple
    @test LW.inspect(prepared).lowering_detail.stages isa Tuple

    reversed = LW.sequence(second_stage, first_stage)
    @test_throws Exception LW.plan(
        reversed, topology; backend = KA.CPU()
    )
    duplicate_output = LW.sequence(first_stage, first_stage)
    @test_throws Exception LW.plan(
        duplicate_output, topology; backend = KA.CPU()
    )
end

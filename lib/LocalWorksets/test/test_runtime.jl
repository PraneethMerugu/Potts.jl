@testset "central rejection, freshness, capacity, and task ownership" begin
    fixture = _zbuffer_fixture(; lease_capacity = 2)
    @test_throws LW.LocalWorkValidationError LW.plan(
        fixture.work,
        merge(fixture.topology, (epoch = Int64(1),));
        backend = KA.CPU(),
    )
    @test_throws LW.LocalWorkValidationError LW.plan(
        fixture.work,
        merge(fixture.topology, (
            destination_count = Int64(typemax(Int32)) + 1,
        ));
        backend = KA.CPU(),
    )
    conjunctive = _conjunctive_fixture()
    @test_throws LW.LocalWorkValidationError LW.plan(
        conjunctive.work,
        merge(conjunctive.topology, (epoch = Int64(1),));
        backend = KA.CPU(),
    )
    external = LW.localwork(
        (family = :external_executor, emission = LW.masked(:value, true)),
        1:5;
        read = fixture.work.reads,
        outputs = fixture.work.outputs,
        active = :fragment_count,
    )
    @test_throws Exception LW.plan(
        external, fixture.topology; backend = KA.CPU()
    )
    @test_throws ArgumentError LW.localwork(
        _UnauthorizedOperation(),
        1:5;
        read = fixture.work.reads,
        outputs = fixture.work.outputs,
        active = :fragment_count,
    )
    @test_throws Exception LW.plan(
        fixture.work, fixture.topology; backend = _UnauthorizedBackend()
    )
    @test_throws Exception LW.plan(
        fixture.work,
        fixture.topology;
        backend = _EvidenceBypassBackend(),
    )
    @test_throws Exception LW.plan(
        fixture.work,
        fixture.topology;
        backend = _OuterBypassBackend(),
    )
    fingerprint_bypass_topology = _FingerprintBypassTopology(
        copy(fixture.topology.pixel_indices),
        copy(fixture.topology.primitive_ids),
        fixture.topology.item_count,
        fixture.topology.destination_count,
        fixture.topology.epoch,
    )
    @test_throws Exception LW.plan(
        fixture.work, fingerprint_bypass_topology; backend = KA.CPU()
    )
    external_workspace = _ExternalWorkspace(
        Vector{Int32}(undef, 4),
        Vector{UInt32}(undef, 4),
        Any[nothing],
    )
    @test_throws Exception LW.prepare(
        fixture.workplan,
        fixture.storage;
        workspace = external_workspace,
        submission = fixture.submission,
    )
    lowering = fixture.workplan.lowering
    @test_throws Exception invoke(
        LW._centrally_admitted_lowering_call,
        Tuple{Function, Tuple, Symbol},
        LW._workspace_arrays,
        (lowering, fixture.work, external_workspace),
        :workspace_arrays,
    )
    @test_throws Exception invoke(
        LW._centrally_admitted_lowering_call,
        Tuple{Function, Tuple, Symbol},
        LW._prepare_lowering,
        (
            lowering,
            fixture.work,
            fixture.storage,
            external_workspace,
            KA.CPU(),
        ),
        :preparation,
    )
    @test_throws Exception invoke(
        LW._centrally_admitted_lowering_call,
        Tuple{Function, Tuple, Symbol},
        LW._execute_lowering!,
        (
            _ExternalRuntime(),
            lowering,
            fixture.work,
            fixture.storage,
            external_workspace,
            (; fragment_count = Int32(5)),
        ),
        :execution,
    )

    decorative = LW.localwork(
        fixture.work.operation,
        1:5;
        read = merge(fixture.work.reads, (; decorative = :never_bound)),
        outputs = fixture.work.outputs,
        active = :fragment_count,
    )
    @test_throws Exception LW.plan(
        decorative, fixture.topology; backend = KA.CPU()
    )
    @test_throws ArgumentError LW.resolved(
        :pixel_indices;
        empty = UInt32(0),
        rank = (type = Int32, order = :arrival,
                lower = Int32(-1), upper = Int32(1)),
        tie_break = (type = UInt32, order = :min),
        capacity = 5,
        key_type = Int32,
        value_type = UInt32,
    )

    wide_active = (;
        fragment_count = LW.value_slot(
            Int32; bounds = Int32(0):Int32(6)
        ),
    )
    @test_throws Exception LW.prepare(
        fixture.workplan,
        fixture.storage;
        workspace = (
            winner_ranks = Vector{Int32}(undef, 4),
            winner_identities = Vector{UInt32}(undef, 4),
            leases = Any[nothing],
        ),
        submission = wide_active,
    )

    aliased_workspace = (
        winner_ranks = fixture.storage.fragment_depths,
        winner_identities = Vector{UInt32}(undef, 4),
        leases = Any[nothing],
    )
    @test_throws Exception LW.prepare(
        fixture.workplan,
        fixture.storage;
        workspace = aliased_workspace,
        submission = fixture.submission,
    )

    opaque_topology = _OpaqueZTopology(
        copy(fixture.topology.pixel_indices),
        copy(fixture.topology.primitive_ids),
        fixture.topology.item_count,
        fixture.topology.destination_count,
        fixture.topology.epoch,
    )
    opaque_plan = LW.plan(
        fixture.work, opaque_topology; backend = KA.CPU()
    )
    @test LW.inspect(opaque_plan).lowering ==
          LW.inspect(fixture.workplan).lowering
    opaque_topology.pixel_indices[1] = Int32(3)
    @test_throws Exception LW.prepare(
        opaque_plan,
        fixture.storage;
        workspace = (
            winner_ranks = Vector{Int32}(undef, 4),
            winner_identities = Vector{UInt32}(undef, 4),
            leases = Any[nothing],
        ),
        submission = fixture.submission,
    )

    frozen_fixture = _zbuffer_fixture()
    frozen_fixture.topology.pixel_indices[1] = Int32(3)
    frozen_event = LW.run!(
        frozen_fixture.prepared, (; fragment_count = Int32(5))
    )
    wait(frozen_event)
    @test frozen_fixture.storage.framebuffer_color ==
          UInt32[0x22, 0x33, 0x55, 0]

    first_event = LW.run!(
        fixture.prepared, (; fragment_count = Int32(5))
    )
    second_event = LW.run!(
        fixture.prepared, (; fragment_count = Int32(5))
    )
    @test_throws Exception LW.run!(
        fixture.prepared, (; fragment_count = Int32(5))
    )
    @test !LW.inspect(fixture.prepared).poisoned
    wait(first_event)
    @test LW.inspect(fixture.prepared).drained == UInt64(2)
    @test all(isnothing, fixture.prepared.leases)
    wait(second_event)
    @test LW.inspect(fixture.prepared).wait_count == 1
    third_event = LW.run!(
        fixture.prepared, (; fragment_count = Int32(5))
    )
    wait(third_event)
    @test first_event.serial == UInt64(1)

    task_result = fetch(Threads.@spawn try
        LW.run!(fixture.prepared, (; fragment_count = Int32(1)))
        :unexpected
    catch error
        typeof(error)
    end)
    @test task_result !== :unexpected
    @test !LW.inspect(fixture.prepared).poisoned
end

@testset "generated submission rejection is exact and prelaunch" begin
    cases = (
        (;),
        (; fragment_count = Int32(5), extra = Int32(1)),
        (; fragment_count = Int64(5)),
        (; fragment_count = Int32(6)),
    )
    for submission in cases
        fixture = _zbuffer_fixture()
        @test_throws LW.LocalWorkValidationError LW.run!(
            fixture.prepared, submission
        )
        facts = LW.inspect(fixture.prepared)
        @test facts.submitted == UInt64(0)
        @test facts.drained == UInt64(0)
        @test !facts.poisoned
        @test all(isnothing, fixture.prepared.leases)
    end

    fixture = _zbuffer_fixture()
    static_storage = (
        fragment_depths = fixture.storage.fragment_depths,
        fragment_colors = fixture.storage.fragment_colors,
        framebuffer_color = fixture.storage.framebuffer_color,
    )
    schema = (
        fragment_count = fixture.submission.fragment_count,
        fragment_coverage = LW.storage_slot(
            fixture.storage.fragment_coverage; access = :read
        ),
    )
    prepared = LW.prepare(
        fixture.workplan,
        static_storage;
        workspace = fixture.workspace,
        submission = schema,
    )
    @test_throws LW.LocalWorkValidationError LW.run!(prepared, (
        fragment_count = Int32(5),
        fragment_coverage = falses(6),
    ))
    facts = LW.inspect(prepared)
    @test facts.submitted == UInt64(0)
    @test facts.drained == UInt64(0)
    @test !facts.poisoned
    @test all(isnothing, prepared.leases)
end

@testset "synchronous failure poisons the shared implicit-order scope" begin
    facts = fetch(@async begin
        bad = _zbuffer_fixture(; lease_capacity = 2)
        peer = _zbuffer_fixture(; lease_capacity = 2)
        same_lane = LW.inspect(bad.prepared).lane ==
                    LW.inspect(peer.prepared).lane
        bad.storage.fragment_depths[5] = Int32(1000)
        failure = try
            LW.run!(bad.prepared, (; fragment_count = Int32(5)))
            nothing
        catch error
            error
        end
        peer_failure = try
            LW.run!(peer.prepared, (; fragment_count = Int32(5)))
            nothing
        catch error
            error
        end
        bad_facts = LW.inspect(bad.prepared)
        peer_facts = LW.inspect(peer.prepared)
        return (;
            same_lane,
            failure,
            peer_failure,
            bad_poisoned = bad_facts.poisoned,
            peer_poisoned = peer_facts.poisoned,
            bad_submitted = bad_facts.submitted,
            peer_submitted = peer_facts.submitted,
            bad_drained = bad_facts.drained,
            peer_drained = peer_facts.drained,
            retained_leases = count(
                value -> !isnothing(value), bad.prepared.leases
            ),
            peer_leases_clear = all(isnothing, peer.prepared.leases),
            clear_launch_observed = bad.storage.framebuffer_color !=
                                    fill(UInt32(0xff), 4),
        )
    end)
    @test facts.same_lane
    @test facts.failure !== nothing
    @test facts.peer_failure !== nothing
    @test facts.bad_poisoned
    @test facts.peer_poisoned
    @test facts.bad_submitted == facts.peer_submitted == UInt64(0)
    @test facts.bad_drained == facts.peer_drained == UInt64(0)
    @test facts.retained_leases == 1
    @test facts.peer_leases_clear
    @test facts.clear_launch_observed
end

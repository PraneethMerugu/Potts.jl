struct _LocalWorksetsLevel1Scale
    factor::Int32
end

struct _LocalWorksetsDiagnosticIndependent end
function (::_LocalWorksetsDiagnosticIndependent)(item::Int32, reads, values)
    return (streamed = LocalWorksets.emit(@inbounds(reads.source[item])),)
end

struct _LocalWorksetsDiagnosticResolved end
function (::_LocalWorksetsDiagnosticResolved)(item::Int32, reads, values)
    return (
        fracture = LocalWorksets.candidate(
            UInt32(item); rank = Int32(item)
        ),
    )
end

function run_localworksets_structured_plan_faults(array_convert; backend_name)
    LW = LocalWorksets
    prototype = array_convert(Int32[0])
    backend = LW.KernelAbstractions.get_backend(prototype)
    sentinel = array_convert(fill(Int32(71), 2))

    independent = LW.localwork(
        _LocalWorksetsDiagnosticIndependent(), 1:2;
        read = (source = :source,),
        outputs = (
            streamed = LW.independent(:route; value_type = Int32),
        ),
    )
    independent_topology = LW.topology(
        independent;
        epoch = UInt64(1),
        routes = (route = reshape(Int32[1, 1], 1, 2),),
        destination_counts = (streamed = 2,),
    )
    independent_error = try
        LW.plan(independent, independent_topology; backend)
        nothing
    catch error
        error
    end

    resolved = LW.localwork(
        _LocalWorksetsDiagnosticResolved(), 1:2;
        outputs = (
            fracture = LW.resolved(
                :route;
                value_type = UInt32,
                maximum = 1,
                empty = UInt32(0),
                rank = (
                    type = Int32,
                    order = :max,
                    lower = typemin(Int32),
                    upper = typemax(Int32),
                ),
                tie_break = (type = UInt32, order = :min),
            ),
        ),
    )
    resolved_topology = LW.topology(
        resolved;
        epoch = UInt64(1),
        routes = (route = reshape(Int32[1, 1], 1, 2),),
        destination_counts = (fracture = 1,),
        semantic_ids = (fracture = reshape(UInt32[9, 9], 1, 2),),
    )
    resolved_error = try
        LW.plan(resolved, resolved_topology; backend)
        nothing
    catch error
        error
    end

    @test independent_error isa LW.LocalWorkValidationError
    @test independent_error.stage == :plan
    @test independent_error.contract == :independent_writer_uniqueness
    @test independent_error.port == :streamed
    @test resolved_error isa LW.LocalWorkValidationError
    @test resolved_error.stage == :plan
    @test resolved_error.contract == :resolved_semantic_identity_uniqueness
    @test resolved_error.port == :fracture
    @test Array(sentinel) == fill(Int32(71), 2)
    return (
        backend = backend_name,
        independent_contract = independent_error.contract,
        resolved_contract = resolved_error.contract,
        output_preserved = Array(sentinel) == fill(Int32(71), 2),
    )
end

function (operation::_LocalWorksetsLevel1Scale)(item::Int32, reads, values)
    return LocalWorksets.emit(
        @inbounds(reads.source[item]) * operation.factor
    )
end

struct _LocalWorksetsSequenceAdd end
(::_LocalWorksetsSequenceAdd)(item::Int32, reads, values) = (
    middle = LocalWorksets.emit(@inbounds(reads.source[item]) + Int32(1)),
)

struct _LocalWorksetsSequenceDouble end
(::_LocalWorksetsSequenceDouble)(item::Int32, reads, values) = (
    result = LocalWorksets.emit(@inbounds(reads.middle[item]) * Int32(2)),
)

struct _LocalWorksetsTwoLane end
(::_LocalWorksetsTwoLane)(item::Int32, reads, values) = (
    output = (
        LocalWorksets.emit(@inbounds(reads.source[item])),
        LocalWorksets.emit(@inbounds(reads.source[item]) + Int32(10)),
    ),
)

function _localworksets_zbuffer_declaration()
    LW = LocalWorksets
    topology = (
        pixel_indices = Int32[1, 1, 2, 2, 3],
        primitive_ids = UInt32[50, 10, 30, 20, 40],
        item_count = Int32(5),
        destination_count = Int32(4),
        epoch = UInt64(1),
    )
    output = LW.resolved(
        :pixel_indices;
        empty = UInt32(0),
        rank = (
            type = Int32,
            order = :min,
            lower = Int32(-100),
            upper = Int32(100),
        ),
        tie_break = (type = UInt32, order = :min),
        capacity = 5,
        key_type = Int32,
        value_type = UInt32,
        mask = :fragment_coverage,
    )
    work = LW.localwork(
        (family = :resolved_selection,
         emission = LW.masked(:value, :mask)),
        1:5;
        read = (
            key = :pixel_indices,
            rank = :fragment_depths,
            identity = :primitive_ids,
            value = :fragment_colors,
            mask = :fragment_coverage,
        ),
        outputs = (; framebuffer_color = output),
        active = :fragment_count,
    )
    return (; work, topology)
end


function _localworksets_zbuffer_fixture(
        array_convert;
        lease_capacity = 12,
        workplan = nothing,
    )
    LW = LocalWorksets
    declaration = _localworksets_zbuffer_declaration()
    prototype = array_convert(Int32[0])
    backend = LocalWorksets.KernelAbstractions.get_backend(prototype)
    workplan = workplan === nothing ? LW.plan(
        declaration.work, declaration.topology; backend
    ) : workplan
    storage = (
        fragment_depths = array_convert(Int32[-2, -2, -1, -1, 4]),
        fragment_colors = array_convert(
            UInt32[0x11, 0x22, 0x33, 0x44, 0x55]
        ),
        framebuffer_color = array_convert(fill(UInt32(0xff), 4)),
        fragment_coverage = array_convert(
            Bool[true, true, true, false, true]
        ),
    )
    workspace = (
        winner_ranks = array_convert(Vector{Int32}(undef, 4)),
        winner_identities = array_convert(Vector{UInt32}(undef, 4)),
        leases = Any[nothing for _ in 1:lease_capacity],
    )
    submission = (;
        fragment_count = LW.value_slot(
            Int32; bounds = Int32(0):Int32(5)
        ),
    )
    prepared = LW.prepare(
        workplan, storage; workspace, submission
    )
    return merge(declaration, (;
        LW, backend, workplan, prepared, storage, workspace, submission,
    ))
end


function _localworksets_sequence_fixture(array_convert)
    LW = LocalWorksets
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
    work = LW.sequence(
        make_stage(:source_colors, :first_depths, :visible_colors),
        make_stage(
            :visible_colors,
            :second_depths,
            :copied_colors;
            rank_order = :max,
            mask_binding = :second_coverage,
        ),
    )
    prototype = array_convert(Int32[0])
    backend = LocalWorksets.KernelAbstractions.get_backend(prototype)
    workplan = LW.plan(work, topology; backend)
    storage = (
        source_colors = array_convert(UInt32[1, 2, 3, 4]),
        first_depths = array_convert(Int32[0, 0, 0, 0]),
        visible_colors = array_convert(fill(UInt32(99), 4)),
        second_depths = array_convert(Int32[1, 1, 1, 1]),
        second_coverage = array_convert(Bool[true, true, true, true]),
        copied_colors = array_convert(fill(UInt32(88), 4)),
    )
    stage_workspace() = (
        winner_ranks = array_convert(Vector{Int32}(undef, 4)),
        winner_identities = array_convert(Vector{UInt32}(undef, 4)),
    )
    workspace = (
        stages = (stage_workspace(), stage_workspace()),
        leases = Any[nothing, nothing],
    )
    prepared = LW.prepare(workplan, storage; workspace)
    return (; LW, workplan, prepared, storage, workspace)
end

function _localworksets_conjunctive_fixture(array_convert; lease_capacity = 12)
    LW = LocalWorksets
    item_count = 6
    output = LW.resolved(
        (:old_claims, :new_claims);
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
            proof = :strictly_increasing_active_prefix,
        ),
        capacity = item_count,
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
    work = LW.localwork(
        (family = :resolved_conjunctive_selection, eligible = UInt8(5)),
        1:item_count;
        read = (
            key_a = :old_claims,
            key_b = :new_claims,
            rank = :priorities,
            identity = :semantic_ids,
            value = :dispositions,
            gate = :execution_open,
        ),
        outputs = (; dispositions = output),
        active = :active_count,
    )
    topology = (
        item_count = Int32(item_count),
        destination_count = Int32(4),
        epoch = UInt64(1),
    )
    prototype = array_convert(Int32[0])
    backend = LocalWorksets.KernelAbstractions.get_backend(prototype)
    workplan = LW.plan(work, topology; backend)
    storage = (
        old_claims = array_convert(Int32[1, 1, 3, 0, 2, -1]),
        new_claims = array_convert(Int32[2, 3, 4, 0, 2, 0]),
        priorities = array_convert(UInt32[10, 9, 8, 7, 11, 6]),
        semantic_ids = array_convert(Int32[10, 20, 30, 40, 50, 60]),
        dispositions = array_convert(UInt8[5, 5, 5, 5, 5, 4]),
        execution_open = array_convert(Bool[true]),
    )
    workspace = (
        winner_ranks = array_convert(fill(UInt32(0), 4)),
        winner_identities = array_convert(fill(UInt32(0), 4)),
        leases = Any[nothing for _ in 1:lease_capacity],
    )
    submission = (;
        active_count = LW.value_slot(
            Int32; bounds = Int32(0):Int32(item_count)
        ),
    )
    prepared = LW.prepare(workplan, storage; workspace, submission)
    return (; LW, backend, workplan, prepared, storage, workspace)
end


function run_localworksets_execution(
        array_convert;
        backend_name,
        compiler_cache_size = nothing,
    )
    fixture = _localworksets_zbuffer_fixture(array_convert)
    LW = fixture.LW

    # The concise single-output wrapper must remain a normal concrete device
    # callable. This is the real-Metal compilation/execution witness; the
    # wrapper introduces neither a distinct lowering nor a host callback.
    level1_work = LW.localwork(
        _LocalWorksetsLevel1Scale(Int32(3)),
        1:3,
        :scaled => LW.independent(:route; value_type = Int32);
        read = (source = :level1_source,),
    )
    level1_topology = LW.topology(
        level1_work;
        epoch = UInt64(71),
        routes = (route = reshape(Int32[2, 3, 1], 1, 3),),
        destination_counts = (scaled = 3,),
    )
    level1_storage = (
        level1_source = array_convert(Int32[4, 5, 6]),
        scaled = array_convert(fill(Int32(-1), 3)),
    )
    level1_prepared = LW.prepare(
        LW.plan(level1_work, level1_topology; backend = fixture.backend),
        level1_storage,
    )
    wait(LW.run!(level1_prepared))
    @test Array(level1_storage.scaled) == Int32[18, 12, 15]
    @test LW.inspect(level1_work).authoring == :single_output
    @test LW.inspect(level1_prepared).workspace_ownership == :package

    # Distinct generic stages own distinct routes/fingerprints but one ordered
    # topology epoch. They must compose without an intermediate host wait.
    sequence_first = LW.localwork(
        _LocalWorksetsSequenceAdd(),
        1:3;
        read = (source = :sequence_source,),
        outputs = (
            middle = LW.independent(:middle_route; value_type = Int32),
        ),
    )
    sequence_second = LW.localwork(
        _LocalWorksetsSequenceDouble(),
        1:3;
        read = (middle = :middle,),
        outputs = (
            result = LW.independent(:result_route; value_type = Int32),
        ),
    )
    generic_sequence = LW.sequence(sequence_first, sequence_second)
    sequence_topology = (
        epoch = UInt64(72),
        item_count = 3,
        routes = (
            middle_route = reshape(Int32[1, 2, 3], 1, 3),
            result_route = reshape(Int32[3, 1, 2], 1, 3),
        ),
        destination_counts = (middle = 3, result = 3),
        semantic_ids = (;),
    )
    sequence_storage = (
        sequence_source = array_convert(Int32[2, 4, 6]),
        middle = array_convert(fill(Int32(-1), 3)),
        result = array_convert(fill(Int32(-1), 3)),
    )
    sequence_prepared = LW.prepare(
        LW.plan(generic_sequence, sequence_topology; backend = fixture.backend),
        sequence_storage,
    )
    sequence_event = LW.run!(sequence_prepared)
    @test LW.inspect(sequence_prepared).wait_count == 0
    wait(sequence_event)
    @test Array(sequence_storage.middle) == Int32[3, 5, 7]
    @test Array(sequence_storage.result) == Int32[10, 14, 6]
    @test LW.inspect(sequence_prepared).wait_count == 1
    @test LW.inspect(sequence_prepared).launches == 2

    full_zero = LW.localwork(
        _LocalWorksetsTwoLane(),
        1:1;
        read = (source = :zero_source,),
        outputs = (
            output = LW.independent(
                :zero_route; value_type = Int32, maximum = 2
            ),
        ),
    )
    full_zero_topology = (
        epoch = UInt64(73),
        item_count = 1,
        routes = (zero_route = reshape(Int32[1, 0], 2, 1),),
        destination_counts = (output = 1,),
        semantic_ids = (;),
    )
    @test_throws LW.LocalWorkValidationError LW.plan(
        full_zero, full_zero_topology; backend = fixture.backend
    )

    partial_zero = LW.localwork(
        _LocalWorksetsTwoLane(),
        1:1;
        read = (source = :zero_source,),
        outputs = (
            output = LW.independent(
                :zero_route;
                value_type = Int32,
                maximum = 2,
                coverage = :partial,
            ),
        ),
    )
    partial_storage = (
        zero_source = array_convert(Int32[7]),
        output = array_convert(fill(Int32(-1), 1)),
    )
    partial_prepared = LW.prepare(
        LW.plan(partial_zero, full_zero_topology; backend = fixture.backend),
        partial_storage,
    )
    wait(LW.run!(partial_prepared))
    @test Array(partial_storage.output) == Int32[7]

    event = LW.run!(
        fixture.prepared, (; fragment_count = Int32(5))
    )
    @test LW.inspect(fixture.prepared).wait_count == 0
    wait(event)
    @test Array(fixture.storage.framebuffer_color) ==
          UInt32[0x22, 0x33, 0x55, 0]
    @test Array(fixture.workspace.winner_ranks) == Int32[-2, -1, 4, 100]
    @test Array(fixture.workspace.winner_identities) ==
          UInt32[10, 30, 40, typemax(UInt32)]

    automatic = _localworksets_zbuffer_fixture(array_convert)
    automatic_prepared = LW.prepare(
        automatic.workplan,
        automatic.storage;
        submission = automatic.submission,
        lease_capacity = 2,
    )
    automatic_before = Array(automatic.storage.framebuffer_color)
    automatic_facts = LW.inspect(automatic_prepared)
    @test automatic_facts.workspace_ownership == :package
    @test automatic_facts.allocation_class == :allocated_once_during_prepare
    @test automatic_facts.submitted == 0
    @test automatic_facts.wait_count == 0
    @test Array(automatic.storage.framebuffer_color) == automatic_before
    @test LW.KernelAbstractions.get_backend(
        automatic_prepared.workspace.winner_ranks
    ) == automatic.backend
    wait(LW.run!(
        automatic_prepared, (; fragment_count = Int32(5))
    ))
    @test Array(automatic.storage.framebuffer_color) ==
          UInt32[0x22, 0x33, 0x55, 0]

    facts = LW.inspect(fixture.prepared)
    planned = LW.inspect(fixture.workplan)
    @test facts.provider == :KernelAbstractions
    @test facts.event_scope == :backend_implicit_order_tail
    @test facts.event_cumulative
    @test !facts.event_selective
    @test facts.asynchronous_error_observation ==
          (
        synchronization = :kernelabstractions_backend_contract,
        asynchronous_failures = :backend_defined,
        failure_scope = :backend_owner_task,
    )
    @test facts.launches == 4
    @test planned.workspace.total_bytes == 32
    @test planned.topology_transfer_bytes == 40
    @test planned.capability.backend == typeof(fixture.backend)
    @test planned.qualification.operation_structure == :validated
    @test planned.qualification.provider_environment == :reviewed
    @test planned.qualification.selected_device_compilation ==
          :deferred_to_first_run
    @test planned.qualification.provider_compile_validation == :not_available
    @test planned.qualification.host_fallback == :forbidden
    @test planned.capability.compiler == (
        julia = VERSION,
        kernelabstractions = Base.pkgversion(LW.KernelAbstractions),
        atomix = Base.pkgversion(LW.Atomix),
        adapt = Base.pkgversion(LW.Adapt),
        backend_package_uuid =
            "dde4c033-4e86-420c-a63e-0dd931031962",
        backend_package_version = Base.pkgversion(Metal),
        backend_module = "Metal.MetalKernels",
        backend_type = "MetalBackend",
        device_type = "Int64",
        device_value = "1",
        device_identity = (
            source = :reviewed_backend_probe,
            name = "Apple M1 Pro",
            registryID = UInt64(0x000000010000099d),
            location = "Metal.MTL.MTLDeviceLocationBuiltIn",
            locationNumber = UInt64(0),
            lowPower = false,
            headless = false,
            removable = false,
            hasUnifiedMemory = true,
        ),
        runtime_identity = (
            macos_version = v"15.6.1",
            darwin_version = v"24.6.0",
            metal_target = v"3.2.0",
            air_target = v"2.7.0",
            metallib_target = v"1.2.8",
        ),
        provider_preferences = (
            default_storage = nothing,
            label_resources = nothing,
            nonblocking_synchronization = nothing,
            command_batching = nothing,
            command_batching_ops = nothing,
            command_batching_bytes = nothing,
            command_batching_inflight = nothing,
        ),
        kernel = Sys.KERNEL,
        architecture = Sys.ARCH,
        machine = Sys.MACHINE,
        cpu = Sys.CPU_NAME,
        word_size = Sys.WORD_SIZE,
        qualification = :centrally_reviewed_environment,
    )
    @test planned.capability.rank_type == Int32
    @test planned.capability.atomic_operation == :min
    @test planned.capability.address_space == :global

    rank_identity = facts.lowering_detail.workspace.rank_identity
    identity_identity = facts.lowering_detail.workspace.identity_identity
    lease_identity = facts.lease_identity
    for active_count in (4, 3, 2, 1, 0)
        queued = LW.run!(
            fixture.prepared,
            (; fragment_count = Int32(active_count)),
        )
        active_count == 0 && wait(queued)
    end
    warm = LW.inspect(fixture.prepared)
    @test warm.lowering_detail.workspace.rank_identity == rank_identity
    @test warm.lowering_detail.workspace.identity_identity == identity_identity
    @test warm.lease_identity == lease_identity
    @test Array(fixture.storage.framebuffer_color) == fill(UInt32(0), 4)

    cumulative_fixture = _localworksets_zbuffer_fixture(
        array_convert; lease_capacity = 12
    )
    receipts = [LW.run!(
        cumulative_fixture.prepared, (; fragment_count = Int32(5))
    ) for _ in 1:12]
    @test_throws Exception LW.run!(
        cumulative_fixture.prepared, (; fragment_count = Int32(5))
    )
    @test !LW.inspect(cumulative_fixture.prepared).poisoned
    first_receipt = first(receipts)
    wait(first_receipt)
    @test LW.inspect(cumulative_fixture.prepared).drained == UInt64(12)
    @test all(isnothing, cumulative_fixture.prepared.leases)
    wait(last(receipts))
    @test LW.inspect(cumulative_fixture.prepared).wait_count == 1

    sequence_fixture = _localworksets_sequence_fixture(array_convert)
    sequence_event = LW.run!(sequence_fixture.prepared)
    @test LW.inspect(sequence_fixture.prepared).wait_count == 0
    wait(sequence_event)
    @test Array(sequence_fixture.storage.visible_colors) == UInt32[1, 2, 3, 4]
    @test Array(sequence_fixture.storage.copied_colors) == UInt32[1, 2, 3, 4]
    @test LW.inspect(sequence_fixture.prepared).wait_count == 1
    @test LW.inspect(sequence_fixture.workplan).launches == 8

    conjunctive = _localworksets_conjunctive_fixture(array_convert)
    conjunctive_event = LW.run!(
        conjunctive.prepared, (; active_count = Int32(6))
    )
    wait(conjunctive_event)
    @test Array(conjunctive.storage.dispositions) ==
          UInt8[2, 2, 2, 5, 5, 4]
    @test Array(conjunctive.workspace.winner_ranks) ==
          UInt32[10, 11, 9, 8]
    @test Array(conjunctive.workspace.winner_identities) ==
          UInt32[10, 50, 20, 30]
    conjunctive_facts = LW.inspect(conjunctive.prepared)
    @test conjunctive_facts.launches == 4
    @test conjunctive_facts.topology_transfer_bytes == 0
    @test conjunctive_facts.lowering_detail.alias_proof ==
          :proven_pointwise_readwrite

    # One reusable plan may prepare distinct same-schema storage identities.
    # After both concrete prepared types are warm, alternating those identities
    # and changing only the bounded scalar submission must not add a backend
    # specialization. Vendor runners may supply a read-only compiler-cache
    # counter; it is evidence plumbing, not a production LocalWorksets hook.
    schema_a = _localworksets_zbuffer_fixture(array_convert)
    schema_b = _localworksets_zbuffer_fixture(
        array_convert; workplan = schema_a.workplan
    )
    @test schema_b.workplan === schema_a.workplan
    @test typeof(schema_a.prepared.runtime) ===
          typeof(schema_b.prepared.runtime)
    @test objectid(schema_a.storage.fragment_depths) !=
          objectid(schema_b.storage.fragment_depths)
    wait(LW.run!(schema_a.prepared, (; fragment_count = Int32(5))))
    wait(LW.run!(schema_b.prepared, (; fragment_count = Int32(4))))
    cache_before = compiler_cache_size === nothing ? nothing :
                   compiler_cache_size()
    for (fixture_index, active_count) in enumerate((3, 2, 5, 1, 4, 0))
        selected = isodd(fixture_index) ? schema_a : schema_b
        wait(LW.run!(
            selected.prepared,
            (; fragment_count = Int32(active_count)),
        ))
    end
    cache_after = compiler_cache_size === nothing ? nothing :
                  compiler_cache_size()
    compiler_cache_size === nothing || @test cache_after == cache_before

    wrong_task_result = fetch(Threads.@spawn try
        wait(event)
        :unexpected
    catch error
        typeof(error)
    end)
    @test wrong_task_result !== :unexpected

    return (
        backend = backend_name,
        lowering = planned.lowering,
        launches = facts.launches,
        workspace_bytes = planned.workspace.total_bytes,
        topology_transfer_bytes = planned.topology_transfer_bytes,
        lease_capacity = facts.record_capacity,
        sequence_launches = LW.inspect(sequence_fixture.workplan).launches,
        event_scope = facts.event_scope,
        asynchronous_error_observation =
            facts.asynchronous_error_observation,
        same_schema_plan_reused = schema_b.workplan === schema_a.workplan,
        same_schema_compiler_cache_entries = (
            before = cache_before,
            after = cache_after,
        ),
    )
end

function run_localworksets_device_failure(array_convert; backend_name)
    fixture = _localworksets_zbuffer_fixture(array_convert; lease_capacity = 7)
    LW = fixture.LW

    # This is a deliberate external mutation after preparation. The invalid
    # rank is observed in the production device kernel, not by a test hook.
    copyto!(
        fixture.storage.fragment_depths,
        array_convert(Int32[0, -2, -1, -1, 1000]),
    )
    event = LW.run!(
        fixture.prepared, (; fragment_count = Int32(5))
    )
    failure = try
        wait(event)
        nothing
    catch error
        error
    end
    @test failure !== nothing
    @test LW.inspect(fixture.prepared).poisoned
    @test_throws Exception LW.run!(
        fixture.prepared, (; fragment_count = Int32(1))
    )
    return (
        backend = backend_name,
        failure_type = nameof(typeof(failure)),
        poisoned = LW.inspect(fixture.prepared).poisoned,
        observation =
            LW.inspect(fixture.prepared).asynchronous_error_observation,
    )
end

function run_localworksets_shared_failure_scope(array_convert; backend_name)
    bad = _localworksets_zbuffer_fixture(array_convert; lease_capacity = 2)
    good = _localworksets_zbuffer_fixture(array_convert; lease_capacity = 2)
    @test LocalWorksets.inspect(bad.prepared).lane ==
          LocalWorksets.inspect(good.prepared).lane

    copyto!(
        bad.storage.fragment_depths,
        array_convert(Int32[0, -2, -1, -1, 1000]),
    )
    bad_event = LocalWorksets.run!(
        bad.prepared, (; fragment_count = Int32(5))
    )
    good_event = LocalWorksets.run!(
        good.prepared, (; fragment_count = Int32(5))
    )
    good_failure = try
        wait(good_event)
        nothing
    catch error
        error
    end
    bad_failure = try
        wait(bad_event)
        nothing
    catch error
        error
    end
    @test good_failure !== nothing
    @test bad_failure !== nothing
    good_facts = LocalWorksets.inspect(good.prepared)
    bad_facts = LocalWorksets.inspect(bad.prepared)
    @test good_facts.poisoned
    @test bad_facts.poisoned
    @test good_facts.drained == bad_facts.drained == UInt64(0)
    @test_throws Exception LocalWorksets.run!(
        good.prepared, (; fragment_count = Int32(1))
    )
    @test_throws Exception LocalWorksets.run!(
        bad.prepared, (; fragment_count = Int32(1))
    )
    return (
        backend = backend_name,
        scope = good_facts.asynchronous_error_observation.failure_scope,
        good_failure = nameof(typeof(good_failure)),
        bad_failure = nameof(typeof(bad_failure)),
        good_poisoned = good_facts.poisoned,
        bad_poisoned = bad_facts.poisoned,
        drained = (good_facts.drained, bad_facts.drained),
    )
end

@testset "LW-4C1 shared topology and workspace specifications are authoritative" begin
    for fixture in (_zbuffer_fixture(), _conjunctive_fixture())
        lowering = fixture.workplan.lowering
        payload = invoke(
            LW._centrally_owned_static_topology_payload,
            Tuple{Any},
            lowering,
        )
        @test invoke(
            LW._centrally_count_topology_payload_bytes,
            Tuple{Any},
            payload,
        ) == LW.inspect(fixture.workplan).topology_transfer_bytes

        copied = invoke(
            LW._centrally_copy_topology_payload,
            Tuple{Any, Any},
            KA.CPU(),
            payload,
        )
        @test typeof(copied) === typeof(payload)

        spec = invoke(
            LW._centrally_owned_workspace_spec,
            Tuple{Any, Any},
            lowering,
            fixture.work,
        )
        arrays = invoke(
            LW._workspace_arrays_from_spec,
            Tuple{Any, Tuple},
            fixture.workspace,
            spec,
        )
        @test Tuple(first.(arrays)) == Tuple(leaf.name for leaf in spec)
        @test invoke(
            LW._workspace_spec_bytes,
            Tuple{Tuple},
            spec,
        ) == LW.inspect(fixture.workplan).workspace.total_bytes
        @test all(
            array -> KA.get_backend(last(array)) == KA.CPU(), arrays
        )
    end
end

@testset "LW-4C1 shared binding requirements enforce declared access" begin
    backend = KA.CPU()
    work = LW.localwork(
        _PermutationOperation(),
        1:2;
        read = (source = :source,),
        outputs = (
            streamed = LW.independent(
                :route; value_type = Int32, coverage = :all
            ),
        ),
    )
    topology = (
        epoch = UInt64(1),
        item_count = 2,
        routes = (route = reshape(Int32[1, 2], 1, 2),),
        destination_counts = (streamed = 2,),
    )
    plan = LW.plan(work, topology; backend)
    source = Int32[1, 2]
    output = zeros(Int32, 2)
    @test_throws LW.LocalWorkValidationError LW.prepare(
        plan,
        (source = source,);
        workspace = (leases = Any[nothing],),
        submission = (
            streamed = LW.storage_slot(output; access = :read),
        ),
    )
end

struct _C2FirstOperation end
struct _C2SecondOperation end

function (::_C2FirstOperation)(item::Int32, reads, values)
    return (middle = LW.emit(@inbounds(reads.source[item]) + Int32(1)),)
end

function (::_C2SecondOperation)(item::Int32, reads, values)
    return (result = LW.emit(@inbounds(reads.middle[item]) * Int32(2)),)
end

@testset "LW-4C2 canonical topology and automatic workspace are explicit" begin
    backend = KA.CPU()
    first_work = LW.localwork(
        _C2FirstOperation(),
        1:3;
        read = (source = :source,),
        outputs = (
            middle = LW.independent(
                :middle_route; value_type = Int32, coverage = :partial
            ),
        ),
    )
    second_work = LW.localwork(
        _C2SecondOperation(),
        1:3;
        read = (middle = :middle,),
        outputs = (
            result = LW.independent(:result_route; value_type = Int32),
        ),
    )
    work = LW.sequence((first_work, second_work))
    @test LW.inspect(work).family == :ordered_sequence
    @test length(LW.inspect(work).stages) == 2
    topology = LW.topology(
        first_work;
        epoch = UInt64(4),
        routes = (
            middle_route = reshape(Int32[1, 2, 3], 1, 3),
        ),
        destination_counts = (middle = 4,),
    )
    @test topology.item_count == 3
    @test topology.destination_counts.middle == 4
    @test topology.semantic_ids == (;)
    @test_throws ArgumentError LW.topology(
        first_work;
        epoch = 4,
        routes = topology.routes,
        destination_counts = topology.destination_counts,
    )

    storage = (
        source = Int32[2, 4, 6],
        middle = fill(Int32(-1), 4),
    )
    workplan = LW.plan(first_work, topology; backend)
    prepared = LW.prepare(workplan, storage; lease_capacity = 2)
    prepared_facts = LW.inspect(prepared)
    @test prepared_facts.workspace_ownership == :package
    @test prepared_facts.allocation_class == :allocated_once_during_prepare
    @test prepared_facts.record_capacity == 2
    @test prepared_facts.algorithmic_workspace_bytes == 0
    @test prepared_facts.workspace_facts == (;)
    @test keys(prepared.workspace) == (:leases,)
    event = LW.run!(prepared)
    wait(event)
    @test storage.middle == Int32[3, 5, 7, -1]

    sequence_topology = (
        epoch = UInt64(5),
        item_count = 3,
        routes = (
            middle_route = reshape(Int32[1, 2, 3], 1, 3),
            result_route = reshape(Int32[3, 1, 2], 1, 3),
        ),
        destination_counts = (middle = 3, result = 3),
        semantic_ids = (;),
    )
    sequence_storage = (
        source = Int32[2, 4, 6],
        middle = fill(Int32(-1), 3),
        result = fill(Int32(-1), 3),
    )
    sequence_plan = LW.plan(work, sequence_topology; backend)
    @test LW.inspect(sequence_plan).launches == 2
    @test length(LW.inspect(sequence_plan).stages) == 2
    sequence_prepared = LW.prepare(
        sequence_plan, sequence_storage; lease_capacity = 1
    )
    wait(LW.run!(sequence_prepared))
    @test sequence_storage.middle == Int32[3, 5, 7]
    @test sequence_storage.result == Int32[10, 14, 6]

    explicit = LW.prepare(
        workplan,
        storage;
        workspace = (leases = Any[nothing],),
    )
    @test LW.inspect(explicit).workspace_ownership == :caller
    @test LW.inspect(explicit).allocation_class == :caller_owned_prebound
    @test_throws LW.LocalWorkValidationError LW.prepare(
        workplan,
        storage;
        workspace = (leases = Any[nothing],),
        lease_capacity = 2,
    )

    missing_error = try
        LW.prepare(workplan, (source = storage.source,))
        nothing
    catch error
        error
    end
    @test missing_error isa LW.LocalWorkValidationError
    @test missing_error.stage == :prepare
    @test missing_error.contract == :storage_binding_names
    @test missing_error.expected == (:source, :middle)
    @test missing_error.actual == (:source,)
    @test missing_error.hint isa String

    dynamic_source = Int32[8, 9, 10]
    dynamic_output = fill(Int32(-3), 4)
    dynamic = LW.prepare(
        workplan,
        (;);
        submission = (
            source = LW.storage_slot(dynamic_source; access = :read),
            middle = LW.storage_slot(dynamic_output; access = :write),
        ),
    )
    wait(LW.run!(dynamic, (;
        source = dynamic_source,
        middle = dynamic_output,
    )))
    @test dynamic_output == Int32[9, 10, 11, -3]
    @test isempty(LW.inspect(dynamic).static_bindings)
end

@testset "LW-4C2 automatic nested workspaces preserve buffered semantics" begin
    outputs = (
        edge = LW.independent(:edge_route; value_type = Int32),
        force = LW.combined(
            :force_route;
            value_type = Int32,
            maximum = 2,
            combine = LW.deterministic(+, Int32(0)),
        ),
        fracture = LW.resolved(
            :fracture_route;
            value_type = UInt32,
            maximum = 1,
            empty = UInt32(0),
            rank = (
                type = Int32,
                order = :max,
                lower = Int32(-10),
                upper = Int32(10),
            ),
            tie_break = (type = UInt32, order = :min),
        ),
    )
    work = LW.localwork(
        _HeterogeneousOperation(),
        1:3;
        read = (source = :source,),
        outputs,
    )
    topology = LW.topology(
        work;
        epoch = UInt64(6),
        routes = (
            edge_route = reshape(Int32[3, 1, 2], 1, 3),
            force_route = Int32[1 1 2; 2 2 1],
            fracture_route = reshape(Int32[1, 1, 2], 1, 3),
        ),
        destination_counts = (edge = 3, force = 2, fracture = 3),
        semantic_ids = (
            fracture = reshape(UInt32[30, 20, 10], 1, 3),
        ),
    )
    storage = (
        source = Int32[1, 5, 3],
        edge = fill(Int32(-1), 3),
        force = fill(Int32(-1), 2),
        fracture = fill(UInt32(99), 3),
    )
    workplan = LW.plan(work, topology; backend = KA.CPU())
    prepared = LW.prepare(workplan, storage; lease_capacity = 2)
    @test keys(prepared.workspace.records) == (:force, :fracture)
    @test size(prepared.workspace.records.force.values) == (6,)
    @test size(prepared.workspace.records.fracture.ranks) == (3,)
    @test LW.inspect(workplan).workspace.total_bytes == 57
    facts = LW.inspect(prepared)
    @test facts.algorithmic_workspace_bytes == 57
    @test keys(facts.workspace_facts) == (
        :force_record_values,
        :force_record_valid,
        :fracture_record_ranks,
        :fracture_record_values,
        :fracture_record_valid,
    )
    @test all(
        fact -> fact.backend == KA.CPU,
        values(facts.workspace_facts),
    )
    wait(LW.run!(prepared))
    @test storage.edge == Int32[105, 103, 101]
    @test storage.force == Int32[3, -3]
    @test storage.fracture == UInt32[10, 30, 0]
end

@testset "LW-4C2 automatic workspace covers retained specialized profiles" begin
    legacy = _zbuffer_fixture()
    legacy_output = copy(legacy.storage.framebuffer_color)
    legacy_prepared = LW.prepare(
        legacy.workplan,
        legacy.storage;
        submission = legacy.submission,
        lease_capacity = 2,
    )
    legacy_facts = LW.inspect(legacy_prepared)
    @test legacy_facts.workspace_ownership == :package
    @test legacy_facts.submitted == 0
    @test legacy_facts.wait_count == 0
    @test legacy.storage.framebuffer_color == legacy_output
    @test length(legacy_prepared.workspace.winner_ranks) == 4
    @test length(legacy_prepared.workspace.winner_identities) == 4
    wait(LW.run!(legacy_prepared, (; fragment_count = Int32(5))))
    @test legacy.storage.framebuffer_color == UInt32[0x22, 0x33, 0x55, 0]

    conjunctive = _conjunctive_fixture()
    conjunctive_prepared = LW.prepare(
        conjunctive.workplan,
        conjunctive.storage;
        submission = conjunctive.submission,
    )
    @test LW.inspect(conjunctive_prepared).workspace_ownership == :package
    @test length(conjunctive_prepared.workspace.winner_ranks) == 4
    wait(LW.run!(
        conjunctive_prepared, (; active_count = Int32(6))
    ))
    @test conjunctive.storage.dispositions == UInt8[2, 2, 2, 5, 5, 4]

    @test_throws LW.LocalWorkValidationError LW.prepare(
        legacy.workplan,
        legacy.storage;
        submission = legacy.submission,
        lease_capacity = 0,
    )

    source_root = dirname(pathof(LW))
    allocation_source = read(joinpath(
        source_root, "execution", "workspace_support.jl"
    ), String)
    @test occursin("KernelAbstractions.allocate", allocation_source)
    @test !occursin("zeros(", allocation_source)
    @test !occursin("Adapt.adapt", allocation_source)
    for name in ("planning.jl", "execution.jl", "inspection.jl")
        @test !occursin(
            "KernelAbstractions.allocate",
            read(joinpath(source_root, name), String),
        )
    end
end

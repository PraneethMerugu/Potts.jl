struct _PermutationOperation end

function (::_PermutationOperation)(item::Int32, reads, values)
    return (streamed = LW.emit(@inbounds(reads.source[item]) + Int32(10)),)
end

struct _CombinedIntegerOperation end

function (::_CombinedIntegerOperation)(item::Int32, reads, values)
    value = @inbounds reads.source[item]
    return (
        canonical = (LW.emit(value), LW.emit(value * Int32(10), item != 2)),
        relaxed = (LW.emit(value), LW.emit(value * Int32(10), item != 2)),
    )
end

struct _CombinedFloatOperation end

function (::_CombinedFloatOperation)(item::Int32, reads, values)
    value = @inbounds reads.source[item]
    return (force = (LW.emit(value), LW.emit(value / Float32(3))),)
end

struct _HeterogeneousOperation end

const _HETEROGENEOUS_INVOCATIONS = Threads.Atomic{Int}(0)

struct _CountedHeterogeneousOperation end

function (::_CountedHeterogeneousOperation)(item::Int32, reads, values)
    Threads.atomic_add!(_HETEROGENEOUS_INVOCATIONS, 1)
    value = @inbounds reads.source[item]
    return (
        edge = LW.emit(value),
        force = (LW.emit(value), LW.emit(-value)),
        fracture = LW.candidate(value, UInt32(item)),
    )
end

function (::_HeterogeneousOperation)(item::Int32, reads, values)
    value = @inbounds reads.source[item]
    return (
        edge = LW.emit(value + Int32(100)),
        force = (LW.emit(value), LW.emit(-value)),
        fracture = LW.candidate(
            value, UInt32(item * 10), item != Int32(2)
        ),
    )
end

struct _WrongHeterogeneousArity end
function (::_WrongHeterogeneousArity)(item::Int32, reads, values)
    value = @inbounds reads.source[item]
    return (
        edge = LW.emit(value),
        force = LW.emit(value),
        fracture = LW.candidate(value, UInt32(item)),
    )
end

struct _WrongHeterogeneousResolvedForm end
function (::_WrongHeterogeneousResolvedForm)(item::Int32, reads, values)
    value = @inbounds reads.source[item]
    return (
        edge = LW.emit(value),
        force = (LW.emit(value), LW.emit(-value)),
        fracture = LW.emit(UInt32(item)),
    )
end

struct _WrongHeterogeneousResolvedTypes end
function (::_WrongHeterogeneousResolvedTypes)(item::Int32, reads, values)
    value = @inbounds reads.source[item]
    return (
        edge = LW.emit(value),
        force = (LW.emit(value), LW.emit(-value)),
        fracture = LW.candidate(Float32(value), Int32(item)),
    )
end

struct _WrongHeterogeneousCoverage end
function (::_WrongHeterogeneousCoverage)(item::Int32, reads, values)
    value = @inbounds reads.source[item]
    return (
        edge = LW.emit(value, true),
        force = (LW.emit(value), LW.emit(-value)),
        fracture = LW.candidate(value, UInt32(item)),
    )
end


@testset "LW-4B heterogeneous independent combined resolved work" begin
    backend = KA.CPU()
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
    topology = (
        epoch = UInt64(6),
        item_count = 3,
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
    workplan = LW.plan(work, topology; backend)
    storage = (
        source = Int32[1, 5, 3],
        edge = fill(Int32(-1), 3),
        force = fill(Int32(-1), 2),
        fracture = fill(UInt32(99), 3),
    )
    workspace = (
        records = (
            force = (
                values = Vector{Int32}(undef, 6),
                valid = Vector{Bool}(undef, 6),
            ),
            fracture = (
                ranks = Vector{Int32}(undef, 3),
                values = Vector{UInt32}(undef, 3),
                valid = Vector{Bool}(undef, 3),
            ),
        ),
        leases = Any[nothing, nothing],
    )
    prepared = LW.prepare(workplan, storage; workspace)
    event = LW.run!(prepared)
    wait(event)
    @test storage.edge == Int32[105, 103, 101]
    @test storage.force == Int32[3, -3]
    @test storage.fracture == UInt32[10, 30, 0]
    @test LW.inspect(workplan).launches == 2
    @test LW.inspect(workplan).capability.ports.edge.family == :independent
    @test LW.inspect(workplan).capability.ports.force.family == :combined
    @test LW.inspect(workplan).capability.ports.fracture.family == :resolved
    @test LW.inspect(workplan).capability.ports.fracture.mode == :resolved
    @test LW.inspect(workplan).ports.edge.route == :edge_route
    @test LW.inspect(workplan).ports.edge.coverage == :all
    @test LW.inspect(workplan).ports.edge.law.kind == :independent
    @test LW.inspect(workplan).ports.edge.empty_destination ==
        :not_possible_by_total_coverage
    @test LW.inspect(workplan).ports.force.route == :force_route
    @test LW.inspect(workplan).ports.force.law.mode == :deterministic
    @test LW.inspect(workplan).ports.force.law.identity == Int32(0)
    @test LW.inspect(workplan).ports.fracture.route == :fracture_route
    @test LW.inspect(workplan).ports.fracture.law.rank.order == :max
    @test LW.inspect(workplan).ports.fracture.law.tie_break.order == :min
    @test LW.inspect(workplan).ports.fracture.law.empty == UInt32(0)
    for port in values(LW.inspect(workplan).ports)
        @test keys(port.determinism) == LW._DETERMINISM_DIMENSIONS
    end
    @test LW.inspect(prepared).lowering_detail.operation_invocations ==
        :once_per_active_item

    duplicate_ids = merge(topology, (
        semantic_ids = (
            fracture = reshape(UInt32[20, 20, 10], 1, 3),
        ),
    ))
    @test_throws LW.LocalWorkValidationError LW.plan(
        work, duplicate_ids; backend
    )
    wrong_ids = merge(topology, (
        semantic_ids = (
            fracture = reshape(Int32[30, 20, 10], 1, 3),
        ),
    ))
    @test_throws LW.LocalWorkValidationError LW.plan(
        work, wrong_ids; backend
    )

    for (operation, rejected_port) in (
            (_WrongHeterogeneousArity(), :force),
            (_WrongHeterogeneousResolvedForm(), :fracture),
            (_WrongHeterogeneousResolvedTypes(), :fracture),
            (_WrongHeterogeneousCoverage(), :edge),
        )
        invalid_work = LW.localwork(
            operation,
            1:3;
            read = (source = :source,),
            outputs,
        )
        invalid_plan = LW.plan(invalid_work, topology; backend)
        error = try
            LW.prepare(invalid_plan, storage; workspace)
            nothing
        catch exception
            exception
        end
        @test error isa LW.LocalWorkValidationError
        @test occursin(
            "output port :$(rejected_port)", sprint(showerror, error)
        )
    end
end

@testset "LW-4B heterogeneous operation executes once per CPU item" begin
    backend = KA.CPU()
    item_count = 4
    work = LW.localwork(
        _CountedHeterogeneousOperation(),
        1:item_count;
        read = (source = :source,),
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
                    order = :min,
                    lower = Int32(-10),
                    upper = Int32(10),
                ),
                tie_break = (type = UInt32, order = :min),
            ),
        ),
    )
    topology = (
        epoch = UInt64(9),
        item_count,
        routes = (
            edge_route = reshape(Int32[1, 2, 3, 4], 1, item_count),
            force_route = Int32[1 1 2 2; 2 2 1 1],
            fracture_route = reshape(Int32[1, 1, 2, 2], 1, item_count),
        ),
        destination_counts = (edge = 4, force = 2, fracture = 2),
        semantic_ids = (
            fracture = reshape(UInt32[4, 3, 2, 1], 1, item_count),
        ),
    )
    storage = (
        source = Int32[1, 2, 3, 4],
        edge = zeros(Int32, 4),
        force = zeros(Int32, 2),
        fracture = zeros(UInt32, 2),
    )
    workspace = (
        records = (
            force = (
                values = Vector{Int32}(undef, 2 * item_count),
                valid = Vector{Bool}(undef, 2 * item_count),
            ),
            fracture = (
                ranks = Vector{Int32}(undef, item_count),
                values = Vector{UInt32}(undef, item_count),
                valid = Vector{Bool}(undef, item_count),
            ),
        ),
        leases = Any[nothing],
    )
    prepared = LW.prepare(
        LW.plan(work, topology; backend), storage; workspace
    )
    _HETEROGENEOUS_INVOCATIONS[] = 0
    wait(LW.run!(prepared))
    @test _HETEROGENEOUS_INVOCATIONS[] == item_count
    @test storage.edge == storage.source
    @test storage.force == Int32[-4, 4]
    @test storage.fracture == UInt32[1, 3]
end

@testset "LW-4B deterministic and fast combined laws" begin
    backend = KA.CPU()
    route = Int32[1 1 2; 2 2 0]
    outputs = (
        canonical = LW.combined(
            :canonical_route;
            value_type = Int32,
            maximum = 2,
            combine = LW.deterministic(+, Int32(0)),
        ),
        relaxed = LW.combined(
            :relaxed_route;
            value_type = Int32,
            maximum = 2,
            combine = LW.fast(+, Int32(0)),
        ),
    )
    work = LW.localwork(
        _CombinedIntegerOperation(),
        1:3;
        read = (source = :source,),
        outputs,
    )
    topology = (
        epoch = UInt64(4),
        item_count = 3,
        routes = (canonical_route = route, relaxed_route = copy(route)),
        destination_counts = (canonical = 3, relaxed = 3),
    )
    workplan = LW.plan(work, topology; backend)
    storage = (
        source = Int32[1, 2, 3],
        canonical = fill(Int32(-1), 3),
        relaxed = fill(Int32(-1), 3),
    )
    workspace = (
        records = (
            canonical = (
                values = Vector{Int32}(undef, 6),
                valid = Vector{Bool}(undef, 6),
            ),
        ),
        leases = Any[nothing, nothing],
    )
    prepared = LW.prepare(workplan, storage; workspace)
    event = LW.run!(prepared)
    wait(event)
    @test storage.canonical == Int32[3, 13, 0]
    @test storage.relaxed == Int32[3, 13, 0]
    @test LW.inspect(workplan).launches == 3
    @test LW.inspect(workplan).phases == (
        :initialize_fast, :apply, :publish_canonical
    )
    @test LW.inspect(workplan).ports.canonical.publication_phase ==
        :publish_canonical
    @test LW.inspect(workplan).ports.relaxed.publication_phase == :apply
    @test LW.inspect(workplan).workspace.total_bytes == 6 * 5
    @test LW.inspect(workplan).capability.ports.canonical.mode ==
        :deterministic
    @test LW.inspect(workplan).capability.ports.relaxed.mode == :fast
    @test LW.inspect(workplan).ports.canonical.route == :canonical_route
    @test LW.inspect(workplan).ports.canonical.coverage == :not_applicable
    @test LW.inspect(workplan).ports.canonical.law.operation === +
    @test LW.inspect(workplan).ports.canonical.determinism.
        same_run_replay.guarantee == :canonical_item_local_slot
    @test LW.inspect(workplan).ports.relaxed.determinism.
        same_run_replay.guarantee == :not_claimed
    @test LW.inspect(prepared).lowering_detail.phases == (
        :initialize_fast, :apply, :publish_canonical
    )
    @test LW.inspect(prepared).wait_count == 1

    too_short = (
        records = (
            canonical = (
                values = Vector{Int32}(undef, 5),
                valid = Vector{Bool}(undef, 6),
            ),
        ),
        leases = Any[nothing],
    )
    @test_throws LW.LocalWorkValidationError LW.prepare(
        workplan, storage; workspace = too_short
    )

    float_work = LW.localwork(
        _CombinedFloatOperation(),
        1:4;
        read = (source = :source,),
        outputs = (
            force = LW.combined(
                :route;
                value_type = Float32,
                maximum = 2,
                combine = LW.deterministic(+, Float32(0)),
            ),
        ),
    )
    float_route = Int32[1 1 1 1; 1 1 1 1]
    float_topology = (
        epoch = UInt64(5),
        item_count = 4,
        routes = (route = float_route,),
        destination_counts = (force = 2,),
    )
    float_plan = LW.plan(float_work, float_topology; backend)
    float_source = Float32[1.0, 1f-6, -1.0, 3.0]
    float_storage = (source = float_source, force = fill(Float32(-1), 2))
    float_workspace = (
        records = (
            force = (
                values = Vector{Float32}(undef, 8),
                valid = Vector{Bool}(undef, 8),
            ),
        ),
        leases = Any[nothing],
    )
    float_prepared = LW.prepare(
        float_plan, float_storage; workspace = float_workspace
    )
    float_event = LW.run!(float_prepared)
    wait(float_event)
    reference = Float32(0)
    for item in eachindex(float_source)
        reference += float_source[item]
        reference += float_source[item] / Float32(3)
    end
    @test reinterpret(UInt32, float_storage.force[1]) ==
        reinterpret(UInt32, reference)
    @test float_storage.force[2] === Float32(0)
    @test LW.inspect(float_plan).determinism.bucket_order_invariance.guarantee ==
        :canonical_item_local_slot

    bad_law = LW.localwork(
        _CombinedFloatOperation(),
        1:4;
        read = (source = :source,),
        outputs = (
            force = LW.combined(
                :route;
                value_type = Float32,
                maximum = 2,
                combine = LW.deterministic(*, Float32(1)),
            ),
        ),
    )
    @test_throws LW.LocalWorkValidationError LW.plan(
        bad_law, float_topology; backend
    )
end

struct _PartialOperation end

function (::_PartialOperation)(item::Int32, reads, values)
    return (
        first = LW.emit(@inbounds(reads.source[item]), isodd(item)),
        second = (
            LW.emit(@inbounds(reads.source[item]) + Int32(100)),
            LW.emit(@inbounds(reads.source[item]) + Int32(200), item != 2),
        ),
    )
end

struct _ConditionalFullOperation end
(::_ConditionalFullOperation)(item::Int32, reads, values) =
    (output = LW.emit(@inbounds(reads.source[item]), true),)

struct _WrongValueOperation end
(::_WrongValueOperation)(item::Int32, reads, values) =
    (output = LW.emit(Float32(@inbounds(reads.source[item]))),)

@testset "LW-4B direct independent lowering" begin
    backend = KA.CPU()
    route = reshape(Int32[4, 2, 1, 3], 1, 4)
    work = LW.localwork(
        _PermutationOperation(),
        1:4;
        read = (source = :source,),
        outputs = (
            streamed = LW.independent(
                :stream_route; value_type = Int32
            ),
        ),
    )
    topology = (
        epoch = UInt64(1),
        item_count = 4,
        routes = (stream_route = route,),
        destination_counts = (streamed = 4,),
    )
    workplan = LW.plan(work, topology; backend)
    storage = (
        source = Int32[1, 2, 3, 4],
        streamed = fill(Int32(-1), 4),
    )
    prepared = LW.prepare(
        workplan,
        storage;
        workspace = (leases = Any[nothing, nothing],),
    )
    event = LW.run!(prepared)
    @test storage.streamed == fill(Int32(-1), 4) ||
        storage.streamed == Int32[13, 12, 14, 11]
    wait(event)
    @test storage.streamed == Int32[13, 12, 14, 11]
    @test LW.inspect(workplan).family == :direct
    @test LW.inspect(workplan).launches == 1
    @test LW.inspect(workplan).phases == (:apply_publish,)
    @test LW.inspect(workplan).ports.streamed.publication_phase ==
        :apply_publish
    @test LW.inspect(workplan).ports.streamed.post_launch_failure_visibility ==
        :may_be_partially_visible
    @test LW.inspect(workplan).ports.streamed.route == :stream_route
    @test LW.inspect(workplan).ports.streamed.coverage == :all
    @test LW.inspect(workplan).ports.streamed.law == (
        kind = :independent, coverage = :all
    )
    @test LW.inspect(workplan).ports.streamed.empty_destination ==
        :not_possible_by_total_coverage
    @test LW.inspect(workplan).ports.streamed.determinism.
        same_run_replay.guarantee == :qualified_disjoint_publication
    @test LW.inspect(workplan).workspace.algorithmic_bytes == 0
    @test LW.inspect(workplan).topology_transfer_bytes == sizeof(route)
    @test LW.inspect(prepared).lowering_detail.phases == (:apply_publish,)
    @test LW.inspect(prepared).wait_count == 1

    duplicate = merge(topology, (
        routes = (stream_route = reshape(Int32[1, 1, 3, 4], 1, 4),),
    ))
    @test_throws LW.LocalWorkValidationError LW.plan(
        work, duplicate; backend
    )
    missing = merge(topology, (
        routes = (stream_route = reshape(Int32[1, 2, 3, 0], 1, 4),),
    ))
    @test_throws LW.LocalWorkValidationError LW.plan(
        work, missing; backend
    )
    out_of_range = merge(topology, (
        routes = (stream_route = reshape(Int32[1, 2, 3, 5], 1, 4),),
    ))
    @test_throws LW.LocalWorkValidationError LW.plan(
        work, out_of_range; backend
    )
    zero_lane = LW.localwork(
        _CombinedIntegerOperation(),
        1:1;
        read = (source = :source,),
        outputs = (
            canonical = LW.independent(
                :route; value_type = Int32, maximum = 2
            ),
        ),
    )
    zero_lane_topology = (
        epoch = UInt64(21),
        item_count = 1,
        routes = (route = reshape(Int32[1, 0], 2, 1),),
        destination_counts = (canonical = 1,),
    )
    zero_error = try
        LW.plan(zero_lane, zero_lane_topology; backend)
        nothing
    catch exception
        exception
    end
    @test zero_error isa LW.LocalWorkValidationError
    @test zero_error.stage == :plan
    @test zero_error.contract == :independent_output_coverage
    @test zero_error.port == :canonical
    @test zero_error.expected == :strictly_positive_exact_permutation
    @test zero_error.actual == :contains_zero
    @test occursin("destination zero", sprint(showerror, zero_error))

    all_zero_topology = merge(zero_lane_topology, (
        routes = (route = reshape(Int32[0, 0], 2, 1),),
        destination_counts = (canonical = 0,),
    ))
    @test_throws LW.LocalWorkValidationError LW.plan(
        zero_lane, all_zero_topology; backend
    )

    full_conditional = LW.localwork(
        _ConditionalFullOperation(),
        1:4;
        read = (source = :source,),
        outputs = (
            output = LW.independent(:route; value_type = Int32),
        ),
    )
    full_topology = (
        epoch = UInt64(2),
        item_count = 4,
        routes = (route = reshape(Int32[1, 2, 3, 4], 1, 4),),
        destination_counts = (output = 4,),
    )
    full_plan = LW.plan(full_conditional, full_topology; backend)
    coverage_error = try
        LW.prepare(
            full_plan,
            (source = Int32[1, 2, 3, 4], output = zeros(Int32, 4));
            workspace = (leases = Any[nothing],),
        )
        nothing
    catch exception
        exception
    end
    @test coverage_error isa LW.LocalWorkValidationError
    @test coverage_error.stage == :prepare
    @test coverage_error.contract == :independent_output_coverage
    @test coverage_error.port == :output
    @test coverage_error.expected == :unconditional_emission

    wrong_value = LW.localwork(
        _WrongValueOperation(),
        1:4;
        read = (source = :source,),
        outputs = (
            output = LW.independent(:route; value_type = Int32),
        ),
    )
    wrong_plan = LW.plan(wrong_value, full_topology; backend)
    value_error = try
        LW.prepare(
            wrong_plan,
            (source = Int32[1, 2, 3, 4], output = zeros(Int32, 4));
            workspace = (leases = Any[nothing],),
        )
        nothing
    catch exception
        exception
    end
    @test value_error isa LW.LocalWorkValidationError
    @test value_error.stage == :prepare
    @test value_error.contract == :operation_result_value_type
    @test value_error.port == :output
    @test value_error.expected === Int32
    @test value_error.actual === Float32

    unsupported = LW.localwork(
        _WrongValueOperation(),
        1:4;
        read = (source = :source,),
        outputs = (
            output = LW.independent(:route; value_type = Float64),
        ),
    )
    capability_error = try
        LW.plan(unsupported, full_topology; backend)
        nothing
    catch exception
        exception
    end
    @test capability_error isa LW.LocalWorkValidationError
    @test capability_error.stage == :plan
    @test capability_error.contract == :backend_capability
    @test capability_error.port == :output
    @test capability_error.expected == :centrally_qualified_store
    @test capability_error.actual.value_type === Float64
end

struct _DynamicReadOperation end

function (::_DynamicReadOperation)(item::Int32, reads, values)
    return (output = LW.emit(@inbounds(reads.source[item]) + Int32(1)),)
end

struct _LateDirectOperation end

function (::_LateDirectOperation)(item::Int32, reads, values)
    return (output = LW.emit(@inbounds(reads.source[item])),)
end

struct _LateBufferedOperation end

function (::_LateBufferedOperation)(item::Int32, reads, values)
    return (output = LW.emit(@inbounds(reads.source[item])),)
end

mutable struct _MutableCombinedWorkspace
    records
    leases::Vector{Any}
end

struct _ExternalCombinationLaw{M, F, T} <: LW._AbstractCombinationLaw
    operation::F
    identity::T
end

struct _HugeRoute <: AbstractMatrix{Int32}
    dimensions::Tuple{Int, Int}
end

Base.size(route::_HugeRoute) = route.dimensions
Base.getindex(::_HugeRoute, ::Int, ::Int) =
    error("a rejected huge route must not be indexed")

@testset "LW-4B preparation integrity and checked bounds" begin
    backend = KA.CPU()
    route = reshape(Int32[1, 2], 1, 2)
    topology = (
        epoch = UInt64(12),
        item_count = 2,
        routes = (route = route,),
        destination_counts = (output = 2,),
    )

    dynamic_work = LW.localwork(
        _DynamicReadOperation(),
        1:2;
        read = (source = :source,),
        outputs = (
            output = LW.independent(:route; value_type = Int32),
        ),
    )
    dynamic_plan = LW.plan(dynamic_work, topology; backend)
    first_source = Int32[4, 5]
    dynamic_storage = (output = fill(Int32(-1), 2),)
    dynamic_prepared = LW.prepare(
        dynamic_plan,
        dynamic_storage;
        workspace = (leases = Any[nothing, nothing],),
        submission = (
            source = LW.storage_slot(first_source; access = :read),
        ),
    )
    @test_throws ErrorException setproperty!(
        dynamic_prepared,
        :storage,
        (output = fill(Int32(-2), 2),),
    )
    @test_throws ErrorException setproperty!(
        dynamic_prepared,
        :workspace,
        (leases = Any[nothing, nothing],),
    )
    first_event = LW.run!(dynamic_prepared, (source = first_source,))
    wait(first_event)
    @test dynamic_storage.output == Int32[5, 6]
    second_source = Int32[8, 9]
    second_event = LW.run!(dynamic_prepared, (source = second_source,))
    wait(second_event)
    @test dynamic_storage.output == Int32[9, 10]
    @test_throws LW.LocalWorkValidationError LW.run!(
        dynamic_prepared, (source = @view(second_source[:]),)
    )
    @test !LW.inspect(dynamic_prepared).poisoned

    late_work = LW.localwork(
        _LateDirectOperation(),
        1:2;
        read = (source = :source,),
        outputs = (
            output = LW.independent(:route; value_type = Int32),
        ),
    )
    late_storage = (source = Int32[7, 8], output = fill(Int32(-1), 2))
    late_prepared = LW.prepare(
        LW.plan(late_work, topology; backend),
        late_storage;
        workspace = (leases = Any[nothing],),
    )
    @eval function (::_LateDirectOperation)(
            item::Int32,
            reads::NamedTuple{(:source,), Tuple{Vector{Int32}}},
            values::NamedTuple{(), Tuple{}},
        )
        return (output = LW.emit(Int32(99)),)
    end
    @test_throws LW.LocalWorkValidationError LW.run!(late_prepared)
    @test late_storage.output == fill(Int32(-1), 2)
    @test LW.inspect(late_prepared).submitted == 0
    @test !LW.inspect(late_prepared).poisoned
    @test all(isnothing, late_prepared.leases)

    combined_work = LW.localwork(
        _DynamicReadOperation(),
        1:2;
        read = (source = :source,),
        outputs = (
            output = LW.combined(
                :route;
                value_type = Int32,
                combine = LW.deterministic(+, Int32(0)),
            ),
        ),
    )
    combined_topology = merge(topology, (
        routes = (route = reshape(Int32[1, 1], 1, 2),),
        destination_counts = (output = 1,),
    ))
    late_buffered_work = LW.localwork(
        _LateBufferedOperation(),
        1:2;
        read = (source = :source,),
        outputs = (
            output = LW.combined(
                :route;
                value_type = Int32,
                combine = LW.deterministic(+, Int32(0)),
            ),
        ),
    )
    late_buffered_storage = (
        source = Int32[2, 3], output = fill(Int32(-1), 1)
    )
    late_buffered_workspace = (
        records = (
            output = (
                values = zeros(Int32, 2),
                valid = fill(false, 2),
            ),
        ),
        leases = Any[nothing],
    )
    late_buffered_prepared = LW.prepare(
        LW.plan(late_buffered_work, combined_topology; backend),
        late_buffered_storage;
        workspace = late_buffered_workspace,
    )
    @eval function (::_LateBufferedOperation)(
            item::Int32,
            reads::NamedTuple{(:source,), Tuple{Vector{Int32}}},
            values::NamedTuple{(), Tuple{}},
        )
        return (output = LW.emit(Int32(101)),)
    end
    @test_throws LW.LocalWorkValidationError LW.run!(
        late_buffered_prepared
    )
    @test late_buffered_storage.output == fill(Int32(-1), 1)
    @test LW.inspect(late_buffered_prepared).submitted == 0
    @test !LW.inspect(late_buffered_prepared).poisoned
    @test all(isnothing, late_buffered_prepared.leases)

    mutable_workspace = _MutableCombinedWorkspace(
        (
            output = (
                values = zeros(Int32, 2),
                valid = fill(false, 2),
            ),
        ),
        Any[nothing],
    )
    @test_throws LW.LocalWorkValidationError LW.prepare(
        LW.plan(combined_work, combined_topology; backend),
        (source = Int32[2, 3], output = zeros(Int32, 1));
        workspace = mutable_workspace,
    )

    evil = _ExternalCombinationLaw{:evil, typeof(+), Int32}(+, Int32(0))
    @test_throws ArgumentError LW.combined(
        :route; value_type = Int32, combine = evil
    )
    @test_throws ArgumentError LW.resolved(
        Symbol("");
        value_type = UInt32,
        maximum = 1,
        empty = UInt32(0),
        rank = (
            type = Int32,
            order = :min,
            lower = typemin(Int32),
            upper = typemax(Int32),
        ),
        tie_break = (type = UInt32, order = :min),
    )
    @test_throws LW.LocalWorkValidationError LW.plan(
        dynamic_work, merge(topology, (epoch = Int64(12),)); backend
    )

    huge_items = Int(typemax(Int32)) + 1
    huge_topology = (
        epoch = UInt64(13),
        item_count = huge_items,
        routes = (route = _HugeRoute((1, huge_items)),),
        destination_counts = (output = 1,),
    )
    huge_work = LW.localwork(
        _DynamicReadOperation(),
        1:huge_items;
        read = (source = :source,),
        outputs = (
            output = LW.independent(
                :route; value_type = Int32, coverage = :partial
            ),
        ),
    )
    @test_throws LW.LocalWorkValidationError LW.plan(
        huge_work, huge_topology; backend
    )

    max_items = Int(typemax(Int32))
    oversized_combined = LW.localwork(
        _DynamicReadOperation(),
        1:max_items;
        read = (source = :source,),
        outputs = (
            output = LW.combined(
                :route;
                value_type = Int32,
                maximum = 2,
                combine = LW.deterministic(+, Int32(0)),
            ),
        ),
    )
    oversized_topology = (
        epoch = UInt64(14),
        item_count = max_items,
        routes = (route = _HugeRoute((2, max_items)),),
        destination_counts = (output = 1,),
    )
    @test_throws LW.LocalWorkValidationError LW.plan(
        oversized_combined, oversized_topology; backend
    )
end

@testset "LW-4B partial and bounded multi-emission independent ports" begin
    backend = KA.CPU()
    work = LW.localwork(
        _PartialOperation(),
        1:3;
        read = (source = :source,),
        outputs = (
            first = LW.independent(
                :first_route;
                value_type = Int32,
                coverage = :partial,
            ),
            second = LW.independent(
                :second_route;
                value_type = Int32,
                maximum = 2,
                coverage = :partial,
            ),
        ),
        active = :active_count,
    )
    topology = (
        epoch = UInt64(3),
        item_count = 3,
        routes = (
            first_route = reshape(Int32[1, 2, 0], 1, 3),
            second_route = Int32[1 3 5; 2 4 0],
        ),
        destination_counts = (first = 3, second = 5),
    )
    workplan = LW.plan(work, topology; backend)
    storage = (
        source = Int32[7, 8, 9],
        first = fill(Int32(-1), 3),
        second = fill(Int32(-2), 5),
    )
    prepared = LW.prepare(
        workplan,
        storage;
        workspace = (leases = Any[nothing, nothing],),
        submission = (
            active_count = LW.value_slot(
                Int32; bounds = Int32(0):Int32(3)
            ),
        ),
    )
    event = LW.run!(prepared, (active_count = Int32(2),))
    wait(event)
    @test storage.first == Int32[7, -1, -1]
    @test storage.second == Int32[107, 207, 108, -2, -2]
    @test LW.inspect(workplan).capability.ports.first.maximum_emissions == 1
    @test LW.inspect(workplan).capability.ports.second.maximum_emissions == 2
    @test LW.inspect(workplan).ports.first.empty_destination ==
        :preserve_existing
    @test LW.inspect(workplan).ports.second.empty_destination ==
        :preserve_existing

    topology.routes.first_route[1, 1] = Int32(3)
    @test_throws LW.LocalWorkValidationError LW.prepare(
        workplan,
        storage;
        workspace = (leases = Any[nothing],),
        submission = (
            active_count = LW.value_slot(
                Int32; bounds = Int32(0):Int32(3)
            ),
        ),
    )
end

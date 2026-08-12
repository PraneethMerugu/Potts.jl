import KernelAbstractions
import LocalWorksets
using KernelAbstractions: @index, @kernel
using Random
using Statistics

const _LW4B_PERF_BATCH = 16
const _LW4B_PERF_SAMPLES = parse(
    Int, get(ENV, "LW4_PERF_SAMPLES", "1000")
)
_LW4B_PERF_SAMPLES in (1_000, 2_000) || error(
    "LW4_PERF_SAMPLES must select the reviewed 1000 or 2000 profile"
)
const _LW4B_BOOTSTRAP_SAMPLES = 10_000

# Benchmark-only direct receipt scope. It gives the handwritten oracle the
# same bounded lease, cumulative receipt and one-final-wait shape as
# LocalWorksets without importing LocalWorksets machinery into the oracle.
mutable struct _LW4BDirectScope{B}
    backend::B
    leases::Vector{Any}
    submitted::UInt64
    drained::UInt64
    waits::Int
end

struct _LW4BDirectEvent{S}
    scope::S
    serial::UInt64
end

function _lw4b_direct_submit!(launch!::F, scope::_LW4BDirectScope) where {F}
    outstanding = scope.submitted - scope.drained
    outstanding < UInt64(length(scope.leases)) ||
        error("direct benchmark receipt capacity exhausted")
    serial = scope.submitted + UInt64(1)
    index = Int(mod(serial - UInt64(1), UInt64(length(scope.leases)))) + 1
    scope.leases[index] = launch!
    launch!()
    scope.submitted = serial
    return _LW4BDirectEvent(scope, serial)
end

function Base.wait(event::_LW4BDirectEvent)
    scope = event.scope
    event.serial <= scope.submitted || error("invalid direct receipt")
    event.serial <= scope.drained && return event
    KernelAbstractions.synchronize(scope.backend)
    scope.waits += 1
    completed = scope.submitted
    for serial in (scope.drained + UInt64(1)):completed
        index = Int(mod(
            serial - UInt64(1), UInt64(length(scope.leases))
        )) + 1
        scope.leases[index] = nothing
    end
    scope.drained = completed
    return event
end

_lw4b_sample(sample) = (
    time = sample.time,
    allocated_bytes = sample.bytes,
    allocation_count = Base.gc_alloc_count(sample.gcstats),
)

@kernel function _lw4b_direct_d2q9_kernel!(
        operation, source, output, routes, item_count::Int32
    )
    item = @index(Global, Linear)
    if item <= item_count
        result = operation(
            Int32(item), (populations = source,), (;)
        ).populations
        for lane in 1:9
            destination = Int(@inbounds routes[lane, item])
            @inbounds output[destination] = result[lane].value
        end
    end
end

@kernel function _lw4b_direct_zbuffer_apply!(
        operation,
        depths,
        colors,
        covered,
        record_ranks,
        record_values,
        record_valid,
        lower,
        upper,
        item_count::Int32,
    )
    item = @index(Global, Linear)
    if item <= item_count
        candidate = operation(Int32(item), (
            color = colors,
            covered = covered,
            depth = depths,
        ), (;)).color
        lower <= candidate.rank <= upper ||
            error("resolved rank is outside its declared total domain")
        @inbounds begin
            record_ranks[item] = candidate.rank
            record_values[item] = candidate.value
            record_valid[item] = candidate.when
        end
    end
end

@kernel function _lw4b_direct_zbuffer_publish!(
        output,
        offsets,
        records,
        semantic_ids,
        record_ranks,
        record_values,
        record_valid,
        upper,
        empty,
        destination_count::Int32,
    )
    destination = @index(Global, Linear)
    if destination <= destination_count
        found = false
        winner_rank = upper
        winner_identity = typemax(UInt32)
        winner_value = empty
        first_index = Int(@inbounds offsets[destination])
        last_index = Int(@inbounds offsets[destination + 1]) - 1
        for segment_index in first_index:last_index
            record = Int(@inbounds records[segment_index])
            if @inbounds record_valid[record]
                rank = @inbounds record_ranks[record]
                identity = @inbounds semantic_ids[record]
                if !found || rank < winner_rank ||
                        rank == winner_rank && identity < winner_identity
                    found = true
                    winner_rank = rank
                    winner_identity = identity
                    winner_value = @inbounds record_values[record]
                end
            end
        end
        @inbounds output[destination] = winner_value
    end
end

function _lw4b_d2q9_perf_fixture(array_type, backend; side::Int)
    item_count = side * side
    routes = _lw_d2q9_routes(side, side)
    equilibrium = ntuple(lane -> Float32(lane) / 20f0, 9)
    operation = _LWD2Q9Collision(equilibrium, 0.75f0)
    work = LocalWorksets.localwork(
        operation,
        1:item_count;
        read = (populations = :source,),
        outputs = (
            populations = LocalWorksets.independent(
                :stream; value_type = Float32, maximum = 9
            ),
        ),
    )
    topology = LocalWorksets.topology(
        work;
        epoch = UInt64(1),
        routes = (stream = routes,),
        destination_counts = (populations = 9 * item_count,),
    )
    plan = LocalWorksets.plan(work, topology; backend)
    count = 9 * item_count
    source = array_type(Float32[
        Float32(index % 17) / 7f0 for index in 1:count
    ])
    candidate_output = array_type(fill(Float32(0), count))
    direct_output = array_type(fill(Float32(0), count))
    prepared = LocalWorksets.prepare(
        plan,
        (source = source, populations = candidate_output);
        workspace = (
            leases = Any[nothing for _ in 1:(2 * _LW4B_PERF_BATCH)],
        ),
    )
    routes = array_type(topology.routes.stream)
    direct_kernel = _lw4b_direct_d2q9_kernel!(backend)
    direct_scope = _LW4BDirectScope(
        backend,
        Any[nothing for _ in 1:(2 * _LW4B_PERF_BATCH)],
        UInt64(0),
        UInt64(0),
        0,
    )
    return (;
        backend,
        operation,
        source,
        candidate_output,
        direct_output,
        prepared,
        routes,
        direct_kernel,
        direct_scope,
        item_count,
    )
end

function _lw4b_candidate_batch!(fixture)
    event = nothing
    sample = @timed begin
        for _ in 1:_LW4B_PERF_BATCH
            event = LocalWorksets.run!(fixture.prepared)
        end
        wait(event)
    end
    return _lw4b_sample(sample)
end

function _lw4b_direct_batch!(fixture)
    sample = @timed begin
        event = nothing
        for _ in 1:_LW4B_PERF_BATCH
            event = _lw4b_direct_submit!(fixture.direct_scope) do
                fixture.direct_kernel(
                    fixture.operation,
                    fixture.source,
                    fixture.direct_output,
                    fixture.routes,
                    Int32(fixture.item_count);
                    ndrange = fixture.item_count,
                )
            end
        end
        wait(event)
    end
    return _lw4b_sample(sample)
end

function _lw4b_bootstrap_upper(direct, candidate)
    length(direct) == length(candidate) || error("unpaired samples")
    rng = Xoshiro(UInt64(0x6c77346270657266))
    indices = Vector{Int}(undef, length(direct))
    ratios = Vector{Float64}(undef, _LW4B_BOOTSTRAP_SAMPLES)
    for sample in eachindex(ratios)
        rand!(rng, indices, eachindex(direct))
        ratios[sample] = median(@view candidate[indices]) /
            median(@view direct[indices])
    end
    return quantile(ratios, 0.95)
end

function run_lw4b_d2q9_performance(
        array_type = Array;
        backend = KernelAbstractions.CPU(),
        side::Int = backend isa KernelAbstractions.CPU ? 512 : 256,
    )
    fixture = _lw4b_d2q9_perf_fixture(array_type, backend; side)
    for _ in 1:5
        _lw4b_direct_batch!(fixture)
        _lw4b_candidate_batch!(fixture)
    end
    direct = Vector{Float64}(undef, _LW4B_PERF_SAMPLES)
    candidate = similar(direct)
    direct_bytes = Vector{Int}(undef, _LW4B_PERF_SAMPLES)
    candidate_bytes = similar(direct_bytes)
    direct_counts = similar(direct_bytes)
    candidate_counts = similar(direct_bytes)
    order = rand(
        Xoshiro(UInt64(0x6c7734626f726465)),
        Bool,
        _LW4B_PERF_SAMPLES,
    )
    for index in eachindex(direct)
        if order[index]
            candidate_sample = _lw4b_candidate_batch!(fixture)
            direct_sample = _lw4b_direct_batch!(fixture)
        else
            direct_sample = _lw4b_direct_batch!(fixture)
            candidate_sample = _lw4b_candidate_batch!(fixture)
        end
        direct[index] = direct_sample.time
        direct_bytes[index] = direct_sample.allocated_bytes
        direct_counts[index] = direct_sample.allocation_count
        candidate[index] = candidate_sample.time
        candidate_bytes[index] = candidate_sample.allocated_bytes
        candidate_counts[index] = candidate_sample.allocation_count
    end
    Array(fixture.candidate_output) == Array(fixture.direct_output) ||
        error("D2Q9 direct/candidate performance results differ")
    ratio = median(candidate) / median(direct)
    upper95 = _lw4b_bootstrap_upper(direct, candidate)
    prepared_facts = LocalWorksets.inspect(fixture.prepared)
    return (
        witness = :d2q9_direct,
        side,
        batch = _LW4B_PERF_BATCH,
        samples = _LW4B_PERF_SAMPLES,
        sample_order_candidate_first = order,
        direct_seconds = direct,
        candidate_seconds = candidate,
        direct_allocated_byte_samples = direct_bytes,
        candidate_allocated_byte_samples = candidate_bytes,
        direct_allocation_count_samples = direct_counts,
        candidate_allocation_count_samples = candidate_counts,
        direct_median = median(direct),
        candidate_median = median(candidate),
        ratio,
        upper95,
        threshold = 1.05,
        passed = upper95 <= 1.05,
        direct_allocated_bytes = Int(median(direct_bytes)),
        candidate_allocated_bytes = Int(median(candidate_bytes)),
        direct_allocation_count = Int(median(direct_counts)),
        candidate_allocation_count = Int(median(candidate_counts)),
        direct_launches_per_submission = 1,
        candidate_launches_per_submission = prepared_facts.launches,
        direct_waits = fixture.direct_scope.waits,
        candidate_waits = prepared_facts.wait_count,
        direct_submitted = fixture.direct_scope.submitted,
        direct_drained = fixture.direct_scope.drained,
        candidate_submitted = prepared_facts.submitted,
        candidate_drained = prepared_facts.drained,
        candidate_topology_transfer_bytes =
            prepared_facts.topology_transfer_bytes,
        candidate_workspace_bytes = prepared_facts.algorithmic_workspace_bytes,
        candidate_workspace_ownership = prepared_facts.workspace_ownership,
        candidate_workspace_identities = Tuple(
            name => getproperty(prepared_facts.workspace_facts, name).identity
            for name in keys(prepared_facts.workspace_facts)
        ),
        candidate_lease_identity = prepared_facts.lease_identity,
    )
end

function _lw4b_zbuffer_perf_fixture(
        array_type, backend; destination_count::Int
    )
    item_count = 4 * destination_count
    route = reshape(
        repeat(Int32.(1:destination_count); inner = 4), 1, item_count
    )
    identities = reshape(
        repeat(UInt32[4, 3, 2, 1], destination_count), 1, item_count
    )
    topology = (
        epoch = UInt64(8),
        item_count,
        routes = (pixel = route,),
        destination_counts = (color = destination_count,),
        semantic_ids = (color = identities,),
    )
    operation = _LWZBufferOperation()
    work = LocalWorksets.localwork(
        operation,
        1:item_count;
        read = (
            color = :colors,
            covered = :covered,
            depth = :depths,
        ),
        outputs = (
            color = LocalWorksets.resolved(
                :pixel;
                value_type = UInt32,
                maximum = 1,
                empty = UInt32(0),
                rank = (
                    type = Int32,
                    order = :min,
                    lower = Int32(-1_000_000),
                    upper = Int32(1_000_000),
                ),
                tie_break = (type = UInt32, order = :min),
            ),
        ),
    )
    plan = LocalWorksets.plan(work, topology; backend)
    depths_host = Int32[
        Int32(mod(index * 17, 257) - 128) for index in 1:item_count
    ]
    colors_host = UInt32.(1:item_count)
    covered_host = [mod(index, 11) != 0 for index in 1:item_count]
    depths = array_type(depths_host)
    colors = array_type(colors_host)
    covered = array_type(covered_host)
    candidate_output = array_type(fill(UInt32(0), destination_count))
    direct_output = array_type(fill(UInt32(0), destination_count))
    candidate_ranks = array_type(fill(Int32(0), item_count))
    candidate_values = array_type(fill(UInt32(0), item_count))
    candidate_valid = array_type(fill(false, item_count))
    workspace = (
        records = (color = (
            ranks = candidate_ranks,
            values = candidate_values,
            valid = candidate_valid,
        ),),
        leases = Any[nothing for _ in 1:(2 * _LW4B_PERF_BATCH)],
    )
    prepared = LocalWorksets.prepare(
        plan,
        (
            colors = colors,
            covered = covered,
            depths = depths,
            color = candidate_output,
        );
        workspace,
    )
    offsets = Int32[4 * (destination - 1) + 1
                    for destination in 1:(destination_count + 1)]
    records = Int32.(1:item_count)
    direct_scope = _LW4BDirectScope(
        backend,
        Any[nothing for _ in 1:(2 * _LW4B_PERF_BATCH)],
        UInt64(0),
        UInt64(0),
        0,
    )
    return (;
        backend,
        operation,
        depths,
        colors,
        covered,
        candidate_output,
        direct_output,
        prepared,
        offsets = array_type(offsets),
        records = array_type(records),
        semantic_ids = array_type(vec(identities)),
        direct_ranks = array_type(fill(Int32(0), item_count)),
        direct_values = array_type(fill(UInt32(0), item_count)),
        direct_valid = array_type(fill(false, item_count)),
        apply_kernel = _lw4b_direct_zbuffer_apply!(backend),
        publish_kernel = _lw4b_direct_zbuffer_publish!(backend),
        direct_scope,
        item_count,
        destination_count,
    )
end

function _lw4b_zbuffer_candidate_batch!(fixture)
    event = nothing
    sample = @timed begin
        for _ in 1:_LW4B_PERF_BATCH
            event = LocalWorksets.run!(fixture.prepared)
        end
        wait(event)
    end
    return _lw4b_sample(sample)
end

function _lw4b_zbuffer_direct_batch!(fixture)
    sample = @timed begin
        event = nothing
        for _ in 1:_LW4B_PERF_BATCH
            event = _lw4b_direct_submit!(fixture.direct_scope) do
                fixture.apply_kernel(
                    fixture.operation,
                    fixture.depths,
                    fixture.colors,
                    fixture.covered,
                    fixture.direct_ranks,
                    fixture.direct_values,
                    fixture.direct_valid,
                    Int32(-1_000_000),
                    Int32(1_000_000),
                    Int32(fixture.item_count);
                    ndrange = fixture.item_count,
                )
                fixture.publish_kernel(
                    fixture.direct_output,
                    fixture.offsets,
                    fixture.records,
                    fixture.semantic_ids,
                    fixture.direct_ranks,
                    fixture.direct_values,
                    fixture.direct_valid,
                    Int32(1_000_000),
                    UInt32(0),
                    Int32(fixture.destination_count);
                    ndrange = fixture.destination_count,
                )
            end
        end
        wait(event)
    end
    return _lw4b_sample(sample)
end

function run_lw4b_zbuffer_performance(
        array_type = Array;
        backend = KernelAbstractions.CPU(),
        destination_count::Int = backend isa KernelAbstractions.CPU ?
            131_072 : 262_144,
    )
    fixture = _lw4b_zbuffer_perf_fixture(
        array_type, backend; destination_count
    )
    for _ in 1:5
        _lw4b_zbuffer_direct_batch!(fixture)
        _lw4b_zbuffer_candidate_batch!(fixture)
    end
    direct = Vector{Float64}(undef, _LW4B_PERF_SAMPLES)
    candidate = similar(direct)
    direct_bytes = Vector{Int}(undef, _LW4B_PERF_SAMPLES)
    candidate_bytes = similar(direct_bytes)
    direct_counts = similar(direct_bytes)
    candidate_counts = similar(direct_bytes)
    order = rand(
        Xoshiro(UInt64(0x6c7734627a6f7264)),
        Bool,
        _LW4B_PERF_SAMPLES,
    )
    for index in eachindex(direct)
        if order[index]
            candidate_sample = _lw4b_zbuffer_candidate_batch!(fixture)
            direct_sample = _lw4b_zbuffer_direct_batch!(fixture)
        else
            direct_sample = _lw4b_zbuffer_direct_batch!(fixture)
            candidate_sample = _lw4b_zbuffer_candidate_batch!(fixture)
        end
        direct[index] = direct_sample.time
        direct_bytes[index] = direct_sample.allocated_bytes
        direct_counts[index] = direct_sample.allocation_count
        candidate[index] = candidate_sample.time
        candidate_bytes[index] = candidate_sample.allocated_bytes
        candidate_counts[index] = candidate_sample.allocation_count
    end
    Array(fixture.candidate_output) == Array(fixture.direct_output) ||
        error("z-buffer direct/candidate performance results differ")
    ratio = median(candidate) / median(direct)
    upper95 = _lw4b_bootstrap_upper(direct, candidate)
    prepared_facts = LocalWorksets.inspect(fixture.prepared)
    return (
        witness = :zbuffer_buffered,
        destination_count,
        batch = _LW4B_PERF_BATCH,
        samples = _LW4B_PERF_SAMPLES,
        sample_order_candidate_first = order,
        direct_seconds = direct,
        candidate_seconds = candidate,
        direct_allocated_byte_samples = direct_bytes,
        candidate_allocated_byte_samples = candidate_bytes,
        direct_allocation_count_samples = direct_counts,
        candidate_allocation_count_samples = candidate_counts,
        direct_median = median(direct),
        candidate_median = median(candidate),
        ratio,
        upper95,
        threshold = 1.05,
        passed = upper95 <= 1.05,
        direct_allocated_bytes = Int(median(direct_bytes)),
        candidate_allocated_bytes = Int(median(candidate_bytes)),
        direct_allocation_count = Int(median(direct_counts)),
        candidate_allocation_count = Int(median(candidate_counts)),
        direct_launches_per_submission = 2,
        candidate_launches_per_submission = prepared_facts.launches,
        direct_waits = fixture.direct_scope.waits,
        candidate_waits = prepared_facts.wait_count,
        direct_submitted = fixture.direct_scope.submitted,
        direct_drained = fixture.direct_scope.drained,
        candidate_submitted = prepared_facts.submitted,
        candidate_drained = prepared_facts.drained,
        candidate_topology_transfer_bytes =
            prepared_facts.topology_transfer_bytes,
        candidate_workspace_bytes = prepared_facts.algorithmic_workspace_bytes,
        candidate_workspace_ownership = prepared_facts.workspace_ownership,
        candidate_workspace_identities = Tuple(
            name => getproperty(prepared_facts.workspace_facts, name).identity
            for name in keys(prepared_facts.workspace_facts)
        ),
        candidate_lease_identity = prepared_facts.lease_identity,
    )
end

abspath(PROGRAM_FILE) == (@__FILE__) && begin
    include("lbm_d2q9.jl")
    include("zbuffer.jl")
    d2q9 = run_lw4b_d2q9_performance()
    zbuffer = run_lw4b_zbuffer_performance()
    println(d2q9)
    println(zbuffer)
    if haskey(ENV, "LW4_MACHINE_RESULTS")
        import Serialization
        Serialization.serialize(
            ENV["LW4_MACHINE_RESULTS"], (; d2q9, zbuffer)
        )
    end
    d2q9.passed || error("CPU D2Q9 performance gate failed")
    zbuffer.passed || error("CPU z-buffer performance gate failed")
end

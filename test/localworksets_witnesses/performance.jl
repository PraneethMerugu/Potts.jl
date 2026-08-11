import KernelAbstractions
import LocalWorksets
using KernelAbstractions: @index, @kernel
using Random
using Statistics

const _LW4B_PERF_BATCH = 16
const _LW4B_PERF_SAMPLES = 1_000
const _LW4B_BOOTSTRAP_SAMPLES = 10_000

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
    topology = _lw_d2q9_topology(side, side)
    equilibrium = ntuple(lane -> Float32(lane) / 20f0, 9)
    operation = _LWD2Q9Collision(equilibrium, 0.75f0)
    work = LocalWorksets.localwork(
        operation,
        1:topology.item_count;
        read = (populations = :source,),
        outputs = (
            populations = LocalWorksets.independent(
                :stream; value_type = Float32, maximum = 9
            ),
        ),
    )
    plan = LocalWorksets.plan(work, topology; backend)
    count = 9 * topology.item_count
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
    return (;
        backend,
        operation,
        source,
        candidate_output,
        direct_output,
        prepared,
        routes,
        direct_kernel,
        item_count = topology.item_count,
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
    return sample.time, sample.bytes
end

function _lw4b_direct_batch!(fixture)
    sample = @timed begin
        for _ in 1:_LW4B_PERF_BATCH
            fixture.direct_kernel(
                fixture.operation,
                fixture.source,
                fixture.direct_output,
                fixture.routes,
                Int32(fixture.item_count);
                ndrange = fixture.item_count,
            )
        end
        KernelAbstractions.synchronize(fixture.backend)
    end
    return sample.time, sample.bytes
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
    order = rand(
        Xoshiro(UInt64(0x6c7734626f726465)),
        Bool,
        _LW4B_PERF_SAMPLES,
    )
    for index in eachindex(direct)
        if order[index]
            candidate[index], candidate_bytes[index] =
                _lw4b_candidate_batch!(fixture)
            direct[index], direct_bytes[index] =
                _lw4b_direct_batch!(fixture)
        else
            direct[index], direct_bytes[index] =
                _lw4b_direct_batch!(fixture)
            candidate[index], candidate_bytes[index] =
                _lw4b_candidate_batch!(fixture)
        end
    end
    Array(fixture.candidate_output) == Array(fixture.direct_output) ||
        error("D2Q9 direct/candidate performance results differ")
    ratio = median(candidate) / median(direct)
    upper95 = _lw4b_bootstrap_upper(direct, candidate)
    return (
        witness = :d2q9_direct,
        side,
        batch = _LW4B_PERF_BATCH,
        samples = _LW4B_PERF_SAMPLES,
        direct_median = median(direct),
        candidate_median = median(candidate),
        ratio,
        upper95,
        threshold = 1.05,
        passed = upper95 <= 1.05,
        direct_allocations = Int(median(direct_bytes)),
        candidate_allocations = Int(median(candidate_bytes)),
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
    return sample.time, sample.bytes
end

function _lw4b_zbuffer_direct_batch!(fixture)
    sample = @timed begin
        for _ in 1:_LW4B_PERF_BATCH
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
        KernelAbstractions.synchronize(fixture.backend)
    end
    return sample.time, sample.bytes
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
    order = rand(
        Xoshiro(UInt64(0x6c7734627a6f7264)),
        Bool,
        _LW4B_PERF_SAMPLES,
    )
    for index in eachindex(direct)
        if order[index]
            candidate[index], candidate_bytes[index] =
                _lw4b_zbuffer_candidate_batch!(fixture)
            direct[index], direct_bytes[index] =
                _lw4b_zbuffer_direct_batch!(fixture)
        else
            direct[index], direct_bytes[index] =
                _lw4b_zbuffer_direct_batch!(fixture)
            candidate[index], candidate_bytes[index] =
                _lw4b_zbuffer_candidate_batch!(fixture)
        end
    end
    Array(fixture.candidate_output) == Array(fixture.direct_output) ||
        error("z-buffer direct/candidate performance results differ")
    ratio = median(candidate) / median(direct)
    upper95 = _lw4b_bootstrap_upper(direct, candidate)
    return (
        witness = :zbuffer_buffered,
        destination_count,
        batch = _LW4B_PERF_BATCH,
        samples = _LW4B_PERF_SAMPLES,
        direct_median = median(direct),
        candidate_median = median(candidate),
        ratio,
        upper95,
        threshold = 1.05,
        passed = upper95 <= 1.05,
        direct_allocations = Int(median(direct_bytes)),
        candidate_allocations = Int(median(candidate_bytes)),
    )
end

abspath(PROGRAM_FILE) == (@__FILE__) && begin
    include("lbm_d2q9.jl")
    include("zbuffer.jl")
    d2q9 = run_lw4b_d2q9_performance()
    zbuffer = run_lw4b_zbuffer_performance()
    println(d2q9)
    println(zbuffer)
    d2q9.passed || error("CPU D2Q9 performance gate failed")
    zbuffer.passed || error("CPU z-buffer performance gate failed")
end

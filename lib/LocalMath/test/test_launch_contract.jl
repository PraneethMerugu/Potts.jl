using Statistics: median

function _baseline_scan_add!(backend, prefix, parent, extent::Int)
    event = LocalMath._compacted_scan_add_kernel!(
        backend, min(extent, 256), extent
    )(prefix, parent, Int32(extent); ndrange = extent)
    event === nothing || wait(event)
    KernelAbstractions.synchronize(backend)
    return prefix
end

function _bounded_scan_add!(backend, prefix, parent, extent::Int)
    event = LocalMath._launch_1d!(
        LocalMath._compacted_scan_add_kernel!, backend, extent, Val(256),
        prefix, parent, Int32(extent))
    event === nothing || wait(event)
    KernelAbstractions.synchronize(backend)
    return prefix
end

function _warm_allocation_samples!(launch!, backend, prefix, parent, extent)
    launch!(backend, prefix, parent, extent)
    return map(1:7) do _
        GC.gc()
        @allocated launch!(backend, prefix, parent, extent)
    end
end

@testset "bounded physical launch contract" begin
    backend = KernelAbstractions.CPU()
    for extent in (16, 24, 32, 33, 64, 65, 128, 129, 256, 300)
        baseline = fill(Int32(1), extent)
        bounded = copy(baseline)
        parent = fill(Int32(2), max(cld(extent, 256), 1))
        _baseline_scan_add!(backend, baseline, parent, extent)
        _bounded_scan_add!(backend, bounded, parent, extent)
        @test bounded == baseline
    end

    baseline = fill(Int32(1), 24)
    bounded = copy(baseline)
    parent = fill(Int32(0), 1)
    baseline_bytes = _warm_allocation_samples!(
        _baseline_scan_add!, backend, baseline, parent, 24)
    bounded_bytes = _warm_allocation_samples!(
        _bounded_scan_add!, backend, bounded, parent, 24)
    @test median(bounded_bytes) <= median(baseline_bytes)
end

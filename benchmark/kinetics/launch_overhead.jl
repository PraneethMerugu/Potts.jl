#     julia --project=lib/CorePotts/test benchmark/kinetics/launch_overhead.jl   # ROCm, GPU otherwise idle
# Results 2026-11-04 (gfx1151): KA launch 5.8–8 µs, HIP graph replay 1.9–5 µs, raw @roc 2.7–5.7 µs
# (16k–400k work items); cooperative launches hold at most 160 workgroups of 256; sync_grid
# 0.8 µs (30 groups) to 2.1 µs (160 groups).
# P6.0bl: per-launch cost on the PC's GPU. A sequence of `n` small KernelAbstractions launches, run
# directly and replayed as one captured HIP graph; per launch, for several work sizes.
using AMDGPU, KernelAbstractions, Printf
@kernel function touch!(a, k)
    i = @index(Global, Linear)
    @inbounds a[i] = a[i] * 0.5f0 + Float32(k)
end
const backend = ROCBackend()
const kern = touch!(backend)
seqof(a, n, m) = for k in 1:n
    kern(a, k; ndrange = m)
end
function direct(a, n, m)
    seqof(a, n, m); AMDGPU.synchronize()
    t = @elapsed (for _ in 1:20; seqof(a, n, m); end; AMDGPU.synchronize())
    return t / (20n)
end
function graph(a, n, m)
    seqof(a, n, m); AMDGPU.synchronize()
    g = AMDGPU.HIP.capture(() -> seqof(a, n, m))
    ex = AMDGPU.HIP.instantiate(g)
    AMDGPU.HIP.launch(ex); AMDGPU.synchronize()
    t = @elapsed (for _ in 1:20; AMDGPU.HIP.launch(ex); end; AMDGPU.synchronize())
    return t / (20n)
end
for m in (1, 7_500, 250_000, 1_000_000)
    a = AMDGPU.ones(Float32, m)
    n = 480
    @printf("work items %8d: direct %6.2f µs/launch, graph %6.2f µs/launch\n", m, 1e6 * direct(a, n, m), 1e6 * graph(a, n, m))
end

# raw AMDGPU launches (no KernelAbstractions launch path) and the grid-wide barrier of one
# cooperative launch (`sync_grid`), per barrier
function rtouch!(a, k)
    i = (AMDGPU.workgroupIdx().x - 1) * AMDGPU.workgroupDim().x + AMDGPU.workitemIdx().x
    i <= length(a) && (@inbounds a[i] = a[i] * 0.5f0 + Float32(k))
    return nothing
end
function rawlaunch(a, n, m)
    g = 256; b = cld(m, g)
    k = @roc launch = false rtouch!(a, 1)
    run() = for j in 1:n
        k(a, j; groupsize = g, gridsize = b)
    end
    run(); AMDGPU.synchronize()
    t = @elapsed (for _ in 1:20; run(); end; AMDGPU.synchronize())
    return t / (20n)
end
function gsync!(a, nsync)
    i = (AMDGPU.workgroupIdx().x - 1) * AMDGPU.workgroupDim().x + AMDGPU.workitemIdx().x
    for k in 1:nsync
        i <= length(a) && (@inbounds a[i] = a[i] * 0.5f0 + Float32(k))
        AMDGPU.Device.sync_grid()
    end
    return nothing
end
function gridsync(a, nsync, m)
    g = 256; b = cld(m, g)
    k = @roc launch = false gsync!(a, nsync)
    k(a, 1; groupsize = g, gridsize = b, cooperative = true); AMDGPU.synchronize()
    t1 = @elapsed (k(a, 1; groupsize = g, gridsize = b, cooperative = true); AMDGPU.synchronize())
    tn = @elapsed (k(a, nsync; groupsize = g, gridsize = b, cooperative = true); AMDGPU.synchronize())
    return (tn - t1) / (nsync - 1)
end
# the largest cooperative grid (workgroups of 256 resident at once), then the barrier cost
function maxcoop()
    a = AMDGPU.ones(Float32, 256 * 4096)
    k = @roc launch = false gsync!(a, 1)
    lo, hi = 1, 4096
    while lo < hi
        mid = cld(lo + hi, 2)
        ok = try
            k(a, 1; groupsize = 256, gridsize = mid, cooperative = true); AMDGPU.synchronize(); true
        catch
            false
        end
        ok ? (lo = mid) : (hi = mid - 1)
    end
    return lo
end
const NCOOP = maxcoop()
@printf("cooperative launch: at most %d workgroups of 256 (%d work items); %d compute units\n", NCOOP, 256NCOOP,
    AMDGPU.HIP.properties(AMDGPU.device()).multiProcessorCount)
for m in (7_500, 256 * NCOOP)
    a = AMDGPU.ones(Float32, m)
    @printf("work items %8d: raw @roc %6.2f µs/launch, grid barrier %6.2f µs/sync\n", m,
        1e6 * rawlaunch(a, 480, m), 1e6 * gridsync(a, 2000, m))
end

#     julia --project=lib/CorePotts/test benchmark/kinetics/launch_overhead.jl   # ROCm, GPU otherwise idle
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

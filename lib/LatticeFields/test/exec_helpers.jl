# Shared Exec test helpers (exec.jl, exec_device.jl and qa/exec.jl use them).
using LatticeFields: Exec
using KernelAbstractions: KernelAbstractions
using AllocCheck: check_allocs

const KA = KernelAbstractions

# a body per type parameter, so a tuple of launches is heterogeneous
struct AddK{K} end
(::AddK{K})(i, a) where {K} = (@inbounds a[i] += K; nothing)        # i ≤ n ≤ length(a)
struct Tick{K} end
(::Tick)() = nothing
visit!(i, cnt) = (@inbounds cnt[i] += 1; nothing)                    # i ≤ n ≤ length(cnt)
scale!(i, out, k) = (@inbounds out[i] = k * i; nothing)              # i ≤ n ≤ length(out)

# a mock device: not the host executor; `synchronize` is a no-op
struct MockDevice <: KA.Backend end
KA.synchronize(::MockDevice) = nothing

# Negative control for the plan walk: the recursive walk Exec does not use (pass 3: it
# allocates per launch beyond 32 launches)
rwalk(::Tuple{}) = nothing
rwalk(t::Tuple) = (first(t)(); rwalk(Base.tail(t)))

function host_plan(n)
    a = zeros(Int, 64)
    b = zeros(Float32, 64)
    ls = ntuple(
        k -> isodd(k) ? Exec.Launch(KA.CPU(), AddK{k}(), (a,), 64; static = true) :
            Exec.Launch(KA.CPU(), scale!, (b, Float32(k)), 64; static = true),
        n
    )
    return ls, a, b
end

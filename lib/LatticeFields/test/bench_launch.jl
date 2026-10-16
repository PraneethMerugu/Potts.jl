# Host cost of Exec launches (PG-0 `launch_dep(args)`, PG-13 host bytes per launch), not a
# test: a dependent chain of 200 launches per form, then host bytes per warm launch.
#
#   julia --project=lib/LatticeFields/test lib/LatticeFields/test/bench_launch.jl rocm|metal|cpu
#
# Forms: Exec.Launch with a static ndrange, Exec.Launch with a dynamic one, Exec.launch!
# (CorePotts' path: dynamic ndrange, backend workgroup), each over 1, 11 and 21 arrays at one
# site and at 42³; then a plan of 64 heterogeneous static launches, walked by Exec.Plan.
using LatticeFields: Exec
using KernelAbstractions: KernelAbstractions
using Printf: @printf
const KA = KernelAbstractions

const WHICH = isempty(ARGS) ? "cpu" : ARGS[1]
if WHICH == "rocm"
    using AMDGPU: AMDGPU
    const DEV = AMDGPU.ROCBackend()
    dev(x) = AMDGPU.ROCArray(x)
elseif WHICH == "metal"
    using Metal: Metal
    const DEV = Metal.MetalBackend()
    dev(x) = Metal.MtlArray(x)
else
    const DEV = KA.CPU()
    dev(x) = x
end
devsync() = KA.synchronize(DEV)
println("Exec launch cost on $WHICH; KA $(pkgversion(KA)); threads $(Threads.nthreads())")

# a body over K arrays: out[i] = Σ in_k[i] * p_k (the S/P form of v3, as one args tuple)
struct SumK{K} end
function (::SumK{K})(i, S, P) where {K}
    acc = 0.0f0
    for k in 1:K
        acc += @inbounds(S[k + 1][i]) * P[k]        # i ≤ n ≤ length of every array
    end
    @inbounds S[1][i] = acc
    return nothing
end

const NL = 200
function chain(f)
    f(); devsync()
    best = Inf
    for _ in 1:9
        devsync(); t0 = time_ns()
        for _ in 1:NL
            f()
        end
        devsync(); best = min(best, (time_ns() - t0) / NL)
    end
    f(); devsync(); f(); devsync()
    b = @allocated f()
    devsync()
    return best / 1e3, b
end

for (lbl, n) in (("1 site", 1), ("42³", 42^3))
    for K in (0, 10, 20)
        S = ntuple(_ -> dev(rand(Float32, 42^3)), K + 1)
        P = ntuple(k -> Float32(k), K)
        body = SumK{K}()
        ls = Exec.Launch(DEV, body, (S, P), n; static = true)
        ld = Exec.Launch(DEV, body, (S, P), n; static = false)
        for (form, f) in (("Launch static ndrange", ls), ("Launch dynamic ndrange", ld),
                ("Exec.launch! (CorePotts)", () -> Exec.launch!(DEV, body, n, (S, P))))
            us, b = chain(f)
            @printf("LAUNCH %-8s %2d arrays  %-26s dep %7.2f µs  host %6d B\n", lbl, K + 1, form, us, b)
        end
    end
end

# plan walk: 64 heterogeneous static launches (32 bodies × 2)
S = ntuple(_ -> dev(rand(Float32, 1024)), 4)
ls = ntuple(k -> Exec.Launch(DEV, SumK{mod(k, 3)}(), (S, ntuple(j -> Float32(k + j), mod(k, 3))), 1024; static = true), 64)
plan = Exec.Plan(ls)
Exec.compile_all!(DEV, collect(Any, ls))
us, b = chain(plan)
each = sum(l -> chain(l)[2], ls)
@printf("PLAN 64 launches: dep %7.2f µs/launch  host %d B/plan (%d B as 64 single launches)\n", us / 64, b, each)

# Solvers on a GPU (LATTICEFIELDS_GPU = metal | rocm): Float32 solves equal the host form
# bitwise and repeat bitwise; the no-Float64 walk on the device argument types; the Float64
# solver of unanchored weak-reaction groups (user ruling, D-C7b): `:done` at weak reaction where
# the backend has Float64, the documented Float32 fallback (and the refusal) where it has not.

@testsetup module LF_solvers_device
using Test, LatticeFields
# imports an earlier file made in the old single Main
using LatticeFields.Solvers: solve_plan
include("shared/lf_runner.jl")
include("exec_helpers.jl")
include("host_runner.jl")
include("solvers_cases.jl")
include("device_backend.jl")
const KAd = LatticeFields.Schedule.KernelAbstractions
# `DEV` and the GPU package come from device_backend.jl (loaded once by runtests.jl)
devconvert(x) = gpu == "metal" ? Metal.mtlconvert(x) : AMDGPU.rocconvert(x)

"""
The test executor on `DEV`: site launches through one KernelAbstractions kernel, workgroup
launches through `Schedule.workgroups!`.
"""
struct DevExec end
Solvers.alloc(::DevExec, ::Type{T}, n) where {T} = KAd.zeros(DEV, T, max(n, 1))
Solvers.to_host(::DevExec, A) = (KAd.synchronize(DEV); Array(A))
Schedule.supports(::DevExec, ::Type{Float64}) = gpu != "metal"
KAd.@kernel function _sites!(body, S, P, G, n)
    i = KAd.@index(Global, Linear)
    if i <= n
        body(_index(i, G), S, P, G)
    end
end
function Solvers.launch!(::DevExec, l::Solvers.Launch)
    if l.wg == 0
        _sites!(DEV, 256)(l.body, l.S, l.P, l.G, l.n; ndrange = cld(l.n, 256) * 256)
    else
        Schedule.workgroups!(DEV, l.body, l.n, l.wg, l.phases, eltype(l.lds), l.ldslen,
            l.S, l.P, l.G)
    end
    return nothing
end

function dev_solved(case, exec; T = Float32, kw...)
    op, inputs = case
    sv = FieldSolver(exec, op; T, kw...)
    foreach(((k, v),) -> copyto!(field(sv, k), v), inputs)
    k = steady!(sv)
    return k, Array(field(sv, Solvers.solution_key(sv))), scalars(sv), sv
end
include("shared/export_all.jl")
end

@testitem "device Float32 solves equal the host form bitwise, and repeat" setup = [LF_solvers_device] tags = [:latticefields, :solvers, :gpu_only] begin
using .LF_solvers_device: instances
@testset "device Float32 solves equal the host form bitwise, and repeat" begin
    for (name, s, kw) in (("disk128", 0.022, (;)), (
                    "per128", 0.022, (; solver_type = Float32),
                ),
                ("sphere42", 0.022, (;)), ("disk128", 1.9e-3, (; linsolve = Multigrid())),
                ("per256", 5.5e-6, (; solver_type = Float32)),
            )
        h = dev_solved(named_case(name, s), HostExec(); kw...)
        d1 = dev_solved(named_case(name, s), DevExec(); kw...)
        d2 = dev_solved(named_case(name, s), DevExec(); kw...)
        @test d1[4].T == Float32
        @test d1[1] == h[1] && d1[3].status === h[3].status && d1[2] == h[2]
        @test d1[2] == d2[2]
    end
end
end

@testitem "no Float64 in device code: the walk on device argument types" setup = [LF_solvers_device] tags = [:latticefields, :solvers, :gpu_only] begin
using .LF_solvers_device: instances
@testset "no Float64 in device code: the walk on device argument types" begin
        for (c, kw) in (
                ("disk128", (;)), ("disk128", (; linsolve = Multigrid())),
                ("per128", (; solver_type = Float32)), ("sphere42", (;)),
            )
        sv = FieldSolver(DevExec(), named_case(c, 0.022)[1]; T = Float32, kw...)
        bad = String[]
        for sp in (Solvers.rebuild_plan(sv), Solvers.lift_plan(sv), Solvers.solve_plan(sv, 1)),
            seg in [sp.segments; sp.epilogue], l in seg

            S, G = devconvert(l.S), devconvert(l.G)
            f64_type(Tuple{typeof(S), typeof(l.P), typeof(G)}) &&
                push!(bad, "args " * l.key)
            args = l.wg == 0 ? (typeof(_index(1, l.G)),) :
                   (Int32, Int32, Int32, typeof(devconvert(l.lds)))
            append!(bad, f64_sites(Tuple{typeof(l.body), args..., typeof(S), typeof(l.P),
                typeof(G)}))
        end
        @test isempty(bad) || (foreach(println, unique(bad)); false)
    end
end
end

@testitem "unanchored weak-reaction groups: Float64 solver on device (gpu)" setup = [LF_solvers_device] tags = [:latticefields, :solvers, :gpu_only] begin
using .LF_solvers_device: instances
@testset "unanchored weak-reaction groups: Float64 solver on device ($gpu)" begin
    case = named_case("per256", 5.5e-6)
    if gpu == "metal"                      # no Float64: documented Float32 fallback, refusal
        k, _, sc, sv = dev_solved(case, DevExec())
        @test sv.T == Float32 && sc.status === :floor
            @test_throws ["ArgumentError", "Float64", "solver_type", "not supported", "use Float32"] FieldSolver(DevExec(), case[1]; solver_type = Float64)
    else
        k, u, sc, sv = dev_solved(case, DevExec())
        h = dev_solved(case, HostExec())
        @test sv.T == Float64 && sv.state == Float32 && eltype(u) == Float32
        @test sc.status === :done && sc.rnorm <= 1e-6 * sc.bnorm
        @test k == h[1] && maximum(abs, u .- h[2]) <= 2eps(Float32) * maximum(abs, h[2])
    end
end
end

@testitem "Exec as the solver executor on gpu: capability, not policy (P5 C2-1)" setup = [LF_solvers_device] tags = [:latticefields, :solvers, :gpu_only] begin
using .LF_solvers_device: instances
@testset "Exec as the solver executor on $gpu: capability, not policy (P5 C2-1)" begin
    # `Schedule.supports(DEV, Float64)` is the hardware capability (`Exec.supports`), never the
    # Float32 default-float policy: on ROCm `:auto` keeps the periodic Float64 solve
    case = named_case("per256", 5.5e-6)
    k, u, sc, sv = dev_solved(case, DEV)
    if gpu == "metal"
        @test !Schedule.supports(DEV, Float64) && sv.T == Float32 && sc.status === :floor
    else
        @test Schedule.supports(DEV, Float64) && LatticeFields.Exec.default_float(DEV) === Float32
        @test sv.T == Float64 && sv.state == Float32 && eltype(u) == Float32
        @test sc.status === :done && sc.rnorm <= 1e-6 * sc.bnorm
        h = dev_solved(case, DevExec())
        @test k == h[1] && maximum(abs, u .- h[2]) <= 2eps(Float32) * maximum(abs, h[2])
    end
end
end

# No `double` in device kernels' LLVM IR (D-157; extends D-047): the hook-based half. Metal
# has no doubles, so device code never touches Float64 (CLAUDE.md); ROCm has them and would
# run such code silently. The full scan of every kernel the GPU group compiles is
# `test/shared/device_ir_scan.jl` (run at the end of both GPU suites) with its coverage
# check `test/device_coverage.jl`; this file holds what needs GPUCompiler's compile hook:
#
# - negative controls for the scan itself: a kernel that widens to Float64 through a
#   Float64 literal, and one that converts explicitly, are flagged; their Float32 twin is not;
# - the staged lifecycle's compile-only launch (`_CompileOnly`, lifecycle_device.jl) compiles
#   and does not dispatch on ROCm, as that code assumes.
#
# ROCm only (included first from test/gpu.jl when POTTS_GPU=rocm).
module DeviceIR
using Test, Potts, PottsModels
using Potts: CorePotts
import AMDGPU
const GPUCompiler = AMDGPU.GPUCompiler
const KA = CorePotts.KernelAbstractions

# the LLVM type token `double`, not part of a name (`%double`, `@julia_double_1`, `.double`)
const DOUBLE = r"(?<![%@.\w\"])double(?![\w.\"])"

"""`[(kernel, optimized LLVM module)]` of every distinct kernel compiled while `f()` runs.
While a hook is set GPUCompiler recompiles at every launch, so `f` should be short."""
function kernels_ir(f)
    out = Tuple{String, String}[]
    seen = Set{Any}()
    function hook(job)
        key = (job.source, job.config)
        key in seen && return nothing
        push!(seen, key)
        GPUCompiler.compile_hook[] = nothing          # code_llvm compiles again: no re-entry
        try
            push!(out, (string(job.source.specTypes), sprint(io -> GPUCompiler.code_llvm(io, job; dump_module = true))))
        finally
            GPUCompiler.compile_hook[] = hook
        end
        return nothing
    end
    old = GPUCompiler.compile_hook[]
    GPUCompiler.compile_hook[] = hook
    try
        f()
        AMDGPU.synchronize()
    finally
        GPUCompiler.compile_hook[] = old
    end
    return out
end

"""The lines of `ir` that mention `double`."""
doubles(ir) = filter(l -> occursin(DOUBLE, l), split(ir, '\n'))

# --- negative controls ----------------------------------------------------------------
KA.@kernel function devir_f64_literal!(a)
    i = KA.@index(Global, Linear)
    @inbounds a[i] = a[i] * 1.000000001          # Float32 * Float64 literal → Float64
end
KA.@kernel function devir_f64_convert!(a)
    i = KA.@index(Global, Linear)
    @inbounds a[i] = Float32(sqrt(Float64(a[i])))
end
KA.@kernel function devir_f32!(a)
    i = KA.@index(Global, Linear)
    @inbounds a[i] = a[i] * 1.000000001f0
end

@testset "device IR: the scan flags a Float64-touching kernel (negative control)" begin
    backend = AMDGPU.ROCBackend()
    for (k, flagged) in ((devir_f64_literal!, true), (devir_f64_convert!, true), (devir_f32!, false))
        a = AMDGPU.ROCArray(ones(Float32, 8))
        irs = kernels_ir(() -> k(backend)(a; ndrange = 8))
        @test length(irs) == 1                                          # the hook saw the kernel
        @test any(!isempty ∘ doubles ∘ last, irs) == flagged
        @test Array(a)[1] ≈ (k === devir_f64_convert! ? 1.0f0 : 1.000000001f0)  # and it ran
    end
end

# --- the staged lifecycle's compile-only launch (lifecycle_device.jl, `_CompileOnly`) -----
# It relies on the backend compiling a launch over an empty range and then not dispatching
# it (verified for Metal.jl 1.10); on ROCm: the hook sees the kernel, the array is untouched.
@inline devir_write!(i, a) = (@inbounds a[i] = 2.0f0; nothing)      # i ≤ length(a)

@testset "device IR: a compile-only launch compiles and does not dispatch (ROCm)" begin
    backend = AMDGPU.ROCBackend()
    a = AMDGPU.ROCArray(ones(Float32, 4))
    irs = kernels_ir(() -> CorePotts._stage!(CorePotts._CompileOnly(), devir_write!, backend, 4, (a,)))
    @test length(irs) == 1 && occursin("devir_write!", first(only(irs)))
    @test Array(a) == ones(Float32, 4)
    CorePotts._stage!(CorePotts._Enqueue(), devir_write!, backend, 4, (a,))   # control: a launch writes
    AMDGPU.synchronize()
    @test Array(a) == fill(2.0f0, 4)
end

end # module DeviceIR

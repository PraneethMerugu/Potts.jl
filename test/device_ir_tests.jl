# No `double` in device kernels' LLVM IR (D-157; extends D-047): the hook-based half. Metal
# has no doubles, so device code never touches Float64 (CLAUDE.md); ROCm has them and would
# run such code silently. The full scan of every kernel the GPU group compiles is
# `test/shared/device_ir_scan.jl` (run at the end of both GPU suites) with its coverage
# check `test/device_coverage.jl`; this file holds what needs GPUCompiler's compile hook:
#
# - negative controls for the scan itself: a kernel that widens to Float64 through a
#   Float64 literal, and one that converts explicitly, are flagged; their Float32 twin is
#   not;
# - the staged lifecycle's compile-only launch (`_CompileOnly`, lifecycle_device.jl)
#   compiles the kernel the launch then runs, and writes nothing, on ROCm.
#
# ROCm only (included first from test/gpu.jl when POTTS_GPU=rocm).

@testsetup module DeviceIrSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
# module DeviceIR
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testsetup module DeviceIR
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))

using Test, Potts, PottsModels

using Potts: CorePotts

import AMDGPU

const GPUCompiler = AMDGPU.GPUCompiler

const KA = CorePotts.KernelAbstractions

# the LLVM type token `double`, not part of a name (`%double`, `@julia_double_1`, `.double`)
const DOUBLE = r"(?<![%@.\w\"])double(?![\w.\"])"

"""Run `g()` with GPUCompiler's compile hook set to `h`: a `Ref` up to GPUCompiler 1, a
`ScopedValue` from GPUCompiler 2 on."""
function with_compile_hook(g, h)
    if GPUCompiler.compile_hook isa Base.ScopedValues.ScopedValue
        return Base.ScopedValues.with(g, GPUCompiler.compile_hook => h)
    end
    old = GPUCompiler.compile_hook[]
    GPUCompiler.compile_hook[] = h
    try
        return g()
    finally
        GPUCompiler.compile_hook[] = old
    end
end

"""`[(kernel, optimized LLVM module)]` of every distinct kernel compiled while `f()` runs.
While a hook is set GPUCompiler recompiles at every launch, so `f` should be short."""
function kernels_ir(f)
    out = Tuple{String, String}[]
    seen = Set{Any}()
    function hook(job)
        key = (job.source, job.config)
        key in seen && return nothing
        push!(seen, key)
        # code_llvm compiles again: no hook inside it, so no re-entry
        ir = with_compile_hook(nothing) do
            sprint(io -> GPUCompiler.code_llvm(io, job; dump_module = true))
        end
        push!(out, (string(job.source.specTypes), ir))
        return nothing
    end
    with_compile_hook(hook) do
        f()
        AMDGPU.synchronize()
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

# --- the staged lifecycle's compile-only launch (lifecycle_device.jl, `_CompileOnly`) -----
# `Exec.compile!`: a launch of the kernel `Exec.launch!` runs, with `n = 0` (no work item
# passes the guard). On ROCm: the hook sees the kernel, the array is untouched, and the
# launch that follows compiles nothing new (`_kernel_instances` does not grow).
@inline devir_write!(i, a) = (@inbounds a[i] = 2.0f0; nothing)
# i ≤ length(a)
@inline devir_write3!(i, a) = (@inbounds a[i] = 3.0f0; nothing)
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "device IR: the scan flags a Float64-touching kernel (negative control)" setup = [
    DeviceIR,
] tags = [
    :potts, :device_ir, :gpu, :rocm, :device,
] begin
    @testset "device IR: the scan flags a Float64-touching kernel (negative control)" begin
        backend = AMDGPU.ROCBackend()
        for (k, flagged) in (
                (devir_f64_literal!, true), (devir_f64_convert!, true), (
                    devir_f32!, false,
                ),
            )
            a = AMDGPU.ROCArray(ones(Float32, 8))
            irs = kernels_ir(() -> k(backend)(a; ndrange = 8))
            # the hook saw the kernel
            @test length(irs) == 1
            @test any(!isempty ∘ doubles ∘ last, irs) == flagged
            # and it ran
            @test Array(a)[1] ≈ (k === devir_f64_convert! ? 1.0f0 : 1.000000001f0)
        end
    end
end

# i ≤ length(a)
@testitem "device IR: a compile-only launch compiles and does not dispatch (ROCm)" setup = [
    DeviceIR,
] tags = [
    :potts, :device_ir, :gpu, :rocm, :device,
] begin
    @testset "device IR: a compile-only launch compiles and does not dispatch (ROCm)" begin
        backend = AMDGPU.ROCBackend()
        a = AMDGPU.ROCArray(ones(Float32, 4))
        m = CorePotts._CompileOnly()
        CorePotts._stage!(m, devir_write!, backend, 4, (a,))
        @test length(m.jobs) == 1
        irs = kernels_ir(() -> CorePotts._compile!(m, backend))
        @test length(irs) == 1 && occursin("devir_write!", first(only(irs)))
        @test Array(a) == ones(Float32, 4)
        # control: a launch writes
        CorePotts._stage!(CorePotts._Enqueue(), devir_write!, backend, 4, (a,))
        AMDGPU.synchronize()
        @test Array(a) == fill(2.0f0, 4)
        # without the hook (which recompiles at every launch): the compile adds one kernel
        # instance, the launch that follows none
        b = AMDGPU.ROCArray(ones(Float32, 4))
        ninst() = length(AMDGPU.Compiler._kernel_instances)
        m2 = CorePotts._CompileOnly()
        CorePotts._stage!(m2, devir_write3!, backend, 4, (b,))
        n0 = ninst()
        CorePotts._compile!(m2, backend)
        @test ninst() == n0 + 1 && Array(b) == ones(Float32, 4)
        CorePotts._stage!(CorePotts._Enqueue(), devir_write3!, backend, 4, (b,))
        AMDGPU.synchronize()
        @test ninst() == n0 + 1 && Array(b) == fill(3.0f0, 4)
    end
end

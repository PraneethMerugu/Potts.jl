# The full no-`double` scan (D-157; extends D-047), ROCm only. Included at the END of
# `test/gpu.jl` and `lib/CorePotts/test/gpu.jl`, after every device test of that suite has
# run: every kernel AMDGPU compiled and loaded in this process (`compiled_kernels`,
# kernel_listing.jl; compile-only launches included) is rebuilt as a GPUCompiler job with
# the device's default config (what a KA launch uses) and its optimized LLVM module is
# scanned for the LLVM type `double`. Metal refuses such kernels itself; ROCm
# would run them, so this stands in for Metal while Metal verification is deferred.
#
# Negative control in the same route: two Float64-touching kernels and their Float32 twin
# are launched first, so they sit in the same cache; the scan must flag exactly the
# Float64 ones (with test/device_ir.jl's three hook controls, in the Potts suite, alike).
#
# The kernel signatures seen are written to `$POTTS_DEVICE_IR_DIR/<suite>.txt` when that
# variable is set (the `GROUP=GPU` runner sets it); `test/device_coverage.jl` then checks
# that every CorePotts kernel and launch body appears in the union of both suites.
module DeviceIRScan
using Test
import AMDGPU
const GPUCompiler = AMDGPU.GPUCompiler
const KA = Base.loaded_modules[
    Base.PkgId(
        Base.UUID("63c18a36-062a-441e-b654-da1e3ab1ce7c"), "KernelAbstractions"
    ),
]

include(joinpath(@__DIR__, "kernel_listing.jl"))

# the LLVM type token `double`, not part of a name (`%double`, `@julia_double_1`, `.double`)
const DOUBLE = r"(?<![%@.\w\"])double(?![\w.\"])"

"""The lines of `ir` that mention `double`."""
doubles(ir) = filter(l -> occursin(DOUBLE, l), split(ir, '\n'))

KA.@kernel function scan_f64_literal!(a)
    i = KA.@index(Global, Linear)
    @inbounds a[i] = a[i] * 1.000000001          # Float32 * Float64 literal → Float64
end
KA.@kernel function scan_f64_convert!(a)
    i = KA.@index(Global, Linear)
    @inbounds a[i] = Float32(sqrt(Float64(a[i])))
end
KA.@kernel function scan_f32!(a)
    i = KA.@index(Global, Linear)
    @inbounds a[i] = a[i] * 1.000000001f0
end

"""Launch the three control kernels (so that the kernel listing holds them)."""
function run_controls!()
    backend = AMDGPU.ROCBackend()
    for k in (scan_f64_literal!, scan_f64_convert!, scan_f32!)
        k(backend)(AMDGPU.ROCArray(ones(Float32, 8)); ndrange = 8)
    end
    AMDGPU.synchronize()
    return nothing
end

"""`[(signature, lines with double)]` of every kernel in the kernel listing."""
function scan()
    config = AMDGPU.Compiler.compiler_config(AMDGPU.device())
    out = Tuple{String, Vector{SubString{String}}}[]
    for (F, TT) in compiled_kernels(AMDGPU)
        job = GPUCompiler.CompilerJob(GPUCompiler.methodinstance(F, TT), config)
        ir = sprint(io -> GPUCompiler.code_llvm(io, job; dump_module = true))
        push!(out, (string(Tuple{F, TT.parameters...}), doubles(ir)))
    end
    return out
end

# the deliberate controls: this file's and the hook-based ones of test/device_ir_tests.jl
# (Potts)
function iscontrol(sig)
    return occursin("DeviceIRScan.gpu_scan_", sig) ||
        occursin(r"DeviceIR(?:#\d+\")?\.gpu_devir_", sig)
end

# The D-157 carve-out: kernels whose Float64 a user declared (a group's
# `compute_type` or `solver_type`, a field's `lattice_storage` of Float64) are registered in
# LatticeFields' Exec registry, and the scan skips exactly those
function _exec()
    k = findfirst(id -> id.name == "LatticeFields", collect(keys(Base.loaded_modules)))
    return if k === nothing
        nothing
    else
        Base.loaded_modules[collect(keys(Base.loaded_modules))[k]].Exec
    end
end
registered(sig) = (E = _exec(); E !== nothing && E.float64_registered(sig))

"""Run the controls, scan the cache, test; record the signatures for the coverage check."""
function check(suite::AbstractString)
    @testset "device IR: no `double` in any kernel this suite compiled ($suite, full \
        scan)" begin
        run_controls!()
        res = scan()
        ctl = filter(r -> iscontrol(r[1]), res)
        # control: all three cached
        @test count(r -> occursin("DeviceIRScan.gpu_scan_", r[1]), ctl) == 3
        @test count(r -> !isempty(r[2]), ctl) == count(r -> occursin("f64", r[1]), ctl) >= 2
        # flagged ⇔ Float64
        @test all(r -> occursin("f64", r[1]) == !isempty(r[2]), ctl)
        reg = filter(r -> !iscontrol(r[1]) && registered(r[1]), res)
        real = filter(r -> !iscontrol(r[1]) && !registered(r[1]), res)
        @test length(real) > 0
        if !isempty(reg)
            # the carve-out is used (a registered kernel holds `double`), and without the
            # registry those kernels are flagged (negative control: the registry entries
            # removed)
            @test any(r -> !isempty(r[2]), reg)
            E = _exec()
            saved = copy(E.FLOAT64_KERNELS)
            empty!(E.FLOAT64_KERNELS)
            flagged = count(r -> !isempty(r[2]) && !registered(r[1]), reg)
            union!(E.FLOAT64_KERNELS, saved)
            @test flagged > 0
            @info "device IR: declared Float64 kernels skipped ($suite)" kernels = length(
                reg
            ) with_double = count(
                r -> !isempty(r[2]), reg
            )
        end
        for (sig, d) in real
            @test isempty(d)
            isempty(d) ||
                @error "device IR: `double` in a \
                    kernel" kernel = first(sig, 2000) lines = first(d, 8)
        end
        @info "device IR full scan ($suite)" kernels = length(real) with_double = count(
            r -> !isempty(r[2]), real
        )
        dir = get(ENV, "POTTS_DEVICE_IR_DIR", "")
        isempty(dir) || write(joinpath(dir, "$suite.txt"), join((r[1] for r in real), '\n'))
    end
    return nothing
end

end # module DeviceIRScan

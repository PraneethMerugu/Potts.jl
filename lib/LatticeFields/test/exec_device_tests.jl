# Exec on a device (Metal or ROCm): the `if` guard, compile-before-enqueue reuse, static and
# dynamic ndranges (one compile per distinct static ndrange?), parallel compile, plan walk
# overhead. Compiles are counted in the device's kernel listing (`compiled_kernels`): one
# entry per compiled (function, argument types) pair.

# fresh body types per testset, so no earlier compile is reused

@testsetup module LF_exec_device
using Test, LatticeFields
include("shared/preamble.jl")
include("exec_helpers.jl")
include("host_runner.jl")
include("device_backend.jl")
include("shared/exec.jl")
struct Put{K} end
# i ≤ n ≤ length(a)
(::Put{K})(i, a) where {K} = (@inbounds a[i] = Float32(K); nothing)

"""Compiles added while `f()` runs (synchronized)."""
function compiles(f)
    devsync()
    c0 = instances()
    f()
    devsync()
    return instances() - c0
end

# Checked on KA 0.9.43: a static ndrange is part of the kernel type,
# so each distinct ndrange is expected to be its own compile; a dynamic one is not.
const NDRANGE_COMPILES = Dict{Symbol, Vector{Int}}()
include("shared/export_all.jl")
end

@testitem "Exec device (gpu): the guard stops at n" setup = [LF_exec_device] tags = [
    :latticefields, :exec, :gpu_only,
] begin
    using .LF_exec_device: instances
    @testset "Exec device ($gpu): the guard stops at n" begin
        for n in (1, 255, 256, 257, 1000)
            a = devarray(zeros(Float32, n + 300))
            Exec.launch!(DEV, Put{1}(), n, (a,))
            h = Array(a)
            # nothing past n
            @test all(==(1.0f0), h[1:n]) && all(iszero, h[(n + 1):end])
            for static in (true, false)
                b = devarray(zeros(Float32, n + 300))
                Exec.Launch(DEV, Put{2}(), (b,), n; workgroupsize = 64, static)()
                hb = Array(b)
                @test all(==(2.0f0), hb[1:n]) && all(iszero, hb[(n + 1):end])
            end
        end
    end
end

@testitem "Exec device (gpu): compile! compiles the launch's kernel and writes \
    nothing" setup = [LF_exec_device] tags = [
    :latticefields, :exec, :gpu_only,
] begin
    using .LF_exec_device: instances
    @testset "Exec device ($gpu): compile! compiles the launch's kernel and writes \
        nothing" begin
        a = devarray(ones(Float32, 300))
        @test compiles(() -> Exec.compile!(DEV, Put{3}(), (a,))) == 1
        @test Array(a) == ones(Float32, 300)
        @test compiles(() -> Exec.launch!(DEV, Put{3}(), 300, (a,))) == 0      # reused
        @test Array(a) == fill(3.0f0, 300)
        # any n: dynamic ndrange
        @test compiles(() -> Exec.launch!(DEV, Put{3}(), 17, (a,))) == 0
        # negative control: a body never compiled adds one
        @test compiles(() -> Exec.launch!(DEV, Put{4}(), 300, (a,))) == 1
        # Launch: the compile launch is the kernel the launch runs (static: over the full
        # ndrange)
        for static in (true, false)
            b = devarray(ones(Float32, 300))
            l = Exec.Launch(
                DEV, static ? Put{5}() : Put{6}(), (b,), 300; workgroupsize = 64, static
            )
            @test compiles(() -> Exec.compile!(l)) == 1
            @test Array(b) == ones(Float32, 300)
            @test compiles(l) == 0
            @test Array(b) == fill(static ? 5.0f0 : 6.0f0, 300)
        end
    end
end

@testitem "Exec device (gpu): compiles per distinct ndrange" setup = [
    LF_exec_device,
] tags = [
    :latticefields, :exec, :gpu_only,
] begin
    using .LF_exec_device: instances
    @testset "Exec device ($gpu): compiles per distinct ndrange" begin
        a = devarray(zeros(Float32, 4096))
        # static: sizes 256 and 512 and 1024 (multiples of 64: the ndranges differ), then
        # 256 again
        stat = [
            compiles(
                Exec.Launch(
                    DEV, Put{7}(), (a,), n; workgroupsize = 64, static = true
                )
            )
                for n in (256, 512, 1024, 256)
        ]
        dyn = [
            compiles(
                Exec.Launch(
                    DEV, Put{8}(), (a,), n; workgroupsize = 64, static = false
                )
            )
                for n in (256, 512, 1024, 256)
        ]
        NDRANGE_COMPILES[:static] = stat
        NDRANGE_COMPILES[:dynamic] = dyn
        @info "compiles per launch at ndranges 256, 512, 1024, 256 on $gpu \
            (KA $(pkgversion(KA)))" static = stat dynamic = dyn
        @test stat == [1, 1, 1, 0]                 # one compile per distinct static ndrange
        @test dyn == [1, 0, 0, 0]                  # one compile, whatever the ndrange
        # same ndrange from a different n (both round up to 256): no new compile
        @test compiles(
            Exec.Launch(
                DEV, Put{7}(), (a,), 200; workgroupsize = 64, static = true
            )
        ) == 0
    end
end

@testitem "Exec device (gpu): compile_all! compiles a set on host tasks" setup = [
    LF_exec_device,
] tags = [
    :latticefields, :exec, :gpu_only,
] begin
    using .LF_exec_device: instances
    @testset "Exec device ($gpu): compile_all! compiles a set on host tasks" begin
        a = devarray(zeros(Float32, 512))
        ls = (
            Exec.Launch(DEV, Put{11}(), (a,), 512; workgroupsize = 64, static = true),
            Exec.Launch(DEV, Put{12}(), (a,), 512; workgroupsize = 64, static = false),
            Exec.Launch(DEV, Put{13}(), (a,), 100; workgroupsize = 64, static = true),
        )
        jobs = Any[ls..., () -> Exec.compile!(DEV, Put{14}(), (a,))]
        @test compiles(() -> Exec.compile_all!(DEV, jobs)) == 4
        # nothing written
        @test Array(a) == zeros(Float32, 512)
        @test compiles(
            () -> (
                foreach(l -> l(), ls); Exec.launch!(DEV, Put{14}(), 512, (a,))
            )
        ) == 0
        @test Array(a) == fill(14.0f0, 512)
    end
end

@testitem "Exec device (gpu): the plan walk adds no host bytes" setup = [
    LF_exec_device,
] tags = [
    :latticefields, :exec, :gpu_only,
] begin
    using .LF_exec_device: instances
    @testset "Exec device ($gpu): the plan walk adds no host bytes" begin
        a = devarray(zeros(Float32, 1024))
        b = devarray(zeros(Float32, 1024))
        ls = ntuple(
            k -> Exec.Launch(
                DEV, isodd(k) ? Put{k + 100}() : Put{1}(), (isodd(k) ? a : b,), 1024;
                workgroupsize = 64, static = true
            ), 40
        )
        plan = Exec.Plan(ls)
        Exec.compile_all!(DEV, collect(Any, ls))
        plan()
        devsync()
        warm(f) = (f(); devsync(); f(); devsync(); a = @allocated f(); devsync(); a)
        bytes_plan = warm(plan)
        bytes_each = sum(l -> warm(l), ls)
        @info "plan of 40 launches on $gpu: $(bytes_plan) B; the launches one by \
            one: $(bytes_each) B"
        @test bytes_plan <= bytes_each
    end
end

@testitem "Exec device (gpu): the Schedule contract's Cartesian form" setup = [
    LF_exec_device,
] tags = [
    :latticefields, :exec, :gpu_only,
] begin
    using .LF_exec_device: instances
    @testset "Exec device ($gpu): the Schedule contract's Cartesian form" begin
        G = (; n = Int32(70), dims = (Int32(7), Int32(10)), rt = ())
        b = devarray(zeros(Float32, 100))
        c = Exec.Launch(
            DEV, cart_body, ((b,), (3.0f0,), G), (7, 10);
            workgroupsize = (4, 4), static = true
        )
        @test compiles(() -> Exec.compile!(c)) == 1
        # the compile launch writes nothing
        @test all(iszero, Array(b))
        @test compiles(c) == 0
        # padded items wrote nothing
        @test Array(b) == [3.0f0 .* (1:70); zeros(Float32, 30)]
        a = devarray(zeros(Float32, 100))
        l = Exec.Launch(
            DEV, lin_body, ((a,), (2.0f0,), G), (Int(G.n),);
            workgroupsize = (64,), static = true
        )
        l()
        @test Array(a) == [2.0f0 .* (1:70); zeros(Float32, 30)]
    end
end

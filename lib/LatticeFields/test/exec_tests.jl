# Exec on the host: the executor, launches, plans, compile and capabilities. Device
# behavior (the guard, compile reuse, static ndranges) is in exec_device.jl.

@testsetup module LF_exec
using Test, LatticeFields
include("exec_helpers.jl")
include("host_runner.jl")
include("shared/exec.jl")
include("shared/export_all.jl")
end

@testitem "Exec: capabilities" setup = [LF_exec] tags = [:latticefields, :exec] begin
    @testset "Exec: capabilities" begin
        @test Exec.ishost(KA.CPU()) && !Exec.ishost(MockDevice())
        # capability: the host runs every isbits type; a device Float32, Float64 where KA
        # says so; kernels take isbits values only, so no backend runs BigFloat
        @test Exec.supports(KA.CPU(), Float64) && !Exec.supports(KA.CPU(), BigFloat)
        @test Exec.supports(MockDevice(), Float32) && !Exec.supports(MockDevice(), BigFloat)
        @test Exec.supports(MockDevice(), Float64) == KA.supports_float64(MockDevice())
        # policy: Float64 on the host, Float32 on every device whatever the hardware has
        @test Exec.default_float(KA.CPU()) === Float64 &&
            Exec.default_float(MockDevice()) === Float32
    end
end

@testitem "Exec: host executor visits each index once" setup = [LF_exec] tags = [
    :latticefields, :exec,
] begin
    @testset "Exec: host executor visits each index once" begin
        for n in (0, 1, 7, Exec.HOST_GRAIN, Exec.HOST_GRAIN + 1, 3 * Exec.HOST_GRAIN + 5)
            cnt = zeros(Int, n + 3)
            Exec.host_launch!(visit!, n, (cnt,))
            @test cnt[1:n] == ones(Int, n) && all(iszero, cnt[(n + 1):end])
        end
        # the threaded chunked loop, forced (one thread runs it too): every chunk size,
        # ragged ends
        n = 1000
        for chunk in (1, 3, 64, 999, 1000)
            cnt = zeros(Int, n + 1)
            Exec._host_threaded!(visit!, n, chunk, (cnt,))
            @test cnt[1:n] == ones(Int, n) && cnt[end] == 0
        end
        # negative control: an off-by-one range is caught by the same check
        cnt = zeros(Int, n + 1)
        Exec.host_launch!(visit!, n + 1, (cnt,))
        @test !(cnt[1:n] == ones(Int, n) && cnt[end] == 0)
        # launch! on the CPU is the host executor; n ≤ 0 runs nothing
        out = zeros(Int, 10)
        Exec.launch!(KA.CPU(), scale!, 10, (out, 3))
        @test out == 3 .* (1:10)
        Exec.launch!(KA.CPU(), scale!, 0, (out, 5))
        @test out == 3 .* (1:10)
    end
end

@testitem "Exec: the host loop allocates nothing" setup = [LF_exec] tags = [
    :latticefields, :exec,
] begin
    @testset "Exec: the host loop allocates nothing" begin
        a = zeros(Float32, 100)
        @test isempty(
            check_allocs(
                Exec._host_loop!, (
                    AddK{1}, Int, Tuple{Vector{Float32}},
                )
            )
        )
        Exec.host_launch!(AddK{1}(), 100, (a,))
        @test (@allocated Exec.host_launch!(AddK{1}(), 100, (a,))) == 0
        @test (@allocated Exec.launch!(KA.CPU(), AddK{1}(), 100, (a,))) == 0
    end
end

@testitem "Exec: Launch on the host" setup = [LF_exec] tags = [:latticefields, :exec] begin
    @testset "Exec: Launch on the host" begin
        a = zeros(Int, 20)
        l = Exec.Launch(KA.CPU(), AddK{2}(), (a,), 15; static = true)
        @test l isa Exec.Launch{Exec.HostExec, 0}
        l()
        @test a == [fill(2, 15); zeros(Int, 5)]
        # compile writes nothing
        @test Exec.compile!(l) === nothing && a == [fill(2, 15); zeros(Int, 5)]
        l()
        @test (@allocated l()) == 0
        @test_throws ArgumentError Exec.Launch(KA.CPU(), AddK{2}(), (a,), -1; static = true)
        @test_throws ArgumentError Exec.Launch(
            MockDevice(), AddK{2}(), (a,), 4; static = true, workgroupsize = 0
        )
    end
end

# PG-13: the plan walk adds nothing on a plan of more than 32 heterogeneous launches
@testitem "Exec: plan walk, n launches" setup = [LF_exec] tags = [
    :latticefields,
    :exec,
] begin
    @testset "Exec: plan walk, $n launches" for n in (5, 32, 40, 72)
        ls, a, b = host_plan(n)
        @test !(ls isa NTuple)                                          # heterogeneous
        plan = Exec.Plan(ls)
        # one walker per length
        @test length(plan) == n && plan.walk === Exec.walker(n)
        plan()
        @test a == fill(sum(k for k in 1:n if isodd(k)), 64)
        # the last even k wins
        @test b == Float32.(2 * (n ÷ 2) .* (1:64))
        plan()
        @test (@allocated plan()) == 0
        @test Base.return_types(plan, ())[1] === Nothing
        # the walk itself, statically: a plan of plain callables (the host executor's
        # threaded branch is reachable from a Launch and allocates its tasks by design)
        calls = ntuple(k -> Tick{k}(), n)
        @test isempty(check_allocs(Exec.walker(n), (typeof(calls),)))
        # negative control: the recursive walk over the same tuple allocates beyond 32
        # launches
        rwalk(ls)
        if n > 32
            @test (@allocated rwalk(ls)) > 0
        end
    end
end

@testitem "Exec: compile_all! runs every job and rethrows a failure" setup = [
    LF_exec,
] tags = [
    :latticefields, :exec,
] begin
    @testset "Exec: compile_all! runs every job and rethrows a failure" begin
        @test Exec.compile_all!(KA.CPU(), [() -> error("never runs on the host")]) ===
            nothing
        ran = zeros(Int, 16)
        Exec.compile_all!(MockDevice(), [() -> (ran[k] += 1) for k in 1:16])
        @test ran == ones(Int, 16)
        jobs = [() -> nothing, () -> throw(ArgumentError("compile failed")), () -> nothing]
        err = try
            Exec.compile_all!(MockDevice(), jobs)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError && err.msg == "compile failed"
    end
end

@testitem "Exec: walker emits one call per launch" setup = [LF_exec] tags = [
    :latticefields, :exec,
] begin
    @testset "Exec: walker emits one call per launch" begin
        log = Int[]
        calls = ntuple(k -> (() -> push!(log, k)), 40)
        Exec.walker(40)(calls)
        @test log == 1:40
        @test Exec.walker(0)(()) === nothing
        @test_throws ArgumentError Exec.walker(-1)
    end
end

@testitem "Exec: the Schedule contract's linear and Cartesian forms (host)" setup = [
    LF_exec,
] tags = [
    :latticefields, :exec,
] begin
    @testset "Exec: the Schedule contract's linear and Cartesian forms (host)" begin
        a = zeros(Float32, 40)
        G = (; n = 30, dims = (5, 6), rt = ())
        l = Exec.Launch(KA.CPU(), lin_body, ((a,), (2.0f0,), G), (G.n,); static = true)
        @test l isa Exec.LinearLaunch
        l()
        @test a == [2.0f0 .* (1:30); zeros(Float32, 10)]
        b = zeros(Float32, 40)
        c = Exec.Launch(KA.CPU(), cart_body, ((b,), (3.0f0,), G), G.dims; static = true)
        @test c isa Exec.CartesianLaunch
        @test Exec.compile!(c) === nothing && all(iszero, b)
        c()
        @test b == [3.0f0 .* (1:30); zeros(Float32, 10)]
        @test (@allocated c()) == 0
        p = Exec.Plan((l, c))
        p()
        @test (@allocated p()) == 0
        @test_throws ArgumentError Exec.Launch(
            KA.CPU(), cart_body, ((b,), (3.0f0,), G), (5, -1); static = true
        )
    end
end

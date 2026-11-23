# Fusion is taken whenever it is legal, at every problem size; fused execution matches split
# execution; fusion legality; ordering; static ndrange marking.

@testsetup module LF_schedule_fusion
using Test, LatticeFields
# imports an earlier file made in the old single Main
using LatticeFields.IR: IRError
using Random: Xoshiro
using LatticeFields.Solvers: field
include("../host_runner.jl")
include("../shared/compile_multilevel.jl")
include("../shared/schedule_fusion.jl")
include("../shared/export_all.jl")
end

@testitem "fusion is taken whenever legal, at every size" setup = [
    LF_schedule_fusion,
] tags = [
    :latticefields, :schedule,
] begin
    @testset "fusion is taken whenever legal, at every size" begin
        cases = [
            (smoother, (42, 42, 42), 4), (smoother, (256, 256, 256), 5),
            (residual, (42, 42, 42), 4), (residual, (256, 256, 256), 4),
            (restrict, (42, 42, 42), 4), (restrict, (256, 256, 256), 4),
            (prolong, (128, 128, 128), 4), (prolong, (256, 256, 256), 4),
            (independent, (64, 64), 8), (independent, (4096, 4096), 8),
        ]
        for (family, dims, K) in cases
            sp = plan(family(dims, K))
            @test length(sp.launches) == 1
            @test length(sp.decisions) == K - 1
            @test all(d -> d.merged && d.reason == :legal, sp.decisions)
        end
        # the report names every fusion
        r = sprint(fusion_report, plan(independent((4096, 4096), 3)))
        @test count("fuse  ", r) == 2 && !occursin("split", r)
        # control: debug planning splits the same programs
        @test length(plan(smoother((256, 256, 256), 5); fuse = false).launches) == 5
    end
end

@testitem "fused steps match split steps" setup = [LF_schedule_fusion] tags = [
    :latticefields, :schedule,
] begin
    @testset "fused steps match split steps" begin
        for (family, dims, K) in (
                (smoother, (9, 7, 6), 3), (residual, (11, 6), 4),
                (restrict, (8, 6, 4), 3), (prolong, (10, 8), 3),
                (independent, (13, 5), 4),
            )
            s = family(dims, K)
            fused, split = plan(s), plan(s; fuse = false)
            @test length(fused.launches) == 1 && length(split.launches) == K
            a, b = step_fields(s, fused), step_fields(s, split)
            @test keys(a) == keys(b)
            @test all(k -> isapprox(a[k], b[k]; rtol = 1.0e-6), keys(a))
        end
        # control: a changed parameter changes the fused result
        s = smoother((9, 7, 6), 3)
        a = step_fields(s, plan(s))
        b = step_fields(s, plan(s); P = (0.3, 0.3, 0.7))
        @test !isapprox(a["out1"], b["out1"]; rtol = 1.0e-6)
    end
end

@testitem "fusion legality and order" setup = [LF_schedule_fusion] tags = [
    :latticefields, :schedule,
] begin
    @testset "fusion legality and order" begin
        s = producer_consumer((0, 0, 0))
        sp = plan(s)
        @test length(sp.launches) == 1 &&
            sp.launches[1].members == ["z_produce", "a_consume"]
        s = producer_consumer((1, 0, 0))
        sp = plan(s)
        @test length(sp.launches) == 2 &&
            [l.members[1] for l in sp.launches] == ["z_produce", "a_consume"]
        d = only(sp.decisions)
        @test !d.merged && d.reason == :illegal && occursin("at offset (1, 0, 0)", d.detail)
        @test occursin("split z_produce | a_consume  illegal", sprint(fusion_report, sp))
        # the same pair at offset 0 is legal, so it fuses
        @test plan(producer_consumer((0, 0, 0))).decisions[1].merged
    end
end

@testitem "Jacobi groups: a read cycle reads old values" setup = [
    LF_schedule_fusion,
] tags = [
    :latticefields, :schedule,
] begin
    @testset "Jacobi groups: a read cycle reads old values" begin
        function cycle(buffers)
            pb = ProgramBuilder(Grid((5, 4)); periodic = (true, true))
            x = field!(pb, "x"; buffers)
            y = field!(pb, "y"; buffers)
            k1 = kernel(pb)
            store(k1, x, load(k1, y; offset = (1, 0)) + 1)
            add!(pb, k1, "fx")
            k2 = kernel(pb)
            store(k2, y, load(k2, x; offset = (0, 1)) * 2)
            add!(pb, k2, "fy")
            return semantic(program(pb))
        end
        s = cycle(2)
        @test step_order(s, [1, 2]) == [[1, 2]]
        x0, y0 = rand(Xoshiro(14), Float32, 5, 4), rand(Xoshiro(15), Float32, 5, 4)
        st = HostStore(s)
        copyto!(current(st, s, "x"), x0)
        copyto!(current(st, s, "y"), y0)
        run_step!(s, plan(s), st, ())
        @test reshape(current(st, s, "x"), 5, 4) == circshift(y0, (-1, 0)) .+ 1
        @test reshape(current(st, s, "y"), 5, 4) == circshift(x0, (0, -1)) .* 2
        @test_throws IR.IRError step_order(cycle(1), [1, 2])
    end
end

@testitem "a one-buffer field inside a Jacobi group is read new (its writer first)" setup =
    [LF_schedule_fusion] tags = [
    :latticefields, :schedule,
] begin
    @testset "a one-buffer field inside a Jacobi group is read new (its writer first)" begin
        # x, y two-buffer, K one-buffer: `z_K` (K ← x) sorts last by key, but `fy` reads K's
        # new value, so `z_K` runs before it; x and y keep the Jacobi rule (old values)
        function auxloop(off)
            pb = ProgramBuilder(Grid((5, 4)); periodic = (true, true))
            x = field!(pb, "x"; buffers = 2)
            y = field!(pb, "y"; buffers = 2)
            K = field!(pb, "K"; role = :aux)
            k1 = kernel(pb)
            store(k1, x, load(k1, y) + 1)
            add!(pb, k1, "fx")
            k2 = kernel(pb)
            store(k2, y, load(k2, K; offset = off) * 2)
            add!(pb, k2, "fy")
            k3 = kernel(pb)
            store(k3, K, load(k3, x) - 3)
            add!(pb, k3, "z_K")
            return semantic(program(pb))
        end
        x0, y0 = rand(Xoshiro(21), Float32, 5, 4), rand(Xoshiro(22), Float32, 5, 4)
        for off in ((0, 0), (1, 0))
            s = auxloop(off)
            order = only(step_order(s, [1, 2, 3]))
            # (fx reads no one-buffer field)
            @test [s.kernels[i].key for i in order] == ["fx", "z_K", "fy"]
            for fuse in (true, false)
                st = HostStore(s)
                copyto!(current(st, s, "x"), x0)
                copyto!(current(st, s, "y"), y0)
                sp = plan(s; fuse)
                run_step!(s, sp, st, ())
                @test reshape(current(st, s, "K"), 5, 4) == x0 .- 3
                @test reshape(current(st, s, "y"), 5, 4) == circshift(x0 .- 3, .-off) .* 2
                @test reshape(current(st, s, "x"), 5, 4) == y0 .+ 1
                # an offset read of K is not fused with its writer (it would read other
                # sites' old K)
                fuse && off != (0, 0) &&
                    @test !any(l -> "z_K" in l.members && "fy" in l.members, sp.launches)
            end
        end
        # control: one-buffer fields that define each other are refused, naming only them
        pb = ProgramBuilder(Grid((5, 4)); periodic = (true, true))
        x = field!(pb, "x"; buffers = 2)
        K = field!(pb, "K"; role = :aux)
        L = field!(pb, "L"; role = :aux)
        for (f, g, key) in ((K, L, "aK"), (L, K, "aL"))
            kb = kernel(pb)
            store(kb, f, load(kb, g) + load(kb, x))
            add!(pb, kb, key)
        end
        kb = kernel(pb)
        store(kb, x, load(kb, K) + 1)
        add!(pb, kb, "fx")
        s = semantic(program(pb))
        err = try
            step_order(s, [1, 2, 3])
            ""
        catch e
            e isa IR.IRError || rethrow()
            sprint(showerror, e)
        end
        @test occursin("cycle", err)
    end
end

@testitem "fused execution is bit-exact with split execution" setup = [
    LF_schedule_fusion,
] tags = [
    :latticefields, :schedule,
] begin
    @testset "fused execution is bit-exact with split execution" begin
        s = producer_consumer((0, 0, 0); dims = (7, 5, 3))
        function exec(sp)
            st = HostStore(
                s;
                init = (k, A) -> (A .= rand(Xoshiro(16), eltype(A), length(A)))
            )
            run_step!(s, sp, st, (0.3,))
            return (
                copy(current(st, s, "v")), copy(current(st, s, "w")),
            )
        end
        fused, split = plan(s), plan(s; fuse = false)
        @test length(fused.launches) == 1 && length(split.launches) == 2
        @test exec(fused) == exec(split)
    end
end

@testitem "content addressing and static ndrange" setup = [LF_schedule_fusion] tags = [
    :latticefields, :schedule,
] begin
    @testset "content addressing and static ndrange" begin
        pb = ProgramBuilder(Grid((8, 8)); periodic = (true, true), levels = 2)
        f0, g0 = field!(pb, "a0"; role = :input), field!(pb, "b0"; role = :output)
        f1, g1 = field!(pb, "a1"; role = :input, levels = [1]),
            field!(pb, "b1"; role = :output, levels = [1])
        for (f, g, l) in ((f0, g0, 0), (f1, g1, 1))
            kb = kernel(pb, Space{2}(; level = l))
            store(kb, g, 2 * load(kb, f))
            add!(pb, kb, "double$l")
        end
        sp = plan(semantic(program(pb)))
        @test length(sp.launches) == 2                      # different spaces never fuse
        @test sp.launches[1].kernel.hash == sp.launches[2].kernel.hash
        @test sp.launches[1].ndrange != sp.launches[2].ndrange
        @test !sp.launches[1].static && !sp.launches[2].static
        @test all(l -> l.static, plan(smoother((16, 16, 16), 2)).launches)
    end
end

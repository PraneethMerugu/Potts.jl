# Regressions found in review of the emitter, each against an independent oracle written
# here with `mod1` and `clamp` (not the emitter's index code): periodic wrap with |offset| ≥
# the axis, box stencils on corners and degenerate axes, the ZERO policy, the coarse-level
# convention, and the refusals added by the review.

@testsetup module LF_compile_regressions
using Test, LatticeFields
include("../host_runner.jl")
include("../fixtures.jl")
using LatticeFields.IR: IRError, ZERO, coord, constant
using LatticeFields.Schedule: live_estimate, kernel_arrays, merge_kernels, fusion_blocker,
    MAX_ARRAYS, MAX_LIVE

function regmsg(f)
    return try
        f()
        ""
    catch e
        e isa IRError ? e.msg : rethrow()
    end
end

"""
Run a one-output program under every emission mode; returns the outputs.
"""
function each_mode(pb, inputs, P = (); out = "v")
    map((CompileOptions(), CompileOptions(; index = :linear), debug_options())) do o
        s, sp = build(pb; options = o)
        st = HostStore(s)
        foreach(((k, v),) -> copyto!(current(st, s, k), v), inputs)
        run_step!(s, sp, st, P)
        copy(current(st, s, out))
    end
end

"""
Weighted 3^N box stencil; non-periodic axes have no-flux faces (ghost = center).
"""
function boxnf(dims, per)
    N = length(dims)
    pb = ProgramBuilder(Grid(dims); periodic = per)
    u = field!(pb, "u"; role = :input)
    v = field!(pb, "v"; role = :output)
    for d in 1:N, s in (-1, 1)
        per[d] || rule!(pb, FaceRule(u, d, s, Coef(0), Coef(1), Coef(0)))
    end
    kb = kernel(pb)
    w(o) = 1 + sum(abs, o) + 0.1 * o[1]
    store(
        kb,
        v,
        sum(
            load(kb, u; offset = Tuple(o)) * w(Tuple(o))
                for o in CartesianIndices(ntuple(_ -> -1:1, N))
        )
    )
    add!(pb, kb, "box")
    return pb
end
function boxoracle(u, per)
    N = ndims(u)
    out = zeros(size(u))
    for I in CartesianIndices(u), o in CartesianIndices(ntuple(_ -> -1:1, N))
        # no-flux ghost of a cell-centered face is the nearest inside value, axis by axis
        J = ntuple(
            d -> if per[d]
                mod1(I[d] + o[d], size(u, d))
            else
                clamp(I[d] + o[d], 1, size(u, d))
            end, N
        )
        out[I] += u[J...] * (1 + sum(abs, Tuple(o)) + 0.1 * o[1])
    end
    return out
end
include("../shared/export_all.jl")
end

@testitem "periodic wrap with offsets as large as the axis" setup = [
    LF_compile_regressions,
] tags = [
    :latticefields, :compile,
] begin
    @testset "periodic wrap with offsets as large as the axis" begin
        for off in ((5, 0), (-7, 0), (2, 3), (0, -4))
            pb = ProgramBuilder(Grid((2, 3)); periodic = (true, true))
            u, v = field!(pb, "u"; role = :input), field!(pb, "v"; role = :output)
            kb = kernel(pb)
            store(kb, v, load(kb, u; offset = off))
            add!(pb, kb, "k")
            u0 = reshape(Float32.(1:6), 2, 3)
            want = [u0[mod1(i + off[1], 2), mod1(j + off[2], 3)] for i in 1:2, j in 1:3]
            for got in each_mode(pb, ("u" => u0,))
                @test reshape(got, 2, 3) == want
            end
        end
    end
end

@testitem "box stencils on corners and degenerate axes" setup = [
    LF_compile_regressions,
] tags = [
    :latticefields, :compile,
] begin
    @testset "box stencils on corners and degenerate axes" begin
        for (dims, per) in (
                ((5, 3), (false, false)), ((5, 3, 3), (false, false, false)),
                ((5, 3, 3), (true, false, false)), ((1, 3, 2), (true, false, false)), (
                    (7, 1), (false, true),
                ),
            )
            u0 = rand(Xoshiro(21), Float32, dims...)
            want = boxoracle(Float64.(u0), per)
            for got in each_mode(boxnf(dims, per), ("u" => u0,))
                @test reshape(got, dims) ≈ want rtol = 1.0e-5
            end
        end
    end
end

@testitem "ZERO policy reads 0 outside, on the unclamped coordinate" setup = [
    LF_compile_regressions,
] tags = [
    :latticefields, :compile,
] begin
    @testset "ZERO policy reads 0 outside, on the unclamped coordinate" begin
        pb = ProgramBuilder(Grid((4,)))
        r, o = field!(pb, "r"; role = :input), field!(pb, "v"; role = :output)
        kb = kernel(pb)
        store(
            kb, o,
            load(kb, r; offset = (1,), policy = ZERO) +
                10 * load(kb, r; offset = (-2,), policy = ZERO)
        )
        add!(pb, kb, "k")
        r0 = Float32[1, 2, 3, 4]
        at(i) = 1 <= i <= 4 ? r0[i] : 0.0f0
        want = [at(i + 1) + 10 * at(i - 2) for i in 1:4]
        for got in each_mode(pb, ("r" => r0,))
            @test got == want
        end
    end
end

@testitem "coarse levels: n ÷ 2 sites, last aggregate of an odd axis has width 3" setup = [
    LF_compile_regressions,
] tags = [
    :latticefields, :compile,
] begin
    @testset "coarse levels: n ÷ 2 sites, last aggregate of an odd axis has width 3" begin
        # restriction 5 → 2: aggregates {1,2} and {3,4,5}; the width-3 tail reads offset 2
        # only at the last coarse site (gated on the coarse coordinate)
        pb = ProgramBuilder(Grid((5,)); levels = 2)
        r = field!(pb, "r"; role = :input)
        rc = field!(pb, "v"; role = :output, levels = [1])
        kb = kernel(pb, Space{1}(; level = 1))
        tail = select(
            eq(coord(kb, 1), constant(kb, 2, I32)),
            load(kb, r; level = -1, offset = (2,), policy = ZERO), constant(kb, 0.0)
        )
        # inside by the
        pair = load(kb, r; level = -1, offset = (0,), policy = IR.INSIDE) +
            # n ÷ 2 convention
            load(kb, r; level = -1, offset = (1,), policy = IR.INSIDE)
        store(kb, rc, pair + tail)
        add!(pb, kb, "restrict")
        r0 = Float32[1, 2, 3, 4, 5]
        for got in each_mode(pb, ("r" => r0,))
            @test got == Float32[1 + 2, 3 + 4 + 5]
        end
        # prolongation 5 ← 2: fine x reads coarse min((x − 1) ÷ 2 + 1, 2)
        pb = ProgramBuilder(Grid((5,)); levels = 2)
        e = field!(pb, "e"; role = :input, levels = [1])
        f = field!(pb, "v"; role = :output)
        kb = kernel(pb)
        store(kb, f, load(kb, e; level = 1))
        add!(pb, kb, "prolong")
        for got in each_mode(pb, ("e" => Float32[10, 20],))
            @test got == Float32[10, 10, 20, 20, 20]
        end
        @test IR.leveldims(IR.Level(Grid((42, 5, 1)), 1)) == (21, 2, 1)
    end
end

@testitem "review refusals and hygiene" setup = [LF_compile_regressions] tags = [
    :latticefields, :compile,
] begin
    @testset "review refusals and hygiene" begin
        # :accumulate adds to the current value at the own site
        pb = ProgramBuilder(Grid((4,)); periodic = (true,))
        r, o = field!(pb, "r"; role = :input), field!(pb, "v"; role = :output)
        kb = kernel(pb)
        IR.store(kb, o, load(kb, r); law = :accumulate)
        add!(pb, kb, "acc")
        for got in each_mode(
                pb, (
                    "r" => Float32[1, 2, 3, 4], "v" => Float32[10, 20, 30, 40],
                )
            )
            @test got == Float32[11, 22, 33, 44]
        end
        # α = β = 0 face rule
        pb = ProgramBuilder(Grid((4, 4)); periodic = (true, false))
        u = field!(pb, "u"; buffers = 2)
        foreach(s -> rule!(pb, FaceRule(u, 2, s, Coef(0), Coef(0), Coef(1))), (-1, 1))
        kb = kernel(pb)
        store(kb, u, load(kb, u; offset = (0, 1)))
        add!(pb, kb, "k")
        @test occursin("α = β = 0", regmsg(() -> semantic(program(pb))))
        # explicit level widths are refused (the n ÷ 2 convention is fixed)
        pb = ProgramBuilder(Grid((5,)); levels = 2)
        pb.hierarchy[2] = IR.Level{1}(pb.hierarchy[2].grid, 1, (Int8[2, 3],))
        a = field!(pb, "a"; role = :input)
        b = field!(pb, "b"; role = :output)
        kb = kernel(pb)
        store(kb, b, load(kb, a))
        add!(pb, kb, "k")
        @test occursin("level widths", regmsg(() -> semantic(program(pb))))
        # the body text carries no source paths, so the content hash is location-independent
        s, sp = build(diffusion3())
        @test !occursin(".jl", string(sp.launches[1].kernel.body))
        @test !any(x -> x isa LineNumberNode, (y for y in sp.launches[1].kernel.body.args))
    end
end

@testitem "fusion hard limits: array arguments and the register prefilter" setup = [
    LF_compile_regressions,
] tags = [
    :latticefields, :compile,
] begin
    @testset "fusion hard limits: array arguments and the register prefilter" begin
        src = read(joinpath(@__DIR__, "..", "shared", "schedule_fusion.jl"), String)
        @isdefined(smoother) || include_string(@__MODULE__, split(src, "nlaunch(s) =")[1])
        s = smoother((42, 42, 42), 20)
        sp = plan(s)
        @test length(sp.launches) > 1
        @test any(d -> d.reason == :limit, sp.decisions)
        @test all(
            l -> length(kernel_arrays(s, l.kernel.kernel)) <= MAX_ARRAYS, sp.launches
        )
        @test length(plan(smoother((42, 42, 42), 4)).launches) == 1
        # negative control: every kernel may legally join the others, and the merge of all
        # of them breaks the array limit, so the limit is what splits
        ids = collect(eachindex(s.kernels))
        scc = Dict(i => i for i in ids)
        @test all(i -> fusion_blocker(s, ids[1:(i - 1)], i, scc) === nothing, ids[2:end])
        @test length(kernel_arrays(s, merge_kernels(s, ids, scc))) > MAX_ARRAYS
        @test live_estimate(s.kernels[1]) < MAX_LIVE
    end
end

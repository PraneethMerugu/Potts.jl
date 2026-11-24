# Regressions found in review of the emitter, each against an independent oracle written
# here with `mod1` and `clamp` (not the emitter's index code): periodic wrap with |offset| ≥
# the axis, box stencils on corners and degenerate axes, the ZERO policy, the coarse-level
# convention, and the refusals added by the review.

@testsetup module LF_compile_regressions
using Test, LatticeFields
include("../host_runner.jl")
include("../fixtures.jl")
using LatticeFields.IR: IRError, ZERO, coord, constant
using LatticeFields.Schedule: fusion_blocker
using LatticeFields: Exec
using LatticeFields.Problems: BoundStep
using ForwardDiff: Dual

# a stand-in device with the kernel-argument budget `SMALL_ARGS[]`: it binds host launches,
# whose argument bytes are those of their argument tuple
struct SmallArgs <: KernelAbstractions.Backend end
struct MockArgsless <: KernelAbstractions.Backend end
const SMALL_ARGS = Ref(0)
Exec.ishost(::SmallArgs) = true
Exec.kernel_argument_bytes(::SmallArgs) = SMALL_ARGS[]

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

@testitem "fusion stops at the backend's kernel-argument budget" setup = [
    LF_compile_regressions,
] tags = [
    :latticefields, :compile,
] begin
    @testset "fusion stops at the backend's kernel-argument budget" begin
        src = read(joinpath(@__DIR__, "..", "shared", "schedule_fusion.jl"), String)
        @isdefined(smoother) || include_string(@__MODULE__, split(src, "nlaunch(s) =")[1])
        # 2 smoothers with 3 parameters each
        s = smoother((8, 8, 8), 2)
        ids = collect(eachindex(s.kernels))
        scc = Dict(i => i for i in ids)
        @test fusion_blocker(s, ids[1:1], 2, scc) === nothing
        # the CPU has no budget: one launch
        @test Exec.kernel_argument_bytes(KernelAbstractions.CPU()) === nothing
        sp = plan(s)
        @test length(sp.launches) == 1
        st = HostStore(s)
        P = (0.5, 0.25, 0.75)
        bytes(bs) = [Exec.launch_argument_bytes(x.launch) for x in bs.launches]
        primal = only(bytes(BoundStep(KernelAbstractions.CPU(), s, sp, st, P)))
        # a budget the primal launch fills: the primal binding keeps one launch
        SMALL_ARGS[] = primal
        @test bytes(BoundStep(SmallArgs(), s, sp, st, P)) == [primal]
        # the Dual parameters make the fused launch larger: that binding splits
        bs = BoundStep(SmallArgs(), s, sp, st, P; c = Dual(0.0, 1.0))
        @test length(bs.launches) == 2
        @test all(<=(primal), bytes(bs))
        # the plans at the budget, one per argument types: primal one launch, Dual two
        plans = collect(values(sp.bound))
        @test sort([length(q.launches) for q in plans]) == [1, 2]
        dp = only(filter(q -> length(q.launches) == 2, plans))
        @test count(d -> d.reason == :limit, dp.decisions) == 1
        @test occursin("budget of $primal B", sprint(Schedule.fusion_report, dp))
        # the primal plan is still one launch
        @test length(sp.launches) == 1
        # a backend with no known budget is refused, naming the method to define
        err = try
            Exec.kernel_argument_bytes(MockArgsless())
        catch e
            e
        end
        @test err isa ArgumentError && occursin("kernel_argument_bytes", err.msg)
    end
end

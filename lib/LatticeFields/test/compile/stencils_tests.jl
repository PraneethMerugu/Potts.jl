# Generated FV-style 5- and 7-point stencils through the host runner, against hand loops
# (bit-exact where the operation order is the same), a naive loop and the debug emission.

@testsetup module LF_compile_stencils
using Test, LatticeFields
include("../host_runner.jl")
include("../fixtures.jl")
"""
Does an expression hold a Float64 literal or the symbol `Float64`?
"""
has_f64(x) = x isa Float64 || x === :Float64 || (x isa Expr && any(has_f64, x.args))

"""
2D 9-point / 3D 27-point box stencil (the access pattern of Q1 finite elements), periodic.
"""
function boxprog(dims)
    N = length(dims)
    pb = ProgramBuilder(Grid(dims); periodic = ntuple(_ -> true, N), nparams = 1)
    u = field!(pb, "u")
    v = field!(pb, "v")
    kb = kernel(pb)
    acc = sum(
        load(kb, u; offset = Tuple(o)) * (1 + sum(abs, Tuple(o)))
            for o in CartesianIndices(ntuple(_ -> -1:1, N))
    )
    store(kb, v, param(kb, 1) * acc)
    add!(pb, kb, "box")
    return pb
end
include("../shared/export_all.jl")
end

@testitem "5-point 2D, periodic: bit-exact with the hand loop" setup = [LF_compile_stencils] tags = [:latticefields, :compile] begin
    @testset "5-point 2D, periodic: bit-exact with the hand loop" begin
        rng = Xoshiro(1)
        u0 = rand(rng, Float32, 7, 5)
        P = (0.1, 0.7, 1.3)
        s, sp = build(diffusion2())
        @test length(sp.launches) == 1 && sp.launches[1].kernel.strategy == :linear
        got = run_field(s, sp, u0, P; steps = 3)
        ref = copy(u0)
        tmp = similar(u0)
        for _ in 1:3
            hand2!(tmp, ref, P)
            ref, tmp = tmp, ref
        end
        @test reinterpret(UInt32, got) == reinterpret(UInt32, ref)
        # negative control: one ulp up in one input element is detected
        u1 = copy(u0)
        u1[3, 2] = nextfloat(u1[3, 2])
        @test reinterpret(UInt32, run_field(s, sp, u1, P; steps = 3)) !=
            reinterpret(UInt32, ref)
    end
end

@testitem "7-point 3D, periodic / no flux / Dirichlet: bit-exact with the hand loop" setup = [LF_compile_stencils] tags = [:latticefields, :compile] begin
    @testset "7-point 3D, periodic / no flux / Dirichlet: bit-exact with the hand loop" begin
        rng = Xoshiro(2)
        u0 = rand(rng, Float32, 6, 5, 4)
        P = (0.05, 0.9, 1.1, 0.25, 2.0)
        s, sp = build(diffusion3())
        got = run_field(s, sp, u0, P; steps = 3)
        ref, tmp = copy(u0), similar(u0)
        for _ in 1:3
            hand3!(tmp, ref, P)
            ref, tmp = tmp, ref
        end
        @test reinterpret(UInt32, got) == reinterpret(UInt32, ref)
        # a naive loop in another order and the Float64 debug emission agree to tolerance
        nv = naive3!(zeros(Float64, size(u0)), Float64.(u0), P)
        @test run_field(s, sp, u0, P) ≈ nv rtol = 1.0e-5
        sd, spd = build(diffusion3(); options = debug_options())
        @test !has_f64(sp.launches[1].kernel.body) && has_f64(spd.launches[1].kernel.body)
        @test run_field(sd, spd, u0, P) ≈ nv rtol = 1.0e-7   # Float64 compute, one rounding at the store
        # Int64 site index (above 2³¹ sites) gives the same bits
        s64, sp64 = build(diffusion3(); options = CompileOptions(; I = Int64))
        @test run_field(s64, sp64, u0, P; steps = 3) == got
    end
end

@testitem "Cartesian index strategy for box stencils" setup = [LF_compile_stencils] tags = [:latticefields, :compile] begin
    @testset "Cartesian index strategy for box stencils" begin
        for dims in ((9, 7), (5, 4, 3))
            rng = Xoshiro(3)
            u0 = rand(rng, Float32, dims...)
            s, sp = build(boxprog(dims))
            @test sp.launches[1].kernel.strategy == :cartesian
            @test sp.launches[1].workgroup == (length(dims) == 3 ? (64, 2, 2) : (64, 4))
            sl, spl = build(boxprog(dims); options = CompileOptions(; index = :linear))
            @test spl.launches[1].kernel.strategy == :linear
            function runbox(sx, spx)
                st = HostStore(sx)
                copyto!(current(st, sx, "u"), u0)
                run_step!(sx, spx, st, (0.5,))
                return copy(current(st, sx, "v"))
            end
            @test runbox(s, sp) == runbox(sl, spl)                        # same IR, same order: same bits
            sd, spd = build(boxprog(dims); options = debug_options())
            @test runbox(s, sp) ≈ runbox(sd, spd) rtol = 1.0e-5
        end
    end
end

@testitem "warm host launch allocates nothing" setup = [LF_compile_stencils] tags = [:latticefields, :compile] begin
    @testset "warm host launch allocates nothing" begin
        s, sp = build(diffusion3())
        st = HostStore(s)
        prep = prepare(s, sp.launches[1], st, (0.1, 1.0, 1.0, 0.0, 1.0))
        run!(prep)
        @test (@allocated run!(prep)) == 0
    end
end

@testitem "an integer power emits products, not `^`" setup = [LF_compile_stencils] tags = [:latticefields, :compile] begin
    @testset "an integer power emits products, not `^`" begin
        function powprog(n)
            pb = ProgramBuilder(Grid((7, 5)); periodic = (true, true), nparams = 1)
            u = field!(pb, "u"; buffers = 2)
            kb = kernel(pb)
            store(kb, u, load(kb, u)^n)
            add!(pb, kb, "pow")
            return pb
        end
        is_pow(x) = x isa Expr && x.head === :call && (x.args[1] === :^ || x.args[1] === ^)
        has(x, pred) = pred(x) || (x isa Expr && any(a -> has(a, pred), x.args))
        @test has(:(a + b^5), is_pow)                       # control: the detector sees a `^`
        u0 = 0.5f0 .+ rand(Xoshiro(2), Float32, 7, 5)
        for n in (-3, 4, 5, 7), options in (CompileOptions(), debug_options())
            s, sp = build(powprog(n); options)
            @test !has(sp.launches[1].kernel.body, is_pow)
            ref = Float32.(Float64.(u0) .^ n)
            @test run_field(s, sp, u0, (1.0,)) ≈ ref rtol = 2 * abs(n) * eps(Float32)
        end
    end
end

# Generated FV-style 5- and 7-point stencils through the host runner, against hand loops
# (bit-exact where the operation order is the same), a naive loop and the debug emission.

"""
Does an expression hold a Float64 literal or the symbol `Float64`?
"""
has_f64(x) = x isa Float64 || x === :Float64 || (x isa Expr && any(has_f64, x.args))

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
    @test run_field(s, sp, u0, P) ≈ nv rtol = 1e-5
    sd, spd = build(diffusion3(); options = debug_options())
    @test !has_f64(sp.launches[1].kernel.body) && has_f64(spd.launches[1].kernel.body)
    @test run_field(sd, spd, u0, P) ≈ nv rtol = 1e-7   # Float64 compute, one rounding at the store
    # Int64 site index (above 2³¹ sites) gives the same bits
    s64, sp64 = build(diffusion3(); options = CompileOptions(; I = Int64))
    @test run_field(s64, sp64, u0, P; steps = 3) == got
end

"""
2D 9-point / 3D 27-point box stencil (the Q1-like access pattern), periodic.
"""
function boxprog(dims)
    N = length(dims)
    pb = ProgramBuilder(Grid(dims); periodic = ntuple(_ -> true, N), nparams = 1)
    u = field!(pb, "u")
    v = field!(pb, "v")
    kb = kernel(pb)
    acc = sum(load(kb, u; offset = Tuple(o)) * (1 + sum(abs, Tuple(o)))
    for o in CartesianIndices(ntuple(_ -> -1:1, N)))
    store(kb, v, param(kb, 1) * acc)
    add!(pb, kb, "box")
    return pb
end

@testset "Cartesian index strategy for box stencils" begin
    for dims in ((9, 7), (5, 4, 3))
        rng = Xoshiro(3)
        u0 = rand(rng, Float32, dims...)
        s, sp = build(boxprog(dims))
        @test sp.launches[1].kernel.strategy == :cartesian
        @test sp.launches[1].workgroup == (length(dims) == 3 ? (64, 2, 2) : (64, 4))
        sl, spl = build(boxprog(dims); options = CompileOptions(; index = :linear))
        @test spl.launches[1].kernel.strategy == :linear
        runbox(sx, spx) = (st = HostStore(sx); copyto!(current(st, sx, "u"), u0);
            run_step!(sx, spx, st, (0.5,)); copy(current(st, sx, "v")))
        @test runbox(s, sp) == runbox(sl, spl)                        # same IR, same order: same bits
        sd, spd = build(boxprog(dims); options = debug_options())
        @test runbox(s, sp) ≈ runbox(sd, spd) rtol = 1e-5
    end
end

@testset "warm host launch allocates nothing" begin
    s, sp = build(diffusion3())
    st = HostStore(s)
    prep = prepare(s, sp.launches[1], st, (0.1, 1.0, 1.0, 0.0, 1.0))
    run!(prep)
    @test (@allocated run!(prep)) == 0
end

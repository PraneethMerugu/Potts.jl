# Integer lanes, tables, masked spaces (write-complete with pass-through), immersed and
# node-value rules, each against a hand loop.

@testsetup module LF_compile_lanes_masks
using Test, LatticeFields
include("../host_runner.jl")
include("../fixtures.jl")
using LatticeFields.IR: constant, cast, bittest, table, ImmersedRule, NodeValueRule, mask!

"""
Masked 5-point step: diffusion inside mask `m`, pass-through outside.
"""
function masked2(dims)
    pb = ProgramBuilder(Grid(dims); periodic = (true, true), nparams = 3)
    u = field!(pb, "u"; buffers = 2)
    m = mask!(pb, "m")
    kb = kernel(pb, Space{2}(MASKED; mask = m))
    c = load(kb, u)
    nb = sum(load(kb, u; offset = o) for o in OFFS2)
    store(kb, u, c + param(kb, 1) * param(kb, 2) / param(kb, 3)^2 * (nb - 4c))
    add!(pb, kb, "diffuse")
    return pb
end

"""
Odd substep count with a mask that moves one column per substep.
"""
function masked_run(s, sp, u0, P; steps = 3)
    st = HostStore(s)
    copyto!(current(st, s, "u"), u0)
    nx, ny = size(u0)
    ref, tmp = copy(u0), similar(u0)
    for t in 1:steps
        mk = [UInt8(mod1(i + t, nx) <= nx ÷ 2) for i in 1:nx, j in 1:ny]
        copyto!(current(st, s, "m"), mk)
        run_step!(s, sp, st, P)
        hand2!(tmp, ref, P)
        tmp .= ifelse.(mk .!= 0, tmp, ref)
        ref, tmp = tmp, ref
    end
    return reshape(copy(current(st, s, "u")), size(u0)), ref
end
include("../shared/export_all.jl")
end

@testitem "masked space is write-complete (odd substeps, moving mask)" setup = [LF_compile_lanes_masks] tags = [:latticefields, :compile] begin
@testset "masked space is write-complete (odd substeps, moving mask)" begin
    u0 = rand(Xoshiro(4), Float32, 8, 5)
    P = (0.1, 0.7, 1.3)
    s, sp = build(masked2((8, 5)))
    got, ref = masked_run(s, sp, u0, P)
    @test reinterpret(UInt32, got) == reinterpret(UInt32, ref)
    # negative control: without the pass-through, outside sites keep a stale buffer
    bad = merge(LOWERING, (; passthrough = c -> Any[]))
    sb, spb = build(masked2((8, 5)); stages = bad)
    gotb, _ = masked_run(sb, spb, u0, P)
    @test gotb != ref
end
end

@testitem "integer lanes: U8 mask counts into I32, U32 bit test into U8" setup = [LF_compile_lanes_masks] tags = [:latticefields, :compile] begin
@testset "integer lanes: U8 mask counts into I32, U32 bit test into U8" begin
    dims = (6, 5)
    pb = ProgramBuilder(Grid(dims); periodic = (true, true))
    m = field!(pb, "m"; storage = U8, role = :input)
    cnt = field!(pb, "cnt"; storage = I32, role = :aux)
    fl = field!(pb, "flags"; storage = U32, role = :input)
    bit = field!(pb, "bit"; storage = U8, role = :output)
    kb = kernel(pb)
    one32, zero32 = constant(kb, 1, I32), constant(kb, 0, I32)
    hits = sum(select(eq(load(kb, m; offset = o), constant(kb, 0, U8)), zero32, one32)
    for o in OFFS2)
    store(kb, cnt, load(kb, cnt) + hits)
    store(kb, bit, select(bittest(load(kb, fl), 3), constant(kb, 1, U8), constant(kb, 0, U8)))
    add!(pb, kb, "count")
    s, sp = build(pb)
    rng = Xoshiro(5)
    mv, fv, c0 = rand(rng, UInt8(0):UInt8(2), dims), rand(rng, UInt32, dims),
    rand(rng, Int32(0):Int32(9), dims)
    st = HostStore(s)
    copyto!(current(st, s, "m"), mv)
    copyto!(current(st, s, "flags"), fv)
    copyto!(current(st, s, "cnt"), c0)
    run_step!(s, sp, st, ())
    nx, ny = dims
    want = [c0[i, j] +
            Int32(sum(mv[mod1(i + a, nx), mod1(j + b, ny)] != 0 for (a, b) in OFFS2))
            for i in 1:nx, j in 1:ny]
    @test reshape(current(st, s, "cnt"), dims) == want
    @test reshape(current(st, s, "bit"), dims) == UInt8.((fv .>> 3) .& 1)
    @test eltype(current(st, s, "cnt")) == Int32
end
end

@testitem "tables: per-kind lookup with zero at index 0" setup = [LF_compile_lanes_masks] tags = [:latticefields, :compile] begin
@testset "tables: per-kind lookup with zero at index 0" begin
    pb = ProgramBuilder(Grid((5, 4)))
    kind = field!(pb, "kind"; storage = I32, role = :input)
    out = field!(pb, "rate"; role = :output)
    tb = IR.table!(pb, "rate_by_kind"; storage = F32)
    kb = kernel(pb)
    store(kb, out, table(kb, tb, F32, load(kb, kind)) * 2)
    add!(pb, kb, "lookup")
    s, sp = build(pb)
    st = HostStore(s)
    kv = rand(Xoshiro(6), Int32(0):Int32(3), 20)
    copyto!(current(st, s, "kind"), kv)
    st.tables[Int32(1)] = Float32[1.5, 2.5, 4.0]
    run_step!(s, sp, st, ())
    @test current(st, s, "rate") ==
          [k == 0 ? 0.0f0 : 2 * Float32[1.5, 2.5, 4.0][k] for k in kv]
end
end

@testitem "immersed zero-flux rule conserves mass outside the obstacle" setup = [LF_compile_lanes_masks] tags = [:latticefields, :compile] begin
@testset "immersed zero-flux rule conserves mass outside the obstacle" begin
    function prog(rule::Bool)
        pb = ProgramBuilder(Grid((9, 8)); periodic = (true, true), nparams = 3)
        u = field!(pb, "u"; buffers = 2)
        ob = mask!(pb, "obstacle")
        rule && rule!(pb, ImmersedRule(u, ob, :zero_flux))
        kb = kernel(pb)
        c = load(kb, u)
        store(kb,
            u,
            c +
            param(kb, 1) * param(kb, 2) / param(kb, 3)^2 *
            (sum(load(kb, u; offset = o) for o in OFFS2) - 4c))
        add!(pb, kb, "diffuse")
        return pb
    end
    obst = [UInt8(3 <= i <= 5 && 3 <= j <= 6) for i in 1:9, j in 1:8]
    fluid = vec(obst .== 0)
    u0 = rand(Xoshiro(7), Float32, 9, 8)
    function mass(rule)
        s, sp = build(prog(rule))
        st = HostStore(s)
        copyto!(current(st, s, "u"), u0)
        copyto!(current(st, s, "obstacle"), obst)
        foreach(_ -> run_step!(s, sp, st, (0.2, 1.0, 1.0)), 1:5)
        return sum(Float64, current(st, s, "u")[fluid])
    end
    m0 = sum(Float64, vec(u0)[fluid])
    @test mass(true) ≈ m0 rtol = 1e-5
    @test !isapprox(mass(false), m0; rtol = 1e-3)               # negative control
end
end

@testitem "node-value rule: masked sites store the value (identity row)" setup = [LF_compile_lanes_masks] tags = [:latticefields, :compile] begin
@testset "node-value rule: masked sites store the value (identity row)" begin
    pb = ProgramBuilder(Grid((6, 6)); periodic = (true, true), nparams = 4)
    u = field!(pb, "u"; buffers = 2)
    d = mask!(pb, "dirichlet")
    rule!(pb, NodeValueRule(u, d, Coef(1.0, 4), :harmonic))
    kb = kernel(pb)
    c = load(kb, u)
    store(kb,
        u,
        c +
        param(kb, 1) * param(kb, 2) / param(kb, 3)^2 *
        (sum(load(kb, u; offset = o) for o in OFFS2) - 4c))
    add!(pb, kb, "diffuse")
    s, sp = build(pb)
    st = HostStore(s)
    dm = [UInt8(i == 2) for i in 1:6, j in 1:6]
    u0 = rand(Xoshiro(8), Float32, 6, 6)
    copyto!(current(st, s, "u"), u0)
    copyto!(current(st, s, "dirichlet"), dm)
    run_step!(s, sp, st, (0.1, 1.0, 1.0, 0.75))
    got = reshape(current(st, s, "u"), 6, 6)
    @test all(got[2, :] .== 0.75f0)
    @test got[4:6, :] == hand2!(similar(u0), u0, (0.1, 1.0, 1.0))[4:6, :]
end
end

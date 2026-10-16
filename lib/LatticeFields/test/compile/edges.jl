# Edge cases: idempotent semantic passes, level checks, the automatic Int64 index, throw-free
# domain-restricted math and lazy COND, multi-component planes, rounded forwarding.

using LatticeFields.IR: IRError, ImmersedRule, mask!, constant, cond

errmsg(f) =
    try
        f()
        ""
    catch e
        e isa IRError ? e.msg : rethrow()
    end

@testset "semantic passes are idempotent" begin
    pb = ProgramBuilder(Grid((6, 5)); periodic = (true, false), nparams = 1)
    u = field!(pb, "u"; buffers = 2)
    ob = mask!(pb, "ob")
    rule!(pb, ImmersedRule(u, ob, :zero_flux))
    foreach(s -> rule!(pb, FaceRule(u, 2, s, Coef(0), Coef(1), Coef(0))), (-1, 1))
    kb = kernel(pb)
    store(kb, u, sum(load(kb, u; offset = o) for o in OFFS2) * param(kb, 1))
    add!(pb, kb, "k")
    p = program(pb)
    s1 = semantic(p)
    @test sprint(IR.print_program, semantic(s1)) == sprint(IR.print_program, s1)
    @test fingerprint(s1) == fingerprint(p)
    @test !any(a -> a.policy == IR.RESOLVE, s1.kernels[1].accesses)
end

@testset "levels: accesses and stores must match the field's levels" begin
    pb = ProgramBuilder(Grid((8, 8)); periodic = (true, true), levels = 2)
    fine = field!(pb, "fine"; role = :input)
    coarse = field!(pb, "coarse"; role = :output, levels = [1])
    kb = kernel(pb)                                     # level-0 space storing a level-1 field
    store(kb, coarse, load(kb, fine))
    add!(pb, kb, "wrong_store")
    @test occursin("store to `coarse` at level 0", errmsg(() -> semantic(program(pb))))
    pb = ProgramBuilder(Grid((8, 8)); periodic = (true, true), levels = 2)
    fine = field!(pb, "fine"; role = :input)
    coarse = field!(pb, "coarse"; role = :output, levels = [1])
    kb = kernel(pb, Space{2}(; level = 1))              # reads the fine field at relative level 0
    store(kb, coarse, load(kb, fine))
    add!(pb, kb, "wrong_read")
    @test occursin("access to `fine` at level 1", errmsg(() -> semantic(program(pb))))
end

@testset "Int64 site index above 2³¹ − 1 elements" begin
    pb = ProgramBuilder(Grid((50_000, 50_000)); periodic = (true, true))
    u, v = field!(pb, "u"; role = :input), field!(pb, "v"; role = :output)
    kb = kernel(pb)
    store(kb, v, load(kb, u; offset = (1, 0)))
    add!(pb, kb, "shift")
    s = semantic(program(pb))
    @test compile_kernel(s, s.kernels[1]).I == Int64
    @test compile_kernel(semantic(program(diffusion2())), semantic(program(diffusion2())).kernels[1]).I ==
          Int32
end

@testset "domain-restricted math returns NaN; COND is lazy" begin
    pb = ProgramBuilder(Grid((4, 3)))
    u = field!(pb, "u"; role = :input)
    a, b, c = (field!(pb, k; role = :output) for k in ("a", "b", "c"))
    kb = kernel(pb)
    x = load(kb, u)
    store(kb, a, cond(0 < x, log(x), constant(kb, 0.0)))
    store(kb, b, sqrt(x))
    store(kb, c, select(0 < x, log(x), constant(kb, 0.0)))
    add!(pb, kb, "math")
    s, sp = build(pb)
    @test occursin("if", string(sp.launches[1].kernel.body))
    st = HostStore(s)
    uv = Float32[-2, -1, 0, 0.5, 1, 2, 3, -0.5, 4, 5, -3, 7]
    copyto!(current(st, s, "u"), uv)
    run_step!(s, sp, st, ())                            # does not throw on negative inputs
    want = [v > 0 ? log(v) : 0.0f0 for v in uv]
    @test current(st, s, "a") == want
    @test current(st, s, "c") == want
    @test all(isnan, current(st, s, "b")[uv .< 0]) &&
          current(st, s, "b")[uv .>= 0] == sqrt.(uv[uv .>= 0])
end

@testset "multi-component fields are planes; two-buffer partial writes are refused" begin
    pb = ProgramBuilder(Grid((5, 4)); periodic = (true, true))
    v = field!(pb, "v"; shape = [2], buffers = 2)
    kb = kernel(pb)
    store(kb, v, load(kb, v; comp = 2, offset = (1, 0)); comp = 1)
    store(kb, v, load(kb, v; comp = 1, offset = (0, -1)) * 2; comp = 2)
    add!(pb, kb, "swap")
    s, sp = build(pb)
    st = HostStore(s)
    v0 = rand(Xoshiro(17), Float32, 5, 4, 2)
    copyto!(current(st, s, "v"), v0)
    run_step!(s, sp, st, ())
    got = reshape(current(st, s, "v"), 5, 4, 2)
    @test got[:, :, 1] == circshift(v0[:, :, 2], (-1, 0))
    @test got[:, :, 2] == 2 .* circshift(v0[:, :, 1], (0, 1))
    pb = ProgramBuilder(Grid((5, 4)); periodic = (true, true))
    v = field!(pb, "v"; shape = [2], buffers = 2)
    kb = kernel(pb)
    store(kb, v, load(kb, v; comp = 2); comp = 1)
    add!(pb, kb, "half")
    @test occursin("all its components", errmsg(() -> semantic(program(pb))))
end

@testset "forwarding keeps the lane rounding (F16 aux, Float32 compute)" begin
    pb = ProgramBuilder(Grid((7, 5)); periodic = (true, true), nparams = 1)
    u = field!(pb, "u"; role = :input)
    w = field!(pb, "w"; role = :aux, storage = F16)
    v = field!(pb, "v"; role = :output)
    ka = kernel(pb)
    store(ka, w, load(ka, u) * param(ka, 1) + 0.1)
    add!(pb, ka, "a")
    kc = kernel(pb)
    store(kc, v, load(kc, w) * 3)
    add!(pb, kc, "b")
    s = semantic(program(pb))
    fused, split = plan(s), plan(s; fuse = false)
    @test length(fused.launches) == 1 && length(split.launches) == 2
    exec(sp) = (
        st = HostStore(s); copyto!(current(st, s, "u"), rand(Xoshiro(18), Float32, 35));
        run_step!(s, sp, st, (0.37,)); copy(current(st, s, "v")))
    @test exec(fused) == exec(split)
end

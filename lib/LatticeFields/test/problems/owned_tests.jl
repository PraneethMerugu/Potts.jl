# The owned path and the ODE path on builder programs (no front end): warm steps allocate
# nothing (PG-13: also a plan of more than 32 launches), FieldProblem steps equal the
# hand loop, slot parity alternates, the face check refuses degenerate Robin parameters,
# and the ODE right side equals the stepper's rate.
using LatticeFields.Problems: FieldProblem, ExplicitEuler, BoundStep, LatticeIndex,
                              FieldSlot,
                              ode_problem, face_checks, check_faces, degenerate_face
using LatticeFields.IR: runtime
using CommonSolve: solve, init, step!
using SciMLBase: SciMLBase

"""
2D periodic diffusion stepped with `dt = G.rt[2]` (the owned stepper form).
"""
function euler2(dims; rate = false, storage = F32)
    pb = ProgramBuilder(Grid(dims); periodic = (true, true), nparams = 1)
    u = field!(pb, "u"; buffers = rate ? 1 : 2, storage)
    g = rate ? field!(pb, "∂u"; role = :scratch, storage) : u
    kb = kernel(pb)
    c = load(kb, u)
    r = param(kb, 1) * (sum(load(kb, u; offset = o) for o in OFFS2) - 4c)
    store(kb, g, rate ? r : c + runtime(kb, 2) * r)
    add!(pb, kb, "diffuse")
    return program(pb)
end

@testset "FieldProblem: steps equal the hand loop; warm steps allocate nothing" begin
    dims = (12, 10)
    u0 = rand(Xoshiro(5), Float32, prod(dims))
    ix = LatticeIndex(; variables = [:u => FieldSlot(1:prod(dims), dims)], parameters = [:D =>
        1])
    prob = FieldProblem(
        euler2(dims), Float64.(u0), (0.0, 0.1), [0.5]; state = ["u"], kind = :rate,
        index = ix)
    sol = solve(prob, ExplicitEuler(; dt = 0.05, substeps = 1); saveat = 0.05)
    v = reshape(u0, dims)
    for _ in 1:2
        v = hand2!(similar(v), v, (0.05, 0.5, 1.0))               # u + (dt D/h²)(Σ nb − 4u)
    end
    @test isapprox(sol[:u][end], v; rtol = 1e-5) &&
          !isapprox(sol[:u][end], reshape(u0, dims); rtol = 1e-3)
    integ = init(prob, ExplicitEuler(; dt = 0.05, substeps = 1))
    step!(integ)
    @test integ.store.cur[1] == 2                                 # one swap per substep
    step!(integ)
    @test (@allocated step!(integ)) == 0
end

@testset "substeps follow the stability bound at the current parameters" begin
    dims = (8, 8)
    ix = LatticeIndex(; variables = [:u => FieldSlot(1:prod(dims), dims)], parameters = [:D => 1])
    S = LatticeFields.Problems.substeps
    unknown = FieldProblem(euler2(dims), zeros(64), (0.0, 0.1), [0.5]; state = ["u"], kind = :rate, index = ix)
    @test_throws ArgumentError S(unknown, ExplicitEuler(; dt = 0.05))       # no bound, no count
    @test S(unknown, ExplicitEuler(; dt = 0.05, substeps = 3)) == 3
    prob = FieldProblem(euler2(dims), zeros(64), (0.0, 0.1), [0.5]; state = ["u"], kind = :rate,
        index = ix, stability = p -> 8 * p[1])
    @test S(prob, ExplicitEuler(; dt = 0.5)) == ceil(Int, 0.5 * 4 / 1.8)
    @test S(SciMLBase.remake(prob; p = [2.0]), ExplicitEuler(; dt = 0.5)) == ceil(Int, 0.5 * 16 / 1.8)
    integ = init(prob, ExplicitEuler(; dt = 0.05))
    LatticeFields.Problems.SII.setp(integ, :D)(integ, 100.0)
    @test integ.substeps == ceil(Int, 0.05 * 800 / 1.8)
    # a user count is a minimum (ruling Q2, F1): raised to the bound's count, kept above it, and
    # used as given when there is no bound (`unknown` above). On f9a77dd3 the count was used
    # as given below the bound too: substeps = 1 gave 1 here, not 2
    @test S(prob, ExplicitEuler(; dt = 0.5, substeps = 1)) == ceil(Int, 0.5 * 4 / 1.8) == 2
    @test S(prob, ExplicitEuler(; dt = 0.5, substeps = 5)) == 5
end

@testset "PG-13: a plan of more than 32 launches allocates nothing" begin
    pb = ProgramBuilder(Grid((8, 8)); periodic = (true, true), nparams = 1)
    fs = [field!(pb, "u$(lpad(k, 2, '0'))"; buffers = 2) for k in 1:40]
    for (k, f) in enumerate(fs)
        kb = kernel(pb)
        store(kb, f, load(kb, f; offset = (1, 0)) * param(kb, 1) + runtime(kb, 1))
        add!(pb, kb, "k$(lpad(k, 2, '0'))")
    end
    s, sp = build(pb; fuse = false)
    @test length(sp.launches) == 40
    st = HostStore(s)
    bs = BoundStep(HOST, s, sp, st, (1.0,))
    bs((0.0, 0.0))
    @test (@allocated bs((1.0, 0.0))) == 0
    @test array(st, IR.fieldid(s, "u01"), :next)[1] == 1.0f0     # G.rt[1] reached the body
end

@testset "Robin faces: parameter checks" begin
    pb = ProgramBuilder(Grid((4, 4)); periodic = (false, true), nparams = 2)
    u = field!(pb, "u"; buffers = 2)
    rule!(pb, FaceRule(u, 1, -1, Coef(1.0), Coef(1.0, 1), Coef(0.0)))   # α = 1, β = P1
    rule!(pb, FaceRule(u, 1, 1, Coef(1.0, 2), Coef(1.0), Coef(0.0)))    # α = P2, β = 1
    kb = kernel(pb)
    store(kb, u, load(kb, u; offset = (1, 0)))
    add!(pb, kb, "k")
    p = program(pb)
    fc = face_checks(p)
    @test length(fc) == 2
    @test degenerate_face(fc, [1.0, 1.0]) == 0
    @test sort([degenerate_face(fc, [-0.5, 1.0]), degenerate_face(fc, [1.0, -2.0])]) ==
          [1, 2]
    @test_throws ArgumentError check_faces(fc, [-0.5, 1.0])
    ok = [1.0, 1.0]
    @test (@allocated degenerate_face(fc, ok)) == 0
    @test_throws ArgumentError FieldProblem(
        p, zeros(16), (0.0, 1.0), [-0.5, 1.0]; state = ["u"], kind = :rate)
    prob = FieldProblem(p, zeros(16), (0.0, 1.0), [1.0, 1.0]; state = ["u"], kind = :rate)
    @test_throws ArgumentError SciMLBase.remake(prob; p = [1.0, -2.0])
end

@testset "ODE form: the right side is the rate" begin
    dims = (12, 10)
    u0 = rand(Xoshiro(6), prod(dims))
    ix = LatticeIndex(; variables = [:u => FieldSlot(1:prod(dims), dims)])
    ode = ode_problem(
        euler2(dims; rate = true, storage = F64), u0, (0.0, 1.0), [0.5]; state = ["u"],
        rates = Dict("u" => "∂u"), index = ix, options = CompileOptions(; T = Float64))
    @test ode isa SciMLBase.ODEProblem
    du = similar(ode.u0)
    ode.f(du, ode.u0, ode.p, 0.0)
    v = reshape(u0, dims)
    nb = circshift(v, (1, 0)) + circshift(v, (-1, 0)) + circshift(v, (0, 1)) +
         circshift(v, (0, -1))
    @test maximum(abs, du .- vec(0.5 .* (nb .- 4v))) < 1e-12
    @test (@allocated ode.f(du, ode.u0, ode.p, 0.0)) == 0
end

@testset "a U8 input takes 0…255 unless declared Bool (F1 round 5)" begin
    # round 4: every U8 input was held to 0/1, so a raw U8 IR input refused 7
    pb = ProgramBuilder(Grid((3, 3)); nparams = 0)
    k8 = field!(pb, "k"; storage = U8, role = :input)
    x = field!(pb, "x")
    kb = kernel(pb)
    store(kb, x, load(kb, x) + load(kb, k8))
    add!(pb, kb, "k")
    prog = program(pb)
    cv(v; bool) = try
        LatticeFields.Problems._check_integer(prog, "k", "k", v; bool); ""
    catch e
        sprint(showerror, e)
    end
    @test cv(fill(7, 9); bool = false) == "" && cv(fill(255, 9); bool = false) == ""
    w = fill(0, 9); w[5] = 300
    err = cv(w; bool = false)
    @test occursin("integer values (a kind map: UInt8)", err) && occursin("at site (2, 2)", err)
    err = cv(fill(7, 9); bool = true)
    @test occursin("a Bool mask", err) && occursin("got 7 at site (1, 1)", err)
    @test cv([true, false, 1, 0, 1, 0, 1, 0, 1]; bool = true) == ""
end

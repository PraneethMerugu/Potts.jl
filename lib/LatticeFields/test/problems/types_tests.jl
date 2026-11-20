# Number types (P5 role model) on builder programs: Dual parameters through FieldProblem
# against finite differences, hoisted time, init-written aux fields in every ODE variant and
# after parameter changes, and the refusal of an explicit options.T that differs from u0.
# (The conversion primitives and the Float64 check are in compile/numbers.jl.)

@testsetup module LF_problems_types
using Test, LatticeFields
include("../host_runner.jl")
include("../fixtures.jl")
include("../shared/problems_owned.jl")
using ForwardDiff: ForwardDiff, Dual
using OrdinaryDiffEqRosenbrock: Rodas5P
using SymbolicIndexingInterface: setp
using LatticeFields.IR: F32, F64

"""
6×4 periodic: init kernel `a = p[2]` (a float aux field), rate `∂u = p[1] (Σ nb − 4u) − a u`
(`ode = true`), or the owned Euler form `u + dt (…)`.
"""
function initaux(; ode = true)
    pb = ProgramBuilder(Grid((6, 4)); periodic = (true, true), nparams = 2)
    u = field!(pb, "u"; buffers = ode ? 1 : 2, storage = F64)
    a = field!(pb, "a"; role = :aux, storage = F64)
    g = ode ? field!(pb, "∂u"; role = :scratch, storage = F64) : u
    ki = kernel(pb)
    store(ki, a, param(ki, 2))
    add!(pb, ki, "init")
    kb = kernel(pb)
    c = load(kb, u)
    r = param(kb, 1) * (sum(load(kb, u; offset = o) for o in OFFS2) - 4c) - load(kb, a) * c
    store(kb, g, ode ? r : c + runtime(kb, 2) * r)
    add!(pb, kb, "rate")
    return program(pb)
end
# the rate by hand
function rate_hand(u, D, k)
    v = reshape(u, 6, 4)
    lap = circshift(v, (1, 0)) .+ circshift(v, (-1, 0)) .+ circshift(v, (0, 1)) .+ circshift(v, (0, -1)) .- 4v
    return vec(D .* lap .- k .* v)
end
include("../shared/export_all.jl")
end

@testitem "Dual parameters through FieldProblem (vs finite differences)" setup = [LF_problems_types] tags = [:latticefields, :problems] begin
    @testset "Dual parameters through FieldProblem (vs finite differences)" begin
        dims = (8, 6)
        u0 = rand(Xoshiro(3), prod(dims))
        ix = LatticeIndex(; variables = [:u => FieldSlot(1:prod(dims), dims)], parameters = [:D => 1])
        prob = FieldProblem(
            euler2(dims; storage = F64), u0, (0.0, 0.2), [0.05]; state = ["u"],
            kind = :rate, index = ix
        )
        alg = ExplicitEuler(; substeps = 1)
        J(D) = sum(abs2, solve(SciMLBase.remake(prob; p = [D]), alg; dt = 0.05).u[end])
        d = ForwardDiff.derivative(J, 0.05)
        h = 1.0e-6
        @test isapprox(d, (J(0.05 + h) - J(0.05 - h)) / 2h; rtol = 1.0e-6) && d != 0
        rp = SciMLBase.remake(prob; p = [Dual{Nothing}(0.05, 1.0)])
        @test eltype(rp) == Dual{Nothing, Float64, 1} && rp.step === prob.step   # same value type: same plans
        # a Float32 lane under Duals stores Dual{Float32}
        p32 = FieldProblem(euler2(dims), Float32.(u0), (0.0, 0.2), [0.05]; state = ["u"], kind = :rate, index = ix)
        i32 = init(SciMLBase.remake(p32; p = [Dual{Nothing}(0.05, 1.0)]), alg; dt = 0.05)
        @test eltype(i32.store.flat[1]) == Dual{Nothing, Float32, 1}
    end
end

@testitem "hoisted time: a parameter-and-t subtree is derived on the host per launch" setup = [LF_problems_types] tags = [:latticefields, :problems] begin
    @testset "hoisted time: a parameter-and-t subtree is derived on the host per launch" begin
        pb = ProgramBuilder(Grid((4, 4)); periodic = (true, true), nparams = 1)
        u = field!(pb, "u"; buffers = 2, storage = F32)
        kb = kernel(pb)
        store(kb, u, load(kb, u) + runtime(kb, 2) * (param(kb, 1) * runtime(kb, 1)))
        add!(pb, kb, "src")
        s = semantic(program(pb))
        ck = only(plan(s; options = CompileOptions(; T = Float32)).launches).kernel
        @test ck.timed && !occursin("G.rt[1]", string(ck.body))
        prob = FieldProblem(program(pb), zeros(Float32, 16), (1.0e5, 1.0e5 + 0.04), [3.0]; state = ["u"], kind = :rate)
        sol = solve(prob, ExplicitEuler(; substeps = 1); dt = 0.01)
        ref = sum(0.01 * 3.0 * (1.0e5 + 0.01k) for k in 0:3)
        @test isapprox(sol.u[end][1], ref; rtol = 1.0e-6)
        # a kernel with no t-dependent subtree is not re-derived
        @test !only(plan(semantic(euler2((4, 4))); options = CompileOptions(; T = Float32)).launches).kernel.timed
    end
end

@testitem "init-written aux in every ODE variant and after parameter changes" setup = [LF_problems_types] tags = [:latticefields, :problems] begin
    @testset "init-written aux in every ODE variant and after parameter changes" begin
        u0 = rand(Xoshiro(11), 24)
        p0 = [0.1, 2.0]
        ode = ode_problem(
            initaux(), u0, (0.0, 0.5), p0; state = ["u"], rates = Dict("u" => "∂u"),
            init = ["init"]
        )
        rhs(u, p) = (du = similar(u, promote_type(eltype(u), eltype(p))); ode.f(du, u, p, 0.0); du)
        @test rhs(u0, p0) ≈ rate_hand(u0, 0.1, 2.0)                       # native
        # Dual p: the variant runs init with its own (Dual) parameters
        pd = [Dual{Nothing}(0.1, 1.0, 0.0), Dual{Nothing}(2.0, 0.0, 1.0)]
        dd = rhs(u0, pd)
        @test ForwardDiff.value.(dd) ≈ rate_hand(u0, 0.1, 2.0)
        @test [ForwardDiff.partials(x)[2] for x in dd] ≈ -u0                # ∂/∂k through init
        # a Float32 u on the Float64 build: its own variant, init included
        @test rhs(Float32.(u0), p0) ≈ rate_hand(Float32.(u0), 0.1, 2.0) rtol = 1.0e-5
        # a new parameter vector re-runs init (remake); the same vector does not need to
        @test rhs(u0, [0.1, 5.0]) ≈ rate_hand(u0, 0.1, 5.0)
        @test rhs(u0, p0) ≈ rate_hand(u0, 0.1, 2.0)
        q = copy(p0)
        @test rhs(u0, q) ≈ rate_hand(u0, 0.1, 2.0)
        q[2] = 3.0                                                         # in place, same object
        @test rhs(u0, q) ≈ rate_hand(u0, 0.1, 3.0)
        # dJ/dk through init only, against finite differences; also with Rodas5P (Jacobian and
        # time gradient variants run init)
        function J(k; alg = Rodas5P())
            return sum(
                SciMLBase.solve(
                    SciMLBase.remake(
                        ode; p = [0.1, k],
                        u0 = promote_type(Float64, typeof(k)).(u0)
                    ), alg; abstol = 1.0e-10, reltol = 1.0e-10
                ).u[end]
            )
        end
        h = 1.0e-6
        dk = ForwardDiff.derivative(J, 2.0)
        @test isapprox(dk, (J(2.0 + h) - J(2.0 - h)) / 2h; rtol = 1.0e-5) && dk != 0
        # chunked ForwardDiff re-seeds the partials of one Dual vector in place (same object, same
        # primal values): init must re-run. Negative control: the old skip rule,
        # which compared primal values only, would leave ∂a/∂k from chunk 1 and give dJ/dk = 0.
        function Jp(θ)
            return sum(
                SciMLBase.solve(
                    SciMLBase.remake(ode; p = θ, u0 = eltype(θ).(u0)), Rodas5P();
                    abstol = 1.0e-10, reltol = 1.0e-10
                ).u[end]
            )
        end
        g1 = ForwardDiff.gradient(Jp, p0, ForwardDiff.GradientConfig(Jp, p0, ForwardDiff.Chunk{1}()))
        @test isapprox(g1[2], dk; rtol = 1.0e-6)
        pv = [Dual{Nothing}(0.1, 1.0), Dual{Nothing}(2.0, 0.0)]
        rhs(u0, pv)
        pv .= [Dual{Nothing}(0.1, 0.0), Dual{Nothing}(2.0, 1.0)]                 # re-seed in place
        @test [ForwardDiff.partials(x)[1] for x in rhs(u0, pv)] ≈ -u0
        # owned path: Dual p through init, and setp re-runs init
        own = FieldProblem(
            initaux(; ode = false), u0, (0.0, 0.2), p0; state = ["u"], kind = :rate,
            init = ["init"], index = LatticeIndex(;
                variables = [:u => FieldSlot(1:24, (6, 4))],
                parameters = [:D => 1, :k => 2]
            )
        )
        alg = ExplicitEuler(; substeps = 1)
        Jo(k) = sum(solve(SciMLBase.remake(own; p = [0.1, k]), alg; dt = 0.05).u[end])
        @test isapprox(ForwardDiff.derivative(Jo, 2.0), (Jo(2.0 + h) - Jo(2.0 - h)) / 2h; rtol = 1.0e-6)
        integ = init(own, alg; dt = 0.05)
        setp(integ, :k)(integ, 5.0)
        step!(integ)
        @test integ[:u] ≈ reshape(u0 .+ 0.05 .* rate_hand(u0, 0.1, 5.0), 6, 4)
    end
end

@testitem "an explicit options.T that differs from u0 is refused" setup = [LF_problems_types] tags = [:latticefields, :problems] begin
    @testset "an explicit options.T that differs from u0 is refused" begin
        @test_throws ArgumentError FieldProblem(
            euler2((8, 8)), zeros(64), (0.0, 0.1), [0.5]; state = ["u"],
            kind = :rate, options = CompileOptions(; T = Float32)
        )
        @test FieldProblem(
            euler2((8, 8)), zeros(Float32, 64), (0.0, 0.1), [0.5]; state = ["u"],
            kind = :rate, options = CompileOptions(; T = Float32)
        ) isa FieldProblem
        @test_throws ArgumentError ode_problem(
            euler2((8, 8); rate = true), zeros(64), (0.0, 1.0), [0.5];
            state = ["u"], rates = Dict("u" => "∂u"), options = CompileOptions(; T = Float32)
        )
    end
end

@testitem "generic float types (Float16, Float32, Float64, BigFloat) through FieldProblem" setup = [LF_problems_types] tags = [:latticefields, :problems] begin
    @testset "generic float types through FieldProblem" begin
        dims = (8, 6)
        u0_64 = rand(Xoshiro(19), prod(dims))
        ix = LatticeIndex(; variables = [:u => FieldSlot(1:prod(dims), dims)], parameters = [:D => 1])
        alg = ExplicitEuler(; substeps = 1)
        function run_T(T)
            return solve(
                FieldProblem(
                    euler2(dims; storage = LatticeFields.IR.F32), T.(u0_64),
                    (0.0, 0.2), T[0.05]; state = ["u"], kind = :rate, index = ix
                ), alg
                ; dt = 0.05
            )
        end
        s64 = run_T(Float64)
        sbig = run_T(BigFloat)
        s32 = run_T(Float32)
        s16 = run_T(Float16)
        @test eltype(s64.u[end]) == Float64
        @test eltype(sbig.u[end]) == BigFloat
        @test eltype(s32.u[end]) == Float32
        @test eltype(s16.u[end]) == Float16
        @test maximum(abs, Float64.(sbig.u[end]) .- s64.u[end]) < 1.0e-12
        @test maximum(abs, Float64.(s32.u[end]) .- s64.u[end]) < 1.0e-5
        @test maximum(abs, Float64.(s16.u[end]) .- s64.u[end]) < 2.0e-2
    end
end

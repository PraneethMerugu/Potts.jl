# F4-08 (F4 design §3.7, SX-15, Q-A (b)): the lattice multigrid as a LinearSolve preconditioner
# (`LatticeMultigrid`) and algorithm (`LatticePCG`). FBDF with GMRES preconditioned by `LatticeMultigrid()`
# at 256² takes far fewer Krylov iterations per linear solve than GMRES alone; `LatticePCG()`
# solves a linear system with no time to the direct solve; the SX-18 oracles move from 8×8 to
# 64² on the sparse Jacobian (OrdinaryDiffEq's ImplicitEuler against BackwardEuler, Trapezoid
# against CrankNicolson); on a device FBDF runs matrix-free with the preconditioner.
# Negative controls: at the base 978e73c7 `LatticeMultigrid` is undefined and `sparse = true` is
# refused (every testset errors); a preconditioner built without the shift `1/γ` fails the
# iteration bound (~/lpwork/f4b3/nc-*.log).

@testsetup module LP_precond
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables, Differential, PDESystem,
                           System, mtkcompile, ODEProblem, unknowns, parameters, ShiftIndex, Shift, Pre,
                           t_nounits as t, D_nounits as D
using Symbolics: Symbolics, Num, Equation, unwrap, simplify, substitute, get_variables
using SymbolicUtils: SymbolicUtils, iscall, operation, arguments, unwrap_const
using DomainSets: Interval
using SciMLBase: SciMLBase
using LatticeFields: LatticeFields, Problems as LFP
# imports an earlier file made in the old single Main
using SparseArrays: sparse
include("shared/lp_runner.jl")
include("shared/discretize.jl")
include("shared/problems.jl")
include("shared/bounds.jl")
include("shared/families.jl")
include("shared/precond.jl")
include("shared/export_all.jl")
end

@testitem "F4-08: FBDF with GMRES and LatticeMultigrid at 256²" setup = [LP_precond] tags = [:latticepde, :precond] begin
    @testset "F4-08: FBDF with GMRES and LatticeMultigrid at 256²" begin
    prob = discretize(qsys(0.5), qdisc(256))
        mg = LatticeMultigrid()
    s1, k1 = qfbdf(prob; precs = mg)
    s0, k0 = qfbdf(prob)
        @info "F4-08 FBDF 256²: Krylov iterations per linear solve, GMRES $(round(k0; digits = 1)), with LatticeMultigrid $(round(k1; digits = 1)); steps $(s0.stats.naccept), $(s1.stats.naccept)"
    @test SciMLBase.successful_retcode(s0) && SciMLBase.successful_retcode(s1)
    @test maximum(abs, s1.u[end] .- s0.u[end]) < 1e-4
    # Preconditioned GMRES keeps Krylov iterations O(1) (<= 6) and >= 5x fewer than unpreconditioned GMRES
    @test k1 <= 6 && k0 >= 5k1 || (println("F4-08 iterations ", (k0, k1)); false)
    P = only(values(mg.engines))
    @test P isa LFP.MGPreconditioner && P.applies > 0 && isfinite(P.γ)
        @test repr(mg) == "LatticeMultigrid()" && occursin("cycle = (3, 3)", repr(LatticeMultigrid(; cycle = (3, 3))))
    # the documented small memory (`gmres_restart = 10`): the same steps, W builds and iterations
        s2, k2 = qfbdf(prob; precs = LatticeMultigrid(), gmres_restart = 10)
    @test (s2.stats.naccept, s2.stats.nw, s2.stats.nsolve) == (s1.stats.naccept, s1.stats.nw, s1.stats.nsolve) && k2 == k1 ||
          (println("F4-08 gmres_restart 10 ", (s2.stats, k2), " against 200 ", (s1.stats, k1)); false)
end
end

@testitem "F4-08: LatticePCG solves a linear system with no time" setup = [LP_precond] tags = [:latticepde, :precond] begin
@testset "F4-08: LatticePCG solves a linear system with no time" begin
    fdom = [x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
        sl = PDESystem([0 ~ 0.3 * laplacian(qw(x, y)) - 2.0 * qw(x, y) + x], [qw(0, y) ~ 1.0], fdom, [x, y], [qw(x, y)], Num[]; name = :ql)
    lp = discretize(sl, qdisc(32))
    want = LFP.lattice_matrix(lp.A) \ lp.b
    a = solve(lp, LatticePCG(); reltol = 1e-13, abstol = 0.0)
    @test SciMLBase.successful_retcode(a) && norm(a.u .- want) <= 1e-8 * norm(want)
        g = solve(lp, LatticeGMRES(); reltol = 1.0e-12, abstol = 0.0)
        @test SciMLBase.successful_retcode(g) && norm(g.u .- want) <= 1.0e-8 * norm(want)
    # Contraction rho <= 0.25 at rtol = 1e-13 bounds iterations <= ceil(log(1e-13)/log(0.25)) = 22
    @test a.iters <= 22 || (println("F4-08 LatticePCG iterations ", a.iters); false)
    d = solve(lp)                                        # (the default: the owned QuasiSteady)
    @test norm(d.u[1] .- want) <= 1e-6 * norm(want)
    @test occursin("LatticePCG", repr(LatticePCG()))
    # as an OrdinaryDiffEq linear solver for a symmetric `W`
    prob = discretize(qsys(0.02), qdisc(64))
    s = solve(prob, FBDF(; linsolve = LatticePCG()); abstol = 1e-8, reltol = 1e-8)
        sg = solve(prob, FBDF(; linsolve = LatticeGMRES()); abstol = 1.0e-8, reltol = 1.0e-8)
        r = solve(prob, FBDF(; linsolve = KrylovJL_GMRES(; precs = LatticeMultigrid())); abstol = 1.0e-8, reltol = 1.0e-8)
    @test SciMLBase.successful_retcode(s) && maximum(abs, s.u[end] .- r.u[end]) < 1e-6
        @test SciMLBase.successful_retcode(sg) && maximum(abs, sg.u[end] .- r.u[end]) < 1.0e-6
end
end

@testitem "F4-08: SX-18 at 64², OrdinaryDiffEq's ImplicitEuler and Trapezoid" setup = [LP_precond] tags = [:latticepde, :precond] begin
@testset "F4-08: SX-18 at 64², OrdinaryDiffEq's ImplicitEuler and Trapezoid" begin
    f = sin(3t) * x
    prob = discretize(qsys(0.4; f), qdisc(64); sparse = true)
    h = 0.05
    so = solve(prob, ImplicitEuler(); dt = h, adaptive = false, abstol = 1e-12, reltol = 1e-12)
        sb = solve(discretize(qsys(0.4; f), qdisc(64)), BackwardEuler(; linsolve = QTIGHT); dt = h)
    @test maximum(abs, sb.u[end] .- so.u[end]) < 1e-8 || (println("F4-08 IE ", maximum(abs, sb.u[end] .- so.u[end])); false)
    # Crank–Nicolson's damped start is two Backward Euler steps of h/2
    s0 = solve(prob, ImplicitEuler(); dt = h / 2, adaptive = false, abstol = 1e-12, reltol = 1e-12, tspan = (0.0, h))
    st = solve(SciMLBase.remake(prob; u0 = s0.u[end], tspan = (h, 0.4)), Trapezoid(); dt = h, adaptive = false,
        abstol = 1e-12, reltol = 1e-12)
        sc = solve(discretize(qsys(0.4; f), qdisc(64)), CrankNicolson(; linsolve = QTIGHT); dt = h)
    @test maximum(abs, sc.u[end] .- st.u[end]) < 1e-8 || (println("F4-08 TR ", maximum(abs, sc.u[end] .- st.u[end])); false)
end
end

@testitem "F4-08: FBDF matrix-free on the device with LatticeMultigrid" setup = [LP_precond] tags = [:latticepde, :precond] begin
if lowercase(get(ENV, "LATTICEPDE_GPU", "")) == "rocm"
    using AMDGPU: AMDGPU
        @testset "F4-08: FBDF matrix-free on the device with LatticeMultigrid" begin
        dev = AMDGPU.ROCBackend()
        sys = qsys(0.02)
        pd = discretize(sys, LatticeDiscretization(Grid((64, 64)); T = Float32, backend = dev))
        @test pd.f.jac_prototype isa SciMLBase.SciMLOperators.FunctionOperator
        msg = try
            discretize(sys, LatticeDiscretization(Grid((64, 64)); T = Float32, backend = dev); sparse = true)
            ""
        catch e
            sprint(showerror, e)
        end
            @test occursin("jvp", msg)
            alg = FBDF(; linsolve = KrylovJL_GMRES(; precs = LatticeMultigrid()))
        sd = solve(pd, alg; abstol = 1.0f-5, reltol = 1.0f-5)
        ph = discretize(sys, LatticeDiscretization(Grid((64, 64)); T = Float32))
        sh = solve(ph, alg; abstol = 1.0f-5, reltol = 1.0f-5)
        @test SciMLBase.successful_retcode(sd) && maximum(abs, Array(sd.u[end]) .- sh.u[end]) < 1.0f-3
    end
end
end

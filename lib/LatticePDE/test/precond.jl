# F4-08 (F4 design §3.7, SX-15, Q-A (b)): the lattice multigrid as a LinearSolve preconditioner
# (`LatticeMG`) and algorithm (`LatticePCG`). FBDF with GMRES preconditioned by `LatticeMG()`
# at 256² takes far fewer Krylov iterations per linear solve than GMRES alone; `LatticePCG()`
# solves a linear system with no time to the direct solve; the SX-18 oracles move from 8×8 to
# 64² on the sparse Jacobian (OrdinaryDiffEq's ImplicitEuler against BackwardEuler, Trapezoid
# against CrankNicolson); on a device FBDF runs matrix-free with the preconditioner.
# Negative controls: at the base 978e73c7 `LatticeMG` is undefined and `sparse = true` is
# refused (every testset errors); a preconditioner built without the shift `1/γ` fails the
# iteration bound (~/lpwork/f4b3/nc-*.log).
using LinearAlgebra: norm
using SparseArrays: SparseArrays
using LinearSolve: LinearSolve, KrylovJL_GMRES
using OrdinaryDiffEqBDF: FBDF
using OrdinaryDiffEqSDIRK: ImplicitEuler, Trapezoid

@parameters qD = 0.05 qk = 1.0
@variables qc(..) qw(..)
qdom(T) = [t ∈ Interval(0.0, T), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
qsys(T; f = 0.0) = PDESystem([D(qc(t, x, y)) ~ qD * Δ(qc(t, x, y)) - qk * qc(t, x, y) + f],
    [qc(0, x, y) ~ sin(π * x) * cos(π * y), qc(t, 0, y) ~ 1.0], qdom(T), [t, x, y], [qc(t, x, y)], [qD, qk]; name = :qs)
qdisc(n; kw...) = LatticeDiscretization(Grid((n, n)); T = Float64, kw...)
const QTIGHT = DevicePCG(; rtol = 1e-13, budget = 400)

# FBDF with GMRES (and `precs`) on `prob`: the solution and the Krylov iterations per linear solve
function qfbdf(prob; precs = nothing, gmres_restart = 200)
    j = prob.f.jvp
    c0 = j.calls[]
    s = solve(prob, FBDF(; linsolve = KrylovJL_GMRES(; precs, gmres_restart)); abstol = 1e-6, reltol = 1e-6)
    return s, (j.calls[] - c0) / max(s.stats.nsolve, 1)
end

@testset "F4-08: FBDF with GMRES and LatticeMG at 256²" begin
    prob = discretize(qsys(0.5), qdisc(256))
    mg = LatticeMG()
    s1, k1 = qfbdf(prob; precs = mg)
    s0, k0 = qfbdf(prob)
    @info "F4-08 FBDF 256²: Krylov iterations per linear solve, GMRES $(round(k0; digits = 1)), with LatticeMG $(round(k1; digits = 1)); steps $(s0.stats.naccept), $(s1.stats.naccept)"
    @test SciMLBase.successful_retcode(s0) && SciMLBase.successful_retcode(s1)
    @test maximum(abs, s1.u[end] .- s0.u[end]) < 1e-4
    @test k1 <= 4 && k0 >= 5k1 || (println("F4-08 iterations ", (k0, k1)); false)    # (measured 26.5 and 3.4: 7.8×)
    P = only(values(mg.engines))
    @test P isa LFP.MGPreconditioner && P.applies > 0 && isfinite(P.γ)
    @test occursin("LatticeMG(; cycle = (2, 2), cycles = 1)", repr(mg))
    # the documented small memory (`gmres_restart = 10`): the same steps, W builds and iterations
    s2, k2 = qfbdf(prob; precs = LatticeMG(), gmres_restart = 10)
    @test (s2.stats.naccept, s2.stats.nw, s2.stats.nsolve) == (s1.stats.naccept, s1.stats.nw, s1.stats.nsolve) && k2 == k1 ||
          (println("F4-08 gmres_restart 10 ", (s2.stats, k2), " against 200 ", (s1.stats, k1)); false)
end

@testset "F4-08: LatticePCG solves a linear system with no time" begin
    fdom = [x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
    sl = PDESystem([0 ~ 0.3 * Δ(qw(x, y)) - 2.0 * qw(x, y) + x], [qw(0, y) ~ 1.0], fdom, [x, y], [qw(x, y)], Num[]; name = :ql)
    lp = discretize(sl, qdisc(32))
    want = LFP.lattice_matrix(lp.A) \ lp.b
    a = solve(lp, LatticePCG(); reltol = 1e-13, abstol = 0.0)
    @test SciMLBase.successful_retcode(a) && norm(a.u .- want) <= 1e-8 * norm(want)
    @test a.iters <= 16 || (println("F4-08 LatticePCG iterations ", a.iters); false)    # (13 measured)
    d = solve(lp)                                        # (the default: the owned QuasiSteady)
    @test norm(d.u[1] .- want) <= 1e-6 * norm(want)
    @test occursin("LatticePCG", repr(LatticePCG()))
    # as an OrdinaryDiffEq linear solver for a symmetric `W`
    prob = discretize(qsys(0.02), qdisc(64))
    s = solve(prob, FBDF(; linsolve = LatticePCG()); abstol = 1e-8, reltol = 1e-8)
    r = solve(prob, FBDF(; linsolve = KrylovJL_GMRES(; precs = LatticeMG())); abstol = 1e-8, reltol = 1e-8)
    @test SciMLBase.successful_retcode(s) && maximum(abs, s.u[end] .- r.u[end]) < 1e-6
end

@testset "F4-08: SX-18 at 64², OrdinaryDiffEq's ImplicitEuler and Trapezoid" begin
    f = sin(3t) * x
    prob = discretize(qsys(0.4; f), qdisc(64); sparse = true)
    h = 0.05
    so = solve(prob, ImplicitEuler(); dt = h, adaptive = false, abstol = 1e-12, reltol = 1e-12)
    sb = solve(discretize(qsys(0.4; f), qdisc(64)), BackwardEuler(; dt = h, inner = QTIGHT))
    @test maximum(abs, sb.u[end] .- so.u[end]) < 1e-8 || (println("F4-08 IE ", maximum(abs, sb.u[end] .- so.u[end])); false)
    # Crank–Nicolson's damped start is two Backward Euler steps of h/2
    s0 = solve(prob, ImplicitEuler(); dt = h / 2, adaptive = false, abstol = 1e-12, reltol = 1e-12, tspan = (0.0, h))
    st = solve(SciMLBase.remake(prob; u0 = s0.u[end], tspan = (h, 0.4)), Trapezoid(); dt = h, adaptive = false,
        abstol = 1e-12, reltol = 1e-12)
    sc = solve(discretize(qsys(0.4; f), qdisc(64)), CrankNicolson(; dt = h, inner = QTIGHT))
    @test maximum(abs, sc.u[end] .- st.u[end]) < 1e-8 || (println("F4-08 TR ", maximum(abs, sc.u[end] .- st.u[end])); false)
end

if lowercase(get(ENV, "LATTICEPDE_GPU", "")) == "rocm"
    using AMDGPU: AMDGPU
    @testset "F4-08: FBDF matrix-free on the device with LatticeMG" begin
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
        @test occursin("hardware limit", msg) && occursin("jvp", msg)
        alg = FBDF(; linsolve = KrylovJL_GMRES(; precs = LatticeMG()))
        sd = solve(pd, alg; abstol = 1.0f-5, reltol = 1.0f-5)
        ph = discretize(sys, LatticeDiscretization(Grid((64, 64)); T = Float32))
        sh = solve(ph, alg; abstol = 1.0f-5, reltol = 1.0f-5)
        @test SciMLBase.successful_retcode(sd) && maximum(abs, Array(sd.u[end]) .- sh.u[end]) < 1.0f-3
    end
end

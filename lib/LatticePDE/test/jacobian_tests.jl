# F4-07 (F4 design §3.7, AF-01, SX-13): the Jacobian of the right side from the IR. The
# pattern `jacobian_sparsity` reads off the rate program equals the nonzero pattern of the dense
# ForwardDiff Jacobian on 8×8 (at a random state, so no entry is zero by accident) for every
# face kind, an advection row with Robin faces, masks, a `Coarse(2)` field, a hexagonal lattice, a cross-grid read, an aux chain and a
# steady row (a mass-matrix system). `jac = true` gives the dense Jacobian to 1e-12, `jvp` gives
# `J v`, and Rodas5P with `sparse = true` runs at 128² in bounded memory and is the limit of
# the owned BackwardEuler run. The pattern at 128² allocates under 64 MiB (a typed walk).
# Negative controls: at the base 978e73c7 `discretize(…; jac = true)` is refused ("the
# `ODEFunction` keywords `jac` and `sparse` are planned") and `jacobian_sparsity` is undefined,
# so every testset errors; a pattern that reads past a face as if the axis were periodic fails
# the face cases, and one that takes a restriction's third child at every coarse site fails
# `Coarse(2)` (~/lpwork/f4b3/nc-*.log); the untyped walk (`_Walk.k::Any`) allocates 256 MiB at
# 128² and fails the pattern's bound (~/lpwork/f4b3fix/nc-untyped.log).

@testsetup module LP_jacobian
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables, Differential, PDESystem,
                           System, mtkcompile, ODEProblem, unknowns, parameters, ShiftIndex, Shift, Pre,
                           t_nounits as t, D_nounits as D
using Symbolics: Symbolics, Num, Equation, unwrap, simplify, substitute, get_variables
using SymbolicUtils: SymbolicUtils, iscall, operation, arguments, unwrap_const
using DomainSets: Interval
using SciMLBase: SciMLBase
using LatticeFields: LatticeFields, Problems as LFP
include("shared/lp_runner.jl")
include("shared/discretize.jl")
using LinearAlgebra: norm
using SparseArrays: SparseArrays, sparse, nnz
using ForwardDiff: ForwardDiff
using Random: Random
using LatticeFields.IR: HEX
using OrdinaryDiffEqRosenbrock: Rodas5P

@parameters jD = 0.05 ja = 0.7 jb = 0.4
@variables jc(..) jv(..) jk(..)::Int32 [input = true] ja1(..) ja2(..)
jdom(T = 0.1) = [t ∈ Interval(0.0, T), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
jlev(name, k) = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(Symbolics.variables(name,
        T = SymbolicUtils.FnType{Tuple, Real, Nothing}))), LatticePDE.LatticeLevel, Coarse(k)))
const jC2 = jlev(:jcoarse, 2)
const JK1 = Int32[i <= 3 && j >= 6 ? 1 : 0 for i in 1:8, j in 1:8]
jdisc(dims = (8, 8); kw...) = LatticeDiscretization(Grid(dims; kw...); T = Float64)
jsys(eqs, bcs, dvs, ps = [jD]; name = :js) = PDESystem(eqs, bcs, jdom(), [t, x, y], dvs, ps; name)

# the dense Jacobian of the problem's right side at `u` (ForwardDiff)
function jdense(prob, u)
    f = prob.f
    return ForwardDiff.jacobian((du, v) -> f(du, v, prob.p, prob.tspan[1]), similar(u), u)
end
jstate(prob; seed = 1) = (Random.seed!(seed); collect(prob.u0) .+ 0.5 .* rand(length(prob.u0)))

# the systems of the pattern tests: (label, system, discretization, inputs)
function jcases()
    c, v, k = jc(t, x, y), jv(t, x, y), jk(t, x, y)
    Dx, Dy = Differential(x), Differential(y)
    ic = [jc(0, x, y) ~ x + y]
    out = Any[]
    push!(out, ("Dirichlet", jsys([D(c) ~ jD * Δ(c) - c], [ic; jc(t, 0, y) ~ 1.0; jc(t, x, 1) ~ 0.5], [c]), jdisc(), ()))
    push!(out, ("Neumann", jsys([D(c) ~ jD * Δ(c) - c^2], [ic; Dx(jc(t, 1, y)) ~ 0.3], [c]), jdisc(), ()))
    push!(out, ("Robin", jsys([D(c) ~ jD * Δ(c)], [ic; 2.0 * jc(t, x, 0) + Dy(jc(t, x, 0)) ~ 0.5], [c]), jdisc(), ()))
    push!(out, ("periodic", jsys([D(c) ~ jD * Δ(c) + c * (1 - c)], [ic; jc(t, x, 0) ~ jc(t, x, 1); jc(t, 0, y) ~ jc(t, 1, y)], [c]),
        jdisc(), ()))
    push!(out, ("advection, Robin", jsys([D(c) ~ -Advect(Upwind1())([0.3, -0.2], c) + 0.01 * Δ(c)],
        [ic; 2.0 * jc(t, 0, y) + Dx(jc(t, 0, y)) ~ 0.5; 1.5 * jc(t, 1, y) - Dx(jc(t, 1, y)) ~ 0.0; jc(t, x, 0) ~ 1.0], [c], Num[]),
        jdisc(), ()))
    push!(out, ("masks", jsys([D(c) ~ jD * Δ(c) - c], [ic; c ~ masked(k == 1, 2.0)], [c, k]), jdisc(), (k => JK1,)))
    cc = jC2(t, x, y)
    push!(out, ("Coarse(2)", jsys([D(cc) ~ 0.05 * Δ(cc) - cc + ja * v, D(v) ~ 0.02 * Δ(v) - v + jb * cc],
        [jC2(0, x, y) ~ x, jv(0, x, y) ~ y], [cc, v], [ja, jb]), jdisc(), ()))
    push!(out, ("hexagonal", jsys([D(c) ~ jD * Δ(c) - c], [ic; jc(t, 0, y) ~ 1.0], [c]), jdisc(; geometry = HEX), ()))
    push!(out, ("cross-grid", jsys([D(cc) ~ 0.01 * Δ(cc), D(v) ~ 0.5 * Δ(cc) - v], [jC2(0, x, y) ~ x^2, jv(0, x, y) ~ 0.0],
        [cc, v], Num[]), jdisc((16, 16)), ()))
    a1, a2 = ja1(t, x, y), ja2(t, x, y)
    # (an aux field takes no face condition: a spatial operator of one needs periodic axes)
    push!(out, ("aux chain", jsys([a1 ~ Δ(c), a2 ~ a1 * c, D(c) ~ -0.01 * Δ(a2)],
        [ic; jc(t, x, 0) ~ jc(t, x, 1); jc(t, 0, y) ~ jc(t, 1, y)], [c, a1, a2]), jdisc(), ()))
    push!(out, ("steady row", jsys([D(c) ~ jD * Δ(c) - c + v, 0 ~ 0.1 * Δ(v) - v + c], [ic; jc(t, 0, y) ~ 1.0], [c, v]),
        jdisc(), ()))
    return out
end
jprob(sys, disc, ins; kw...) = discretize(sys, disc; inputs = collect(Pair, ins), kw...)
jpattern(J) = sparse(J .!= 0)
include("shared/export_all.jl")
end

@testitem "F4-07: the pattern from the IR equals the dense Jacobian's" setup = [LP_jacobian] tags = [:latticepde, :jacobian] begin
@testset "F4-07: the pattern from the IR equals the dense Jacobian's" begin
    for (label, sys, disc, ins) in jcases()
        prob = jprob(sys, disc, ins)
        P = LFP.jacobian_sparsity(prob)
        u = jstate(prob)
        if label == "masks"
            # a masked site keeps its row (a mask that moves with an input write stays covered):
            # the pattern is the unmasked system's, and holds the masked one's
            free = jprob(sys, disc, (jk(t, x, y) => zeros(Int32, 8, 8),))
            want = jpattern(jdense(free, u))
            got = jpattern(jdense(prob, u))
            @test P == want || (println("F4-07 pattern ", label, ": ", nnz(P), " vs ", nnz(want)); false)
            @test all(P[got])
            @test nnz(got) < nnz(want)                     # control: the masked rows are empty in the run
        else
            want = jpattern(jdense(prob, u))
            @test P == want || (println("F4-07 pattern ", label, ": ", nnz(P), " vs ", nnz(want), " missing ",
                count(want .& .!P), " extra ", count(P .& .!want)); false)
        end
    end
end
end

@testitem "F4-07: jac = true is the dense Jacobian; jvp is J v" setup = [LP_jacobian] tags = [:latticepde, :jacobian] begin
@testset "F4-07: jac = true is the dense Jacobian; jvp is J v" begin
    for (label, sys, disc, ins) in jcases()
        prob = jprob(sys, disc, ins; jac = true, sparse = true)
        @test prob.f.jac_prototype isa SparseArrays.SparseMatrixCSC && prob.f.colorvec isa Vector{Int}
        u = jstate(prob; seed = 2)
        Jd = jdense(prob, u)
        J = copy(prob.f.jac_prototype)
        prob.f.jac(J, u, prob.p, prob.tspan[1])
        @test maximum(abs, Matrix(J) .- Jd) <= 1e-12 * max(1, maximum(abs, Jd)) ||
              (println("F4-07 jac ", label, " ", maximum(abs, Matrix(J) .- Jd)); false)
        Jm = zeros(size(Jd))                               # a dense matrix takes the same entries
        prob.f.jac(Jm, u, prob.p, prob.tspan[1])
        @test Jm == Matrix(J)
        v = randn(length(u))
        Jv = similar(u)
        prob.f.jvp(Jv, v, u, prob.p, prob.tspan[1])
        @test norm(Jv .- Jd * v) <= 1e-12 * max(1, norm(Jd * v))
    end
    # a 5-point stencil takes 5 colors (the lattice coloring `(x + 2y) mod 5`; greedy takes 7)
    prob = jprob(jcases()[1][2:4]...; sparse = true)
    @test maximum(prob.f.colorvec) == 5
    # the default: `jvp` is set, no sparse prototype; a map has no Jacobian
    d = jprob(jcases()[1][2:4]...)
    @test d.f.jvp isa LFP.LatticeJVP && d.f.jac_prototype === nothing
    # the steady-state conversion keeps `jac` and `jvp` in residual form (SciMLBase's own drops
    # the jvp's vector; base a53839b8: "Nonconforming functions detected: jvp")
    jp = jprob(jcases()[1][2:4]...; jac = true, sparse = true)
    nl = SciMLBase.NonlinearProblem(SciMLBase.SteadyStateProblem(jp))
    u, v = jstate(jp), randn(length(jp.u0))
    a, b = similar(u), similar(u)
    nl.f.jvp(a, v, u, nl.p)
    jp.f.jvp(b, v, u, jp.p, Inf)
    @test a == b && nl.f.jac_prototype === jp.f.jac_prototype
    r = similar(u)
    nl.f(r, u, nl.p)
    jp.f(b, u, jp.p, Inf)
    @test r == b
end
end

@testitem "F4-07: Rodas5P with sparse = true at 128² runs in bounded memory" setup = [LP_jacobian] tags = [:latticepde, :jacobian] begin
@testset "F4-07: Rodas5P with sparse = true at 128² runs in bounded memory" begin
    @parameters jr = 2.0
    c = jc(t, x, y)
    sys = PDESystem([D(c) ~ 0.05 * Δ(c) - jr * c], [jc(0, x, y) ~ sin(π * x) * sin(π * y), jc(t, 0, y) ~ 0.0],
        jdom(0.05), [t, x, y], [c], [jr]; name = :jbig)
    prob = discretize(sys, jdisc((128, 128)); sparse = true)
    @test nnz(prob.f.jac_prototype) <= 5 * 128^2
    # the pattern walk is type-stable: ~12 MiB at 128² (an untyped walk, a dynamic dispatch per
    # node visit, allocated 256 MiB)
    pb = @allocated LFP.jacobian_sparsity(prob)
    @test pb < 64 * 2^20 || (println("F4-07 jacobian_sparsity 128² allocated ", pb / 2^20, " MiB"); false)
    s = solve(prob, Rodas5P(); abstol = 1e-8, reltol = 1e-8)              # (warm)
    bytes = @allocated s = solve(prob, Rodas5P(); abstol = 1e-8, reltol = 1e-8)
    @test SciMLBase.successful_retcode(s)
    # a dense Jacobian alone would take 128⁴ × 8 B = 2.1 GB
    @test bytes < 400 * 2^20 || (println("F4-07 Rodas5P 128² allocated ", bytes / 2^20, " MiB"); false)
    # the owned BackwardEuler run tends to it at first order as dt halves
        e(dt) = maximum(
            abs, solve(
                prob, BackwardEuler(; substeps = 1, linsolve = DevicePCG(; reltol = 1.0e-10, maxiters = 200)),
                saveat = 0.05; dt
            ).u[end] .- s.u[end]
        )
    e1, e2, e3 = e(0.01), e(0.005), e(0.0025)
    @test e1 > e2 > e3 && 1.6 < e1 / e2 < 2.4 && 1.6 < e2 / e3 < 2.4 || (println("F4-07 BE errors ", (e1, e2, e3)); false)
end
end

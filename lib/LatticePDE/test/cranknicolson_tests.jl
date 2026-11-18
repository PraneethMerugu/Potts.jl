# F3-10 (F3 design §3.3, §5): `CrankNicolson` in front end B. Each substep solves
# `(u − uⁿ)/h = (r(uⁿ) + r(u))/2` (`r(uⁿ)` at tⁿ, `r(u)` at tⁿ⁺¹) through the implicit runtime with
# the shift `2/h`; a start (init, `reset!`) is damped: two Backward Euler steps of `h/2` at
# tⁿ + h/2 and tⁿ + h, with the same operator. The tests compare with the hand matrices, the
# exact semi-discrete solution, a manufactured solution, step data and OrdinaryDiffEq's
# `Trapezoid`. Base (69bef544, ~/lpwork/f3b4-nc10-base.log): `CrankNicolson` is not defined
# (every testset errors). Negative controls (mutations of this tree, ~/lpwork/f3b4-nc10-*.log):
# no damped start (nodamp), `r(uⁿ)` at tⁿ⁺¹ (stage).

@testsetup module LP_cranknicolson
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
include("shared/problems.jl")
include("shared/bounds.jl")
include("shared/silent.jl")
include("shared/groups.jl")
include("shared/families.jl")
include("shared/odepath.jl")
include("shared/precond.jl")
include("shared/groups_coupling.jl")
include("shared/implicit.jl")
include("shared/robin_site.jl")
include("shared/cranknicolson.jl")
include("shared/export_all.jl")
end

@testitem "F3-10: CrankNicolson: order 2, the manufactured solution, the stages" setup = [LP_cranknicolson] tags = [:latticepde, :cranknicolson] begin
@testset "F3-10: CrankNicolson: order 2, the manufactured solution, the stages" begin
    p, λ, u0 = eig_problem(16)
        err(dt) = maximum(abs, blast(solve(p, CrankNicolson(; linsolve = BTIGHT); dt)) .- exp(0.3λ * 0.4) .* u0)
    es = [err(0.4 / 2^k) for k in 2:5]
    @test all(o -> abs(o - 2) < 0.1, log2.(es[1:(end - 1)] ./ es[2:end]))       # (measured 2.02, 2.01, 2.00)
    # the manufactured solution: `r(uⁿ)` at tⁿ, `r(u)` at tⁿ⁺¹, the damped start at tⁿ + h/2 and tⁿ + h
        em, om = mf_orders(CrankNicolson(; linsolve = BTIGHT), [0.1 / 2^k for k in 0:3])
    @test all(o -> abs(o - 2) < 0.1, om) || (println("CN manufactured orders ", om); false)
    # two windows against the hand matrices: the first is the damped start (two Backward Euler
    # steps of h/2 at h/2 and h), the second a Crank–Nicolson step (r(uⁿ) at h, r(u) at 2h)
    h = 0.1
    p8 = mf_problem(BDIMS)
        u0 = vec(init(p8, CrankNicolson(); dt = h)[bce])
        us, ig = windows(p8, CrankNicolson(; linsolve = BTIGHT), 2; dt = h)
    half(u, tt) = (Lb = mf_rate(tt); (I - h / 2 * Lb[1]) \ (u .+ h / 2 .* Lb[2]))
    w1 = half(half(u0, h / 2), h)
    @test maximum(abs, us[1] .- w1) < 1e-9
    function cn(u, ta, tb)
        La, ba = mf_rate(ta)
        Lb, bb = mf_rate(tb)
        return (I - h / 2 * Lb) \ (u .+ h / 2 .* (La * u .+ ba .+ bb))
    end
    want, wrong = cn(us[1], h, 2h), cn(us[1], 2h, 2h)
    @test maximum(abs, us[2] .- want) < 1e-9 && maximum(abs, us[2] .- wrong) > 1e-3
        @test only(ig.runtimes).cache.newton == 1 && SciMLBase.check_error(ig) == ReturnCode.Success
end
end

@testitem "F3-10: the damped start: step data, `reset!`, no extra rebuild" setup = [LP_cranknicolson] tags = [:latticepde, :cranknicolson] begin
@testset "F3-10: the damped start: step data, `reset!`, no extra rebuild" begin
    # 1D step data at z = h/dx² = 400 (P1 (b)): the total variation after the first step stays
    # ≤ 1 (plain Crank–Nicolson rings, TV 2.86: the nodamp control)
    n = 200
    h = 400 / n^2
    p = step1d(n, h)
        ig = init(p, CrankNicolson(; linsolve = BTIGHT); dt = h)
    step!(ig)
    @test tv1(ig[b1(t, x)]) <= 1 + 1e-9 || (println("TV ", tv1(ig[b1(t, x)])); false)
    # no extra rebuild: the two half steps share the operator (shift 2/h) with the later steps
    c = only(ig.runtimes).cache
    @test c.rebuilds == 1 && !c.start
    for _ in 1:3
        step!(ig)
    end
    @test c.rebuilds == 1 && tv1(ig[b1(t, x)]) <= 1 + 1e-9
    # a state write re-damps (`reset!`): the next window equals a fresh problem's first window
    # from the written state (damped), bitwise
    pe, _, _ = eig_problem(16)
        us, ig = windows(pe, CrankNicolson(; linsolve = BTIGHT), 2; dt = 0.05)
    v = 0.5 .* reshape(us[2], 16, 16) .+ 0.1
    ig[bce] = v
    @test only(ig.runtimes).cache.start
    step!(ig)
        fresh = init(remake(pe; u0 = vec(v)), CrankNicolson(; linsolve = BTIGHT); dt = 0.05)
    step!(fresh)
    @test vec(ig[bce]) == vec(fresh[bce])
    # (a Crank–Nicolson step from the same state differs: the write did restart it)
        nd = init(remake(pe; u0 = vec(v)), CrankNicolson(; linsolve = BTIGHT); dt = 0.05)
    only(nd.runtimes).cache.start = false
    step!(nd)
    @test maximum(abs, vec(nd[bce]) .- vec(fresh[bce])) > 1e-6
    @test bwarm(ig) == 0                                       # the warm window allocates nothing
end
end

@testitem "F3-10: SX-18: OrdinaryDiffEq's Trapezoid with the start replicated" setup = [LP_cranknicolson] tags = [:latticepde, :cranknicolson] begin
@testset "F3-10: SX-18: OrdinaryDiffEq's Trapezoid with the start replicated" begin
    # the `:ode` path: two ImplicitEuler steps of h/2 (the damped start), then Trapezoid at h
        sx = bsys(
            [D(bce) ~ bD * laplacian(bce) - bk * bce + sin(3t) * x], [bc(0, x, y) ~ x * y, bc(t, 0, y) ~ 1.0], [bD, bk];
        T = 0.4, dvs = [bce])
    po = discretize(sx, LatticeDiscretization(Grid((8, 8)); T = Float64))
    h = 0.05
    s0 = solve(po, ImplicitEuler(); dt = h / 2, adaptive = false, abstol = 1e-12, reltol = 1e-12, tspan = (0.0, h))
    st = solve(remake(po; u0 = s0.u[end], tspan = (h, 0.4)), Trapezoid(); dt = h, adaptive = false, abstol = 1e-12,
        reltol = 1e-12)
    sb = solve(discretize(sx, LatticeDiscretization(Grid((8, 8)); T = Float64)),
            CrankNicolson(; linsolve = BTIGHT); dt = h
        )
    @test maximum(abs, vec(blast(sb)) .- st.u[end]) < 1e-8
end
end

@testitem "F3-10: counts, components, parameter writes, messages" setup = [LP_cranknicolson] tags = [:latticepde, :cranknicolson] begin
@testset "F3-10: counts, components, parameter writes, messages" begin
    # the growth rule with the shift 2/h: `+ g c` needs n ≥ ⌈2 · ½ · dt g⌉ (Backward Euler: ⌈2 dt g⌉)
        pg = bown(bsys([D(bce) ~ bD * laplacian(bce) + bk * bce], [bc(0, x, y) ~ x], [bD, bk]))
        @test init(pg, CrankNicolson(); dt = 0.5).substeps == 1 && init(pg, BackwardEuler(); dt = 0.5).substeps == 2
    # components: the operator and the run of the scalar spelling, bitwise
    @variables bu(..)[1:2]
    bue = bu(t, x, y)
        comp = nlsys(
            [D(bue[1]) ~ 0.05 * laplacian(bue[1]) - 40 * bue[1] / (0.025 + bue[1]) + 20, D(bue[2]) ~ 0.05 * laplacian(bue[2]) - bue[2] + bue[1]],
        [bu(0, x, y)[1] ~ 0.5, bu(0, x, y)[2] ~ 0.0], [bue]; T = 0.3)
        scal = nlsys(
            [D(bce) ~ 0.05 * laplacian(bce) - 40 * bce / (0.025 + bce) + 20, D(boe) ~ 0.05 * laplacian(boe) - boe + bce],
        [bc(0, x, y) ~ 0.5, bo(0, x, y) ~ 0.0], [bce, boe]; T = 0.3)
        a = @test_logs min_level = WARN solve(nlown(comp), CrankNicolson(); dt = 0.05)
        b = solve(nlown(scal), CrankNicolson(); dt = 0.05)
        @test LatticePDE.Problems.field_stats(a) == LatticePDE.Problems.field_stats(b) && a.stats.solves > 0
    @test a[bue[1], length(a.t)] == b[bce, length(b.t)] && a[bue[2], length(a.t)] == b[boe, length(b.t)]
    # a parameter write reclassifies as a fresh problem (a Robin face's sign; the count) and
    # restarts (damped), so the written run equals the fresh one
        for alg in (CrankNicolson(; linsolve = BTIGHT),), (v0, v1) in ((-1.0, 1.0), (1.0, -1.0))
        sys0, rb = robin_sys(v0)
            ig = init(nlown(sys0; dims = (10, 8)), alg; dt = 0.1)
        step!(ig)
        u = vec(ig[bce])
        ig.ps[rb] = v1
            fresh = init(remake(nlown(first(robin_sys(v1)); dims = (10, 8)); u0 = u), alg; dt = 0.1)
        c, cf = only(ig.runtimes).cache, only(fresh.runtimes).cache
        @test (c.exact, c.seen, c.newton, c.check, c.start, c.γ) == (cf.exact, cf.seen, cf.newton, cf.check, cf.start, cf.γ)
        @test ig.substeps == fresh.substeps
        step!(ig)
        step!(fresh)
        @test maximum(abs, vec(ig[bce]) .- vec(fresh[bce])) < 1e-12
    end
    # the keywords and messages name the algorithm
    e(f) = try
        f(); ""
    catch err
        err isa ArgumentError ? err.msg : sprint(showerror, err)
    end
    @test startswith(e(() -> CrankNicolson(; newton = 0)), "CrankNicolson: newton = 0 is the Newton iterations")
    @test e(() -> CrankNicolson(; theta = 0.5)) ==
            "CrankNicolson: no keyword `theta`; its keywords are `substeps`, `newton`, `lower_bound`, `linsolve`, `solver_type`, `init` and `compute_type`"
        a = CrankNicolson(; newton = 2, linsolve = DevicePCG(; maxiters = 12))
    @test eval(Meta.parse(repr(a))) == a
        phex = discretize(
            bsys([D(bce) ~ bD * laplacian(bce)], [bc(0, x, y) ~ x], [bD]; dvs = [bce]),
        LatticeDiscretization(Grid((8, 8); geometry = HEX); T = Float64))
        @test solve(phex, CrankNicolson(); dt = 0.1).retcode == ReturnCode.Success     # (F3-20: was refused)
        p16 = discretize(
            bsys([D(bce) ~ bD * laplacian(bce)], [bc(0, x, y) ~ x], [bD]; dvs = [bce]),
        LatticeDiscretization(Grid(BDIMS); T = Float16))
        @test startswith(e(() -> init(p16, CrankNicolson(); dt = 0.1)), "CrankNicolson: the field `bc` holds Float16 and the problem's value type is Float16")
end
end

# Review r2 S2: in front end B a group's count reads the group's own fields: the damped start
# rule of CrankNicolson sees another group's field (it moves between windows, so the group's
# data jump) and the growth rule sees only the group's rows. Base (773f0957,
# ~/lpwork/f3b5-nc-r2-s2.log): the other-group read counts 1 (the jump missed) and the growth
# of `bo` raises both groups' counts to 2.
@testitem "F3-10/11 (r2 S2): B counts read the group's own fields" setup = [LP_cranknicolson] tags = [:latticepde, :cranknicolson] begin
@testset "F3-10/11 (r2 S2): B counts read the group's own fields" begin
        rd = bsys(
            [D(bce) ~ 0.3 * laplacian(bce) - bce + boe, D(boe) ~ 0.3 * laplacian(boe) - boe], [bc(0, x, y) ~ 0.0, bo(0, x, y) ~ 1.0], Any[];
        T = 0.4, dvs = [bce, boe])
    p = discretize(rd, LatticeDiscretization(Grid((8, 8)); T = Float64))
        @test [r.n for r in init(p, FieldGroups(bce => CrankNicolson(), boe => BackwardEuler()); dt = 0.1).runtimes] == [2, 1]
        @test only(init(p, CrankNicolson(); dt = 0.1).runtimes).n == 1          # (the same group: no jump)
        gr = bsys(
            [D(bce) ~ 0.3 * laplacian(bce) - bce + x, D(boe) ~ 0.3 * laplacian(boe) + bk * boe], [bc(0, x, y) ~ 0.0, bo(0, x, y) ~ x], [bk];
        T = 1.0, dvs = [bce, boe])
    p = discretize(gr, LatticeDiscretization(Grid((8, 8)); T = Float64))
        ig = init(p, FieldGroups(bce => BackwardEuler(), boe => BackwardEuler(; linsolve = BTIGHT)); dt = 0.5)
    @test [r.n for r in ig.runtimes] == [1, 2]
    ig.ps[bk] = 4.0                                    # (a write: the counts again, `⌈2 · 0.5 · 4⌉`)
    @test [r.n for r in ig.runtimes] == [1, 4]
end
end

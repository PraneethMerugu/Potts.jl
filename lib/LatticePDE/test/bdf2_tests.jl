# F3-11 (F3 design §3.3, §5): `BDF2` in standalone LatticePDE. Each substep solves
# `(u − (4uⁿ − uⁿ⁻¹)/3)/(2h/3) = r(u)` at tⁿ⁺¹ through the implicit runtime (shift `3/(2h)`); a start
# (init, `reset!`, every change of `h`) is one Backward Euler substep with the Backward Euler
# operator. `uⁿ⁻¹` lives in the runtime's cache, never in the state. Base (the F3-10 commit,
# ~/lpwork/f3b4-nc11-base.log): `BDF2` is not defined (every testset errors). Negative controls
# (mutations, ~/lpwork/f3b4-nc11-*.log): the start from a zero history (zerohist), a change of
# `h` without the restart (norestart).

@testsetup module LP_bdf2
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
using OrdinaryDiffEqBDF: ABDF2

# one Backward Euler substep of `p` from its start state, with the operator rebuilt as BDF2's
# start does
be_first(p, h) = (ig = init(p, BackwardEuler(; linsolve = BTIGHT); dt = h); step!(ig); vec(ig[bce]))
include("shared/export_all.jl")
end

@testitem "F3-11: BDF2: order 2, the manufactured solution, the stage" setup = [LP_bdf2] tags = [:latticepde, :bdf2] begin
@testset "F3-11: BDF2: order 2, the manufactured solution, the stage" begin
    p, λ, u0 = eig_problem(16)
        err(dt) = maximum(abs, blast(solve(p, BDF2(; linsolve = BTIGHT); dt)) .- exp(0.3λ * 0.4) .* u0)
    # (from h = 0.025 down: at h = 0.05 the Backward Euler start's error and BDF2's own cancel, so
    # coarser ladders show orders like 7.1, −0.8; a scalar BDF2 recurrence reproduces them, r1 N1)
    es = [err(0.4 / 2^k) for k in 4:7]
    @test all(o -> abs(o - 2) < 0.1, log2.(es[1:(end - 1)] ./ es[2:end])) || (println("BDF2 heat ", es); false)
        em, om = mf_orders(BDF2(; linsolve = BTIGHT), [0.025 / 2^k for k in 0:3])
    @test all(o -> abs(o - 2) < 0.1, om) || (println("BDF2 manufactured orders ", om); false)
    # two windows against the hand matrices: Backward Euler at h, then BDF2 at 2h
    h = 0.1
    p8 = mf_problem(BDIMS)
        u0 = vec(init(p8, BDF2(); dt = h)[bce])
        us, ig = windows(p8, BDF2(; linsolve = BTIGHT), 2; dt = h)
    L1, b1_ = mf_rate(h)
    @test maximum(abs, us[1] .- (I - h * L1) \ (u0 .+ h .* b1_)) < 1e-9
    L2, b2 = mf_rate(2h)
    want = (I - 2h / 3 * L2) \ ((4 .* us[1] .- u0) ./ 3 .+ 2h / 3 .* b2)
    @test maximum(abs, us[2] .- want) < 1e-9
end
end

@testitem "F3-11: the Backward Euler start: init, reset!, a change of h" setup = [LP_bdf2] tags = [:latticepde, :bdf2] begin
@testset "F3-11: the Backward Euler start: init, reset!, a change of h" begin
    p, _, _ = eig_problem(16)
    h = 0.05
    # the first substep after init is one Backward Euler substep, bitwise (the Backward Euler
    # operator, then the BDF2 one: two rebuilds)
        ig = init(p, BDF2(; linsolve = BTIGHT); dt = h)
    c = only(ig.runtimes).cache
    @test c.start && c.γ == 1.0
    step!(ig)
    @test vec(ig[bce]) == be_first(p, h) && !c.start && c.rebuilds == 1
    step!(ig)
    @test c.γ == 2 / 3 && c.rebuilds == 2
    # … and after `reset!` (a state write): the next substep is Backward Euler from the written state
    v = 0.5 .* reshape(vec(ig[bce]), 16, 16) .+ 0.1
    ig[bce] = v
    @test c.start
    step!(ig)
    @test vec(ig[bce]) == be_first(remake(p; u0 = vec(v)), h) && c.rebuilds == 3
    step!(ig)
    @test c.rebuilds == 4 && c.γ == 2 / 3
    # a change of the substep length restarts it (the formula holds for one h): the window after
    # `substeps` doubles starts with a Backward Euler substep and the run keeps order 2 (without
    # the restart, one halving of h drops BDF2 to order 1: reviewer probe (5), the norestart control)
    function halved(dt)
            ig = init(p, BDF2(; substeps = 1, linsolve = BTIGHT); dt)
        m = ig.nsteps
        for k in 1:m
            k == m ÷ 2 + 1 && (ig.substeps = 2)
            step!(ig)
        end
        return vec(ig[bce])
    end
    _, λ, u0 = eig_problem(16)
    es = [maximum(abs, halved(0.4 / 2^k) .- vec(exp(0.3λ * 0.4) .* u0)) for k in 4:7]
    @test all(o -> abs(o - 2) < 0.15, log2.(es[1:(end - 1)] ./ es[2:end])) || (println("halved orders ", log2.(es[1:(end - 1)] ./ es[2:end])); false)
    # a parameter write that changes the automatic count (the growth rule: n ≥ ⌈2 dt g⌉) restarts
    # too: the written run equals a fresh problem from the written state
    @parameters bg2 = 1.0
        sg = bsys([D(bce) ~ bD * laplacian(bce) + bg2 * bce], [bc(0, x, y) ~ x * y], [bD, bg2]; T = 2.0, dvs = [bce])
    pg = discretize(sg, LatticeDiscretization(Grid(BDIMS); T = Float64))
        ig = init(pg, BDF2(; linsolve = BTIGHT); dt = 0.5)
    @test ig.substeps == 1
    step!(ig); step!(ig)
    u = vec(ig[bce])
    ig.ps[bg2] = 4.0
    @test ig.substeps == 4 && only(ig.runtimes).cache.start
    step!(ig)
        fresh = init(remake(pg; u0 = u, p = [bg2 => 4.0]), BDF2(; linsolve = BTIGHT); dt = 0.5)
    step!(fresh)
    @test vec(ig[bce]) == vec(fresh[bce])
end
end

@testitem "F3-11: the history is not state; positivity is `lower`; SX-18" setup = [LP_bdf2] tags = [:latticepde, :bdf2] begin
@testset "F3-11: the history is not state; positivity is `lower`; SX-18" begin
    p, _, _ = eig_problem(16)
        s = solve(p, BDF2(); dt = 0.05, saveat = 0.1)
    @test all(u -> length(u) == length(p.u0), s.u)
        ig = init(p, BDF2(); dt = 0.05, save_everystep = false)
    step!(ig)
    @test length(ig.store.bufs[fieldid(LFP.field_problem(p).program, "bc")]) == 2                 # (c, c__next): no third buffer
    @test only(ig.runtimes).cache.rows[1].prev isa Vector{Float64}
    @test bwarm(ig) == 0                                       # the warm window allocates nothing
    # a decay with h λ = 10 from a smooth start: the BDF2 right side `(4uⁿ − uⁿ⁻¹)/3` is negative
    # (reviewer probe (1): −0.028); `lower = 0` clips it
        sd = bsys([D(bce) ~ 1.0e-6 * laplacian(bce) - 100.0 * bce], [bc(0, x, y) ~ 1.0], Any[]; T = 0.4, dvs = [bce])
    pd = discretize(sd, LatticeDiscretization(Grid((4, 4)); T = Float64))
        neg = solve(pd, BDF2(); dt = 0.1, saveat = 0.1)
    @test minimum(minimum.(neg.u)) < -0.02
        pos = solve(pd, BDF2(; lower_bound = 0.0); dt = 0.1, saveat = 0.1)
    @test minimum(minimum.(pos.u)) >= 0
        @test minimum(minimum.(solve(pd, BackwardEuler(); dt = 0.1).u)) >= 0      # (Backward Euler needs no clip)
    # SX-18: OrdinaryDiffEq's ABDF2 at a fixed step, whose first step is ImplicitEuler (its
    # `perform_step!` takes the Euler cache at `iter == 1`), as BDF2's start
        sx = bsys(
            [D(bce) ~ bD * laplacian(bce) - bk * bce + sin(3t) * x], [bc(0, x, y) ~ x * y, bc(t, 0, y) ~ 1.0], [bD, bk];
        T = 0.4, dvs = [bce])
    po = discretize(sx, LatticeDiscretization(Grid((8, 8)); T = Float64))
    sa = solve(po, ABDF2(); dt = 0.05, adaptive = false, abstol = 1e-12, reltol = 1e-12)
        sb = solve(discretize(sx, LatticeDiscretization(Grid((8, 8)); T = Float64)), BDF2(; linsolve = BTIGHT); dt = 0.05)
    @test sa.t[end] ≈ 0.4 && maximum(abs, vec(blast(sb)) .- sa.u[end]) < 1e-8
end
end

@testitem "F3-11: components, parameter writes, messages" setup = [LP_bdf2] tags = [:latticepde, :bdf2] begin
@testset "F3-11: components, parameter writes, messages" begin
    @variables bu(..)[1:2]
    bue = bu(t, x, y)
        comp = nlsys(
            [D(bue[1]) ~ 0.05 * laplacian(bue[1]) - 40 * bue[1] / (0.025 + bue[1]) + 20, D(bue[2]) ~ 0.05 * laplacian(bue[2]) - bue[2] + bue[1]],
        [bu(0, x, y)[1] ~ 0.5, bu(0, x, y)[2] ~ 0.0], [bue]; T = 0.3)
        scal = nlsys(
            [D(bce) ~ 0.05 * laplacian(bce) - 40 * bce / (0.025 + bce) + 20, D(boe) ~ 0.05 * laplacian(boe) - boe + bce],
        [bc(0, x, y) ~ 0.5, bo(0, x, y) ~ 0.0], [bce, boe]; T = 0.3)
        a = @test_logs min_level = WARN solve(nlown(comp), BDF2(); dt = 0.05)
        b = solve(nlown(scal), BDF2(); dt = 0.05)
        @test LatticePDE.Problems.field_stats(a) == LatticePDE.Problems.field_stats(b) && a.stats.solves > 0
    @test a[bue[1], length(a.t)] == b[bce, length(b.t)] && a[bue[2], length(a.t)] == b[boe, length(b.t)]
    for (v0, v1) in ((-1.0, 1.0), (1.0, -1.0))
            alg = BDF2(; linsolve = BTIGHT)
        sys0, rb = robin_sys(v0)
            ig = init(nlown(sys0; dims = (10, 8)), alg; dt = 0.1)
        step!(ig); step!(ig)
        u = vec(ig[bce])
        ig.ps[rb] = v1
            fresh = init(remake(nlown(first(robin_sys(v1)); dims = (10, 8)); u0 = u), alg; dt = 0.1)
        c, cf = only(ig.runtimes).cache, only(fresh.runtimes).cache
        @test (c.exact, c.seen, c.newton, c.check, c.start) == (cf.exact, cf.seen, cf.newton, cf.check, cf.start)
        step!(ig); step!(fresh)
        @test maximum(abs, vec(ig[bce]) .- vec(fresh[bce])) < 1e-12
    end
    e(f) = try
        f(); ""
    catch err
        err isa ArgumentError ? err.msg : sprint(showerror, err)
    end
        @test startswith(e(() -> BDF2(; lower_bound = Inf)), "BDF2: lower_bound = Inf must be a finite number")
        a = BDF2(; substeps = 3, lower_bound = 0.0)
    @test eval(Meta.parse(repr(a))) == a
    # the counts are those of the Backward Euler start: `+ g c` needs n ≥ ⌈2 dt g⌉
        pg = bown(bsys([D(bce) ~ bD * laplacian(bce) + bk * bce], [bc(0, x, y) ~ x], [bD, bk]))
        @test init(pg, BDF2(); dt = 0.5).substeps == 2
    ig = @test_logs (:warn, r"^BDF2\(substeps = 1\): field `bc` takes 2 substeps, more than the 1 requested: a local growth") init(pg,
            BDF2(; substeps = 1); dt = 0.5
        )
end
end

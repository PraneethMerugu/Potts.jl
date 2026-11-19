# F2-06 review: every group keeps its own substep count through a rebind; the coupling between
# groups has a bound (ruling K-unsafe); `setu` drops the algorithm's history; the per-group
# counts are reported; the messages print an algorithm in its keyword form.

@testsetup module LP_groups_coupling
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
include("shared/silent.jl")
include("shared/groups.jl")
include("shared/groups_coupling.jl")
include("shared/export_all.jl")
end

@testitem "F2-06 review: each group keeps its count through setp, an input write and a table write" setup = [LP_groups_coupling] tags = [:latticepde, :groups_coupling] begin
@testset "F2-06 review: each group keeps its count through setp, an input write and a table write" begin
    # c decays at a rate read through a kind table; o diffuses (its count is the larger)
        sys = PDESystem(
            [D(pce) ~ -gkc * value_at(gKt, pqe) * pce, D(poe) ~ gDo * laplacian(poe)],
        [gpc(0, x, y) ~ 1.0, gpo(0, x, y) ~ x * y, gpo(t, 0, y) ~ gpo(t, 1, y), gpo(t, x, 0) ~ gpo(t, x, 1),
         gpc(t, 0, y) ~ gpc(t, 1, y), gpc(t, x, 0) ~ gpc(t, x, 1)],
        [t ∈ Interval(0.0, 0.1), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [pce, poe, pqe],
        [gkc, gDo, gKt]; name = :pp)
    p = discretize(sys, LatticeDiscretization(Grid((16, 16)); T = Float64);
        inputs = [pqe => fill(Int32(1), 16, 16)])
        alg = FieldGroups(pce => ExplicitEuler(; substeps = 1), poe => ExplicitEuler())
        ig = init(p, alg; dt = 0.01)
    c0 = LFP.substep_counts(ig)
    @test c0 == [1, 4]                                            # o: ⌈0.01 · 0.3 · 2048 / 1.8⌉ = 4
        @test LFP.substep_counts(init(remake(p; p = [gkc => 0.2]), alg; dt = 0.01)) == c0     # a fresh init
    setp(ig, gkc)(ig, 0.2)                                        # (base: [1, 1], o unstable)
    @test LFP.substep_counts(ig) == c0 && ig.substeps == 1
    ig[pqe] = fill(Int32(2), 16, 16)                              # a bound input
    @test LFP.substep_counts(ig) == c0
    ig.ps[gKt] = [1.5, 2.5]                                          # a table
    @test LFP.substep_counts(ig) == c0
    for _ in 1:5
        step!(ig)
    end
    @test maximum(abs, ig[poe]) <= 1.0                            # o stays bounded (diffusion of x y)
        s = solve(p, alg; dt = 0.01)
    @test LFP.substep_counts(s) == c0 && substep_counts(s)[1] == 1
end
end

@testitem "F2-06 review: the coupling between groups is bounded (K-unsafe: refused with the routes)" setup = [LP_groups_coupling] tags = [:latticepde, :groups_coupling] begin
@testset "F2-06 review: the coupling between groups is bounded (K-unsafe: refused with the routes)" begin
    rp = discretize(rsys(), LatticeDiscretization(Grid((4, 4)); T = Float64))
    # k dt = 3 in two groups (base: counts [1, 1], Success at 3.3e41)
    @test_throws ArgumentError init(rp, rtwo(1); dt = 0.01)
    @test_throws ArgumentError init(rp, rtwo(50); dt = 0.01)
    @test_throws ArgumentError solve(
        rp, FieldGroups(r1e => ExplicitEuler(); default = ExplicitEuler(; substeps = 1)); dt = 0.01
    )
    @test_throws ArgumentError init(rp, ExplicitEuler(); dt = 0.01)   # one group: refused
    # weak coupling (k dt = 0.05): accepted, and the run is the groups stepped one after the other
    wp = remake(rp; p = [gk => 5.0])
        ig = init(wp, rtwo(1); dt = 0.01)
    sol = solve!(ig)
    @test sol.retcode == ReturnCode.Success
    c, o = 1.0, 0.0
    for _ in 1:10
        c = c - 5.0 * 0.01 * o                                    # the c group: o held over the window
        o = o + 5.0 * 0.01 * c                                    # the o group reads the new c (2 substeps, exact)
    end
    @test all(≈(c; rtol = 1e-12), sol[:gr1, end]) && all(≈(o; rtol = 1e-12), sol[:gr2, end])
    @test abs(c - cos(0.5)) < 2e-2 && abs(o - sin(0.5)) < 2e-2    # within the splitting's truncation
    # a parameter change past the limit is refused, atomically
    @test_throws ArgumentError setp(ig, gk)(ig, 300.0)
    @test getp(ig, gk)(ig) == 5.0
    @test_throws ArgumentError init(remake(wp; p = [gk => 300.0]), rtwo(1); dt = 0.01)
end
end

@testitem "F2-06 review: setu drops the history; FieldGroups and clip messages" setup = [LP_groups_coupling] tags = [:latticepde, :groups_coupling] begin
@testset "F2-06 review: setu drops the history; FieldGroups and clip messages" begin
    p = gown(gsys())
        ig = init(p, GStub(0); dt = 0.01)
    c = only(ig.runtimes).cache
    setu(ig, gce)(ig, fill(2.0, 8, 8))                            # (base: no reset)
    @test c.resets == 1 && ig[gce] == fill(2.0, 8, 8)
    # the rate/map mix is refused
    @test_throws ArgumentError init(p, FieldGroups(gce => ExplicitEuler(; substeps = 2), goe => ExplicitMap()); dt = 0.01)
    # a clip that is not finite
    for v in (NaN, Inf, -Inf)
        @test_throws ArgumentError ExplicitEuler(; lower_bound = v)
    end
        @test ExplicitEuler(; lower_bound = -1.0).lower_bound == -1.0                  # control
end
end

@testitem "F2-06 round 2: a one-way chain between groups is not limited (B)" setup = [LP_groups_coupling] tags = [:latticepde, :groups_coupling] begin
@testset "F2-06 round 2: a one-way chain between groups is not limited (B)" begin
    # c decays alone; the reader (u, or a: stepped before c, the groups run in state order, by
    # key) reads c in its own group: block triangular, stable for any split
    for (cfirst, rv, re, rk) in ((true, gwu, wue, "gwu"), (false, gwa, wae, "gwa"))
        sys = PDESystem([D(wce) ~ -0.1 * wce, D(re) ~ gwk * wce - re], [gwc(0, x, y) ~ 1.0, rv(0, x, y) ~ 0.0], GW_DOM,
            [t, x, y], [wce, re], [gwk]; name = :oneway)
        p = discretize(sys, gwdisc())
        for k in (300.0, 3000.0)                                  # k dt = 3 and 30 (refused before round 2)
                alg = FieldGroups(wce => ExplicitEuler(; substeps = 2), re => ExplicitEuler(; substeps = 3))
                ig = init(remake(p; p = [gwk => k]), alg; dt = 0.01)
            @test [rt.keys for rt in ig.runtimes] == (cfirst ? [["gwc"], [rk]] : [[rk], ["gwc"]])
            sol = solve!(ig)
            @test sol.retcode == ReturnCode.Success
            # the groups one after the other, by hand
            nc, nu = cfirst ? (substep_counts(sol)[1], substep_counts(sol)[2]) : (substep_counts(sol)[2], substep_counts(sol)[1])
            @test (nc, nu) == (2, 3)
            c, u = 1.0, 0.0
            for _ in 1:10
                if cfirst
                    for _ in 1:nc; c -= 0.01 / nc * 0.1 * c; end
                    for _ in 1:nu; u += 0.01 / nu * (k * c - u); end
                else
                    c0 = c                                        # the reader steps before the c group
                    for _ in 1:nu; u += 0.01 / nu * (k * c0 - u); end
                    for _ in 1:nc; c -= 0.01 / nc * 0.1 * c; end
                end
            end
            @test all(≈(c; rtol = 1e-12), sol[:gwc, end]) && all(≈(u; rtol = 1e-12), sol[Symbol(rk), end])
            uex = k * (exp(-0.01) - exp(-0.1)) / 0.9               # u' = k e^{-0.1 t} − u
            @test abs(sol[Symbol(rk), end][1] - uex) < 0.1 * uex   # bounded: the first-order split error
        end
    end
end
end

@testitem "F2-06 round 2: loops of groups are limited, chains next to them are not (B)" setup = [LP_groups_coupling] tags = [:latticepde, :groups_coupling] begin
@testset "F2-06 round 2: loops of groups are limited, chains next to them are not (B)" begin
    # a 3-group loop: a reads b, b reads c, c reads a
    sys3 = PDESystem([D(wce) ~ -gwk * woe, D(woe) ~ -gwk * wve, D(wve) ~ gwk * wce],
        [gwc(0, x, y) ~ 1.0, gwo(0, x, y) ~ 0.0, gwv(0, x, y) ~ 0.0], GW_DOM, [t, x, y], [wce, woe, wve], [gwk]; name = :loop3)
    p3 = discretize(sys3, gwdisc())
        three = FieldGroups(
            wce => ExplicitEuler(; substeps = 1), woe => ExplicitEuler(; substeps = 2),
            wve => ExplicitEuler(; substeps = 3)
        )
        e = gwerr(() -> init(p3, three; dt = 0.01))
    @test occursin("read one another in a loop", e) && occursin("`gwc`, `gwo`, `gwv`", e) &&
          occursin("dt · Σ max|coefficient| = 3.0 > 1", e)
        @test solve(remake(p3; p = [gwk => 5.0]), three; dt = 0.01).retcode == ReturnCode.Success          # k dt = 0.05
    # a loop (c, o: the rotation at gwr) and a chain out of it (u reads c at gwk)
    sysc = PDESystem([D(wce) ~ -gwr * woe, D(woe) ~ gwr * wce, D(wue) ~ gwk * wce - wue],
        [gwc(0, x, y) ~ 1.0, gwo(0, x, y) ~ 0.0, gwu(0, x, y) ~ 0.0], GW_DOM, [t, x, y], [wce, woe, wue], [gwk, gwr];
        name = :loopchain)
    pc = discretize(sysc, gwdisc())
        algc = FieldGroups(
            wce => ExplicitEuler(; substeps = 1), woe => ExplicitEuler(; substeps = 2),
            wue => ExplicitEuler(; substeps = 3)
        )
    # u's κ = 3 (not in the loop), the loop's 0.05: accepted
        @test solve(pc, algc; dt = 0.01).retcode == ReturnCode.Success
        ig = init(pc, algc; dt = 0.01)
    setp(ig, gwk)(ig, 3000.0)                                     # u's κ = 30: still accepted
    @test getp(ig, gwk)(ig) == 3000.0
    # the loop past the limit (gwr dt = 3): refused, naming the loop's fields only
    e = gwerr(() -> setp(ig, gwr)(ig, 300.0))
    @test occursin("the groups of `gwc`, `gwo` read one another in a loop", e) && !occursin("gwu", e)
    @test getp(ig, gwr)(ig) == 5.0                                # atomic
end
end

@testitem "F2-06 round 3: an unseen term that reads another field counts as reading every group (B)" setup = [LP_groups_coupling] tags = [:latticepde, :groups_coupling] begin
@testset "F2-06 round 3: an unseen term that reads another field counts as reading every group (B)" begin
    # c's rate has a nonlinear term that reads o (unseen: the bound does not record what it
    # reads); o decays alone, u reads c. The true graph is the chain o → c → u, but c counts as
    # reading every group, so c ⇄ u is a loop and u's κ is limited (conservative), with the cause
    sys = PDESystem([D(wce) ~ -0.1 * wce - 1e-9 * wce * woe^2, D(woe) ~ -woe, D(wue) ~ gwk * wce - wue],
        [gwc(0, x, y) ~ 1.0, gwo(0, x, y) ~ 1.0, gwu(0, x, y) ~ 0.0], GW_DOM, [t, x, y], [wce, woe, wue], [gwk];
        name = :unseen)
    p = discretize(sys, gwdisc())
        alg = FieldGroups(
            wce => ExplicitEuler(; substeps = 2), woe => ExplicitEuler(; substeps = 1),
            wue => ExplicitEuler(; substeps = 3)
        )
        e = gwerr(() -> init(p, alg; dt = 0.01))
    @test occursin("the groups of `gwc`, `gwu` read one another in a loop", e) && occursin("dt · Σ max|coefficient| = 3.0", e) &&
          occursin("the terms of `gwc` that the bound cannot see and that read another field count as reading every other group", e)
        @test solve(remake(p; p = [gwk => 50.0]), alg; dt = 0.01).retcode == ReturnCode.Success          # κ = 0.5
end
end

@testitem "F2-06 round 3: an unseen term on the row's own field couples no group (B)" setup = [LP_groups_coupling] tags = [:latticepde, :groups_coupling] begin
@testset "F2-06 round 3: an unseen term on the row's own field couples no group (B)" begin
    # `-a^3` reads only a: the chain a → c is one-way (k dt = 3; refused in round 2)
    for selfterm in (-wae^3, -0.1 * wae - 1e-9 * wae^3)
        sys = PDESystem([D(wae) ~ selfterm, D(woe) ~ -woe, D(wce) ~ gwk * wae - wce],
            [gwa(0, x, y) ~ 1.0, gwo(0, x, y) ~ 1.0, gwc(0, x, y) ~ 0.0], GW_DOM, [t, x, y], [wae, woe, wce], [gwk];
            name = :selfsrc)
        p = discretize(sys, gwdisc())
            alg = FieldGroups(
                wae => ExplicitEuler(; substeps = 2), woe => ExplicitEuler(; substeps = 1),
                wce => ExplicitEuler(; substeps = 3)
            )
            sol = solve(p, alg; dt = 0.01)
        @test sol.retcode == ReturnCode.Success
        @test 0 < sol[:gwc, end][1] < 300 * 0.1                    # bounded by k t max a
    end
end
end

@testitem "F2-06 round 3: a loop counts only the reads inside it (B)" setup = [LP_groups_coupling] tags = [:latticepde, :groups_coupling] begin
@testset "F2-06 round 3: a loop counts only the reads inside it (B)" begin
    # a is a one-way source (k dt = 3) of the loop b ⇄ c (w dt = 0.005): accepted (refused in round 2)
    @parameters gxk = 300.0 gxw = 0.5
    @variables gxa(..) gxb(..) gxc(..)
    xa, xb, xc = gxa(t, x, y), gxb(t, x, y), gxc(t, x, y)
    sys = PDESystem([D(xa) ~ -xa, D(xb) ~ gxk * xa - gxw * xc, D(xc) ~ gxw * xb],
        [gxa(0, x, y) ~ 1.0, gxb(0, x, y) ~ 0.0, gxc(0, x, y) ~ 0.0], GW_DOM, [t, x, y], [xa, xb, xc], [gxk, gxw]; name = :chainloop)
    p = discretize(sys, gwdisc())
        alg = FieldGroups(
            xa => ExplicitEuler(; substeps = 1), xb => ExplicitEuler(; substeps = 2),
            xc => ExplicitEuler(; substeps = 3)
        )
        sol = solve(p, alg; dt = 0.01)
    @test sol.retcode == ReturnCode.Success && substep_counts(sol) == [1, 2, 3]
    a, b, c = 1.0, 0.0, 0.0                                       # the groups in state order, by hand
    for _ in 1:10
        a -= 0.01 * a
        for _ in 1:2; b += 0.005 * (300 * a - 0.5 * c); end
        for _ in 1:3; c += 0.01 / 3 * 0.5 * b; end
    end
    @test all(≈(a; rtol = 1e-12), sol[:gxa, end]) && all(≈(b; rtol = 1e-12), sol[:gxb, end]) &&
          all(≈(c; rtol = 1e-12), sol[:gxc, end])
    # a strong loop (w dt = 3) is still refused: κ is the loop's own 3.0 (not 3 + 3), naming b and c only
        e = gwerr(() -> init(remake(p; p = [gxw => 300.0]), alg; dt = 0.01))
    @test occursin("the groups of `gxb`, `gxc` read one another in a loop", e) &&
          occursin("dt · Σ max|coefficient| = 3.0 >", e) && occursin("the coefficient `-gxw` of `gxc`", e) && !occursin("gxa", e)
end
end

@testitem "F2-06 round 2: following the printed routes is accepted (B)" setup = [LP_groups_coupling] tags = [:latticepde, :groups_coupling] begin
@testset "F2-06 round 2: following the printed routes is accepted (B)" begin
    rp = discretize(rsys(), LatticeDiscretization(Grid((4, 4)); T = Float64))
    for k in (150.0, 1 / 0.0033335, 300.0, 7.0e3 / 3, 1234.5)
        pk = remake(rp; p = [gk => k])
            e = gwerr(() -> init(pk, rtwo(1); dt = 0.01))
        @test occursin("> 1", e)
        # the limit, verbatim (rounded down), with a time span it divides
        lim = gwnum(e, "dt ≤")
        @test lim * k <= 1
        @test init(remake(pk; tspan = (0.0, 10lim)),
                FieldGroups(r1e => ExplicitEuler(; substeps = 1), r2e => ExplicitEuler(; substeps = 2)); dt = lim
            ) isa
              LFP.FieldIntegrator
        # a dt that divides the time span, verbatim (`dt = 0.1/30`)
        m = match(r"such as dt = ([0-9.]+)/([0-9]+)", e)
        dt = parse(Float64, m.captures[1]) / parse(Int, m.captures[2])
            sol = solve(pk, FieldGroups(r1e => ExplicitEuler(; substeps = 1), r2e => ExplicitEuler(; substeps = 2)); dt)
        @test sol.retcode == ReturnCode.Success
        # route 1: the rotation's rows are not dominant, so the message asks for an explicit count, which runs
        @test occursin("in one group with an explicit count", e)
            @test init(pk, ExplicitEuler(; substeps = 400); dt = 0.01) isa LFP.FieldIntegrator
    end
    # route 1 when the merged rows are dominant: the count can be automatic, and it is
    sysd = PDESystem([D(r1e) ~ -10gk * r1e - gk * r2e, D(r2e) ~ gk * r1e - 10gk * r2e], [gr1(0, x, y) ~ 1.0, gr2(0, x, y) ~ 0.0],
        GW_DOM, [t, x, y], [r1e, r2e], [gk]; name = :dom)
    pd = discretize(sysd, LatticeDiscretization(Grid((4, 4)); T = Float64))
        e = gwerr(() -> init(pd, rtwo(1); dt = 0.01))
    @test occursin("in one group (one algorithm; its count can be automatic)", e)
        @test solve(pd, ExplicitEuler(); dt = 0.01).retcode == ReturnCode.Success
end
end

@testitem "F2-06 round 2: the message prints the user's text and a short dt (B)" setup = [LP_groups_coupling] tags = [:latticepde, :groups_coupling] begin
@testset "F2-06 round 2: the message prints the user's text and a short dt (B)" begin
    @parameters gwKt[1:2] = [1.0, 2.0]
    @variables gwq(..)::Int32 [input = true, bounds = (1, 2)]
    qe = gwq(t, x, y)
        sys = PDESystem(
            [D(wce) ~ -value_at(gwKt, qe) * woe, D(woe) ~ 0.1 * wce], [gwc(0, x, y) ~ 1.0, gwo(0, x, y) ~ 0.0],
        [t ∈ Interval(0.0, 0.1), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [wce, woe, qe], [gwKt];
        name = :tabtext)
    p = discretize(sys, gwdisc(); inputs = [qe => fill(Int32(1), 4, 4)])
    dt = 0.1 / 30
        ig = init(p, FieldGroups(wce => ExplicitEuler(; substeps = 1), woe => ExplicitEuler(; substeps = 2)); dt)
    e = gwerr(() -> (ig.ps[gwKt] = [500.0, 2.0]))
        @test occursin("the coefficient `-value_at(gwKt, gwq)` of `gwo`", e) && !occursin("LatticePDE.", e) && !occursin("(t, x, y)", e)
    @test occursin("dt = 0.00333333:", e)
    @test substep_counts(ig) == [1, 2]                            # exported from LatticePDE
end
end

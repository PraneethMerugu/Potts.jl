# A loop of field groups coupled only through terms
# the stability bound cannot see has κ = 0 over the seen cross terms, so the coupling rule
# never checks its lag; `init` (and each parameter write that recounts) warns once per loop,
# naming the loop's fields and the unseen cross terms, with the routes, and never refuses.
# `field_report`'s κ line says the same. Negative control at 9347add7:
# no such warning is given. The
# trigger reads each unseen term's own reads; negative control at c0673406:
# an out-of-loop read warns, the conservative chain has the
# loop wording, a self-only term is listed, an aux read's route names the aux.

@testsetup module LP_unseen_loop
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
include("shared/params.jl")
include("shared/families.jl")
include("shared/odepath.jl")
include("shared/precond.jl")
include("shared/groups_coupling.jl")
include("shared/implicit.jl")
include("shared/robin_site.jl")
include("shared/grids.jl")
include("shared/maskswitch.jl")
include("shared/coupled.jl")
include("shared/numbers.jl")
include("shared/coarse.jl")
include("shared/report.jl")
include("shared/unseen_loop.jl")
include("shared/export_all.jl")
end

@testitem "a loop coupled only through unseen terms warns once, and runs as before" setup = [LP_unseen_loop] tags = [:latticepde, :unseen_loop] begin
using .LP_unseen_loop: fd
    @testset "a loop coupled only through unseen terms warns once, and runs as before" begin
    p = discretize(gsys(su, sv, sue, sve; name = :gs13c), LatticeDiscretization(Grid((12, 12))))
        alg = FieldGroups(sue => ExplicitEuler(; substeps = 4), sve => BackwardEuler())
    local ig
        w = loopwarns(() -> (ig = init(p, alg; dt = 1.0)))
    @test w == ["the groups of `su`, `sv` read one another in a loop through terms the stability bound cannot see: " *
                "κ = dt · rate = 0.0; κ covers only the cross terms the bound sees (unseen: su: -su*(sv^2), sv: su*(sv^2)), " *
                "so the lag between the groups (each reads the others' fields held over each window dt = 1.0) is not checked, " *
                "and a large dt can make the run inaccurate without making it unstable. Step `su`, `sv` in one group, or " *
                "declare intervals (`bounds = (lo, hi)`) for `su`, `sv`, so the bound sees them"]
    # once per loop: a second init, a solve and a parameter write that recounts do not warn again
    local s1
        @test isempty(loopwarns(() -> (s1 = solve(p, alg; dt = 1.0))))
    @test isempty(loopwarns(() -> (ig.ps[sF] = 0.036)))
    # never refused, and the run is the run it was (the warning changes nothing)
        s2 = solve(p, alg; dt = 1.0)
    @test s1.retcode == ReturnCode.Success && s1.u == s2.u
        @test swarm(init(p, alg; dt = 1.0, save_everystep = false)) == 0
    # the report's κ line says what the warning says
    rep = sprint(field_report, s1)
    @test occursin("group 1: loop [1, 2], κ = dt · rate = 1.0 × 0.0 = 0.0 (≤ 1); κ covers only the cross terms the bound " *
                   "sees (unseen: su: -su*(sv^2), sv: su*(sv^2))", rep)
end
end

@testitem "no warning for one group, for a loop the bound sees, or with intervals that let it see the terms" setup = [LP_unseen_loop] tags = [:latticepde, :unseen_loop] begin
using .LP_unseen_loop: fd
    @testset "no warning for one group, for a loop the bound sees, or with intervals that let it see the terms" begin
    # one group: no loop between groups
    p1 = discretize(gsys(su, sv, sue, sve; name = :gs13c1), LatticeDiscretization(Grid((10, 10))))
        @test isempty(loopwarns(() -> init(p1, BackwardEuler(); dt = 1.0)))
    # a loop whose cross terms the bound sees (`ra o`, `0.1 c`)
    @parameters sa = 0.3 sb = 0.2
    @variables sc(..) so(..)
    sce, soe = sc(t, x, y), so(t, x, y)
        ps = discretize(
            PDESystem(
                [D(sce) ~ laplacian(sce) + sa * soe, D(soe) ~ -sb * soe + 0.1 * sce],
        [sc(0, x, y) ~ x * y, so(0, x, y) ~ 1.0 + x, sc(t, 0, y) ~ sc(t, 1, y), sc(t, x, 0) ~ sc(t, x, 1),
         so(t, 0, y) ~ so(t, 1, y), so(t, x, 0) ~ so(t, x, 1)], sdom(0.1), [t, x, y], [sce, soe], [sa, sb]; name = :seen13c),
        LatticeDiscretization(Grid((8, 8))))
        @test isempty(loopwarns(() -> init(ps, FieldGroups(sce => ExplicitEuler(), soe => BackwardEuler()); dt = 0.01)))
    # declared intervals: the bound sees `u v²` (its coefficients bounded over the intervals), so
    # κ > 0 is checked (at dt = 1 it is 2 > 1 and refused; at dt = 0.25 it is 0.5) and nothing is unseen
    pb = discretize(gsys(bu, bv, bue, bve; name = :gs13cb), LatticeDiscretization(Grid((12, 12))))
        algb = FieldGroups(bue => ExplicitEuler(; substeps = 4), bve => BackwardEuler())
        @test isempty(loopwarns(() -> init(pb, algb; dt = 0.25)))
        rb = sprint(io -> field_report(io, pb, algb; dt = 0.25))
    κ = parse(Float64, match(r"group 1: loop \[1, 2\], κ = dt · rate = 0\.25 × [0-9.e-]+ = ([0-9.e-]+)", rb).captures[1])
        @test κ > 0 && !occursin("κ covers only", rb) && init(pb, algb; dt = 0.25) isa LFP.FieldIntegrator
end
end

@testitem "the trigger reads each unseen term's own reads" setup = [LP_unseen_loop] tags = [:latticepde, :unseen_loop] begin
using .LP_unseen_loop: fd
    @testset "the trigger reads each unseen term's own reads" begin
    sdisc = LatticeDiscretization(Grid((8, 8)))
    per(fs...) = reduce(vcat, [[f(t, 0, y) ~ f(t, 1, y), f(t, x, 0) ~ f(t, x, 1)] for f in fs])
    # S1: a loop a ⇄ b closed by seen reads; a's unseen term reads c, outside the loop: no warning
    @variables oa(..) ob(..) oc(..)
    oae, obe, oce = oa(t, x, y), ob(t, x, y), oc(t, x, y)
        po = discretize(
            PDESystem(
                [D(oae) ~ laplacian(oae) + 0.3 * obe - 0.001 * oae * oce^2, D(obe) ~ -0.2 * obe + 0.1 * oae, D(oce) ~ -0.5 * oce],
        [[oa(0, x, y) ~ x, ob(0, x, y) ~ 1.0, oc(0, x, y) ~ 1.0]; per(oa, ob, oc)], sdom(0.1), [t, x, y], [oae, obe, oce], Num[];
        name = :out13c), sdisc)
        algo = FieldGroups(oae => ExplicitEuler(; substeps = 4), obe => BackwardEuler(), oce => ExplicitEuler())
        @test isempty(loopwarns(() -> init(po, algo; dt = 0.01)))
        @test !occursin("κ covers only", sprint(io -> field_report(io, po, algo; dt = 0.01)))
    # S1: the loop exists only because the unseen term counts as reading every group (a chain
    # z → c → u): the conservative wording
    @variables zc(..) zu(..) zz(..)
    zce, zue, zze = zc(t, x, y), zu(t, x, y), zz(t, x, y)
    pz = discretize(PDESystem([D(zce) ~ -0.1 * zce - 1.0e-9 * zce * zze^2, D(zue) ~ 3.0 * zce - zue, D(zze) ~ -0.5 * zze],
        [[zc(0, x, y) ~ 1.0, zu(0, x, y) ~ 0.0, zz(0, x, y) ~ 1.0]; per(zc, zu, zz)], sdom(0.1), [t, x, y], [zce, zue, zze], Num[]; name = :chain13c), sdisc)
        algz = FieldGroups(zce => ExplicitEuler(; substeps = 2), zue => BackwardEuler(), zze => ExplicitEuler())
        @test loopwarns(() -> init(pz, algz; dt = 0.01)) ==
          ["a term the bound cannot see (zc: -1.0e-9zc*(zz^2)) counts as reading every group, so `zc`, `zu` are checked as a " *
           "loop; κ = dt · rate = 0.0 covers only the seen terms, so the lag between the groups (each reads the others' fields " *
           "held over each window dt = 0.01) is not checked, and a large dt can make the run inaccurate without making it " *
           "unstable. Step `zc`, `zu` in one group, or declare intervals (`bounds = (lo, hi)`) for `zc`, `zz`, so the bound sees them"]
    # S2: a term on its own field alone (`-ta³`) is not listed
    @variables ta(..) tb(..)
    tae, tbe = ta(t, x, y), tb(t, x, y)
        pt = discretize(
            PDESystem(
                [D(tae) ~ laplacian(tae) - 0.1 * tae * tbe^2 - tae^3, D(tbe) ~ -0.2 * tbe + 0.1 * tae],
        [[ta(0, x, y) ~ x, tb(0, x, y) ~ 1.0]; per(ta, tb)], sdom(0.1), [t, x, y], [tae, tbe], Num[]; name = :self13c), sdisc)
        wt = loopwarns(() -> init(pt, FieldGroups(tae => ExplicitEuler(; substeps = 4), tbe => BackwardEuler()); dt = 0.01))
    @test length(wt) == 1 && occursin("(unseen: ta: -0.1ta*(tb^2)), so", wt[1]) && !occursin("ta^3", wt[1])
    # N1: an unseen read of an aux field `K ~ a b`: the route names the state fields the aux reads
    @variables xa(..) xb(..) xK(..)
    xae, xbe, xKe = xa(t, x, y), xb(t, x, y), xK(t, x, y)
        px = discretize(
            PDESystem(
                [D(xae) ~ laplacian(xae) + 0.5 * xKe, D(xbe) ~ -0.2 * xbe + 0.1 * xae, xKe ~ xae * xbe],
        [[xa(0, x, y) ~ x, xb(0, x, y) ~ 1.0]; per(xa, xb)], sdom(0.1), [t, x, y], [xae, xbe, xKe], Num[]; name = :aux13c), sdisc)
        wx = loopwarns(() -> init(px, FieldGroups(xae => ExplicitEuler(; substeps = 4), xbe => BackwardEuler()); dt = 0.01))
    @test length(wx) == 1 && endswith(wx[1], "declare intervals (`bounds = (lo, hi)`) for `xa`, `xb`, so the bound sees them")
end
end

# Standalone LatticePDE: `field_report` prints each field group's policy
# (algorithm, window, substep count and its cause, bound, number types, the implicit facts)
# and a run's counters, for problems, owned integrators and solutions, and SciML solves. It
# reads what the objects hold: a warm `step!` still allocates nothing after a report.
# Negative controls: at 4d025fa8 (~/lpwork/f4-13b/nc-base.log) `field_report` is not defined;
# at 3e4dd1f8 (nc-fix.log) `field_report(prob, alg)` and `sol.stats.implicit` are missing; at
# 48d6a305 (nc-rev.log) the review's cases fail on their text: a coupled solve's operator
# reads "inexact … ρ_in = 5.0", an unseen term "ρ_in = 0.0", κ with an unseen cross term has no
# note, a bound that reads the time takes the last window's count, local rows print a PCG, an
# unbounded explicit group prints "0 substeps", `field_report(prob, alg)` without `io` is a
# MethodError.

@testsetup module LP_report
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
include("shared/export_all.jl")
end

@testitem "F4-13: field_report of an explicit group: the count and its cause (bound, user minimum, both)" setup = [LP_report] tags = [:latticepde, :report] begin
using .LP_report: fd
@testset "F4-13: field_report of an explicit group: the count and its cause (bound, user minimum, both)" begin
    # §7.4 at 512²: 12 substeps of the bound (the count the device test checks)
    p = rprob(512; T = 0.02)
        ig = init(p, ExplicitEuler(); dt = 0.01)
    rep = sprint(field_report, ig)
    @test substep_counts(ig) == [12]
        @test occursin("Field report: owned integrator, ExplicitEuler()", rep)
        @test occursin("group 1 of 1: rc (ExplicitEuler())", rep)
    @test rline(rep, "window") == "  window     dt = 0.01, 12 substeps (h = 0.000833333)"
    s = rline(rep, "substeps")
    @test occursin("the bound, ⌈dt ρ / 1.8⌉ = ⌈0.01 × ", s) && endswith(s, "/ 1.8⌉ = 12 [bound]")
    @test startswith(rline(rep, "bound"), "  bound      ρ = ")
    @test rline(rep, "numbers") == "  numbers    state Float64, compute Float64"
    @test rline(rep, "run") == "  run        0 windows; status Success"
    @test rline(rep, "launches") == "  launches   1 per substep; no fusion decision (one kernel)"
        @test rline(rep, "linsolve") == ""                       # (explicit: no implicit lines)
    # batch-end review S1, S5: no route at 12 substeps; at ten times the window the bound sets 117,
    # and the route gives BackwardEuler's count. The bound line splits ρ into the parts of its
    # row (base ab34e226, ~/lpwork/f4BE/nc.log: no route line, no parts)
    @test rline(rep, "route") == ""
        r = sprint(field_report, init(p, ExplicitEuler(); dt = 0.1))
    @test occursin("117 substeps", rline(r, "window"))
    m = match(r"^  route      BackwardEuler\(\) steps this group in (\d+) substeps?$", rline(r, "route"))
    @test m !== nothing && parse(Int, m.captures[1]) < 117 || (println(r); false)
    @test occursin(r"^  bound      ρ = \S+ \(row rc: diffusion \S+, reaction 0\.1\)$", rline(rep, "bound")) || (println(rep); false)
    # (review N1: no empty clause, no canonical bracket; about ten lines per group)
    @test !occursin("none", rep) && !occursin("[ExplicitEuler(", rep)
    @test count(==('\n'), split(rep, "group 1 of 1")[2]) <= 10
    # the user minimum above the bound, the user minimum equal to it, and the bound above it
    for (m, cause, n) in ((50, "[user]", 50), (12, "[both]", 12), (4, "[bound]", 12))
            r = sprint(field_report, init(p, ExplicitEuler(; substeps = m); dt = 0.01))
        @test endswith(rline(r, "substeps"), cause) && occursin("$n substeps", rline(r, "window"))
        @test occursin("substeps = $m", rline(r, "substeps"))
    end
    # the report reads the integrator and changes nothing: the run after it is the run without it
        a, b = init(p, ExplicitEuler(); dt = 0.01), init(p, ExplicitEuler(); dt = 0.01)
    sprint(field_report, a)
    step!(a)
    step!(b)
        @test a.u == b.u && a.retcode == b.retcode == ReturnCode.Default        # both in progress
end
end

@testitem "F4-13: a warm step! allocates nothing after a report, and the run is unchanged (explicit, BE)" setup = [LP_report] tags = [:latticepde, :report] begin
using .LP_report: fd
@testset "F4-13: a warm step! allocates nothing after a report, and the run is unchanged (explicit, BE)" begin
    p = rprob(32)
        for alg in (ExplicitEuler(), BackwardEuler())
            ig, ref = init(p, alg; dt = 0.01, save_everystep = false), init(p, alg; dt = 0.01, save_everystep = false)
        before = rwarm(ig)
        rwarm(ref)
        sprint(field_report, ig)
        after = rwarm(ig)
        rwarm(ref)
        @test before == 0 && after == 0
        @test ig.u == ref.u                                 # bitwise
    end
end
end

@testitem "F4-13: field_report of a Backward Euler group: inner, multigrid levels, the Newton count" setup = [LP_report] tags = [:latticepde, :report] begin
using .LP_report: fd
@testset "F4-13: field_report of a Backward Euler group: inner, multigrid levels, the Newton count" begin
    p = rprob(32)
        ig = init(p, BackwardEuler(); dt = 0.01)
    step!(ig)
    rep = sprint(field_report, ig)
        @test occursin("group 1 of 1: rc (BackwardEuler())", rep)
    @test endswith(rline(rep, "substeps"), "[least]") && occursin("the least count 1", rline(rep, "substeps"))
    c = only(ig.runtimes).cache
    sv = only(r.solver for r in c.rows)
    @test length(sv.prog.hierarchy) > 1
        @test rline(rep, "linsolve") == "  linsolve   LatticePCG() (`linsolve = :auto`), multigrid levels $(length(sv.prog.hierarchy))"
        @test rline(rep, "numbers") == "  numbers    state Float64, compute Float64, solver $(sv.T) (`solver_type = :auto`)"
    @test rline(rep, "newton") == "  newton     1, automatic: the operator is exact" && c.newton == 1
    @test rline(rep, "operator") == "  operator   J̃ exact"
    @test rline(rep, "run") == "  run        1 window; 1 solve; status Success"
    # a given count and inner print as given, in keyword form
        r2 = sprint(field_report, init(p, BackwardEuler(; nlsolve = LatticeNewton(; max_iter = 3), substeps = 2, linsolve = LatticeMultigrid(; cycles = 2)); dt = 0.01))
        @test rline(r2, "newton") == "  newton     3: given (`nlsolve = LatticeNewton(; max_iter = 3)`)"
    # (as resolved: `cycles = k` sets the budget)
        @test startswith(rline(r2, "linsolve"), "  linsolve   LatticeMultigrid(; cycles = 2, maxiters = 2), multigrid levels") && !occursin("linsolve = :auto", r2)
    @test endswith(rline(r2, "substeps"), "[user]") && occursin("2 substeps", rline(r2, "window"))
end
end

@testitem "F4-13: field_report of groups: two algorithms, and the coupling rule's κ" setup = [LP_report] tags = [:latticepde, :report] begin
using .LP_report: fd
@testset "F4-13: field_report of groups: two algorithms, and the coupling rule's κ" begin
    p = discretize(rsys2(), LatticeDiscretization(Grid((8, 8))))
        ig = init(p, FieldGroups(rce => ExplicitEuler(), roe => BackwardEuler()); dt = 0.01)
    step!(ig)
    rep = sprint(field_report, ig)
        @test occursin("Field report: owned integrator, FieldGroups(rc => ExplicitEuler(), ro => BackwardEuler())", rep)
    @test occursin("group 1 of 2: rc (ExplicitEuler", rep) && occursin("group 2 of 2: ro (BackwardEuler", rep)
    @test occursin("substep counts rc 3, ro 1", rline(rep, "counters"))      # (review N2: by group)
    @test endswith(rline(rep, "substeps"), "= 3 [bound]") && rline(rep, "bound") == "  bound      ρ = 512.0 (row rc: diffusion 512.0)"   # (Δ on 8²: 8/h² = 512)
        @test rline(rep, "linsolve") == "  linsolve   none: every row is local (solved site by site) (`linsolve = :auto`)"
    # the coupling: both groups are in one loop, κ = dt · rate (the rate: ra = 0.3 for rc, 0.1 for ro)
    @test occursin("group 1: loop [1, 2], κ = dt · rate = 0.01 × 0.3 = 0.003 (≤ 1)", rep)
    @test occursin("group 2: loop [1, 2], κ = dt · rate = 0.01 × 0.1 = 0.001 (≤ 1)", rep)
end
end

@testitem "F4-13: field_report of solutions: owned and OrdinaryDiffEq; of a problem and a SciML integrator" setup = [LP_report] tags = [:latticepde, :report] begin
using .LP_report: fd
@testset "F4-13: field_report of solutions: owned and OrdinaryDiffEq; of a problem and a SciML integrator" begin
    p = rprob(32; T = 0.1)
        s = solve(p, BackwardEuler(); dt = 0.01, saveat = 0.05)
    rep = sprint(field_report, s)
        @test occursin("Field report: owned solve, BackwardEuler(), retcode Success", rep)
    @test rline(rep, "saves") == "  saves      3 over (0.0, 0.1); 10 windows"
    @test rline(rep, "counters") == "  counters   substep counts rc 1; 10 solves"
    @test endswith(rline(rep, "substeps"), "[least]")
    # (the implicit facts resolved at the run's bind, kept in `sol.stats.implicit`)
        @test occursin("(`linsolve = :auto`), multigrid levels", rline(rep, "linsolve")) &&
          rline(rep, "newton") == "  newton     1, automatic: the operator is exact" && rline(rep, "operator") == "  operator   J̃ exact"
    @test startswith(sprint(show, s.stats), "LatticeStats(10 windows, 10 implicit solves, substep counts [1], implicit facts of 1 of 1 groups")
        se = solve(p, ExplicitEuler(; substeps = 3); dt = 0.01)
    @test endswith(rline(sprint(field_report, se), "substeps"), "[user]")
    # an OrdinaryDiffEq solve: its solver, statistics and return code, the function's keywords
    st = solve(p, Tsit5(); saveat = 0.05)
    r = sprint(field_report, st)
    @test occursin("Field report: SciML solve, Tsit5, retcode Success", r)
    @test occursin("nf $(st.stats.nf)", r) && occursin("$(st.stats.naccept) accepted", r) && !occursin("njacs 0", r)
    @test rline(r, "function") == "  function   right side built 1 time; jvp LatticeJVP; mass matrix I"
    @test startswith(rline(r, "bound"), "  bound      ρ = ")
    # a problem: the system and its bound, no group policy (no algorithm yet)
    rp = sprint(field_report, p)
    @test occursin("Field report: problem (ODEProblem, family ode)", rp)
    @test rline(rp, "problem") == "  problem    rates, 1 state field (rc); grid 32×32; backend CPU"
    @test occursin("`field_report(prob, alg)` gives the policy", rp)
    # an OrdinaryDiffEq integrator
    oi = init(p, Tsit5())
    step!(oi)
    ri = sprint(field_report, oi)
    @test occursin("Field report: SciML integrator, Tsit5", ri) && occursin("  stats      nf ", ri)
    # anything else is refused in words
        @test_throws ArgumentError field_report(devnull, SciMLBase.ODEProblem((du, u, p, t) -> (du .= 0), [1.0], (0.0, 1.0)))
end
end

@testitem "F4-13 (fixup): field_report(prob, alg): the policy under an algorithm, nothing bound" setup = [LP_report] tags = [:latticepde, :report] begin
using .LP_report: fd
@testset "F4-13 (fixup): field_report(prob, alg): the policy under an algorithm, nothing bound" begin
    p = rprob(512; T = 0.02)
        rep = sprint(io -> field_report(io, p, ExplicitEuler(); dt = 0.01))
        @test occursin("Field report: problem under ExplicitEuler() (the policy at the problem's parameters; nothing bound)", rep)
    @test rline(rep, "window") == "  window     dt = 0.01, 12 substeps (h = 0.000833333)" && endswith(rline(rep, "substeps"), "= 12 [bound]")
    # the same group lines as the integrator's policy (the run's lines are left out)
    pol(r) = [l for l in split(r, '\n') if any(k -> startswith(l, "  " * rpad(k, 11)), ("window", "substeps", "bound", "numbers"))]
        @test pol(rep) == pol(sprint(field_report, init(p, ExplicitEuler(); dt = 0.01)))
        @test endswith(rline(sprint(io -> field_report(io, p, ExplicitEuler(; substeps = 50); dt = 0.01)), "substeps"), "[user]")
    # nothing bound: no plan made, and the right side never built
    q = rprob(32)
    gq = LFP.lattice_metadata(q).problem.group
    n0 = length(gq.plans)
        rb = sprint(io -> field_report(io, q, BackwardEuler(); dt = 0.01))
    @test length(gq.plans) == n0 && LFP.lattice_metadata(q).builds[] == 0
        @test endswith(rline(rb, "substeps"), "[least]") && rline(rb, "linsolve") == "  linsolve   LatticePCG() (`linsolve = :auto`)"
    @test rline(rb, "newton") == "  newton     automatic (set when the group is bound)"
        @test rline(sprint(io -> field_report(io, q, BackwardEuler(; nlsolve = LatticeNewton(; max_iter = 3)); dt = 0.01)), "newton") ==
            "  newton     3: given (`nlsolve = LatticeNewton(; max_iter = 3)`)"
        @test occursin("κ = 0.0001", rline(sprint(io -> field_report(io, q, BackwardEuler(; nlsolve = LatticeNewton(; κ = 1.0e-4, max_iter = 3)); dt = 0.01)), "newton"))
    # groups and the coupling rule, as the integrator prints them; local rows as `init` binds them (review S4)
    p2 = discretize(rsys2(), LatticeDiscretization(Grid((8, 8))))
        r2 = sprint(io -> field_report(io, p2, FieldGroups(rce => ExplicitEuler(), roe => BackwardEuler()); dt = 0.01))
    @test occursin("group 1 of 2: rc", r2) && occursin("group 2 of 2: ro", r2) && endswith(rline(r2, "substeps"), "= 3 [bound]")
    @test occursin("group 1: loop [1, 2], κ = dt · rate = 0.01 × 0.3 = 0.003 (≤ 1)", r2)
        @test rline(r2, "linsolve") == "  linsolve   none: every row is local (solved site by site)"
    # the policy's refusals hold: no window (no `dt`, no clock)
        @test_throws ArgumentError field_report(devnull, q, BackwardEuler())
    # without `io`: stdout (review M1)
    out = mktemp() do path, io
        redirect_stdout(io) do
                field_report(q, BackwardEuler(); dt = 0.01)
        end
        flush(io)
        read(path, String)
    end
        @test startswith(out, "Field report: problem under BackwardEuler()")
end
end

@testitem "F4-13 (fixup): sol.stats.implicit keeps the resolved implicit facts per group, as data" setup = [LP_report] tags = [:latticepde, :report] begin
using .LP_report: fd
@testset "F4-13 (fixup): sol.stats.implicit keeps the resolved implicit facts per group, as data" begin
    q = rprob(32; T = 0.05)
        s = solve(q, BackwardEuler(); dt = 0.01)
    f = only(s.stats.implicit)
        ig = init(q, BackwardEuler(); dt = 0.01)
    sv = only(r.solver for r in only(ig.runtimes).cache.rows)
    @test f isa LFP.ImplicitFacts && f.keys == ["rc"] && f.newton == 1 && f.levels == [length(sv.prog.hierarchy)]
        @test f.solver_type == [sv.T] && f.exact && !f.coupled && !f.given && f.linsolve == Any[LatticePCG()] && f.h == 0.01
    @test f == LFP.implicit_facts(only(ig.runtimes))
        @test solve(q, ExplicitEuler(); dt = 0.01).stats.implicit == [nothing]
    p2 = discretize(rsys2(), LatticeDiscretization(Grid((8, 8))))
        s2 = solve(p2, FieldGroups(rce => ExplicitEuler(), roe => BackwardEuler(; nlsolve = LatticeNewton(; max_iter = 2))); dt = 0.01)
    @test s2.stats.implicit[1] === nothing && s2.stats.implicit[2].newton == 2 && s2.stats.implicit[2].given
        @test occursin("2: given (`nlsolve = LatticeNewton(; max_iter = 2)`)", sprint(field_report, s2))
end
end

@testitem "F4-13 (review): an inexact operator: advection's ρ_in, the convergence rule and the Newton count by hand" setup = [LP_report] tags = [:latticepde, :report] begin
using .LP_report: fd
@testset "F4-13 (review): an inexact operator: advection's ρ_in, the convergence rule and the Newton count by hand" begin
    # upwind advection with v = (1, 0.5) on 32²: ρ_in = 2 (|1| + |0.5|) / h = 2 × 1.5 × 32 = 96. The
    # convergence rule n2 = ⌈2γ dt ρ_in⌉: BE (γ = 1) ⌈2 × 0.05 × 96⌉ = ⌈9.6⌉ = 10, CN (γ = 1/2) ⌈4.8⌉ = 5.
    # BE's Newton count: h = 0.005, ρ_c = γ h ρ_in = 0.48, ⌈log ε_N / log 0.48⌉ = 10
        sys = PDESystem(
            [D(rqe) ~ 0.01 * laplacian(rqe) - Advect(Upwind1())([1.0, 0.5], rqe) + 1], [rq(0, x, y) ~ ifelse(x < 0.5, 1.0, 0.0)],
        rdom(0.2), [t, x, y], [rqe], Num[]; name = :adv)
    p = discretize(sys, LatticeDiscretization(Grid((32, 32))))
        rb = sprint(field_report, init(p, BackwardEuler(); dt = 0.05))
    @test rline(rb, "window") == "  window     dt = 0.05, 10 substeps (h = 0.005)"
    @test occursin("the convergence rule ⌈2γ dt ρ_in / (1 − θ)⌉ = 10), above the least count 1 [bound]", rline(rb, "substeps"))
    @test rline(rb, "newton") == "  newton     10, automatic: the contraction γ h ρ_in + θ = 0.48 of the terms out of the operator (ρ_in = 96.0, h = 0.005)"
    @test occursin("J̃ inexact: ", rline(rb, "operator")) && occursin("; ρ_in = 96.0, corrected by the Newton iterations", rline(rb, "operator"))
        rcn = sprint(field_report, init(p, CrankNicolson(); dt = 0.05))
    @test rline(rcn, "window") == "  window     dt = 0.05, 5 substeps (h = 0.01)" && occursin("convergence rule ⌈2γ dt ρ_in / (1 − θ)⌉ = 5)", rcn)
    # the same policy without binding
        @test rline(sprint(io -> field_report(io, p, BackwardEuler(); dt = 0.05)), "window") == rline(rb, "window")
end
end

@testitem "F4-13 (review): a coupled solve, a cycle under Backward Euler, QuasiSteady, Crank–Nicolson's least count 2" setup = [LP_report] tags = [:latticepde, :report] begin
using .LP_report: fd
@testset "F4-13 (review): a coupled solve, a cycle under Backward Euler, QuasiSteady, Crank–Nicolson's least count 2" begin
        sys = PDESystem(
            [D(rcye) ~ 0.1 * laplacian(rcye) - rcye + 5.0 * rcze, D(rcze) ~ 0.1 * laplacian(rcze) - rcze - 5.0 * rcye],
        [rcy(0, x, y) ~ x, rcz(0, x, y) ~ y], rdom(0.2), [t, x, y], [rcye, rcze], Num[]; name = :cyc)
    p = discretize(sys, LatticeDiscretization(Grid((8, 8))))
    # QuasiSteady takes the coupled solve: its operator is the whole Jacobian (review M2)
        ig = init(p, QuasiSteady(); dt = 0.05)
    step!(ig)
    rq_ = sprint(field_report, ig)
    @test LFP._primal_cache(only(ig.runtimes).cache).cs !== nothing
    @test rline(rq_, "operator") == "  operator   J̃ the whole Jacobian (coupled solve: exact)"
    @test rline(rq_, "newton") == "  newton     1, automatic: the coupled solve's operator is the whole Jacobian (linear: one solve)"
        @test startswith(rline(rq_, "linsolve"), "  linsolve   coupled solve LatticeGMRES(), each field preconditioned by LatticePCG(; maxiters = 2)")
    # (QuasiSteady: one solve per window, no substep line and no explicit bound, review N3)
    @test rline(rq_, "window") == "  window     dt = 0.05, one steady solve per window" && rline(rq_, "substeps") == "" &&
          rline(rq_, "bound") == ""
    # Backward Euler solves the rows one by one: the cycle is out of the operator, ρ_in = 5 (the cross coefficient)
        rb = sprint(field_report, init(p, BackwardEuler(); dt = 0.05))
    @test rline(rb, "operator") == "  operator   J̃ inexact: the cycle among the group's fields; ρ_in = 5.0, corrected by the Newton iterations"
    @test rline(sprint(field_report, p), "types") == "  types      state Float64, parameters none"
    # Crank–Nicolson on data that jump every window (it reads another group's field): the least count 2
    p2 = discretize(rsys2(), LatticeDiscretization(Grid((8, 8))))
        r2 = sprint(field_report, init(p2, FieldGroups(rce => CrankNicolson(), roe => BackwardEuler()); dt = 0.01))
    @test rline(r2, "window") == "  window     dt = 0.01, 2 substeps (h = 0.005)" && occursin("the least count 2 (", rline(r2, "substeps")) &&
          endswith(rline(r2, "substeps"), "[least]")
end
end

@testitem "F4-13 (review): unseen terms: ρ_in unknown, κ over the seen cross terms only, an unbounded group refused" setup = [LP_report] tags = [:latticepde, :report] begin
using .LP_report: fd
@testset "F4-13 (review): unseen terms: ρ_in unknown, κ over the seen cross terms only, an unbounded group refused" begin
    # Gray-Scott: `u v²` is a term no bound sees (review S1, S2)
        gs = PDESystem(
            [D(rue) ~ 2.0e-5 * laplacian(rue) - rue * rve^2 + gF * (1 - rue), D(rve) ~ 1.0e-5 * laplacian(rve) + rue * rve^2 - (gF + gk) * rve],
        [ru(0, x, y) ~ 1.0 - 0.5x, rv(0, x, y) ~ 0.25x, ru(t, 0, y) ~ ru(t, 1, y), ru(t, x, 0) ~ ru(t, x, 1),
         rv(t, 0, y) ~ rv(t, 1, y), rv(t, x, 0) ~ rv(t, x, 1)], rdom(2.0), [t, x, y], [rue, rve], [gF, gk]; name = :gs)
    p = discretize(gs, LatticeDiscretization(Grid((16, 16))))
        alg = FieldGroups(rue => ExplicitEuler(; substeps = 4), rve => BackwardEuler())
        rep = sprint(field_report, solve(p, alg; dt = 1.0))
    op = rlines(rep, "operator")[1]
    @test occursin("ρ_in unknown (no bound sees ", op) && !occursin("ρ_in = 0.0", rep)
    @test occursin("4, automatic: ρ_in unknown (no bound sees a term out of the operator", rline(rep, "newton"))
    @test occursin("group 1: loop [1, 2], κ = dt · rate = 1.0 × 0.0 = 0.0 (≤ 1); κ covers only the cross terms the bound sees (unseen: ru: -ru*(rv^2), rv: ru*(rv^2))", rep)
    @test occursin("ρ not finite; over the terms it sees", rline(rep, "bound")) && occursin("unseen: ru: -ru*(rv^2)", rline(rep, "bound"))
    # with no count, `init` refuses the explicit group, and the report says so (review S4)
        bad = FieldGroups(rue => ExplicitEuler(), rve => BackwardEuler())
        rr = sprint(io -> field_report(io, p, bad; dt = 1.0))
    @test rline(rr, "window") == "  window     dt = 1.0, no count"
    @test occursin("`init` refuses this group: the bound is not finite", rline(rr, "substeps")) &&
            occursin("give a count, `ExplicitEuler(; substeps = n)`", rline(rr, "substeps")) && endswith(rline(rr, "substeps"), "[refused]")
        @test_throws ArgumentError init(p, bad; dt = 1.0)
end
end

@testitem "F4-13 (review): κ near 1: 0.99 runs, 1.000000001 is refused, as the report says" setup = [LP_report] tags = [:latticepde, :report] begin
using .LP_report: fd
@testset "F4-13 (review): κ near 1: 0.99 runs, 1.000000001 is refused, as the report says" begin
    p = discretize(rsys2(), LatticeDiscretization(Grid((8, 8))))
        alg = FieldGroups(rce => ExplicitEuler(), roe => BackwardEuler())
    p99 = remake(p; p = [ra => 99.0])
        @test occursin("κ = dt · rate = 0.01 × 99.0 = 0.99 (≤ 1)", sprint(io -> field_report(io, p99, alg; dt = 0.01))) && init(p99, alg; dt = 0.01) isa LFP.FieldIntegrator
    pbad = remake(p; p = [ra => 100.0000001])
        @test occursin("κ = dt · rate = 0.01 × 100.0 = 1.0 (> 1)", sprint(io -> field_report(io, pbad, alg; dt = 0.01)))
        @test_throws ArgumentError init(pbad, alg; dt = 0.01)
end
end

@testitem "F4-13 (review): a bound that reads the time: the first window's count, the window restored" setup = [LP_report] tags = [:latticepde, :report] begin
using .LP_report: fd
@testset "F4-13 (review): a bound that reads the time: the first window's count, the window restored" begin
    @variables rt_(..)
    rte = rt_(t, x, y)
        sys = PDESystem(
            [D(rte) ~ laplacian(rte)], [rt_(0, x, y) ~ x * y, (-1 - 40t) * rt_(t, 0, y) - Differential(x)(rt_(t, 0, y)) ~ 0.0],
        rdom(0.5), [t, x, y], [rte], Num[]; name = :rt)
    p = discretize(sys, LatticeDiscretization(Grid((16, 16))))
    stab = LFP.lattice_metadata(p).problem.stability
    w0 = LFP.bound_window(stab)
        rf = sprint(io -> field_report(io, p, ExplicitEuler(); dt = 0.1))
    @test LFP.bound_window(stab) == w0                         # restored
    @test occursin("this count is the first window's, [0.0, 0.1]", rline(rf, "window"))
        s = solve(p, ExplicitEuler(); dt = 0.1)
    last = s.stats.counts[1]
    rs = sprint(field_report, s)
    n1 = parse(Int, match(r", (\d+) substeps", rline(rf, "window")).captures[1])
    @test last > n1                                            # (the face grows: later windows take more)
    @test startswith(rline(rs, "substeps"), "  substeps   the run's last window took $last; $n1 by the bound")
    @test rline(rs, "window") == rline(rf, "window")           # (the window line: the first window's count, as it says)
    # after the run the problem's report still gives the first window's count
        @test rline(sprint(io -> field_report(io, p, ExplicitEuler(); dt = 0.1)), "window") == rline(rf, "window")
end
end

@testitem "F4-13 (review): the problem line: hexagonal grids, coarse fields; a map's header" setup = [LP_report] tags = [:latticepde, :report] begin
using .LP_report: fd
@testset "F4-13 (review): the problem line: hexagonal grids, coarse fields; a map's header" begin
        sys = PDESystem([D(rce) ~ 0.2 * laplacian(rce) - rce], [rc(0, x, y) ~ x * y], rdom(0.2), [t, x, y], [rce], Num[]; name = :hx)
    ph = discretize(sys, LatticeDiscretization(Grid((16, 16); geometry = HEX)))
    @test occursin("grid 16×16 (hexagonal)", rline(sprint(field_report, ph), "problem"))
    cz = first(@variables rcf(..) [lattice_level = Coarse(2)])
    cze = cz(t, x, y)
        pc = discretize(
            PDESystem([D(cze) ~ 0.2 * laplacian(cze) - cze], [cz(0, x, y) ~ x * y], rdom(0.2), [t, x, y], [cze], Num[]; name = :cf),
        LatticeDiscretization(Grid((16, 16))))
    @test occursin("own grids: rcf 8×8 (coarse)", rline(sprint(field_report, pc), "problem"))
    @parameters rdx [lattice_spacing = 1]
    @variables rN(..)
    rNe = rN(t, x, y)
    pm = discretize(PDESystem([Shift(t, 1)(rNe) ~ (rN(t, x + rdx, y) + rN(t, x - rdx, y)) / 2], [rN(0, x, y) ~ x],
        [t ∈ Interval(0.0, 3.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [rNe], [rdx]; name = :m),
        LatticeDiscretization(Grid((8, 8))))
    rm = sprint(field_report, init(pm, ExplicitMap()))
    @test occursin("Field report: owned integrator, ExplicitMap()\n", rm) && rline(rm, "window") == "  window     dt = 1.0, one map step per window"
end
end

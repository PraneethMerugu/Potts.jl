# F4-13 (F4 design §3.9, AF-09), the Potts side: `field_report` of a `PottsProblem`, a
# `PottsIntegrator` and a `PottsSolution` prints each field group of the model as LatticeFields
# prints the groups of a LatticePDE problem (`Problems.group_report`, one function re-exported by
# Potts): the algorithm, the window (the MCS), the substep count and its cause, the bound, the
# number types, the implicit facts, the coupling rule's κ, and the run's counters. Oracle: the
# report of the bare PDESystem (`discretize(Potts.fields(model))` stepped by the owned
# integrator) prints the same group lines. The report reads what the objects hold: a warm
# `step!` still allocates nothing after it.
# Negative control: at 5100e988 `field_report` is not defined in Potts (this file fails at its
# first testset, ~/lpwork/f4F13/nc-base.log).

@testsetup module FieldsReportSetup
using Potts, Test
using Potts: CorePotts
isdefined(@__MODULE__, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))
using Potts, Test


module FrPDE
using Potts: Potts
using Potts.ModelingToolkitBase: PDESystem, Differential, @variables, @parameters
const t = Potts.t
const Dt = Differential(t)
const Δ = Potts.LatticePDE.Δ
const lattice_domain = Potts.LatticePDE.lattice_domain
@parameters x y Do = 50.0 sc = 0.01 ec = 0.05 Du = 0.2 ka = 0.3 kb = 0.2
@variables c(..) = 0.0 u(..) = 0.0 endo(..)::Bool [input = true]
const C, U, E = c(t, x, y), u(t, x, y), endo(t, x, y)
# Merks' VEGF: secreted by the endothelial cells, decaying in the medium, `Do = 50` (the audit's
# case: ⌈8 Do / 1.8⌉ = 223 substeps per MCS, 2026-10-18 usability audit, item 12)
vegf() = PDESystem([Dt(C) ~ Do * Δ(C) + sc * E - ec * (1 - E) * C], [], lattice_domain(t, (x, y), (24, 20)), [t, x, y],
    [C, E], [Do, sc, ec]; name = :vegf)
# two fields that read each other (a loop of two groups under `solvers`)
loop() = PDESystem([Dt(C) ~ Du * Δ(C) + ka * U - 0.1 * C + sc * E, Dt(U) ~ -kb * U + 0.1 * C], [],
    lattice_domain(t, (x, y), (24, 20)), [t, x, y], [C, U, E], [Du, ka, kb, sc]; name = :loop)
end


@potts_model FrMerks begin
    @kinds medium endothelial
    @parameters χ = 50.0
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(endothelial) => (volume - 16.0)^2
    @fields c = FrPDE.vegf() (FrPDE.endo => kind == endothelial)
    @drive Chemotaxis(c; strength = χ, kinds = (endothelial,))
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model FrLoop begin
    @kinds medium endothelial
    @lattice Lattice((24, 20); boundary = Closed())
    @energy cells(endothelial) => (volume - 16.0)^2
    @fields c, u = FrPDE.loop() (FrPDE.endo => kind == endothelial)
    @sweep Metropolis(; temperature = 4.0)
end


fr_op() = (σ = zeros(Int32, 24, 20); σ[5:8, 5:8] .= 1; σ[14:17, 10:13] .= 2; [ownership => σ, kind => [:endothelial, :endothelial]])

fr_prob(m; kw...) = PottsProblem(m, fr_op(), (0, 4); seed = 3, kw...)

# the text of a report line `label   text` (the first such line), and the lines of a report from
# its first group block on
fr_line(rep, label) = (l = filter(s -> startswith(s, "  " * rpad(label, 11)), split(rep, '\n')); isempty(l) ? "" : String(l[1]))

fr_groups(rep) = (ls = split(chomp(rep), '\n'); [String(s) for s in ls[findfirst(s -> startswith(s, "group "), ls):end]])

fr_warm(ig) = (step!(ig); step!(ig); @allocated step!(ig))
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

   # (a function barrier)
@testitem "F4-13: field_report of a Merks-like model at Do = 50 shows the 223 substeps and their cause" setup = [FieldsReportSetup] tags = [:potts, :fields_report] begin
    @testset "F4-13: field_report of a Merks-like model at Do = 50 shows the 223 substeps and their cause" begin
        @test isdefined(Potts, :field_report) && Base.isexported(Potts, :field_report)
        @test Potts.field_report === Potts.LatticePDE.field_report === Potts.LatticeFields.Problems.field_report
        m = FrMerks(; name = :m)
        prob = fr_prob(m)
        rep = sprint(field_report, prob)
        @test startswith(rep, "Field report: PottsProblem, 1 field group (the policy at the problem's parameters; nothing bound)")
        @test occursin("group 1 of 1: c (ExplicitEuler())", rep)
        @test fr_line(rep, "window") == "  window     dt = 1.0, 223 substeps (h = 0.0044843)"
        # ρ = 8 Do + ec (the decay in the medium) = 400.05
        @test fr_line(rep, "substeps") == "  substeps   the bound, ⌈dt ρ / 1.8⌉ = ⌈1.0 × 400.05 / 1.8⌉ = 223 [bound]"
        # batch-end review S5, S1: ρ split into the parts of its row; past 20 substeps of the bound,
        # the implicit count as a route (base ab34e226, ~/lpwork/f4BE/nc.log: `ρ = 400.05` alone, no route)
        @test fr_line(rep, "bound") == "  bound      ρ = 400.05 (row c: diffusion 400.0, reaction 0.05)"
        @test fr_line(rep, "route") == "  route      BackwardEuler() steps this group in 1 substep"
        @test fr_line(rep, "numbers") == "  numbers    state Float64, compute Float64"
        @test fr_line(rep, "backend") == "  backend    set at `init` (`init(prob, alg; backend)`; the CPU by default)"
        @test substep_counts(prob) == [223]
        # the integrator: the same policy, with the run's counters
        integ = init(prob, SequentialCPM())
        step!(integ)
        step!(integ)
        ri = sprint(field_report, integ)
        @test startswith(ri, "Field report: PottsIntegrator, 1 field group, SequentialCPM")
        @test fr_line(ri, "time") == "  time       MCS 2 of (0, 4), retcode Default"
        @test fr_line(ri, "backend") == "  backend    CPU"
        @test fr_line(ri, "counters") == "  counters   substep counts c 223; code Success"
        @test fr_line(ri, "substeps") == fr_line(rep, "substeps")
        @test fr_line(ri, "run") == "  run        2 windows; status Success"
        @test fr_line(ri, "launches") == "  launches   1 per substep; no fusion decision (one kernel)"
        # the user minimum above the bound, equal to it, and below it
        for (n, cause, k) in ((300, "[user]", 300), (223, "[both]", 223), (10, "[bound]", 223))
            r = sprint(field_report, init(fr_prob(m; field_solver = ExplicitEuler(; substeps = n)), SequentialCPM()))
            @test endswith(fr_line(r, "substeps"), cause) && occursin("$k substeps", fr_line(r, "window"))
            @test occursin("substeps = $n", fr_line(r, "substeps"))
        end
        # the solution: the policy at the problem's parameters and the run's field counters
        sol = solve(prob, SequentialCPM())
        rs = sprint(field_report, sol)
        @test startswith(rs, "Field report: PottsSolution, 1 field group, SequentialCPM, retcode Success")
        @test fr_line(rs, "saves") == "  saves      5 over (0, 4), 4 MCS"                 # every MCS (SciML)
        @test fr_line(rs, "substeps") == fr_line(rep, "substeps")
        # batch-end review (e): the solution keeps the counts its run used and the backend
        @test fr_line(rs, "counters") == "  counters   substep counts c 223; code Success"
        @test fr_line(rs, "backend") == "  backend    CPU"
        # a user minimum above the bound sets the count: no route
        r = sprint(field_report, fr_prob(m; field_solver = ExplicitEuler(; substeps = 300)))
        @test fr_line(r, "route") == ""
    end
end

@testitem "batch-end review (e): a PottsSolution's report matches its integrator's (counts, implicit facts)" setup = [FieldsReportSetup] tags = [:potts, :fields_report] begin
    @testset "batch-end review (e): a PottsSolution's report matches its integrator's (counts, implicit facts)" begin
        # base ab34e226 (~/lpwork/f4BE/nc.log): the solution prints the policy as given (`newton
        # automatic (set when the group is bound)`, no substep counts) and no backend
        m = FrMerks(; name = :m)
        for fs in (ExplicitEuler(), BackwardEuler(; linsolve = Multigrid()))
            prob = fr_prob(m; field_solver = fs)
            sol = solve(prob, SequentialCPM())
            integ = init(prob, SequentialCPM())
            for _ in 1:4
                step!(integ)
            end
            rs, ri = sprint(field_report, sol), sprint(field_report, integ)
            # (the integrator also gives its run counters and launches)
            own(r) = [l for l in fr_groups(r) if !startswith(l, "  run ") && !startswith(l, "  launches ") && !startswith(l, "  fusion ")]
            @test own(rs) == own(ri) || (println(rs, "\n---\n", ri); false)
            @test fr_line(rs, "counters") == fr_line(ri, "counters")
            @test sol.stats.fields.counts == substep_counts(integ)
            @test (sol.stats.fields.implicit[1] === nothing) == (fs isa ExplicitEuler)
        end
        rs = sprint(field_report, solve(fr_prob(m; field_solver = BackwardEuler(; linsolve = Multigrid())), SequentialCPM()))
        @test fr_line(rs, "newton") == "  newton     1, automatic: the operator is exact"
        @test fr_line(rs, "linsolve") == "  linsolve   Multigrid(; maxiters = 12), multigrid levels 5"
    end
end

@testitem "F4-13: field_report of a BackwardEuler group: inner, multigrid levels, the Newton count" setup = [FieldsReportSetup] tags = [:potts, :fields_report] begin
    @testset "F4-13: field_report of a BackwardEuler group: inner, multigrid levels, the Newton count" begin
        m = FrMerks(; name = :m)
        integ = init(fr_prob(m; field_solver = BackwardEuler(; linsolve = Multigrid())), SequentialCPM())
        step!(integ)
        rep = sprint(field_report, integ)
        @test occursin("group 1 of 1: c (BackwardEuler(; linsolve = Multigrid()))", rep)
        @test fr_line(rep, "window") == "  window     dt = 1.0, 1 substep (h = 1.0)"
        @test endswith(fr_line(rep, "substeps"), "[least]")
        @test fr_line(rep, "linsolve") == "  linsolve   Multigrid(; maxiters = 12), multigrid levels 5"
        @test fr_line(rep, "newton") == "  newton     1, automatic: the operator is exact"
        @test fr_line(rep, "operator") == "  operator   J̃ exact"
        @test fr_line(rep, "numbers") == "  numbers    state Float64, compute Float64, solver Float64 (`solver_type = :auto`)"
        @test fr_line(rep, "counters") == "  counters   substep counts c 1; 1 solve; code Success"
        @test fr_line(rep, "run") == "  run        1 window; 1 solve; status Success"
        # a given Newton count and `linsolve = :auto`
        r = sprint(field_report, init(fr_prob(m; field_solver = BackwardEuler(; newton = 3)), SequentialCPM()))
        @test fr_line(r, "newton") == "  newton     3: given (`newton = 3`)"
        @test startswith(fr_line(r, "linsolve"), "  linsolve   DevicePCG() (`linsolve = :auto`), multigrid levels ")
        # a problem: `inner` and the Newton count as given (resolved when the group is bound)
        rp = sprint(field_report, fr_prob(m; field_solver = BackwardEuler(; linsolve = Multigrid())))
        @test fr_line(rp, "linsolve") == "  linsolve   Multigrid()"
        @test fr_line(rp, "newton") == "  newton     automatic (set when the group is bound)"
    end
end

@testitem "F4-13: a coupled model and its bare PDESystem print the same group lines" setup = [FieldsReportSetup] tags = [:potts, :fields_report] begin
    @testset "F4-13: a coupled model and its bare PDESystem print the same group lines" begin
        LP = Potts.LatticePDE
        cases = ((FrMerks(; name = :m), ExplicitEuler(), ExplicitEuler(), 1),
            (FrMerks(; name = :m), BackwardEuler(; linsolve = Multigrid()), BackwardEuler(; linsolve = Multigrid()), 1),
            (FrLoop(; name = :m), FieldGroups(:u => ExplicitEuler(; substeps = 4); default = ExplicitEuler()),
                FieldGroups(:u => ExplicitEuler(; substeps = 4); default = ExplicitEuler()), 2))
        # the owned algorithms also give their window (`dt = 1.0`), which a Potts problem takes from
        # the MCS: the headers differ by it alone
        nodt(s) = replace(s, "(; dt = 1.0)" => "()", "dt = 1.0, " => "", ", dt = 1.0" => "")
        for (m, fs, own, ngroups) in cases
            integ = init(fr_prob(m; field_solver = fs), SequentialCPM())
            bare = LP.discretize(Potts.fields(m), LP.LatticeDiscretization(LP.Grid((24, 20)); T = Float64);
                inputs = collect(Potts.field_inputs(integ)))
            oi = init(bare, own; dt = 1.0)
            step!(integ)
            step!(oi)
            a, b = fr_groups(sprint(field_report, integ)), fr_groups(sprint(field_report, oi))
            @test count(s -> startswith(s, "group "), a) == ngroups
            @test nodt.(a) == nodt.(b) || (println(join(a, '\n'), "\n---\n", join(b, '\n')); false)
        end
        # the loop's κ (two groups that read each other), at the parameters of both groups (`ka` is
        # read by the group of `c` only)
        rep = sprint(field_report, fr_prob(FrLoop(; name = :m); field_solver = FieldGroups(:u => ExplicitEuler(; substeps = 4);
            default = ExplicitEuler())))
        @test occursin("""
    coupling:
      group 1: loop [1, 2], κ = dt · rate = 1.0 × 0.3 = 0.3 (≤ 1); worst row c reads u through ka
      group 2: loop [1, 2], κ = dt · rate = 1.0 × 0.1 = 0.1 (≤ 1); worst row u reads c through 0.1
    """, rep) || (print(rep); false)
    end
end

@testitem "F4-13: a report adds nothing to a run (a warm step! allocates 0 B after it)" setup = [FieldsReportSetup] tags = [:potts, :fields_report] begin
    @testset "F4-13: a report adds nothing to a run (a warm step! allocates 0 B after it)" begin
        m = FrMerks(; name = :m)
        for fs in (ExplicitEuler(), BackwardEuler(; linsolve = Multigrid()))
            integ = init(PottsProblem(m, fr_op(), (0, 20); seed = 3, field_solver = fs), SequentialCPM(); save_everystep = false)
            @test fr_warm(integ) == 0
            field_report(devnull, integ)
            @test fr_warm(integ) == 0
            # the run after a report is the run without it
            ref = init(PottsProblem(m, fr_op(), (0, 20); seed = 3, field_solver = fs), SequentialCPM())
            for _ in 1:3
                step!(ref)
            end
            field_report(devnull, ref)
            for _ in 1:3
                step!(ref)
            end
            plain = init(PottsProblem(m, fr_op(), (0, 20); seed = 3, field_solver = fs), SequentialCPM())
            for _ in 1:6
                step!(plain)
            end
            @test ref.u.site.c == plain.u.site.c && ref.u.σ == plain.u.σ
        end
    end
end

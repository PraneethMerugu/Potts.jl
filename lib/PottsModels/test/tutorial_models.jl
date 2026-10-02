# The model tutorials (docs/models/*.jl) build each published model section by section; the
# finished models live in docs/models/src/*_model.jl, which the pages show and run. Each must
# compile to the same problem as the shipped constructor: the same generated code, lattice
# and solvers (the checkpoint fingerprint), the same parameter defaults, relations, frozen
# mask and initial state. A tutorial that drifts from its constructor fails here.
module TutorialModels
using Potts
const SRC = joinpath(@__DIR__, "..", "..", "..", "docs", "models", "src")
for f in ("graner_glazier", "merks", "akeeb", "wortel_act", "openvt")
    include(joinpath(SRC, f * "_model.jl"))
end
end

function same_problem(a, b)
    return a.f.fingerprint == b.f.fingerprint && a.p == b.p && a.lattice == b.lattice && a.contact == b.contact &&
           a.proposal == b.proposal && a.relations == b.relations && a.spacing == b.spacing &&
           a.frozen == b.frozen && a.u0.σ == b.u0.σ && a.u0.cell == b.u0.cell && a.u0.site == b.u0.site &&
           a.u0.model == b.u0.model
end

@testset "model tutorials build the shipped models" begin
    T = TutorialModels
    two(dims, a, b) = (s = zeros(Int32, dims); s[a...] .= 1; s[b...] .= 2; s)
    σg, kg = graner_glazier_state()
    gg = [ownership => σg, kind => kg]
    merks = [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]]
    act = [ownership => two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:cell, :cell]]
    euler = (; field_solver = ExplicitEuler(substeps = 2, lower = 0.0))
    cases = [
        ("Graner–Glazier", T.CellSorting(; name = :m), GranerGlazier(; name = :m), gg, (;)),
        ("Graner–Glazier, keywords", T.CellSorting(; name = :m, lattice = (144, 144), T = 5.0),
            GranerGlazier(; name = :m, lattice = (144, 144), T = 5.0),
            (s = graner_glazier_state(2); [ownership => s[1], kind => s[2]]), (;)),
        ("Merks", T.Vasculogenesis(; name = :m, lattice = (8, 8)), MerksVasculogenesis(; name = :m, lattice = (8, 8)),
            merks, euler),
        ("Merks, contact-inhibited", T.Vasculogenesis(; name = :m, lattice = (8, 8), contact_inhibited = true),
            MerksVasculogenesis(; name = :m, lattice = (8, 8), contact_inhibited = true), merks, euler),
        ("Akeeb", T.LeaderFollowerInvasion(; name = :m, lattice = (99, 60)), AkeebInvasion(; name = :m, lattice = (99, 60)),
            akeeb_state(; lattice = (99, 60)), (; capacity = 1000)),
        ("Akeeb, the page's μ = 24", T.LeaderFollowerInvasion(; name = :m, lattice = (99, 60), μ = 24.0),
            AkeebInvasion(; name = :m, lattice = (99, 60), μ = 24.0), akeeb_state(; lattice = (99, 60)), (; capacity = 1000)),
        ("Wortel Act", T.ActMigration(; name = :m, lattice = (8, 8)), WortelAct(; name = :m, lattice = (8, 8)), act, (;)),
        ("Wortel Act, connected", T.ActMigration(; name = :m, lattice = (8, 8), connected = true),
            WortelAct(; name = :m, lattice = (8, 8), connected = true), act, (;)),
        ("OpenVT", T.GrowingMonolayer(; name = :m, lattice = (24, 24)),
            OpenVTGrowingMonolayer(; name = :m, lattice = (24, 24)), openvt_monolayer_state(; lattice = (24, 24)),
            (; capacity = 64)),
    ]
    @testset "$label" for (label, tutorial, shipped, op, kw) in cases
        @test same_problem(PottsProblem(tutorial, op, (0, 1); kw...), PottsProblem(shipped, op, (0, 1); kw...))
    end
    # negative controls: a changed default, a switched structural parameter and another model
    # are told apart
    @test !same_problem(PottsProblem(T.CellSorting(; name = :m, T = 5.0), gg, (0, 1)),
        PottsProblem(GranerGlazier(; name = :m), gg, (0, 1)))
    @test PottsProblem(T.Vasculogenesis(; name = :m, lattice = (8, 8), contact_inhibited = true), merks, (0, 1); euler...).f.fingerprint !=
          PottsProblem(MerksVasculogenesis(; name = :m, lattice = (8, 8)), merks, (0, 1); euler...).f.fingerprint
    @test PottsProblem(T.ActMigration(; name = :m, lattice = (8, 8), connected = true), act, (0, 1)).f.fingerprint !=
          PottsProblem(WortelAct(; name = :m, lattice = (8, 8)), act, (0, 1)).f.fingerprint
end

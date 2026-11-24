# Empirical convergence orders (temporal and spatial via `observed_orders`) and
# multigrid mesh-independence across refined grids (h -> h/2 -> h/4). The cases are in
# shared/convergence_cases.jl; each item also checks the committed data file of the
# convergence docs page (docs/src/fields/convergence.toml) against what it computes.
# Regenerate that file with
#   julia --project=lib/LatticePDE/test -e 'using Pkg; Pkg.instantiate()'
#   julia --project=lib/LatticePDE/test lib/LatticePDE/test/write_convergence_data.jl

@testsetup module LP_convergence_orders
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables,
    Differential, PDESystem,
    System, t_nounits as t, D_nounits as D
using Symbolics: Num
using DomainSets: Interval
using SciMLBase: SciMLBase, solve
using LatticeFields: LatticeFields, Problems as LFP
using OrdinaryDiffEqTsit5: Tsit5
include("shared/preamble.jl")
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
include("../../../test/shared/convergence_helpers.jl")
include("shared/convergence_cases.jl")
const COMMITTED_CONVERGENCE = read_convergence_data(CONVERGENCE_DATA_FILE)
checks_committed(cases) = convergence_data_issues(
    filter(r -> r["name"] in [c.name for c in cases], COMMITTED_CONVERGENCE), cases
)
include("shared/export_all.jl")
end

@testitem "temporal convergence orders (EE, BE, CN, BDF2, IMEX)" setup = [
    LP_convergence_orders,
] tags = [
    :latticepde, :convergence,
] begin
    @testset "temporal convergence orders" begin
        # Manufactured solution u(t, x, y) = exp(t) * sin(pi * x) * sin(pi * y) on [0, 1]^2
        # against the semi-discrete Tsit5 reference (eliminates spatial error)
        cases = temporal_convergence_cases()
        for c in cases
            @testset "$(c.name)" begin
                @test all(o -> abs(o - c.expected_order) < 0.15, c.observed_orders)
                @test abs(c.observed_order - c.expected_order) < 0.15
            end
        end

        @testset "IMEX FieldGroups (ExplicitEuler + BackwardEuler)" begin
            c = imex_convergence_case()
            @test all(o -> abs(o - 1.0) < 0.15, c.observed_orders)
            @test abs(c.observed_order - 1.0) < 0.15
            push!(cases, c)
        end
        @test checks_committed(cases) == String[]
    end
end

@testitem "spatial convergence orders (DivKGrad, Upwind1, Robin, Hex)" setup = [
    LP_convergence_orders,
] tags = [
    :latticepde, :convergence,
] begin
    @testset "spatial convergence orders" begin
        cases = []
        @testset "DivKGrad(:harmonic and :arithmetic) variable coefficient O(h^2)" begin
            for mean_kind in (:harmonic, :arithmetic)
                c = divkgrad_convergence_case(mean_kind)
                @test all(o -> abs(o - 2.0) < 0.15, c.observed_orders)
                @test abs(c.observed_order - 2.0) < 0.15
                push!(cases, c)
            end
        end

        @testset "Advect(Upwind1()) spatial order O(h)" begin
            c = upwind_convergence_case()
            @test all(o -> abs(o - 1.0) < 0.15, c.observed_orders)
            @test abs(c.observed_order - 1.0) < 0.15
            push!(cases, c)
        end

        @testset "Robin face spatial order O(h^2)" begin
            c = robin_convergence_case()
            @test all(o -> abs(o - 2.0) < 0.15, c.observed_orders)
            @test abs(c.observed_order - 2.0) < 0.15
            push!(cases, c)
        end

        @testset "Hexagonal Laplacian spatial order O(h^2)" begin
            c = hex_convergence_case()
            @test all(o -> abs(o - 2.0) < 0.2, c.observed_orders)
            @test abs(c.observed_order - 2.0) < 0.2
            push!(cases, c)
        end
        @test checks_committed(cases) == String[]
    end
end

@testitem "multigrid mesh-independence under grid refinement (h -> h/2 -> h/4)" setup = [
    LP_convergence_orders,
] tags = [
    :latticepde, :convergence,
] begin
    @testset "multigrid mesh-independence under grid refinement" begin
        (; case, iters, successes) = multigrid_convergence_case()
        for ok in successes
            @test ok
        end
        # Iteration counts stay bounded and mesh-independent (no O(N) blowup)
        @test all(<=(25), iters)
        @test maximum(iters) - minimum(iters) <= 6
        # Spatial error converges at O(h^2)
        @test all(o -> abs(o - 2.0) < 0.1, case.observed_orders)
        @test abs(case.observed_order - 2.0) < 0.1
        @test checks_committed([case]) == String[]
    end
end

@testitem "committed convergence data: every case, and the check catches changes" setup = [
    LP_convergence_orders,
] tags = [
    :latticepde, :convergence,
] begin
    names = [row["name"] for row in COMMITTED_CONVERGENCE]
    @test names == [
        "ExplicitEuler", "BackwardEuler", "CrankNicolson", "BDF2", "FieldGroups IMEX",
        "DivKGrad harmonic", "DivKGrad arithmetic", "Advect Upwind1", "Robin face",
        "Hexagonal Laplacian", "Laplacian (LatticePCG)",
    ]
    # the file agrees with itself, read back as computed records
    asrecord(r) = (; (Symbol(k) => r[String(k)] for k in CONVERGENCE_FIELDS)...)
    records = asrecord.(COMMITTED_CONVERGENCE)
    @test convergence_data_issues(COMMITTED_CONVERGENCE, records) == String[]
    # negative controls: a perturbed error, a changed expected order, a missing case
    perturbed = deepcopy(COMMITTED_CONVERGENCE)
    perturbed[3]["errors"][2] *= 1.01
    issues = convergence_data_issues(perturbed, records)
    @test length(issues) == 1 && startswith(only(issues), "CrankNicolson: errors")
    perturbed = deepcopy(COMMITTED_CONVERGENCE)
    perturbed[1]["expected_order"] = 2.0
    @test length(convergence_data_issues(perturbed, records)) == 1
    @test convergence_data_issues(COMMITTED_CONVERGENCE[2:end], records) ==
        ["ExplicitEuler: not in the data file"]
    @test convergence_data_issues(COMMITTED_CONVERGENCE, records[2:end]) ==
        ["ExplicitEuler: in the data file, but not a case"]
end

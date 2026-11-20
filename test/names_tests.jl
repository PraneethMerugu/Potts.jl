# The public names of the packages: exported and public names and the keywords of the
# algorithm constructors are ASCII (`Δ`, the notation alias of `laplacian`, is the one
# exception), the old names of the conformance renames stay removed, and no export clashes
# with a package that a user loads beside ours. The checks are in shared/names_checks.jl;
# add a package here with its own allowlists (MakiePotts has its own in
# lib/MakiePotts/test).

@testsetup module NamesSetup
using Potts, CorePotts, PottsModels
include(joinpath(@__DIR__, "shared", "names_checks.jl"))
const LF = Potts.LatticeFields
const LP = Potts.LatticePDE
const LF_MODULES = (LF, LF.IR, LF.Compile, LF.Schedule, LF.Exec, LF.Solvers, LF.Problems)
end

@testitem "field libraries: exported and public names are ASCII" setup = [
    NamesSetup,
] tags = [
    :potts, :names,
] begin
    using .NamesSetup: LF_MODULES, LP, non_ascii_names
    @testset "field libraries: exported and public names are ASCII" begin
        for mod in LF_MODULES
            @test isempty(non_ascii_names(mod)) ||
                (println(mod, ": ", non_ascii_names(mod)); false)
        end
        @test non_ascii_names(LP) == [:Δ]
        @test non_ascii_names(LP; allow = (:Δ,)) == Symbol[]
        @test LP.Δ === LP.laplacian && !Base.isexported(LP, :Δ)
    end
end

@testitem "field libraries: the keywords of the algorithm constructors are ASCII" setup = [
    NamesSetup,
] tags = [
    :potts, :names,
] begin
    using .NamesSetup: LF, LP
    @testset "field libraries: the keywords of the algorithm constructors are ASCII" begin
        P, S = LF.Problems, LF.Solvers
        ctors = (
            P.ExplicitEuler, P.ExplicitMap, P.LatticeNewton, P.BackwardEuler,
            P.CrankNicolson, P.BDF2, P.QuasiSteady, P.FieldGroups,
            S.LatticePCG, S.LatticeGMRES, S.LatticeMultigrid, LP.LatticeDiscretization,
        )
        function kwargs(f)
            return unique!(
                reduce(vcat, (Base.kwarg_decl(m) for m in methods(f)); init = Symbol[])
            )
        end
        for f in ctors
            kws = kwargs(f)
            @test !isempty(kws) || f === P.ExplicitMap
            @test all(
                k -> isascii(String(k)) || (f === P.LatticeNewton && k === :κ),
                kws
            ) ||
                (println(f, ": ", kws); false)
        end
        # the solver keywords have their SciML names; the window `dt` is a keyword of
        # `solve`
        @test :linsolve in kwargs(P.BackwardEuler)
        @test :κ in kwargs(P.LatticeNewton) && :max_iter in kwargs(P.LatticeNewton) &&
            :check_div in kwargs(P.LatticeNewton)
        @test :maxiters in kwargs(S.LatticePCG) && :reltol in kwargs(S.LatticePCG)
        @test :gmres_restart in kwargs(S.LatticeGMRES)
        @test :dt ∉ kwargs(P.ExplicitEuler)
    end
end

@testitem "field libraries: the renamed names are gone" setup = [NamesSetup] tags = [
    :potts, :names,
] begin
    using .NamesSetup: LF, LP, Potts
    @testset "field libraries: the renamed names are gone" begin
        removed = (
            LF.Problems => (:FieldAlgorithm, :ImplicitAlgorithm, :PolicyTexts, :LatticeMG),
            LF.IR => (:BRule,),
            LF.Solvers => (:V, :Multigrid),
            LP => (
                :at, :at2, :AdvectionScheme, :jacobian_sparsity,
                :LatticeMG, :PottsEntity, :get_potts_entity, :Multigrid,
            ),
            Potts => (:at, :at2, :Multigrid),
        )
        for (mod, ns) in removed, n in ns
            @test !isdefined(mod, n) || (println(mod, ".", n, " is still defined"); false)
        end
        # their replacements
        @test LF.Problems.AbstractImplicitFieldAlgorithm <:
        LF.Problems.AbstractFieldAlgorithm
        @test isabstracttype(LF.Problems.AbstractPolicyTexts) &&
            isabstracttype(LF.IR.AbstractBoundaryRule)
        @test isabstracttype(LP.AbstractAdvectionScheme) &&
            LP.Upwind1 <: LP.AbstractAdvectionScheme
        @test LF.Solvers.VCycle(2, 2) isa LF.Solvers.VCycle &&
            LP.LatticeMultigrid === LF.Problems.LatticeMultigrid
        @test LP.field_jacobian_sparsity === LF.Problems.field_jacobian_sparsity
        @test Base.ispublic(Potts, :PottsEntity) && !Base.isexported(Potts, :PottsEntity)
        @test Base.ispublic(Potts, :get_potts_entity) &&
            !Base.isexported(Potts, :get_potts_entity)
    end
end

@testitem "field libraries: no export clashes with the packages a user loads beside \
    them" setup = [NamesSetup] tags = [
    :potts, :names,
] begin
    using .NamesSetup: LF, LP, CLASH_PACKAGES, manifest_package, export_clashes
    @testset "field libraries: no export clashes with the packages a user loads beside \
        them" begin
        others = [manifest_package(p) for p in CLASH_PACKAGES]
        @test export_clashes(LF, others) == Pair{Symbol, Symbol}[]
        # `Grid` (the lattice of a discretization) is kept by ruling: Graphs exports a graph
        # generator of that name, and a user who loads both qualifies one
        @test export_clashes(LP, others) == [:Grid => :Graphs]
        @test export_clashes(LP, others; allow = (:Grid => :Graphs,)) ==
            Pair{Symbol, Symbol}[]
    end
end

@testitem "packages: exported and public names are ASCII" setup = [NamesSetup] tags = [
    :potts, :names,
] begin
    using .NamesSetup: Potts, CorePotts, PottsModels, non_ascii_names
    @testset "packages: exported and public names are ASCII" begin
        for mod in (CorePotts, Potts, Potts.Layouts, PottsModels, PottsModels.Analysis)
            @test isempty(non_ascii_names(mod)) ||
                (println(mod, ": ", non_ascii_names(mod)); false)
        end
    end
end

@testitem "packages: the renamed names are gone" setup = [NamesSetup] tags = [
    :potts,
    :names,
] begin
    using .NamesSetup: Potts, CorePotts, PottsModels
    @testset "packages: the renamed names are gone" begin
        removed = (
            CorePotts => (
                :shape, :neighbors, :contact, :Ball, :MeanFold,
                :CPMAlgorithm, :AcceptanceLaw, :RelationSpec,
                :TrackDeltaH, :BLOCK_GRAIN, :FUSE_SITES, :FUSE_CELLS,
            ),
            Potts => (:wrap,),
            PottsModels.Analysis => (:msd, :furth_msd, :trapz),
        )
        for (mod, ns) in removed, n in ns
            @test !isdefined(mod, n) || (println(mod, ".", n, " is still defined"); false)
        end
        # their replacements
        @test :ownership in fieldnames(CorePotts.CPMState) &&
            :σ ∉ fieldnames(CorePotts.CPMState)
        @test isabstracttype(CorePotts.AbstractCPMAlgorithm) &&
            CorePotts.SequentialCPM <: CorePotts.AbstractCPMAlgorithm
        @test isabstracttype(CorePotts.AbstractAcceptanceLaw) &&
            isabstracttype(CorePotts.AbstractRelationSpec)
        @test isabstracttype(CorePotts.AbstractNeighborhoodMean)
        for n in (:cell_shape, :contact_neighbors, :contact_measure, :EuclideanBall)
            @test Base.isexported(CorePotts, n)
        end
        @test Base.ispublic(CorePotts, :TrackEnergyChange)
        @test :accepted_energy_change in fieldnames(CorePotts.PottsStats) &&
            :accepted_ΔH ∉ fieldnames(CorePotts.PottsStats)
        # names that clash with a package loaded beside Potts are public, not exported
        for n in (
                :declared_parameters, :declared_variables, :RK4, :wrap_system, :anneal,
                :Layouts,
            )
            @test Base.ispublic(Potts, n) && !Base.isexported(Potts, n)
        end
        @test !isdefined(Potts, :parameters) || !Base.isexported(Potts, :parameters)
        @test !isdefined(Potts, :variables) || !Base.isexported(Potts, :variables)
        for n in (
                :mean_squared_displacement, :furth_mean_squared_displacement,
                :trapezoid_integral,
            )
            @test Base.isexported(PottsModels.Analysis, n)
        end
    end
end

@testitem "packages: the layout words are opt-in" setup = [NamesSetup] tags = [
    :potts,
    :names,
] begin
    using .NamesSetup: Potts
    @testset "packages: the layout words are opt-in" begin
        words = (
            :AbstractLayout, :Tiling, :Scattered, :Frame, :InsertUntil,
            :overlay, :layout, :HyperSphere, :Circle,
            :Sphere, :Point, :Center, :RandomPoints, :Voronoi, :Eden,
            :Splits, :Interior, :Fill, :Objects, :Group,
        )
        for n in words
            @test Base.isexported(Potts.Layouts, n) && !Base.isexported(Potts, n)
            # the layout words are Potts's own (public there too); the shapes are
            # GeometryBasics'
            isdefined(Potts, n) && @test getglobal(Potts.Layouts, n) === getglobal(Potts, n)
        end
        for n in (:HyperSphere, :Circle, :Sphere, :Point)
            @test parentmodule(getglobal(Potts.Layouts, n)) !== Potts
        end
    end
end

@testitem "packages: the DSL names are ASCII, primes are aliases" setup = [
    NamesSetup,
] tags = [
    :potts, :names,
] begin
    using Potts
    @testset "packages: the DSL names are ASCII, primes are aliases" begin
        @test all(n -> isascii(String(n)), Potts.BUILTIN_NAMES)
        @test all(n -> isascii(String(n)), keys(Potts.DSL))
        @test :neighbor_kind in Potts.BUILTIN_NAMES &&
            :neighbor_owner in Potts.BUILTIN_NAMES
        @potts_model NamesAscii begin
            @kinds medium dark light
            @parameters J[kind, kind] = [0.0 2.0 2.0; 2.0 1.0 3.0; 2.0 3.0 1.0]
            @variables c(site) = 0.0
            @lattice Lattice((24, 24))
            @sweep Metropolis(; temperature = 1.0)
            @energy contacts =>
                J[kind, neighbor_kind] + (owner == neighbor_owner) + c * neighbor(c)
        end
        @potts_model NamesPrimed begin
            @kinds medium dark light
            @parameters J[kind, kind] = [0.0 2.0 2.0; 2.0 1.0 3.0; 2.0 3.0 1.0]
            @variables c(site) = 0.0
            @lattice Lattice((24, 24))
            @sweep Metropolis(; temperature = 1.0)
            @energy contacts => J[kind, kind′] + (owner == owner′) + c * c′
        end
        @named ascii = NamesAscii()
        @named primed = NamesPrimed()
        @test string.(last.(Potts.hamiltonian(ascii))) ==
            string.(last.(Potts.hamiltonian(primed)))
        @test occursin("neighbor_kind", string(last(only(Potts.hamiltonian(ascii)))))
        # a model needs a name, as an MTK system does
        @test_throws UndefKeywordError NamesAscii()
    end
end

@testitem "packages: no export clashes with the packages a user loads beside them" setup = [
    NamesSetup,
] tags = [
    :potts, :names,
] begin
    using .NamesSetup: Potts, CorePotts, PottsModels, CLASH_PACKAGES, manifest_package,
        export_clashes
    @testset "packages: no export clashes with the packages a user loads beside them" begin
        others = [manifest_package(p) for p in CLASH_PACKAGES]
        for mod in (CorePotts, Potts, PottsModels)
            @test export_clashes(mod, others) == Pair{Symbol, Symbol}[]
        end
        # the opt-in submodules keep their words: `using Potts.Layouts` brings
        # GeometryBasics' `Point` and `Sphere` (DomainSets has its own), `using
        # PottsModels.Analysis` brings `components` (the connected components of a cell
        # graph) `Fill` (a layout filling a region) is kept too: FillArrays exports an array
        # of that name
        layouts_allow = (
            :Fill => :FillArrays, :Point => :DomainSets, :Sphere => :DomainSets,
        )
        # and `t`, MTK's unitless `t_nounits` (ModelingToolkitBase's own `t` carries units
        # and is public, not exported) `using Potts.Fields` brings `Δ` (Graphs exports a
        # maximum-degree function of that name) and `t`, MTK's unitless `t_nounits`
        # (ModelingToolkitBase's own `t` carries units)
        fields_allow = (:t => :ModelingToolkitBase, :Δ => :Graphs)
        @test export_clashes(Potts.Fields, others; allow = fields_allow) ==
            Pair{Symbol, Symbol}[]
        @test export_clashes(PottsModels.Analysis, others) ==
            [:components => :Distributions, :components => :DomainSets]
    end
end

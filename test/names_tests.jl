# The public names of the field libraries LatticeFields and LatticePDE: exported and public
# names and the keywords of the algorithm constructors are ASCII (`Δ`, the notation alias of
# `laplacian`, is the one exception), the old names of the conformance renames stay removed,
# and no export clashes with a package that a user loads beside ours. The checks are in
# shared/names_checks.jl; add a package here with its own allowlists.

@testsetup module NamesSetup
using Potts
include(joinpath(@__DIR__, "shared", "names_checks.jl"))
const LF = Potts.LatticeFields
const LP = Potts.LatticePDE
const LF_MODULES = (LF, LF.IR, LF.Compile, LF.Schedule, LF.Exec, LF.Solvers, LF.Problems)
end

@testitem "field libraries: exported and public names are ASCII" setup = [NamesSetup] tags = [:potts, :names] begin
    using .NamesSetup: LF_MODULES, LP, non_ascii_names
    @testset "field libraries: exported and public names are ASCII" begin
        for mod in LF_MODULES
            @test isempty(non_ascii_names(mod)) || (println(mod, ": ", non_ascii_names(mod)); false)
        end
        @test non_ascii_names(LP) == [:Δ]
        @test non_ascii_names(LP; allow = (:Δ,)) == Symbol[]
        @test LP.Δ === LP.laplacian && !Base.isexported(LP, :Δ)
    end
end

@testitem "field libraries: the keywords of the algorithm constructors are ASCII" setup = [NamesSetup] tags = [:potts, :names] begin
    using .NamesSetup: LF, LP
    @testset "field libraries: the keywords of the algorithm constructors are ASCII" begin
        P, S = LF.Problems, LF.Solvers
        ctors = (
            P.ExplicitEuler, P.ExplicitMap, P.BackwardEuler, P.CrankNicolson, P.BDF2, P.QuasiSteady, P.FieldGroups,
            S.DevicePCG, S.DeviceGMRES, S.Multigrid, LP.LatticeDiscretization,
        )
        kwargs(f) = unique!(reduce(vcat, (Base.kwarg_decl(m) for m in methods(f)); init = Symbol[]))
        for f in ctors
            kws = kwargs(f)
            @test !isempty(kws) || f === P.ExplicitMap
            @test all(k -> isascii(String(k)), kws) || (println(f, ": ", kws); false)
        end
        # the solver keywords have their SciML names; the window `dt` is a keyword of `solve`
        @test :linsolve in kwargs(P.BackwardEuler)
        @test :maxiters in kwargs(S.DevicePCG) && :reltol in kwargs(S.DevicePCG)
        @test :gmres_restart in kwargs(S.DeviceGMRES)
        @test :dt ∉ kwargs(P.ExplicitEuler)
    end
end

@testitem "field libraries: the renamed names are gone" setup = [NamesSetup] tags = [:potts, :names] begin
    using .NamesSetup: LF, LP, Potts
    @testset "field libraries: the renamed names are gone" begin
        removed = (
            LF.Problems => (:FieldAlgorithm, :ImplicitAlgorithm, :PolicyTexts, :LatticeMG),
            LF.IR => (:BRule,),
            LF.Solvers => (:V,),
            LP => (:at, :at2, :AdvectionScheme, :jacobian_sparsity, :LatticeMG, :PottsEntity, :get_potts_entity),
            Potts => (:at, :at2),
        )
        for (mod, ns) in removed, n in ns
            @test !isdefined(mod, n) || (println(mod, ".", n, " is still defined"); false)
        end
        # their replacements
        @test LF.Problems.AbstractImplicitFieldAlgorithm <: LF.Problems.AbstractFieldAlgorithm
        @test isabstracttype(LF.Problems.AbstractPolicyTexts) && isabstracttype(LF.IR.AbstractBoundaryRule)
        @test isabstracttype(LP.AbstractAdvectionScheme) && LP.Upwind1 <: LP.AbstractAdvectionScheme
        @test LF.Solvers.VCycle(2, 2) isa LF.Solvers.VCycle && LP.LatticeMultigrid === LF.Problems.LatticeMultigrid
        @test LP.field_jacobian_sparsity === LF.Problems.field_jacobian_sparsity
        @test Base.ispublic(Potts, :PottsEntity) && !Base.isexported(Potts, :PottsEntity)
        @test Base.ispublic(Potts, :get_potts_entity) && !Base.isexported(Potts, :get_potts_entity)
    end
end

@testitem "field libraries: no export clashes with the packages a user loads beside them" setup = [NamesSetup] tags = [:potts, :names] begin
    using .NamesSetup: LF, LP, CLASH_PACKAGES, manifest_package, export_clashes
    @testset "field libraries: no export clashes with the packages a user loads beside them" begin
        others = [manifest_package(p) for p in CLASH_PACKAGES]
        @test export_clashes(LF, others) == Pair{Symbol, Symbol}[]
        # `Grid` (the lattice of a discretization) is kept by ruling: Graphs exports a graph
        # generator of that name, and a user who loads both qualifies one
        @test export_clashes(LP, others) == [:Grid => :Graphs]
        @test export_clashes(LP, others; allow = (:Grid => :Graphs,)) == Pair{Symbol, Symbol}[]
    end
end

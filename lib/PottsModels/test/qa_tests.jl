# Quality checks of PottsModels: Aqua, ExplicitImports, API docs, the error-message rules,
# JET and allocations.
@testsetup module QualitySetup
using Test, Potts, PottsModels
using Potts: CorePotts
using AllocCheck: AllocCheck
using CairoMakie: CairoMakie
using MakiePotts: MakiePotts
using JET: @test_opt
include(joinpath(@__DIR__, "..", "..", "..", "test", "shared", "qa_common.jl"))
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "PottsModels QA" setup = [QualitySetup] tags = [:pottsmodels, :qa] begin
    @testset "PottsModels QA" begin
        @testset "Aqua" begin
            # `check_extras = false`: workspace test-only deps live in test/Project.toml.
            qa_aqua(PottsModels; deps_compat = (; check_extras = false))
            # the piracy check inside each loaded extension
            exts = qa_extension_piracies(PottsModels)
            @test Base.get_extension(PottsModels, :PottsModelsMakieExt) in exts
        end

        @testset "ExplicitImports" begin
            # `R2HC`, `r2r`: FFTW's documented real-to-halfcomplex plan API, not declared
            # `public` in FFTW.
            qa_explicit_imports(PottsModels; nonpublic_explicit = (:R2HC, :r2r))
        end

        @testset "API docs and extensions" begin
            qa_api_docs(
                PottsModels;
                submodules = (PottsModels.Analysis,),
                docs_dir = joinpath(@__DIR__, "..", "..", "..", "docs")
            )
            @test Base.get_extension(PottsModels, :PottsModelsMakieExt) !== nothing
        end

        @testset "Error and message rules" begin
            qa_error_rules(
                pkgdir(PottsModels);
                reviewed_invariants = ["src/benchmarks/openvt_package.jl"]
            )
        end

        @testset "JET and AllocCheck" begin
            @test_opt target_modules = (PottsModels,) akeeb_contacts(2.0)
            σ, kinds = graner_glazier_state()
            prob = PottsProblem(
                GranerGlazier(; name = :gg_qa), [
                    ownership => σ, kind => kinds,
                ], (0, 2)
            )
            integ = init(
                prob, SequentialCPM(; proposal = Moore(1)); save_start = false,
                save_everystep = false
            )
            step!(integ)
            @test_opt target_modules = (PottsModels, Potts, CorePotts) step!(integ)
            @test (@allocated step!(integ)) == 0
            # AllocCheck static verification on pure scalar helper / warm integrator
            # accessor
            @test isempty(
                AllocCheck.check_allocs(
                    x -> PottsModels.akeeb_phenotype(x, 12.0),
                    (Float64,)
                )
            )
        end
    end
end

# JET's error analysis of the whole package: undefined names and fields (D-298)
@testitem "PottsModels QA: JET package analysis" setup = [QualitySetup] tags = [
    :pottsmodels, :qa,
] begin
    @testset "PottsModels QA: JET package analysis" begin
        qa_jet_package(
            PottsModels;
            locals = [
                # the `&&` in the OpenVT reference model's update lowers to a closure, which
                # captures the parameter `γ` of the generated constructor through a box
                r"`γ` is not defined \(macro\.jl\)" => "boxed capture in generated code",
            ]
        )
    end
end

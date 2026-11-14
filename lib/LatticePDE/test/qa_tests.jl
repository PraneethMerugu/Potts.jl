@testsetup module LP_qa
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
include("shared/export_all.jl")
end

@testitem "QA" setup = [LP_qa] tags = [:latticepde, :qa] begin
    @testset "QA" begin
        using Aqua, ExplicitImports
        Aqua.test_all(LatticePDE; ambiguities = false)
        @test isempty(Test.detect_ambiguities(LatticePDE))
        @test isempty(Docs.undocumented_names(LatticePDE; private = false))
        @test check_no_implicit_imports(LatticePDE) === nothing
        @test check_no_stale_explicit_imports(LatticePDE) === nothing
        @test check_all_qualified_accesses_via_owners(LatticePDE) === nothing
        # `VarDomainPairing` (what `x ∈ (a, b)` builds) is not declared public by Symbolics
        @test check_all_explicit_imports_are_public(LatticePDE; ignore = (:VarDomainPairing,)) === nothing
        # `get_unit` (MTK unit inference, which registered operators extend) is
        # not declared public by ModelingToolkitBase
        @test check_all_qualified_accesses_are_public(LatticePDE; ignore = (:get_unit,)) === nothing
        # no model, paper or author names in the package or its tests (BRIEF rules)
        files = [joinpath(d, f) for dir in ("src", "test") for (d, _, fs) in walkdir(joinpath(@__DIR__, "..", dir))
                 for f in fs if endswith(f, ".jl")]
        banned = Regex("\\b(" * join(["Jiang", "Merks", "Bauer", "Graner", "Glazier", "Fortuna", "Hogeweg", "Szabo",
                                        "Marée", "FBCA", "OpenVT"], "|") * ")\\b")
        @test isempty(filter(f -> normpath(f) != normpath(@__FILE__) && occursin(banned, read(f, String)), files))
        @test !any(f -> occursin("@generated", read(f, String)), filter(f -> occursin("/src/", f), files))
    end
end

# QA: ExplicitImports, the name ban (no model, paper or author names in the package or its
# tests), and no `@generated` in the source.

@testsetup module LF_qa_qa
using Test, LatticeFields
# imports an earlier file made in the old single Main
using LatticeFields: Compile
using ForwardDiff: Dual
using ExplicitImports: ExplicitImports, check_no_implicit_imports,
                       check_all_explicit_imports_are_public,
                       check_no_stale_explicit_imports,
                       check_all_qualified_accesses_via_owners,
                       check_all_qualified_accesses_are_public

const LF_NONPUBLIC = (
    :RuntimeGeneratedFunction, :drop_expr,  # RGF's documented API; the package declares no `public`
    :remove_linenums!,                     # Base.remove_linenums!: canonical body text for hashing
    :RefValue,                             # Base's concrete `Ref` type: the concrete cells of `LatticeParameters` and the lazy right side (F4-00)
    :Dual, :Partials, :partials, :value,   # ForwardDiff's documented Dual API (extension); no `public`
    :Compile,                              # the extension extends LatticeFields.Compile (declared public with the module list at C2/C7a)
    :supports_float64,                     # KernelAbstractions' Float64 capability query (Metal: false); KA declares no `public`
    :deepcopy_internal,                    # Base's documented hook for a type's own `deepcopy` (LatticeRHS: a copy has no owner task, SX-37)
    :dotview,                              # Base's hook for `a[i] .= v` (FieldIntegrator: an error, not a write into a copy)
    :DefaultInit,                          # DiffEqBase's default DAE init algorithm, which OrdinaryDiffEqCore imports and documents; no `public` (F4-02)
    :inferencebarrier,                     # Base's inference barrier (`init` binds each group at its own algorithm's type, F3 r2)
    :kdot, :knorm, :kaxpy!, :kaxpby!, :kcopy!, :kdivcopy!, :kfill!,  # Krylov.jl's vector functions, the documented hook of a custom vector type (F3-12d `CoupledVector`); no `public` (compat 0.10)
    :Tag,                                  # ForwardDiff's documented tag of a Dual (the extension's colored Jacobian and JVP, F4-07); no `public`
    :AbstractKrylovSubspaceMethod, :init_cacheval, :needs_concrete_A, :LinearCache  # LinearSolve's documented hooks of a new algorithm (the extension's `LatticePCG`, F4-08); no `public`
)
include("../shared/export_all.jl")
end

@testitem "ExplicitImports" setup = [LF_qa_qa] tags = [:latticefields, :qa] begin
@testset "ExplicitImports" begin
    @test check_no_implicit_imports(LatticeFields) === nothing
    @test check_all_explicit_imports_are_public(LatticeFields; ignore = LF_NONPUBLIC) ===
          nothing
    @test check_no_stale_explicit_imports(LatticeFields) === nothing
    @test check_all_qualified_accesses_via_owners(LatticeFields) === nothing
    @test check_all_qualified_accesses_are_public(LatticeFields; ignore = LF_NONPUBLIC) ===
          nothing
end
end

@testitem "API docs and extensions" setup = [LF_qa_qa] tags = [:latticefields, :qa] begin
using OrdinaryDiffEqRosenbrock: OrdinaryDiffEqRosenbrock
@testset "Docs.undocumented_names and extensions (LatticeFields)" begin
    @test isempty(Docs.undocumented_names(LatticeFields; private = false))
    @test Base.get_extension(LatticeFields, :LatticeFieldsForwardDiffExt) !== nothing
    @test Base.get_extension(LatticeFields, :LatticeFieldsDiffEqBaseExt) !== nothing
    @test Base.get_extension(LatticeFields, :LatticeFieldsOrdinaryDiffEqCoreExt) !== nothing
    if any(k -> k.name == "LinearSolve", keys(Base.loaded_modules))
        @test Base.get_extension(LatticeFields, :LatticeFieldsLinearSolveExt) !== nothing
    end
end
end

@testitem "Aqua" setup = [LF_qa_qa] tags = [:latticefields, :qa] begin
@testset "Aqua" begin
    using Aqua: Aqua
    Aqua.test_all(LatticeFields)
end
end

# Aqua's ambiguity check loads only LatticeFields' own dependencies. A user's session also
# loads array and polynomial packages whose generic methods (`==` on any AbstractArray) can be
# ambiguous with LatticeFields' own (f2d9c774 had 8 such, with these three loaded): load them
# here and require LatticeFields to add none (a guard).
@testitem "no ambiguities with common array packages loaded" setup = [LF_qa_qa] tags = [:latticefields, :qa] begin
@testset "no ambiguities with common array packages loaded" begin
    @eval using ArrayLayouts: ArrayLayouts
    @eval using DynamicPolynomials: DynamicPolynomials
    @eval using SparseArrays: SparseArrays
    @test isempty(Test.detect_ambiguities(LatticeFields; recursive = true))
end
end

@testitem "source rules" setup = [LF_qa_qa] tags = [:latticefields, :qa] begin
@testset "source rules" begin
    root = dirname(@__DIR__) |> dirname
    files = [joinpath(d, f) for dir in ("src", "test")
             for (d, _, fs) in walkdir(joinpath(root, dir))
             for f in fs if endswith(f, ".jl")]
    banned = r"\b(Jiang|Merks|Bauer|Graner|Glazier|Fortuna|Hogeweg|Szabo|Marée|FBCA|OpenVT)\b"
    hits = [f for f in files if f != (@__FILE__) && occursin(banned, read(f, String))]
    @test isempty(hits)
    @test !any(f -> occursin("@generated", read(f, String)), filter(f -> occursin("/src/", f), files))
end
end

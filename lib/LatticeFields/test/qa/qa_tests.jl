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
    :RefValue,                             # Base's concrete `Ref` type: the concrete cells of `LatticeParameters` and the lazy right side
    :Dual, :Partials, :partials, :value,   # ForwardDiff's documented Dual API (extension); no `public`
    :Compile,                              # the extension extends LatticeFields.Compile (declared public with the module list)
    :supports_float64,                     # KernelAbstractions' Float64 capability query (Metal: false); KA declares no `public`
    :deepcopy_internal,                    # Base's documented hook for a type's own `deepcopy` (LatticeRHS: a copy has no owner task)
    :dotview,                              # Base's hook for `a[i] .= v` (FieldIntegrator: an error, not a write into a copy)
    :DefaultInit,                          # DiffEqBase's default DAE init algorithm, which OrdinaryDiffEqCore imports and documents; no `public`
    :inferencebarrier,                     # Base's inference barrier (`init` binds each group at its own algorithm's type)
    :kdot, :knorm, :kaxpy!, :kaxpby!, :kcopy!, :kdivcopy!, :kfill!,  # Krylov.jl's vector functions, the documented hook of a custom vector type (`CoupledVector`); no `public` (compat 0.10)
    :Tag,                                  # ForwardDiff's documented tag of a Dual (the extension's colored Jacobian and JVP); no `public`
    :AbstractKrylovSubspaceMethod, :init_cacheval, :needs_concrete_A, :LinearCache,  # LinearSolve's documented hooks of a new algorithm
    :SciMLLinearSolveAlgorithm, :default_alias_A, :default_alias_b, :update_tolerances_internal!,  # (`LatticePCG`, `LatticeGMRES`, `LatticeMultigrid`; `algorithm_interface_issues`); no `public`
)
include(joinpath(@__DIR__, "..", "..", "..", "..", "test", "shared", "qa_common.jl"))
include("../shared/export_all.jl")
end

@testsetup module LF_qa_rhs
using Test, LatticeFields
using JET: @test_opt
include("../host_runner.jl")
include("../fixtures.jl")
include("../shared/problems_owned.jl")
using LatticeFields.Problems: LatticeRHS, ode_problem
include("../shared/export_all.jl")
end

@testitem "ExplicitImports" setup = [LF_qa_qa] tags = [:latticefields, :qa] begin
@testset "ExplicitImports" begin
        qa_explicit_imports(
            LatticeFields;
            nonpublic_explicit = LF_NONPUBLIC,
            nonpublic_qualified = LF_NONPUBLIC
        )
end
end

@testitem "API docs and extensions" setup = [LF_qa_qa] tags = [:latticefields, :qa] begin
using OrdinaryDiffEqRosenbrock: OrdinaryDiffEqRosenbrock
@testset "Docs.undocumented_names and extensions (LatticeFields)" begin
        # LatticeFields is an internal sublibrary not listed in docs/make.jl `modules`.
        qa_api_docs(LatticeFields; check_docs_blocks = false)
    @test Base.get_extension(LatticeFields, :LatticeFieldsForwardDiffExt) !== nothing
    @test Base.get_extension(LatticeFields, :LatticeFieldsDiffEqBaseExt) !== nothing
        @test Base.get_extension(LatticeFields, :LatticeFieldsOrdinaryDiffEqCoreExt) !== nothing
end
end

@testitem "Aqua" setup = [LF_qa_qa] tags = [:latticefields, :qa] begin
@testset "Aqua" begin
        qa_aqua(LatticeFields)
        # the piracy check inside each loaded extension (Aqua does not look inside them)
        @eval using OrdinaryDiffEqRosenbrock: OrdinaryDiffEqRosenbrock
        exts = qa_extension_piracies(LatticeFields)
        @test Base.get_extension(LatticeFields, :LatticeFieldsOrdinaryDiffEqCoreExt) in exts
end
end

# Aqua's ambiguity check loads only LatticeFields' own dependencies. A user's session also
# loads array and polynomial packages whose generic methods (`==` on any AbstractArray) can be
# ambiguous with LatticeFields' own (f2d9c774 had 8 such, with three of these loaded, and
# `getindex` on a solution was ambiguous with BlockArrays' and BandedMatrices' index types until
# D-298): load them here and require LatticeFields to add none (a guard).
@testitem "no ambiguities with common array packages loaded" setup = [LF_qa_qa] tags = [:latticefields, :qa] begin
    @testset "no ambiguities with common array packages loaded" begin
        @eval using ArrayLayouts: ArrayLayouts
        @eval using BandedMatrices: BandedMatrices
        @eval using BlockArrays: BlockArrays
        @eval using DynamicPolynomials: DynamicPolynomials
        @eval using SparseArrays: SparseArrays
        @test isempty(Test.detect_ambiguities(LatticeFields; recursive = true))
    end
end

@testitem "source rules" setup = [LF_qa_qa] tags = [:latticefields, :qa] begin
@testset "source rules" begin
    root = dirname(@__DIR__) |> dirname
        qa_source_rules(root; exclude_files = [@__FILE__])
        qa_error_rules(root; reviewed_invariants = ["src/compile/emit.jl", "src/problems/tangent.jl"])
end
end

# JET's error analysis of the whole package: undefined names and fields (D-298)
@testitem "JET package analysis" setup = [LF_qa_qa] tags = [:latticefields, :qa] begin
    @testset "JET package analysis" begin
        qa_jet_package(
            LatticeFields;
            broken = [
                # `_canonical_fields` reads `init` only when the field list has it
                # (`f === :init && getfield(s, f) …`); JET propagates `:init` into the
                # algorithms that have no such field
                r"LatticeGMRES has no field `init`" => "a branch JET cannot rule out",
                r"LatticePCG has no field `init`" => "a branch JET cannot rule out",
            ]
        )
    end
end

# the right side of the ODE form (`ODEFunction(LatticeRHS)`): its per-call work, the walk over
# the bound launches, has no runtime dispatch. The call's other branches (upload of new tables
# and inputs, derived slots, checks, init kernels, masked fields) dispatch at run time by design
# (function barriers on parameter changes); see D-298.
@testitem "JET: the ODE right side LatticeRHS" setup = [LF_qa_rhs] tags = [:latticefields, :qa] begin
    @testset "JET: the ODE right side LatticeRHS" begin
        dims = (12, 10)
        u0 = rand(Xoshiro(6), prod(dims))
        ix = LatticeIndex(; variables = [:u => FieldSlot(1:prod(dims), dims)])
        ode = ode_problem(
            euler2(dims; rate = true, storage = F64), u0, (0.0, 1.0), [0.5]; state = ["u"],
            rates = Dict("u" => "∂u"), index = ix, options = CompileOptions(; T = Float64)
        )
        rhs = ode.f.f
        @test rhs isa LatticeRHS
        du = similar(ode.u0)
        rhs(du, ode.u0, ode.p, 0.0)
        pv, k = LatticeFields.Problems._pvals(ode.p), LatticeFields.Problems._ptick(ode.p)
        @test_opt target_modules = (LatticeFields,) rhs.walk(rhs.launches, (du, ode.u0, pv, 0.0, k))
        # the walk is the whole per-call work: it alone gives the right side's rates
        du2 = zero(du)
        rhs.walk(rhs.launches, (du2, ode.u0, pv, 0.0, k))
        @test du2 == du
    end
end

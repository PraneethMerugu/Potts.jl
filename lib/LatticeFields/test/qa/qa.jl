# QA: ExplicitImports, the name ban (no model, paper or author names in the package or its
# tests), and no `@generated` in the source.

using ExplicitImports: ExplicitImports, check_no_implicit_imports,
                       check_all_explicit_imports_are_public,
                       check_no_stale_explicit_imports,
                       check_all_qualified_accesses_via_owners,
                       check_all_qualified_accesses_are_public

const LF_NONPUBLIC = (
    :RuntimeGeneratedFunction, :drop_expr,  # RGF's documented API; the package declares no `public`
    :remove_linenums!,                     # Base.remove_linenums!: canonical body text for hashing
    :Dual, :Partials, :partials, :value,   # ForwardDiff's documented Dual API (extension); no `public`
    :Compile                               # the extension extends LatticeFields.Compile (declared public with the module list at C2/C7a)
)

@testset "ExplicitImports" begin
    @test check_no_implicit_imports(LatticeFields) === nothing
    @test check_all_explicit_imports_are_public(LatticeFields; ignore = LF_NONPUBLIC) ===
          nothing
    @test check_no_stale_explicit_imports(LatticeFields) === nothing
    @test check_all_qualified_accesses_via_owners(LatticeFields) === nothing
    @test check_all_qualified_accesses_are_public(LatticeFields; ignore = LF_NONPUBLIC) ===
          nothing
end

@testset "Aqua" begin
    using Aqua: Aqua
    Aqua.test_all(LatticeFields)
end

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

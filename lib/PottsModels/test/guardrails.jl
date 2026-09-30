# Non-privilege guardrails (D-051 R0, review §6): the published models use only public
# primitives, build from `using Potts` alone, and the DSL surface changes only by review.
using ExplicitImports

@testset "PottsModels uses only public names" begin
    @test check_no_implicit_imports(PottsModels) === nothing
    @test check_all_explicit_imports_are_public(PottsModels) === nothing
    @test check_all_qualified_accesses_are_public(PottsModels) === nothing
    @test check_all_qualified_accesses_via_owners(PottsModels) === nothing
    @test check_no_stale_explicit_imports(PottsModels) === nothing
    @test check_no_self_qualified_accesses(PottsModels) === nothing
end

@testset "every model builds from `using Potts` alone" begin
    src = joinpath(@__DIR__, "..", "src")
    for f in sort(filter(f -> f != "PottsModels.jl" && endswith(f, ".jl"), readdir(src)))
        m = Module(Symbol(:Sandbox_, splitext(f)[1]))
        Core.eval(m, :(using Potts; using DelimitedFiles: readdlm; using Random: MersenneTwister))
        Base.include(m, joinpath(src, f))
        ctors = filter(n -> isdefined(m, n) && isuppercase(first(string(n))) && getfield(m, n) isa Function,
            names(m; all = true))
        @test !isempty(ctors)
        for c in ctors
            @test mtkcompile(getfield(m, c)(; name = :probe)) isa Potts.CompiledPottsSystem
        end
    end
end

# The reviewed DSL surface: every name the model body sees, and every keyword of its
# constructors. A new name or option (a model-shaped flag under a generic name, like the
# removed `extension_only`) must be reviewed and added here.
const DSL_NAMES = [:Adaptive, :Adhesion, :Chemotaxis, :Every, :ExplicitEuler, :RK4, :RandomPlane, :Split,
    :Surface, :Volume, :cells, :centroid, :clusters, :connectivity, :contacts, :displacement, :dot, :edges,
    :geomean, :integral, :log1p_geomean, :major_axis, :mean, :minor_axis, :new_contact, :no_extinction, :norm,
    :normalize, :principal_axis, :rand, :saturating, :saturating_linear, :sites, :Δ]
const DSL_KEYWORDS = Dict(:connectivity => [:rule], :Volume => [:strength, :target], :Surface => [:strength, :target],
    :Chemotaxis => [:kinds, :response, :strength, :when])

@testset "DSL surface snapshot" begin
    @test sort(collect(keys(Potts.DSL))) == sort(DSL_NAMES)
    kw = Dict{Symbol, Vector{Symbol}}()
    for (n, f) in pairs(Potts.DSL)
        f isa Function || continue
        ks = sort(unique(reduce(vcat, [Symbol.(Base.kwarg_decl(mm)) for mm in methods(f)]; init = Symbol[])))
        isempty(ks) || (kw[n] = ks)
    end
    @test kw == DSL_KEYWORDS
    @test_throws ArgumentError Potts.DSL.connectivity(1; rule = :unknown)       # Symbol options are checked
end

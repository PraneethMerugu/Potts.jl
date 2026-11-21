# Non-privilege guardrails (D-051 R0, review §6): the published models use only public
# primitives, build from `using Potts` alone, and the DSL vocabulary is documented.

@testsetup module GuardrailsSetup
include(joinpath(@__DIR__, "shared", "common.jl"))
using ExplicitImports
using CairoMakie: CairoMakie
using MakiePotts: MakiePotts
# The reproduction scripts are not modules, so ExplicitImports cannot see them: walk their
# syntax instead. For the family modules `Potts`, `CorePotts` and `PottsModels`:
# - every qualified access `M.x` must name a public binding, chains link by link
#   (`Potts.CorePotts.x` checks `Potts.CorePotts`, then `CorePotts.x`);
# - every `using/import` path must be public link by link, with or without a colon
#   (`using Potts.CorePotts: x`, `import Potts.x`), and so must each imported name;
# - a family module may not be bound to another name (`import Potts as P`,
#   `using Potts: CorePotts as C`, `const P = Potts`): an alias would hide later accesses.
# Not handled: reflection (`getproperty(Potts, :x)`, `getfield`, `@eval`).
const POTTS_FAMILY = Dict(
    :Potts => Potts, :CorePotts => Potts.CorePotts, :PottsModels =>
        PottsModels
)
_isfamily(v) = v isa Module && get(POTTS_FAMILY, nameof(v), nothing) === v
function nonpublic_accesses(ex, bad = String[])
    ex isa Expr || return bad
    if ex.head === :. && length(ex.args) == 2 && ex.args[2] isa QuoteNode
        m = _family_module(ex.args[1], bad)
        if m !== nothing
            x = ex.args[2].value
            Base.ispublic(m, x) || push!(bad, "$(nameof(m)).$x")
            return bad
        end
    elseif ex.head in (:using, :import)
        if length(ex.args) == 1 && ex.args[1] isa Expr && ex.args[1].head === :(:)
            path, items... = ex.args[1].args
            m = _resolve_path(path.args, bad)
            m isa Module || return bad
            for it in items
                x = it.head === :as ? it.args[1].args[end] : it.args[end]
                Base.ispublic(m, x) || push!(bad, "$(nameof(m)).$x (imported)")
                it.head === :as && _isfamily(isdefined(m, x) ? getfield(m, x) : nothing) &&
                    push!(bad, "alias $(it.args[2]) = $x")
            end
        else
            for it in ex.args
                path = it.head === :as ? it.args[1].args : it.args
                v = _resolve_path(path, bad)
                it.head === :as && _isfamily(v) &&
                    push!(bad, "alias $(it.args[2]) = $(join(path, '.'))")
            end
        end
        return bad
    elseif ex.head === :(=) && length(ex.args) == 2
        rhs = ex.args[2]
        v = rhs isa Symbol ? get(POTTS_FAMILY, rhs, nothing) : _family_module(rhs, bad)
        v === nothing || push!(bad, "alias $(ex.args[1]) = $(nameof(v))")
    end
    foreach(a -> nonpublic_accesses(a, bad), ex.args)
    return bad
end
# The family module a qualified-access prefix names (`nothing` if none); a non-public link
# of a chain (`Potts.CorePotts`) is pushed to `bad`.
function _family_module(p, bad)
    p isa Symbol && return get(POTTS_FAMILY, p, nothing)
    p isa Expr && p.head === :. && length(p.args) == 2 && p.args[2] isa QuoteNode ||
        return nothing
    m = _family_module(p.args[1], bad)
    m === nothing && return nothing
    x = p.args[2].value
    v = isdefined(m, x) ? getfield(m, x) : nothing
    _isfamily(v) || return nothing
    Base.ispublic(m, x) || push!(bad, "$(nameof(m)).$x")
    return v
end
# A `using/import` path (symbols) from a family module, checked link by link: every link
# after the first must be public in the module before it. Returns what the path names
# (`nothing` if it does not start at a family module).
function _resolve_path(path, bad)
    m = get(POTTS_FAMILY, first(path), nothing)
    m === nothing && return nothing
    v = m
    for x in path[2:end]
        v isa Module || return nothing
        Base.ispublic(v, x) || push!(bad, "$(nameof(v)).$x")
        v = isdefined(v, x) ? getfield(v, x) : nothing
    end
    return v
end
nonpublic_accesses(src::AbstractString) = nonpublic_accesses(Meta.parseall(src))
# The DSL vocabulary (`Potts.DSL`, the names a model body sees) is not exported, so
# `Docs.undocumented_names` cannot see it: every name must be documented, in a Potts
# docstring or in the manual. A new name passes once it is documented; the surface itself is
# reviewed in the diff of `Potts.DSL`, not pinned here.
function dsl_docs_corpus()
    texts = String[]
    for (_, md) in Docs.meta(Potts), d in values(md.docs)
        push!(texts, join(string.(d.text)))
    end
    manual = joinpath(pkgdir(Potts), "docs", "src", "manual")
    for f in readdir(manual; join = true)
        endswith(f, ".md") && push!(texts, read(f, String))
    end
    return join(texts, "\n")
end
# a docstring bound to Potts's own name (not one Potts takes from Base or a stdlib, like
# `rand`), or the name in backticks in a docstring or the manual
function dsl_documented(corpus, n)
    return (Docs.Binding(Potts, n).mod === Potts && Base.Docs.hasdoc(Potts, n)) ||
        occursin(Regex("`" * string(n) * "[`(\\[ ]"), corpus)
end
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

@testitem "PottsModels uses only public names" setup = [GuardrailsSetup] tags = [
    :pottsmodels, :guardrails,
] begin
    @testset "PottsModels uses only public names" begin
        @test check_no_implicit_imports(PottsModels) === nothing
        # FFTW documents but does not export `r2r` and its kinds; `rfft` is ambiguous once
        # FFTA (a KernelDensity dependency) is loaded (`Analysis.power_spectrum`)
        @test check_all_explicit_imports_are_public(PottsModels; ignore = (:R2HC, :r2r)) ===
            nothing
        # no exception: `akeeb_state` draws its clocks through the public `Potts.layer_rng`
        # (D-138)
        @test check_all_qualified_accesses_are_public(PottsModels) === nothing
        @test check_all_qualified_accesses_via_owners(PottsModels) === nothing
        @test check_no_stale_explicit_imports(PottsModels) === nothing
        @test check_no_self_qualified_accesses(PottsModels) === nothing
    end
end

@testitem "PottsModels docs and extensions" setup = [GuardrailsSetup] tags = [
    :pottsmodels, :guardrails,
] begin
    @testset "PottsModels docs and extensions" begin
        @test isempty(Docs.undocumented_names(PottsModels; private = false))
        @test isempty(Docs.undocumented_names(PottsModels.Analysis; private = false))
        @test Base.get_extension(PottsModels, :PottsModelsMakieExt) !== nothing
        if isdefined(@__MODULE__, :PottsDevices) && PottsDevices.device_name() == "rocm"
            @test Base.get_extension(PottsModels, :PottsModelsAMDGPUExt) !== nothing
        end
    end
end

@testitem "reproduction scripts use only public names" setup = [GuardrailsSetup] tags = [
    :pottsmodels, :guardrails,
] begin
    @testset "reproduction scripts use only public names" begin
        dir = joinpath(@__DIR__, "..", "reproductions")
        scripts = sort(filter(endswith(".jl"), readdir(dir)))
        @test !isempty(scripts)
        for f in scripts
            @test isempty(nonpublic_accesses(read(joinpath(dir, f), String)))
        end
        # negative controls: each form is caught, and public names pass
        @test nonpublic_accesses("Potts.lattice_spec((4, 4))") == ["Potts.lattice_spec"]
        @test nonpublic_accesses(
            "f(x) = CorePotts.linear_index(l, x) + CorePotts._embed(g, x)"
        ) ==
            ["CorePotts._embed"]
        @test nonpublic_accesses("Potts.CorePotts.shift(l, x, o)") == ["Potts.CorePotts"]
        @test nonpublic_accesses("Potts.CorePotts._embed(g, x)") ==
            ["Potts.CorePotts", "CorePotts._embed"]
        @test nonpublic_accesses("using Potts: layout, lattice_spec") ==
            ["Potts.lattice_spec (imported)"]
        @test nonpublic_accesses("import Potts: lattice_spec as ls") ==
            ["Potts.lattice_spec (imported)"]
        @test nonpublic_accesses("using Potts.CorePotts: shift") == ["Potts.CorePotts"]
        @test nonpublic_accesses("using CorePotts: shift, _embed") ==
            ["CorePotts._embed (imported)"]
        @test nonpublic_accesses("import Potts.lattice_spec") == ["Potts.lattice_spec"]
        @test nonpublic_accesses("using Potts, Potts.CorePotts") == ["Potts.CorePotts"]
        @test nonpublic_accesses("import Potts as P") == ["alias P = Potts"]
        @test nonpublic_accesses("import CorePotts as C") == ["alias C = CorePotts"]
        @test nonpublic_accesses("import Potts.CorePotts as C") ==
            ["Potts.CorePotts", "alias C = Potts.CorePotts"]
        @test nonpublic_accesses("using Potts: CorePotts as C") ==
            ["Potts.CorePotts (imported)", "alias C = CorePotts"]
        @test nonpublic_accesses("using PottsModels: PottsModels as PM") ==
            ["alias PM = PottsModels"]
        @test nonpublic_accesses("const P = Potts") == ["alias P = Potts"]
        @test nonpublic_accesses("const CP = CorePotts") == ["alias CP = CorePotts"]
        @test nonpublic_accesses("PM = PottsModels") == ["alias PM = PottsModels"]
        @test isempty(
            nonpublic_accesses(
                """
                using Potts, PottsModels; using Potts: layout, paint!; import \
                CorePotts.shift
                Potts.paint!(op, l, lat); Potts.new_cell!(op, k); CorePotts.shift(l, x, \
                o); Makie.wong_colors()
                const alg = SequentialCPM(); f(x) = Potts.layout(x)"""
            )
        )
    end
end

@testitem "every model builds from `using Potts` and `using Potts.Layouts` alone" setup = [
    GuardrailsSetup,
] tags = [
    :pottsmodels, :guardrails,
] begin
    @testset "every model builds from `using Potts` and `using Potts.Layouts` alone" begin
        src = joinpath(@__DIR__, "..", "src")
        for f in sort(
                filter(f -> f != "PottsModels.jl" && endswith(f, ".jl"), readdir(src))
            )
            m = Module(Symbol(:Sandbox_, splitext(f)[1]))
            Core.eval(
                m,
                :(
                    using Potts;
                    using Potts.Layouts;
                    using DelimitedFiles: readdlm;
                    using Random: MersenneTwister
                )
            )
            Base.include(m, joinpath(src, f))
            ctors = filter(
                n -> isdefined(m, n) && isuppercase(first(string(n))) &&
                    getfield(m, n) isa Function,
                names(m; all = true)
            )
            @test !isempty(ctors)
            for c in ctors
                @test mtkcompile(getfield(m, c)(; name = :probe)) isa
                    Potts.CompiledPottsSystem
            end
        end
    end
end

@testitem "DSL vocabulary is documented" setup = [GuardrailsSetup] tags = [
    :pottsmodels, :guardrails,
] begin
    @testset "DSL vocabulary is documented" begin
        corpus = dsl_docs_corpus()
        @test isempty(filter(n -> !dsl_documented(corpus, n), collect(keys(Potts.DSL))))
        # controls: each branch alone passes, and a name the docs never mention fails;
        # Base's docstring of `rand` does not count for Potts's `rand`
        @test dsl_documented("", :transfer) && dsl_documented("`zz(`", :zz)
        @test !dsl_documented(corpus, :no_such_dsl_name) && !dsl_documented("", :rand)
        # Symbol options are checked
        @test_throws ArgumentError Potts.DSL.connectivity(1; rule = :unknown)
    end
end

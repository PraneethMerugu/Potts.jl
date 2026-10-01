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

# The reproduction scripts are not modules, so ExplicitImports cannot see them: walk their
# syntax instead. For the family modules `Potts`, `CorePotts` and `PottsModels`:
# - every qualified access `M.x` must name a public binding, chains link by link
#   (`Potts.CorePotts.x` checks `Potts.CorePotts`, then `CorePotts.x`);
# - every `using/import` path must be public link by link, with or without a colon
#   (`using Potts.CorePotts: x`, `import Potts.x`), and so must each imported name;
# - a family module may not be bound to another name (`import Potts as P`,
#   `using Potts: CorePotts as C`, `const P = Potts`): an alias would hide later accesses.
# Not handled: reflection (`getproperty(Potts, :x)`, `getfield`, `@eval`).
const POTTS_FAMILY = Dict(:Potts => Potts, :CorePotts => Potts.CorePotts, :PottsModels => PottsModels)
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
                it.head === :as && _isfamily(v) && push!(bad, "alias $(it.args[2]) = $(join(path, '.'))")
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
    p isa Expr && p.head === :. && length(p.args) == 2 && p.args[2] isa QuoteNode || return nothing
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

@testset "reproduction scripts use only public names" begin
    dir = joinpath(@__DIR__, "..", "reproductions")
    scripts = sort(filter(endswith(".jl"), readdir(dir)))
    @test !isempty(scripts)
    for f in scripts
        @test isempty(nonpublic_accesses(read(joinpath(dir, f), String)))
    end
    # negative controls: each form is caught, and public names pass
    @test nonpublic_accesses("Potts.lattice_spec((4, 4))") == ["Potts.lattice_spec"]
    @test nonpublic_accesses("f(x) = CorePotts.linear_index(l, x) + CorePotts._embed(g, x)") == ["CorePotts._embed"]
    @test nonpublic_accesses("Potts.CorePotts.shift(l, x, o)") == ["Potts.CorePotts"]
    @test nonpublic_accesses("Potts.CorePotts._embed(g, x)") == ["Potts.CorePotts", "CorePotts._embed"]
    @test nonpublic_accesses("using Potts: layout, lattice_spec") == ["Potts.lattice_spec (imported)"]
    @test nonpublic_accesses("import Potts: lattice_spec as ls") == ["Potts.lattice_spec (imported)"]
    @test nonpublic_accesses("using Potts.CorePotts: shift") == ["Potts.CorePotts"]
    @test nonpublic_accesses("using CorePotts: shift, _embed") == ["CorePotts._embed (imported)"]
    @test nonpublic_accesses("import Potts.lattice_spec") == ["Potts.lattice_spec"]
    @test nonpublic_accesses("using Potts, Potts.CorePotts") == ["Potts.CorePotts"]
    @test nonpublic_accesses("import Potts as P") == ["alias P = Potts"]
    @test nonpublic_accesses("import CorePotts as C") == ["alias C = CorePotts"]
    @test nonpublic_accesses("import Potts.CorePotts as C") == ["Potts.CorePotts", "alias C = Potts.CorePotts"]
    @test nonpublic_accesses("using Potts: CorePotts as C") == ["Potts.CorePotts (imported)", "alias C = CorePotts"]
    @test nonpublic_accesses("using PottsModels: PottsModels as PM") == ["alias PM = PottsModels"]
    @test nonpublic_accesses("const P = Potts") == ["alias P = Potts"]
    @test nonpublic_accesses("const CP = CorePotts") == ["alias CP = CorePotts"]
    @test nonpublic_accesses("PM = PottsModels") == ["alias PM = PottsModels"]
    @test isempty(nonpublic_accesses("""
        using Potts, PottsModels; using Potts: layout, paint!; import CorePotts.shift
        Potts.paint!(op, l, lat); Potts.new_cell!(op, k); CorePotts.shift(l, x, o); Makie.wong_colors()
        const alg = SequentialCPM(); f(x) = Potts.layout(x)"""))
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

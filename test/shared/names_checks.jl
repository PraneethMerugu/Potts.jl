# Name checks for the public surface of the packages: exported and public names are ASCII,
# removed names stay removed, and an export does not clash with a package a user loads beside
# ours. `test/names_tests.jl` runs them; add a package there with its own allowlists.

using TOML: TOML

# The packages a user loads beside ours. They are loaded from the shared workspace manifest by
# UUID, so a test project does not need them as direct dependencies.
const CLASH_PACKAGES = [
    "ModelingToolkitBase", "Symbolics", "SymbolicUtils", "SciMLBase", "DiffEqBase",
    "LinearSolve", "NonlinearSolve", "OrdinaryDiffEqCore", "JumpProcesses", "Graphs", "StatsBase",
    "Distributions", "KernelAbstractions", "SymbolicIndexingInterface", "DomainSets",
]

# the module of the package `name` in the workspace manifest, loaded by UUID
function manifest_package(name::AbstractString)
    manifest = TOML.parsefile(joinpath(@__DIR__, "..", "..", "Manifest.toml"))
    entry = only(manifest["deps"][name])
    return Base.require(Base.PkgId(Base.UUID(entry["uuid"]), name))
end

# the names `mod` exports or declares public, without the module's own name
public_names(mod::Module) = [n for n in names(mod) if n !== nameof(mod) && Base.ispublic(mod, n)]

# the exported and public names of `mod` that are not ASCII, less the ones in `allow`
non_ascii_names(mod::Module; allow = ()) = sort!([n for n in public_names(mod) if !isascii(String(n)) && n ∉ allow])

# the names that `mod` and one of `others` both export with different bindings, as
# `name => package name` pairs, less the pairs in `allow`
function export_clashes(mod::Module, others; allow = ())
    out = Pair{Symbol, Symbol}[]
    for other in others, n in names(other)
        (n === nameof(other) || !Base.isexported(mod, n) || (n => nameof(other)) in allow) && continue
        isdefined(mod, n) && isdefined(other, n) || continue
        getglobal(mod, n) === getglobal(other, n) || push!(out, n => nameof(other))
    end
    return sort!(out)
end

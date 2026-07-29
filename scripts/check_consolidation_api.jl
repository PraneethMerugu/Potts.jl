using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const BASELINE_PATH = joinpath(
    ROOT, "design", "evidence", "consolidation-baseline", "api-v1.toml")
const NAMING_PATH = joinpath(ROOT, "spec", "consolidation-naming-v1.toml")
const ENTRYPOINTS = Dict(
    "ProcessBigraphs" => "lib/ProcessBigraphs/src/ProcessBigraphs.jl",
    "CorePotts" => "lib/CorePotts/src/CorePotts.jl",
    "PottsToolkit" => "src/PottsToolkit.jl",
    "MakiePotts" => "lib/MakiePotts/src/MakiePotts.jl",
)

function walk_expressions!(visitor, value)
    value isa Expr || return
    visitor(value)
    foreach(argument -> walk_expressions!(visitor, argument), value.args)
end

function exported_names(path)
    syntax = Meta.parseall(read(joinpath(ROOT, path), String); filename=path)
    exports = Set{String}()
    walk_expressions!(syntax) do expression
        expression.head === :export || return
        for argument in expression.args
            name =
                argument isa Symbol ? string(argument) :
                argument isa Expr && argument.head === :. ?
                    string(last(argument.args)) : nothing
            isnothing(name) || push!(exports, name)
        end
    end
    sort!(collect(exports))
end

baseline = TOML.parsefile(BASELINE_PATH)
naming = TOML.parsefile(NAMING_PATH)
baseline_packages =
    Dict(String(row["name"]) => row for row in baseline["packages"])
canonical_additions = Dict(package => Set{String}() for package in keys(ENTRYPOINTS))
for row in naming["public_names"]
    package = String(row["package"])
    canonical = String(row["canonical"])
    push!(canonical_additions[package], canonical)
end

failures = String[]
for (package, entrypoint) in sort!(collect(ENTRYPOINTS); by=first)
    baseline_names =
        Set(String(row["name"]) for row in baseline_packages[package]["exports"])
    expected = union(baseline_names, canonical_additions[package])
    actual = Set(exported_names(entrypoint))
    missing = sort!(collect(setdiff(expected, actual)))
    unexpected = sort!(collect(setdiff(actual, expected)))
    isempty(missing) ||
        push!(failures, "$package is missing baseline/canonical exports: $(join(missing, ", "))")
    isempty(unexpected) ||
        push!(failures, "$package has unapproved exports: $(join(unexpected, ", "))")
end

process_project = TOML.parsefile(joinpath(ROOT, "lib", "ProcessBigraphs", "Project.toml"))
process_project["version"] == "0.5.1" ||
    push!(failures, "ProcessBigraphs consolidation candidate must be version 0.5.1")

if isempty(failures)
    baseline_count = sum(
        length(package["exports"]) for package in values(baseline_packages))
    addition_count = sum(length, values(canonical_additions))
    println("All $baseline_count baseline exports remain; " *
            "$addition_count approved domain-oriented canonical names are present, " *
            "with no unrelated export delta.")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("consolidation API check failed with $(length(failures)) error(s)")
end

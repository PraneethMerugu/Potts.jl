using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const BASELINE_PATH = joinpath(
    ROOT, "design", "evidence", "consolidation-baseline", "api-v1.toml")
const NAMING_PATH = joinpath(ROOT, "spec", "consolidation-naming-v1.toml")
const PHASE17_API_PATH =
    joinpath(ROOT, "spec", "process-bigraph-phase17-api-v1.toml")
const PHASE17_ENTRY_PATH =
    joinpath(ROOT, "spec", "process-bigraph-phase17-entry-v1.toml")
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
phase17_api = TOML.parsefile(PHASE17_API_PATH)
phase17_entry = TOML.parsefile(PHASE17_ENTRY_PATH)
baseline_packages =
    Dict(String(row["name"]) => row for row in baseline["packages"])
canonical_additions = Dict(package => Set{String}() for package in keys(ENTRYPOINTS))
for row in naming["public_names"]
    package = String(row["package"])
    canonical = String(row["canonical"])
    push!(canonical_additions[package], canonical)
end
union!(
    canonical_additions["ProcessBigraphs"],
    String.(phase17_api["process_bigraphs"]["user_additions"]["exported"]),
)
union!(
    canonical_additions["CorePotts"],
    String.(phase17_api["corepotts"]["user_additions"]["exported_types"]),
    String.(phase17_api["corepotts"]["user_additions"]["exported_functions"]),
)
union!(
    canonical_additions["PottsToolkit"],
    String.(phase17_api["pottstoolkit"]["user_additions"]["exported"]),
)
approved_unexports = Dict(package => Set{String}() for package in keys(ENTRYPOINTS))
extension_contract =
    phase17_api["process_bigraphs"]["extension_required"]
union!(
    approved_unexports["ProcessBigraphs"],
    String.(extension_contract["public_unexported_functions"]),
    String.(extension_contract["public_unexported_types"]),
)

failures = String[]
for (package, entrypoint) in sort!(collect(ENTRYPOINTS); by=first)
    baseline_names =
        Set(String(row["name"]) for row in baseline_packages[package]["exports"])
    expected = union(
        setdiff(baseline_names, approved_unexports[package]),
        canonical_additions[package],
    )
    actual = Set(exported_names(entrypoint))
    missing = sort!(collect(setdiff(expected, actual)))
    unexpected = sort!(collect(setdiff(actual, expected)))
    isempty(missing) ||
        push!(failures, "$package is missing baseline/canonical exports: $(join(missing, ", "))")
    isempty(unexpected) ||
        push!(failures, "$package has unapproved exports: $(join(unexpected, ", "))")
end

process_project = TOML.parsefile(joinpath(ROOT, "lib", "ProcessBigraphs", "Project.toml"))
permitted_version = phase17_entry["permitted_process_bigraphs_version"]
process_project["version"] == permitted_version ||
    push!(failures,
        "ProcessBigraphs productization candidate must be version $permitted_version")

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

using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const SPEC_PATH = joinpath(ROOT, "spec", "consolidation-architecture-v1.toml")
const SPEC = TOML.parsefile(SPEC_PATH)

failures = String[]
check(condition, message) = condition || push!(failures, message)

projects = Dict{String,Dict{String,Any}}()
for path in (
    "Project.toml",
    "lib/CorePotts/Project.toml",
    "lib/ProcessBigraphs/Project.toml",
    "lib/MakiePotts/Project.toml",
)
    project = TOML.parsefile(joinpath(ROOT, path))
    projects[String(project["name"])] = project
end

for layer in SPEC["package_layers"]
    package = String(layer["package"])
    check(isfile(joinpath(ROOT, layer["entrypoint"])),
        "$package entrypoint is missing")
    dependencies = Set(String.(keys(get(projects[package], "deps", Dict()))))
    forbidden = intersect(
        dependencies, Set(String.(layer["forbidden_family_dependencies"])))
    check(isempty(forbidden),
        "$package has forbidden upward package edges: $(join(sort!(collect(forbidden)), ", "))")
    order = String.(layer["order"])
    check(length(order) == length(unique(order)),
        "$package responsibility order repeats a layer")
end

concepts = String[]
owners = String[]
for authority in SPEC["authorities"]
    concept = String(authority["concept"])
    owner = String(authority["owner"])
    push!(concepts, concept)
    push!(owners, owner)
    check(isfile(joinpath(ROOT, owner)),
        "production authority is missing for $concept: $owner")
    check(!isempty(authority["consumers"]),
        "production authority has no declared consumers: $concept")
end
check(length(concepts) == length(unique(concepts)),
    "a production concept has multiple authority rows")

function source_line_count(path)
    count(eachline(path)) do line
        stripped = strip(line)
        !isempty(stripped) && !startswith(stripped, '#')
    end
end

waivers = Dict(String(row["path"]) => row for row in SPEC["large_file_waivers"])
production_roots = ("src", "lib/ProcessBigraphs/src", "lib/CorePotts/src", "lib/MakiePotts/src")
large_files = Dict{String,Int}()
for root in production_roots
    for (directory, _, files) in walkdir(joinpath(ROOT, root))
        for file in files
            endswith(file, ".jl") || continue
            path = joinpath(directory, file)
            lines = source_line_count(path)
            lines > SPEC["large_file_threshold"] || continue
            large_files[relpath(path, ROOT)] = lines
        end
    end
end

unreviewed_large_files = setdiff(Set(keys(large_files)), Set(keys(waivers)))
check(isempty(unreviewed_large_files),
    "large production files lack reviewed waivers: " *
    join(sort!(collect(unreviewed_large_files)), ", "))
for (path, waiver) in waivers
    absolute = joinpath(ROOT, path)
    check(isfile(absolute), "large-file waiver target is missing: $path")
    isfile(absolute) || continue
    lines = source_line_count(absolute)
    reviewed_lines = waiver["reviewed_lines"]
    maximum_lines = waiver["maximum_lines"]
    check(reviewed_lines > SPEC["large_file_threshold"],
        "large-file waiver review baseline must exceed the threshold for $path")
    check(maximum_lines >= reviewed_lines &&
          maximum_lines <= ceil(Int,
              reviewed_lines * (1 + SPEC["maximum_waiver_growth_percent"] / 100)),
        "large-file waiver ceiling is invalid for $path")
    check(lines <= maximum_lines,
        "large-file waiver ceiling exceeded for $path: maximum " *
        "$maximum_lines, found $lines")
    check(length(strip(String(waiver["rationale"]))) >= 80,
        "large-file waiver rationale is not substantive for $path")
end

split_aggregators = Dict(
    "lib/ProcessBigraphs/src/composition.jl" => 3,
    "lib/ProcessBigraphs/src/structural_transactions.jl" => 4,
    "lib/CorePotts/src/coupled/continuous.jl" => 6,
    "lib/CorePotts/src/coupled/dynamic_state.jl" => 2,
    "lib/CorePotts/src/coupled/polarity.jl" => 2,
    "lib/CorePotts/src/coupled/relationships.jl" => 7,
    "src/authoring/normalization.jl" => 4,
    "src/authoring/level1_rules.jl" => 4,
)
for (path, expected_includes) in split_aggregators
    text = read(joinpath(ROOT, path), String)
    includes = collect(eachmatch(r"""include\("([^"]+)"\)""", text))
    check(length(includes) == expected_includes,
        "split aggregator $path has an unexpected responsibility count")
    check(length(includes) == length(unique(match.captures[1] for match in includes)),
        "split aggregator $path repeats an include")
end

if isempty(failures)
    println("Consolidated architecture has one-way package edges, explicit concept authorities, " *
            "$(length(split_aggregators)) responsibility aggregators, and " *
            "$(length(waivers)) reviewed large-file waivers.")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("consolidation architecture check failed with $(length(failures)) error(s)")
end

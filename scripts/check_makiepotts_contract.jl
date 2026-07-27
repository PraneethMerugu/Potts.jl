using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const MANIFEST_PATH = joinpath(
    ROOT, "design", "makiepotts", "public-api-v0.2.toml")
const MODULE_PATH = joinpath(
    ROOT, "lib", "MakiePotts", "src", "MakiePotts.jl")
const SOURCE_ROOT = joinpath(ROOT, "lib", "MakiePotts", "src")

manifest = TOML.parsefile(MANIFEST_PATH)

function exported_names(path)
    result = Set{String}()
    for line in eachline(path)
        matched = match(r"^\s*export\s+(.+)$", line)
        matched === nothing && continue
        for name in split(matched.captures[1], ',')
            push!(result, strip(name))
        end
    end
    return result
end

classified = Dict(
    "stable" => Set{String}(manifest["stable_exports"]),
    "limited" => Set{String}(manifest["limited_exports"]),
    "experimental" => Set{String}(manifest["experimental_exports"]),
)

for (left_name, left) in classified, (right_name, right) in classified
    left_name < right_name || continue
    overlap = intersect(left, right)
    isempty(overlap) || error(
        "MakiePotts API names classified as both $left_name and $right_name: " *
        join(sort!(collect(overlap)), ", "))
end

declared = union(values(classified)...)
exported = exported_names(MODULE_PATH)
missing = setdiff(declared, exported)
unclassified = setdiff(exported, declared)
isempty(missing) || error(
    "classified MakiePotts names are no longer exported: " *
    join(sort!(collect(missing)), ", "))
isempty(unclassified) || error(
    "MakiePotts exports require a stability classification: " *
    join(sort!(collect(unclassified)), ", "))

fragments = manifest["architecture"]["forbidden_source_fragments"]
violations = String[]
for path in sort!(filter(endswith(".jl"), readdir(SOURCE_ROOT; join = true)))
    for (line_number, line) in enumerate(eachline(path))
        for fragment in fragments
            occursin(fragment, line) || continue
            push!(violations,
                "$(relpath(path, ROOT)):$line_number contains forbidden `$fragment`")
        end
    end
end
isempty(violations) || error(
    "MakiePotts bypasses an accessor boundary:\n  " * join(violations, "\n  "))

println("MakiePotts v0.2 API classification and accessor boundary passed")

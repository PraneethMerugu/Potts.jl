#!/usr/bin/env julia

using TOML

const ROOT = let
    prefix = "--root="
    argument = findfirst(arg -> startswith(arg, prefix), ARGS)
    argument === nothing ?
        normpath(joinpath(@__DIR__, "..")) :
        abspath(ARGS[argument][nextind(ARGS[argument], lastindex(prefix)):end])
end
const failures = String[]
check(condition, message) = condition || push!(failures, message)

function load(relative)
    path = joinpath(ROOT, relative)
    check(isfile(path), "missing required file: $relative")
    return isfile(path) ? TOML.parsefile(path) : Dict{String,Any}()
end

contract =
    load("spec/process-bigraph-phase17-documentation-quality-v1.toml")
entry = load("spec/process-bigraph-phase17-entry-v1.toml")
pages = get(contract, "pages", Any[])
paths = String[row["path"] for row in pages]
ids = String[row["id"] for row in pages]

check(length(pages) == get(contract, "required_page_count", -1),
    "registered documentation page count is stale")
check(length(paths) == length(unique(paths)),
    "documentation registry contains duplicate paths")
check(length(ids) == length(unique(ids)),
    "documentation registry contains duplicate ids")
check(all(row -> row["required"] == true, pages),
    "all registered Phase 17 pages must be required")

status = get(entry, "implementation_status", "")
docs_active = status in (
    "17.D-independent-manual",
    "17.E-scientific-case-studies",
    "17.F-reconciliation-and-attestation",
    "complete",
)
if docs_active
    for relative in paths
        check(isfile(joinpath(ROOT, relative)),
            "missing registered documentation page: $relative")
    end
    required_environment = (
        "lib/ProcessBigraphs/docs/Project.toml",
        "lib/ProcessBigraphs/docs/Manifest.toml",
        "lib/ProcessBigraphs/docs/make.jl",
        "lib/ProcessBigraphs/docs/README.md",
    )
    for relative in required_environment
        check(isfile(joinpath(ROOT, relative)),
            "missing independent documentation environment file: $relative")
    end
    forbidden = (
        r"\binclude\s*\(" => "reader-facing include",
        r"ReferenceModels\.(Wortel2021|Merks2006)\.(model|problem|composite)\s*\(" =>
            "prebuilt case-study constructor",
    )
    for relative in paths
        isfile(joinpath(ROOT, relative)) || continue
        source = read(joinpath(ROOT, relative), String)
        for (pattern, label) in forbidden
            check(!occursin(pattern, source),
                "$relative contains forbidden $label")
        end
    end
end

if isempty(failures)
    println("ProcessBigraphs Phase 17 documentation contract passed:")
    println("  registered pages: $(length(pages))")
    println("  complete site enforced: $docs_active")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("Phase 17 documentation check failed with $(length(failures)) error(s)")
end

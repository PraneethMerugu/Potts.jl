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

entry = load("spec/process-bigraph-phase17-entry-v1.toml")
ledger = load("spec/process-bigraph-phase17-qualification-v1.toml")
requirements = get(ledger, "requirements", Any[])

check(length(requirements) == get(ledger, "required_row_count", -1),
    "qualification row count is stale")
for row in requirements
    check(row["status"] == "qualified",
        "$(row["id"]) is not qualified")
    evidence = String.(row["evidence"])
    check(!isempty(evidence), "$(row["id"]) has no evidence")
    for relative in evidence
        check(ispath(joinpath(ROOT, relative)),
            "$(row["id"]) evidence does not resolve: $relative")
    end
end
check(get(ledger, "closure_status", "") == "qualified",
    "qualification ledger closure_status is not qualified")
check(get(entry, "implementation_status", "") == "complete",
    "Phase 17 entry implementation_status is not complete")
check(get(entry, "status", "") == "qualified_unpublished_internal_beta",
    "Phase 17 entry status is not the accepted completion status")

if isempty(failures)
    println("ProcessBigraphs Phase 17 closure passed: $(length(requirements)) qualified rows")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("Phase 17 closure failed with $(length(failures)) error(s)")
end

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

contract = load("spec/process-bigraph-phase17-browser-qa-v1.toml")
entry = load("spec/process-bigraph-phase17-entry-v1.toml")
journeys = get(contract, "journeys", Any[])
ids = String[row["id"] for row in journeys]

check(length(journeys) == 8 && length(ids) == length(unique(ids)),
    "browser journey registry must contain eight unique journeys")
check(Set(contract["environment"]["browsers"]) ==
      Set(["chromium", "firefox", "webkit"]),
    "browser engine matrix changed")
check(contract["accessibility"]["violations_allowed"] == 0 &&
      contract["accessibility"]["disabled_rules_allowed"] == 0,
    "accessibility gate must remain zero-waiver")
check(contract["terminal_agent"]["complete_rerun_after_repair"] == true,
    "terminal agent must completely rerun after a repair")

browser_active =
    get(entry, "implementation_status", "") in (
        "17.F-reconciliation-and-attestation", "complete")
if browser_active
    required = (
        "lib/ProcessBigraphs/docs/browser/package.json",
        "lib/ProcessBigraphs/docs/browser/playwright.config.ts",
        "lib/ProcessBigraphs/docs/browser/tests/site.spec.ts",
        "lib/ProcessBigraphs/docs/browser/tests/visual.spec.ts",
        "lib/ProcessBigraphs/docs/browser/scripts/lighthouse.mjs",
    )
    for relative in required
        check(isfile(joinpath(ROOT, relative)),
            "missing browser qualification file: $relative")
    end
end

if isempty(failures)
    println("ProcessBigraphs Phase 17 browser contract passed:")
    println("  task journeys: $(length(journeys))")
    println("  rendered-site gate enforced: $browser_active")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("Phase 17 browser contract failed with $(length(failures)) error(s)")
end

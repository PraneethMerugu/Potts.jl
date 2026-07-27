#!/usr/bin/env julia

using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const PACKAGE = joinpath(ROOT, "lib", "ProcessBigraphs")
const failures = String[]

check(condition, message) = condition || push!(failures, message)
require_file(path) = (check(isfile(path), "missing $(relpath(path, ROOT))"); path)

project_path = require_file(joinpath(PACKAGE, "Project.toml"))
module_path = require_file(joinpath(PACKAGE, "src", "ProcessBigraphs.jl"))
registry_path = require_file(joinpath(PACKAGE, "parity-registry.toml"))
readme_path = require_file(joinpath(PACKAGE, "README.md"))
docs_path = require_file(joinpath(PACKAGE, "docs", "src", "internal.md"))
tests_path = require_file(joinpath(PACKAGE, "test", "runtests.jl"))
evidence_path = require_file(
    joinpath(ROOT, "design", "evidence", "process-bigraph-pb0-evidence-v1.toml"))
audit_path = require_file(
    joinpath(ROOT, "design", "audits", "process-bigraph-pb0-implementation-audit.md"))

check(!isfile(joinpath(PACKAGE, "Manifest.toml")),
    "independent package must not retain lib/ProcessBigraphs/Manifest.toml")

project = TOML.parsefile(project_path)
check(project["name"] == "ProcessBigraphs", "package name changed")
check(project["uuid"] == "efcc6515-205e-41e3-b553-f38f05ad529c",
    "package UUID changed")
check(project["version"] == "0.3.0",
    "Phase 15.B package must preserve PB0 under its internal 0.3.0 identity")
check(project["compat"]["julia"] == "1.12.6",
    "PB0 must target exact active Julia 1.12.6")
check(Set(keys(project["deps"])) == Set(["ACSets", "Catlab", "SHA"]),
    "Phase 15.A dependencies must preserve SHA and add only ACSets/Catlab")
check(project["compat"]["SHA"] == "0.7", "SHA compatibility is missing")
check(project["compat"]["Aqua"] == "0.8", "Aqua compatibility is missing")
check(project["compat"]["Test"] == "1", "Test compatibility is missing")

required_sources = [
    "errors.jl",
    "paths.jl",
    "time.jl",
    "canonical.jl",
    "schemas.jl",
    "store.jl",
    "effects.jl",
    "capabilities.jl",
    "declarations.jl",
    "algebraic_structure.jl",
    "composites.jl",
    "lowering.jl",
    "runtime.jl",
    "checkpoint.jl",
]
module_text = read(module_path, String)
for source in required_sources
    require_file(joinpath(PACKAGE, "src", source))
    check(occursin("include(\"$source\")", module_text),
        "module does not include $source")
end

for forbidden in ("using CorePotts", "import CorePotts", "using PottsToolkit",
                  "import PottsToolkit")
    for source in readdir(joinpath(PACKAGE, "src"); join=true)
        endswith(source, ".jl") || continue
        check(!occursin(forbidden, read(source, String)),
            "$(basename(source)) contains forbidden domain dependency '$forbidden'")
    end
end

registry = TOML.parsefile(registry_path)
check(registry["maturity"] in (
        "phase_15b_open_composition",
        "phase_15c_implementation_candidate",
        "phase_15c_serial_internal_alpha",
    ),
    "package registry no longer preserves PB0 evidence")
check(registry["public_release"] == false, "package registry claims a public release")
check(registry["pins"]["process_bigraph"] ==
    "305ea826191e9f897f0c6e207bc303bbc44a9eef",
    "Process-Bigraph pin changed")
check(registry["pins"]["bigraph_schema"] ==
    "4b208e13620e09e877af52ea07273bc9429a3a17",
    "Bigraph-Schema pin changed")

features = registry["features"]
ids = [feature["id"] for feature in features]
check(length(ids) == length(unique(ids)), "package registry feature IDs are not unique")
check(length(features) >= 20, "PB0 registry omits implemented/partial feature rows")
check(all(feature -> feature["implementation_status"] in ("implemented", "partial"),
    features), "PB0 feature has an invalid implementation status")
check(all(feature -> feature["oracle_status"] in (
        "direct_passing",
        "direct_partial",
        "independent_passing_candidate",
        "independent_qualified",
    ), features), "package feature has an invalid oracle status")
check(all(feature -> isfile(joinpath(PACKAGE, feature["test"])), features),
    "PB0 feature references a missing direct test")

evidence = TOML.parsefile(evidence_path)
check(evidence["status"] == "passed_bounded_foundation",
    "PB0 evidence does not pass its bounded gate")
check(evidence["qualification"]["pb0_tests_passed"] >= 77,
    "PB0 test count regressed")
check(evidence["qualification"]["aqua_checks_passed"] >= 10,
    "Aqua evidence is incomplete")
check(evidence["public_release"] == false && evidence["internal_alpha"] == false,
    "PB0 evidence overclaims maturity")
check(Set(evidence["qualification"]["implemented_direct_rows"]) <= Set(ids),
    "evidence references an unknown implemented feature")
check(Set(evidence["qualification"]["partial_direct_rows"]) <= Set(ids),
    "evidence references an unknown partial feature")

for markdown in (readme_path, docs_path, audit_path)
    text = read(markdown, String)
    check(iseven(length(collect(eachmatch(r"```", text)))),
        "$(relpath(markdown, ROOT)) has unbalanced code fences")
    for match in eachmatch(r"!?\[[^\]]*\]\(([^)]+)\)", text)
        target = strip(match.captures[1])
        startswith(target, r"https?://") && continue
        startswith(target, '#') && continue
        target = strip(first(split(target, '#')), ['<', '>'])
        isempty(target) && continue
        check(ispath(normpath(joinpath(dirname(markdown), target))),
            "$(relpath(markdown, ROOT)) has missing link '$target'")
    end
end

if isempty(failures)
    println("ProcessBigraphs Phase 14.PB0 structure and evidence check passed")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    exit(1)
end

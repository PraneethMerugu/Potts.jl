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
docs_contract =
    load("spec/process-bigraph-phase17-documentation-quality-v1.toml")
browser_contract =
    load("spec/process-bigraph-phase17-browser-qa-v1.toml")
report = load("design/evidence/phase-17/phase17-qualification-v1.toml")
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

digest_pattern = r"^[0-9a-f]{64}$"
qualifying_digest = get(report, "qualifying_content_sha256", "")
check(occursin(digest_pattern, qualifying_digest),
    "qualification report lacks an exact qualifying-content digest")
check(get(report, "status", "") == "qualified",
    "Phase 17 qualification report is not qualified")
provenance = get(report, "provenance", Dict{String,Any}())
check(!isempty(get(provenance, "commands", String[])) &&
      !isempty(get(provenance, "environment", String[])) &&
      !isempty(get(provenance, "artifacts", String[])) &&
      !isempty(get(provenance, "limitations", String[])) &&
      get(provenance, "assertion_count", 0) > 0,
    "qualification report lacks command, environment, artifact, assertion, or limitation provenance")

documentation = get(report, "documentation", Dict{String,Any}())
check(get(documentation, "registered_pages", 0) ==
      docs_contract["required_page_count"],
    "deterministic evidence has the wrong registered-page count")
check(get(documentation, "canonical_programs", 0) == 18,
    "deterministic evidence has the wrong canonical-program count")
check(get(documentation, "strict_root_build_passed", false) &&
      get(documentation, "strict_process_bigraphs_build_passed", false) &&
      get(documentation, "runtime_budgets_passed", false),
    "strict documentation build or runtime-budget evidence is incomplete")

case_studies = get(report, "case_studies", Dict{String,Any}())
check(get(case_studies, "wortel_exact_fixed_seed_equivalence", false) &&
      get(case_studies, "merks_exact_fixed_seed_equivalence", false) &&
      get(case_studies, "seed_sensitive_bounded_outputs", false),
    "stochastic case-study equivalence evidence is incomplete")

smokes = get(report, "clean_install_smokes", Dict{String,Any}())
for platform in ("linux_x86_64", "macos_arm64", "windows_x86_64")
    check(get(smokes, platform, "") == "success",
        "clean-install smoke is not qualified for $platform")
end

rendered = get(report, "rendered_site", Dict{String,Any}())
check(get(rendered, "playwright_browsers", String[]) ==
      browser_contract["environment"]["browsers"],
    "rendered-site evidence does not cover the required browser matrix")
check(get(rendered, "playwright_failures", -1) == 0 &&
      get(rendered, "axe_violations", -1) == 0 &&
      get(rendered, "visual_routes", 0) ==
        length(browser_contract["routes"]["visual_regression_routes"]) &&
      get(rendered, "lighthouse_routes", 0) ==
        length(browser_contract["routes"]["lighthouse_routes"]) &&
      get(rendered, "lighthouse_runs_per_route", 0) ==
        browser_contract["lighthouse"]["runs_per_route"],
    "rendered-site deterministic evidence is incomplete")

terminal = get(report, "terminal_agent", Dict{String,Any}())
check(get(terminal, "passed", false) &&
      get(terminal, "auditor_led", false) &&
      !get(terminal, "external_user_study", true) &&
      !get(terminal, "human_accessibility_audit", true) &&
      get(terminal, "final_disposition", "") == "pass",
    "terminal browser-agent disposition is incomplete or overstated")

journeys = get(report, "journeys", Any[])
expected_journeys =
    Set(String(row["id"]) for row in browser_contract["journeys"])
actual_journeys = Set(String(get(row, "id", "")) for row in journeys)
check(actual_journeys == expected_journeys &&
      length(journeys) == length(expected_journeys),
    "terminal browser evidence does not contain every accepted journey exactly once")
for row in journeys
    id = get(row, "id", "unknown")
    check(get(row, "passed", false), "terminal browser journey failed: $id")
    check(!isempty(get(row, "persona", "")) &&
          !isempty(get(row, "start_route", "")) &&
          !isempty(get(row, "task", "")) &&
          !isempty(get(row, "actions", String[])) &&
          !isempty(get(row, "success_criteria", String[])) &&
          !isempty(get(row, "observed_result", "")) &&
          !isempty(get(row, "viewport", "")) &&
          !isempty(get(row, "theme", "")) &&
          !isempty(get(row, "screenshot", "")) &&
          haskey(row, "finding_ids") &&
          get(row, "console_errors", -1) == 0 &&
          get(row, "network_failures", -1) == 0,
        "terminal browser journey evidence is incomplete: $id")
end

route_matrix = get(report, "route_matrix", Dict{String,Any}())
expected_route_assessments =
    length(browser_contract["routes"]["required_terminal_routes"]) *
    length(browser_contract["viewports"]) *
    length(browser_contract["environment"]["color_schemes"])
expected_routes = Set(String.(
    browser_contract["routes"]["required_terminal_routes"]))
expected_viewports =
    Set(String(row["id"]) for row in browser_contract["viewports"])
expected_themes =
    Set(String.(browser_contract["environment"]["color_schemes"]))
check(Set(String.(get(route_matrix, "routes", String[]))) == expected_routes &&
      Set(String.(get(route_matrix, "viewports", String[]))) == expected_viewports &&
      Set(String.(get(route_matrix, "themes", String[]))) == expected_themes &&
      get(route_matrix, "assessments", 0) == expected_route_assessments &&
      get(route_matrix, "failures", -1) == 0 &&
      get(route_matrix, "screenshots", 0) > 0,
    "terminal route, viewport, and theme matrix is incomplete")

rubric = get(report, "rubric", Dict{String,Any}())
scores = get(rubric, "scores", Dict{String,Any}())
categories = String.(docs_contract["rubric"]["categories"])
check(Set(keys(scores)) == Set(categories),
    "documentation rubric does not score every required category exactly once")
numeric_scores = [get(scores, category, -1) for category in categories]
check(all(score -> score isa Integer && 0 <= score <= 10, numeric_scores),
    "documentation rubric contains a score outside 0–10")
check(sum(numeric_scores) >= docs_contract["rubric"]["minimum_total"] &&
      minimum(numeric_scores; init=-1) >= docs_contract["rubric"]["minimum_each"],
    "documentation rubric misses its total or per-category floor")
for category in docs_contract["rubric"]["required_nine_or_better"]
    check(get(scores, category, -1) >= 9,
        "documentation rubric category must score at least 9: $category")
end

if isempty(failures)
    println("ProcessBigraphs Phase 17 closure passed: $(length(requirements)) qualified rows")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("Phase 17 closure failed with $(length(failures)) error(s)")
end

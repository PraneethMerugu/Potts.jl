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
    check(isfile(path), "missing required file: $(relative)")
    isfile(path) ? TOML.parsefile(path) : Dict{String,Any}()
end

function read_required(relative)
    path = joinpath(ROOT, relative)
    check(isfile(path), "missing required file: $(relative)")
    isfile(path) ? read(path, String) : ""
end

function unique_strings(values, label)
    strings = String.(values)
    check(length(strings) == length(unique(strings)),
        "$(label) contains duplicate values")
    strings
end

const entry = load("spec/process-bigraph-phase17-entry-v1.toml")
const api = load("spec/process-bigraph-phase17-api-v1.toml")
const docs = load("spec/process-bigraph-phase17-documentation-quality-v1.toml")
const browser = load("spec/process-bigraph-phase17-browser-qa-v1.toml")
const ledger = load("spec/process-bigraph-phase17-qualification-v1.toml")

const round1 = read_required(
    "design/audits/process-bigraph-phase17-owner-interview-round-1.md")
const round2 = read_required(
    "design/audits/process-bigraph-phase17-owner-interview-round-2.md")
const round3 = read_required(
    "design/audits/process-bigraph-phase17-owner-interview-round-3.md")
const decision = read_required(
    "spec/decisions/0042-process-bigraph-model-and-documentation-productization.md")
const normative = read_required(
    "spec/phase-17-process-bigraph-model-and-documentation-productization.md")
const plan = read_required(
    "design/audits/process-bigraph-phase17-implementation-plan.md")
const audit = read_required(
    "design/audits/process-bigraph-phase17-specification-audit.md")

check(get(entry, "schema_version", "") == "1.0.0" &&
      get(entry, "contract_id", "") == "process-bigraph-phase17-entry-v1" &&
      get(entry, "phase", "") == "17",
    "Phase 17 entry identity changed")
const active_implementation_statuses = Set([
    "17.A-contract-freeze",
    "17.B-public-boundary-closure",
    "17.C-model-migration",
    "17.D-independent-manual",
    "17.E-scientific-case-studies",
    "17.F-reconciliation-and-attestation",
])
const active = get(entry, "status", "") == "in_progress" &&
    get(entry, "implementation_status", "") in active_implementation_statuses &&
    get(entry, "implementation_authorized", false) == true &&
    entry["prerequisites"]["owner_sendoff_received"] == true
check(active, "entry must record the received owner send-off and active 17.A state")
check(get(entry, "internal_beta", false) == true &&
      get(entry, "public_release", true) == false,
    "Phase 17 must remain an unpublished internal beta")
check(get(entry, "baseline_commit", "") ==
      "04f39dc05f847b7dd84f24f12cce24d1ed0229a6",
    "researched consolidation baseline changed without reconciliation")

const expected_subgates = [
    "17.A-contract-freeze",
    "17.B-public-boundary-closure",
    "17.C-model-migration",
    "17.D-independent-manual",
    "17.E-scientific-case-studies",
    "17.F-reconciliation-and-attestation",
]
check(entry["ordering"]["subgates"] == expected_subgates &&
      entry["ordering"]["strictly_ordered"] == true &&
      entry["ordering"]["compensation_allowed"] == false &&
      entry["ordering"]["one_branch"] == true,
    "Phase 17 subgate ordering or one-branch rule changed")
check(entry["ordering"]["branch"] == "codex/ProcessBigraphs-Docs" &&
      occursin("no reset", entry["ordering"]["baseline_merge_strategy"]),
    "Phase 17 branch or nondestructive merge rule changed")

check(entry["dependency_policy"]["process_bigraphs_depends_on_corepotts"] == false &&
      entry["dependency_policy"]["process_bigraphs_depends_on_pottstoolkit"] == false &&
      entry["dependency_policy"]["corepotts_depends_on_process_bigraphs"] == true &&
      entry["dependency_policy"]["pottstoolkit_depends_on_process_bigraphs"] == true,
    "accepted package dependency direction changed")
check(entry["models"]["canonical_models"] == ["wortel-2021", "merks-2006"] &&
      entry["models"]["internal_api_references_allowed"] == 0 &&
      entry["models"]["tutorial_imports_prebuilt_model"] == false &&
      entry["models"]["quantitative_reproduction_claim"] == false,
    "accepted model or claim boundary changed")
check(entry["documentation"]["minimum_curated_pages"] == 35 &&
      entry["documentation"]["minimum_quality_score"] == 92 &&
      entry["documentation"]["minimum_category_score"] == 8 &&
      entry["documentation"]["reader_include_forbidden"] == true,
    "documentation floor or visible-program rule changed")
check(entry["browser"]["terminal_functional_gate"] == true &&
      entry["browser"]["waivers_allowed"] == false &&
      entry["browser"]["viewports"] ==
        ["1440x900", "1024x768", "390x844"],
    "terminal browser gate, waiver, or viewport rule changed")
check(entry["autonomy"]["implementation_requires_owner_sendoff"] == true &&
      entry["autonomy"]["merge_main_allowed"] == false &&
      entry["autonomy"]["registry_release_allowed"] == false &&
      entry["autonomy"]["preserve_user_paper_pdf_deletion"] == true,
    "autonomous authority or user-work preservation changed")

for relative in values(entry["authority"])
    path = normpath(joinpath(ROOT, "spec", relative))
    # Authority paths are relative to spec/. The checker itself lives one level
    # above, so normalize there and accept its existing absolute target.
    check(isfile(path), "entry authority does not resolve: $(relative)")
end

check(get(api, "contract_id", "") == "process-bigraph-phase17-api-v1" &&
      get(api, "status", "") == "specified",
    "API contract identity or status changed")
check(Set(api["classes"]) == Set([
        "exported_user",
        "public_extension",
        "experimental_beta",
        "deprecated_compat",
        "internal",
    ]),
    "API class set changed")
check(api["classification_policy"]["every_binding_exactly_once"] == true &&
      api["classification_policy"]["admitted_docstring_coverage_percent"] == 100 &&
      api["classification_policy"]["admitted_owning_page_coverage_percent"] == 100,
    "API completeness requirements changed")
check(api["process_bigraphs"]["user_additions"]["exported"] ==
      ["managed_field_process"],
    "ProcessBigraphs user addition changed")
check(api["corepotts"]["user_additions"]["exported_types"] ==
      ["ActivityPottsProblem"] &&
      Set(api["corepotts"]["user_additions"]["exported_functions"]) ==
      Set(["static_relation", "site_property_value"]),
    "CorePotts narrow user additions changed")
check(Set(api["corepotts"]["reused_supported_functions"]["exported"]) ==
      Set([
          "logical_state",
          "current_mcs_report",
          "capture_checkpoint",
          "restore_checkpoint",
      ]),
    "CorePotts generic accessor reuse changed")
check(Set(api["corepotts"]["internal_required"]["bindings"]) ==
      Set(["CoupledIntegrator", "CoupledState", "MCSPlan", "init_coupled"]),
    "required CorePotts internal binding set changed")
check(api["topology"]["required_signature"] ==
      "static_relation(role, topology; spacing, weights)" &&
      api["topology"]["private_offsets_in_models"] == false,
    "topology authoring boundary changed")
check(api["compatibility"]["merks_semantic_version"] == 2 &&
      api["compatibility"]["wortel_semantic_version"] == 1 &&
      api["compatibility"]["silent_merks_v1_as_v2_restore"] == false,
    "model version or checkpoint migration boundary changed")

check(get(docs, "contract_id", "") ==
      "process-bigraph-phase17-documentation-quality-v1" &&
      get(docs, "required_page_count", 0) == 35,
    "documentation contract identity or page count changed")
const pages = docs["pages"]
const page_ids = unique_strings([row["id"] for row in pages], "page registry")
check(length(pages) == 35, "documentation registry must contain exactly 35 required pages")
check(all(row -> row["required"] == true, pages),
    "every Phase 17 registry page must be required")
check(count(row -> row["kind"] == "learn", pages) == 10,
    "documentation registry must contain exactly 10 Learn pages")
check(count(row -> row["kind"] == "example", pages) == 6,
    "documentation registry must contain exactly six complete examples")
check(count(row -> row["kind"] ==
      "qualified-source-bounded-case-study", pages) == 2,
    "documentation registry must contain exactly two scientific case studies")
check(count(row -> row["kind"] == "concept", pages) == 9,
    "documentation registry must contain exactly nine concept pages")
check(count(row -> row["kind"] == "api", pages) == 5,
    "documentation registry must contain exactly five API pages")
check(Set(row["section"] for row in pages) == Set(docs["top_level_sections"]),
    "page registry sections disagree with top-level navigation")
check(docs["visibility"]["complete_program_visible"] == true &&
      docs["visibility"]["complete_program_executed"] == true &&
      docs["visibility"]["reader_include_forbidden"] == true &&
      docs["visibility"]["prebuilt_case_study_model_forbidden"] == true,
    "visible executed source contract changed")
check(docs["runtime_budgets_seconds"]["first_tutorial_warm_max"] == 10 &&
      docs["runtime_budgets_seconds"]["ordinary_example_warm_max"] == 15 &&
      docs["runtime_budgets_seconds"]["wortel_case_study_warm_max"] == 30 &&
      docs["runtime_budgets_seconds"]["merks_case_study_warm_max"] == 60 &&
      docs["runtime_budgets_seconds"]["all_required_programs_warm_max"] == 240 &&
      docs["runtime_budgets_seconds"]["strict_docs_build_warm_max"] == 480,
    "documentation runtime budgets changed")
check(docs["rubric"]["minimum_total"] == 92 &&
      docs["rubric"]["minimum_each"] == 8 &&
      length(docs["rubric"]["categories"]) == 10,
    "documentation rubric changed")
check(length(docs["task_reviews"]) == 3 &&
      Set(row["id"] for row in docs["task_reviews"]) ==
      Set(["model-composer", "adapter-author", "reproducibility-researcher"]),
    "required persona review set changed")

check(get(browser, "contract_id", "") ==
      "process-bigraph-phase17-browser-qa-v1" &&
      browser["terminal_functional_gate"] == true &&
      browser["waivers_allowed"] == false,
    "browser contract identity or terminal gate changed")
check(length(browser["viewports"]) == 3 &&
      Set((row["width"], row["height"]) for row in browser["viewports"]) ==
      Set([(1440, 900), (1024, 768), (390, 844)]),
    "browser viewport registry changed")
check(Set(browser["environment"]["browsers"]) ==
      Set(["chromium", "firefox", "webkit"]) &&
      Set(browser["environment"]["color_schemes"]) == Set(["light", "dark"]),
    "browser engine or theme matrix changed")
check(browser["accessibility"]["standard"] == "WCAG-2.2-AA" &&
      browser["accessibility"]["violations_allowed"] == 0 &&
      browser["accessibility"]["disabled_rules_allowed"] == 0 &&
      browser["accessibility"]["broad_exclusions_allowed"] == 0,
    "accessibility target or no-exclusion policy changed")
check(browser["lighthouse"]["runs_per_route"] == 3 &&
      browser["lighthouse"]["accessibility_min"] == 1.0 &&
      browser["lighthouse"]["best_practices_min"] == 1.0 &&
      browser["lighthouse"]["seo_min"] == 0.95 &&
      browser["lighthouse"]["mobile_performance_min"] == 0.90 &&
      browser["lighthouse"]["cls_max"] == 0.1,
    "Lighthouse thresholds changed")
const journeys = browser["journeys"]
unique_strings([row["id"] for row in journeys], "browser journeys")
check(length(journeys) == 8,
    "browser contract must contain exactly eight task journeys")
check(browser["terminal_agent"]["complete_rerun_after_repair"] == true &&
      browser["terminal_agent"]["static_source_only_forbidden"] == true,
    "browser repair or rendered-site requirement changed")

check(get(ledger, "contract_id", "") ==
      "process-bigraph-phase17-qualification-v1" &&
      ledger["status"] == "specified" &&
      ledger["closure_status"] == "open",
    "qualification ledger identity or preimplementation status changed")
const rows = ledger["requirements"]
const row_ids = unique_strings([row["id"] for row in rows], "qualification ledger")
check(length(rows) == ledger["required_row_count"] == 44,
    "qualification ledger must contain exactly 44 required rows")
check(Set(row["subgate"] for row in rows) ==
      Set(["17.A", "17.B", "17.C", "17.D", "17.E", "17.F"]),
    "qualification ledger does not cover every subgate")
check(all(row -> row["status"] == "qualified",
        filter(row -> row["subgate"] == "17.A", rows)),
    "qualified 17.A contract-freeze rows changed")
check(all(row -> row["status"] in ledger["allowed_statuses"], rows),
    "qualification ledger contains an invalid status")

for (name, text, expected) in [
    ("Round 1", round1, 14),
    ("Round 2", round2, 18),
    ("Round 3", round3, 28),
]
    found = length(collect(eachmatch(Regex("P17-R[123]-[0-9]{2}"), text)))
    check(found >= expected,
        "$(name) is missing accepted decision identifiers")
    check(occursin("accepted", lowercase(text)),
        "$(name) is not recorded as accepted")
end

for (name, text, phrases) in [
    ("Decision 0042", decision, [
        "one bounded Phase 17",
        "qualified unpublished internal beta",
        "terminal browser-agent",
        "implementation not authorized",
    ]),
    ("Normative specification", normative, [
        "MUST remain a qualified unpublished internal beta",
        "ActivityPottsProblem",
        "The site MUST contain the page inventory",
        "Any failure MUST reopen implementation",
    ]),
    ("Implementation plan", plan, [
        "explicit owner send-off received",
        "Subgate 17.A",
        "Terminal browser-agent gate",
        "Do not stop merely because",
    ]),
    ("Specification audit", audit, [
        "implementation authorized",
        "Closed ambiguities",
        "sufficient to implement Phase 17 autonomously",
    ]),
]
    for phrase in phrases
        check(occursin(lowercase(phrase), lowercase(text)),
            "$(name) missing required phrase: $(phrase)")
    end
end

if isempty(failures)
    println("ProcessBigraphs Phase 17 specification check passed:")
    println("  accepted interview decisions: 14 + 18 + 28")
    println("  required documentation pages: ", length(pages))
    println("  required browser journeys: ", length(journeys))
    println("  qualification rows: ", length(rows))
    println("  implementation authorized: true")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("ProcessBigraphs Phase 17 specification check failed with $(length(failures)) error(s)")
end

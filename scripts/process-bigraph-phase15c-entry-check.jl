#!/usr/bin/env julia

using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const failures = String[]
fail(message) = push!(failures, message)
check(condition, message) = condition || fail(message)

function require_file(relative_path)
    path = joinpath(ROOT, relative_path)
    check(isfile(path), "missing Phase 15.C artifact: $(relative_path)")
    path
end

function unique_strings(values, label)
    check(all(value -> value isa String && !isempty(value), values),
        "$(label) contains an empty identity")
    check(length(values) == length(unique(values)),
        "$(label) contains duplicate identities")
    Set(String.(values))
end

const TARGETS = Set([
    "canonical-state-serialization",
    "temporal-process-protocol",
    "ordered-reactive-step-protocol",
    "explicit-iterative-constructs",
    "imminent-event-scheduler",
    "adaptive-deadlines",
    "versioned-update-algebra",
    "settled-boundary-checkpoint",
    "versioned-process-continuation",
    "semantic-lineage-rng",
    "transactional-failure",
    "readonly-observer-protocol",
    "serial-semantic-executor",
    "multirate-input-semantics",
    "independent-julia-specification-oracle",
])
const SUPPORTING = Set([
    "workflow-cycle-rejection",
    "exact-integer-logical-time",
    "actual-elapsed-partial-interval",
    "same-time-common-snapshot",
    "typed-process-deltas",
    "deterministic-conflict-reconciliation",
    "atomic-event-commit",
])
const RETAINED = Set([
    "canonical-process-bigraph-acset",
    "compiled-structural-epoch",
    "structured-cospan-open-composition",
    "derived-directed-wiring-view",
])
const EXCLUDED = Set([
    "structural-add-remove",
    "structural-divide",
    "structural-move-rewire",
    "process-reconfiguration-retirement",
    "merge-engulf-burst-general-rewrite",
    "mid-event-restart",
    "extension-emitters",
    "declared-measured-transfers",
    "threads-executor",
    "dagger-coarse-executor",
    "sciml-ode-adapter",
    "modelingtoolkit-frontend",
    "catalyst-jumpprocesses-adapter",
    "cobrexa-jump-fba-adapter",
    "sbml-supported-feature-matrix",
    "potts-spatial-process-adapter",
    "whole-cell-style-composite",
    "algebraic-rewriting-structural-transactions",
    "algebraicdynamics-scientific-extension",
    "python-declaration-interchange",
    "vivarium1-api-compatibility",
    "ray-rest-ec2-nextflow-backends",
])
const STAGES = [
    "15.C0-entry-freeze",
    "15.C1-production-serial-scheduler",
    "15.C2-semantic-rng",
    "15.C3-observation-and-continuation",
    "15.C4-failure-and-checkpoint",
    "15.C5-independent-julia-oracle",
    "15.C6-qualification-matrix",
    "15.C7-two-stage-closure",
]

const REQUIRED = [
    "design/audits/process-bigraph-phase15c-serial-alpha-owner-interview.md",
    "spec/decisions/0038-process-bigraph-serial-alpha.md",
    "design/audits/process-bigraph-phase15c-serial-alpha-plan.md",
    "spec/process-bigraph-phase15c-entry-v1.toml",
    "spec/process-bigraph-phase15c-qualification-v1.toml",
    "spec/process-bigraph-parity-registry-v1.toml",
    "lib/ProcessBigraphs/parity-registry.toml",
    "lib/ProcessBigraphs/Project.toml",
    "lib/ProcessBigraphs/src/executor.jl",
    "lib/ProcessBigraphs/src/scheduling.jl",
    "lib/ProcessBigraphs/src/semantic_rng.jl",
    "lib/ProcessBigraphs/src/continuations.jl",
    "lib/ProcessBigraphs/src/observation.jl",
    "lib/ProcessBigraphs/src/transactions.jl",
    "lib/ProcessBigraphs/src/logical_codec.jl",
    "lib/ProcessBigraphs/src/checkpoint_codec.jl",
    "lib/ProcessBigraphs/test/phase15c/test_serial_scheduler.jl",
    "lib/ProcessBigraphs/test/phase15c/test_semantic_rng.jl",
    "lib/ProcessBigraphs/test/phase15c/test_observation_continuation.jl",
    "lib/ProcessBigraphs/test/phase15c/test_failure_checkpoint.jl",
    "lib/ProcessBigraphs/test/phase15c/test_authoring_equivalence.jl",
    "lib/ProcessBigraphs/test/phase15c/test_properties_metamorphic.jl",
    "lib/ProcessBigraphs/test/phase15c/test_restart_matrix.jl",
    "lib/ProcessBigraphs/test/specification_oracle/Oracle.jl",
    "lib/ProcessBigraphs/test/specification_oracle/fixtures.toml",
    "lib/ProcessBigraphs/test/specification_oracle/derivations.toml",
    "lib/ProcessBigraphs/test/specification_oracle/boundary_check.jl",
    "scripts/process-bigraph-phase15c-oracle.jl",
    "scripts/process-bigraph-phase15c-guardrails.jl",
    "scripts/process-bigraph-phase15c-candidate.jl",
    ".github/workflows/ci.yml",
]
paths = Dict(path => require_file(path) for path in REQUIRED)

entry = TOML.parsefile(paths["spec/process-bigraph-phase15c-entry-v1.toml"])
qualification = TOML.parsefile(
    paths["spec/process-bigraph-phase15c-qualification-v1.toml"])
registry = TOML.parsefile(
    paths["spec/process-bigraph-parity-registry-v1.toml"])
local_registry = TOML.parsefile(
    paths["lib/ProcessBigraphs/parity-registry.toml"])
project = TOML.parsefile(paths["lib/ProcessBigraphs/Project.toml"])

check(entry["schema_version"] == "1.0.0" &&
      entry["contract_id"] == "process-bigraphs-phase15c-entry-v1",
    "entry contract identity changed")
check(entry["pins"]["process_bigraph_commit"] ==
      "305ea826191e9f897f0c6e207bc303bbc44a9eef" &&
      entry["pins"]["bigraph_schema_commit"] ==
      "4b208e13620e09e877af52ea07273bc9429a3a17" &&
      entry["pins"]["upstream_python_runtime_execution"] == "forbidden",
    "source pins or no-Python-oracle rule changed")
check(Set(entry["scope"]["target_features"]) == TARGETS &&
      Set(entry["scope"]["supporting_oracle_features"]) == SUPPORTING &&
      Set(entry["scope"]["retained_direct_features"]) == RETAINED &&
      Set(entry["scope"]["excluded_features"]) == EXCLUDED,
    "frozen allowlists or exclusions changed")
check(entry["ordering"]["strict"] == true &&
      entry["ordering"]["stages"] == STAGES,
    "strict C0-C7 order changed")
check(entry["closure"]["implementation_pr_required"] == true &&
      entry["closure"]["closure_attestation_pr_required"] == true &&
      entry["closure"]["merge_method"] == "squash" &&
      entry["closure"]["ci_bypass_allowed"] == false &&
      entry["closure"]["publish_package"] == false,
    "two-stage closure policy changed")

phase_status = entry["runtime_implementation_status"]
candidate = phase_status == "implemented_awaiting_attestation"
closed = phase_status == "qualified_internal_alpha"
check(candidate || closed,
    "Phase 15.C checker requires implementation-candidate or closed state")
check(entry["public_release"] == false,
    "Phase 15.C must not claim a public release")
if candidate
    check(entry["status"] == "implementation_candidate" &&
          entry["internal_alpha"] == false &&
          entry["current_package_version"] == "0.3.0" &&
          project["version"] == "0.3.0",
        "implementation PR must remain 0.3.0 and pre-alpha")
    check(!isfile(joinpath(
            ROOT, "design/evidence/process-bigraph-phase15c-evidence-v1.toml")),
        "final attestation evidence must not exist in the implementation PR")
else
    require_file("design/evidence/process-bigraph-phase15c-evidence-v1.toml")
    check(entry["status"] == "closed_internal_alpha" &&
          entry["internal_alpha"] == true &&
          entry["current_package_version"] == "0.4.0" &&
          project["version"] == "0.4.0",
        "closed Phase 15.C must use version 0.4.0 and internal-alpha=true")
end

check(entry["entry_ci"]["phase15c_runtime_tests_present"] == true &&
      entry["entry_ci"]["phase15c_oracle_lane_present"] == true,
    "entry contract does not record the implementation and oracle CI lanes")

check(qualification["schema_version"] == "1.0.0" &&
      qualification["phase"] == "15.C",
    "qualification ledger identity changed")
for (key, expected) in (
    "fixture_count" => 8,
    "method_count" => 8,
    "authoring_path_count" => 6,
    "invariance_dimension_count" => 8,
    "performance_guardrail_count" => 4,
    "failure_stage_count" => 8,
    "mutation_target_count" => 5,
    "restart_cut_count" => 33,
    "phase15c_assertion_count" => 440,
    "historical_assertion_count" => 309,
    "aqua_assertion_count" => 9,
    "oracle_differential_row_count" => 22,
    "oracle_unit_assertion_count" => 6,
    "mutation_assertion_count" => 10,
)
    check(qualification[key] == expected,
        "qualification total $(key) changed")
end
check(sum(group["count"] for group in
        qualification["assertion_groups"]) ==
      qualification["phase15c_assertion_count"],
    "assertion-group ledger does not reconcile")
check(sum(length(row["cuts"]) for row in
        qualification["restart_fixtures"]) ==
      qualification["restart_cut_count"],
    "restart-cut ledger does not reconcile")
for (field, count) in (
    "fixtures" => 8,
    "methods" => 8,
    "authoring_paths" => 6,
    "invariance_dimensions" => 8,
    "performance_guardrails" => 4,
    "failure_stages" => 8,
    "mutation_targets" => 5,
)
    check(length(unique_strings(qualification[field], field)) == count,
        "$(field) ledger count changed")
end

derivations = TOML.parsefile(joinpath(
    ROOT, "lib", "ProcessBigraphs", "test",
    "specification_oracle", "derivations.toml"))["rules"]
check(length(derivations) == 22 &&
      Set(String(rule["id"]) for rule in derivations) ==
        TARGETS ∪ SUPPORTING,
    "independent oracle derivations are not exactly the 22 scoped rows")
oracle_source = read(paths[
    "lib/ProcessBigraphs/test/specification_oracle/Oracle.jl"], String)
check(!occursin(r"(?m)^\s*(using|import)\s+ProcessBigraphs\b",
        oracle_source),
    "independent oracle imports production")
for (directory, _, files) in walkdir(joinpath(
        ROOT, "lib", "ProcessBigraphs", "src"))
    for file in files
        endswith(file, ".jl") || continue
        check(!occursin("specification_oracle",
                read(joinpath(directory, file), String)),
            "production source depends on the test oracle")
    end
end

features = Dict(row["id"] => row for row in registry["features"])
oracles = Dict(row["id"] => row for row in registry["oracles"])
check(TARGETS ∪ SUPPORTING ∪ RETAINED <= Set(keys(features)),
    "root registry omits Phase 15.C scoped features")
check(oracles["oracle-independent-specification"]["status"] ==
      (candidate ? "oracle_passing" : "qualified"),
    "root independent-oracle status disagrees with closure stage")
for id in TARGETS ∪ SUPPORTING
    check(features[id]["status"] ==
          (candidate ? "oracle_passing" : "qualified"),
        "feature $(id) disagrees with Phase 15.C closure stage")
end
for id in RETAINED
    check(features[id]["status"] == "implemented",
        "retained Phase 15.A/B row $(id) was relabelled")
end
for id in EXCLUDED
    check(features[id]["status"] != "qualified",
        "excluded feature $(id) was qualified")
end

check(local_registry["package_version"] == project["version"] &&
      local_registry["internal_alpha"] == closed &&
      local_registry["public_release"] == false,
    "package-local maturity disagrees with closure stage")
check(registry["registry_status"] == (candidate ?
        "phase15c-implementation-candidate-awaiting-attestation" :
        "phase15c-qualified-serial-internal-alpha"),
    "root registry status disagrees with closure stage")

ci = read(paths[".github/workflows/ci.yml"], String)
for phrase in (
    "ProcessBigraphs Phase 15.C implementation and closure",
    "Phase 15.C independent oracle",
    "scripts/process-bigraph-phase15c-oracle.jl",
    "scripts/process-bigraph-phase15c-guardrails.jl",
    "scripts/process-bigraph-phase15c-candidate.jl",
    "phase15c-guardrails.toml",
    "phase15c_candidate",
    "actions/upload-artifact",
)
    check(occursin(phrase, ci),
        "CI is missing Phase 15.C requirement: $(phrase)")
end

if isempty(failures)
    println("ProcessBigraphs Phase 15.C implementation check passed:")
    println("  closure stage: ", candidate ?
        "implementation candidate awaiting attestation" :
        "qualified serial internal alpha")
    println("  15 targets + 7 supporting + 4 retained; 22 exclusions")
    println("  440 Phase 15.C + 309 historical + 9 Aqua assertions")
    println("  22 exact oracle rows; 5 mutants; 8 failure stages; 33 restart cuts")
else
    println(stderr,
        "ProcessBigraphs Phase 15.C check failed with $(length(failures)) issue(s):")
    for message in failures
        println(stderr, "  - ", message)
    end
    exit(1)
end

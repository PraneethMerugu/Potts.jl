#!/usr/bin/env julia

using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const failures = String[]

fail(message) = push!(failures, message)
check(condition, message) = condition || fail(message)

function require_file(relative_path)
    path = joinpath(ROOT, relative_path)
    check(isfile(path), "missing Phase 15.C entry artifact: $relative_path")
    path
end

function ids(rows, label)
    values = [get(row, "id", "") for row in rows]
    check(all(value -> value isa String && !isempty(value), values),
        "$label contains an empty id")
    check(length(values) == length(unique(values)), "$label contains duplicate ids")
    values
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

required = [
    "design/audits/process-bigraph-phase15c-serial-alpha-owner-interview.md",
    "spec/decisions/0038-process-bigraph-serial-alpha.md",
    "design/audits/process-bigraph-phase15c-serial-alpha-plan.md",
    "spec/process-bigraph-phase15c-entry-v1.toml",
    "design/audits/process-bigraph-phase15c-entry-audit.md",
    "scripts/process-bigraph-phase15c-entry-check.jl",
    "spec/process-bigraph-runtime-semantics.md",
    "spec/process-bigraph-parity-registry-v1.toml",
    "lib/ProcessBigraphs/parity-registry.toml",
    "lib/ProcessBigraphs/Project.toml",
    "design/refactor-roadmap.md",
    "design/repository-architecture-standard.md",
    "lib/ProcessBigraphs/README.md",
    "lib/ProcessBigraphs/docs/src/internal.md",
    "spec/README.md",
    "spec/decisions/README.md",
    ".github/workflows/ci.yml",
]
paths = Dict(path => require_file(path) for path in required)

entry = TOML.parsefile(paths["spec/process-bigraph-phase15c-entry-v1.toml"])
registry = TOML.parsefile(paths["spec/process-bigraph-parity-registry-v1.toml"])
local_registry = TOML.parsefile(paths["lib/ProcessBigraphs/parity-registry.toml"])
project = TOML.parsefile(paths["lib/ProcessBigraphs/Project.toml"])

check(entry["schema_version"] == "1.0.0", "entry schema version changed")
check(entry["contract_id"] == "process-bigraphs-phase15c-entry-v1",
    "entry contract identity changed")
check(entry["phase"] == "15.C" &&
      entry["status"] == "ready_after_preimplementation_packet_merges" &&
      entry["runtime_implementation_status"] == "not_started",
    "entry contract does not record a frozen, unimplemented Phase 15.C")
check(entry["internal_alpha"] == false && entry["public_release"] == false,
    "entry contract overclaims maturity or release")
check(entry["current_package_version"] == "0.3.0" &&
      entry["closure_package_version"] == "0.4.0" &&
      entry["julia"] == "1.12.6",
    "entry version boundary changed")
check(entry["pins"]["process_bigraph_commit"] ==
      "305ea826191e9f897f0c6e207bc303bbc44a9eef" &&
      entry["pins"]["bigraph_schema_commit"] ==
      "4b208e13620e09e877af52ea07273bc9429a3a17" &&
      entry["pins"]["upstream_python_runtime_execution"] == "forbidden",
    "entry source pins or Python execution policy changed")

scope = entry["scope"]
actual_targets = Set(scope["target_features"])
actual_supporting = Set(scope["supporting_oracle_features"])
actual_retained = Set(scope["retained_direct_features"])
actual_excluded = Set(scope["excluded_features"])
check(actual_targets == TARGETS, "Phase 15.C target allowlist changed")
check(actual_supporting == SUPPORTING, "Phase 15.C supporting allowlist changed")
check(actual_retained == RETAINED, "Phase 15.C retained-evidence allowlist changed")
check(actual_excluded == EXCLUDED, "Phase 15.C exclusion list changed")
for (set, expected_length, label) in [
        (actual_targets, 15, "target"),
        (actual_supporting, 7, "supporting"),
        (actual_retained, 4, "retained"),
        (actual_excluded, 22, "excluded")]
    check(length(set) == expected_length, "$label feature count changed")
end
sets = [actual_targets, actual_supporting, actual_retained, actual_excluded]
check(all(isempty(intersect(sets[i], sets[j]))
          for i in eachindex(sets) for j in (i + 1):length(sets)),
    "entry feature sets overlap")
check(entry["ordering"]["strict"] == true &&
      entry["ordering"]["stages"] == STAGES,
    "strict C0--C7 ordering changed")

check(entry["scheduler"]["executor"] == "SerialExecutor policy over SerialRuntime state" &&
      occursin("common immutable", entry["scheduler"]["same_time_visibility"]) &&
      occursin("atomically", entry["scheduler"]["adaptive_deadline"]),
    "scheduler authority or atomic visibility changed")
check(entry["rng"]["model"] == "versioned counter-based semantic addressing" &&
      entry["rng"]["failed_event_consumes_identity"] == false &&
      entry["rng"]["observer_namespace_isolated"] == true,
    "semantic RNG boundary changed")
check(entry["continuation"]["untracked_any_alpha_qualified"] == false &&
      entry["failure"]["policy"] == "deterministic fail-stop" &&
      entry["failure"]["implicit_retry"] == false,
    "continuation or fail-stop boundary changed")
check(entry["checkpoint"]["julia_object_serialization_authoritative"] == false &&
      entry["checkpoint"]["restore_mode"] == "exact compatible serial restore only",
    "checkpoint authority changed")
check(entry["oracle"]["location"] ==
      "lib/ProcessBigraphs/test/specification_oracle" &&
      entry["oracle"]["production_dependency"] == false,
    "independent-oracle ownership changed")
check(entry["closure"]["all_or_nothing"] == true &&
      entry["closure"]["implementation_pr_required"] == true &&
      entry["closure"]["closure_attestation_pr_required"] == true &&
      entry["closure"]["version_bump_in_attestation"] == "0.4.0" &&
      entry["closure"]["publish_package"] == false,
    "two-stage closure contract changed")
check(entry["entry_ci"]["phase15c_runtime_tests_present"] == false &&
      entry["entry_ci"]["phase15c_oracle_lane_present"] == false,
    "pre-implementation packet falsely claims runtime/oracle CI")

features = registry["features"]
feature_id_list = ids(features, "root feature registry")
feature_ids = Set(feature_id_list)
check(TARGETS ∪ SUPPORTING ∪ RETAINED <= feature_ids,
    "root registry omits an entry-scoped feature")
feature_by_id = Dict(row["id"] => row for row in features)
for id in TARGETS ∪ SUPPORTING
    check("oracle-independent-specification" in feature_by_id[id]["oracle_ids"],
        "feature '$id' is not attached to the Phase 15.C oracle")
end
for id in TARGETS
    check(feature_by_id[id]["status"] != "qualified",
        "target '$id' is prematurely qualified")
end

oracles = registry["oracles"]
oracle_id_list = ids(oracles, "root oracle registry")
oracle_by_id = Dict(row["id"] => row for row in oracles)
phase15c_oracle = oracle_by_id["oracle-independent-specification"]
check(phase15c_oracle["kind"] == "independent_julia" &&
      phase15c_oracle["status"] == "not_started" &&
      phase15c_oracle["required"] == true,
    "Phase 15.C oracle maturity or kind changed")
check(Set(phase15c_oracle["feature_ids"]) == TARGETS ∪ SUPPORTING,
    "Phase 15.C oracle scope is not exactly target plus supporting features")
for id in ["oracle-dynamic-topology", "oracle-division-lineage",
        "oracle-executor-equivalence", "oracle-residency-hardware",
        "oracle-whole-cell-composite"]
    check(haskey(oracle_by_id, id) && oracle_by_id[id]["status"] == "not_started",
        "broader oracle '$id' is missing or prematurely passed")
end

check(registry["registry_status"] ==
      "phase15c-entry-frozen-runtime-not-started",
    "root registry does not record the Phase 15.C entry freeze")
summary = registry["phase15c_entry"]
check(summary["status"] == entry["status"] &&
      summary["runtime_implementation_status"] == "not_started" &&
      summary["target_feature_count"] == 15 &&
      summary["supporting_oracle_feature_count"] == 7 &&
      summary["retained_direct_feature_count"] == 4 &&
      summary["internal_alpha"] == false &&
      summary["public_release"] == false,
    "root registry Phase 15.C summary disagrees with entry contract")

check(project["version"] == "0.3.0" &&
      Set(keys(project["deps"])) == Set(["ACSets", "Catlab", "SHA"]) &&
      project["compat"]["julia"] == "1.12.6",
    "package identity or dependency boundary changed before implementation")
check(local_registry["package_version"] == "0.3.0" &&
      local_registry["maturity"] == "phase_15b_open_composition" &&
      local_registry["internal_alpha"] == false &&
      local_registry["public_release"] == false,
    "package-local registry overclaims Phase 15.C maturity")
next_architecture = local_registry["accepted_next_architecture"]
check(next_architecture["phase15c_status"] ==
      "entry_frozen_runtime_not_started" &&
      next_architecture["phase15c_target_feature_count"] == 15 &&
      next_architecture["phase15c_supporting_oracle_feature_count"] == 7 &&
      next_architecture["phase15c_retained_direct_feature_count"] == 4,
    "package-local Phase 15.C planning metadata changed")

interview = read(paths[
    "design/audits/process-bigraph-phase15c-serial-alpha-owner-interview.md"], String)
decision = read(paths["spec/decisions/0038-process-bigraph-serial-alpha.md"], String)
plan = read(paths[
    "design/audits/process-bigraph-phase15c-serial-alpha-plan.md"], String)
audit = read(paths[
    "design/audits/process-bigraph-phase15c-entry-audit.md"], String)
semantics = read(paths["spec/process-bigraph-runtime-semantics.md"], String)
check(occursin("Status: Complete; all 64 owner decisions resolved", interview) &&
      occursin("owner selected a for all eight questions in all eight rounds",
        lowercase(replace(interview, '\n' => ' '))),
    "owner interview is incomplete")
check(occursin(
        "Status: Accepted pre-implementation architecture; Phase 15.C runtime implementation not started",
        decision),
    "Decision 0038 disposition changed")
check(occursin(
        "Status: Accepted pre-implementation plan; runtime implementation not started",
        plan),
    "Phase 15.C plan disposition changed")
check(occursin(
        "Status: Passed pre-implementation design audit; runtime implementation not started",
        audit),
    "Phase 15.C entry audit disposition changed")
for phrase in [
        "Version: 1.3.0",
        "one common immutable pre-commit snapshot",
        "unpublished candidate",
        "counter-based",
        "deterministic fail-stop",
        "independent",
        "object serialization"]
    check(occursin(phrase, semantics),
        "runtime semantics are missing '$phrase'")
end

documentation = join(read(paths[path], String) for path in [
    "design/refactor-roadmap.md",
    "design/repository-architecture-standard.md",
    "lib/ProcessBigraphs/README.md",
    "lib/ProcessBigraphs/docs/src/internal.md",
    "spec/README.md",
    "spec/decisions/README.md",
])
for phrase in [
        "0038-process-bigraph-serial-alpha.md",
        "process-bigraph-phase15c-entry-v1.toml",
        "process-bigraph-phase15c-serial-alpha-plan.md",
        "runtime implementation not started"]
    check(occursin(phrase, lowercase(documentation)),
        "documentation is missing Phase 15.C entry reference '$phrase'")
end

ci = read(paths[".github/workflows/ci.yml"], String)
check(occursin(
        "name: Enforce ProcessBigraphs Phase 15.C pre-implementation entry", ci) &&
      occursin(
        "julia --startup-file=no scripts/process-bigraph-phase15c-entry-check.jl", ci),
    "required CI does not enforce the Phase 15.C entry gate")
check(!ispath(joinpath(ROOT, "design/evidence/process-bigraph-phase15c-evidence-v1.toml")),
    "final Phase 15.C evidence exists before implementation and attestation")

if isempty(failures)
    println("ProcessBigraphs Phase 15.C pre-implementation entry check passed:")
    println("  64 owner decisions resolved and frozen in Decision 0038")
    println("  15 targets + 7 supporting + 4 retained rows; 22 explicit exclusions")
    println("  strict C0--C7 plan and independent Julia-oracle boundary")
    println("  package remains 0.3.0 with internal_alpha=false")
    println("  runtime implementation, oracle evidence, and qualification not started")
else
    println(stderr,
        "ProcessBigraphs Phase 15.C entry check failed with $(length(failures)) issue(s):")
    for message in failures
        println(stderr, "  - ", message)
    end
    exit(1)
end

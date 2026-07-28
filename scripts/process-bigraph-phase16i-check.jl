#!/usr/bin/env julia

using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const failures = String[]
check(condition, message) = condition || push!(failures, message)

function require_file(relative)
    path = joinpath(ROOT, relative)
    check(isfile(path), "missing Phase 16.I artifact: $(relative)")
    return path
end

const REQUIRED = [
    "design/audits/process-bigraph-phase16i-reconciliation-audit.md",
    "design/evidence/process-bigraph-phase16c-evidence-v1.toml",
    "design/evidence/process-bigraph-phase16hc-evidence-v1.toml",
    "benchmark/phase16hc_authoring_qualification.jl",
    "lib/ProcessBigraphs/Project.toml",
    "lib/ProcessBigraphs/README.md",
    "lib/ProcessBigraphs/docs/src/internal.md",
    "lib/ProcessBigraphs/docs/src/internal-beta.md",
    "lib/ProcessBigraphs/docs/src/adapters-and-solvers.md",
    "lib/ProcessBigraphs/docs/src/failure-and-persistence.md",
    "lib/ProcessBigraphs/docs/src/phase16-capabilities.md",
    "lib/ProcessBigraphs/parity-registry.toml",
    "scripts/process-bigraph-phase16-docs.jl",
    "scripts/process-bigraph-phase16i-candidate.jl",
    "spec/process-bigraph-phase16-entry-v1.toml",
    "spec/process-bigraph-phase16-api-v1.toml",
    "spec/process-bigraph-phase16-backend-matrix-v1.toml",
    "spec/process-bigraph-phase16-migration-registry-v1.toml",
    "spec/process-bigraph-phase16-model-scope-v1.toml",
    "spec/process-bigraph-phase16-qualification-v1.toml",
    "spec/process-bigraph-parity-registry-v1.toml",
    ".github/workflows/ci.yml",
]
paths = Dict(path => require_file(path) for path in REQUIRED)
const RESOLUTION_FILES = Set([
    "Project.toml",
    "Manifest.toml",
    "benchmark/Project.toml",
    "benchmark/Manifest.toml",
    "docs/Project.toml",
    "docs/Manifest.toml",
    "examples/Project.toml",
    "examples/Manifest.toml",
    "examples/dashboards/Project.toml",
    "examples/dashboards/Manifest.toml",
    "examples/notebooks/Project.toml",
    "examples/notebooks/Manifest.toml",
    "integration/Project.toml",
    "lib/CorePotts/Project.toml",
    "lib/MakiePotts/Project.toml",
    "lib/MakiePotts/test/backends/Project.toml",
    "lib/MakiePotts/test/backends/Manifest.toml",
    "lib/ProcessBigraphs/Project.toml",
    "paper/Project.toml",
    "paper/Manifest.toml",
])

entry = TOML.parsefile(paths["spec/process-bigraph-phase16-entry-v1.toml"])
api = TOML.parsefile(paths["spec/process-bigraph-phase16-api-v1.toml"])
matrix = TOML.parsefile(
    paths["spec/process-bigraph-phase16-backend-matrix-v1.toml"])
migration = TOML.parsefile(
    paths["spec/process-bigraph-phase16-migration-registry-v1.toml"])
models = TOML.parsefile(
    paths["spec/process-bigraph-phase16-model-scope-v1.toml"])
ledger = TOML.parsefile(
    paths["spec/process-bigraph-phase16-qualification-v1.toml"])
parity = TOML.parsefile(
    paths["spec/process-bigraph-parity-registry-v1.toml"])
local_parity = TOML.parsefile(
    paths["lib/ProcessBigraphs/parity-registry.toml"])
project = TOML.parsefile(paths["lib/ProcessBigraphs/Project.toml"])
phase16c = TOML.parsefile(
    paths["design/evidence/process-bigraph-phase16c-evidence-v1.toml"])

state = entry["implementation_status"]
candidate = state == "phase16i_candidate"
closed = state == "phase16_internal_beta_qualified"
check(candidate || closed,
    "Phase 16.I checker requires candidate or qualified internal-beta state")

requirements = Dict(row["id"] => row for row in ledger["requirements"])
i_status = candidate ? "oracle_passing" : "qualified"
for id in ["P16-I01", "P16-I02", "P16-I03"]
    check(requirements[id]["status"] == i_status,
        "$(id) must be $(i_status)")
end
for (id, row) in requirements
    startswith(id, "P16-I") && continue
    check(row["status"] == "qualified",
        "$(id) lost qualification during Phase 16.I")
end
check(length(requirements) == ledger["required_row_count"] == 38,
    "Phase 16.I ledger row count changed")
check(candidate ?
      (ledger["status"] == "open" && ledger["closure_status"] == "open") :
      (ledger["status"] == "qualified_internal_beta" &&
       ledger["closure_status"] == "qualified_internal_beta"),
    "Phase 16.I ledger closure state changed")

check(entry["phase16i"]["status"] == (candidate ? "candidate" : "qualified") &&
      entry["phase16i"]["all_prior_subgates_qualified"] == true &&
      entry["phase16i"]["documentation_reconciled"] == true &&
      entry["phase16i"]["clean_independent_packages_required"] == true &&
      entry["phase16i"]["frozen_performance_required"] == true &&
      entry["phase16i"]["exact_head_candidate_required"] == true &&
      entry["phase16i"]["prospective_merge_tree_identity_required"] == true &&
      entry["phase16i"]["metadata_only_attestation_required"] == true,
    "Phase 16.I control-plane contract changed")
check(entry["internal_beta"] == closed &&
      entry["public_release"] == false &&
      project["version"] == (closed ? "0.5.0" : "0.4.0") &&
      entry["current_package_version"] == project["version"] &&
      api["current_package_version"] == project["version"],
    "Phase 16.I maturity or package version is inconsistent")

check(api["status"] == state &&
      api["current_new_exports"] == api["planned_internal_beta_exports"] &&
      api["public_release"] == false &&
      matrix["status"] == "phase16c_qualified" &&
      matrix["phase16f_status"] == "qualified" &&
      matrix["phase16g_status"] == "qualified" &&
      matrix["phase16h_status"] == "qualified" &&
      matrix["phase16hc_status"] == "qualified" &&
      migration["status"] == "phase16hc_qualified" &&
      all(row["status"] == "qualified" for row in models["models"]),
    "Phase 16.I API, backend, migration, or model matrices diverged")
check(parity["phase16_entry"]["implementation_status"] == state &&
      parity["phase16_entry"]["internal_beta"] == closed &&
      parity["phase16_entry"]["public_release"] == false &&
      local_parity["accepted_next_architecture"]["phase16_status"] == state &&
      local_parity["accepted_next_architecture"]["phase16_internal_beta"] ==
          closed &&
      local_parity["accepted_next_architecture"]["phase16_public_release"] ==
          false,
    "Phase 16.I root/package maturity registries diverged")

check(phase16c["status"] == "qualified" &&
      phase16c["ci"]["conclusion"] == "success" &&
      phase16c["hardware"]["metal_exact_head"] == true &&
      phase16c["hardware"]["rocm_exact_head"] == true,
    "Phase 16.I lost mandatory trusted hardware evidence")
check(Set(keys(project["deps"])) ==
      Set(["ACSets", "AlgebraicRewriting", "Catlab", "SHA"]) &&
      Set(keys(project["weakdeps"])) == Set(["CommonSolve", "SciMLBase"]) &&
      !haskey(project["deps"], "CorePotts") &&
      !haskey(project["deps"], "SciMLBase"),
    "ProcessBigraphs independent dependency boundary widened")

doc_requirements = Dict(
    "lib/ProcessBigraphs/docs/src/internal-beta.md" => [
        "when and why", "ordinary Julia", "Important limits",
        "metadata-only",
    ],
    "lib/ProcessBigraphs/docs/src/adapters-and-solvers.md" => [
        "The ownership boundary", "Exact targets and early returns",
        "SciML adapter", "Independent adapters", "silent",
    ],
    "lib/ProcessBigraphs/docs/src/failure-and-persistence.md" => [
        "Transaction boundary", "Failure stages", "Settled checkpoints",
        "Legacy conversion", "non-destructive",
    ],
    "lib/ProcessBigraphs/docs/src/phase16-capabilities.md" => [
        "Generated by scripts/process-bigraph-phase16-docs.jl",
        "Backend envelopes", "API families", "Runnable model scope",
        "Explicit Phase 16 scope exclusions",
    ],
)
for (relative, phrases) in doc_requirements
    text = read(paths[relative], String)
    for phrase in phrases
        check(occursin(phrase, text),
            "$(relative) omits $(phrase)")
    end
end

generated_check = success(`$(Base.julia_cmd()) --startup-file=no $(paths[
    "scripts/process-bigraph-phase16-docs.jl"]) --check`)
check(generated_check,
    "Phase 16 generated capability documentation is stale")

workflow = read(paths[".github/workflows/ci.yml"], String)
for phrase in (
    "process-bigraph-phase16i-check.jl",
    "process-bigraph-phase16-docs.jl --check",
    "phase16i_candidate:",
    "process-bigraph-phase16i-candidate.jl",
    "process-bigraphs-phase16i-candidate",
    "PHASE16I_CANDIDATE_RESULT",
)
    check(occursin(phrase, workflow),
        "CI omits Phase 16.I gate: $(phrase)")
end
for phrase in (
    "Pkg.activate(; temp=true)",
    "Pkg.develop(path=abspath(ENV[\"PROJECT\"]))",
    "Pkg.instantiate(; julia_version_strict=true)",
    "Pkg.test(ENV[\"PACKAGE\"]",
)
    check(occursin(phrase, workflow),
        "CI clean-package contract omits $(phrase)")
end

performance = TOML.parsefile(require_file(
    "design/evidence/process-bigraph-phase16hc-authoring-performance-v1.toml"))
check(all(values(performance["checks"])) &&
      performance["plan_identity_equal"] == true &&
      performance["warm_execution"]["time_ratio"] <=
          performance["budgets"]["warm_runtime_ratio_max"] &&
      performance["warm_execution"]["allocation_ratio"] <=
          performance["budgets"]["warm_allocation_ratio_max"],
    "frozen Phase 16 authoring performance evidence no longer passes")

final_evidence_path =
    joinpath(ROOT, "design", "evidence", "process-bigraph-phase16i-evidence-v1.toml")
candidate_path = joinpath(
    ROOT, "design", "evidence", "phase-16", "phase16i-candidate.toml")
if candidate
    check(!isfile(final_evidence_path) && !isfile(candidate_path),
        "candidate tree must not contain final Phase 16.I attestation evidence")
else
    final_evidence = TOML.parsefile(require_file(
        "design/evidence/process-bigraph-phase16i-evidence-v1.toml"))
    candidate_artifact = TOML.parsefile(require_file(
        "design/evidence/phase-16/phase16i-candidate.toml"))
    check(final_evidence["status"] == "qualified_internal_beta" &&
          final_evidence["phase"] == "16.I" &&
          final_evidence["internal_beta"] == true &&
          final_evidence["public_release"] == false &&
          final_evidence["candidate"]["artifact_sha256"] ==
              bytes2hex(SHA.sha256(read(candidate_path))) &&
          candidate_artifact["artifact_kind"] ==
              "phase16i-exact-head-internal-beta-candidate" &&
          candidate_artifact["tree_identity_verified"] == true &&
          candidate_artifact["dirty_state"] == "clean" &&
          Set(keys(candidate_artifact["dependency_resolution"])) ==
              RESOLUTION_FILES &&
          candidate_artifact["qualification"][
              "all_rows_at_least_oracle_passing"] == true &&
          candidate_artifact["performance"]["all_frozen_budgets_pass"] ==
              true,
        "Phase 16.I final attestation or candidate identity is invalid")
end

if isempty(failures)
    println("ProcessBigraphs Phase 16.I ",
        candidate ? "exact-head candidate" : "internal-beta qualification",
        " check passed.")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("ProcessBigraphs Phase 16.I check failed with $(length(failures)) error(s)")
end

#!/usr/bin/env julia

using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const failures = String[]
fail(message) = push!(failures, message)
check(condition, message) = condition || fail(message)

function require_file(relative_path)
    path = joinpath(ROOT, relative_path)
    check(isfile(path), "missing Phase 16 artifact: $(relative_path)")
    path
end

const REQUIRED = [
    "design/audits/process-bigraph-phase16-owner-interview.md",
    "design/audits/process-bigraph-phase16-implementation-plan.md",
    "design/audits/process-bigraph-phase16-entry-audit.md",
    "spec/decisions/0039-phase-16-compute-ownership-and-scope.md",
    "spec/phase-16-engine-field-structural-and-adapter-semantics.md",
    "spec/process-bigraph-phase16-entry-v1.toml",
    "spec/process-bigraph-phase16-qualification-v1.toml",
    "spec/process-bigraph-phase16-backend-matrix-v1.toml",
    "spec/process-bigraph-phase16-migration-registry-v1.toml",
    "spec/process-bigraph-phase16-model-scope-v1.toml",
    "spec/process-bigraph-phase16-api-v1.toml",
    "spec/process-bigraph-parity-registry-v1.toml",
    "lib/ProcessBigraphs/parity-registry.toml",
    "lib/ProcessBigraphs/Project.toml",
    "lib/ProcessBigraphs/ext/ProcessBigraphsSciMLExt.jl",
    "spec/process-bigraph-runtime-semantics.md",
    "spec/phase-14-semantic-kernel.md",
    "design/refactor-roadmap.md",
    "spec/README.md",
    "spec/conformance-evidence.md",
    ".github/workflows/ci.yml",
]
paths = Dict(path => require_file(path) for path in REQUIRED)

entry = TOML.parsefile(paths["spec/process-bigraph-phase16-entry-v1.toml"])
ledger = TOML.parsefile(paths["spec/process-bigraph-phase16-qualification-v1.toml"])
backends = TOML.parsefile(paths["spec/process-bigraph-phase16-backend-matrix-v1.toml"])
migration = TOML.parsefile(paths["spec/process-bigraph-phase16-migration-registry-v1.toml"])
models = TOML.parsefile(paths["spec/process-bigraph-phase16-model-scope-v1.toml"])
api = TOML.parsefile(paths["spec/process-bigraph-phase16-api-v1.toml"])
parity = TOML.parsefile(paths["spec/process-bigraph-parity-registry-v1.toml"])
local_parity = TOML.parsefile(paths["lib/ProcessBigraphs/parity-registry.toml"])
project = TOML.parsefile(paths["lib/ProcessBigraphs/Project.toml"])

check(entry["schema_version"] == "1.0.0" &&
      entry["contract_id"] == "process-bigraphs-phase16-entry-v1" &&
      entry["phase"] == "16",
    "Phase 16 entry identity changed")
check(entry["status"] == "ready_to_start" &&
      entry["implementation_status"] == "not_started" &&
      entry["internal_beta"] == false &&
      entry["public_release"] == false,
    "entry must claim ready-to-start but no implementation, beta, or release")
check(entry["current_package_version"] == "0.4.0" &&
      entry["target_package_version"] == "0.5.0",
    "Phase 16 maturity versions changed")

check(entry["principle"]["one_authority"] == true &&
      occursin("when and why", entry["principle"]["runtime"]) &&
      occursin("how", entry["principle"]["engine"]),
    "compute-ownership invariant changed")
check(entry["prerequisites"]["phase13_frozen"] == true &&
      entry["prerequisites"]["phase14_g3b_attested"] == true &&
      entry["prerequisites"]["process_bigraphs_phase15c_internal_alpha"] == true &&
      entry["prerequisites"]["g4_external_prerequisite"] == false &&
      occursin("16.C", entry["prerequisites"]["g4_disposition"]),
    "entry prerequisites or absorbed-G4 disposition changed")

const SUBGATES = [
    "16.A-entry-contract-dependencies-api-and-checkers",
    "16.B-engine-and-field-protocol",
    "16.C-absorbed-g4-native-field-qualification",
    "16.D-algebraic-rewriting-dynamic-hierarchy",
    "16.E-corepotts-adapter-checkpoint-and-first-cutover",
    "16.F-sciml-custom-and-cross-adapter-qualification",
    "16.G-runnable-merks-2006",
    "16.H-runnable-cnv-scenario38",
    "16.I-reconciliation-and-internal-beta-attestation",
]
check(entry["ordering"]["subgates"] == SUBGATES &&
      entry["ordering"]["parallel_after"] == "16.B" &&
      Set(entry["ordering"]["parallel_branches"]) == Set(["16.C", "16.D"]) &&
      entry["ordering"]["compensation_allowed"] == false,
    "Phase 16 subgate ordering changed")

required_scope = Set(entry["scope"]["required"])
for id in [
    "solver-neutral-engine-protocol",
    "native-field-cpu-metal-rocm",
    "algebraic-rewriting-dynamic-hierarchy",
    "corepotts-strangler-adapter-and-first-cutover",
    "cpu-sciml-field-adapter",
    "cpu-independent-custom-field-adapter",
    "runnable-source-bounded-merks-2006",
    "runnable-source-bounded-cnv-scenario38-sim902",
]
    check(id in required_scope, "required Phase 16 scope missing $(id)")
end
excluded_scope = Set(entry["scope"]["excluded"])
for id in [
    "public-release",
    "dagger-or-distributed-qualification",
    "universal-solver-gpu-support",
    "full-merks-publication-analysis",
    "full-cnv-publication-analysis",
    "whole-cell-qualification",
]
    check(id in excluded_scope, "Phase 16 exclusion missing $(id)")
end

check(entry["dependency_policy"]["core_hard_sciml_dependency"] == false &&
      entry["dependency_policy"]["process_bigraphs_depends_on_corepotts"] == false &&
      entry["dependency_policy"]["corepotts_depends_on_process_bigraphs"] == true &&
      entry["dependency_policy"]["upstream_python_runtime_execution"] == "forbidden",
    "dependency direction or no-Python rule changed")
check(Set(keys(project["deps"])) ==
      Set(["ACSets", "AlgebraicRewriting", "Catlab", "SHA"]) &&
      project["deps"]["AlgebraicRewriting"] ==
      "725a01d3-f174-5bbd-84e1-b9417bad95d9" &&
      project["compat"]["AlgebraicRewriting"] ==
      entry["dependency_policy"]["algebraic_rewriting_compat"],
    "actual direct dependencies do not match the Phase 16 entry contract")
check(Set(keys(project["weakdeps"])) == Set(["CommonSolve", "SciMLBase"]) &&
      project["extensions"]["ProcessBigraphsSciMLExt"] ==
      ["CommonSolve", "SciMLBase"] &&
      project["compat"]["CommonSolve"] ==
      entry["dependency_policy"]["commonsolve_compat"] &&
      project["compat"]["SciMLBase"] ==
      entry["dependency_policy"]["scimlbase_compat"],
    "actual SciML weak-dependency extension boundary does not match Phase 16")
check(entry["backends"]["native_required"] == ["CPU", "Metal", "ROCm"] &&
      entry["backends"]["real_hardware_required"] == ["Metal", "ROCm"] &&
      entry["backends"]["cuda"] == "deferred" &&
      entry["backends"]["hidden_transfer"] == "forbidden" &&
      entry["backends"]["hidden_host_fallback"] == "forbidden",
    "backend qualification boundary changed")
check(entry["models"]["full_analysis_required"] == false &&
      entry["models"]["quantitative_reproduction_claim"] == false,
    "model scope must remain runnable, not reproduction")
check(entry["closure"]["closure_checker_expected_now"] == "open" &&
      entry["closure"]["publish_package"] == false &&
      entry["closure"]["real_hardware_required"] == true,
    "Phase 16 closure discipline changed")

requirements = ledger["requirements"]
check(ledger["status"] == "open" && ledger["closure_status"] == "open",
    "qualification ledger must remain open at entry")
check(length(requirements) == ledger["required_row_count"] == 31,
    "Phase 16 ledger must contain exactly 31 required rows")
ids = String[row["id"] for row in requirements]
check(length(ids) == length(unique(ids)), "duplicate Phase 16 requirement id")
allowed = Set(ledger["allowed_statuses"])
check(all(row -> row["status"] in allowed, requirements),
    "qualification ledger contains an invalid status")
check(all(row -> row["status"] == "specified", requirements),
    "entry packet may not claim implementation evidence")
check(Set(String[row["subgate"] for row in requirements]) ==
      Set(["16.A", "16.B", "16.C", "16.D", "16.E", "16.F", "16.G", "16.H", "16.I"]),
    "qualification ledger does not cover every subgate")

envelopes = Dict(row["id"] => row for row in backends["envelopes"])
check(Set(keys(envelopes)) == Set([
        "native-cartesian-field",
        "sciml-cartesian-field",
        "independent-custom-field",
        "merks-source-faithful-assembly",
        "cnv-source-faithful-assembly",
    ]),
    "backend matrix envelope set changed")
native = envelopes["native-cartesian-field"]
check(native["CPU"] == "specified" && native["Metal"] == "specified" &&
      native["ROCm"] == "specified" && native["CUDA"] == "not_applicable",
    "native field matrix must require CPU/Metal/ROCm and defer CUDA")
for id in ["sciml-cartesian-field", "independent-custom-field",
           "merks-source-faithful-assembly", "cnv-source-faithful-assembly"]
    row = envelopes[id]
    check(row["CPU"] == "specified" &&
          row["Metal"] == "unsupported" &&
          row["ROCm"] == "unsupported",
        "$(id) must make an honest CPU-only Phase 16 claim")
end

check(migration["one_production_authority_per_slice"] == true &&
      migration["silent_fallback"] == false &&
      migration["checkpoint"]["existing_attested_readers_retained"] == true &&
      migration["checkpoint"]["settled_boundaries_only"] == true,
    "migration authority or checkpoint rule changed")
slice_ids = Set(String[row["id"] for row in migration["slices"]])
check(slice_ids == Set(["field-substrate", "dynamic-lifecycle", "merks-assembly", "cnv-assembly"]),
    "migration slice registry changed")

model_rows = Dict(row["id"] => row for row in models["models"])
check(models["claim"] == "runnable source-bounded reimplementation" &&
      models["quantitative_reproduction"] == false &&
      models["full_analysis"] == false,
    "Phase 16 model claim widened")
check(Set(keys(model_rows)) ==
      Set(["merks-2006-vasculogenesis", "shirinifard-2012-cnv"]),
    "required Phase 16 model set changed")
check(model_rows["merks-2006-vasculogenesis"]["required_dimension"] == [500, 500],
    "Merks canonical dimension changed")
check(model_rows["shirinifard-2012-cnv"]["required_scenario"] == 38 &&
      model_rows["shirinifard-2012-cnv"]["required_source_simulation"] == 902 &&
      model_rows["shirinifard-2012-cnv"]["required_dimension"] == [40, 40, 35],
    "CNV scenario/source/domain changed")

check(api["status"] == "frozen_preimplementation" &&
      api["current_new_exports"] == [] &&
      api["public_release"] == false &&
      api["policy"]["core_is_solver_neutral"] == true &&
      api["policy"]["sciml_via_extension"] == true &&
      api["policy"]["qualified_exports_only"] == true,
    "Phase 16 API contract widens the current unqualified surface")
planned_exports = String.(api["planned_internal_beta_exports"])
check(length(planned_exports) == length(unique(planned_exports)) &&
      Set(row["id"] for row in api["families"]) ==
      Set(["engine", "field", "structure", "sciml", "corepotts"]),
    "Phase 16 planned API identities or families are inconsistent")

check(parity["phase16_entry"]["status"] == "specified_ready_to_start" &&
      parity["phase16_entry"]["implementation_status"] == "not_started" &&
      parity["phase16_entry"]["g4_disposition"] == "mandatory Phase 16.C" &&
      parity["phase16_entry"]["internal_beta"] == false &&
      parity["phase16_entry"]["public_release"] == false,
    "root parity registry misstates Phase 16 entry or maturity")
check(local_parity["accepted_next_architecture"]["phase16_status"] ==
      "specified_ready_to_start" &&
      local_parity["accepted_next_architecture"]["phase16_internal_beta"] == false &&
      local_parity["accepted_next_architecture"]["phase16_public_release"] == false,
    "package-local registry misstates Phase 16 entry or maturity")

for (path, phrases) in [
    ("spec/decisions/0039-phase-16-compute-ownership-and-scope.md",
        ["when and why", "how", "Phase 16.C", "runnable source-bounded"]),
    ("spec/phase-16-engine-field-structural-and-adapter-semantics.md",
        ["ProcessBigraphs MUST be the only authority", "An engine MUST retain control",
         "Merks 2006", "CNV scenario 38"]),
    ("design/refactor-roadmap.md",
        ["absorbed G4", "Phase 16.C", "CPU SciML"]),
    ("spec/process-bigraph-runtime-semantics.md",
        ["Decision 0039", "solver-neutral"]),
    ("spec/README.md", ["Phase 16", "Decision 0039"]),
    ("spec/conformance-evidence.md", ["Phase 16", "specified"]),
    (".github/workflows/ci.yml", ["process-bigraph-phase16-entry-check.jl"]),
]
    text = read(paths[path], String)
    for phrase in phrases
        check(occursin(phrase, text), "$(path) missing required phrase: $(phrase)")
    end
end

if isempty(failures)
    println("ProcessBigraphs Phase 16 entry check passed: ready to start 16.A; closure remains open.")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("ProcessBigraphs Phase 16 entry check failed with $(length(failures)) error(s)")
end

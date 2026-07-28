#!/usr/bin/env julia

using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const failures = String[]
check(condition, message) = condition || push!(failures, message)

function require_file(relative)
    path = joinpath(ROOT, relative)
    check(isfile(path), "missing Phase 16.H artifact: $(relative)")
    path
end

const REQUIRED = [
    "design/audits/process-bigraph-phase16h-cnv-audit.md",
    "design/evidence/process-bigraph-phase16h-evidence-v1.toml",
    "lib/CorePotts/src/coupled/shirinifard2012.jl",
    "lib/CorePotts/test/test_phase16_shirinifard2012.jl",
    "lib/ProcessBigraphs/src/canonical.jl",
    "lib/ProcessBigraphs/src/managed_field_process.jl",
    "lib/ProcessBigraphs/test/test_paths_time_canonical.jl",
    "spec/process-bigraph-phase16-entry-v1.toml",
    "spec/process-bigraph-phase16-qualification-v1.toml",
    "spec/process-bigraph-phase16-backend-matrix-v1.toml",
    "spec/process-bigraph-phase16-migration-registry-v1.toml",
    "spec/process-bigraph-phase16-model-scope-v1.toml",
    "spec/process-bigraph-phase16-cnv-trace-v1.toml",
    "spec/process-bigraph-parity-registry-v1.toml",
    "lib/ProcessBigraphs/parity-registry.toml",
    ".github/workflows/ci.yml",
]
paths = Dict(path => require_file(path) for path in REQUIRED)

entry = TOML.parsefile(paths["spec/process-bigraph-phase16-entry-v1.toml"])
ledger = TOML.parsefile(
    paths["spec/process-bigraph-phase16-qualification-v1.toml"])
matrix = TOML.parsefile(
    paths["spec/process-bigraph-phase16-backend-matrix-v1.toml"])
migration = TOML.parsefile(
    paths["spec/process-bigraph-phase16-migration-registry-v1.toml"])
models = TOML.parsefile(
    paths["spec/process-bigraph-phase16-model-scope-v1.toml"])
trace = TOML.parsefile(
    paths["spec/process-bigraph-phase16-cnv-trace-v1.toml"])
parity = TOML.parsefile(
    paths["spec/process-bigraph-parity-registry-v1.toml"])
local_parity = TOML.parsefile(
    paths["lib/ProcessBigraphs/parity-registry.toml"])
evidence = TOML.parsefile(
    paths["design/evidence/process-bigraph-phase16h-evidence-v1.toml"])
requirements = Dict(row["id"] => row for row in ledger["requirements"])
envelopes = Dict(row["id"] => row for row in matrix["envelopes"])
slices = Dict(row["id"] => row for row in migration["slices"])
model_rows = Dict(row["id"] => row for row in models["models"])

check(entry["implementation_status"] ==
      "phase16h_qualified_c_hardware_open",
    "Phase 16.H checker requires qualified-H/C-hardware-open state")
for id in ["P16-H01", "P16-H02", "P16-H03"]
    check(requirements[id]["status"] == "qualified",
        "$(id) is not qualified")
    check("design/evidence/process-bigraph-phase16h-evidence-v1.toml" in
          requirements[id]["evidence"],
        "$(id) does not cite Phase 16.H evidence")
end
for id in [
    "P16-A01", "P16-A02", "P16-A03",
    "P16-B01", "P16-B02", "P16-B03", "P16-B04", "P16-B05", "P16-B06",
    "P16-C01",
    "P16-D01", "P16-D02", "P16-D03", "P16-D04",
    "P16-E01", "P16-E02", "P16-E03",
    "P16-F01", "P16-F02", "P16-F03",
    "P16-G01", "P16-G02",
]
    check(requirements[id]["status"] == "qualified",
        "$(id) lost prior qualification")
end
check(requirements["P16-C02"]["status"] == "oracle_passing" &&
      requirements["P16-C03"]["status"] == "implemented" &&
      requirements["P16-C04"]["status"] == "oracle_passing",
    "Phase 16.H must not overclaim open Phase 16.C hardware rows")
for id in ["P16-I01", "P16-I02", "P16-I03"]
    check(requirements[id]["status"] == "specified",
        "$(id) must remain open before reconciliation")
end

cnv_envelope = envelopes["cnv-source-faithful-assembly"]
check(matrix["phase16h_status"] == "qualified" &&
      cnv_envelope["CPU"] == "qualified" &&
      cnv_envelope["Metal"] == "unsupported" &&
      cnv_envelope["ROCm"] == "unsupported" &&
      cnv_envelope["CUDA"] == "not_applicable",
    "CNV backend envelope is not the qualified CPU-only claim")
check(migration["status"] == "phase16h_qualified" &&
      slices["cnv-assembly"]["status"] == "qualified",
    "CNV migration slice is not qualified")
cnv_model = model_rows["shirinifard-2012-cnv"]
check(cnv_model["status"] == "qualified" &&
      cnv_model["required_scenario"] == 38 &&
      cnv_model["required_source_simulation"] == 902 &&
      cnv_model["required_dimension"] == [40, 40, 35] &&
      cnv_model["excluded"] ==
      ["full_year_CI", "ten_replica_reproduction",
       "full_morphology_classifier", "quantitative_reproduction"],
    "CNV model scope is unqualified or widened")

check(trace["trace_id"] == "process-bigraph-phase16-cnv-trace-v1" &&
      trace["phase"] == "16.H" &&
      trace["scenario"] == 38 &&
      trace["source_simulation"] == 902 &&
      trace["claim"] == "runnable source-bounded reimplementation" &&
      trace["quantitative_reproduction"] == false &&
      trace["ordinary_ci_source_assets"] == false &&
      trace["primary_source"]["doi"] == "10.1371/journal.pcbi.1002440" &&
      trace["source_asset_lane"]["text_s6_sha256"] ==
      evidence["source_assets"]["text_s6_archive_sha256"] &&
      trace["canonical_configuration"]["dimensions"] == [40, 40, 35] &&
      trace["canonical_configuration"]["seed"] == 498377 &&
      occursin("ProcessBigraphs owns schedule", trace["compute_ownership"]),
    "CNV source trace identity, source, scope, or ownership changed")
check(Set(row["id"] for row in trace["mechanisms"]) ==
      Set(["startup", "chemotaxis", "potts_mechanics", "phenotype_timers",
           "growth_division_death", "plastic_relationships",
           "brm_degradation"]),
    "CNV source trace mechanism coverage changed")

assembly = read(
    paths["lib/CorePotts/src/coupled/shirinifard2012.jl"], String)
tests = read(
    paths["lib/CorePotts/test/test_phase16_shirinifard2012.jl"], String)
canonical = read(paths["lib/ProcessBigraphs/src/canonical.jl"], String)
canonical_tests = read(
    paths["lib/ProcessBigraphs/test/test_paths_time_canonical.jl"], String)
managed = read(
    paths["lib/ProcessBigraphs/src/managed_field_process.jl"], String)
for required in (
    "CNV2012AmbiguityProfile",
    "CNV2012CPMStep",
    "CNV2012BiologyStep",
    "CNV2012ExchangeStep",
    "cnv2012_initial_state",
    "cnv2012_initial_relationships",
    "cnv2012_chemotaxis_response",
    "cnv2012_composite",
    "cnv2012_native_composite",
    "cnv2012_observation_plan",
    "BudgetedSequentialCPM",
    "AttemptsPerSite",
)
    check(occursin(required, assembly),
        "CNV assembly omits $(required)")
end
for required in (
    "Phase 16.H CNV source trace and generated startup",
    "Phase 16.H CNV lifecycle and degradation microfixtures",
    "Phase 16.H CNV managed four-field assembly",
    "mcs=400",
    "division_result",
    "death_result",
    "logical_checkpoint",
    "FailureInjection",
)
    check(occursin(required, tests),
        "Phase 16.H tests omit $(required)")
end
for required in (
    "ManagedFieldAdvanceProcess",
    "execute_engine!",
    "mcs_publication_policy",
)
    check(occursin(required, managed),
        "managed field coupling omits $(required)")
end
check(occursin("where {T<:Unsigned}", canonical) &&
      occursin("AbstractArray{Float64}", canonical) &&
      occursin("canonical numeric array specialization parity",
          canonical_tests),
    "canonical numeric-array specialization or parity fixtures changed")

check(evidence["status"] == "qualified" &&
      evidence["phase"] == "16.H" &&
      evidence["implementation_commit"] ==
      "eb007dee16d6e4eba22c518eed06424a72d5cb29" &&
      evidence["implementation_tree"] ==
      "ac452d879cf122b75118d36582e6dbe288be14cb" &&
      Set(evidence["qualified_rows"]) ==
      Set(["P16-H01", "P16-H02", "P16-H03"]) &&
      evidence["quantitative_reproduction"] == false &&
      evidence["full_analysis"] == false &&
      evidence["canonical_startup"]["active_identities"] == 4978 &&
      evidence["canonical_startup"]["plastic_relationships"] == 1138 &&
      evidence["full_domain_one_mcs"]["final_occupied_voxels"] == 40700 &&
      evidence["tests"]["phase16h_total_assertions"] == 37 &&
      evidence["tests"]["process_bigraphs_total_assertions"] == 1155 &&
      evidence["tests"]["corepotts_total_assertions"] == 3863,
    "Phase 16.H evidence identity, scope, startup, or test totals changed")

for (path_key, hash_key) in (
    ("trace", "trace_sha256"),
    ("audit", "audit_sha256"),
    ("assembly", "assembly_sha256"),
    ("tests", "tests_sha256"),
    ("canonical_encoder", "canonical_encoder_sha256"),
    ("canonical_encoder_tests", "canonical_encoder_tests_sha256"),
    ("managed_field_process", "managed_field_process_sha256"),
)
    relative = evidence["artifacts"][path_key]
    actual = bytes2hex(SHA.sha256(read(joinpath(ROOT, relative))))
    check(actual == evidence["artifacts"][hash_key],
        "Phase 16.H artifact hash changed: $(relative)")
end

phase_state = "phase16h_qualified_c_hardware_open"
check(parity["phase16_entry"]["implementation_status"] == phase_state &&
      parity["phase16_entry"]["phase16h_trace"] ==
      "process-bigraph-phase16-cnv-trace-v1.toml" &&
      local_parity["accepted_next_architecture"]["phase16_status"] ==
      phase_state,
    "root or package parity registry does not record Phase 16.H")
workflow = read(paths[".github/workflows/ci.yml"], String)
check(occursin("process-bigraph-phase16h-check.jl", workflow),
    "CI does not enforce the Phase 16.H qualification checker")

if isempty(failures)
    println("ProcessBigraphs Phase 16.H CNV qualification check passed.")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("ProcessBigraphs Phase 16.H check failed with $(length(failures)) error(s)")
end

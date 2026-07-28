#!/usr/bin/env julia

using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const failures = String[]
check(condition, message) = condition || push!(failures, message)

function require_file(relative)
    path = joinpath(ROOT, relative)
    check(isfile(path), "missing Phase 16.G artifact: $(relative)")
    path
end

const REQUIRED = [
    "design/audits/process-bigraph-phase16g-merks-audit.md",
    "design/audits/phase-14-model-source-records-v1.toml",
    "design/evidence/process-bigraph-phase16g-evidence-v1.toml",
    "lib/CorePotts/src/components/merks_local_connectivity.jl",
    "lib/CorePotts/src/coupled/merks2006.jl",
    "lib/CorePotts/test/test_phase16_merks2006.jl",
    "lib/ProcessBigraphs/src/managed_field_process.jl",
    "spec/process-bigraph-phase16-entry-v1.toml",
    "spec/process-bigraph-phase16-qualification-v1.toml",
    "spec/process-bigraph-phase16-backend-matrix-v1.toml",
    "spec/process-bigraph-phase16-migration-registry-v1.toml",
    "spec/process-bigraph-phase16-model-scope-v1.toml",
    "spec/process-bigraph-phase16-merks-trace-v1.toml",
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
    paths["spec/process-bigraph-phase16-merks-trace-v1.toml"])
evidence = TOML.parsefile(
    paths["design/evidence/process-bigraph-phase16g-evidence-v1.toml"])
requirements = Dict(row["id"] => row for row in ledger["requirements"])
envelopes = Dict(row["id"] => row for row in matrix["envelopes"])
slices = Dict(row["id"] => row for row in migration["slices"])
model_rows = Dict(row["id"] => row for row in models["models"])

check(entry["implementation_status"] in (
      "phase16g_qualified_c_hardware_open",
      "phase16h_qualified_c_hardware_open"),
    "Phase 16.G checker requires qualified-G/C-hardware-open state")
for id in ["P16-G01", "P16-G02"]
    check(requirements[id]["status"] == "qualified",
        "$(id) is not qualified")
    check("design/evidence/process-bigraph-phase16g-evidence-v1.toml" in
          requirements[id]["evidence"],
        "$(id) does not cite Phase 16.G evidence")
end
for id in [
    "P16-A01", "P16-A02", "P16-A03",
    "P16-B01", "P16-B02", "P16-B03", "P16-B04", "P16-B05", "P16-B06",
    "P16-C01",
    "P16-D01", "P16-D02", "P16-D03", "P16-D04",
    "P16-E01", "P16-E02", "P16-E03",
    "P16-F01", "P16-F02", "P16-F03",
]
    check(requirements[id]["status"] == "qualified",
        "$(id) lost prior qualification")
end
check(requirements["P16-C02"]["status"] == "oracle_passing" &&
      requirements["P16-C03"]["status"] == "implemented" &&
      requirements["P16-C04"]["status"] == "oracle_passing",
    "Phase 16.G must not overclaim open Phase 16.C hardware rows")

merks_envelope = envelopes["merks-source-faithful-assembly"]
check(merks_envelope["CPU"] == "qualified" &&
      merks_envelope["Metal"] == "unsupported" &&
      merks_envelope["ROCm"] == "unsupported" &&
      merks_envelope["CUDA"] == "not_applicable",
    "Merks backend envelope is not the qualified CPU-only claim")
check(slices["merks-assembly"]["status"] == "qualified",
    "Merks migration slice is not qualified")
check(model_rows["merks-2006-vasculogenesis"]["status"] == "qualified" &&
      model_rows["merks-2006-vasculogenesis"]["excluded"] ==
      ["Figure_5_full_ensemble", "publication_morphometry_pipeline",
       "quantitative_reproduction"],
    "Merks model scope is unqualified or widened")

check(trace["trace_id"] == "process-bigraph-phase16-merks-trace-v1" &&
      trace["doi"] == "10.1016/j.ydbio.2005.10.003" &&
      trace["claim"] == "runnable source-bounded reimplementation" &&
      trace["quantitative_reproduction"] == false &&
      trace["reference_split"]["profile"] == "field_then_cpm_v1" &&
      trace["compute_ownership"]["scheduler"] ==
      "ProcessBigraphs SerialRuntime" &&
      trace["reference_ambiguity_profile"]["profile"] ==
      "bounded_reference_v1",
    "Merks source trace identity, scope, ownership, or profiles changed")
check(Set(row["id"] for row in trace["qualification_targets"]) ==
      Set(["P16-G01", "P16-G02"]),
    "Merks trace does not cover both Phase 16.G rows")

connectivity = read(
    paths["lib/CorePotts/src/components/merks_local_connectivity.jl"], String)
assembly = read(paths["lib/CorePotts/src/coupled/merks2006.jl"], String)
tests = read(paths["lib/CorePotts/test/test_phase16_merks2006.jl"], String)
managed = read(
    paths["lib/ProcessBigraphs/src/managed_field_process.jl"], String)
for required in (
    "collision_threshold=2",
    "exactly_two_cell_exception=true",
    "source_penalty=\"E0 > 2000\"",
)
    check(occursin(required, connectivity),
        "Merks connectivity implementation omits $(required)")
end
for required in (
    "Merks2006AmbiguityProfile",
    "Merks2006CPMStep",
    "Merks2006SecretionStep",
    "merks2006_initial_labels",
    "merks2006_composite",
    "merks2006_observation_plan",
    "source_chemotaxis_gamma",
    "corepotts_elongation_strength",
)
    check(occursin(required, assembly),
        "Merks assembly omits $(required)")
end
for required in (
    "ManagedFieldAdvanceProcess",
    "execute_engine!",
    "mcs_publication_policy",
)
    check(occursin(required, managed),
        "managed field coupling omits $(required)")
end
for required in (
    "source-mechanism microfixtures",
    "canonical startup and native assembly",
    "arbitrary SciML field assembly",
    "independent external field assembly",
    "logical_checkpoint",
    "disconnected_cells",
)
    check(occursin(required, tests),
        "Phase 16.G tests omit $(required)")
end

check(evidence["status"] == "qualified" &&
      evidence["phase"] == "16.G" &&
      evidence["implementation_commit"] ==
      "09150b5457ae622093aa6a3ad61a7fc2d70b87e7" &&
      evidence["implementation_tree"] ==
      "3e81f1affa1c517a32f6026a9d204730dd4aaa46" &&
      Set(evidence["qualified_rows"]) == Set(["P16-G01", "P16-G02"]) &&
      evidence["quantitative_reproduction"] == false &&
      evidence["full_analysis"] == false &&
      evidence["tests"]["phase16g_total_assertions"] == 40 &&
      evidence["tests"]["process_bigraphs_full_assertions"] == 1150 &&
      evidence["tests"]["corepotts_preexisting_regression_assertions"] ==
      3805 &&
      evidence["tests"]["corepotts_phase16f_final_cross_adapter_assertions"] ==
      14,
    "Phase 16.G evidence identity, scope, or test totals changed")

for (path_key, hash_key) in (
    ("trace", "trace_sha256"),
    ("source_record", "source_record_sha256"),
    ("connectivity", "connectivity_sha256"),
    ("assembly", "assembly_sha256"),
    ("tests", "tests_sha256"),
    ("managed_field_process", "managed_field_process_sha256"),
)
    relative = evidence["artifacts"][path_key]
    actual = bytes2hex(SHA.sha256(read(joinpath(ROOT, relative))))
    check(actual == evidence["artifacts"][hash_key],
        "Phase 16.G artifact hash changed: $(relative)")
end

workflow = read(paths[".github/workflows/ci.yml"], String)
check(occursin("process-bigraph-phase16g-check.jl", workflow),
    "CI does not enforce the Phase 16.G qualification checker")

if isempty(failures)
    println("ProcessBigraphs Phase 16.G Merks qualification check passed.")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("ProcessBigraphs Phase 16.G check failed with $(length(failures)) error(s)")
end

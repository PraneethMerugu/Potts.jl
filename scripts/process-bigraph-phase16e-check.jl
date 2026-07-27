#!/usr/bin/env julia

using TOML
using SHA

const ROOT = normpath(joinpath(@__DIR__, ".."))
const failures = String[]
check(condition, message) = condition || push!(failures, message)

function require_file(relative)
    path = joinpath(ROOT, relative)
    check(isfile(path), "missing Phase 16.E artifact: $(relative)")
    path
end

const REQUIRED = [
    "design/audits/process-bigraph-phase16e-corepotts-cutover-audit.md",
    "design/evidence/process-bigraph-phase16e-evidence-v1.toml",
    "lib/ProcessBigraphs/src/managed_engine.jl",
    "lib/ProcessBigraphs/src/checkpoint_v3.jl",
    "lib/ProcessBigraphs/src/logical_codec.jl",
    "lib/ProcessBigraphs/test/phase16/test_phase16e_checkpoint.jl",
    "lib/CorePotts/src/coupled/process_bigraph_adapter.jl",
    "lib/CorePotts/src/persistence/process_bigraph_conversion.jl",
    "lib/CorePotts/test/test_phase16_process_bigraph_adapter.jl",
    "lib/ProcessBigraphs/Project.toml",
    "lib/CorePotts/Project.toml",
    "spec/process-bigraph-phase16-entry-v1.toml",
    "spec/process-bigraph-phase16-api-v1.toml",
    "spec/process-bigraph-phase16-qualification-v1.toml",
    "spec/process-bigraph-phase16-migration-registry-v1.toml",
    ".github/workflows/ci.yml",
]
paths = Dict(path => require_file(path) for path in REQUIRED)

entry = TOML.parsefile(paths["spec/process-bigraph-phase16-entry-v1.toml"])
api = TOML.parsefile(paths["spec/process-bigraph-phase16-api-v1.toml"])
ledger = TOML.parsefile(
    paths["spec/process-bigraph-phase16-qualification-v1.toml"])
migration = TOML.parsefile(
    paths["spec/process-bigraph-phase16-migration-registry-v1.toml"])
evidence = TOML.parsefile(
    paths["design/evidence/process-bigraph-phase16e-evidence-v1.toml"])
process_project =
    TOML.parsefile(paths["lib/ProcessBigraphs/Project.toml"])
core_project = TOML.parsefile(paths["lib/CorePotts/Project.toml"])
requirements = Dict(row["id"] => row for row in ledger["requirements"])

check(entry["implementation_status"] ==
      "phase16e_qualified_c_hardware_open",
    "Phase 16.E checker requires qualified-E/C-hardware-open state")
for id in ["P16-E01", "P16-E02", "P16-E03"]
    check(requirements[id]["status"] == "qualified",
        "$(id) is not qualified")
    check("design/evidence/process-bigraph-phase16e-evidence-v1.toml" in
          requirements[id]["evidence"],
        "$(id) does not cite Phase 16.E evidence")
end
for id in [
    "P16-A01", "P16-A02", "P16-A03",
    "P16-B01", "P16-B02", "P16-B03",
    "P16-B04", "P16-B05", "P16-B06", "P16-C01",
    "P16-D01", "P16-D02", "P16-D03", "P16-D04",
]
    check(requirements[id]["status"] == "qualified",
        "$(id) lost prior qualification")
end
check(requirements["P16-C02"]["status"] == "oracle_passing" &&
      requirements["P16-C03"]["status"] == "implemented" &&
      requirements["P16-C04"]["status"] == "oracle_passing",
    "Phase 16.E must not overclaim the open Phase 16.C hardware rows")

families = Dict(row["id"] => row for row in api["families"])
check(api["status"] == entry["implementation_status"] &&
      api["current_new_exports"] == [] &&
      families["corepotts"]["status"] == "qualified" &&
      families["sciml"]["status"] == "specified" &&
      api["policy"]["unqualified_names_may_not_be_exported"] == true,
    "Phase 16.E API state or no-early-export rule changed")

check(Set(keys(process_project["deps"])) ==
      Set(["ACSets", "AlgebraicRewriting", "Catlab", "SHA"]) &&
      !haskey(process_project["deps"], "CorePotts"),
    "ProcessBigraphs acquired a CorePotts or non-neutral hard dependency")
check(get(core_project["deps"], "ProcessBigraphs", nothing) ==
      "efcc6515-205e-41e3-b553-f38f05ad529c" &&
      core_project["compat"]["ProcessBigraphs"] == "0.4" &&
      core_project["sources"]["ProcessBigraphs"]["path"] ==
          "../ProcessBigraphs",
    "CorePotts-to-ProcessBigraphs dependency direction is not exact")

slices = Dict(row["id"] => row for row in migration["slices"])
check(migration["status"] == "phase16e_qualified" &&
      migration["checkpoint"]["status"] == "qualified" &&
      migration["checkpoint"]["existing_attested_readers_retained"] == true &&
      migration["checkpoint"]["settled_boundaries_only"] == true &&
      slices["field-substrate"]["status"] == "qualified" &&
      slices["dynamic-lifecycle"]["status"] == "specified" &&
      migration["one_production_authority_per_slice"] == true &&
      migration["silent_fallback"] == false,
    "Phase 16.E migration registry overclaims or loses cutover invariants")

managed = read(paths["lib/ProcessBigraphs/src/managed_engine.jl"], String)
checkpoint = read(paths["lib/ProcessBigraphs/src/checkpoint_v3.jl"], String)
adapter =
    read(paths["lib/CorePotts/src/coupled/process_bigraph_adapter.jl"], String)
conversion = read(
    paths["lib/CorePotts/src/persistence/process_bigraph_conversion.jl"],
    String,
)
process_tests = read(
    paths["lib/ProcessBigraphs/test/phase16/test_phase16e_checkpoint.jl"],
    String,
)
core_tests = read(
    paths["lib/CorePotts/test/test_phase16_process_bigraph_adapter.jl"],
    String,
)
for required in (
    "ManagedEngineRuntime", "advance_managed_engine!",
    "DomainStructuralIdentity", "DomainStructuralRequest",
    "select_domain_structural_requests", "managed_engine_fail_stop",
)
    check(occursin(required, managed),
        "managed authority implementation omits $(required)")
end
for required in (
    "LogicalCheckpointV3", "phase16_checkpoint",
    "restore_phase16_checkpoint", "convert_legacy_checkpoint",
    "_restore_structural_topology", "destructive_legacy_conversion",
)
    check(occursin(required, checkpoint),
        "V3 checkpoint implementation omits $(required)")
end
for required in (
    "CorePottsNativeFieldAdapter", "process_bigraph_native_field_runtime",
    "CorePottsNativeCandidateToken", "stage_native_field!",
    "publish_native_field!", "engine_checkpoint_payload",
    "corepotts_cell_structural_request",
)
    check(occursin(required, adapter),
        "CorePotts adapter omits $(required)")
end
for required in (
    "CorePottsCanonicalCheckpointConverter",
    "CorePottsCoupledCheckpointConverter",
    "validate_checkpoint", "checkpoint_storage_payload",
)
    check(occursin(required, conversion),
        "legacy conversion omits $(required)")
end
check(!occursin("CorePotts",
        join(read.(filter(path -> endswith(path, ".jl"),
            readdir(joinpath(ROOT, "lib", "ProcessBigraphs", "src");
                join=true)), String), "\n")),
    "ProcessBigraphs source names or imports CorePotts")
check(!occursin("fallback", lowercase(adapter)),
    "CorePotts adapter contains a fallback path")

for required in (
    "managed authority and logical checkpoint v3",
    "typed domain structural requests", "corrupted",
    "authorize=(candidate, invocation) -> false",
)
    check(occursin(required, lowercase(process_tests)),
        "ProcessBigraphs Phase 16.E tests omit $(required)")
end
for required in (
    "native-field strangler cutover", "V3 restart differential",
    "non-destructive CorePotts legacy conversion",
    "for cut in 0:3", "managed_states == direct_states",
    "CorePottsCoupledCheckpointConverter",
)
    check(occursin(required, core_tests),
        "CorePotts Phase 16.E tests omit $(required)")
end

check(evidence["status"] == "qualified" &&
      evidence["phase"] == "16.E" &&
      Set(evidence["qualified_rows"]) ==
          Set(["P16-E01", "P16-E02", "P16-E03"]) &&
      evidence["authority"]["one_production_authority"] == true &&
      evidence["authority"]["silent_fallback"] == false &&
      evidence["structural_requests"]["per_cell_acset_rows"] == false &&
      evidence["checkpoint"]["prototype_free_structural_restore"] == true &&
      evidence["checkpoint"]["existing_readers_retained"] == true &&
      evidence["differential"]["restart_cuts"] == [0, 1, 2, 3] &&
      evidence["tests"]["process_bigraphs_full_assertions"] == 1061 &&
      evidence["tests"]["corepotts_full_assertions"] == 3772 &&
      evidence["tests"]["process_bigraphs_full_package_suite"] == "passed" &&
      evidence["tests"]["corepotts_full_package_suite"] == "passed",
    "Phase 16.E evidence identity, semantics, or totals changed")

for (path_key, hash_key) in (
    "managed_engine" => "managed_engine_sha256",
    "checkpoint_v3" => "checkpoint_v3_sha256",
    "logical_codec" => "logical_codec_sha256",
    "corepotts_adapter" => "corepotts_adapter_sha256",
    "legacy_conversion" => "legacy_conversion_sha256",
    "process_bigraphs_tests" => "process_bigraphs_tests_sha256",
    "corepotts_tests" => "corepotts_tests_sha256",
)
    artifact = joinpath(ROOT, evidence["artifacts"][path_key])
    check(bytes2hex(SHA.sha256(read(artifact))) ==
          evidence["artifacts"][hash_key],
        "Phase 16.E artifact $(path_key) differs from content-addressed evidence")
end

workflow = read(paths[".github/workflows/ci.yml"], String)
check(occursin("process-bigraph-phase16e-check.jl", workflow),
    "CI does not enforce the Phase 16.E checker")

if isempty(failures)
    println("ProcessBigraphs Phase 16.E qualification check passed.")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("ProcessBigraphs Phase 16.E check failed with $(length(failures)) error(s)")
end

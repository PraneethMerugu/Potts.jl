#!/usr/bin/env julia

using TOML
using SHA

const ROOT = normpath(joinpath(@__DIR__, ".."))
const failures = String[]
check(condition, message) = condition || push!(failures, message)

function require_file(relative)
    path = joinpath(ROOT, relative)
    check(isfile(path), "missing Phase 16.C artifact: $(relative)")
    path
end

const REQUIRED = [
    "design/audits/process-bigraph-phase16c-native-field-audit.md",
    "lib/CorePotts/src/coupled/native_fields.jl",
    "lib/CorePotts/test/test_phase16_native_fields.jl",
    "benchmark/phase16_native_field_qualification.jl",
    "spec/process-bigraph-phase16-entry-v1.toml",
    "spec/process-bigraph-phase16-backend-matrix-v1.toml",
    "spec/process-bigraph-phase16-qualification-v1.toml",
    ".github/workflows/gpu-validation.yml",
]
paths = Dict(path => require_file(path) for path in REQUIRED)

entry = TOML.parsefile(paths["spec/process-bigraph-phase16-entry-v1.toml"])
matrix = TOML.parsefile(
    paths["spec/process-bigraph-phase16-backend-matrix-v1.toml"])
ledger = TOML.parsefile(
    paths["spec/process-bigraph-phase16-qualification-v1.toml"])
requirements = Dict(row["id"] => row for row in ledger["requirements"])
candidate = entry["implementation_status"] in (
    "phase16c_candidate", "phase16d_qualified_c_hardware_open",
    "phase16e_qualified_c_hardware_open",
    "phase16f_qualified_c_hardware_open",
    "phase16g_qualified_c_hardware_open")
qualified = entry["implementation_status"] == "phase16c_qualified"
check(candidate || qualified,
    "Phase 16.C checker requires candidate or qualified state")

expected = qualified ? "qualified" : nothing
if candidate
    check(requirements["P16-C01"]["status"] == "qualified" &&
          requirements["P16-C02"]["status"] == "oracle_passing" &&
          requirements["P16-C03"]["status"] == "implemented" &&
          requirements["P16-C04"]["status"] == "oracle_passing",
        "Phase 16.C candidate ledger overclaims required hardware qualification")
else
    for id in ["P16-C01", "P16-C02", "P16-C03", "P16-C04"]
        check(requirements[id]["status"] == expected,
            "$(id) is not qualified")
    end
end
for id in [
    "P16-A01", "P16-A02", "P16-A03",
    "P16-B01", "P16-B02", "P16-B03",
    "P16-B04", "P16-B05", "P16-B06",
]
    check(requirements[id]["status"] == "qualified",
        "$(id) lost prior qualification")
end

envelopes = Dict(row["id"] => row for row in matrix["envelopes"])
native = envelopes["native-cartesian-field"]
expected_cpu = "qualified"
expected_device = qualified ? "qualified" : "implemented"
check(matrix["status"] ==
      (qualified ? "phase16c_qualified" : "phase16c_candidate") &&
      native["CPU"] == expected_cpu &&
      native["Metal"] == expected_device &&
      native["ROCm"] == expected_device &&
      native["CUDA"] == "not_applicable",
    "native backend matrix disagrees with Phase 16.C state")

source = read(paths["lib/CorePotts/src/coupled/native_fields.jl"], String)
tests = read(paths["lib/CorePotts/test/test_phase16_native_fields.jl"], String)
benchmark = read(paths["benchmark/phase16_native_field_qualification.jl"], String)
workflow = read(paths[".github/workflows/gpu-validation.yml"], String)
for required in (
    "@kernel", "KernelAbstractions", "NativeFieldGeometry",
    "stage_native_field!", "complete_native_field!", "publish_native_field!",
    "discard_native_field!", "adapt_native_field_engine",
    "MixedFieldBoundary", "publication_epoch", "Base.Checked.checked_mul",
)
    check(occursin(required, source),
        "native field implementation omits $(required)")
end
for required in (
    "manufactured refinement", "conservation", "restart",
    "p16c_stage_allocations", "p16c_publish_allocations",
    "Float32(NaN)", "MixedFieldBoundary", "(3, 4, 5)",
)
    check(occursin(required, tests),
        "native field CPU evidence omits $(required)")
end
for required in (
    "periodic-2d", "mixed-3d", "maximum_absolute_error",
    "staging_host_to_device_transfers", "warm_device_allocations",
    "publication_host_allocated_bytes", "native_field_source_sha256",
)
    check(occursin(required, benchmark),
        "native field hardware artifact omits $(required)")
end
for required in (
    "runs-on: [self-hosted, metal]",
    "runs-on: [self-hosted, rocm]",
    "phase16_native_field_qualification.jl",
    "--backend=metal",
    "--backend=amdgpu",
)
    check(occursin(required, workflow),
        "trusted hardware workflow omits $(required)")
end

if qualified
    evidence = TOML.parsefile(require_file(
        "design/evidence/process-bigraph-phase16c-evidence-v1.toml"))
    check(evidence["status"] == "qualified" &&
          evidence["phase"] == "16.C" &&
          evidence["hardware"]["metal_exact_head"] == true &&
          evidence["hardware"]["rocm_exact_head"] == true,
        "Phase 16.C final evidence lacks exact-head real hardware")
else
    evidence = TOML.parsefile(require_file(
        "design/evidence/process-bigraph-phase16c-candidate-evidence-v1.toml"))
    cpu_path = require_file(
        "design/evidence/phase-16/native-field/cpu-exact-head.toml")
    metal_path = require_file(
        "design/evidence/phase-16/native-field/metal-local-exact-head.toml")
    cpu = TOML.parsefile(cpu_path)
    metal = TOML.parsefile(metal_path)
    check(evidence["status"] == "candidate_hardware_open" &&
          evidence["cpu"]["status"] == "qualified" &&
          evidence["metal"]["trusted_self_hosted_artifact"] == false &&
          evidence["rocm"]["exact_head_artifact"] == false &&
          cpu["github_sha"] == evidence["provenance"]["implementation_commit"] &&
          metal["github_sha"] == evidence["provenance"]["implementation_commit"] &&
          bytes2hex(SHA.sha256(read(cpu_path))) ==
              evidence["cpu"]["artifact_sha256"] &&
          bytes2hex(SHA.sha256(read(metal_path))) ==
              evidence["metal"]["artifact_sha256"] &&
          all(row -> row["publication_host_allocated_bytes"] == 0 &&
                     row["staging_host_to_device_transfers"] == 0,
              vcat(cpu["cases"], metal["cases"])),
        "Phase 16.C candidate evidence overclaims hardware or guardrails")
end

if isempty(failures)
    println("ProcessBigraphs Phase 16.C $(candidate ? "implementation candidate" : "qualification") check passed.")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("ProcessBigraphs Phase 16.C check failed with $(length(failures)) error(s)")
end

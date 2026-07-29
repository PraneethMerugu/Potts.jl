#!/usr/bin/env julia

using TOML

const REPO = normpath(joinpath(@__DIR__, ".."))
const failures = String[]

check(condition, message) = condition || push!(failures, message)
read_repo(path) = read(joinpath(REPO, path), String)

decision = "spec/decisions/0035-wang-sequential-gpu-disposition.md"
registry = TOML.parsefile(joinpath(
    REPO, "spec", "phase-14-contract-registry-v2.toml"))
workflow = read_repo(".github/workflows/gpu-validation.yml")
preflight = read_repo("lib/CorePotts/src/coupled/preflight.jl")
integration = read_repo("integration/runtests.jl")

check(isfile(joinpath(REPO, decision)), "Decision 0035 is missing")
check(occursin("Wang G3-B sequential CPU passed", registry["status"]) &&
      occursin("Wang assembled GPU qualification retired", registry["status"]) &&
      occursin("G4 preserved and reassigned to Phase 16.C", registry["status"]),
    "registry does not record the Wang CPU disposition and Phase 16.C G4 gate")
check(!occursin("Wang G3-C", workflow) &&
      !occursin("phase14_wang_g3c", workflow),
    "GPU workflow still contains Wang G3-C qualification")
check(!occursin("_wang_g3c_gpu_qualified", preflight) &&
      !occursin("phase14-wang-g3c-gpu-native-qualification", preflight),
    "CorePotts still promotes an assembled Wang GPU profile")
check(occursin("test_phase14_wang_cpu_disposition.jl", integration),
    "integration suite omits the Wang CPU disposition test")

retired_paths = [
    "benchmark/phase14_wang_g3c_qualification.jl",
    "benchmark/profile_phase14_wang_g3c_amdgpu.jl",
    "benchmark/profile_phase14_wang_g3c_metal.jl",
    "benchmark/src/Phase14WangG3CQualification.jl",
    "scripts/attest_phase14_g3c.jl",
    "scripts/check_phase14_g3c_closure.jl",
    "scripts/check_phase14_g3c_entry.jl",
    "scripts/run_phase14_g3c_conformance.jl",
    "design/audits/phase-14-g3c-closure-ledger-v1.toml",
    "design/audits/phase-14-g3c-evidence-schema-v1.toml",
    "design/audits/phase-14-g3c-implementation-and-hardware-closure.md",
]
for path in retired_paths
    check(!ispath(joinpath(REPO, path)),
        "retired Wang GPU artifact still exists: $path")
end

if isempty(failures)
    println("Phase 14 Wang sequential CPU disposition: PASS")
    println("  G3-B remains the paper-faithful CPU reference")
    println("  assembled Wang GPU qualification is retired; G4 is preserved as Phase 16.C")
else
    for failure in failures
        println(stderr, "ERROR: ", failure)
    end
    exit(1)
end

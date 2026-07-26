#!/usr/bin/env julia

using TOML

const REPO = normpath(joinpath(@__DIR__, ".."))
const AUDITS = joinpath(REPO, "design", "audits")
const LEDGER_PATH = joinpath(
    AUDITS, "phase-14-g3c-closure-ledger-v1.toml")
const SCHEMA_PATH = joinpath(
    AUDITS, "phase-14-g3c-evidence-schema-v1.toml")
const G3B_LEDGER_PATH = joinpath(
    AUDITS, "phase-14-g3b-closure-ledger-v1.toml")

failures = String[]
check(condition, message) =
    condition || push!(failures, message)

for path in (LEDGER_PATH, SCHEMA_PATH, G3B_LEDGER_PATH)
    check(isfile(path), "missing $(relpath(path, REPO))")
end
isempty(failures) || begin
    foreach(message -> println(" - ", message), failures)
    exit(1)
end

ledger = TOML.parsefile(LEDGER_PATH)
schema = TOML.parsefile(SCHEMA_PATH)
g3b = TOML.parsefile(G3B_LEDGER_PATH)

check(ledger["schema_version"] == "1.0.0",
    "G3-C ledger schema must be 1.0.0")
check(ledger["gate"] == "G3-C",
    "G3-C ledger gate identity differs")
check(ledger["inherited_contract_revision"] == 7,
    "G3-C must inherit G3-B contract revision 7")
check(g3b["overall_status"] == "passed" &&
      g3b["contract_revision"] == 7,
    "G3-C cannot open without passed G3-B revision 7")
check(ledger["overall_status"] in (
        "hardware_pending", "passed"),
    "G3-C overall status is invalid")
check(Set(ledger["required_backends"]) ==
      Set(["metal", "amdgpu"]),
    "G3-C must require Metal and ROCm")
check(ledger["required_profile"] == "paper" &&
      ledger["required_side"] == 256 &&
      ledger["required_target_mcs"] == 500 &&
      ledger["portable_number_type"] == "Float32",
    "G3-C paper profile differs from the frozen contract")

requirements = Dict{String, Any}()
for row in ledger["requirement"]
    id = get(row, "id", "")
    isempty(id) &&
        check(false, "G3-C requirement has an empty id")
    haskey(requirements, id) &&
        check(false, "duplicate G3-C requirement '$id'")
    requirements[id] = row
    for evidence in get(row, "evidence", String[])
        path = normpath(joinpath(AUDITS, evidence))
        check(isfile(path),
            "G3-C requirement '$id' is missing evidence '$evidence'")
    end
end
required_requirements = Set([
    "g3b-semantic-abi-lock",
    "exact-backend-preflight",
    "backend-resident-canonical-execution",
    "device-code",
    "same-backend-replay-and-restart",
    "transfer-allocation-and-residency",
    "cross-backend-numerical-conformance",
    "memory-and-performance",
    "hardware-environment-provenance",
    "fail-closed-attestation",
])
check(Set(keys(requirements)) == required_requirements,
    "G3-C requirement registry is incomplete")

g3b_processes = Set(row["id"] for row in g3b["process_evidence"])
g3c_processes = Dict{String, Any}()
for row in ledger["process"]
    id = row["id"]
    haskey(g3c_processes, id) &&
        check(false, "duplicate G3-C process '$id'")
    g3c_processes[id] = row
    for backend in ("metal", "amdgpu")
        check(row[backend] in ("hardware_pending", "passed"),
            "G3-C process '$id' has invalid $backend status")
    end
end
check(Set(keys(g3c_processes)) == g3b_processes,
    "G3-C process identities differ from the frozen G3-B plan")

check(schema["schema_version"] == "1.0.0" &&
      schema["suite"] == ledger["qualification_suite"],
    "G3-C evidence schema and ledger suite differ")
check(Set(schema["required_backends"]) ==
      Set(ledger["required_backends"]),
    "G3-C evidence schema backend set differs")
check(schema["qualification"]["required_side"] ==
      ledger["required_side"] &&
      schema["qualification"]["required_target_mcs"] ==
      ledger["required_target_mcs"] &&
      schema["qualification"]["required_g3b_contract_revision"] ==
      ledger["inherited_contract_revision"],
    "G3-C evidence schema does not bind the ledger profile")

boundaries = ledger["claim_boundaries"]
if ledger["overall_status"] == "hardware_pending"
    for key in ("metal_qualified", "rocm_qualified",
            "g3c_complete", "g4_open")
        check(boundaries[key] === false,
            "pending G3-C ledger overclaims '$key'")
    end
end

source_checks = Dict(
    "lib/CorePotts/src/coupled/preflight.jl" => [
        "_wang_g3c_gpu_qualified",
        "_coupled_tree_backend_valid",
        "phase14-wang-g3c-gpu-native-qualification-v1",
    ],
    "integration/conformance/phase14_wang_fixture.jl" => [
        "adaptor = Array",
        "ExecutionPlan",
        "scientific_storage_valid",
    ],
    "benchmark/src/Phase14WangG3CQualification.jl" => [
        "qualify_phase14_wang_g3c_backend",
        "_phase14_wang_replay_restart",
        "_phase14_wang_cpu_comparison",
        "status_scalar_transfers",
    ],
    "benchmark/profile_phase14_wang_g3c_metal.jl" =>
        ["Metal.@device_code_air"],
    "benchmark/profile_phase14_wang_g3c_amdgpu.jl" =>
        ["AMDGPU.@device_code"],
)
for (relative, tokens) in source_checks
    path = joinpath(REPO, relative)
    check(isfile(path), "missing G3-C implementation file $relative")
    isfile(path) || continue
    text = read(path, String)
    for token in tokens
        check(occursin(token, text),
            "$relative is missing required token '$token'")
    end
end

if !isempty(failures)
    println("Phase 14 G3-C entry: OPEN")
    foreach(message -> println(" - ", message), failures)
    exit(1)
end

println("Phase 14 G3-C entry: PASS")
println("  G3-B revision-7 semantic ABI inherited unchanged")
println("  exact Metal/ROCm preflight and canonical backend fixture present")
println("  dual-backend paper qualification remains fail-closed hardware evidence")

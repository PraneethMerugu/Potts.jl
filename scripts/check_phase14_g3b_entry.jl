#!/usr/bin/env julia

using TOML

const REPO = normpath(joinpath(@__DIR__, ".."))
const CONTRACT_PATH = joinpath(
    REPO, "design", "audits", "phase-14-g3b-entry-contract-v1.toml")
const ORDER_PATH = joinpath(
    REPO, "design", "audits", "phase-14-wang-order-oracle-v1.toml")
const failures = String[]

check(condition, message) = condition || push!(failures, message)

isfile(CONTRACT_PATH) || error("missing G3-B entry contract")
isfile(ORDER_PATH) || error("missing Wang order authority")

contract = TOML.parsefile(CONTRACT_PATH)
order = TOML.parsefile(ORDER_PATH)

check(contract["status"] == "accepted-implementation-entry",
    "G3-B entry contract is not accepted")
check(contract["entry_decision"]["implementation_may_start"] === true,
    "G3-B entry contract does not permit implementation")
check(contract["entry_decision"]["architecture_interview_required"] === false,
    "G3-B entry contract unexpectedly requires another architecture interview")

function unique_ids(rows, label)
    ids = [row["id"] for row in rows]
    check(length(ids) == length(unique(ids)), "$label contains duplicate ids")
    return Set(ids)
end

state_ids = unique_ids(contract["state"], "state registry")
workspace_ids = unique_ids(contract["workspace"], "workspace registry")
process_ids = unique_ids(contract["process"], "process registry")
conformance_ids = unique_ids(contract["conformance"], "conformance registry")
oracle_ids = unique_ids(contract["runtime_oracles"], "runtime-oracle registry")

expected_states = Set([
    "secretome",
    "centroid_history",
    "self_polarity",
    "signal",
    "uptake_multiplier",
    "intracellular_state",
    "focal_strength",
    "focal_relationships",
    "motility_force",
])
expected_workspaces = Set([
    "field_ping_pong",
    "cell_reduction",
    "polarity_snapshot",
    "relationship_transactions",
    "observation_reducers",
])
expected_processes = Set(contract["plan"]["ordered_processes"])
expected_conformance = Set([
    "history-ring",
    "intracellular-affine-ode",
    "periodic-field",
    "uptake-calibration",
    "relationship-graph",
    "polarity-and-force",
    "wang-plan-boundaries",
    "device-readiness",
])
expected_oracles = Set([
    "wang-potts-boundary-and-attempt-accounting",
    "wang-roadrunner-numerical-profile",
])

check(state_ids == expected_states, "G3-B state registry is incomplete")
check(workspace_ids == expected_workspaces, "G3-B workspace registry is incomplete")
check(process_ids == expected_processes,
    "root plan and process registry contain different process identities")
check(conformance_ids == expected_conformance,
    "G3-B conformance registry is incomplete")
check(oracle_ids == expected_oracles,
    "G3-B runtime-oracle registry is incomplete")

process_by_id = Dict(row["id"] => row for row in contract["process"])
phases = [process_by_id[id]["phase"] for id in contract["plan"]["ordered_processes"]]
check(phases == collect(1:length(phases)),
    "G3-B root-plan process phases are not canonical and contiguous")

required_backends = Set(["CPU", "Metal", "ROCm"])
for row in contract["state"]
    check(Set(row["adaptation"]) == required_backends,
        "state '$(row["id"])' does not require CPU, Metal, and ROCm adaptation")
    check(!isempty(row["persistence"]),
        "state '$(row["id"])' has no persistence payload")
end
for row in contract["workspace"]
    check(Set(row["adaptation"]) == required_backends,
        "workspace '$(row["id"])' does not require CPU, Metal, and ROCm adaptation")
    check(row["steady_state_allocation"] === false,
        "workspace '$(row["id"])' permits steady-state allocation")
end
for row in contract["process"]
    check(Set(row["backend_requirements"]) == required_backends,
        "process '$(row["id"])' does not require CPU, Metal, and ROCm")
    check(!isempty(row["reads"]) || !isempty(row["writes"]),
        "process '$(row["id"])' declares neither reads nor writes")
end

check(contract["boundary_expectations"]["mcs_120"]["first_potts_using_retune"] ==
      order["boundary_mcs_120"]["first_potts_mcs_using_focal_strength_20"],
    "MCS 120 boundary disagrees with accepted Wang order")
check(contract["boundary_expectations"]["mcs_210"]["first_potts_using_scanned_strength"] ==
      order["boundary_mcs_210"]["first_potts_mcs_using_scanned_focal_strength"],
    "MCS 210 boundary disagrees with accepted Wang order")
check(contract["boundary_expectations"]["mcs_211"]["ode_reads_same_mcs_signal"] ==
      order["boundary_mcs_211"]["ode_reads_same_mcs_signal_s"],
    "MCS 211 boundary disagrees with accepted Wang order")
check(contract["capacities"]["history_capacity"] == 5,
    "source-faithful centroid history capacity must remain five")
check(contract["capacities"]["relationship_maximum_degree"] == 4,
    "source-faithful focal maximum degree must remain four")

for row in contract["runtime_oracles"]
    check(row["status"] == "required-before-g3b-closure",
        "runtime oracle '$(row["id"])' has an unexpected status")
    check("G3-B completion claim" in row["blocks"],
        "runtime oracle '$(row["id"])' does not block an unsupported completion claim")
end

isempty(failures) || error(join(failures, '\n'))

println("Phase 14.1 G3-B implementation entry contract: PASS")

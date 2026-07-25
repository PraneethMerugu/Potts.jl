#!/usr/bin/env julia

using TOML

const REPO = normpath(joinpath(@__DIR__, ".."))
const CONTRACT_PATH = joinpath(
    REPO, "design", "audits", "phase-14-g3b-entry-contract-v1.toml")
const ORDER_PATH = joinpath(
    REPO, "design", "audits", "phase-14-wang-order-oracle-v1.toml")
const ENTRY_PACKET_PATH = joinpath(
    REPO, "design", "audits", "phase-14-g3b-entry-packet.md")
const CLOSURE_AUDIT_PATH = joinpath(
    REPO, "design", "audits", "phase-14-g3b-closure-spec-audit.md")
const FIELD_EVIDENCE_PATH = joinpath(
    REPO, "design", "audits", "phase-14-g3b-field-evidence.md")
const EXCHANGE_EVIDENCE_PATH = joinpath(
    REPO, "design", "audits", "phase-14-g3b-exchange-evidence.md")
const INTRACELLULAR_EVIDENCE_PATH = joinpath(
    REPO, "design", "audits", "phase-14-g3b-intracellular-evidence.md")
const CLOSURE_LEDGER_PATH = joinpath(
    REPO, "design", "audits", "phase-14-g3b-closure-ledger-v1.toml")
const CONTINUOUS_SOURCE_PATH = joinpath(
    REPO, "lib", "CorePotts", "src", "coupled", "continuous.jl")
const failures = String[]

check(condition, message) = condition || push!(failures, message)

isfile(CONTRACT_PATH) || error("missing G3-B entry contract")
isfile(ORDER_PATH) || error("missing Wang order authority")
isfile(ENTRY_PACKET_PATH) || error("missing G3-B entry packet")
isfile(CLOSURE_AUDIT_PATH) || error("missing G3-B closure specification audit")
isfile(FIELD_EVIDENCE_PATH) || error("missing G3-B atomic-field evidence")
isfile(EXCHANGE_EVIDENCE_PATH) || error("missing G3-B exchange evidence")
isfile(INTRACELLULAR_EVIDENCE_PATH) ||
    error("missing G3-B intracellular evidence")
isfile(CLOSURE_LEDGER_PATH) || error("missing G3-B closure ledger")

contract = TOML.parsefile(CONTRACT_PATH)
order = TOML.parsefile(ORDER_PATH)
entry_packet = read(ENTRY_PACKET_PATH, String)
closure_audit = read(CLOSURE_AUDIT_PATH, String)
field_evidence = read(FIELD_EVIDENCE_PATH, String)
exchange_evidence = read(EXCHANGE_EVIDENCE_PATH, String)
intracellular_evidence = read(INTRACELLULAR_EVIDENCE_PATH, String)
closure_ledger = TOML.parsefile(CLOSURE_LEDGER_PATH)
continuous_source = read(CONTINUOUS_SOURCE_PATH, String)

check(contract["status"] == "accepted-implementation-entry",
    "G3-B entry contract is not accepted")
check(contract["schema_version"] == "1.2.0" && contract["revision"] == 3,
    "G3-B entry checker requires revision-3 schema 1.2.0")
check(contract["entry_decision"]["implementation_may_start"] === true,
    "G3-B entry contract does not permit implementation")
check(contract["entry_decision"]["architecture_interview_required"] === false,
    "G3-B entry contract unexpectedly requires another architecture interview")
check(occursin("source mcs `k` maps to normalized target mcs `k+1`",
        lowercase(closure_audit)),
    "G3-B closure audit does not state the accepted source-time mapping")
check(occursin("typed cross-domain write set", closure_audit) &&
      occursin("completed-mcs", lowercase(closure_audit)),
    "G3-B closure audit omits publication or persistence closure")
check(occursin("portable kernelabstractions reference accepted",
          lowercase(field_evidence)) &&
      occursin("allocates exactly zero bytes", field_evidence),
    "atomic-field evidence overclaims backend closure or omits allocation evidence")
check(occursin("atomic field evidence", entry_packet) &&
      occursin("not a GPU qualification claim", entry_packet),
    "G3-B entry packet does not bound the field evidence claim")
check(occursin("portable fixed-tree kernelabstractions reference accepted",
          lowercase(exchange_evidence)) &&
      occursin("zero-byte warm sequential CPU", exchange_evidence) &&
      occursin("exchange transaction evidence", entry_packet),
    "G3-B exchange evidence is missing or overclaims portable closure")
check(occursin("50/50 intracellular assertions", intracellular_evidence) &&
      occursin("RoadRunner", intracellular_evidence) &&
      occursin("real GPU qualification remain open", intracellular_evidence),
    "G3-B intracellular evidence is missing or overclaims closure")
for required_source in (
        "WANG_PORTABLE_REDUCTION_WIDTH = 256",
        "_exchange_device_reduce_cells!",
        "_exchange_device_calibrate_maximum!",
        "_exchange_device_commit_field!",
        "_exchange_device_commit_signal!",
        "_periodic_field_device_substep!",
        "_field_device_commit!",
        "synchronize_field_exchange_status!",
        "synchronize_field_advance_status!",
        "AffineCellAdvance",
        "UniformCellInitialization",
        "synchronize_affine_cell_status!")
    check(occursin(required_source, continuous_source),
        "portable field/exchange source is missing '$required_source'")
end

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
    "field_staging",
    "cell_reduction",
    "phase_status",
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
    "wang-field-numerical-profile",
])
expected_closure_requirements = Set([
    "source-provenance-lock",
    "canonical-wang-assembly",
    "sequential-cpu-conformance",
    "order-and-boundaries",
    "transaction-and-failure-atomicity",
    "completed-mcs-restart",
    "steady-state-resource-contract",
    "portable-abi-readiness",
    "foreign-runtime-oracles",
    "observation-schema",
    "regression-and-api-freeze",
    "evidence-reproducibility",
])

check(state_ids == expected_states, "G3-B state registry is incomplete")
check(workspace_ids == expected_workspaces, "G3-B workspace registry is incomplete")
check(process_ids == expected_processes,
    "root plan and process registry contain different process identities")
check(conformance_ids == expected_conformance,
    "G3-B conformance registry is incomplete")
check(oracle_ids == expected_oracles,
    "G3-B runtime-oracle registry is incomplete")
closure_requirement_ids =
    unique_ids(contract["closure_requirement"], "closure requirement registry")
check(closure_requirement_ids == expected_closure_requirements,
    "G3-B closure requirement registry is incomplete")

ledger_ids = unique_ids(closure_ledger["requirement"], "closure ledger")
check(ledger_ids == expected_closure_requirements,
    "G3-B closure ledger does not match the closure requirement registry")
check(closure_ledger["contract_revision"] == contract["revision"],
    "G3-B closure ledger targets a stale contract revision")
allowed_closure_statuses = Set(["pending", "partial", "passed"])
for row in closure_ledger["requirement"]
    check(row["status"] in allowed_closure_statuses,
        "closure row '$(row["id"])' has an invalid status")
    check(!isempty(row["evidence"]),
        "closure row '$(row["id"])' has no evidence pointer")
end
all_passed = all(
    row -> row["status"] == "passed", closure_ledger["requirement"])
check((closure_ledger["overall_status"] == "passed") == all_passed,
    "closure overall status must be passed exactly when every row is passed")
check(contract["closure_protocol"]["status"] in ("open", "passed") &&
      contract["closure_protocol"]["status"] ==
          closure_ledger["overall_status"],
    "G3-B contract and ledger closure statuses disagree")
check(occursin("every closure_requirement",
          contract["closure_protocol"]["completion_rule"]) &&
      occursin("clean commit", contract["closure_protocol"]["evidence_rule"]),
    "G3-B closure protocol is not fail-closed and commit-addressed")

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

check(contract["boundary_expectations"]["source_mcs_120"]["first_source_potts_using_retune"] ==
      order["boundary_mcs_120"]["first_potts_mcs_using_focal_strength_20"],
    "source MCS 120 boundary disagrees with accepted Wang order")
check(contract["boundary_expectations"]["source_mcs_210"]["first_source_potts_using_scanned_strength"] ==
      order["boundary_mcs_210"]["first_potts_mcs_using_scanned_focal_strength"],
    "source MCS 210 boundary disagrees with accepted Wang order")
check(contract["boundary_expectations"]["source_mcs_211"]["ode_reads_same_mcs_signal"] ==
      order["boundary_mcs_211"]["ode_reads_same_mcs_signal_s"],
    "source MCS 211 boundary disagrees with accepted Wang order")
check(contract["capacities"]["history_capacity"] == 5,
    "source-faithful centroid history capacity must remain five")
check(contract["capacities"]["relationship_maximum_degree"] == 4,
    "source-faithful focal maximum degree must remain four")

mapping = contract["source_time_mapping"]
check(mapping["source_first"] == 0 && mapping["source_last"] == 499 &&
      mapping["target_first"] == 1 && mapping["target_last"] == 500,
    "G3-B source-to-target MCS range must remain 0:499 -> 1:500")
check(mapping["source_label_is_clock"] === false,
    "source MCS label must not become a second clock")
check(order["normalized_time_mapping"]["rule"] ==
      "Potts.jl normalized target MCS = CompuCell3D source MCS + 1",
    "Wang order authority lacks the accepted normalized MCS mapping")
check(occursin("No source step()", mapping["initialization_rule"]),
    "G3-B initialization may hide source step() work")

state_by_id = Dict(row["id"] => row for row in contract["state"])
field = state_by_id["secretome"]
check(occursin("logical 256x256", field["schema"]) &&
      occursin("authoritative", field["physical_layout"]),
    "Wang field logical shape or authoritative storage is not frozen")
check(!any(item -> occursin("buffer index", item) ||
                  occursin("substep boundary", item), field["persistence"]),
    "field persistence must not contain physical buffer or internal-substep state")
check(state_by_id["uptake_multiplier"]["owner"] == "global",
    "the identical Wang uptake multiplier must normalize to global state")

field_workspace = only(row for row in contract["workspace"]
    if row["id"] == "field_staging")
check(occursin("two same-shape", field_workspace["layout"]),
    "strict field failure atomicity requires two staging grids")

field_process = process_by_id["secretome_field_advance"]
check(occursin("one atomic synchronous process commit", field_process["commit"]) &&
      occursin("no internal substep is externally visible or checkpointable",
          field_process["commit"]),
    "field substeps have regressed into process commits or checkpoint boundaries")
check(occursin("unchanged", field_process["failure_policy"]),
    "field process lacks explicit failure atomicity")

exchange = process_by_id["secretome_signal_exchange"]
check(occursin("plan-resolved mode", exchange["trigger"]),
    "exchange mode is not resolved by the root plan")
check(Set(exchange["writes"]) ==
      Set(["secretome", "signal", "uptake_multiplier"]),
    "exchange declared writes do not span field, cell, and global state")
check(occursin("cross-domain logical transaction", exchange["commit"]),
    "exchange lacks one cross-domain publication transaction")
check(occursin("Floating atomics", exchange["reduction_policy"]),
    "exchange reduction policy does not reject scheduler-dependent floating atomics")
check(occursin("zero/nonfinite", exchange["numerical_policy"]),
    "exchange lacks zero/nonfinite calibration failure semantics")
check(occursin("commits nothing", exchange["failure_policy"]) &&
      occursin("uninitialized multiplier", exchange["failure_policy"]),
    "exchange failure policy is incomplete")

stable = contract["plan"]["stable_boundary"]
check(contract["plan"]["forbid_process_local_mcs_branching"] === true,
    "root plan permits a hidden process-local MCS scheduler")
check(stable["kind"] == "completed MCS after required observation" &&
      stable["internal_field_substeps"] === false &&
      stable["post_field_phase"] === false &&
      stable["post_exchange_phase"] === false &&
      stable["partial_mcs_restart"] === false,
    "G3-B stable boundaries disagree with the semantic-kernel persistence contract")

mode_table = contract["plan"]["exchange_modes"]
check(mode_table == Dict(
        "target_1_121" => "inactive",
        "target_122_210" => "reset",
        "target_211" => "calibrate",
        "target_212_500" => "publish"),
    "G3-B exchange mode table is incomplete or shifted")

for key in ("field_local_atol", "field_local_rtol",
        "uptake_local_atol", "uptake_local_rtol")
    check(contract["numerical_tolerances"][key] > 0,
        "G3-B numerical tolerance '$key' must be preregistered and positive")
end

source_120 = contract["boundary_expectations"]["source_mcs_120"]
source_210 = contract["boundary_expectations"]["source_mcs_210"]
source_211 = contract["boundary_expectations"]["source_mcs_211"]
check(source_120["target_mcs"] == 121 &&
      source_210["target_mcs"] == 211 &&
      source_211["target_mcs"] == 212,
    "source 120/210/211 boundaries do not map to target 121/211/212")

for row in contract["runtime_oracles"]
    check(row["status"] == "required-before-g3b-closure",
        "runtime oracle '$(row["id"])' has an unexpected status")
    check("G3-B completion claim" in row["blocks"],
        "runtime oracle '$(row["id"])' does not block an unsupported completion claim")
end

isempty(failures) || error(join(failures, '\n'))

println("Phase 14.1 G3-B implementation entry contract: PASS")

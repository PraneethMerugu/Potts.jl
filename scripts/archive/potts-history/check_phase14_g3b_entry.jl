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
const RELATIONSHIP_EVIDENCE_PATH = joinpath(
    REPO, "design", "audits", "phase-14-g3b-relationship-evidence.md")
const POLARITY_FORCE_EVIDENCE_PATH = joinpath(
    REPO, "design", "audits", "phase-14-g3b-polarity-force-evidence.md")
const OBSERVATION_SOURCE_AUDIT_PATH = joinpath(
    REPO, "design", "audits", "phase-14-g3b-observation-source-audit.md")
const OBSERVATION_EVIDENCE_PATH = joinpath(
    REPO, "design", "audits", "phase-14-g3b-observation-evidence.md")
const POTTS_FPP_STUDY_PATH = joinpath(
    REPO, "design", "audits", "phase-14-g3b-potts-fpp-source-study.md")
const ROADRUNNER_STUDY_PATH = joinpath(
    REPO, "design", "audits", "phase-14-g3b-roadrunner-source-study.md")
const FIELD_STUDY_PATH = joinpath(
    REPO, "design", "audits", "phase-14-g3b-field-source-study.md")
const CLOSURE_LEDGER_PATH = joinpath(
    REPO, "design", "audits", "phase-14-g3b-closure-ledger-v1.toml")
const RUNTIME_SOURCE_ROOT =
    joinpath(REPO, "lib", "CorePotts", "src")
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
isfile(RELATIONSHIP_EVIDENCE_PATH) ||
    error("missing G3-B relationship evidence")
isfile(POLARITY_FORCE_EVIDENCE_PATH) ||
    error("missing G3-B polarity/force evidence")
isfile(OBSERVATION_SOURCE_AUDIT_PATH) ||
    error("missing G3-B observation source audit")
isfile(OBSERVATION_EVIDENCE_PATH) ||
    error("missing G3-B observation evidence")
isfile(POTTS_FPP_STUDY_PATH) ||
    error("missing G3-B Potts/FPP source study")
isfile(ROADRUNNER_STUDY_PATH) ||
    error("missing G3-B RoadRunner source study")
isfile(FIELD_STUDY_PATH) ||
    error("missing G3-B field source study")
isfile(CLOSURE_LEDGER_PATH) || error("missing G3-B closure ledger")

contract = TOML.parsefile(CONTRACT_PATH)
order = TOML.parsefile(ORDER_PATH)
entry_packet = read(ENTRY_PACKET_PATH, String)
closure_audit = read(CLOSURE_AUDIT_PATH, String)
field_evidence = read(FIELD_EVIDENCE_PATH, String)
exchange_evidence = read(EXCHANGE_EVIDENCE_PATH, String)
intracellular_evidence = read(INTRACELLULAR_EVIDENCE_PATH, String)
relationship_evidence = read(RELATIONSHIP_EVIDENCE_PATH, String)
polarity_force_evidence =
    read(POLARITY_FORCE_EVIDENCE_PATH, String)
observation_source_audit =
    read(OBSERVATION_SOURCE_AUDIT_PATH, String)
observation_evidence =
    read(OBSERVATION_EVIDENCE_PATH, String)
potts_fpp_study = read(POTTS_FPP_STUDY_PATH, String)
roadrunner_study = read(ROADRUNNER_STUDY_PATH, String)
field_study = read(FIELD_STUDY_PATH, String)
closure_ledger = TOML.parsefile(CLOSURE_LEDGER_PATH)
runtime_sources = String[]
for (root, _, files) in walkdir(RUNTIME_SOURCE_ROOT)
    for file in sort!(filter(name -> endswith(name, ".jl"), files))
        push!(runtime_sources, read(joinpath(root, file), String))
    end
end
implementation_source = join(runtime_sources, '\n')

check(contract["status"] == "accepted-implementation-entry",
    "G3-B entry contract is not accepted")
check(contract["schema_version"] == "1.6.0" && contract["revision"] == 7,
    "G3-B entry checker requires revision-7 schema 1.6.0")
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
check(occursin("portable kernelabstractions reference",
          lowercase(field_evidence)) &&
      occursin("accepted", lowercase(field_evidence)) &&
      occursin("allocates exactly zero bytes", field_evidence),
    "atomic-field evidence overclaims backend closure or omits allocation evidence")
check(occursin("atomic field evidence", entry_packet) &&
      occursin("not a GPU qualification claim", entry_packet),
    "G3-B entry packet does not bound the field evidence claim")
check(occursin("revision 7", lowercase(entry_packet)) &&
      occursin("bit-packed", lowercase(entry_packet)) &&
      occursin("packed atomic key", lowercase(entry_packet)) &&
      occursin("dimension-generic", lowercase(entry_packet)) &&
      occursin("cell-slot capacity", lowercase(entry_packet)) &&
      occursin("process-by-process proof", lowercase(entry_packet)) &&
      occursin("sha-256", lowercase(entry_packet)),
    "G3-B entry packet does not describe revision-7 normalization and closure hardening")
check(occursin("portable fixed-tree kernelabstractions reference accepted",
          lowercase(exchange_evidence)) &&
      occursin("zero-byte warm sequential CPU", exchange_evidence) &&
      occursin("exchange transaction evidence", entry_packet),
    "G3-B exchange evidence is missing or overclaims portable closure")
check(occursin("50/50 intracellular assertions", intracellular_evidence) &&
      occursin("RoadRunner", intracellular_evidence) &&
      occursin("real GPU qualification remains G3-C", intracellular_evidence),
    "G3-B intracellular evidence is missing or overclaims closure")
check(occursin("no live CC3D oracle", potts_fpp_study) &&
      occursin("implicit no-flux", lowercase(potts_fpp_study)) &&
      occursin("no live RoadRunner oracle", roadrunner_study) &&
      occursin("1_094_400", roadrunner_study) &&
      occursin("no live CC3D oracle", field_study) &&
      occursin("five", lowercase(field_study)) &&
      occursin("substep", lowercase(field_study)),
    "G3-B pinned source studies or no-external-oracle policy are incomplete")
check(occursin("51/51 assertions", relationship_evidence) &&
      occursin("23/23 assertions", relationship_evidence) &&
      occursin("45/45 assertions", relationship_evidence) &&
      occursin("assembled-model", relationship_evidence) &&
      occursin("Real Metal", relationship_evidence),
    "G3-B relationship evidence is missing or overclaims closure")
check(occursin("67/67 assertions", polarity_force_evidence) &&
      occursin("bit-packed", lowercase(polarity_force_evidence)) &&
      occursin("heterogeneous failures",
          lowercase(polarity_force_evidence)) &&
      occursin("assembled Wang order", polarity_force_evidence) &&
      occursin("real GPU qualification remain open",
          polarity_force_evidence),
    "G3-B polarity/force evidence is missing or overclaims closure")
check(occursin("107/107 assertions", observation_evidence) &&
      occursin("three-dimensional", lowercase(observation_evidence)) &&
      occursin("assembled Wang order", observation_evidence) &&
      occursin("real GPU qualification remain open",
          observation_evidence) &&
      occursin("2633fd41c85b5256b2d2975b9bc60b28271bb1f7dd1c9b72e015788ac847cc30",
          observation_source_audit) &&
      occursin("target `122:500`", observation_source_audit),
    "G3-B observation evidence or source traceability is incomplete")
check(!occursin(r"(?i)\bwang(?:\b|_)", implementation_source),
    "CorePotts runtime source contains a Wang-specific implementation identity")

function unique_ids(rows, label)
    ids = [row["id"] for row in rows]
    check(length(ids) == length(unique(ids)), "$label contains duplicate ids")
    return Set(ids)
end

state_ids = unique_ids(contract["state"], "state registry")
workspace_ids = unique_ids(contract["workspace"], "workspace registry")
process_ids = unique_ids(contract["process"], "process registry")
conformance_ids = unique_ids(contract["conformance"], "conformance registry")
study_ids = unique_ids(
    contract["semantic_studies"], "source-semantic study registry")
command_ids = unique_ids(contract["closure_command"], "closure-command registry")

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
    "bounded-observations",
    "wang-plan-boundaries",
    "device-readiness",
])
expected_studies = Set([
    "wang-cc3d-potts-fpp-source-study",
    "wang-roadrunner-coupling-study",
    "wang-cc3d-field-source-study",
])
expected_commands = Set([
    "g3b-entry-contract",
    "wang-order-oracle",
    "g3a-generic-authoring",
    "g3b-assembled-conformance",
    "g3b-portable-abi",
    "g3b-failure-matrix",
    "g3b-restart-matrix",
    "g3b-resource-matrix",
    "g3b-observation-matrix",
    "corepotts-full",
    "pottstoolkit-full",
    "phase13-api-inventory",
    "repository-structure",
    "legacy-containment",
])
expected_closure_requirements = Set([
    "source-provenance-lock",
    "canonical-wang-assembly",
    "generic-api-and-composability",
    "sequential-cpu-conformance",
    "order-and-boundaries",
    "transaction-and-failure-atomicity",
    "completed-mcs-restart",
    "steady-state-resource-contract",
    "portable-abi-readiness",
    "source-semantic-study",
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
check(study_ids == expected_studies,
    "G3-B source-semantic study registry is incomplete")
check(command_ids == expected_commands,
    "G3-B closure-command registry is incomplete")

normalization = contract["contact_neighbor_normalization"]
check(occursin("ephemeral derived process workspace",
          normalization["state_rule"]) &&
      occursin("not authoritative", normalization["state_rule"]) &&
      occursin("atomic OR", normalization["storage_rule"]) &&
      occursin("ascending neighbor identity",
          normalization["reduction_rule"]) &&
      occursin("excluded from semantic checkpoints",
          normalization["persistence_rule"]),
    "G3-B contact-neighbor normalization is incomplete")
check(occursin("cld(cell_capacity, 32)",
          contract["capacities"]["contact_adjacency_capacity"]) &&
      occursin("four low UInt32 bits",
          contract["capacities"]["packed_failure_capacity"]),
    "G3-B compact adjacency or packed-failure capacity is not frozen")

workspace_rows = Dict(row["id"] => row for row in contract["workspace"])
polarity_workspace = workspace_rows["polarity_snapshot"]
check(occursin("bit-packed", polarity_workspace["layout"]) &&
      occursin("cld(cell_capacity,32)",
          polarity_workspace["capacity"]) &&
      occursin("packed UInt32 failure key",
          polarity_workspace["capacity"]),
    "G3-B polarity workspace does not match the revision-6 execution view")

process_rows = Dict(row["id"] => row for row in contract["process"])
potts_process = process_rows["potts_metropolis"]
alignment_process = process_rows["neighbor_polarity_alignment"]
check(!any(item -> occursin("contact-neighbor", item),
          potts_process["writes"]) &&
      any(item -> occursin("post-Potts ownership", item),
          alignment_process["reads"]) &&
      occursin("bit-packed symmetric adjacency",
          alignment_process["snapshot"]),
    "G3-B process read/write authority still treats contact adjacency as scientific state")
check(occursin("packs failure class",
          contract["portable_abi"]["status_rule"]) &&
      occursin("one UInt32 key",
          contract["portable_abi"]["status_rule"]),
    "G3-B portable status rule does not select one packed diagnostic pair")

closure_requirement_ids =
    unique_ids(contract["closure_requirement"], "closure requirement registry")
check(closure_requirement_ids == expected_closure_requirements,
    "G3-B closure requirement registry is incomplete")

ledger_ids = unique_ids(closure_ledger["requirement"], "closure ledger")
check(ledger_ids == expected_closure_requirements,
    "G3-B closure ledger does not match the closure requirement registry")
check(closure_ledger["contract_revision"] == contract["revision"],
    "G3-B closure ledger targets a stale contract revision")
check(closure_ledger["schema_version"] == "1.1.0",
    "G3-B closure ledger does not use the revision-7 proof-matrix schema")
allowed_closure_statuses = Set(["pending", "partial", "passed"])
for row in closure_ledger["requirement"]
    check(row["status"] in allowed_closure_statuses,
        "closure row '$(row["id"])' has an invalid status")
    check(!isempty(row["evidence"]),
        "closure row '$(row["id"])' has no evidence pointer")
    check(row["proof_ids"] == ["requirement:$(row["id"])"],
        "closure row '$(row["id"])' lacks its exact manifest proof identity")
end

proof_facets = Set(contract["process_proof"]["required_facets"])
ledger_facets = Set(closure_ledger["process_matrix"]["required_facets"])
check(proof_facets == ledger_facets && length(proof_facets) == 9,
    "G3-B process proof facets disagree between contract and ledger")
process_evidence_ids =
    unique_ids(closure_ledger["process_evidence"], "process evidence matrix")
check(process_evidence_ids == expected_processes,
    "G3-B process evidence matrix does not cover the canonical root plan")
for row in closure_ledger["process_evidence"]
    passed = Set(row["passed_facets"])
    remaining = Set(row["remaining_facets"])
    check(isempty(intersect(passed, remaining)) &&
          union(passed, remaining) == proof_facets,
        "process evidence '$(row["id"])' does not partition required facets")
    derived_status = isempty(passed) ? "pending" :
        isempty(remaining) ? "passed" : "partial"
    check(row["status"] == derived_status,
        "process evidence '$(row["id"])' status is not derived from its facets")
end
all_passed =
    all(row -> row["status"] == "passed", closure_ledger["requirement"]) &&
    all(row -> row["status"] == "passed", closure_ledger["process_evidence"])
check((closure_ledger["overall_status"] == "passed") == all_passed,
    "closure overall status must be passed exactly when every requirement and process row is passed")
check(contract["closure_protocol"]["status"] in ("open", "passed") &&
      contract["closure_protocol"]["status"] ==
          closure_ledger["overall_status"],
    "G3-B contract and ledger closure statuses disagree")
check(occursin("every closure_requirement",
          contract["closure_protocol"]["completion_rule"]) &&
      occursin("clean tested commit", contract["closure_protocol"]["evidence_rule"]),
    "G3-B closure protocol is not fail-closed and commit-addressed")

attestation = contract["closure_attestation"]
check(attestation["schema_version"] == "1.0.0" &&
      attestation["manifest"] == closure_ledger["manifest"] &&
      attestation["hash_algorithm"] == "sha256",
    "G3-B closure attestation schema, manifest, or hash contract is inconsistent")
check(occursin("restricted", attestation["attestation_commit_rule"]) &&
      occursin("changed paths", attestation["attestation_commit_rule"]) &&
      occursin("clean implementation commit", attestation["tested_commit_rule"]),
    "G3-B closure attestation does not freeze the tested commit and post-test diff")
for row in contract["closure_command"]
    check(!isempty(row["command"]) && !isempty(row["claim"]),
        "closure command '$(row["id"])' lacks exact command text or claim")
    check(occursin("--startup-file=no", row["command"]),
        "closure command '$(row["id"])' does not disable startup-file drift")
end

process_by_id = Dict(row["id"] => row for row in contract["process"])
phases = [process_by_id[id]["phase"] for id in contract["plan"]["ordered_processes"]]
check(phases == collect(1:length(phases)),
    "G3-B root-plan process phases are not canonical and contiguous")
potts_process = process_by_id["potts_metropolis"]
check(occursin("NeighborOrder-3", potts_process["topology_policy"]) &&
      occursin("activation energy -50", potts_process["topology_policy"]) &&
      occursin("std::random_shuffle", potts_process["source_rng_policy"]) &&
      occursin("semantic Philox", potts_process["source_rng_policy"]),
    "G3-B focal-topology eligibility or RNG profile is not frozen")
check(occursin("exactly once", potts_process["energy_policy"]) &&
      occursin("extinction", potts_process["energy_policy"]) &&
      occursin("not double counted", potts_process["energy_policy"]) &&
      occursin("independent", potts_process["boundary_policy"]),
    "G3-B dynamic focal energy or Potts/field boundary separation is incomplete")

accepted_copy = contract["accepted_copy_transaction"]
check(occursin("exactly one transaction effect",
          accepted_copy["binding_rule"]) &&
      occursin("identical scientific configuration",
          accepted_copy["binding_rule"]) &&
      occursin("alias the authoritative coupled state",
          accepted_copy["binding_rule"]) &&
      occursin("pre-attempt", accepted_copy["proposal_rule"]) &&
      occursin("infallible", accepted_copy["commit_rule"]) &&
      occursin("byte-identical", accepted_copy["failure_rule"]) &&
      occursin("zero-based attempt ordinal", accepted_copy["attempt_identity"]),
    "G3-B accepted-copy transaction is not preflighted and atomically frozen")
topology_rng = contract["randomness"]["portable_focal_topology"]
check(topology_rng["contract"] == "Philox4x32x10V1" &&
      occursin("zero-based Potts attempt ordinal", topology_rng["address"]) &&
      occursin("do not shift", topology_rng["draw_rule"]) &&
      occursin("observation", topology_rng["replay_rule"]),
    "G3-B portable focal-topology RNG address or invariance is incomplete")

genericity = contract["genericity"]
check(occursin("No exported Wang-named", genericity["public_api_rule"]) &&
      occursin("positional mega-constructor", genericity["public_api_rule"]) &&
      occursin("non-Wang microassembly", genericity["reuse_rule"]) &&
      occursin("typed named bindings", genericity["coupling_rule"]),
    "G3-B generic API and composability guardrails are incomplete")
portable_abi = contract["portable_abi"]
check(occursin("one tree", portable_abi["storage_rule"]) &&
      occursin("method dispatch", portable_abi["dispatch_rule"]) &&
      occursin("capability preflight", portable_abi["dispatch_rule"]) &&
      occursin("plan constant", portable_abi["launch_rule"]) &&
      occursin("No per-cell", portable_abi["launch_rule"]) &&
      occursin("no scientific field, cell, relationship, or observation payload",
          portable_abi["transfer_rule"]) &&
      occursin("status scalars", portable_abi["transfer_rule"]) &&
      occursin("may not alter", portable_abi["promotion_lock"]),
    "G3-B portable ABI does not freeze adaptation, launches, transfers, and G3-C inheritance")

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
check(occursin("one finite endpoint type",
          contract["capacities"]["relationship_degree_rule"]) &&
      occursin("typed per-pair degree policy",
          contract["capacities"]["relationship_degree_rule"]) &&
      occursin("not implied",
          contract["capacities"]["relationship_degree_rule"]),
    "G3-B degree cap overclaims generic multi-type source parity")

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

observations = contract["observations"]
per_cell_record = observations["per_cell_record"]
geometry_snapshot = observations["geometry_snapshot"]
expected_source_columns = [
    "cell_id", "x", "y", "x_self_polarity", "y_self_polarity",
    "a", "s", "rac", "f", "f_x", "f_y", "fpp", "f_coef", "p_frac",
]
check(per_cell_record["source_columns"] == expected_source_columns &&
      per_cell_record["derived_columns"] ==
          ["target_mcs", "source_mcs", "cell_generation"],
    "G3-B exact per-cell observation columns are not frozen")
check(geometry_snapshot["target_mcs"] == [91, 271] &&
      geometry_snapshot["source_mcs"] == [90, 270] &&
      occursin("lossless", geometry_snapshot["payload"]) &&
      occursin("Phase 14.3", geometry_snapshot["deferred"]),
    "G3-B lossless geometry snapshots or Phase 14.3 boundary are incomplete")
check(occursin("ascending persistent cell identity", observations["ordering"]) &&
      occursin("arbitrary typed named per-cell property bindings",
          observations["generic_primitive_boundary"]) &&
      occursin("full N-dimensional lattice shape",
          observations["generic_primitive_boundary"]) &&
      occursin("maximum representable persistent one-based cell slot",
          observations["capacity_semantics"]) &&
      occursin("Wang declaration-layer configuration",
          observations["paper_profile_boundary"]) &&
      occursin("deterministic pre-publication failure", observations["overflow"]) &&
      occursin("neither duplicates nor skips", observations["restart"]) &&
      occursin("explicitly requested", observations["host_boundary"]),
    "G3-B observation order, overflow, restart, or publication boundary is incomplete")

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

for row in contract["semantic_studies"]
    check(row["status"] == "required-before-g3b-closure",
        "source-semantic study '$(row["id"])' has an unexpected status")
    check("G3-B completion claim" in row["blocks"],
        "source-semantic study '$(row["id"])' does not block an unsupported completion claim")
    check(row["external_execution_required"] === false &&
          !isempty(row["source_identity_required"]) &&
          !isempty(row["evidence_target"]) &&
          !isempty(row["conformance_rule"]),
        "source-semantic study '$(row["id"])' lacks source identity, analysis, uncertainty, or conformance requirements")
end

isempty(failures) || error(join(failures, '\n'))

println("Phase 14.1 G3-B implementation entry contract: PASS")

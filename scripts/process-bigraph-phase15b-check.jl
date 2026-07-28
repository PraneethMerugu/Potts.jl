#!/usr/bin/env julia

using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const failures = String[]
const PHASE15B_IMPLEMENTATION_SLICE =
    "5caff0ce5e87b001a7abe3a77d1be422daf56d76"
const PHASE15B_QUALIFIED_HEAD =
    "fc3ff11373b979b4d443f0d192d7bf6b8c444a47"
const PHASE15B_MERGE_COMMIT =
    "5643a1e8ca8c3dfc2d1cb124274823beae206dd3"
const PHASE15B_QUALIFIED_TREE =
    "a32f86db29dc82276df8fe6e81a6a64bf837e916"
const PHASE15B_CI_RUN = 30230566611

fail(message) = push!(failures, message)
check(condition, message) = condition || fail(message)

function require_file(relative_path)
    path = joinpath(ROOT, relative_path)
    check(isfile(path), "missing Phase 15.B artifact: $relative_path")
    path
end

project_path = require_file("lib/ProcessBigraphs/Project.toml")
phase15c_entry_path = require_file("spec/process-bigraph-phase15c-entry-v1.toml")
module_path = require_file("lib/ProcessBigraphs/src/ProcessBigraphs.jl")
structure_path = require_file("lib/ProcessBigraphs/src/algebraic_structure.jl")
composition_path = require_file("lib/ProcessBigraphs/src/composition.jl")
lowering_path = require_file("lib/ProcessBigraphs/src/lowering.jl")
runtime_path = require_file("lib/ProcessBigraphs/src/runtime.jl")
checkpoint_path = require_file("lib/ProcessBigraphs/src/checkpoint.jl")
test_path = require_file(
    "lib/ProcessBigraphs/test/test_phase15b_open_composition.jl")
runner_path = require_file("lib/ProcessBigraphs/test/runtests.jl")
readme_path = require_file("lib/ProcessBigraphs/README.md")
docs_path = require_file("lib/ProcessBigraphs/docs/src/internal.md")
local_registry_path = require_file("lib/ProcessBigraphs/parity-registry.toml")
root_registry_path = require_file("spec/process-bigraph-parity-registry-v1.toml")
decision_path = require_file(
    "spec/decisions/0037-process-bigraph-open-composition.md")
platform_decision_path = require_file(
    "spec/decisions/0034-process-bigraph-runtime-platform.md")
plan_path = require_file(
    "design/audits/process-bigraph-phase15b-open-composition-plan.md")
evidence_path = require_file(
    "design/evidence/process-bigraph-phase15b-evidence-v1.toml")
audit_path = require_file(
    "design/audits/process-bigraph-phase15b-open-composition-audit.md")
roadmap_path = require_file("design/refactor-roadmap.md")
ci_path = require_file(".github/workflows/ci.yml")

project = TOML.parsefile(project_path)
phase15c_entry = TOML.parsefile(phase15c_entry_path)
expected_package_version =
    phase15c_entry["runtime_implementation_status"] == "qualified_internal_alpha" ?
    "0.4.0" : "0.3.0"
check(project["version"] == expected_package_version,
    "package identity disagrees with the Phase 15.C lifecycle stage")
check(Set(keys(project["deps"])) ==
      Set(["ACSets", "AlgebraicRewriting", "Catlab", "SHA"]),
    "Phase 15.B dependencies must be retained alongside admitted Phase 16 AlgebraicRewriting")
check(project["compat"]["ACSets"] == "0.2.29" &&
      project["compat"]["Catlab"] == "0.17.6" &&
      project["compat"]["julia"] == "1.12.6",
    "accepted ACSets, Catlab, or Julia compatibility bounds changed")

module_source = read(module_path, String)
structure_source = read(structure_path, String)
composition_source = read(composition_path, String)
lowering_source = read(lowering_path, String)
runtime_source = read(runtime_path, String)
checkpoint_source = read(checkpoint_path, String)
tests = read(test_path, String)
runner = read(runner_path, String)
docs = read(readme_path, String) * "\n" * read(docs_path, String)
ci = read(ci_path, String)

for phrase in [
    "include(\"composition.jl\")",
    "BoundaryEndpoint",
    "CompositionSpec",
    "annotated_wiring_diagram",
]
    check(occursin(phrase, module_source), "module wiring is missing '$phrase'")
end
for phrase in [
    "PROCESS_BIGRAPH_ACSET_VERSION = \"1.1.0\"",
    ":CompositeContainment",
    ":Endpoint",
    ":BoundaryMap",
    ":Junction",
    ":JunctionEndpoint",
    "Catlab.OpenACSetTypes",
]
    check(occursin(phrase, structure_source),
        "canonical open structure is missing '$phrase'")
end
for phrase in [
    "struct BoundaryEndpoint",
    "struct OpenComposite",
    "struct CompositeMount",
    "struct JunctionSpec",
    "struct CompositionSpec",
    "function compose_open",
    "ProcessBigraphStructuredMulticospan",
    "struct AnnotatedWiringDiagram",
    "PROCESS_BIGRAPH_OPEN_PROFILE_VERSION = \"1.0.0\"",
    "canonical_model(view::AnnotatedWiringDiagram)",
    "canonical_model(::Catlab.WiringDiagram)",
]
    check(occursin(phrase, composition_source),
        "open-composition implementation is missing '$phrase'")
end
for phrase in [
    "_root_composite",
    "_validate_open_structure",
    "_materialize_static",
    "composite_containment",
    "junction_endpoint",
]
    check(occursin(phrase, lowering_source),
        "hierarchy lowering or provenance is missing '$phrase'")
end

for forbidden in ("ACSets", "Catlab", "OpenComposite", "WiringDiagram",
        "StructuredCospan", "StaticComposite", "canonical_structure")
    check(!occursin(forbidden, runtime_source),
        "runtime hot path mentions authoring structure '$forbidden'")
    check(!occursin(forbidden, checkpoint_source),
        "checkpoint path mentions authoring structure '$forbidden'")
end

for phrase in [
    "row_permuted",
    "checkpoint_fingerprint",
    "nested immutable composition",
    "endpoint roles, privacy, and repeated definitions",
    "n-way junctions and exact endpoint contracts",
    "TransferDeclaration",
    "phase15b_reverse_rows",
    "malformed",
    "Catlab.WiringDiagram",
]
    check(occursin(phrase, tests), "Phase 15.B tests are missing '$phrase'")
end
check(occursin("test_phase15b_open_composition.jl", runner),
    "Phase 15.B tests are absent from the package runner")
check(occursin("scripts/process-bigraph-phase15b-check.jl", ci),
    "Phase 15.B checker is absent from the required CI workflow")
for phrase in [
    "Immutable open composition",
    "Advanced AlgebraicJulia access",
    "generic Catlab",
    "Phase 15.C",
]
    check(occursin(phrase, docs), "Phase 15.B documentation is missing '$phrase'")
end

local_registry = TOML.parsefile(local_registry_path)
check(local_registry["schema_version"] == "1.3.0" &&
      local_registry["maturity"] in (
        "phase_15b_open_composition",
        "phase_15c_implementation_candidate",
        "phase_15c_serial_internal_alpha",
      ),
    "package-local Phase 15.B maturity is not closed")
local_features = Dict(row["id"] => row for row in local_registry["features"])
target_rows = Set([
    "structured-cospan-open-composition",
    "derived-directed-wiring-view",
])
check(target_rows <= Set(keys(local_features)),
    "package-local registry omits a Phase 15.B row")
check(all(local_features[id]["implementation_status"] == "implemented" &&
          local_features[id]["oracle_status"] == "direct_passing"
          for id in target_rows),
    "package-local Phase 15.B rows lack direct evidence")

root_registry = TOML.parsefile(root_registry_path)
check(root_registry["schema_version"] == "1.3.0" &&
      root_registry["registry_status"] in (
        "phase15c-entry-frozen-runtime-not-started",
        "phase15c-implementation-candidate-awaiting-attestation",
        "phase15c-qualified-serial-internal-alpha",
      ),
    "root registry does not preserve bounded Phase 15.B")
phase15b = root_registry["phase15b_implementation"]
check(phase15b["status"] == "passed_open_composition" &&
      Set(phase15b["implemented_rows"]) == target_rows,
    "Phase 15.B summary and implemented rows disagree")
root_features = Dict(row["id"] => row for row in root_registry["features"])
check(all(root_features[id]["status"] == "implemented" &&
          root_features[id]["evidence_status"] == "direct_passing_phase15b"
          for id in target_rows),
    "root Phase 15.B feature claims disagree with evidence")

evidence = TOML.parsefile(evidence_path)
check(evidence["status"] == "passed_open_composition" &&
      evidence["runtime_version"] == "0.3.0",
    "Phase 15.B evidence status or runtime version is wrong")
check(evidence["runtime_commit"] == PHASE15B_MERGE_COMMIT,
    "Phase 15.B evidence does not name the merged runtime commit")
provenance = evidence["provenance"]
check(provenance["implementation_slice_commit"] ==
        PHASE15B_IMPLEMENTATION_SLICE &&
      provenance["qualified_head_commit"] == PHASE15B_QUALIFIED_HEAD &&
      provenance["merge_commit"] == PHASE15B_MERGE_COMMIT,
    "Phase 15.B implementation, qualification, or merge provenance is stale")
check(provenance["qualified_head_tree"] == PHASE15B_QUALIFIED_TREE &&
      provenance["merge_tree"] == PHASE15B_QUALIFIED_TREE,
    "Phase 15.B qualified and merged trees are not recorded as identical")
check(provenance["pull_request"] == 21 &&
      provenance["pull_request_url"] ==
        "https://github.com/PraneethMerugu/Potts.jl/pull/21" &&
      provenance["ci_run"] == PHASE15B_CI_RUN &&
      provenance["ci_run_url"] ==
        "https://github.com/PraneethMerugu/Potts.jl/actions/runs/30230566611" &&
      provenance["merge_method"] == "squash",
    "Phase 15.B PR, CI, or merge-method provenance is stale")
check(evidence["qualification"]["result"] == "passed" &&
      evidence["qualification"]["processbigraphs_tests_passed"] == 309 &&
      evidence["qualification"]["phase15b_open_composition_assertions"] == 193 &&
      evidence["qualification"]["aqua_checks_passed"] == 9,
    "Phase 15.B test counts or result are incomplete")
check(Set(evidence["qualification"]["implemented_rows"]) == target_rows,
    "Phase 15.B evidence rows disagree with the registries")
check(evidence["claims"]["structured_cospans"] == true &&
      evidence["claims"]["derived_directed_wiring_profile"] == true &&
      evidence["claims"]["nested_open_composites"] == true,
    "Phase 15.B evidence omits implemented claims")
check(evidence["claims"]["internal_alpha"] == false &&
      evidence["claims"]["independent_julia_specification_oracle"] == false &&
      evidence["claims"]["dynamic_rewriting"] == false &&
      evidence["claims"]["public_parity"] == false,
    "Phase 15.B evidence overclaims later gates")
check(evidence["policy"]["upstream_python_runtime_executed"] == false,
    "Phase 15.B evidence permits upstream Python execution")

decision = read(decision_path, String)
platform_decision = read(platform_decision_path, String)
plan = read(plan_path, String)
audit = read(audit_path, String)
roadmap = read(roadmap_path, String)
check(occursin("Implemented and directly passing", decision),
    "Decision 0037 implementation disposition is stale")
check(occursin(
        "PB0 and Phase 15.A--15.C passed; ProcessBigraphs 0.4.0 is a qualified serial internal alpha",
        platform_decision),
    "Decision 0034 implementation disposition is stale")
check(occursin("Status: Implemented and directly passing", plan),
    "Phase 15.B plan status is stale")
for phrase in [
    "Status: Phase 15.B passed",
    "Requirement audit",
    "Architectural findings",
    "Post-merge provenance and maintenance disposition",
    PHASE15B_QUALIFIED_HEAD,
    PHASE15B_MERGE_COMMIT,
    PHASE15B_QUALIFIED_TREE,
    "Subsequent Phase 15.C disposition",
]
    check(occursin(phrase, audit), "Phase 15.B audit is missing '$phrase'")
end
status_sources = join([
    platform_decision,
    local_features["canonical-process-bigraph-acset"]["limitation"],
    root_registry["pb0_implementation"]["remaining_claim"],
    root_registry["phase15a_implementation"]["remaining_claim"],
    roadmap,
], "\n")
for stale in [
    "Phase 15 not implemented",
    "Phase 15.B implementation remains open",
    "their implementation and evidence remain open",
    "while structured composition, the independent Julia specification oracle",
    "Structured-cospan composition, directed wiring views, the independent specification oracle",
]
    check(!occursin(stale, status_sources),
        "stale Phase 15.B status remains: '$stale'")
end

if isempty(failures)
    println("ProcessBigraphs Phase 15.B closure check passed:")
    println("  typed same-schema endpoints and real Catlab structured cospans")
    println("  pure n-ary composition with exact roles, contracts, identity, and initialization")
    println("  arbitrary-depth immutable hierarchy compiled to flat indexed runtime plans")
    println("  lossless annotated wiring profile with generic diagrams fail-closed")
    println("  193 direct Phase 15.B assertions and preserved PB0/Phase 15.A baselines")
    println(expected_package_version == "0.4.0" ?
        "  Phase 15.C oracle/internal alpha is qualified; dynamic rewriting and release remain open" :
        "  independent oracle, complete internal alpha, dynamic rewriting, and release remain open")
else
    println(stderr,
        "ProcessBigraphs Phase 15.B closure failed with $(length(failures)) issue(s):")
    for message in failures
        println(stderr, "  - ", message)
    end
    exit(1)
end

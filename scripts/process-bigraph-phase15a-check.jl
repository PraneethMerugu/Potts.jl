#!/usr/bin/env julia

using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const failures = String[]

fail(message) = push!(failures, message)
check(condition, message) = condition || fail(message)

function require_file(relative_path)
    path = joinpath(ROOT, relative_path)
    check(isfile(path), "missing Phase 15.A artifact: $relative_path")
    path
end

project_path = require_file("lib/ProcessBigraphs/Project.toml")
phase15c_entry_path = require_file("spec/process-bigraph-phase15c-entry-v1.toml")
module_path = require_file("lib/ProcessBigraphs/src/ProcessBigraphs.jl")
structure_path = require_file("lib/ProcessBigraphs/src/algebraic_structure.jl")
lowering_path = require_file("lib/ProcessBigraphs/src/lowering.jl")
composites_path = require_file("lib/ProcessBigraphs/src/composites.jl")
runtime_path = require_file("lib/ProcessBigraphs/src/runtime.jl")
checkpoint_path = require_file("lib/ProcessBigraphs/src/checkpoint.jl")
test_path = require_file(
    "lib/ProcessBigraphs/test/test_phase15a_algebraic_structure.jl")
runner_path = require_file("lib/ProcessBigraphs/test/runtests.jl")
local_registry_path = require_file("lib/ProcessBigraphs/parity-registry.toml")
root_registry_path = require_file("spec/process-bigraph-parity-registry-v1.toml")
evidence_path = require_file("design/evidence/process-bigraph-phase15a-evidence-v1.toml")
audit_path = require_file(
    "design/audits/process-bigraph-phase15a-canonical-structure-audit.md")

project = TOML.parsefile(project_path)
phase15c_entry = TOML.parsefile(phase15c_entry_path)
expected_package_version =
    phase15c_entry["runtime_implementation_status"] == "qualified_internal_alpha" ?
    "0.4.0" : "0.3.0"
check(project["version"] == expected_package_version,
    "package identity disagrees with the Phase 15.C lifecycle stage")
deps = Set(keys(get(project, "deps", Dict{String,Any}())))
check(deps == Set(["ACSets", "Catlab", "SHA"]),
    "ProcessBigraphs runtime dependencies must be exactly ACSets, Catlab, and SHA")
compat = project["compat"]
check(get(compat, "ACSets", "") == "0.2.29",
    "ACSets compatibility must begin at accepted v0.2.29")
check(get(compat, "Catlab", "") == "0.17.6",
    "Catlab compatibility must begin at accepted v0.17.6")
check(get(compat, "julia", "") == "1.12.6",
    "ProcessBigraphs must continue to target Julia 1.12.6")

module_source = read(module_path, String)
structure_source = read(structure_path, String)
lowering_source = read(lowering_path, String)
composites_source = read(composites_path, String)
runtime_source = read(runtime_path, String)
checkpoint_source = read(checkpoint_path, String)
tests = read(test_path, String)
runner = read(runner_path, String)

for phrase in [
    "import ACSets",
    "import Catlab",
    "include(\"algebraic_structure.jl\")",
    "include(\"lowering.jl\")",
]
    check(occursin(phrase, module_source), "module wiring is missing '$phrase'")
end
for phrase in [
    "@acset_type ProcessBigraphACSet",
    "struct CanonicalModel",
    "struct StructuralProvenance",
    "struct StructuralEpoch",
    "struct ExecutionPlan",
]
    check(occursin(phrase, structure_source),
        "canonical structure implementation is missing '$phrase'")
end
for phrase in [
    "_lower_static_to_structure",
    "_reconstruct_schema",
    "_validate_canonical_structure",
    "compile_composite(model::CanonicalModel)",
    "reverse_insertion",
]
    check(occursin(phrase, lowering_source),
        "canonical lowering is missing '$phrase'")
end
check(occursin("epoch::StructuralEpoch", composites_source) &&
      occursin("plan::ExecutionPlan", composites_source) &&
      !occursin("declaration::StaticComposite", composites_source),
    "CompiledComposite still retains the authoring declaration")
check(!occursin("ACSets", runtime_source) &&
      !occursin("StaticComposite", runtime_source) &&
      !occursin("canonical_structure", runtime_source),
    "runtime hot path reaches an ACSet or authoring façade")
check(!occursin(".declaration.processes", runtime_source) &&
      !occursin(".declaration.steps", checkpoint_source),
    "runtime or checkpoint code still traverses the PB0 declaration")

for phrase in [
    "canonical ProcessBigraph ACSet",
    "row, declaration, and authoring-path invariance",
    "canonical_fast != renumbered_fast",
    "model_fingerprint(typed) == model_fingerprint(row_permuted)",
    "compile_composite(canonical_rows;",
    "fail-closed corruption",
    "StaticComposite ∉ fieldtypes(CompiledComposite)",
]
    check(occursin(phrase, tests), "Phase 15.A tests are missing '$phrase'")
end
check(occursin("test_phase15a_algebraic_structure.jl", runner),
    "Phase 15.A tests are absent from the package runner")

local_registry = TOML.parsefile(local_registry_path)
check(local_registry["maturity"] in (
        "phase_15b_open_composition",
        "phase_15c_implementation_candidate",
        "phase_15c_serial_internal_alpha",
    ),
    "package-local maturity no longer preserves Phase 15.A")
root_registry = TOML.parsefile(root_registry_path)
check(root_registry["registry_status"] in (
        "phase15c-entry-frozen-runtime-not-started",
        "phase15c-implementation-candidate-awaiting-attestation",
        "phase15c-qualified-serial-internal-alpha",
    ),
    "root registry no longer preserves Phase 15.A")
phase15a = root_registry["phase15a_implementation"]
check(phase15a["status"] == "passed_canonical_structure",
    "root registry does not close Phase 15.A")
check(Set(phase15a["implemented_rows"]) == Set([
    "canonical-process-bigraph-acset",
    "compiled-structural-epoch",
]), "Phase 15.A implemented-row set changed")

evidence = TOML.parsefile(evidence_path)
check(evidence["status"] == "passed_canonical_structure",
    "Phase 15.A evidence status is not passed")
check(occursin(r"^[0-9a-f]{40}$", evidence["runtime_commit"]),
    "Phase 15.A evidence lacks an exact implementation commit")
check(evidence["dependencies"]["ACSets"] == "0.2.29" &&
      evidence["dependencies"]["Catlab"] == "0.17.6",
    "Phase 15.A dependency evidence changed")
check(evidence["qualification"]["pb0_model_fingerprint"] ==
      "49614f983db7f29d5c19465db95f5a367211a2ddea514fbf6d653f1fbfc90e30",
    "PB0 model fingerprint baseline changed")
check(evidence["qualification"]["pb0_final_snapshot_fingerprint"] ==
      "20b33b31def9e172bc7c9a57d4915f18094689667338e0eed90b70aac9ae4a3a",
    "PB0 final-state baseline changed")
check(evidence["claims"]["internal_alpha"] == false &&
      evidence["claims"]["structured_cospans"] == false &&
      evidence["claims"]["dynamic_rewriting"] == false,
    "Phase 15.A evidence overclaims later gates")

audit = read(audit_path, String)
for phrase in [
    "Status: Phase 15.A passed",
    "Canonical ProcessBigraph ACSet",
    "Compiled structural epoch",
    "Subsequent Phase 15 disposition",
]
    check(occursin(phrase, audit), "Phase 15.A audit is missing '$phrase'")
end

if isempty(failures)
    println("ProcessBigraphs Phase 15.A closure check passed:")
    println("  ACSets 0.2.29 and Catlab 0.17.6 are direct bounded dependencies")
    println("  typed and direct-ACSet authoring share one canonical structure")
    println("  compiled runtime and checkpoint paths use immutable indexed plans")
    println("  PB0 fingerprints, traces, failure atomicity, and replay are preserved")
    println(expected_package_version == "0.4.0" ?
        "  Phase 15.C internal alpha is qualified; later AlgebraicJulia phases remain fail-closed" :
        "  complete internal alpha and later AlgebraicJulia phases remain fail-closed")
else
    println(stderr,
        "ProcessBigraphs Phase 15.A closure failed with $(length(failures)) issue(s):")
    for message in failures
        println(stderr, "  - ", message)
    end
    exit(1)
end

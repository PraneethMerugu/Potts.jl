#!/usr/bin/env julia

using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const failures = String[]
check(condition, message) = condition || push!(failures, message)

function require_file(relative)
    path = joinpath(ROOT, relative)
    check(isfile(path), "missing Phase 16.HC artifact: $(relative)")
    path
end

const REQUIRED = [
    "design/audits/process-bigraph-phase16hc-high-level-authoring-audit.md",
    "design/audits/process-bigraph-phase16hc-high-level-authoring-owner-interview.md",
    "design/evidence/process-bigraph-phase16hc-authoring-performance-v1.toml",
    "design/evidence/process-bigraph-phase16hc-evidence-v1.toml",
    "benchmark/phase16hc_authoring_qualification.jl",
    "lib/ProcessBigraphs/Project.toml",
    "lib/ProcessBigraphs/README.md",
    "lib/ProcessBigraphs/docs/src/internal.md",
    "lib/ProcessBigraphs/src/ProcessBigraphs.jl",
    "lib/ProcessBigraphs/src/authoring.jl",
    "lib/ProcessBigraphs/src/authoring/model.jl",
    "lib/ProcessBigraphs/src/authoring/builder.jl",
    "lib/ProcessBigraphs/src/authoring/validation.jl",
    "lib/ProcessBigraphs/src/authoring/lowering.jl",
    "lib/ProcessBigraphs/src/authoring/inspection.jl",
    "lib/ProcessBigraphs/src/authoring/serialization.jl",
    "lib/ProcessBigraphs/src/authoring/problem.jl",
    "lib/ProcessBigraphs/src/authoring/structure.jl",
    "lib/ProcessBigraphs/test/test_high_level_authoring.jl",
    "lib/ProcessBigraphs/test/examples/high_level_authoring.jl",
    "lib/CorePotts/src/coupled/merks2006.jl",
    "lib/CorePotts/src/coupled/shirinifard2012.jl",
    "scripts/process-bigraph-phase16hc-ir-guard.jl",
    "spec/decisions/0040-process-bigraph-high-level-authoring.md",
    "spec/process-bigraph-high-level-authoring-semantics.md",
    "spec/process-bigraph-phase16-entry-v1.toml",
    "spec/process-bigraph-phase16-api-v1.toml",
    "spec/process-bigraph-phase16-backend-matrix-v1.toml",
    "spec/process-bigraph-phase16-migration-registry-v1.toml",
    "spec/process-bigraph-phase16-qualification-v1.toml",
    "spec/process-bigraph-parity-registry-v1.toml",
    "lib/ProcessBigraphs/parity-registry.toml",
    ".github/workflows/ci.yml",
]
paths = Dict(path => require_file(path) for path in REQUIRED)

entry = TOML.parsefile(paths["spec/process-bigraph-phase16-entry-v1.toml"])
api = TOML.parsefile(paths["spec/process-bigraph-phase16-api-v1.toml"])
matrix = TOML.parsefile(
    paths["spec/process-bigraph-phase16-backend-matrix-v1.toml"])
migration = TOML.parsefile(
    paths["spec/process-bigraph-phase16-migration-registry-v1.toml"])
ledger = TOML.parsefile(
    paths["spec/process-bigraph-phase16-qualification-v1.toml"])
parity = TOML.parsefile(
    paths["spec/process-bigraph-parity-registry-v1.toml"])
local_parity = TOML.parsefile(
    paths["lib/ProcessBigraphs/parity-registry.toml"])
performance = TOML.parsefile(
    paths["design/evidence/process-bigraph-phase16hc-authoring-performance-v1.toml"])
evidence = TOML.parsefile(
    paths["design/evidence/process-bigraph-phase16hc-evidence-v1.toml"])
project = TOML.parsefile(paths["lib/ProcessBigraphs/Project.toml"])

requirements = Dict(row["id"] => row for row in ledger["requirements"])
families = Dict(row["id"] => row for row in api["families"])
slices = Dict(row["id"] => row for row in migration["slices"])

phase_state = "phase16hc_qualified_c_hardware_open"
check(entry["implementation_status"] == phase_state &&
      entry["phase16hc"]["status"] == "qualified" &&
      entry["phase16hc"]["implementation_authorized"] == true &&
      entry["phase16hc"]["migration_authorized"] == true &&
      entry["internal_beta"] == false &&
      entry["public_release"] == false,
    "Phase 16.HC entry state is not qualified with hardware honestly open")

for id in ["P16-HC01", "P16-HC02", "P16-HC03", "P16-HC04",
           "P16-HC05", "P16-HC06", "P16-HC07"]
    check(requirements[id]["status"] == "qualified",
        "$(id) is not qualified")
    check("design/evidence/process-bigraph-phase16hc-evidence-v1.toml" in
          requirements[id]["evidence"],
        "$(id) does not cite Phase 16.HC evidence")
end
for id in [
    "P16-A01", "P16-A02", "P16-A03",
    "P16-B01", "P16-B02", "P16-B03", "P16-B04", "P16-B05", "P16-B06",
    "P16-C01",
    "P16-D01", "P16-D02", "P16-D03", "P16-D04",
    "P16-E01", "P16-E02", "P16-E03",
    "P16-F01", "P16-F02", "P16-F03",
    "P16-G01", "P16-G02",
    "P16-H01", "P16-H02", "P16-H03",
]
    check(requirements[id]["status"] == "qualified",
        "$(id) lost prior qualification")
end
check(requirements["P16-C02"]["status"] == "oracle_passing" &&
      requirements["P16-C03"]["status"] == "implemented" &&
      requirements["P16-C04"]["status"] == "oracle_passing",
    "Phase 16.HC must not overclaim open real-hardware rows")
for id in ["P16-I01", "P16-I02", "P16-I03"]
    check(requirements[id]["status"] == "specified",
        "$(id) must remain open before Phase 16.I reconciliation")
end

check(api["status"] == phase_state &&
      api["current_new_exports"] == api["planned_internal_beta_exports"] &&
      length(api["current_new_exports"]) ==
      length(unique(api["current_new_exports"])) &&
      families["authoring"]["status"] == "qualified" &&
      api["phase16hc"]["status"] == "qualified" &&
      api["policy"]["ordinary_julia_api_required"] == true &&
      api["policy"]["full_compose_macro_required"] == false &&
      api["policy"]["raw_ir_required_for_scientific_models"] == false,
    "high-level authoring API registry is not qualified or internally consistent")
expected_authoring_exports = Set([
    "CompositeModel", "LoweredModel", "SimulationProblem", "StateIntervention",
    "ValidationReport", "ModelValidationError", "Every", "At", "On", "After",
    "compose", "store!", "mount!", "connect!", "attach!", "expose!",
    "schedule!", "iteration!", "parameter!", "observable!", "allow_instances!",
    "lower", "compile", "validate", "describe", "diagram", "explain", "remake",
    "semantic_fingerprint", "ir_fingerprint", "plan_fingerprint",
    "problem_fingerprint", "origin_map", "parameter_names", "with_parameters",
    "spawn", "divide", "remove", "move",
])
check(expected_authoring_exports <= Set(api["current_new_exports"]),
    "qualified authoring exports are incomplete")
check(Set([
        "StoreHandle", "ComponentHandle", "PortHandle", "ParameterHandle",
        "ObservableHandle", "MountedCompositeHandle", "MountedEndpointHandle",
        "TemplateHandle", "ValidationDiagnostic", "AttachmentReport",
        "encode_semantic_model", "decode_semantic_model",
    ]) <= Set(api["planned_public_unexported"]),
    "expert authoring types or semantic codecs lost their unexported disposition")

check(matrix["phase16hc_status"] == "qualified" &&
      migration["status"] == "phase16hc_qualified",
    "backend or migration control plane does not record qualified Phase 16.HC")
for id in [
    "high-level-authoring-core",
    "merks-high-level-authoring",
    "cnv-high-level-authoring",
    "ordinary-tests-examples-and-docs-authoring",
]
    check(slices[id]["status"] == "qualified",
        "migration slice $(id) is not qualified")
end
check(parity["phase16_entry"]["implementation_status"] == phase_state &&
      local_parity["accepted_next_architecture"]["phase16_status"] == phase_state,
    "root or package parity registry does not record qualified Phase 16.HC")

facade = read(paths["lib/ProcessBigraphs/src/authoring.jl"], String)
facade_includes = [
    "model.jl", "builder.jl", "validation.jl", "lowering.jl",
    "inspection.jl", "serialization.jl", "problem.jl", "structure.jl",
]
check(all(file -> occursin("include(\"authoring/$(file)\")", facade),
          facade_includes) &&
      countlines(IOBuffer(facade)) <= 12,
    "authoring.jl is no longer a small cohesive-module facade")

model_source = read(paths["lib/ProcessBigraphs/src/authoring/model.jl"], String)
builder_source = read(paths["lib/ProcessBigraphs/src/authoring/builder.jl"], String)
validation_source =
    read(paths["lib/ProcessBigraphs/src/authoring/validation.jl"], String)
lowering_source =
    read(paths["lib/ProcessBigraphs/src/authoring/lowering.jl"], String)
serialization_source =
    read(paths["lib/ProcessBigraphs/src/authoring/serialization.jl"], String)
problem_source =
    read(paths["lib/ProcessBigraphs/src/authoring/problem.jl"], String)
for required in (
    "struct CompositeModel",
    "struct LoweredModel",
    "struct AuthorOrigin",
    "struct ValidationDiagnostic",
    "struct Every",
    "struct At",
    "struct On",
    "struct After",
)
    check(occursin(required, model_source),
        "semantic model layer omits $(required)")
end
for required in (
    "mutable struct CompositeBuilder",
    "function store!",
    "function mount!",
    "function connect!",
    "function attach!",
    "function schedule!",
    "function expose!",
    "function parameter!",
    "function observable!",
    "function allow_instances!",
)
    check(occursin(required, builder_source),
        "ordinary Julia builder omits $(required)")
end
check(occursin("function validate(", validation_source) &&
      occursin("function compose(", validation_source) &&
      occursin("ModelValidationError", validation_source),
    "validation/finalization lifecycle changed")
check(occursin("function _origin_map(", lowering_source) &&
      occursin("function lower(", lowering_source) &&
      occursin("author_origins", lowering_source),
    "deterministic lowering or plan-carried author origins changed")
check(occursin("SEMANTIC_MODEL_FORMAT_ID", serialization_source) &&
      occursin("function encode_semantic_model(", serialization_source) &&
      occursin("function decode_semantic_model(", serialization_source) &&
      occursin("migrate_semantic_model_payload", serialization_source),
    "semantic serialization or explicit migration protocol changed")
check(occursin("struct StateIntervention", problem_source) &&
      occursin("struct SimulationProblem", problem_source) &&
      occursin("_StateInterventionProcess", problem_source) &&
      occursin("function _bind_interventions(", problem_source),
    "typed problem binding or ordinary intervention lowering changed")

tests = read(
    paths["lib/ProcessBigraphs/test/test_high_level_authoring.jl"], String)
for required in (
    "semantic builder lifecycle and lowering",
    "relationship connections, exact At, and On scheduling",
    "problem parameters are validated and rebound before compilation",
    "typed problem interventions use ordinary atomic publication",
    "ordinary Julia expressibility and deterministic identity",
    "hierarchy, shared junctions, and explicit exports",
    "structured diagnostics and exact attachment",
    "structural templates author typed requests",
    "encode_semantic_model",
    "origin_map",
)
    check(occursin(required, tests),
        "high-level authoring tests omit $(required)")
end

raw_ir = r"\b(?:StaticComposite|ProcessDeclaration|StepDeclaration|PortBinding)\s*\("
for relative in [
    "lib/CorePotts/src/coupled/merks2006.jl",
    "lib/CorePotts/src/coupled/shirinifard2012.jl",
]
    check(!occursin(raw_ir, read(paths[relative], String)),
        "$(relative) still constructs raw ProcessBigraph IR")
end
check(all(name -> haskey(project["weakdeps"], name),
          ["CommonSolve", "SciMLBase"]) &&
      all(name -> !haskey(project["deps"], name),
          ["CommonSolve", "SciMLBase", "CorePotts", "ModelingToolkit",
           "OrdinaryDiffEq", "Metal", "AMDGPU"]),
    "ProcessBigraphs core dependency boundary changed")

check(performance["evidence_id"] ==
      "process-bigraph-phase16hc-authoring-performance-v1" &&
      performance["events"] == 128 &&
      performance["repetitions"] == 9 &&
      performance["plan_identity_equal"] == true &&
      all(values(performance["checks"])) &&
      performance["warm_execution"]["time_ratio"] <=
      performance["budgets"]["warm_runtime_ratio_max"] &&
      performance["warm_execution"]["allocation_ratio"] <=
      performance["budgets"]["warm_allocation_ratio_max"],
    "frozen authoring performance evidence does not pass its declared budgets")

check(evidence["status"] == "qualified" &&
      evidence["phase"] == "16.HC" &&
      evidence["implementation_commit"] ==
      "50e4af354ca18c63908f3525519319034abc788f" &&
      evidence["implementation_tree"] ==
      "1b42c5e0b18f37d1df0ec07bd1f95803393bd4fa" &&
      Set(evidence["qualified_rows"]) ==
      Set(["P16-HC01", "P16-HC02", "P16-HC03", "P16-HC04",
           "P16-HC05", "P16-HC06", "P16-HC07"]) &&
      evidence["tests"]["process_bigraphs_total_assertions"] == 1221 &&
      evidence["tests"]["corepotts_total_assertions"] == 3863,
    "Phase 16.HC evidence identity, rows, or test totals changed")

for artifact in evidence["artifacts"]
    relative = artifact["path"]
    actual = bytes2hex(SHA.sha256(read(joinpath(ROOT, relative))))
    check(actual == artifact["sha256"],
        "Phase 16.HC artifact hash changed: $(relative)")
end

workflow = read(paths[".github/workflows/ci.yml"], String)
check(occursin("process-bigraph-phase16hc-check.jl", workflow) &&
      occursin("process-bigraph-phase16hc-ir-guard.jl", workflow) &&
      occursin("test/examples/high_level_authoring.jl", workflow),
    "CI does not enforce HC qualification, raw-IR policy, and executable docs")

if isempty(failures)
    println("ProcessBigraphs Phase 16.HC high-level authoring qualification check passed.")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error(
        "ProcessBigraphs Phase 16.HC check failed with $(length(failures)) error(s)",
    )
end

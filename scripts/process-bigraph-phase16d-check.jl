#!/usr/bin/env julia

using TOML
using SHA

const ROOT = normpath(joinpath(@__DIR__, ".."))
const failures = String[]
check(condition, message) = condition || push!(failures, message)

function require_file(relative)
    path = joinpath(ROOT, relative)
    check(isfile(path), "missing Phase 16.D artifact: $(relative)")
    path
end

const REQUIRED = [
    "design/audits/process-bigraph-phase16d-structural-transaction-audit.md",
    "design/evidence/process-bigraph-phase16d-evidence-v1.toml",
    "lib/ProcessBigraphs/src/structural_transactions.jl",
    "lib/ProcessBigraphs/test/phase16/test_phase16d_structural_transactions.jl",
    "spec/process-bigraph-phase16-entry-v1.toml",
    "spec/process-bigraph-phase16-api-v1.toml",
    "spec/process-bigraph-phase16-qualification-v1.toml",
    ".github/workflows/ci.yml",
]
paths = Dict(path => require_file(path) for path in REQUIRED)

entry = TOML.parsefile(paths["spec/process-bigraph-phase16-entry-v1.toml"])
api = TOML.parsefile(paths["spec/process-bigraph-phase16-api-v1.toml"])
ledger = TOML.parsefile(
    paths["spec/process-bigraph-phase16-qualification-v1.toml"])
evidence = TOML.parsefile(
    paths["design/evidence/process-bigraph-phase16d-evidence-v1.toml"])
requirements = Dict(row["id"] => row for row in ledger["requirements"])

check(entry["implementation_status"] in (
      "phase16d_qualified_c_hardware_open",
      "phase16e_qualified_c_hardware_open",
      "phase16f_qualified_c_hardware_open"),
    "Phase 16.D checker requires qualified-D/C-hardware-open state")
for id in ["P16-D01", "P16-D02", "P16-D03", "P16-D04"]
    check(requirements[id]["status"] == "qualified",
        "$(id) is not qualified")
    check("design/evidence/process-bigraph-phase16d-evidence-v1.toml" in
          requirements[id]["evidence"],
        "$(id) does not cite Phase 16.D evidence")
end
for id in [
    "P16-A01", "P16-A02", "P16-A03",
    "P16-B01", "P16-B02", "P16-B03",
    "P16-B04", "P16-B05", "P16-B06", "P16-C01",
]
    check(requirements[id]["status"] == "qualified",
        "$(id) lost prior qualification")
end
check(requirements["P16-C02"]["status"] == "oracle_passing" &&
      requirements["P16-C03"]["status"] == "implemented" &&
      requirements["P16-C04"]["status"] == "oracle_passing",
    "Phase 16.D must not overclaim the open Phase 16.C hardware rows")

families = Dict(row["id"] => row for row in api["families"])
f_qualified =
    entry["implementation_status"] == "phase16f_qualified_c_hardware_open"
check(api["status"] == entry["implementation_status"] &&
      api["current_new_exports"] ==
      (f_qualified ? api["planned_internal_beta_exports"] : []) &&
      families["structure"]["status"] == "qualified" &&
      api["policy"]["unqualified_names_may_not_be_exported"] == true,
    "Phase 16.D API family or no-early-export rule changed")

source_path = paths["lib/ProcessBigraphs/src/structural_transactions.jl"]
tests_path =
    paths["lib/ProcessBigraphs/test/phase16/test_phase16d_structural_transactions.jl"]
source = read(source_path, String)
tests = read(tests_path, String)
for required in (
    "AddCompositeRequest", "RemoveCompositeRequest",
    "DivideCompositeRequest", "MoveCompositeRequest",
    "RewireBindingRequest", "StructuralIdentityRecord",
    "StructuralLineage", "StructuralCapacity",
    "stage_structural_transaction", "publish_structural_transaction",
    "AlgebraicRewriting.Rule{:DPO}", "_apply_reference!",
    "unresolved_structural_conflict", "owned_closure_mismatch",
    "structural_checkpoint", "restore_structural_checkpoint",
    "numeric_structural_validation_failed",
)
    check(occursin(required, source),
        "structural transaction implementation omits $(required)")
end
check(!occursin("Rule{:SPO}", source) &&
      !occursin("cascading_rem", source),
    "stable structural operations use SPO or implicit cascade")

for required in (
    "DPO-backed stable operations", "candidate-order oracle",
    "bounded conflict fuzz and shrink", "settled-boundary structural restart",
    "p16d_shrink_conflict", "orders = (", "cases == 81",
    ":selection, :reference, :rewrite, :validation",
    "numeric_structural_validation_failed",
)
    check(occursin(required, tests),
        "Phase 16.D tests omit $(required)")
end

check(evidence["status"] == "qualified" &&
      evidence["phase"] == "16.D" &&
      Set(evidence["qualified_rows"]) ==
          Set(["P16-D01", "P16-D02", "P16-D03", "P16-D04"]) &&
      evidence["dependencies"]["rewrite_semantics"] == "DPO" &&
      evidence["dependencies"]["implicit_spo_cascade"] == false &&
      evidence["semantics"]["numeric_and_structural_atomic"] == true &&
      evidence["semantics"]["checksummed_settled_restart"] == true &&
      evidence["oracle"]["bounded_order_permutations"] == 6 &&
      evidence["oracle"]["bounded_conflict_cases"] == 81 &&
      evidence["oracle"]["minimal_conflict_shrinker"] == true &&
      evidence["tests"]["phase16d_assertions"] == 173 &&
      evidence["tests"]["full_package_assertions"] == 1019 &&
      evidence["tests"]["full_package_suite"] == "passed",
    "Phase 16.D evidence identity, semantics, or totals changed")
check(bytes2hex(SHA.sha256(read(source_path))) ==
      evidence["artifacts"]["source_sha256"] &&
      bytes2hex(SHA.sha256(read(tests_path))) ==
      evidence["artifacts"]["tests_sha256"],
    "Phase 16.D source or tests differ from content-addressed evidence")

workflow = read(paths[".github/workflows/ci.yml"], String)
check(occursin("process-bigraph-phase16d-check.jl", workflow),
    "CI does not enforce the Phase 16.D checker")
module_source = read(joinpath(
    ROOT, "lib", "ProcessBigraphs", "src", "ProcessBigraphs.jl"), String)
for name in (
    "AddCompositeRequest", "RemoveCompositeRequest",
    "DivideCompositeRequest", "MoveCompositeRequest",
    "RewireBindingRequest", "stage_structural_transaction",
    "publish_structural_transaction",
)
    check(!occursin(Regex("(?m)^export[^\\n]*\\b$(name)\\b"), module_source),
        "Phase 16.D internal name $(name) was exported before Phase 16.F")
end

if isempty(failures)
    println("ProcessBigraphs Phase 16.D qualification check passed.")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("ProcessBigraphs Phase 16.D check failed with $(length(failures)) error(s)")
end

#!/usr/bin/env julia

using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const failures = String[]
check(condition, message) = condition || push!(failures, message)

function require_file(relative)
    path = joinpath(ROOT, relative)
    check(isfile(path), "missing Phase 16.B artifact: $(relative)")
    path
end

const REQUIRED = [
    "design/audits/process-bigraph-phase16b-engine-field-audit.md",
    "lib/ProcessBigraphs/src/engine_protocol.jl",
    "lib/ProcessBigraphs/src/fields.jl",
    "lib/ProcessBigraphs/test/phase16/test_phase16b_engine_field.jl",
    "spec/process-bigraph-phase16-entry-v1.toml",
    "spec/process-bigraph-phase16-api-v1.toml",
    "spec/process-bigraph-phase16-qualification-v1.toml",
    "lib/ProcessBigraphs/Project.toml",
    ".github/workflows/ci.yml",
]
paths = Dict(path => require_file(path) for path in REQUIRED)

entry = TOML.parsefile(paths["spec/process-bigraph-phase16-entry-v1.toml"])
api = TOML.parsefile(paths["spec/process-bigraph-phase16-api-v1.toml"])
ledger = TOML.parsefile(paths["spec/process-bigraph-phase16-qualification-v1.toml"])
project = TOML.parsefile(paths["lib/ProcessBigraphs/Project.toml"])
requirements = Dict(row["id"] => row for row in ledger["requirements"])

candidate = entry["implementation_status"] == "phase16b_candidate"
qualified = entry["implementation_status"] in (
    "phase16b_qualified", "phase16c_candidate", "phase16c_qualified",
    "phase16d_qualified_c_hardware_open",
    "phase16e_qualified_c_hardware_open",
    "phase16f_qualified_c_hardware_open",
    "phase16g_qualified_c_hardware_open",
    "phase16h_qualified_c_hardware_open",
    "phase16hc_qualified_c_hardware_open",
    "phase16hc_qualified",
    "phase16i_candidate",
    "phase16_internal_beta_qualified")
d_qualified = entry["implementation_status"] in (
    "phase16d_qualified_c_hardware_open",
    "phase16e_qualified_c_hardware_open",
    "phase16f_qualified_c_hardware_open",
    "phase16g_qualified_c_hardware_open",
    "phase16h_qualified_c_hardware_open",
    "phase16hc_qualified_c_hardware_open",
    "phase16hc_qualified",
    "phase16i_candidate",
    "phase16_internal_beta_qualified")
f_qualified = entry["implementation_status"] in (
    "phase16f_qualified_c_hardware_open",
    "phase16g_qualified_c_hardware_open",
    "phase16h_qualified_c_hardware_open",
    "phase16hc_qualified_c_hardware_open",
    "phase16hc_qualified",
    "phase16i_candidate",
    "phase16_internal_beta_qualified")
check(candidate || qualified,
    "Phase 16.B checker requires candidate or qualified state")
expected = candidate ? "implemented" : "qualified"
for id in ["P16-B01", "P16-B02", "P16-B03", "P16-B04", "P16-B05", "P16-B06"]
    check(requirements[id]["status"] == expected,
        "$(id) must be $(expected) in the current Phase 16.B state")
end
for id in ["P16-A01", "P16-A02", "P16-A03"]
    check(requirements[id]["status"] == "qualified",
        "$(id) lost Phase 16.A qualification")
end
qualified_count = count(row -> row["status"] == "qualified", values(requirements))
check(candidate ? qualified_count == 3 : qualified_count >= 9,
    "Phase 16.B ledger does not preserve the admitted Phase 16.A/B qualifications")

check(api["current_new_exports"] ==
      (f_qualified ? api["planned_internal_beta_exports"] : []) &&
      api["policy"]["unqualified_names_may_not_be_exported"] == true,
    "Phase 16.B must not widen the public API before Phase 16.F cross-adapter qualification")
families = Dict(row["id"] => row for row in api["families"])
check(families["engine"]["status"] == expected &&
      families["field"]["status"] == expected &&
      families["structure"]["status"] ==
          (d_qualified ? "qualified" : "specified") &&
      families["sciml"]["status"] ==
          (f_qualified ? "qualified" : "specified"),
    "Phase 16.B API family states are inconsistent")

check(Set(keys(project["deps"])) ==
      Set(["ACSets", "AlgebraicRewriting", "Catlab", "SHA"]) &&
      Set(keys(project["weakdeps"])) == Set(["CommonSolve", "SciMLBase"]),
    "solver-neutral core dependency direction changed")

engine_source = read(paths["lib/ProcessBigraphs/src/engine_protocol.jl"], String)
field_source = read(paths["lib/ProcessBigraphs/src/fields.jl"], String)
test_source = read(
    paths["lib/ProcessBigraphs/test/phase16/test_phase16b_engine_field.jl"],
    String,
)
for forbidden in ("SciMLBase", "CommonSolve", "CorePotts")
    check(!occursin(forbidden, engine_source) && !occursin(forbidden, field_source),
        "Phase 16.B core source imports or names $(forbidden)")
end
for required in (
    "stage_operation!", "complete_operation!", "validate_candidate",
    "publish_candidate!", "discard_candidate!", "execute_engine!",
    "EngineEarlyReturn", "EngineEventRequest", "EngineFailure",
    "EngineContinuation", "projection_value",
)
    check(occursin(required, engine_source),
        "engine protocol omits $(required)")
end
for required in (
    "FieldDescriptor", "FieldGeometry", "FieldBoundary", "FieldState",
    "sample_field", "deposit_field", "execute_exchange", "FieldSplitPlan",
    "undeclared_field_algebraic_loop",
)
    check(occursin(required, field_source),
        "field protocol omits $(required)")
end
for required in (
    "p16b_publication_allocations", "stage_throw", "complete_throw",
    "publish_throw", "discard_throw", "restart cuts", "periodic",
    "reject-shortage", "FieldIterationRegion",
)
    check(occursin(required, test_source),
        "Phase 16.B test evidence omits $(required)")
end

planned = Set(Symbol.(api["planned_internal_beta_exports"]))
module_source = read(joinpath(
    ROOT, "lib", "ProcessBigraphs", "src", "ProcessBigraphs.jl"), String)
if !f_qualified
    for name in planned
        check(!occursin(Regex("(?m)^export[^\\n]*\\b$(name)\\b"), module_source),
            "unqualified Phase 16 name $(name) was exported early")
    end
end

if qualified
    evidence_path = require_file(
        "design/evidence/process-bigraph-phase16b-evidence-v1.toml")
    evidence = TOML.parsefile(evidence_path)
    check(evidence["status"] == "qualified" &&
          evidence["phase"] == "16.B" &&
          evidence["totals"]["phase16b_assertions"] >= 81 &&
          Set(evidence["qualified_rows"]) ==
          Set(["P16-B01", "P16-B02", "P16-B03",
               "P16-B04", "P16-B05", "P16-B06"]),
        "Phase 16.B evidence identity or totals changed")
else
    check(!isfile(joinpath(
        ROOT, "design/evidence/process-bigraph-phase16b-evidence-v1.toml")),
        "candidate state cannot contain final Phase 16.B evidence")
end

if isempty(failures)
    println("ProcessBigraphs Phase 16.B $(candidate ? "implementation candidate" : "qualification") check passed.")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("ProcessBigraphs Phase 16.B check failed with $(length(failures)) error(s)")
end

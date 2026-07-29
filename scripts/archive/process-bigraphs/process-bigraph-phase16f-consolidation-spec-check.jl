#!/usr/bin/env julia

using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const failures = String[]
fail(message) = push!(failures, message)
check(condition, message) = condition || fail(message)

function require_file(relative_path)
    path = joinpath(ROOT, relative_path)
    check(isfile(path), "missing Phase 16.F consolidation artifact: $(relative_path)")
    path
end

const PATHS = Dict(path => require_file(path) for path in [
    "design/audits/process-bigraph-phase16f-solver-integration-consolidation-research.md",
    "design/audits/process-bigraph-phase16-implementation-plan.md",
    "spec/decisions/0039-phase-16-compute-ownership-and-scope.md",
    "spec/phase-16-engine-field-structural-and-adapter-semantics.md",
    "spec/process-bigraph-phase16-entry-v1.toml",
    "spec/process-bigraph-phase16-qualification-v1.toml",
    "spec/process-bigraph-phase16-backend-matrix-v1.toml",
    "spec/process-bigraph-phase16-api-v1.toml",
    "spec/process-bigraph-parity-registry-v1.toml",
    "lib/ProcessBigraphs/parity-registry.toml",
])

entry = TOML.parsefile(PATHS["spec/process-bigraph-phase16-entry-v1.toml"])
ledger = TOML.parsefile(PATHS["spec/process-bigraph-phase16-qualification-v1.toml"])
backends = TOML.parsefile(PATHS["spec/process-bigraph-phase16-backend-matrix-v1.toml"])
api = TOML.parsefile(PATHS["spec/process-bigraph-phase16-api-v1.toml"])
parity = TOML.parsefile(PATHS["spec/process-bigraph-parity-registry-v1.toml"])
local_parity = TOML.parsefile(PATHS["lib/ProcessBigraphs/parity-registry.toml"])

f_qualified = entry["implementation_status"] in (
    "phase16f_qualified_c_hardware_open",
    "phase16g_qualified_c_hardware_open",
    "phase16h_qualified_c_hardware_open",
    "phase16hc_qualified_c_hardware_open",
    "phase16hc_qualified",
    "phase16i_candidate",
    "phase16_internal_beta_qualified")
check(entry["implementation_status"] in (
      "phase16e_qualified_c_hardware_open",
      "phase16f_qualified_c_hardware_open",
      "phase16g_qualified_c_hardware_open",
      "phase16h_qualified_c_hardware_open",
      "phase16hc_qualified_c_hardware_open",
      "phase16hc_qualified",
      "phase16i_candidate",
      "phase16_internal_beta_qualified"),
    "16.F consolidation checker requires the admitted E or F state")
check(entry["authority"]["phase16f_consolidation_research"] ==
      "../design/audits/process-bigraph-phase16f-solver-integration-consolidation-research.md" &&
      entry["authority"]["phase16f_consolidation_checker"] ==
      "../scripts/process-bigraph-phase16f-consolidation-spec-check.jl",
    "entry contract does not identify the 16.F consolidation authorities")
check(entry["ordering"]["phase16f_internal_order"] ==
      ["16.F0-consolidation-repair", "P16-F01", "P16-F02", "P16-F03"] &&
      entry["ordering"]["models_wait_for_qualified_phase16f"] == true,
    "16.F repair/qualification order or Merks/CNV join changed")

solver = entry["solver_integration"]
check(solver["phase16f_prototype_status"] ==
      (f_qualified ?
       "replaced_by_qualified_real_solver_implementation" :
      "unqualified_repair_required") &&
      solver["prototype_commit"] ==
      "e0fd0b3f51fd681923e7ac8b62963e9713430322" &&
      solver["process_bigraph_owned_sciml_solve"] == "forbidden" &&
      solver["qualified_algorithm_selection"] == "explicit_real_algorithm_object" &&
      solver["automatic_algorithm_selection"] == "experimental" &&
      solver["generic_continuation"] ==
      "reconstruct_each_invocation_from_published_canonical_state" &&
      solver["generic_replay"] == "numerical" &&
      occursin("outside ProcessBigraphs core", solver["custom_adapter_location"]) &&
      occursin("analytic/manufactured", solver["cross_adapter_oracle"]) &&
      occursin("research reference only", solver["mermaid_role"]),
    "solver-integration repair contract is incomplete or widened")

requirements = Dict(row["id"] => row for row in ledger["requirements"])
check(all(id -> requirements[id]["status"] ==
        (f_qualified ? "qualified" : "specified"),
        ["P16-F01", "P16-F02", "P16-F03"]),
    "16.F rows disagree with consolidation qualification state")
check(occursin("real-SciML", requirements["P16-F01"]["title"]) &&
      any(occursin("exact-target", evidence)
          for evidence in requirements["P16-F01"]["evidence"]) &&
      any(occursin("outside ProcessBigraphs core", evidence)
          for evidence in requirements["P16-F02"]["evidence"]) &&
      any(occursin("convergence", evidence)
          for evidence in requirements["P16-F03"]["evidence"]),
    "16.F ledger evidence does not encode the consolidation target")

envelopes = Dict(row["id"] => row for row in backends["envelopes"])
sciml = envelopes["sciml-cartesian-field"]
custom = envelopes["independent-custom-field"]
check(sciml["CPU"] == (f_qualified ? "qualified" : "specified") &&
      occursin("explicit injected real solver", sciml["algorithm"]) &&
      occursin("exact-target", sciml["exact_target"]) &&
      occursin("reconstruct each invocation", sciml["continuation"]) &&
      first(sciml["replay"]) == "numerical by default",
    "SciML backend envelope is not the bounded real-solver target")
check(custom["CPU"] == (f_qualified ? "qualified" : "specified") &&
      occursin("outside ProcessBigraphs core", custom["location"]) &&
      occursin("no SciML dependency", custom["independence"]),
    "custom adapter is not an external-style independent conformance envelope")

policy = api["policy"]
repair = api["phase16f_consolidation"]
check(api["current_new_exports"] ==
      (f_qualified ? api["planned_internal_beta_exports"] : []) &&
      policy["qualified_exports_only"] == true &&
      policy["process_bigraph_owned_sciml_solve"] == false &&
      policy["explicit_real_sciml_algorithm"] == true &&
      policy["automatic_algorithm_selection_qualified"] == false &&
      policy["custom_conformance_adapter_is_core_api"] == false &&
      policy["prototype_exports_are_admitted"] == false &&
      repair["status"] == (f_qualified ? "qualified" : "repair_required") &&
      repair["restore_current_new_exports_to"] == [],
    "Phase 16.F API containment or repair status changed")

expected_prototype_status = f_qualified ?
    "replaced_by_qualified_real_solver_implementation" :
    "unqualified_repair_required"
check(parity["phase16_entry"]["phase16f_prototype_status"] ==
      expected_prototype_status &&
      local_parity["accepted_next_architecture"]["phase16f_prototype_status"] ==
      expected_prototype_status,
    "root and package-local registries disagree about the prototype")

for (path, phrases) in [
    ("design/audits/process-bigraph-phase16f-solver-integration-consolidation-research.md",
        ["Mermaid-sized real-solver integration", "P16FixedEuler",
         "reconstruct_each_invocation", "MUST NOT begin"]),
    ("spec/decisions/0039-phase-16-compute-ownership-and-scope.md",
        ["real solver algorithm", "MUST NOT define a numerical"]),
    ("spec/phase-16-engine-field-structural-and-adapter-semantics.md",
        ["Real-solver handoff", "standard SciML return-code/error interface",
         "Mermaid.jl is a research reference"]),
    ("design/audits/process-bigraph-phase16-implementation-plan.md",
        ["mandatory 16.F0 repair",
         f_qualified ? "Qualified at implementation commit" :
         "unqualified 16.F prototype"]),
]
    content = read(PATHS[path], String)
    for phrase in phrases
        check(occursin(phrase, content), "$(path) missing required phrase: $(phrase)")
    end
end

if isempty(failures)
    println(f_qualified ?
        "ProcessBigraphs Phase 16.F consolidation check passed: repair is qualified." :
        "ProcessBigraphs Phase 16.F consolidation specification check passed; implementation repair and qualification remain open.")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("ProcessBigraphs Phase 16.F consolidation specification check failed with $(length(failures)) error(s)")
end

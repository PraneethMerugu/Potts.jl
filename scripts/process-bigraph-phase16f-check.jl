#!/usr/bin/env julia

using TOML
using SHA

const ROOT = normpath(joinpath(@__DIR__, ".."))
const failures = String[]
check(condition, message) = condition || push!(failures, message)

function require_file(relative)
    path = joinpath(ROOT, relative)
    check(isfile(path), "missing Phase 16.F artifact: $(relative)")
    path
end

const REQUIRED = [
    "design/audits/process-bigraph-phase16f-solver-plurality-audit.md",
    "design/evidence/process-bigraph-phase16f-evidence-v1.toml",
    "lib/ProcessBigraphs/ext/ProcessBigraphsSciMLExt.jl",
    "lib/ProcessBigraphs/src/bounded_cartesian_field_problem.jl",
    "lib/ProcessBigraphs/src/ProcessBigraphs.jl",
    "lib/ProcessBigraphs/test/fixtures/independent_custom_field_adapter.jl",
    "lib/ProcessBigraphs/test/phase16/test_phase16f_solver_plurality.jl",
    "lib/CorePotts/test/test_phase16_solver_plurality.jl",
    "lib/ProcessBigraphs/Project.toml",
    "lib/CorePotts/Project.toml",
    "spec/process-bigraph-phase16-entry-v1.toml",
    "spec/process-bigraph-phase16-api-v1.toml",
    "spec/process-bigraph-phase16-backend-matrix-v1.toml",
    "spec/process-bigraph-phase16-qualification-v1.toml",
    ".github/workflows/ci.yml",
]
paths = Dict(path => require_file(path) for path in REQUIRED)

entry = TOML.parsefile(paths["spec/process-bigraph-phase16-entry-v1.toml"])
api = TOML.parsefile(paths["spec/process-bigraph-phase16-api-v1.toml"])
matrix = TOML.parsefile(paths["spec/process-bigraph-phase16-backend-matrix-v1.toml"])
ledger = TOML.parsefile(paths["spec/process-bigraph-phase16-qualification-v1.toml"])
evidence = TOML.parsefile(
    paths["design/evidence/process-bigraph-phase16f-evidence-v1.toml"])
process_project = TOML.parsefile(paths["lib/ProcessBigraphs/Project.toml"])
core_project = TOML.parsefile(paths["lib/CorePotts/Project.toml"])
requirements = Dict(row["id"] => row for row in ledger["requirements"])
envelopes = Dict(row["id"] => row for row in matrix["envelopes"])

check(entry["implementation_status"] in (
      "phase16f_qualified_c_hardware_open",
      "phase16g_qualified_c_hardware_open"),
    "Phase 16.F checker requires qualified-F/C-hardware-open state")
for id in ["P16-F01", "P16-F02", "P16-F03"]
    check(requirements[id]["status"] == "qualified",
        "$(id) is not qualified")
    check("design/evidence/process-bigraph-phase16f-evidence-v1.toml" in
          requirements[id]["evidence"],
        "$(id) does not cite Phase 16.F evidence")
end
for id in [
    "P16-A01", "P16-A02", "P16-A03",
    "P16-B01", "P16-B02", "P16-B03", "P16-B04", "P16-B05", "P16-B06",
    "P16-C01",
    "P16-D01", "P16-D02", "P16-D03", "P16-D04",
    "P16-E01", "P16-E02", "P16-E03",
]
    check(requirements[id]["status"] == "qualified",
        "$(id) lost prior qualification")
end
check(requirements["P16-C02"]["status"] == "oracle_passing" &&
      requirements["P16-C03"]["status"] == "implemented" &&
      requirements["P16-C04"]["status"] == "oracle_passing",
    "Phase 16.F must not overclaim the open Phase 16.C hardware rows")

check(envelopes["sciml-cartesian-field"]["CPU"] == "qualified" &&
      envelopes["independent-custom-field"]["CPU"] == "qualified" &&
      envelopes["sciml-cartesian-field"]["Metal"] == "unsupported" &&
      envelopes["independent-custom-field"]["ROCm"] == "unsupported",
    "Phase 16.F backend matrix is not the qualified CPU-only envelope")

check(api["status"] == entry["implementation_status"] &&
      api["current_new_exports"] == api["planned_internal_beta_exports"] &&
      api["phase16f_consolidation"]["status"] == "qualified" &&
      api["policy"]["prototype_exports_are_admitted"] == false,
    "Phase 16.F API admission does not match the bounded allowlist")

check(Set(keys(process_project["deps"])) ==
      Set(["ACSets", "AlgebraicRewriting", "Catlab", "SHA"]) &&
      Set(keys(process_project["weakdeps"])) ==
      Set(["CommonSolve", "SciMLBase"]) &&
      "OrdinaryDiffEqTsit5" in process_project["targets"]["test"] &&
      haskey(process_project["extras"], "OrdinaryDiffEqTsit5") &&
      !haskey(process_project["deps"], "OrdinaryDiffEqTsit5"),
    "ProcessBigraphs concrete solver is not test-only")
check("OrdinaryDiffEqTsit5" in core_project["targets"]["test"] &&
      haskey(core_project["extras"], "OrdinaryDiffEqTsit5") &&
      !haskey(core_project["deps"], "OrdinaryDiffEqTsit5"),
    "CorePotts concrete solver is not test-only")

extension = read(paths[
    "lib/ProcessBigraphs/ext/ProcessBigraphsSciMLExt.jl"], String)
problem = read(paths[
    "lib/ProcessBigraphs/src/bounded_cartesian_field_problem.jl"], String)
fixture = read(paths[
    "lib/ProcessBigraphs/test/fixtures/independent_custom_field_adapter.jl"], String)
process_tests = read(paths[
    "lib/ProcessBigraphs/test/phase16/test_phase16f_solver_plurality.jl"], String)
core_tests = read(paths[
    "lib/CorePotts/test/test_phase16_solver_plurality.jl"], String)

for forbidden in (
    "P16FixedEuler", "P16SciMLSolution", "function CommonSolve.solve",
)
    check(!occursin(forbidden, extension),
        "SciML extension retains forbidden prototype construct $(forbidden)")
end
for required in (
    "CommonSolve.init", "CommonSolve.step!",
    "SciMLBase.ODEProblem", "SciMLBase.check_error",
    "SciMLBase.successful_retcode", "reconstruct_each_invocation",
    "algorithm_package_version", "QUALIFIED_SOLVER_OPTION_KEYS",
)
    check(occursin(required, extension),
        "SciML extension omits $(required)")
end
check(!occursin("substeps_per_tick", problem) &&
      !occursin("laplacian", lowercase(problem)),
    "solver-neutral problem contains numerical algorithm policy")
check(!occursin("SciML", fixture) &&
      occursin("independent-classical-rk4", fixture) &&
      occursin("_fixture_laplacian", fixture) &&
      !occursin("_fixture_laplacian", extension),
    "custom fixture is not numerically independent")
check(!isfile(joinpath(
        ROOT, "lib", "ProcessBigraphs", "src", "custom_field_adapter.jl")),
    "custom conformance adapter remains in production core")

for required in (
    "real solver handoff and declaration provenance",
    "analytic and convergence evidence",
    "tight_error < loose_error",
    "custom_errors[3] < custom_errors[2] / 8",
    "phase16f-manufactured-fourier",
    "payload.aggregate_replay === :numerical",
)
    check(occursin(required, process_tests),
        "ProcessBigraphs Phase 16.F tests omit $(required)")
end
for required in (
    "native real-solver custom cross-adapter evidence",
    "Float64", "Float32", "native_error", "sciml_error", "custom_error",
)
    check(occursin(required, core_tests),
        "CorePotts Phase 16.F tests omit $(required)")
end

check(evidence["status"] == "qualified" &&
      evidence["phase"] == "16.F" &&
      evidence["implementation_commit"] ==
      "9f9daf19e34c5430361cb98c8002f025a74d217a" &&
      evidence["implementation_tree"] ==
      "e371867f85c0dd646dc77ba781bd2a746fd4b097" &&
      evidence["compatibility_requalification_commit"] ==
      "09150b5457ae622093aa6a3ad61a7fc2d70b87e7" &&
      evidence["compatibility_requalification_tree"] ==
      "3e81f1affa1c517a32f6026a9d204730dd4aaa46" &&
      Set(evidence["qualified_rows"]) ==
      Set(["P16-F01", "P16-F02", "P16-F03"]) &&
      evidence["sciml"]["algorithm_explicit"] == true &&
      evidence["sciml"]["process_bigraph_owned_solve"] == false &&
      evidence["continuation"]["replay_class"] == "numerical" &&
      evidence["custom"]["sciml_dependency"] == false &&
      evidence["custom"]["shared_numerical_helper"] == false &&
      evidence["phase16g_compatibility"]["spatial_decay_weights"] == true &&
      evidence["phase16g_compatibility"]["legacy_forcing_only_invocations"] ==
      true &&
      evidence["tests"]["process_bigraphs_phase16f_assertions"] == 88 &&
      evidence["tests"]["corepotts_phase16f_assertions"] == 14 &&
      evidence["tests"]["process_bigraphs_full_assertions"] == 1150 &&
      evidence["tests"]["corepotts_full_assertions"] == 3786 &&
      evidence["tests"]["process_bigraphs_full_package_suite"] == "passed" &&
      evidence["tests"]["corepotts_full_package_suite"] == "passed",
    "Phase 16.F evidence identity, architecture, or test totals changed")

hash_pairs = [
    ("sciml_extension", "sciml_extension_sha256"),
    ("bounded_problem", "bounded_problem_sha256"),
    ("module", "module_sha256"),
    ("custom_fixture", "custom_fixture_sha256"),
    ("process_bigraphs_tests", "process_bigraphs_tests_sha256"),
    ("corepotts_tests", "corepotts_tests_sha256"),
]
for (path_key, hash_key) in hash_pairs
    relative = evidence["artifacts"][path_key]
    check(bytes2hex(SHA.sha256(read(joinpath(ROOT, relative)))) ==
          evidence["artifacts"][hash_key],
        "Phase 16.F artifact hash changed: $(relative)")
end
check(bytes2hex(SHA.sha256(read(paths["lib/ProcessBigraphs/Project.toml"]))) ==
      evidence["artifacts"]["process_bigraphs_project_sha256"] &&
      bytes2hex(SHA.sha256(read(paths["lib/CorePotts/Project.toml"]))) ==
      evidence["artifacts"]["corepotts_project_sha256"],
    "Phase 16.F package dependency evidence changed")

workflow = read(paths[".github/workflows/ci.yml"], String)
check(occursin("process-bigraph-phase16f-check.jl", workflow),
    "CI does not enforce the Phase 16.F qualification checker")

if isempty(failures)
    println("ProcessBigraphs Phase 16.F qualification check passed.")
else
    foreach(message -> println(stderr, "ERROR: ", message), failures)
    error("ProcessBigraphs Phase 16.F check failed with $(length(failures)) error(s)")
end

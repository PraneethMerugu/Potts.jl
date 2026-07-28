#!/usr/bin/env julia

using Dates
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
length(ARGS) == 2 ||
    error("usage: process-bigraph-phase16i-candidate.jl OUTPUT PERFORMANCE_REPORT")
const OUTPUT = abspath(ARGS[1])
const PERFORMANCE_PATH = abspath(ARGS[2])

file_sha256(path) = bytes2hex(sha256(read(path)))
git(args...) = readchomp(`git -C $(ROOT) $(args)`)

isempty(git("status", "--porcelain")) ||
    error("Phase 16.I candidate generation requires a clean exact-head tree")
isfile(PERFORMANCE_PATH) ||
    error("missing Phase 16.I performance report: $(PERFORMANCE_PATH)")

entry = TOML.parsefile(joinpath(
    ROOT, "spec", "process-bigraph-phase16-entry-v1.toml"))
ledger = TOML.parsefile(joinpath(
    ROOT, "spec", "process-bigraph-phase16-qualification-v1.toml"))
matrix = TOML.parsefile(joinpath(
    ROOT, "spec", "process-bigraph-phase16-backend-matrix-v1.toml"))
api = TOML.parsefile(joinpath(
    ROOT, "spec", "process-bigraph-phase16-api-v1.toml"))
project = TOML.parsefile(joinpath(
    ROOT, "lib", "ProcessBigraphs", "Project.toml"))
performance = TOML.parsefile(PERFORMANCE_PATH)
phase16c = TOML.parsefile(joinpath(
    ROOT, "design", "evidence", "process-bigraph-phase16c-evidence-v1.toml"))

entry["implementation_status"] == "phase16i_candidate" ||
    error("Phase 16.I candidate artifact requires phase16i_candidate state")
all(row["status"] in ("qualified", "oracle_passing")
    for row in ledger["requirements"]) ||
    error("Phase 16.I candidate contains a row below oracle_passing")
all(values(performance["checks"])) ||
    error("Phase 16.I performance report does not pass every frozen budget")
phase16c["status"] == "qualified" &&
    phase16c["ci"]["conclusion"] == "success" ||
    error("Phase 16.C trusted hardware evidence is not qualified")

head = git("rev-parse", "HEAD")
tree = git("rev-parse", "HEAD^{tree}")
base_ref = get(ENV, "PHASE16_BASE_REF", "origin/main")
base_commit = git("rev-parse", base_ref)
merge_base = git("merge-base", base_commit, head)
merge_tree = first(split(git("merge-tree", "--write-tree", base_commit, head), '\n'))
tree == merge_tree ||
    error("prospective merge tree differs from the exact-head candidate tree")

evidence_files = [
    "design/evidence/process-bigraph-phase16a-evidence-v1.toml",
    "design/evidence/process-bigraph-phase16b-evidence-v1.toml",
    "design/evidence/process-bigraph-phase16c-evidence-v1.toml",
    "design/evidence/process-bigraph-phase16d-evidence-v1.toml",
    "design/evidence/process-bigraph-phase16e-evidence-v1.toml",
    "design/evidence/process-bigraph-phase16f-evidence-v1.toml",
    "design/evidence/process-bigraph-phase16g-evidence-v1.toml",
    "design/evidence/process-bigraph-phase16h-evidence-v1.toml",
    "design/evidence/process-bigraph-phase16hc-evidence-v1.toml",
]
documentation_files = [
    "lib/ProcessBigraphs/README.md",
    "lib/ProcessBigraphs/docs/src/internal.md",
    "lib/ProcessBigraphs/docs/src/internal-beta.md",
    "lib/ProcessBigraphs/docs/src/adapters-and-solvers.md",
    "lib/ProcessBigraphs/docs/src/failure-and-persistence.md",
    "lib/ProcessBigraphs/docs/src/phase16-capabilities.md",
]
resolution_files = [
    "Project.toml",
    "Manifest.toml",
    "benchmark/Project.toml",
    "benchmark/Manifest.toml",
    "docs/Project.toml",
    "docs/Manifest.toml",
    "examples/Project.toml",
    "examples/Manifest.toml",
    "examples/dashboards/Project.toml",
    "examples/dashboards/Manifest.toml",
    "examples/notebooks/Project.toml",
    "examples/notebooks/Manifest.toml",
    "integration/Project.toml",
    "lib/CorePotts/Project.toml",
    "lib/MakiePotts/Project.toml",
    "lib/MakiePotts/test/backends/Project.toml",
    "lib/MakiePotts/test/backends/Manifest.toml",
    "lib/ProcessBigraphs/Project.toml",
    "paper/Project.toml",
    "paper/Manifest.toml",
]

cpu = Sys.cpu_info()
artifact = Dict(
    "schema_version" => "1.0.0",
    "artifact_kind" => "phase16i-exact-head-internal-beta-candidate",
    "generated_at_utc" => string(now(UTC)),
    "runtime_package" => "ProcessBigraphs",
    "runtime_version" => project["version"],
    "internal_beta" => false,
    "public_release" => false,
    "qualified_head_commit" => head,
    "qualified_tree" => tree,
    "base_ref" => base_ref,
    "base_commit" => base_commit,
    "merge_base" => merge_base,
    "prospective_merge_tree" => merge_tree,
    "tree_identity_verified" => true,
    "dirty_state" => "clean",
    "ci" => Dict(
        "repository" => get(ENV, "GITHUB_REPOSITORY", "local"),
        "run_id" => get(ENV, "GITHUB_RUN_ID", "local"),
        "run_attempt" => get(ENV, "GITHUB_RUN_ATTEMPT", "local"),
        "job" => get(ENV, "GITHUB_JOB", "local"),
        "sha" => get(ENV, "GITHUB_SHA", head),
        "required_jobs" => [
            "project",
            "packages",
            "integration",
            "phase15c_oracle",
            "phase15c_candidate",
            "cpu_macos_arm64",
            "cpu_linux_x64",
            "phase16i_candidate",
            "required",
        ],
    ),
    "environment" => Dict(
        "julia_version" => string(VERSION),
        "architecture" => string(Sys.ARCH),
        "kernel" => string(Sys.KERNEL),
        "word_size" => Sys.WORD_SIZE,
        "cpu_model" => isempty(cpu) ? "unavailable" : cpu[1].model,
        "cpu_threads" => Sys.CPU_THREADS,
        "total_memory_bytes" => Sys.total_memory(),
    ),
    "qualification" => Dict(
        "required_rows" => ledger["required_row_count"],
        "qualified_rows" =>
            count(row -> row["status"] == "qualified", ledger["requirements"]),
        "oracle_passing_rows" =>
            count(row -> row["status"] == "oracle_passing",
                ledger["requirements"]),
        "closure_status" => ledger["closure_status"],
        "all_rows_at_least_oracle_passing" => true,
        "metadata_only_attestation_required" => true,
    ),
    "hardware" => Dict(
        "phase16c_evidence_sha256" => file_sha256(joinpath(
            ROOT, "design", "evidence",
            "process-bigraph-phase16c-evidence-v1.toml")),
        "workflow_run_id" => phase16c["ci"]["run_id"],
        "workflow_head_sha" => phase16c["ci"]["head_sha"],
        "metal_hardware_id" => phase16c["metal"]["hardware_id"],
        "rocm_hardware_id" => phase16c["rocm"]["hardware_id"],
        "metal_exact_head" => phase16c["hardware"]["metal_exact_head"],
        "rocm_exact_head" => phase16c["hardware"]["rocm_exact_head"],
        "native_field_source_sha256" =>
            phase16c["provenance"]["native_field_source_sha256"],
    ),
    "performance" => Dict(
        "report_sha256" => file_sha256(PERFORMANCE_PATH),
        "evidence_id" => performance["evidence_id"],
        "events" => performance["events"],
        "repetitions" => performance["repetitions"],
        "plan_identity_equal" => performance["plan_identity_equal"],
        "all_frozen_budgets_pass" => all(values(performance["checks"])),
        "warm_time_ratio" => performance["warm_execution"]["time_ratio"],
        "warm_allocation_ratio" =>
            performance["warm_execution"]["allocation_ratio"],
        "fastest_runtime_claim" => false,
    ),
    "api" => Dict(
        "exported_internal_beta_names" =>
            length(api["planned_internal_beta_exports"]),
        "qualified_name_expert_names" =>
            length(api["planned_public_unexported"]),
        "constructor_spelling_stable" =>
            api["policy"]["constructor_spelling_stable_at_internal_beta"],
        "semantic_identity_stable" =>
            api["policy"]["semantic_identity_stable_at_internal_beta"],
    ),
    "backend_matrix" => Dict(
        row["id"] => Dict(
            backend => row[backend]
            for backend in ("CPU", "Metal", "ROCm", "CUDA")
        )
        for row in matrix["envelopes"]
    ),
    "evidence_manifests" => Dict(
        path => file_sha256(joinpath(ROOT, path)) for path in evidence_files
    ),
    "documentation" => Dict(
        path => file_sha256(joinpath(ROOT, path))
        for path in documentation_files
    ),
    "dependency_resolution" => Dict(
        path => file_sha256(joinpath(ROOT, path))
        for path in resolution_files
    ),
    "commands" => [
        "julia --project=. -e 'using Pkg; Pkg.test()'",
        "julia --project=lib/CorePotts -e 'using Pkg; Pkg.test()'",
        "julia --project=lib/ProcessBigraphs -e 'using Pkg; Pkg.test()'",
        "julia --project=integration integration/runtests.jl",
        "julia scripts/process-bigraph-phase16-docs.jl --check",
        "julia scripts/process-bigraph-phase16i-check.jl",
        "julia --project=benchmark -e 'using Pkg; Pkg.instantiate()'",
        "julia --project=benchmark benchmark/phase16hc_authoring_qualification.jl",
    ],
    "limitations" => entry["scope"]["excluded"],
)

mkpath(dirname(OUTPUT))
open(OUTPUT, "w") do io
    TOML.print(io, artifact; sorted=true)
end
println("Phase 16.I exact-head candidate artifact written to $(OUTPUT)")
println("sha256=$(file_sha256(OUTPUT))")

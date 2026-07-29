#!/usr/bin/env julia

using Dates
using SHA
using TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
length(ARGS) == 2 ||
    error("usage: process-bigraph-phase15c-candidate.jl OUTPUT GUARDRAIL_REPORT")
output = abspath(ARGS[1])
guardrail_path = abspath(ARGS[2])
ledger = TOML.parsefile(joinpath(
    ROOT, "spec", "process-bigraph-phase15c-qualification-v1.toml"))
entry = TOML.parsefile(joinpath(
    ROOT, "spec", "process-bigraph-phase15c-entry-v1.toml"))
project = TOML.parsefile(joinpath(
    ROOT, "lib", "ProcessBigraphs", "Project.toml"))
guardrails = TOML.parsefile(guardrail_path)

file_sha256(path) = bytes2hex(sha256(read(path)))

git(args...) = readchomp(`git -C $(ROOT) $(args)`)
head = git("rev-parse", "HEAD")
tree = git("rev-parse", "HEAD^{tree}")

artifact = Dict(
    "schema_version" => "1.0.0",
    "artifact_kind" => "phase15c-implementation-candidate",
    "generated_at_utc" => string(now(UTC)),
    "runtime_package" => "ProcessBigraphs",
    "runtime_version" => project["version"],
    "qualified_head_commit" => head,
    "qualified_tree" => tree,
    "ci_run_id" => get(ENV, "GITHUB_RUN_ID", "local"),
    "ci_run_attempt" => get(ENV, "GITHUB_RUN_ATTEMPT", "local"),
    "ci_repository" => get(ENV, "GITHUB_REPOSITORY", "local"),
    "ci_job_id" => get(ENV, "GITHUB_JOB", "local"),
    "required_ci_jobs" => [
        "project",
        "packages",
        "integration",
        "phase15c_oracle",
        "phase15c_candidate",
        "required",
    ],
    "julia_version" => string(VERSION),
    "julia_arch" => string(Sys.ARCH),
    "julia_kernel" => string(Sys.KERNEL),
    "source_pins" => Dict(
        "process_bigraph" =>
            "305ea826191e9f897f0c6e207bc303bbc44a9eef",
        "bigraph_schema" =>
            "4b208e13620e09e877af52ea07273bc9429a3a17",
    ),
    "fixture_source" => Dict(
        "path" =>
            "lib/ProcessBigraphs/test/specification_oracle/fixtures.toml",
        "sha256" => file_sha256(joinpath(
            ROOT,
            "lib",
            "ProcessBigraphs",
            "test",
            "specification_oracle",
            "fixtures.toml",
        )),
        "implementation_path" =>
            "lib/ProcessBigraphs/test/phase15c/fixtures.jl",
        "implementation_sha256" => file_sha256(joinpath(
            ROOT,
            "lib",
            "ProcessBigraphs",
            "test",
            "phase15c",
            "fixtures.jl",
        )),
    ),
    "fixture_fingerprints" => Dict(
        id => bytes2hex(sha256(codeunits(join((
            "phase15c-fixture-v1",
            id,
            file_sha256(joinpath(
                ROOT,
                "lib",
                "ProcessBigraphs",
                "test",
                "specification_oracle",
                "fixtures.toml",
            )),
            file_sha256(joinpath(
                ROOT,
                "lib",
                "ProcessBigraphs",
                "test",
                "phase15c",
                "fixtures.jl",
            )),
        ), '\0'))))
        for id in ledger["fixtures"]
    ),
    "model_fingerprints" => guardrails["model_identity"],
    "dependency_resolution" => guardrails["dependency_resolution"],
    "qualification_ledger" => Dict(
        "path" => "spec/process-bigraph-phase15c-qualification-v1.toml",
        "sha256" => file_sha256(joinpath(
            ROOT, "spec", "process-bigraph-phase15c-qualification-v1.toml")),
    ),
    "runtime_project" => Dict(
        "path" => "lib/ProcessBigraphs/Project.toml",
        "sha256" => file_sha256(joinpath(
            ROOT, "lib", "ProcessBigraphs", "Project.toml")),
        "compat" => get(project, "compat", Dict()),
        "dependencies" => get(project, "deps", Dict()),
    ),
    "totals" => Dict(
        key => ledger[key] for key in (
            "fixture_count",
            "method_count",
            "authoring_path_count",
            "invariance_dimension_count",
            "performance_guardrail_count",
            "failure_stage_count",
            "mutation_target_count",
            "restart_cut_count",
            "phase15c_assertion_count",
            "historical_assertion_count",
            "aqua_assertion_count",
            "oracle_differential_row_count",
            "oracle_unit_assertion_count",
            "mutation_assertion_count",
        )
    ),
    "assertion_groups" => ledger["assertion_groups"],
    "qualification_methods" => ledger["methods"],
    "qualified_feature_scope" => entry["scope"],
    "failure_stages" => ledger["failure_stages"],
    "mutation_targets_killed" => ledger["mutation_targets"],
    "restart_fixtures" => ledger["restart_fixtures"],
    "performance_guardrails" => Dict(
        "declared" => ledger["performance_guardrails"],
        "report_sha256" => bytes2hex(sha256(read(guardrail_path))),
        "results" => guardrails["guardrails"],
        "measurements" => guardrails["measurements"],
        "fastest_runtime_claim" => guardrails["fastest_runtime_claim"],
    ),
    "limitations" => [
        "immutable topology only",
        "serial executor only",
        "CPU semantic qualification only",
        "exact-compatible settled-boundary restore only",
        "no scientific adapters or Potts cutover",
        "not a public release",
    ],
)

mkpath(dirname(output))
open(output, "w") do io
    TOML.print(io, artifact; sorted=true)
end
println("Phase 15.C candidate artifact written to $(output)")
println("sha256=$(bytes2hex(sha256(read(output))))")

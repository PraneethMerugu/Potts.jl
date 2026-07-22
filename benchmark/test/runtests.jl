using Test
using TOML

include(joinpath(@__DIR__, "..", "src", "Phase12Comparison.jl"))
using .Phase12Comparison

function synthetic_record(process_id; steady = 1.0, first_mcs = 2.0,
        memory = 1000, backend = "cpu", hardware_id = "cpu-arm64-reference",
        fingerprint = "model-fingerprint", device_allocations = 0,
        julia_threads = 1)
    return Dict(
        "schema_version" => PHASE12_SCHEMA_VERSION,
        "record_kind" => "phase12-performance-run",
        "comparison_identity" => Dict(
            "contract_version" => PHASE12_CONTRACT_VERSION,
            "workload_set_version" => "paper-core-1.0.0",
            "harness_tree_sha256" => "harness-tree",
            "backend" => backend,
            "hardware_id" => hardware_id,
            "julia_version" => "1.12.6",
            "architecture" => "aarch64",
            "os" => "Darwin",
            "julia_threads" => julia_threads,
            "precision" => "Float32",
            "profile" => "full",
            "tuning_policy" => "conservative",
        ),
        "run" => Dict("process_id" => process_id),
        "provenance" => Dict(
            "implementation_commit" => "baseline-implementation",
            "implementation_tree_sha256" => "tree",
            "harness_commit" => "harness",
            "git_dirty" => false,
        ),
        "workloads" => Dict(
            "migration_2d" => Dict(
                "family" => "single_cell_migration",
                "algorithm" => "SequentialCPM",
                "semantic_fingerprint" => fingerprint,
                "dimension_count" => 2,
                "dimensions" => [128, 128],
                "sites" => 128^2,
                "timed_mcs" => 10,
                "declared_lifecycle_observation_per_mcs" => false,
                "steady_median_seconds_per_mcs" => steady,
                "first_mcs_seconds" => first_mcs,
                "steady_median_host_allocated_bytes_per_mcs" => 0.0,
                "warm_execution_metrics" => Dict(
                    "host_allocations" => 0,
                    "device_allocations" => device_allocations,
                    "host_to_device_transfers" => 0,
                    "host_synchronizations" => 0,
                    "device_to_host_transfers" => 0,
                ),
                "residency" => Dict("backend_resident_bytes" => memory),
            ),
        ),
    )
end

@testset "Phase 12 CPU scaling summary" begin
    groups = Dict{Int, Vector{Any}}()
    for threads in (1, 2, 4)
        groups[threads] = Any[synthetic_record(
            "scaling-$threads-$process";
            steady = 1 / min(threads, 2),
            julia_threads = threads,
            hardware_id = "cpu-arm64-reference-$threads-physical-threads")
            for process in 1:3]
    end
    result = summarize_cpu_scaling(groups)
    @test result["comparable"]
    @test result["thread_counts"] == [1, 2, 4]
    @test result["scaling"]["2"]["algorithm_geometric_mean_speedups"][
        "SequentialCPM"] ≈ 2
    @test result["scaling"]["4"]["workloads"]["migration_2d"][
        "parallel_efficiency"] ≈ 0.5

    wrong_commit = deepcopy(groups)
    wrong_commit[4][1]["provenance"]["implementation_commit"] = "other"
    result = summarize_cpu_scaling(wrong_commit)
    @test !result["comparable"]
    @test any(contains("implementation commits"), result["issues"])

    result = summarize_cpu_scaling(Dict(2 => groups[2]))
    @test !result["comparable"]
    @test any(contains("requires one thread"), result["issues"])
end

function synthetic_cold_record(process_id; scale = 1.0, hardware_id = "cpu-arm64-reference")
    metrics = Dict(key => scale * (index / 10) for (index, key) in enumerate((
        "backend_import_seconds", "package_import_seconds", "model_construction_seconds",
        "normalization_seconds", "lowering_seconds", "problem_construction_seconds",
        "initialization_seconds", "first_mcs_seconds")))
    return Dict(
        "schema_version" => PHASE12_SCHEMA_VERSION,
        "record_kind" => "phase12-cold-run",
        "comparison_identity" => Dict(
            "contract_version" => PHASE12_CONTRACT_VERSION,
            "cold_workload_version" => "differential-adhesion-1.0.0",
            "cold_harness_tree_sha256" => "cold-harness",
            "backend" => "cpu",
            "hardware_id" => hardware_id,
            "julia_version" => "1.12.6",
            "architecture" => "aarch64",
            "os" => "Darwin",
            "julia_threads" => 1,
            "precision" => "Float32",
            "algorithm" => "SequentialCPM",
        ),
        "run" => Dict("process_id" => process_id),
        "provenance" => Dict(
            "implementation_commit" => "baseline-implementation",
            "implementation_tree_sha256" => "tree",
            "harness_commit" => "harness",
            "git_dirty" => false,
        ),
        "metrics" => metrics,
    )
end

function synthetic_precompile_record(process_id)
    return Dict(
        "schema_version" => PHASE12_SCHEMA_VERSION,
        "record_kind" => "phase12-precompile-run",
        "comparison_identity" => Dict(
            "contract_version" => PHASE12_CONTRACT_VERSION,
            "precompile_workload_version" => "isolated-environment-1.0.0",
            "precompile_harness_tree_sha256" => "precompile-harness",
            "backend" => "cpu",
            "hardware_id" => "cpu-arm64-reference",
            "julia_version" => "1.12.6",
            "architecture" => "aarch64",
            "os" => "Darwin",
            "julia_threads" => 1,
        ),
        "run" => Dict(
            "process_id" => process_id,
            "network_policy" => "offline",
        ),
        "provenance" => Dict(
            "implementation_commit" => "baseline-implementation",
            "implementation_tree_sha256" => "tree",
            "harness_commit" => "harness",
            "git_dirty" => false,
        ),
        "metrics" => Dict(
            "base_environment_precompile_seconds" => 10.0,
            "backend_environment_precompile_seconds" => 0.0,
            "total_precompile_seconds" => 10.0,
            "isolated_depot_bytes" => 1000,
        ),
    )
end

@testset "Phase 12 comparison contract" begin
    baseline = [synthetic_record("baseline-$index"; steady = 1 + 0.01index)
                for index in 1:3]
    faster = [synthetic_record("faster-$index"; steady = 0.9 + 0.01index,
                  first_mcs = 1.9, memory = 1000)
              for index in 1:3]
    result = compare_record_groups(baseline, faster)
    @test result["comparable"]
    @test result["passed"]
    @test result["algorithm_geometric_mean_steady_seconds_ratios"]["SequentialCPM"] < 1
    @test !result["paired_evidence"]["available"]
    io = IOBuffer()
    TOML.print(io, result; sorted = true)
    @test !isempty(take!(io))

    regression = [synthetic_record("regression-$index"; steady = 1.2,
                      first_mcs = 2.0, memory = 1000)
                  for index in 1:3]
    result = compare_record_groups(baseline, regression)
    @test result["comparable"]
    @test !result["passed"]
    @test !result["workloads"]["migration_2d"]["passed"]

    wrong_hardware = deepcopy(faster)
    for record in wrong_hardware
        record["comparison_identity"]["hardware_id"] = "different-host"
    end
    result = compare_record_groups(baseline, wrong_hardware)
    @test !result["comparable"]
    @test any(contains("hardware_id"), result["issues"])

    wrong_model = deepcopy(faster)
    for record in wrong_model
        record["workloads"]["migration_2d"]["semantic_fingerprint"] = "different"
    end
    result = compare_record_groups(baseline, wrong_model)
    @test !result["comparable"]
    @test any(contains("semantic_fingerprint"), result["issues"])

    allocating = [synthetic_record("allocating-$index"; steady = 0.8,
                      device_allocations = 1)
                  for index in 1:3]
    result = compare_record_groups(baseline, allocating)
    @test result["comparable"]
    @test !result["passed"]
    @test !isempty(result["residency_issues"])

    duplicate_process = [synthetic_record("same") for _ in 1:3]
    result = compare_record_groups(baseline, duplicate_process)
    @test !result["comparable"]
    @test any(contains("repeated process_id"), result["issues"])

    wrong_harness = deepcopy(faster)
    for record in wrong_harness
        record["comparison_identity"]["harness_tree_sha256"] = "different-harness"
    end
    result = compare_record_groups(baseline, wrong_harness)
    @test !result["comparable"]
    @test any(contains("harness_tree_sha256"), result["issues"])

    dirty = deepcopy(faster)
    dirty[1]["provenance"]["git_dirty"] = true
    result = compare_record_groups(baseline, dirty)
    @test !result["comparable"]
    @test any(contains("clean worktree"), result["issues"])

    hidden_transfer = deepcopy(faster)
    hidden_transfer[1]["workloads"]["migration_2d"]["warm_execution_metrics"][
        "device_to_host_transfers"] = 1
    result = compare_record_groups(baseline, hidden_transfer)
    @test result["comparable"]
    @test !result["passed"]
    @test any(contains("device_to_host_transfers"), result["residency_issues"])

    mixed_baseline = deepcopy(baseline)
    mixed_candidate = deepcopy(faster)
    for record in mixed_baseline
        lottery = deepcopy(record["workloads"]["migration_2d"])
        lottery["algorithm"] = "LotteryCPM"
        lottery["steady_median_seconds_per_mcs"] = 1.0
        record["workloads"]["lottery_migration_2d"] = lottery
    end
    for record in mixed_candidate
        lottery = deepcopy(record["workloads"]["migration_2d"])
        lottery["algorithm"] = "LotteryCPM"
        lottery["steady_median_seconds_per_mcs"] = 1.2
        record["workloads"]["lottery_migration_2d"] = lottery
    end
    result = compare_record_groups(mixed_baseline, mixed_candidate)
    @test !result["passed"]
    @test result["algorithm_geometric_mean_steady_seconds_ratios"]["SequentialCPM"] < 1
    @test result["algorithm_geometric_mean_steady_seconds_ratios"]["LotteryCPM"] > 1

    paired_baseline = Any[]
    paired_candidate = Any[]
    for pair in 1:4
        baseline_ordinal, candidate_ordinal = isodd(pair) ? (1, 2) : (2, 1)
        push!(paired_baseline, synthetic_record(
            "paired-run-paired-baseline-pair$pair-ordinal$baseline_ordinal";
            steady = 1.0))
        push!(paired_candidate, synthetic_record(
            "paired-run-paired-candidate-pair$pair-ordinal$candidate_ordinal";
            steady = 0.9))
    end
    result = compare_record_groups(paired_baseline, paired_candidate;
        minimum_processes = 4)
    @test result["passed"]
    @test result["paired_evidence"]["available"]
    @test result["paired_evidence"]["comparable"]
    @test result["paired_evidence"]["pairs"] == 4
    @test result["paired_evidence"]["orders"] == [
        "baseline/candidate", "candidate/baseline",
        "baseline/candidate", "candidate/baseline"]
    @test result["paired_evidence"][
        "algorithm_geometric_mean_steady_seconds_ratios"]["SequentialCPM"] ≈ 0.9

    @test_throws ArgumentError aggregate_records(baseline[1:2])
end

@testset "Phase 12 cold comparison contract" begin
    baseline = [synthetic_cold_record("baseline-cold-$index") for index in 1:3]
    faster = [synthetic_cold_record("faster-cold-$index"; scale = 0.9) for index in 1:3]
    result = compare_cold_record_groups(baseline, faster)
    @test result["comparable"]
    @test result["passed"]
    @test all(<(1), values(result["metric_ratios"]))

    slower = [synthetic_cold_record("slower-cold-$index"; scale = 1.2) for index in 1:3]
    result = compare_cold_record_groups(baseline, slower)
    @test result["comparable"]
    @test !result["passed"]

    other_host = [synthetic_cold_record("other-cold-$index";
                      hardware_id = "other-host") for index in 1:3]
    result = compare_cold_record_groups(baseline, other_host)
    @test !result["comparable"]
    @test any(contains("hardware_id"), result["issues"])

    result = compare_cold_record_groups(baseline[1:2], faster)
    @test !result["comparable"]
    @test any(contains("at least 3"), result["issues"])
end

@testset "Phase 12 precompile record contract" begin
    record = synthetic_precompile_record("precompile-1")
    @test isempty(validate_precompile_record(record))

    online = deepcopy(record)
    online["run"]["network_policy"] = "allow"
    @test any(contains("offline"), validate_precompile_record(online))

    dirty = deepcopy(record)
    dirty["provenance"]["git_dirty"] = true
    @test any(contains("clean worktree"), validate_precompile_record(dirty))

    missing = deepcopy(record)
    delete!(missing["metrics"], "isolated_depot_bytes")
    @test any(contains("isolated_depot_bytes"), validate_precompile_record(missing))

    reused = deepcopy(record)
    reused["metrics"]["base_environment_precompile_seconds"] = 0.0
    reused["metrics"]["total_precompile_seconds"] = 0.0
    reused["metrics"]["isolated_depot_bytes"] = 0
    reused_issues = validate_precompile_record(reused)
    @test any(contains("fresh depot"), reused_issues)
    @test any(contains("fresh compiled cache"), reused_issues)

    baseline = [synthetic_precompile_record("baseline-precompile-$index") for index in 1:3]
    faster = deepcopy(baseline)
    for (index, candidate) in pairs(faster)
        candidate["run"]["process_id"] = "candidate-precompile-$index"
        for key in keys(candidate["metrics"])
            candidate["metrics"][key] *= 0.9
        end
    end
    comparison = compare_precompile_record_groups(baseline, faster)
    @test comparison["comparable"]
    @test comparison["passed"]

    larger = deepcopy(faster)
    for candidate in larger
        candidate["metrics"]["isolated_depot_bytes"] = 1200
    end
    comparison = compare_precompile_record_groups(baseline, larger)
    @test comparison["comparable"]
    @test !comparison["passed"]
end

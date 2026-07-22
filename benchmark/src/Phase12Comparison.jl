module Phase12Comparison

using Statistics
using TOML

export PHASE12_SCHEMA_VERSION, PHASE12_CONTRACT_VERSION
export load_record, validate_record, compatibility_issues
export aggregate_records, compare_record_groups, paired_evidence, print_comparison
export summarize_cpu_scaling
export load_cold_record, validate_cold_record, compare_cold_record_groups
export load_precompile_record, validate_precompile_record
export compare_precompile_record_groups

const PHASE12_SCHEMA_VERSION = "3.0.0"
const PHASE12_CONTRACT_VERSION = "1.0.0"

const COMPARISON_IDENTITY_KEYS = (
    "contract_version",
    "workload_set_version",
    "harness_tree_sha256",
    "backend",
    "hardware_id",
    "julia_version",
    "architecture",
    "os",
    "julia_threads",
    "precision",
    "profile",
    "tuning_policy",
)

const WORKLOAD_IDENTITY_KEYS = (
    "family",
    "algorithm",
    "semantic_fingerprint",
    "dimension_count",
    "dimensions",
    "sites",
    "timed_mcs",
    "declared_lifecycle_observation_per_mcs",
)

const REQUIRED_WORKLOAD_KEYS = (
    "steady_median_seconds_per_mcs",
    "first_mcs_seconds",
    "steady_median_host_allocated_bytes_per_mcs",
    "warm_execution_metrics",
    "residency",
)

const ZERO_WARM_METRICS = (
    "host_allocations",
    "device_allocations",
    "host_to_device_transfers",
)

const COLD_IDENTITY_KEYS = (
    "contract_version",
    "cold_workload_version",
    "cold_harness_tree_sha256",
    "backend",
    "hardware_id",
    "julia_version",
    "architecture",
    "os",
    "julia_threads",
    "precision",
    "algorithm",
)

const COLD_METRIC_KEYS = (
    "backend_import_seconds",
    "package_import_seconds",
    "model_construction_seconds",
    "normalization_seconds",
    "lowering_seconds",
    "problem_construction_seconds",
    "initialization_seconds",
    "first_mcs_seconds",
)

const PRECOMPILE_IDENTITY_KEYS = (
    "contract_version",
    "precompile_workload_version",
    "precompile_harness_tree_sha256",
    "backend",
    "hardware_id",
    "julia_version",
    "architecture",
    "os",
    "julia_threads",
)

const PRECOMPILE_METRIC_KEYS = (
    "base_environment_precompile_seconds",
    "backend_environment_precompile_seconds",
    "total_precompile_seconds",
    "isolated_depot_bytes",
)

const PAIRED_PROCESS_ID_PATTERN =
    r"^(.*)-paired-(baseline|candidate)-pair([1-9][0-9]*)-ordinal([12])$"

function load_record(path::AbstractString)
    record = TOML.parsefile(path)
    issues = validate_record(record)
    isempty(issues) || throw(ArgumentError(
        "invalid Phase 12 record $(abspath(path)):\n- " * join(issues, "\n- ")))
    return record
end

function _table(record, key, issues, context)
    value = get(record, key, nothing)
    value isa AbstractDict || push!(issues, "$context requires table `$key`")
    return value isa AbstractDict ? value : Dict{String, Any}()
end

function _finite_nonnegative(value)
    return value isa Real && isfinite(value) && value >= 0
end

function validate_record(record::AbstractDict)
    issues = String[]
    get(record, "schema_version", nothing) == PHASE12_SCHEMA_VERSION || push!(issues,
        "schema_version must be $PHASE12_SCHEMA_VERSION")
    get(record, "record_kind", nothing) == "phase12-performance-run" || push!(issues,
        "record_kind must be phase12-performance-run")
    identity = _table(record, "comparison_identity", issues, "record")
    for key in COMPARISON_IDENTITY_KEYS
        haskey(identity, key) || push!(issues, "comparison_identity is missing `$key`")
    end
    get(identity, "contract_version", nothing) == PHASE12_CONTRACT_VERSION || push!(issues,
        "contract_version must be $PHASE12_CONTRACT_VERSION")
    run = _table(record, "run", issues, "record")
    haskey(run, "process_id") || push!(issues, "run is missing `process_id`")
    provenance = _table(record, "provenance", issues, "record")
    for key in ("implementation_commit", "implementation_tree_sha256", "harness_commit",
            "git_dirty")
        haskey(provenance, key) || push!(issues, "provenance is missing `$key`")
    end
    get(provenance, "git_dirty", true) === false || push!(issues,
        "authoritative Phase 12 records require a clean worktree")
    get(provenance, "harness_git_dirty", false) === false || push!(issues,
        "authoritative Phase 12 records require a clean harness worktree")
    workloads = _table(record, "workloads", issues, "record")
    isempty(workloads) && push!(issues, "record contains no workloads")
    for (name, workload) in workloads
        workload isa AbstractDict || begin
            push!(issues, "workload `$name` must be a table")
            continue
        end
        for key in WORKLOAD_IDENTITY_KEYS
            haskey(workload, key) || push!(issues, "workload `$name` is missing `$key`")
        end
        for key in REQUIRED_WORKLOAD_KEYS
            haskey(workload, key) || push!(issues, "workload `$name` is missing `$key`")
        end
        for key in ("steady_median_seconds_per_mcs", "first_mcs_seconds",
                "steady_median_host_allocated_bytes_per_mcs")
            haskey(workload, key) && !_finite_nonnegative(workload[key]) && push!(issues,
                "workload `$name` metric `$key` must be finite and non-negative")
        end
        get(workload, "timed_mcs", 0) isa Integer && workload["timed_mcs"] > 0 ||
            push!(issues, "workload `$name` timed_mcs must be a positive integer")
        get(workload, "declared_lifecycle_observation_per_mcs", nothing) isa Bool ||
            push!(issues,
                "workload `$name` declared_lifecycle_observation_per_mcs must be Boolean")
        warm = get(workload, "warm_execution_metrics", Dict{String, Any}())
        warm isa AbstractDict || push!(issues,
            "workload `$name` warm_execution_metrics must be a table")
        residency = get(workload, "residency", Dict{String, Any}())
        residency isa AbstractDict || push!(issues,
            "workload `$name` residency must be a table")
        if residency isa AbstractDict
            bytes = get(residency, "backend_resident_bytes", nothing)
            _finite_nonnegative(bytes) || push!(issues,
                "workload `$name` residency requires non-negative backend_resident_bytes")
        end
    end
    return issues
end

function _identity_issues(left, right, keys, context)
    issues = String[]
    for key in keys
        left_value = get(left, key, nothing)
        right_value = get(right, key, nothing)
        isequal(left_value, right_value) || push!(issues,
            "$context differs at `$key`: $(repr(left_value)) != $(repr(right_value))")
    end
    return issues
end

function compatibility_issues(baseline::AbstractDict, candidate::AbstractDict)
    issues = vcat(validate_record(baseline), validate_record(candidate))
    isempty(issues) || return unique!(issues)
    append!(issues, _identity_issues(
        baseline["comparison_identity"], candidate["comparison_identity"],
        COMPARISON_IDENTITY_KEYS, "comparison identity"))
    baseline_names = sort!(collect(keys(baseline["workloads"])))
    candidate_names = sort!(collect(keys(candidate["workloads"])))
    baseline_names == candidate_names || push!(issues,
        "workload sets differ: $(repr(baseline_names)) != $(repr(candidate_names))")
    for name in intersect(baseline_names, candidate_names)
        append!(issues, _identity_issues(
            baseline["workloads"][name], candidate["workloads"][name],
            WORKLOAD_IDENTITY_KEYS, "workload `$name` identity"))
    end
    return issues
end

function _group_issues(records::AbstractVector, label::String)
    issues = String[]
    isempty(records) && return ["$label group is empty"]
    for (index, record) in pairs(records)
        append!(issues, ("$label record $index: $issue" for issue in validate_record(record)))
    end
    isempty(issues) || return issues
    first_record = first(records)
    process_ids = String[]
    for (index, record) in pairs(records)
        append!(issues, ("$label record $index: $issue" for issue in
            compatibility_issues(first_record, record)))
        push!(process_ids, string(record["run"]["process_id"]))
    end
    length(unique(process_ids)) == length(process_ids) || push!(issues,
        "$label group contains repeated process_id values")
    return unique!(issues)
end

function _paired_process_metadata(record::AbstractDict)
    process_id = string(record["run"]["process_id"])
    matched = match(PAIRED_PROCESS_ID_PATTERN, process_id)
    isnothing(matched) && return nothing
    return (
        run_id = matched.captures[1],
        subject = matched.captures[2],
        pair = parse(Int, matched.captures[3]),
        ordinal = parse(Int, matched.captures[4]),
    )
end

"""
    paired_evidence(baseline, candidate)

Validate and summarize an optional counterbalanced paired schedule.  Ordinary independent
record groups remain valid; when every process id has the paired identity emitted by
`paired_repeat.jl`, this reports pair-level candidate/baseline steady-time ratios without
changing the release gate evaluated by `compare_record_groups`.
"""
function paired_evidence(baseline::AbstractVector, candidate::AbstractVector)
    all_records = vcat(collect(baseline), collect(candidate))
    metadata = _paired_process_metadata.(all_records)
    all(isnothing, metadata) && return nothing
    any(isnothing, metadata) && return Dict(
        "comparable" => false,
        "issues" => ["paired evidence mixes paired and unpaired process identities"],
    )

    entries = Dict{Int, Dict{String, Any}}()
    issues = String[]
    run_ids = String[]
    for (expected_subject, records) in (("baseline", baseline), ("candidate", candidate))
        for record in records
            meta = _paired_process_metadata(record)::NamedTuple
            push!(run_ids, meta.run_id)
            process_id = record["run"]["process_id"]
            meta.subject == expected_subject || push!(issues,
                "paired process $process_id labels itself `$(meta.subject)` but belongs to `$expected_subject`")
            pair = get!(entries, meta.pair, Dict{String, Any}())
            haskey(pair, meta.subject) && push!(issues,
                "paired schedule contains duplicate $(meta.subject) record for pair $(meta.pair)")
            pair[meta.subject] = (record = record, ordinal = meta.ordinal)
        end
    end
    length(unique(run_ids)) == 1 || push!(issues,
        "paired records must share one run identity")

    orders = String[]
    for pair_index in sort!(collect(keys(entries)))
        pair = entries[pair_index]
        haskey(pair, "baseline") && haskey(pair, "candidate") || begin
            push!(issues, "paired schedule is missing a subject for pair $pair_index")
            continue
        end
        baseline_ordinal = pair["baseline"].ordinal
        candidate_ordinal = pair["candidate"].ordinal
        Set((baseline_ordinal, candidate_ordinal)) == Set((1, 2)) || push!(issues,
            "paired schedule pair $pair_index must contain ordinals 1 and 2")
        push!(orders, baseline_ordinal == 1 ? "baseline/candidate" : "candidate/baseline")
    end
    all(orders[index] != orders[index + 1] for index in 1:(length(orders) - 1)) ||
        push!(issues, "paired schedule must alternate the first subject")
    isempty(issues) || return Dict("comparable" => false, "issues" => unique!(issues))

    pair_indices = sort!(collect(keys(entries)))
    workload_ratios = Dict{String, Vector{Float64}}()
    algorithm_ratios = Dict{String, Vector{Float64}}()
    for pair_index in pair_indices
        before = entries[pair_index]["baseline"].record
        after = entries[pair_index]["candidate"].record
        for name in sort!(collect(keys(before["workloads"])))
            baseline_workload = before["workloads"][name]
            candidate_workload = after["workloads"][name]
            ratio = _ratio(candidate_workload["steady_median_seconds_per_mcs"],
                baseline_workload["steady_median_seconds_per_mcs"])
            push!(get!(workload_ratios, name, Float64[]), ratio)
            push!(get!(algorithm_ratios, baseline_workload["algorithm"], Float64[]), ratio)
        end
    end
    return Dict(
        "comparable" => true,
        "pairs" => length(pair_indices),
        "orders" => orders,
        "workload_steady_seconds_ratios" => workload_ratios,
        "workload_geometric_mean_steady_seconds_ratios" => Dict(
            name => exp(mean(log, ratios)) for (name, ratios) in workload_ratios),
        "algorithm_geometric_mean_steady_seconds_ratios" => Dict(
            name => exp(mean(log, ratios)) for (name, ratios) in algorithm_ratios),
    )
end

_median_metric(records, workload, key) =
    median(Float64(record["workloads"][workload][key]) for record in records)

_median_residency(records, workload) = median(Float64(
    record["workloads"][workload]["residency"]["backend_resident_bytes"])
    for record in records)

function aggregate_records(records::AbstractVector; minimum_processes::Int = 3)
    minimum_processes > 0 || throw(ArgumentError("minimum_processes must be positive"))
    issues = _group_issues(records, "aggregate")
    isempty(issues) || throw(ArgumentError(join(issues, "\n")))
    length(records) >= minimum_processes || throw(ArgumentError(
        "aggregate requires at least $minimum_processes independent processes; got $(length(records))"))
    workloads = Dict{String, Any}()
    for name in sort!(collect(keys(first(records)["workloads"])))
        workloads[name] = Dict(
            "algorithm" => first(records)["workloads"][name]["algorithm"],
            "process_steady_seconds_per_mcs" => [Float64(
                record["workloads"][name]["steady_median_seconds_per_mcs"])
                for record in records],
            "median_steady_seconds_per_mcs" =>
                _median_metric(records, name, "steady_median_seconds_per_mcs"),
            "median_first_mcs_seconds" =>
                _median_metric(records, name, "first_mcs_seconds"),
            "median_host_allocated_bytes_per_mcs" =>
                _median_metric(records, name, "steady_median_host_allocated_bytes_per_mcs"),
            "median_backend_resident_bytes" => _median_residency(records, name),
        )
    end
    return Dict(
        "processes" => length(records),
        "comparison_identity" => deepcopy(first(records)["comparison_identity"]),
        "implementation_commit" => first(records)["provenance"]["implementation_commit"],
        "workloads" => workloads,
    )
end

function _cpu_system_id(hardware_id::AbstractString)
    return replace(hardware_id,
        r"-[1-9][0-9]*-(?:pinned-)?physical-threads$" => "")
end

"""Summarize separately qualified fixed-thread CPU groups as scaling evidence."""
function summarize_cpu_scaling(groups::AbstractDict; minimum_processes::Int = 3)
    minimum_processes > 0 || throw(ArgumentError("minimum_processes must be positive"))
    threads = sort!(Int.(collect(keys(groups))))
    isempty(threads) && return Dict(
        "comparable" => false, "issues" => ["CPU scaling matrix is empty"])
    first(threads) == 1 || return Dict(
        "comparable" => false, "issues" => ["CPU scaling matrix requires one thread"])
    all(>(0), threads) || return Dict(
        "comparable" => false, "issues" => ["CPU thread counts must be positive"])

    issues = String[]
    aggregates = Dict{Int, Any}()
    reference = nothing
    comparison_keys = filter(
        key -> !(key in ("hardware_id", "julia_threads")), COMPARISON_IDENTITY_KEYS)
    for thread_count in threads
        records = groups[thread_count]
        append!(issues, ("$thread_count threads: $issue" for issue in
            _group_issues(records, "$thread_count-thread group")))
        length(records) >= minimum_processes || push!(issues,
            "$thread_count-thread group requires at least $minimum_processes processes")
        isempty(records) && continue
        identity = first(records)["comparison_identity"]
        get(identity, "backend", nothing) == "cpu" || push!(issues,
            "$thread_count-thread group must use the CPU backend")
        get(identity, "julia_threads", nothing) == thread_count || push!(issues,
            "$thread_count-thread group identity does not match its thread count")
        current = first(records)
        if isnothing(reference)
            reference = current
        else
            append!(issues, _identity_issues(
                reference["comparison_identity"], current["comparison_identity"],
                comparison_keys, "CPU scaling comparison identity"))
            _cpu_system_id(reference["comparison_identity"]["hardware_id"]) ==
                _cpu_system_id(current["comparison_identity"]["hardware_id"]) || push!(issues,
                "CPU scaling groups use different hardware systems")
            reference["provenance"]["implementation_commit"] ==
                current["provenance"]["implementation_commit"] || push!(issues,
                "CPU scaling groups use different implementation commits")
            reference_names = sort!(collect(keys(reference["workloads"])))
            current_names = sort!(collect(keys(current["workloads"])))
            reference_names == current_names || push!(issues,
                "CPU scaling groups use different workload sets")
            for name in intersect(reference_names, current_names)
                append!(issues, _identity_issues(
                    reference["workloads"][name], current["workloads"][name],
                    WORKLOAD_IDENTITY_KEYS, "CPU scaling workload `$name`"))
            end
        end
    end
    isempty(issues) || return Dict(
        "comparable" => false, "issues" => unique!(issues))

    for thread_count in threads
        aggregates[thread_count] = aggregate_records(
            groups[thread_count]; minimum_processes)
    end
    baseline = aggregates[1]
    summaries = Dict{String, Any}()
    for thread_count in threads
        aggregate = aggregates[thread_count]
        workloads = Dict{String, Any}()
        algorithm_speedups = Dict{String, Vector{Float64}}()
        for name in sort!(collect(keys(baseline["workloads"])))
            one_thread = baseline["workloads"][name]
            threaded = aggregate["workloads"][name]
            speedup = _ratio(one_thread["median_steady_seconds_per_mcs"],
                threaded["median_steady_seconds_per_mcs"])
            algorithm = one_thread["algorithm"]
            push!(get!(algorithm_speedups, algorithm, Float64[]), speedup)
            workloads[name] = Dict(
                "algorithm" => algorithm,
                "speedup_over_one_thread" => speedup,
                "parallel_efficiency" => speedup / thread_count,
            )
        end
        summaries[string(thread_count)] = Dict(
            "threads" => thread_count,
            "processes" => aggregate["processes"],
            "workloads" => workloads,
            "algorithm_geometric_mean_speedups" => Dict(
                algorithm => exp(mean(log, speedups))
                for (algorithm, speedups) in algorithm_speedups),
        )
    end
    return Dict(
        "schema_version" => PHASE12_SCHEMA_VERSION,
        "contract_version" => PHASE12_CONTRACT_VERSION,
        "record_kind" => "phase12-cpu-scaling-summary",
        "comparable" => true,
        "hardware_system_id" => _cpu_system_id(
            reference["comparison_identity"]["hardware_id"]),
        "implementation_commit" => reference["provenance"]["implementation_commit"],
        "thread_counts" => threads,
        "scaling" => summaries,
    )
end

function _ratio(candidate, baseline)
    baseline == 0 && return candidate == 0 ? 1.0 : Inf
    return candidate / baseline
end

function _candidate_residency_issues(records)
    issues = String[]
    for (record_index, record) in pairs(records), (name, workload) in record["workloads"]
        warm = workload["warm_execution_metrics"]
        for key in ZERO_WARM_METRICS
            value = get(warm, key, nothing)
            value == 0 || push!(issues,
                "candidate record $record_index workload `$name` requires zero `$key`; got $(repr(value))")
        end
        timed_mcs = workload["timed_mcs"]
        declared_lifecycle = workload["declared_lifecycle_observation_per_mcs"]
        backend = record["comparison_identity"]["backend"]
        expected_synchronizations = declared_lifecycle ? timed_mcs : 0
        expected_device_to_host = declared_lifecycle && backend != "cpu" ? timed_mcs : 0
        for (key, expected) in (
                "host_synchronizations" => expected_synchronizations,
                "device_to_host_transfers" => expected_device_to_host)
            value = get(warm, key, nothing)
            value == expected || push!(issues,
                "candidate record $record_index workload `$name` expected `$key`=$expected; got $(repr(value))")
        end
    end
    return issues
end

function compare_record_groups(baseline::AbstractVector, candidate::AbstractVector;
        minimum_processes::Int = 3, regression_threshold::Real = 0.05,
        memory_threshold::Real = 0.05)
    0 <= regression_threshold < 1 || throw(ArgumentError(
        "regression_threshold must lie in [0, 1)"))
    0 <= memory_threshold < 1 || throw(ArgumentError(
        "memory_threshold must lie in [0, 1)"))
    issues = vcat(_group_issues(baseline, "baseline"),
        _group_issues(candidate, "candidate"))
    if isempty(issues) && !isempty(baseline) && !isempty(candidate)
        append!(issues, compatibility_issues(first(baseline), first(candidate)))
    end
    paired = paired_evidence(baseline, candidate)
    !isnothing(paired) && !paired["comparable"] && append!(issues, paired["issues"])
    length(baseline) >= minimum_processes || push!(issues,
        "baseline requires at least $minimum_processes independent processes")
    length(candidate) >= minimum_processes || push!(issues,
        "candidate requires at least $minimum_processes independent processes")
    isempty(issues) || return Dict(
        "comparable" => false, "passed" => false, "issues" => unique!(issues))

    baseline_aggregate = aggregate_records(baseline; minimum_processes)
    candidate_aggregate = aggregate_records(candidate; minimum_processes)
    residency_issues = _candidate_residency_issues(candidate)
    comparisons = Dict{String, Any}()
    steady_ratios = Dict{String, Vector{Float64}}()
    passed = isempty(residency_issues)
    for name in sort!(collect(keys(baseline_aggregate["workloads"])))
        before = baseline_aggregate["workloads"][name]
        after = candidate_aggregate["workloads"][name]
        steady_ratio = _ratio(after["median_steady_seconds_per_mcs"],
            before["median_steady_seconds_per_mcs"])
        first_ratio = _ratio(after["median_first_mcs_seconds"],
            before["median_first_mcs_seconds"])
        memory_ratio = _ratio(after["median_backend_resident_bytes"],
            before["median_backend_resident_bytes"])
        workload_passed = steady_ratio <= 1 + regression_threshold &&
                          memory_ratio <= 1 + memory_threshold
        passed &= workload_passed
        algorithm = before["algorithm"]
        push!(get!(steady_ratios, algorithm, Float64[]), steady_ratio)
        comparisons[name] = Dict(
            "passed" => workload_passed,
            "steady_seconds_ratio" => steady_ratio,
            "steady_throughput_ratio" => inv(steady_ratio),
            "order_dependent_first_mcs_seconds_ratio_diagnostic" => first_ratio,
            "backend_resident_bytes_ratio" => memory_ratio,
        )
    end
    algorithm_geometric_means = Dict(
        algorithm => exp(mean(log, ratios)) for (algorithm, ratios) in steady_ratios)
    geometric_mean_passed = all(<=(1), values(algorithm_geometric_means))
    passed &= geometric_mean_passed
    return Dict(
        "schema_version" => PHASE12_SCHEMA_VERSION,
        "contract_version" => PHASE12_CONTRACT_VERSION,
        "comparable" => true,
        "passed" => passed,
        "regression_threshold" => Float64(regression_threshold),
        "memory_threshold" => Float64(memory_threshold),
        "algorithm_geometric_mean_steady_seconds_ratios" => algorithm_geometric_means,
        "geometric_mean_passed" => geometric_mean_passed,
        "residency_issues" => residency_issues,
        "paired_evidence" => paired,
        "baseline" => baseline_aggregate,
        "candidate" => candidate_aggregate,
        "workloads" => comparisons,
    )
end

function print_comparison(io::IO, comparison::AbstractDict)
    if !get(comparison, "comparable", false)
        println(io, "Phase 12 comparison: INCOMPARABLE")
        for issue in get(comparison, "issues", String[])
            println(io, "- ", issue)
        end
        return comparison
    end
    println(io, "Phase 12 comparison: ", comparison["passed"] ? "PASS" : "FAIL")
    for algorithm in sort!(collect(keys(
            comparison["algorithm_geometric_mean_steady_seconds_ratios"])))
        println(io, algorithm, " geometric mean steady-time ratio: ", round(
            comparison["algorithm_geometric_mean_steady_seconds_ratios"][algorithm];
            digits = 6))
    end
    println(io, "| Workload | Steady time | Throughput | First MCS diagnostic | Memory | Gate |")
    println(io, "|---|---:|---:|---:|---:|---:|")
    for name in sort!(collect(keys(comparison["workloads"])))
        result = comparison["workloads"][name]
        println(io, "| ", name, " | ",
            round(result["steady_seconds_ratio"]; digits = 6), " | ",
            round(result["steady_throughput_ratio"]; digits = 6), " | ",
            round(result["order_dependent_first_mcs_seconds_ratio_diagnostic"];
                digits = 6), " | ",
            round(result["backend_resident_bytes_ratio"]; digits = 6), " | ",
            result["passed"] ? "pass" : "fail", " |")
    end
    for issue in comparison["residency_issues"]
        println(io, "- ", issue)
    end
    return comparison
end

print_comparison(comparison::AbstractDict) = print_comparison(stdout, comparison)

function validate_cold_record(record::AbstractDict)
    issues = String[]
    get(record, "schema_version", nothing) == PHASE12_SCHEMA_VERSION || push!(issues,
        "schema_version must be $PHASE12_SCHEMA_VERSION")
    get(record, "record_kind", nothing) == "phase12-cold-run" || push!(issues,
        "record_kind must be phase12-cold-run")
    identity = _table(record, "comparison_identity", issues, "cold record")
    for key in COLD_IDENTITY_KEYS
        haskey(identity, key) || push!(issues, "comparison_identity is missing `$key`")
    end
    get(identity, "contract_version", nothing) == PHASE12_CONTRACT_VERSION || push!(issues,
        "contract_version must be $PHASE12_CONTRACT_VERSION")
    run = _table(record, "run", issues, "cold record")
    haskey(run, "process_id") || push!(issues, "run is missing `process_id`")
    provenance = _table(record, "provenance", issues, "cold record")
    for key in ("implementation_commit", "implementation_tree_sha256", "harness_commit",
            "git_dirty")
        haskey(provenance, key) || push!(issues, "provenance is missing `$key`")
    end
    get(provenance, "git_dirty", true) === false || push!(issues,
        "authoritative Phase 12 cold records require a clean worktree")
    metrics = _table(record, "metrics", issues, "cold record")
    for key in COLD_METRIC_KEYS
        haskey(metrics, key) || push!(issues, "cold metrics are missing `$key`")
        haskey(metrics, key) && !_finite_nonnegative(metrics[key]) && push!(issues,
            "cold metric `$key` must be finite and non-negative")
    end
    return issues
end

function load_cold_record(path::AbstractString)
    record = TOML.parsefile(path)
    issues = validate_cold_record(record)
    isempty(issues) || throw(ArgumentError(
        "invalid Phase 12 cold record $(abspath(path)):\n- " * join(issues, "\n- ")))
    return record
end

function validate_precompile_record(record::AbstractDict)
    issues = String[]
    get(record, "schema_version", nothing) == PHASE12_SCHEMA_VERSION || push!(issues,
        "schema_version must be $PHASE12_SCHEMA_VERSION")
    get(record, "record_kind", nothing) == "phase12-precompile-run" || push!(issues,
        "record_kind must be phase12-precompile-run")
    identity = _table(record, "comparison_identity", issues, "precompile record")
    for key in PRECOMPILE_IDENTITY_KEYS
        haskey(identity, key) || push!(issues, "comparison_identity is missing `$key`")
    end
    get(identity, "contract_version", nothing) == PHASE12_CONTRACT_VERSION || push!(issues,
        "contract_version must be $PHASE12_CONTRACT_VERSION")
    run = _table(record, "run", issues, "precompile record")
    haskey(run, "process_id") || push!(issues, "run is missing `process_id`")
    get(run, "network_policy", nothing) == "offline" || push!(issues,
        "precompile run must declare offline network policy")
    provenance = _table(record, "provenance", issues, "precompile record")
    for key in ("implementation_commit", "implementation_tree_sha256", "harness_commit",
            "git_dirty")
        haskey(provenance, key) || push!(issues, "provenance is missing `$key`")
    end
    get(provenance, "git_dirty", true) === false || push!(issues,
        "authoritative Phase 12 precompile records require a clean worktree")
    metrics = _table(record, "metrics", issues, "precompile record")
    for key in PRECOMPILE_METRIC_KEYS
        haskey(metrics, key) || push!(issues, "precompile metrics are missing `$key`")
        haskey(metrics, key) && !_finite_nonnegative(metrics[key]) && push!(issues,
            "precompile metric `$key` must be finite and non-negative")
    end
    get(metrics, "base_environment_precompile_seconds", 0) > 0 || push!(issues,
        "base_environment_precompile_seconds must be positive for a fresh depot")
    get(metrics, "total_precompile_seconds", 0) > 0 || push!(issues,
        "total_precompile_seconds must be positive for a fresh depot")
    get(metrics, "isolated_depot_bytes", 0) > 0 || push!(issues,
        "isolated_depot_bytes must be positive for a fresh compiled cache")
    return issues
end

function load_precompile_record(path::AbstractString)
    record = TOML.parsefile(path)
    issues = validate_precompile_record(record)
    isempty(issues) || throw(ArgumentError(
        "invalid Phase 12 precompile record $(abspath(path)):\n- " *
        join(issues, "\n- ")))
    return record
end

function _precompile_group_issues(records, label)
    issues = String[]
    isempty(records) && return ["$label precompile group is empty"]
    for (index, record) in pairs(records)
        append!(issues, ("$label precompile record $index: $issue" for issue in
            validate_precompile_record(record)))
    end
    isempty(issues) || return issues
    first_record = first(records)
    process_ids = String[]
    for (index, record) in pairs(records)
        append!(issues, ("$label precompile record $index: $issue" for issue in
            _identity_issues(first_record["comparison_identity"],
                record["comparison_identity"], PRECOMPILE_IDENTITY_KEYS,
                "precompile comparison identity")))
        push!(process_ids, string(record["run"]["process_id"]))
    end
    length(unique(process_ids)) == length(process_ids) || push!(issues,
        "$label precompile group contains repeated process_id values")
    return unique!(issues)
end

function compare_precompile_record_groups(baseline::AbstractVector,
        candidate::AbstractVector; minimum_processes::Int = 3,
        regression_threshold::Real = 0.05, cache_threshold::Real = 0.05)
    0 <= regression_threshold < 1 || throw(ArgumentError(
        "regression_threshold must lie in [0, 1)"))
    0 <= cache_threshold < 1 || throw(ArgumentError(
        "cache_threshold must lie in [0, 1)"))
    issues = vcat(_precompile_group_issues(baseline, "baseline"),
        _precompile_group_issues(candidate, "candidate"))
    if isempty(issues) && !isempty(baseline) && !isempty(candidate)
        append!(issues, _identity_issues(
            first(baseline)["comparison_identity"], first(candidate)["comparison_identity"],
            PRECOMPILE_IDENTITY_KEYS, "precompile comparison identity"))
    end
    length(baseline) >= minimum_processes || push!(issues,
        "baseline requires at least $minimum_processes independent precompile processes")
    length(candidate) >= minimum_processes || push!(issues,
        "candidate requires at least $minimum_processes independent precompile processes")
    isempty(issues) || return Dict(
        "comparable" => false, "passed" => false, "issues" => unique!(issues))
    ratios = Dict{String, Float64}()
    passed = true
    for key in PRECOMPILE_METRIC_KEYS
        before = median(Float64(record["metrics"][key]) for record in baseline)
        after = median(Float64(record["metrics"][key]) for record in candidate)
        ratio = _ratio(after, before)
        ratios[key] = ratio
        threshold = key == "isolated_depot_bytes" ? cache_threshold : regression_threshold
        passed &= ratio <= 1 + threshold
    end
    return Dict(
        "schema_version" => PHASE12_SCHEMA_VERSION,
        "contract_version" => PHASE12_CONTRACT_VERSION,
        "comparable" => true,
        "passed" => passed,
        "regression_threshold" => Float64(regression_threshold),
        "cache_threshold" => Float64(cache_threshold),
        "metric_ratios" => ratios,
        "baseline_processes" => length(baseline),
        "candidate_processes" => length(candidate),
    )
end

function _cold_group_issues(records, label)
    issues = String[]
    isempty(records) && return ["$label cold group is empty"]
    for (index, record) in pairs(records)
        append!(issues,
            ("$label cold record $index: $issue" for issue in validate_cold_record(record)))
    end
    isempty(issues) || return issues
    first_record = first(records)
    process_ids = String[]
    for (index, record) in pairs(records)
        append!(issues, ("$label cold record $index: $issue" for issue in _identity_issues(
            first_record["comparison_identity"], record["comparison_identity"],
            COLD_IDENTITY_KEYS, "cold comparison identity")))
        push!(process_ids, string(record["run"]["process_id"]))
    end
    length(unique(process_ids)) == length(process_ids) || push!(issues,
        "$label cold group contains repeated process_id values")
    return unique!(issues)
end

function compare_cold_record_groups(baseline::AbstractVector, candidate::AbstractVector;
        minimum_processes::Int = 3, regression_threshold::Real = 0.05)
    0 <= regression_threshold < 1 || throw(ArgumentError(
        "regression_threshold must lie in [0, 1)"))
    issues = vcat(_cold_group_issues(baseline, "baseline"),
        _cold_group_issues(candidate, "candidate"))
    if isempty(issues) && !isempty(baseline) && !isempty(candidate)
        append!(issues, _identity_issues(
            first(baseline)["comparison_identity"], first(candidate)["comparison_identity"],
            COLD_IDENTITY_KEYS, "cold comparison identity"))
    end
    length(baseline) >= minimum_processes || push!(issues,
        "baseline requires at least $minimum_processes independent cold processes")
    length(candidate) >= minimum_processes || push!(issues,
        "candidate requires at least $minimum_processes independent cold processes")
    isempty(issues) || return Dict(
        "comparable" => false, "passed" => false, "issues" => unique!(issues))
    ratios = Dict{String, Float64}()
    passed = true
    for key in COLD_METRIC_KEYS
        before = median(Float64(record["metrics"][key]) for record in baseline)
        after = median(Float64(record["metrics"][key]) for record in candidate)
        ratio = _ratio(after, before)
        ratios[key] = ratio
        passed &= ratio <= 1 + regression_threshold
    end
    return Dict(
        "schema_version" => PHASE12_SCHEMA_VERSION,
        "contract_version" => PHASE12_CONTRACT_VERSION,
        "comparable" => true,
        "passed" => passed,
        "regression_threshold" => Float64(regression_threshold),
        "metric_ratios" => ratios,
        "baseline_processes" => length(baseline),
        "candidate_processes" => length(candidate),
    )
end

end

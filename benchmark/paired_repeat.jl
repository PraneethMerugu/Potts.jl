VERSION == v"1.12.6" ||
    error("The refactor benchmark target is Julia 1.12.6; found $VERSION")

include(joinpath(@__DIR__, "src", "PairedPerformanceRunner.jl"))
using .PairedPerformanceRunner

function option(name, default = nothing)
    prefix = "--$name="
    argument = findfirst(value -> startswith(value, prefix), ARGS)
    return isnothing(argument) ? default : ARGS[argument][(length(prefix) + 1):end]
end

function required_option(name)
    value = option(name)
    isnothing(value) && throw(ArgumentError("missing required --$name=VALUE"))
    return value
end

baseline_root = abspath(required_option("baseline-root"))
candidate_root = abspath(required_option("candidate-root"))
backend = option("backend", "cpu")
profile = option("profile", "full")
precision = option("precision", "Float32")
repetitions = parse(Int, option("repetitions", "4"))

isdir(baseline_root) || throw(ArgumentError("baseline root does not exist: $baseline_root"))
isdir(candidate_root) || throw(ArgumentError("candidate root does not exist: $candidate_root"))
backend in ("cpu", "metal", "amdgpu") || error(
    "performance comparison paired runner requires --backend=cpu, metal, or amdgpu")
profile == "full" || error("paired performance comparison evidence requires --profile=full")
precision in ("Float32", "Float64") || error("precision must be Float32 or Float64")
backend != "cpu" && precision != "Float32" && error(
    "GPU Float64 is not a performance comparison paired-performance target")
repetitions >= 4 || error(
    "paired performance comparison evidence requires at least four balanced fresh-process pairs")

run_id = get(ENV, "GITHUB_RUN_ID", "local")
run_attempt = get(ENV, "GITHUB_RUN_ATTEMPT", "1")
pair_id = "$run_id-$run_attempt-$backend-$profile-$precision-paired"
worker = abspath(joinpath(@__DIR__, "performance_worker.jl"))
isfile(worker) || error("paired benchmark harness worker is missing: $worker")

function worker_command(root)
    # Each subject loads its own path-pinned package implementation while both
    # subjects execute this one immutable harness checkout.
    return paired_worker_command(worker, root; backend, profile, precision)
end

function run_subject!(label, root, pair_index, ordinal)
    process_id = "$pair_id-$label-pair$pair_index-ordinal$ordinal"
    command = worker_command(root)
    environment = Dict(
        "POTTS_BENCHMARK_PROCESS_ID" => process_id,
        "POTTS_BENCHMARK_PAIR_ID" => pair_id,
        "POTTS_BENCHMARK_PAIR_INDEX" => string(pair_index),
        "POTTS_BENCHMARK_PAIR_SUBJECT" => label,
        "POTTS_BENCHMARK_PAIR_ORDINAL" => string(ordinal),
        "POTTS_BENCHMARK_SUBJECT_ROOT" => root,
    )
    run(addenv(command, environment...))
end

# Alternate the subject that runs first.  Four pairs produce the balanced order
# baseline/candidate, candidate/baseline, baseline/candidate, candidate/baseline.
for pair_index in 1:repetitions
    first, second = isodd(pair_index) ?
                    (("baseline", baseline_root), ("candidate", candidate_root)) :
                    (("candidate", candidate_root), ("baseline", baseline_root))
    run_subject!(first[1], first[2], pair_index, 1)
    run_subject!(second[1], second[2], pair_index, 2)
end

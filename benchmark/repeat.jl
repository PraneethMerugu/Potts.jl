VERSION == v"1.12.6" ||
    error("The refactor benchmark target is Julia 1.12.6; found $VERSION")

function option(name, default)
    prefix = "--$name="
    argument = findfirst(value -> startswith(value, prefix), ARGS)
    return isnothing(argument) ? default : ARGS[argument][(length(prefix) + 1):end]
end

backend = option("backend", "cpu")
profile = option("profile", "smoke")
precision = option("precision", "Float32")
repetitions = parse(Int, option("repetitions", "1"))
backend in ("cpu", "metal", "amdgpu") || error(
    "performance comparison requires --backend=cpu, metal, or amdgpu")
profile in ("smoke", "full", "throughput") || error(
    "Expected --profile=smoke, full, or throughput")
precision in ("Float32", "Float64") || error(
    "Expected --precision=Float32 or Float64")
backend != "cpu" && precision != "Float32" && error(
    "GPU Float64 performance is optional and not qualified in performance comparison")
repetitions in (1, 3, 5) || error("performance comparison repetitions must be 1, 3, or 5")

worker = joinpath(@__DIR__, "performance_worker.jl")
project = Base.active_project()
run_id = get(ENV, "GITHUB_RUN_ID", "local")
run_attempt = get(ENV, "GITHUB_RUN_ATTEMPT", "1")

for repetition in 1:repetitions
    process_id = "$run_id-$run_attempt-$backend-$profile-$precision-$repetition"
    command = `$(Base.julia_cmd()) --project=$project --startup-file=no $worker --backend=$backend --profile=$profile --precision=$precision`
    run(addenv(command, "POTTS_BENCHMARK_PROCESS_ID" => process_id))
end

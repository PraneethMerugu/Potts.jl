VERSION == v"1.12.6" ||
    error("The tiled benchmark target is Julia 1.12.6; found $VERSION")

function option(name, default)
    prefix = "--$name="
    argument = findfirst(value -> startswith(value, prefix), ARGS)
    return isnothing(argument) ? default : ARGS[argument][(length(prefix) + 1):end]
end

backend = option("backend", "cpu")
backend in ("cpu", "metal", "amdgpu") ||
    error("Expected --backend=cpu, --backend=metal, or --backend=amdgpu")
backend == "metal" && (@eval using Metal)
backend == "amdgpu" && (@eval using AMDGPU)

include(joinpath(@__DIR__, "src", "PottsBenchmarks.jl"))
using .PottsBenchmarks
using CorePotts

measurement = PottsBenchmarks.measure_reference_backend(backend;
    profile = "smoke", algorithm = TiledCheckerboardCPM(temperature = 2.0f0),
    skip_incompatible = true)
workloads = measurement["workloads"]
sort!(collect(keys(workloads))) ==
    ["differential_adhesion", "uniform_adhesion_tiled_baseline"] ||
    error("the tiled smoke matrix does not contain the two registered workloads")

for label in sort!(collect(keys(workloads)))
    workload = workloads[label]
    configuration = workload["tiled_execution_configuration"]
    backend == "cpu" ||
        configuration["resolved_storage_policy"] == "workgroup_local" ||
        error("$backend $label did not select the qualified workgroup-local path")
    warm = workload["warm_execution_metrics"]
    warm["host_synchronizations"] == 0 ||
        error("$backend $label introduced a warm host synchronization")
    warm["device_allocations"] == 0 ||
        error("$backend $label introduced a warm device allocation")
    println("TILED_SMOKE=", Dict(
        "backend" => backend,
        "workload" => label,
        "seconds_per_mcs" => workload["steady_median_seconds_per_mcs"],
        "activated_attempts_per_second" =>
            workload["median_activated_attempts_per_second"],
        "accepted_copies_per_second" => workload["median_accepted_copies_per_second"],
        "configuration" => configuration,
        "warm_execution_metrics" => warm,
    ))
end

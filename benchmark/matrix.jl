VERSION == v"1.12.6" ||
    error("The refactor benchmark target is Julia 1.12.6; found $VERSION")

function option(name, default)
    prefix = "--$name="
    argument = findfirst(arg -> startswith(arg, prefix), ARGS)
    return isnothing(argument) ? default : ARGS[argument][(length(prefix) + 1):end]
end

backend = option("backend", "cpu")
profile = option("profile", "smoke")
profile in ("smoke", "full") || error("Expected --profile=smoke or --profile=full")

backend == "metal" && (@eval using Metal)
backend == "cuda" && (@eval using CUDA)
backend == "amdgpu" && (@eval using AMDGPU)

include(joinpath(@__DIR__, "src", "PottsBenchmarks.jl"))
using .PottsBenchmarks

rng_qualification = PottsBenchmarks.qualify_rng_backend(backend)
println("RNG_QUALIFICATION=", rng_qualification)
execution_qualification = PottsBenchmarks.qualify_execution_backend(backend)
println("EXECUTION_QUALIFICATION=", execution_qualification)
scientific_qualification = PottsBenchmarks.qualify_scientific_backend(backend)
println("SCIENTIFIC_QUALIFICATION=", scientific_qualification)
sequential_qualification = PottsBenchmarks.qualify_sequential_backend(backend)
println("SEQUENTIAL_QUALIFICATION=", sequential_qualification)
checkerboard_qualification = PottsBenchmarks.qualify_checkerboard_backend(backend)
println("CHECKERBOARD_QUALIFICATION=", checkerboard_qualification)
lottery_qualification = PottsBenchmarks.qualify_lottery_backend(backend)
println("LOTTERY_QUALIFICATION=", lottery_qualification)
mechanics_qualification = PottsBenchmarks.qualify_mechanics_backend(backend)
println("MECHANICS_QUALIFICATION=", mechanics_qualification)
lifecycle_qualification = PottsBenchmarks.qualify_lifecycle_backend(backend)
println("LIFECYCLE_QUALIFICATION=", lifecycle_qualification)
persistence_qualification = PottsBenchmarks.qualify_persistence_backend(backend)
println("PERSISTENCE_QUALIFICATION=", persistence_qualification)
lifecycle_performance = PottsBenchmarks.measure_lifecycle_backend(backend)
println("LIFECYCLE_PERFORMANCE=", lifecycle_performance)
solver_interface_qualification = PottsBenchmarks.qualify_solver_interface_backend(backend)
println("SOLVER_INTERFACE_QUALIFICATION=", solver_interface_qualification)
authoring_qualification = PottsBenchmarks.qualify_authoring_backend(backend)
println("AUTHORING_QUALIFICATION=", authoring_qualification)
extended_authoring_qualification = PottsBenchmarks.qualify_extended_authoring_backend(backend)
println("EXTENDED_AUTHORING_QUALIFICATION=", extended_authoring_qualification)
authoring_performance = PottsBenchmarks.measure_authoring_backend(backend)
println("AUTHORING_PERFORMANCE=", authoring_performance)
reference_performance = PottsBenchmarks.measure_reference_backend(
    backend; profile, skip_incompatible = true)
println("REFERENCE_PERFORMANCE=", Dict(
    "profile" => profile,
    "workloads" => sort!(collect(keys(reference_performance["workloads"]))),
    "required_families" => reference_performance["required_families"]))
balanced_reference_performance = PottsBenchmarks.measure_balanced_reference_backend(
    backend; profile, sequential_reference = reference_performance)
println("PERFORMANCE_REFERENCE_PERFORMANCE=", Dict(
    "profile" => profile,
    "workload_count" => length(balanced_reference_performance["workloads"]),
    "required_algorithms" => balanced_reference_performance["required_algorithms"]))
_, benchmark_device = PottsBenchmarks.load_backend(backend)
single_run_record = PottsBenchmarks.single_run_result(
    backend, profile, benchmark_device;
    qualification = authoring_qualification,
    direct_comparison = authoring_performance,
    reference_performance = reference_performance,
    checkpoint_performance = lifecycle_performance)
single_run_path = PottsBenchmarks.write_single_run_result(single_run_record)
println("SINGLE_RUN_RESULT=", single_run_path)
balanced_record = PottsBenchmarks.balanced_result(
    backend, profile, benchmark_device;
    qualification = authoring_qualification,
    direct_comparison = authoring_performance,
    reference_performance = balanced_reference_performance,
    checkpoint_performance = lifecycle_performance)
balanced_path = PottsBenchmarks.write_balanced_result(balanced_record)
println("PERFORMANCE_RESULT=", balanced_path)
solver_interface_performance = PottsBenchmarks.measure_solver_interface_backend(backend)
println("SOLVER_INTERFACE_PERFORMANCE=", solver_interface_performance)

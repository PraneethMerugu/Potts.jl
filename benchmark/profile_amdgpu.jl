VERSION == v"1.12.6" ||
    error("The refactor benchmark target is Julia 1.12.6; found $VERSION")

using AMDGPU

include(joinpath(@__DIR__, "profile_common.jl"))
using .BackendProfile

backend_name = "amdgpu"
probe = AMDGPU.ROCArray(zeros(UInt8, 1))
backend = BackendProfile.KernelAbstractions.get_backend(probe)
directory, provenance = BackendProfile.profile_directory(
    backend_name, string(backend))
profiles = Dict{String, Any}()

for algorithm_name in BackendProfile.PROFILE_ALGORITHMS
    integrator = BackendProfile.prepare_integrator(
        backend_name, backend, algorithm_name)
    code_directory = joinpath(directory, algorithm_name, "device-code")
    AMDGPU.@device_code dir=code_directory begin
        BackendProfile.synchronized_steps!(integrator, 1)
    end
    BackendProfile.synchronized_steps!(integrator, 1)
    println("PERFORMANCE_ROCPROF_BEGIN=", algorithm_name)
    profiled_seconds = BackendProfile.synchronized_steps!(integrator, 5)
    println("PERFORMANCE_ROCPROF_END=", algorithm_name)
    profiles[algorithm_name] = Dict(
        "code" => BackendProfile.code_summary(code_directory),
        "profiled_mcs" => 5,
        "profiled_wall_seconds" => profiled_seconds,
    )
end

trace_status = get(ENV, "POTTS_ROCPROF_TRACE_STATUS", "external-capture-required")
path = BackendProfile.write_record(directory, backend_name, provenance,
    "AMDGPU", string(Base.pkgversion(AMDGPU)), profiles;
    trace_kind = "rocprofv3 HIP/HSA/kernel Perfetto trace",
    trace_status)
println("PERFORMANCE_BACKEND_PROFILE=", path)

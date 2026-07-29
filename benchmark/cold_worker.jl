VERSION == v"1.12.6" ||
    error("The refactor benchmark target is Julia 1.12.6; found $VERSION")

function option(name, default)
    prefix = "--$name="
    argument = findfirst(value -> startswith(value, prefix), ARGS)
    return isnothing(argument) ? default : ARGS[argument][(length(prefix) + 1):end]
end

backend_name = option("backend", "cpu")
algorithm_name = option("algorithm", "SequentialCPM")
backend_name in ("cpu", "metal", "amdgpu") || error(
    "performance comparison cold measurement requires cpu, metal, or amdgpu")
algorithm_name in ("SequentialCPM", "SequentialEquilibrium", "CheckerboardSweepCPM",
    "LotteryCPM") || error("unknown performance comparison cold algorithm `$algorithm_name`")

backend_import = @timed begin
    backend_name == "metal" && (@eval using Metal)
    backend_name == "amdgpu" && (@eval using AMDGPU)
end

package_import = @timed begin
    @eval using Adapt
    @eval using CorePotts
    @eval using KernelAbstractions
    @eval using PottsToolkit
    @eval using SciMLBase
end

algorithm = if algorithm_name == "SequentialCPM"
    CorePotts.SequentialCPM(temperature = 2.0f0)
elseif algorithm_name == "SequentialEquilibrium"
    CorePotts.SequentialEquilibrium(temperature = 2.0f0)
elseif algorithm_name == "CheckerboardSweepCPM"
    CorePotts.CheckerboardSweepCPM(temperature = 2.0f0)
else
    CorePotts.LotteryCPM(temperature = 2.0f0)
end

model_timing = @timed PottsToolkit.ReferenceModels.differential_adhesion_model(
    target_volume = 20)
model = model_timing.value
normalization_timing = @timed PottsToolkit.normalize(model)
lowering_timing = @timed PottsToolkit.lower(model; dimensions = 2)
problem_timing = @timed PottsToolkit.ReferenceModels.differential_adhesion_problem(
    (32, 32); cells_per_population = 8, target_volume = 20, capacity = 64,
    tspan = (0, 4), seed = 0x7068617365313201)
problem = problem_timing.value

probe = if backend_name == "cpu"
    zeros(UInt8, 1)
elseif backend_name == "metal"
    Metal.MtlArray(zeros(UInt8, 1))
else
    AMDGPU.ROCArray(zeros(UInt8, 1))
end
backend = KernelAbstractions.get_backend(probe)
report = PottsToolkit.backend_report(problem, algorithm, backend)
report.qualified || error(
    "$backend_name $algorithm_name cold workload failed preflight: $(report.messages)")

initialization_timing = @timed SciMLBase.init(problem, algorithm;
    backend, verbose = false, save_start = false, save_end = false)
integrator = initialization_timing.value
first_mcs_timing = @timed begin
    SciMLBase.step!(integrator, 1)
    KernelAbstractions.synchronize(integrator.inner.plan.backend)
end

# Provenance and serialization occur only after every cold timing boundary is closed.
include(joinpath(@__DIR__, "src", "PottsBenchmarks.jl"))
using .PottsBenchmarks
using Dates
using SHA
using TOML

provenance = PottsBenchmarks.provenance(backend_name, string(backend))
cold_harness_files = [
    joinpath(@__DIR__, "cold_worker.jl"),
]
cold_harness_checksum = PottsBenchmarks.file_set_checksum(cold_harness_files)
process_id = get(ENV, "POTTS_BENCHMARK_PROCESS_ID",
    string(Dates.format(now(UTC), dateformat"yyyymmddTHHMMSS.sss"), "-", getpid()))

record = Dict(
    "schema_version" => PottsBenchmarks.PerformanceComparison.PERFORMANCE_SCHEMA_VERSION,
    "record_kind" => "phase12-cold-run",
    "recorded_at_utc" => string(now(UTC)),
    "comparison_identity" => Dict(
        "contract_version" => PottsBenchmarks.PerformanceComparison.PERFORMANCE_CONTRACT_VERSION,
        "cold_workload_version" => "differential-adhesion-1.0.0",
        "cold_harness_tree_sha256" => cold_harness_checksum,
        "backend" => backend_name,
        "hardware_id" => provenance["hardware_id"],
        "julia_version" => string(VERSION),
        "architecture" => string(Sys.ARCH),
        "os" => string(Sys.KERNEL),
        "julia_threads" => Threads.nthreads(),
        "precision" => "Float32",
        "algorithm" => algorithm_name,
    ),
    "run" => Dict(
        "process_id" => process_id,
        "independence_unit" => "fresh Julia process",
    ),
    "provenance" => provenance,
    "metrics" => Dict(
        "backend_import_seconds" => backend_import.time,
        "package_import_seconds" => package_import.time,
        "model_construction_seconds" => model_timing.time,
        "normalization_seconds" => normalization_timing.time,
        "lowering_seconds" => lowering_timing.time,
        "problem_construction_seconds" => problem_timing.time,
        "initialization_seconds" => initialization_timing.time,
        "first_mcs_seconds" => first_mcs_timing.time,
        "backend_import_host_bytes" => backend_import.bytes,
        "package_import_host_bytes" => package_import.bytes,
        "initialization_host_bytes" => initialization_timing.bytes,
        "first_mcs_host_bytes" => first_mcs_timing.bytes,
    ),
)

issues = PottsBenchmarks.PerformanceComparison.validate_cold_record(record)
isempty(issues) || error("refusing to write invalid performance comparison cold result:\n- " *
                         join(issues, "\n- "))
directory = joinpath(PottsBenchmarks.RESULTS_ROOT, provenance["subject_id"], "cold",
    backend_name, algorithm_name)
mkpath(directory)
timestamp = Dates.format(now(UTC), dateformat"yyyymmddTHHMMSS")
path = joinpath(directory, "$(timestamp)-cold-run-$process_id.toml")
open(path, "w") do io
    TOML.print(io, record; sorted = true)
end
println("PERFORMANCE_COLD_RESULT=", path)

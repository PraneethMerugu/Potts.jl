module BackendProfile

using CorePotts
using Dates
using KernelAbstractions
using PottsToolkit
using SciMLBase
using TOML

include(joinpath(@__DIR__, "src", "PottsBenchmarks.jl"))
using .PottsBenchmarks

const PROFILE_SCHEMA_VERSION = "1.0.0"
const PROFILE_WORKLOAD_VERSION = "differential-adhesion-1.0.0"
const PROFILE_ALGORITHMS = (
    "SequentialCPM",
    "SequentialEquilibrium",
    "CheckerboardSweepCPM",
    "LotteryCPM",
)

function algorithm(name::String)
    name == "SequentialCPM" && return SequentialCPM(temperature = 2.0f0)
    name == "SequentialEquilibrium" && return SequentialEquilibrium(temperature = 2.0f0)
    name == "CheckerboardSweepCPM" &&
        return CheckerboardSweepCPM(temperature = 2.0f0)
    name == "LotteryCPM" && return LotteryCPM(temperature = 2.0f0)
    throw(ArgumentError("unknown performance comparison profile algorithm `$name`"))
end

function prepare_integrator(backend_name::String, backend, algorithm_name::String)
    problem = PottsToolkit.ReferenceModels.differential_adhesion_problem(
        (32, 32); cells_per_population = 8, target_volume = 20, capacity = 64,
        tspan = (0, 16), seed = 0x7068617365313201)
    selected_algorithm = algorithm(algorithm_name)
    report = PottsToolkit.backend_report(problem, selected_algorithm, backend)
    report.qualified || error(
        "$backend_name $algorithm_name profile workload failed preflight: $(report.messages)")
    integrator = SciMLBase.init(problem, selected_algorithm;
        backend, verbose = false, save_start = false, save_end = false)
    return integrator
end

function synchronized_steps!(integrator, steps::Int)
    steps > 0 || throw(ArgumentError("profile steps must be positive"))
    started = time_ns()
    SciMLBase.step!(integrator, steps)
    KernelAbstractions.synchronize(integrator.inner.plan.backend)
    return (time_ns() - started) / 1.0e9
end

function profile_directory(backend_name::String, device::String)
    provenance = PottsBenchmarks.provenance(backend_name, device)
    timestamp = Dates.format(now(UTC), dateformat"yyyymmddTHHMMSS")
    directory = joinpath(PottsBenchmarks.RESULTS_ROOT, provenance["subject_id"],
        "profiles", backend_name, timestamp)
    mkpath(directory)
    return directory, provenance
end

function _native_metadata(path::String)
    metadata = Dict{String, Any}()
    for line in eachline(path)
        for (key, pattern) in (
                "next_free_vgpr" => r"\.amdhsa_next_free_vgpr\s+(\d+)",
                "next_free_sgpr" => r"\.amdhsa_next_free_sgpr\s+(\d+)",
                "group_segment_fixed_bytes" =>
                    r"\.amdhsa_group_segment_fixed_size\s+(\d+)",
                "private_segment_fixed_bytes" =>
                    r"\.amdhsa_private_segment_fixed_size\s+(\d+)")
            match_result = match(pattern, line)
            match_result === nothing ||
                (metadata[key] = parse(Int, only(match_result.captures)))
        end
    end
    return metadata
end

function _native_compilation_jobs(path::String)
    jobs = count(line -> startswith(line, "// CompilerJob"), eachline(path))
    # The full `@device_code` dumper writes one native file per compilation job
    # without a header. Native-only reflection writes every captured job to one
    # aggregate file and prefixes each section with `// CompilerJob`.
    return jobs == 0 && filesize(path) > 0 ? 1 : jobs
end

function code_summary(directory::String)
    files = sort!(String[joinpath(root, name)
        for (root, _, names) in walkdir(directory) for name in names])
    native_files = filter(path -> endswith(path, ".asm"), files)
    native = Dict{String, Any}()
    for path in native_files
        metadata = _native_metadata(path)
        native[relpath(path, directory)] = Dict(
            "bytes" => filesize(path),
            "authoritative_metadata" => metadata,
            "metadata_available" => !isempty(metadata),
        )
    end
    return Dict(
        "file_count" => length(files),
        "total_bytes" => sum(filesize, files; init = 0),
        "native_file_count" => length(native_files),
        "native_compilation_job_count" =>
            sum(_native_compilation_jobs, native_files; init = 0),
        "native_code_bytes" => sum(filesize, native_files; init = 0),
        "native_files" => native,
    )
end

function write_record(directory::String, backend_name::String, provenance,
        backend_package::String, backend_version::String, profiles;
        trace_kind::String, trace_status::String)
    Set(keys(profiles)) == Set(PROFILE_ALGORITHMS) || error(
        "backend profile must cover every performance comparison scientific algorithm")
    for (algorithm_name, profile) in profiles
        code = profile["code"]
        code["file_count"] > 0 || error("$algorithm_name produced no device code")
        code["native_file_count"] > 0 || error(
            "$algorithm_name produced no backend-native code")
        code["native_compilation_job_count"] > 0 || error(
            "$algorithm_name produced no backend-native compilation jobs")
        code["native_code_bytes"] > 0 || error(
            "$algorithm_name backend-native code is empty")
        profile["profiled_mcs"] == 5 || error(
            "$algorithm_name did not execute the declared profile horizon")
        profile["profiled_wall_seconds"] > 0 || error(
            "$algorithm_name profile timing is not positive")
        if haskey(profile, "chronological_trace_enabled")
            profile["chronological_trace_enabled"] || error(
                "$algorithm_name did not enable chronological trace capture")
            profile["device_command_buffer_count"] > 0 || error(
                "$algorithm_name chronological trace recorded no device command buffers")
            profile["device_operation_count"] > 0 || error(
                "$algorithm_name chronological trace recorded no GPU operations")
            profile["profile_text_bytes"] > 0 || error(
                "$algorithm_name chronological trace artifact is empty")
        end
    end
    record = Dict(
        "schema_version" => PROFILE_SCHEMA_VERSION,
        "record_kind" => "phase12-backend-profile",
        "recorded_at_utc" => string(now(UTC)),
        "comparison_identity" => Dict(
            "workload_version" => PROFILE_WORKLOAD_VERSION,
            "backend" => backend_name,
            "hardware_id" => provenance["hardware_id"],
            "julia_version" => string(VERSION),
            "precision" => "Float32",
            "profile_steps" => 5,
        ),
        "provenance" => provenance,
        "backend_package" => Dict(
            "name" => backend_package,
            "version" => backend_version,
        ),
        "measurement_contract" => Dict(
            "scientific_workload" => "differential adhesion",
            "device_code_captured_before_warm_profile" => true,
            "timed_region_backend_synchronized" => true,
            "registers_never_inferred_from_occupancy" => true,
            "unavailable_metrics_reported_as_unavailable" => true,
            "trace_kind" => trace_kind,
            "trace_status" => trace_status,
        ),
        "profiles" => profiles,
    )
    path = joinpath(directory, "backend-profile.toml")
    open(path, "w") do io
        TOML.print(io, record; sorted = true)
    end
    return path
end

end

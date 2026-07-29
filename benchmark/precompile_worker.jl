VERSION == v"1.12.6" ||
    error("The refactor benchmark target is Julia 1.12.6; found $VERSION")

function option(name, default)
    prefix = "--$name="
    argument = findfirst(value -> startswith(value, prefix), ARGS)
    return isnothing(argument) ? default : ARGS[argument][(length(prefix) + 1):end]
end

function directory_bytes(root)
    bytes = Int64(0)
    for (directory, _, names) in walkdir(root), name in names
        bytes += filesize(joinpath(directory, name))
    end
    return bytes
end

function link_offline_sources!(isolated_depot)
    for entry in ("packages", "artifacts", "registries", "clones", "dev")
        source = findfirst(path -> isdir(joinpath(path, entry)), Base.DEPOT_PATH)
        source === nothing && continue
        symlink(joinpath(Base.DEPOT_PATH[source], entry), joinpath(isolated_depot, entry);
            dir_target = true)
    end
    return isolated_depot
end

backend_name = option("backend", "cpu")
backend_name in ("cpu", "metal", "amdgpu") || error(
    "performance comparison precompile measurement requires cpu, metal, or amdgpu")

repository_root = normpath(joinpath(@__DIR__, ".."))
base_project = joinpath(@__DIR__, "Project.toml")
backend_project = backend_name == "metal" ?
    joinpath(@__DIR__, "backends", "metal", "Project.toml") :
    joinpath(@__DIR__, "backends", "amdgpu", "Project.toml")

base_precompile_seconds, backend_precompile_seconds, isolated_cache_bytes =
        mktempdir() do isolated_depot
    link_offline_sources!(isolated_depot)
    common_environment = (
        "JULIA_DEPOT_PATH" => isolated_depot,
        "JULIA_LOAD_PATH" => "@:@stdlib",
        "JULIA_PKG_OFFLINE" => "true",
        "JULIA_PKG_PRECOMPILE_AUTO" => "0",
    )
    base_command = `$(Base.julia_cmd()) --project=$base_project --startup-file=no -e 'using Pkg; Pkg.precompile(; strict=true)'`
    base_seconds = @elapsed run(addenv(base_command, common_environment...))
    backend_seconds = 0.0
    if backend_name != "cpu"
        backend_command = `$(Base.julia_cmd()) --project=$backend_project --startup-file=no -e 'using Pkg; Pkg.precompile(; strict=true)'`
        backend_seconds = @elapsed run(addenv(
            backend_command, common_environment...))
    end
    compiled_directory = joinpath(isolated_depot, "compiled")
    cache_bytes = isdir(compiled_directory) ?
        directory_bytes(compiled_directory) : Int64(0)
    return base_seconds, backend_seconds, cache_bytes
end

# Provenance and serialization occur only after isolated precompilation has completed.
include(joinpath(@__DIR__, "src", "PottsBenchmarks.jl"))
using .PottsBenchmarks
using Dates
using TOML

provenance = PottsBenchmarks.provenance(backend_name, "isolated-precompile")
precompile_harness_checksum = PottsBenchmarks.file_set_checksum(
    [joinpath(@__DIR__, "precompile_worker.jl")])
process_id = get(ENV, "POTTS_BENCHMARK_PROCESS_ID",
    string(Dates.format(now(UTC), dateformat"yyyymmddTHHMMSS.sss"), "-", getpid()))
record = Dict(
    "schema_version" => PottsBenchmarks.PerformanceComparison.PERFORMANCE_SCHEMA_VERSION,
    "record_kind" => "phase12-precompile-run",
    "recorded_at_utc" => string(now(UTC)),
    "comparison_identity" => Dict(
        "contract_version" => PottsBenchmarks.PerformanceComparison.PERFORMANCE_CONTRACT_VERSION,
        "precompile_workload_version" => "isolated-environment-1.0.0",
        "precompile_harness_tree_sha256" => precompile_harness_checksum,
        "backend" => backend_name,
        "hardware_id" => provenance["hardware_id"],
        "julia_version" => string(VERSION),
        "architecture" => string(Sys.ARCH),
        "os" => string(Sys.KERNEL),
        "julia_threads" => Threads.nthreads(),
    ),
    "run" => Dict(
        "process_id" => process_id,
        "independence_unit" => "fresh isolated writable depot",
        "network_policy" => "offline",
    ),
    "provenance" => provenance,
    "metrics" => Dict(
        "base_environment_precompile_seconds" => base_precompile_seconds,
        "backend_environment_precompile_seconds" => backend_precompile_seconds,
        "total_precompile_seconds" =>
            base_precompile_seconds + backend_precompile_seconds,
        "isolated_depot_bytes" => isolated_cache_bytes,
    ),
)

issues = PottsBenchmarks.PerformanceComparison.validate_precompile_record(record)
isempty(issues) || error("refusing to write invalid performance comparison precompile result:\n- " *
                         join(issues, "\n- "))
directory = joinpath(PottsBenchmarks.RESULTS_ROOT, provenance["subject_id"],
    "precompile", backend_name)
mkpath(directory)
timestamp = Dates.format(now(UTC), dateformat"yyyymmddTHHMMSS")
path = joinpath(directory, "$(timestamp)-precompile-run-$process_id.toml")
open(path, "w") do io
    TOML.print(io, record; sorted = true)
end
println("PERFORMANCE_PRECOMPILE_RESULT=", path)

module PottsTestTelemetry

using ParallelTestRunner
using Test
using TOML

struct TelemetryRecord <: ParallelTestRunner.AbstractTestRecord
    base::ParallelTestRunner.TestRecord
end

function _directory()
    directory = get(ENV, "POTTS_TEST_TELEMETRY_DIR", "")
    isempty(directory) && return nothing
    mkpath(directory)
    return directory
end

function _safe_name(name)
    return replace(string(name), r"[^A-Za-z0-9_.-]" => "-")
end

function _loaded_extensions()
    extensions = String[]
    package_ids = collect(keys(Base.loaded_modules))
    for extension in package_ids
        extension.uuid === nothing && continue
        for parent in package_ids
            parent.uuid === nothing && continue
            extension.uuid == Base.uuid5(parent.uuid, extension.name) || continue
            push!(extensions, "$(parent.name)=>$(extension.name)")
            break
        end
    end
    return sort!(unique!(extensions))
end

function record(name, values)
    directory = _directory()
    directory === nothing && return nothing
    path = joinpath(directory, string(_safe_name(name), "-", getpid(), "-", time_ns(), ".toml"))
    open(path, "w") do io
        TOML.print(io, Dict("measurement" => merge(
            Dict("name" => string(name), "process_id" => getpid(), "thread_count" => Threads.nthreads()),
            Dict(string(key) => value for (key, value) in values),
        )))
    end
    return path
end

function ParallelTestRunner.execute(
    ::Type{TelemetryRecord}, mod::Module, expression, name, start_time, custom_args,
)
    base = ParallelTestRunner.execute(
        ParallelTestRunner.TestRecord, mod, expression, name, start_time, custom_args,
    )
    counts = Test.get_test_counts(base.value)
    record("fixture-$(name)", Dict(
        "kind" => "parallel_test_runner_fixture",
        "fixture" => name,
        "status" => counts.fails == 0 && counts.errors == 0 ? "success" : "failure",
        "loaded_extension_modules" => _loaded_extensions(),
        "worker_total_seconds" => base.time,
        "compilation_seconds" => base.compile_time,
        "scientific_execution_seconds" => max(0.0, base.time - base.compile_time),
        "gc_seconds" => base.gctime,
        "allocated_bytes" => Int(base.bytes),
        "maximum_rss_bytes" => Int(base.rss),
        "scheduled_total_seconds" => base.total_time,
    ))
    return TelemetryRecord(base)
end

end

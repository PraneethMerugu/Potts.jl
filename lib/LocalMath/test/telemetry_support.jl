module LocalMathTestTelemetry

using TOML

function include_fixture(
        target::Module, path::AbstractString, label::AbstractString;
        kind = "fixture", ordinal::Integer = 0,
    )
    telemetry_directory = get(ENV, "LOCALMATH_CI_TELEMETRY", "")
    isempty(telemetry_directory) && return Base.include(target, path)

    result = @timed Base.include(target, path)
    mkpath(telemetry_directory)
    safe_label = replace(label, r"[^A-Za-z0-9_.-]" => "_")
    output = joinpath(
        telemetry_directory,
        "$(kind)-$(getpid())-$(safe_label).toml",
    )
    open(output, "w") do stream
        TOML.print(stream, Dict(
            "schema_version" => 1,
            "kind" => kind,
            "fixture" => label,
            "ordinal" => ordinal,
            "first_family" => ordinal == 1,
            "process_id" => getpid(),
            "elapsed_seconds" => result.time,
            "compile_seconds" => result.compile_time,
            "recompile_seconds" => result.recompile_time,
            "gc_seconds" => result.gctime,
            "allocated_bytes" => result.bytes,
            "rss_bytes" => Sys.maxrss(),
        ))
    end
    return result.value
end

end

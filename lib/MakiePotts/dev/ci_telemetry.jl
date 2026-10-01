module CITelemetry

    export observe, record_duration

    escape_json(value) = replace(
        string(value), '\\' => "\\\\", '"' => "\\\"", '\n' => "\\n", '\r' => "\\r"
    )

    function emit_record(label, elapsed_seconds, status; kind = "phase", detail = "")
        path = get(ENV, "CI_TELEMETRY_PATH", "")
        isempty(path) && return nothing
        mkpath(dirname(path))
        fields = (
            kind = kind,
            label = label,
            elapsed_seconds = elapsed_seconds,
            status = status,
            detail = detail,
            repository = get(ENV, "GITHUB_REPOSITORY", "local"),
            job = get(ENV, "GITHUB_JOB", "local"),
            run_id = get(ENV, "GITHUB_RUN_ID", "local"),
            revision = get(ENV, "GITHUB_SHA", "local"),
            runner_os = get(ENV, "RUNNER_OS", string(Sys.KERNEL)),
            localmath_ref = get(ENV, "LOCALMATH_REF", "unspecified"),
            corepotts_ref = get(ENV, "COREPOTTS_REF", "unspecified"),
            potts_ref = get(ENV, "POTTS_REF", "unspecified"),
        )
        open(path, "a") do io
            print(io, '{')
            for (index, (key, value)) in enumerate(pairs(fields))
                index == 1 || print(io, ',')
                print(io, '"', key, "\":")
                if value isa Number
                    print(io, value)
                else
                    print(io, '"', escape_json(value), '"')
                end
            end
            println(io, '}')
        end
        return nothing
    end

    observe(label, detail) = emit_record(
        label, 0.0, "observed"; kind = "observation", detail
    )

    function record_duration(action, label; kind = "phase")
        started = time_ns()
        status = "success"
        try
            return action()
        catch
            status = "failure"
            rethrow()
        finally
            elapsed = (time_ns() - started) / 1.0e9
            emit_record(label, elapsed, status; kind)
        end
    end

    function main(arguments)
        if length(arguments) >= 3 && arguments[1] == "measure" && arguments[3] == "--"
            command = Cmd(arguments[4:end])
            return record_duration(arguments[2]) do
                run(command)
            end
        elseif length(arguments) == 3 && arguments[1] == "observe"
            return observe(arguments[2], arguments[3])
        end
        error(
            "usage: julia dev/ci_telemetry.jl measure LABEL -- COMMAND [ARG ...] " *
                "or julia dev/ci_telemetry.jl observe LABEL DETAIL"
        )
    end

end

if abspath(PROGRAM_FILE) == @__FILE__
    CITelemetry.main(ARGS)
end

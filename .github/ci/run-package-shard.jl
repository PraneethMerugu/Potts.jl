using Dates
using Pkg

function record_phase(name, action)
    output = get(ENV, "CI_TELEMETRY_FILE", "ci-telemetry/phases.tsv")
    mkpath(dirname(output))
    isfile(output) || open(output, "w") do io
        println(io, "phase\tstarted_at\tfinished_at\tduration_seconds\tstatus")
    end
    started_at = now(UTC)
    started = time_ns()
    status = "success"
    try
        return action()
    catch
        status = "failure"
        rethrow()
    finally
        finished_at = now(UTC)
        duration = (time_ns() - started) / 1.0e9
        open(output, "a") do io
            println(io, join((name, started_at, finished_at, duration, status), '\t'))
        end
    end
end

shard = ENV["POTTS_TEST_SHARD"]
previous_auto = get(ENV, "JULIA_PKG_PRECOMPILE_AUTO", nothing)
record_phase("environment-resolution") do
    ENV["JULIA_PKG_PRECOMPILE_AUTO"] = "0"
    try
        Pkg.activate(; temp = true)
        Pkg.develop([
            PackageSpec(; path) for path in ("deps/LocalMath", "deps/CorePotts", ".")
        ])
    finally
        if previous_auto === nothing
            delete!(ENV, "JULIA_PKG_PRECOMPILE_AUTO")
        else
            ENV["JULIA_PKG_PRECOMPILE_AUTO"] = previous_auto
        end
    end
end

# Keep Pkg.test as the ordinary authority for test-environment resolution and
# automatic dependency precompilation. Its output is retained and summarized.
Pkg.test("Potts"; test_args = ["--jobs=2", "--verbose", "--shard=$shard"])

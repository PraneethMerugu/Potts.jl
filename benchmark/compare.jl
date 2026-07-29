VERSION == v"1.12.6" ||
    error("The refactor benchmark target is Julia 1.12.6; found $VERSION")

include(joinpath(@__DIR__, "src", "PerformanceComparison.jl"))
using .PerformanceComparison
using TOML

function options(arguments)
    values = Dict("baseline" => String[], "candidate" => String[])
    minimum_processes = 3
    output = nothing
    kind = "warm"
    for argument in arguments
        if startswith(argument, "--baseline=")
            push!(values["baseline"], split(argument, "="; limit = 2)[2])
        elseif startswith(argument, "--candidate=")
            push!(values["candidate"], split(argument, "="; limit = 2)[2])
        elseif startswith(argument, "--minimum-processes=")
            minimum_processes = parse(Int, split(argument, "="; limit = 2)[2])
        elseif startswith(argument, "--output=")
            output = split(argument, "="; limit = 2)[2]
        elseif startswith(argument, "--kind=")
            kind = split(argument, "="; limit = 2)[2]
        else
            throw(ArgumentError("unknown comparison option `$argument`"))
        end
    end
    isempty(values["baseline"]) && throw(ArgumentError(
        "provide at least one --baseline=PATH"))
    isempty(values["candidate"]) && throw(ArgumentError(
        "provide at least one --candidate=PATH"))
    kind in ("warm", "cold", "precompile") || throw(ArgumentError(
        "--kind must be warm, cold, or precompile"))
    return values, minimum_processes, output, kind
end

function main(arguments)
    paths, minimum_processes, output, kind = options(arguments)
    loader, comparator = if kind == "warm"
        (load_record, compare_record_groups)
    elseif kind == "cold"
        (load_cold_record, compare_cold_record_groups)
    else
        (load_precompile_record, compare_precompile_record_groups)
    end
    baseline = loader.(paths["baseline"])
    candidate = loader.(paths["candidate"])
    comparison = comparator(baseline, candidate; minimum_processes)
    if kind == "warm"
        print_comparison(comparison)
    else
        TOML.print(stdout, comparison; sorted = true)
    end
    if output !== nothing
        open(output, "w") do io
            TOML.print(io, comparison; sorted = true)
        end
    end
    return comparison["passed"] ? 0 : 1
end

exit(main(ARGS))

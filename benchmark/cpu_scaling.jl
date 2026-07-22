VERSION == v"1.12.6" ||
    error("The refactor benchmark target is Julia 1.12.6; found $VERSION")

include(joinpath(@__DIR__, "src", "Phase12Comparison.jl"))
using .Phase12Comparison
using TOML

function options(arguments)
    groups = Dict{Int, Vector{String}}()
    minimum_processes = 3
    output = nothing
    for argument in arguments
        if startswith(argument, "--group=")
            value = split(argument, "="; limit = 2)[2]
            fields = split(value, ":"; limit = 2)
            length(fields) == 2 || throw(ArgumentError(
                "--group requires THREADS:PATH"))
            threads = parse(Int, fields[1])
            push!(get!(groups, threads, String[]), fields[2])
        elseif startswith(argument, "--minimum-processes=")
            minimum_processes = parse(Int, split(argument, "="; limit = 2)[2])
        elseif startswith(argument, "--output=")
            output = split(argument, "="; limit = 2)[2]
        else
            throw(ArgumentError("unknown CPU scaling option `$argument`"))
        end
    end
    isempty(groups) && throw(ArgumentError(
        "provide repeated --group=THREADS:PATH records"))
    return groups, minimum_processes, output
end

function main(arguments)
    paths, minimum_processes, output = options(arguments)
    groups = Dict(
        threads => load_record.(records) for (threads, records) in paths)
    summary = summarize_cpu_scaling(groups; minimum_processes)
    TOML.print(stdout, summary; sorted = true)
    if output !== nothing
        open(output, "w") do io
            TOML.print(io, summary; sorted = true)
        end
    end
    return summary["comparable"] ? 0 : 1
end

exit(main(ARGS))

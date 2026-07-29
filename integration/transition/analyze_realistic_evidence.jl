#!/usr/bin/env julia

using TOML

include(joinpath(@__DIR__, "TransitionEmpirical.jl"))
include(joinpath(@__DIR__, "RealisticScaleRunner.jl"))
include(joinpath(@__DIR__, "RealisticEvidenceArchive.jl"))
include(joinpath(@__DIR__, "RealisticEvidenceAnalysis.jl"))
include(joinpath(@__DIR__, "CommandLine.jl"))

using .RealisticScaleRunner
using .RealisticEvidenceAnalysis
using .TransitionCommandLine: parse_options

function main(args)
    parsed = parse_options(args)
    options = parsed.options
    haskey(options, "reference") || throw(ArgumentError("--reference is required"))
    haskey(options, "candidate") || throw(ArgumentError("--candidate is required"))
    references = TOML.parsefile.(split(options["reference"], ','))
    candidates = TOML.parsefile.(split(options["candidate"], ','))
    length(references) == length(candidates) || throw(ArgumentError(
        "comma-separated --reference and --candidate lists must have equal lengths"))
    comparison = Symbol(get(options, "comparison", "paired_algorithm"))
    manifest = load_realistic_manifest()
    result = length(references) == 1 ?
        analyze_realistic_equivalence(only(references), only(candidates);
            comparison, manifest) :
        analyze_realistic_family(references, candidates; comparison, manifest)
    output = abspath(get(options, "output", "realistic-evidence-analysis.toml"))
    write_realistic_analysis(output, result; force = parsed.force)
    println("wrote transition-kernel realistic $(result["result"]["status"]) to $output")
    result["result"]["qualification_eligible"] &&
        !result["result"]["qualification_passed"] && exit(1)
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)

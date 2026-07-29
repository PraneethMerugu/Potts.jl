#!/usr/bin/env julia

using CorePotts

include(joinpath(@__DIR__, "..", "TestBackend.jl"))
include(joinpath(@__DIR__, "TransitionKernelOracle.jl"))
include(joinpath(@__DIR__, "TransitionKernelAnalysis.jl"))
include(joinpath(@__DIR__, "TransitionEvidenceArchive.jl"))
include(joinpath(@__DIR__, "TransitionEmpirical.jl"))
include(joinpath(@__DIR__, "CheckerboardOracle.jl"))
include(joinpath(@__DIR__, "TransitionFixtures.jl"))
include(joinpath(@__DIR__, "ProductionTransitionSampler.jl"))
include(joinpath(@__DIR__, "ProductionEvidenceArchive.jl"))

using .TestBackend
using .TransitionFixtures
using .ProductionTransitionSampler
using .ProductionEvidenceArchive

function parse_options(args)
    options = Dict{String, String}()
    force = false
    index = 1
    while index <= length(args)
        argument = args[index]
        if argument == "--force"
            force = true
            index += 1
            continue
        end
        startswith(argument, "--") || throw(ArgumentError(
            "unexpected positional argument: $argument"))
        index < length(args) || throw(ArgumentError("missing value for $argument"))
        options[argument[3:end]] = args[index + 1]
        index += 2
    end
    return (; options, force)
end

function source_revision(profile::Symbol)
    revision = get(ENV, "GITHUB_SHA", "")
    isempty(revision) && (revision = readchomp(`git rev-parse HEAD`))
    dirty = !isempty(readchomp(`git status --porcelain`))
    profile === :qualification && dirty && throw(ArgumentError(
        "qualification evidence requires a clean committed source revision"))
    return dirty ? string(revision, "-dirty") : revision
end

function selected_row(rows, selector::AbstractString)
    parsed = tryparse(Int, selector)
    parsed === nothing || return rows[parsed]
    match = findfirst(row -> row.row_id == selector, rows)
    match === nothing && throw(ArgumentError("unknown transition-kernel row: $selector"))
    return rows[match]
end

function main(args)
    parsed = parse_options(args)
    options = parsed.options
    profile = Symbol(get(options, "profile", "diagnostic"))
    profile in (:diagnostic, :qualification) || throw(ArgumentError(
        "--profile must be diagnostic or qualification"))
    manifest = load_transition_manifest()
    rows = empirical_fixture_rows(manifest)
    row = selected_row(rows, get(options, "row", "1"))
    algorithm_text = get(options, "algorithm", "SequentialCPM")
    algorithm = algorithm_symbol(algorithm_text)
    registered = Int(manifest["empirical_sampling"]["replicas_per_source_state"])
    default_replicas = profile === :qualification ? registered : 4096
    replicas = parse(Int, get(options, "replicas", string(default_replicas)))
    profile === :qualification && replicas != registered && throw(ArgumentError(
        "qualification profile requires exactly $registered replicas"))
    fixture = build_transition_fixture(row; manifest)
    revision = source_revision(profile)
    backend_name = lowercase(BACKEND_GROUP == "AMDGPU" ? "rocm" : BACKEND_GROUP)
    algorithm_name = algorithm === :sequential ? "SequentialCPM" : "CheckerboardSweepCPM"
    command = join(vcat(["julia --project=integration",
        "integration/transition/run_transition_empirical.jl"], args), ' ')

    root = normpath(joinpath(@__DIR__, "..", ".."))
    default_name = join((row.row_id, lowercase(algorithm_name), String(profile)), '-') * ".toml"
    output = abspath(get(options, "output", joinpath(root, "design", "evidence",
        "phase-13", "empirical", backend_name, default_name)))
    record = if !fixture.production_supported
        build_limited_domain_evidence(fixture, row, algorithm; backend = backend_name,
            manifest, source_revision = revision, reproduction_command = command)
    else
        oracle = oracle_probability_row(fixture, algorithm)
        support = count(>(0), oracle)
        maximum_support = Int(manifest["empirical_sampling"]["maximum_oracle_support"])
        if support > maximum_support
            build_limited_domain_evidence(fixture, row, algorithm;
                backend = backend_name, manifest, source_revision = revision,
                reproduction_command = command,
                limitation = "oracle support $support exceeds registered empirical cap $maximum_support")
        else
            sample = sample_production_row(fixture, algorithm; replicas,
                seed_base = parse(UInt64, manifest["empirical_sampling"]["seed_base_hex"]),
                backend = BACKEND)
            build_production_evidence(fixture, row, sample; profile, manifest,
                source_revision = revision, reproduction_command = command)
        end
    end
    write_production_evidence(output, record; force = parsed.force)
    println("wrote transition-kernel $(record["result"]["status"]) evidence to $output")
    return record["result"]["status"] == "statistical-fail" &&
        profile === :qualification ? exit(1) : nothing
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)

#!/usr/bin/env julia

include(joinpath(@__DIR__, "..", "TestBackend.jl"))
include(joinpath(@__DIR__, "TransitionEmpirical.jl"))
include(joinpath(@__DIR__, "RealisticScaleRunner.jl"))
include(joinpath(@__DIR__, "RealisticEvidenceArchive.jl"))
include(joinpath(@__DIR__, "CommandLine.jl"))

using .TestBackend
using .RealisticScaleRunner
using .RealisticEvidenceArchive
using .TransitionCommandLine: parse_options

function source_revision(profile::Symbol)
    revision = get(ENV, "GITHUB_SHA", "")
    isempty(revision) && (revision = readchomp(`git rev-parse HEAD`))
    dirty = !isempty(readchomp(`git status --porcelain`))
    profile === :qualification && dirty && throw(ArgumentError(
        "qualification evidence requires a clean committed source revision"))
    return dirty ? string(revision, "-dirty") : revision
end

function main(args)
    parsed = parse_options(args)
    options = parsed.options
    profile = Symbol(get(options, "profile", "diagnostic"))
    profile in (:diagnostic, :qualification) || throw(ArgumentError(
        "--profile must be diagnostic or qualification"))
    manifest = load_realistic_manifest()
    workload = realistic_workload(get(options, "workload", "adhesion_volume_relaxation"),
        manifest)
    algorithm = get(options, "algorithm", "SequentialCPM")
    algorithm in ("SequentialCPM", "CheckerboardSweepCPM") || throw(ArgumentError(
        "--algorithm must be SequentialCPM or CheckerboardSweepCPM"))
    registered = Int(manifest["replicas_per_identity"])
    backend_name = lowercase(BACKEND_GROUP == "AMDGPU" ? "rocm" : BACKEND_GROUP)
    profile === :qualification &&
        !realistic_identity_applicable(algorithm, backend_name, manifest) &&
        throw(ArgumentError(
            "$algorithm on $backend_name is outside the registered realistic qualification domain"))
    replicas = parse(Int, get(options, "replicas",
        string(profile === :qualification ? registered : 2)))
    profile === :qualification && replicas != registered && throw(ArgumentError(
        "qualification profile requires exactly $registered replicas"))
    replicas > 0 || throw(ArgumentError("--replicas must be positive"))
    revision = source_revision(profile)
    seed_base = parse(UInt64, manifest["seed_base_hex"])
    summaries = Dict{String, Any}[]
    for index in 1:replicas
        push!(summaries, run_realistic_replica(workload, algorithm;
            seed = seed_base + UInt64(index - 1), backend = BACKEND, manifest))
        println("completed realistic replica $index/$replicas")
    end
    command = join(vcat(["julia --project=integration",
        "integration/transition/run_realistic_evidence.jl"], args), ' ')
    record = build_realistic_evidence(workload, algorithm, summaries;
        backend = backend_name, profile, manifest, source_revision = revision,
        reproduction_command = command)
    root = normpath(joinpath(@__DIR__, "..", ".."))
    default_name = join((workload["id"], lowercase(algorithm), String(profile)), '-') * ".toml"
    output = abspath(get(options, "output", joinpath(root, "design", "evidence",
        "phase-13", "realistic", backend_name, default_name)))
    write_realistic_evidence(output, record; force = parsed.force)
    println("wrote transition-kernel realistic evidence to $output")
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)

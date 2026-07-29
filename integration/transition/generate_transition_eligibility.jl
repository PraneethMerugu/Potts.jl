#!/usr/bin/env julia

using CorePotts
using SHA
using TOML

include(joinpath(@__DIR__, "TransitionKernelOracle.jl"))
include(joinpath(@__DIR__, "TransitionEmpirical.jl"))
include(joinpath(@__DIR__, "CheckerboardOracle.jl"))
include(joinpath(@__DIR__, "TransitionFixtures.jl"))
include(joinpath(@__DIR__, "ProductionTransitionSampler.jl"))

using .TransitionFixtures
using .ProductionTransitionSampler

function generate(output)
    manifest = load_transition_manifest()
    maximum_support = Int(manifest["empirical_sampling"]["maximum_oracle_support"])
    records = Dict{String, Any}[]
    for row in empirical_fixture_rows(manifest)
        fixture = build_transition_fixture(row; manifest)
        for algorithm in (:sequential, :checkerboard)
            support = nothing
            limitation = fixture.production_limitation
            if fixture.production_supported
                probabilities = oracle_probability_row(fixture, algorithm)
                support = count(>(0), probabilities)
                support > maximum_support && (limitation =
                    "oracle support $support exceeds registered empirical cap $maximum_support")
            end
            push!(records, Dict{String, Any}(
                "row_id" => row.row_id,
                "fixture" => fixture.id,
                "algorithm" => algorithm === :sequential ?
                    "SequentialCPM" : "CheckerboardSweepCPM",
                "production_supported" => fixture.production_supported,
                "oracle_support" => support === nothing ? -1 : support,
                "empirical_eligible" => limitation === nothing,
                "disposition" => limitation === nothing ?
                    "qualification-required" : "limited-domain-unqualified",
                "limitation" => limitation === nothing ? "" : String(limitation)))
        end
    end
    record = Dict{String, Any}(
        "schema_version" => "1.0.0",
        "fixture_manifest" => "../../../audits/phase-13-fixture-manifest.toml",
        "sampling_plan" => manifest["statistical_plan"],
        "maximum_oracle_support" => maximum_support,
        "registered_rows" => length(records),
        "eligible_rows" => count(item -> item["empirical_eligible"], records),
        "limited_rows" => count(item -> !item["empirical_eligible"], records),
        "rows" => records)
    mkpath(dirname(output))
    open(output, "w") do io
        TOML.print(io, record; sorted = true)
    end
    record["sha256"] = bytes2hex(open(SHA.sha256, output))
    return record
end

function main(args)
    root = normpath(joinpath(@__DIR__, "..", ".."))
    output = isempty(args) ? joinpath(root, "design", "evidence", "phase-13",
        "empirical", "eligibility.toml") : abspath(first(args))
    record = generate(output)
    println("wrote $(record["eligible_rows"]) eligible and $(record["limited_rows"]) limited transition-kernel rows to $output")
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main(ARGS)

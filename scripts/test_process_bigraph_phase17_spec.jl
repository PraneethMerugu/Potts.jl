#!/usr/bin/env julia

using TOML
using Test

const ROOT = normpath(joinpath(@__DIR__, ".."))
const CHECKER = joinpath(ROOT, "scripts", "check_process_bigraph_phase17_spec.jl")

const REQUIRED_FILES = [
    "design/audits/process-bigraph-phase17-owner-interview-round-1.md",
    "design/audits/process-bigraph-phase17-owner-interview-round-2.md",
    "design/audits/process-bigraph-phase17-owner-interview-round-3.md",
    "design/audits/process-bigraph-phase17-implementation-plan.md",
    "design/audits/process-bigraph-phase17-specification-audit.md",
    "spec/decisions/0042-process-bigraph-model-and-documentation-productization.md",
    "spec/phase-17-process-bigraph-model-and-documentation-productization.md",
    "spec/process-bigraph-phase17-entry-v1.toml",
    "spec/process-bigraph-phase17-api-v1.toml",
    "spec/process-bigraph-phase17-api-inventory-v1.toml",
    "spec/process-bigraph-phase17-documentation-quality-v1.toml",
    "spec/process-bigraph-phase17-browser-qa-v1.toml",
    "spec/process-bigraph-phase17-qualification-v1.toml",
    "scripts/check_process_bigraph_phase17_spec.jl",
    "scripts/test_process_bigraph_phase17_spec.jl",
    "scripts/check_process_bigraph_phase17_api.jl",
    "scripts/test_process_bigraph_phase17_api.jl",
    "scripts/check_process_bigraph_phase17_docs.jl",
    "scripts/check_process_bigraph_phase17_browser_contract.jl",
    "scripts/check_process_bigraph_phase17_internal_use.jl",
    "scripts/check_process_bigraph_phase17_closure.jl",
]

function copy_packet(destination)
    for relative in REQUIRED_FILES
        source = joinpath(ROOT, relative)
        target = joinpath(destination, relative)
        mkpath(dirname(target))
        cp(source, target; force=true)
    end
end

function checker_command(root)
    `$(Base.julia_cmd()) --startup-file=no $(joinpath(root, "scripts",
        "check_process_bigraph_phase17_spec.jl")) --root=$(root)`
end

function rewrite_toml(mutate!, root, relative)
    path = joinpath(root, relative)
    document = TOML.parsefile(path)
    mutate!(document)
    open(path, "w") do io
        TOML.print(io, document; sorted=true)
    end
end

function rejects(mutate!)
    mktempdir() do temp
        copy_packet(temp)
        mutate!(temp)
        !success(pipeline(checker_command(temp);
            stdout=devnull, stderr=devnull))
    end
end

@testset "Phase 17 specification checker" begin
    mktempdir() do temp
        copy_packet(temp)
        @test success(pipeline(checker_command(temp);
            stdout=devnull, stderr=devnull))
    end

    @test rejects() do temp
        rewrite_toml(
            temp,
            "spec/process-bigraph-phase17-entry-v1.toml",
        ) do document
            document["implementation_authorized"] = false
        end
    end

    @test rejects() do temp
        rewrite_toml(
            temp,
            "spec/process-bigraph-phase17-documentation-quality-v1.toml",
        ) do document
            pop!(document["pages"])
        end
    end

    @test rejects() do temp
        rewrite_toml(
            temp,
            "spec/process-bigraph-phase17-browser-qa-v1.toml",
        ) do document
            document["waivers_allowed"] = true
        end
    end

    @test rejects() do temp
        rewrite_toml(
            temp,
            "spec/process-bigraph-phase17-api-v1.toml",
        ) do document
            document["process_bigraphs"]["user_additions"]["exported"] =
                ["managed_field_process", "internal_session"]
        end
    end

    @test rejects() do temp
        rewrite_toml(
            temp,
            "spec/process-bigraph-phase17-qualification-v1.toml",
        ) do document
            pop!(document["requirements"])
        end
    end
end

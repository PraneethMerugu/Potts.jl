#!/usr/bin/env julia

using Test

const ROOT = normpath(joinpath(@__DIR__, ".."))
const CHECKER = joinpath(ROOT, "scripts", "check_process_bigraph_phase17_api.jl")

function checker_succeeds(root)
    process = run(ignorestatus(`$(Base.julia_cmd()) --startup-file=no $CHECKER --root=$root`))
    return success(process)
end

function mutated_copy(transform)
    temporary = mktempdir()
    for relative in (
        "spec/process-bigraph-phase17-api-v1.toml",
        "spec/process-bigraph-phase17-api-inventory-v1.toml",
        "spec/process-bigraph-phase17-entry-v1.toml",
        "lib/ProcessBigraphs/src/ProcessBigraphs.jl",
    )
        target = joinpath(temporary, relative)
        mkpath(dirname(target))
        cp(joinpath(ROOT, relative), target)
    end
    transform(temporary)
    return temporary
end

@testset "Phase 17 API inventory checker" begin
    @test checker_succeeds(ROOT)

    root = mutated_copy() do temporary
        path = joinpath(temporary,
            "lib", "ProcessBigraphs", "src", "ProcessBigraphs.jl")
        open(path, "a") do io
            println(io, "\nexport UnclassifiedFixture")
        end
    end
    @test !checker_succeeds(root)

    root = mutated_copy() do temporary
        path = joinpath(temporary,
            "spec", "process-bigraph-phase17-api-inventory-v1.toml")
        text = read(path, String)
        write(path, replace(text,
            "unclassified_allowed = 0" => "unclassified_allowed = 1";
            count=1))
    end
    @test !checker_succeeds(root)

    root = mutated_copy() do temporary
        path = joinpath(temporary,
            "spec", "process-bigraph-phase17-api-inventory-v1.toml")
        text = read(path, String)
        write(path, replace(text,
            "class = \"exported_user\"" => "class = \"unknown\"";
            count=1))
    end
    @test !checker_succeeds(root)
end

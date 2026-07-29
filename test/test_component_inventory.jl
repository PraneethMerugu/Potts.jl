using TOML

@testset "model authoring stable-component inventory" begin
    path = joinpath(@__DIR__, "..", "design", "audits",
        "phase-11-stable-component-inventory.toml")
    inventory = TOML.parsefile(path)
    entries = inventory["component"]
    statuses = Set(("covered", "uncovered", "excluded"))
    exported_toolkit_names = Set(names(PottsToolkit))
    @test all(entry -> entry["status"] in statuses, entries)
    @test length(unique(entry["core"] for entry in entries)) == length(entries)
    for entry in entries
        @test isdefined(CorePotts, Symbol(entry["core"]))
        if entry["status"] == "covered"
            @test haskey(entry, "level1")
            level1_name = Symbol(entry["level1"])
            @test isdefined(PottsToolkit, level1_name)
            @test level1_name in exported_toolkit_names
        elseif entry["status"] == "uncovered"
            @test haskey(entry, "level2") || haskey(entry, "level3")
            @test haskey(entry, "reason")
        else
            @test haskey(entry, "reason")
        end
    end
    denominator = count(entry -> entry["status"] != "excluded", entries)
    covered = count(entry -> entry["status"] == "covered", entries)
    coverage = covered / denominator
    @test denominator > 0
    @test coverage >= inventory["coverage_target"]
    @test covered == 72
    @test denominator == 73
end

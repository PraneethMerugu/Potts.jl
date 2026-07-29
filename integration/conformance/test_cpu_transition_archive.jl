using TOML
using SHA

@testset "transition-kernel CPU transition qualification archive" begin
    directory = normpath(joinpath(@__DIR__, "..", "..", "design",
        "evidence", "phase-13", "empirical", "cpu"))
    index = TOML.parsefile(joinpath(directory, "index.toml"))
    @test index["status"] == "all-applicable-cpu-transition-rows-pass-v2"
    @test index["sampling_plan"] == "phase-13-transition-evidence-v2"
    @test index["production_real_type"] == "Float32"
    @test index["supersedes"] == "v1/index.toml"
    @test index["eligible_rows"] == index["passed_rows"] == 8
    @test index["failed_rows"] == 0
    @test length(index["artifacts"]) == 8
    identities = Set{Tuple{String, String}}()
    for artifact in index["artifacts"]
        path = joinpath(directory, artifact["file"])
        @test isfile(path)
        @test bytes2hex(sha256(read(path))) == artifact["sha256"]
        record = TOML.parsefile(path)
        report = ProductionEvidenceArchive.validate_production_evidence(record)
        @test report.valid
        @test record["result"]["status"] == "statistical-pass"
        @test record["result"]["qualification_passed"]
        @test record["sampling"]["profile"] == "qualification"
        @test record["sampling"]["replicas"] == 262_144
        @test record["schema"]["version"] == "1.1.0"
        @test record["environment"]["production_real_type"] == "Float32"
        @test record["identity"]["sampling_plan_version"] == index["sampling_plan"]
        @test record["identity"]["source_revision"] == index["source_revision"]
        push!(identities, (record["identity"]["row_id"],
            record["identity"]["algorithm_identity"]))
    end
    @test length(identities) == 8

    v1_index = TOML.parsefile(joinpath(directory, "v1", "index.toml"))
    @test v1_index["status"] == "superseded-v1-do-not-pool-with-v2"
    @test v1_index["superseded_by"] == "../index.toml"
    @test v1_index["sampling_plan"] == "phase-13-transition-evidence-v1"
    @test length(v1_index["artifacts"]) == 8
end

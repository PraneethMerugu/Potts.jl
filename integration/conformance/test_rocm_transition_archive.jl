using TOML
using SHA

@testset "transition-kernel ROCm transition qualification archive" begin
    empirical = normpath(joinpath(@__DIR__, "..", "..", "design",
        "evidence", "phase-13", "empirical"))
    directory = joinpath(empirical, "rocm")
    cpu_directory = joinpath(empirical, "cpu")
    index = TOML.parsefile(joinpath(directory, "index.toml"))
    cpu_index = TOML.parsefile(joinpath(cpu_directory, "index.toml"))

    @test index["status"] == "all-applicable-rocm-transition-rows-pass-v2"
    @test index["sampling_plan"] == "phase-13-transition-evidence-v2"
    @test index["production_real_type"] == "Float32"
    @test index["eligible_rows"] == index["passed_rows"] == 8
    @test index["failed_rows"] == 0
    @test length(index["artifacts"]) == 8
    @test index["source_revision"] == cpu_index["source_revision"]
    @test sum(run["admitted_artifacts"] for run in index["workflow_runs"]) == 8
    @test Set(run["run_id"] for run in index["workflow_runs"]) ==
          Set([29982959301, 29986444195])

    identities = Set{Tuple{String, String}}()
    for artifact in index["artifacts"]
        path = joinpath(directory, artifact["file"])
        cpu_path = joinpath(cpu_directory, artifact["file"])
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
        @test record["identity"]["backend_identity"] == "rocm"
        @test record["identity"]["sampling_plan_version"] == index["sampling_plan"]
        @test record["identity"]["source_revision"] == index["source_revision"]

        # Identical semantic seeds and the portable Float32 policy yield exact corroborating
        # counts here. Each ROCm row must still pass its own preregistered statistical test above.
        cpu_record = TOML.parsefile(cpu_path)
        @test cpu_record["identity"]["backend_identity"] == "cpu"
        @test cpu_record["identity"]["row_id"] == record["identity"]["row_id"]
        @test cpu_record["identity"]["algorithm_identity"] ==
              record["identity"]["algorithm_identity"]
        @test cpu_record["raw_counts"] == record["raw_counts"]
        @test cpu_record["oracle"]["row"] == record["oracle"]["row"]
        push!(identities, (record["identity"]["row_id"],
            record["identity"]["algorithm_identity"]))
    end
    @test length(identities) == 8
end

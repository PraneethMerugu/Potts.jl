using TOML
using SHA

@testset "transition-kernel CPU realistic qualification archive" begin
    directory = normpath(joinpath(@__DIR__, "..", "..", "design",
        "evidence", "phase-13", "realistic", "cpu"))
    index = TOML.parsefile(joinpath(directory, "index.toml"))
    @test index["status"] ==
        "cpu-realistic-battery-complete-algorithm-equivalence-not-demonstrated"
    @test index["analysis_status"] == "equivalence-fail"
    @test index["workloads"] == 3
    @test index["qualification_identities"] == 6
    @test index["analyzed_endpoints"] == 42
    @test length(index["artifacts"]) == 7
    @test isfile(normpath(joinpath(directory, index["workload_manifest"])))
    @test isfile(normpath(joinpath(directory, index["statistical_registration"])))

    evidence = Dict{Tuple{String, String}, Dict{String, Any}}()
    archived_analysis = nothing
    for artifact in index["artifacts"]
        path = joinpath(directory, artifact["file"])
        @test isfile(path)
        @test bytes2hex(sha256(read(path))) == artifact["sha256"]
        record = TOML.parsefile(path)
        if artifact["kind"] == "qualification-evidence"
            report = RealisticEvidenceArchive.validate_realistic_evidence(record)
            @test report.valid
            @test record["identity"]["source_revision"] == index["source_revision"]
            @test record["identity"]["study_version"] == index["study_version"]
            @test record["identity"]["statistical_plan"] == index["statistical_plan"]
            @test record["identity"]["number_type"] == index["number_type"]
            @test record["sampling"]["profile"] == "qualification"
            @test record["sampling"]["replicas"] ==
                index["registered_replicas_per_identity"]
            identity = (record["identity"]["workload"],
                record["identity"]["algorithm"])
            @test !haskey(evidence, identity)
            evidence[identity] = record
        else
            @test artifact["kind"] == "family-analysis"
            archived_analysis = record
        end
    end
    @test length(evidence) == 6
    @test archived_analysis !== nothing
    @test archived_analysis["schema"]["name"] ==
        "potts-realistic-equivalence-family-analysis"
    @test archived_analysis["multiplicity"]["hypotheses"] == 42
    @test archived_analysis["result"]["qualification_eligible"]
    @test !archived_analysis["result"]["qualification_passed"]
    @test archived_analysis["result"]["status"] == "equivalence-fail"

    manifest = RealisticScaleRunner.load_realistic_manifest(
        normpath(joinpath(directory, index["workload_manifest"])))
    workloads = getindex.(manifest["workloads"], "id")
    references = [evidence[(workload, "SequentialCPM")] for workload in workloads]
    candidates = [evidence[(workload, "CheckerboardSweepCPM")] for workload in workloads]
    recomputed = RealisticEvidenceAnalysis.analyze_realistic_family(
        references, candidates; comparison = :paired_algorithm, manifest)
    test_realistic_analysis_archive(recomputed, archived_analysis)
end

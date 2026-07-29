using TOML
using SHA

@testset "transition-kernel ROCm realistic qualification archive" begin
    root = normpath(joinpath(@__DIR__, "..", "..", "design",
        "evidence", "phase-13", "realistic"))
    root_index = TOML.parsefile(joinpath(root, "index.toml"))
    @test root_index["rocm_portability_analysis"] == "equivalence-fail"
    @test root_index["status"] == "cpu-metal-rocm-realistic-battery-complete"

    directory = joinpath(root, "rocm")
    index = TOML.parsefile(joinpath(directory, "index.toml"))
    @test index["status"] ==
        "rocm-checkerboard-battery-complete-independent-equivalence-not-demonstrated"
    @test index["analysis_status"] == "equivalence-fail"
    @test index["workloads"] == 3
    @test index["qualification_identities"] == 3
    @test index["analyzed_endpoints"] == 42
    @test index["equivalent_endpoints"] == 26
    @test index["non_equivalent_endpoints"] == 16
    @test !index["scientific_replica_values_exactly_equal_to_cpu"]
    @test index["endpoint_pass_pattern_matches_metal"]
    @test length(index["artifacts"]) == 4

    cpu_directory = normpath(joinpath(directory, "..", "cpu"))
    cpu_index = TOML.parsefile(joinpath(cpu_directory, "index.toml"))
    cpu_evidence = Dict{String, Dict{String, Any}}()
    for artifact in cpu_index["artifacts"]
        artifact["kind"] == "qualification-evidence" || continue
        artifact["algorithm"] == "CheckerboardSweepCPM" || continue
        cpu_evidence[artifact["workload"]] =
            TOML.parsefile(joinpath(cpu_directory, artifact["file"]))
    end

    rocm_evidence = Dict{String, Dict{String, Any}}()
    archived_analysis = nothing
    for artifact in index["artifacts"]
        path = joinpath(directory, artifact["file"])
        @test isfile(path)
        @test bytes2hex(sha256(read(path))) == artifact["sha256"]
        record = TOML.parsefile(path)
        if artifact["kind"] == "qualification-evidence"
            report = RealisticEvidenceArchive.validate_realistic_evidence(record)
            @test report.valid
            @test record["identity"]["backend"] == "rocm"
            @test record["identity"]["source_revision"] == index["source_revision"]
            @test record["identity"]["study_version"] == index["study_version"]
            @test record["sampling"]["profile"] == "qualification"
            @test record["sampling"]["replicas"] ==
                index["registered_replicas_per_identity"]
            rocm_evidence[artifact["workload"]] = record
        else
            @test artifact["kind"] == "family-analysis"
            archived_analysis = record
        end
    end
    @test length(rocm_evidence) == 3
    @test archived_analysis !== nothing
    @test archived_analysis["multiplicity"]["hypotheses"] == 42
    @test archived_analysis["result"]["status"] == "equivalence-fail"
    @test count(endpoint -> endpoint["passed"],
        archived_analysis["endpoints"]) == 26

    ignored_summary_fields = Set((
        "backend",
        "device_to_host_transfers",
        "elapsed_measured_seconds",
        "measured_mcs_per_second",
    ))
    any_scientific_difference = false
    for workload in keys(rocm_evidence)
        cpu_summaries = cpu_evidence[workload]["replica_primary_summaries"]
        rocm_summaries = rocm_evidence[workload]["replica_primary_summaries"]
        @test length(cpu_summaries) == length(rocm_summaries) == 512
        scientific_fields = setdiff(Set(keys(first(cpu_summaries))),
            ignored_summary_fields)
        @test scientific_fields == setdiff(Set(keys(first(rocm_summaries))),
            ignored_summary_fields)
        any_scientific_difference |= any(field ->
            getindex.(cpu_summaries, field) != getindex.(rocm_summaries, field),
            scientific_fields)
    end
    @test any_scientific_difference

    manifest = RealisticScaleRunner.load_realistic_manifest(
        normpath(joinpath(directory, index["workload_manifest"])))
    workloads = getindex.(manifest["workloads"], "id")
    recomputed = RealisticEvidenceAnalysis.analyze_realistic_family(
        [cpu_evidence[workload] for workload in workloads],
        [rocm_evidence[workload] for workload in workloads];
        comparison = :independent_backend, manifest)
    test_realistic_analysis_archive(recomputed, archived_analysis)

    metal_analysis = TOML.parsefile(normpath(joinpath(
        directory, "..", "metal", "CheckerboardSweepCPM-portability-family.toml")))
    @test getindex.(archived_analysis["endpoints"], "passed") ==
        getindex.(metal_analysis["endpoints"], "passed")
end

using TOML
using SHA

@testset "transition-kernel Metal realistic qualification archive" begin
    root = normpath(joinpath(@__DIR__, "..", "..", "design",
        "evidence", "phase-13", "realistic"))
    root_index = TOML.parsefile(joinpath(root, "index.toml"))
    @test root_index["study_version"] == "phase13-realistic-workloads-v4"
    @test root_index["cpu_algorithm_analysis"] == "equivalence-fail"
    @test root_index["metal_portability_analysis"] == "equivalence-fail"
    @test root_index["rocm_portability_analysis"] == "equivalence-fail"
    @test root_index["status"] == "cpu-metal-rocm-realistic-battery-complete"

    directory = joinpath(root, "metal")
    index = TOML.parsefile(joinpath(directory, "index.toml"))
    @test index["status"] ==
        "metal-checkerboard-battery-complete-independent-equivalence-not-demonstrated"
    @test index["analysis_status"] == "equivalence-fail"
    @test index["workloads"] == 3
    @test index["qualification_identities"] == 3
    @test index["analyzed_endpoints"] == 42
    @test index["equivalent_endpoints"] == 26
    @test index["non_equivalent_endpoints"] == 16
    @test index["scientific_replica_values_exactly_equal_to_cpu"]
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

    metal_evidence = Dict{String, Dict{String, Any}}()
    archived_analysis = nothing
    for artifact in index["artifacts"]
        path = joinpath(directory, artifact["file"])
        @test isfile(path)
        @test bytes2hex(sha256(read(path))) == artifact["sha256"]
        record = TOML.parsefile(path)
        if artifact["kind"] == "qualification-evidence"
            report = RealisticEvidenceArchive.validate_realistic_evidence(record)
            @test report.valid
            @test record["identity"]["backend"] == "metal"
            @test record["identity"]["source_revision"] == index["source_revision"]
            @test record["identity"]["study_version"] == index["study_version"]
            @test record["sampling"]["profile"] == "qualification"
            @test record["sampling"]["replicas"] ==
                index["registered_replicas_per_identity"]
            metal_evidence[artifact["workload"]] = record
        else
            @test artifact["kind"] == "family-analysis"
            archived_analysis = record
        end
    end
    @test length(metal_evidence) == 3
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
    for workload in keys(metal_evidence)
        cpu_summaries = cpu_evidence[workload]["replica_primary_summaries"]
        metal_summaries = metal_evidence[workload]["replica_primary_summaries"]
        @test length(cpu_summaries) == length(metal_summaries) == 512
        scientific_fields = setdiff(Set(keys(first(cpu_summaries))),
            ignored_summary_fields)
        @test scientific_fields == setdiff(Set(keys(first(metal_summaries))),
            ignored_summary_fields)
        @test all(field -> getindex.(cpu_summaries, field) ==
            getindex.(metal_summaries, field), scientific_fields)
    end

    manifest = RealisticScaleRunner.load_realistic_manifest(
        normpath(joinpath(directory, index["workload_manifest"])))
    workloads = getindex.(manifest["workloads"], "id")
    recomputed = RealisticEvidenceAnalysis.analyze_realistic_family(
        [cpu_evidence[workload] for workload in workloads],
        [metal_evidence[workload] for workload in workloads];
        comparison = :independent_backend, manifest)
    test_realistic_analysis_archive(recomputed, archived_analysis)
end

@testset "transition-kernel isolated CPU timing diagnostics" begin
    directory = normpath(joinpath(@__DIR__, "..", "..", "design",
        "evidence", "phase-13", "realistic", "diagnostic", "cpu-speed"))
    index = TOML.parsefile(joinpath(directory, "index.toml"))
    @test index["profile"] == "diagnostic"
    @test index["replicas_per_identity"] == 8
    @test !index["qualification_evidence"]
    @test index["isolated_processes"]
    @test length(index["artifacts"]) == 6
    for artifact in index["artifacts"]
        path = joinpath(directory, artifact["file"])
        @test bytes2hex(sha256(read(path))) == artifact["sha256"]
        record = TOML.parsefile(path)
        @test RealisticEvidenceArchive.validate_realistic_evidence(record).valid
        @test record["sampling"]["profile"] == "diagnostic"
        @test record["sampling"]["replicas"] == 8
        @test record["identity"]["source_revision"] == index["source_revision"]
    end
end

@testset "transition-kernel generated figure archive" begin
    directory = normpath(joinpath(@__DIR__, "..", "..", "design",
        "evidence", "phase-13", "figures"))
    index = TOML.parsefile(joinpath(directory, "index.toml"))
    @test index["speed_fidelity_status"] == "equivalence-fail"
    @test length(index["figures"]) == 5
    @test length(index["speed_fidelity_points"]) == 3
    @test all(point -> point["timing_replicas_per_algorithm"] == 8,
        index["speed_fidelity_points"])
    @test all(point -> 0.0 <= point["equivalent_endpoint_fraction"] <= 1.0,
        index["speed_fidelity_points"])
    for figure in index["figures"]
        path = joinpath(directory, figure["path"])
        @test isfile(path)
        @test bytes2hex(sha256(read(path))) == figure["sha256"]
    end
end

@testset "transition-kernel Metal device-code inspection archive" begin
    directory = normpath(joinpath(@__DIR__, "..", "..", "design",
        "evidence", "phase-13", "device-code", "metal"))
    index = TOML.parsefile(joinpath(directory, "index.toml"))
    profile_path = joinpath(directory, index["profile_record"])
    @test bytes2hex(sha256(read(profile_path))) ==
        index["profile_record_sha256"]
    profile = TOML.parsefile(profile_path)
    @test profile["provenance"]["git_commit"] == index["source_revision"]
    @test !profile["provenance"]["git_dirty"]
    @test profile["comparison_identity"]["julia_version"] == index["julia_version"]
    @test length(index["algorithms"]) == 2
    for algorithm in index["algorithms"]
        @test algorithm["native_compilation_jobs"] > 0
        @test algorithm["native_code_bytes"] > 0
        @test algorithm["device_operations"] > 0
        @test algorithm["device_command_buffers"] > 0
        @test bytes2hex(sha256(read(joinpath(directory,
            algorithm["native_code"])))) == algorithm["native_code_sha256"]
        @test bytes2hex(sha256(read(joinpath(directory,
            algorithm["trace"])))) == algorithm["trace_sha256"]
    end
end

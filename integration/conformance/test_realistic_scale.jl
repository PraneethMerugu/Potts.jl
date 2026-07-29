using .RealisticScaleRunner
using .RealisticEvidenceArchive
using .RealisticEvidenceAnalysis
using TOML

@testset "transition-kernel realistic-scale registration and runner" begin
    manifest = load_realistic_manifest()
    @test manifest["manifest_version"] == "phase13-realistic-workloads-v4"
    @test manifest["status"] == "registered-applicability-amendment-before-v4-sampling"
    @test manifest["layout_seed_domain"] != manifest["simulation_seed_domain"]
    @test length(manifest["workloads"]) == 3
    @test realistic_identity_applicable("SequentialCPM", "cpu", manifest)
    @test !realistic_identity_applicable("SequentialCPM", "metal", manifest)
    @test !realistic_identity_applicable("SequentialCPM", "rocm", manifest)
    @test all(backend -> realistic_identity_applicable(
        "CheckerboardSweepCPM", backend, manifest), ("cpu", "metal", "rocm"))
    legacy_manifest = deepcopy(manifest)
    delete!(legacy_manifest, "qualification_identities")
    @test realistic_identity_applicable("SequentialCPM", "metal", legacy_manifest)

    seeds = derive_replica_seeds(0x1301000000000001)
    @test seeds == derive_replica_seeds(0x1301000000000001)
    @test seeds.layout != seeds.dynamics
    @test_throws ArgumentError derive_replica_seeds(-1)

    relaxation = deepcopy(realistic_workload("adhesion_volume_relaxation", manifest))
    relaxation["dimensions"] = [16, 16]
    relaxation["cell_count"] = 4
    relaxation["burn_in_mcs"] = 1
    relaxation["measured_mcs"] = 4
    relaxation["observation_cadence_mcs"] = 1
    problem = build_realistic_problem(relaxation, 0x1301000000000001; manifest)
    @test problem.seed == seeds.dynamics
    @test problem.capacity == CorePotts.CellCapacity(4)
    @test CorePotts.property_values(problem.u0, :volume__target)[1:4] == fill(25.0f0, 4)
    @test CorePotts.property_values(problem.u0, :volume__strength)[1:4] == fill(1.0f0, 4)

    relaxation_results = Dict{String, Any}[]
    for algorithm in ("SequentialCPM", "CheckerboardSweepCPM")
        result = run_realistic_replica(relaxation, algorithm;
            seed = 0x1301000000000001, manifest)
        algorithm == "SequentialCPM" && push!(relaxation_results, result)
        @test result["algorithm"] == algorithm
        @test result["backend"] == "CPU"
        @test result["observation_count"] == 4
        @test result["observation_synchronizations"] == 4
        @test result["measured_mcs_per_second"] > 0
        @test isfinite(result["energy_per_mutable_site_mean"])
        @test startswith(result["layout_seed_hex"], "0x")
        @test startswith(result["dynamics_seed_hex"], "0x")
    end

    second = run_realistic_replica(relaxation, "SequentialCPM";
        seed = 0x1301000000000002, manifest)
    push!(relaxation_results, second)
    evidence = build_realistic_evidence(relaxation, "SequentialCPM",
        relaxation_results; backend = "cpu", profile = :diagnostic, manifest,
        source_revision = "test-dirty", reproduction_command = "test command")
    @test_throws ArgumentError build_realistic_evidence(relaxation, "SequentialCPM",
        relaxation_results; backend = "metal", profile = :qualification, manifest,
        source_revision = "test-dirty", reproduction_command = "test command")
    @test evidence["result"]["status"] == "diagnostic-collected"
    @test validate_realistic_evidence(evidence).valid
    @test evidence["identity"]["workload_fingerprint"] ==
        workload_fingerprint(relaxation, manifest)
    checker_summaries = deepcopy(relaxation_results)
    foreach(summary -> summary["algorithm"] = "CheckerboardSweepCPM", checker_summaries)
    checker_evidence = build_realistic_evidence(relaxation, "CheckerboardSweepCPM",
        checker_summaries; backend = "cpu", profile = :diagnostic, manifest,
        source_revision = "test-dirty", reproduction_command = "test command")
    metal_summaries = deepcopy(checker_summaries)
    foreach(summary -> summary["backend"] = "MetalBackend", metal_summaries)
    metal_evidence = build_realistic_evidence(relaxation, "CheckerboardSweepCPM",
        metal_summaries; backend = "metal", profile = :diagnostic, manifest,
        source_revision = "test-dirty", reproduction_command = "test command")
    @test metal_evidence["identity"]["backend"] == "metal"
    @test validate_realistic_evidence(metal_evidence).valid
    mismatched_backend = deepcopy(metal_evidence)
    mismatched_backend["replica_primary_summaries"][1]["backend"] = "CPU"
    @test !validate_realistic_evidence(mismatched_backend).valid
    analysis = analyze_realistic_equivalence(evidence, checker_evidence;
        comparison = :paired_algorithm, manifest)
    @test analysis["schema"]["name"] == "potts-realistic-equivalence-analysis"
    @test analysis["multiplicity"]["method"] == "Holm two-one-sided equivalence"
    @test length(analysis["endpoints"]) == 14
    @test all(haskey(endpoint, "adjusted_interval") for endpoint in analysis["endpoints"])
    mixed_revision = deepcopy(checker_evidence)
    mixed_revision["identity"]["source_revision"] = "different-revision"
    @test_throws ArgumentError analyze_realistic_equivalence(evidence, mixed_revision;
        comparison = :paired_algorithm, manifest)
    mixed_registration = deepcopy(checker_evidence)
    mixed_registration["sampling"]["registered_replicas"] += 1
    @test_throws ArgumentError analyze_realistic_equivalence(evidence, mixed_registration;
        comparison = :paired_algorithm, manifest)
    mktempdir() do directory
        path = joinpath(directory, "realistic.toml")
        @test write_realistic_evidence(path, evidence) == path
        @test validate_realistic_evidence(TOML.parsefile(path)).valid
        @test_throws ArgumentError write_realistic_evidence(path, evidence)
    end

    sorting = deepcopy(realistic_workload("differential_adhesion_sorting", manifest))
    sorting["dimensions"] = [16, 16]
    sorting["cell_count"] = 4
    sorting["burn_in_mcs"] = 1
    sorting["measured_mcs"] = 4
    sorting["observation_cadence_mcs"] = 1
    sorting_result = run_realistic_replica(sorting, "SequentialCPM";
        seed = 0x1301000000000002, manifest)
    @test 0 <= sorting_result["heterotypic_contact_fraction_mean"] <= 1
    @test 0 <= sorting_result["segregation_index_mean"] <= 1
    @test sorting_result["sorting_effective_sample_size"] > 0

    migration = deepcopy(realistic_workload("single_cell_migration", manifest))
    migration["dimensions"] = [16, 16]
    migration["burn_in_mcs"] = 1
    migration["measured_mcs"] = 5
    migration["observation_cadence_mcs"] = 1
    migration_result = run_realistic_replica(migration, "CheckerboardSweepCPM";
        seed = 0x1301000000000003, manifest)
    @test migration_result["net_displacement"] >= 0
    @test migration_result["mean_squared_displacement"] >= 0
    @test 0 <= migration_result["persistence"] <= 1
    @test migration_result["velocity_effective_sample_size"] > 0

    sorting_evidence = build_realistic_evidence(sorting, "SequentialCPM",
        [sorting_result]; backend = "cpu", profile = :diagnostic, manifest,
        source_revision = "test-dirty", reproduction_command = "test command")
    sorting_checker_summaries = [deepcopy(sorting_result)]
    sorting_checker_summaries[1]["algorithm"] = "CheckerboardSweepCPM"
    sorting_checker = build_realistic_evidence(sorting, "CheckerboardSweepCPM",
        sorting_checker_summaries; backend = "cpu", profile = :diagnostic, manifest,
        source_revision = "test-dirty", reproduction_command = "test command")
    migration_sequential_summaries = [deepcopy(migration_result)]
    migration_sequential_summaries[1]["algorithm"] = "SequentialCPM"
    migration_sequential = build_realistic_evidence(migration, "SequentialCPM",
        migration_sequential_summaries; backend = "cpu", profile = :diagnostic, manifest,
        source_revision = "test-dirty", reproduction_command = "test command")
    migration_checker = build_realistic_evidence(migration, "CheckerboardSweepCPM",
        [migration_result]; backend = "cpu", profile = :diagnostic, manifest,
        source_revision = "test-dirty", reproduction_command = "test command")
    family = analyze_realistic_family(
        [evidence, sorting_evidence, migration_sequential],
        [checker_evidence, sorting_checker, migration_checker];
        comparison = :paired_algorithm, manifest)
    @test family["schema"]["name"] ==
        "potts-realistic-equivalence-family-analysis"
    @test family["multiplicity"]["hypotheses"] == 42
    @test family["multiplicity"]["scope"] ==
        "all applicable primary endpoints in the claim family"
    mixed_sorting_evidence = deepcopy(sorting_evidence)
    mixed_sorting_checker = deepcopy(sorting_checker)
    mixed_sorting_evidence["identity"]["source_revision"] = "different-revision"
    mixed_sorting_checker["identity"]["source_revision"] = "different-revision"
    @test_throws ArgumentError analyze_realistic_family(
        [evidence, mixed_sorting_evidence, migration_sequential],
        [checker_evidence, mixed_sorting_checker, migration_checker];
        comparison = :paired_algorithm, manifest)
    @test_throws ArgumentError analyze_realistic_family(
        [evidence, evidence, migration_sequential],
        [checker_evidence, checker_evidence, migration_checker];
        comparison = :paired_algorithm, manifest)
end

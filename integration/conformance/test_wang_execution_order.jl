using SHA
using TOML

include(joinpath(@__DIR__, "..", "..", "scripts", "validate_wang_order_oracle.jl"))

@testset "Wang model Wang source/runtime execution-order authority" begin
    repository = normpath(joinpath(@__DIR__, "..", ".."))
    audit_path = joinpath(repository, "design", "audits",
        "phase-14-wang-order-oracle-v1.toml")
    evidence_path = joinpath(repository, "design", "evidence", "phase-14",
        "wang-order", "index.toml")
    audit = TOML.parsefile(audit_path)
    evidence = TOML.parsefile(evidence_path)

    @test audit["schema_version"] == "1.0.0"
    @test audit["status"] == "accepted-source-and-runtime-order"
    @test evidence["schema_version"] == "1.0.0"
    @test evidence["status"] == "pass"
    @test evidence["model_id"] == audit["model_id"]
    @test evidence["wang_source"]["git_commit"] ==
          "60ebcf013aafefdff39ebe566114ee79f2a6e54d"
    @test evidence["compucell3d"]["version"] == "4.2.5"
    @test evidence["compucell3d"]["source_tag_commit"] ==
          "4ca1f2919a5da53111d2027d2e00b626aba1cd28"
    @test evidence["compucell3d"]["exit_code"] == 0
    @test evidence["oracle"]["result"] == "pass"

    expected_order = [
        "potts_metropolis",
        "xml_diffusion_solver_fe",
        "xml_blob_initializer_step_noop_after_start",
        "python_migration_history_and_secretome",
        "python_intracellular_ode",
        "python_focal_parameters_if_mcs_mod_10_is_zero",
        "python_polarity_force_and_output",
        "restart_snapshot_screenshot_and_steering",
    ]
    normalized_time_mapping = audit["normalized_time_mapping"]
    @test normalized_time_mapping["canonical_mcs_order"] == expected_order
    @test isempty(normalized_time_mapping["wang_run_before_mcs_steppables"])
    @test normalized_time_mapping["xml_steppable_order"] ==
          ["DiffusionSolverFE", "BlobInitializer"]
    @test normalized_time_mapping["normal_python_registration_order"] == [
        "migration_racdir_fppSteppable",
        "OdeSteppable",
        "FocalPointPlasticityParams",
        "OdeUpdateParams",
    ]

    processes = Dict(process["id"] => process for process in audit["processes"])
    @test Set(keys(processes)) == Set([
        "potts_metropolis",
        "xml_diffusion_solver_fe",
        "python_migration_history_and_secretome",
        "python_intracellular_ode",
        "python_focal_parameters",
        "python_polarity_force_and_output",
    ])
    @test processes["python_focal_parameters"]["cadence_mcs"] == 10
    @test occursin("same MCS",
        processes["python_intracellular_ode"]["visibility"])
    @test occursin("next Potts MCS",
        processes["python_polarity_force_and_output"]["visibility"])

    @test audit["boundary_mcs_120"]["first_potts_mcs_using_focal_strength_20"] == 121
    @test !audit["boundary_mcs_210"]["calibration_uptake_writes_signal_s"]
    @test audit["boundary_mcs_210"]["first_potts_mcs_using_scanned_focal_strength"] == 211
    @test audit["boundary_mcs_211"]["ode_reads_same_mcs_signal_s"]
    @test audit["history_discrepancy"]["classification"] ==
          "paper-t-minus-5_source-t-minus-4"

    trace_path = joinpath(dirname(evidence_path), evidence["oracle"]["trace"])
    @test bytes2hex(sha256(read(trace_path))) == evidence["oracle"]["trace_sha256"]
    @test isempty(validate_wang_order_trace(trace_path))

    @test length(evidence["fixture_files"]) == 5
    for fixture in evidence["fixture_files"]
        fixture_path = joinpath(repository, fixture["path"])
        @test isfile(fixture_path)
        @test bytes2hex(sha256(read(fixture_path))) == fixture["sha256"]
    end
    @test length(evidence["wang_source"]["files"]) == 6
    @test length(unique(file["sha256"] for file in evidence["wang_source"]["files"])) == 6

    source_records = TOML.parsefile(joinpath(repository, "design", "audits",
        "phase-14-model-source-records-v1.toml"))
    wang = only(filter(row -> row["id"] == audit["model_id"], source_records["models"]))
    @test wang["paper_sha256"] == evidence["paper"]["local_reference_sha256"]
    @test occursin("accepted exact order", wang["update_schedule"])
    @test !any(occursin("steppable order", ambiguity)
               for ambiguity in wang["unresolved_ambiguities"])
    @test any(occursin("x(t)-x(t-4)", parameter) for parameter in wang["parameters"])
end

using Test
using SHA
using TOML
using .TransitionKernelOracle
using .TransitionEvidenceArchive

function _archive_test_identity(fixture, state; algorithm_version = v"1.0.0",
        scheduler_version = v"1.0.0", rng_version = v"1.0.0")
    return EvidenceIdentity(
        model_fingerprint = "sha256:test-model",
        initial_state_fingerprint = state_fingerprint(state),
        algorithm = "SequentialCPM",
        algorithm_semantic_version = algorithm_version,
        scheduler = "sequential_with_replacement",
        scheduler_version = scheduler_version,
        rng = "Philox4x32x10V1",
        rng_contract_version = rng_version,
        semantic_seed_or_range = "exact-enumeration:no-random-draws",
        topology = "von_neumann",
        boundaries = ["no_flux"],
        dimension = 1,
        acceptance_law = "OracleConventionalMetropolis",
        temperature = "0",
        components = ["none"],
        backend = "cpu-exact-oracle",
        fixture = fixture,
        sampling_plan_version = "phase13-transition-evidence-v1",
        source_revision = "content-sha256:test-source",
    )
end

@testset "transition-kernelF fixture manifest is bounded and covers registered strata" begin
    path = joinpath(@__DIR__, "..", "..", "design", "audits",
        "phase-13-fixture-manifest.toml")
    manifest = TOML.parsefile(path)
    report = validate_fixture_manifest(manifest)
    @test report.valid
    @test isempty(report.errors)
    @test manifest["registered_empirical_source_states"] == 12
    @test sum(length(fixture["empirical_source_states"])
              for fixture in manifest["fixtures"]) == 12

    overflow = deepcopy(manifest)
    overflow["fixtures"][2]["empirical_source_states"] = fill("cell:1", 25)
    overflow_report = validate_fixture_manifest(overflow)
    @test !overflow_report.valid
    @test any(error -> occursin("cap of 24", error), overflow_report.errors)
end

@testset "transition-kernelF exact evidence schema and round-trip" begin
    fixture = hand_derived_1d_fixture()
    primitive = primitive_kernel(fixture.catalog, fixture.domain, fixture.model)
    normalized = sequential_mcs_kernel(fixture.catalog, fixture.domain, fixture.model)
    identity = _archive_test_identity(
        "hand-derived-1d-noflux-zero-primitive", fixture.catalog.states[2])
    observable = [count(==(fixture.cell), state.owners)
                  for state in fixture.catalog.states]
    archive = archive_kernel(primitive; identity, domain = fixture.domain,
        reference_kernel = normalized, observable,
        thresholds = Dict("row_sum" => "exact"),
        environment = Dict("julia_version" => string(VERSION)),
        reproduction_command = "julia --project=integration ...")

    @test archive["precision"]["kind"] == "exact_rational"
    @test archive["kernel"]["matrix_format"] == "sparse-coordinate-row-source"
    @test length(archive["states"]) == 4
    @test length(archive["kernel"]["entries"]) == 8
    @test haskey(archive, "comparison")
    @test haskey(archive["analysis"], "probability_currents")
    @test haskey(archive["analysis"], "eigenvalues")
    @test haskey(archive["analysis"], "observable")
    @test validate_evidence_archive(archive; expected_identity = identity).valid

    mktempdir() do directory
        path = joinpath(directory, "evidence.toml")
        write_evidence_archive(path, archive)
        @test_throws ArgumentError write_evidence_archive(path, archive)
        loaded = read_evidence_archive(path)
        report = validate_evidence_archive(loaded; expected_identity = identity)
        @test report.valid
        @test loaded["kernel"]["entries"] == archive["kernel"]["entries"]
    end

    corrupt = deepcopy(archive)
    corrupt["kernel"]["entries"][1]["probability"] = "0"
    corrupt_report = validate_evidence_archive(corrupt)
    @test !corrupt_report.valid
    @test any(error -> occursin("not normalized", error), corrupt_report.errors)

    stale_schema = deepcopy(archive)
    stale_schema["schema"]["version"] = "2.0.0"
    @test !validate_evidence_archive(stale_schema).valid
end

@testset "transition-kernelF semantic contract changes invalidate evidence" begin
    fixture = hand_derived_1d_fixture()
    kernel = primitive_kernel(fixture.catalog, fixture.domain, fixture.model)
    archived_identity = _archive_test_identity("semantic-invalidation", fixture.catalog.states[2])
    archive = archive_kernel(kernel; identity = archived_identity, domain = fixture.domain)

    for expected_identity in (
            _archive_test_identity("semantic-invalidation", fixture.catalog.states[2];
                algorithm_version = v"2.0.0"),
            _archive_test_identity("semantic-invalidation", fixture.catalog.states[2];
                scheduler_version = v"1.1.0"),
            _archive_test_identity("semantic-invalidation", fixture.catalog.states[2];
                rng_version = v"1.0.1"))
        report = validate_evidence_archive(archive; expected_identity)
        @test !report.valid
        @test any(error -> occursin("semantic identity mismatch", error), report.errors)
    end

    malformed = deepcopy(archive)
    malformed["identity"]["scheduler_version"] = "not-a-version"
    report = validate_evidence_archive(malformed)
    @test !report.valid
    @test any(error -> occursin("not a semantic version", error), report.errors)
end

@testset "transition-kernelF checked exact evidence is complete and content-addressed" begin
    evidence_directory = joinpath(@__DIR__, "..", "..", "design", "evidence",
        "phase-13", "exact")
    index = TOML.parsefile(joinpath(evidence_directory, "index.toml"))
    @test index["evidence_schema_version"] == string(EVIDENCE_SCHEMA_VERSION)
    @test index["analysis_program_version"] == string(ANALYSIS_PROGRAM_VERSION)
    @test length(index["artifacts"]) == 12
    fixture_manifest = normpath(joinpath(evidence_directory, index["fixture_manifest"]))
    @test isfile(fixture_manifest)
    for artifact in index["artifacts"]
        path = joinpath(evidence_directory, artifact["path"])
        @test isfile(path)
        @test bytes2hex(open(SHA.sha256, path)) == artifact["sha256"]
        @test validate_evidence_archive(path).valid
    end
end

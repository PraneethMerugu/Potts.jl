using Test
using TOML
using KernelAbstractions
using .TransitionFixtures
using .ProductionTransitionSampler
using .ProductionEvidenceArchive

@testset "transition-kernel production evidence records" begin
    manifest = load_transition_manifest()
    rows = empirical_fixture_rows(manifest)
    pairs = [(row, build_transition_fixture(row; manifest)) for row in rows]
    unsupported_row, unsupported = first(filter(pair -> !last(pair).production_supported, pairs))
    limited = build_limited_domain_evidence(unsupported, unsupported_row, :sequential;
        backend = "cpu", manifest, source_revision = "test-revision",
        reproduction_command = "transition diagnostic test")
    @test validate_production_evidence(limited).valid
    @test limited["result"]["status"] == "limited-domain"
    @test !limited["result"]["qualification_passed"]

    supported_row, supported = first(filter(pair -> last(pair).production_supported, pairs))
    sample = sample_production_row(supported, :sequential; replicas = 32,
        backend = KernelAbstractions.CPU())
    diagnostic = build_production_evidence(supported, supported_row, sample;
        profile = :diagnostic, manifest, source_revision = "test-revision",
        reproduction_command = "transition diagnostic test")
    @test validate_production_evidence(diagnostic).valid
    @test !diagnostic["result"]["qualification_passed"]
    @test diagnostic["sampling"]["profile"] == "diagnostic"
    @test diagnostic["schema"]["version"] == "1.1.0"
    @test diagnostic["environment"]["production_real_type"] == "Float32"
    @test sum(diagnostic["raw_counts"]) == 32
    @test_throws ArgumentError build_production_evidence(
        supported, supported_row, sample; profile = :qualification, manifest,
        source_revision = "test-revision", reproduction_command = "invalid")

    mktempdir() do directory
        path = joinpath(directory, "diagnostic.toml")
        write_production_evidence(path, diagnostic)
        @test validate_production_evidence(TOML.parsefile(path)).valid
        @test_throws ArgumentError write_production_evidence(path, diagnostic)
    end
end

@testset "transition-kernel empirical eligibility ledger" begin
    path = joinpath(@__DIR__, "..", "..", "design", "evidence", "phase-13",
        "empirical", "eligibility.toml")
    ledger = TOML.parsefile(path)
    @test ledger["registered_rows"] == 24
    @test ledger["eligible_rows"] == 8
    @test ledger["limited_rows"] == 16
    @test count(row -> row["disposition"] == "qualification-required",
        ledger["rows"]) == 8
    @test all(row -> row["oracle_support"] <= ledger["maximum_oracle_support"],
        filter(row -> row["empirical_eligible"], ledger["rows"]))
end

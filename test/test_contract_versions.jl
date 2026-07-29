using Test

@testset "Toolkit contract identities and reports" begin
    @test PottsToolkit.PHASE13_RESULT_EVIDENCE_SCHEMA_VERSION ===
          PottsToolkit.RESULT_EVIDENCE_SCHEMA_VERSION
    versions = PottsToolkit.scientific_contract_versions()
    @test versions === CorePotts.scientific_contract_versions()
    @test PottsToolkit.AUTHORING_DSL_CONTRACT_VERSION == versions.authoring_dsl
    @test PottsToolkit.NORMALIZED_IR_CONTRACT_VERSION == versions.normalized_ir
    @test PottsToolkit.SEMANTIC_FINGERPRINT_VERSION == versions.semantic_fingerprint
    @test PottsToolkit.EXECUTION_FINGERPRINT_VERSION == versions.execution_fingerprint
    @test PottsToolkit.RESULT_EVIDENCE_SCHEMA_VERSION ==
          versions.result_evidence_schema

    medium = PottsToolkit.Medium(:Medium)
    cell = PottsToolkit.CellType(:Cell)
    volume = PottsToolkit.VolumeConstraint(cell => (target = 4.0, strength = 1.0))
    model = PottsToolkit.PottsModel(medium, cell, volume)
    normalized = PottsToolkit.normalize(model)
    manifest = PottsToolkit.semantic_manifest(normalized)
    @test manifest.schema_version == versions.normalized_ir
    @test manifest.authoring_dsl_version == versions.authoring_dsl
    @test manifest.normalized_ir_version == versions.normalized_ir
    @test manifest.fingerprint.version == versions.semantic_fingerprint

    mask = falses(4, 4)
    mask[2:3, 2:3] .= true
    problem = PottsToolkit.problem(model, (4, 4), PottsToolkit.CellLayout(cell, 1, mask);
        capacity = 2, tspan = (0, 1))
    stable = PottsToolkit.backend_report(problem, PottsToolkit.CheckerboardSweepCPM())
    @test stable.guarantee.api_status === :stable
    @test stable.guarantee.guarantee_label === :unqualified
    @test stable.guarantee.maximum_observed_discrepancy == 0.5625
    @test stable.guarantee.tested_backends == (:cpu, :metal, :amdgpu)
    @test occursin("guarantee=unqualified", sprint(show, stable))

    tiled = PottsToolkit.backend_report(problem, PottsToolkit.TiledCheckerboardCPM(
        tile_size = (2, 2), shared_memory = :disabled))
    @test tiled.guarantee.api_status === :experimental
    @test tiled.guarantee.paper_scope === :non_paper
end

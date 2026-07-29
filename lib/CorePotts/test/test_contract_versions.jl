using Test

function _extension_default_profile()
    AlgorithmGuaranteeProfile(
        proposal_process = :downstream,
        equilibrium_status = :not_claimed,
        kinetic_interpretation = :downstream,
        transaction_semantics = :downstream,
        mcs_normalization = :downstream,
        reproducibility_scope = :downstream,
        compatible_component_scopes = (),
        validation_evidence = (:downstream_fixture,),
        backend_contract = (:cpu,),
        dimensions = (2,),
    )
end

@testset "frozen contract versions" begin
    @test PHASE13_RESULT_EVIDENCE_SCHEMA_VERSION === RESULT_EVIDENCE_SCHEMA_VERSION
    @test Phase14ContractVersions === CoupledContractVersions
    @test PHASE14_CONTRACT_SET_VERSION === COUPLED_CONTRACT_SET_VERSION
    @test PHASE14_CONTRACT_VERSIONS === COUPLED_CONTRACT_VERSIONS
    @test phase14_contract_versions === coupled_contract_versions
    versions = scientific_contract_versions()
    @test versions === SCIENTIFIC_CONTRACT_VERSIONS
    @test versions.freeze_status === :phase13_frozen
    @test versions.rng == RNG_CONTRACT_VERSION == rng_contract_version(Philox4x32x10V1())
    @test versions.authoring_dsl == AUTHORING_DSL_CONTRACT_VERSION
    @test versions.normalized_ir == NORMALIZED_IR_CONTRACT_VERSION
    @test versions.checkpoint_schema == CHECKPOINT_SCHEMA_VERSION ==
          CorePotts._CHECKPOINT_SCHEMA_VERSION
    @test versions.semantic_fingerprint == SEMANTIC_FINGERPRINT_VERSION
    @test versions.execution_fingerprint == EXECUTION_FINGERPRINT_VERSION
    @test versions.result_evidence_schema == RESULT_EVIDENCE_SCHEMA_VERSION
    @test component_identity(SequentialCPM()).version ==
          SEQUENTIAL_ALGORITHM_CONTRACT_VERSION
    @test component_identity(SequentialEquilibrium()).version ==
          SEQUENTIAL_ALGORITHM_CONTRACT_VERSION
    @test component_identity(CheckerboardSweepCPM()).version ==
          CHECKERBOARD_SCHEDULER_CONTRACT_VERSION
    @test component_identity(LotteryCPM()).version == LOTTERY_ALGORITHM_CONTRACT_VERSION
    @test component_identity(TiledCheckerboardCPM()).version ==
          TILED_CHECKERBOARD_EXPERIMENTAL_CONTRACT_VERSION
    @test occursin("phase13_frozen", sprint(show, versions))
end

@testset "algorithm guarantee metadata defaults and scope" begin
    @test algorithm_guarantee_taxonomy() === ALGORITHM_GUARANTEE_TAXONOMY
    default = _extension_default_profile()
    @test default.guarantee_label === :unqualified
    @test default.qualified_domain == ()
    @test default.maximum_observed_discrepancy === nothing
    @test default.tested_backends == ()
    @test default.evidence_version === nothing
    @test default.api_status === :provisional
    @test default.paper_scope === :not_admitted

    sequential = algorithm_guarantees(SequentialCPM())
    equilibrium = algorithm_guarantees(SequentialEquilibrium())
    checkerboard = algorithm_guarantees(CheckerboardSweepCPM())
    lottery = algorithm_guarantees(LotteryCPM())
    tiled = algorithm_guarantees(TiledCheckerboardCPM())
    @test sequential.guarantee_label === checkerboard.guarantee_label === :unqualified
    @test sequential.api_status === checkerboard.api_status === :stable
    @test sequential.paper_scope === checkerboard.paper_scope === :phase13_core
    @test sequential.maximum_observed_discrepancy == 0.0
    @test checkerboard.maximum_observed_discrepancy == 0.5625
    @test sequential.tested_backends ==
          checkerboard.tested_backends == (:cpu, :metal, :amdgpu)
    @test sequential.evidence_version ==
          checkerboard.evidence_version == RESULT_EVIDENCE_SCHEMA_VERSION
    @test sequential.qualified_domain.transition.registration ===
          checkerboard.qualified_domain.transition.registration ===
          :phase13_transition_evidence_v2
    @test sequential.qualified_domain.realistic.role === :cpu_reference
    @test sequential.qualified_domain.realistic.backends == (:cpu,)
    @test checkerboard.qualified_domain.realistic.backends == (:cpu, :metal, :amdgpu)
    @test equilibrium.paper_scope === :not_admitted
    @test equilibrium.guarantee_label === :unqualified
    @test equilibrium.api_status === :experimental
    @test lottery.api_status === :limited
    @test lottery.paper_scope === :later_protocol_consumer
    @test lottery.guarantee_label === :unqualified
    @test tiled.api_status === :experimental
    @test tiled.paper_scope === :non_paper
    @test tiled.guarantee_label === :unqualified
    @test isempty(tiled.tested_backends)
    @test tiled.evidence_version === nothing
    rendered = sprint(show, MIME("text/plain"), tiled)
    @test occursin("experimental", rendered)
    @test occursin("unqualified", rendered)

    qualified = AlgorithmGuaranteeProfile(
        proposal_process = :fixture,
        equilibrium_status = :not_claimed,
        kinetic_interpretation = :fixture,
        transaction_semantics = :fixture,
        mcs_normalization = :fixture,
        reproducibility_scope = :fixture,
        compatible_component_scopes = (),
        validation_evidence = (:retained_record,),
        backend_contract = (:cpu,),
        dimensions = (2,),
        guarantee_label = :observably_comparable,
        qualified_domain = (fixture = :example,),
        maximum_observed_discrepancy = 0.01,
        tested_backends = (:cpu,),
        evidence_version = RESULT_EVIDENCE_SCHEMA_VERSION,
    )
    @test qualified.guarantee_label === :observably_comparable
    @test qualified.tested_backends == (:cpu,)

    @test_throws ArgumentError AlgorithmGuaranteeProfile(
        proposal_process = :bad,
        equilibrium_status = :not_claimed,
        kinetic_interpretation = :bad,
        transaction_semantics = :bad,
        mcs_normalization = :bad,
        reproducibility_scope = :bad,
        compatible_component_scopes = (),
        validation_evidence = (:fixture,),
        backend_contract = (:cpu,),
        dimensions = (2,),
        guarantee_label = :exact,
    )
    @test_throws ArgumentError AlgorithmGuaranteeProfile(
        proposal_process = :unsupported_claim,
        equilibrium_status = :not_claimed,
        kinetic_interpretation = :unsupported_claim,
        transaction_semantics = :unsupported_claim,
        mcs_normalization = :unsupported_claim,
        reproducibility_scope = :unsupported_claim,
        compatible_component_scopes = (),
        validation_evidence = (:fixture,),
        backend_contract = (:cpu,),
        dimensions = (2,),
        guarantee_label = :observably_comparable,
    )
end

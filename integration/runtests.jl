using Test
using CorePotts
using PottsToolkit
include("TestBackend.jl")
using .TestBackend: BACKEND, BACKEND_GROUP, backend_array, backend_zeros, @skip_if_no_gpu

@info "Running cross-package integration suite" backend=BACKEND_GROUP

const TEST_SHARD = get(ENV, "POTTS_TEST_SHARD", "all")
const TEST_SHARDS = ("all", "thermodynamics", "biophysics", "integration", "conformance")
TEST_SHARD in TEST_SHARDS || error(
    "POTTS_TEST_SHARD must be one of $(join(TEST_SHARDS, ", ")); got $(repr(TEST_SHARD))")
run_shard(name) = TEST_SHARD == "all" || TEST_SHARD == name
@info "Selected test shard" shard=TEST_SHARD

include("reference/ReferenceSemantics.jl")
include("conformance/ConformanceHarness.jl")
include("transition/TransitionKernelOracle.jl")
include("transition/TransitionKernelAnalysis.jl")
include("transition/TransitionEvidenceArchive.jl")
include("transition/TransitionEmpirical.jl")
include("transition/CheckerboardOracle.jl")
include("transition/TransitionFixtures.jl")
include("transition/ProductionTransitionSampler.jl")
include("transition/ProductionEvidenceArchive.jl")
include("transition/RealisticScaleRunner.jl")
include("transition/RealisticEvidenceArchive.jl")
include("transition/RealisticEvidenceAnalysis.jl")
include("conformance/RealisticAnalysisArchiveComparison.jl")

@testset "Potts package-family integration [$(BACKEND_GROUP)]" begin
    run_shard("thermodynamics") && include("test_thermodynamics.jl")
    run_shard("biophysics") && include("test_biophysics.jl")
    if run_shard("integration")
        include("test_level2_integration.jl")
    end
    if run_shard("conformance")
        include("conformance/test_reference_semantics.jl")
        include("conformance/test_harness.jl")
        include("conformance/test_transition_oracle.jl")
        include("conformance/test_transition_analysis.jl")
        include("conformance/test_transition_evidence_archive.jl")
        include("conformance/test_transition_empirical.jl")
        include("conformance/test_sequential_transition.jl")
        include("conformance/test_checkerboard_oracle.jl")
        include("conformance/test_checkerboard_analysis.jl")
        include("conformance/test_transition_production_adapter.jl")
        include("conformance/test_transition_fixtures.jl")
        include("conformance/test_transition_production_sampler.jl")
        include("conformance/test_transition_production_evidence.jl")
        include("conformance/test_cpu_transition_archive.jl")
        include("conformance/test_metal_transition_archive.jl")
        include("conformance/test_rocm_transition_archive.jl")
        include("conformance/test_realistic_scale.jl")
        include("conformance/test_cpu_realistic_archive.jl")
        include("conformance/test_metal_realistic_archive.jl")
        include("conformance/test_rocm_realistic_archive.jl")
        include("conformance/test_rocm_device_code_archive.jl")
        include("conformance/test_wang_execution_order.jl")
        include("conformance/test_wang_model_authoring.jl")
        include("conformance/test_wang_sequential_disposition.jl")
        include("conformance/test_distributed_ensemble.jl")
    end
end

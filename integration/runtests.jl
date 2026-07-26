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
include("transition/Phase13Fixtures.jl")
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
        include("conformance/test_phase13_oracle.jl")
        include("conformance/test_phase13_analysis.jl")
        include("conformance/test_phase13_evidence_archive.jl")
        include("conformance/test_phase13_empirical.jl")
        include("conformance/test_phase13_sequential.jl")
        include("conformance/test_phase13_checkerboard_oracle.jl")
        include("conformance/test_phase13_checkerboard_analysis.jl")
        include("conformance/test_phase13_production_adapter.jl")
        include("conformance/test_phase13_fixtures.jl")
        include("conformance/test_phase13_production_sampler.jl")
        include("conformance/test_phase13_production_evidence.jl")
        include("conformance/test_phase13_cpu_qualification_archive.jl")
        include("conformance/test_phase13_metal_qualification_archive.jl")
        include("conformance/test_phase13_rocm_qualification_archive.jl")
        include("conformance/test_phase13_realistic_scale.jl")
        include("conformance/test_phase13_realistic_qualification_archive.jl")
        include("conformance/test_phase13_metal_realistic_qualification_archive.jl")
        include("conformance/test_phase13_rocm_realistic_qualification_archive.jl")
        include("conformance/test_phase13_rocm_device_code_archive.jl")
        include("conformance/test_phase14_wang_order.jl")
        include("conformance/test_phase14_wang_authoring.jl")
        include("conformance/test_phase14_wang_g3c.jl")
        include("conformance/test_phase9_distributed.jl")
    end
end

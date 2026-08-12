using Metal
using LocalWorksets
using PottsToolkit
using Test

Metal.functional() || error("the selected Metal witness is not functional")
Metal.allowscalar(false)

include("../../../test/localworksets_witnesses/lbm_d2q9.jl")
include("../../../test/localworksets_witnesses/lattice_spring.jl")
include("../../../test/localworksets_witnesses/matrix_free_fem.jl")
include("../../../test/localworksets_witnesses/zbuffer.jl")
include("../../../lib/LocalWorksets/test/backend_conformance.jl")
include("../../../test/backend_conformance/checkerboard_execution.jl")
include("../../../test/backend_conformance/localworksets_execution.jl")

backend = Metal.MetalBackend()
reports = (
    run_lw_d2q9_witness(Metal.MtlArray; backend),
    run_lw_lattice_spring_witness(Metal.MtlArray; backend),
    run_lw_lattice_spring_witness(Metal.MtlArray; backend, force_mode = :fast),
    run_lw_matrix_free_fem_witness(Metal.MtlArray; backend),
    run_lw_zbuffer_witness(Metal.MtlArray; backend),
)

@testset "LW-4 Check real-Metal semantics" begin
    @test map(report -> report.launches, reports) == (1, 2, 3, 2, 2)
    @test all(report -> report.waits == 2, reports)
    @test all(report -> report.invalid_rejected, reports)
    @test reports[3].determinism.same_run_replay.guarantee ==
        :not_claimed_for_fast_ports
end

facts = run_localworksets_execution(
    Metal.MtlArray;
    backend_name = :metal,
    compiler_cache_size = () -> length(Metal.compiler_cache(Metal.device())),
)
failure = fetch(schedule(Task() do
    run_localworksets_device_failure(Metal.MtlArray; backend_name = :metal)
end))
shared = fetch(schedule(Task() do
    run_localworksets_shared_failure_scope(Metal.MtlArray; backend_name = :metal)
end))
checkerboard = run_localworksets_checkerboard_vertical(
    Metal.MtlArray; backend_name = :metal, kernel_convert = Metal.mtlconvert
)
checkerboard_failure = fetch(schedule(Task() do
    run_localworksets_checkerboard_failures(Metal.MtlArray; backend_name = :metal)
end))

@testset "LW-4 Check Metal lifetime and failure" begin
    @test facts.backend == :metal
    @test facts.event_scope == :backend_implicit_order_tail
    @test failure.poisoned
    @test shared.good_poisoned && shared.bad_poisoned
    @test checkerboard.submitted_mcs == checkerboard.committed_mcs == 12
    @test checkerboard.synchronizations == 1
    @test checkerboard_failure.expected_failure_commit == 0
    @test checkerboard_failure.provider_poisoned
end

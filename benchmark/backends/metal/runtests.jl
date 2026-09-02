using Metal
using LocalMath
using Potts
using Test
import KernelAbstractions

Metal.functional() || error("the selected Metal witness is not functional")
Metal.allowscalar(false)

const METAL_SEMANTIC_WITNESSES = (
    "extension_load_order.jl",
    "stage_program.jl",
    "execution_receipts.jl",
    "localmath_authoring.jl",
    "localmath_correctness.jl",
    "corepotts_feasibility.jl",
    "corepotts_relationship_stages.jl",
    "corepotts_stabilization.jl",
    "corepotts_relationship_energy.jl",
    "corepotts_stage_boundaries.jl",
    "destination_grouping.jl",
    "localmath_execution_parity.jl",
    "proposal_execution_parity.jl",
    "queued_lifecycle_runtime.jl",
    "lifecycle_transaction_conformance.jl",
    "native_component_execution.jl",
)
const METAL_PERFORMANCE_PROGRAMS = ("native_component_performance.jl",)

@testset "real-Metal runner inventory" begin
    discovered = Set(filter(name -> endswith(name, ".jl") && name != "runtests.jl",
        readdir(@__DIR__)))
    @test discovered == union(Set(METAL_SEMANTIC_WITNESSES),
        Set(METAL_PERFORMANCE_PROGRAMS))
end

# The authoritative device packet runs every semantic witness. Performance
# programs are intentionally separate and never implied by this runner.
for witness in METAL_SEMANTIC_WITNESSES
    include(witness)
end

include("../../../test/localmath_witnesses/lbm_d2q9.jl")
include("../../../test/localmath_witnesses/lattice_spring.jl")
include("../../../test/localmath_witnesses/matrix_free_fem.jl")
include("../../../test/localmath_witnesses/zbuffer.jl")
include("../../../test/localmath_witnesses/compacted_dem_contacts.jl")
include("../../../test/localmath_witnesses/compacted_active_fem.jl")
include("../../../test/localmath_witnesses/compacted_particle_cells.jl")
include("../../../test/localmath_witnesses/ordered_rsa.jl")
include("../../../test/localmath_witnesses/ordered_pgs_3d.jl")
include("../../../test/localmath_witnesses/ordered_stoichiometry.jl")
include("../../../test/localmath_witnesses/localmath_authoring.jl")

@testset "LocalMath cross-domain real-Metal witnesses" begin
    backend = Metal.MetalBackend()
    lbm = run_localmath_d2q9_witness(Metal.MtlArray; backend)
    spring = run_localmath_lattice_spring_witness(Metal.MtlArray; backend)
    fem = run_localmath_matrix_free_fem_witness(Metal.MtlArray; backend)
    zbuffer = run_localmath_zbuffer_witness(Metal.MtlArray; backend)
    dem = run_localmath_compacted_dem_contacts_witness(Metal.MtlArray; backend)
    active_fem = run_localmath_compacted_active_fem_witness(Metal.MtlArray; backend)
    particle_cells = run_localmath_compacted_particle_cells_witness(
        Metal.MtlArray; backend)
    rsa = run_localmath_ordered_rsa_witness(Metal.MtlArray; backend)
    pgs = run_localmath_ordered_pgs_3d_witness(Metal.MtlArray; backend)
    chemistry = run_localmath_ordered_stoichiometry_witness(Metal.MtlArray; backend)
    authored = run_localmath_authored_domain_witness(Metal.MtlArray; backend)

    @test lbm.result == lbm.reference
    @test spring.result == spring.reference
    @test fem.result == fem.reference
    @test zbuffer.result == zbuffer.reference
    @test length(dem.cases) == 6
    @test length(active_fem.cases) == 2
    @test length(particle_cells.cases) == 2
    @test rsa.result == rsa.reference
    @test pgs.result == pgs.reference
    @test chemistry.result == chemistry.reference
    @test authored.graph.forward == Float32[3, 5, 7]
    @test authored.graph.inverse == Float32[3, 8, 12, 7]
    @test authored.potts.winner == Int32[1, 3]
    @test rsa.sequential_counterexample
    @test pgs.sequential_counterexample
    @test chemistry.sequential_counterexample
end

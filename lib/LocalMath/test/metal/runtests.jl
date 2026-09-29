using KernelAbstractions
using LocalMath
using Metal
using Statistics
using Test

include(joinpath(@__DIR__, "..", "telemetry_support.jl"))

Metal.functional() || error("the selected Metal witness is not functional")
Metal.allowscalar(false)

const LOCALMATH_METAL_WITNESSES = (
    "stage_program.jl",
    "execution_receipts.jl",
    "localmath_authoring.jl",
    "localmath_correctness.jl",
    "destination_grouping.jl",
    "product_values.jl",
    "ordered_fold_control.jl",
    "ordered_fold_step_validation.jl",
    "reduction_control.jl",
    "empty_pointwise_domains.jl",
    "collect_canonical_order.jl",
    "keyed_reduce.jl",
    "trigonometric_stages.jl",
)

@testset "LocalMath Metal runner inventory" begin
    discovered = Set(
        filter(
            name -> endswith(name, ".jl") && name != "runtests.jl",
            readdir(@__DIR__),
        )
    )
    @test discovered == Set(LOCALMATH_METAL_WITNESSES)
end

for (ordinal, witness) in enumerate(LOCALMATH_METAL_WITNESSES)
    LocalMathTestTelemetry.include_fixture(
        @__MODULE__, joinpath(@__DIR__, witness), witness;
        kind = "metal_fixture", ordinal,
    )
end

for (ordinal, witness) in enumerate((
        "lbm_d2q9.jl",
        "lattice_spring.jl",
        "matrix_free_fem.jl",
        "zbuffer.jl",
        "compacted_dem_contacts.jl",
        "compacted_active_fem.jl",
        "compacted_particle_cells.jl",
        "ordered_rsa.jl",
        "ordered_pgs_3d.jl",
        "ordered_stoichiometry.jl",
        "localmath_authoring.jl",
    ))
    LocalMathTestTelemetry.include_fixture(
        @__MODULE__,
        joinpath(@__DIR__, "..", "scientific_witnesses", witness), witness;
        kind = "metal_scientific_fixture", ordinal,
    )
end

@testset "LocalMath cross-domain Metal witnesses" begin
    backend = Metal.MetalBackend()
    lbm = run_localmath_d2q9_witness(Metal.MtlArray; backend)
    spring = run_localmath_lattice_spring_witness(Metal.MtlArray; backend)
    fem = run_localmath_matrix_free_fem_witness(Metal.MtlArray; backend)
    zbuffer = run_localmath_zbuffer_witness(Metal.MtlArray; backend)
    dem = run_localmath_compacted_dem_contacts_witness(Metal.MtlArray; backend)
    active_fem = run_localmath_compacted_active_fem_witness(
        Metal.MtlArray; backend
    )
    particle_cells = run_localmath_compacted_particle_cells_witness(
        Metal.MtlArray; backend
    )
    rsa = run_localmath_ordered_rsa_witness(Metal.MtlArray; backend)
    pgs = run_localmath_ordered_pgs_3d_witness(Metal.MtlArray; backend)
    chemistry = run_localmath_ordered_stoichiometry_witness(
        Metal.MtlArray; backend
    )
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

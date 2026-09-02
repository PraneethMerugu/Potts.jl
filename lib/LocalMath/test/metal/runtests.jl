using KernelAbstractions
using LocalMath
using Metal
using Test

Metal.functional() || error("the selected Metal witness is not functional")
Metal.allowscalar(false)

const LOCALMATH_METAL_WITNESSES = (
    "stage_program.jl",
    "execution_receipts.jl",
    "localmath_authoring.jl",
    "localmath_correctness.jl",
    "destination_grouping.jl",
)

@testset "LocalMath Metal runner inventory" begin
    discovered = Set(filter(
        name -> endswith(name, ".jl") && name != "runtests.jl",
        readdir(@__DIR__),
    ))
    @test discovered == Set(LOCALMATH_METAL_WITNESSES)
end

foreach(include, LOCALMATH_METAL_WITNESSES)

for witness in (
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
    )
    include(joinpath(@__DIR__, "..", "scientific_witnesses", witness))
end

@testset "LocalMath cross-domain Metal witnesses" begin
    backend = Metal.MetalBackend()
    @test run_localmath_d2q9_witness(Metal.MtlArray; backend).result ==
        run_localmath_d2q9_witness(Metal.MtlArray; backend).reference
    @test run_localmath_lattice_spring_witness(Metal.MtlArray; backend).result ==
        run_localmath_lattice_spring_witness(Metal.MtlArray; backend).reference
    @test run_localmath_matrix_free_fem_witness(Metal.MtlArray; backend).result ==
        run_localmath_matrix_free_fem_witness(Metal.MtlArray; backend).reference
    @test run_localmath_zbuffer_witness(Metal.MtlArray; backend).result ==
        run_localmath_zbuffer_witness(Metal.MtlArray; backend).reference
end

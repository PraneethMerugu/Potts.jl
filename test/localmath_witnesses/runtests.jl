include("lbm_d2q9.jl")
include("lattice_spring.jl")
include("matrix_free_fem.jl")
include("zbuffer.jl")
include("compacted_dem_contacts.jl")
include("compacted_active_fem.jl")
include("compacted_particle_cells.jl")
include("ordered_rsa.jl")
include("ordered_pgs_3d.jl")
include("ordered_stoichiometry.jl")
include("localmath_authoring.jl")

using Test

@testset "LocalMath scientific examples" begin
    lbm = run_localmath_d2q9_witness()
    spring = run_localmath_lattice_spring_witness()
    relaxed_spring = run_localmath_lattice_spring_witness(; force_mode = :fast)
    fem = run_localmath_matrix_free_fem_witness()
    zbuffer = run_localmath_zbuffer_witness()
    rsa = run_localmath_ordered_rsa_witness()
    pgs = run_localmath_ordered_pgs_3d_witness()
    chemistry = run_localmath_ordered_stoichiometry_witness()

    @test lbm.result == lbm.reference
    @test spring.result == spring.reference
    @test relaxed_spring.result.damage == relaxed_spring.reference.damage
    @test relaxed_spring.result.edge_state == relaxed_spring.reference.edge_state
    @test all(isapprox.(relaxed_spring.result.force,
        relaxed_spring.reference.force; rtol = 8eps(Float32)))
    @test relaxed_spring.result.fracture == relaxed_spring.reference.fracture
    @test fem.result == fem.reference
    @test zbuffer.result == zbuffer.reference
    @test rsa.result == rsa.reference
    @test pgs.result == pgs.reference
    @test chemistry.result == chemistry.reference
    @test length(lbm.semantics.stages) == 1
    @test map(publication -> publication.details.law.kind,
        only(lbm.semantics.stages).publications) == (:unique, :unique)
    @test length(spring.semantics.stages) == 2
    @test map(publication -> publication.details.law.kind,
        spring.semantics.stages[2].publications) ==
        (:unique, :reduce, :resolve)
    @test only(fem.semantics.stages).publications[1].details.law.kind ===
        :reduce
    @test only(zbuffer.semantics.stages).publications[1].details.law.kind ===
        :resolve
end

@testset "LocalMath compacted scientific examples" begin
    @test length(run_localmath_compacted_dem_contacts_witness().cases) == 6
    @test length(run_localmath_compacted_active_fem_witness().cases) == 2
    particle_cells = run_localmath_compacted_particle_cells_witness()
    @test length(particle_cells.cases) == 2
    @test length(particle_cells.diagnostics) == 2
end

@testset "LocalMath authored domain examples" begin
    result = run_localmath_authored_domain_witness()
    @test length(result.stencil1.periodic) == 6
    @test length(result.stencil2.periodic) == 20
    @test length(result.stencil3.periodic) == 64
    @test length(result.cic) == 5
    @test length(result.tsc) == 5
    @test result.graph.forward == Float32[3, 5, 7]
    @test result.graph.inverse == Float32[3, 8, 12, 7]
    @test result.potts.winner == Int32[1, 3]
end

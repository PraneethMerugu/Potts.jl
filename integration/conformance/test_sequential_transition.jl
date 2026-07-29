using Test
using .TransitionKernelOracle
using .TransitionKernelAnalysis

function _moore_relation(::Val{N}) where {N}
    offsets = Tuple(offset for offset in Iterators.product(
        ntuple(_ -> -1:1, Val(N))...) if any(!iszero, offset))
    return OracleRelation(offsets)
end

@testset "transition evidence equilibrium sequential qualification" begin
    medium = oracle_medium(1)
    cell = oracle_cell(1)
    domain = OracleDomain((3,); boundaries = (OraclePeriodic,))
    relation = von_neumann_relation(Val(1))
    volume = OracleVolumeEnergy(Dict(1 => 1), Dict(1 => 1))
    model = OracleModel(relation, (volume,);
        acceptance = OracleMetropolisHastings(), temperature = 1)
    catalog = enumerate_states(domain, (medium, cell))
    primitive = primitive_kernel(catalog, domain, model)
    normalized = sequential_mcs_kernel(catalog, domain, model)

    @test validate_kernel(primitive).valid
    @test validate_kernel(normalized).valid
    classes = communicating_classes(primitive; tolerance = big"1e-70")
    @test length(classes) == 3
    interior = only(class for class in classes if length(class) == 6)
    @test all(state -> 0 < count(==(cell), state.owners) < 3,
        catalog.states[interior])

    interior_matrix = Matrix(normalized.matrix[interior, interior])
    stationary = stationary_analysis(interior_matrix; tolerance = 1e-11)
    @test stationary.nonnegative
    @test stationary.normalized
    @test stationary.stationarity_residual < 1e-11
    @test stationary.detailed_balance_residual < 1e-11
    @test is_irreducible(interior_matrix; tolerance = 1e-14)
    @test is_aperiodic(interior_matrix; tolerance = 1e-14)

    expected = Float64[]
    for state_id in interior
        energy = Float64(TransitionKernelOracle.global_energy(
            model, catalog.states[state_id], domain, BigFloat))
        push!(expected, exp(-energy))
    end
    expected ./= sum(expected)
    @test stationary.distribution ≈ expected rtol = 1e-10 atol = 1e-12
    @test maximum(abs, probability_currents(
        interior_matrix, stationary.distribution)) < 1e-11
end

@testset "transition evidence exhaustive tiny 2D and selected 3D lowering" begin
    medium = oracle_medium(1)
    first_cell = oracle_cell(1)
    second_cell = oracle_cell(2)
    labels = (medium, first_cell, second_cell)
    owner_types = Dict(medium => 1, first_cell => 2, second_cell => 2)
    interactions = Rational{Int}[0 2; 2 1]
    volume = OracleVolumeEnergy(
        Dict(1 => 1, 2 => 1), Dict(1 => 1, 2 => 1))

    for boundaries in ((OraclePeriodic, OraclePeriodic),
                       (OracleNoFlux, OracleNoFlux)),
        relation in (von_neumann_relation(Val(2)), _moore_relation(Val(2)))
        domain = OracleDomain((2, 2); boundaries)
        contact = OracleContactEnergy(interactions, owner_types, relation)
        model = OracleModel(relation, (volume, contact); temperature = 0)
        catalog = enumerate_states(domain, labels)
        @test length(catalog.states) == 81
        primitive = primitive_kernel(catalog, domain, model)
        normalized = sequential_mcs_kernel(catalog, domain, model)
        @test validate_kernel(primitive).valid
        @test validate_kernel(normalized).valid
        @test primitive.resolution === :primitive_attempt
        @test normalized.resolution === :normalized_mcs
    end

    domain_3d = OracleDomain((2, 1, 1);
        boundaries = (OracleNoFlux, OracleNoFlux, OracleNoFlux))
    relation_3d = von_neumann_relation(Val(3))
    contact_3d = OracleContactEnergy(interactions, owner_types, relation_3d)
    model_3d = OracleModel(relation_3d, (volume, contact_3d); temperature = 0)
    catalog_3d = enumerate_states(domain_3d, labels)
    primitive_3d = primitive_kernel(catalog_3d, domain_3d, model_3d)
    normalized_3d = sequential_mcs_kernel(catalog_3d, domain_3d, model_3d)
    @test length(catalog_3d.states) == 9
    @test validate_kernel(primitive_3d).valid
    @test validate_kernel(normalized_3d).valid
end

using Test
using SparseArrays
using .TransitionKernelOracle

@testset "sequential transition typed independent oracle state" begin
    cell = oracle_cell(1)
    medium = oracle_medium(1)
    @test cell != medium
    @test cell.kind === OracleCellKind
    @test medium.kind === OracleMediumKind
    @test_throws ArgumentError oracle_cell(0)

    domain = OracleDomain((3,); boundaries = (OraclePeriodic,))
    relation = von_neumann_relation(Val(1))
    @test TransitionKernelOracle.realize_neighbor(domain, relation, 1, 1) == 3
    @test TransitionKernelOracle.realize_neighbor(domain, relation, 3, 2) == 1

    no_flux = OracleDomain((3,); boundaries = (OracleNoFlux,))
    @test TransitionKernelOracle.realize_neighbor(no_flux, relation, 1, 1) === nothing
    @test TransitionKernelOracle.realize_neighbor(no_flux, relation, 3, 2) === nothing

    state = OracleMicrostate((cell, cell, medium))
    same_owner = direct_proposal(state, domain, relation, 1, 2)
    @test same_owner === nothing
    proposal = direct_proposal(state, domain, relation, 3, 1)
    @test proposal isa OracleProposal
    @test proposal.losing == medium
    @test proposal.gaining == cell
    @test proposal.forward_multiplicity == 2
    @test proposal.reverse_multiplicity == 0
    destination = destination_state(state, proposal)
    @test destination.owners == (cell, cell, cell)
    @test state.owners == (cell, cell, medium)
end

@testset "sequential transition independent global adhesion and volume energies" begin
    cell = oracle_cell(1)
    medium = oracle_medium(1)
    domain = OracleDomain((3,); boundaries = (OraclePeriodic,))
    relation = von_neumann_relation(Val(1))
    volume = OracleVolumeEnergy(Dict(1 => 1//1), Dict(1 => 2//1))
    contact = OracleContactEnergy(
        Rational{Int}[0 3; 3 0], Dict(medium => 1, cell => 2), relation)
    model = OracleModel(relation, (volume, contact); temperature = 0)
    state = OracleMicrostate((cell, cell, medium))

    @test global_volume_energy(volume, state, Rational{BigInt}) == 2
    @test global_contact_energy(contact, state, domain, Rational{BigInt}) == 6
    @test TransitionKernelOracle.global_energy(
        model, state, domain, Rational{BigInt}) == 8

    proposal = direct_proposal(state, domain, relation, 3, 1)
    destination = destination_state(state, proposal)
    @test global_volume_energy(volume, destination, Rational{BigInt}) == 8
    @test global_contact_energy(contact, destination, domain, Rational{BigInt}) == 0
    @test TransitionKernelOracle.global_energy(
              model, destination, domain, Rational{BigInt}) -
          TransitionKernelOracle.global_energy(
              model, state, domain, Rational{BigInt}) == 0
end

@testset "sequential transition hand-derived one-dimensional kernel" begin
    fixture = hand_derived_1d_fixture()
    @test length(fixture.catalog.states) == 4
    @test map(state -> state.owners, fixture.catalog.states) == [
        (fixture.medium, fixture.medium),
        (fixture.cell, fixture.medium),
        (fixture.medium, fixture.cell),
        (fixture.cell, fixture.cell),
    ]

    primitive = primitive_kernel(
        fixture.catalog, fixture.domain, fixture.model)
    normalized = sequential_mcs_kernel(
        fixture.catalog, fixture.domain, fixture.model)
    @test eltype(primitive.matrix) === ExactProbability
    @test primitive.convergence === nothing
    @test Matrix(primitive.matrix) == fixture.expected_primitive
    @test Matrix(normalized.matrix) == fixture.expected_mcs
    @test normalized.resolution === :normalized_mcs
    @test validate_kernel(primitive).valid
    @test validate_kernel(normalized).valid
    @test validate_kernel(normalized).row_sums == fill(1//1, 4)

    mixed = fixture.catalog.states[2]
    row = transition_row(primitive, mixed)
    @test row[1] == 1//4
    @test row[2] == 1//2
    @test row[4] == 1//4
    @test length(transition_records(primitive)) == 8
end

@testset "sequential transition exact zero-temperature Hastings multiplicities" begin
    cell = oracle_cell(1)
    medium = oracle_medium(1)
    domain = OracleDomain((5,); boundaries = (OraclePeriodic,))
    relation = OracleRelation(((-2,), (-1,), (1,), (2,)))
    model = OracleModel(relation;
        acceptance = OracleMetropolisHastings(), temperature = 0)
    catalog = enumerate_states(domain, (medium, cell))
    source = OracleMicrostate((cell, cell, medium, cell, medium))
    destination = OracleMicrostate((cell, cell, cell, cell, medium))
    proposal = direct_proposal(source, domain, relation, 3, 1)
    @test proposal.forward_multiplicity == 3
    @test proposal.reverse_multiplicity == 1

    kernel = primitive_kernel(catalog, domain, model)
    @test kernel.matrix[state_id(catalog, source), state_id(catalog, destination)] == 1//20
    @test validate_kernel(kernel).valid
end

@testset "sequential transition high-precision finite-temperature convergence" begin
    cell = oracle_cell(1)
    medium = oracle_medium(1)
    domain = OracleDomain((2,); boundaries = (OracleNoFlux,))
    relation = von_neumann_relation(Val(1))
    volume = OracleVolumeEnergy(Dict(1 => 1//1), Dict(1 => 1//1))
    model = OracleModel(relation, (volume,);
        acceptance = OracleConventionalMetropolis(), temperature = 1//1)
    catalog = enumerate_states(domain, (medium, cell))
    precision = PrecisionPolicy(bits = 192, refinement_bits = 96,
        tolerance = "1e-50")

    primitive = primitive_kernel(catalog, domain, model; precision)
    normalized = sequential_mcs_kernel(catalog, domain, model; precision)
    @test eltype(primitive.matrix) === BigFloat
    @test primitive.convergence isa ConvergenceRecord
    @test primitive.convergence.converged
    @test primitive.convergence.base_bits == 192
    @test primitive.convergence.refined_bits == 288
    @test normalized.convergence.converged
    @test validate_kernel(primitive).valid
    @test validate_kernel(normalized).valid

    mixed = OracleMicrostate((cell, medium))
    mixed_id = state_id(catalog, mixed)
    all_cell_id = state_id(catalog, OracleMicrostate((cell, cell)))
    expected = setprecision(288) do
        exp(BigFloat(-1)) / BigFloat(4)
    end
    @test primitive.matrix[mixed_id, all_cell_id] ≈ expected rtol = big"1e-70"
end

@testset "sequential transition catalog closure and independence guard" begin
    fixture = hand_derived_1d_fixture()
    incomplete = StateCatalog(fixture.catalog.states[1:3])
    @test_throws ArgumentError primitive_kernel(
        incomplete, fixture.domain, fixture.model)

    source = read(joinpath(@__DIR__, "..", "transition",
        "TransitionKernelOracle.jl"), String)
    forbidden = (
        "using CorePotts", "import CorePotts", "construct_copy_attempt",
        "construct_proposal_attempt", "energy_change", "evaluate_copy",
        "stage_copy_transaction", "commit_copy_proposal", "_realized_coloring",
        "_checkerboard_",
    )
    @test all(token -> !occursin(token, source), forbidden)
end

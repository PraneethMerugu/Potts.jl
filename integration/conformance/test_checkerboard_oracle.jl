using Test
using .TransitionKernelOracle
using .CheckerboardOracle

@testset "checkerboard transition independent canonical checkerboard coloring" begin
    relation1 = von_neumann_relation(Val(1))
    line = OracleDomain((3,); boundaries = (OracleNoFlux,))
    coloring1 = canonical_greedy_coloring(line, (relation1,))
    @test coloring1.sites == [1, 2, 3]
    @test coloring1.colors == [1, 2, 1]
    @test coloring1.color_sites == [[1, 3], [2]]
    @test color_orders(coloring1) == Tuple[(1, 2), (2, 1)]

    relation2 = von_neumann_relation(Val(2))
    square = OracleDomain((2, 2);
        boundaries = (OraclePeriodic, OraclePeriodic))
    coloring2 = canonical_greedy_coloring(square, (relation2,))
    @test coloring2.sites == [1, 2, 3, 4]
    @test coloring2.colors == [1, 2, 2, 1]
    @test coloring2.color_sites == [[1, 4], [2, 3]]
end

@testset "checkerboard transition exact UInt32 conflict ties" begin
    cell = oracle_cell(1)
    medium = oracle_medium(1)
    domain = OracleDomain((3,); boundaries = (OracleNoFlux,))
    relation = von_neumann_relation(Val(1))
    state = OracleMicrostate((medium, cell, medium))
    left = direct_proposal(state, domain, relation, 1, 2)
    right = direct_proposal(state, domain, relation, 3, 1)
    @test left isa OracleProposal
    @test right isa OracleProposal
    @test left.gaining == right.gaining == cell
    @test left.losing.kind === OracleMediumKind
    @test right.losing.kind === OracleMediumKind

    distribution = conflict_selection_distribution((left, right))
    word_count = big(1) << 32
    @test distribution.claim_tie_probability == 1 // word_count
    @test distribution.outcomes[(1,)] == (word_count + 1) // (2word_count)
    @test distribution.outcomes[(2,)] == (word_count - 1) // (2word_count)
    @test !haskey(distribution.outcomes, (1, 2))
    @test sum(values(distribution.outcomes)) == 1
end

@testset "checkerboard transition lifted color-pass and normalized-MCS rows" begin
    cell = oracle_cell(1)
    medium = oracle_medium(1)
    domain = OracleDomain((2, 2);
        boundaries = (OraclePeriodic, OraclePeriodic))
    relation = von_neumann_relation(Val(2))
    model = OracleModel(relation;
        acceptance = OracleConventionalMetropolis(), temperature = 0)
    catalog = enumerate_states(domain, (medium, cell))
    coloring = canonical_greedy_coloring(domain, (relation,))
    source = OracleMicrostate((cell, medium, medium, cell))

    lifted = checkerboard_lifted_mcs_row(source, coloring, domain, model)
    @test sum(values(lifted)) == 1
    @test all(state -> state.ordinal == length(state.order) + 1, keys(lifted))
    @test Set(state.order for state in keys(lifted)) == Set(color_orders(coloring))

    marginal = marginalize_configuration(lifted)
    @test marginal == checkerboard_mcs_row(source, coloring, domain, model)
    @test sum(values(marginal)) == 1

    full = checkerboard_mcs_kernel(catalog, domain, model)
    @test full.resolution === :checkerboard_normalized_mcs
    @test validate_kernel(full).valid
    source_id = state_id(catalog, source)
    @test all(pair -> full.matrix[source_id, state_id(catalog, first(pair))] ==
        last(pair), marginal)

    color_pass = checkerboard_color_pass_kernel(catalog, domain, model)
    @test color_pass.resolution === :checkerboard_color_pass
    @test size(color_pass.matrix) == (96, 96)
    @test all(row -> sum(color_pass.matrix[row, :]) == 1,
        axes(color_pass.matrix, 1))

    first_order = first(color_orders(coloring))
    initial_lift = CheckerboardLiftedState(source, first_order, 1)
    pass_row = checkerboard_lifted_color_pass_row(
        initial_lift, coloring, domain, model)
    @test sum(values(pass_row)) == 1
    @test all(state -> state.order == first_order && state.ordinal == 2,
        keys(pass_row))
end

@testset "checkerboard transition finite-temperature acceptance subsets" begin
    cell = oracle_cell(1)
    medium = oracle_medium(1)
    domain = OracleDomain((2,); boundaries = (OracleNoFlux,))
    relation = von_neumann_relation(Val(1))
    volume = OracleVolumeEnergy(Dict(1 => 1 // 1), Dict(1 => 1 // 1))
    model = OracleModel(relation, (volume,);
        acceptance = OracleConventionalMetropolis(), temperature = 1 // 1)
    catalog = enumerate_states(domain, (medium, cell))
    coloring = canonical_greedy_coloring(domain, (relation,))
    source = OracleMicrostate((cell, medium))
    precision = PrecisionPolicy(bits = 192, refinement_bits = 96,
        tolerance = "1e-50")

    # The second site chooses its cell donor with probability 1/2. That uphill volume proposal
    # has ΔH = 1 and is accepted with exp(-1), while the no-flux direction is a self-transition.
    row = checkerboard_color_pass_row(
        source, 2, coloring, domain, model; precision)
    all_cell = OracleMicrostate((cell, cell))
    expected = setprecision(288) do
        exp(BigFloat(-1)) / BigFloat(2)
    end
    @test row[all_cell] ≈ expected rtol = big"1e-70"
    @test row[source] ≈ 1 - expected rtol = big"1e-70"
    @test sum(values(row)) ≈ 1 rtol = big"1e-70"

    full = checkerboard_mcs_kernel(catalog, domain, model; precision)
    @test full.convergence isa ConvergenceRecord
    @test full.convergence.converged
    @test validate_kernel(full).valid

    pass = checkerboard_color_pass_kernel(catalog, domain, model; precision)
    @test pass.convergence isa ConvergenceRecord
    @test pass.convergence.converged
end

@testset "checkerboard transition mechanistic sequential-checkerboard discrepancy" begin
    cell = oracle_cell(1)
    medium = oracle_medium(1)
    domain = OracleDomain((3,); boundaries = (OraclePeriodic,))
    relation = von_neumann_relation(Val(1))
    model = OracleModel(relation;
        acceptance = OracleConventionalMetropolis(), temperature = 0)
    catalog = enumerate_states(domain, (medium, cell))
    source = OracleMicrostate((cell, medium, medium))
    source_id = state_id(catalog, source)

    sequential = sequential_mcs_kernel(catalog, domain, model)
    checkerboard = checkerboard_mcs_kernel(catalog, domain, model)
    sequential_row = sequential.matrix[source_id, :]
    checkerboard_row = checkerboard.matrix[source_id, :]
    total_variation = sum(abs(sequential_row[destination] -
        checkerboard_row[destination]) for destination in axes(sequential.matrix, 2)) / 2

    # Sequential draws recipients with replacement, so it can leave this state unchanged after
    # three attempts. The randomized checkerboard sweep visits each of the three colors exactly
    # once and has no path back to this source configuration.
    @test sequential.matrix[source_id, source_id] == 5 // 54
    @test checkerboard.matrix[source_id, source_id] == 0
    @test total_variation == 41 // 216
end

@testset "checkerboard transition checkerboard oracle independence guard" begin
    source = read(joinpath(@__DIR__, "..", "transition",
        "CheckerboardOracle.jl"), String)
    forbidden = (
        "using CorePotts", "import CorePotts", "construct_copy_attempt",
        "construct_proposal_attempt", "energy_change", "evaluate_copy",
        "stage_copy_transaction", "commit_copy_proposal", "_realized_coloring",
        "_checkerboard_order_kernel!", "_checkerboard_candidates!",
        "_checkerboard_commit!",
    )
    @test all(token -> !occursin(token, source), forbidden)
end

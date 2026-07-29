using KernelAbstractions
using Statistics

function _lottery_fixture(::Type{T} = Float32, dims = (4, 4)) where {
        T <: AbstractFloat}
    fixture = _scientific_fixture(T, dims)
    tracker = BoundaryMeasureTracker(fixture.boundary.metric, fixture.boundary.relation)
    components = ScientificComponentSet(
        energies = (fixture.volume, fixture.contact, fixture.boundary,))
    return (; fixture..., tracker, components)
end

@testset "LotteryCPM values and capability rejection" begin
    algorithm = LotteryCPM(temperature = 6.0f0)
    @test algorithm.temperature === 6.0f0
    @test component_identity(algorithm).key == :lottery_cpm
    guarantees = algorithm_guarantees(algorithm)
    @test guarantees.mcs_normalization ==
          :one_activation_per_mutable_site_in_expectation
    @test guarantees.equilibrium_status == :not_claimed
    @test guarantees.proposal_process.rounds == :realized_maximum_degree_plus_one
    @test guarantees.transaction_semantics.snapshot == :common_per_round
    @test :neighbor_covariance_statistics in guarantees.validation_evidence
    @test_throws ArgumentError LotteryCPM(temperature = -1.0f0)

    fixture = _lottery_fixture()
    compiled = compile_scientific_state(
        fixture.state, fixture.domain, fixture.tracker)
    connectivity = PreserveConnectedCells(
        first_shell_relation(ConnectivityRole(), Val(2)))
    constrained = ScientificComponentSet(
        energies = fixture.components.energies, constraints = (connectivity,))
    @test_throws ArgumentError init_scientific(compiled,
        fixture.proposal_relation, constrained, algorithm)
end

@testset "Lottery expected-MCS accounting and replay" begin
    fixture = _lottery_fixture()
    first_state = compile_scientific_state(
        fixture.state, fixture.domain, fixture.tracker)
    second_state = compile_scientific_state(
        fixture.state, fixture.domain, fixture.tracker)
    algorithm = LotteryCPM(temperature = 5.0f0)
    first_run = init_scientific(first_state, fixture.proposal_relation,
        fixture.components, algorithm; seed = 0x1077)
    second_run = init_scientific(second_state, fixture.proposal_relation,
        fixture.components, algorithm; seed = 0x1077)

    @test current_mcs_report(first_run) === nothing
    @test step!(first_run) === first_run
    @test step!(second_run) === second_run
    reports = test_parallel_algorithm_report_contract(first_run, second_run)
    first_report = reports.first_report
    second_report = reports.second_report
    site_count = mutable_site_count(fixture.domain)
    @test first_report.mcs == 1
    @test first_report.internal_rounds == first_run.algorithm_workspace.round_count
    @test first_report.scheduler_candidates ==
          site_count * first_report.internal_rounds
    test_parallel_algorithm_replay_contract(
        first_run, second_run, first_state, second_state, fixture.tracker)
end

@testset "Lottery topology calibration is uniform across closed boundaries" begin
    dims = (5, 5)
    state = LogicalPottsState(fill(MediumOwner(1), dims), CellCapacity(1);
        medium_domains = [MediumID(1)])
    boundaries = (AxisBoundary(ClosedBoundary()), AxisBoundary(ClosedBoundary()))
    domain = CartesianDomain(dims; boundaries)
    proposal = first_shell_relation(ProposalRole(), Val(2))
    surface = first_shell_relation(SurfaceRole(), Val(2))
    tracker = BoundaryMeasureTracker(BoundaryEdgeCount(), surface)
    compiled = compile_scientific_state(state, domain, tracker)
    integration = init_scientific(compiled, proposal, ScientificComponentSet(),
        LotteryCPM(); seed = 0xca11)
    workspace = integration.algorithm_workspace
    @test workspace.round_count == 5
    degrees = diff(Array(workspace.neighbor_offsets))
    @test minimum(degrees) == 2
    @test maximum(degrees) == 4

    mcs_count = 200
    activation_counts = zeros(Int, prod(dims))
    round_orders = Set{Tuple}()
    expected_order = collect(UInt32(1):workspace.round_count)
    for _ in 1:mcs_count
        step!(integration)
        KernelAbstractions.synchronize(integration.plan.backend)
        order = Array(workspace.round_order)
        @test sort(order) == expected_order
        push!(round_orders, Tuple(order))
        activation_counts .+= @view workspace.accounting[1:prod(dims)]
    end
    @test length(round_orders) > 1
    # Each site's exact per-round probability is 1 / (maximum_degree + 1), so one
    # activated opportunity per MCS in expectation irrespective of realized degree.
    @test all(abs.(activation_counts .- mcs_count) .<= 50)
    corners = activation_counts[[1, 5, 21, 25]]
    interior = activation_counts[[7, 8, 9, 12, 13, 14, 17, 18, 19]]
    @test abs(sum(corners) / length(corners) - sum(interior) / length(interior)) <= 30
end

@testset "Lottery 3D execution" begin
    fixture = _lottery_fixture(Float32, (3, 3, 3))
    compiled = compile_scientific_state(
        fixture.state, fixture.domain, fixture.tracker)
    integration = init_scientific(compiled, fixture.proposal_relation,
        fixture.components, LotteryCPM(temperature = 4.0f0); seed = 29)
    step!(integration)
    report = current_mcs_report(integration)
    @test report.scheduler_candidates ==
          27 * integration.algorithm_workspace.round_count
    snapshot = logical_state(integration)
    @test isempty(tracker_conformance_errors(compiled, fixture.tracker, snapshot))
end

@testset "Lottery waiting, repetition, and spatial statistics" begin
    dims = (8, 8)
    state = LogicalPottsState(fill(MediumOwner(1), dims), CellCapacity(1);
        medium_domains = [MediumID(1)])
    domain = CartesianDomain(dims)
    proposal = first_shell_relation(ProposalRole(), Val(2))
    tracker = BoundaryMeasureTracker(
        BoundaryEdgeCount(), first_shell_relation(SurfaceRole(), Val(2)))
    compiled = compile_scientific_state(state, domain, tracker)
    integration = init_scientific(compiled, proposal, ScientificComponentSet(),
        LotteryCPM(); seed = 0x57a71571c)
    workspace = integration.algorithm_workspace
    @test workspace.round_count == 5

    mcs_count = 600
    site_count = prod(dims)
    activated = zeros(Int, mcs_count, site_count)
    for mcs in 1:mcs_count
        step!(integration)
        KernelAbstractions.synchronize(integration.plan.backend)
        activated[mcs, :] .= @view workspace.accounting[1:site_count]
    end
    @test length(unique(Array(workspace.tickets))) == site_count
    samples = vec(activated)
    expected_zero = (4 / 5)^5
    expected_repeat = 1 - expected_zero - (4 / 5)^4
    @test abs(mean(samples) - 1) <= 0.03
    @test abs(var(samples; corrected = false) - 4 / 5) <= 0.04
    @test abs(mean(samples .== 0) - expected_zero) <= 0.02
    @test abs(mean(samples .>= 2) - expected_repeat) <= 0.02

    waiting_intervals = Int[]
    for site in 1:site_count
        active_mcs = findall(>(0), @view activated[:, site])
        append!(waiting_intervals, diff(active_mcs))
    end
    active_probability = 1 - expected_zero
    @test abs(mean(waiting_intervals) - inv(active_probability)) <= 0.06

    linear = LinearIndices(dims)
    neighbor_products = Float64[]
    for y in 1:dims[2], x in 1:dims[1]
        left = linear[x, y]
        right = linear[x == dims[1] ? 1 : x + 1, y]
        append!(neighbor_products,
            (activated[:, left] .- 1) .* (activated[:, right] .- 1))
    end
    # Adjacent sites cannot be local-ticket maxima in the same round. Summing the
    # per-round covariance -1/25 across five rounds gives -1/5 per MCS.
    @test abs(mean(neighbor_products) + 1 / 5) <= 0.04
end

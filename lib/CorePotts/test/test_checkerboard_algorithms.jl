using KernelAbstractions

struct _UndeclaredCheckerboardEnergy <: AbstractEnergy end
CorePotts.component_identity(::_UndeclaredCheckerboardEnergy) =
    ComponentIdentity(:undeclared_checkerboard_test, v"1.0.0", :energy)
CorePotts.energy_change(::_UndeclaredCheckerboardEnergy, proposal, state) = 0.0f0

function _checkerboard_fixture(::Type{T} = Float32, dims = (4, 4)) where {
        T <: AbstractFloat}
    fixture = _scientific_fixture(T, dims)
    tracker = BoundaryMeasureTracker(fixture.boundary.metric, fixture.boundary.relation)
    components = ScientificComponentSet(
        energies = (fixture.volume, fixture.contact, fixture.boundary,))
    return (; fixture..., tracker, components)
end

function _conflict_attempt(recipient, losing, gaining)
    return CopyAttempt(ActionableCopy, UInt32(recipient), UInt32(recipient + 1),
        CellOwner(CellID(losing)), CellOwner(CellID(gaining)), UInt32(1), UInt64(1),
        UInt64(recipient), UInt32(1), UInt32(1))
end

function _run_conflict_claims(attempts, priorities; capacity = 8)
    backend = KernelAbstractions.CPU()
    order = UInt32[1]
    offsets = UInt32[1, length(attempts) + 1]
    selected = ones(UInt8, length(attempts))
    dispositions = zeros(UInt8, length(attempts))
    max_priority = zeros(UInt32, capacity)
    min_identity = fill(typemax(UInt32), capacity)
    claim = CorePotts._checkerboard_claim_priorities!(backend, 8)
    ties = CorePotts._checkerboard_claim_ties!(backend, 8)
    select = CorePotts._checkerboard_select_conflicts!(backend, 8)
    claim(order, offsets, attempts, UInt32.(priorities), max_priority,
        UInt32(1); ndrange = length(attempts))
    ties(order, offsets, attempts, UInt32.(priorities), max_priority,
        min_identity, UInt32(1); ndrange = length(attempts))
    select(order, offsets, attempts, UInt32.(priorities), selected, dispositions,
        max_priority, min_identity, UInt32(1); ndrange = length(attempts))
    KernelAbstractions.synchronize(backend)
    return (; selected, dispositions, max_priority, min_identity)
end

@testset "CheckerboardSweepCPM values and capabilities" begin
    algorithm = CheckerboardSweepCPM(temperature = 6.0f0)
    @test algorithm.temperature === 6.0f0
    @test component_identity(algorithm).key == :checkerboard_sweep_cpm
    guarantees = algorithm_guarantees(algorithm)
    @test guarantees.mcs_normalization == :exact_once_per_mutable_site
    @test guarantees.equilibrium_status == :not_claimed
    @test guarantees.proposal_process.color_order ==
          :semantic_random_permutation_once_per_mcs
    @test guarantees.transaction_semantics.snapshot == :common_per_color
    @test :hard_constraint in guarantees.compatible_component_scopes.rejected
    @test :realized_coloring_validation in guarantees.validation_evidence
    @test_throws ArgumentError CheckerboardSweepCPM(temperature = -1.0f0)
    @test scientific_access(PositiveYield(1.0f0)) isa
          SnapshotScientificAccess
    @test scientific_access(_UndeclaredCheckerboardEnergy()) isa
          UnsupportedScientificAccess

    fixture = _checkerboard_fixture()
    compiled = compile_scientific_state(
        fixture.state, fixture.domain, fixture.tracker)
    connectivity = PreserveConnectedCells(
        first_shell_relation(ConnectivityRole(), Val(2)))
    constrained = ScientificComponentSet(
        energies = fixture.components.energies, constraints = (connectivity,))
    @test_throws ArgumentError init_scientific(compiled,
        fixture.proposal_relation, constrained, algorithm)
    @test_throws ScientificInterfaceError init_scientific(compiled,
        fixture.proposal_relation,
        ScientificComponentSet(energies = (_UndeclaredCheckerboardEnergy(),)),
        algorithm)
end


@testset "Checkerboard coloring includes tracker interaction relations" begin
    fixture = _scientific_fixture(Float32, (5, 5))
    extended_surface = normalized_kernel_relation(Val(2))
    tracker = BoundaryMeasureTracker(WeightedBoundaryCount(), extended_surface)
    compiled = compile_scientific_state(fixture.state, fixture.domain, tracker)
    integration = init_scientific(compiled, fixture.proposal_relation,
        ScientificComponentSet(), CheckerboardSweepCPM(); seed = 7)
    workspace = integration.algorithm_workspace
    sites = Array(workspace.sites)
    offsets = Array(workspace.color_offsets)
    for color in 1:Int(workspace.color_count)
        color_sites = Set(sites[Int(offsets[color]):Int(offsets[color + 1] - 1)])
        for site in color_sites, direction in 1:direction_count(extended_surface)
            neighbor = realize_neighbor(
                compiled.domain, extended_surface, Int(site), direction)
            neighbor.kind === MutableNeighbor || continue
            @test !(neighbor.site in color_sites)
        end
    end
end

@testset "Checkerboard color order is a semantic permutation" begin
    fixture = _checkerboard_fixture(Float32, (4, 4))
    compiled = compile_scientific_state(
        fixture.state, fixture.domain, fixture.tracker)
    integration = init_scientific(compiled, fixture.proposal_relation,
        fixture.components, CheckerboardSweepCPM(); seed = 0xc0102)
    workspace = integration.algorithm_workspace
    expected = collect(UInt32(1):workspace.color_count)
    observed = Set{Tuple}()
    for _ in 1:16
        step!(integration)
        KernelAbstractions.synchronize(integration.plan.backend)
        order = Array(workspace.color_order)
        @test sort(order) == expected
        push!(observed, Tuple(order))
    end
    @test length(observed) > 1
end

@testset "Checkerboard exact sweep accounting and replay" begin
    fixture = _checkerboard_fixture()
    first_state = compile_scientific_state(
        fixture.state, fixture.domain, fixture.tracker)
    second_state = compile_scientific_state(
        fixture.state, fixture.domain, fixture.tracker)
    algorithm = CheckerboardSweepCPM(temperature = 5.0f0)
    first_run = init_scientific(first_state, fixture.proposal_relation,
        fixture.components, algorithm; seed = 0xc01a)
    second_run = init_scientific(second_state, fixture.proposal_relation,
        fixture.components, algorithm; seed = 0xc01a)

    @test first_run.algorithm_workspace.color_count >= 2
    @test current_mcs_report(first_run) === nothing
    @test step!(first_run) === first_run
    @test step!(second_run) === second_run
    launches_before_report = first_run.plan.metrics.launches
    synchronizations_before_report = first_run.plan.metrics.host_synchronizations
    reports = test_parallel_algorithm_report_contract(first_run, second_run)
    first_report = reports.first_report
    second_report = reports.second_report
    @test first_run.plan.metrics.launches == launches_before_report + 1
    @test first_run.plan.metrics.host_synchronizations ==
          synchronizations_before_report + 1
    @test first_report.mcs == 1
    @test first_report.internal_rounds ==
          first_run.algorithm_workspace.color_count
    @test first_report.scheduler_candidates == mutable_site_count(fixture.domain)
    @test first_report.activated_attempts == mutable_site_count(fixture.domain)
    test_parallel_algorithm_replay_contract(
        first_run, second_run, first_state, second_state, fixture.tracker)
end

@testset "Checkerboard realized coloring handles odd periodic domains" begin
    fixture = _checkerboard_fixture(Float32, (3, 3))
    compiled = compile_scientific_state(
        fixture.state, fixture.domain, fixture.tracker)
    integration = init_scientific(compiled, fixture.proposal_relation,
        fixture.components, CheckerboardSweepCPM(temperature = 4.0f0); seed = 19)
    @test integration.algorithm_workspace.color_count >= 3
    step!(integration)
    report = current_mcs_report(integration)
    @test report.activated_attempts == 9
    snapshot = logical_state(integration)
    @test isempty(tracker_conformance_errors(
        compiled, fixture.tracker, snapshot))
end

@testset "Checkerboard deterministic cell claims" begin
    chain = _run_conflict_claims([
        _conflict_attempt(1, 1, 2),
        _conflict_attempt(2, 2, 3),
        _conflict_attempt(3, 3, 4),
    ], [10, 20, 30])
    @test chain.selected == UInt8[0, 0, 1]
    @test chain.dispositions == UInt8[1, 1, 0]
    @test chain.max_priority[2:3] == UInt32[20, 30]

    exact_tie = _run_conflict_claims([
        _conflict_attempt(5, 1, 2),
        _conflict_attempt(3, 2, 3),
    ], [7, 7])
    @test exact_tie.selected == UInt8[0, 1]
    @test exact_tie.min_identity[2] == UInt32(3)
end

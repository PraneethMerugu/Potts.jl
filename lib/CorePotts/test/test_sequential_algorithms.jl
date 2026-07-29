using SciMLBase

function _sequential_fixture(::Type{T} = Float32) where {T <: AbstractFloat}
    fixture = _scientific_fixture(T, (4, 4))
    tracker = BoundaryMeasureTracker(fixture.boundary.metric, fixture.boundary.relation)
    components = ScientificComponentSet(
        energies = (fixture.volume, fixture.contact, fixture.boundary,))
    return (; fixture..., tracker, components)
end

@testset "scientific component sequential algorithm values" begin
    conventional = SequentialCPM(temperature = 7.5f0)
    equilibrium = SequentialEquilibrium(temperature = 7.5)
    @test conventional.temperature === 7.5f0
    @test equilibrium.temperature === 7.5
    @test component_identity(conventional).key == :sequential_cpm
    @test component_identity(equilibrium).key == :sequential_equilibrium
    conventional_profile = algorithm_guarantees(conventional)
    equilibrium_profile = algorithm_guarantees(equilibrium)
    @test conventional_profile isa AlgorithmGuaranteeProfile
    @test conventional_profile.proposal_process.recipient == :uniform_with_replacement
    @test conventional_profile.mcs_normalization == :exact_n_independent_attempts
    @test conventional_profile.transaction_semantics.commit == :immediate_serial
    @test :mechanical in conventional_profile.compatible_component_scopes.supported
    @test equilibrium_profile.equilibrium_status ==
          :qualified_reversible_models
    @test :mechanical in equilibrium_profile.compatible_component_scopes.rejected
    @test equilibrium_profile.backend_contract == (:cpu, :metal, :amdgpu)
    @test_throws ArgumentError SequentialCPM(temperature = -1.0f0)
    @test_throws ArgumentError SequentialEquilibrium(temperature = Float32(NaN))

    fixture = _sequential_fixture()
    compiled = compile_scientific_state(
        fixture.state, fixture.domain, fixture.tracker)
    coupling = OwnerScalarCoupling(:volume_strength, MediumID(1) => 0.0f0;
        number_type = Float32)
    field = CellCenteredField(zeros(Float32, 4, 4))
    drive = ChemotaxisDrive(
        field, coupling, LinearResponse(), ExtensionChemotaxis())
    modifier = PositiveYield(1.0f0)
    @test_throws ArgumentError init_scientific(compiled,
        fixture.proposal_relation, ScientificComponentSet(drives = (drive,)),
        equilibrium)
    @test_throws ArgumentError init_scientific(compiled,
        fixture.proposal_relation,
        ScientificComponentSet(kinetic_modifiers = (modifier,)), equilibrium)
    @test_throws ArgumentError init_scientific(compiled,
        fixture.proposal_relation, ScientificComponentSet(drives = (drive,)),
        SequentialCPM(temperature = 0.0f0))
end

@testset "SequentialCPM normalized accounting and replay" begin
    fixture = _sequential_fixture()
    first_state = compile_scientific_state(
        fixture.state, fixture.domain, fixture.tracker)
    second_state = compile_scientific_state(
        fixture.state, fixture.domain, fixture.tracker)
    algorithm = SequentialCPM(temperature = 5.0f0)
    first_run = init_scientific(first_state, fixture.proposal_relation,
        fixture.components, algorithm; seed = 0x5eed)
    second_run = init_scientific(second_state, fixture.proposal_relation,
        fixture.components, algorithm; seed = 0x5eed)

    @test algorithm_guarantees(first_run) == algorithm_guarantees(algorithm)
    @test current_mcs_report(first_run) === nothing
    @test step!(first_run) === first_run
    @test step!(second_run) === second_run
    first_report = current_mcs_report(first_run)
    second_report = current_mcs_report(second_run)
    site_count = mutable_site_count(fixture.domain)
    @test first_report == second_report
    @test first_report.mcs == 1
    @test first_report.internal_rounds == 1
    @test first_report.scheduler_candidates == site_count
    @test first_report.activated_attempts == site_count
    @test first_report.dynamic_conflicts == 0
    @test first_report.realized_proposals ==
          first_report.constraint_rejections + first_report.acceptance_rejections +
          first_report.accepted_copies
    @test first_report.activated_attempts ==
          first_report.same_owner_no_ops + first_report.boundary_no_ops +
          first_report.immutable_recipient_no_ops + first_report.constraint_rejections +
          first_report.acceptance_rejections + first_report.accepted_copies

    first_snapshot = logical_state(first_run)
    second_snapshot = logical_state(second_run)
    @test lattice_storage(first_snapshot) == lattice_storage(second_snapshot)
    @test isempty(tracker_conformance_errors(
        first_state, fixture.tracker, first_snapshot))
    @test isempty(tracker_conformance_errors(
        second_state, fixture.tracker, second_snapshot))

    @test step!(first_run, 2) === first_run
    @test first_run.mcs == 3
    @test current_mcs_report(first_run).mcs == 3
    @test_throws ArgumentError step!(first_run, -1)
end

@testset "Sequential no-op budget and equilibrium execution" begin
    dims = (3, 3)
    state = LogicalPottsState(fill(MediumOwner(1), dims), CellCapacity(1);
        medium_domains = [MediumID(1)])
    domain = CartesianDomain(dims)
    proposal_relation = first_shell_relation(ProposalRole(), Val(2))
    surface_relation = first_shell_relation(SurfaceRole(), Val(2))
    tracker = BoundaryMeasureTracker(BoundaryEdgeCount(), surface_relation)
    components = ScientificComponentSet()

    conventional_state = compile_scientific_state(state, domain, tracker)
    conventional = init_scientific(conventional_state, proposal_relation, components;
        seed = 91)
    step!(conventional)
    report = current_mcs_report(conventional)
    @test report.activated_attempts == 9
    @test report.same_owner_no_ops == 9
    @test report.realized_proposals == 0
    @test report.accepted_copies == 0

    equilibrium_state = compile_scientific_state(state, domain, tracker)
    equilibrium = init_scientific(equilibrium_state, proposal_relation, components,
        SequentialEquilibrium(temperature = 2.0); seed = 91)
    step!(equilibrium)
    @test current_mcs_report(equilibrium).same_owner_no_ops == 9
end

@testset "Sequential 3D and connectivity execution" begin
    three_dimensional = _scientific_fixture(Float64, (3, 3, 3))
    tracker_3d = BoundaryMeasureTracker(
        three_dimensional.boundary.metric, three_dimensional.boundary.relation)
    components_3d = ScientificComponentSet(energies = (
        three_dimensional.volume, three_dimensional.contact,
        three_dimensional.boundary,))
    compiled_3d = compile_scientific_state(
        three_dimensional.state, three_dimensional.domain, tracker_3d)
    integration_3d = init_scientific(compiled_3d,
        three_dimensional.proposal_relation, components_3d,
        SequentialCPM(temperature = 4.0); seed = 13)
    step!(integration_3d)
    report_3d = current_mcs_report(integration_3d)
    @test report_3d.activated_attempts == 27
    snapshot_3d = logical_state(integration_3d)
    @test isempty(tracker_conformance_errors(compiled_3d, tracker_3d, snapshot_3d))

    connected = _sequential_fixture()
    connectivity = PreserveConnectedCells(
        first_shell_relation(ConnectivityRole(), Val(2)))
    connected_components = ScientificComponentSet(
        energies = connected.components.energies, constraints = (connectivity,))
    compiled_connected = compile_scientific_state(
        connected.state, connected.domain, connected.tracker)
    connected_run = init_scientific(compiled_connected,
        connected.proposal_relation, connected_components,
        SequentialCPM(temperature = 5.0f0); seed = 17)
    @test connected_run.connectivity_workspace isa ConnectivityWorkspace
    step!(connected_run)
    connected_report = current_mcs_report(connected_run)
    @test connected_report.activated_attempts == 16
    connected_snapshot = logical_state(connected_run)
    @test isempty(tracker_conformance_errors(
        compiled_connected, connected.tracker, connected_snapshot))
end

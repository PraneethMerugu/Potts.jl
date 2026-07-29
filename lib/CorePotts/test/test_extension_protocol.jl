module ExternalEnergyExtension

using CorePotts

struct ConstantProposalEnergy{T <: AbstractFloat} <: AbstractEnergy
    value::T
end

CorePotts.component_identity(::ConstantProposalEnergy) =
    ComponentIdentity(:constant_proposal_energy, v"1.0.0", :energy)
CorePotts.energy_change(component::ConstantProposalEnergy, proposal::CopyProposal,
    state::LogicalPottsState) = component.value
CorePotts.proposal_energy_change(component::ConstantProposalEnergy,
    proposal::CopyProposal, context::ScientificProposalContext) = component.value
CorePotts.scientific_access(::ConstantProposalEnergy) = SnapshotScientificAccess()
CorePotts.component_semantic_data(component::ConstantProposalEnergy) =
    (value = component.value,)

struct TwoDimensionalEnergy{T <: AbstractFloat} <: AbstractEnergy
    value::T
end
CorePotts.component_identity(::TwoDimensionalEnergy) =
    ComponentIdentity(:two_dimensional_energy, v"1.0.0", :energy)
CorePotts.energy_change(component::TwoDimensionalEnergy,
    proposal::CopyProposal, state::LogicalPottsState) = component.value
CorePotts.proposal_energy_change(component::TwoDimensionalEnergy,
    proposal::CopyProposal, context::ScientificProposalContext) = component.value
CorePotts.scientific_access(::TwoDimensionalEnergy) = SnapshotScientificAccess()
CorePotts.capabilities(::TwoDimensionalEnergy) =
    ScientificCapabilities(dimensions = (2,))
CorePotts.component_semantic_data(component::TwoDimensionalEnergy) =
    (value = component.value,)

struct IncompleteCompiledEnergy <: AbstractEnergy end
CorePotts.component_identity(::IncompleteCompiledEnergy) =
    ComponentIdentity(:incomplete_compiled_energy, v"1.0.0", :energy)
CorePotts.energy_change(::IncompleteCompiledEnergy,
    proposal::CopyProposal, state::LogicalPottsState) = 0.0f0

end


@testset "extension protocol composable lifecycle trigger protocol" begin
    owners = reshape(OwnerRef[CellOwner(1), CellOwner(2)], 1, 2)
    state = LogicalPottsState(owners, CellCapacity(2);
        cell_types = Dict(CellID(1) => CellTypeID(1), CellID(2) => CellTypeID(2)),
        medium_domains = (MediumID(1),))
    snapshot = PreLifecycleSnapshot(state, 1)
    rng = LifecycleRNGContext(Philox4x32x10V1(), UInt64(9), UInt64(7))
    first_type = CellTypeIn(CellTypeID(1))
    stochastic = BernoulliCellTrigger(1.0f0, 3)
    conjunction = AllLifecycleTriggers(first_type, stochastic)

    @test lifecycle_triggered(first_type, snapshot, CellID(1))
    @test !lifecycle_triggered(first_type, snapshot, CellID(2))
    @test lifecycle_triggered(conjunction, snapshot, CellID(1), rng)
    @test !lifecycle_triggered(conjunction, snapshot, CellID(2), rng)
    @test isbitstype(typeof(conjunction))
    @test_throws ArgumentError CellTypeIn()
end


@testset "extension protocol downstream compiled-component protocol" begin
    component = ExternalEnergyExtension.ConstantProposalEnergy(2.5f0)
    @test validate_energy_component(component).category === :energy
    @test validate_proposal_component(component) === component
    @test scientific_access(component) isa SnapshotScientificAccess

    metadata = component_metadata(component)
    @test metadata.identity.key === :constant_proposal_energy
    @test metadata.identity.category === :energy
    @test metadata.semantic_data == (value = 2.5f0,)

    fixture = _scientific_fixture(Float32, (4, 4))
    selected = nothing
    for recipient in eachindex(lattice_storage(fixture.state)),
            direction in 1:direction_count(fixture.proposal_relation)
        attempt = construct_copy_attempt(fixture.state, fixture.domain,
            fixture.proposal_relation, recipient, direction)
        if is_actionable(attempt)
            selected = actionable_proposal(attempt)
            break
        end
    end
    @test selected !== nothing

    tracker = BoundaryMeasureTracker(fixture.boundary.metric, fixture.boundary.relation)
    compiled = compile_scientific_state(fixture.state, fixture.domain, tracker)
    transaction = stage_copy_transaction(compiled, tracker, selected)
    context = ScientificProposalContext(compiled, transaction)
    components = ScientificComponentSet(energies = (component,))
    evaluation = evaluate_copy(components, selected, context, Float32)

    @test evaluation.delta_h == 2.5f0
    @test evaluation.constraints_allowed
    @test isbitstype(typeof(components))

    model = PottsModel(fixture.proposal_relation, tracker; components)
    problem = PottsProblem(model, fixture.state, fixture.domain, (0, 1))
    @test compatibility_report(problem, SequentialCPM()).qualified

    connectivity = PreserveConnectedCells(first_shell_relation(
        ConnectivityRole(), Val(2); spacing = fixture.domain.spacing))
    constrained_model = PottsModel(fixture.proposal_relation, tracker;
        components = ScientificComponentSet(constraints = (connectivity,)))
    constrained_problem = PottsProblem(
        constrained_model, fixture.state, fixture.domain, (0, 1))
    constrained_report = compatibility_report(
        constrained_problem, CheckerboardSweepCPM())
    @test !constrained_report.qualified
    @test any(message -> occursin("hard constraints", message),
        constrained_report.messages)

    fixture_3d = _scientific_fixture(Float32, (3, 3, 3))
    tracker_3d = BoundaryMeasureTracker(
        fixture_3d.boundary.metric, fixture_3d.boundary.relation)
    dimensions_model = PottsModel(fixture_3d.proposal_relation, tracker_3d;
        components = ScientificComponentSet(energies =
            (ExternalEnergyExtension.TwoDimensionalEnergy(1.0f0),)))
    dimensions_problem = PottsProblem(
        dimensions_model, fixture_3d.state, fixture_3d.domain, (0, 1))
    dimensions_report = compatibility_report(dimensions_problem, SequentialCPM())
    @test !dimensions_report.qualified
    @test any(message -> occursin("does not declare 3D support", message),
        dimensions_report.messages)

    incomplete_model = PottsModel(fixture.proposal_relation, tracker;
        components = ScientificComponentSet(energies =
            (ExternalEnergyExtension.IncompleteCompiledEnergy(),)))
    incomplete_problem = PottsProblem(
        incomplete_model, fixture.state, fixture.domain, (0, 1))
    incomplete_report = compatibility_report(incomplete_problem, SequentialCPM())
    @test !incomplete_report.qualified
    @test any(message -> occursin("missing proposal_energy_change", message),
        incomplete_report.messages)
end

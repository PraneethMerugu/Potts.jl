struct _RejectAllContactPairs end
@inline (::_RejectAllContactPairs)(left_type::UInt32, right_type::UInt32) = false

function _contact_relationship_fixture(owners, cell_count;
        maximum_degree = 4, relationship_capacity = 16,
        pair_filter = CorePotts.SameCellTypePair(CellTypeID(1)),
        activation_energy = -50.0f0,
        initial_payload =
            CorePotts.ElasticLinkParameters(0.0f0, 0.0f0, 100_000.0f0))
    state = LogicalPottsState(
        owners, CellCapacity(cell_count);
        cell_types = Dict(
            CellID(id) => CellTypeID(1) for id in 1:cell_count),
        medium_domains = [MediumID(1)])
    spacing = (1.0f0, 1.0f0)
    domain = CartesianDomain(size(owners); spacing)
    boundary_relation = first_shell_relation(
        SurfaceRole(), Val(2); spacing)
    boundary_tracker =
        BoundaryMeasureTracker(BoundaryEdgeCount(), boundary_relation)
    connectivity = first_shell_relation(
        ConnectivityRole(), Val(2); spacing)
    moment_tracker = UnwrappedMomentTracker(
        connectivity; number_type = Float32)
    compiled = compile_scientific_state(
        state, domain, boundary_tracker; moment_tracker)
    contact_relation = static_relation(
        SpatialQueryRole(), CorePotts.offsets(CorePotts.MooreTopology{2}());
        spacing)
    declaration = CorePotts.RelationshipSet(
        :contact_links;
        edge = CorePotts.ElasticLinkParameters{Float32},
        maximum_degree,
        capacity = CorePotts.RelationshipCapacity(
            relationship_capacity))
    relationships = CorePotts.RelationshipState(declaration)
    component = CorePotts.ContactRelationshipHamiltonian(
        :contact_link_energy, :contact_links;
        relation = contact_relation,
        pair_filter,
        activation_energy,
        initial_payload,
        namespace = CorePotts.RNGNamespaceIdentity(0x1414_0001))
    effect =
        CorePotts.ContactRelationshipTransaction(component, relationships)
    workspace = CorePotts.CoupledAttemptWorkspace(
        (), (), (effect,))
    return (;
        state, domain, boundary_tracker, moment_tracker, compiled,
        declaration, relationships, component, effect, workspace)
end

function _contact_endpoint(fixture, id)
    cell = CellID(id)
    return CorePotts.CellEndpoint(
        cell, generation(fixture.state, cell))
end

function _contact_proposal(fixture, recipient, donor, losing, gaining)
    linear = LinearIndices(fixture.domain.dims)
    proposal = CopyProposal(
        linear[recipient...], linear[donor...],
        losing == 0 ? MediumOwner(1) : CellOwner(losing),
        gaining == 0 ? MediumOwner(1) : CellOwner(gaining))
    staged = stage_copy_transaction(
        fixture.compiled, fixture.boundary_tracker, proposal;
        moment_tracker = fixture.moment_tracker)
    return proposal, staged
end

function _prepare_contact!(
        fixture, proposal, staged;
        mcs = UInt64(1), attempt = UInt32(1))
    scientific = scientific_execution(fixture.compiled)
    CorePotts.begin_accepted_copy_mcs!(
        fixture.effect, scientific, mcs)
    CorePotts.prepare_accepted_copy_effect!(
        fixture.effect, proposal, staged, scientific,
        Philox4x32x10V1(), UInt64(0x1414),
        mcs, attempt)
    context = ScientificProposalContext(
        scientific, staged;
        algorithm_workspace = fixture.workspace)
    return scientific, context
end

function _contact_edge_keys(relationships)
    return Tuple(
        (value(edge.left.cell), value(edge.right.cell))
        for edge in relationships.edges)
end

@testset "coupled dynamics dynamic contact spring energy is exact and counted once" begin
    owners = fill(MediumOwner(1), 7, 7)
    owners[3, 3] = owners[3, 4] = CellOwner(1)
    owners[4, 3] = owners[4, 4] = CellOwner(2)
    fixture = _contact_relationship_fixture(owners, 2)
    payload =
        CorePotts.ElasticLinkParameters(2.0f0, 2.0f0, 100.0f0)
    CorePotts.create_relationship!(
        fixture.relationships,
        _contact_endpoint(fixture, 1),
        _contact_endpoint(fixture, 2), payload)
    proposal, staged = _contact_proposal(
        fixture, (3, 3), (4, 3), 1, 2)
    _, context = _prepare_contact!(fixture, proposal, staged)

    @test only(fixture.effect.candidate_present) == UInt8(0)
    old_distance = 1.0f0
    new_distance = sqrt(8.0f0 / 9.0f0)
    expected = 2.0f0 * (
        (new_distance - 2.0f0)^2 -
        (old_distance - 2.0f0)^2)
    observed = proposal_energy_change(
        fixture.component, proposal, context)
    @test observed ≈ expected atol = 8eps(Float32)
    @test observed != 2expected

    before_edges = deepcopy(fixture.relationships.edges)
    before_epoch = only(fixture.relationships.publication_epoch)
    @test CorePotts.preflight_accepted_copy_effect!(
        fixture.effect, proposal, staged,
        scientific_execution(fixture.compiled))
    CorePotts.commit_accepted_copy_effect!(
        fixture.effect, proposal, staged,
        scientific_execution(fixture.compiled))
    @test fixture.relationships.edges == before_edges
    @test only(fixture.relationships.publication_epoch) == before_epoch
end

@testset "coupled dynamics dynamic contact extinction subtracts energy and removes all links" begin
    owners = fill(MediumOwner(1), 7, 7)
    owners[3, 3] = CellOwner(1)
    owners[4, 3] = owners[4, 4] = CellOwner(2)
    fixture = _contact_relationship_fixture(owners, 2)
    payload =
        CorePotts.ElasticLinkParameters(3.0f0, 1.0f0, 100.0f0)
    CorePotts.create_relationship!(
        fixture.relationships,
        _contact_endpoint(fixture, 1),
        _contact_endpoint(fixture, 2), payload)
    proposal, staged = _contact_proposal(
        fixture, (3, 3), (4, 3), 1, 2)
    scientific, context = _prepare_contact!(fixture, proposal, staged)

    expected = -3.0f0 * (sqrt(1.25f0) - 1.0f0)^2
    @test proposal_energy_change(
        fixture.component, proposal, context) ≈
        expected atol = 8eps(Float32)
    before_epoch = only(fixture.relationships.publication_epoch)
    @test CorePotts.preflight_accepted_copy_effect!(
        fixture.effect, proposal, staged, scientific)
    @test only(fixture.effect.removal_count) == UInt32(1)
    CorePotts.commit_accepted_copy_effect!(
        fixture.effect, proposal, staged, scientific)
    @test isempty(fixture.relationships.edges)
    @test only(fixture.relationships.publication_epoch) ==
        before_epoch + UInt64(1)
    @test commit_staged!(
        fixture.compiled, staged; accepted = true)
    @test !is_active(
        logical_snapshot(fixture.compiled.potts), CellID(1))
end

@testset "coupled dynamics dynamic contact removes one canonical overlength link per endpoint" begin
    owners = fill(MediumOwner(1), 8, 8)
    owners[3, 3] = owners[3, 4] = CellOwner(1)
    owners[4, 3] = owners[4, 4] = CellOwner(2)
    owners[2, 2] = CellOwner(3)
    owners[7, 7] = CellOwner(4)
    fixture = _contact_relationship_fixture(
        owners, 4; pair_filter = _RejectAllContactPairs())
    payload =
        CorePotts.ElasticLinkParameters(0.0f0, 0.0f0, 0.0f0)
    for pair in ((1, 3), (1, 4), (2, 3), (2, 4))
        CorePotts.create_relationship!(
            fixture.relationships,
            _contact_endpoint(fixture, pair[1]),
            _contact_endpoint(fixture, pair[2]), payload)
    end
    proposal, staged = _contact_proposal(
        fixture, (4, 3), (3, 3), 2, 1)
    scientific, context = _prepare_contact!(fixture, proposal, staged)
    @test proposal_energy_change(
        fixture.component, proposal, context) == 0.0f0
    before_epoch = only(fixture.relationships.publication_epoch)
    @test CorePotts.preflight_accepted_copy_effect!(
        fixture.effect, proposal, staged, scientific)
    @test only(fixture.effect.removal_count) == UInt32(2)
    @test Tuple(fixture.effect.removal_endpoint_a[1:2]) ==
        (UInt32(1), UInt32(2))
    @test Tuple(fixture.effect.removal_endpoint_b[1:2]) ==
        (UInt32(3), UInt32(3))
    CorePotts.commit_accepted_copy_effect!(
        fixture.effect, proposal, staged, scientific)
    @test _contact_edge_keys(fixture.relationships) == ((1, 4), (2, 4))
    @test only(fixture.relationships.publication_epoch) ==
        before_epoch + UInt64(1)
end

@testset "coupled dynamics dynamic contact extinction removes every incident link" begin
    owners = fill(MediumOwner(1), 8, 8)
    owners[3, 3] = CellOwner(1)
    owners[4, 3] = CellOwner(2)
    owners[5, 3] = CellOwner(3)
    owners[4, 5] = CellOwner(4)
    fixture = _contact_relationship_fixture(
        owners, 4; pair_filter = _RejectAllContactPairs())
    payload =
        CorePotts.ElasticLinkParameters(0.0f0, 0.0f0, 100.0f0)
    for other in (1, 3, 4)
        CorePotts.create_relationship!(
            fixture.relationships,
            _contact_endpoint(fixture, 2),
            _contact_endpoint(fixture, other), payload)
    end
    proposal, staged = _contact_proposal(
        fixture, (4, 3), (3, 3), 2, 1)
    scientific, _ = _prepare_contact!(fixture, proposal, staged)
    before_epoch = only(fixture.relationships.publication_epoch)
    @test CorePotts.preflight_accepted_copy_effect!(
        fixture.effect, proposal, staged, scientific)
    @test only(fixture.effect.removal_count) == UInt32(3)
    CorePotts.commit_accepted_copy_effect!(
        fixture.effect, proposal, staged, scientific)
    @test isempty(fixture.relationships.edges)
    @test only(fixture.relationships.publication_epoch) ==
        before_epoch + UInt64(1)
end

@testset "coupled dynamics dynamic contact degree, capacity, and stale preflight are atomic" begin
    owners = fill(MediumOwner(1), 8, 8)
    owners[3, 3] = owners[3, 4] = CellOwner(1)
    owners[4, 3] = owners[4, 4] = CellOwner(2)
    owners[7, 6] = CellOwner(3)
    degree_fixture = _contact_relationship_fixture(
        owners, 3; maximum_degree = 1)
    payload =
        CorePotts.ElasticLinkParameters(0.0f0, 0.0f0, 100.0f0)
    CorePotts.create_relationship!(
        degree_fixture.relationships,
        _contact_endpoint(degree_fixture, 1),
        _contact_endpoint(degree_fixture, 3), payload)
    degree_proposal, degree_staged = _contact_proposal(
        degree_fixture, (4, 3), (3, 3), 2, 1)
    _prepare_contact!(
        degree_fixture, degree_proposal, degree_staged)
    @test only(degree_fixture.effect.candidate_present) == UInt8(0)
    @test all(iszero, degree_fixture.effect.permutation)

    owners[7, 7] = CellOwner(4)
    capacity_fixture = _contact_relationship_fixture(
        owners, 4; relationship_capacity = 1)
    CorePotts.create_relationship!(
        capacity_fixture.relationships,
        _contact_endpoint(capacity_fixture, 3),
        _contact_endpoint(capacity_fixture, 4), payload)
    proposal, staged = _contact_proposal(
        capacity_fixture, (4, 3), (3, 3), 2, 1)
    scientific, context = _prepare_contact!(
        capacity_fixture, proposal, staged)
    @test only(capacity_fixture.effect.candidate_present) == UInt8(1)
    @test proposal_energy_change(
        capacity_fixture.component, proposal, context) == -50.0f0
    before_edges = deepcopy(capacity_fixture.relationships.edges)
    before_epoch =
        only(capacity_fixture.relationships.publication_epoch)
    @test !CorePotts.preflight_accepted_copy_effect!(
        capacity_fixture.effect, proposal, staged, scientific)
    @test only(capacity_fixture.effect.status) ==
        CorePotts.CONTACT_RELATIONSHIP_CAPACITY
    @test capacity_fixture.relationships.edges == before_edges
    @test only(capacity_fixture.relationships.publication_epoch) ==
        before_epoch

    stale_fixture = _contact_relationship_fixture(owners, 4)
    stale_proposal, stale_staged = _contact_proposal(
        stale_fixture, (4, 3), (3, 3), 2, 1)
    stale_scientific, _ = _prepare_contact!(
        stale_fixture, stale_proposal, stale_staged)
    @test only(stale_fixture.effect.candidate_present) == UInt8(1)
    stale_fixture.compiled.potts.storage.generations[
        Int(only(stale_fixture.effect.candidate_endpoint))] += UInt64(1)
    @test !CorePotts.preflight_accepted_copy_effect!(
        stale_fixture.effect, stale_proposal,
        stale_staged, stale_scientific)
    @test only(stale_fixture.effect.status) ==
        CorePotts.CONTACT_RELATIONSHIP_STALE_ENDPOINT
    @test isempty(stale_fixture.relationships.edges)
    @test only(stale_fixture.relationships.publication_epoch) == UInt64(0)
end

@testset "coupled dynamics dynamic contact creation is canonical and restart-safe" begin
    owners = fill(MediumOwner(1), 8, 8)
    owners[3, 3] = owners[3, 4] = CellOwner(1)
    owners[4, 3] = owners[4, 4] = CellOwner(2)
    owners[7, 6] = CellOwner(3)
    owners[7, 7] = CellOwner(4)
    fixture = _contact_relationship_fixture(owners, 4)
    payload =
        CorePotts.ElasticLinkParameters(0.0f0, 0.0f0, 100.0f0)
    CorePotts.create_relationship!(
        fixture.relationships,
        _contact_endpoint(fixture, 3),
        _contact_endpoint(fixture, 4), payload)
    proposal, staged = _contact_proposal(
        fixture, (4, 3), (3, 3), 2, 1)
    scientific, _ = _prepare_contact!(fixture, proposal, staged)
    @test CorePotts.preflight_accepted_copy_effect!(
        fixture.effect, proposal, staged, scientific)
    CorePotts.commit_accepted_copy_effect!(
        fixture.effect, proposal, staged, scientific)
    @test _contact_edge_keys(fixture.relationships) == ((1, 2), (3, 4))

    components = ScientificComponentSet(
        energies = (fixture.component,))
    proposal_relation = first_shell_relation(
        ProposalRole(), Val(2); spacing = (1.0f0, 1.0f0))
    potts = init_scientific(
        fixture.compiled, proposal_relation,
        components, SequentialCPM(temperature = 20.0f0);
        seed = 0x1414,
        moment_tracker = fixture.moment_tracker,
        algorithm_workspace = fixture.workspace)
    plan = CorePotts.MCSPlan(
        CorePotts.PottsAttempts(),
        CorePotts.LifecyclePhase(),
        CorePotts.ObservationPhase())
    coupled = CorePotts.init_coupled(
        potts, plan,
        CorePotts.CoupledState(
            relationships = (fixture.relationships,)))
    checkpoint = capture_checkpoint(coupled)
    restored = restore_checkpoint(checkpoint, coupled)
    @test CorePotts.accepted_copy_workspace_state_valid(
        restored.potts.algorithm_workspace, restored.state)
    @test _contact_edge_keys(restored.state.relationships[1]) ==
        ((1, 2), (3, 4))
    step!(coupled)
    step!(restored)
    @test logical_state(coupled.potts)._owners ==
        logical_state(restored.potts)._owners
    @test coupled.state.relationships[1].edges ==
        restored.state.relationships[1].edges
    @test capture_checkpoint(coupled).state_fingerprint ==
        capture_checkpoint(restored).state_fingerprint
end

function _contact_zero_allocation_probe(
        fixture, proposal, staged)
    scientific, context = _prepare_contact!(
        fixture, proposal, staged;
        mcs = UInt64(2), attempt = UInt32(3))
    proposal_energy_change(
        fixture.component, proposal, context)
    CorePotts.preflight_accepted_copy_effect!(
        fixture.effect, proposal, staged, scientific)
    return nothing
end

@testset "coupled dynamics dynamic contact warm attempt path allocates zero bytes" begin
    owners = fill(MediumOwner(1), 7, 7)
    owners[3, 3] = owners[3, 4] = CellOwner(1)
    owners[4, 3] = owners[4, 4] = CellOwner(2)
    fixture = _contact_relationship_fixture(
        owners, 2; pair_filter = _RejectAllContactPairs())
    proposal, staged = _contact_proposal(
        fixture, (4, 3), (3, 3), 2, 1)
    _contact_zero_allocation_probe(fixture, proposal, staged)
    @test @allocated(
        _contact_zero_allocation_probe(
            fixture, proposal, staged)) == 0
end

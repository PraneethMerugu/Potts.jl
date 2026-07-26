function _phase14_relationship_process_plan(
        execution_mode)
    fixture = _scientific_fixture(
        Float32, (4, 4))
    property_values(
        fixture.state,
        :target_volume) .= 3.0f0
    property_values(
        fixture.state,
        :volume_strength) .= 1.0f6
    property_values(
        fixture.state,
        :target_boundary) .= 8.0f0
    property_values(
        fixture.state,
        :boundary_strength) .= 1.0f6
    tracker = BoundaryMeasureTracker(
        fixture.boundary.metric,
        fixture.boundary.relation)
    compiled = compile_scientific_state(
        fixture.state, fixture.domain, tracker)
    components = ScientificComponentSet(
        energies = (
            fixture.volume,
            fixture.contact,
            fixture.boundary))
    potts = init_scientific(
        compiled, fixture.proposal_relation,
        components,
        SequentialCPM(
            temperature = 0.0f0);
        seed = 0x14c1)

    declaration = CorePotts.RelationshipSet(
        :scheduled_links;
        edge =
            CorePotts.ElasticLinkParameters{
                Float32},
        maximum_degree = 2,
        capacity =
            CorePotts.RelationshipCapacity(4))
    relationships =
        CorePotts.RelationshipState(
        declaration)
    first = CorePotts.CellEndpoint(
        CellID(1),
        generation(fixture.state, CellID(1)))
    second = CorePotts.CellEndpoint(
        CellID(2),
        generation(fixture.state, CellID(2)))
    initial =
        CorePotts.ElasticLinkParameters(
            0.0f0, 0.0f0, 100000.0f0)
    CorePotts.create_relationship!(
        relationships, first, second, initial)

    retune = CorePotts.ElasticLinkRetune(
        :scheduled_retune,
        declaration, :cells;
        property = :volume_strength,
        strength = 0.0f0,
        target_length = 8.0f0,
        maximum_length = 12.0f0)
    cleanup = CorePotts.RelationshipCleanup(
        :scheduled_cleanup, declaration)

    protocol = CorePotts.StagedProtocol(
        CorePotts.ProtocolStage(
            :relax;
            mcs = CorePotts.MCSRange(1, 1)),
        CorePotts.ProtocolStage(
            :active;
            mcs = CorePotts.MCSRange(2, 4)))
    parameters =
        CorePotts.ScheduledParameter(
        :focal_parameters, protocol;
        relax =
            CorePotts.ElasticLinkParameters(
                10.0f0, 8.0f0, 12.0f0),
        active =
            CorePotts.ElasticLinkParameters(
                20.0f0, 8.0f0, 12.0f0))
    plan = CorePotts.MCSPlan(
        CorePotts.PottsAttempts(),
        CorePotts.CoupledPhase(
            :scheduled_retune,
            CorePotts.Update(
                retune;
                active =
                    CorePotts.PeriodicMCS(1, 2),
                value = parameters)),
        CorePotts.CoupledPhase(
            :relationship_cleanup,
            CorePotts.Update(
                cleanup)),
        CorePotts.LifecyclePhase(),
        CorePotts.ObservationPhase())
    state = CorePotts.CoupledState(
        relationships = (relationships,))
    coupled = CorePotts.init_coupled(
        potts, plan, state;
        protocol, execution_mode)
    realized = Tuple(
        CorePotts.invocation_process(
            only(entry.invocations))
        for entry in coupled.plan.entries
        if entry isa CorePotts.CoupledPhase)
    @test realized[1] isa
        CorePotts.ElasticLinkRetuneExecution
    @test realized[end] isa
        CorePotts.RelationshipCleanupExecution
    @test CorePotts.canonical_process_law(
        realized[1]) == retune
    @test CorePotts.canonical_process_law(
        realized[end]) == cleanup
    return (;
        coupled, relationships, compiled,
        first, second)
end

@testset "Phase 14 scheduled retune and cleanup execute through the root plan" begin
    host =
        _phase14_relationship_process_plan(
        CorePotts.HostCoupledExecution())
    portable =
        _phase14_relationship_process_plan(
        CorePotts.PortableCoupledExecution())

    for fixture in (host, portable)
        coupled = fixture.coupled
        relationships =
            fixture.relationships
        properties = CorePotts.scientific_execution(
            fixture.compiled).core.properties

        @test CorePotts.SciMLBase.step!(
            coupled) === coupled
        @test relationships.payload.strength[1] ==
              10.0f0
        @test properties.volume_strength ==
              Float32[10, 10]

        @test CorePotts.SciMLBase.step!(
            coupled) === coupled
        @test relationships.payload.strength[1] ==
              10.0f0

        @test CorePotts.SciMLBase.step!(
            coupled) === coupled
        @test relationships.payload.strength[1] ==
              20.0f0
        @test properties.volume_strength ==
              Float32[20, 20]

        relationships.generation_b[1] +=
            UInt64(1)
        @test CorePotts.SciMLBase.step!(
            coupled) === coupled
        @test relationships.count[1] == 0
        @test isempty(relationships.edges)
        @test coupled.mcs == 4
    end

    @test CorePotts.coupled_state_fingerprint(
        host.coupled) ==
          CorePotts.coupled_state_fingerprint(
        portable.coupled)
end

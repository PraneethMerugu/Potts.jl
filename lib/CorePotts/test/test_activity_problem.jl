import ProcessBigraphs
import SciMLBase

@testset "ActivityPottsProblem supported façade" begin
    fixture = _scientific_fixture(Float32, (6, 6))
    tracker = BoundaryMeasureTracker(
        fixture.boundary.metric, fixture.boundary.relation)
    relation = static_relation(
        SpatialQueryRole(),
        MooreTopology{2}();
        spacing=(1.0f0, 1.0f0),
    )
    algorithm = BudgetedSequentialCPM(
        AttemptsPerSite(1); temperature=20.0f0)
    program = ActivityProgram(
        maximum=10.0f0,
        strength=20.0f0,
        relation=relation,
        algorithm=algorithm,
        observation_cadence=1,
    )
    model = PottsModel(
        fixture.proposal_relation,
        tracker;
        components=ScientificComponentSet(energies=(
            fixture.volume,
            fixture.contact,
            fixture.boundary,
        )),
    )
    problem = PottsProblem(
        model,
        fixture.state,
        fixture.domain,
        (0, 2);
        seed=0x17b0,
    )
    activity_problem = ActivityPottsProblem(problem, program)
    integrator = SciMLBase.init(activity_problem)

    @test isempty(propertynames(integrator))
    @test_throws ArgumentError integrator.algorithm
    @test logical_state(integrator) isa LogicalPottsState
    @test site_property_value(integrator, 1) == 0.0f0
    @test current_mcs_report(integrator) === nothing
    @test isempty(ProcessBigraphs.observation_records(integrator))
    @test_throws BoundsError site_property_value(integrator, 0)

    @test SciMLBase.step!(integrator) === integrator
    @test current_mcs_report(integrator).mcs == 1
    @test length(ProcessBigraphs.observation_records(integrator)) == 1
    @test 0.0f0 <= site_property_value(integrator, 1) <= 10.0f0

    checkpoint = capture_checkpoint(integrator)
    restored = restore_checkpoint(checkpoint, integrator)
    @test ProcessBigraphs.observation_records(restored) ==
          ProcessBigraphs.observation_records(integrator)
    @test SciMLBase.step!(integrator) === integrator
    @test SciMLBase.step!(restored) === restored
    @test lattice_storage(logical_state(restored)) ==
          lattice_storage(logical_state(integrator))
    @test ProcessBigraphs.observation_records(restored) ==
          ProcessBigraphs.observation_records(integrator)
    @test all(site_property_value(restored, site) ==
              site_property_value(integrator, site)
        for site in 1:length(lattice_storage(logical_state(integrator))))
    @test_throws IntegratorTerminatedError SciMLBase.step!(integrator)

    @test_throws ArgumentError SciMLBase.init(
        activity_problem,
        SequentialCPM(),
    )
    incompatible_program = ActivityProgram(
        maximum=11.0f0,
        strength=20.0f0,
        relation=relation,
        algorithm=algorithm,
        observation_cadence=1,
    )
    incompatible_model = PottsModel(
        fixture.proposal_relation,
        tracker;
        components=ScientificComponentSet(energies=(
            fixture.volume,
            fixture.contact,
            fixture.boundary,
            program.hamiltonian,
        )),
    )
    incompatible_problem = PottsProblem(
        incompatible_model,
        fixture.state,
        fixture.domain,
        (0, 1),
    )
    @test_throws ArgumentError ActivityPottsProblem(
        incompatible_problem, incompatible_program)
end

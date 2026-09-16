import Serialization

@testset "scheduled stored-state schemas persist logically" begin
    @variables begin
        stored_site_marker
        stored_cell_marker
        stored_medium_marker
        stored_model_marker
    end
    cell = CellKind(:stored_cell; extinction = RetireAtZero())
    medium = MediumKind(:stored_medium)
    source = PottsSystem(
        name = :stored_state_model,
        statements = StatementSet((
            Lattice((4, 3)),
            cell,
            medium,
            SiteState(
                stored_site_marker;
                name = :stored_site_marker,
                initial = 1.0,
            ),
            CellState(
                stored_cell_marker;
                name = :stored_cell_marker,
                initial = 2.0,
                retirement = RetireTo(0.0),
            ),
            MediumState(
                stored_medium_marker;
                name = :stored_medium_marker,
                initial = 3.0,
            ),
            ModelState(
                stored_model_marker;
                name = :stored_model_marker,
                initial = 4.0,
            ),
            Protocol(Sweep(); name = :main),
        )),
        unknowns = [
            stored_site_marker,
            stored_cell_marker,
            stored_medium_marker,
            stored_model_marker,
        ],
    )
    scheduled = mtkcompile(source)
    schema = inspect(scheduled, StateSchema())
    @test Set(entry.storage for entry in schema.states) ==
          Set((:site, :cell, :medium, :model))

    labels = zeros(Int, 4, 3)
    labels[2, 2] = 1
    site_values = reshape(Float32.(1:12), 4, 3)
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        values = (
            stored_site_marker => site_values,
            stored_cell_marker => Float32[7],
            stored_model_marker => 9.0f0,
        ),
    )
    problem = PottsProblem(scheduled, initial, (0, 1); seed = 3)
    site_values .= -1
    integrator = init(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float32,
        save_start = false,
    )
    @test failure_report(integrator) === nothing
    saved = integrator.u
    @test saved[:stored_site_marker] == reshape(Float32.(1:12), 4, 3)
    @test saved[:stored_cell_marker][1] == 7.0f0
    @test all(==(2.0f0), saved[:stored_cell_marker][2:end])
    @test saved[:stored_medium_marker] == 3.0f0
    @test saved[:stored_model_marker] == 9.0f0
    @test SymbolicIndexingInterface.getu(
        problem, stored_model_marker
    )(problem) == 9.0f0
    @test SymbolicIndexingInterface.getu(
        integrator, stored_model_marker
    )(integrator) == 9.0f0

    captured = checkpoint(integrator)
    restored = init(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float32,
        checkpoint = captured,
        save_start = false,
    )
    @test failure_report(restored) === nothing
    @test restored.u[:stored_site_marker] == saved[:stored_site_marker]
    @test restored.u[:stored_cell_marker] == saved[:stored_cell_marker]
    @test restored.u[:stored_medium_marker] == saved[:stored_medium_marker]
    @test restored.u[:stored_model_marker] == saved[:stored_model_marker]

    restored_solution = solve!(restored)
    @test restored_solution.retcode == SciMLBase.ReturnCode.Success
    @test failure_report(restored_solution) === nothing
end

@testset "saved-state public named projections use one normalized store" begin
    @test_throws ArgumentError Potts.PottsSavedValues((:amount,), (1, 2))
    @test_throws ArgumentError Potts.PottsSavedValues((:amount, :amount), (1, 2))

    amount = Float32[1, 2]
    links = ((Int32(1), Int32(2)),)
    saved = PottsSavedState(
        3,
        reshape(Int32[1, 0], 2, 1),
        Int16[1],
        UInt32[1],
        Int32[1],
        (amount = amount,),
        (links = links,),
        (sample = 4.0f0,),
        (:sample, :unsaved_sample),
        (),
    )

    states_oracle = (amount = amount,)
    topology_oracle = (links = links,)
    observations_oracle = (sample = 4.0f0,)
    @test keys(saved.states) == (:amount,)
    @test keys(saved.topology) == (:links,)
    @test keys(saved.observations) == (:sample,)
    @test values(saved.states) == values(states_oracle)
    @test Tuple(saved.states) == Tuple(states_oracle)
    @test NamedTuple(saved.states) === states_oracle
    @test collect(saved.states) == collect(states_oracle)
    @test saved.states[1] === amount
    @test saved.states[:amount] === amount
    @test get(saved.states, :amount, nothing) === amount
    @test get(saved.states, :missing, nothing) === nothing
    @test haskey(saved.states, :amount)
    @test !haskey(saved.states, :missing)
    @test_throws FieldError saved.states[:missing]
    @test_throws FieldError saved.states.missing
    @test propertynames(saved.states) == (:amount,)
    @test collect(pairs(saved.states)) == collect(pairs(states_oracle))
    @test saved.states == states_oracle
    @test states_oracle == saved.states
    @test isequal(saved.states, states_oracle)
    @test hash(saved.states) == hash(states_oracle)
    @test sprint(show, saved.states) == sprint(show, states_oracle)
    @test saved.topology == topology_oracle
    @test saved.observations == observations_oracle
    @test saved.states.amount === amount
    @test saved.topology.links === links
    @test saved.observations.sample === 4.0f0
    @test saved[:amount] === saved.amount === amount
    @test saved[:links] === saved.links === links
    @test saved[:sample] === saved.sample === 4.0f0
    @test propertynames(saved) == (
        :mcs, :ownership, :cell_kinds, :cell_generations, :volumes,
        :native, :amount, :links, :sample,
    )
    @test_throws Potts.PottsKnownUnsavedError saved[:unsaved_sample]
    @test_throws Potts.PottsUnknownIdentityError saved[:unknown]

    amount[1] = 9.0f0
    @test saved[:amount][1] == 9.0f0

    stream = IOBuffer()
    Serialization.serialize(stream, saved)
    seekstart(stream)
    restored = Serialization.deserialize(stream)
    @test restored.states == saved.states
    @test restored.topology == saved.topology
    @test restored.observations == saved.observations
    @test restored[:amount] == saved[:amount]
    @test propertynames(restored) == propertynames(saved)
end

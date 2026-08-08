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
    @test restored.u[:stored_site_marker] == saved[:stored_site_marker]
    @test restored.u[:stored_cell_marker] == saved[:stored_cell_marker]
    @test restored.u[:stored_medium_marker] == saved[:stored_medium_marker]
    @test restored.u[:stored_model_marker] == saved[:stored_model_marker]
end

@testset "runtime, solution, and symbolic indexing" begin
    @parameters target=8.0 strength=2.0 temperature=4.0
    cell = CellKind(:cell)
    medium = MediumKind(:medium)
    @named source = PottsSystem(
        statements = StatementSet((
            Lattice((8, 8); relations = (proposal = VonNeumann(),)),
            cell,
            medium,
            Volume(cell; target, strength),
            Protocol(Sweep(; temperature); name = :main),
        )),
        parameters = [target, strength, temperature],
    )
    executable = compile(
        complete(source);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float64,
    )
    labels = zeros(Int, 8, 8)
    labels[3:5, 3:5] .= 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium)
    )
    problem = PottsProblem(executable, initial, (0, 6); seed = 0x55)
    first_integrator = init(problem)
    second_integrator = init(problem)
    @test first_integrator.runtime !== second_integrator.runtime
    @test first_integrator.u.ownership !== second_integrator.u.ownership
    @test first_integrator.t == 0
    step!(first_integrator)
    @test first_integrator.t == 1

    first_solution = solve(problem; save_everystep = true)
    replay = solve(problem; save_everystep = true)
    other_replica = solve(remake(problem; replica = 2); save_everystep = true)
    @test first_solution isa SciMLBase.AbstractTimeseriesSolution
    @test first_solution.retcode == SciMLBase.ReturnCode.Success
    @test first_solution.t == collect(0:6)
    @test all(
        left.ownership == right.ownership
        for (left, right) in zip(first_solution, replay)
    )
    @test any(
        left.ownership != right.ownership
        for (left, right) in zip(first_solution, other_replica)
    )
    @test first_solution(6).mcs == 6
    @test_throws ArgumentError solve(problem; saveat = [0, 2.5])
    endpoints = solve(problem)
    @test endpoints.t == [0, 6]
    @test_throws PottsToolkit.PottsUnsavedTimeError endpoints(3)
    @test_throws ArgumentError solve(problem; adaptive = true)

    @test SymbolicIndexingInterface.getp(problem, target)(problem) == 8.0
    setter = SymbolicIndexingInterface.setp(first_integrator, target)
    setter(first_integrator, 9.0)
    @test SymbolicIndexingInterface.getp(first_integrator, target)(
        first_integrator
    ) == 9.0
    transactional = SymbolicIndexingInterface.setp(
        first_integrator, (target, strength)
    )
    @test_throws ArgumentError transactional(first_integrator, (10.0, Inf))
    @test SymbolicIndexingInterface.getp(first_integrator, target)(
        first_integrator
    ) == 9.0
    @test SymbolicIndexingInterface.getp(first_integrator, strength)(
        first_integrator
    ) == 2.0
    transactional(first_integrator, (9.5, 2.5))
    @test SymbolicIndexingInterface.getp(first_integrator, target)(
        first_integrator
    ) == 9.5
    remade_buffer = SymbolicIndexingInterface.remake_buffer(
        executable, problem.parameters, (target,), (12.0,)
    )
    @test remade_buffer[:target] == 12.0
    @test problem.parameters[:target] == 8.0
    updated_solution = solve!(first_integrator)
    @test SymbolicIndexingInterface.getp(updated_solution, target)(
        updated_solution
    ) == 9.5
    @test last(updated_solution.provenance.parameter_history).second[1] == 9.5
    @test length(updated_solution.provenance.problem) == 64
    @test_throws ArgumentError begin
        immutable_setter = SymbolicIndexingInterface.setp(problem, target)
        immutable_setter(problem, 9.0)
    end

    ensemble = SciMLBase.EnsembleProblem(problem)
    serial = solve(
        ensemble,
        nothing,
        SciMLBase.EnsembleSerial();
        trajectories = 3,
    )
    threaded = solve(
        ensemble,
        nothing,
        SciMLBase.EnsembleThreads();
        trajectories = 3,
    )
    @test [solution.prob.replica for solution in serial.u] == UInt32[1, 2, 3]
    @test all(
        left.u[end].ownership == right.u[end].ownership
        for (left, right) in zip(serial.u, threaded.u)
    )
    @test any(
        serial.u[1].u[end].ownership != solution.u[end].ownership
        for solution in serial.u[2:end]
    )

    rerun_ensemble = SciMLBase.EnsembleProblem(
        remake(problem; tspan = (0, 2));
        output_func = (solution, context) -> (
            solution, context.repeat == 1
        ),
    )
    rerun = solve(
        rerun_ensemble,
        nothing,
        SciMLBase.EnsembleSerial();
        trajectories = 1,
    )
    @test only(rerun.u).prob.ensemble_repeat == 2
end

@testset "declared stored-state schemas persist logically" begin
    @variables t site_marker(t) cell_marker(t) medium_marker(t) model_marker(t)
    cell = CellKind(:stored_cell)
    medium = MediumKind(:stored_medium)
    @named stored = PottsSystem(
        statements = StatementSet((
            Lattice((4, 3)),
            cell,
            medium,
            SiteState(site_marker; name = :site_marker, initial = 1.0),
            CellState(cell_marker; name = :cell_marker, initial = 2.0),
            MediumState(medium_marker; name = :medium_marker, initial = 3.0),
            ModelState(model_marker; name = :model_marker, initial = 4.0),
            Protocol(Sweep(); name = :main),
        )),
        unknowns = [site_marker, cell_marker, medium_marker, model_marker],
        independent_variables = [t],
    )
    executable = compile(
        complete(stored);
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    labels = zeros(Int, 4, 3)
    labels[2, 2] = 1
    site_values = reshape(Float32.(1:12), 4, 3)
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        values = (
            site_marker => site_values,
            cell_marker => Float32[7],
            model_marker => 9.0f0,
        ),
    )
    problem = PottsProblem(executable, initial, (0, 1); seed = 3)
    site_values .= -1
    integrator = init(problem; save_start = false)
    @test SymbolicIndexingInterface.getu(problem, model_marker)(problem) ==
          9.0f0
    saved = integrator.u
    @test saved[:site_marker] == reshape(Float32.(1:12), 4, 3)
    @test saved[:cell_marker] == Float32[7]
    @test saved[:medium_marker] == 3.0f0
    @test saved[:model_marker] == 9.0f0
    @test SymbolicIndexingInterface.getu(integrator, model_marker)(integrator) ==
          9.0f0
    restored = init(
        problem;
        checkpoint = checkpoint(integrator),
        save_start = false,
    )
    @test restored.u[:site_marker] == saved[:site_marker]
    @test restored.u[:cell_marker] == saved[:cell_marker]
end

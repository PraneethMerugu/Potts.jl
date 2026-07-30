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
    @test_throws ArgumentError endpoints(3)
    @test_throws ArgumentError solve(problem; adaptive = true)

    @test SymbolicIndexingInterface.getp(problem, target)(problem) == 8.0
    setter = SymbolicIndexingInterface.setp(first_integrator, target)
    setter(first_integrator, 9.0)
    @test SymbolicIndexingInterface.getp(first_integrator, target)(
        first_integrator
    ) == 9.0
    @test_throws ArgumentError begin
        immutable_setter = SymbolicIndexingInterface.setp(problem, target)
        immutable_setter(problem, 9.0)
    end
end


@testset "checkpoint continuation" begin
    @parameters target=8.0 strength=2.0 temperature=5.0
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
        scalar_type = Float32,
    )
    labels = zeros(Int, 8, 8)
    labels[3:5, 3:5] .= 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium)
    )
    problem = PottsProblem(executable, initial, (0, 10); seed = 0x123456)
    uninterrupted = solve(problem)

    integrator = init(problem; save_start = false)
    for _ in 1:5
        step!(integrator)
    end
    captured = checkpoint(integrator)
    @test captured.schema == v"1.0.0"
    @test captured.core.snapshot.mcs == 5
    @test length(captured.checksum) == 64
    resumed = solve!(init(problem; checkpoint = captured, save_start = false))
    @test uninterrupted(10).ownership == resumed(10).ownership
    @test uninterrupted(10).volumes == resumed(10).volumes

    other_executable = compile(
        complete(source);
        engine = CheckerboardEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    other_problem = PottsProblem(
        other_executable, initial, (0, 10); seed = 0x123456
    )
    @test_throws ArgumentError init(other_problem; checkpoint = captured)
end


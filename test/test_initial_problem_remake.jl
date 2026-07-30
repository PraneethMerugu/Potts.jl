@testset "initial state, problem, and remake" begin
    @parameters target=8.0 strength temperature
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
    labelled = LabelledCells(labels; cells = [cell], medium)
    initial = PottsInitialState(ownership = labelled)
    labels .= 7
    @test all(getfield(getfield(initial, :ownership), :labels)[3:5, 3:5] .== 1)
    @test_throws ArgumentError PottsProblem(
        executable, initial, (0, 5); p = [strength => 2.0], seed = 4
    )
    problem = PottsProblem(
        executable,
        initial,
        (0, 5);
        p = [strength => 2.0, temperature => 4.0],
        seed = 0x1234,
    )
    @test problem.seed == 0x1234
    @test problem.replica == 1
    @test_throws UndefKeywordError PottsProblem(
        executable,
        initial,
        (0, 5);
        p = [strength => 2.0, temperature => 4.0],
    )
    @test_throws ArgumentError PottsProblem(
        executable,
        initial,
        (0.5, 5);
        p = [strength => 2.0, temperature => 4.0],
        seed = 1,
    )
    @test_throws ArgumentError PottsProblem(
        executable,
        initial,
        (0, 5);
        p = [strength => 2.0, temperature => 4.0],
        seed = 1,
        replica = 0,
    )

    remade = remake(problem; tspan = (2, 8), seed = 99, replica = 3)
    @test remade.tspan == (2, 8)
    @test remade.seed == 99
    @test remade.replica == 3
    @test remade.initial !== problem.initial
    @test_throws ArgumentError remake(problem; algorithm = :forbidden)

    layout = OwnershipLayout(
        (8, 8),
        CellPlacement(1, cell, ((3, 3), (3, 4), (4, 3), (4, 4)));
        medium,
    )
    layout_problem = PottsProblem(
        executable,
        PottsInitialState(ownership = layout),
        (0, 1);
        p = [strength => 2.0, temperature => 4.0],
        seed = 2,
    )
    @test sum(init(layout_problem).u.ownership .== 1) == 4
end

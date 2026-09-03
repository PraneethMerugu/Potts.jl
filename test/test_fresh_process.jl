@testset "fresh-process public authoring through solution" begin
    project = dirname(Base.active_project())
    script = raw"""
        using Potts
        using SciMLBase
        using Symbolics
        using ModelingToolkitBase: @parameters

        @parameters target = 4.0 strength = 1.0 temperature = 2.0
        cell = CellKind(:cell; extinction = RetireAtZero())
        medium = MediumKind(:medium)
        @mtkcompile model = PottsSystem(
            statements = StatementSet((
                Lattice((4, 4); boundary = Periodic()),
                cell,
                medium,
                Volume(cell; target, strength),
                Protocol(Sweep(; temperature); name = :main),
            )),
            parameters = [target, strength, temperature],
        )
        labels = zeros(Int, 4, 4)
        labels[2:3, 2:3] .= 1
        initial = PottsInitialState(
            ownership = LabelledCells(labels; cells = [cell], medium),
        )
        problem = PottsProblem(
            model,
            initial,
            (0, 2);
            p = (target => 4.0, strength => 1.0, temperature => 2.0),
            seed = 0x5a17,
        )
        solution = solve(
            problem,
            SequentialCPM();
            backend = CPUBackend(),
            scalar_type = Float64,
            saveat = (1, 2),
        )
        @assert solution.retcode == SciMLBase.ReturnCode.Success
        @assert solution.t == [0, 1, 2]
        @assert last(solution).mcs == 2
        @assert size(last(solution).ownership) == (4, 4)
        @assert !any(id -> id.name == "ModelingToolkit", keys(Base.loaded_modules))
        print("fresh-solution-ok")
    """
    command = `$(Base.julia_cmd()) --startup-file=no --project=$(project) -e $script`
    @test read(command, String) == "fresh-solution-ok"
end

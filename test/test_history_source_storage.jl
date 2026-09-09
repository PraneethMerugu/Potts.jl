using StaticArrays

@testset "history retention rejects Boolean sample counts" begin
    @variables value memory
    source = PottsSystem(
        name = :boolean_retention,
        statements = StatementSet((ModelState(value; initial = 1.0), HistoryState(memory; of = value, depth = true))),
        unknowns = (value, memory),
    )
    @test_throws r"depth must be a positive integer" complete(source)
end

@testset "history retains source domain and physical sample values" begin
    @variables position[1:2] memory
    cell = CellKind(:cell; extinction = ForbidExtinction())
    medium = MediumKind(:medium)
    for constructor in (ModelState, SiteState, CellState)
        function declaration(prehistory)
            source = PottsSystem(
                name = :sampled_positions,
                statements = StatementSet(
                    (
                        Lattice((2, 2); boundary = Closed(), max_cells = 3), cell, medium,
                        constructor(position; initial = SVector(2.0u"m", 4.0u"m")),
                        HistoryState(memory; of = position, depth = 3, initial = prehistory, cadence = Every(2)),
                        ProposalConstraint(:fixed_ownership, false),
                        Protocol(Sweep(; temperature = 0.0); name = :main),
                    )
                ),
                unknowns = (position, memory),
            )
            return mtkcompile(complete(source; reference_units = ReferenceUnits(length = 2.0u"m")))
        end
        ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium)
        is_model = constructor === ModelState
        snapshot(value) = is_model ? value : fill(value, constructor === CellState ? (3,) : (2, 2))
        for prehistory in (nothing, 0, SVector(600.0u"cm", 800.0u"cm"))
            system = declaration(prehistory)
            initial_sample = prehistory isa StaticArray ? SVector(3.0f0, 4.0f0) : SVector(0.0f0, 0.0f0)
            problem = PottsProblem(system, PottsInitialState(; ownership), (0, 2); seed = 17)
            integrator = init(problem, SequentialCPM(); scalar_type = Float32)
            @test integrator.u[:memory] == ntuple(_ -> snapshot(initial_sample), 3)
            step!(integrator)
            @test integrator.u[:memory] == ntuple(_ -> snapshot(initial_sample), 3)
            step!(integrator)
            @test integrator.u[:memory] == (snapshot(initial_sample), snapshot(initial_sample), snapshot(SVector(1.0f0, 2.0f0)))
        end
        if constructor === CellState
            sample = [SVector(600.0u"cm", 800.0u"cm")]
            initial = PottsInitialState(; ownership, values = (memory => (sample, sample, sample),))
            integrator = init(PottsProblem(declaration(nothing), initial, (0, 1); seed = 17))
            @test all(values -> values == [SVector(3.0f0, 4.0f0), SVector(0.0f0, 0.0f0), SVector(0.0f0, 0.0f0)], integrator.u[:memory])
            @test length(integrator.u.cell_kinds) == 1
            @test integrator.u[:position] == fill(SVector(1.0f0, 2.0f0), 3)
        end
        @test_throws ArgumentError init(PottsProblem(declaration(SVector(1.0u"s", 2.0u"s")), PottsInitialState(; ownership), (0, 1); seed = 17))
    end
end

@testset "ordinary cell initial values cover declared storage without creating identities" begin
    @variables value
    cell = CellKind(:cell; extinction = ForbidExtinction())
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :reserved_cell_storage,
        statements = StatementSet(
            (
                Lattice((2, 2); max_cells = 3), cell, medium,
                CellState(value; initial = 2.0),
                ProposalConstraint(:fixed_ownership, false),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ), unknowns = (value,),
    )
    ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium)
    initial = PottsInitialState(; ownership, values = (value => [7.0],))
    integrator = init(PottsProblem(source, initial, (0, 1); seed = 17))
    @test integrator.u[:value] == Float32[7, 2, 2]
    @test length(integrator.u.cell_kinds) == 1
    invalid = PottsInitialState(; ownership, values = (value => ones(4),))
    @test_throws r"initial cell state.*value" init(PottsProblem(source, invalid, (0, 1); seed = 17))
end

@testset "a history sample source is distinct from its lifecycle policy inputs" begin
    @variables signal retirement_value memory
    cell = CellKind(:cell; extinction = ForbidExtinction())
    medium = MediumKind(:medium)
    source = PottsSystem(
        name = :history_policy_input, statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed(), max_cells = 1), cell, medium,
                CellState(signal; initial = 2.0), CellState(retirement_value; initial = 9.0),
                HistoryState(memory; of = signal, depth = 2, initial = 0.0, retirement = RetireTo(retirement_value)),
                ProposalConstraint(:fixed_ownership, false), Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ), unknowns = (signal, retirement_value, memory)
    )
    initial = PottsInitialState(ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium))
    integrator = init(PottsProblem(source, initial, (0, 1); seed = 17))
    step!(integrator)
    @test integrator.u[:memory] == ([0.0f0], [2.0f0])
end

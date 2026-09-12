using StaticArrays
using Symbolics
using SymbolicIndexingInterface
using ModelingToolkitBase
using DynamicQuantities

function _logical_state_mutation_contract(algorithms, backend)
    @testset "canonical logical state setters publish one validated transaction" begin
        @variables amount polarity[1:2] site_value cell_value[1:2] medium_value memory cell_memory site_memory
        @variables product::NamedTuple{(:amount, :enabled), Tuple{Float64, Bool}}
        @parameters increment = 1.0
        cell = CellKind(:cell; extinction = ForbidExtinction())
        medium = MediumKind(:medium)
        product_state = ModelState(product; initial = (amount = 2.0, enabled = true))
        source = PottsSystem(
            name = :mutable_logical_state,
            statements = StatementSet(
                (
                    Lattice((2, 2); boundary = Closed(), max_cells = 3), cell, medium,
                    ModelState(amount; initial = 1.0),
                    ModelState(polarity; initial = SVector(1.0, 0.0)), product_state,
                    SiteState(site_value; initial = 3.0),
                    CellState(cell_value; initial = SVector(1.0, 2.0), retirement = RetireTo(SVector(0.0, 0.0))),
                    MediumState(medium_value; initial = 4.0),
                    HistoryState(memory; of = amount, depth = 2, cadence = AtMCS(0)),
                    HistoryState(cell_memory; of = cell_value, depth = 2, cadence = AtMCS(0)),
                    HistoryState(site_memory; of = site_value, depth = 2, cadence = AtMCS(0)),
                    Synchronous(:advance, Assign(amount, amount + increment)),
                    Observation(:amount_snapshot, amount),
                    ProposalConstraint(:held_ownership, false),
                    Protocol(Sweep(; temperature = 0.0); name = :main),
                )
            ),
            unknowns = (amount, polarity, product, site_value, cell_value, medium_value, memory, cell_memory, site_memory),
            parameters = (increment,),
        )
        labels = Int32[1 1; 0 2]
        initial = PottsInitialState(ownership = LabelledCells(labels; cells = [cell, cell], medium))
        problem = PottsProblem(source, initial, (0, 2); seed = 27)
        names = (:amount, :polarity, :product, :site_value, :cell_value, :medium_value, :memory, :cell_memory, :site_memory)
        for algorithm in algorithms
            integrator = init(problem, algorithm; backend, scalar_type = Float32, observables = (:amount_snapshot,))
            original = integrator.u
            old_saved = first(integrator.saved_states)
            whole = setu(problem, (amount, polarity, product, site_value, cell_value, medium_value))
            sites = Float32[5 6; 7 8]
            cells = [SVector(3, 4), SVector(5, 6), SVector(7, 8)]
            whole(integrator, (10.0, SVector(0, 1), (amount = 9.0, enabled = false), sites, cells, 12.0))
            @test integrator.u[:amount] === 10.0f0
            @test integrator.u[:polarity] === SVector(0.0f0, 1.0f0)
            @test integrator.u[:product] === (amount = 9.0f0, enabled = false)
            @test integrator.u[:site_value] == sites
            @test integrator.u[:cell_value] == cells
            @test integrator.u[:medium_value] === 12.0f0
            setu(problem.system, amount)(integrator, 10.0)
            @test integrator.u[:amount] === 10.0f0
            @test only(integrator.u[:amount_snapshot]) === 10.0f0
            @test integrator.u.ownership == labels
            @test integrator.t == 0
            @test original[:amount] === old_saved[:amount] === 1.0f0
            sites .= -1
            @test integrator.u[:site_value] == Float32[5 6; 7 8]

            # Whole array/product targets are not batches of their logical leaves.
            setu(integrator, polarity)(integrator, SVector(2, 3))
            setu(integrator, product)(integrator, (amount = 7.0, enabled = true))
            @test getu(integrator, polarity)(integrator) == SVector(2.0f0, 3.0f0)
            @test integrator.u[:product] === (amount = 7.0f0, enabled = true)
            named = setu(integrator, (scalar = amount, vector = polarity))
            named(integrator, (scalar = 11.0,))
            @test integrator.u[:amount] === 11.0f0
            @test integrator.u[:polarity] == SVector(2.0f0, 3.0f0)
            before_empty = integrator.u
            named(integrator, NamedTuple())
            @test integrator.u === before_empty
            @test integrator.t == 0
            index = SymbolicIndexingInterface.variable_index(problem.system, amount)
            SymbolicIndexingInterface.set_state!(integrator, 13.0, index)
            @test integrator.u[:amount] === 13.0f0

            for invalid in (SVector(1, 2, 3), SVector(1.0, Inf))
                before = integrator.u
                @test_throws ArgumentError setu(integrator, (amount, polarity))(integrator, (99.0, invalid))
                @test integrator.u === before
                @test all(name -> integrator.u[name] == before[name], names)
                @test integrator.t == 0
            end
            @test_throws ArgumentError setu(integrator, cell_value)(integrator, cells[1:2])
            @test_throws ArgumentError whole(integrator, (99.0, SVector(0, 1), (enabled = true, amount = 2.0), zeros(2, 2), cells, 3))
            @test integrator.u[:amount] === 13.0f0
            for forbidden in (:ownership, :amount_snapshot, amount + 1, polarity[1], product_state.amount, (amount, amount), true)
                @test_throws ArgumentError setu(integrator, forbidden)
            end
            @test_throws ArgumentError SymbolicIndexingInterface.set_state!(problem, 1.0, index)
            @test_throws ArgumentError named(integrator, (unknown = 1.0,))
            setu(integrator, increment)(integrator, 2.0)
            @test getp(integrator, increment)(integrator) == 2.0f0
            setu(integrator, (rate = increment,))(integrator, (rate = 3.0,))
            @test getp(integrator, increment)(integrator) == 3.0f0
            setu(integrator, (increment,))(integrator, (2.0,))
            @test getp(integrator, increment)(integrator) == 2.0f0

            history_sites = (fill(21.0, 2, 2), fill(22.0, 2, 2))
            history_cells = (fill(SVector(11, 12), 3), fill(SVector(13, 14), 3))
            setu(integrator, (memory, cell_memory, site_memory))(
                integrator, ((31.0, 32.0), history_cells, history_sites)
            )
            @test integrator.u[:memory] === (31.0f0, 32.0f0)
            @test integrator.u[:cell_memory] == history_cells
            @test integrator.u[:site_memory] == history_sites
            before = integrator.u
            @test_throws ArgumentError setu(integrator, (amount, cell_memory))(
                integrator, (99.0, (cells, cells[1:2]))
            )
            @test integrator.u === before
            restored = init(problem, algorithm; backend, scalar_type = Float32, checkpoint = checkpoint(integrator), observables = (:amount_snapshot,))
            @test all(name -> restored.u[name] == integrator.u[name], names)
            step!(integrator)
            step!(restored)
            @test integrator.u[:amount] === restored.u[:amount] === 15.0f0
            @test all(name -> restored.u[name] == integrator.u[name], names)
            @test restored.u[:memory] === (31.0f0, 32.0f0)
            @test restored.u.ownership == labels
            @test old_saved[:amount] === 1.0f0

            mutate = SciMLBase.DiscreteCallback(
                (_, time, _) -> time == 1,
                callback_integrator -> begin
                    setu(callback_integrator, amount)(callback_integrator, 80.0)
                    setp(callback_integrator, increment)(callback_integrator, 9.0)
                end; save_positions = (true, true),
            )
            fail = SciMLBase.DiscreteCallback(
                (_, time, _) -> time == 1, _ -> error("late callback failure");
                save_positions = (false, false),
            )
            callback_integrator = init(problem, algorithm; backend, scalar_type = Float32, callback = SciMLBase.CallbackSet(mutate, fail))
            @test_throws r"late callback failure" step!(callback_integrator)
            @test callback_integrator.u[:amount] === 2.0f0
            @test getp(callback_integrator, increment)(callback_integrator) === 1.0f0
            @test length(callback_integrator.saved_states) == 1
            @test_throws r"terminal-failed" setu(callback_integrator, amount)(callback_integrator, 3.0)
        end
    end

    @testset "logical setters reuse declared dimensional conversion" begin
        @variables length_value time_value
        cell = CellKind(:cell; extinction = ForbidExtinction())
        medium = MediumKind(:medium)
        source = PottsSystem(
            name = :dimensional_mutation,
            statements = StatementSet(
                (
                    Lattice((2, 2); boundary = Closed()), cell, medium,
                    ModelState(length_value; initial = 1.0u"m"),
                    ModelState(time_value; initial = 1.0u"s"),
                    ProposalConstraint(:held_ownership, false),
                    Protocol(Sweep(; temperature = 0.0); name = :main),
                )
            ),
        )
        system = complete(source; reference_units = ReferenceUnits(length = 1.0u"m", time = 1.0u"s"))
        initial = PottsInitialState(ownership = LabelledCells(ones(Int, 2, 2); cells = [cell], medium))
        problem = PottsProblem(system, initial, (0, 1); seed = 28)
        for algorithm in algorithms
            integrator = init(problem, algorithm; backend, scalar_type = Float32)
            setter = setu(integrator, (length_value, time_value))
            setter(integrator, (200.0u"cm", 3.0u"s"))
            @test integrator.u[:length_value] === 2.0f0
            @test integrator.u[:time_value] === 3.0f0
            before = integrator.u
            @test_throws ArgumentError setter(integrator, (9.0u"m", 4.0u"m"))
            @test integrator.u === before
            @test_throws ArgumentError setu(integrator, length_value)(integrator, 5.0)
            @test integrator.u[:length_value] === 2.0f0
            restored = init(problem, algorithm; backend, scalar_type = Float32, checkpoint = checkpoint(integrator))
            @test restored.u[:length_value] === 2.0f0
            @test restored.u[:time_value] === 3.0f0
        end
    end
    return nothing
end

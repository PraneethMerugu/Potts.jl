@testset "compound effect authoring" begin
    @testset "synchronous compound assignments share boundary-entry values" begin
        @variables left right
        for state_constructor in (ModelState, SiteState)
            system = PottsSystem(
                name = :swap,
                statements = StatementSet(
                    (
                        Lattice((2, 2); boundary = Closed()),
                        CellKind(:cell; extinction = RetireAtZero()),
                        MediumKind(:medium),
                        state_constructor(left; initial = 2.0),
                        state_constructor(right; initial = 7.0),
                        Synchronous(:exchange, Assign(left, right), Assign(right, left)),
                        Protocol(Sweep(; temperature = 0.0); name = :main),
                    )
                ),
                unknowns = (left, right),
            )
            initial = PottsInitialState(
                ownership = LabelledCells(
                    ones(Int, 2, 2);
                    cells = [CellKind(:cell; extinction = RetireAtZero())],
                    medium = MediumKind(:medium)
                ),
            )
            for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
                solution = solve(PottsProblem(system, initial, (0, 1); seed = 17), algorithm)
                @test solution.u[end][:left] == (state_constructor === ModelState ? 7.0 : fill(7.0, 2, 2))
                @test solution.u[end][:right] == (state_constructor === ModelState ? 2.0 : fill(2.0, 2, 2))
            end
        end
    end

    @testset "accepted-copy compound assignments retain the entry snapshot" begin
        @variables first_value second_value
        copy_context = ProposalContext(:copy)
        system = PottsSystem(
            name = :copy_exchange,
            statements = StatementSet(
                (
                    Lattice((4, 4); boundary = Periodic()),
                    CellKind(:cell; extinction = RetireAtZero()),
                    MediumKind(:medium),
                    ProposalConstraint(:extensions_only, copy_context.is_extension),
                    SiteState(first_value; initial = 2.0),
                    SiteState(second_value; initial = 7.0),
                    AcceptedCopy(
                        :exchange,
                        Assign(first_value, second_value), Assign(second_value, first_value);
                        when = copy_context.is_extension & (first_value < 3.0)
                    ),
                    Protocol(Sweep(; temperature = 0.0); name = :main),
                )
            ),
            unknowns = (first_value, second_value),
        )
        labels = zeros(Int, 4, 4)
        labels[2:3, 2:3] .= 1
        initial = PottsInitialState(
            ownership = LabelledCells(
                labels;
                cells = [CellKind(:cell; extinction = RetireAtZero())],
                medium = MediumKind(:medium)
            ),
        )
        for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
            solution = solve(PottsProblem(system, initial, (0, 2); seed = 17), algorithm)
            @test solution.retcode == SciMLBase.ReturnCode.Success
            @test solution.stats.accepted > 0
            first_values = solution.u[end][:first_value]
            second_values = solution.u[end][:second_value]
            @test any(==(7.0), first_values)
            @test all(first_values .+ second_values .== 9.0)
            @test all(value -> value in (2.0, 7.0), first_values)
        end
    end

    @testset "compound synchronous writers are explicit" begin
        @variables amount other
        duplicate = PottsSystem(
            name = :duplicate,
            statements = StatementSet(
                (
                    ModelState(amount; initial = 1.0),
                    Synchronous(:update, Assign(amount, 2.0), Assign(amount, 3.0)),
                )
            ),
            unknowns = (amount,),
        )
        @test_throws r"one synchronous assignment per state" complete(duplicate)
        mixed = PottsSystem(
            name = :mixed,
            statements = StatementSet(
                (
                    ModelState(amount; initial = 1.0),
                    SiteState(other; initial = 2.0),
                    Synchronous(:update, Assign(amount, 2.0), Assign(other, 3.0)),
                )
            ),
            unknowns = (amount, other),
        )
        @test_throws r"synchronous effects must share one iteration domain" mtkcompile(mixed)
    end

    @testset "a failing synchronous effect publishes none of its assignments" begin
        @variables left right
        @parameters divisor = 0.0
        for state_constructor in (ModelState, SiteState)
            system = PottsSystem(
                name = :failed_exchange,
                statements = StatementSet(
                    (
                        Lattice((2, 2); boundary = Closed()),
                        CellKind(:cell; extinction = RetireAtZero()),
                        MediumKind(:medium),
                        state_constructor(left; initial = 2.0),
                        state_constructor(right; initial = 7.0),
                        Synchronous(:exchange, Assign(left, right), Assign(right, left / divisor)),
                        Protocol(Sweep(; temperature = 0.0); name = :main),
                    )
                ),
                unknowns = (left, right), parameters = (divisor,),
            )
            initial = PottsInitialState(
                ownership = LabelledCells(
                    ones(Int, 2, 2);
                    cells = [CellKind(:cell; extinction = RetireAtZero())],
                    medium = MediumKind(:medium)
                ),
            )
            for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
                integrator = init(PottsProblem(system, initial, (0, 1); seed = 17), algorithm)
                if algorithm isa SequentialCPM
                    @test_throws DomainError solve!(integrator)
                else
                    solution = solve!(integrator)
                    @test solution.retcode == SciMLBase.ReturnCode.Failure
                    @test failure_report(solution) !== nothing
                end
                # Read the live settled state, not the integrator's pre-step cache.
                current = Potts._current_saved_state(integrator)
                @test current[:left] == (state_constructor === ModelState ? 2.0 : fill(2.0, 2, 2))
                @test current[:right] == (state_constructor === ModelState ? 7.0 : fill(7.0, 2, 2))
            end
        end
    end

    @testset "accepted-copy assignment and relationship creation share a transaction" begin
        @variables marker
        @parameters payload_divisor = 1.0
        cell = CellKind(:cell; extinction = RetireAtZero())
        medium = MediumKind(:medium)
        links = RelationshipState(
            :links;
            endpoints = Undirected(cell, cell), payload = (score = 1.0,),
            capacity = 2, maximum_degree = 2, lifecycle = RemoveWithEndpoint()
        )
        copy_context = ProposalContext(:copy)
        system = PottsSystem(
            name = :marked_link,
            statements = StatementSet(
                (
                    Lattice((4, 4); boundary = Periodic()), cell, medium, links,
                    SiteState(marker; initial = 0.0),
                    ProposalConstraint(:preserve_cells, cell_volume(copy_context.target_cell) > 1),
                    AcceptedCopy(
                        :mark_and_link,
                        Assign(marker, 1.0),
                        Create(
                            links, copy_context.source_cell, copy_context.target_cell;
                            payload = (score = 1.0 / payload_divisor,)
                        );
                        when = !linked(links, copy_context.source_cell, copy_context.target_cell)
                    ),
                    Protocol(Sweep(; temperature = 0.0); name = :main),
                )
            ),
            unknowns = (marker,), parameters = (payload_divisor,),
        )
        labels = ones(Int, 4, 4)
        labels[3:4, :] .= 2
        initial = PottsInitialState(ownership = LabelledCells(labels; cells = [cell, cell], medium))
        for algorithm in (SequentialCPM(), CheckerboardSweepCPM()), divisor in (1.0, 0.0)
            integrator = init(
                PottsProblem(
                    system, initial, (0, 1);
                    seed = 17, p = (payload_divisor => divisor,)
                ), algorithm
            )
            if iszero(divisor)
                if algorithm isa SequentialCPM
                    @test_throws DomainError solve!(integrator)
                else
                    solution = solve!(integrator)
                    @test solution.retcode == SciMLBase.ReturnCode.Failure
                    @test failure_report(solution) !== nothing
                end
                current = Potts._current_saved_state(integrator)
                @test all(iszero, current[:marker])
                @test count(current[:links].active) == 0
                @test current.ownership == labels
            else
                solution = solve!(integrator)
                @test solution.retcode == SciMLBase.ReturnCode.Success
                @test any(==(1.0), solution.u[end][:marker])
                @test count(solution.u[end][:links].active) == 1
            end
        end
    end
end

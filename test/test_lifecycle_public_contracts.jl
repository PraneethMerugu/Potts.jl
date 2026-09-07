@testset "external lifecycle ABI is frozen and executable through CompilerSPI" begin
    @variables external_lifecycle_state
    cell = CellKind(:external_lifecycle_cell; extinction = RetireAtZero())
    daughter = CellKind(:external_lifecycle_daughter; extinction = RetireAtZero())
    medium = MediumKind(:external_lifecycle_medium)
    relation = SpatialRelation(
        :external_lifecycle_division; neighborhood = VonNeumann()
    )
    state = CellState(
        external_lifecycle_state;
        initial = 1.0,
        retirement = RetireTo(0.0),
        division = CopyToDaughters(),
    )
    anchor = CellBinding(:external_lifecycle_anchor)
    create = LifecycleProcess(
        :external_lifecycle_create;
        domain = model(),
        expression = LifecycleOperationFixtures.external_lifecycle_trigger(
            Symbolics.Num(1)
        ),
        effects = (CreateCell(
            cell;
            placement = LifecycleOperationFixtures.external_lifecycle_placement(
                Symbolics.Num(1)
            ),
            state = (state => InitializeFrom(2.0),),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(1),
    )
    transition = LifecycleProcess(
        :external_lifecycle_transition;
        domain = cells(cell),
        anchor,
        expression = LifecycleOperationFixtures.external_lifecycle_trigger(
            anchor_value(anchor)
        ),
        effects = (Transition(
            anchor,
            daughter;
            state = (state => Transform(
                LifecycleOperationFixtures.external_lifecycle_transform(
                    external_lifecycle_state
                )
            ),),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(2),
    )
    divide = LifecycleProcess(
        :external_lifecycle_divide;
        domain = cells(cell),
        anchor,
        expression = false,
        effects = (Divide(
            anchor;
            geometry =
                LifecycleOperationFixtures.external_lifecycle_partition(
                    anchor_value(anchor)
                ),
            relation,
            side = CanonicalSide(),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(3),
    )
    source = PottsSystem(
        name = :external_lifecycle_spi,
        statements = StatementSet((
            Lattice((3, 3); max_cells = 3),
            cell,
            daughter,
            medium,
            relation,
            state,
            ProposalConstraint(:freeze_external_lifecycle, false),
            create,
            transition,
            divide,
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        unknowns = [external_lifecycle_state],
    )
    completed = complete(source)
    plans = inspect(completed, LifecyclePlans())
    abis = Tuple(Iterators.flatten(plan.operation_abis for plan in plans))
    external = filter(
        item -> startswith(String(item.operation), "external_lifecycle_"),
        abis,
    )
    @test Set(item.abi.role for item in external) == Set((
        :trigger, :placement, :binary_partition, :state_transform,
    ))
    @test all(item.owner === :LifecycleOperationFixtures for item in external)

    scheduled = mtkcompile(completed)
    empty_initial = PottsInitialState(
        ownership = LabelledCells(
            zeros(Int, 3, 3); cells = [], medium
        )
    )
    solution = solve(
        PottsProblem(scheduled, empty_initial, (0, 1); seed = 0x51f4),
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float32,
        save_everystep = true,
    )
    @test solution.retcode == SciMLBase.ReturnCode.Success
    @test count(!iszero, last(solution).cell_kinds) == 1
    @test sort(filter(!iszero, last(solution).volumes)) == Int32[2]
    @test last(solution)[:external_lifecycle_state][1] == 2
end

@testset "public lifecycle capacity failure is atomic" begin
    births = cell -> ntuple(2) do index
        LifecycleProcess(
            Symbol(:capacity_birth_, index);
            domain = model(),
            expression = true,
            effects = (CreateCell(
                cell;
                placement = SeedAt(index),
                on_inadmissible = ErrorOnInadmissible(),
            ),),
            cadence = AtMCS(1),
        )
    end
    fixture = lifecycle_birth_system(
        :public_capacity_failure, births; max_cells = 1
    )
    integrator = init(
        PottsProblem(
            mtkcompile(fixture.source), fixture.initial, (0, 1);
            seed = 0x51f5,
        ),
        SequentialCPM();
        scalar_type = Float32,
        save_start = false,
    )
    before = deepcopy(integrator.u)
    @test step!(integrator) === integrator
    @test integrator.retcode == SciMLBase.ReturnCode.Failure
    @test integrator.failure_report isa CorePotts.ProgramFailureReport
    @test integrator.failure_report.required == 2
    @test integrator.failure_report.available == 1
    @test integrator.failure_report.maximum == 1
    @test integrator.u.ownership == before.ownership
    @test integrator.u.cell_kinds == before.cell_kinds
    @test integrator.u.cell_generations == before.cell_generations
end

@testset "lifecycle construction diagnostics stay source-located" begin
    function split_error(fraction)
        @variables diagnostic_state
        cell = CellKind(:diagnostic_cell; extinction = RetireAtZero())
        medium = MediumKind(:diagnostic_medium)
        relation = SpatialRelation(
            :diagnostic_division; neighborhood = VonNeumann()
        )
        state = CellState(
            diagnostic_state;
            initial = 1.0,
            retirement = RetireTo(0.0),
            division = CopyToDaughters(),
        )
        anchor = CellBinding(:diagnostic_anchor)
        divide = only(@statements begin
            LifecycleProcess(
                :invalid_split;
                domain = cells(cell),
                anchor,
                expression = true,
                effects = (Divide(
                    anchor;
                    geometry = SpecifiedNormalPlane((1.0, 0.0)),
                    relation,
                    side = CanonicalSide(),
                    state = (
                        state => SplitConservatively(
                            fraction; rounding = :exact
                        ),
                    ),
                    on_inadmissible = ErrorOnInadmissible(),
                ),),
                cadence = AtMCS(1),
            )
        end)
        source = PottsSystem(
            name = :invalid_lifecycle_split,
            statements = StatementSet((
                Lattice((4, 4); max_cells = 2),
                cell,
                medium,
                relation,
                state,
                divide,
                Protocol(Sweep(); name = :main),
            )),
            unknowns = [diagnostic_state],
        )
        return try
            complete(source)
            nothing
        catch caught
            caught
        end
    end
    for fraction in (1.5, 0.5u"μm")
        error = split_error(fraction)
        @test error isa Potts.PottsValidationError
        @test only(error.diagnostics).kind ===
              :invalid_lifecycle_split_fraction
        @test only(error.diagnostics).source isa SourceLocation
    end
end

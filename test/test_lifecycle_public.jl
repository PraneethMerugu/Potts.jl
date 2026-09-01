isdefined(@__MODULE__, :LifecycleOperationFixtures) ||
    include("fixtures/LifecycleOperationFixtures.jl")

function lifecycle_public_fixture()
    @variables lifecycle_activity
    cell = CellKind(:lifecycle_cell; extinction = RetireAtZero(priority = -20))
    daughter = CellKind(
        :lifecycle_daughter; extinction = RetireAtZero(priority = -20)
    )
    medium = MediumKind(:lifecycle_medium)
    relation = SpatialRelation(
        :lifecycle_division; neighborhood = VonNeumann()
    )
    activity = CellState(
        lifecycle_activity;
        initial = 1.0,
        retirement = RetireTo(0.0),
        division = CopyToDaughters(),
    )
    anchor = CellBinding(:lifecycle_event_cell)
    create_site = LinearIndices((6, 6))[CartesianIndex(5, 2)]
    reuse_site = LinearIndices((6, 6))[CartesianIndex(2, 2)]
    create = LifecycleProcess(
        :lifecycle_create;
        domain = model(),
        expression = true,
        effects = (CreateCell(
            cell;
            placement = SeedStencil(
                create_site, ((0, 0), (1, 0)); relation
            ),
            state = (activity => InitializeFrom(2.0),),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(1),
    )
    transition = LifecycleProcess(
        :lifecycle_transition;
        domain = cells(cell),
        anchor,
        expression = true,
        effects = (Transition(
            anchor,
            daughter;
            state = (activity => Transform(lifecycle_activity + 1),),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(2),
    )
    divide = LifecycleProcess(
        :lifecycle_divide;
        domain = cells(daughter),
        anchor,
        expression = true,
        effects = (Divide(
            anchor;
            geometry = SpecifiedNormalPlane((1.0, 0.0)),
            relation,
            side = CanonicalSide(),
            state = (
                activity => SplitConservatively(0.5; rounding = :exact),
            ),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(3),
    )
    remove = LifecycleProcess(
        :lifecycle_remove;
        domain = cells(daughter),
        anchor,
        expression = true,
        effects = (RemoveCell(
            anchor;
            replacement = medium,
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(4),
    )
    reuse = LifecycleProcess(
        :lifecycle_reuse;
        domain = model(),
        expression = true,
        effects = (CreateCell(
            daughter;
            placement = SeedAt(reuse_site),
            state = (activity => InitializeFrom(5.0),),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(5),
    )
    source = PottsSystem(
        name = :lifecycle_public_model,
        statements = StatementSet((
            Lattice((6, 6); max_cells = 6),
            cell,
            daughter,
            medium,
            relation,
            activity,
            ProposalConstraint(:freeze_lifecycle_trajectory, false),
            create,
            transition,
            divide,
            remove,
            reuse,
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        unknowns = [lifecycle_activity],
    )
    labels = zeros(Int, 6, 6)
    labels[2:5, 4] .= 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium)
    )
    return (; source, initial, activity = lifecycle_activity)
end

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

function lifecycle_birth_system(
        name,
        births;
        max_cells,
        conflicts = RejectLifecycleAmbiguity(),
        state = nothing,
        unknowns = [],
    )
    cell = CellKind(:birth_cell; extinction = RetireAtZero())
    medium = MediumKind(:birth_medium)
    declarations = state === nothing ? () : (state,)
    source = PottsSystem(
        name = name,
        statements = StatementSet((
            Lattice((3, 3); max_cells),
            cell,
            medium,
            declarations...,
            births(cell)...,
            Protocol(
                Sweep(); name = :main, lifecycle_conflicts = conflicts
            ),
        )),
        unknowns = unknowns,
    )
    initial = PottsInitialState(
        ownership = LabelledCells(
            zeros(Int, 3, 3); cells = [], medium
        )
    )
    return (; source, initial)
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

function permutation_lifecycle_fixture(reverse_order; conflicting = false)
    births = cell -> begin
        sites = conflicting ? (1, 1) : (1, 2)
        declarations = ntuple(2) do index
            LifecycleProcess(
                Symbol(:permutation_birth_, index);
                domain = model(),
                expression = true,
                effects = (CreateCell(
                    cell;
                    placement = SeedAt(sites[index]),
                    on_inadmissible = ErrorOnInadmissible(),
                ),),
                cadence = AtMCS(1),
            )
        end
        return reverse_order ? reverse(declarations) : declarations
    end
    return lifecycle_birth_system(
        conflicting ? :public_conflict_permutation :
        :public_success_permutation,
        births;
        max_cells = 2,
    )
end

@testset "lifecycle permutation and conflict diagnostics are canonical" begin
    successful = map((false, true)) do reversed
        fixture = permutation_lifecycle_fixture(reversed)
        scheduled = mtkcompile(fixture.source)
        integrator = init(
            PottsProblem(
                scheduled, fixture.initial, (0, 1);
                seed = 0x51f6,
            ),
            SequentialCPM();
            scalar_type = Float32,
            save_everystep = true,
        )
        lifecycle_fingerprint = getfield(
            getfield(integrator, :plan), :reports
        ).lifecycle.fingerprint
        solution = solve!(integrator)
        (; lifecycle_fingerprint, solution)
    end
    @test successful[1].lifecycle_fingerprint ==
          successful[2].lifecycle_fingerprint
    @test last(successful[1].solution).ownership ==
          last(successful[2].solution).ownership
    @test last(successful[1].solution).cell_generations ==
          last(successful[2].solution).cell_generations

    conflicts = map((false, true)) do reversed
        fixture = permutation_lifecycle_fixture(reversed; conflicting = true)
        scheduled = mtkcompile(fixture.source)
        integrator = init(
            PottsProblem(
                scheduled, fixture.initial, (0, 1);
                seed = 0x51f7,
            ),
            SequentialCPM();
            scalar_type = Float32,
            save_start = false,
        )
        before = deepcopy(integrator.u)
        lifecycle_fingerprint = getfield(
            getfield(integrator, :plan), :reports
        ).lifecycle.fingerprint
        step!(integrator)
        (; lifecycle_fingerprint, integrator, before)
    end
    @test conflicts[1].lifecycle_fingerprint ==
          conflicts[2].lifecycle_fingerprint
    @test all(
        candidate -> candidate.integrator.retcode ==
                     SciMLBase.ReturnCode.Failure,
        conflicts,
    )
    first_report = conflicts[1].integrator.failure_report
    second_report = conflicts[2].integrator.failure_report
    @test first_report isa CorePotts.ProgramFailureReport
    @test second_report isa CorePotts.ProgramFailureReport
    @test (first_report.source, first_report.secondary_source,
           first_report.anchor, first_report.detail) ==
          (second_report.source, second_report.secondary_source,
           second_report.anchor, second_report.detail)
    for candidate in conflicts
        @test candidate.integrator.u.ownership == candidate.before.ownership
        @test candidate.integrator.u.cell_kinds == candidate.before.cell_kinds
        @test candidate.integrator.u.cell_generations ==
              candidate.before.cell_generations
    end
end

@testset "stable lifecycle priority selects the declared winner" begin
    @variables priority_state
    state = CellState(
        priority_state;
        initial = 0.0,
        retirement = RetireTo(0.0),
        division = CopyToDaughters(),
    )
    births = cell -> (
        LifecycleProcess(
            :priority_low;
            domain = model(),
            expression = true,
            effects = (CreateCell(
                cell;
                placement = SeedAt(1),
                state = (state => InitializeFrom(1.0),),
                priority = 1,
                on_inadmissible = ErrorOnInadmissible(),
            ),),
            cadence = AtMCS(1),
        ),
        LifecycleProcess(
            :priority_high;
            domain = model(),
            expression = true,
            effects = (CreateCell(
                cell;
                placement = SeedAt(1),
                state = (state => InitializeFrom(10.0),),
                priority = 10,
                on_inadmissible = ErrorOnInadmissible(),
            ),),
            cadence = AtMCS(1),
        ),
    )
    fixture = lifecycle_birth_system(
        :public_priority_selection,
        births;
        max_cells = 2,
        conflicts = StableLifecyclePriority(),
        state,
        unknowns = [priority_state],
    )
    solution = solve(
        PottsProblem(
            mtkcompile(fixture.source), fixture.initial, (0, 1);
            seed = 0x51f8,
        ),
        SequentialCPM();
        scalar_type = Float32,
        save_everystep = true,
    )
    @test solution.retcode == SciMLBase.ReturnCode.Success
    @test count(!iszero, last(solution).cell_kinds) == 1
    @test last(solution)[:priority_state][1] == 10
end

@testset "scheduled public lifecycle trajectory and restart" begin
    fixture = lifecycle_public_fixture()
    scheduled = mtkcompile(fixture.source)
    plans = inspect(scheduled, LifecyclePlans())
    @test Set(plan.effect for plan in plans) ==
          Set((:CreateCell, :Transition, :Divide, :RemoveCell, :Retire))
    @test count(plan -> plan.effect === :Retire, plans) == 2
    problem = PottsProblem(scheduled, fixture.initial, (0, 5); seed = 0x51f3)
    solution = solve(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float32,
        save_everystep = true,
    )
    @test solution.retcode == SciMLBase.ReturnCode.Success
    @test solution.t == collect(0:5)
    @test count(!iszero, solution(1).cell_kinds) == 2
    @test solution(1).cell_generations[1:2] == UInt32[1, 1]
    @test solution(1)[:lifecycle_activity][1:2] == Float32[1, 2]
    @test count(!iszero, solution(2).cell_kinds) == 2
    @test solution(2)[:lifecycle_activity][1:2] == Float32[2, 3]
    @test count(!iszero, solution(3).cell_kinds) == 4
    @test sum(solution(3).volumes) == 6
    @test sum(solution(3)[:lifecycle_activity][1:4]) == 5
    @test all(iszero, solution(4).cell_kinds)
    @test all(solution(4).ownership .<= 0)
    @test solution(5).cell_kinds[1] != 0
    @test solution(5).cell_generations[1] == 2
    @test solution(5)[:lifecycle_activity][1] == 5

    integrator = init(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float32,
        save_start = false,
    )
    step!(integrator)
    step!(integrator)
    captured = checkpoint(integrator)
    resumed = solve!(init(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float32,
        checkpoint = captured,
        save_start = false,
    ))
    @test last(resumed).ownership == solution(5).ownership
    @test last(resumed).cell_kinds == solution(5).cell_kinds
    @test last(resumed).cell_generations == solution(5).cell_generations
    @test last(resumed)[:lifecycle_activity] ==
          solution(5)[:lifecycle_activity]
end

@testset "lifecycle relationship consequence is public and generation safe" begin
    cell = CellKind(:linked_cell; extinction = RetireAtZero())
    medium = MediumKind(:linked_medium)
    links = RelationshipState(
        :linked_edges;
        endpoints = Undirected(cell, cell),
        capacity = 2,
        maximum_degree = 1,
        lifecycle = RemoveWithEndpoint(),
    )
    anchor = CellBinding(:linked_remove_anchor)
    remove = LifecycleProcess(
        :remove_linked_endpoint;
        domain = cells(cell),
        anchor,
        expression = anchor_value(anchor) == 1,
        effects = (RemoveCell(
            anchor;
            replacement = medium,
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(1),
    )
    scheduled = mtkcompile(PottsSystem(
        name = :lifecycle_relationship_model,
        statements = StatementSet((
            Lattice((5, 5); max_cells = 2),
            cell,
            medium,
            links,
            ProposalConstraint(:freeze_linked_lifecycle, false),
            remove,
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
    ))
    labels = zeros(Int, 5, 5)
    labels[2, 2] = 1
    labels[4, 4] = 2
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels; cells = [cell, cell], medium
        ),
        values = (links => [(1, 2)],),
    )
    solution = solve(
        PottsProblem(scheduled, initial, (0, 1); seed = 12),
        SequentialCPM();
        scalar_type = Float64,
        save_everystep = true,
    )
    @test count(solution(0)[:linked_edges].active) == 1
    @test count(solution(1)[:linked_edges].active) == 0
    @test solution(1).cell_kinds[1] == 0
    @test solution(1).cell_generations[1] == 1
end

@testset "public lifecycle state-policy families execute transactionally" begin
    @variables begin
        policy_copy
        policy_preserve_reset
        policy_reset_both
        policy_split
        policy_transform
        policy_redraw
    end
    cell = CellKind(:policy_cell; extinction = RetireAtZero())
    daughter = CellKind(:policy_daughter; extinction = RetireAtZero())
    medium = MediumKind(:policy_medium)
    relation = SpatialRelation(
        :policy_division; neighborhood = VonNeumann()
    )
    variables = (
        policy_copy,
        policy_preserve_reset,
        policy_reset_both,
        policy_split,
        policy_transform,
        policy_redraw,
    )
    states = map(enumerate(variables)) do (index, variable)
        CellState(
            variable;
            name = Symbol(:policy_state_, index),
            initial = 10.0 * index,
            retirement = RetireTo(0.0),
            division = CopyToDaughters(),
        )
    end
    state_names = ntuple(index -> Symbol(:policy_state_, index), length(states))
    anchor = CellBinding(:policy_anchor)
    create_site = LinearIndices((5, 5))[CartesianIndex(2, 3)]
    create = LifecycleProcess(
        :policy_create;
        domain = model(),
        expression = true,
        effects = (CreateCell(
            cell;
            placement = SeedStencil(
                create_site, ((0, 0), (1, 0), (2, 0), (3, 0)); relation
            ),
            state = Tuple(
                state => InitializeFrom(10.0 * index)
                for (index, state) in enumerate(states)
            ),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(1),
    )
    transition = LifecycleProcess(
        :policy_transition;
        domain = cells(cell),
        anchor,
        expression = true,
        effects = (Transition(
            anchor,
            daughter;
            state = (
                states[1] => Preserve(),
                states[2] => ResetTo(22.0),
                states[3] => Transform(policy_reset_both + 3.0),
                states[4] => Preserve(),
                states[5] => Preserve(),
                states[6] => Preserve(),
            ),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(2),
    )
    divide = LifecycleProcess(
        :policy_divide;
        domain = cells(daughter),
        anchor,
        expression = true,
        effects = (Divide(
            anchor;
            geometry = SpecifiedNormalPlane((1.0, 0.0)),
            relation,
            side = CanonicalSide(),
            parent_kind = PreserveKind(),
            daughter_kind = SetKind(daughter),
            state = (
                states[1] => CopyToDaughters(),
                states[2] => PreserveParentResetDaughter(2.0),
                states[3] => ResetBoth(3.0, 4.0),
                states[4] => SplitConservatively(0.25; rounding = :exact),
                states[5] => TransformDaughters(5.0, 15.0),
                states[6] => RedrawDaughters(
                    Uniform(6.0, 7.0),
                    Uniform(8.0, 9.0);
                    parent_draw = :redraw_parent,
                    daughter_draw = :redraw_daughter,
                ),
            ),
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(3),
    )
    remove = LifecycleProcess(
        :policy_remove;
        domain = cells(daughter),
        anchor,
        expression = true,
        effects = (RemoveCell(
            anchor;
            replacement = medium,
            on_inadmissible = ErrorOnInadmissible(),
        ),),
        cadence = AtMCS(4),
    )
    source = PottsSystem(
        name = :public_lifecycle_state_policy_matrix,
        statements = StatementSet((
            Lattice((5, 5); max_cells = 3),
            cell,
            daughter,
            medium,
            relation,
            states...,
            ProposalConstraint(:freeze_policy_matrix, false),
            create,
            transition,
            divide,
            remove,
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        unknowns = collect(variables),
    )
    problem = PottsProblem(
        mtkcompile(source),
        PottsInitialState(ownership = LabelledCells(
            zeros(Int, 5, 5); cells = [], medium
        )),
        (0, 4);
        seed = 0x51f9,
    )
    solution = solve(
        problem,
        SequentialCPM();
        scalar_type = Float64,
        save_everystep = true,
    )
    replay = solve(
        problem,
        SequentialCPM();
        scalar_type = Float64,
        save_everystep = true,
    )
    @test solution.retcode == SciMLBase.ReturnCode.Success
    @test solution(1)[state_names[1]][1] == 10
    @test solution(2)[state_names[1]][1] == 10
    @test solution(2)[state_names[2]][1] == 22
    @test solution(2)[state_names[3]][1] == 33
    @test solution(3)[state_names[1]][1:2] == [10, 10]
    @test solution(3)[state_names[2]][1:2] == [22, 2]
    @test solution(3)[state_names[3]][1:2] == [3, 4]
    @test sum(solution(3)[state_names[4]][1:2]) == 40
    @test solution(3)[state_names[5]][1:2] == [5, 15]
    @test 6 < solution(3)[state_names[6]][1] < 7
    @test 8 < solution(3)[state_names[6]][2] < 9
    @test solution(3)[state_names[6]] == replay(3)[state_names[6]]
    @test all(iszero, solution(4).cell_kinds)
    @test all(name -> all(iszero, solution(4)[name][1:2]), state_names)
end

@testset "public binary partition policy matrix is preserved" begin
    cell = CellKind(:partition_cell; extinction = RetireAtZero())
    medium = MediumKind(:partition_medium)
    relation = SpatialRelation(
        :partition_relation; neighborhood = VonNeumann()
    )
    anchor = CellBinding(:partition_anchor)
    geometries = (
        RandomPlane(point = CellCentroid(), draw = :partition_random),
        PrincipalAxisPlane(:major; point = CellCentroid()),
        PrincipalAxisPlane(:minor; point = CellCentroid()),
        SpecifiedNormalPlane((1.0, 0.0); point = CellCentroid()),
    )
    variants = Tuple(
        (geometry, side)
        for geometry in geometries
        for side in (CanonicalSide(), StableRandomSide(:partition_side))
    )
    divisions = map(enumerate(variants)) do (cell_id, variant)
        geometry, side = variant
        LifecycleProcess(
            Symbol(:partition_policy_, cell_id);
            domain = cells(cell),
            anchor,
            expression = anchor_value(anchor) == cell_id,
            effects = (Divide(
                anchor;
                geometry,
                relation,
                side,
                on_inadmissible = ErrorOnInadmissible(),
            ),),
            cadence = AtMCS(1),
        )
    end
    source = PottsSystem(
        name = :public_partition_policy_matrix,
        statements = StatementSet((
            Lattice((12, 12); max_cells = 16),
            cell,
            medium,
            relation,
            ProposalConstraint(:freeze_partition_matrix, false),
            divisions...,
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
    )
    labels = zeros(Int, 12, 12)
    origins = (
        (1, 1), (1, 5), (1, 9), (5, 1),
        (5, 5), (5, 9), (9, 1), (9, 5),
    )
    for (cell_id, (row, column)) in enumerate(origins)
        labels[row:(row + 1), column:(column + 1)] .= cell_id
    end
    problem = PottsProblem(
        mtkcompile(source),
        PottsInitialState(ownership = LabelledCells(
            labels; cells = fill(cell, length(origins)), medium
        )),
        (0, 1);
        seed = 0x51fa,
    )
    first = solve(
        problem,
        SequentialCPM();
        scalar_type = Float32,
        save_everystep = true,
    )
    replay = solve(
        problem,
        SequentialCPM();
        scalar_type = Float32,
        save_everystep = true,
    )
    @test first.retcode == SciMLBase.ReturnCode.Success
    @test count(!iszero, last(first).cell_kinds) == 16
    @test sum(last(first).volumes) == count(!iszero, labels)
    @test last(first).ownership == last(replay).ownership
end

@testset "public lifecycle relationship-policy matrix is preserved" begin
    cell = CellKind(:policy_link_cell; extinction = RetireAtZero())
    transitioned = CellKind(
        :policy_link_destination; extinction = RetireAtZero()
    )
    medium = MediumKind(:policy_link_medium)
    links = RelationshipState(
        :policy_links;
        endpoints = Undirected(cell, cell),
        capacity = 5,
        maximum_degree = 1,
        lifecycle = RejectEndpointRetirement(),
    )
    anchor = CellBinding(:policy_link_anchor)
    policies = (
        (1, RemoveCell(
            anchor;
            replacement = medium,
            relationships = (links => RejectWhileLinked(),),
            on_inadmissible = FilterInadmissible(),
        )),
        (3, RemoveCell(
            anchor;
            replacement = medium,
            relationships = (links => RemoveIncident(),),
            on_inadmissible = ErrorOnInadmissible(),
        )),
        (5, Transition(
            anchor,
            transitioned;
            relationships = (links => PreserveCompatible(),),
            # Exact endpoint kinds make this incident edge incompatible with
            # the destination.  PreserveCompatible therefore filters the
            # transition and leaves both the cell and edge untouched.
            on_inadmissible = FilterInadmissible(),
        )),
        (7, Transition(
            anchor,
            transitioned;
            relationships = (links => RemoveIncompatible(),),
            on_inadmissible = ErrorOnInadmissible(),
        )),
        (9, Transition(
            anchor,
            transitioned;
            relationships = (links => RejectIncompatible(),),
            on_inadmissible = FilterInadmissible(),
        )),
    )
    processes = map(policies) do (cell_id, effect)
        LifecycleProcess(
            Symbol(:relationship_policy_, cell_id);
            domain = cells(cell),
            anchor,
            expression = anchor_value(anchor) == cell_id,
            effects = (effect,),
            cadence = AtMCS(1),
        )
    end
    source = PottsSystem(
        name = :public_relationship_policy_matrix,
        statements = StatementSet((
            Lattice((4, 4); max_cells = 10),
            cell,
            transitioned,
            medium,
            links,
            ProposalConstraint(:freeze_relationship_matrix, false),
            processes...,
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
    )
    labels = zeros(Int, 4, 4)
    labels[1:10] .= 1:10
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels; cells = fill(cell, 10), medium
        ),
        values = (links => [(1, 2), (3, 4), (5, 6), (7, 8), (9, 10)],),
    )
    solution = solve(
        PottsProblem(mtkcompile(source), initial, (0, 1); seed = 0x51fb),
        SequentialCPM();
        scalar_type = Float32,
        save_everystep = true,
    )
    @test solution.retcode == SciMLBase.ReturnCode.Success
    before = solution(0)
    after = solution(1)
    topology = after[:policy_links]
    active_endpoints = Set(
        (topology.endpoint_a[index], topology.endpoint_b[index])
        for index in eachindex(topology.active) if topology.active[index]
    )
    @test active_endpoints == Set(((Int32(1), Int32(2)),
                                  (Int32(5), Int32(6)),
                                  (Int32(9), Int32(10))))
    @test after.cell_kinds[1] == before.cell_kinds[1]
    @test after.cell_kinds[3] == 0
    @test after.cell_kinds[5] == before.cell_kinds[5]
    @test after.cell_kinds[7] != before.cell_kinds[7]
    @test after.cell_kinds[7] != 0
    @test after.cell_kinds[9] == before.cell_kinds[9]
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
        @test error isa PottsToolkit.PottsValidationError
        @test only(error.diagnostics).kind ===
              :invalid_lifecycle_split_fraction
        @test only(error.diagnostics).source isa SourceLocation
    end
end

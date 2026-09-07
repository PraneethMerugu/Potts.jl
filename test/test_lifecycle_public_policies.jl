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

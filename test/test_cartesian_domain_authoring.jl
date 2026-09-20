const CartesianSPI = CorePotts.CompilerSPI

@testset "obstacle completion traverses its owner, not its mask" begin
    medium = MediumKind(:obstacle_traversal_medium)
    obstacle = Obstacle(trues(64, 64); owner = WallDomainOwner(:wall, medium))

    mapped = Potts._map_symbolic_payload(identity, obstacle)
    @test mapped.mask === obstacle.mask
    @test mapped.owner.kind === obstacle.owner.kind

    namespaced = Potts._namespace_reference_payload(obstacle, (:component,))
    @test namespaced.mask === obstacle.mask
    @test Symbol(statement_id(namespaced.owner.kind)) ==
        :obstacle_traversal_medium

    resources = Any[]
    Potts._record_resources!(
        resources,
        obstacle,
        (:component,),
        owner -> Potts.QualifiedStatementID(
            (:component,), statement_id(owner.kind)
        ),
    )
    @test string(only(resources)) ==
        "component₊obstacle_traversal_medium"
end

function _cartesian_authoring_fixture(
        obstacle_site;
        obstacle_owner = :wall,
        attempts = AttemptsPerSite(1),
        boundary_builder = (bulk, wall) -> (
            AxisBoundary(
                negative = FixedExterior(bulk),
                positive = FixedExterior(wall),
            ),
            AxisBoundary(Closed()),
        ),
    )
    cell = CellKind(:cartesian_cell; extinction = RetireAtZero())
    medium = MediumKind(:cartesian_medium)
    wall_kind = MediumKind(:cartesian_wall_kind)
    bulk = MediumDomainOwner(:cartesian_bulk, medium)
    wall = WallDomainOwner(:cartesian_wall, wall_kind)
    mask = falses(4, 4)
    mask[obstacle_site] = true
    obstacle_domain_owner = obstacle_owner === :default ? bulk : wall
    lattice = Lattice(
        (4, 4);
        boundary = boundary_builder(bulk, wall),
        default_owner = bulk,
        domain_owners = (wall,),
        obstacles = Obstacle(mask; owner = obstacle_domain_owner),
        max_cells = 2,
    )
    source = PottsSystem(
        name = :cartesian_authoring_fixture,
        statements = StatementSet(
            (
                lattice,
                cell,
                medium,
                wall_kind,
                ProposalConstraint(:cartesian_frozen, false),
                Protocol(Sweep(; attempts, temperature = 0.0); name = :main),
            )
        ),
    )
    return (; source, cell, medium, wall_kind, bulk, wall, mask)
end

@testset "Cartesian attempt budgets use the mutable-site population" begin
    for budget in (1, 2, 16), algorithm in
            (SequentialCPM(), CheckerboardSweepCPM())
        fixture = _cartesian_authoring_fixture(
            CartesianIndex(2, 2); attempts = AttemptsPerSite(budget)
        )
        labels = zeros(Int32, 4, 4)
        labels[1, 1] = 1
        initial = PottsInitialState(
            ownership = LabelledCells(
                labels; cells = [fixture.cell], medium = fixture.medium
            )
        )
        solution = solve(
            PottsProblem(mtkcompile(fixture.source), initial, (0, 1); seed = 0x51),
            algorithm; backend = CPUBackend(), scalar_type = Float32,
        )
        @test solution.stats.candidate_attempts == 15 * budget
        @test solution.stats.candidate_attempts ==
            solution.stats.accepted + solution.stats.null_attempts +
            solution.stats.rejected
    end
end

function _lower_cartesian_fixture(fixture; algorithm = SequentialCPM())
    scheduled = mtkcompile(fixture.source)
    plan = Potts._lower_scheduled_execution_plan(
        scheduled, algorithm, CPUBackend(), Float32
    )
    domain = CartesianSPI.cartesian_domain(plan.core_program)
    return (; scheduled, plan, domain, report = CartesianSPI.cartesian_domain_report(domain))
end

function _cartesian_owner_count_fixture(owner_count::Int; nested = false)
    cell = CellKind(:owner_count_cell; extinction = RetireAtZero())
    kinds = ntuple(index -> MediumKind(Symbol(:owner_count_kind_, index)), 3)
    owners = ntuple(
        index -> WallDomainOwner(Symbol(:owner_count_, index), kinds[index]), 3
    )
    component = PottsSystem(
        name = :owner_count_fixture,
        statements = StatementSet(
            (
                Lattice(
                    (4, 4);
                    boundary = Closed(),
                    domain_owners = Tuple(owners[1:owner_count]),
                ),
                cell,
                kinds...,
                ProposalConstraint(:owner_count_frozen, false),
                Protocol(Sweep(); name = :main),
            )
        ),
    )
    source = nested ? PottsSystem(
        name = :owner_count_root, systems = (component,)
    ) : component
    return _lower_cartesian_fixture((; source))
end

function _typed_ir_metrics(method, argument_types)
    typed = only(code_typed(method, argument_types; optimize = true))
    code = first(typed)
    call_count(value) = value isa Expr ?
        (value.head in (:call, :invoke) ? 1 : 0) +
        sum(call_count, value.args; init = 0) : 0
    return (
        statements = length(code.code),
        calls = sum(call_count, code.code; init = 0),
        return_type = last(typed),
    )
end

function _cartesian_removal_fixture(replacement_builder = (_, reservoir, _) -> reservoir)
    cell = CellKind(:removal_cell; extinction = RetireAtZero())
    bulk_kind = MediumKind(:removal_bulk_kind)
    reservoir_kind = MediumKind(:removal_reservoir_kind)
    wall_kind = MediumKind(:removal_wall_kind)
    bulk = MediumDomainOwner(:bulk, bulk_kind)
    reservoir = MediumDomainOwner(:reservoir, reservoir_kind)
    wall = WallDomainOwner(:wall, wall_kind)
    replacement = replacement_builder(bulk, reservoir, wall)
    anchor = CellBinding(:removed_cell)
    remove = LifecycleProcess(
        :remove_to_domain_owner;
        domain = cells(cell),
        anchor,
        expression = true,
        effects = (
            RemoveCell(
                anchor;
                replacement,
                on_inadmissible = ErrorOnInadmissible(),
            ),
        ),
        cadence = AtMCS(1),
    )
    source = PottsSystem(
        name = :cartesian_removal,
        statements = StatementSet(
            (
                Lattice(
                    (3, 3);
                    boundary = Closed(),
                    default_owner = bulk,
                    domain_owners = (reservoir, wall),
                    max_cells = 1,
                ),
                cell,
                bulk_kind,
                reservoir_kind,
                wall_kind,
                ProposalConstraint(:freeze_removal_proposals, false),
                remove,
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
    )
    labels = zeros(Int32, 3, 3)
    labels[2, 2] = 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium = bulk)
    )
    return (; source, initial, bulk, reservoir, wall, wall_kind)
end

@testset "typed Cartesian domain authoring lowers one owner authority" begin
    fixture = _cartesian_authoring_fixture(CartesianIndex(2, 2))
    fixture.mask[1, 1] = true
    lowered = _lower_cartesian_fixture(fixture)

    @test lowered.report.shape == (4, 4)
    @test lowered.report.mutable_site_count == 15
    @test lowered.report.faces[1].kind === CartesianSPI.FixedExteriorCartesianFace
    @test lowered.report.faces[1].owner_handle == 0
    @test lowered.report.faces[2].kind === CartesianSPI.FixedExteriorCartesianFace
    @test lowered.report.faces[2].owner_handle != 0
    @test only(lowered.report.obstacles).site == 6

    default = CartesianSPI.owner_metadata(
        lowered.domain, Int16[], UInt32[], Int32(0)
    )
    wall_entry = only(
        filter(
            entry -> entry.identity.local_id == :cartesian_wall,
            lowered.plan.domain_owner_manifest,
        )
    )
    wall_code = CartesianSPI.domain_owner_code(
        lowered.domain, wall_entry.metadata
    )
    wall = CartesianSPI.owner_metadata(
        lowered.domain, Int16[], UInt32[], wall_code
    )
    @test default.category === CartesianSPI.MediumDomainOwnerCategory
    @test wall.category === CartesianSPI.WallDomainOwnerCategory
    @test default.kind != wall.kind

    requirement = only(
        inspect(lowered.scheduled, Capabilities()).requirements.domains
    )
    @test requirement.identity == (
        path = (:cartesian_authoring_fixture,), local_id = :lattice,
    )
    @test requirement.boundary[1].negative == (
        kind = :fixed_exterior,
        owner = (
            local_id = :cartesian_bulk,
            category = :medium,
            kind = :cartesian_medium,
        ),
    )
    @test only(requirement.obstacles) == (
        owner = (
            local_id = :cartesian_wall,
            category = :wall,
            kind = :cartesian_wall_kind,
        ),
        masked_site_count = 1,
    )

    default_obstacle = _lower_cartesian_fixture(
        _cartesian_authoring_fixture(
            CartesianIndex(3, 3); obstacle_owner = :default
        )
    )
    @test only(default_obstacle.report.obstacles).owner_handle == 0
    @test CartesianSPI.owner_at(
        default_obstacle.domain, zeros(Int32, 4, 4), CartesianIndex(3, 3)
    ) == 0
end

@testset "Cartesian faces and masks remain runtime specialization data" begin
    baseline = _lower_cartesian_fixture(
        _cartesian_authoring_fixture(CartesianIndex(2, 2))
    )
    moved_obstacle = _lower_cartesian_fixture(
        _cartesian_authoring_fixture(CartesianIndex(3, 2))
    )
    closed_faces = _lower_cartesian_fixture(
        _cartesian_authoring_fixture(
            CartesianIndex(2, 2);
            boundary_builder = (_, _) -> (
                AxisBoundary(Closed()), AxisBoundary(Closed()),
            ),
        )
    )

    @test typeof(baseline.domain) === typeof(moved_obstacle.domain)
    @test typeof(baseline.domain) === typeof(closed_faces.domain)
    report_metrics = _typed_ir_metrics(
        CartesianSPI.cartesian_domain_report, Tuple{typeof(baseline.domain)}
    )
    @test isconcretetype(report_metrics.return_type)
    @test report_metrics == _typed_ir_metrics(
        CartesianSPI.cartesian_domain_report,
        Tuple{typeof(moved_obstacle.domain)},
    )
    @test report_metrics == _typed_ir_metrics(
        CartesianSPI.cartesian_domain_report,
        Tuple{typeof(closed_faces.domain)},
    )
    argument_types = Tuple{typeof(baseline.domain), Matrix{Int32}, Int32}
    metrics = _typed_ir_metrics(CartesianSPI.owner_at, argument_types)
    @test metrics.return_type === Int32
    @test metrics == _typed_ir_metrics(
        CartesianSPI.owner_at,
        Tuple{typeof(moved_obstacle.domain), Matrix{Int32}, Int32},
    )
    @test metrics == _typed_ir_metrics(
        CartesianSPI.owner_at,
        Tuple{typeof(closed_faces.domain), Matrix{Int32}, Int32},
    )

    owner_counts = map(_cartesian_owner_count_fixture, (0, 1, 3))
    @test map(item -> length(item.plan.domain_owner_manifest), owner_counts) ==
        (0, 1, 3)
    @test all(
        item -> typeof(item.plan) === typeof(first(owner_counts).plan),
        owner_counts,
    )
    @test all(
        item -> typeof(item.plan.domain_owner_manifest) ===
            typeof(first(owner_counts).plan.domain_owner_manifest),
        owner_counts,
    )
    nested_owners = _cartesian_owner_count_fixture(3; nested = true)
    @test typeof(nested_owners.plan.domain_owner_manifest) ===
        typeof(last(owner_counts).plan.domain_owner_manifest)
    @test eltype(nested_owners.plan.domain_owner_manifest) ===
        eltype(last(owner_counts).plan.domain_owner_manifest)
end


@testset "lifecycle removal resolves exact registered domain-owner metadata" begin
    fixture = _cartesian_removal_fixture()
    scheduled = mtkcompile(fixture.source)
    plan = Potts._lower_scheduled_execution_plan(
        scheduled, SequentialCPM(), CPUBackend(), Float32
    )
    reservoir = only(
        filter(
            entry -> entry.identity.local_id == :reservoir,
            plan.domain_owner_manifest,
        )
    )
    reservoir_code = CartesianSPI.domain_owner_code(
        CartesianSPI.cartesian_domain(plan.core_program), reservoir.metadata
    )
    solution = solve(
        PottsProblem(scheduled, fixture.initial, (0, 1); seed = 0x0c11),
        SequentialCPM();
        scalar_type = Float32,
        save_everystep = true,
    )
    @test last(solution).ownership[2, 2] == reservoir_code

    forged_category = _cartesian_removal_fixture(
        (_, _, wall) -> MediumDomainOwner(wall.id, wall.kind)
    )
    @test_throws r"metadata does not match its registered identity" begin
        _lower_cartesian_fixture((; source = forged_category.source))
    end

    forged_kind = _cartesian_removal_fixture(
        (_, reservoir, wall) -> MediumDomainOwner(reservoir.id, wall.kind)
    )
    @test_throws r"metadata does not match its registered identity" begin
        _lower_cartesian_fixture((; source = forged_kind.source))
    end
end

@testset "domain owners have declaring-lattice lexical identity" begin
    function nested_plan(component_name)
        fixture = _cartesian_authoring_fixture(CartesianIndex(2, 2))
        component = PottsSystem(
            name = component_name,
            statements = StatementSet(statements(fixture.source)),
        )
        source = PottsSystem(name = :owner_namespace_root, systems = (component,))
        scheduled = mtkcompile(source)
        requirement = only(inspect(scheduled, Capabilities()).requirements.domains)
        @test requirement.default_owner.kind ==
            Symbol(component_name, "₊cartesian_medium")
        return Potts._lower_scheduled_execution_plan(
            scheduled, SequentialCPM(), CPUBackend(), Float32
        )
    end
    left = nested_plan(:left_domain)
    right = nested_plan(:right_domain)
    left_bulk = only(
        filter(
            entry -> entry.identity.local_id == :cartesian_bulk,
            left.domain_owner_manifest,
        )
    )
    right_bulk = only(
        filter(
            entry -> entry.identity.local_id == :cartesian_bulk,
            right.domain_owner_manifest,
        )
    )
    @test left_bulk.identity.lattice != right_bulk.identity.lattice
    @test left_bulk.metadata.identity != right_bulk.metadata.identity

    cell = CellKind(:shared_owner_cell; extinction = RetireAtZero())
    medium = MediumKind(:shared_owner_medium)
    bulk = MediumDomainOwner(:bulk, medium)
    function consumer(name, cadence)
        anchor = CellBinding(Symbol(name, :_cell))
        return PottsSystem(
            name = name,
            statements = StatementSet(
                (
                    MediumKind(:shared_owner_medium),
                    LifecycleProcess(
                        Symbol(name, :_remove);
                        domain = cells(cell),
                        anchor,
                        expression = false,
                        effects = (
                            RemoveCell(
                                anchor;
                                replacement = bulk,
                                on_inadmissible = ErrorOnInadmissible(),
                            ),
                        ),
                        cadence = AtMCS(cadence),
                    ),
                )
            ),
        )
    end
    shared_source = PottsSystem(
        name = :shared_owner_root,
        statements = StatementSet(
            (
                Lattice((3, 3); default_owner = bulk),
                cell,
                medium,
                ProposalConstraint(:shared_owner_frozen, false),
                Protocol(Sweep(); name = :main),
            )
        ),
        systems = (consumer(:first_consumer, 1), consumer(:second_consumer, 2)),
    )
    shared_plan = Potts._lower_scheduled_execution_plan(
        mtkcompile(shared_source), SequentialCPM(), CPUBackend(), Float32
    )
    @test count(
        entry -> entry.identity.local_id == :bulk,
        shared_plan.domain_owner_manifest,
    ) == 1

    shared_completed = mtkcompile(shared_source)
    shared_records = Potts._completion_data(shared_completed).source_graph.records
    lattice_record = only(filter(
        record -> record.kind === :LatticeDomain, shared_records
    ))
    root_medium_record = only(filter(
        record -> record.kind === :MediumKind &&
            record.identity.path == lattice_record.identity.path &&
            Symbol(record.identity.local_id) === :shared_owner_medium,
        shared_records,
    ))
    @test root_medium_record.identity in lattice_record.resources
    for record in filter(
            candidate -> candidate.kind === :LifecycleProcess &&
                Symbol(candidate.identity.local_id) in
                    (:first_consumer_remove, :second_consumer_remove),
            shared_records,
        )
        @test lattice_record.identity in record.resources
        false_child_kind = Potts.QualifiedStatementID(
            record.identity.path, Potts.StatementID(:shared_owner_medium)
        )
        @test false_child_kind ∉ record.resources
    end

    first_lattice = only(statements(Lattice((2, 2); name = :first_lattice)))
    second_lattice = only(statements(Lattice((2, 2); name = :second_lattice)))
    duplicate_lattices = PottsSystem(
        name = :duplicate_lattices,
        statements = StatementSet(
            (
                first_lattice,
                second_lattice,
                CellKind(:duplicate_lattice_cell; extinction = RetireAtZero()),
                MediumKind(:duplicate_lattice_medium),
                Protocol(Sweep(); name = :main),
            )
        ),
    )
    @test_throws r"at most one lattice domain" begin
        _lower_cartesian_fixture((; source = duplicate_lattices))
    end
end

@testset "canonical kind names remain valid with nested local-name reuse" begin
    cell = CellKind(:duplicate_kind_cell; extinction = RetireAtZero())
    medium = MediumKind(:shared_medium)
    bulk = MediumDomainOwner(:bulk, medium)
    child = PottsSystem(
        name = :other_scope,
        statements = StatementSet(MediumKind(:shared_medium)),
    )
    source = PottsSystem(
        name = :duplicate_kind_root,
        statements = StatementSet(
            (
                Lattice((2, 2); default_owner = bulk),
                cell,
                medium,
                ProposalConstraint(:duplicate_kind_frozen, false),
                Protocol(Sweep(); name = :main),
            )
        ),
        systems = (child,),
    )
    scheduled = mtkcompile(source)
    labels = ones(Int32, 2, 2)
    valid = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium = bulk)
    )
    @test init(
        PottsProblem(scheduled, valid, (0, 0); seed = 1),
        SequentialCPM();
        scalar_type = Float32,
    ) isa PottsIntegrator

    for root_medium in (medium, MediumKind(:shared_medium), :shared_medium)
        direct = PottsInitialState(
            ownership = LabelledCells(
                labels; cells = [cell], medium = root_medium
            )
        )
        @test init(
            PottsProblem(scheduled, direct, (0, 0); seed = 1),
            SequentialCPM();
            scalar_type = Float32,
        ) isa PottsIntegrator
    end


    child_medium = PottsInitialState(
        ownership = LabelledCells(
            labels; cells = [cell], medium = :other_scope₊shared_medium
        )
    )
    @test_throws r"does not match the lattice default" init(
        PottsProblem(scheduled, child_medium, (0, 0); seed = 1),
        SequentialCPM();
        scalar_type = Float32,
    )

    plan = Potts._lower_scheduled_execution_plan(
        scheduled, SequentialCPM(), CPUBackend(), Float32
    )
    @test_throws r"metadata does not match its registered identity" begin
        Potts._registered_domain_owner(
            plan.domain_owner_manifest,
            MediumDomainOwner(
                :bulk, MediumKind(:other_scope₊shared_medium)
            ),
        )
    end
end

@testset "Cartesian authoring rejects ambiguous ownership declarations" begin
    medium = MediumKind(:ambiguous_medium)
    shared_medium = MediumDomainOwner(:shared_domain, medium)
    shared_wall = WallDomainOwner(:shared_domain, medium)
    cell = CellKind(:ambiguous_cell; extinction = RetireAtZero())
    conflicting = PottsSystem(
        name = :conflicting_cartesian_owner,
        statements = StatementSet(
            (
                Lattice(
                    (3, 3);
                    default_owner = shared_medium,
                    domain_owners = (shared_wall,),
                ),
                cell,
                medium,
                Protocol(Sweep(); name = :main),
            )
        ),
    )
    scheduled = mtkcompile(conflicting)
    @test_throws r"conflicting category or kind" Potts._lower_scheduled_execution_plan(
        scheduled, SequentialCPM(), CPUBackend(), Float32
    )

    alternate_medium = MediumKind(:alternate_ambiguous_medium)
    conflicting_kind = PottsSystem(
        name = :conflicting_cartesian_owner_kind,
        statements = StatementSet(
            (
                Lattice(
                    (3, 3);
                    default_owner = shared_medium,
                    domain_owners = (
                        MediumDomainOwner(:shared_domain, alternate_medium),
                    ),
                ),
                cell,
                medium,
                alternate_medium,
                Protocol(Sweep(); name = :main),
            )
        ),
    )
    @test_throws r"conflicting category or kind" Potts._lower_scheduled_execution_plan(
        mtkcompile(conflicting_kind), SequentialCPM(), CPUBackend(), Float32
    )

    @test_throws r"RemoveCell replacement must be a MediumDomainOwner" RemoveCell(
        1;
        replacement = shared_wall,
        on_inadmissible = ErrorOnInadmissible(),
    )
    @test_throws r"RemoveCell replacement must be a MediumDomainOwner" RemoveCell(
        1;
        replacement = medium,
        on_inadmissible = ErrorOnInadmissible(),
    )
    @test_throws r"MediumPlacement requires a MediumDomainOwner" MediumPlacement(
        shared_wall, ((1, 1),)
    )
    @test_throws r"MediumKind alone does not identify a domain owner" MediumPlacement(
        medium, ((1, 1),)
    )

    unpaired = _cartesian_authoring_fixture(
        CartesianIndex(2, 2);
        boundary_builder = (bulk, _) -> (
            AxisBoundary(negative = Periodic(), positive = FixedExterior(bulk)),
            AxisBoundary(Closed()),
        ),
    )
    @test_throws r"periodic Cartesian faces must occur as a pair" begin
        _lower_cartesian_fixture(unpaired)
    end

    first_mask = falses(4, 4)
    second_mask = falses(4, 4)
    first_mask[2, 2] = true
    second_mask[2, 2] = true
    overlapping = _cartesian_authoring_fixture(CartesianIndex(3, 3))
    lattice = Lattice(
        (4, 4);
        default_owner = overlapping.bulk,
        domain_owners = (overlapping.wall,),
        obstacles = (
            Obstacle(first_mask; owner = overlapping.wall),
            Obstacle(second_mask; owner = overlapping.wall),
        ),
    )
    source = PottsSystem(
        name = :overlapping_cartesian_obstacles,
        statements = StatementSet(
            (
                lattice,
                overlapping.cell,
                overlapping.medium,
                overlapping.wall_kind,
                Protocol(Sweep(); name = :main),
            )
        ),
    )
    @test_throws r"obstacle masks overlap" Potts._lower_scheduled_execution_plan(
        mtkcompile(source), SequentialCPM(), CPUBackend(), Float32
    )
end

@testset "obstacle initialization is explicit and fingerprinted" begin
    first = _cartesian_authoring_fixture(CartesianIndex(2, 2))
    second = _cartesian_authoring_fixture(CartesianIndex(3, 2))
    first_lowered = _lower_cartesian_fixture(first)
    second_lowered = _lower_cartesian_fixture(second)
    @test first_lowered.plan.fingerprint != second_lowered.plan.fingerprint

    labels = zeros(Int, 4, 4)
    labels[1, 1] = 1
    valid = PottsInitialState(
        ownership = LabelledCells(
            labels; cells = [first.cell], medium = first.medium
        )
    )
    integrator = init(
        PottsProblem(first_lowered.scheduled, valid, (0, 0); seed = 1),
        SequentialCPM();
        scalar_type = Float32,
    )
    wall = CartesianSPI.owner_metadata(
        first_lowered.domain,
        integrator.u.cell_kinds,
        integrator.u.cell_generations,
        CartesianSPI.owner_at(
            first_lowered.domain, integrator.u.ownership, CartesianIndex(2, 2)
        ),
    )
    @test wall.category === CartesianSPI.WallDomainOwnerCategory

    mismatched_owner = MediumDomainOwner(first.bulk.id, first.wall_kind)
    mismatched = PottsInitialState(
        ownership = LabelledCells(
            labels; cells = [first.cell], medium = mismatched_owner
        )
    )
    @test_throws r"metadata does not match its registered identity" init(
        PottsProblem(first_lowered.scheduled, mismatched, (0, 0); seed = 1),
        SequentialCPM();
        scalar_type = Float32,
    )

    invalid_labels = copy(labels)
    invalid_labels[2, 2] = 1
    invalid = PottsInitialState(
        ownership = LabelledCells(
            invalid_labels; cells = [first.cell], medium = first.medium
        )
    )
    @test_throws r"initial ownership at obstacle site" init(
        PottsProblem(first_lowered.scheduled, invalid, (0, 0); seed = 1),
        SequentialCPM();
        scalar_type = Float32,
    )

    overlapping_layout = PottsInitialState(
        ownership = OwnershipLayout(
            (4, 4),
            CellPlacement(1, first.cell, ((2, 2),));
            medium = first.medium,
        )
    )
    @test_throws r"placements overlap" init(
        PottsProblem(
            first_lowered.scheduled, overlapping_layout, (0, 0); seed = 1
        ),
        SequentialCPM();
        scalar_type = Float32,
    )
end

@testset "scheduled Wortel activity witness" begin
    @variables wortel_activity wortel_history
    @parameters begin
        wortel_target = 6.0
        wortel_volume_strength = 1.0
        wortel_maximum = 5.0
        wortel_activity_strength = 4.0
        wortel_temperature = 8.0
    end
    endothelial = CellKind(:wortel_endothelial; extinction = RetireAtZero())
    extracellular = MediumKind(:wortel_extracellular)
    activity = SiteState(
        wortel_activity;
        name = :wortel_activity,
        owner = endothelial,
        initial = 0.0,
        lifecycle = ClearOnOwnershipChange(),
    )
    memory = HistoryState(
        wortel_history;
        name = :wortel_history,
        initial = 0.0,
        of = wortel_activity,
        depth = 2,
        cadence = EveryMCS(),
    )
    copy = ProposalContext(:wortel_copy)
    surface_anchor = CellBinding(:wortel_surface_anchor)
    source = PottsSystem(
        name = :wortel_black_box,
        statements = (@statements begin
            Lattice(
                (8, 8);
                boundary = Periodic(),
                relations = (
                    proposal = Moore(),
                    contact = Moore(),
                    surface = Moore(),
                    activity_neighborhood = Moore(),
                    connectivity = Moore(),
                    connectivity_background = VonNeumann(),
                ),
            )
            endothelial
            extracellular
            Volume(
                endothelial;
                target = wortel_target,
                strength = wortel_volume_strength,
            )
            ContactEnergy([
                (extracellular ↔ endothelial) => 6.0,
                (endothelial ↔ endothelial) => 2.0,
            ])
            HamiltonianTerm(
                :wortel_surface_energy;
                domain = cells(endothelial),
                anchor = surface_anchor,
                expression = 0.05 * (
                    cell_surface(surface_anchor) - 8.0
                )^2,
            )
            activity
            memory
            ActEnergy(
                endothelial,
                wortel_activity;
                maximum = wortel_maximum,
                strength = wortel_activity_strength,
                reduction = :activity_neighborhood,
            )
            AcceptedCopy(
                :wortel_activate,
                Assign(wortel_activity, wortel_maximum);
                when = copy.is_extension,
            )
            Synchronous(
                :wortel_decay,
                Assign(wortel_activity, max(wortel_activity - 1, 0));
                phase = AfterMCS(),
            )
            LocalConnectivity(endothelial)
            Protocol(
                Sweep(; temperature = wortel_temperature);
                name = :wortel_protocol,
            )
            Observation(:wortel_occupied, occupancy(endothelial, :lattice))
        end),
        unknowns = [wortel_activity, wortel_history],
        parameters = [
            wortel_target,
            wortel_volume_strength,
            wortel_maximum,
            wortel_activity_strength,
            wortel_temperature,
        ],
    )
    scheduled = mtkcompile(source)
    labels = zeros(Int32, 8, 8)
    labels[2:3, 2:3] .= 1
    labels[6:7, 6:7] .= 2
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels;
            cells = [endothelial, endothelial],
            medium = extracellular,
        ),
        values = (wortel_activity => zeros(Float32, 8, 8),),
    )
    problem = PottsProblem(scheduled, initial, (0, 2); seed = 0x3302)
    solution = solve(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float32,
        save_everystep = true,
        observables = (:wortel_occupied,),
    )
    replay = solve(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float32,
        save_everystep = true,
    )
    independent = solve(
        remake(problem; replica = 2),
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float32,
        save_everystep = true,
    )
    @test solution.retcode == SciMLBase.ReturnCode.Success
    @test getfield.(solution.u, :ownership) == getfield.(replay.u, :ownership)
    @test any(
        left.ownership != right.ownership
        for (left, right) in zip(solution.u, independent.u)
    )
    final = last(solution)
    @test all(isfinite, final[:wortel_activity])
    @test minimum(final[:wortel_activity]) >= 0.0f0
    @test maximum(final[:wortel_activity]) <= 5.0f0
    @test length(final[:wortel_history]) == 2
    @test last(final[:wortel_history]) == final[:wortel_activity]
    @test final[:wortel_occupied] == count(!iszero, final.ownership)
    @test_throws Potts.PottsKnownUnsavedError replay(2)[:wortel_occupied]
    @test_throws Potts.PottsUnknownIdentityError replay(2)[:not_declared]
    activity_getter = SymbolicIndexingInterface.getsym(
        solution, wortel_activity
    )
    @test length(activity_getter(solution)) == length(solution.t)
    occupied_getter = SymbolicIndexingInterface.getsym(
        solution, :wortel_occupied
    )
    @test occupied_getter(solution) ==
          [state[:wortel_occupied] for state in solution]
    @test_throws Potts.PottsKnownUnsavedError begin
        SymbolicIndexingInterface.getsym(
            replay, :wortel_occupied
        )(replay)
    end
end

@testset "scheduled Merks discrete-field witness" begin
    @variables merks_field
    @parameters begin
        merks_target = 6.0
        merks_volume_strength = 1.0
        merks_chemo_strength = 2.0
        merks_diffusion = 0.08
        merks_secretion = 0.02
        merks_decay = 0.01
        merks_temperature = 6.0
    end
    endothelial = CellKind(:merks_endothelial; extinction = RetireAtZero())
    extracellular = MediumKind(:merks_extracellular)
    field = FieldState(
        merks_field;
        name = :merks_field,
        initial = 0.0,
        evolution = DiscreteFieldEuler(),
        diffusion = merks_diffusion,
        secretion = merks_secretion,
        decay = merks_decay,
        substeps = 2,
        duration_per_mcs = 1.0,
        source_kind = endothelial,
        stencil = :field_stencil,
    )
    source = PottsSystem(
        name = :merks_black_box,
        statements = StatementSet((
            Lattice(
                (8, 8);
                boundary = Closed(),
                relations = (
                    proposal = Moore(),
                    connectivity = Moore(),
                    connectivity_background = VonNeumann(),
                    field_stencil = VonNeumann(),
                ),
            ),
            endothelial,
            extracellular,
            field,
            Volume(
                endothelial;
                target = merks_target,
                strength = merks_volume_strength,
            ),
            Chemotaxis(
                endothelial,
                field;
                strength = merks_chemo_strength,
                mode = ExtensionsOnly(),
                sample = Nearest(),
            ),
            LocalConnectivity(endothelial),
            Protocol(
                Sweep(; temperature = merks_temperature);
                name = :merks_protocol,
            ),
            Observation(:merks_field_snapshot, merks_field),
        )),
        unknowns = [merks_field],
        parameters = [
            merks_target,
            merks_volume_strength,
            merks_chemo_strength,
            merks_diffusion,
            merks_secretion,
            merks_decay,
            merks_temperature,
        ],
    )
    scheduled = mtkcompile(source)
    labels = zeros(Int32, 8, 8)
    labels[3:5, 3:5] .= 1
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels; cells = [endothelial], medium = extracellular
        ),
        values = (merks_field => zeros(Float64, 8, 8),),
    )
    solution = solve(
        PottsProblem(scheduled, initial, (0, 2); seed = 0x3303),
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_everystep = true,
        observables = (:merks_field_snapshot,),
    )
    final = last(solution)
    @test solution.retcode == SciMLBase.ReturnCode.Success
    @test all(isfinite, final[:merks_field])
    @test sum(final[:merks_field]) > 0
    @test final[:merks_field_snapshot] == final[:merks_field]
end

@testset "discrete-field Euler boundary oracle and restart" begin
    function field_oracle_problem(boundary, suffix)
        field_variable = only(@variables oracle_field)
        diffusion = only(@parameters oracle_diffusion = 0.1)
        cell = CellKind(
            Symbol(:oracle_cell_, suffix); extinction = RetireAtZero()
        )
        medium = MediumKind(Symbol(:oracle_medium_, suffix))
        boundary_policy = boundary === :frozen ? FrozenBorder(cell) : boundary
        field = FieldState(
            field_variable;
            name = Symbol(:oracle_field_, suffix),
            initial = 0.0,
            evolution = DiscreteFieldEuler(),
            diffusion,
            decay = 0.0,
            secretion = 0.0,
            substeps = 1,
            duration_per_mcs = 1.0,
            stencil = :field_stencil,
        )
        source = PottsSystem(
            name = Symbol(:oracle_model_, suffix),
            statements = StatementSet((
                Lattice(
                    (3, 3);
                    boundary = boundary_policy,
                    relations = (field_stencil = VonNeumann(),),
                ),
                cell,
                medium,
                field,
                ProposalConstraint(Symbol(:freeze_oracle_, suffix), false),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )),
            unknowns = [field_variable],
            parameters = [diffusion],
        )
        initial_field = zeros(3, 3)
        initial_field[1, 1] = 1.0
        initial = PottsInitialState(
            ownership = LabelledCells(
                zeros(Int, 3, 3); cells = CellKind[], medium
            ),
            values = (field_variable => initial_field,),
        )
        problem = PottsProblem(
            mtkcompile(source), initial, (0, 2); seed = 0x3304
        )
        return problem, Symbol(:oracle_field_, suffix)
    end

    periodic_problem, periodic_name = field_oracle_problem(
        Periodic(), :periodic
    )
    periodic = init(
        periodic_problem, SequentialCPM(); scalar_type = Float32
    )
    step!(periodic)
    periodic_expected = zeros(3, 3)
    periodic_expected[1, 1] = 0.6
    periodic_expected[2, 1] = 0.1
    periodic_expected[3, 1] = 0.1
    periodic_expected[1, 2] = 0.1
    periodic_expected[1, 3] = 0.1
    @test periodic.u[periodic_name] ≈ periodic_expected

    closed_problem, closed_name = field_oracle_problem(Closed(), :closed)
    closed = init(closed_problem, SequentialCPM(); scalar_type = Float32)
    step!(closed)
    closed_expected = zeros(3, 3)
    closed_expected[1, 1] = 0.8
    closed_expected[2, 1] = 0.1
    closed_expected[1, 2] = 0.1
    @test closed.u[closed_name] ≈ closed_expected

    frozen_problem, frozen_name = field_oracle_problem(
        :frozen, :frozen
    )
    frozen = init(frozen_problem, SequentialCPM(); scalar_type = Float32)
    step!(frozen)
    @test frozen.u[frozen_name] ≈ closed_expected

    saved = checkpoint(periodic)
    restored = init(
        periodic_problem,
        SequentialCPM();
        scalar_type = Float32,
        checkpoint = saved,
    )
    step!(periodic)
    step!(restored)
    @test periodic.u[periodic_name] == restored.u[periodic_name]
end

@testset "scheduled focal relationship and restart witness" begin
    @parameters begin
        focal_target = 4.0
        focal_volume_strength = 1.0
        focal_strength = 1.5
        focal_length = 3.0
        focal_break = 12.0
        focal_temperature = 5.0
    end
    endothelial = CellKind(:focal_endothelial; extinction = RetireAtZero())
    extracellular = MediumKind(:focal_extracellular)
    links = RelationshipState(
        :focal_links;
        endpoints = Undirected(endothelial, endothelial),
        payload = (
            strength = focal_strength,
            target = focal_length,
            maximum = focal_break,
        ),
        capacity = 4,
        maximum_degree = 2,
        lifecycle = RemoveWithEndpoint(),
    )
    edge = RelationshipBinding(:focal_edge, links)
    copy = ProposalContext(:focal_copy)
    source = PottsSystem(
        name = :focal_black_box,
        statements = StatementSet((
            Lattice(
                (8, 6);
                boundary = Closed(),
                relations = (proposal = VonNeumann(),),
            ),
            endothelial,
            extracellular,
            links,
            Volume(
                endothelial;
                target = focal_target,
                strength = focal_volume_strength,
            ),
            RelationshipEnergy(
                :focal_energy,
                edge,
                edge.strength * (
                    distance(
                        unwrapped_center(edge.a),
                        unwrapped_center(edge.b),
                    ) - edge.target
                )^2,
            ),
            AcceptedCopy(
                :focal_create_contact,
                Create(
                    links,
                    copy.source_cell,
                    copy.target_cell;
                    payload = (
                        strength = focal_strength,
                        target = focal_length,
                        maximum = focal_break,
                    ),
                );
                when = new_contact(copy.source_cell, copy.target_cell) &
                       !linked(links, copy.source_cell, copy.target_cell),
            ),
            LifecycleProcess(
                :focal_remove_stretched;
                domain = edges(links),
                expression = distance(
                    unwrapped_center(edge.a), unwrapped_center(edge.b)
                ) > edge.maximum,
                effects = (Remove(links, edge),),
                phase = Lifecycle(),
            ),
            Protocol(
                Sweep(; temperature = focal_temperature);
                name = :focal_protocol,
            ),
            Observation(:focal_degree, degree(links, 1)),
        )),
        parameters = [
            focal_target,
            focal_volume_strength,
            focal_strength,
            focal_length,
            focal_break,
            focal_temperature,
        ],
    )
    scheduled = mtkcompile(source)
    labels = zeros(Int32, 8, 6)
    labels[2:3, 2:3] .= 1
    labels[6:7, 4:5] .= 2
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels;
            cells = [endothelial, endothelial],
            medium = extracellular,
        ),
        values = (links => [(1, 2)],),
    )
    stale_initial = PottsInitialState(
        ownership = initial.ownership,
        values = (links => [(
            1,
            2,
            (
                generation_a = 2,
                generation_b = 1,
                strength = 1.5,
                target = 3.0,
                maximum = 12.0,
            ),
        )],),
    )
    @test_throws ArgumentError PottsProblem(
        scheduled, stale_initial, (0, 1); seed = 1
    )

    stretched_initial = PottsInitialState(
        ownership = initial.ownership,
        values = (links => [(
            1,
            2,
            (strength = 1.5, target = 3.0, maximum = 1.0),
        )],),
    )
    stretched = solve(
        PottsProblem(scheduled, stretched_initial, (0, 1); seed = 0x3305),
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_everystep = true,
    )
    @test count(last(stretched)[:focal_links].active) == 0
    stretched_checkerboard = solve(
        PottsProblem(scheduled, stretched_initial, (0, 1); seed = 0x3305),
        CheckerboardSweepCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_everystep = true,
    )
    @test count(last(stretched_checkerboard)[:focal_links].active) == 0

    contact_labels = zeros(Int32, 8, 6)
    contact_labels[3, 2] = 1
    contact_labels[3, 4] = 2
    contact_initial = PottsInitialState(
        ownership = LabelledCells(
            contact_labels;
            cells = [endothelial, endothelial],
            medium = extracellular,
        ),
    )
    created = nothing
    for seed in UInt64(1):UInt64(256)
        candidate = solve(
            PottsProblem(scheduled, contact_initial, (0, 1); seed),
            SequentialCPM();
            backend = CPUBackend(),
            scalar_type = Float64,
            save_everystep = true,
        )
        count(last(candidate)[:focal_links].active) == 1 || continue
        created = candidate
        break
    end
    @test created !== nothing
    created === nothing && error("no accepted-copy focal link witness found")
    @test created.stats.accepted > 0
    @test last(created).ownership != contact_labels
    @test count(last(created)[:focal_links].active) == 1

    problem = PottsProblem(scheduled, initial, (0, 2); seed = 0x3304)
    uninterrupted = solve(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_everystep = true,
        observables = (:focal_degree,),
    )
    @test count(uninterrupted(0)[:focal_links].active) == 1
    @test uninterrupted(0)[:focal_degree] == 1

    integrator = init(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_start = false,
    )
    step!(integrator)
    captured = checkpoint(integrator)
    resumed = solve!(init(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        checkpoint = captured,
        save_start = false,
    ))
    @test last(resumed).ownership == last(uninterrupted).ownership
    @test last(resumed)[:focal_links].active ==
          last(uninterrupted)[:focal_links].active
    @test last(resumed)[:focal_links].endpoint_a ==
          last(uninterrupted)[:focal_links].endpoint_a
end

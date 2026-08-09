@testset "scheduled finite three-site reference witness" begin
    @parameters finite_weight = log(2.0) finite_temperature = 1.0
    finite_cell = CellKind(:finite_cell; extinction = RetireAtZero())
    finite_medium = MediumKind(:finite_medium)
    finite_site = SiteBinding(:finite_site)
    finite_copy = ProposalContext(:finite_copy)
    source = PottsSystem(
        name = :finite_three_site,
        statements = StatementSet((
            # Keep the three-site state space while exercising the currently
            # supported two-dimensional CPU profile.
            Lattice(
                (3, 1);
                boundary = Periodic(),
                relations = (proposal = VonNeumann(),),
            ),
            finite_cell,
            finite_medium,
            HamiltonianTerm(
                :finite_energy;
                domain = sites(:lattice),
                anchor = finite_site,
                expression = finite_weight * occupancy(finite_cell, finite_site),
            ),
            ProposalConstraint(
                :finite_nonempty_domains,
                ifelse(
                    finite_copy.is_extension,
                    cell_volume(finite_copy.source_cell) < 2,
                    ifelse(
                        finite_copy.is_retraction,
                        cell_volume(finite_copy.target_cell) > 1,
                        true,
                    ),
                ),
            ),
            Protocol(
                Sweep(; temperature = finite_temperature);
                name = :finite_protocol,
            ),
        )),
        parameters = [finite_weight, finite_temperature],
    )
    scheduled = mtkcompile(source)
    initial = PottsInitialState(
        ownership = LabelledCells(
            reshape(Int32[1, 0, 0], 3, 1);
            cells = [finite_cell],
            medium = finite_medium,
        ),
    )
    problem = PottsProblem(
        scheduled,
        initial,
        (0, 3);
        p = (
            finite_weight => log(2.0),
            finite_temperature => 1.0,
        ),
        seed = 0x3301,
    )
    first = solve(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_everystep = true,
    )
    replay = solve(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_everystep = true,
    )
    @test first.retcode == SciMLBase.ReturnCode.Success
    @test first.t == collect(0:3)
    @test getfield.(first.u, :ownership) == getfield.(replay.u, :ownership)
    @test all(state -> count(==(Int32(1)), state.ownership) in 1:2, first.u)
    @test first.stats.candidate_attempts == 9
    @test first.stats.candidate_attempts ==
          first.stats.accepted + first.stats.null_attempts +
          first.stats.constraint_rejections + first.stats.energy_rejections
end

@testset "scheduled chemotaxis follows the independent gradient sign" begin
    @variables chemotaxis_field chemotaxis_gate
    cell = CellKind(:chemotaxis_cell; extinction = RetireAtZero())
    medium = MediumKind(:chemotaxis_medium)
    field = FieldState(
        chemotaxis_field;
        name = :chemotaxis_field,
        initial = 0.0,
    )
    gate = FieldState(
        chemotaxis_gate;
        name = :chemotaxis_gate,
        initial = 0.0,
    )
    copy = ProposalContext(:chemotaxis_copy)
    source = PottsSystem(
        name = :chemotaxis_gradient_witness,
        statements = StatementSet((
            Lattice(
                (2, 1);
                boundary = Closed(),
                relations = (proposal = VonNeumann(),),
            ),
            cell,
            medium,
            field,
            gate,
            Chemotaxis(
                cell,
                chemotaxis_field;
                strength = 2.0,
                mode = ExtensionsOnly(),
                sample = Nearest(),
            ),
            ProposalConstraint(
                :isolate_directed_chemotaxis_extension,
                copy.is_extension &
                (field_value(chemotaxis_gate, copy.source_site) == 1) &
                (field_value(chemotaxis_gate, copy.target_site) == 2),
            ),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        unknowns = [chemotaxis_field, chemotaxis_gate],
    )
    scheduled = mtkcompile(source)
    labels = reshape(Int32[1, 0], 2, 1)
    gate_values = reshape(Float64[1, 2], 2, 1)
    initial(target_concentration) = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        values = (
            chemotaxis_field => reshape(
                Float64[1, target_concentration], 2, 1
            ),
            chemotaxis_gate => gate_values,
        ),
    )
    function run(target_concentration, seed)
        return solve(
            PottsProblem(
                scheduled, initial(target_concentration), (0, 1); seed
            ),
            SequentialCPM();
            backend = CPUBackend(),
            scalar_type = Float64,
            save_everystep = true,
        )
    end

    witness = nothing
    for seed in UInt64(1):UInt64(512)
        # Independent law: -strength * (target - source) is -6 for the
        # increasing field and +2 for the decreasing field.
        favorable = run(4.0, seed)
        favorable.stats.accepted == 1 || continue
        unfavorable = run(0.0, seed)
        unfavorable.stats.energy_rejections > 0 || continue
        witness = (; favorable, unfavorable)
        break
    end
    @test witness !== nothing
    witness === nothing && error("no directed chemotaxis witness found")
    @test all(==(Int32(1)), last(witness.favorable).ownership)
    @test witness.unfavorable.stats.accepted == 0
    @test last(witness.unfavorable).ownership == labels
end

@testset "scheduled elongation follows an independent shape-energy sign" begin
    @variables elongation_gate
    @parameters elongation_target = 3.0
    cell = CellKind(:elongation_cell; extinction = RetireAtZero())
    medium = MediumKind(:elongation_medium)
    gate = FieldState(
        elongation_gate; name = :elongation_gate, initial = 0.0
    )
    copy_context = ProposalContext(:elongation_copy)
    source = PottsSystem(
        name = :elongation_sign_witness,
        statements = StatementSet((
            Lattice(
                (4, 1);
                boundary = Closed(),
                relations = (proposal = VonNeumann(),),
            ),
            cell,
            medium,
            gate,
            Elongation(cell; target = elongation_target, strength = 4.0),
            ProposalConstraint(
                :isolate_elongation_extension,
                copy_context.is_extension &
                (field_value(
                    elongation_gate, copy_context.source_site
                ) == 1) &
                (field_value(
                    elongation_gate, copy_context.target_site
                ) == 2),
            ),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        unknowns = [elongation_gate],
        parameters = [elongation_target],
    )
    scheduled = mtkcompile(source)
    labels = reshape(Int32[1, 1, 0, 0], 4, 1)
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        values = (
            elongation_gate => reshape(Float64[0, 1, 2, 0], 4, 1),
        ),
    )
    run(target, seed) = solve(
        PottsProblem(
            scheduled,
            initial,
            (0, 1);
            p = (elongation_target => target,),
            seed,
        ),
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_everystep = true,
    )
    witness = nothing
    for seed in UInt64(1):UInt64(256)
        favorable = run(3.0, seed)
        favorable.stats.accepted == 1 || continue
        unfavorable = run(1.0, seed)
        unfavorable.stats.energy_rejections > 0 || continue
        witness = (; favorable, unfavorable)
        break
    end
    @test witness !== nothing
    witness === nothing && error("no directed elongation witness found")
    @test last(witness.favorable).ownership ==
          reshape(Int32[1, 1, 1, 0], 4, 1)
    @test last(witness.unfavorable).ownership == labels
end

@testset "relationship constraint blocks linked-cell absorption" begin
    cell = CellKind(:constrained_link_cell; extinction = RetireAtZero())
    medium = MediumKind(:constrained_link_medium)
    links = RelationshipState(
        :constrained_links;
        endpoints = Undirected(cell, cell),
        capacity = 1,
        maximum_degree = 1,
        lifecycle = RemoveWithEndpoint(),
    )
    copy_context = ProposalContext(:constrained_link_copy)
    source = PottsSystem(
        name = :relationship_constraint_witness,
        statements = StatementSet((
            Lattice(
                (2, 1);
                boundary = Closed(),
                relations = (proposal = VonNeumann(),),
            ),
            cell,
            medium,
            links,
            RelationshipConstraint(
                :preserve_linked_cells,
                links,
                !linked(
                    links,
                    copy_context.source_cell,
                    copy_context.target_cell,
                ),
            ),
            Protocol(Sweep(; temperature = 100.0); name = :main),
        )),
    )
    labels = reshape(Int32[1, 2], 2, 1)
    solution = solve(
        PottsProblem(
            mtkcompile(source),
            PottsInitialState(
                ownership = LabelledCells(
                    labels; cells = [cell, cell], medium
                ),
                values = (links => [(1, 2)],),
            ),
            (0, 1);
            seed = 0x3306,
        ),
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_everystep = true,
    )
    @test solution.retcode == SciMLBase.ReturnCode.Success
    @test last(solution).ownership == labels
    @test solution.stats.accepted == 0
    # The closed two-site relation deduplicates coincident directions, so the
    # exact attempt partition is topology-specific.  At least one proposed
    # absorption must reach and be rejected by the relationship constraint.
    @test solution.stats.constraint_rejections > 0
    @test count(last(solution)[:constrained_links].active) == 1
end

@testset "relationship retune publishes payload and survives checkpoint" begin
    cell = CellKind(:retune_cell; extinction = RetireAtZero())
    medium = MediumKind(:retune_medium)
    links = RelationshipState(
        :retune_links;
        endpoints = Undirected(cell, cell),
        payload = (score = 1.0, marker = 1.0),
        capacity = 1,
        maximum_degree = 1,
        lifecycle = RemoveWithEndpoint(),
    )
    edge = RelationshipBinding(:retune_edge, links)
    retune = LifecycleProcess(
        :retune_once;
        domain = edges(links),
        expression = edge.marker > 0,
        effects = (Retune(
            links,
            edge;
            payload = (score = edge.score + 2, marker = 0.0),
        ),),
        cadence = AtMCS(1),
    )
    source = PottsSystem(
        name = :relationship_retune_witness,
        statements = StatementSet((
            Lattice((3, 1); boundary = Closed()),
            cell,
            medium,
            links,
            ProposalConstraint(:freeze_retune_witness, false),
            retune,
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
    )
    labels = reshape(Int32[1, 0, 2], 3, 1)
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels; cells = [cell, cell], medium
        ),
        values = (links => [(1, 2)],),
    )
    scheduled = mtkcompile(source)
    problem = PottsProblem(scheduled, initial, (0, 2); seed = 0x3307)
    uninterrupted = solve(
        problem,
        SequentialCPM();
        backend = CPUBackend(),
        scalar_type = Float64,
        save_everystep = true,
    )
    topology = uninterrupted(1)[:retune_links]
    edge_slot = only(findall(topology.active))
    @test topology.payload[1][edge_slot] == 3
    @test topology.payload[2][edge_slot] == 0

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
    @test last(resumed)[:retune_links].payload ==
          last(uninterrupted)[:retune_links].payload
    @test last(resumed)[:retune_links].active ==
          last(uninterrupted)[:retune_links].active
end

@testset "accepted ownership survives filtered relationship admission" begin
    @variables relationship_filter_mask
    cell = CellKind(:relationship_filter_cell; extinction = RetireAtZero())
    medium = MediumKind(:relationship_filter_medium)
    mask = FieldState(
        relationship_filter_mask;
        name = :relationship_filter_mask,
        initial = 0.0,
    )
    links = RelationshipState(
        :filtered_links;
        endpoints = Undirected(cell, cell),
        payload = (weight = 1.0,),
        capacity = 3,
        maximum_degree = 1,
        lifecycle = RemoveWithEndpoint(),
    )
    copy = ProposalContext(:relationship_filter_copy)
    source = PottsSystem(
        name = :relationship_filter_model,
        statements = StatementSet((
            Lattice(
                (5, 5);
                boundary = Closed(),
                relations = (proposal = VonNeumann(),),
            ),
            cell,
            medium,
            mask,
            links,
            ProposalConstraint(
                :only_marked_relationship_copy,
                (field_value(
                    relationship_filter_mask, copy.source_site
                ) == 1) &
                (field_value(
                    relationship_filter_mask, copy.target_site
                ) == 2),
            ),
            AcceptedCopy(
                :request_filtered_link,
                Create(
                    links,
                    copy.source_cell,
                    copy.target_cell;
                    payload = (weight = 1.0,),
                );
                when = new_contact(copy.source_cell, copy.target_cell) &
                       !linked(links, copy.source_cell, copy.target_cell),
            ),
            Protocol(Sweep(; temperature = 1.0); name = :main),
        )),
        unknowns = [relationship_filter_mask],
    )
    scheduled = mtkcompile(source)
    labels = zeros(Int32, 5, 5)
    labels[3, 2] = 1
    labels[1, 1] = 2
    labels[3, 4] = 3
    mask_values = zeros(Float64, 5, 5)
    mask_values[3, 2] = 1
    mask_values[3, 3] = 2
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels; cells = [cell, cell, cell], medium
        ),
        values = (
            relationship_filter_mask => mask_values,
            links => [(1, 2)],
        ),
    )
    witness = nothing
    for seed in UInt64(1):UInt64(512)
        candidate = solve(
            PottsProblem(scheduled, initial, (0, 1); seed),
            SequentialCPM();
            backend = CPUBackend(),
            scalar_type = Float64,
            save_everystep = true,
        )
        last(candidate).ownership[3, 3] == 1 || continue
        witness = candidate
        break
    end
    @test witness !== nothing
    witness === nothing && error("no filtered relationship witness found")
    final = last(witness)
    @test witness.stats.accepted == 1
    @test final.ownership[3, 3] == 1
    topology = final[:filtered_links]
    @test count(topology.active) == 1
    edge = only(findall(topology.active))
    @test (topology.endpoint_a[edge], topology.endpoint_b[edge]) ==
          (Int32(1), Int32(2))
end

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
    @test_throws PottsToolkit.PottsKnownUnsavedError replay(2)[:wortel_occupied]
    @test_throws PottsToolkit.PottsUnknownIdentityError replay(2)[:not_declared]
    activity_getter = SymbolicIndexingInterface.getsym(
        solution, wortel_activity
    )
    @test length(activity_getter(solution)) == length(solution.t)
    occupied_getter = SymbolicIndexingInterface.getsym(
        solution, :wortel_occupied
    )
    @test occupied_getter(solution) ==
          [state[:wortel_occupied] for state in solution]
    @test_throws PottsToolkit.PottsKnownUnsavedError begin
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

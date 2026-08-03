@testset "visible Wortel activity fixture" begin
    # The full reduced model assembly is intentionally visible here. It mirrors
    # Wortel et al.'s stochastic Act-CPM mechanism without a hidden model builder.
    @variables t activity(t) activity_history(t)
    @parameters begin
        A₀ = 12.0
        λA = 1.0
        M = 10.0
        λact = 20.0
        temperature = 18.0
    end

    endothelial = CellKind(:endothelial; extinction = RetireAtZero())
    extracellular = MediumKind(:extracellular)
    activity_state = SiteState(
        activity;
        name = :activity,
        owner = endothelial,
        initial = 0.0,
        lifecycle = ClearOnOwnershipChange(),
    )
    activity_memory = HistoryState(
        activity_history;
        name = :activity_history,
        initial = 0.0,
        of = activity,
        depth = 2,
        cadence = EveryMCS(),
    )
    copy_context = ProposalContext(:copy)
    model_statements = @statements begin
        Lattice(
            (20, 16);
            boundary = Periodic(),
            relations = (
                proposal = Moore(1),
                contact = Moore(1),
                surface = Moore(1),
                query = Moore(1),
                activity_neighborhood = Moore(1),
                connectivity = Moore(1),
                connectivity_background = VonNeumann(1),
            ),
        )
        endothelial
        extracellular
        Volume(endothelial; target = A₀, strength = λA)
        ContactEnergy([
            (extracellular ↔ endothelial) => 6.0,
            (endothelial ↔ endothelial) => 2.0,
        ])
        activity_state
        activity_memory
        ActEnergy(
            endothelial,
            activity;
            maximum = M,
            strength = λact,
            reduction = :activity_neighborhood,
        )
        AcceptedCopy(
            :activate_protrusion,
            Assign(activity, M);
            when = copy_context.is_extension,
        )
        Synchronous(
            :decay_activity,
            Assign(activity, max(activity - 1, 0));
            phase = AfterMCS(),
            decay = 1.0,
        )
        LocalConnectivity(endothelial)
        Protocol(
            Sweep(:cpm; attempts = AttemptsPerSite(1), temperature),
            ObserveStage(:trajectory; every = 1);
            name = :main,
        )
        Observation(:occupied_sites, occupancy(endothelial, :lattice))
    end

    @named wortel = PottsSystem(
        statements = model_statements,
        unknowns = [activity, activity_history],
        parameters = [A₀, λA, M, λact, temperature],
        independent_variables = [t],
        initial_conditions = Dict(activity => 0.0, activity_history => 0.0),
    )
    completed = complete(wortel)
    executable = compile(
        completed;
        engine = SequentialEngine(),
        backend = CPUBackend(),
        scalar_type = Float32,
    )
    capabilities = inspect(executable, Capabilities())
    @test :site in capabilities.state_domains
    @test :history in capabilities.state_domains
    @test :SiteAssignmentEffect in capabilities.stage_effects
    @test :ShiftAppendEffect in capabilities.stage_effects

    labels = zeros(Int, 20, 16)
    labels[4:6, 6:8] .= 1
    labels[13:15, 8:10] .= 2
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels; cells = [endothelial, endothelial], medium = extracellular
        ),
        values = [activity => zeros(Float32, size(labels))],
    )
    problem = PottsProblem(executable, initial, (0, 6); seed = 0x7068617365313401)
    trajectory = solve(
        problem; save_everystep = true, observables = (:occupied_sites,)
    )
    replay = solve(problem; save_everystep = true)
    independent = solve(
        remake(problem; replica = 2); save_everystep = true
    )
    @test all(
        left.ownership == right.ownership &&
        left.activity == right.activity &&
        left.activity_history == right.activity_history
        for (left, right) in zip(trajectory, replay)
    )
    @test any(
        left.ownership != right.ownership
        for (left, right) in zip(trajectory, independent)
    )
    @test maximum(trajectory(6).activity) <= 10
    @test minimum(trajectory(6).activity) >= 0
    @test length(trajectory(6).activity_history) == 2
    @test last(trajectory(6).activity_history) == trajectory(6).activity
    @test trajectory(6)[:occupied_sites] ==
          count(!iszero, trajectory(6).ownership)
    @test_throws PottsToolkit.PottsKnownUnsavedError replay(6)[:occupied_sites]
    @test_throws PottsToolkit.PottsUnknownIdentityError replay(6)[:not_declared]
    activity_getter = SymbolicIndexingInterface.getsym(trajectory, activity)
    @test length(activity_getter(trajectory)) == length(trajectory.t)
    occupancy_getter = SymbolicIndexingInterface.getsym(
        trajectory, :occupied_sites
    )
    @test occupancy_getter(trajectory) ==
          [state[:occupied_sites] for state in trajectory]
    @test_throws PottsToolkit.PottsKnownUnsavedError begin
        SymbolicIndexingInterface.getsym(replay, :occupied_sites)(replay)
    end
end

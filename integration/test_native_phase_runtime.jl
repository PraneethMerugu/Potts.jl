using OrdinaryDiffEqTsit5: Tsit5

@testset "native output reaches same-MCS lifecycle" begin
    @independent_variables phase_t
    @variables phase_x(phase_t) = 1.0 phase_target
    phase_D = ModelingToolkitBase.Differential(phase_t)
    @named phase_ode = ModelingToolkit.System(
        [phase_D(phase_x) ~ 1.0], phase_t)

    follower = CellKind(:phase_follower; extinction = ForbidExtinction())
    medium = MediumKind(:phase_medium)
    relation = SpatialRelation(:phase_division; neighborhood = VonNeumann())
    anchor = CellBinding(:phase_divider)
    function phase_problem(phase; horizon = 1,
            cadence = EveryMCS(), division_mcs = 1,
            target_division = CopyToDaughters())
        target = CellState(phase_target; initial = 1.0,
            division = target_division)
        mitosis = LifecycleProcess(:phase_mitosis;
            domain = cells(follower), anchor,
            expression = phase_target > 1.5,
            effects = (Divide(anchor;
                geometry = SpecifiedNormalPlane((1.0, 0.0)),
                relation, side = CanonicalSide(),
                on_inadmissible = ErrorOnInadmissible()),),
            cadence = AtMCS(division_mcs))
        component = NativeComponent(phase_ode;
            name = :growth, family = ODEComponent(), scope = PerCell(),
            phase, domain = cells(follower),
            cadence, time = FixedPhysicalTime(0.0, 1.0),
            outputs = (NativeOutput(phase_x, target;
                value_type = Float64),),
            lifecycle = PerCellNativeLifecycle(
                creation = PreserveNativeInitialization(),
                transition = Preserve(), division = CopyToDaughters()))
        source = PottsSystem(name = :native_phase_lifecycle,
            statements = StatementSet((
                Lattice((5, 5); boundary = Closed(), max_cells = 4,
                    relations = (proposal = VonNeumann(),)),
                follower, medium, target, relation, mitosis,
                ProposalConstraint(:phase_freeze, false),
                Protocol(Sweep(; temperature = 1.0); name = :main),
            )), unknowns = [phase_target], native_components = (component,))
        labels = zeros(Int, 5, 5)
        labels[2:3, 2:3] .= 1
        initial = PottsInitialState(
            ownership = LabelledCells(labels; cells = [follower], medium),
            native = (NativeOperatingPoint(
                (:native_phase_lifecycle, :growth);
                values = (phase_x => 1.0,)),))
        return PottsProblem(source, initial, (0, horizon); seed = 0x5048)
    end

    profile = NativeSolveProfile((:native_phase_lifecycle, :growth), Tsit5();
        adaptive = false, dt = 1.0)
    before = solve(phase_problem(BeforeLifecycle()), SequentialCPM();
        backend = CPUBackend(), native_profiles = (profile,), saveat = [0, 1])
    after = solve(phase_problem(AfterCompletedMCS()), SequentialCPM();
        backend = CPUBackend(), native_profiles = (profile,), saveat = [0, 1])
    @test failure_report(before) === nothing
    @test failure_report(after) === nothing
    @test count(>(0), before.u[end].cell_kinds) == 2
    @test count(>(0), after.u[end].cell_kinds) == 1
    @test before(1)[:phase_target][1] ≈ 2.0
    @test before(1)[:phase_target][2] ≈ 2.0
    @test after(1)[:phase_target][1] ≈ 2.0
    path = (:native_phase_lifecycle, :growth)
    for slot in 1:2
        state = before(1)
        identity = CellIdentity(slot, state.cell_generations[slot],
            state.cell_kinds[slot])
        @test native_value(before, path, identity, phase_x; index = 2) ≈ 2.0
    end

    replay_profile = NativeSolveProfile(
        (:native_phase_lifecycle, :growth), Tsit5();
        profile_id = "pre-lifecycle-fixed-tsit5", deterministic = true,
        exact_replay = true, adaptive = false, dt = 1.0)
    replay_problem = phase_problem(BeforeLifecycle(); horizon = 2)
    direct = solve(replay_problem, SequentialCPM();
        backend = CPUBackend(), native_profiles = (replay_profile,),
        saveat = [0, 1, 2])
    staged = init(replay_problem, SequentialCPM(); backend = CPUBackend(),
        native_profiles = (replay_profile,), saveat = [0, 1, 2])
    Potts.SciMLBase.step!(staged)
    restored = init(replay_problem, SequentialCPM(); backend = CPUBackend(),
        native_profiles = (replay_profile,), checkpoint = checkpoint(staged),
        saveat = [0, 1, 2])
    Potts.SciMLBase.solve!(restored)
    @test restored.u.ownership == direct(2).ownership
    @test restored.u[:phase_target] == direct(2)[:phase_target]
    for slot in 1:2
        state = direct(2)
        identity = CellIdentity(slot, state.cell_generations[slot],
            state.cell_kinds[slot])
        @test native_value(direct, path, identity, phase_x; index = 3) ≈ 3.0
    end

    sparse_problem = phase_problem(BeforeLifecycle(); horizon = 4,
        cadence = Every(3), division_mcs = 3,
        target_division = TransformDaughters(
            phase_target / 2, phase_target / 2))
    sparse = init(sparse_problem, SequentialCPM(); backend = CPUBackend(),
        native_profiles = (replay_profile,))
    for _ in 1:3
        Potts.SciMLBase.step!(sparse)
    end
    @test count(>(0), sparse.u.cell_kinds) == 2
    @test sparse.u[:phase_target][1:2] ≈ [2.0, 2.0]
    Potts.SciMLBase.step!(sparse)
    @test sparse.u[:phase_target][1:2] ≈ [2.0, 2.0]
    restored_sparse = init(sparse_problem, SequentialCPM();
        backend = CPUBackend(), native_profiles = (replay_profile,),
        checkpoint = checkpoint(sparse))
    @test restored_sparse.u[:phase_target][1:2] ≈ [2.0, 2.0]

    failing_profile = NativeSolveProfile(
        (:native_phase_lifecycle, :growth), Tsit5();
        adaptive = false, dt = 0.01, maxiters = 1)
    failing = init(phase_problem(BeforeLifecycle()), SequentialCPM();
        backend = CPUBackend(), native_profiles = (failing_profile,))
    before_failure = deepcopy(failing.u)
    @test_throws Potts.NativeSolveFailure Potts.SciMLBase.step!(failing)
    @test failing.t == 0
    @test failing.u.ownership == before_failure.ownership
    @test failing.u[:phase_target] == before_failure[:phase_target]

    failing_after = init(phase_problem(AfterCompletedMCS()),
        SequentialCPM(); backend = CPUBackend(),
        native_profiles = (failing_profile,))
    after_failure = deepcopy(failing_after.u)
    @test_throws Potts.NativeSolveFailure Potts.SciMLBase.step!(failing_after)
    @test failing_after.t == 0
    @test failing_after.u.ownership == after_failure.ownership
    @test failing_after.u[:phase_target] == after_failure[:phase_target]
end

@testset "qualified per-cell native domain selects nested kind" begin
    @independent_variables qualified_t
    @variables qualified_x(qualified_t) = 0.0
    @named qualified_ode = ModelingToolkit.System(
        [ModelingToolkitBase.Differential(qualified_t)(qualified_x) ~ 1.0],
        qualified_t)
    child_kind = CellKind(:follower; extinction = ForbidExtinction())
    medium = MediumKind(:qualified_medium)
    relation = SpatialRelation(:qualified_division;
        neighborhood = VonNeumann())
    anchor = CellBinding(:qualified_anchor)
    dormant = LifecycleProcess(:qualified_dormant;
        domain = cells(child_kind), anchor, expression = false,
        effects = (Divide(anchor;
            geometry = SpecifiedNormalPlane((1.0, 0.0)), relation,
            side = CanonicalSide(),
            on_inadmissible = FilterInadmissible()),),
        cadence = AtMCS(1))
    component = NativeComponent(qualified_ode;
        name = :growth, family = ODEComponent(), scope = PerCell(),
        domain = cells(child_kind), phase = AfterCompletedMCS(),
        time = FixedPhysicalTime(0.0, 1.0),
        lifecycle = PerCellNativeLifecycle(
            creation = PreserveNativeInitialization(),
            transition = Preserve(), division = CopyToDaughters()))
    child = PottsSystem(name = :nested,
        statements = StatementSet((child_kind, relation, dormant)),
        native_components = (component,))
    source = PottsSystem(name = :qualified_native_root,
        statements = StatementSet((
            Lattice((4, 4); boundary = Closed(), max_cells = 2),
            medium,
            ProposalConstraint(:qualified_freeze, false),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )), systems = (child,))
    labels = zeros(Int, 4, 4)
    labels[2, 2] = 1
    path = (:qualified_native_root, :nested, :growth)
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [child_kind], medium),
        native = (NativeOperatingPoint(path;
            values = (qualified_x => 0.0,)),))
    profile = NativeSolveProfile(path, Tsit5();
        adaptive = false, dt = 1.0)
    result = solve(PottsProblem(source, initial, (0, 1); seed = 0x5050),
        SequentialCPM(); backend = CPUBackend(),
        native_profiles = (profile,))
    state = result(1)
    identity = CellIdentity(1, state.cell_generations[1],
        state.cell_kinds[1])
    @test native_value(result, path, identity, qualified_x; index = 2) ≈ 1.0
end

@testset "mixed native phases follow visibility, not declaration order" begin
    @independent_variables pre_t post_t
    @variables pre_x(pre_t) = 0.0 post_x(post_t) = 0.0
    @variables pre_value post_value observed_pre(post_t)
    @named pre_ode = ModelingToolkit.System(
        [ModelingToolkitBase.Differential(pre_t)(pre_x) ~ 1.0], pre_t)
    @named post_ode = ModelingToolkit.System(
        [ModelingToolkitBase.Differential(post_t)(post_x) ~ observed_pre],
        post_t)
    cell = CellKind(:mixed_phase_cell; extinction = ForbidExtinction())
    medium = MediumKind(:mixed_phase_medium)
    first_state = CellState(pre_value; initial = 0.0,
        division = CopyToDaughters())
    second_state = CellState(post_value; initial = 0.0,
        division = CopyToDaughters())
    relation = SpatialRelation(:mixed_phase_division;
        neighborhood = VonNeumann())
    anchor = CellBinding(:mixed_phase_anchor)
    dormant_lifecycle = LifecycleProcess(:mixed_phase_dormant;
        domain = cells(cell), anchor, expression = false,
        effects = (Divide(anchor;
            geometry = SpecifiedNormalPlane((1.0, 0.0)), relation,
            side = CanonicalSide(),
            on_inadmissible = FilterInadmissible()),),
        cadence = AtMCS(1))
    pre = NativeComponent(pre_ode;
        name = :pre, family = ODEComponent(), scope = PerCell(),
        domain = cells(cell), phase = BeforeLifecycle(),
        time = FixedPhysicalTime(0.0, 1.0),
        outputs = (NativeOutput(pre_x, first_state; value_type = Float64),),
        lifecycle = PerCellNativeLifecycle(
            creation = PreserveNativeInitialization(),
            transition = Preserve(), division = CopyToDaughters()))
    post = NativeComponent(post_ode;
        name = :post, family = ODEComponent(), scope = PerCell(),
        domain = cells(cell), phase = AfterCompletedMCS(),
        time = FixedPhysicalTime(0.0, 1.0),
        inputs = (NativeInput(observed_pre, first_state;
            value_type = Float64),),
        outputs = (NativeOutput(post_x, second_state;
            value_type = Float64),),
        lifecycle = PerCellNativeLifecycle(
            creation = PreserveNativeInitialization(),
            transition = Preserve(), division = CopyToDaughters()))
    function ordered_problem(components)
        source = PottsSystem(name = :mixed_native_phases,
            statements = StatementSet((
                Lattice((4, 4); boundary = Closed(), max_cells = 2),
                cell, medium, first_state, second_state, relation,
                dormant_lifecycle,
                ProposalConstraint(:mixed_freeze, false),
                Protocol(Sweep(; temperature = 1.0); name = :main),
            )), unknowns = [pre_value, post_value],
            native_components = components)
        labels = zeros(Int, 4, 4)
        labels[2, 2] = 1
        initial = PottsInitialState(
            ownership = LabelledCells(labels; cells = [cell], medium),
            native = (
                NativeOperatingPoint((:mixed_native_phases, :pre);
                    values = (pre_x => 0.0,)),
                NativeOperatingPoint((:mixed_native_phases, :post);
                    values = (post_x => 0.0,)),
            ))
        return PottsProblem(source, initial, (0, 1); seed = 0x5049)
    end
    profiles = (
        NativeSolveProfile((:mixed_native_phases, :pre), Tsit5();
            adaptive = false, dt = 1.0),
        NativeSolveProfile((:mixed_native_phases, :post), Tsit5();
            adaptive = false, dt = 1.0),
    )
    ordered = solve(ordered_problem((pre, post)), SequentialCPM();
        backend = CPUBackend(), native_profiles = profiles)
    reversed = solve(ordered_problem((post, pre)), SequentialCPM();
        backend = CPUBackend(), native_profiles = profiles)
    @test failure_report(ordered) === nothing
    @test failure_report(reversed) === nothing
    @test ordered(1)[:pre_value][1] ≈ 1.0
    @test ordered(1)[:post_value][1] ≈ 1.0
    @test reversed(1)[:pre_value] == ordered(1)[:pre_value]
    @test reversed(1)[:post_value] == ordered(1)[:post_value]
end

@testset "filtered native cadence begins at cell creation" begin
    @independent_variables cadence_t
    @variables cadence_x(cadence_t) = 0.0 cadence_value
    cadence_D = ModelingToolkitBase.Differential(cadence_t)
    @named cadence_ode = ModelingToolkit.System(
        [cadence_D(cadence_x) ~ 1.0], cadence_t)
    cell = CellKind(:cadence_cell; extinction = ForbidExtinction())
    medium = MediumKind(:cadence_medium)
    value = CellState(cadence_value; initial = 0.0,
        creation = InitializeFrom(0.0))
    relation = SpatialRelation(:cadence_creation; neighborhood = VonNeumann())
    site = LinearIndices((6, 6))[CartesianIndex(4, 3)]
    create = LifecycleProcess(:cadence_create;
        domain = model(), expression = true,
        effects = (CreateCell(cell;
            placement = SeedStencil(site, ((0, 0), (1, 0)); relation),
            on_inadmissible = ErrorOnInadmissible()),),
        cadence = AtMCS(1))
    component = NativeComponent(cadence_ode;
        name = :cadence_growth, family = ODEComponent(), scope = PerCell(),
        phase = AfterCompletedMCS(), domain = cells(cell),
        cadence = Every(3), time = FixedPhysicalTime(0.0, 1.0),
        outputs = (NativeOutput(cadence_x, value;
            value_type = Float64),),
        lifecycle = PerCellNativeLifecycle(
            creation = PreserveNativeInitialization(),
            transition = Preserve(), division = CopyToDaughters()))
    source = PottsSystem(name = :native_cadence_birth,
        statements = StatementSet((
            Lattice((6, 6); boundary = Closed(), max_cells = 4),
            cell, medium, value, relation, create,
            ProposalConstraint(:cadence_freeze, false),
            Protocol(Sweep(; temperature = 1.0); name = :main),
        )), unknowns = [cadence_value], native_components = (component,))
    labels = zeros(Int, 6, 6)
    labels[2, 2] = 1
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        native = (NativeOperatingPoint((:native_cadence_birth, :cadence_growth);
            values = (cadence_x => 0.0,)),))
    problem = PottsProblem(source, initial, (0, 3); seed = 0x5068)
    path = (:native_cadence_birth, :cadence_growth)
    serial_profile = NativeSolveProfile(path, Tsit5();
        adaptive = false, dt = 1.0)
    batch_profile = NativeSolveProfile(path, Tsit5();
        execution = BatchedNativeExecution(2), adaptive = false, dt = 1.0)
    serial = solve(problem, SequentialCPM();
        backend = CPUBackend(), native_profiles = (serial_profile,),
        saveat = [0, 1, 3])
    batched = solve(problem, SequentialCPM();
        backend = CPUBackend(), native_profiles = (batch_profile,),
        saveat = [0, 1, 3])
    @test failure_report(serial) === nothing
    @test failure_report(batched) === nothing
    @test count(>(0), serial(1).cell_kinds) == 2
    @test serial(3)[:cadence_value][1] ≈ 3.0
    @test serial(3)[:cadence_value][2] ≈ 2.0
    @test batched(3)[:cadence_value] ≈ serial(3)[:cadence_value]
end

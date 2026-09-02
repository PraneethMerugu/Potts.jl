using OrdinaryDiffEqTsit5: Tsit5
using SciMLBase

@testset "batched CPU per-cell parity" begin
    @independent_variables batch_t
    @variables batch_x(batch_t) = 1.0 batch_drive(batch_t) batch_seen(batch_t)
    batch_D = ModelingToolkitBase.Differential(batch_t)
    @named batch_system = ModelingToolkit.System(
        [batch_D(batch_x) ~ batch_drive],
        batch_t;
        observed = [batch_seen ~ 2batch_x],
    )
    @variables batch_potts_drive batch_potts_output
    drive = CellState(
        batch_potts_drive;
        name = :batch_drive,
        initial = 2.0,
        retirement = RetireTo(0.0),
    )
    output = CellState(
        batch_potts_output;
        name = :batch_output,
        initial = 0.0,
        retirement = RetireTo(0.0),
    )
    component = NativeComponent(
        batch_system;
        name = :batch_island,
        family = ODEComponent(),
        scope = PerCell(),
        time = FixedPhysicalTime(0.0, 0.1),
        inputs = (NativeInput(
            batch_drive, drive; value_type = Float64
        ),),
        outputs = (NativeOutput(
            batch_x, output; value_type = Float64
        ),),
        lifecycle = PerCellNativeLifecycle(
            creation = PreserveNativeInitialization(),
            transition = Preserve(),
            division = CopyToDaughters(),
        ),
    )
    cell = CellKind(:batch_cell; extinction = RetireAtZero())
    medium = MediumKind(:batch_medium)
    source = PottsSystem(
        name = :batched_cpu_model,
        statements = StatementSet((
            Lattice((4, 4); boundary = Closed(), max_cells = 4),
            cell,
            medium,
            drive,
            output,
            ProposalConstraint(:freeze_batched_cpu, false),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        unknowns = [batch_potts_drive, batch_potts_output],
        native_components = (component,),
    )
    scheduled = mtkcompile(source)
    path = (:batched_cpu_model, :batch_island)
    labels = zeros(Int, 4, 4)
    labels[1, 1] = 1
    labels[1, 4] = 2
    labels[4, 1] = 3
    labels[4, 4] = 4
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels; cells = fill(cell, 4), medium
        ),
        values = (drive => [1.0, 2.0, 3.0, 4.0],),
        native = (NativeOperatingPoint(
            path; values = (batch_x => 1.0,)
        ),),
    )
    problem = PottsProblem(scheduled, initial, (0, 1); seed = 0x506)
    serial_profile = NativeSolveProfile(
        path,
        Tsit5();
        profile_id = "tsit5-batch-parity-serial-v1",
        deterministic = true,
        exact_replay = true,
        adaptive = false,
        dt = 0.01,
    )
    batched_profile = NativeSolveProfile(
        path,
        Tsit5();
        profile_id = "tsit5-batch-parity-width3-v1",
        execution = BatchedNativeExecution(3),
        deterministic = true,
        exact_replay = true,
        adaptive = false,
        dt = 0.01,
    )
    serial = solve(
        problem, SequentialCPM(); native_profiles = (serial_profile,)
    )
    batched = solve(
        problem, SequentialCPM(); native_profiles = (batched_profile,)
    )
    @test last(batched).ownership == last(serial).ownership
    @test last(batched).cell_kinds == last(serial).cell_kinds
    @test last(batched).cell_generations == last(serial).cell_generations
    @test last(batched).batch_output == last(serial).batch_output
    for slot in 1:4
        identity = CellIdentity(
            slot,
            last(batched).cell_generations[slot],
            last(batched).cell_kinds[slot],
        )
        @test native_value(batched, path, identity, batch_x) ≈
            1.0 + 0.1slot
        @test native_value(batched, path, identity, batch_seen) ≈
            2.0 + 0.2slot
        @test native_value(batched, path, identity, batch_x) ==
            native_value(serial, path, identity, batch_x)
    end
    report = inspect(init(
        problem,
        SequentialCPM();
        native_profiles = (batched_profile,),
    ), Capabilities())
    @test only(report.key.native).execution ==
        (mode = :batched_cpu, width = 3)
    @test only(report.evidence.native).suite ===
        :per_cell_batched_cpu_native_ode_exact_replay
    @test only(report.key.native).evidence.profile_fingerprint ==
        only(report.evidence.native).profile_fingerprint
    scalar_error = try
        init(
            problem,
            SequentialCPM();
            scalar_type = Float32,
            native_profiles = (batched_profile,),
        )
        nothing
    catch error
        error
    end
    @test scalar_error isa Potts.NativeCapabilityError
    @test scalar_error.capability === :scalar_type

    dae_component = NativeComponent(
        batch_system;
        name = :batch_dae_island,
        family = DAEComponent(),
        scope = PerCell(),
        time = FixedPhysicalTime(0.0, 0.1),
        inputs = (NativeInput(
            batch_drive, drive; value_type = Float64
        ),),
        lifecycle = PerCellNativeLifecycle(
            creation = PreserveNativeInitialization(),
            transition = Preserve(),
            division = CopyToDaughters(),
        ),
    )
    dae_source = PottsSystem(
        name = :batched_dae_rejection,
        statements = StatementSet((
            Lattice((4, 4); boundary = Closed(), max_cells = 4),
            cell,
            medium,
            drive,
            ProposalConstraint(:freeze_batched_dae, false),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        unknowns = [batch_potts_drive],
        native_components = (dae_component,),
    )
    dae_path = (:batched_dae_rejection, :batch_dae_island)
    dae_problem = PottsProblem(
        mtkcompile(dae_source),
        PottsInitialState(
            ownership = LabelledCells(
                labels; cells = fill(cell, 4), medium
            ),
            native = (NativeOperatingPoint(
                dae_path; values = (batch_x => 1.0,)
            ),),
        ),
        (0, 1);
        seed = 0x508,
    )
    dae_profile = NativeSolveProfile(
        dae_path,
        Tsit5();
        profile_id = "batched-dae-rejected",
        execution = BatchedNativeExecution(4),
        deterministic = true,
        adaptive = false,
        dt = 0.01,
    )
    dae_error = try
        init(
            dae_problem,
            SequentialCPM();
            native_profiles = (dae_profile,),
        )
        nothing
    catch error
        error
    end
    @test dae_error isa Potts.NativeCapabilityError
    @test dae_error.capability === :native_execution_mode

    @independent_variables batch_event_t
    @variables batch_event_x(batch_event_t) = 0.0
    batch_event_D = ModelingToolkitBase.Differential(batch_event_t)
    @named batch_event_system = ModelingToolkit.System(
        [batch_event_D(batch_event_x) ~ 1.0],
        batch_event_t;
        continuous_events = (
            [batch_event_x ~ 0.05] => [batch_event_x ~ 0.0]
        ),
    )
    event_component = NativeComponent(
        batch_event_system;
        name = :batch_event_island,
        family = ODEComponent(),
        scope = PerCell(),
        time = FixedPhysicalTime(0.0, 0.1),
        lifecycle = PerCellNativeLifecycle(
            creation = PreserveNativeInitialization(),
            transition = Preserve(),
            division = CopyToDaughters(),
        ),
    )
    event_source = PottsSystem(
        name = :batched_event_rejection,
        statements = StatementSet((
            Lattice((4, 4); boundary = Closed(), max_cells = 4),
            cell,
            medium,
            ProposalConstraint(:freeze_batched_event, false),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        native_components = (event_component,),
    )
    event_path = (:batched_event_rejection, :batch_event_island)
    event_problem = PottsProblem(
        mtkcompile(event_source),
        PottsInitialState(
            ownership = LabelledCells(
                labels; cells = fill(cell, 4), medium
            ),
            native = (NativeOperatingPoint(
                event_path; values = (batch_event_x => 0.0,)
            ),),
        ),
        (0, 1);
        seed = 0x509,
    )
    event_profile = NativeSolveProfile(
        event_path,
        Tsit5();
        profile_id = "batched-event-rejected",
        execution = BatchedNativeExecution(4),
        deterministic = true,
        adaptive = false,
        dt = 0.01,
    )
    event_error = try
        init(
            event_problem,
            SequentialCPM();
            native_profiles = (event_profile,),
        )
        nothing
    catch error
        error
    end
    @test event_error isa Potts.NativeCapabilityError
    @test event_error.capability === :native_events

    callback = SciMLBase.DiscreteCallback(
        (_state, _time, _integrator) -> false,
        (_integrator) -> nothing,
    )
    callback_error = try
        init(
            problem,
            SequentialCPM();
            native_profiles = (batched_profile,),
            callback,
        )
        nothing
    catch error
        error
    end
    @test callback_error isa Potts.NativeCapabilityError
    @test callback_error.capability === :outer_callbacks
end

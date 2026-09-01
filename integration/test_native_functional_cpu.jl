using OrdinaryDiffEqTsit5: Tsit5
using SciMLBase

@testset "functional native CPU execution" begin
    @independent_variables functional_t
    @variables functional_x(functional_t) = 1.0
    @variables functional_drive(functional_t)
    functional_D = ModelingToolkitBase.Differential(functional_t)
    @named native_system = ModelingToolkit.System(
        [functional_D(functional_x) ~ functional_drive], functional_t
    )

    @variables potts_drive potts_output
    drive = CellState(
        potts_drive;
        name = :functional_drive,
        initial = 1.0,
        retirement = RetireTo(0.0),
    )
    output = CellState(
        potts_output;
        name = :functional_output,
        initial = 0.0,
        retirement = RetireTo(0.0),
    )
    component = NativeComponent(
        native_system;
        name = :native_island,
        family = ODEComponent(),
        scope = PerCell(),
        time = FixedPhysicalTime(0.0, 0.1),
        inputs = (NativeInput(
            functional_drive, drive; value_type = Float64
        ),),
        outputs = (NativeOutput(
            functional_x, output; value_type = Float64
        ),),
        lifecycle = PerCellNativeLifecycle(
            creation = PreserveNativeInitialization(),
            transition = Preserve(),
            division = CopyToDaughters(),
        ),
    )
    cell = CellKind(:functional_cell; extinction = RetireAtZero())
    medium = MediumKind(:functional_medium)
    source = PottsSystem(
        name = :functional_native_cpu,
        statements = StatementSet((
            Lattice((4, 4); boundary = Closed(), max_cells = 4),
            cell,
            medium,
            drive,
            output,
            ProposalConstraint(:freeze_functional_native, false),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        unknowns = [potts_drive, potts_output],
        native_components = (component,),
    )
    scheduled = mtkcompile(source)
    path = (:functional_native_cpu, :native_island)
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
            path; values = (functional_x => 1.0,)
        ),),
    )
    problem = PottsProblem(scheduled, initial, (0, 1); seed = 0x50a)
    serial_profile = NativeSolveProfile(
        path,
        Tsit5();
        deterministic = true,
        adaptive = false,
        dt = 0.01,
    )
    batched_profile = NativeSolveProfile(
        path,
        Tsit5();
        execution = BatchedNativeExecution(3),
        deterministic = true,
        adaptive = false,
        dt = 0.01,
    )

    serial = solve(
        problem, SequentialCPM(); native_profiles = (serial_profile,)
    )
    batched = solve(
        problem, SequentialCPM(); native_profiles = (batched_profile,)
    )
    @test last(batched).functional_output == last(serial).functional_output
    @test last(batched).ownership == last(serial).ownership
    for slot in 1:4
        identity = CellIdentity(
            slot,
            last(batched).cell_generations[slot],
            last(batched).cell_kinds[slot],
        )
        @test native_value(batched, path, identity, functional_x) ≈
            1.0 + 0.1slot
        @test native_value(batched, path, identity, functional_x) ==
            native_value(serial, path, identity, functional_x)
    end
    for profile in (serial_profile, batched_profile)
        report = inspect(init(
            problem, SequentialCPM(); native_profiles = (profile,)
        ), Capabilities())
        @test report.status === PottsToolkit.CorePotts.BackendSPI.Supported
        @test !report.exact_replay
        @test report.evidence.conjunction === nothing
    end

    failing_profile = NativeSolveProfile(
        path,
        Tsit5();
        execution = BatchedNativeExecution(3),
        deterministic = true,
        adaptive = false,
        dt = 0.01,
        maxiters = 1,
    )
    failing = init(
        problem, SequentialCPM(); native_profiles = (failing_profile,)
    )
    before = failing.u
    @test_throws PottsToolkit.NativeSolveFailure step!(failing)
    @test failing.t == 0
    @test failing.retcode == SciMLBase.ReturnCode.Failure
    @test failing.u.ownership == before.ownership
    @test only(failing.u.native).active == only(before.native).active
    @test map(value -> value === nothing ? nothing : value.u,
        only(failing.u.native).states) ==
        map(value -> value === nothing ? nothing : value.u,
            only(before.native).states)
end

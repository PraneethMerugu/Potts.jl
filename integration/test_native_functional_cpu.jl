using OrdinaryDiffEqTsit5: Tsit5
using SciMLBase

@testset "native islands without outputs retain maintained input values" begin
    for input_only in (true, false)
        @testset "$(input_only ? "input-only" : "no-input") ODE island" begin
            @independent_variables retained_t
            @variables retained_x(retained_t) = 1.0 retained_input(retained_t)
            derivative = ModelingToolkitBase.Differential(retained_t)
            @named retained_ode = ModelingToolkit.System(
                [derivative(retained_x) ~ (input_only ? retained_input : 1.0)], retained_t
            )
            @variables signal total drive
            small = 2.0^-54
            lattice = LatticeDomain(:space; shape = (2, 2), spacing = (1.0, 1.0),
                boundary = Closed(), max_cells = 2)
            kind = CellKind(:cell; extinction = ForbidExtinction())
            medium = MediumKind(:medium)
            site = SiteBinding(:locations, sites(lattice))
            owner = CellBinding(:owners, cells(kind))
            drive_state = ModelState(drive; initial = 1.0)
            component = NativeComponent(
                retained_ode; name = :observer, family = ODEComponent(),
                time = FixedPhysicalTime(0.0, 0.1),
                inputs = input_only ? (NativeInput(retained_input, drive_state; value_type = Float64),) : (),
            )
            copy_context = ProposalContext(:copy)
            source = PottsSystem(
                name = :retained_native_inputs,
                statements = StatementSet((
                    lattice, kind, medium, drive_state,
                    FieldState(signal; initial = 0.0, scope = site),
                    CellState(total; initial = 0.0, scope = owner),
                    Synchronous(:measure, Assign(total,
                        aggregate(signal; over = site, by = owner, atol = small)); anchor = owner),
                    ProposalConstraint(:remove_large_contribution,
                        (copy_context.source_cell == 2) & (copy_context.target_cell == 1) &
                        (field_value(signal, copy_context.target_site) > 0.5)),
                    Protocol(Sweep(; temperature = 0.0); name = :main),
                )),
                unknowns = (signal, total, drive), native_components = (component,),
            )
            path = (:retained_native_inputs, :observer)
            labels = Int32[1 2; 1 2]
            signals = reshape(Float64[1, small, 0, 0], 2, 2)
            initial = PottsInitialState(
                ownership = LabelledCells(labels; cells = [kind, kind], medium),
                values = (signal => signals,),
                native = (NativeOperatingPoint(path; values = (retained_x => 1.0,)),),
            )
            problem = PottsProblem(source, initial, (0, 34); seed = 0x3826)
            profile = NativeSolveProfile(path, Tsit5(); deterministic = true,
                adaptive = false, dt = 0.01)
            integrator = init(problem, SequentialCPM(); scalar_type = Float64,
                native_profiles = (profile,))
            # Only one ownership change is admissible. Its incremental update
            # subtracts 1 from the rounded sum (1 + small), leaving cached zero.
            for _ in 1:32
                step!(integrator)
                @test native_value(integrator, path, retained_x) ≈ 1.0 + 0.1integrator.t
                integrator.u.ownership[1] == 2 && break
            end
            expected_labels = copy(labels)
            expected_labels[1] = 2
            @test integrator.u.ownership == expected_labels
            canonical = sum((signals[index] for index in eachindex(signals)
                if expected_labels[index] == 1); init = 0.0)
            @test canonical === small
            @test integrator.u[:total][1] === 0.0
            for _ in 1:2
                step!(integrator)
                @test integrator.u.ownership == expected_labels
                @test integrator.u[:signal] == signals
                @test integrator.u[:total][1] === 0.0
                @test integrator.u[:total][1] != canonical
                @test native_value(integrator, path, retained_x) ≈ 1.0 + 0.1integrator.t
            end
        end
    end
end

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
        @test report.status === Potts.CorePotts.BackendSPI.Supported
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
    @test_throws Potts.NativeSolveFailure step!(failing)
    @test failing.t == 0
    @test failing.retcode == SciMLBase.ReturnCode.Failure
    @test failing.u.ownership == before.ownership
    @test only(failing.u.native).active == only(before.native).active
    @test map(value -> value === nothing ? nothing : value.u,
        only(failing.u.native).states) ==
        map(value -> value === nothing ? nothing : value.u,
            only(before.native).states)
end

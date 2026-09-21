using OrdinaryDiffEqTsit5: Tsit5
using SymbolicIndexingInterface: setu

@testset "maintained cell sums cross one held native snapshot boundary" begin
    @independent_variables aggregate_native_t
    @variables aggregate_native_x(aggregate_native_t) = 1.0
    @variables aggregate_native_input(aggregate_native_t)
    aggregate_native_D = ModelingToolkitBase.Differential(aggregate_native_t)
    @named aggregate_native_system = ModelingToolkit.System(
        [aggregate_native_D(aggregate_native_x) ~ aggregate_native_input],
        aggregate_native_t,
    )

    @variables aggregate_signal aggregate_input native_output observed_output
    lattice = LatticeDomain(
        :aggregate_native_space;
        shape = (2, 2), spacing = (1.0, 1.0), boundary = Closed(),
        max_cells = 2,
    )
    kind = CellKind(:aggregate_native_cell; extinction = RetireAtZero())
    medium = MediumKind(:aggregate_native_medium)
    site = SiteBinding(:aggregate_native_sites, sites(lattice))
    owner = CellBinding(:aggregate_native_cells, cells(kind))
    signal = FieldState(aggregate_signal; initial = 0.0, scope = site)
    input = CellState(
        aggregate_input; initial = 0.0, scope = owner,
        retirement = RetireTo(0.0),
    )
    output = CellState(
        native_output; initial = 0.0, scope = owner,
        retirement = RetireTo(0.0),
    )
    observed = CellState(
        observed_output; initial = -1.0, scope = owner,
        retirement = RetireTo(0.0),
    )
    component = NativeComponent(
        aggregate_native_system;
        name = :aggregate_native_island,
        family = ODEComponent(),
        scope = PerCell(),
        time = FixedPhysicalTime(0.0, 0.1),
        cadence = Every(2),
        inputs = (
            NativeInput(
                aggregate_native_input, input; value_type = Float64,
            ),
        ),
        outputs = (
            NativeOutput(
                aggregate_native_x, output; value_type = Float64,
            ),
        ),
        lifecycle = PerCellNativeLifecycle(
            creation = PreserveNativeInitialization(),
            transition = Preserve(),
            division = CopyToDaughters(),
        ),
    )
    source = PottsSystem(
        name = :aggregate_native_snapshot,
        statements = StatementSet((
            lattice,
            kind,
            medium,
            signal,
            input,
            output,
            observed,
            Synchronous(
                :publish_aggregate_native_input,
                Assign(
                    aggregate_input,
                    aggregate(aggregate_signal; over = site, by = owner),
                );
                anchor = owner,
            ),
            Synchronous(
                :observe_held_native_output,
                Assign(observed_output, native_output);
                anchor = owner,
            ),
            ProposalConstraint(:hold_aggregate_native_ownership, false),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )),
        unknowns = (
            aggregate_signal, aggregate_input, native_output, observed_output,
        ),
        native_components = (component,),
    )
    path = (:aggregate_native_snapshot, :aggregate_native_island)
    labels = Int32[1 2; 1 0]
    initial_signal = Float64[1 5; 3 4]
    initial = PottsInitialState(
        ownership = LabelledCells(
            labels; cells = [kind, kind], medium,
        ),
        values = (aggregate_signal => initial_signal,),
        native = (
            NativeOperatingPoint(
                path; values = (aggregate_native_x => 1.0,),
            ),
        ),
    )
    problem = PottsProblem(source, initial, (0, 3); seed = 0x50c)
    profile = NativeSolveProfile(
        path,
        Tsit5();
        profile_id = "aggregate-native-tsit5-fixed-v1",
        deterministic = true,
        exact_replay = true,
        adaptive = false,
        dt = 0.01,
    )
    integrator = init(
        problem, SequentialCPM(); scalar_type = Float64,
        native_profiles = (profile,),
    )

    owner_sums(values) = Float64[
        sum(
            (values[index] for index in eachindex(labels)
             if labels[index] == cell);
            init = 0.0,
        ) for cell in 1:2
    ]
    initial_sums = owner_sums(initial_signal)
    @test integrator.u[:native_output] == [1.0, 1.0]
    step!(integrator)
    @test integrator.t == 1
    @test integrator.u[:aggregate_input] == initial_sums
    @test integrator.u[:observed_output] == [1.0, 1.0]
    @test integrator.u[:native_output] == [1.0, 1.0]

    changed_signal = Float64[2 7; 4 0]
    setu(integrator, aggregate_signal)(integrator, changed_signal)
    changed_sums = owner_sums(changed_signal)
    @test integrator.u[:aggregate_input] == initial_sums
    restored = init(
        problem, SequentialCPM(); scalar_type = Float64,
        native_profiles = (profile,), checkpoint = checkpoint(integrator),
    )

    for current in (integrator, restored)
        step!(current)
        expected_native = 1.0 .+ 0.2 .* changed_sums
        @test current.t == 2
        @test current.u[:aggregate_input] == changed_sums
        @test current.u[:observed_output] == [1.0, 1.0]
        @test current.u[:native_output] ≈ expected_native atol = 2e-8
        for slot in 1:2
            identity = CellIdentity(
                slot,
                current.u.cell_generations[slot],
                current.u.cell_kinds[slot],
            )
            @test native_value(
                current, path, identity, aggregate_native_x,
            ) ≈ expected_native[slot] atol = 2e-8
        end
        step!(current)
        @test current.t == 3
        @test current.u[:aggregate_input] == changed_sums
        @test current.u[:observed_output] ≈ expected_native atol = 2e-8
        @test current.u[:native_output] ≈ expected_native atol = 2e-8
        @test failure_report(current) === nothing
    end
    @test checkpoint(restored).checksum == checkpoint(integrator).checksum
end

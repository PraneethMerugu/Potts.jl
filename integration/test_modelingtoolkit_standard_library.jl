@testset "native ModelingToolkitStandardLibrary component" begin
    import OrdinaryDiffEqTsit5

    @named native_filter =
        ModelingToolkitStandardLibrary.Blocks.FirstOrder(T = 1.0, k = 2.0)
    filter_inputs = ModelingToolkitBase.inputs(native_filter)
    filter_outputs = ModelingToolkitBase.outputs(native_filter)
    native_filter_input = Symbolics.wrap(only(filter_inputs))
    native_filter_output = Symbolics.wrap(only(filter_outputs))
    @test length(filter_inputs) == 1
    @test length(filter_outputs) == 1

    @variables filter_drive filter_output
    drive_state = ModelState(
        filter_drive; name = :filter_drive_state, initial = 1.0
    )
    output_state = ModelState(
        filter_output; name = :filter_output_state, initial = 0.0
    )
    component = NativeComponent(
        native_filter;
        name = :native_filter_component,
        family = ODEComponent(),
        time = FixedPhysicalTime(0.0, 0.25),
        inputs = (
            NativeInput(
                native_filter_input, drive_state; value_type = Float64
            ),
        ),
        outputs = (
            NativeOutput(
                native_filter_output, output_state; value_type = Float64
            ),
        ),
    )
    cell = CellKind(:filter_cell; extinction = RetireAtZero())
    medium = MediumKind(:filter_medium)
    source = PottsSystem(
        name = :mtsl_coupled_model,
        statements = StatementSet((
            Lattice((4, 4)),
            cell,
            medium,
            drive_state,
            output_state,
            Protocol(Sweep(; temperature = 1.0); name = :main),
        )),
        unknowns = [filter_drive, filter_output],
        native_components = (component,),
    )
    scheduled_potts = mtkcompile(source)
    compiled = only(scheduled_native_components(scheduled_potts))
    scheduled = PottsToolkit.native_scheduled_system(compiled)

    @test PottsToolkit.native_original_system(compiled) === native_filter
    @test ModelingToolkitBase.get_isscheduled(scheduled)
    @test any(isequal(only(filter_inputs)), ModelingToolkitBase.inputs(scheduled))
    @test any(isequal(only(filter_outputs)), ModelingToolkitBase.outputs(scheduled))
    @test !isempty(ModelingToolkitBase.get_systems(native_filter))
    @test !isempty(ModelingToolkitBase.get_initial_conditions(scheduled))
    @test PottsToolkit.native_component_path(compiled) ==
        (:mtsl_coupled_model, :native_filter_component)

    labels = zeros(Int, 4, 4)
    labels[2, 2] = 1
    path = (:mtsl_coupled_model, :native_filter_component)
    initial = PottsInitialState(
        ownership = LabelledCells(labels; cells = [cell], medium),
        native = (NativeOperatingPoint(path),),
    )
    problem = PottsProblem(scheduled_potts, initial, (0, 1); seed = 0x508)
    profile = NativeSolveProfile(
        path,
        OrdinaryDiffEqTsit5.Tsit5();
        deterministic = true,
        adaptive = false,
        dt = 0.005,
    )
    integrator = init(
        problem, SequentialCPM(); native_profiles = (profile,),
        save_everystep = true,
    )
    @test integrator.capability_report.status ===
        PottsToolkit.CorePotts.BackendSPI.Supported
    @test !integrator.capability_report.exact_replay
    @test integrator.capability_report.evidence.conjunction === nothing
    @test integrator.u[:filter_output_state] === 0.0
    step!(integrator)
    @test integrator.u[:filter_output_state] ≈
        2(1 - exp(-0.25)) atol = 2e-8
end

struct NativeAuthoringFixtureSystem <: ModelingToolkitBase.AbstractSystem
    name::Symbol
end
struct NativeAuthoringAlgorithm end

Base.nameof(system::NativeAuthoringFixtureSystem) = system.name

@testset "per-cell native component authoring" begin
    @variables native_cell_input native_cell_output
    @variables potts_model_input potts_cell_input potts_cell_output
    model_input = ModelState(
        potts_model_input; name = :per_cell_model_input, initial = 1.0
    )
    cell_input = CellState(
        potts_cell_input; name = :per_cell_input, initial = 2.0
    )
    cell_output = CellState(
        potts_cell_output; name = :per_cell_output, initial = 0.0
    )
    source = NativeAuthoringFixtureSystem(:per_cell_source)
    lifecycle = PerCellNativeLifecycle(
        creation = PreserveNativeInitialization(),
        transition = Preserve(),
        division = CopyToDaughters(),
    )
    component = NativeComponent(
        source;
        name = :per_cell_component,
        family = ODEComponent(),
        scope = PerCell(),
        time = FixedPhysicalTime(0.0, 0.5),
        inputs = (
            NativeInput(native_cell_input, model_input; value_type = Float64),
            NativeInput(native_cell_output, cell_input; value_type = Float64),
        ),
        outputs = (
            NativeOutput(native_cell_output + native_cell_input, cell_output;
                value_type = Float64),
        ),
        lifecycle,
    )
    @test getfield(component, :scope) isa PerCell
    @test getfield(component, :lifecycle) === lifecycle

    @named named_per_cell = NativeComponent(
        source;
        family = DAEComponent(),
        scope = PerCell(),
        time = FixedPhysicalTime(0.0, 1.0),
        lifecycle = PerCellNativeLifecycle(
            creation = Unsupported(),
            transition = ResetTo((native_cell_output => 0.0,)),
            division = TransformDaughters(
                (native_cell_output => native_cell_output,),
                (native_cell_output => 0.0,),
            ),
        ),
    )
    @test nameof(named_per_cell) === :named_per_cell

    serial_profile = NativeSolveProfile(
        (:root, :component), NativeAuthoringAlgorithm()
    )
    @test serial_profile.execution isa SerialNativeExecution
    batched_profile = NativeSolveProfile(
        (:root, :component),
        NativeAuthoringAlgorithm();
        execution = BatchedNativeExecution(8),
    )
    @test batched_profile.execution.width == 8
    @test_throws ArgumentError BatchedNativeExecution(1)

    @test_throws ArgumentError NativeComponent(
        source;
        name = :implicit_lifecycle,
        family = ODEComponent(),
        scope = PerCell(),
        time = FixedPhysicalTime(0.0, 1.0),
    )
    @test_throws ArgumentError NativeComponent(
        source;
        name = :global_cell_port,
        family = ODEComponent(),
        time = FixedPhysicalTime(0.0, 1.0),
        inputs = NativeInput(native_cell_input, cell_input; value_type = Float64),
    )
    @test_throws ArgumentError NativeComponent(
        source;
        name = :per_cell_model_output,
        family = ODEComponent(),
        scope = PerCell(),
        time = FixedPhysicalTime(0.0, 1.0),
        outputs = NativeOutput(native_cell_output, model_input; value_type = Float64),
        lifecycle,
    )
    @test_throws ArgumentError PerCellNativeLifecycle(
        creation = Preserve(), transition = Preserve(),
        division = CopyToDaughters(),
    )
    @test_throws ArgumentError PerCellNativeLifecycle(
        creation = PreserveNativeInitialization(), transition = RetireTo(0.0),
        division = CopyToDaughters(),
    )
    @test_throws ArgumentError PerCellNativeLifecycle(
        creation = PreserveNativeInitialization(), transition = Preserve(),
        division = RedrawDaughters(Normal(0.0, 1.0), Normal(0.0, 1.0);
            parent_draw = :parent, daughter_draw = :daughter),
    )
end

@testset "native component authoring and composition" begin
    @variables native_fixture_input native_fixture_output
    @variables potts_fixture_input potts_fixture_output
    input_state = ModelState(
        potts_fixture_input; name = :native_fixture_input_state, initial = 0.0
    )
    output_state = ModelState(
        potts_fixture_output; name = :native_fixture_output_state, initial = 0.0
    )
    native_source_system = NativeAuthoringFixtureSystem(:native_fixture_source)
    component = NativeComponent(
        native_source_system;
        name = :native_fixture,
        family = ODEComponent(),
        time = FixedPhysicalTime(1.0, 0.25),
        cadence = Every(2),
        inputs = (
            NativeInput(
                native_fixture_input, input_state; value_type = Float64
            ),
        ),
        outputs = (
            NativeOutput(
                native_fixture_output, output_state; value_type = Float64
            ),
        ),
    )
    @named named_component = NativeComponent(
        native_source_system;
        family = ODEComponent(),
        time = FixedPhysicalTime(0.0, 0.25),
    )
    @test nameof(named_component) === :named_component
    @test PottsToolkit.native_source(named_component) === native_source_system
    source = PottsSystem(
        name = :native_authoring,
        statements = StatementSet((input_state, output_state)),
        unknowns = [potts_fixture_input, potts_fixture_output],
        native_components = (component,),
    )

    @test only(native_components(source)) === component
    @test PottsToolkit.native_source(component) === native_source_system
    @test PottsToolkit.native_cadence_stride(component) == 2
    @test native_time_interval(component, 2) == (1.0, 1.5)
    @test_throws ArgumentError scheduled_native_components(source)

    child = PottsSystem(name = :potts_child)
    composed = compose(source, [child])
    @test only(ModelingToolkitBase.get_systems(composed)) === child
    @test only(native_components(composed)) === component

    root = PottsSystem(name = :native_root, systems = (source,))
    flattened = flatten(root)
    @test isempty(ModelingToolkitBase.get_systems(flattened))
    flattened_component = only(native_components(flattened))
    @test nameof(flattened_component) === :native_authoring₊native_fixture
    @test PottsToolkit.native_source(flattened_component) === native_source_system
    @test statement_id(PottsToolkit.potts_endpoint(
        only(PottsToolkit.native_inputs(flattened_component))
    )) == StatementID(:native_authoring₊native_fixture_input_state)

    base_component = NativeComponent(
        native_source_system;
        name = :native_base_component,
        family = ODEComponent(),
        time = FixedPhysicalTime(0.0, 1.0),
    )
    base = PottsSystem(
        name = :native_base, native_components = (base_component,)
    )
    derived = extend(source, base; name = :native_derived)
    @test native_components(derived) == (base_component, component)

    @test_throws ArgumentError PottsSystem(
        name = :duplicate_native_names,
        native_components = (component, component),
    )
    colliding_child = PottsSystem(name = :native_fixture)
    @test_throws ArgumentError PottsSystem(
        name = :native_name_collision,
        systems = (colliding_child,),
        native_components = (component,),
    )
end

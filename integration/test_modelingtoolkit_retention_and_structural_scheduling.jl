@testset "native ModelingToolkit retention and structural scheduling" begin
    @independent_variables native_t
    @variables native_x(native_t) = 1.0 native_drive(native_t)
    @variables native_readout(native_t)
    @parameters native_rate = 0.25
    native_differential = ModelingToolkitBase.Differential(native_t)
    @named native_source = ModelingToolkit.ODESystem(
        [native_differential(native_x) ~
            -native_rate * native_x + native_drive],
        native_t,
        [native_x, native_drive],
        [native_rate],
        initialization_eqs = [native_x ~ 1.0],
        observed = [native_readout ~ 2native_x],
        continuous_events = [native_x ~ 0.5],
    )
    source_initial_conditions = ModelingToolkitBase.get_initial_conditions(
        native_source
    )
    source_equations = ModelingToolkitBase.equations(native_source)
    source_initialization = ModelingToolkitBase.initialization_equations(
        native_source
    )
    source_observed = ModelingToolkitBase.get_observed(native_source)
    source_events = ModelingToolkitBase.continuous_events(native_source)

    @variables coupled_drive coupled_output
    drive_state = ModelState(
        coupled_drive; name = :native_drive_state, initial = 0.0
    )
    output_state = ModelState(
        coupled_output; name = :native_output_state, initial = 1.0
    )
    component = NativeComponent(
        native_source;
        name = :native_decay,
        family = ODEComponent(),
        scope = Global(),
        time = FixedPhysicalTime(0.0, 0.1),
        cadence = EveryMCS(),
        split = CPMThenComponents(),
        inputs = (
            NativeInput(native_drive, drive_state; value_type = Float64),
        ),
        outputs = (
            NativeOutput(native_x, output_state; value_type = Float64),
        ),
    )
    cell = CellKind(:native_cell; extinction = RetireAtZero())
    medium = MediumKind(:native_medium)
    source = PottsSystem(
        name = :native_coupled_model,
        statements = StatementSet((
            Lattice((4, 4)),
            cell,
            medium,
            drive_state,
            output_state,
            Protocol(Sweep(; temperature = 1.0); name = :main),
        )),
        unknowns = [coupled_drive, coupled_output],
        native_components = (component,),
    )

    @test native_source === PottsToolkit.native_source(component)
    @test only(native_components(source)) === component
    @test isempty(ModelingToolkitBase.get_systems(source))

    completed = complete(source)
    completed_native = only(getfield(completed, :completion).native_components)
    @test PottsToolkit.native_component_path(completed_native) ==
        (:native_coupled_model, :native_decay)
    @test completed_native.declaration === component
    @test all(endpoint ->
        PottsToolkit.potts_endpoint(endpoint) isa
            PottsToolkit.QualifiedStatementID,
        completed_native.endpoints,
    )
    @test Set(endpoint.potts_kind for endpoint in completed_native.endpoints) ==
        Set((:ModelState,))
    @test length(string(completed_native.source_fingerprint)) == 64

    scheduled = mtkcompile(completed)
    compiled = only(scheduled_native_components(scheduled))
    scheduled_data = getfield(scheduled, :completion).scheduled
    @test PottsToolkit.native_component_path(compiled) ==
        (:native_coupled_model, :native_decay)
    @test PottsToolkit.native_original_system(compiled) === native_source
    @test PottsToolkit.native_scheduled_system(compiled) !== native_source
    @test ModelingToolkitBase.get_isscheduled(
        PottsToolkit.native_scheduled_system(compiled)
    )
    @test compiled.original_fingerprint == completed_native.source_fingerprint
    @test length(string(compiled.scheduled_fingerprint)) == 64
    @test only(scheduled_data.native_components) === compiled
    @test only(scheduled_data.provenance.native_components).path ==
        (:native_coupled_model, :native_decay)
    @test only(scheduled_data.capability_requirements.native_components).family ===
        :ODEComponent

    @test ModelingToolkitBase.equations(native_source) === source_equations ||
        ModelingToolkitBase.equations(native_source) == source_equations
    @test isequal(
        ModelingToolkitBase.get_initial_conditions(native_source),
        source_initial_conditions,
    )
    @test ModelingToolkitBase.initialization_equations(native_source) ==
        source_initialization
    @test ModelingToolkitBase.get_observed(native_source) == source_observed
    @test ModelingToolkitBase.continuous_events(native_source) == source_events
    @test !isempty(ModelingToolkitBase.initialization_equations(
        PottsToolkit.native_scheduled_system(compiled)
    ))
    @test !isempty(ModelingToolkitBase.get_observed(
        PottsToolkit.native_scheduled_system(compiled)
    ))
    @test !isempty(ModelingToolkitBase.continuous_events(
        PottsToolkit.native_scheduled_system(compiled)
    ))
    @test PottsToolkit.native_index_provider(compiled) ===
        PottsToolkit.native_scheduled_system(compiled)
    @test PottsToolkit.native_problem_constructor(compiled) ===
        PottsToolkit.SciMLBase.ODEProblem
    endpoint_variables = map(
        PottsToolkit.native_variable,
        PottsToolkit.native_coupling_endpoints(compiled),
    )
    @test all(isequal.(endpoint_variables, (native_drive, native_x)))
    @test !isdefined(PottsToolkit, :EquationComponent) ||
        isempty(methods(PottsToolkit.EquationComponent))

    missing_component = NativeComponent(
        native_source;
        name = :missing_endpoint_component,
        family = ODEComponent(),
        time = FixedPhysicalTime(0.0, 0.1),
        inputs = (
            NativeInput(
                native_drive,
                ModelState(:not_in_model; initial = 0.0);
                value_type = Float64,
            ),
        ),
    )
    missing_system = PottsSystem(
        name = :missing_endpoint_model,
        statements = getfield(source, :statements),
        unknowns = getfield(source, :unknowns),
        native_components = (missing_component,),
    )
    missing_error = try
        complete(missing_system)
        nothing
    catch caught
        caught
    end
    @test missing_error isa ArgumentError
    @test occursin("does not resolve", sprint(showerror, missing_error))

    @variables ambiguous_potts_state
    ambiguous_endpoint = ModelState(
        ambiguous_potts_state; name = :shared_native_endpoint, initial = 0.0
    )
    ambiguous_component = NativeComponent(
        native_source;
        name = :ambiguous_endpoint_component,
        family = ODEComponent(),
        time = FixedPhysicalTime(0.0, 0.1),
        inputs = (
            NativeInput(
                native_drive, ambiguous_endpoint; value_type = Float64
            ),
        ),
    )
    ambiguous_system = PottsSystem(
        name = :ambiguous_endpoint_model,
        statements = getfield(source, :statements),
        unknowns = getfield(source, :unknowns),
        systems = (
            PottsSystem(
                name = :first_state_owner,
                statements = StatementSet(ambiguous_endpoint),
                unknowns = [ambiguous_potts_state],
            ),
            PottsSystem(
                name = :second_state_owner,
                statements = StatementSet(ambiguous_endpoint),
                unknowns = [ambiguous_potts_state],
            ),
        ),
        native_components = (ambiguous_component,),
    )
    ambiguous_error = try
        complete(ambiguous_system)
        nothing
    catch caught
        caught
    end
    @test ambiguous_error isa ArgumentError
    @test occursin("is ambiguous across", sprint(showerror, ambiguous_error))

    second_component = NativeComponent(
        native_source;
        name = :second_native_writer,
        family = ODEComponent(),
        time = FixedPhysicalTime(0.0, 0.1),
        outputs = (
            NativeOutput(native_x, output_state; value_type = Float64),
        ),
    )
    duplicate_writer_system = PottsSystem(
        name = :duplicate_writer_model,
        statements = getfield(source, :statements),
        unknowns = getfield(source, :unknowns),
        native_components = (component, second_component),
    )
    writer_error = try
        complete(duplicate_writer_system)
        nothing
    catch caught
        caught
    end
    @test writer_error isa ArgumentError
    @test occursin("multiple native writers", sprint(showerror, writer_error))
end

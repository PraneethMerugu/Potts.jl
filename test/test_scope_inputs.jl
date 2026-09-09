struct ScopeNativeInputFixture <: ModelingToolkitBase.AbstractSystem
    name::Symbol
end
Base.nameof(system::ScopeNativeInputFixture) = getfield(system, :name)
Potts.native_source_fingerprint(system::ScopeNativeInputFixture) =
    Potts.NativeSourceFingerprint(Potts._sha256_hex(:scope_native_input_fixture, nameof(system)))

@testset "scoped processes resolve parent inputs and native-backed state" begin
    @variables native_input native_output input_value output_value incoming_output result_value
    @parameters forcing = 2.0 incoming_forcing
    kind = CellKind(:cell; extinction = RetireAtZero())
    input_state = ModelState(input_value; initial = 1.0)
    output_state = ModelState(output_value; initial = 0.0)
    native = NativeComponent(
        ScopeNativeInputFixture(:native_source); name = :native,
        family = ODEComponent(), time = FixedPhysicalTime(0.0, 0.25),
        inputs = (NativeInput(native_input, input_state; value_type = Float64),),
        outputs = (NativeOutput(native_output + native_input, output_state; value_type = Float64),),
    )
    consumer = PottsSystem(
        name = :consumer,
        statements = scoped(cells(kind), :reader) do anchor
            StatementSet(
                (
                    CellState(result_value; initial = 0.0, retirement = RetireTo(0.0)),
                    Synchronous(:read, Assign(result_value, incoming_forcing + incoming_output)),
                )
            )
        end,
        imports = (incoming_forcing => ComponentReference((), forcing), incoming_output => ComponentReference((), output_state)),
        unknowns = (result_value,),
    )
    parent = PottsSystem(
        name = :parent, statements = StatementSet((kind, input_state, output_state)),
        unknowns = (input_value, output_value), parameters = (forcing,),
        native_components = (native,), systems = (consumer,),
    )
    completed = complete(parent)
    @test length(unknowns(completed)) == 3
    @test length(parameters(completed)) == 1
    @test length(native_components(completed)) == 1
    @test !any(variable -> isequal(variable, incoming_output), unknowns(completed))
end

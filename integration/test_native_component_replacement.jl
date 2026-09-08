using OrdinaryDiffEqTsit5: Tsit5
using SciMLBase
include(joinpath(@__DIR__, "..", "examples", "native_component_replacement.jl"))

function native_component_test_integrator(source)
    scheduled = ModelingToolkitBase.mtkcompile(source)
    paths = unique(item.component_path for item in inspect(scheduled, ExternalIO()))
    initial = PottsInitialState(
        ownership = LabelledCells(
            ones(Int, 2, 2);
            cells = [CellKind(:cell; extinction = RetireAtZero())],
            medium = MediumKind(:medium),
        ),
        native = Tuple(NativeOperatingPoint(path) for path in paths),
    )
    problem = PottsProblem(scheduled, initial, (0, 2); seed = 17)
    profiles = Tuple(NativeSolveProfile(path, Tsit5(); adaptive = false, dt = 0.01) for path in paths)
    return init(problem, SequentialCPM(); native_profiles = profiles, save_everystep = true)
end

@testset "native output imports reconnect to one surviving state owner" begin
    @independent_variables output_t
    @variables native_output(output_t) = 0.0
    @named native_source = ModelingToolkit.System(
        [ModelingToolkitBase.Differential(output_t)(native_output) ~ 1.0], output_t
    )
    @variables incoming amount response
    owner = ModelState(amount; initial = 0.0)
    owner_source = PottsSystem(name = :owner, statements = StatementSet(owner))
    alias = ModelState(incoming; initial = 99.0)
    native = NativeComponent(
        native_source; name = :ode, family = ODEComponent(),
        time = FixedPhysicalTime(0.0, 0.1),
        outputs = (NativeOutput(native_output, alias; value_type = Float64),),
    )
    writer = PottsSystem(
        name = :writer, native_components = (native,),
        imports = (incoming => ComponentReference((:owner,), owner),),
    )
    root_statements = StatementSet(
        (
            Lattice((2, 2); boundary = Closed()),
            CellKind(:cell; extinction = RetireAtZero()),
            MediumKind(:medium),
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )
    )
    source = PottsSystem(name = :output_import, statements = root_statements, systems = (owner_source, writer))
    replacement = ModelState(response; initial = 0.0)
    replacement_source = PottsSystem(name = :owner, statements = StatementSet(replacement))
    @test_throws ArgumentError replace_component(source, (:owner,) => replacement_source)
    replaced = replace_component(
        source, (:owner,) => replacement_source;
        reconnect = (ComponentReference((:owner,), owner) => ComponentReference((:owner,), replacement),),
    )
    integrator = native_component_test_integrator(replaced)
    @test integrator.u.owner₊response == 0.0
    step!(integrator)
    step!(integrator)
    @test integrator.u.owner₊response ≈ 0.2 atol = 1.0e-10
    @test length(inspect(ModelingToolkitBase.mtkcompile(replaced), StateSchema()).states) == 1
    duplicate = PottsSystem(
        name = :duplicate, native_components = (native,),
        imports = (incoming => ComponentReference((:owner,), owner),),
    )
    @test_throws ArgumentError ModelingToolkitBase.complete(ModelingToolkitBase.compose(source, [duplicate]))

    @parameters not_a_state = 1.0
    wrong_kind = PottsSystem(
        name = :wrong_kind, statements = root_statements, parameters = (not_a_state,),
        systems = (
            PottsSystem(
                name = :writer, native_components = (native,),
                imports = (incoming => ComponentReference((), not_a_state),),
            ),
        ),
    )
    @test_throws ArgumentError ModelingToolkitBase.complete(wrong_kind)

    # A direct port bound to a particular declaration keeps that owner even
    # when the native component also contains the same variable spelling.
    direct_owner = ModelState(amount; initial = 2.0)
    local_state = ModelState(amount; initial = 3.0)
    direct_native = NativeComponent(
        native_source; name = :ode, family = ODEComponent(),
        time = FixedPhysicalTime(0.0, 0.1),
        outputs = (NativeOutput(native_output, direct_owner; value_type = Float64),),
    )
    direct = PottsSystem(
        name = :direct, statements = StatementSet((root_statements..., direct_owner)),
        systems = (PottsSystem(name = :child, statements = StatementSet(local_state), native_components = (direct_native,)),),
    )
    direct_binding = only(inspect(ModelingToolkitBase.complete(direct), ExternalIO()))
    @test direct_binding.potts_identity.path == (:direct,)

    direct_writer = PottsSystem(
        name = :direct_writer,
        native_components = (
            NativeComponent(
                native_source; name = :ode, family = ODEComponent(),
                time = FixedPhysicalTime(0.0, 0.1),
                outputs = (NativeOutput(native_output, owner; value_type = Float64),),
            ),
        ),
    )
    directly_connected = PottsSystem(
        name = :directly_connected, statements = root_statements,
        systems = (owner_source, direct_writer),
    )
    same_name = PottsSystem(name = :owner, statements = StatementSet(ModelState(amount; initial = 3.0)))
    dangling_error = try
        replace_component(directly_connected, (:owner,) => same_name)
        nothing
    catch error
        error
    end
    @test dangling_error isa ArgumentError
    @test occursin("explicit component imports", sprint(showerror, dangling_error))
end

@testset "nested native imports and repeated namespace names keep distinct owners" begin
    @variables forcing
    owner = ModelState(forcing; initial = 2.0)
    component = NativeComponentReplacementExample.accumulator(:left, forcing, ComponentReference((), owner))
    root_statements = StatementSet(
        (
            Lattice((2, 2); boundary = Closed()),
            CellKind(:cell; extinction = RetireAtZero()),
            MediumKind(:medium), owner,
            Protocol(Sweep(; temperature = 0.0); name = :main),
        )
    )
    source = PottsSystem(name = :left, statements = root_statements, systems = (component.source,))
    completed = ModelingToolkitBase.complete(source)
    child = only(ModelingToolkitBase.get_systems(completed))
    bindings = inspect(child, ExternalIO())
    @test only(filter(item -> item.direction === :input, bindings)).potts_identity.path == (:left,)
    @test only(filter(item -> item.direction === :output, bindings)).potts_identity.path == (:left, :left)
    @test_throws ArgumentError ModelingToolkitBase.mtkcompile(child)
    integrator = native_component_test_integrator(source)
    step!(integrator)
    step!(integrator)
    @test integrator.u.forcing == 2.0
    @test integrator.u.left₊forcing ≈ 0.4 atol = 1.0e-10

    nested = PottsSystem(
        name = :nested_root,
        statements = root_statements,
        systems = (PottsSystem(name = :group, systems = (component.source,)),),
    )
    nested_integrator = native_component_test_integrator(nested)
    step!(nested_integrator)
    step!(nested_integrator)
    @test nested_integrator.u.group₊left₊forcing ≈ 0.4 atol = 1.0e-10
end

@testset "native component imports preserve shared ownership and native identity" begin
    example = NativeComponentReplacementExample.shared_input_model()
    completed = ModelingToolkitBase.complete(example.source)
    @test ModelingToolkitBase.complete(completed) === completed
    endpoints = inspect(completed, ExternalIO())
    forcing = filter(item -> item.direction === :input && item.component_path[end - 1] in (:left, :right), endpoints)
    @test length(forcing) == 2
    @test all(item -> item.potts_identity == Potts.QualifiedStatementID((:native_shared,), statement_id(example.forcing_state)), forcing)
    child = first(ModelingToolkitBase.get_systems(completed))
    child_input = only(filter(item -> item.direction === :input, inspect(child, ExternalIO())))
    @test child_input.potts_identity == first(forcing).potts_identity
    standalone_error = try
        ModelingToolkitBase.mtkcompile(child)
        nothing
    catch error
        error
    end
    @test standalone_error isa ArgumentError
    @test occursin("containing PottsSystem", sprint(showerror, standalone_error))

    scheduled = ModelingToolkitBase.mtkcompile(completed)
    left_native = only(filter(component -> Potts.native_component_path(component) == (:native_shared, :left, :ode), Potts.scheduled_native_components(scheduled)))
    @test Potts.native_original_system(left_native) === example.left.equations
    @test isequal(Potts.native_variable(first(Potts.native_coupling_endpoints(left_native))), example.left.drive)
    @test length(inspect(scheduled, StateSchema()).states) == 4
    integrator = native_component_test_integrator(example.source)
    step!(integrator)
    @test native_value(integrator, (:native_shared, :left, :ode), example.left.x) ≈ 0.2 atol = 1.0e-10
    @test integrator.u.reader₊total ≈ 0.0 atol = 1.0e-10
    step!(integrator)
    @test integrator.u.left₊amount ≈ 0.4 atol = 1.0e-10
    @test integrator.u.right₊amount ≈ 1.2 atol = 1.0e-10
    # Native islands sample the same held pre-publication boundary, not one
    # another's partially published values during their shared advancement.
    @test integrator.u.reader₊total ≈ 0.02 atol = 1.0e-10
end

@testset "native subtree replacement reconnects ports and removes owned equations" begin
    example = NativeComponentReplacementExample.replaced_input_model()
    integrator = native_component_test_integrator(example.replaced)
    step!(integrator)
    step!(integrator)
    @test integrator.u.left₊response ≈ 2.0 atol = 1.0e-10
    @test integrator.u.right₊amount ≈ 1.2 atol = 1.0e-10
    @test integrator.u.reader₊total ≈ 0.1 atol = 1.0e-10
    @test native_value(integrator, (:native_shared, :left, :ode), example.replacement.x) ≈ 2.0 atol = 1.0e-10
    scheduled = ModelingToolkitBase.mtkcompile(example.replaced)
    left_native = only(filter(component -> Potts.native_component_path(component) == (:native_shared, :left, :ode), Potts.scheduled_native_components(scheduled)))
    @test Potts.native_original_system(left_native) === example.replacement.equations
    @test !any(item -> item.potts_identity.local_id == statement_id(example.original.left.state) && item.potts_identity.path == (:native_shared, :left), inspect(scheduled, ExternalIO()))
    @test_throws ArgumentError replace_component(example.original.source, (:left,) => example.replacement.source)
    @variables missing
    bad = NativeComponentReplacementExample.accumulator(:bad, missing, ComponentReference((:absent,), missing))
    @test_throws ArgumentError ModelingToolkitBase.complete(ModelingToolkitBase.compose(example.original.source, [bad.source]))
    original = native_component_test_integrator(example.original.source)
    step!(original)
    step!(original)
    @test original.u.left₊amount ≈ 0.4 atol = 1.0e-10
end

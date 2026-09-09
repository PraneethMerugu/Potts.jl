include(joinpath(@__DIR__, "..", "examples", "component_replacement.jl"))

@testset "completed child ownership retains its enclosing qualification" begin
    @variables amount
    @parameters increment = 1.0
    source = PottsSystem(
        name = :unit,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed()),
                CellKind(:cell; extinction = RetireAtZero()),
                MediumKind(:medium),
                ModelState(amount; initial = 0.0),
                Synchronous(:advance, Assign(amount, amount + increment)),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ),
        parameters = (increment,), unknowns = (amount,),
        inputs = (increment,), outputs = (amount,),
    )
    independent = complete(source)
    parent = complete(PottsSystem(name = :enclosing, systems = (source,)))
    contextual = only(ModelingToolkitBase.get_systems(parent))
    @test all(record -> record.identity.path == (:unit,), inspect(independent, Statements()))
    @test all(record -> record.identity.path == (:enclosing, :unit), inspect(contextual, Statements()))
    @test complete(contextual) === contextual
    @test isequal(only(parameters(contextual)), ModelingToolkitBase.renamespace(:unit, increment))
    scheduled = mtkcompile(contextual)
    for accessor in (
            parameters, unknowns, ModelingToolkitBase.inputs, ModelingToolkitBase.outputs,
            equations, ModelingToolkitBase.observed, initial_conditions,
        )
        @test isequal(accessor(scheduled), accessor(contextual))
    end
    initial = PottsInitialState(
        ownership = LabelledCells(
            ones(Int, 2, 2);
            cells = [CellKind(:cell; extinction = RetireAtZero())],
            medium = MediumKind(:medium),
        )
    )
    independent_solution = solve(PottsProblem(independent, initial, (0, 2); seed = 17), SequentialCPM())
    contextual_solution = solve(
        PottsProblem(
            contextual, initial, (0, 2); seed = 17,
            p = (only(parameters(contextual)) => 3.0,),
        ), SequentialCPM()
    )
    @test independent_solution.u[end][:amount] == 2.0
    @test contextual_solution.u[end][:unit₊amount] == 6.0
end

@testset "completed symbolic getters share the contextual source coordinate system" begin
    @variables x y
    @parameters k = 2.0
    child = PottsSystem(
        name = :child,
        statements = StatementSet((ModelState(x; initial = 0.0), Observation(:sample, x))),
        equations = (x ~ k,), unknowns = (x,), parameters = (k, ModelingToolkitBase.Initial(x)),
        inputs = (k,), outputs = (x,), observed = (y ~ x + k,),
        initial_conditions = Dict(x => k),
    )
    independent = complete(child)
    parent = complete(PottsSystem(name = :parent, systems = (child,)))
    contextual = only(ModelingToolkitBase.get_systems(parent))
    qualified_x = ModelingToolkitBase.renamespace(:child, x)
    qualified_y = ModelingToolkitBase.renamespace(:child, y)
    qualified_k = ModelingToolkitBase.renamespace(:child, k)
    for system in (contextual, parent)
        @test isequal(unknowns(system), [qualified_x])
        @test isequal(parameters(system), [qualified_k])
        @test isequal(ModelingToolkitBase.inputs(system), [qualified_k])
        @test isequal(ModelingToolkitBase.outputs(system), [qualified_x])
        @test equations(system) == [qualified_x ~ qualified_k]
        @test ModelingToolkitBase.observed(system) == [qualified_y ~ qualified_x + qualified_k]
        @test isequal(initial_conditions(system), Dict(qualified_x => qualified_k))
        @test ModelingToolkitBase.getdefault(only(parameters(system))) == 2.0
        @test isequal(parameters(system; initial_parameters = true), [qualified_k, ModelingToolkitBase.Initial(qualified_x)])
    end
    for system in (child, independent)
        @test isequal(unknowns(system), [x])
        @test isequal(parameters(system), [k])
        @test isequal(ModelingToolkitBase.inputs(system), [k])
        @test isequal(ModelingToolkitBase.outputs(system), [x])
        @test equations(system) == [x ~ k]
        @test ModelingToolkitBase.observed(system) == [y ~ x + k]
        @test isequal(initial_conditions(system), Dict(x => k))
        @test isequal(parameters(system; initial_parameters = true), [k, ModelingToolkitBase.Initial(x)])
    end
end

@testset "shared imported IO is unique and parent initial conditions take precedence" begin
    @variables x imported_parameter imported_state
    @parameters k = 2.0
    state = ModelState(x; initial = 0.0)
    function consumer(name)
        return PottsSystem(
            name = name,
            inputs = (imported_parameter, imported_state),
            imports = (
                imported_parameter => ComponentReference((), k),
                imported_state => ComponentReference((), state),
            ),
            initial_conditions = Dict(imported_state => 99.0),
        )
    end
    source = PottsSystem(
        name = :shared_io, statements = StatementSet(state),
        parameters = (k,), unknowns = (x,), inputs = (k,), outputs = (x,),
        initial_conditions = Dict(x => 4.0),
        systems = (consumer(:first), consumer(:second)),
    )
    completed = complete(source)
    @test isequal(parameters(completed), [k])
    @test isequal(unknowns(completed), [x])
    @test isequal(ModelingToolkitBase.inputs(completed), [k, x])
    @test isequal(ModelingToolkitBase.outputs(completed), [x])
    @test isequal(initial_conditions(completed), Dict(x => 4.0))
    for child in ModelingToolkitBase.get_systems(completed)
        @test isempty(parameters(child))
        @test isempty(unknowns(child))
        @test isequal(ModelingToolkitBase.inputs(child), [k, x])
        @test isequal(initial_conditions(child), Dict(x => 99.0))
    end
end

function component_test_problem(source; p = ())
    initial = PottsInitialState(
        ownership = LabelledCells(
            ones(Int, 2, 2);
            cells = [CellKind(:cell; extinction = RetireAtZero())],
            medium = MediumKind(:medium),
        )
    )
    return PottsProblem(source, initial, (0, 2); p, seed = 17)
end

@testset "explicit component imports share an owner, not state instances ($algorithm)" for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
    example = ComponentReplacementExample.shared_input_model()
    completed = complete(example.source)
    @test complete(completed) === completed
    @test length(parameters(completed)) == 1
    @test length(parameters(complete(example.source))) == 1
    @test isequal(only(parameters(completed)), example.forcing)
    @test length(inspect(mtkcompile(completed), StateSchema()).states) == 2

    solution = solve(component_test_problem(example.source), algorithm; saveat = 0:2)
    @test solution.u[end][:left₊amount] == 4.0
    @test solution.u[end][:right₊amount] == 12.0
    changed = solve(
        component_test_problem(example.source; p = (example.forcing => 3.0,)),
        algorithm; saveat = 0:2
    )
    @test changed.u[end][:left₊amount] == 6.0
    @test changed.u[end][:right₊amount] == 18.0
    flattened = solve(component_test_problem(flatten(example.source)), algorithm; saveat = 0:2)
    @test flattened.u[end][:left₊amount] == solution.u[end][:left₊amount]
    @test flattened.u[end][:right₊amount] == solution.u[end][:right₊amount]
    @test_throws ArgumentError Symbolics.substitute(example.source, Dict(example.forcing => 3.0))

    # Two readers see the same held, independently owned state. There is only
    # one storage declaration for the producer, not a local copy per import.
    @variables total
    output = ComponentReference((:left,), example.left.state)
    first_reader = ComponentReplacementExample.accumulator(:first_reader, total, output)
    second_reader = ComponentReplacementExample.accumulator(:second_reader, total, output)
    readers = compose(example.source, [first_reader.source, second_reader.source])
    observed = solve(component_test_problem(readers), algorithm; saveat = 0:2)
    @test observed.u[end][:first_reader₊total] == 2.0
    @test observed.u[end][:second_reader₊total] == 2.0
    @test length(inspect(mtkcompile(readers), StateSchema()).states) == 4

    nested = compose(
        example.source, [
            PottsSystem(
                name = :nested,
                systems = (ComponentReplacementExample.accumulator(:reader, total, output).source,)
            ),
        ]
    )
    nested_solution = solve(component_test_problem(nested), algorithm; saveat = 0:2)
    @test nested_solution.u[end][:nested₊reader₊total] == 2.0
    @test length(parameters(mtkcompile(nested))) == 1
end

@testset "replacement reconnects output identity and retains external inputs ($algorithm)" for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
    example = ComponentReplacementExample.replaced_input_model()
    original = solve(component_test_problem(example.source), algorithm; saveat = 0:2)
    replaced = solve(component_test_problem(example.replaced), algorithm; saveat = 0:2)
    @test original.u[end][:left₊amount] == 4.0
    @test original.u[end][:reader₊total] == 2.0
    @test replaced.u[end][:left₊response] == 20.0
    @test replaced.u[end][:reader₊total] == 10.0
    @test replaced.u[end][:right₊amount] == 12.0
    @test_throws Potts.PottsUnknownIdentityError replaced.u[end][:left₊amount]
    @test length(parameters(mtkcompile(example.replaced))) == 1
    @test !iscomplete(example.replaced)
    @test_throws ArgumentError replace_component(
        complete(example.source),
        (:left,) => example.replacement.source
    )

    # Reusing an output's spelling is not permission to reconnect its consumers.
    original_example = ComponentReplacementExample.shared_input_model()
    same_name = original_example.left.source
    @test_throws ArgumentError replace_component(example.source, (:left,) => same_name)
    @test_throws ArgumentError replace_component(example.source, (:missing,) => same_name)
    @test_throws ArgumentError replace_component(example.source, () => same_name)
end

@testset "component binding failures reject ambiguous ownership" begin
    @parameters shared = 2.0
    @variables input value output
    reference = ComponentReference((), shared)
    @test_throws ArgumentError ComponentReference((), :shared)
    @test_throws ArgumentError ComponentReference((), CellKind(:not_a_symbolic_state))
    @test_throws ArgumentError ComponentReference((), shared + 1)
    @test_throws ArgumentError PottsSystem(
        name = :invalid,
        imports = (input + value => reference,)
    )
    @test_throws ArgumentError PottsSystem(
        name = :duplicate,
        imports = (input => reference, input => reference)
    )
    owned_alias = PottsSystem(name = :child, parameters = (input,), imports = (input => reference,))
    @test_throws ArgumentError complete(
        PottsSystem(
            name = :root,
            parameters = (shared,), systems = (owned_alias,)
        )
    )
    unresolved = PottsSystem(
        name = :child,
        imports = (input => ComponentReference((:missing,), shared),)
    )
    @test_throws ArgumentError complete(
        PottsSystem(
            name = :root,
            parameters = (shared,), systems = (unresolved,)
        )
    )

    state = ModelState(value; initial = 1.0)
    unrelated = ModelState(value; initial = 9.0)
    bad_reader = PottsSystem(
        name = :reader,
        imports = (input => ComponentReference((:owner,), unrelated),)
    )
    @test_throws ArgumentError complete(
        PottsSystem(
            name = :root,
            systems = (PottsSystem(name = :owner, statements = StatementSet(state)), bad_reader)
        )
    )

    example = ComponentReplacementExample.shared_input_model()
    # An imported write resolves to the same canonical target as its owner's
    # write; a second namespace cannot hide a duplicate synchronous writer.
    writer = PottsSystem(
        name = :writer,
        statements = StatementSet(Synchronous(:write, Assign(input, 0.0))),
        imports = (input => ComponentReference((:left,), example.left.state),)
    )
    @test_throws Potts.PottsValidationError complete(compose(example.source, [writer]))
end

@testset "reconnections reject changed contracts and unowned connections" begin
    @variables original_value replacement_value incoming mirror amount
    original_state = ModelState(original_value; initial = 1.0u"m")
    replacement_state = ModelState(replacement_value; initial = 1.0u"s")
    old_reference = ComponentReference((:producer,), original_state)
    producer = PottsSystem(name = :producer, statements = StatementSet(original_state))
    reader = PottsSystem(name = :reader, imports = (incoming => old_reference,), outputs = (incoming,))
    source = PottsSystem(name = :root, systems = (producer, reader))
    replacement = PottsSystem(name = :producer, statements = StatementSet(replacement_state))
    connection = old_reference => ComponentReference((:producer,), replacement_state)
    @test_throws ArgumentError replace_component(
        source, (:producer,) => replacement;
        reconnect = (connection,)
    )
    @test_throws ArgumentError replace_component(
        source, (:producer,) => replacement;
        reconnect = (connection, connection)
    )
    @test_throws ArgumentError replace_component(
        PottsSystem(name = :root, systems = (producer,)),
        (:producer,) => replacement; reconnect = (connection,)
    )

    example = ComponentReplacementExample.shared_input_model()
    external = ModelingToolkitBase.renamespace(:left, amount)
    implicit = PottsSystem(
        name = :implicit, statements = StatementSet(
            (
                ModelState(mirror; initial = 0.0),
                Synchronous(:copy_mirror, Assign(mirror, external)),
            )
        )
    )
    implicit_source = extend(implicit, example.source)
    @test_throws ArgumentError replace_component(implicit_source, (:left,) => example.left.source)
    @parameters retained_default = external
    for extra in (
            PottsSystem(name = :with_default, parameters = (retained_default,)),
            PottsSystem(name = :with_observation, observed = (mirror ~ external,)),
        )
        composed = extend(extra, example.source)
        error = try
            replace_component(composed, (:left,) => example.left.source)
            nothing
        catch caught
            caught
        end
        @test error isa ArgumentError
        @test occursin("explicit component imports", sprint(showerror, error))
    end
end

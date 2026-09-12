using StaticArrays
include(joinpath(@__DIR__, "fixtures", "product_fields.jl"))

@testset "product declarations expose fields without adding symbolic owners" begin
    @variables memory::NamedTuple{(:amount, :polarity, :nested, :core, :name), Tuple{Float64, SVector{2, Float64}, NamedTuple{(:enabled,), Tuple{Bool}}, Float64, Int}}
    declaration = ModelState(memory)
    @test propertynames(declaration) == (:amount, :polarity, :nested, :core, :name)
    @test Symbolics.symtype(Symbolics.unwrap(declaration.core)) === Float64
    @test Symbolics.symtype(Symbolics.unwrap(declaration.name)) === Int
    @test_throws r"no field" declaration.absent
    @test size(declaration.polarity) == (2,)
    for expression in (declaration.amount + 1, -declaration.polarity[2], declaration.nested.enabled)
        variables = Symbolics.get_variables(expression)
        @test length(variables) == 1
        @test isequal(Symbolics.unwrap(only(variables)), Symbolics.unwrap(memory))
        namespaced = ModelingToolkitBase.renamespace(:left, memory)
        changed = Symbolics.substitute(expression, Dict(memory => namespaced))
        @test Symbolics.symtype(Symbolics.unwrap(changed)) === Symbolics.symtype(Symbolics.unwrap(expression))
        @test isequal(Symbolics.unwrap(only(Symbolics.get_variables(changed))), Symbolics.unwrap(namespaced))
    end
    array_expression = Symbolics.substitute(
        declaration.polarity,
        Dict(memory => ModelingToolkitBase.renamespace(:right, memory))
    )
    @test size(array_expression) == (2,)
    @test Symbolics.symtype(Symbolics.unwrap(array_expression)) === SVector{2, Float64}
end

@testset "field projections share one closed operation schema" begin
    system, _ = _product_field_system()
    analysis = Potts._analyze_completed_system(complete(system))
    schemas = filter(schema -> schema.transfer.identity === :product_field, analysis.graph.operation_snapshot)
    @test length(schemas) == 1
    @test only(schemas).arity == 2
    @test only(schemas).callable === CorePotts.CompilerSPI.operation_callable(Val(:product_field), v"1.0.0")
    nodes = filter(node -> node.operation === :product_field, analysis.graph.nodes)
    @test length(nodes) >= 4
    @test any(node -> analysis.facts.result_type[node.identity] === Bool, nodes)
    @test any(node -> analysis.facts.shape[node.identity] == (2,), nodes)
end

@testset "imported product fields retain the whole state owner" begin
    @variables source_memory::NamedTuple{(:amount, :enabled), Tuple{Float64, Bool}}
    @variables borrowed::NamedTuple{(:amount, :enabled), Tuple{Float64, Bool}}
    @variables output
    owner = ModelState(source_memory; initial = (amount = 2.0, enabled = true))
    reference = ModelState(borrowed)
    reader = PottsSystem(
        name = :reader,
        statements = StatementSet(
            (
                ModelState(output; initial = 0.0),
                Synchronous(:read, Assign(output, reference.amount + 1)),
            )
        ),
        unknowns = (output,),
        imports = (borrowed => ComponentReference((), owner),)
    )
    system = PottsSystem(
        name = :root,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed()),
                CellKind(:cell; extinction = RetireAtZero()), MediumKind(:medium), owner,
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        ), systems = (reader,), unknowns = (source_memory,)
    )
    completed = complete(system)
    @test count(value -> isequal(value, source_memory), ModelingToolkitBase.unknowns(completed)) == 1
    analysis = Potts._analyze_completed_system(completed)
    @test count(node -> node.operation === :product_field, analysis.graph.nodes) == 1
    initial = PottsInitialState(ownership = LabelledCells(ones(Int, 2, 2); cells = [CellKind(:cell; extinction = RetireAtZero())], medium = MediumKind(:medium)))
    problem = PottsProblem(completed, initial, (0, 1); seed = 19)
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        result = solve(problem, algorithm; scalar_type = Float32)
        @test result.u[end][:reader₊output] === 3.0f0
        @test result.u[end][:source_memory] === (amount = 2.0f0, enabled = true)
    end
end

@testset "projected fields retain their own dimensions" begin
    @variables memory::NamedTuple{(:distance, :duration), Tuple{Float64, Float64}}
    @variables speed
    state = ModelState(memory; initial = (distance = 6.0u"m", duration = 2.0u"s"))
    system = PottsSystem(
        name = :dimensional_product,
        statements = StatementSet(
            (
                Lattice((2, 2); boundary = Closed()),
                CellKind(:cell; extinction = RetireAtZero()), MediumKind(:medium), state,
                ModelState(speed; initial = 0.0u"m/s"),
                Synchronous(:compute, Assign(speed, state.distance / state.duration)),
                Protocol(Sweep(; temperature = 0.0); name = :main),
            )
        )
    )
    analysis = Potts._analyze_completed_system(
        complete(
            system;
            reference_units = ReferenceUnits(length = 1.0u"m", time = 1.0u"s", speed = 1.0u"m/s")
        )
    )
    root = only(filter(root -> root.role === :effect_1_value, analysis.graph.roots))
    @test analysis.facts.units[root.node] == Potts._canonical_dimension(DynamicQuantities.dimension(1.0u"m/s"))
end

@testset "scalar and vector product fields execute in ordinary scheduled assignments" begin
    system, initial = _product_field_system()
    problem = PottsProblem(system, initial, (0, 2); seed = 17)
    for algorithm in (SequentialCPM(), CheckerboardSweepCPM())
        integrator = init(problem, algorithm; scalar_type = Float32)
        step!(integrator)
        _test_product_field_values(integrator)
        restored = init(problem, algorithm; scalar_type = Float32, checkpoint = checkpoint(integrator))
        step!(integrator)
        step!(restored)
        @test restored.t == integrator.t == 2
        for name in (:amount, :polarity, :memory)
            @test restored.u[name] == integrator.u[name]
        end
    end
end

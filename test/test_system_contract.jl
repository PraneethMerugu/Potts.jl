@testset "PottsSystem contract" begin
    @variables t x(t)
    @parameters k

    source_equations = [x ~ k]
    source_unknowns = [x]
    source_parameters = [k]
    source_initial = Dict(x => 1.0)
    site_anchor = SiteBinding(:site_anchor)
    @named child = PottsSystem(
        statements = StatementSet((
            CellKind(:cell),
            HamiltonianTerm(
                :energy;
                domain = sites(:lattice),
                anchor = site_anchor,
                expression = k * x,
            ),
        )),
        equations = source_equations,
        unknowns = source_unknowns,
        parameters = source_parameters,
        independent_variables = [t],
        inputs = [k],
        outputs = [x],
        initial_conditions = source_initial,
    )

    empty!(source_equations)
    empty!(source_unknowns)
    empty!(source_parameters)
    empty!(source_initial)
    @test equations(child) == [x ~ k]
    @test length(unknowns(child)) == 1 && isequal(only(unknowns(child)), x)
    @test length(parameters(child)) == 1 && isequal(only(parameters(child)), k)
    @test initial_conditions(child)[x] == 1.0
    @test isequal(child.x, ModelingToolkitBase.renamespace(child, x))
    @test !iscomplete(child)

    @named parent = PottsSystem()
    tree = compose(parent, [child])
    @test isequal(
        tree.child.x,
        ModelingToolkitBase.renamespace(
            parent, ModelingToolkitBase.renamespace(child, x)
        ),
    )
    @test nameof(tree) == :parent
    @test propertynames(tree) == [:child]
    qualified_tree = complete(tree)
    energy_record = only(filter(
        record -> record.identity.local_id == StatementID(:energy),
        inspect(qualified_tree, Statements()),
    ))
    @test any(isequal(
        ModelingToolkitBase.renamespace(:child, x)
    ), energy_record.reads)
    @test any(isequal(
        ModelingToolkitBase.renamespace(:child, k)
    ), energy_record.reads)
    @test !any(isequal(x), energy_record.reads)
    @test !any(isequal(k), energy_record.reads)
    @test !any(isequal(x), inspect(qualified_tree, Variables()))

    @test ModelingToolkitBase.equations(tree) == [
        ModelingToolkitBase.renamespace(:child, x) ~
        ModelingToolkitBase.renamespace(:child, k),
    ]
    @test isequal(ModelingToolkitBase.independent_variables(tree), [t])
    @test isequal(ModelingToolkitBase.inputs(tree), [
        ModelingToolkitBase.renamespace(:child, k),
    ])
    @test isequal(ModelingToolkitBase.outputs(tree), [
        ModelingToolkitBase.renamespace(:child, x),
    ])
    @test ModelingToolkitBase.initial_conditions(tree) == Dict(
        ModelingToolkitBase.renamespace(:child, x) => 1.0
    )

    flattened = flatten(tree)
    @test isempty(ModelingToolkitBase.get_systems(flattened))
    @test ModelingToolkitBase.equations(flattened) ==
          ModelingToolkitBase.equations(tree)
    @test isequal(
        ModelingToolkitBase.unknowns(flattened),
        ModelingToolkitBase.unknowns(tree),
    )
    @test isequal(
        ModelingToolkitBase.parameters(flattened),
        ModelingToolkitBase.parameters(tree),
    )
    @test isequal(
        ModelingToolkitBase.inputs(flattened),
        ModelingToolkitBase.inputs(tree),
    )
    @test isequal(
        ModelingToolkitBase.outputs(flattened),
        ModelingToolkitBase.outputs(tree),
    )
    @test ModelingToolkitBase.initial_conditions(flattened) ==
          ModelingToolkitBase.initial_conditions(tree)
    @test Symbol(statement_id(only(filter(
        statement -> statement isa HamiltonianTerm,
        statements(flattened),
    )))) == :child₊energy

    renamed = Symbolics.rename(child, :renamed)
    @test nameof(renamed) == :renamed
    @test nameof(child) == :child

    substituted = substitute(child, Dict(k => 2.0))
    @test equations(substituted) == [x ~ 2.0]
    @test isempty(ModelingToolkitBase.get_ps(substituted))
    @test occursin("2.0", sprint(show, statements(substituted)[2]))

    @named addition = PottsSystem(
        statements = StatementSet(MediumKind(:medium)),
        unknowns = [x],
        independent_variables = [t],
    )
    merged = extend(addition, child)
    @test length(statements(merged)) == 3
    @test length(unknowns(merged)) == 1 && isequal(only(unknowns(merged)), x)
    @test_throws ArgumentError extend(child, child)

    completed = complete(child)
    @test iscomplete(completed)
    @test complete(completed) === completed
    @test_throws ArgumentError compose(completed, PottsSystem[])
    @test_throws ArgumentError Symbolics.rename(completed, :other)
    @test_throws ArgumentError substitute(completed, Dict(k => 3.0))
end

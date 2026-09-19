@testset "ModelingToolkit assimilation" begin
    @independent_variables t
    @variables x(t)
    @parameters rate = 0.25
    equation = Differential(t)(x) ~ -rate * x
    @named external = ModelingToolkit.ODESystem(
        [equation], t, [x], [rate]
    )
    process = EquationProcess(
        :decay,
        [equation];
        writes = [x],
        solver = ExplicitEuler(),
        cadence = EveryMCS(),
    )
    component = EquationComponent(external, process; name = :decay_component)
    @test component isa PottsSystem
    @test !iscomplete(component)
    @test ModelingToolkitBase.equations(component) == [equation]
    @test all(isequal.(ModelingToolkitBase.unknowns(component), [x]))
    @test all(isequal.(ModelingToolkitBase.parameters(component), [rate]))
    @test only(statements(component)) isa EquationProcess

    completed_external = ModelingToolkit.complete(external)
    @test_throws ArgumentError EquationComponent(
        completed_external, process; name = :forbidden
    )

    @variables y(t)
    nested_equation = Differential(t)(y) ~ -rate * y
    @named inner = ModelingToolkit.ODESystem(
        [nested_equation], t, [y], [rate]
    )
    @named outer = ModelingToolkit.ODESystem(Equation[], t)
    hierarchy = ModelingToolkit.compose(outer, inner)
    hierarchical_process = EquationProcess(
        :hierarchical_decay,
        ModelingToolkitBase.equations(hierarchy);
        writes = [ModelingToolkitBase.renamespace(inner, y)],
        solver = ExplicitEuler(),
        cadence = EveryMCS(),
    )
    hierarchical = EquationComponent(
        hierarchy, hierarchical_process; name = :hierarchical_component
    )
    @test length(ModelingToolkitBase.get_systems(hierarchical)) == 1
    @test only(statements(hierarchical)) === hierarchical_process
    @test isempty(statements(only(ModelingToolkitBase.get_systems(hierarchical))))
    @test isequal(
        ModelingToolkitBase.equations(hierarchical),
        ModelingToolkitBase.equations(hierarchy),
    )

    @variables z(t)
    unrelated = Differential(t)(z) ~ -z
    @test_throws ArgumentError EquationComponent(
        external,
        EquationProcess(
            :unrelated,
            [unrelated];
            writes = [z],
            solver = ExplicitEuler(),
        );
        name = :invalid_equation_selection,
    )
end

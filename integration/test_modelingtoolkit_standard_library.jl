@testset "ModelingToolkitStandardLibrary composition" begin
    @named source = ModelingToolkitStandardLibrary.Blocks.Constant(k = 2.0)
    @test source isa ModelingToolkitBase.AbstractSystem
    equations = ModelingToolkitBase.equations(source)
    writes = ModelingToolkitBase.unknowns(source)
    process = EquationProcess(
        :constant_block,
        equations;
        writes,
        solver = ExplicitEuler(),
        cadence = EveryMCS(),
    )
    component = EquationComponent(
        source, process; name = :constant_component
    )
    @test component isa PottsSystem
    @test ModelingToolkitBase.equations(component) == equations
    @test all(isequal.(
        ModelingToolkitBase.outputs(component),
        ModelingToolkitBase.outputs(source),
    ))
end

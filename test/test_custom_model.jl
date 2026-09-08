@testset "custom model authoring and continuation example" begin
    include(joinpath(dirname(@__DIR__), "examples", "custom_model.jl"))
    custom = CustomModel.run_custom_model()
    @test custom.solution.retcode == SciMLBase.ReturnCode.Success
    @test failure_report(custom.solution) === nothing
    @test custom.uninterrupted.retcode == SciMLBase.ReturnCode.Success
    @test last(custom.uninterrupted).ownership == last(custom.resumed).ownership
    @test last(custom.uninterrupted)[:activity] == last(custom.resumed)[:activity]
end

@testset "fresh-process weak-extension load orders" begin
    project = @__DIR__
    orders = (
        raw"""
        using Potts
        @assert Base.get_extension(Potts, :PottsModelingToolkitExt) === nothing
        @assert Base.get_extension(Potts, :PottsMethodOfLinesExt) === nothing
        @assert Base.get_extension(Potts, :PottsUnitfulExt) === nothing
        using ModelingToolkit
        @assert Base.get_extension(Potts, :PottsModelingToolkitExt) !== nothing
        using MethodOfLines
        @assert Base.get_extension(Potts, :PottsMethodOfLinesExt) !== nothing
        using Unitful
        @assert Base.get_extension(Potts, :PottsUnitfulExt) !== nothing
        print("potts-first-ok")
        """,
        raw"""
        using ModelingToolkit
        using MethodOfLines
        using Unitful
        using Potts
        @assert Base.get_extension(Potts, :PottsModelingToolkitExt) !== nothing
        @assert Base.get_extension(Potts, :PottsMethodOfLinesExt) !== nothing
        @assert Base.get_extension(Potts, :PottsUnitfulExt) !== nothing
        print("dependencies-first-ok")
        """,
        raw"""
        using Unitful
        using Potts
        @assert Base.get_extension(Potts, :PottsUnitfulExt) !== nothing
        using MethodOfLines
        using ModelingToolkit
        @assert Base.get_extension(Potts, :PottsModelingToolkitExt) !== nothing
        @assert Base.get_extension(Potts, :PottsMethodOfLinesExt) !== nothing
        print("interleaved-ok")
        """,
    )
    expected = ("potts-first-ok", "dependencies-first-ok", "interleaved-ok")
    for (script, output) in zip(orders, expected)
        command = `$(Base.julia_cmd()) --startup-file=no --project=$(project) -e $script`
        @test read(command, String) == output
    end
end

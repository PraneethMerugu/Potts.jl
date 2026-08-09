@testset "fresh-process weak-extension load orders" begin
    project = @__DIR__
    orders = (
        raw"""
        using PottsToolkit
        @assert Base.get_extension(PottsToolkit, :PottsToolkitModelingToolkitExt) === nothing
        @assert Base.get_extension(PottsToolkit, :PottsToolkitMethodOfLinesExt) === nothing
        @assert Base.get_extension(PottsToolkit, :PottsToolkitUnitfulExt) === nothing
        using ModelingToolkit
        @assert Base.get_extension(PottsToolkit, :PottsToolkitModelingToolkitExt) !== nothing
        using MethodOfLines
        @assert Base.get_extension(PottsToolkit, :PottsToolkitMethodOfLinesExt) !== nothing
        using Unitful
        @assert Base.get_extension(PottsToolkit, :PottsToolkitUnitfulExt) !== nothing
        print("potts-first-ok")
        """,
        raw"""
        using ModelingToolkit
        using MethodOfLines
        using Unitful
        using PottsToolkit
        @assert Base.get_extension(PottsToolkit, :PottsToolkitModelingToolkitExt) !== nothing
        @assert Base.get_extension(PottsToolkit, :PottsToolkitMethodOfLinesExt) !== nothing
        @assert Base.get_extension(PottsToolkit, :PottsToolkitUnitfulExt) !== nothing
        print("dependencies-first-ok")
        """,
        raw"""
        using Unitful
        using PottsToolkit
        @assert Base.get_extension(PottsToolkit, :PottsToolkitUnitfulExt) !== nothing
        using MethodOfLines
        using ModelingToolkit
        @assert Base.get_extension(PottsToolkit, :PottsToolkitModelingToolkitExt) !== nothing
        @assert Base.get_extension(PottsToolkit, :PottsToolkitMethodOfLinesExt) !== nothing
        print("interleaved-ok")
        """,
    )
    expected = ("potts-first-ok", "dependencies-first-ok", "interleaved-ok")
    for (script, output) in zip(orders, expected)
        command = `$(Base.julia_cmd()) --startup-file=no --project=$(project) -e $script`
        @test read(command, String) == output
    end
end

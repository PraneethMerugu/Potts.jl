@testset "fresh-process Metal extension load orders" begin
    project = @__DIR__
    orders = (
        raw"""
        using PottsToolkit
        @assert Base.get_extension(PottsToolkit, :PottsToolkitMetalExt) === nothing
        @assert Base.get_extension(PottsToolkit, :PottsToolkitMetalNativeExt) === nothing
        using ModelingToolkit
        using StaticArrays
        using DiffEqGPU
        using Metal
        @assert Metal.functional()
        @assert Base.get_extension(PottsToolkit, :PottsToolkitMetalExt) !== nothing
        @assert Base.get_extension(PottsToolkit, :PottsToolkitModelingToolkitExt) !== nothing
        @assert Base.get_extension(PottsToolkit, :PottsToolkitMetalNativeExt) !== nothing
        print("potts-first-metal-ok")
        """,
        raw"""
        using Metal
        using DiffEqGPU
        using ModelingToolkit
        using StaticArrays
        using PottsToolkit
        @assert Metal.functional()
        @assert Base.get_extension(PottsToolkit, :PottsToolkitMetalExt) !== nothing
        @assert Base.get_extension(PottsToolkit, :PottsToolkitModelingToolkitExt) !== nothing
        @assert Base.get_extension(PottsToolkit, :PottsToolkitMetalNativeExt) !== nothing
        print("dependencies-first-metal-ok")
        """,
    )
    expected = ("potts-first-metal-ok", "dependencies-first-metal-ok")
    for (script, output) in zip(orders, expected)
        command = `$(Base.julia_cmd()) --startup-file=no --project=$(project) -e $script`
        @test read(command, String) == output
    end
end

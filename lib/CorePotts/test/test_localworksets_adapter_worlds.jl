@testset "Core trusted adapter drains admitted work across method worlds" begin
    fixture = joinpath(
        @__DIR__, "fixtures", "localworksets_adapter_world_attack.jl"
    )
    project = dirname(@__DIR__)
    for profile in ("broad", "specific")
        command = `$(Base.julia_cmd()) --startup-file=no --project=$project $fixture $profile`
        @test success(command)
    end
end

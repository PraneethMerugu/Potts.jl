@testset "tiled execution tiled Level 1 integration" begin
    @test PottsToolkit.TiledCheckerboardCPM === CorePotts.TiledCheckerboardCPM
    problem = PottsToolkit.ReferenceModels.differential_adhesion_problem((16, 16);
        cells_per_population = 2, target_volume = 8, capacity = 8,
        tspan = (0, 2), seed = 17)
    algorithm = PottsToolkit.TiledCheckerboardCPM(temperature = 5.0f0,
        tile_size = (4, 4), switching_interval = 4, shared_memory = :disabled)
    report = PottsToolkit.backend_report(problem, algorithm)
    @test report.qualified
    solution = CorePotts.solve(problem, algorithm;
        snapshot_policy = CorePotts.HostSnapshotPolicy())
    @test solution.t[end] == 2
    @test CorePotts.assert_valid_state(solution.u[end].state) === solution.u[end].state
end

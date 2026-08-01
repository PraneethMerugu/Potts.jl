include("../setup.jl")
include("../backend_conformance/g2_descriptor_boundary.jl")

@testset "Symbolic Potts V1 fast compiler/runtime boundary" begin
    @testset "registered external descriptor boundary" begin
        report = run_g2_descriptor_boundary(
            Array,
            zeros;
            backend_name = :cpu,
            descriptor_count = 1,
        )
        @test report.backend === :cpu
    end
    include("../test_g2_r1_repairs.jl")
    include("../test_checkpoint.jl")
end

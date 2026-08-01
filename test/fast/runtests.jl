include("../setup.jl")

@testset "Symbolic Potts V1 fast compiler/runtime boundary" begin
    include("../test_g2_r1_repairs.jl")
    include("../test_checkpoint.jl")
end

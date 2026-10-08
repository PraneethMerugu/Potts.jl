using Potts, Test
isdefined(Main, :PottsDevices) || include(joinpath(@__DIR__, "shared", "devices.jl"))

@testset "Potts re-exports CorePotts" begin
    @test isdefined(Potts, :PottsProblem)
    @test Potts.PottsProblem === Potts.CorePotts.PottsProblem
end

include(joinpath(@__DIR__, "..", "benchmark", "models.jl"))
include("ports/models.jl")
include("ports/symbolic_models.jl")
include("symbolic.jl")
include("kind_classes.jl")
include("draws_folds.jl")
include("oracle.jl")
include("audit.jl")
include("units.jl")
include("adaptive.jl")
include("layouts.jl")
include("solvers.jl")
include("analysis.jl")
include("boundary_schedule.jl")
include("sweep_spec.jl")
include("algebraic.jl")
include("initialization.jl")
include("edge_updates.jl")
PottsDevices.on_device() && include("gpu.jl")     # POTTS_GPU = metal | rocm (D-157)
get(ENV, "POTTS_QA", "true") == "true" && include("qa.jl")

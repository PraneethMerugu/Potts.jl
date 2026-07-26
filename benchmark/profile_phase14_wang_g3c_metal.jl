VERSION == v"1.12.6" ||
    error("Phase 14 Wang G3-C Metal profiling requires Julia 1.12.6; found $VERSION")

using Metal
using SciMLBase

include(joinpath(@__DIR__, "src", "PottsBenchmarks.jl"))
using .PottsBenchmarks

run = PottsBenchmarks._phase14_build_wang_g3c(
    "metal", 32)
SciMLBase.step!(run.coupled, 210)
PottsBenchmarks.KernelAbstractions.synchronize(
    run.backend)

directory = joinpath(
    PottsBenchmarks.RESULTS_ROOT,
    "phase14-g3c-device-code", "metal")
mkpath(directory)
path = joinpath(
    directory, "wang-coupled-kernels.air")
open(path, "w") do io
    Metal.@device_code_air io=io dump_module=true raw=true begin
        # Target 211 exercises Potts, field, history, calibration,
        # intracellular, retune, alignment, force, cleanup, and bounded
        # observation kernels in the frozen source order.
        SciMLBase.step!(run.coupled)
        PottsBenchmarks.KernelAbstractions.synchronize(
            run.backend)
    end
end
filesize(path) > 0 ||
    error("Wang G3-C Metal device-code capture was empty")
println("PHASE14_WANG_G3C_METAL_DEVICE_CODE=", path)

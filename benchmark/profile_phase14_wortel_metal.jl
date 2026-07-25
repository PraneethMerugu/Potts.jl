VERSION == v"1.12.6" ||
    error("Phase 14 Metal profiling requires Julia 1.12.6; found $VERSION")

using Metal
using SciMLBase

include(joinpath(@__DIR__, "src", "PottsBenchmarks.jl"))
using .PottsBenchmarks

run = PottsBenchmarks._phase14_build_wortel(
    "metal", (48, 48);
    seed = UInt64(0x70686173653134f1),
    observation_cadence = 1000)
SciMLBase.step!(run.coupled)
PottsBenchmarks.KernelAbstractions.synchronize(run.backend)

directory = joinpath(
    PottsBenchmarks.RESULTS_ROOT, "phase14-device-code", "metal")
mkpath(directory)
path = joinpath(directory, "wortel-coupled-kernels.air")
open(path, "w") do io
    Metal.@device_code_air io=io dump_module=true raw=true begin
        SciMLBase.step!(run.coupled)
        PottsBenchmarks.KernelAbstractions.synchronize(run.backend)
    end
end
filesize(path) > 0 ||
    error("Phase 14 Metal device-code capture was empty")
println("PHASE14_WORTEL_METAL_DEVICE_CODE=", path)

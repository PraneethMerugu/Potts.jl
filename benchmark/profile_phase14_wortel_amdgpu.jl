VERSION == v"1.12.6" ||
    error("Phase 14 ROCm profiling requires Julia 1.12.6; found $VERSION")

using AMDGPU
using SciMLBase

include(joinpath(@__DIR__, "src", "PottsBenchmarks.jl"))
using .PottsBenchmarks

run = PottsBenchmarks._phase14_build_wortel(
    "amdgpu", (48, 48);
    seed = UInt64(0x70686173653134f2),
    observation_cadence = 1000)
directory = joinpath(
    PottsBenchmarks.RESULTS_ROOT, "phase14-device-code", "amdgpu")
AMDGPU.@device_code dir=directory begin
    SciMLBase.step!(run.coupled)
    PottsBenchmarks.KernelAbstractions.synchronize(run.backend)
end
files = filter(isfile, (joinpath(directory, name) for name in readdir(directory)))
isempty(files) &&
    error("Phase 14 ROCm device-code capture produced no files")
all(iszero ∘ filesize, files) &&
    error("Phase 14 ROCm device-code capture contained only empty files")
println("PHASE14_WORTEL_ROCM_DEVICE_CODE=", directory)

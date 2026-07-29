VERSION == v"1.12.6" ||
    error("Wortel model ROCm profiling requires Julia 1.12.6; found $VERSION")

using AMDGPU
using SciMLBase

include(joinpath(@__DIR__, "src", "PottsBenchmarks.jl"))
using .PottsBenchmarks

run = PottsBenchmarks._build_wortel_model(
    "amdgpu", (48, 48);
    seed = UInt64(0x70686173653134f2),
    observation_cadence = 1000)
directory = joinpath(
    PottsBenchmarks.RESULTS_ROOT, "wortel-device-code", "amdgpu")
AMDGPU.@device_code dir=directory begin
    SciMLBase.step!(run.coupled)
    PottsBenchmarks.KernelAbstractions.synchronize(run.backend)
end
files = filter(isfile, map(name -> joinpath(directory, name), readdir(directory)))
isempty(files) &&
    error("Wortel model ROCm device-code capture produced no files")
all(iszero ∘ filesize, files) &&
    error("Wortel model ROCm device-code capture contained only empty files")
println("WORTEL_MODEL_ROCM_DEVICE_CODE=", directory)

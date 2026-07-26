VERSION == v"1.12.6" ||
    error("Phase 14 Wang G3-C ROCm profiling requires Julia 1.12.6; found $VERSION")

using AMDGPU
using SciMLBase

include(joinpath(@__DIR__, "src", "PottsBenchmarks.jl"))
using .PottsBenchmarks

run = PottsBenchmarks._phase14_build_wang_g3c(
    "amdgpu", 32)
SciMLBase.step!(run.coupled, 210)
PottsBenchmarks.KernelAbstractions.synchronize(
    run.backend)

directory = joinpath(
    PottsBenchmarks.RESULTS_ROOT,
    "phase14-g3c-device-code", "amdgpu")
mkpath(directory)
AMDGPU.@device_code dir=directory begin
    SciMLBase.step!(run.coupled)
    PottsBenchmarks.KernelAbstractions.synchronize(
        run.backend)
end
files = filter(
    isfile,
    map(name -> joinpath(directory, name),
        readdir(directory)))
isempty(files) &&
    error("Wang G3-C ROCm device-code capture produced no files")
all(iszero ∘ filesize, files) &&
    error("Wang G3-C ROCm device-code capture contained only empty files")
println("PHASE14_WANG_G3C_ROCM_DEVICE_CODE=", directory)

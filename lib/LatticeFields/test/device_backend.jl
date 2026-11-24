# The device of the GPU tests (POTTS_GPU = metal | rocm). Each device setup
# (`LF_exec_device`, `LF_problems_device`, `LF_solvers_device`) includes it; their items are
# `:gpu_only`, so they run only with a device selected (POTTS_GPU, or GROUP=gpu).
if gpu == "metal"
    using Metal: Metal
    const DEV = Metal.MetalBackend()
    const GPUPKG = Metal
    devarray(x) = Metal.MtlArray(x)
else
    using AMDGPU: AMDGPU
    const DEV = AMDGPU.ROCBackend()
    const GPUPKG = AMDGPU
    devarray(x) = AMDGPU.ROCArray(x)
end
devsync() = KA.synchronize(DEV)
# the kernels compiled and loaded on the device so far (one listing for every suite)
include(joinpath(@__DIR__, "..", "..", "..", "test", "shared", "kernel_listing.jl"))
instances() = length(compiled_kernels(GPUPKG))

# The device of the GPU tests (POTTS_GPU = metal | rocm). Each device setup
# (`LF_exec_device`, `LF_problems_device`, `LF_solvers_device`) includes it; their items are
# `:gpu_only`, so they run only with a device selected (POTTS_GPU, or GROUP=gpu).
if gpu == "metal"
    using Metal: Metal
    const DEV = Metal.MetalBackend()
    instances() = length(Metal.kernel_instances)
    devarray(x) = Metal.MtlArray(x)
else
    using AMDGPU: AMDGPU
    const DEV = AMDGPU.ROCBackend()
    instances() = length(AMDGPU.Compiler._kernel_instances)
    devarray(x) = AMDGPU.ROCArray(x)
end
devsync() = KA.synchronize(DEV)

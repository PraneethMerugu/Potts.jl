# The device of the GPU tests (LATTICEFIELDS_GPU = metal | rocm), loaded once by runtests.jl.
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

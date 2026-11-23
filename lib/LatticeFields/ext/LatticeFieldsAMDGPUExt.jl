# The kernel-argument budget of ROCm (4 KiB), which bounds kernel fusion.
module LatticeFieldsAMDGPUExt

using AMDGPU: ROCBackend
using LatticeFields: Exec

# The budget of a launch's explicit argument tuple. No HIP or ROCm document states a limit
# for it; 4096 bytes is the limit CUDA documents for kernel parameters before 12.1
# (https://developer.nvidia.com/blog/cuda-12-1-supports-large-kernel-parameters), and the
# full ROCm GPU suites run at it. The hidden arguments the compiler appends (the implicit
# kernel arguments) are not counted.
Exec.kernel_argument_bytes(::ROCBackend) = 4096

end

# The kernel-argument budget of ROCm (4 KiB), which bounds kernel fusion.
module LatticeFieldsAMDGPUExt

using AMDGPU: ROCBackend
using LatticeFields: Exec

Exec.kernel_argument_bytes(::ROCBackend) = 4096

end

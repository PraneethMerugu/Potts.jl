# The kernel-argument budget of Metal (4 KiB, the limit of inline argument bytes), which
# bounds kernel fusion.
module LatticeFieldsMetalExt

using Metal: MetalBackend
using LatticeFields: Exec

# `setBytes` takes at most 4 KB per argument (Apple, MTLComputeCommandEncoder,
# https://developer.apple.com/documentation/metal/mtlcomputecommandencoder), and Metal.jl
# sets each kernel argument on its own, so a budget on the whole argument tuple is
# conservative here. Not verified on a device.
Exec.kernel_argument_bytes(::MetalBackend) = 4096

end

# The kernel-argument budget of Metal (4 KiB, the limit of inline argument bytes), which
# bounds kernel fusion.
module LatticeFieldsMetalExt

using Metal: MetalBackend
using LatticeFields: Exec

Exec.kernel_argument_bytes(::MetalBackend) = 4096

end

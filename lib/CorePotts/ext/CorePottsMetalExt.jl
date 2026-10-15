# Metal has no 64-bit atomic add (D-251): the mask counters of a lattice above 2³¹ − 1 sites
# need one, so `init` refuses such a run there, and the device lifecycle's counter (unused
# without a mask that follows the state) stays Int32.
module CorePottsMetalExt

using CorePotts: CorePotts
using Metal: MetalBackend

CorePotts._atomic64(::MetalBackend) = false

end

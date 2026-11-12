# Definitions of the old runtests.jl (its preamble) that other test files use (moved here by TS1b).
using Test, LatticeFields

# device tests: LATTICEFIELDS_GPU (or POTTS_GPU) = metal | rocm
const gpu = lowercase(strip(get(ENV, "LATTICEFIELDS_GPU", get(ENV, "POTTS_GPU", ""))))
gpu in ("", "metal", "rocm") ||
    error("LATTICEFIELDS_GPU must be \"\", \"metal\" or \"rocm\"; got \"$gpu\"")

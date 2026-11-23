# The definitions that the test files of this package include first (their preamble).
using Test, LatticeFields

# device tests: POTTS_GPU = metal | rocm
const gpu = lowercase(strip(get(ENV, "POTTS_GPU", "")))
gpu in ("", "metal", "rocm") ||
    error("POTTS_GPU must be \"\", \"metal\" or \"rocm\"; got \"$gpu\"")

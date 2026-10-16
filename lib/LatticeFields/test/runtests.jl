using Test, LatticeFields

# device tests: LATTICEFIELDS_GPU (or POTTS_GPU) = metal | rocm
const gpu = lowercase(strip(get(ENV, "LATTICEFIELDS_GPU", get(ENV, "POTTS_GPU", ""))))
gpu in ("", "metal", "rocm") || error("LATTICEFIELDS_GPU must be \"\", \"metal\" or \"rocm\"; got \"$gpu\"")

@testset "LatticeFields" begin
    include("exec.jl")
    isempty(gpu) || include("exec_device.jl")
    get(ENV, "LATTICEFIELDS_QA", "true") == "true" && include("qa.jl")
end

using Test, LatticeFields

# device tests: LATTICEFIELDS_GPU (or POTTS_GPU) = metal | rocm
const gpu = lowercase(strip(get(ENV, "LATTICEFIELDS_GPU", get(ENV, "POTTS_GPU", ""))))
gpu in ("", "metal", "rocm") || error("LATTICEFIELDS_GPU must be \"\", \"metal\" or \"rocm\"; got \"$gpu\"")

include("exec_helpers.jl")
include("host_runner.jl")
include("fixtures.jl")

# groups: exec, ir, compile, schedule, qa (all by default); LATTICEFIELDS_QA = false skips qa
const GROUPS = isempty(ARGS) ? ["exec", "ir", "compile", "schedule", "qa"] : ARGS

@testset "LatticeFields" begin
    for g in GROUPS
        g == "qa" && get(ENV, "LATTICEFIELDS_QA", "true") != "true" && continue
        @testset "$g" begin
            if g == "exec"
                include("exec.jl")
                isempty(gpu) || include("exec_device.jl")
            else
                for f in sort(readdir(joinpath(@__DIR__, g)))
                    endswith(f, ".jl") && @testset "$f" include(joinpath(@__DIR__, g, f))
                end
            end
        end
    end
end

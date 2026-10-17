using Test, LatticeFields

# device tests: LATTICEFIELDS_GPU (or POTTS_GPU) = metal | rocm
const gpu = lowercase(strip(get(ENV, "LATTICEFIELDS_GPU", get(ENV, "POTTS_GPU", ""))))
gpu in ("", "metal", "rocm") ||
    error("LATTICEFIELDS_GPU must be \"\", \"metal\" or \"rocm\"; got \"$gpu\"")

include("exec_helpers.jl")
include("host_runner.jl")
include("fixtures.jl")
include("solvers_cases.jl")
isempty(gpu) || include("device_backend.jl")

# groups: exec, ir, compile, schedule, problems, solvers, qa (all by default); `solvers_gate`
# (the PG-4 size sweep, about 10 minutes) is opt-in; LATTICEFIELDS_QA = false skips qa
const GROUPS = isempty(ARGS) ?
               ["exec", "ir", "compile", "schedule", "problems", "solvers", "qa"] : ARGS

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
                g == "problems" && !isempty(gpu) && include("problems_device.jl")
            end
            g == "solvers" && !isempty(gpu) &&
                @testset "solvers_device.jl" include("solvers_device.jl")
        end
    end
end

# Child of benchmark/ab.jl: the median warm-MCS time of one gate case in this checkout.
#     julia --project=benchmark benchmark/ab_one.jl <case> <metal|sequential|checkerboard>
# Timed like the gate: on Metal, `step!` followed by `synchronize` (D-090).
ARGS[2] == "metal" && push!(ARGS, "metal")          # gate.jl loads Metal from ARGS
include(joinpath(@__DIR__, "gate.jl"))
using Statistics: median

let metal = ARGS[2] == "metal"
    prob = Dict(cases(metal ? Float32 : Float64))[ARGS[1]]()
    alg = ARGS[2] == "sequential" ? SequentialCPM() : CheckerboardCPM()
    backend = metal ? Metal.MetalBackend() : nothing
    fresh_integrator(prob, alg, backend)
    b = run(@benchmarkable timed_step!(i, $backend) setup = (i = fresh_integrator($prob, $alg, $backend)) evals = 1 samples = 60 seconds = 40)
    println("AB ", median(b).time / length(prob.u0.σ))
end

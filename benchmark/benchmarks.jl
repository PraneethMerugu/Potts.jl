# AirspeedVelocity / BenchmarkTools suite: warm cost of one MCS.
using BenchmarkTools
include("models.jl")

const SUITE = BenchmarkGroup()
for (name, alg) in (("sequential", SequentialCPM(; proposal = Moore(1))),
        ("checkerboard", CheckerboardCPM(; proposal = Moore(1))))
    for scale in (1, 4)
        SUITE["graner"][name]["$(72scale)²"] = @benchmarkable step!(integ) setup = (
            integ = init(graner_problem(; scale = $scale, nmcs = 10^6), $alg;
                save_start = false); step!(integ)) evals = 1 samples = 50
    end
end

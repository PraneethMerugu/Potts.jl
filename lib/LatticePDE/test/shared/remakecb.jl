# Definitions of remakecb_tests.jl that other test files use (moved here by TS1b).
using OrdinaryDiffEqTsit5: Tsit5

@parameters rD = 0.2
@variables rc(..) rq(..)::Int32 [input = true]
rce, rqe = rc(t, x, y), rq(t, x, y)
rdom(T) = [t ∈ Interval(0.0, T), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]

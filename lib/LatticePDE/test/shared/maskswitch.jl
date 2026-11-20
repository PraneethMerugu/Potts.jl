# Definitions of maskswitch_tests.jl that other test files use.
using OrdinaryDiffEqTsit5: Tsit5
using OrdinaryDiffEqRosenbrock: Rodas5P

@parameters mD = 0.2 mt0 = 0.3
@variables mc(..) mk(..)::Int32 [input = true] mq(..) [input = true]
mce, mke, mqe = mc(t, x, y), mk(t, x, y), mq(t, x, y)
mdom = [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
const MK = Int32[i <= 2 ? 1 : 0 for i in 1:8, j in 1:8]

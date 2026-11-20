# Definitions of problems_tests.jl that other test files use.
using OrdinaryDiffEqTsit5: Tsit5
using ForwardDiff: ForwardDiff
using SymbolicIndexingInterface: getp, setp, getsym
using SciMLBase: SciMLBase, ODEProblem, remake

@parameters kr = 0.0 Dr = 1.0 gr = 0.0 βr = -0.5
pdom(T = 1.0) = [t ∈ Interval(0.0, T), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
function psys(eqs, bcs, ps; T = 1.0, dvs = [ce])
    return PDESystem(eqs, bcs, pdom(T), [t, x, y], dvs, ps; name = :p)
end
# (the owned problem field algorithms step, `LFP.field_problem` of the problem `discretize`
# returns)
function owned(sys, n, m = n; T = Float64, inputs = (), kw...)
    return LFP.field_problem(
        discretize(sys, LatticeDiscretization(Grid((n, m)); T, kw...); inputs)
    )
end
fgrid(v, n, m) = reshape(v, n, m)

# Definitions of params_tests.jl that other test files use (moved here by TS1b).
using SciMLBase: SciMLBase, remake
using SymbolicIndexingInterface: getp, setp
using SciMLStructures: SciMLStructures, Tunable, Constants, Discrete
using ForwardDiff: ForwardDiff
using OrdinaryDiffEqTsit5: Tsit5

@parameters Dw[1:2] = [0.5, 1.0] kw0 = 0.2
@variables wk(..)::Int32 [input = true]
wke = wk(t, x, y)
wsys() = PDESystem([D(ce) ~ at(Dw, wke) * Δ(ce) - kw0 * ce],
    [c(0, x, y) ~ x * y, Differential(x)(c(t, 0, y)) ~ 0.0, Differential(x)(c(t, 1, y)) ~ 0.0,
        c(t, x, 0) ~ c(t, x, 1)],
    [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [ce, wke], [Dw, kw0]; name = :w)
const WK1 = Int32[i <= 4 ? 1 : 2 for i in 1:8, j in 1:8]
const WK2 = Int32[j <= 4 ? 2 : 1 for i in 1:8, j in 1:8]
wdisc() = LatticeDiscretization(Grid((8, 8)); T = Float64)
wmsg(f) = try
    f(); ""
catch e
    sprint(showerror, e)
end

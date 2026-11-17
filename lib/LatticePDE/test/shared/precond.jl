# Definitions of precond_tests.jl that other test files use (moved here by TS1b).
using LinearAlgebra: norm
using SparseArrays: SparseArrays
using LinearSolve: LinearSolve, KrylovJL_GMRES
using OrdinaryDiffEqBDF: FBDF
using OrdinaryDiffEqSDIRK: ImplicitEuler, Trapezoid

@parameters qD = 0.05 qk = 1.0
@variables qc(..) qw(..)
qdom(T) = [t ∈ Interval(0.0, T), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
qsys(T; f = 0.0) = PDESystem([D(qc(t, x, y)) ~ qD * Δ(qc(t, x, y)) - qk * qc(t, x, y) + f],
    [qc(0, x, y) ~ sin(π * x) * cos(π * y), qc(t, 0, y) ~ 1.0], qdom(T), [t, x, y], [qc(t, x, y)], [qD, qk]; name = :qs)
qdisc(n; kw...) = LatticeDiscretization(Grid((n, n)); T = Float64, kw...)
const QTIGHT = DevicePCG(; reltol = 1.0e-13, maxiters = 400)

# FBDF with GMRES (and `precs`) on `prob`: the solution and the Krylov iterations per linear solve
function qfbdf(prob; precs = nothing, gmres_restart = 200)
    j = prob.f.jvp
    c0 = j.calls[]
    s = solve(prob, FBDF(; linsolve = KrylovJL_GMRES(; precs, gmres_restart)); abstol = 1e-6, reltol = 1e-6)
    return s, (j.calls[] - c0) / max(s.stats.nsolve, 1)
end

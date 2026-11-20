# Definitions of odepath_tests.jl that other test files use.
using SciMLBase: SciMLBase, remake
using OrdinaryDiffEqTsit5: Tsit5
using OrdinaryDiffEqRosenbrock: Rodas5P
using LinearAlgebra: Diagonal
using LinearSolve: LinearSolve
using SymbolicIndexingInterface: setp
using ForwardDiff: ForwardDiff

@parameters oD = 0.2
@variables oc(..) ok(..)::Int32 [input = true] ov(..)
ode_c, ode_k, ode_v = oc(t, x, y), ok(t, x, y), ov(t, x, y)
odom(T) = [t ∈ Interval(0.0, T), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
const OK1 = Int32[i <= 2 && j <= 2 ? 1 : 0 for i in 1:8, j in 1:8]
const OK2 = Int32[i >= 7 && j >= 7 ? 1 : 0 for i in 1:8, j in 1:8]
odisc(; kw...) = LatticeDiscretization(Grid((8, 8)); T = Float64, kw...)
function omsys()
    return PDESystem(
        [D(ode_c) ~ oD * laplacian(ode_c) - ode_c], [oc(0, x, y) ~ x, ode_c ~ masked(ode_k == 1, 2.0)], odom(0.2),
        [t, x, y], [ode_c, ode_k], [oD]; name = :om)
end
const OTOL = (; abstol = 1e-11, reltol = 1e-11)

# Negative controls at 0a182a0e, in each testset.
@parameters qD = 0.5
@variables qc(..) qk(..)::Int32 [input = true]
qce, qke = qc(t, x, y), qk(t, x, y)
const QK = Int32[i == 1 ? 1 : 0 for i in 1:16, j in 1:16]
function qsys(val)
    return PDESystem(
        [D(qce) ~ qD * laplacian(qce)], [
            qc(0, x, y) ~ 1.0, Differential(x)(qc(t, 1, y)) ~ 0.0,
            Differential(y)(qc(t, x, 0)) ~ 0.0, Differential(y)(qc(t, x, 1)) ~ 0.0, qce ~ masked(qke == 1, val)],
        [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y], [qce, qke], [qD]; name = :q)
end

# Re-review (2026-11-06): a discrete event (a new step index, a write of a parameter or an input
# on the integrator) gives a mask value a jump its rate ∂v/∂t cannot carry, so every masked
# site takes its value again there. Negative control at 9d30a15a, in the testset.
@parameters rra = 1.0
@variables rrc(..) rrk(..)::Int32 [input = true] rrq(..) [input = true]
rrce, rrke, rrqe = rrc(t, x, y), rrk(t, x, y), rrq(t, x, y)
const RRK = Int32[i <= 2 ? 1 : 0 for i in 1:8, j in 1:8]
const RRM = vec(RRK .== 1)
function rrsys(val)
    return PDESystem(
        [D(rrce) ~ 0.2 * laplacian(rrce) - 0.5 * rrce], [rrc(0, x, y) ~ x, rrce ~ masked(rrke == 1, val)],
        odom(1.0), [t, x, y], [rrce, rrke, rrqe], [rra]; name = :rr)
end
# the masked values after a write `k => v` on a Tsit5 integrator at t = 0.5, at t = 1
function rrwrite(val, k, v)
    i = init(discretize(rrsys(val), odisc(); inputs = [rrke => RRK, rrqe => zeros(8, 8)]), Tsit5(); abstol = 1e-9, reltol = 1e-9)
    SciMLBase.step!(i, 0.5, true)
    i.ps[k] = v
    SciMLBase.step!(i, 0.5, true)
    return i.u[RRM]
end

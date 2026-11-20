# Definitions of numbers_tests.jl that other test files use.
using ForwardDiff: ForwardDiff
using OrdinaryDiffEqRosenbrock: Rodas5P
using LatticeFields: LatticeFields, Compile
using SciMLStructures: SciMLStructures, Tunable

@parameters Dn = 0.5 kn = 0.3 gn = 1.0 ωn = 3.0 K0n = 0.2
nsys(; T = 0.1) = psys(
    [D(ce) ~ Dn * laplacian(ce) - kn * ce],
    [c(0, x, y) ~ 0.0, c(t, 0, y) ~ gn, Differential(x)(c(t, 1, y)) ~ 0.0, c(t, x, 0) ~ c(t, x, 1)],
    [Dn, kn, gn]; T)
fd(f, x; h = 1e-6) = (f(x + h) - f(x - h)) / (2h)
pidx(prob, s) = LatticePDE.Problems.SII.parameter_index(prob, s)
withp(p, i, v) = (q = collect(promote_type(eltype(p), typeof(v)), p); q[i] = v; q)

# Derivatives through the implicit solve. A Dual state runs the primal solve and, after
# each stage, its tangent step: the derivative parts solve the stage's linearization with the
# primal operator, one solve per part (no Dual enters a solver). Each case against central
# differences of the run. Base (57ea1baa): every case is refused ("holds ForwardDiff Duals").
# Negative controls (mutations): the parameter part of the operator
# (`(∂A/∂k) u`, the parameters of the face coefficients) dropped from the tangent fails ∂/∂D; the
# right side's (the parameters of no face and no local term) dropped fails ∂/∂g
@parameters kt = 0.7 Dt = 0.3 gt = 0.4
@variables ta(..) tb(..)
tae, tbe = ta(t, x, y), tb(t, x, y)
tdom = [t ∈ Interval(0.0, 0.3), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
tsys(eqs, bcs; dvs = [ce]) = PDESystem(eqs, bcs, tdom, [t, x, y], dvs, [kt, Dt, gt]; name = :tg)
town(sys, dims = (8, 6); geometry = LatticeFields.IR.CUBIC) =
    LFP.field_problem(discretize(sys, LatticeDiscretization(Grid(dims; geometry); T = Float64)))
const TTIGHT = LatticePCG(; reltol = 1.0e-13, maxiters = 200)
# AD and central differences of `sum(out(solve))` in parameter `s`
function tad(prob, alg, s; dt, out = sol -> sol.u[end])
    i = pidx(prob, s)
    J(v) = sum(out(solve(remake(prob; p = withp(prob.p, i, v)), alg; dt)))
    return ForwardDiff.derivative(J, prob.p[i]), fd(J, prob.p[i]; h = 1e-5)
end
tok(ad, f) = isapprox(ad, f; rtol = 1e-7) && ad != 0

# Batch 5 review S3 and N4: a group that declares Float64 on a backend without it (Metal) is
# refused at the bind in words; a stub backend whose `supports_float64` is false stands in.
# The D-157 registry of a store's generic bodies is keyed on a Float64 device array.
struct NoF64Backend <: LatticeFields.Exec.KernelAbstractions.GPU end
LatticeFields.Exec.KernelAbstractions.supports_float64(::NoF64Backend) = false

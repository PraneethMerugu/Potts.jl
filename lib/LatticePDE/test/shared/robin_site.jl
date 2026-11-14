# Definitions of robin_site_tests.jl that other test files use (moved here by TS1b).
using ForwardDiff: ForwardDiff
using LatticeFields: Problems

const RSD = (16, 16)
rsown(sys; dims = RSD) = LFP.field_problem(discretize(sys, LatticeDiscretization(Grid(dims); T = Float64)))
rsys(eqs, bcs, ps; T = 1.0) = PDESystem(eqs, bcs, bdom(T), [t, x, y], [bce], ps; name = :rs)
rsxs() = [(i - 0.5) / RSD[1] for i in 1:RSD[1], j in 1:RSD[2]]
rsys0() = [(j - 0.5) / RSD[2] for i in 1:RSD[1], j in 1:RSD[2]]
# one window of `alg` from the start state `x y`
function rs_window(prob, alg)
    ig = init(prob, alg)
    u0 = copy(vec(ig[bce]))
    step!(ig)
    return ig, u0, vec(ig[bce])
end
# α(y) = 1 + y on x = 0, β(x) = 0.5 + x on y = 1 (as written: `α c + β ∂c/∂x_a = g`)
rs_bcs(α0 = 1.0) = [bc(0, x, y) ~ x * y, (α0 + y) * bc(t, 0, y) - Differential(x)(bc(t, 0, y)) ~ bg,
    2.0 * bc(t, x, 1) + (0.5 + x) * Differential(y)(bc(t, x, 1)) ~ 1.0]
rs_faces(α0 = 1.0) = Dict((1, -1) => (:robin, (x, y) -> α0 + y, -1.0, 0.5), (2, 1) => (:robin, 2.0, (x, y) -> 0.5 + x, 1.0))

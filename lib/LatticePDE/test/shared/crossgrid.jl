# Definitions of crossgrid_tests.jl that other test files use (moved here by TS1b).
using LinearAlgebra: I, Tridiagonal, kron
using ForwardDiff: ForwardDiff
using LatticeFields.IR: HEX
using OrdinaryDiffEqTsit5: Tsit5

xlev(name, k) = Symbolics.wrap(SymbolicUtils.setmetadata(unwrap(first(Symbolics.variables(name, T = SymbolicUtils.FnType{Tuple, Real, Nothing}))),
    LatticePDE.LatticeLevel, Coarse(k)))
xfine(name) = first(@variables $name(..))
const xcc, xLc = xlev(:xcc, 4), xlev(:xLc, 4)
const xu, xv, xX = xfine(:xuu), xfine(:xvv), xfine(:xXf)
xe(f) = f(t, x, y)
xdom(T = 1.0) = [t ∈ Interval(0.0, T), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
# (F4-01: the owned problem field algorithms step, `LFP.field_problem` of the problem `discretize` returns)
xown(sys, dims; kw...) = LFP.field_problem(discretize(sys, LatticeDiscretization(Grid(dims); kw...)))
const XT = 0.002
@parameters xDq = 0.01 xaq = 0.5
# the operators of the cross-grid path (a coordinate coefficient makes the face coefficient vary)
const XOPS = (("Δ", c -> laplacian(c)), ("DivKGrad harmonic", c -> DivKGrad(:harmonic)(1 + x, c)),
              ("DivKGrad arithmetic", c -> DivKGrad(:arithmetic)(1 + x + y, c)),
              ("Advect", c -> Advect(Upwind1())([0.3, -0.2], c)), ("raw Dx(Dx(c))", c -> Differential(x)(Differential(x)(c))),
              ("raw Dy(K Dy(c))", c -> Differential(y)((1 + x) * Differential(y)(c))))
# the two directions as the direct system and the manual route, for the operator `op`
function xpair(op; ps = Num[], a = 0.5, D1 = 0.01)
    ic1 = [xcc(0, x, y) ~ x^2 + sin(3y), xu(0, x, y) ~ 0.0]
    cf = (dir = PDESystem([D(xe(xcc)) ~ D1 * laplacian(xe(xcc)), D(xe(xu)) ~ a * op(xe(xcc)) - xe(xu)], ic1, xdom(), [t, x, y], [xe(xcc), xe(xu)], ps; name = :xd1),
          route = PDESystem([D(xe(xcc)) ~ D1 * laplacian(xe(xcc)), xe(xLc) ~ op(xe(xcc)), D(xe(xu)) ~ a * xe(xLc) - xe(xu)], ic1, xdom(), [t, x, y],
                            [xe(xcc), xe(xLc), xe(xu)], ps; name = :xr1), row = xu)
    ic2 = [xv(0, x, y) ~ sin(7x) * cos(5y), xcc(0, x, y) ~ 0.0]
    fc = (dir = PDESystem([D(xe(xv)) ~ D1 * laplacian(xe(xv)), D(xe(xcc)) ~ a * op(xe(xv)) - xe(xcc)], ic2, xdom(), [t, x, y], [xe(xv), xe(xcc)], ps; name = :xd2),
          route = PDESystem([D(xe(xv)) ~ D1 * laplacian(xe(xv)), xe(xX) ~ op(xe(xv)), D(xe(xcc)) ~ a * xe(xX) - xe(xcc)], ic2, xdom(), [t, x, y],
                            [xe(xv), xe(xX), xe(xcc)], ps; name = :xr2), row = xcc)
    return (; cf, fc)
end
xT1(n) = (m = Matrix(Tridiagonal(ones(n - 1), -2ones(n), ones(n - 1))); m[1, 1] = m[n, n] = -1; m .* n^2)
xL2(n) = (T = xT1(n); kron(Matrix(1.0I, n, n), T) + kron(T, Matrix(1.0I, n, n)))          # axis 1 fastest in `vec`
xctr(n) = [(i - 0.5) / n for i in 1:n]
# the block means (R) and the prolongation (P) between the 16² lattice and its 4² coarse grid
const XR, XP = let R = zeros(16, 256), P = zeros(256, 16)
    for J in 1:4, I in 1:4, j in 1:4, i in 1:4
        f = (4 * (J - 1) + j - 1) * 16 + 4 * (I - 1) + i
        P[f, (J - 1) * 4 + I] = 1
        R[(J - 1) * 4 + I, f] = 1 / 16
    end
    R, P
end

# Definitions of cranknicolson_tests.jl that other test files use.
using OrdinaryDiffEqSDIRK: Trapezoid

# the manufactured solution `u = e^{−t} sin(πx) sin(πy) + t` (its source, the face value
# `t`) on [0, 1]², `dims` sites
function mf_problem(dims)
    src = -exp(-t) * sin(π * x) * sin(π * y) + 1 +
        2π^2 * 0.1 * exp(-t) * sin(π * x) * sin(π * y)
    faces = [bc(t, 0, y) ~ t, bc(t, 1, y) ~ t, bc(t, x, 0) ~ t, bc(t, x, 1) ~ t]
    ms = bsys(
        [D(bce) ~ 0.1 * laplacian(bce) + src],
        [bc(0, x, y) ~ sin(π * x) * sin(π * y); faces], Any[]; T = 1.0, dvs = [bce]
    )
    return discretize(ms, LatticeDiscretization(Grid(dims); T = Float64))
end
function mf_src(xx, yy, tt)
    return -exp(-tt) * sin(π * xx) * sin(π * yy) + 1 +
        2π^2 * 0.1 * exp(-tt) * sin(π * xx) * sin(π * yy)
end
mf_faces(tt) = Dict((a, s) => (:dir, tt) for a in 1:2, s in (-1, 1))
# the hand rate `(L, b)` of the manufactured system on BDIMS at time `tt`
function mf_rate(tt)
    return hand_rate(;
        K = (x, y) -> 0.1, f = (xx, yy) -> mf_src(xx, yy, tt),
        faces = mf_faces(tt)
    )
end
# the errors and orders of `alg` at each window `dt` against the semi-discrete solution (the
# `:ode` path, Tsit5 at 1e-12), `m²` sites
function mf_orders(alg, dts; m = 32)
    ref = solve(mf_problem((m, m)), Tsit5(); reltol = 1.0e-12, abstol = 1.0e-12).u[end]
    pm = mf_problem((m, m))
    es = [maximum(abs, vec(blast(solve(pm, alg; dt))) .- ref) for dt in dts]
    return es, log2.(es[1:(end - 1)] ./ es[2:end])
end
# the heat eigenmode `sin(πx) sin(πy)` with Dirichlet 0 faces (`n²` sites): the
# semi-discrete solution is `e^{D λ t} u0`, so the error is the time error alone
function eig_problem(n; T = 0.4)
    dirs = [bc(t, 0, y) ~ 0.0, bc(t, 1, y) ~ 0.0, bc(t, x, 0) ~ 0.0, bc(t, x, 1) ~ 0.0]
    sys = bsys(
        [D(bce) ~ bD * laplacian(bce)],
        [bc(0, x, y) ~ sin(π * x) * sin(π * y); dirs], [bD]; T, dvs = [bce]
    )
    p = discretize(sys, LatticeDiscretization(Grid((n, n)); T = Float64))
    λ = 2 * (2cos(π / n) - 2) * n^2
    u0 = [sin(π * (i - 0.5) / n) * sin(π * (j - 0.5) / n) for i in 1:n, j in 1:n]
    return p, λ, u0
end
# 1D step data on `n` sites with zero-flux faces, `k` windows of `h`
@variables b1(..)
function step1d(n, h; k = 10)
    s = PDESystem(
        [D(b1(t, x)) ~ laplacian(b1(t, x))], [b1(0, x) ~ ifelse(x < 0.5, 1.0, 0.0)],
        [t ∈ Interval(0.0, k * h), x ∈ Interval(0.0, 1.0)], [t, x], [b1(t, x)], Any[];
        name = :s1
    )
    return discretize(s, LatticeDiscretization(Grid((n,)); T = Float64))
end
tv1(u) = sum(abs, diff(vec(u)))
# `1.5 c − rb ∂c/∂x = 0.2` at x = 1 (rb = −1: a positive diagonal, rb = +1 a negative one)
function robin_sys(v)
    @parameters crb = v
    return PDESystem(
            [D(bce) ~ 0.3 * laplacian(bce) - 2 * bce + 1],
            [
                bc(0, x, y) ~ x * y,
                1.5 * bc(t, 1, y) - crb * Differential(x)(bc(t, 1, y)) ~ 0.2,
            ], bdom(1.0), [
                t, x, y,
            ], [bce],
            [crb]; name = :crob
        ),
        crb
end
# `p`'s state after each of `k` windows of `alg`
function windows(p, alg, k; dt)
    ig = init(p, alg; dt, save_everystep = false)
    return [(step!(ig); copy(vec(ig[bce]))) for _ in 1:k], ig
end

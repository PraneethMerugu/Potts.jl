# Definitions of bounds_tests.jl that other test files use (moved here by TS1b).
using LinearAlgebra: eigvals
using LatticeFields: Problems as LFP

@parameters fx_k = 2.0 fx_a = 3.0 fx_D = 0.1
@variables fc(..) [bounds = (0.0, 1.0)] fu(..) fK(..) fo(..)
fce, fue, fKe, foe = fc(t, x, y), fu(t, x, y), fK(t, x, y), fo(t, x, y)
fdom(T = 1.0) = [t ∈ Interval(0.0, T), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
fsys(eqs, bcs, dvs, ps = Any[fx_k, fx_a, fx_D]) = PDESystem(eqs, bcs, fdom(), [t, x, y], dvs, ps; name = :fb)
# (F4-01: the owned problem field algorithms step, `LFP.field_problem` of the problem `discretize` returns)
fown(sys, n = 32) = LFP.field_problem(discretize(sys, LatticeDiscretization(Grid((n, n)); T = Float64)))
fode(sys, n = 32) = discretize(sys, LatticeDiscretization(Grid((n, n)); T = Float64))
# the rate's Jacobian at `u` by finite differences of the `:ode` path's right side, dense
function fjac(po, u)
    f(v) = (du = similar(v); po.f(du, v, po.p, 0.0); du)
    f0, m = f(u), length(u)
    J = zeros(m, m)
    for j in 1:m
        v = copy(u)
        v[j] += 1e-7
        J[:, j] = (f(v) .- f0) ./ 1e-7
    end
    return J
end
fradius(po, u) = maximum(abs, eigvals(fjac(po, u)))
# `steps` forward Euler steps of `h` from `u` on the `:ode` path's right side: the largest value
function feuler(po, u, h, steps)
    du = similar(u)
    for _ in 1:steps
        po.f(du, u, po.p, 0.0)
        u = u .+ h .* du
        all(isfinite, u) || return Inf
    end
    return maximum(abs, u)
end

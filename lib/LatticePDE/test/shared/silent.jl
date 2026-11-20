# Definitions of silent_tests.jl that other test files use.
using SciMLBase: SciMLBase, remake
using SymbolicIndexingInterface: SymbolicIndexingInterface, getp, setp
using OrdinaryDiffEqTsit5: Tsit5
using Serialization: Serialization

sdom(T = 1.0) = [t ∈ Interval(0.0, T), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
ssys(eqs, bcs, dvs, ps; T = 1.0) = PDESystem(eqs, bcs, sdom(T), [t, x, y], dvs, ps; name = :s)
# (the owned problem field algorithms step, `LFP.field_problem` of the problem `discretize` returns)
sown(sys; n = 4, inputs = (), kw...) =
    LFP.field_problem(discretize(sys, LatticeDiscretization(Grid((n, n)); T = Float64, kw...); inputs))
emsg(f) = try
    f(); ""
catch e
    sprint(showerror, e)
end

@variables mm(..) dm(..)::Bool [input = true] kq(..)::Int32 [input = true] Lc(..)
@variables dd(..)::Bool = true [input = true] kb(..)::Int32 [input = true, bounds = (1, 3)]
me, de, qe, Le, ddv, qb = mm(t, x, y), dm(t, x, y), kq(t, x, y), Lc(t, x, y), dd(t, x, y), kb(t, x, y)

# the spectral radius of a linear rate's Jacobian, by power iteration on the assembled
# operator (the ODE form's right side, column by column)
function sradius(sys, n, inputs; iters = 4000)
    o = discretize(sys, LatticeDiscretization(Grid((n, n)); T = Float64); inputs)
    N = length(o.u0)
    J = zeros(N, N)
    e, du = zero(o.u0), similar(o.u0)
    for j in 1:N
        fill!(e, 0); e[j] = 1
        o.f(du, e, o.p, 0.0)
        J[:, j] .= vec(du)
    end
    v = [1.0 + 0.1 * sin(3.7j) for j in 1:N]
    λ = 0.0
    for _ in 1:iters
        w = J * v
        λ = sqrt(sum(abs2, w)) / sqrt(sum(abs2, v))
        v = w ./ sqrt(sum(abs2, w))
    end
    return λ
end
checker(n, a, b) = [Int32(isodd(i + j) ? a : b) for i in 1:n, j in 1:n]

sok(sol) = SciMLBase.successful_retcode(sol) && all(isfinite, sol[:c, end])
# a run that grew without bound: not finite, or a million times its start (the owned path's
# `Unstable` fires on Inf/NaN only: a run at dt ρ / n = 2.1 reaches 2e130 and reports Success)
sgrew(sol) = (u = sol[:c, end]; !all(isfinite, u) || maximum(abs, u) > 1e6 * maximum(abs, sol[:c, 1]))

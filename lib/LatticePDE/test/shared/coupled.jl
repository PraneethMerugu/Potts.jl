# Definitions of coupled_tests.jl that other test files use (moved here by TS1b).
using LinearAlgebra: LinearAlgebra, I
using Logging: Logging
using KernelAbstractions: KernelAbstractions

# the dense Jacobian of the `:ode` rate of `sys` and its value at 0 (the steady state is `−A \ b`)
function cjac(sys, dims)
    po = discretize(sys, LatticeDiscretization(Grid(dims); T = Float64))
    m = length(po.u0)
    f(v) = (du = similar(v); po.f(du, v, po.p, 0.0); du)
    b0 = f(zeros(m))
    return hcat([f((e = zeros(m); e[j] = 1; e)) .- b0 for j in 1:m]...), b0
end
# (F4-01: the owned problem field algorithms step, `LFP.field_problem` of the problem `discretize` returns)
cown(sys; dims = (8, 8), T = Float64) = LFP.field_problem(discretize(sys, LatticeDiscretization(Grid(dims); T)))
const CTIGHT = DeviceGMRES(; reltol = 1.0e-12, maxiters = 200)
@variables ca(..) cb(..) cq(..) cz(..)
const cae, cbe, cqe, cze = ca(t, x, y), cb(t, x, y), cq(t, x, y), cz(t, x, y)
cmsg(f) = try
    f(); ""
catch err
    err isa ArgumentError ? err.msg : sprint(showerror, err)
end
# the q1 loop of batch 4 review r2 (with sources, so the steady state is not 0): `lhs` is `D`
# (rate rows, which QuasiSteady solves as steady rows) or `0 ~` rows
q1(δ, k; steady = false) = PDESystem(steady ?
        [0 ~ 0.1 * Δ(cae) - δ * cae + k * cbe + x, 0 ~ 0.1 * Δ(cbe) - cbe - k * cae + y] :
        [D(cae) ~ 0.1 * Δ(cae) - δ * cae + k * cbe + x, D(cbe) ~ 0.1 * Δ(cbe) - cbe - k * cae + y],
    [ca(0, x, y) ~ 0.0, cb(0, x, y) ~ 1.0], bdom(0.2), [t, x, y], [cae, cbe], Any[]; name = :q1)

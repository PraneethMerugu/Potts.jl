# Definitions of coupled_tests.jl that other test files use.
using LinearAlgebra: LinearAlgebra, I
using Logging: Logging
using KernelAbstractions: KernelAbstractions

# the dense Jacobian of the `:ode` rate of `sys` and its value at 0 (the steady state is `−A
# \ b`)
function cjac(sys, dims)
    po = discretize(sys, LatticeDiscretization(Grid(dims); T = Float64))
    m = length(po.u0)
    f(v) = (du = similar(v); po.f(du, v, po.p, 0.0); du)
    b0 = f(zeros(m))
    return hcat([f((e = zeros(m); e[j] = 1; e)) .- b0 for j in 1:m]...), b0
end
# (the owned problem field algorithms step, `LFP.field_problem` of the problem `discretize`
# returns)
function cown(sys; dims = (8, 8), T = Float64)
    return LFP.field_problem(discretize(sys, LatticeDiscretization(Grid(dims); T)))
end
const CTIGHT = LatticeGMRES(; reltol = 1.0e-12, maxiters = 200)
@variables ca(..) cb(..) cq(..) cz(..)
const cae, cbe, cqe, cze = ca(t, x, y), cb(t, x, y), cq(t, x, y), cz(t, x, y)
function cmsg(f)
    return try
        f()
        ""
    catch err
        err isa ArgumentError ? err.msg : sprint(showerror, err)
    end
end
# the loop `q1` (a steady field and a rate field that feed each other, with sources, so the
# steady state is not 0): `lhs` is `D`
# (rate rows, which QuasiSteady solves as steady rows) or `0 ~` rows
function q1(δ, k; steady = false)
    return PDESystem(
        if steady
            [
                0 ~ 0.1 * laplacian(cae) - δ * cae + k * cbe + x,
                0 ~ 0.1 * laplacian(cbe) - cbe - k * cae + y,
            ]
        else
            [
                D(cae) ~ 0.1 * laplacian(cae) - δ * cae + k * cbe + x,
                D(cbe) ~ 0.1 * laplacian(cbe) - cbe - k * cae + y,
            ]
        end,
        [ca(0, x, y) ~ 0.0, cb(0, x, y) ~ 1.0], bdom(0.2), [t, x, y], [cae, cbe], Any[];
        name = :q1
    )
end

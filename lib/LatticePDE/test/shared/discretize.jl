# Definitions of discretize_tests.jl that other test files use (moved here by TS1b).
using LatticeFields: LatticeFields
using Random: MersenneTwister
include(joinpath(pkgdir(LatticeFields), "test", "host_runner.jl"))
using LatticeFields.IR: print_program, runtime, F16, F32, F64
using LatticeFields.Compile: semantic, fingerprint_text
using LatticeFields.Schedule: plan
using LatticePDE: BC

const euler = (kb, c, r) -> c + runtime(kb, 2) * r          # rt = (t, dt)
ir(cf) = sprint(print_program, cf.program)
dom2(a = 1.0, b = 1.0) = [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, a), y ∈ Interval(0.0, b)]
pde(eqs, bcs, dvs, ps; d = dom2()) = PDESystem(eqs, bcs, d, [t, x, y], dvs, ps; name = :f)
lower64(sys, dims; kw...) = symbolic_discretize(sys, LatticeDiscretization(Grid(dims); T = Float64); update = euler, kw...)

"""Semantic program, step plan and host store of a lowered system (Float64)."""
function runner(cf)
    s = semantic(cf.program)
    sp = plan(s; options = CompileOptions(; T = Float64))
    return (s = s, sp = sp, st = HostStore(s), P = Tuple(cf.defaults))
end
field(R, key) = current(R.st, R.s, key)
function steps!(R, dt, n; P = R.P)
    for _ in 1:n
        run_step!(R.s, R.sp, R.st, P; rt = (0.0, dt))
    end
    return R
end
throws_with(f, s) = (try
                         f()
                         false
                     catch e
                         e isa ArgumentError && occursin(s, sprint(showerror, e))
                     end)

@parameters x y z Dc = 1e-3 k = 0.1 h0 = 2.0 g0 = 0.5 K0 = 2.0 cT = 0.1 dx [lattice_spacing = 1] dy [lattice_spacing = 2]
@parameters Dk[1:3] = [1.0, 2.0, 3.0]
@variables c(..) o(..) K(..) N(..) kindₛ(..)::Int32 [input = true] vel(..)[1:2] [input = true] u(..)[1:2]
Dx, Dy = Differential(x), Differential(y)
ce, oe, Ke, Ne, ke, ue = c(t, x, y), o(t, x, y), K(t, x, y), N(t, x, y), kindₛ(t, x, y), u(t, x, y)

# a 2D rate system with periodic y (a 1D profile in x, 2 rows)
function profile(bcs, n; rhs = laplacian(ce), ps = [g0, h0], steps = 20000)
    cf = lower64(pde([D(ce) ~ rhs], [bcs; c(t, x, 0) ~ c(t, x, 1)], [ce], ps), (n, 2))
    R = runner(cf)
    steps!(R, 0.2 / n^2, steps)
    xc = ((1:n) .- 0.5) ./ n
    return reshape(field(R, "c"), n, 2)[:, 1], xc
end

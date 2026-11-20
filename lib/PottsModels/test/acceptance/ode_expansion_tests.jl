# every fixed-step ODE system is expanded in place, not
# called through the per-cell `rhs` closure (D-103 review). Inside a RuntimeGeneratedFunction,
# Julia 1.12 lowers that closure to an opaque closure, built on every call whenever the rate
# is not inlined: the warm MCS allocates, and the kernel does not compile on Metal
# (`InvalidIRError`, `jl_new_opaque_closure_jlcall`). D-103 expanded only rates with a gather.
#
# Rates without a gather, each as a cell ODE and as a model ODE:
#   - `Hill`: a two-equation Hill gene circuit (`z^4 / (0.5^4 + z^4)`, `1 / (1 + (y/0.7)^3)`,
#     `exp(-time / 50)`);
#   - `If5`: a 5-level `ifelse` chain with `log1p`;
#   - `Sum16`: a sum of 16 quotients `exp(-i y) sin(i t + y) / (1 + i y^2)`;
#   - `ModelPop`: a model ODE with two population folds (`sum(volume[c] for c in cells) +
#     sum(1.0 for s in sites)`);
#   - `Mixed`: a cell population fold (`sum(z[c] for c in cells)`, `mean(y[c] …)`) plus a
#     20-term sum, two coupled cell ODEs.
# Bytes per warm MCS on the code before the fix (feat/p6-0ag at cb0372a1, 1 thread):
#   cell:  Hill 128 (Euler, Float32: 576); If5 128–544; Sum16 320 (RK4: 0); Mixed 160–640
#   model: ModelPop 208–576; ModelHill 64–288; ModelIf5 48–256; ModelSum16 48–256
# and every one of them (all three solvers, even where the CPU allocates nothing) fails to
# compile on Metal.
#
# Pinned here:
#  1. Zero warm allocations per `step!` (after two warm-up steps, every one of five further
#     steps allocates 0 bytes) for each shape, `SequentialCPM` and `CheckerboardCPM`,
#     `T = Float64` and `Float32`, `ExplicitEuler()` (default), `ExplicitEuler(substeps = 4)`
#     and `Potts.RK4()`. Controls (zero today): a plain cell rate, a plain model fold rate, and a
#     gather rate (expanded since D-103).
#  2. Metal (POTTS_GPU=metal with Metal loaded; Float32, `CheckerboardCPM(; proposal =
#     Moore(1))`): every shape compiles and runs for each fixed-step solver, its σ equals the
#     CPU Float32 run's, and its ODE values equal the CPU's bitwise, except the two Hill
#     shapes, which are within HILL_ULPS = 4 units in the last place. Measured with the
#     fix (`_ode_expand(odes) = true`, Metal.jl 1.10): every shape bitwise except Hill
#     (Euler4 1–2 ulp, RK4 1 ulp) and ModelHill (Euler4 2 ulp). The cause is the device's own
#     math, not the expansion: over 4096 Float32 points in [0.05, 3], Metal and the CPU differ
#     by up to 3 ulp for `x^4` (Julia's CPU `Float32^Int` goes through Float64; 1966 points
#     differ), 1 ulp for `exp(-x)`, 2 for `sin`, 1 for `log1p`, and 0 for `x^2`, `x^3`,
#     `x*x*x*x`, division. In the other shapes the transcendental terms are scaled by
#     1e-3/1e-4 or cut by `ifelse`, so their last-place differences do not reach the result
#     (measured bitwise); those stay bitwise.
#  3. Every shape's rates are live: the ODE values after 10 MCS (seed 7) are finite and differ
#     from the initial ones, and the two algorithms' trajectories differ where the rate reads
#     a population fold.
#  4. A gather-ODE model on Metal runs and equals the CPU Float32 run bitwise (a regression
#     guard for D-103's Metal fix), and a plain-rate control does too.

@testsetup module ODEExpansionSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
using OrdinaryDiffEqRosenbrock: Rodas5P
const ON_DEVICE = PottsDevices.on_device()
const ALGS = (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
const FIXED = (
    ("ExplicitEuler() (default)", (;)), ("ExplicitEuler(substeps = 4)", (; ode_solver = Potts.ExplicitEuler(substeps = 4))),
    ("RK4()", (; ode_solver = Potts.RK4())),
)
const HILL_ULPS = 4
# ---------------------------------------------------------------------------------------
# Models: two 4×4 cells side by side (x = 3:6 and 7:10, y = 3:6) on a 12×8 lattice.
@potts_model Hill begin
    @kinds medium A
    @variables y(cell) = 0.0 z(cell) = 1.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(y) ~ 2.0 * z^4 / (0.5^4 + z^4) - 0.3y + 0.01 * volume * exp(-time / 50)
        D(z) ~ 1.5 / (1 + (y / 0.7)^3) - 0.2z
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model If5 begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ ifelse(
        y > 0.1, 0.01volume - log1p(y), ifelse(
            y > 0.2, 0.02volume - 2log1p(y),
            ifelse(y > 0.3, 0.03volume - 3log1p(y), ifelse(y > 0.4, 0.04volume - 4log1p(y), ifelse(y > 0.5, 0.05volume - 5log1p(y), 0.0)))
        )
    )
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model Sum16 begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ 0.001 * exp(-1 * y) * sin(1 * time + y) / (1 + 1 * y^2) + 0.001 * exp(-2 * y) * sin(2 * time + y) / (1 + 2 * y^2) +
        0.001 * exp(-3 * y) * sin(3 * time + y) / (1 + 3 * y^2) + 0.001 * exp(-4 * y) * sin(4 * time + y) / (1 + 4 * y^2) +
        0.001 * exp(-5 * y) * sin(5 * time + y) / (1 + 5 * y^2) + 0.001 * exp(-6 * y) * sin(6 * time + y) / (1 + 6 * y^2) +
        0.001 * exp(-7 * y) * sin(7 * time + y) / (1 + 7 * y^2) + 0.001 * exp(-8 * y) * sin(8 * time + y) / (1 + 8 * y^2) +
        0.001 * exp(-9 * y) * sin(9 * time + y) / (1 + 9 * y^2) + 0.001 * exp(-10 * y) * sin(10 * time + y) / (1 + 10 * y^2) +
        0.001 * exp(-11 * y) * sin(11 * time + y) / (1 + 11 * y^2) + 0.001 * exp(-12 * y) * sin(12 * time + y) / (1 + 12 * y^2) +
        0.001 * exp(-13 * y) * sin(13 * time + y) / (1 + 13 * y^2) + 0.001 * exp(-14 * y) * sin(14 * time + y) / (1 + 14 * y^2) +
        0.001 * exp(-15 * y) * sin(15 * time + y) / (1 + 15 * y^2) + 0.001 * exp(-16 * y) * sin(16 * time + y) / (1 + 16 * y^2)
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model ModelPop begin
    @kinds medium A
    @variables g(model) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(g) ~ 0.001 * sum(volume[c] for c in cells) + 0.001 * sum(1.0 for s in sites) - 0.1g
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model ExpansionMixed begin
    @kinds medium A
    @variables y(cell) = 0.0 z(cell) = 1.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(y) ~ 0.5 * (sum(z[c] for c in cells) / 2 - y) + 0.0001 * exp(-1 * z) * cos(1 * y) + 0.0001 * exp(-2 * z) * cos(2 * y) +
            0.0001 * exp(-3 * z) * cos(3 * y) + 0.0001 * exp(-4 * z) * cos(4 * y) + 0.0001 * exp(-5 * z) * cos(5 * y) +
            0.0001 * exp(-6 * z) * cos(6 * y) + 0.0001 * exp(-7 * z) * cos(7 * y) + 0.0001 * exp(-8 * z) * cos(8 * y) +
            0.0001 * exp(-9 * z) * cos(9 * y) + 0.0001 * exp(-10 * z) * cos(10 * y) + 0.0001 * exp(-11 * z) * cos(11 * y) +
            0.0001 * exp(-12 * z) * cos(12 * y) + 0.0001 * exp(-13 * z) * cos(13 * y) + 0.0001 * exp(-14 * z) * cos(14 * y) +
            0.0001 * exp(-15 * z) * cos(15 * y) + 0.0001 * exp(-16 * z) * cos(16 * y) + 0.0001 * exp(-17 * z) * cos(17 * y) +
            0.0001 * exp(-18 * z) * cos(18 * y) + 0.0001 * exp(-19 * z) * cos(19 * y) + 0.0001 * exp(-20 * z) * cos(20 * y)
        D(z) ~ -0.1z + 0.01 * mean(y[c] for c in cells)
    end
    @sweep Metropolis(; temperature = 1.0)
end
# model-scope versions of the cell shapes
@potts_model ModelHill begin
    @kinds medium A
    @variables g(model) = 0.0 h(model) = 1.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(g) ~ 2.0 * h^4 / (0.5^4 + h^4) - 0.3g + 0.01 * sum(volume[c] for c in cells) * exp(-time / 50)
        D(h) ~ 1.5 / (1 + (g / 0.7)^3) - 0.2h
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model ModelIf5 begin
    @kinds medium A
    @variables g(model) = 1.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(g) ~ ifelse(
        g > 0.1, 0.0005 * sum(volume[c] for c in cells) - log1p(g), ifelse(
            g > 0.2, 0.02 - 2log1p(g),
            ifelse(g > 0.3, 0.03 - 3log1p(g), ifelse(g > 0.4, 0.04 - 4log1p(g), ifelse(g > 0.5, 0.05 - 5log1p(g), 0.0)))
        )
    )
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model ModelSum16 begin
    @kinds medium A
    @variables g(model) = 1.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(g) ~ 0.001 * exp(-1 * g) * sin(1 * time + g) / (1 + 1 * g^2) + 0.001 * exp(-2 * g) * sin(2 * time + g) / (1 + 2 * g^2) +
        0.001 * exp(-3 * g) * sin(3 * time + g) / (1 + 3 * g^2) + 0.001 * exp(-4 * g) * sin(4 * time + g) / (1 + 4 * g^2) +
        0.001 * exp(-5 * g) * sin(5 * time + g) / (1 + 5 * g^2) + 0.001 * exp(-6 * g) * sin(6 * time + g) / (1 + 6 * g^2) +
        0.001 * exp(-7 * g) * sin(7 * time + g) / (1 + 7 * g^2) + 0.001 * exp(-8 * g) * sin(8 * time + g) / (1 + 8 * g^2) +
        0.001 * exp(-9 * g) * sin(9 * time + g) / (1 + 9 * g^2) + 0.001 * exp(-10 * g) * sin(10 * time + g) / (1 + 10 * g^2) +
        0.001 * exp(-11 * g) * sin(11 * time + g) / (1 + 11 * g^2) + 0.001 * exp(-12 * g) * sin(12 * time + g) / (1 + 12 * g^2) +
        0.001 * exp(-13 * g) * sin(13 * time + g) / (1 + 13 * g^2) + 0.001 * exp(-14 * g) * sin(14 * time + g) / (1 + 14 * g^2) +
        0.001 * exp(-15 * g) * sin(15 * time + g) / (1 + 15 * g^2) + 0.001 * exp(-16 * g) * sin(16 * time + g) / (1 + 16 * g^2) +
        0.001 * sum(volume[c] for c in cells)
    @sweep Metropolis(; temperature = 1.0)
end
# controls: rates that inline today (zero bytes, compile on Metal)
@potts_model Plain begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ 0.01 * volume - 0.1y
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model ModelPlain begin
    @kinds medium A
    @variables g(model) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(g) ~ 0.001 * sum(volume[c] for c in cells) - 0.1g
    @sweep Metropolis(; temperature = 1.0)
end
# a gather in a cell-ODE rate (expanded since D-103)
@potts_model Gather begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ 0.01 * sum(volume[owner[n]] for n in Moore(1)(42)) - 0.1y
    @sweep Metropolis(; temperature = 1.0)
end
const CELL_SHAPES = (Hill, If5, Sum16, ExpansionMixed)
const MODEL_SHAPES = (ModelPop, ModelHill, ModelIf5, ModelSum16)
const SHAPES = (CELL_SHAPES..., MODEL_SHAPES...)
const CONTROLS = (Plain, ModelPlain, Gather)
const HILLS = (Hill, ModelHill)
cellscope(M) = M in (CELL_SHAPES..., Plain, Gather)
sigma() = (s = zeros(Int32, 12, 8); s[3:6, 3:6] .= 1; s[7:10, 3:6] .= 2; s)
function expansion_op(M)
    if cellscope(M)
        return [ownership => sigma(), kind => [:A, :A], :y => [1.0, 2.0]]
    else
        return [ownership => sigma(), kind => [:A, :A]]
    end
end
problem(M, tspan; T = Float64, kw...) = PottsProblem(M(; name = :x), expansion_op(M), tspan; T, seed = 7, kw...)
"""The ODE unknowns of `u` (cells' `y` then `z`; the model's `g` then `h`), as Float64."""
function expansion_values(M, u)
    cellscope(M) && return Float64[Array(u.cell.y)..., (haskey(u.cell, :z) ? Array(u.cell.z) : Float64[])...]
    return Float64[Array(getproperty(u.model, n))[1] for n in (:g, :h) if haskey(u.model, n)]
end
"""Bytes allocated by each of five warm `step!`s (after two warm-up steps)."""
function warm_allocs(prob, alg)
    integ = init(prob, alg; save_start = false, save_end = false, save_everystep = false)
    step!(integ)
    step!(integ)
    out = Int[]
    for _ in 1:5
        push!(out, @allocated step!(integ))
    end
    return out
end
"""Units in the last place between two Float32 values of the same sign."""
expansion_ulps(a::Float32, b::Float32) = signbit(a) == signbit(b) ? abs(Int64(reinterpret(Int32, a)) - Int64(reinterpret(Int32, b))) : typemax(Int64)
const expansion_N = 10
# MCS of the fixtures run
"""CPU and device runs (Float32, CheckerboardCPM, 10 MCS) of `M` with solver keywords `kw`:
`(cpu, device)` final states, `device` the exception if the device run threw."""
function cpu_metal(M, kw)
    prob = problem(M, (0, expansion_N); T = Float32, kw...)
    alg = CheckerboardCPM(; proposal = Moore(1))
    cpu = solve(prob, alg).u[end]
    gpu = try
        solve(prob, alg; backend = PottsDevices.device_backend()).u[end]
    catch e
        e
    end
    return cpu, gpu
end
"""Independent `Rodas5P` (`reltol = 1e-12, abstol = 1e-12`) ODE integration over the recorded
`σ` trajectory of `sol`, computing cell volumes by hand from each post-sweep `σ`."""
function rodas_ref(M, sol)
    u = Float64.(expansion_values(M, sol.u[1]))
    nsites = Float64(length(sol.u[1].ownership))
    for k in 0:(expansion_N - 1)
        σ = Array(sol.u[k + 2].ownership)
        v1 = Float64(count(==(1), σ))
        v2 = Float64(count(==(2), σ))
        rhs = if M === Hill
            (y, _, t) -> [
                2.0 * y[3]^4 / (0.5^4 + y[3]^4) - 0.3 * y[1] + 0.01 * v1 * exp(-t / 50),
                2.0 * y[4]^4 / (0.5^4 + y[4]^4) - 0.3 * y[2] + 0.01 * v2 * exp(-t / 50),
                1.5 / (1 + (y[1] / 0.7)^3) - 0.2 * y[3],
                1.5 / (1 + (y[2] / 0.7)^3) - 0.2 * y[4],
            ]
        elseif M === If5
            f_if5(y, v) = ifelse(
                y > 0.1, 0.01 * v - log1p(y),
                ifelse(
                    y > 0.2, 0.02 * v - 2 * log1p(y),
                    ifelse(
                        y > 0.3, 0.03 * v - 3 * log1p(y),
                        ifelse(
                            y > 0.4, 0.04 * v - 4 * log1p(y),
                            ifelse(y > 0.5, 0.05 * v - 5 * log1p(y), 0.0)
                        )
                    )
                )
            )
            (y, _, _) -> [f_if5(y[1], v1), f_if5(y[2], v2)]
        elseif M === Sum16
            f_s16(y, t) = sum(0.001 * exp(-i * y) * sin(i * t + y) / (1 + i * y^2) for i in 1:16)
            (y, _, t) -> [f_s16(y[1], t), f_s16(y[2], t)]
        elseif M === ExpansionMixed
            # Cross-cell population folds use the start-of-MCS Jacobi scratch values.
            sz0 = u[3] + u[4]
            my0 = (u[1] + u[2]) / 2
            (y, _, _) -> begin
                f_mix(yc, zc) = 0.5 * (sz0 / 2 - yc) + sum(0.0001 * exp(-i * zc) * cos(i * yc) for i in 1:20)
                [f_mix(y[1], y[3]), f_mix(y[2], y[4]), -0.1 * y[3] + 0.01 * my0, -0.1 * y[4] + 0.01 * my0]
            end
        elseif M === ModelPop
            (y, _, _) -> [0.001 * (v1 + v2) + 0.001 * nsites - 0.1 * y[1]]
        elseif M === ModelHill
            (y, _, t) -> [
                2.0 * y[2]^4 / (0.5^4 + y[2]^4) - 0.3 * y[1] + 0.01 * (v1 + v2) * exp(-t / 50),
                1.5 / (1 + (y[1] / 0.7)^3) - 0.2 * y[2],
            ]
        elseif M === ModelIf5
            (y, _, _) -> begin
                g = y[1]
                [
                    ifelse(
                        g > 0.1, 0.0005 * (v1 + v2) - log1p(g),
                        ifelse(
                            g > 0.2, 0.02 - 2 * log1p(g),
                            ifelse(
                                g > 0.3, 0.03 - 3 * log1p(g),
                                ifelse(
                                    g > 0.4, 0.04 - 4 * log1p(g),
                                    ifelse(g > 0.5, 0.05 - 5 * log1p(g), 0.0)
                                )
                            )
                        )
                    ),
                ]
            end
        elseif M === ModelSum16
            (y, _, t) -> [
                sum(0.001 * exp(-i * y[1]) * sin(i * t + y[1]) / (1 + i * y[1]^2) for i in 1:16) + 0.001 * (v1 + v2),
            ]
        else
            error("unknown Expansion shape: $M")
        end
        ode_prob = CorePotts.SciMLBase.ODEProblem(rhs, u, (Float64(k), Float64(k + 1)))
        # Tight 1e-12 reference tolerance makes Rodas5P discretization error negligible
        # compared to the fixed-step Potts ODE solvers under test.
        u = CorePotts.SciMLBase.solve(
            ode_prob, Rodas5P(); reltol = 1.0e-12, abstol = 1.0e-12,
            save_everystep = false
        ).u[end]
    end
    return u
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "ode expansion: the fixtures match independent Rodas5P reference over recorded σ" setup = [ODEExpansionSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # CPU
    @testset "ode expansion: the fixtures match independent Rodas5P reference over recorded σ" begin
        # Every shape's compiled ODE matches an independent Rodas5P integration over the
        # recorded σ trajectory, with 4-substep ExplicitEuler strictly closer than 1-substep,
        # and RK4 (dt = 1.0) within rtol = 1e-3, atol = 1e-6 for smooth oscillatory rates
        # (wider for steep Hill switching and discontinuous ModelIf5).
        got = Dict{Tuple{Symbol, String, Symbol}, Vector{Float64}}()
        for M in SHAPES, (label, kw) in FIXED, alg in ALGS
            sol = solve(problem(M, (0, expansion_N); kw...), alg; saveat = 0:expansion_N)
            v = expansion_values(M, sol.u[end])
            ref = rodas_ref(M, sol)
            got[(nameof(M), label, nameof(typeof(alg)))] = v
            @test all(isfinite, v)
            @test v != expansion_values(M, problem(M, (0, 0)).u0)
            if label == "RK4()"
                # 4th-order RK4 with dt = 1.0: oscillatory rates (sin(16t), cos(20y)) match
                # within 1e-3; steep Hill switching (z^4 / (0.5^4 + z^4)) has ~5% dt = 1.0 error;
                # ModelIf5 has a discontinuous switch at g = 0.1 that dt = 1.0 overshoots by ~0.04.
                if M === ModelIf5
                    @test isapprox(v, ref; rtol = 0.05, atol = 0.05)
                elseif M in HILLS
                    @test isapprox(v, ref; rtol = 0.06, atol = 1.0e-4)
                else
                    @test isapprox(v, ref; rtol = 1.0e-3, atol = 1.0e-6)
                end
            elseif label == "ExplicitEuler(substeps = 4)"
                # dt = 0.25 1st-order Euler error over 10 MCS (~0.1 for steep Hill rates).
                @test isapprox(v, ref; rtol = 0.15, atol = 0.15)
            else
                # dt = 1.0 1st-order Euler error over 10 MCS (~0.6 for steep Hill rates).
                @test isapprox(v, ref; rtol = 0.7, atol = 0.7)
            end
        end
        for M in SHAPES, alg in ALGS
            sol1 = solve(problem(M, (0, expansion_N)), alg; saveat = 0:expansion_N)
            sol4 = solve(problem(M, (0, expansion_N); ode_solver = Potts.ExplicitEuler(substeps = 4)), alg; saveat = 0:expansion_N)
            err1 = maximum(abs.(expansion_values(M, sol1.u[end]) .- rodas_ref(M, sol1)))
            err4 = maximum(abs.(expansion_values(M, sol4.u[end]) .- rodas_ref(M, sol4)))
            @test err4 < err1
        end
        v = got[(:Hill, "ExplicitEuler() (default)", :CheckerboardCPM)]
        @test v[1] != v[2] && v[3] != v[4]
        # the population folds read the state: the two algorithms' trajectories differ
        for M in (ModelPop, ModelHill)
            @test got[(nameof(M), "RK4()", :SequentialCPM)] != got[(nameof(M), "RK4()", :CheckerboardCPM)]
        end
    end
end

@testitem "ode expansion: zero warm allocations, controls" setup = [ODEExpansionSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "ode expansion: zero warm allocations, controls" begin
        for M in CONTROLS, T in (Float64, Float32), (label, kw) in FIXED, alg in ALGS
            a = warm_allocs(problem(M, (0, 100); T, kw...), alg)
            @test all(iszero, a)
            all(iszero, a) || @info "ode expansion control allocates: $(nameof(M)) $T $label $(nameof(typeof(alg))) bytes per step = $a"
        end
    end
end

@testitem "ode expansion: zero warm allocations" setup = [ODEExpansionSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "ode expansion: zero warm allocations ($(nameof(M)))" for M in SHAPES
        for T in (Float64, Float32), (label, kw) in FIXED, alg in ALGS
            a = warm_allocs(problem(M, (0, 100); T, kw...), alg)
            @test all(iszero, a)
            all(iszero, a) || @info "ode expansion allocates: $(nameof(M)) $T $label $(nameof(typeof(alg))) bytes per step = $a"
        end
    end
end

@testitem "ode expansion: every shape compiles and runs on the device, equal to the CPU Float32 run" setup = [ODEExpansionSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # Metal
    @testset "ode expansion: every shape compiles and runs on the device, equal to the CPU Float32 run ($(nameof(M)))" for M in SHAPES
        if ON_DEVICE
            for (label, kw) in FIXED
                cpu, gpu = cpu_metal(M, kw)
                ran = !(gpu isa Exception)
                @test ran
                if !ran
                    s = sprint(showerror, gpu)
                    @info "ode expansion device: $(nameof(M)) $label does not run" error = first(s, 300) opaque_closure = occursin("opaque_closure", s)
                    continue
                end
                @test Array(gpu.ownership) == Array(cpu.ownership)
                c, g = Float32.(expansion_values(M, cpu)), Float32.(expansion_values(M, gpu))
                if M in HILLS
                    @test maximum(expansion_ulps.(c, g)) <= HILL_ULPS
                else
                    @test g == c
                end
                g == c || @info "ode expansion device vs CPU: $(nameof(M)) $label" cpu = c device = g ulps = expansion_ulps.(c, g)
            end
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end

@testitem "ode expansion: a gather-ODE model and a plain control on the device (bitwise to the CPU Float32 run)" setup = [ODEExpansionSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "ode expansion: a gather-ODE model and a plain control on the device (bitwise to the CPU Float32 run)" begin
        if ON_DEVICE
            for M in (Gather, Plain, ModelPlain), (label, kw) in FIXED
                cpu, gpu = cpu_metal(M, kw)
                @test !(gpu isa Exception)
                gpu isa Exception && (@info "ode expansion device: $(nameof(M)) $label does not run" error = first(sprint(showerror, gpu), 300); continue)
                @test Array(gpu.ownership) == Array(cpu.ownership)
                @test expansion_values(M, gpu) == expansion_values(M, cpu)
            end
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end

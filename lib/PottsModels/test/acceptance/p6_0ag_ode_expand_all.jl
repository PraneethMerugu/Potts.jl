# P6.0ag (ROADMAP Phase 6, step 0): every fixed-step ODE system is expanded in place, not
# called through the per-cell `rhs` closure (D-103 review). Inside a RuntimeGeneratedFunction,
# Julia 1.12 lowers that closure to an opaque closure, built on every call whenever the rate
# is not inlined: the warm MCS allocates, and the kernel does not compile on Metal
# (`InvalidIRError`, `jl_new_opaque_closure_jlcall`). D-103 expanded only rates with a gather.
# Frozen (AUTONOMY §7.3).
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
#     and `RK4()`. Controls (zero today): a plain cell rate, a plain model fold rate, and a
#     gather rate (expanded since D-103).
#  2. Metal (POTTS_GPU=metal with Metal loaded; Float32, `CheckerboardCPM(; proposal =
#     Moore(1))`): every shape compiles and runs for each fixed-step solver, its σ equals the
#     CPU Float32 run's, and its ODE values equal the CPU's bitwise, except the two Hill
#     shapes, which are within P60AG_HILL_ULPS = 4 units in the last place. Measured with the
#     fix (`_ode_expand(odes) = true`, Metal.jl 1.10): every shape bitwise except Hill
#     (Euler4 1–2 ulp, RK4 1 ulp) and ModelHill (Euler4 2 ulp). The cause is the device's own
#     math, not the expansion: over 4096 Float32 points in [0.05, 3], Metal and the CPU differ
#     by up to 3 ulp for `x^4` (Julia's CPU `Float32^Int` goes through Float64; 1966 points
#     differ), 1 ulp for `exp(-x)`, 2 for `sin`, 1 for `log1p`, and 0 for `x^2`, `x^3`,
#     `x*x*x*x`, division. In the other shapes the transcendental terms are scaled by
#     1e-3/1e-4 or cut by `ifelse`, so their last-place differences do not reach the result
#     (measured bitwise); those stay bitwise.
#  3. CPU results unchanged: the ODE values after 10 MCS (seed 7) of every shape, algorithm,
#     solver and T equal the values recorded inline from the code before the fix, bitwise;
#     model-scope shapes within 8 ulp (D-105: their sum's term order varies between builds).
#     (Forcing expansion on that code reproduces them all bitwise.)
#  4. A gather-ODE model on Metal runs and equals the CPU Float32 run bitwise (a regression
#     guard for D-103's Metal fix), and a plain-rate control does too.
#  5. Problem fingerprints of published models WITHOUT any ODE are unchanged (GranerGlazier,
#     MerksVasculogenesis). Fingerprints of models with an ODE change by design and are not
#     pinned.
using Potts: CorePotts

const P60AG_ON_METAL = get(ENV, "POTTS_GPU", "") == "metal" && isdefined(Main, :Metal)
const P60AG_ALGS = (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
const P60AG_FIXED = (("ExplicitEuler() (default)", (;)), ("ExplicitEuler(substeps = 4)", (; ode_solver = Potts.ExplicitEuler(substeps = 4))),
    ("RK4()", (; ode_solver = Potts.RK4())))
const P60AG_HILL_ULPS = 4

# ---------------------------------------------------------------------------------------
# Models: two 4×4 cells side by side (x = 3:6 and 7:10, y = 3:6) on a 12×8 lattice.

@potts_model P60agHill begin
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
@potts_model P60agIf5 begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ ifelse(y > 0.1, 0.01volume - log1p(y), ifelse(y > 0.2, 0.02volume - 2log1p(y),
        ifelse(y > 0.3, 0.03volume - 3log1p(y), ifelse(y > 0.4, 0.04volume - 4log1p(y), ifelse(y > 0.5, 0.05volume - 5log1p(y), 0.0)))))
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model P60agSum16 begin
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

@potts_model P60agModelPop begin
    @kinds medium A
    @variables g(model) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(g) ~ 0.001 * sum(volume[c] for c in cells) + 0.001 * sum(1.0 for s in sites) - 0.1g
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model P60agMixed begin
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
@potts_model P60agModelHill begin
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

@potts_model P60agModelIf5 begin
    @kinds medium A
    @variables g(model) = 1.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(g) ~ ifelse(g > 0.1, 0.0005 * sum(volume[c] for c in cells) - log1p(g), ifelse(g > 0.2, 0.02 - 2log1p(g),
        ifelse(g > 0.3, 0.03 - 3log1p(g), ifelse(g > 0.4, 0.04 - 4log1p(g), ifelse(g > 0.5, 0.05 - 5log1p(g), 0.0)))))
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model P60agModelSum16 begin
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
@potts_model P60agPlain begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ 0.01 * volume - 0.1y
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model P60agModelPlain begin
    @kinds medium A
    @variables g(model) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(g) ~ 0.001 * sum(volume[c] for c in cells) - 0.1g
    @sweep Metropolis(; temperature = 1.0)
end

# a gather in a cell-ODE rate (expanded since D-103)
@potts_model P60agGather begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ 0.01 * sum(volume[owner[n]] for n in Moore(1)(42)) - 0.1y
    @sweep Metropolis(; temperature = 1.0)
end

const P60AG_CELL_SHAPES = (P60agHill, P60agIf5, P60agSum16, P60agMixed)
const P60AG_MODEL_SHAPES = (P60agModelPop, P60agModelHill, P60agModelIf5, P60agModelSum16)
const P60AG_SHAPES = (P60AG_CELL_SHAPES..., P60AG_MODEL_SHAPES...)
const P60AG_CONTROLS = (P60agPlain, P60agModelPlain, P60agGather)
const P60AG_HILLS = (P60agHill, P60agModelHill)

p60ag_cellscope(M) = M in (P60AG_CELL_SHAPES..., P60agPlain, P60agGather)
p60ag_sigma() = (s = zeros(Int32, 12, 8); s[3:6, 3:6] .= 1; s[7:10, 3:6] .= 2; s)
p60ag_op(M) = p60ag_cellscope(M) ? [ownership => p60ag_sigma(), kind => [:A, :A], :y => [1.0, 2.0]] :
              [ownership => p60ag_sigma(), kind => [:A, :A]]
p60ag_problem(M, tspan; T = Float64, kw...) = PottsProblem(M(; name = :x), p60ag_op(M), tspan; T, seed = 7, kw...)

"""The ODE unknowns of `u` (cells' `y` then `z`; the model's `g` then `h`), as Float64."""
function p60ag_values(M, u)
    p60ag_cellscope(M) && return Float64[Array(u.cell.y)..., (haskey(u.cell, :z) ? Array(u.cell.z) : Float64[])...]
    return Float64[Array(getproperty(u.model, n))[1] for n in (:g, :h) if haskey(u.model, n)]
end

"""Bytes allocated by each of five warm `step!`s (after two warm-up steps)."""
function p60ag_warm_allocs(prob, alg)
    integ = init(prob, alg; save_start = false, save_end = false)
    step!(integ)
    step!(integ)
    out = Int[]
    for _ in 1:5
        push!(out, @allocated step!(integ))
    end
    return out
end

"""Units in the last place between two Float32 values of the same sign."""
p60ag_ulps(a::Float32, b::Float32) = signbit(a) == signbit(b) ? abs(Int64(reinterpret(Int32, a)) - Int64(reinterpret(Int32, b))) : typemax(Int64)

const p60ag_N = 10                                     # MCS of the recorded results

# ---------------------------------------------------------------------------------------
# Recorded on the code before the fix (feat/p6-0ag at cb0372a1, CPU, 1 thread), seed 7, 10 MCS:
# (model, solver label, algorithm, T) => ODE unknowns after 10 MCS (`p60ag_values`; Float32
# results widened exactly to Float64).

const P60AG_RESULTS = Dict{Tuple{Symbol, String, Symbol, DataType}, Vector{Float64}}(
    (:P60agHill, "ExplicitEuler() (default)", :SequentialCPM, Float64) => [2.0989936514165404, 1.47515671654117, 0.21222627913174308, 0.25537438523178735],
    (:P60agHill, "ExplicitEuler() (default)", :SequentialCPM, Float32) => [2.0989933013916016, 1.475156545639038, 0.2122262865304947, 0.25537440180778503],
    (:P60agHill, "ExplicitEuler() (default)", :CheckerboardCPM, Float64) => [2.08224356583383, 1.4937561468405993, 0.2121555373113417, 0.25605480154316057],
    (:P60agHill, "ExplicitEuler() (default)", :CheckerboardCPM, Float32) => [2.0822432041168213, 1.4937560558319092, 0.2121555507183075, 0.2560548186302185],
    (:P60agHill, "ExplicitEuler(substeps = 4)", :SequentialCPM, Float64) => [1.871310594453223, 1.6707567769927003, 0.25499898821743605, 0.2777098480566056],
    (:P60agHill, "ExplicitEuler(substeps = 4)", :SequentialCPM, Float32) => [1.8713103532791138, 1.670756459236145, 0.2549990117549896, 0.2777099311351776],
    (:P60agHill, "ExplicitEuler(substeps = 4)", :CheckerboardCPM, Float64) => [1.8564638319271034, 1.6870687296134126, 0.2553740979659346, 0.27741134626925756],
    (:P60agHill, "ExplicitEuler(substeps = 4)", :CheckerboardCPM, Float32) => [1.8564633131027222, 1.6870684623718262, 0.25537413358688354, 0.2774113714694977],
    (:P60agHill, "RK4()", :SequentialCPM, Float64) => [1.8690474532125243, 1.7332247875127564, 0.2681659604633495, 0.2819629454824082],
    (:P60agHill, "RK4()", :SequentialCPM, Float32) => [1.8690471649169922, 1.733224630355835, 0.2681660056114197, 0.2819629907608032],
    (:P60agHill, "RK4()", :CheckerboardCPM, Float64) => [1.854904414789083, 1.7485548534062567, 0.2686960029116616, 0.2815208830580529],
    (:P60agHill, "RK4()", :CheckerboardCPM, Float32) => [1.854904294013977, 1.7485545873641968, 0.26869601011276245, 0.28152093291282654],
    (:P60agIf5, "ExplicitEuler() (default)", :SequentialCPM, Float64) => [0.18224735265994974, 0.1633032283809401],
    (:P60agIf5, "ExplicitEuler() (default)", :SequentialCPM, Float32) => [0.1822473555803299, 0.1633032262325287],
    (:P60agIf5, "ExplicitEuler() (default)", :CheckerboardCPM, Float64) => [0.16206953668186, 0.18477174234273244],
    (:P60agIf5, "ExplicitEuler() (default)", :CheckerboardCPM, Float32) => [0.16206952929496765, 0.18477174639701843],
    (:P60agIf5, "ExplicitEuler(substeps = 4)", :SequentialCPM, Float64) => [0.17864280623322212, 0.16569090537772155],
    (:P60agIf5, "ExplicitEuler(substeps = 4)", :SequentialCPM, Float32) => [0.17864279448986053, 0.16569089889526367],
    (:P60agIf5, "ExplicitEuler(substeps = 4)", :CheckerboardCPM, Float64) => [0.16367229548328718, 0.18235996019917133],
    (:P60agIf5, "ExplicitEuler(substeps = 4)", :CheckerboardCPM, Float32) => [0.1636722832918167, 0.1823599636554718],
    (:P60agIf5, "RK4()", :SequentialCPM, Float64) => [0.17819080944612847, 0.1666252072247134],
    (:P60agIf5, "RK4()", :SequentialCPM, Float32) => [0.17819081246852875, 0.16662520170211792],
    (:P60agIf5, "RK4()", :CheckerboardCPM, Float64) => [0.16431157399256932, 0.18210114313964992],
    (:P60agIf5, "RK4()", :CheckerboardCPM, Float32) => [0.16431155800819397, 0.18210114538669586],
    (:P60agSum16, "ExplicitEuler() (default)", :SequentialCPM, Float64) => [1.0002832183334966, 1.9999897149060266],
    (:P60agSum16, "ExplicitEuler() (default)", :SequentialCPM, Float32) => [1.0002832412719727, 1.9999897480010986],
    (:P60agSum16, "ExplicitEuler() (default)", :CheckerboardCPM, Float64) => [1.0002832183334966, 1.9999897149060266],
    (:P60agSum16, "ExplicitEuler() (default)", :CheckerboardCPM, Float32) => [1.0002832412719727, 1.9999897480010986],
    (:P60agSum16, "ExplicitEuler(substeps = 4)", :SequentialCPM, Float64) => [1.0001665844049756, 1.9999717145521665],
    (:P60agSum16, "ExplicitEuler(substeps = 4)", :SequentialCPM, Float32) => [1.000166893005371, 1.9999715089797974],
    (:P60agSum16, "ExplicitEuler(substeps = 4)", :CheckerboardCPM, Float64) => [1.0001665844049756, 1.9999717145521665],
    (:P60agSum16, "ExplicitEuler(substeps = 4)", :CheckerboardCPM, Float32) => [1.000166893005371, 1.9999715089797974],
    (:P60agSum16, "RK4()", :SequentialCPM, Float64) => [1.0001233098077196, 1.9999663938553882],
    (:P60agSum16, "RK4()", :SequentialCPM, Float32) => [1.0001235008239746, 1.9999663829803467],
    (:P60agSum16, "RK4()", :CheckerboardCPM, Float64) => [1.0001233098077196, 1.9999663938553882],
    (:P60agSum16, "RK4()", :CheckerboardCPM, Float32) => [1.0001235008239746, 1.9999663829803467],
    (:P60agModelPop, "ExplicitEuler() (default)", :SequentialCPM, Float64) => [0.8332754040829999],
    (:P60agModelPop, "ExplicitEuler() (default)", :SequentialCPM, Float32) => [0.8332753777503967],
    (:P60agModelPop, "ExplicitEuler() (default)", :CheckerboardCPM, Float64) => [0.8327861333929999],
    (:P60agModelPop, "ExplicitEuler() (default)", :CheckerboardCPM, Float32) => [0.8327861428260803],
    (:P60agModelPop, "ExplicitEuler(substeps = 4)", :SequentialCPM, Float64) => [0.8146732646984259],
    (:P60agModelPop, "ExplicitEuler(substeps = 4)", :SequentialCPM, Float32) => [0.8146733045578003],
    (:P60agModelPop, "ExplicitEuler(substeps = 4)", :CheckerboardCPM, Float64) => [0.8141868799343117],
    (:P60agModelPop, "ExplicitEuler(substeps = 4)", :CheckerboardCPM, Float32) => [0.8141869306564331],
    (:P60agModelPop, "RK4()", :SequentialCPM, Float64) => [0.8087329557142415],
    (:P60agModelPop, "RK4()", :SequentialCPM, Float32) => [0.8087329268455505],
    (:P60agModelPop, "RK4()", :CheckerboardCPM, Float64) => [0.8082476634450528],
    (:P60agModelPop, "RK4()", :CheckerboardCPM, Float32) => [0.8082476854324341],
    (:P60agMixed, "ExplicitEuler() (default)", :SequentialCPM, Float64) => [0.48669957553163773, 0.4876742020938126, 0.4013277667210781, 0.4013277667210781],
    (:P60agMixed, "ExplicitEuler() (default)", :SequentialCPM, Float32) => [0.48669958114624023, 0.48767417669296265, 0.4013277590274811, 0.4013277590274811],
    (:P60agMixed, "ExplicitEuler() (default)", :CheckerboardCPM, Float64) => [0.48669957553163773, 0.4876742020938126, 0.4013277667210781, 0.4013277667210781],
    (:P60agMixed, "ExplicitEuler() (default)", :CheckerboardCPM, Float32) => [0.48669958114624023, 0.48767417669296265, 0.4013277590274811, 0.4013277590274811],
    (:P60agMixed, "ExplicitEuler(substeps = 4)", :SequentialCPM, Float64) => [0.5230593941395449, 0.527843956015992, 0.4177034123704255, 0.4177034123704255],
    (:P60agMixed, "ExplicitEuler(substeps = 4)", :SequentialCPM, Float32) => [0.5230592489242554, 0.5278437733650208, 0.4177033007144928, 0.4177033007144928],
    (:P60agMixed, "ExplicitEuler(substeps = 4)", :CheckerboardCPM, Float64) => [0.5230593941395449, 0.527843956015992, 0.4177034123704255, 0.4177034123704255],
    (:P60agMixed, "ExplicitEuler(substeps = 4)", :CheckerboardCPM, Float32) => [0.5230592489242554, 0.5278437733650208, 0.4177033007144928, 0.4177033007144928],
    (:P60agMixed, "RK4()", :SequentialCPM, Float64) => [0.5340884971803392, 0.5408467128640905, 0.4228294604145212, 0.4228294604145212],
    (:P60agMixed, "RK4()", :SequentialCPM, Float32) => [0.5340884923934937, 0.5408467650413513, 0.4228295087814331, 0.4228295087814331],
    (:P60agMixed, "RK4()", :CheckerboardCPM, Float64) => [0.5340884971803392, 0.5408467128640905, 0.4228294604145212, 0.4228294604145212],
    (:P60agMixed, "RK4()", :CheckerboardCPM, Float32) => [0.5340884923934937, 0.5408467650413513, 0.4228295087814331, 0.4228295087814331],
    (:P60agModelHill, "ExplicitEuler() (default)", :SequentialCPM, Float64) => [4.872155234703284, 0.32776905542037227],
    (:P60agModelHill, "ExplicitEuler() (default)", :SequentialCPM, Float32) => [4.87215518951416, 0.32776907086372375],
    (:P60agModelHill, "ExplicitEuler() (default)", :CheckerboardCPM, Float64) => [4.872560739224415, 0.32777736930137036],
    (:P60agModelHill, "ExplicitEuler() (default)", :CheckerboardCPM, Float32) => [4.872560024261475, 0.32777732610702515],
    (:P60agModelHill, "ExplicitEuler(substeps = 4)", :SequentialCPM, Float64) => [3.365760547195339, 0.2608948833674407],
    (:P60agModelHill, "ExplicitEuler(substeps = 4)", :SequentialCPM, Float32) => [3.3657610416412354, 0.26089489459991455],
    (:P60agModelHill, "ExplicitEuler(substeps = 4)", :CheckerboardCPM, Float64) => [3.3656633126667646, 0.26091877367863736],
    (:P60agModelHill, "ExplicitEuler(substeps = 4)", :CheckerboardCPM, Float32) => [3.3656630516052246, 0.2609187364578247],
    (:P60agModelHill, "RK4()", :SequentialCPM, Float64) => [2.9062550400127396, 0.24623159182881385],
    (:P60agModelHill, "RK4()", :SequentialCPM, Float32) => [2.906254768371582, 0.2462315708398819],
    (:P60agModelHill, "RK4()", :CheckerboardCPM, Float64) => [2.906111242766644, 0.24627998962302128],
    (:P60agModelHill, "RK4()", :CheckerboardCPM, Float32) => [2.906111001968384, 0.2462799847126007],
    (:P60agModelIf5, "ExplicitEuler() (default)", :SequentialCPM, Float64) => [0.05894023053124153],
    (:P60agModelIf5, "ExplicitEuler() (default)", :SequentialCPM, Float32) => [0.058940231800079346],
    (:P60agModelIf5, "ExplicitEuler() (default)", :CheckerboardCPM, Float64) => [0.059440230531241534],
    (:P60agModelIf5, "ExplicitEuler() (default)", :CheckerboardCPM, Float32) => [0.05944022536277771],
    (:P60agModelIf5, "ExplicitEuler(substeps = 4)", :SequentialCPM, Float64) => [0.09139349801584519],
    (:P60agModelIf5, "ExplicitEuler(substeps = 4)", :SequentialCPM, Float32) => [0.09139351546764374],
    (:P60agModelIf5, "ExplicitEuler(substeps = 4)", :CheckerboardCPM, Float64) => [0.09127274998608202],
    (:P60agModelIf5, "ExplicitEuler(substeps = 4)", :CheckerboardCPM, Float32) => [0.0912727639079094],
    (:P60agModelIf5, "RK4()", :SequentialCPM, Float64) => [0.06384454875491356],
    (:P60agModelIf5, "RK4()", :SequentialCPM, Float32) => [0.06384453177452087],
    (:P60agModelIf5, "RK4()", :CheckerboardCPM, Float64) => [0.06351845464848845],
    (:P60agModelIf5, "RK4()", :CheckerboardCPM, Float32) => [0.0635184496641159],
    (:P60agModelSum16, "ExplicitEuler() (default)", :SequentialCPM, Float64) => [1.320234516679355],
    (:P60agModelSum16, "ExplicitEuler() (default)", :SequentialCPM, Float32) => [1.3202344179153442],
    (:P60agModelSum16, "ExplicitEuler() (default)", :CheckerboardCPM, Float64) => [1.3192344655349362],
    (:P60agModelSum16, "ExplicitEuler() (default)", :CheckerboardCPM, Float32) => [1.3192344903945923],
    (:P60agModelSum16, "ExplicitEuler(substeps = 4)", :SequentialCPM, Float64) => [1.3201376476994076],
    (:P60agModelSum16, "ExplicitEuler(substeps = 4)", :SequentialCPM, Float32) => [1.3201379776000977],
    (:P60agModelSum16, "ExplicitEuler(substeps = 4)", :CheckerboardCPM, Float64) => [1.319137545427857],
    (:P60agModelSum16, "ExplicitEuler(substeps = 4)", :CheckerboardCPM, Float32) => [1.319137454032898],
    (:P60agModelSum16, "RK4()", :SequentialCPM, Float64) => [1.3201021674827713],
    (:P60agModelSum16, "RK4()", :SequentialCPM, Float32) => [1.320102334022522],
    (:P60agModelSum16, "RK4()", :CheckerboardCPM, Float64) => [1.3191020450020308],
    (:P60agModelSum16, "RK4()", :CheckerboardCPM, Float32) => [1.3191020488739014],
)

# published models without any ODE => problem fingerprint (Float64, default solvers)
p60ag_published() = (
    (:GranerGlazier, () -> (σ = graner_glazier_state(); PottsProblem(GranerGlazier(; name = :gg), [ownership => σ[1], kind => σ[2]], (0, 10)))),
    (:MerksVasculogenesis, () -> PottsProblem(MerksVasculogenesis(; name = :merks, lattice = (8, 8)),
        [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]], (0, 10);
        field_solver = Potts.ExplicitEuler(substeps = 2, lower = 0.0))),
)
const P60AG_PUBLISHED = Dict{Symbol, UInt64}(
    :GranerGlazier => 0x8942dc9ed483ec21,
    :MerksVasculogenesis => 0xe8c37fa651d985f6,   # re-recorded at the P6.0ag merge (D-102: substep function)
)

"""CPU and Metal runs (Float32, CheckerboardCPM, 10 MCS) of `M` with solver keywords `kw`:
`(cpu, metal)` final states, `metal` the exception if the device run threw."""
function p60ag_cpu_metal(M, kw)
    prob = p60ag_problem(M, (0, p60ag_N); T = Float32, kw...)
    alg = CheckerboardCPM(; proposal = Moore(1))
    cpu = solve(prob, alg).u[end]
    gpu = try
        solve(prob, alg; backend = Main.Metal.MetalBackend()).u[end]
    catch e
        e
    end
    return cpu, gpu
end

# ---------------------------------------------------------------------------------------
# CPU

@testset "P6.0ag: the fixtures" begin
    # every shape moves its unknowns (the rates are live), and the Hill circuit is not at a
    # trivial fixed point: y and z differ between the two cells (volume enters y's rate)
    for M in P60AG_SHAPES, (label, _) in P60AG_FIXED, alg in P60AG_ALGS
        v = P60AG_RESULTS[(nameof(M), label, nameof(typeof(alg)), Float64)]
        @test all(isfinite, v)
        @test v != Float64[p60ag_values(M, p60ag_problem(M, (0, 0)).u0)...]
    end
    v = P60AG_RESULTS[(:P60agHill, "ExplicitEuler() (default)", :CheckerboardCPM, Float64)]
    @test v[1] != v[2] && v[3] != v[4]
    # the population folds read the state: the two algorithms' trajectories differ
    for M in (P60agModelPop, P60agModelHill)
        @test P60AG_RESULTS[(nameof(M), "RK4()", :SequentialCPM, Float64)] != P60AG_RESULTS[(nameof(M), "RK4()", :CheckerboardCPM, Float64)]
    end
end

@testset "P6.0ag: zero warm allocations, controls" begin
    for M in P60AG_CONTROLS, T in (Float64, Float32), (label, kw) in P60AG_FIXED, alg in P60AG_ALGS
        a = p60ag_warm_allocs(p60ag_problem(M, (0, 100); T, kw...), alg)
        @test all(iszero, a)
        all(iszero, a) || @info "P6.0ag control allocates: $(nameof(M)) $T $label $(nameof(typeof(alg))) bytes per step = $a"
    end
end

@testset "P6.0ag: zero warm allocations ($(nameof(M)))" for M in P60AG_SHAPES
    for T in (Float64, Float32), (label, kw) in P60AG_FIXED, alg in P60AG_ALGS
        a = p60ag_warm_allocs(p60ag_problem(M, (0, 100); T, kw...), alg)
        @test all(iszero, a)
        all(iszero, a) || @info "P6.0ag allocates: $(nameof(M)) $T $label $(nameof(typeof(alg))) bytes per step = $a"
    end
end

@testset "P6.0ag: CPU results unchanged (bitwise, $p60ag_N MCS, seed 7)" begin
    for M in P60AG_SHAPES, T in (Float64, Float32), (label, kw) in P60AG_FIXED, alg in P60AG_ALGS
        u = solve(p60ag_problem(M, (0, p60ag_N); T, kw...), alg).u[end]
        want = P60AG_RESULTS[(nameof(M), label, nameof(typeof(alg)), T)]
        if startswith(String(nameof(M)), "P60agModel")
            # D-105: a model-scope rate's sum is ordered by Symbolics' hashes, which differ
            # between package builds, so these values move by a few ulp between builds.
            @test all(isapprox.(p60ag_values(M, u), want; rtol = 8eps(T)))
        else
            @test p60ag_values(M, u) == want
        end
    end
end

@testset "P6.0ag: fingerprints of models without an ODE unchanged" begin
    for (name, build) in p60ag_published()
        @test build().f.fingerprint == P60AG_PUBLISHED[name]
    end
end

# ---------------------------------------------------------------------------------------
# Metal

@testset "P6.0ag: every shape compiles and runs on Metal, equal to the CPU Float32 run ($(nameof(M)))" for M in P60AG_SHAPES
    if P60AG_ON_METAL
        for (label, kw) in P60AG_FIXED
            cpu, gpu = p60ag_cpu_metal(M, kw)
            ran = !(gpu isa Exception)
            @test ran
            if !ran
                s = sprint(showerror, gpu)
                @info "P6.0ag Metal: $(nameof(M)) $label does not run" error = first(s, 300) opaque_closure = occursin("opaque_closure", s)
                continue
            end
            @test Array(gpu.σ) == Array(cpu.σ)
            c, g = Float32.(p60ag_values(M, cpu)), Float32.(p60ag_values(M, gpu))
            if M in P60AG_HILLS
                @test maximum(p60ag_ulps.(c, g)) <= P60AG_HILL_ULPS
            else
                @test g == c
            end
            g == c || @info "P6.0ag Metal vs CPU: $(nameof(M)) $label" cpu = c metal = g ulps = p60ag_ulps.(c, g)
        end
    else
        @test_skip "Metal (POTTS_GPU=metal with Metal loaded)"
    end
end

@testset "P6.0ag: a gather-ODE model and a plain control on Metal (bitwise to the CPU Float32 run)" begin
    if P60AG_ON_METAL
        for M in (P60agGather, P60agPlain, P60agModelPlain), (label, kw) in P60AG_FIXED
            cpu, gpu = p60ag_cpu_metal(M, kw)
            @test !(gpu isa Exception)
            gpu isa Exception && (@info "P6.0ag Metal: $(nameof(M)) $label does not run" error = first(sprint(showerror, gpu), 300); continue)
            @test Array(gpu.σ) == Array(cpu.σ)
            @test p60ag_values(M, gpu) == p60ag_values(M, cpu)
        end
    else
        @test_skip "Metal (POTTS_GPU=metal with Metal loaded)"
    end
end

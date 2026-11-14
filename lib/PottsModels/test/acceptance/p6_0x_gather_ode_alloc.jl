# P6.0x (ROADMAP Phase 6, step 0): a gather inside a cell-ODE rate allocates on every warm
# MCS (480–1472 B here), on both algorithms and every fixed-step solver; the same rate without
# the gather does not allocate.
#
# Pinned here:
#  1. Zero warm allocations per `step!` (after two warm-up steps, every one of five further
#     steps allocates 0 bytes) for a cell ODE whose rate contains a gather, under
#     `SequentialCPM` and `CheckerboardCPM`, `T = Float64` and `Float32`, with the default
#     solver (`ExplicitEuler()`, one step per MCS), `ExplicitEuler(substeps = 4)` and `RK4()`.
#     Three gather shapes over a site neighbourhood (the DSL has no cell-neighbour gather;
#     `neighbors(c)` is a roadmap idea, not vocabulary):
#       - `XVol`: a sum of a non-ODE cell variable over `owner[n]` of a literal site's Moore
#         neighbourhood (the ROADMAP's example);
#       - `XCross`: a conditioned maximum of the cell's own ODE unknown over the other cells
#         around a site (the cross-cell, Jacobi-scratch path of P6.0n, D-078);
#       - `XRing`: a `count` over a named relation (`@relations ring = VonNeumann(1)`)
#         anchored at a site computed from the cell's `id`.
#     `XPlain` (the same kind of rate without a gather) is the control: zero today.
#     Adaptive solvers are not in the zero-allocation targets: they allocate without a
#     gather too (4416 B per MCS for `XPlain` today, P6.0n pins zero only for fixed-step).
#  2. Results unchanged: `y` after 10 MCS (seed 7) for every model, algorithm and solver
#     (adaptive included) equals the values recorded inline from the code before the fix,
#     bitwise; and the problem fingerprints of models without a gather in a cell ODE (the
#     control, a cross-cell indexed read without a gather, and four published models) equal
#     the recorded ones.
#  3. Not pinned: type stability of the generated rate. On the code before the fix,
#     `code_typed` of the cell phase is already concretely inferred (no `Any`- or
#     `Core.Box`-typed call, return `Nothing`); the rate closure is `:invoke`d with a static
#     target and allocates because the closure object holding heap references is built and
#     passed (272 B per cell per call), not because inference fails. An inference assertion
#     would pass today and would pin the phase layout (internal), so the allocation targets
#     above are the acceptance.
using Potts: CorePotts
using OrdinaryDiffEqRosenbrock: Rodas5P

const p60x_ALGS = (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
const p60x_FIXED = (("ExplicitEuler() (default)", (;)), ("ExplicitEuler(substeps = 4)", (; ode_solver = Potts.ExplicitEuler(substeps = 4))),
    ("RK4()", (; ode_solver = Potts.RK4())))
const p60x_SOLVERS = (p60x_FIXED..., ("Adaptive(Rodas5P())", (; ode_solver = Potts.Adaptive(Rodas5P()))))

# ---------------------------------------------------------------------------------------
# Models: two 4×4 cells side by side (x = 3:6 and 7:10, y = 3:6) on a 12×8 lattice. Site 42
# is (6, 4), on their interface; sites 40 and 44 (`36 + 4id`) are (4, 4) and (8, 4), inside
# cell 1 and cell 2.

@potts_model XVol begin
    @kinds medium A
    @parameters k = 0.01
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ k * sum(volume[owner[n]] for n in Moore(1)(42)) - 0.1y
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model XCross begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ 0.5 * (maximum(y[owner[n]] for n in Moore(1)(42) if owner[n] != id) - y)
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model XRing begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @relations ring = VonNeumann(1)
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ 0.1 * count(owner[n] == id for n in ring(36 + 4id)) - 0.2y
    @sweep Metropolis(; temperature = 1.0)
end

# the control: a cell rate reading a cell variable, no gather
@potts_model XPlain begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ 0.01 * volume - 0.1y
    @sweep Metropolis(; temperature = 1.0)
end

# a cross-cell indexed read without a gather (P6.0n's scratch path); zero today
@potts_model XPair begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ 0.5 * (y[3 - id] - y)
    @sweep Metropolis(; temperature = 1.0)
end

const p60x_GATHERS = (XVol, XCross, XRing)
const p60x_CONTROLS = (XPlain, XPair)

p60x_sigma() = (s = zeros(Int32, 12, 8); s[3:6, 3:6] .= 1; s[7:10, 3:6] .= 2; s)
p60x_problem(M, tspan; T = Float64, kw...) =
    PottsProblem(M(; name = :x), [ownership => p60x_sigma(), kind => [:A, :A], :y => [1.0, 2.0]], tspan; T, seed = 7, kw...)

"""Bytes allocated by each of five warm `step!`s (after two warm-up steps)."""
function p60x_warm_allocs(prob, alg)
    integ = init(prob, alg; save_start = false, save_end = false)
    step!(integ)
    step!(integ)
    out = Int[]
    for _ in 1:5
        push!(out, @allocated step!(integ))
    end
    return out
end

const p60x_N = 10                                     # MCS of the recorded results

p60x_final_y(M, alg, kw) = Vector{Float64}(Array(solve(p60x_problem(M, (0, p60x_N); kw...), alg).u[end].cell.y))

# ---------------------------------------------------------------------------------------
# Recorded on the code before the fix (feat/p6-0x at d5bfd3dc, CPU, 1 and 4 threads alike), seed 7, 10 MCS:
# (model, solver label, algorithm) => y after 10 MCS.

# ---------------------------------------------------------------------------------------

@testset "P6.0x: the fixtures exercise their gathers" begin
    # XVol reads the volumes around site 42, which change: the two algorithms' trajectories
    # differ (they would not if the gather read nothing that moves)
    @test p60x_final_y(XVol, SequentialCPM(), (;)) != p60x_final_y(XVol, CheckerboardCPM(), (;))
    # XRing: each anchor's VonNeumann neighbours (four at the start) mostly belong to the
    # cell, so y stays near 0.1 · count / 0.2; with a count of 0 it would decay to
    # 0.8^10 · (1, 2) ≈ (0.11, 0.21). SequentialCPM only (D-271): cells drift, and over 64
    # seeds either algorithm stays above 0.9 in 78 %; the checkerboard's seed 7 does not
    @test all(>(0.9), p60x_final_y(XRing, SequentialCPM(), (;)))
    # XCross: each cell reads the other's y across the interface; both end between their initial values 1 and 2
    for alg in p60x_ALGS
        @test all(v -> 1.0 < v < 2.0, p60x_final_y(XCross, alg, (;)))
    end
    @test Potts._ode_reads_other_cells(mtkcompile(XCross(; name = :x)))
end

@testset "P6.0x: zero warm allocations, no gather (control)" begin
    for M in p60x_CONTROLS, T in (Float64, Float32), (label, kw) in p60x_FIXED, alg in p60x_ALGS
        a = p60x_warm_allocs(p60x_problem(M, (0, 100); T, kw...), alg)
        @test all(iszero, a)
        all(iszero, a) || @info "P6.0x control allocates: $(nameof(M)) $T $label $(nameof(typeof(alg))) bytes per step = $a"
    end
end

@testset "P6.0x: zero warm allocations, gather in a cell-ODE rate ($(nameof(M)))" for M in p60x_GATHERS
    for T in (Float64, Float32), (label, kw) in p60x_FIXED, alg in p60x_ALGS
        a = p60x_warm_allocs(p60x_problem(M, (0, 100); T, kw...), alg)
        @test all(iszero, a)
        all(iszero, a) || @info "P6.0x gather allocates: $(nameof(M)) $T $label $(nameof(typeof(alg))) bytes per step = $a"
    end
end

@testset "P6.0x: the same run twice gives the same values" begin
    for M in (p60x_GATHERS..., p60x_CONTROLS...), (label, kw) in p60x_SOLVERS, alg in p60x_ALGS
        @test p60x_final_y(M, alg, kw) == p60x_final_y(M, alg, kw)
    end
end

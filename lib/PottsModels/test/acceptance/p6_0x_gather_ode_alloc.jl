# P6.0x (ROADMAP Phase 6, step 0): a gather inside a cell-ODE rate allocates on every warm
# MCS (480–1472 B here), on both algorithms and every fixed-step solver; the same rate without
# the gather does not allocate. Frozen (AUTONOMY §7.3).
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

const p60x_RESULTS = Dict{Tuple{Symbol, String, Symbol}, Vector{Float64}}(
    (:XVol, "ExplicitEuler() (default)", :SequentialCPM) => [8.137206881420001, 8.48588532152],
    (:XVol, "ExplicitEuler() (default)", :CheckerboardCPM) => [6.112276670769999, 6.4609551108700005],
    (:XVol, "ExplicitEuler(substeps = 4)", :SequentialCPM) => [7.980329464932799, 8.34356190482068],
    (:XVol, "ExplicitEuler(substeps = 4)", :CheckerboardCPM) => [6.015948275866542, 6.379180715754421],
    (:XVol, "RK4()", :SequentialCPM) => [7.930181178854149, 8.298060953266647],
    (:XVol, "RK4()", :CheckerboardCPM) => [5.98488730440596, 6.352767078818457],
    (:XVol, "Adaptive(Rodas5P())", :SequentialCPM) => [7.930184775682167, 8.298064216855504],
    (:XVol, "Adaptive(Rodas5P())", :CheckerboardCPM) => [5.9848895367510275, 6.352768977924103],
    (:XCross, "ExplicitEuler() (default)", :SequentialCPM) => [1.5, 1.5],
    (:XCross, "ExplicitEuler() (default)", :CheckerboardCPM) => [1.125, 1.125],
    (:XCross, "ExplicitEuler(substeps = 4)", :SequentialCPM) => [1.4999999884277573, 1.5000000115722427],
    (:XCross, "ExplicitEuler(substeps = 4)", :CheckerboardCPM) => [1.1894976762035105, 1.1895921603469648],
    (:XCross, "RK4()", :SequentialCPM) => [1.4999999014183043, 1.5000000985816957],
    (:XCross, "RK4()", :CheckerboardCPM) => [1.2047425646024332, 1.2050048521193004],
    (:XCross, "Adaptive(Rodas5P())", :SequentialCPM) => [1.4999999038193916, 1.5000000965925226],
    (:XCross, "Adaptive(Rodas5P())", :CheckerboardCPM) => [1.2045655353645686, 1.2048250406554117],
    (:XRing, "ExplicitEuler() (default)", :SequentialCPM) => [1.3998809088, 1.091872],
    (:XRing, "ExplicitEuler() (default)", :CheckerboardCPM) => [1.3765118976, 1.6458752],
    (:XRing, "ExplicitEuler(substeps = 4)", :SequentialCPM) => [1.3885621926204719, 1.1362378903265877],
    (:XRing, "ExplicitEuler(substeps = 4)", :CheckerboardCPM) => [1.3755967106641473, 1.6513307990510615],
    (:XRing, "RK4()", :SequentialCPM) => [1.38505768009323, 1.1496756803180677],
    (:XRing, "RK4()", :CheckerboardCPM) => [1.3749779223941017, 1.6532931183695632],
    (:XRing, "Adaptive(Rodas5P())", :SequentialCPM) => [1.3850598505220633, 1.149667406146547],
    (:XRing, "Adaptive(Rodas5P())", :CheckerboardCPM) => [1.3749783522965648, 1.6532918668273324],
    (:XPlain, "ExplicitEuler() (default)", :SequentialCPM) => [1.39338704105, 1.73271534504],
    (:XPlain, "ExplicitEuler() (default)", :CheckerboardCPM) => [1.37812830315, 1.74308137604],
    (:XPlain, "ExplicitEuler(substeps = 4)", :SequentialCPM) => [1.3845013745124777, 1.7389600150590785],
    (:XPlain, "ExplicitEuler(substeps = 4)", :CheckerboardCPM) => [1.3699429098652305, 1.7486546320651826],
    (:XPlain, "RK4()", :SequentialCPM) => [1.3816657345723107, 1.7409489801675833],
    (:XPlain, "RK4()", :CheckerboardCPM) => [1.3673240336725099, 1.7504377583754982],
    (:XPlain, "Adaptive(Rodas5P())", :SequentialCPM) => [1.3816659378752223, 1.7409488376324926],
    (:XPlain, "Adaptive(Rodas5P())", :CheckerboardCPM) => [1.3673242215471366, 1.750437630456749],
    (:XPair, "ExplicitEuler() (default)", :SequentialCPM) => [1.5, 1.5],
    (:XPair, "ExplicitEuler() (default)", :CheckerboardCPM) => [1.5, 1.5],
    (:XPair, "ExplicitEuler(substeps = 4)", :SequentialCPM) => [1.4999999884277573, 1.5000000115722427],
    (:XPair, "ExplicitEuler(substeps = 4)", :CheckerboardCPM) => [1.4999999884277573, 1.5000000115722427],
    (:XPair, "RK4()", :SequentialCPM) => [1.4999999014183043, 1.5000000985816957],
    (:XPair, "RK4()", :CheckerboardCPM) => [1.4999999014183043, 1.5000000985816957],
    (:XPair, "Adaptive(Rodas5P())", :SequentialCPM) => [1.4999999038193916, 1.5000000965925226],
    (:XPair, "Adaptive(Rodas5P())", :CheckerboardCPM) => [1.4999999038193916, 1.5000000965925226],
)

# (model, solver label) => problem fingerprint (Float64)
const p60x_FINGERPRINTS = Dict{Tuple{Symbol, String}, UInt64}(
    (:XPlain, "ExplicitEuler() (default)") => 0x6735c6e78bb18202,
    (:XPlain, "ExplicitEuler(substeps = 4)") => 0x786ca81a07a7ca57,
    (:XPlain, "RK4()") => 0xcf18be4cf6c34e28,
    (:XPlain, "Adaptive(Rodas5P())") => 0xd14f9b0eab30d41e,
    (:XPair, "ExplicitEuler() (default)") => 0x931642ceb3ccf4f0,
    (:XPair, "ExplicitEuler(substeps = 4)") => 0xb0b464bc350e1102,
    (:XPair, "RK4()") => 0x05dd207f8b357730,
    (:XPair, "Adaptive(Rodas5P())") => 0x843419cc959dffb3,
)

# published models (no gather in a cell ODE) => problem fingerprint (Float64, default solvers)
p60x_two(dims, a, b) = (s = zeros(Int32, dims); s[a...] .= 1; s[b...] .= 2; s)
p60x_published() = (
    (:GranerGlazier, () -> (σ = graner_glazier_state(); PottsProblem(GranerGlazier(; name = :gg), [ownership => σ[1], kind => σ[2]], (0, 10)))),
    (:WortelAct, () -> PottsProblem(WortelAct(; name = :act, lattice = (8, 8)),
        [ownership => p60x_two((8, 8), (2:3, 2:3), (6:7, 6:7)), kind => [:cell, :cell]], (0, 10))),
    (:MerksVasculogenesis, () -> PottsProblem(MerksVasculogenesis(; name = :merks, lattice = (8, 8)),
        [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]], (0, 10);
        field_solver = Potts.ExplicitEuler(substeps = 2, lower = 0.0))),
    (:OpenVTGrowingMonolayer, () -> PottsProblem(OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24)),
        openvt_monolayer_state(; lattice = (24, 24)), (0, 10))),
)
const p60x_PUBLISHED = Dict{Symbol, UInt64}(
    :GranerGlazier => 0x04a4528dcdf3fcb8,   # re-pinned under D-122
    :WortelAct => 0xce4f1cec820b20fe,   # re-pinned under D-124
    :MerksVasculogenesis => 0x984e2ad5906fc999,   # re-recorded at the P6.0y merge (D-102: substep function); re-pinned under D-122
    :OpenVTGrowingMonolayer => 0xfcecc4612f387b5e,   # re-pinned under D-122
)

# ---------------------------------------------------------------------------------------

@testset "P6.0x: the fixtures exercise their gathers" begin
    # XVol reads the volumes around site 42, which change: the two algorithms' trajectories
    # differ (they would not if the gather read nothing that moves)
    @test p60x_RESULTS[(:XVol, "ExplicitEuler() (default)", :SequentialCPM)] !=
          p60x_RESULTS[(:XVol, "ExplicitEuler() (default)", :CheckerboardCPM)]
    # XRing: each anchor's VonNeumann neighbours (four at the start) mostly belong to the
    # cell, so y stays near 0.1 · count / 0.2; with a count of 0 it would decay to
    # 0.8^10 · (1, 2) ≈ (0.11, 0.21)
    for alg in p60x_ALGS
        y = p60x_RESULTS[(:XRing, "ExplicitEuler() (default)", nameof(typeof(alg)))]
        @test all(>(0.9), y)
    end
    # XCross: each cell reads the other's y across the interface; both end between their initial values 1 and 2
    for alg in p60x_ALGS
        y = p60x_RESULTS[(:XCross, "ExplicitEuler() (default)", nameof(typeof(alg)))]
        @test all(v -> 1.0 < v < 2.0, y)
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

# D-158: our own steppers stay bitwise; `Adaptive` rows run upstream OrdinaryDiffEq/LinearSolve
# code, whose patch releases may move the last bit, so they are pinned to rtol 1e-12.
@testset "P6.0x: results unchanged (bitwise, $p60x_N MCS, seed 7)" begin
    for M in (p60x_GATHERS..., p60x_CONTROLS...), (label, kw) in p60x_SOLVERS, alg in p60x_ALGS
        want = p60x_RESULTS[(nameof(M), label, nameof(typeof(alg)))]
        if startswith(label, "Adaptive")
            @test p60x_final_y(M, alg, kw) ≈ want rtol = 1e-12
        else
            @test p60x_final_y(M, alg, kw) == want
        end
    end
end

@testset "P6.0x: fingerprints of models without a gather unchanged" begin
    for M in p60x_CONTROLS, (label, kw) in p60x_SOLVERS
        @test p60x_problem(M, (0, p60x_N); kw...).f.fingerprint == p60x_FINGERPRINTS[(nameof(M), label)]
    end
    for (name, build) in p60x_published()
        @test build().f.fingerprint == p60x_PUBLISHED[name]
    end
end

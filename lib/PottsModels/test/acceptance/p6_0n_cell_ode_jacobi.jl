# P6.0n (ROADMAP Phase 6, step 0): cell ODEs that read another cell's ODE state are Jacobi
# across cells (D-038, D-077 scratch rule, D-078; P6.0k review N3). Frozen (AUTONOMY §7.3).
#
# Semantics pinned here:
#  1. Every cell's ODE rate reads every other cell's ODE state as it was at the start of the
#     MCS's ODE step (Jacobi), whatever the cell index order, under both algorithms and on
#     Metal. The cross-cell reads are the public ones a cell ODE can write:
#       - an indexed read `y[j]` of an ODE unknown of the same solver group (`y[3 - id]`,
#         `y[max(id - 1, 1)]`, `y[min(id + 1, n)]`);
#       - a population fold over cells that cannot be hoisted to a model slot (its body reads
#         `time`), so it reads the cells' ODE state inside the ODE kernel.
#  2. Another cell's state is held at its start-of-step value over the whole step, as a
#     different solver group's state already is (D-078): the cell's own unknowns advance
#     through the solver's stages and substeps, the other cells' do not. With `RK4()` or
#     `Adaptive(…)` the oracle is the cell's own ODE with that held forcing.
#  3. Several solver groups in one scope, one of them `Adaptive`, combined with cross-cell
#     reads both within a group and across groups: the same Jacobi result.
#  4. Results do not depend on the cell labels: relabelling the cells (and permuting their
#     initial values with them) permutes the results.
#  5. Zero warm allocations for fixed-step cross-cell ODEs, with one or several groups.
#  6. An empty cell slot (volume 0) does not integrate, and a live cell that reads it reads
#     its unchanged value.
# Every fixture uses `mcs_duration = 1` and one step per MCS (`ExplicitEuler()`, `RK4()`),
# so the synchronous explicit-Euler oracles are exact in small integers. Each oracle comes
# with a Gauss–Seidel (ascending cell order) counterpart that differs from it, so the
# fixtures can tell the two apart (negative control, D-048).
# Not here: model ODEs reading cells (they see the cells' new values by design, D-077 N3),
# substeps > 1 of fixed-step solvers (covered by the held-state rule of item 2), and the
# fold fixture on Metal (an unhoisted fold in a cell ODE does not compile for Metal at all
# today, a separate defect).
using Potts: CorePotts
using OrdinaryDiffEqRosenbrock: Rodas5P

const p60n_EE = Potts.ExplicitEuler
const p60n_RK4 = Potts.RK4
const p60n_Adaptive = Potts.Adaptive
const p60n_ALGS = (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
p60n_rodas() = p60n_Adaptive(Rodas5P(); reltol = 1e-10, abstol = 1e-12)

# ---------------------------------------------------------------------------------------
# Models

# Two cells exchange through an indexed read of the same ODE unknown.
@potts_model P60nPair begin
    @kinds medium A
    @parameters k = 1.0
    @variables y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ k * (y[3 - id] - y)
    @sweep Metropolis(; temperature = 1.0e-6)
end

# Shift registers over 7 slots: cell c takes the value of c − 1 (forward) or c + 1
# (backward) each MCS. An ascending cell loop gets one direction right by accident only.
@potts_model P60nShiftForward begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((42, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ y[max(id - 1, 1)] - y
    @sweep Metropolis(; temperature = 1.0e-6)
end

@potts_model P60nShiftBackward begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((42, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ y[min(id + 1, 7)] - y
    @sweep Metropolis(; temperature = 1.0e-6)
end

# All-to-all coupling through a population fold. The `ε * time` weight (ε = 0) keeps the
# fold from being hoisted to a model slot, so the ODE kernel reads the cells itself;
# `P60nFoldHoisted` is the same rate with a hoisted fold.
@potts_model P60nFold begin
    @kinds medium A
    @parameters ε = 0.0
    @variables y(cell) = 0.0
    @lattice Lattice((18, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ sum(y * (1 + ε * time) for c in cells) - 2y
    @sweep Metropolis(; temperature = 1.0e-6)
end

@potts_model P60nFoldHoisted begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((18, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ sum(y for c in cells) - 2y
    @sweep Metropolis(; temperature = 1.0e-6)
end

# Two unknowns, each reading both of the other cell's unknowns: with `solvers` they fall in
# different groups, so there are cross-cell reads within and across groups.
@potts_model P60nMixed begin
    @kinds medium A
    @variables begin
        y(cell) = 0.0
        z(cell) = 0.0
    end
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations begin
        D(y) ~ y[3 - id] + z[3 - id] - 2y
        D(z) ~ y[3 - id] + z[3 - id] - z
    end
    @sweep Metropolis(; temperature = 1.0e-6)
end

# ---------------------------------------------------------------------------------------
# States: n slots in a row, slot i a 4×4 block at x = 6(i − 1) + 2 …; `labels[i]` is the
# label the block at position i carries (a relabelling permutes them); `dead` slots own no site

function p60n_sigma(n; labels = 1:n, dead = (), height = 8)
    σ = zeros(Int32, 6n, height)
    for i in 1:n
        labels[i] in dead && continue
        σ[(6(i - 1) + 2):(6(i - 1) + 5), 3:6] .= labels[i]
    end
    return σ
end

"""Initial values by label, from values by block position."""
function p60n_by_label(vals, labels)
    out = similar(vals)
    for (i, l) in enumerate(labels)
        out[l] = vals[i]
    end
    return out
end

function p60n_problem(model, n, tspan; T = Float64, labels = 1:n, dead = (), vals = (), kw...)
    op = Any[ownership => p60n_sigma(n; labels, dead), kind => fill(:A, n)]
    for (name, v) in vals
        push!(op, name => p60n_by_label(Float64.(v), labels))
    end
    return PottsProblem(model, op, tspan; T, kw...)
end

"""Trajectory of `name` (one vector over labels per saved time), host arrays."""
p60n_traj(sol, name) = [Float64.(Array(getproperty(u.cell, name))) for u in sol.u]

# ---------------------------------------------------------------------------------------
# Oracles. `rate(y, c)` is cell c's rate on state `y`. Jacobi: every cell steps from the same
# start-of-step state. Gauss–Seidel: cells step in place in ascending order (what a sequential
# kernel without scratch computes). Both with h = 1 (one explicit-Euler step per MCS);
# `skip` cells do not integrate (empty slots).

function p60n_jacobi(rate, y0, m; skip = ())
    traj = [copy(y0)]
    for _ in 1:m
        y = traj[end]
        push!(traj, [c in skip ? y[c] : y[c] + rate(y, c) for c in eachindex(y)])
    end
    return traj
end

function p60n_gauss_seidel(rate, y0, m; skip = ())
    traj = [copy(y0)]
    for _ in 1:m
        y = copy(traj[end])
        for c in eachindex(y)
            c in skip || (y[c] += rate(y, c))
        end
        push!(traj, y)
    end
    return traj
end

p60n_pair_rate(k) = (y, c) -> k * (y[3 - c] - y[c])
p60n_forward_rate(y, c) = y[max(c - 1, 1)] - y[c]
p60n_backward_rate(y, c) = y[min(c + 1, 7)] - y[c]
p60n_fold_rate(live) = (y, c) -> sum(y[j] for j in live) - 2y[c]

const p60n_SHIFT0 = [1.0, 2.0, 4.0, 8.0, 16.0, 32.0, 64.0]
const p60n_DEAD = 4                                  # an empty slot in the shift registers

# The mixed model, one MCS from (y, z), per cell c (o = 3 − c, w = y[o] + z[o] held):
#   y' = w − 2y,  z' = w − z
# Explicit Euler (h = 1): y ← w − y, z ← w. RK4 (one step): the linear decay toward the held
# target scales the deviation by R(−λ) = 1 − λ + λ²/2 − λ³/6 + λ⁴/24. Adaptive: the exact
# solution, deviation × e^(−λ).
p60n_decay(solver, λ) = solver === :ee ? 1 - λ :
                        solver === :rk4 ? 1 - λ + λ^2 / 2 - λ^3 / 6 + λ^4 / 24 : exp(-λ)

function p60n_mixed_oracle(y0, z0, m; ysolver = :ee, zsolver = :ee)
    ys = [copy(y0)]; zs = [copy(z0)]
    for _ in 1:m
        y, z = ys[end], zs[end]
        w = [y[3 - c] + z[3 - c] for c in 1:2]
        push!(ys, [w[c] / 2 + (y[c] - w[c] / 2) * p60n_decay(ysolver, 2) for c in 1:2])
        push!(zs, [w[c] + (z[c] - w[c]) * p60n_decay(zsolver, 1) for c in 1:2])
    end
    return ys, zs
end

# what the mixed model gives if the cells step in place in ascending order (explicit Euler)
function p60n_mixed_gauss_seidel(y0, z0, m)
    ys = [copy(y0)]; zs = [copy(z0)]
    for _ in 1:m
        y, z = copy(ys[end]), copy(zs[end])
        for c in 1:2
            w = y[3 - c] + z[3 - c]
            y[c], z[c] = w - y[c], w
        end
        push!(ys, y); push!(zs, z)
    end
    return ys, zs
end

p60n_close(a, b, T) = length(a) == length(b) &&
                      all(isapprox.(a, b; rtol = T === Float32 ? 1e-5 : 1e-9, atol = T === Float32 ? 1e-5 : 1e-9))

function p60n_warm_allocs(prob, alg)
    integ = init(prob, alg; save_start = false, save_end = false)
    step!(integ)
    step!(integ)
    m = typemax(Int)
    for _ in 1:5
        m = min(m, @allocated step!(integ))
    end
    return m
end

const p60n_M = 4                                     # MCS compared against the oracles

# ---------------------------------------------------------------------------------------

@testset "P6.0n: the oracles tell Jacobi from Gauss–Seidel (negative control)" begin
    @test p60n_jacobi(p60n_pair_rate(1.0), [1.0, 2.0], p60n_M) != p60n_gauss_seidel(p60n_pair_rate(1.0), [1.0, 2.0], p60n_M)
    @test p60n_jacobi(p60n_pair_rate(0.25), [1.0, 2.0], p60n_M) != p60n_gauss_seidel(p60n_pair_rate(0.25), [1.0, 2.0], p60n_M)
    @test p60n_jacobi(p60n_forward_rate, p60n_SHIFT0, p60n_M; skip = (p60n_DEAD,)) !=
          p60n_gauss_seidel(p60n_forward_rate, p60n_SHIFT0, p60n_M; skip = (p60n_DEAD,))
    # backward: an ascending in-place loop reads not-yet-stepped cells, so it is right by
    # accident; the forward register is the one that catches it, a descending loop the reverse
    @test p60n_jacobi(p60n_backward_rate, p60n_SHIFT0, p60n_M; skip = (p60n_DEAD,)) ==
          p60n_gauss_seidel(p60n_backward_rate, p60n_SHIFT0, p60n_M; skip = (p60n_DEAD,))
    @test p60n_jacobi(p60n_fold_rate(1:3), [1.0, 2.0, 4.0], p60n_M) != p60n_gauss_seidel(p60n_fold_rate(1:3), [1.0, 2.0, 4.0], p60n_M)
    @test p60n_mixed_oracle([1.0, 2.0], [4.0, 8.0], 3)[1] != p60n_mixed_gauss_seidel([1.0, 2.0], [4.0, 8.0], 3)[1]
    # hand check of the pair (k = 1 swaps): (1, 2) → (2, 1) → (1, 2)
    @test p60n_jacobi(p60n_pair_rate(1.0), [1.0, 2.0], 2) == [[1.0, 2.0], [2.0, 1.0], [1.0, 2.0]]
    # hand check of the forward register, slot 4 empty: one slot per MCS, slot 5 reads slot 4
    @test p60n_jacobi(p60n_forward_rate, p60n_SHIFT0, 2; skip = (p60n_DEAD,))[3] == [1.0, 1.0, 1.0, 8.0, 8.0, 8.0, 16.0]
end

@testset "P6.0n: two cells exchanging through y[j] are Jacobi" begin
    for T in (Float64, Float32), k in (1.0, 0.25), alg in p60n_ALGS
        prob = p60n_problem(P60nPair(; name = :pair), 2, (0, p60n_M); T, vals = (:y => [1.0, 2.0],))
        prob = remake(prob; p = [:k => k])
        sol = solve(prob, alg; saveat = 0:p60n_M)
        @test p60n_close(p60n_traj(sol, :y), p60n_jacobi(p60n_pair_rate(k), [1.0, 2.0], p60n_M), T)
    end
end

@testset "P6.0n: shift registers move one slot per MCS in both directions" begin
    for T in (Float64, Float32), alg in p60n_ALGS
        for (model, rate) in ((P60nShiftForward, p60n_forward_rate), (P60nShiftBackward, p60n_backward_rate))
            prob = p60n_problem(model(; name = :shift), 7, (0, p60n_M); T, dead = (p60n_DEAD,), vals = (:y => p60n_SHIFT0,))
            sol = solve(prob, alg; saveat = 0:p60n_M)
            @test p60n_close(p60n_traj(sol, :y), p60n_jacobi(rate, p60n_SHIFT0, p60n_M; skip = (p60n_DEAD,)), T)
            @test all(>(0), Array(sol.u[end].cell.volume)[[1:(p60n_DEAD - 1); (p60n_DEAD + 1):7]])
        end
    end
end

@testset "P6.0n: a population fold read inside the ODE kernel is Jacobi" begin
    y0 = [1.0, 2.0, 4.0]
    want = p60n_jacobi(p60n_fold_rate(1:3), y0, p60n_M)
    for T in (Float64, Float32), alg in p60n_ALGS
        for model in (P60nFold, P60nFoldHoisted)      # the hoisted fold is the positive control
            sol = solve(p60n_problem(model(; name = :fold), 3, (0, p60n_M); T, vals = (:y => y0,)), alg; saveat = 0:p60n_M)
            @test p60n_close(p60n_traj(sol, :y), want, T)
        end
    end
end

@testset "P6.0n: results do not depend on the cell labels" begin
    for alg in p60n_ALGS
        # the pair, labels swapped (the model is symmetric under 1 ↔ 2)
        for k in (1.0, 0.25)
            go(labels) = p60n_traj(solve(remake(p60n_problem(P60nPair(; name = :pair), 2, (0, p60n_M); labels,
                    vals = (:y => [1.0, 2.0],)); p = [:k => k]), alg; saveat = 0:p60n_M), :y)
            a, b = go([1, 2]), go([2, 1])
            @test all(t -> b[t][[2, 1]] ≈ a[t], eachindex(a))
        end
        # the fold over three cells, under every relabelling of a 3-cycle and a reversal
        y0 = [1.0, 2.0, 4.0]
        run3(labels) = p60n_traj(solve(p60n_problem(P60nFold(; name = :fold), 3, (0, p60n_M); labels, vals = (:y => y0,)),
                alg; saveat = 0:p60n_M), :y)
        a = run3([1, 2, 3])
        for labels in ([3, 2, 1], [2, 3, 1], [3, 1, 2])
            b = run3(labels)
            @test all(t -> b[t][labels] ≈ a[t], eachindex(a))
        end
        # the mixed model, labels swapped, with an adaptive group
        runm(labels) = (sol = solve(p60n_problem(P60nMixed(; name = :mixed), 2, (0, 3); labels,
                    vals = (:y => [1.0, 2.0], :z => [4.0, 8.0]), solvers = [:z => p60n_rodas()]), alg; saveat = 0:3);
                        (p60n_traj(sol, :y), p60n_traj(sol, :z)))
        (ya, za), (yb, zb) = runm([1, 2]), runm([2, 1])
        @test all(t -> isapprox(yb[t][[2, 1]], ya[t]; rtol = 1e-9) && isapprox(zb[t][[2, 1]], za[t]; rtol = 1e-9), eachindex(ya))
    end
end

@testset "P6.0n: several solver groups (one adaptive) with cross-cell reads" begin
    y0, z0 = [1.0, 2.0], [4.0, 8.0]
    configs = (
        ((;), :ee, :ee),                                                        # one fixed-step group
        ((; solvers = [:z => p60n_RK4()]), :ee, :rk4),                          # two fixed-step groups
        ((; solvers = [:z => p60n_rodas()]), :ee, :adaptive),                   # fixed-step + adaptive
        ((; solvers = [:y => p60n_rodas()]), :adaptive, :ee),                   # the adaptive group first
        ((; ode_solver = p60n_rodas()), :adaptive, :adaptive),                  # one adaptive group
    )
    for (kw, ys, zs) in configs, alg in p60n_ALGS
        prob = p60n_problem(P60nMixed(; name = :mixed), 2, (0, 3); vals = (:y => y0, :z => z0), kw...)
        sol = solve(prob, alg; saveat = 0:3)
        wy, wz = p60n_mixed_oracle(y0, z0, 3; ysolver = ys, zsolver = zs)
        tol = (ys === :adaptive || zs === :adaptive) ? 1e-7 : 1e-12
        @test all(isapprox.(p60n_traj(sol, :y), wy; rtol = tol))
        @test all(isapprox.(p60n_traj(sol, :z), wz; rtol = tol))
    end
end

@testset "P6.0n: zero warm allocations" begin
    for T in (Float64, Float32), alg in p60n_ALGS
        @test p60n_warm_allocs(p60n_problem(P60nPair(; name = :pair), 2, (0, 100); T, vals = (:y => [1.0, 2.0],)), alg) == 0
        @test p60n_warm_allocs(p60n_problem(P60nShiftForward(; name = :shift), 7, (0, 100); T, dead = (p60n_DEAD,),
            vals = (:y => p60n_SHIFT0,)), alg) == 0
        @test p60n_warm_allocs(p60n_problem(P60nFold(; name = :fold), 3, (0, 100); T, vals = (:y => [1.0, 2.0, 4.0],)), alg) == 0
        @test p60n_warm_allocs(p60n_problem(P60nMixed(; name = :mixed), 2, (0, 100); T,
            vals = (:y => [1.0, 2.0], :z => [4.0, 8.0]), solvers = [:z => p60n_RK4()]), alg) == 0
    end
end

@testset "P6.0n: on the device" begin
    if isdefined(Main, :PottsDevices) && Main.PottsDevices.on_device()
        backend = Main.PottsDevices.device_backend()
        alg = CheckerboardCPM(; proposal = Moore(1))
        T = Float32
        for k in (1.0, 0.25)
            prob = remake(p60n_problem(P60nPair(; name = :pair), 2, (0, p60n_M); T, vals = (:y => [1.0, 2.0],)); p = [:k => k])
            sol = solve(prob, alg; backend, saveat = 0:p60n_M)
            @test p60n_close(p60n_traj(sol, :y), p60n_jacobi(p60n_pair_rate(k), [1.0, 2.0], p60n_M), T)
        end
        for (model, rate) in ((P60nShiftForward, p60n_forward_rate), (P60nShiftBackward, p60n_backward_rate))
            prob = p60n_problem(model(; name = :shift), 7, (0, p60n_M); T, dead = (p60n_DEAD,), vals = (:y => p60n_SHIFT0,))
            sol = solve(prob, alg; backend, saveat = 0:p60n_M)
            @test p60n_close(p60n_traj(sol, :y), p60n_jacobi(rate, p60n_SHIFT0, p60n_M; skip = (p60n_DEAD,)), T)
        end
        # (`P60nFold` is not run here: a fold left in the ODE kernel does not compile for Metal
        # yet, with or without cross-cell reads; that is not this item)
        prob = p60n_problem(P60nMixed(; name = :mixed), 2, (0, 3); T, vals = (:y => [1.0, 2.0], :z => [4.0, 8.0]),
            solvers = [:z => p60n_RK4()])
        sol = solve(prob, alg; backend, saveat = 0:3)
        wy, wz = p60n_mixed_oracle([1.0, 2.0], [4.0, 8.0], 3; zsolver = :rk4)
        @test p60n_close(p60n_traj(sol, :y), wy, T) && p60n_close(p60n_traj(sol, :z), wz, T)
    else
        @test_skip "device (POTTS_GPU=metal|rocm)"
    end
end

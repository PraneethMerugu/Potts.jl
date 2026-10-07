# P6.0q (ROADMAP Phase 6, step 0): a population fold that reads `time` inside a cell ODE runs
# on Metal (D-119). Frozen (AUTONOMY §7.3).
#
# History: a fold whose body reads `time` cannot be hoisted to a model slot (`time` is not
# in the model environment), so the ODE kernel computes it per cell. Found by the P6.0n test
# author (D-086): that kernel did not compile for Metal (`InvalidIRError`,
# `jl_new_opaque_closure_jlcall`), so `P60nFold` was left out of P6.0n's Metal testset. A
# fold that reads `mcs` is hoisted and ran on Metal. Reproduced on monorepo 4e81e1eb (after
# P6.0x/P6.0ag, D-103/D-104/D-107, removed the per-cell `rhs` closure): the P6.0n fold
# fixture already runs on Metal and equals the CPU Float32 run (y = [1, 2, 4] → [6, 5, 3] →
# [8, 9, 11] → [20, 19, 17] → [36, 37, 39] on both). This file is the regression guard.
#
# Pinned here (three cells, `mcs_duration = 1`, one step per MCS unless `substeps`):
#  1. Hoisting, the premise of the controls: a fold reading `mcs` only becomes a model slot;
#     a fold reading `time` (alone or with `mcs`) does not; in a rate with both kinds, the
#     `mcs` fold is hoisted and the `time` fold is not. (Checked through the presence of the
#     model slot `__odepop1`, the name `_hoist_populations` gives it.)
#  2. The values on the CPU, `T = Float64` and `Float32`, `SequentialCPM` and
#     `CheckerboardCPM`, `ExplicitEuler()`, `ExplicitEuler(substeps = 4)` and `RK4()`, equal a
#     Jacobi oracle: every cell's fold reads the cells' ODE state at the start of the MCS's
#     ODE step (D-086), held over the stages and substeps, while the cell's own `-2y` term
#     advances. Within the step of MCS n (1-based), `mcs` is n − 1 and `time` is the stage
#     time, (n − 1) + the stage offset (0, h/2, h for RK4; (s − 1)h for substep s).
#  3. `time` really enters: with ε ≠ 0 the time-reading fold gives a different trajectory
#     than with ε = 0, and the oracle with `time` at the stage and substep times differs from
#     the one with `time` held at the MCS start (RK4, Euler with substeps), so the fixtures
#     tell a dropped or frozen `time` apart (negative controls, D-048).
#  4. Metal (POTTS_GPU=metal with Metal loaded; `T = Float32`, `CheckerboardCPM(; proposal =
#     Moore(1))`): the P6.0n fold fixture (ε = 0) and every model and fixed-step solver above
#     compile and run, σ equals the CPU Float32 run's, and the ODE values equal the CPU
#     Float32 run's within P60Q_ULPS = 4 units in the last place (and the oracle in Float32
#     tolerance). Measured on 4e81e1eb (Metal.jl 1.10): every model and solver bitwise
#     (0 ulp); the tolerance only absorbs device math differences (cf. D-107's Hill shapes).

const P60Q_ON_DEVICE = isdefined(Main, :PottsDevices) && Main.PottsDevices.on_device()
const P60Q_ALGS = (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
const P60Q_SOLVERS = (("ExplicitEuler()", (;), :ee, 1), ("ExplicitEuler(substeps = 4)",
    (; ode_solver = Potts.ExplicitEuler(substeps = 4)), :ee, 4), ("RK4()", (; ode_solver = Potts.RK4()), :rk4, 1))
const P60Q_M = 4                                     # MCS compared
const P60Q_Y0 = [1.0, 2.0, 4.0]
const P60Q_ULPS = 4

# ---------------------------------------------------------------------------------------
# Models: three 4×4 cells in a row on an 18×8 lattice (as P6.0n's fold fixture).

# P6.0n's fold fixture, verbatim (`ε * time` with ε = 0 keeps it unhoisted).
@potts_model P60qFoldN begin
    @kinds medium A
    @parameters ε = 0.0
    @variables y(cell) = 0.0
    @lattice Lattice((18, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ sum(y * (1 + ε * time) for c in cells) - 2y
    @sweep Metropolis(; temperature = 1.0e-6)
end

# a fold reading `time` (unhoisted)
@potts_model P60qTime begin
    @kinds medium A
    @parameters ε = 0.25
    @variables y(cell) = 0.0
    @lattice Lattice((18, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ sum(y * (1 + ε * time) for c in cells) - 2y
    @sweep Metropolis(; temperature = 1.0e-6)
end

# a fold reading `mcs` (hoisted; the control)
@potts_model P60qMcs begin
    @kinds medium A
    @parameters η = 0.5
    @variables y(cell) = 0.0
    @lattice Lattice((18, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ sum(y * (1 + η * mcs) for c in cells) - 2y
    @sweep Metropolis(; temperature = 1.0e-6)
end

# one fold reading both (unhoisted)
@potts_model P60qBoth begin
    @kinds medium A
    @parameters begin
        ε = 0.25
        η = 0.5
    end
    @variables y(cell) = 0.0
    @lattice Lattice((18, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ sum(y * (1 + ε * time + η * mcs) for c in cells) - 2y
    @sweep Metropolis(; temperature = 1.0e-6)
end

# two folds in one rate: the `time` one stays in the kernel, the `mcs` one is hoisted
@potts_model P60qTwo begin
    @kinds medium A
    @parameters begin
        ε = 0.25
        η = 0.5
    end
    @variables y(cell) = 0.0
    @lattice Lattice((18, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ sum(y * (1 + ε * time) for c in cells) + sum(η * mcs * y for c in cells) - 2y
    @sweep Metropolis(; temperature = 1.0e-6)
end

# (model, name, ε, η, hoisted slot expected): the fold's weight is 1 + ε·time + η·mcs
const P60Q_MODELS = ((P60qFoldN, "P6.0n fold (ε = 0)", 0.0, 0.0, false), (P60qTime, "time", 0.25, 0.0, false),
    (P60qMcs, "mcs", 0.0, 0.5, true), (P60qBoth, "time and mcs", 0.25, 0.5, false),
    (P60qTwo, "a time fold and an mcs fold", 0.25, 0.5, true))

# ---------------------------------------------------------------------------------------

function p60q_sigma(n)
    σ = zeros(Int32, 6n, 8)
    for i in 1:n
        σ[(6(i - 1) + 2):(6(i - 1) + 5), 3:6] .= i
    end
    return σ
end

p60q_problem(model, kw; T = Float64, tspan = (0, P60Q_M)) =
    PottsProblem(model(; name = :fold), [ownership => p60q_sigma(3), kind => fill(:A, 3), :y => P60Q_Y0], tspan; T, kw...)

p60q_traj(sol) = [Float64.(Array(u.cell.y)) for u in sol.u]

"""Jacobi oracle: per MCS n, S = Σ y (start of step), held; each cell integrates
y' = S (1 + ε τ + η (n − 1)) − 2y over [n − 1, n] with `substeps` steps of `solver`, τ the
stage time (`stagetime = false`: τ held at the MCS start, n − 1, a negative control)."""
function p60q_oracle(ε, η, m; solver = :ee, substeps = 1, stagetime = true)
    traj = [copy(P60Q_Y0)]
    for n in 1:m
        y0 = traj[end]
        S = sum(y0)
        mc = n - 1
        h = 1 / substeps
        next = similar(y0)
        for c in eachindex(y0)
            y = y0[c]
            for s in 1:substeps
                t = mc + (s - 1) * h
                f(τ, v) = S * (1 + ε * (stagetime ? τ : mc) + η * mc) - 2v
                if solver === :rk4
                    k1 = f(t, y)
                    k2 = f(t + h / 2, y + h / 2 * k1)
                    k3 = f(t + h / 2, y + h / 2 * k2)
                    k4 = f(t + h, y + h * k3)
                    y += h / 6 * (k1 + 2k2 + 2k3 + k4)
                else
                    y += h * f(t, y)
                end
            end
            next[c] = y
        end
        push!(traj, next)
    end
    return traj
end

p60q_close(a, b, T) = length(a) == length(b) &&
                      all(isapprox.(a, b; rtol = T === Float32 ? 1e-5 : 1e-12, atol = T === Float32 ? 1e-5 : 1e-12))

"""Largest distance in Float32 units in the last place between two trajectories."""
p60q_ulps(a, b) = maximum(maximum(abs.(reinterpret.(Int32, Float32.(x)) .- reinterpret.(Int32, Float32.(y))))
                          for (x, y) in zip(a, b))

# ---------------------------------------------------------------------------------------

@testset "P6.0q: the oracles (hand checks and negative controls)" begin
    # P6.0n's fixture: y ← S − y (Euler, h = 1)
    @test p60q_oracle(0.0, 0.0, 2) == [[1.0, 2.0, 4.0], [6.0, 5.0, 3.0], [8.0, 9.0, 11.0]]
    # ε = 1/4, step 2 (n = 2, time = 1): S = 14, y ← 14 · 5/4 − y
    @test p60q_oracle(0.25, 0.0, 2)[3] == [11.5, 12.5, 14.5]
    # η = 1/2 likewise (mcs = 1 in step 2): y ← 14 · 3/2 − y
    @test p60q_oracle(0.0, 0.5, 2)[3] == [15.0, 16.0, 18.0]
    # time enters: ε ≠ 0 differs from ε = 0, under each solver
    for (_, _, solver, substeps) in P60Q_SOLVERS
        @test p60q_oracle(0.25, 0.0, P60Q_M; solver, substeps) != p60q_oracle(0.0, 0.0, P60Q_M; solver, substeps)
    end
    # stage times matter under RK4 and substeps (a `time` frozen at the step start differs)
    @test !p60q_close(p60q_oracle(0.25, 0.0, P60Q_M; solver = :rk4),
        p60q_oracle(0.25, 0.0, P60Q_M; solver = :rk4, stagetime = false), Float32)
    @test !p60q_close(p60q_oracle(0.25, 0.5, P60Q_M; substeps = 4),
        p60q_oracle(0.25, 0.5, P60Q_M; substeps = 4, stagetime = false), Float32)
end

@testset "P6.0q: which folds are hoisted" begin
    for (model, name, _, _, hoisted) in P60Q_MODELS
        u = solve(p60q_problem(model, (;); tspan = (0, 1)), SequentialCPM(; proposal = Moore(1))).u[end]
        @test hasproperty(u.model, :__odepop1) == hoisted
    end
end

@testset "P6.0q: CPU values equal the Jacobi oracle ($name)" for (model, name, ε, η, _) in P60Q_MODELS
    for (_, kw, solver, substeps) in P60Q_SOLVERS
        want = p60q_oracle(ε, η, P60Q_M; solver, substeps)
        for T in (Float64, Float32), alg in P60Q_ALGS
            sol = solve(p60q_problem(model, kw; T), alg; saveat = 0:P60Q_M)
            @test p60q_close(p60q_traj(sol), want, T)
        end
    end
end

@testset "P6.0q: `time` read by an unhoisted fold changes the result" begin
    for (_, kw, _, _) in P60Q_SOLVERS, T in (Float64, Float32)
        a = p60q_traj(solve(p60q_problem(P60qTime, kw; T), CheckerboardCPM(; proposal = Moore(1)); saveat = 0:P60Q_M))
        b = p60q_traj(solve(remake(p60q_problem(P60qTime, kw; T); p = [:ε => 0.0]), CheckerboardCPM(; proposal = Moore(1));
            saveat = 0:P60Q_M))
        @test !p60q_close(a, b, T)
    end
end

@testset "P6.0q: on the device (Float32), each fold ($name)" for (model, name, ε, η, _) in P60Q_MODELS
    if P60Q_ON_DEVICE
        backend = Main.PottsDevices.device_backend()
        alg = CheckerboardCPM(; proposal = Moore(1))
        for (sname, kw, solver, substeps) in P60Q_SOLVERS
            prob = p60q_problem(model, kw; T = Float32)
            cpu = solve(prob, alg; saveat = 0:P60Q_M)
            gpu = solve(prob, alg; backend, saveat = 0:P60Q_M)
            a, b = p60q_traj(cpu), p60q_traj(gpu)
            @info "P6.0q $name, $sname: CPU vs device (Float32)" cpu = a[end] device = b[end] ulps = p60q_ulps(a, b)
            @test Array(gpu.u[end].σ) == Array(cpu.u[end].σ)
            @test p60q_ulps(a, b) <= P60Q_ULPS
            @test p60q_close(b, p60q_oracle(ε, η, P60Q_M; solver, substeps), Float32)
        end
    else
        @test_skip "device (POTTS_GPU=metal|rocm)"
    end
end

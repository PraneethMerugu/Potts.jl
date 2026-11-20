# a population fold that reads `time` inside a cell ODE runs
# on Metal (D-119).
#
# History: a fold whose body reads `time` cannot be hoisted to a model slot (`time` is not
# in the model environment), so the ODE kernel computes it per cell. Found by the `cell_ode_jacobi_tests.jl` test
# author (D-086): that kernel did not compile for Metal (`InvalidIRError`,
# `jl_new_opaque_closure_jlcall`), so `Fold` was left out of `cell_ode_jacobi_tests.jl`'s Metal testset. A
# fold that reads `mcs` is hoisted and ran on Metal. Reproduced on monorepo 4e81e1eb (after
# `gather_ode_allocations_tests.jl`/`ode_expansion_tests.jl`, D-103/D-104/D-107, removed the per-cell `rhs` closure): the `cell_ode_jacobi_tests.jl` fold
# fixture already runs on Metal and equals the CPU Float32 run (y = [1, 2, 4] → [6, 5, 3] →
# [8, 9, 11] → [20, 19, 17] → [36, 37, 39] on both). This file is the regression guard.
#
# Pinned here (three cells, `mcs_duration = 1`, one step per MCS unless `substeps`):
#  1. Hoisting, the premise of the controls: a fold reading `mcs` only becomes a model slot;
#     a fold reading `time` (alone or with `mcs`) does not; in a rate with both kinds, the
#     `mcs` fold is hoisted and the `time` fold is not. (Checked through the presence of the
#     model slot `__odepop1`, the name `_hoist_populations` gives it.)
#  2. The values on the CPU, `T = Float64` and `Float32`, `SequentialCPM` and
#     `CheckerboardCPM`, `ExplicitEuler()`, `ExplicitEuler(substeps = 4)` and `Potts.RK4()`, equal a
#     Jacobi oracle: every cell's fold reads the cells' ODE state at the start of the MCS's
#     ODE step (D-086), held over the stages and substeps, while the cell's own `-2y` term
#     advances. Within the step of MCS n (1-based), `mcs` is n − 1 and `time` is the stage
#     time, (n − 1) + the stage offset (0, h/2, h for RK4; (s − 1)h for substep s).
#  3. `time` really enters: with ε ≠ 0 the time-reading fold gives a different trajectory
#     than with ε = 0, and the oracle with `time` at the stage and substep times differs from
#     the one with `time` held at the MCS start (RK4, Euler with substeps), so the fixtures
#     tell a dropped or frozen `time` apart (negative controls, D-048).
#  4. Metal (POTTS_GPU=metal with Metal loaded; `T = Float32`, `CheckerboardCPM(; proposal =
#     Moore(1))`): the `cell_ode_jacobi_tests.jl` fold fixture (ε = 0) and every model and fixed-step solver above
#     compile and run, σ equals the CPU Float32 run's, and the ODE values equal the CPU
#     Float32 run's within ULPS = 4 units in the last place (and the oracle in Float32
#     tolerance). Measured on 4e81e1eb (Metal.jl 1.10): every model and solver bitwise
#     (0 ulp); the tolerance only absorbs device math differences (cf. D-107's Hill shapes).

@testsetup module TimeFoldMetalSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
const ON_DEVICE = PottsDevices.on_device()
const ALGS = (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
const SOLVERS = (
    ("ExplicitEuler()", (;), :ee, 1), (
        "ExplicitEuler(substeps = 4)",
        (; ode_solver = Potts.ExplicitEuler(substeps = 4)), :ee, 4,
    ), ("RK4()", (; ode_solver = Potts.RK4()), :rk4, 1),
)
const TIME_FOLD_M = 4
# MCS compared
const TIME_FOLD_Y0 = [1.0, 2.0, 4.0]
const ULPS = 4
# ---------------------------------------------------------------------------------------
# Models: three 4×4 cells in a row on an 18×8 lattice (as `cell_ode_jacobi_tests.jl`'s fold fixture).

# `cell_ode_jacobi_tests.jl`'s fold fixture, verbatim (`ε * time` with ε = 0 keeps it unhoisted).
@potts_model FoldN begin
    @kinds medium A
    @parameters ε = 0.0
    @variables y(cell) = 0.0
    @lattice Lattice((18, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ sum(y * (1 + ε * time) for c in cells) - 2y
    @sweep Metropolis(; temperature = 1.0e-6)
end
# a fold reading `time` (unhoisted)
@potts_model Time begin
    @kinds medium A
    @parameters ε = 0.25
    @variables y(cell) = 0.0
    @lattice Lattice((18, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ sum(y * (1 + ε * time) for c in cells) - 2y
    @sweep Metropolis(; temperature = 1.0e-6)
end
# a fold reading `mcs` (hoisted; the control)
@potts_model Mcs begin
    @kinds medium A
    @parameters η = 0.5
    @variables y(cell) = 0.0
    @lattice Lattice((18, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ sum(y * (1 + η * mcs) for c in cells) - 2y
    @sweep Metropolis(; temperature = 1.0e-6)
end
# one fold reading both (unhoisted)
@potts_model Both begin
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
@potts_model Two begin
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
const MODELS = (
    (FoldN, "cell ode jacobi fold (ε = 0)", 0.0, 0.0, false), (Time, "time", 0.25, 0.0, false),
    (Mcs, "mcs", 0.0, 0.5, true), (Both, "time and mcs", 0.25, 0.5, false),
    (Two, "a time fold and an mcs fold", 0.25, 0.5, true),
)
# ---------------------------------------------------------------------------------------
function sigma(n)
    σ = zeros(Int32, 6n, 8)
    for i in 1:n
        σ[(6(i - 1) + 2):(6(i - 1) + 5), 3:6] .= i
    end
    return σ
end
problem(model, kw; T = Float64, tspan = (0, TIME_FOLD_M)) =
    PottsProblem(model(; name = :fold), [ownership => sigma(3), kind => fill(:A, 3), :y => TIME_FOLD_Y0], tspan; T, kw...)
time_fold_traj(sol) = [Float64.(Array(u.cell.y)) for u in sol.u]
"""Jacobi oracle: per MCS n, S = Σ y (start of step), held; each cell integrates
y' = S (1 + ε τ + η (n − 1)) − 2y over [n − 1, n] with `substeps` steps of `solver`, τ the
stage time (`stagetime = false`: τ held at the MCS start, n − 1, a negative control)."""
function time_fold_oracle(ε, η, m; solver = :ee, substeps = 1, stagetime = true)
    traj = [copy(TIME_FOLD_Y0)]
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
time_fold_close(a, b, T) = length(a) == length(b) &&
    all(isapprox.(a, b; rtol = T === Float32 ? 1.0e-5 : 1.0e-12, atol = T === Float32 ? 1.0e-5 : 1.0e-12))
"""Largest distance in Float32 units in the last place between two trajectories."""
time_fold_ulps(a, b) = maximum(
    maximum(abs.(reinterpret.(Int32, Float32.(x)) .- reinterpret.(Int32, Float32.(y))))
        for (x, y) in zip(a, b)
)
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "time fold metal: the oracles (hand checks and negative controls)" setup = [TimeFoldMetalSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    @testset "time fold metal: the oracles (hand checks and negative controls)" begin
        # `cell_ode_jacobi_tests.jl`'s fixture: y ← S − y (Euler, h = 1)
        @test time_fold_oracle(0.0, 0.0, 2) == [[1.0, 2.0, 4.0], [6.0, 5.0, 3.0], [8.0, 9.0, 11.0]]
        # ε = 1/4, step 2 (n = 2, time = 1): S = 14, y ← 14 · 5/4 − y
        @test time_fold_oracle(0.25, 0.0, 2)[3] == [11.5, 12.5, 14.5]
        # η = 1/2 likewise (mcs = 1 in step 2): y ← 14 · 3/2 − y
        @test time_fold_oracle(0.0, 0.5, 2)[3] == [15.0, 16.0, 18.0]
        # time enters: ε ≠ 0 differs from ε = 0, under each solver
        for (_, _, solver, substeps) in SOLVERS
            @test time_fold_oracle(0.25, 0.0, TIME_FOLD_M; solver, substeps) != time_fold_oracle(0.0, 0.0, TIME_FOLD_M; solver, substeps)
        end
        # stage times matter under RK4 and substeps (a `time` frozen at the step start differs)
        @test !time_fold_close(
            time_fold_oracle(0.25, 0.0, TIME_FOLD_M; solver = :rk4),
            time_fold_oracle(0.25, 0.0, TIME_FOLD_M; solver = :rk4, stagetime = false), Float32
        )
        @test !time_fold_close(
            time_fold_oracle(0.25, 0.5, TIME_FOLD_M; substeps = 4),
            time_fold_oracle(0.25, 0.5, TIME_FOLD_M; substeps = 4, stagetime = false), Float32
        )
    end
end

@testitem "time fold metal: which folds are hoisted" setup = [TimeFoldMetalSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "time fold metal: which folds are hoisted" begin
        for (model, name, _, _, hoisted) in MODELS
            u = solve(problem(model, (;); tspan = (0, 1)), SequentialCPM(; proposal = Moore(1))).u[end]
            @test hasproperty(u.model, :__odepop1) == hoisted
        end
    end
end

@testitem "time fold metal: CPU values equal the Jacobi oracle" setup = [TimeFoldMetalSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "time fold metal: CPU values equal the Jacobi oracle ($name)" for (model, name, ε, η, _) in MODELS
        for (_, kw, solver, substeps) in SOLVERS
            want = time_fold_oracle(ε, η, TIME_FOLD_M; solver, substeps)
            for T in (Float64, Float32), alg in ALGS
                sol = solve(problem(model, kw; T), alg; saveat = 0:TIME_FOLD_M)
                @test time_fold_close(time_fold_traj(sol), want, T)
            end
        end
    end
end

@testitem "time fold metal: `time` read by an unhoisted fold changes the result" setup = [TimeFoldMetalSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "time fold metal: `time` read by an unhoisted fold changes the result" begin
        for (_, kw, _, _) in SOLVERS, T in (Float64, Float32)
            a = time_fold_traj(solve(problem(Time, kw; T), CheckerboardCPM(; proposal = Moore(1)); saveat = 0:TIME_FOLD_M))
            b = time_fold_traj(
                solve(
                    remake(problem(Time, kw; T); p = [:ε => 0.0]), CheckerboardCPM(; proposal = Moore(1));
                    saveat = 0:TIME_FOLD_M
                )
            )
            @test !time_fold_close(a, b, T)
        end
    end
end

@testitem "time fold metal: on the device (Float32), each fold" setup = [TimeFoldMetalSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "time fold metal: on the device (Float32), each fold ($name)" for (model, name, ε, η, _) in MODELS
        if ON_DEVICE
            backend = PottsDevices.device_backend()
            alg = CheckerboardCPM(; proposal = Moore(1))
            for (sname, kw, solver, substeps) in SOLVERS
                prob = problem(model, kw; T = Float32)
                cpu = solve(prob, alg; saveat = 0:TIME_FOLD_M)
                gpu = solve(prob, alg; backend, saveat = 0:TIME_FOLD_M)
                a, b = time_fold_traj(cpu), time_fold_traj(gpu)
                @info "time fold metal $name, $sname: CPU vs device (Float32)" cpu = a[end] device = b[end] ulps = time_fold_ulps(a, b)
                @test Array(gpu.u[end].ownership) == Array(cpu.u[end].ownership)
                @test time_fold_ulps(a, b) <= ULPS
                @test time_fold_close(b, time_fold_oracle(ε, η, TIME_FOLD_M; solver, substeps), Float32)
            end
        else
            @test_skip "device (POTTS_GPU=metal|rocm)"
        end
    end
end

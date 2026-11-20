# `@sweep mcs_duration`
# is not validated. Decision: D-126 (follows D-123, which did the same for `offset`).
#
# The defect, measured on ab26cd37. `sweep_spec` (src/vocabulary.jl) stores
# `Float64(mcs_duration)` unchecked, and every reader trusts it: the `Adaptive` ODE step
# integrates over `[mcs, mcs + 1) × mcs_duration`, `ExplicitEuler`/`RK4` take steps of
# `mcs_duration`, the field step's substep count divides by it, the clock cadence of a
# discrete component is `dt / mcs_duration`, and the fingerprint hashes it. For the cell ODE
# `D(y) ~ -y`, y(0) = 1, 3 MCS:
#   - NaN or ±Inf: the model builds and `PottsProblem` accepts it; `Adaptive(Rodas5P())`
#     throws `SciMLBase.NaNTspanError` at the first solve, `ExplicitEuler()` and
#     `Potts.RK4()` return retcode Success with y = NaN; the auto-substep field step throws
#     `InexactError: Int64(NaN)`; a `Clock(1.0)` component is refused at `PottsProblem` with
#     a message about the clock period, not about `mcs_duration`.
#   - 0: every solver returns y = 1.0 (time stands still), Success; `Adaptive` only warns
#     "Initial timestep too small"; a `Clock(1.0)` component throws `InexactError:
#     Int64(Inf)`.
#   - -1: time runs backwards silently: `Adaptive` y = e³ = 20.0855, `ExplicitEuler` 2³ = 8,
#     the field grows instead of decaying.
#   - a non-Real (`:a`, `1 + 1im`, `"1"`, a symbolic `@parameters τ`) throws a `MethodError`
#     or `InexactError` from `Float64(…)`, naming neither `@sweep` nor `mcs_duration`.
#   - `big"1e400"` (finite, but over `floatmax(Float64)`) is stored as Inf; `big"1e-400"`
#     (positive) as 0.0.
#
# Rule (D-126), pinned here:
#  A. `mcs_duration` must be a `Real` that is finite and > 0 after `float` and in Float64.
#     Anything else is an `ArgumentError` whose message names `mcs_duration`, thrown by
#     `@sweep` (`sweep_spec`), so building the system throws, not `PottsProblem` and not the
#     first `solve`: NaN, Inf, -Inf (Float64 and Float32), 0, 0.0, -0.0, negative values,
#     `big"1e400"`, `big"1e-400"`, non-Real values (`:a`, `1 + 1im`, `"1"`) and a symbolic
#     parameter. Metropolis and Barker alike; a literal in `@sweep`, a structural keyword of
#     the constructor (`M(; md = …)`), and through `@extend` (an extension's own `@sweep`,
#     or a base built with a bad keyword).
#  B. Every positive finite value is accepted as before (Int, Float64, Float32, Rational,
#     BigFloat, 1e300, floatmin), stored as `Float64(mcs_duration)`; accepted values behave
#     exactly as before: the runs below are checked by hand, and the fingerprints are those
#     recorded on ab26cd37 (the fixtures here and every PottsModels system, the D-121/D-122/
#     D-123 pins).
#  C. Bypass paths: `mcs_duration` reaches a problem only through `@sweep` (or inheritance
#     of a base's sweep under `@extend`): `PottsProblem`, `remake` and `solve` do not take
#     it. Pinned as a guard: each refuses the keyword.

@testsetup module MCSDurationSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
include(joinpath(@__DIR__, "..", "fixtures.jl"))
using Potts: CorePotts
using Potts.ModelingToolkitBase: System, ShiftIndex, Clock, @variables
using OrdinaryDiffEqRosenbrock: Rodas5P
# ---------------------------------------------------------------------------------------
# Fixtures. One 3×3 cell of kind A on a 12×12 lattice, a cell ODE `D(y) ~ -y` (y(0) = 1);
# the duration is a structural keyword `md`, so `ODE(; md = v)` builds with `v`.
@potts_model ODE begin
    @structural_parameters begin
        md = 1.0
        barker = false
    end
    @kinds medium A
    @variables y(cell) = 1.0
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @equations D(y) ~ -y
    if barker
        @sweep Barker(; temperature = 1.0, mcs_duration = md)
    else
        @sweep Metropolis(; temperature = 1.0, mcs_duration = md)
    end
end
# no `mcs_duration` at all (the default)
@potts_model Default begin
    @kinds medium A
    @variables y(cell) = 1.0
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @equations D(y) ~ -y
    @sweep Metropolis(; temperature = 1.0)
end
# a field `c` with uniform decay: on a uniform field Δc = 0, so c' = -0.05 c (a plain MTK
# PDESystem, coupled with `@fields`)
function field_pde()
    t, L = Potts.t, Potts.LatticePDE
    Potts.ModelingToolkitBase.@parameters x y
    Potts.ModelingToolkitBase.@variables c(..)
    C = c(t, x, y)
    return Potts.ModelingToolkitBase.PDESystem(
        [Potts.D(C) ~ 0.1 * L.laplacian(C) - 0.05 * C], [c(0, x, y) ~ 0.0],
        L.lattice_domain(t, (x, y), (12, 12)), [t, x, y], [C], Any[]; name = :duration_field
    )
end
@potts_model Field begin
    @structural_parameters md = 1.0
    @kinds medium A
    @lattice Lattice((12, 12))
    @fields field_pde()
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0, mcs_duration = md)
end
# a discrete per-tick counter `n(k) = n(k − 1) + 1` on a `Clock(1.0)` component
const SYSTEM = Ref{Any}(nothing)
function counter(k)
    t = Potts.t
    @variables n(t) = 0.0
    return System([n(k) ~ n(k - 1) + 1.0], t; name = :ctr)
end
@potts_model DurationClock begin
    @structural_parameters md = 1.0
    @kinds medium A
    @components cells(A) ctr = SYSTEM[]
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0e-6, mcs_duration = md)
end
SYSTEM[] = counter(ShiftIndex(Clock(1.0)))
# a symbolic parameter as the duration
@potts_model Symbolic begin
    @kinds medium A
    @parameters τ = 0.5
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0, mcs_duration = τ)
end
# `@extend`: an extension with its own `@sweep`, and one inheriting the base's
@potts_model ExtOwn begin
    @structural_parameters md = 1.0
    @extend base = ODE()
    @sweep Metropolis(; temperature = 1.0, mcs_duration = md)
end
@potts_model ExtInherit begin
    @structural_parameters md = 1.0
    @extend base = ODE(; md = md)
end
# literals written in `@sweep` (a model per value; built lazily)
const LITERAL = Dict{String, Any}()
for (i, (label, v)) in enumerate(
        [
            "NaN" => :NaN, "Inf" => :Inf, "0" => 0, "-1.0" => -1.0, "0.5" => 0.5,
        ]
    )
    name = Symbol(:Literal, i)
    @eval @potts_model $name begin
        @kinds medium A
        @lattice Lattice((12, 12))
        @energy cells => (volume - 9.0)^2
        @sweep Metropolis(; temperature = 1.0, mcs_duration = $v)
    end
    LITERAL[label] = @eval $name
end
# an invalid offset (D-123) with a valid duration: its ArgumentError does not name
# `mcs_duration` (negative control for the message check)
@potts_model BadOffset begin
    @kinds medium A
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0, offset = NaN, mcs_duration = 0.5)
end
sigma() = (s = zeros(Int32, 12, 12); s[3:5, 3:5] .= 1; s)
duration_op() = [ownership => sigma(), kind => [:A]]
problem(sys; tspan = (0, 3), kw...) = PottsProblem(sys, duration_op(), tspan; kw...)
duration_y(sys; kw...) = solve(problem(sys; kw...), SequentialCPM()).u[end].cell.y[1]
const BAD = [
    "NaN" => NaN, "Inf" => Inf, "-Inf" => -Inf, "NaN32" => NaN32, "Inf32" => Inf32,
    "-Inf32" =>
        -Inf32,
    "0" => 0, "0.0" => 0.0, "-0.0" => -0.0, "0.0f0" => 0.0f0,
    "-1" => -1, "-0.5" => -0.5, "-1//2" => -1 // 2,
    "-floatmin" => -floatmin(Float64), "big\"1e400\"" => big"1e400", "big\"-1e400\"" =>
        big"-1e400",
    "big\"1e-400\"" => big"1e-400", ":a" => :a, "1 + 1im" => 1 + 1im, "\"1\"" => "1",
]
const GOOD = [
    "1" => 1, "2" => 2, "0.5" => 0.5, "0.5f0" => 0.5f0,
    "0.1f0" => 0.1f0, "1//2" => 1 // 2, "3//4" => 3 // 4,
    "big\"0.5\"" => big"0.5", "1e-3" => 1.0e-3, "1e300" => 1.0e300, "floatmin" =>
        floatmin(Float64),
]
"""`f()` throws an ArgumentError whose message contains every one of `words`."""
function argerror(f, words...)
    err = try
        f()
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    err isa ArgumentError && for w in words
        @test occursin(w, err.msg)
    end
    return err
end
# ---------------------------------------------------------------------------------------
# B (cont.). Unchanged pins
function two_wortel()
    s = zeros(Int32, 8, 8)
    s[2:3, 2:3] .= 1
    s[6:7, 6:7] .= 2
    return [ownership => s, kind => [:cell, :cell]]
end
function unchanged()
    return (
        "default" => () -> problem(Default(; name = :ode)),
        "md = 1.0" => () -> problem(ODE(; name = :ode, md = 1.0)),
        "md = 1" => () -> problem(ODE(; name = :ode, md = 1)),
        "md = 0.5" => () -> problem(ODE(; name = :ode, md = 0.5)),
        "md = 1//2" => () -> problem(ODE(; name = :ode, md = 1 // 2)),
        "md = 0.5f0" => () -> problem(ODE(; name = :ode, md = 0.5f0)),
        "md = 2" => () -> problem(ODE(; name = :ode, md = 2)),
        "md = 0.1f0" => () -> problem(ODE(; name = :ode, md = 0.1f0)),
        "Barker md = 0.5" => () -> problem(ODE(; name = :ode, md = 0.5, barker = true)),
        "md = 0.5 Adaptive" =>
            () -> problem(ODE(; name = :ode, md = 0.5); ode_solver = Adaptive(Rodas5P())),
        "md = 0.5 Float32" => () -> problem(ODE(; name = :ode, md = 0.5); T = Float32),
        "extension inheriting md = 0.5" =>
            () -> problem(ExtInherit(; name = :ext, md = 0.5)),
        "field md = 0.5" =>
            () -> PottsProblem(
            Field(; name = :fd, md = 0.5), [duration_op(); :c => ones(12, 12)], (0, 3);
            field_solver = ExplicitEuler()
        ),
        "clock md = 0.5" =>
            () -> PottsProblem(
            DurationClock(; name = :clk, md = 0.5), duration_op(), (
                0, 4,
            )
        ),
        "GranerGlazier" =>
            () -> (
            s = graner_glazier_state();
            PottsProblem(
                GranerGlazier(; name = :gg), [
                    ownership => s[1], kind => s[2],
                ], (0, 10)
            )
        ),
        "WortelAct" =>
            () -> PottsProblem(
            WortelAct(; name = :act, lattice = (8, 8)), two_wortel(), (
                0, 10,
            )
        ),
        "WortelAct connected" =>
            () -> PottsProblem(
            WortelAct(; name = :act, lattice = (8, 8), connected = true),
            two_wortel(), (0, 10)
        ),
        "MerksVasculogenesis" =>
            () -> PottsProblem(
            MerksVasculogenesis(; name = :merks, lattice = (8, 8)),
            [
                ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind =>
                    [:endothelial],
            ], (0, 10);
            field_solver = Potts.ExplicitEuler(substeps = 2, lower_bound = 0.0)
        ),
        "SingleDivisionFixture" =>
            () -> PottsProblem(
            SingleDivisionFixture(; name = :fixture),
            [
                ownership => (s = zeros(Int32, 12, 8); s[5:8, 4:5] .= 1; s), kind =>
                    [:epithelial],
            ], (0, 10)
        ),
        "OpenVTGrowingMonolayer" =>
            () -> PottsProblem(
            OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24)),
            openvt_monolayer_state(; lattice = (24, 24)), (0, 10); capacity = 64
        ),
        "AkeebInvasion" =>
            () -> PottsProblem(
            AkeebInvasion(; name = :akeeb, lattice = (60, 40)), akeeb_state(;
                lattice = (60, 40)
            ), (0, 10);
            capacity = 256
        ),
    )
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "mcs duration: controls" setup = [MCSDurationSetup] tags = [
    :pottsmodels,
    :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # Controls (pass on the base)
    @testset "mcs duration: controls" begin
        # valid durations build (the error channel below is not a blanket failure)
        @test ODE(; name = :ode, md = 0.5) isa PottsSystem
        @test ODE(; name = :ode, md = 0.5, barker = true) isa PottsSystem
        @test LITERAL["0.5"](; name = :lit) isa PottsSystem
        # an `@sweep` ArgumentError surfaces from building the system, and the message check
        # discriminates: the D-123 offset error does not name `mcs_duration`
        err = argerror(() -> BadOffset(; name = :off), "offset")
        @test err isa ArgumentError && !occursin("mcs_duration", err.msg)
        # the duration reaches the solvers: 0.5 and 1.0 runs differ, the default equals 1.0
        @test duration_y(ODE(; name = :ode, md = 0.5)) !=
            duration_y(ODE(; name = :ode, md = 1.0))
        @test duration_y(Default(; name = :ode)) == duration_y(ODE(; name = :ode, md = 1.0))
    end
end

@testitem "mcs duration: an invalid mcs_duration is an ArgumentError at build" setup = [
    MCSDurationSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # A. Invalid durations are an ArgumentError naming `mcs_duration`, at build
    @testset "mcs duration: an invalid mcs_duration is an ArgumentError at build" begin
        for barker in (false, true), (l, v) in BAD
            @testset "$(barker ? "Barker" : "Metropolis")(mcs_duration = $l)" begin
                argerror(() -> ODE(; name = :ode, md = v, barker), "mcs_duration")
            end
        end
        for l in ("NaN", "Inf", "0", "-1.0")
            @testset "literal mcs_duration = $l" begin
                argerror(() -> LITERAL[l](; name = :lit), "mcs_duration")
            end
        end
        # the readers that failed late or silently on the base now fail at build
        for (l, v) in ("NaN" => NaN, "0" => 0.0, "-1" => -1.0)
            @testset "field and clock models, mcs_duration = $l" begin
                argerror(() -> Field(; name = :fd, md = v), "mcs_duration")
                argerror(() -> DurationClock(; name = :clk, md = v), "mcs_duration")
            end
        end
        @testset "a symbolic parameter" begin
            argerror(() -> Symbolic(; name = :sym), "mcs_duration")
        end
        @testset "@extend" begin
            argerror(() -> ExtOwn(; name = :ext, md = NaN), "mcs_duration")
            argerror(() -> ExtOwn(; name = :ext, md = -1), "mcs_duration")
            argerror(() -> ExtInherit(; name = :ext, md = 0), "mcs_duration")
            argerror(() -> ExtInherit(; name = :ext, md = Inf), "mcs_duration")
        end
        # the sweep constructor itself (the macro's target)
        for law in (:metropolis, :barker), (l, v) in BAD
            @test_throws ArgumentError Potts.sweep_spec(
                law; temperature = 1.0,
                mcs_duration = v
            )
        end
    end
end

@testitem "mcs duration: positive finite durations are accepted" setup = [
    MCSDurationSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # B. Valid durations are accepted and behave as before
    @testset "mcs duration: positive finite durations are accepted" begin
        for law in (:metropolis, :barker), (l, v) in GOOD
            s = Potts.sweep_spec(law; temperature = 1.0, mcs_duration = v)
            @test isequal(s.mcs_duration, float(v)) && s.mcs_duration isa typeof(float(v))
        end
        for (l, v) in GOOD
            @testset "md = $l" begin
                md = getfield(
                    getfield(ODE(; name = :ode, md = v), :part),
                    :sweep
                ).mcs_duration
                @test isequal(md, float(v)) && md isa typeof(float(v))
            end
        end
        @test getfield(
            getfield(ExtInherit(; name = :ext, md = 0.5), :part),
            :sweep
        ).mcs_duration ===
            0.5
        @test getfield(
            getfield(ExtOwn(; name = :ext, md = 0.5), :part),
            :sweep
        ).mcs_duration ===
            0.5
    end
end

@testitem "mcs duration: runs at mcs_duration = 0.5 (checked by hand)" setup = [
    MCSDurationSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "mcs duration: runs at mcs_duration = 0.5 (checked by hand)" begin
        sys = ODE(; name = :ode, md = 0.5)
        # 3 MCS of length h = 0.5 of y' = -y from 1:
        #   ExplicitEuler (one step per MCS): (1 - h)³ = 0.125
        @test duration_y(sys) == 0.125
        #   RK4: (1 - h + h²/2 - h³/6 + h⁴/24)³ = (0.60677083…)³ = 0.22339533…
        @test duration_y(sys; ode_solver = Potts.RK4()) ≈
            (1 - 0.5 + 0.125 - 0.5^3 / 6 + 0.5^4 / 24)^3 rtol = 1.0e-12
        #   Adaptive: e^{-1.5}
        @test duration_y(
            sys;
            ode_solver = Adaptive(Rodas5P(); reltol = 1.0e-10, abstol = 1.0e-12)
        ) ≈
            exp(-1.5) rtol = 1.0e-6
        # the same Float64 by another type gives the same run
        for v in (1 // 2, 0.5f0, big"0.5")
            @test duration_y(ODE(; name = :ode, md = v)) == 0.125
        end
        # Barker runs
        @test Symbol(
            solve(
                problem(ODE(; name = :ode, md = 0.5, barker = true)),
                SequentialCPM()
            ).retcode
        ) ===
            :Success
        # an integer duration: 3 MCS of length 2, Adaptive: e^{-6}
        @test duration_y(
            ODE(; name = :ode, md = 2);
            ode_solver = Adaptive(Rodas5P(); reltol = 1.0e-10, abstol = 1.0e-12)
        ) ≈ exp(-6) rtol = 1.0e-6
        # field: the auto substep count at dt = 0.5 is 1 (0.5 · (0.1 · 8 + 0.05) = 0.425 ≤
        # 1.8), so a uniform c = 1 decays to (1 - 0.5 · 0.05)³ = 0.975³ on each of 144 sites
        fprob = PottsProblem(
            Field(; name = :fd, md = 0.5), [duration_op(); :c => ones(12, 12)], (0, 3);
            field_solver = ExplicitEuler()
        )
        @test sum(solve(fprob, SequentialCPM()).u[end].site.c) ≈ 144 *
            0.975^3 rtol = 1.0e-12
        # clock: Clock(1.0) at MCS length 0.5 ticks every 2 MCS (t = 1, 2 after MCS 2, 4)
        cprob = PottsProblem(DurationClock(; name = :clk, md = 0.5), duration_op(), (0, 4))
        @test [u.cell.ctr₊n[1] for u in solve(cprob, SequentialCPM(); saveat = 0:4).u] ==
            [0.0, 0.0, 1.0, 1.0, 2.0]
    end
end

@testitem "mcs duration: PottsProblem, remake and solve do not take mcs_duration" setup = [
    MCSDurationSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    # --------------------------------------------------------------------------------------
    # C. No other path sets the duration
    @testset "mcs duration: PottsProblem, remake and solve do not take mcs_duration" begin
        prob = problem(ODE(; name = :ode, md = 0.5))
        # a problem keeps unknown keywords for `solve` (SciML), which refuses them by name
        @test_throws ArgumentError solve(
            problem(ODE(; name = :ode, md = 0.5); mcs_duration = NaN), SequentialCPM()
        )
        @test_throws ArgumentError remake(prob; mcs_duration = NaN)
        @test_throws ArgumentError solve(prob, SequentialCPM(); mcs_duration = NaN)
        # control: the problem itself is fine
        @test Symbol(solve(prob, SequentialCPM()).retcode) === :Success
    end
end

@testitem "mcs duration: the duration's type does not move the fingerprint" setup = [
    MCSDurationSetup,
] tags = [
    :pottsmodels, :acceptance,
] begin
    @testset "mcs duration: the duration's type does not move the fingerprint" begin
        fps = Dict(name => build().f.fingerprint for (name, build) in unchanged())
        # the same Float64 duration fingerprints alike whatever its type; another duration
        # differs
        @test fps["md = 1.0"] == fps["md = 1"] == fps["default"]
        @test fps["md = 0.5"] == fps["md = 1//2"] == fps["md = 0.5f0"]
        @test length(
            unique(
                [
                    fps["md = 1.0"], fps["md = 0.5"], fps["md = 2"], fps["md = 0.1f0"],
                ]
            )
        ) == 4
    end
end

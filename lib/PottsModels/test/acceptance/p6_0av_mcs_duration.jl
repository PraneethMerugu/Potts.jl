# P6.0av (ROADMAP Phase 6, step 0; found by the P6.0as test author): `@sweep mcs_duration`
# is not validated. Decision: D-126 (follows D-123, which did the same for `offset`).
# Frozen (AUTONOMY §7.3).
#
# The defect, measured on ab26cd37. `sweep_spec` (src/vocabulary.jl) stores
# `Float64(mcs_duration)` unchecked, and every reader trusts it: the `Adaptive` ODE step
# integrates over `[mcs, mcs + 1) × mcs_duration`, `ExplicitEuler`/`RK4` take steps of
# `mcs_duration`, the field step's substep count divides by it, the clock cadence of a
# discrete component is `dt / mcs_duration`, and the fingerprint hashes it. For the cell ODE
# `D(y) ~ -y`, y(0) = 1, 3 MCS:
#   - NaN or ±Inf: the model builds and `PottsProblem` accepts it; `Adaptive(Rodas5P())`
#     throws `SciMLBase.NaNTspanError` at the first solve, `ExplicitEuler()` and `RK4()`
#     return retcode Success with y = NaN; the auto-substep field step throws
#     `InexactError: Int64(NaN)`; a `Clock(1.0)` component is refused at `PottsProblem` with
#     a message about the clock period, not about `mcs_duration`.
#   - 0: every solver returns y = 1.0 (time stands still), Success; `Adaptive` only warns
#     "Initial timestep too small"; a `Clock(1.0)` component throws `InexactError: Int64(Inf)`.
#   - -1: time runs backwards silently: `Adaptive` y = e³ = 20.0855, `ExplicitEuler` 2³ = 8,
#     the field grows instead of decaying.
#   - a non-Real (`:a`, `1 + 1im`, `"1"`, a symbolic `@parameters τ`) throws a `MethodError`
#     or `InexactError` from `Float64(…)`, naming neither `@sweep` nor `mcs_duration`.
#   - `big"1e400"` (finite, but over `floatmax(Float64)`) is stored as Inf; `big"1e-400"`
#     (positive) as 0.0.
#
# Rule (D-126), pinned here:
#  A. `mcs_duration` must be a `Real` that is finite and > 0 after conversion to Float64.
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
#  C. Bypass paths: `mcs_duration` reaches a problem only through `@sweep` (or inheritance of
#     a base's sweep under `@extend`): `PottsProblem`, `remake` and `solve` do not take it.
#     Pinned as a guard: each refuses the keyword.
using Potts: CorePotts
using Potts.ModelingToolkitBase: System, ShiftIndex, Clock, @variables
using OrdinaryDiffEqRosenbrock: Rodas5P

# ---------------------------------------------------------------------------------------
# Fixtures. One 3×3 cell of kind A on a 12×12 lattice, a cell ODE `D(y) ~ -y` (y(0) = 1);
# the duration is a structural keyword `md`, so `P60avODE(; md = v)` builds with `v`.

@potts_model P60avODE begin
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
@potts_model P60avDefault begin
    @kinds medium A
    @variables y(cell) = 1.0
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @equations D(y) ~ -y
    @sweep Metropolis(; temperature = 1.0)
end

# a field `c` with uniform decay: on a uniform field Δc = 0, so c' = -0.05 c
@potts_model P60avField begin
    @structural_parameters md = 1.0
    @kinds medium A
    @variables c(field) = 0.0
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @equations D(c) ~ 0.1 * Δ(c) - 0.05 * c
    @sweep Metropolis(; temperature = 1.0, mcs_duration = md)
end

# a discrete per-tick counter `n(k) = n(k − 1) + 1` on a `Clock(1.0)` component
const P60AV_SYSTEM = Ref{Any}(nothing)
function p60av_counter(k)
    t = Potts.t
    @variables n(t) = 0.0
    return System([n(k) ~ n(k - 1) + 1.0], t; name = :ctr)
end
@potts_model P60avClock begin
    @structural_parameters md = 1.0
    @kinds medium A
    @components cells(A) ctr = P60AV_SYSTEM[]
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0e-6, mcs_duration = md)
end
P60AV_SYSTEM[] = p60av_counter(ShiftIndex(Clock(1.0)))

# a symbolic parameter as the duration
@potts_model P60avSymbolic begin
    @kinds medium A
    @parameters τ = 0.5
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0, mcs_duration = τ)
end

# `@extend`: an extension with its own `@sweep`, and one inheriting the base's
@potts_model P60avExtOwn begin
    @structural_parameters md = 1.0
    @extend base = P60avODE()
    @sweep Metropolis(; temperature = 1.0, mcs_duration = md)
end
@potts_model P60avExtInherit begin
    @structural_parameters md = 1.0
    @extend base = P60avODE(; md = md)
end

# literals written in `@sweep` (a model per value; built lazily)
const P60AV_LITERAL = Dict{String, Any}()
for (i, (label, v)) in enumerate(["NaN" => :NaN, "Inf" => :Inf, "0" => 0, "-1.0" => -1.0, "0.5" => 0.5])
    name = Symbol(:P60avLiteral, i)
    @eval @potts_model $name begin
        @kinds medium A
        @lattice Lattice((12, 12))
        @energy cells => (volume - 9.0)^2
        @sweep Metropolis(; temperature = 1.0, mcs_duration = $v)
    end
    P60AV_LITERAL[label] = @eval $name
end

# an invalid offset (D-123) with a valid duration: its ArgumentError does not name
# `mcs_duration` (negative control for the message check)
@potts_model P60avBadOffset begin
    @kinds medium A
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0, offset = NaN, mcs_duration = 0.5)
end

p60av_sigma() = (s = zeros(Int32, 12, 12); s[3:5, 3:5] .= 1; s)
p60av_op() = [ownership => p60av_sigma(), kind => [:A]]
p60av_problem(sys; tspan = (0, 3), kw...) = PottsProblem(sys, p60av_op(), tspan; kw...)
p60av_y(sys; kw...) = solve(p60av_problem(sys; kw...), SequentialCPM()).u[end].cell.y[1]

const P60AV_BAD = [
    "NaN" => NaN, "Inf" => Inf, "-Inf" => -Inf, "NaN32" => NaN32, "Inf32" => Inf32, "-Inf32" => -Inf32,
    "0" => 0, "0.0" => 0.0, "-0.0" => -0.0, "0.0f0" => 0.0f0, "-1" => -1, "-0.5" => -0.5, "-1//2" => -1 // 2,
    "-floatmin" => -floatmin(Float64), "big\"1e400\"" => big"1e400", "big\"-1e400\"" => big"-1e400",
    "big\"1e-400\"" => big"1e-400", ":a" => :a, "1 + 1im" => 1 + 1im, "\"1\"" => "1",
]
const P60AV_GOOD = [
    "1" => 1, "2" => 2, "0.5" => 0.5, "0.5f0" => 0.5f0, "0.1f0" => 0.1f0, "1//2" => 1 // 2, "3//4" => 3 // 4,
    "big\"0.5\"" => big"0.5", "1e-3" => 1.0e-3, "1e300" => 1.0e300, "floatmin" => floatmin(Float64),
]

"""`f()` throws an ArgumentError whose message contains every one of `words`."""
function p60av_argerror(f, words...)
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
# Controls (pass on the base)

@testset "P6.0av: controls" begin
    # valid durations build (the error channel below is not a blanket failure)
    @test P60avODE(; name = :ode, md = 0.5) isa PottsSystem
    @test P60avODE(; name = :ode, md = 0.5, barker = true) isa PottsSystem
    @test P60AV_LITERAL["0.5"](; name = :lit) isa PottsSystem
    # an `@sweep` ArgumentError surfaces from building the system, and the message check
    # discriminates: the D-123 offset error does not name `mcs_duration`
    err = p60av_argerror(() -> P60avBadOffset(; name = :off), "offset")
    @test err isa ArgumentError && !occursin("mcs_duration", err.msg)
    # the duration reaches the solvers: 0.5 and 1.0 runs differ, the default equals 1.0
    @test p60av_y(P60avODE(; name = :ode, md = 0.5)) != p60av_y(P60avODE(; name = :ode, md = 1.0))
    @test p60av_y(P60avDefault(; name = :ode)) == p60av_y(P60avODE(; name = :ode, md = 1.0))
end

# ---------------------------------------------------------------------------------------
# A. Invalid durations are an ArgumentError naming `mcs_duration`, at build

@testset "P6.0av: an invalid mcs_duration is an ArgumentError at build" begin
    for barker in (false, true), (l, v) in P60AV_BAD
        @testset "$(barker ? "Barker" : "Metropolis")(mcs_duration = $l)" begin
            p60av_argerror(() -> P60avODE(; name = :ode, md = v, barker), "mcs_duration")
        end
    end
    for l in ("NaN", "Inf", "0", "-1.0")
        @testset "literal mcs_duration = $l" begin
            p60av_argerror(() -> P60AV_LITERAL[l](; name = :lit), "mcs_duration")
        end
    end
    # the readers that failed late or silently on the base now fail at build
    for (l, v) in ("NaN" => NaN, "0" => 0.0, "-1" => -1.0)
        @testset "field and clock models, mcs_duration = $l" begin
            p60av_argerror(() -> P60avField(; name = :fd, md = v), "mcs_duration")
            p60av_argerror(() -> P60avClock(; name = :clk, md = v), "mcs_duration")
        end
    end
    @testset "a symbolic parameter" begin
        p60av_argerror(() -> P60avSymbolic(; name = :sym), "mcs_duration")
    end
    @testset "@extend" begin
        p60av_argerror(() -> P60avExtOwn(; name = :ext, md = NaN), "mcs_duration")
        p60av_argerror(() -> P60avExtOwn(; name = :ext, md = -1), "mcs_duration")
        p60av_argerror(() -> P60avExtInherit(; name = :ext, md = 0), "mcs_duration")
        p60av_argerror(() -> P60avExtInherit(; name = :ext, md = Inf), "mcs_duration")
    end
    # the sweep constructor itself (the macro's target)
    for law in (:metropolis, :barker), (l, v) in P60AV_BAD
        @test_throws ArgumentError Potts.sweep_spec(law; temperature = 1.0, mcs_duration = v)
    end
end

# ---------------------------------------------------------------------------------------
# B. Valid durations are accepted and behave as before

@testset "P6.0av: positive finite durations are accepted" begin
    for law in (:metropolis, :barker), (l, v) in P60AV_GOOD
        s = Potts.sweep_spec(law; temperature = 1.0, mcs_duration = v)
        @test s.mcs_duration === Float64(v)
    end
    for (l, v) in P60AV_GOOD
        @testset "md = $l" begin
            @test P60avODE(; name = :ode, md = v).sweep.mcs_duration === Float64(v)
        end
    end
    @test P60avExtInherit(; name = :ext, md = 0.5).sweep.mcs_duration === 0.5
    @test P60avExtOwn(; name = :ext, md = 0.5).sweep.mcs_duration === 0.5
end

@testset "P6.0av: runs at mcs_duration = 0.5 (checked by hand)" begin
    sys = P60avODE(; name = :ode, md = 0.5)
    # 3 MCS of length h = 0.5 of y' = -y from 1:
    #   ExplicitEuler (one step per MCS): (1 - h)³ = 0.125
    @test p60av_y(sys) == 0.125
    #   RK4: (1 - h + h²/2 - h³/6 + h⁴/24)³ = (0.60677083…)³ = 0.22339533…
    @test p60av_y(sys; ode_solver = RK4()) ≈ (1 - 0.5 + 0.125 - 0.5^3 / 6 + 0.5^4 / 24)^3 rtol = 1e-12
    #   Adaptive: e^{-1.5}
    @test p60av_y(sys; ode_solver = Adaptive(Rodas5P(); reltol = 1e-10, abstol = 1e-12)) ≈ exp(-1.5) rtol = 1e-6
    # the same Float64 by another type gives the same run
    for v in (1 // 2, 0.5f0, big"0.5")
        @test p60av_y(P60avODE(; name = :ode, md = v)) == 0.125
    end
    # Barker runs
    @test Symbol(solve(p60av_problem(P60avODE(; name = :ode, md = 0.5, barker = true)), SequentialCPM()).retcode) === :Success
    # an integer duration: 3 MCS of length 2, Adaptive: e^{-6}
    @test p60av_y(P60avODE(; name = :ode, md = 2); ode_solver = Adaptive(Rodas5P(); reltol = 1e-10, abstol = 1e-12)) ≈ exp(-6) rtol = 1e-6
    # field: the auto substep count at dt = 0.5 is 1 (0.5 · (0.1 · 8 + 0.05) = 0.425 ≤ 1.8),
    # so a uniform c = 1 decays to (1 - 0.5 · 0.05)³ = 0.975³ on each of 144 sites
    fprob = PottsProblem(P60avField(; name = :fd, md = 0.5), [p60av_op(); :c => ones(12, 12)], (0, 3);
        field_solver = ExplicitEuler())
    @test sum(solve(fprob, SequentialCPM()).u[end].site.c) ≈ 144 * 0.975^3 rtol = 1e-12
    # clock: Clock(1.0) at MCS length 0.5 ticks every 2 MCS (t = 1, 2 after MCS 2, 4)
    cprob = PottsProblem(P60avClock(; name = :clk, md = 0.5), p60av_op(), (0, 4))
    @test [u.cell.ctr₊n[1] for u in solve(cprob, SequentialCPM(); saveat = 0:4).u] == [0.0, 0.0, 1.0, 1.0, 2.0]
end

# ---------------------------------------------------------------------------------------
# C. No other path sets the duration

@testset "P6.0av: PottsProblem, remake and solve do not take mcs_duration" begin
    prob = p60av_problem(P60avODE(; name = :ode, md = 0.5))
    @test_throws Exception p60av_problem(P60avODE(; name = :ode, md = 0.5); mcs_duration = NaN)
    @test_throws Exception remake(prob; mcs_duration = NaN)
    @test_throws Exception solve(prob, SequentialCPM(); mcs_duration = NaN)
    # control: the problem itself is fine
    @test Symbol(solve(prob, SequentialCPM()).retcode) === :Success
end

# ---------------------------------------------------------------------------------------
# B (cont.). Unchanged pins

function p60av_two_wortel()
    s = zeros(Int32, 8, 8)
    s[2:3, 2:3] .= 1
    s[6:7, 6:7] .= 2
    return [ownership => s, kind => [:cell, :cell]]
end
p60av_unchanged() = (
    "default" => () -> p60av_problem(P60avDefault(; name = :ode)),
    "md = 1.0" => () -> p60av_problem(P60avODE(; name = :ode, md = 1.0)),
    "md = 1" => () -> p60av_problem(P60avODE(; name = :ode, md = 1)),
    "md = 0.5" => () -> p60av_problem(P60avODE(; name = :ode, md = 0.5)),
    "md = 1//2" => () -> p60av_problem(P60avODE(; name = :ode, md = 1 // 2)),
    "md = 0.5f0" => () -> p60av_problem(P60avODE(; name = :ode, md = 0.5f0)),
    "md = 2" => () -> p60av_problem(P60avODE(; name = :ode, md = 2)),
    "md = 0.1f0" => () -> p60av_problem(P60avODE(; name = :ode, md = 0.1f0)),
    "Barker md = 0.5" => () -> p60av_problem(P60avODE(; name = :ode, md = 0.5, barker = true)),
    "md = 0.5 Adaptive" => () -> p60av_problem(P60avODE(; name = :ode, md = 0.5); ode_solver = Adaptive(Rodas5P())),
    "md = 0.5 Float32" => () -> p60av_problem(P60avODE(; name = :ode, md = 0.5); T = Float32),
    "extension inheriting md = 0.5" => () -> p60av_problem(P60avExtInherit(; name = :ext, md = 0.5)),
    "field md = 0.5" => () -> PottsProblem(P60avField(; name = :fd, md = 0.5), [p60av_op(); :c => ones(12, 12)], (0, 3);
        field_solver = ExplicitEuler()),
    "clock md = 0.5" => () -> PottsProblem(P60avClock(; name = :clk, md = 0.5), p60av_op(), (0, 4)),
    "GranerGlazier" => () -> (s = graner_glazier_state(); PottsProblem(GranerGlazier(; name = :gg), [ownership => s[1], kind => s[2]], (0, 10))),
    "WortelAct" => () -> PottsProblem(WortelAct(; name = :act, lattice = (8, 8)), p60av_two_wortel(), (0, 10)),
    "WortelAct connected" => () -> PottsProblem(WortelAct(; name = :act, lattice = (8, 8), connected = true), p60av_two_wortel(), (0, 10)),
    "MerksVasculogenesis" => () -> PottsProblem(MerksVasculogenesis(; name = :merks, lattice = (8, 8)),
        [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]], (0, 10);
        field_solver = Potts.ExplicitEuler(substeps = 2, lower = 0.0)),
    "SingleDivisionFixture" => () -> PottsProblem(SingleDivisionFixture(; name = :fixture),
        [ownership => (s = zeros(Int32, 12, 8); s[5:8, 4:5] .= 1; s), kind => [:epithelial]], (0, 10)),
    "OpenVTGrowingMonolayer" => () -> PottsProblem(OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24)),
        openvt_monolayer_state(; lattice = (24, 24)), (0, 10); capacity = 64),
    "AkeebInvasion" => () -> PottsProblem(AkeebInvasion(; name = :akeeb, lattice = (60, 40)), akeeb_state(; lattice = (60, 40)), (0, 10);
        capacity = 256),
)

# the fixtures recorded on ab26cd37; the PottsModels systems are the D-121/D-122/D-123 pins
const P60AV_FINGERPRINTS = Dict{String, UInt64}(
    "default" => 0xce5034a13ca88aa5,
    "md = 1.0" => 0xce5034a13ca88aa5,
    "md = 1" => 0xce5034a13ca88aa5,
    "md = 0.5" => 0xe0b87213e7b75671,
    "md = 1//2" => 0xe0b87213e7b75671,
    "md = 0.5f0" => 0xe0b87213e7b75671,
    "md = 2" => 0x50bbc875e573d7fb,
    "md = 0.1f0" => 0x62f74878732d8598,
    "Barker md = 0.5" => 0x5005a1da9c54b3b8,
    "md = 0.5 Adaptive" => 0xc32136fed7d16010,
    "md = 0.5 Float32" => 0x4c1d651560a149f2,
    "extension inheriting md = 0.5" => 0xe0b87213e7b75671,
    "field md = 0.5" => 0x0604ff900ded1dcb,
    "clock md = 0.5" => 0x69c263c32c478ae3,
    "GranerGlazier" => 0x04a4528dcdf3fcb8,
    "WortelAct" => 0xd6d4f8e4e7850c5e,
    "WortelAct connected" => 0xa2b5702602b1e8f9,
    "MerksVasculogenesis" => 0x984e2ad5906fc999,
    "SingleDivisionFixture" => 0x13a4ddc2bb677287,
    "OpenVTGrowingMonolayer" => 0xfcecc4612f387b5e,
    "AkeebInvasion" => 0x8d33bd0bb1eddd1c,
)

@testset "P6.0av: fingerprints unchanged" begin
    fps = Dict(name => build().f.fingerprint for (name, build) in p60av_unchanged())
    for (name, _) in p60av_unchanged()
        @test fps[name] == P60AV_FINGERPRINTS[name]
        fps[name] == P60AV_FINGERPRINTS[name] || @info "P6.0av: fingerprint $name = $(repr(fps[name]))"
    end
    # the same Float64 duration fingerprints alike whatever its type; another duration differs
    @test fps["md = 1.0"] == fps["md = 1"] == fps["default"]
    @test fps["md = 0.5"] == fps["md = 1//2"] == fps["md = 0.5f0"]
    @test length(unique([fps["md = 1.0"], fps["md = 0.5"], fps["md = 2"], fps["md = 0.1f0"]])) == 4
end

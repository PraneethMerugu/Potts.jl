# the D-016 fingerprint includes the tick cadence.
# Decision: D-118 (amends D-016).
#
# The defect (D-084 "Observation"). The fingerprint is a hash
# of the generated expressions plus the lattice, spacing, neighbourhood, `T` and the solver
# spec (`_problem_function`, src/problem.jl). A cadence that lives outside the generated code
# is not in it, so two problems that run on different schedules fingerprint alike and a
# checkpoint of one loads into the other. Measured on 4e81e1eb:
#   - MTK clocks of discrete components (`_clocked` → `_Gated(every, offset, phase)`): the
#     cell-scope counter fixture below fingerprints 0x624e96d3df447c64 under ShiftIndex(t, 0),
#     Clock(2), Clock(3), Clock(3; phase = 1) and Clock(3; phase = 2): five schedules, one
#     fingerprint; Clock(1) at mcs_duration = 0.5 (every = 2) and at 1.0 (every = 1) collide
#     too. Model scope likewise (0xe007692286f04d18 for ShiftIndex(t, 0), Clock(2),
#     Clock(2; phase = 1), Clock(3)).
#   - `@divide … Every(n)` when every rule shares one cadence: the cadence is `Lifecycle.every`
#     and no modulo gate is generated (`_cadence_gate(n, g) = nothing` when n == gcd), so
#     Every(1), Every(2), Every(3) fingerprint alike (0x1c66296d224ca43b on the fixture below).
#   - `@link … Every(n)`: the cadence is `HostPhase.every`, not in the code (Every(1), (2), (7)
#     all 0x3693e521a3895940).
#   NOT a gap: `@after_mcs`/`@before_mcs Every(n)` updates: their cell/model/site functions
#   carry `mcs % n == 0 || return nothing` in the generated code, so their fingerprints already
#   differ (Every(1/2/3): 0x97770dd85d99f955, 0x16868ec68c10f99e, 0x05bdb80c9bc4a49c). Their
#   auxiliary `_Gated` phases (fold slots, integral refreshes, site copies) always accompany a
#   gated update function. Asserted below as a control (passes on the base).
#
# Semantics pinned here:
#  1. Controls (pass on the base): the clocked fixtures really tick on different schedules
#     (tick counts against the MTK clock-time oracle of test/symbolic.jl: ticks at
#     t = phase + k·dt, the state saved at t has had #{τ ∈ phase:dt:t, τ > 0} ticks), and the
#     rule-cadence fixtures really fire on different schedules.
#  2. Two problems that differ only in a discrete component's clock period or phase (cell
#     scope and model scope; the `boolean_network_tests.jl` three-node network with Clock(2.0) vs ShiftIndex(t, 0)
#     as planned), or in `mcs_duration` where that changes the resolved cadence,
#     have different fingerprints. How the cadence enters the hash (resolved every/offset of
#     each gated phase, or the clock spec) is left to the implementer; equal fingerprints for
#     equal resolved cadences (e.g. Clock(1.0) vs ShiftIndex(t, 0)) are NOT required.
#  3. Likewise for the cadence of `@divide` and `@link` rules (the same gap: a schedule the
#     code does not show).
#  4. A checkpoint of one fails to load into the other with an `ArgumentError` (in memory and
#     through save_checkpoint/load_checkpoint); a problem built afresh with the same cadence
#     still loads it (control: the error is the fingerprint, not tspan or the state).
#  5. Fingerprints of models without clocked components are unchanged: every PottsModels
#     system and clock-free fixtures (update cadences Every(1) and Every(2), `@divide` and
#     `@link` at the default Every(1)), values recorded on 4e81e1eb (Julia 1.12, T = Float64,
#     default solvers unless named). So a non-default `@divide`/`@link` cadence may change a
#     fingerprint (item 3), the default may not; GranerGlazier, Merks and OpenVT agree with the
#     pins of `ode_expansion_tests.jl`, `canonical_term_order_tests.jl` and
#     `lifecycle_launch_fusion_tests.jl`.

@testsetup module CadenceFingerprintSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
using Potts.ModelingToolkitBase: System, ShiftIndex, Clock, @variables, @parameters
# ---------------------------------------------------------------------------------------
# Fixtures: discrete components on clocks

# `@potts_model` resolves a component's system in module scope when the constructor runs
const SYSTEM = Ref{Any}(nothing)
"""A per-tick counter `n(k) = n(k − 1) + 1` on ShiftIndex `k`."""
function tick_counter(k)
    t = Potts.t
    @variables n(t) = 0.0
    return System([n(k) ~ n(k - 1) + 1.0], t; name = :ctr)
end
"""The three-node network (`boolean_network` of boolean_network_tests.jl, unordered)."""
function tick_network(k)
    t = Potts.t
    @variables A(t)::Bool = false B(t)::Bool = false C(t)::Bool = false
    @parameters wnt::Bool = false
    return System([A(k) ~ wnt | (B(k - 1) & !C(k - 1)), B(k) ~ A(k - 1), C(k) ~ !(A(k - 1) | B(k - 1))], t; name = :grn)
end
function tick_cells(comp; mcs_duration = 1.0)
    SYSTEM[] = comp
    @potts_model Cells begin
        @kinds medium host
        @components cells(host) ctr = SYSTEM[]
        @lattice Lattice((12, 12))
        @energy cells => (volume - 9.0)^2
        @sweep Metropolis(; temperature = 1.0e-6, mcs_duration = mcs_duration)
    end
    return Cells(; name = :cells)
end
function tick_census(comp)
    SYSTEM[] = comp
    @potts_model Census begin
        @kinds medium host
        @components model ctr = SYSTEM[]
        @lattice Lattice((12, 12))
        @energy cells => (volume - 9.0)^2
        @sweep Metropolis(; temperature = 1.0e-6)
    end
    return Census(; name = :census)
end
function tick_grn(comp)
    SYSTEM[] = comp
    @potts_model Grn begin
        @kinds medium host
        @variables input(cell) = 0.0
        @components cells(host) grn = SYSTEM[]
        @equations grn.wnt ~ input > 0.5
        @lattice Lattice((12, 12))
        @energy cells => (volume - 9.0)^2
        @sweep Metropolis(; temperature = 1.0e-6)
    end
    return Grn(; name = :grn)
end
"""Two 3×3 host cells on a 12×12 lattice."""
function sigma()
    σ = zeros(Int32, 12, 12)
    σ[2:4, 2:4] .= 1
    σ[7:9, 7:9] .= 2
    return σ
end
const TICK_OP = [ownership => sigma(), kind => [:host, :host]]
problem(sys; tspan = (0, 12), kw...) = PottsProblem(sys, TICK_OP, tspan; kw...)
tick_fp(sys; kw...) = problem(sys; kw...).f.fingerprint
const TICK_T = Potts.t
# label => (clock, mcs_duration, resolved (every, offset) per D-077: after MCS m when
# (m + 1 − offset) % every == 0)
const CLOCKS = [
    "ShiftIndex(t, 0)" => (ShiftIndex(TICK_T, 0), 1.0),
    "Clock(2.0)" => (ShiftIndex(Clock(2.0)), 1.0),
    "Clock(3.0)" => (ShiftIndex(Clock(3.0)), 1.0),
    "Clock(3.0; phase = 1.0)" => (ShiftIndex(Clock(3.0; phase = 1.0)), 1.0),
    "Clock(3.0; phase = 2.0)" => (ShiftIndex(Clock(3.0; phase = 2.0)), 1.0),
]
# MTK clock-time oracle (test/symbolic.jl): ticks at t = phase + k·dt (t = 0 is the initial state)
oracle(dt, phase, n) = [Float64(count(τ -> 0 < τ <= t, phase:dt:n)) for t in 0:n]
const ORACLE = Dict(
    "ShiftIndex(t, 0)" => oracle(1, 0, 12), "Clock(2.0)" => oracle(2, 0, 12),
    "Clock(3.0)" => oracle(3, 0, 12), "Clock(3.0; phase = 1.0)" => oracle(3, 1, 12),
    "Clock(3.0; phase = 2.0)" => oracle(3, 2, 12)
)
ticks(prob; scope = :cell) =
    [getproperty(getproperty(u, scope), :ctr₊n)[1] for u in solve(prob, SequentialCPM(); saveat = 0:12).u]
# ---------------------------------------------------------------------------------------
# Fixtures: rule cadences (no clocked component)
@potts_model Divide begin
    @structural_parameters n = 1
    @kinds medium A
    @lattice Lattice((24, 24))
    @energy cells => (volume - 9.0)^2
    @divide cells(A) Every(n) when = volume >= 4, along = (1.0, 0.0)
    @sweep Metropolis(; temperature = 1.0e-6)
end
@potts_model Link begin
    @structural_parameters n = 1
    @kinds medium A
    @relationship bond(cell, cell) capacity = 1
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @link bond Every(n) when = new_contact(a, b)
    @sweep Metropolis(; temperature = 1.0e-6)
end
@potts_model Update begin
    @structural_parameters n = 1
    @kinds medium host
    @variables x(cell) = 0.0 m(model) = 0.0
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @after_mcs Every(n) x ~ x + 1
    @before_mcs Every(n) m ~ m + 1
    @sweep Metropolis(; temperature = 1.0e-6)
end
"""One 6×6 cell of kind A (divides along x while volume ≥ 4) on a 24×24 lattice."""
function divide_op()
    σ = zeros(Int32, 24, 24)
    σ[9:14, 9:14] .= 1
    return [ownership => σ, kind => [:A]]
end
tick_divide(n; tspan = (0, 12)) = PottsProblem(Divide(; name = :div, n), divide_op(), tspan; capacity = 64)
"""Two touching 3×3 cells: `new_contact` holds at the first link pass."""
function link_op()
    σ = zeros(Int32, 12, 12)
    σ[3:5, 3:5] .= 1
    σ[6:8, 3:5] .= 2
    return [ownership => σ, kind => [:A, :A]]
end
tick_link(n; tspan = (0, 12)) = PottsProblem(Link(; name = :link, n), link_op(), tspan)
alive(u) = count(>(0), Array(u.cell.volume))
"""The fingerprints `label => fp` differ pairwise (one @test per pair; a failure names the pair)."""
function pairwise_distinct(fps::AbstractVector{<:Pair})
    for i in eachindex(fps), j in (i + 1):lastindex(fps)
        (a, x), (b, y) = fps[i], fps[j]
        ok = x != y
        @test ok
        ok || @info "cadence fingerprint: `$a` and `$b` fingerprint alike ($(repr(x)))"
    end
end
"""A checkpoint of `pa` after `k` MCS: refused by `pb` (ArgumentError), accepted by `pa2`
(a fresh build of `pa`'s model), in memory and through a file."""
function checkpoint_refused(pa, pb, pa2; k = 3, alg = SequentialCPM())
    integ = init(pa, alg)
    for _ in 1:k
        step!(integ)
    end
    ck = checkpoint(integ)
    path = joinpath(mktempdir(), "cadence_fingerprint.jls")
    save_checkpoint(path, ck)
    ck2 = load_checkpoint(path)
    for c in (ck, ck2)
        @test_throws ArgumentError init(pb, alg; checkpoint = c)
        i2 = init(pa2, alg; checkpoint = c)          # control: the same schedule loads
        @test i2.t == k
    end
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "cadence fingerprint: controls — the fixtures run on different schedules" setup = [CadenceFingerprintSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 1. Controls (pass on the base)
    @testset "cadence fingerprint: controls — the fixtures run on different schedules" begin
        for (label, (clk, md)) in CLOCKS
            @test ticks(problem(tick_cells(tick_counter(clk); mcs_duration = md))) == ORACLE[label]
        end
        @test length(unique(values(ORACLE))) == length(CLOCKS)
        # the period is model time: Clock(1) at half an MCS per MCS ticks every two MCS
        @test ticks(problem(tick_cells(tick_counter(ShiftIndex(Clock(1.0))); mcs_duration = 0.5))) == oracle(2, 0, 12)
        @test ticks(problem(tick_cells(tick_counter(ShiftIndex(Clock(1.0)))))) == oracle(1, 0, 12)
        # model scope
        @test ticks(problem(tick_census(tick_counter(ShiftIndex(Clock(2.0))))); scope = :model) == oracle(2, 0, 12)
        @test ticks(problem(tick_census(tick_counter(ShiftIndex(Clock(2.0; phase = 1.0))))); scope = :model) == oracle(2, 1, 12)
        # rule cadences: one division round at MCS 0 then every n MCS (2^rounds cells, D-076);
        # 3 MCS: Every(1) → 8 cells, Every(2) → 4, Every(3) → 2
        @test [alive(solve(tick_divide(n; tspan = (0, 3)), SequentialCPM()).u[end]) for n in (1, 2, 3)] == [8, 4, 2]
        # updates: already fingerprinted (the gate is in the generated code)
        pairwise_distinct(["@after_mcs Every($n)" => tick_fp(Update(; name = :upd, n)) for n in (1, 2, 3)])
    end
end

@testitem "cadence fingerprint: the clock of a discrete component is in the fingerprint" setup = [CadenceFingerprintSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 2–3. A different schedule, a different fingerprint
    @testset "cadence fingerprint: the clock of a discrete component is in the fingerprint" begin
        @testset "the network: Clock(2.0) vs ShiftIndex(t, 0)" begin
            @test tick_fp(tick_grn(tick_network(ShiftIndex(Clock(2.0))))) != tick_fp(tick_grn(tick_network(ShiftIndex(TICK_T, 0))))
        end
        @testset "cell scope: periods and phases" begin
            pairwise_distinct([label => tick_fp(tick_cells(tick_counter(clk); mcs_duration = md)) for (label, (clk, md)) in CLOCKS])
        end
        @testset "cell scope: mcs_duration changes the resolved period" begin
            @test tick_fp(tick_cells(tick_counter(ShiftIndex(Clock(1.0))); mcs_duration = 0.5)) !=
                tick_fp(tick_cells(tick_counter(ShiftIndex(Clock(1.0))); mcs_duration = 1.0))
        end
        @testset "model scope: periods and phases" begin
            pairwise_distinct(
                [
                    label => tick_fp(tick_census(tick_counter(clk)))
                        for (label, clk) in (
                            "ShiftIndex(t, 0)" => ShiftIndex(TICK_T, 0), "Clock(2.0)" => ShiftIndex(Clock(2.0)),
                            "Clock(2.0; phase = 1.0)" => ShiftIndex(Clock(2.0; phase = 1.0)),
                            "Clock(3.0)" => ShiftIndex(Clock(3.0)),
                        )
                ]
            )
        end
        @testset "deterministic: the same clock built twice fingerprints alike" begin
            for (label, (clk, md)) in CLOCKS
                @test tick_fp(tick_cells(tick_counter(clk); mcs_duration = md)) == tick_fp(tick_cells(tick_counter(clk); mcs_duration = md))
            end
        end
    end
end

@testitem "cadence fingerprint: rule cadences are in the fingerprint" setup = [CadenceFingerprintSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "cadence fingerprint: rule cadences are in the fingerprint" begin
        pairwise_distinct(["@divide Every($n)" => tick_divide(n).f.fingerprint for n in (1, 2, 3)])
        pairwise_distinct(["@link Every($n)" => tick_link(n).f.fingerprint for n in (1, 2, 7)])
        @test tick_divide(2).f.fingerprint == tick_divide(2).f.fingerprint
        @test tick_link(7).f.fingerprint == tick_link(7).f.fingerprint
    end
end

@testitem "cadence fingerprint: a checkpoint does not load into another schedule" setup = [CadenceFingerprintSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------
    # 4. Checkpoints do not cross schedules
    @testset "cadence fingerprint: a checkpoint does not load into another schedule" begin
        clk(c) = problem(tick_cells(tick_counter(c)))
        @testset "Clock(2.0) → ShiftIndex(t, 0)" begin
            checkpoint_refused(clk(ShiftIndex(Clock(2.0))), clk(ShiftIndex(TICK_T, 0)), clk(ShiftIndex(Clock(2.0))))
        end
        @testset "Clock(3.0) → Clock(3.0; phase = 1.0)" begin
            checkpoint_refused(clk(ShiftIndex(Clock(3.0))), clk(ShiftIndex(Clock(3.0; phase = 1.0))), clk(ShiftIndex(Clock(3.0))))
        end
        @testset "the network: ShiftIndex(t, 0) → Clock(2.0)" begin
            grn(c) = problem(tick_grn(tick_network(c)))
            checkpoint_refused(grn(ShiftIndex(TICK_T, 0)), grn(ShiftIndex(Clock(2.0))), grn(ShiftIndex(TICK_T, 0)))
        end
        @testset "model scope: Clock(2.0) → Clock(2.0; phase = 1.0)" begin
            cen(c) = problem(tick_census(tick_counter(c)))
            checkpoint_refused(cen(ShiftIndex(Clock(2.0))), cen(ShiftIndex(Clock(2.0; phase = 1.0))), cen(ShiftIndex(Clock(2.0))))
        end
        @testset "@divide Every(2) → Every(3)" begin
            checkpoint_refused(tick_divide(2), tick_divide(3), tick_divide(2))
        end
        @testset "@link Every(2) → Every(7)" begin
            checkpoint_refused(tick_link(2), tick_link(7), tick_link(2))
        end
    end
end

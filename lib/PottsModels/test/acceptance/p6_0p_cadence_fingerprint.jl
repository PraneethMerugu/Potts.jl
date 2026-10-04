# P6.0p (ROADMAP Phase 6, step 0): the D-016 fingerprint includes the tick cadence.
# Decision: D-118 (amends D-016). Frozen (AUTONOMY §7.3).
#
# The defect (found by the P6.0k2 test author, D-084 "Observation"). The fingerprint is a hash
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
#     scope and model scope; the P6.0k three-node network with Clock(2.0) vs ShiftIndex(t, 0)
#     as in the ROADMAP row), or in `mcs_duration` where that changes the resolved cadence,
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
#     pins of p6_0ag/p6_0ah/p6_0af.
using Potts: CorePotts
using Potts.ModelingToolkitBase: System, ShiftIndex, Clock, @variables, @parameters

# ---------------------------------------------------------------------------------------
# Fixtures: discrete components on clocks

# `@potts_model` resolves a component's system in module scope when the constructor runs
const P60P_SYSTEM = Ref{Any}(nothing)

"""A per-tick counter `n(k) = n(k − 1) + 1` on ShiftIndex `k`."""
function p60p_counter(k)
    t = Potts.t
    @variables n(t) = 0.0
    return System([n(k) ~ n(k - 1) + 1.0], t; name = :ctr)
end

"""The P6.0k three-node network (`p60k_network` of p6_0k_boolean_network.jl, unordered)."""
function p60p_network(k)
    t = Potts.t
    @variables A(t)::Bool = false B(t)::Bool = false C(t)::Bool = false
    @parameters wnt::Bool = false
    return System([A(k) ~ wnt | (B(k - 1) & !C(k - 1)), B(k) ~ A(k - 1), C(k) ~ !(A(k - 1) | B(k - 1))], t; name = :grn)
end

function p60p_cells(comp; mcs_duration = 1.0)
    P60P_SYSTEM[] = comp
    @potts_model P60pCells begin
        @kinds medium host
        @components cells(host) ctr = P60P_SYSTEM[]
        @lattice Lattice((12, 12))
        @energy cells => (volume - 9.0)^2
        @sweep Metropolis(; temperature = 1.0e-6, mcs_duration = mcs_duration)
    end
    return P60pCells(; name = :cells)
end

function p60p_census(comp)
    P60P_SYSTEM[] = comp
    @potts_model P60pCensus begin
        @kinds medium host
        @components model ctr = P60P_SYSTEM[]
        @lattice Lattice((12, 12))
        @energy cells => (volume - 9.0)^2
        @sweep Metropolis(; temperature = 1.0e-6)
    end
    return P60pCensus(; name = :census)
end

function p60p_grn(comp)
    P60P_SYSTEM[] = comp
    @potts_model P60pGrn begin
        @kinds medium host
        @variables input(cell) = 0.0
        @components cells(host) grn = P60P_SYSTEM[]
        @equations grn.wnt ~ input > 0.5
        @lattice Lattice((12, 12))
        @energy cells => (volume - 9.0)^2
        @sweep Metropolis(; temperature = 1.0e-6)
    end
    return P60pGrn(; name = :grn)
end

"""Two 3×3 host cells on a 12×12 lattice."""
function p60p_sigma()
    σ = zeros(Int32, 12, 12)
    σ[2:4, 2:4] .= 1
    σ[7:9, 7:9] .= 2
    return σ
end
const P60P_OP = [ownership => p60p_sigma(), kind => [:host, :host]]

p60p_problem(sys; tspan = (0, 12), kw...) = PottsProblem(sys, P60P_OP, tspan; kw...)
p60p_fp(sys; kw...) = p60p_problem(sys; kw...).f.fingerprint

const P60P_T = Potts.t
# label => (clock, mcs_duration, resolved (every, offset) per D-077: after MCS m when
# (m + 1 − offset) % every == 0)
const P60P_CLOCKS = [
    "ShiftIndex(t, 0)" => (ShiftIndex(P60P_T, 0), 1.0),
    "Clock(2.0)" => (ShiftIndex(Clock(2.0)), 1.0),
    "Clock(3.0)" => (ShiftIndex(Clock(3.0)), 1.0),
    "Clock(3.0; phase = 1.0)" => (ShiftIndex(Clock(3.0; phase = 1.0)), 1.0),
    "Clock(3.0; phase = 2.0)" => (ShiftIndex(Clock(3.0; phase = 2.0)), 1.0),
]
# MTK clock-time oracle (test/symbolic.jl): ticks at t = phase + k·dt (t = 0 is the initial state)
p60p_oracle(dt, phase, n) = [Float64(count(τ -> 0 < τ <= t, phase:dt:n)) for t in 0:n]
const P60P_ORACLE = Dict(
    "ShiftIndex(t, 0)" => p60p_oracle(1, 0, 12), "Clock(2.0)" => p60p_oracle(2, 0, 12),
    "Clock(3.0)" => p60p_oracle(3, 0, 12), "Clock(3.0; phase = 1.0)" => p60p_oracle(3, 1, 12),
    "Clock(3.0; phase = 2.0)" => p60p_oracle(3, 2, 12))

p60p_ticks(prob; scope = :cell) =
    [getproperty(getproperty(u, scope), :ctr₊n)[1] for u in solve(prob, SequentialCPM(); saveat = 0:12).u]

# ---------------------------------------------------------------------------------------
# Fixtures: rule cadences (no clocked component)

@potts_model P60pDivide begin
    @structural_parameters n = 1
    @kinds medium A
    @lattice Lattice((24, 24))
    @energy cells => (volume - 9.0)^2
    @divide cells(A) Every(n) when = volume >= 4, along = (1.0, 0.0)
    @sweep Metropolis(; temperature = 1.0e-6)
end

@potts_model P60pLink begin
    @structural_parameters n = 1
    @kinds medium A
    @relationship bond(cell, cell) capacity = 1
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @link bond Every(n) when = new_contact(a, b)
    @sweep Metropolis(; temperature = 1.0e-6)
end

@potts_model P60pUpdate begin
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
function p60p_divide_op()
    σ = zeros(Int32, 24, 24)
    σ[9:14, 9:14] .= 1
    return [ownership => σ, kind => [:A]]
end
p60p_divide(n; tspan = (0, 12)) = PottsProblem(P60pDivide(; name = :div, n), p60p_divide_op(), tspan; capacity = 64)

"""Two touching 3×3 cells: `new_contact` holds at the first link pass."""
function p60p_link_op()
    σ = zeros(Int32, 12, 12)
    σ[3:5, 3:5] .= 1
    σ[6:8, 3:5] .= 2
    return [ownership => σ, kind => [:A, :A]]
end
p60p_link(n; tspan = (0, 12)) = PottsProblem(P60pLink(; name = :link, n), p60p_link_op(), tspan)

p60p_alive(u) = count(>(0), Array(u.cell.volume))

"""The fingerprints `label => fp` differ pairwise (one @test per pair; a failure names the pair)."""
function p60p_pairwise_distinct(fps::AbstractVector{<:Pair})
    for i in eachindex(fps), j in (i + 1):lastindex(fps)
        (a, x), (b, y) = fps[i], fps[j]
        ok = x != y
        @test ok
        ok || @info "P6.0p: `$a` and `$b` fingerprint alike ($(repr(x)))"
    end
end

"""A checkpoint of `pa` after `k` MCS: refused by `pb` (ArgumentError), accepted by `pa2`
(a fresh build of `pa`'s model), in memory and through a file."""
function p60p_checkpoint_refused(pa, pb, pa2; k = 3, alg = SequentialCPM())
    integ = init(pa, alg)
    for _ in 1:k
        step!(integ)
    end
    ck = checkpoint(integ)
    path = joinpath(mktempdir(), "p60p.jls")
    save_checkpoint(path, ck)
    ck2 = load_checkpoint(path)
    for c in (ck, ck2)
        @test_throws ArgumentError init(pb, alg; checkpoint = c)
        i2 = init(pa2, alg; checkpoint = c)          # control: the same schedule loads
        @test i2.t == k
    end
end

# ---------------------------------------------------------------------------------------
# 1. Controls (pass on the base)

@testset "P6.0p: controls — the fixtures run on different schedules" begin
    for (label, (clk, md)) in P60P_CLOCKS
        @test p60p_ticks(p60p_problem(p60p_cells(p60p_counter(clk); mcs_duration = md))) == P60P_ORACLE[label]
    end
    @test length(unique(values(P60P_ORACLE))) == length(P60P_CLOCKS)
    # the period is model time: Clock(1) at half an MCS per MCS ticks every two MCS
    @test p60p_ticks(p60p_problem(p60p_cells(p60p_counter(ShiftIndex(Clock(1.0))); mcs_duration = 0.5))) == p60p_oracle(2, 0, 12)
    @test p60p_ticks(p60p_problem(p60p_cells(p60p_counter(ShiftIndex(Clock(1.0)))))) == p60p_oracle(1, 0, 12)
    # model scope
    @test p60p_ticks(p60p_problem(p60p_census(p60p_counter(ShiftIndex(Clock(2.0))))); scope = :model) == p60p_oracle(2, 0, 12)
    @test p60p_ticks(p60p_problem(p60p_census(p60p_counter(ShiftIndex(Clock(2.0; phase = 1.0))))); scope = :model) == p60p_oracle(2, 1, 12)
    # rule cadences: one division round at MCS 0 then every n MCS (2^rounds cells, D-076);
    # 3 MCS: Every(1) → 8 cells, Every(2) → 4, Every(3) → 2
    @test [p60p_alive(solve(p60p_divide(n; tspan = (0, 3)), SequentialCPM()).u[end]) for n in (1, 2, 3)] == [8, 4, 2]
    # updates: already fingerprinted (the gate is in the generated code)
    p60p_pairwise_distinct(["@after_mcs Every($n)" => p60p_fp(P60pUpdate(; name = :upd, n)) for n in (1, 2, 3)])
end

# ---------------------------------------------------------------------------------------
# 2–3. A different schedule, a different fingerprint

@testset "P6.0p: the clock of a discrete component is in the fingerprint" begin
    @testset "the P6.0k network: Clock(2.0) vs ShiftIndex(t, 0)" begin
        @test p60p_fp(p60p_grn(p60p_network(ShiftIndex(Clock(2.0))))) != p60p_fp(p60p_grn(p60p_network(ShiftIndex(P60P_T, 0))))
    end
    @testset "cell scope: periods and phases" begin
        p60p_pairwise_distinct([label => p60p_fp(p60p_cells(p60p_counter(clk); mcs_duration = md)) for (label, (clk, md)) in P60P_CLOCKS])
    end
    @testset "cell scope: mcs_duration changes the resolved period" begin
        @test p60p_fp(p60p_cells(p60p_counter(ShiftIndex(Clock(1.0))); mcs_duration = 0.5)) !=
              p60p_fp(p60p_cells(p60p_counter(ShiftIndex(Clock(1.0))); mcs_duration = 1.0))
    end
    @testset "model scope: periods and phases" begin
        p60p_pairwise_distinct([label => p60p_fp(p60p_census(p60p_counter(clk)))
                                for (label, clk) in ("ShiftIndex(t, 0)" => ShiftIndex(P60P_T, 0), "Clock(2.0)" => ShiftIndex(Clock(2.0)),
                                                     "Clock(2.0; phase = 1.0)" => ShiftIndex(Clock(2.0; phase = 1.0)),
                                                     "Clock(3.0)" => ShiftIndex(Clock(3.0)))])
    end
    @testset "deterministic: the same clock built twice fingerprints alike" begin
        for (label, (clk, md)) in P60P_CLOCKS
            @test p60p_fp(p60p_cells(p60p_counter(clk); mcs_duration = md)) == p60p_fp(p60p_cells(p60p_counter(clk); mcs_duration = md))
        end
    end
end

@testset "P6.0p: rule cadences are in the fingerprint" begin
    p60p_pairwise_distinct(["@divide Every($n)" => p60p_divide(n).f.fingerprint for n in (1, 2, 3)])
    p60p_pairwise_distinct(["@link Every($n)" => p60p_link(n).f.fingerprint for n in (1, 2, 7)])
    @test p60p_divide(2).f.fingerprint == p60p_divide(2).f.fingerprint
    @test p60p_link(7).f.fingerprint == p60p_link(7).f.fingerprint
end

# ---------------------------------------------------------------------------------------
# 4. Checkpoints do not cross schedules

@testset "P6.0p: a checkpoint does not load into another schedule" begin
    clk(c) = p60p_problem(p60p_cells(p60p_counter(c)))
    @testset "Clock(2.0) → ShiftIndex(t, 0)" begin
        p60p_checkpoint_refused(clk(ShiftIndex(Clock(2.0))), clk(ShiftIndex(P60P_T, 0)), clk(ShiftIndex(Clock(2.0))))
    end
    @testset "Clock(3.0) → Clock(3.0; phase = 1.0)" begin
        p60p_checkpoint_refused(clk(ShiftIndex(Clock(3.0))), clk(ShiftIndex(Clock(3.0; phase = 1.0))), clk(ShiftIndex(Clock(3.0))))
    end
    @testset "the P6.0k network: ShiftIndex(t, 0) → Clock(2.0)" begin
        grn(c) = p60p_problem(p60p_grn(p60p_network(c)))
        p60p_checkpoint_refused(grn(ShiftIndex(P60P_T, 0)), grn(ShiftIndex(Clock(2.0))), grn(ShiftIndex(P60P_T, 0)))
    end
    @testset "model scope: Clock(2.0) → Clock(2.0; phase = 1.0)" begin
        cen(c) = p60p_problem(p60p_census(p60p_counter(c)))
        p60p_checkpoint_refused(cen(ShiftIndex(Clock(2.0))), cen(ShiftIndex(Clock(2.0; phase = 1.0))), cen(ShiftIndex(Clock(2.0))))
    end
    @testset "@divide Every(2) → Every(3)" begin
        p60p_checkpoint_refused(p60p_divide(2), p60p_divide(3), p60p_divide(2))
    end
    @testset "@link Every(2) → Every(7)" begin
        p60p_checkpoint_refused(p60p_link(2), p60p_link(7), p60p_link(2))
    end
end

# ---------------------------------------------------------------------------------------
# 5. Fingerprints of models without clocked components or rule cadences are unchanged

p60p_unchanged() = (
    "GranerGlazier" => () -> (s = graner_glazier_state(); PottsProblem(GranerGlazier(; name = :gg), [ownership => s[1], kind => s[2]], (0, 10))),
    "WortelAct" => () -> PottsProblem(WortelAct(; name = :act, lattice = (8, 8)), p60p_two_wortel(), (0, 10)),
    "WortelAct connected" => () -> PottsProblem(WortelAct(; name = :act, lattice = (8, 8), connected = true), p60p_two_wortel(), (0, 10)),
    "MerksVasculogenesis" => () -> PottsProblem(MerksVasculogenesis(; name = :merks, lattice = (8, 8)),
        [ownership => (s = zeros(Int32, 8, 8); s[3:5, 3:5] .= 1; s), kind => [:endothelial]], (0, 10);
        field_solver = Potts.ExplicitEuler(substeps = 2, lower = 0.0)),
    "SingleDivisionFixture" => () -> PottsProblem(SingleDivisionFixture(; name = :fixture),
        [ownership => (s = zeros(Int32, 12, 8); s[5:8, 4:5] .= 1; s), kind => [:epithelial]], (0, 10)),
    "OpenVTGrowingMonolayer" => () -> PottsProblem(OpenVTGrowingMonolayer(; name = :openvt, lattice = (24, 24)),
        openvt_monolayer_state(; lattice = (24, 24)), (0, 10); capacity = 64),
    "AkeebInvasion" => () -> PottsProblem(AkeebInvasion(; name = :akeeb, lattice = (60, 40)), akeeb_state(; lattice = (60, 40)), (0, 10);
        capacity = 256),
    "@after_mcs/@before_mcs Every(1)" => () -> p60p_problem(P60pUpdate(; name = :upd, n = 1)),
    "@after_mcs/@before_mcs Every(2)" => () -> p60p_problem(P60pUpdate(; name = :upd, n = 2)),
    "@divide Every(1)" => () -> p60p_divide(1),
    "@link Every(1)" => () -> p60p_link(1),
)
function p60p_two_wortel()
    s = zeros(Int32, 8, 8)
    s[2:3, 2:3] .= 1
    s[6:7, 6:7] .= 2
    return [ownership => s, kind => [:cell, :cell]]
end

# recorded on 4e81e1eb (Julia 1.12, Float64)
const P60P_FINGERPRINTS = Dict{String, UInt64}(
    "GranerGlazier" => 0x04a4528dcdf3fcb8,   # re-pinned under D-122
    "WortelAct" => 0xce4f1cec820b20fe,   # re-pinned under D-124
    "WortelAct connected" => 0x993142c5fb9c8f2f,   # re-pinned under D-124
    "MerksVasculogenesis" => 0x984e2ad5906fc999,   # re-pinned under D-122
    "SingleDivisionFixture" => 0x13a4ddc2bb677287,
    "OpenVTGrowingMonolayer" => 0xfcecc4612f387b5e,   # re-pinned under D-122
    "AkeebInvasion" => 0x8d33bd0bb1eddd1c,
    "@after_mcs/@before_mcs Every(1)" => 0x97770dd85d99f955,
    "@after_mcs/@before_mcs Every(2)" => 0x16868ec68c10f99e,
    "@divide Every(1)" => 0x1c66296d224ca43b,
    "@link Every(1)" => 0x3693e521a3895940,
)

@testset "P6.0p: fingerprints of models without clocked components unchanged" begin
    for (name, build) in p60p_unchanged()
        fp = build().f.fingerprint
        @test fp == P60P_FINGERPRINTS[name]
        fp == P60P_FINGERPRINTS[name] || @info "P6.0p: fingerprint $name = $(repr(fp))"
    end
end

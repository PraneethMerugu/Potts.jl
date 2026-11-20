# the frozen-kind mask is recomputed on lifecycle events.
#
# The defect. `@kinds … wall[frozen]` puts the sites of cells of frozen kinds into the
# problem's `frozen` site mask once, at `PottsProblem` (`Potts._frozen_mask`), and the
# integrator builds its `MaskMobility` from it once, at `init`. A lifecycle transition that
# changes a cell's kind leaves the mask as it was: a cell that becomes frozen keeps moving,
# and a frozen cell that becomes a free kind stays pinned.
#
# Semantics pinned here (scope: "a kind that becomes frozen after a transition stops
# moving; the negative control moves"):
#  1. A cell whose kind changes INTO a frozen kind at the lifecycle of MCS S never changes
#     a site from the state saved at t = S + 1 on (the first state with the new kind; the
#     sweep of MCS S ran before the lifecycle, so it may still move then).
#  2. Reverse: a cell whose kind changes OUT OF a frozen kind at MCS S moves afterwards.
#  3. Negative controls, same run length and seed: the same transition into a non-frozen
#     kind keeps moving; a frozen cell with no transition never moves.
#  Both `SequentialCPM` and `CheckerboardCPM`.
#  Not pinned: the attempt count per MCS after the refresh (`nmobile`), and when the mask
#  is refreshed on MCS without a lifecycle event (only its effect at the next sweep is).
#
# The transition. The symbolic `@transition` is later work, so the kind change here is
# CorePotts' own lifecycle transition (`Lifecycle(trigger; kind)`, `EVENT_TRANSITION`, the
# public hand-written lifecycle API) installed on the Potts-generated model with
# `remake(prob; f = …)`. The model's `@divide` never fires; it is there so the state has
# the moment trackers every lifecycle needs. The trigger is `mcs == S`, independent of the
# state, so it holds with any margin (D-054).
#
# Fixture. Closed 30×30 lattice, Moore(1). Cell 1 (kind `cell`, 6×6 at rows 5:10, cols
# 5:10) and cell 2 (kind `wall`, frozen, 6×6 at rows 18:23, cols 18:23); V₀ = 36, λ = 1,
# J = 8 against the medium, T = 10. A free 6×6 cell at T = 10 changes its site set in
# almost every MCS (checked on seeds 1–10, both algorithms: ≥ 20 of the 21 steps before
# the switch, ≥ 37 of the 39 after it for a free cell; volumes stay ≥ 25), so "moves in at
# least half the steps" holds with a wide margin. Metal is not covered here (the
# PottsModels test environment has no GPU backend; the GPU group lives in test/gpu.jl).

@testsetup module FrozenKindMaskSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
const FROZEN_S = 20
# the transition fires at the lifecycle of MCS 20
const FROZEN_T1 = 60
# tspan (0, 60): MCS 0 … 59, states saved at t = 0 … 60
@potts_model Kinds begin
    @kinds medium cell wall[frozen] other
    @parameters begin
        λ = 1.0
        V₀ = 36.0
        T = 10.0
        J[kind, kind] = [0 8 8 8; 8 4 4 4; 8 4 4 4; 8 4 4 4]
    end
    @lattice Lattice((30, 30); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells => λ * (volume - V₀)^2
        contacts => J[kind, neighbor_kind]
    end
    @divide cells(cell) when = volume >= 10000    # never fires: a lifecycle needs the moments
    @sweep Metropolis(; temperature = T)
end
# kind indices (medium = 0): checked against the operating point below
const CELL = Int32(1)
const WALL = Int32(2)
const OTHER = Int32(3)
# At MCS `FROZEN_S`, every live cell whose kind is a key of `moves` takes the mapped kind.
struct Switch{N}
    moves::NTuple{N, Pair{Int32, Int32}}
end
function dest(sw::Switch, k)
    for m in sw.moves
        first(m) == k && return last(m)
    end
    return Int32(k)
end
struct Trigger{S}
    sw::S
end
function (t::Trigger)(st, p, ctx, key, mcs, c)
    return mcs == FROZEN_S && dest(t.sw, st.cell.kind[c]) != st.cell.kind[c] ? EVENT_TRANSITION : EVENT_NONE
end
struct Kind{S}
    sw::S
end
(k::Kind)(st, p, ctx, key, mcs, c) = dest(k.sw, st.cell.kind[c])
# the Potts problem, its lifecycle replaced by the transition `moves` at MCS FROZEN_S
function problem(moves::Pair{Int32, Int32}...; seed = 1)
    σ = zeros(Int32, 30, 30)
    σ[5:10, 5:10] .= 1
    σ[18:23, 18:23] .= 2
    prob = PottsProblem(Kinds(; name = :frozen_kind), [ownership => σ, kind => [:cell, :wall]], (0, FROZEN_T1); seed)
    f = prob.f
    sw = Switch(moves)
    lc = Lifecycle(Trigger(sw); kind = Kind(sw))
    g = CPMFunction(
        f.delta_H; f.commit!, f.constraint, f.temperature, f.bias, f.phases,
        lifecycle = lc, f.acceptance, f.footprint, f.fingerprint, f.sys
    )
    return remake(prob; f = g)
end
sites(u, c) = Array(u.ownership) .== c
# saved states i-1 → i in which cell c's site set changed
moved(sol, c, is) = count(i -> sites(sol.u[i], c) != sites(sol.u[i - 1], c), is)
const BEFORE = 2:(FROZEN_S + 2)
# u at t = 1 … S + 1: sweeps 0 … S (all before the new kind acts)
const AFTER = (FROZEN_S + 3):(FROZEN_T1 + 1)
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "frozen kind mask: a cell that becomes frozen stops moving, a frozen cell that is released moves" setup = [FrozenKindMaskSetup] tags = [:pottsmodels, :acceptance] begin
    # u at t = S + 2 … T1: sweeps S + 1 … T1 − 1 (39 steps)
    @testset "frozen kind mask: a cell that becomes frozen stops moving, a frozen cell that is released moves ($(nameof(typeof(alg))))" for alg in
        (SequentialCPM(), CheckerboardCPM())
        # cell 1: cell → wall (frozen); cell 2: wall → cell (released), in the same lifecycle pass
        prob = problem(CELL => WALL, WALL => CELL)
        @test Array(prob.u0.cell.kind)[1:2] == [CELL, WALL]          # fixture: kind indices
        sol = solve(prob, alg; saveat = 1)
        @test Symbol(sol.retcode) === :Success
        @test sol.t == 0:FROZEN_T1
        # the transition happened at the lifecycle of MCS S, and only there
        @test all(i -> Array(sol.u[i].cell.kind)[1:2] == [CELL, WALL], 1:(FROZEN_S + 1))   # t = 0 … S
        @test all(i -> Array(sol.u[i].cell.kind)[1:2] == [WALL, CELL], (FROZEN_S + 2):(FROZEN_T1 + 1))
        @test sol.stats.lifecycle.transitions == 2
        @test all(u -> Array(u.cell.volume)[1] > 0 && Array(u.cell.volume)[2] > 0, sol.u)

        # fixture: before the switch cell 1 moves, the frozen cell 2 does not
        @test moved(sol, 1, BEFORE) >= length(BEFORE) ÷ 2
        @test moved(sol, 2, BEFORE) == 0

        # 1. frozen after the transition: cell 1's sites never change from t = S + 1 on
        frozen_at = sites(sol.u[FROZEN_S + 2], 1)
        @test all(i -> sites(sol.u[i], 1) == frozen_at, AFTER)        # DEFECT CHECK (currently moves)
        @test moved(sol, 1, AFTER) == 0                               # DEFECT CHECK (currently ≈ every MCS)
        @test Array(sol.u[end].cell.volume)[1] == count(frozen_at)
        # 2. released: cell 2 moves after the transition
        @test moved(sol, 2, AFTER) >= length(AFTER) ÷ 2          # DEFECT CHECK (currently 0)
        @test sites(sol.u[end], 2) != sites(sol.u[FROZEN_S + 2], 2)
    end
end

@testitem "frozen kind mask: the same transition into a free kind keeps moving (negative control)" setup = [FrozenKindMaskSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "frozen kind mask: the same transition into a free kind keeps moving (negative control $(nameof(typeof(alg))))" for alg in
        (SequentialCPM(), CheckerboardCPM())
        # cell 1: cell → other (not frozen); cell 2 stays wall
        prob = problem(CELL => OTHER)
        sol = solve(prob, alg; saveat = 1)
        @test Symbol(sol.retcode) === :Success
        @test all(i -> Array(sol.u[i].cell.kind)[1:2] == [OTHER, WALL], (FROZEN_S + 2):(FROZEN_T1 + 1))
        @test sol.stats.lifecycle.transitions == 1
        @test moved(sol, 1, BEFORE) >= length(BEFORE) ÷ 2
        @test moved(sol, 1, AFTER) >= length(AFTER) ÷ 2          # the control moves
        @test moved(sol, 2, 2:(FROZEN_T1 + 1)) == 0                          # an untouched wall never moves
    end
end

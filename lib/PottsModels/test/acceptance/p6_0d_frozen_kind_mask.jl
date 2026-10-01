# P6.0d (ROADMAP Phase 6, step 0): the frozen-kind mask is recomputed on lifecycle events.
# Frozen (AUTONOMY §7.3).
#
# The defect. `@kinds … wall[frozen]` puts the sites of cells of frozen kinds into the
# problem's `frozen` site mask once, at `PottsProblem` (`Potts._frozen_mask`), and the
# integrator builds its `MaskMobility` from it once, at `init`. A lifecycle transition that
# changes a cell's kind leaves the mask as it was: a cell that becomes frozen keeps moving,
# and a frozen cell that becomes a free kind stays pinned.
#
# Semantics pinned here (ROADMAP: "a kind that becomes frozen after a transition stops
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
# The transition. The symbolic `@transition` arrives with P6.4c, so the kind change here is
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
using Potts: CorePotts

const P60D_S = 20                       # the transition fires at the lifecycle of MCS 20
const P60D_T1 = 60                      # tspan (0, 60): MCS 0 … 59, states saved at t = 0 … 60

@potts_model P60dKinds begin
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
        contacts => J[kind, kind′]
    end
    @divide cells(cell) when = volume >= 10000    # never fires: a lifecycle needs the moments
    @sweep Metropolis(; temperature = T)
end

# kind indices (medium = 0): checked against the operating point below
const P60D_CELL = Int32(1)
const P60D_WALL = Int32(2)
const P60D_OTHER = Int32(3)

# At MCS `P60D_S`, every live cell whose kind is a key of `moves` takes the mapped kind.
struct P60dSwitch{N}
    moves::NTuple{N, Pair{Int32, Int32}}
end
function p60d_dest(sw::P60dSwitch, k)
    for m in sw.moves
        first(m) == k && return last(m)
    end
    return Int32(k)
end
struct P60dTrigger{S}
    sw::S
end
(t::P60dTrigger)(st, p, ctx, key, mcs, c) =
    mcs == P60D_S && p60d_dest(t.sw, st.cell.kind[c]) != st.cell.kind[c] ? EVENT_TRANSITION : EVENT_NONE
struct P60dKind{S}
    sw::S
end
(k::P60dKind)(st, p, ctx, key, mcs, c) = p60d_dest(k.sw, st.cell.kind[c])

# the Potts problem, its lifecycle replaced by the transition `moves` at MCS P60D_S
function p60d_problem(moves::Pair{Int32, Int32}...; seed = 1)
    σ = zeros(Int32, 30, 30)
    σ[5:10, 5:10] .= 1
    σ[18:23, 18:23] .= 2
    prob = PottsProblem(P60dKinds(; name = :p60d), [ownership => σ, kind => [:cell, :wall]], (0, P60D_T1); seed)
    f = prob.f
    sw = P60dSwitch(moves)
    lc = Lifecycle(P60dTrigger(sw); kind = P60dKind(sw))
    g = CPMFunction(f.delta_H; f.commit!, f.constraint, f.claims, f.reads, f.temperature, f.bias, f.phases,
        lifecycle = lc, f.acceptance, f.footprint, f.fingerprint, f.sys)
    return remake(prob; f = g)
end

p60d_sites(u, c) = Array(u.σ) .== c
# saved states i-1 → i in which cell c's site set changed
p60d_moved(sol, c, is) = count(i -> p60d_sites(sol.u[i], c) != p60d_sites(sol.u[i - 1], c), is)

const P60D_BEFORE = 2:(P60D_S + 2)      # u at t = 1 … S + 1: sweeps 0 … S (all before the new kind acts)
const P60D_AFTER = (P60D_S + 3):(P60D_T1 + 1)   # u at t = S + 2 … T1: sweeps S + 1 … T1 − 1 (39 steps)

@testset "P6.0d: a cell that becomes frozen stops moving, a frozen cell that is released moves ($(nameof(typeof(alg))))" for alg in
                                                                                                                         (SequentialCPM(), CheckerboardCPM())
    # cell 1: cell → wall (frozen); cell 2: wall → cell (released), in the same lifecycle pass
    prob = p60d_problem(P60D_CELL => P60D_WALL, P60D_WALL => P60D_CELL)
    @test Array(prob.u0.cell.kind)[1:2] == [P60D_CELL, P60D_WALL]          # fixture: kind indices
    sol = solve(prob, alg; saveat = 1)
    @test Symbol(sol.retcode) === :Success
    @test sol.t == 0:P60D_T1
    # the transition happened at the lifecycle of MCS S, and only there
    @test all(i -> Array(sol.u[i].cell.kind)[1:2] == [P60D_CELL, P60D_WALL], 1:(P60D_S + 1))   # t = 0 … S
    @test all(i -> Array(sol.u[i].cell.kind)[1:2] == [P60D_WALL, P60D_CELL], (P60D_S + 2):(P60D_T1 + 1))
    @test sol.stats.lifecycle.transitions == 2
    @test all(u -> Array(u.cell.volume)[1] > 0 && Array(u.cell.volume)[2] > 0, sol.u)

    # fixture: before the switch cell 1 moves, the frozen cell 2 does not
    @test p60d_moved(sol, 1, P60D_BEFORE) >= length(P60D_BEFORE) ÷ 2
    @test p60d_moved(sol, 2, P60D_BEFORE) == 0

    # 1. frozen after the transition: cell 1's sites never change from t = S + 1 on
    frozen_at = p60d_sites(sol.u[P60D_S + 2], 1)
    @test all(i -> p60d_sites(sol.u[i], 1) == frozen_at, P60D_AFTER)        # DEFECT CHECK (currently moves)
    @test p60d_moved(sol, 1, P60D_AFTER) == 0                               # DEFECT CHECK (currently ≈ every MCS)
    @test Array(sol.u[end].cell.volume)[1] == count(frozen_at)
    # 2. released: cell 2 moves after the transition
    @test p60d_moved(sol, 2, P60D_AFTER) >= length(P60D_AFTER) ÷ 2          # DEFECT CHECK (currently 0)
    @test p60d_sites(sol.u[end], 2) != p60d_sites(sol.u[P60D_S + 2], 2)
end

@testset "P6.0d: the same transition into a free kind keeps moving (negative control, $(nameof(typeof(alg))))" for alg in
                                                                                                              (SequentialCPM(), CheckerboardCPM())
    # cell 1: cell → other (not frozen); cell 2 stays wall
    prob = p60d_problem(P60D_CELL => P60D_OTHER)
    sol = solve(prob, alg; saveat = 1)
    @test Symbol(sol.retcode) === :Success
    @test all(i -> Array(sol.u[i].cell.kind)[1:2] == [P60D_OTHER, P60D_WALL], (P60D_S + 2):(P60D_T1 + 1))
    @test sol.stats.lifecycle.transitions == 1
    @test p60d_moved(sol, 1, P60D_BEFORE) >= length(P60D_BEFORE) ÷ 2
    @test p60d_moved(sol, 1, P60D_AFTER) >= length(P60D_AFTER) ÷ 2          # the control moves
    @test p60d_moved(sol, 2, 2:(P60D_T1 + 1)) == 0                          # an untouched wall never moves
end

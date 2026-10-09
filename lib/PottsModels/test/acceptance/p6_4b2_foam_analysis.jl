# P6.4b2 (ROADMAP Phase 6; D-186 foam stream 2): the foam analysis functions of
# reproduction 04 (Jiang, Swart, Saxena, Asipauskas & Glazier, Phys. Rev. E 59, 5819 (1999),
# "04b"; spec docs/design/research/model-specs/04_foam.md §2.8, §5.2, §6 G12, §8). Frozen
# (AUTONOMY §7.3). Decisions: D-186 (the stream), D-048 (ordinary tests: independent oracles
# and negative controls, no parity harness). Every input is a hand-built ownership array, a
# hand-written neighbour list or a synthetic series; nothing is simulated.
#
# Surface pinned (all in `PottsModels.Analysis`, public; plain Julia on saved states, like
# `cell_graph`). `lat` is a CorePotts `Lattice`; bubble ids are σ's values 1:maximum(σ).
#
#   stored_energy(σ, lat; neighborhood = NeighborOrder(4), θ = 1) -> Real
#       φ, Eq. (8) (04b p.5823): θ times the number of UNORDERED neighbour pairs {i, j}
#       (each pair once) with σ_i ≠ σ_j, over the interaction shell (4th-nearest, 04b
#       p.5822, spec §8 "pair count over the interaction shell"). Pairs wrap on Periodic()
#       axes; a pair leaving a Closed() axis does not exist.
#   side_counts(σ, lat; neighborhood = VonNeumann(1)) -> Vector{Int}
#       n per bubble (04b p.5823: a bubble's sides are its distinct neighbours), equal to
#       length.(cell_graph(σ, lat; neighborhood)). VonNeumann(1) is the default (spec §2.8,
#       topology audit 2026-10-01); a Closed() wall is not a side.
#   contact_changes(prev, next) -> (; lost, gained)
#       prev, next: neighbour lists (cell_graph's form, g[c] = sorted neighbours of c).
#       lost / gained: the unordered pairs (a, b), a < b, adjacent in prev but not in next /
#       in next but not in prev, as sorted Vector{Tuple{Int, Int}}.
#   t1_events(prev, next; unit = :t1) -> Real
#       Per-MCS T1 detection (04b p.5823: "A change in the neighbor list indicates a
#       topological change which ... has to be a T1 event"), counted in a configurable unit
#       (A-15). With L = length(lost), G = length(gained):
#         :t1      (L + G) / 2         one full T1 (one pair parts, one pair meets) = 1;
#                                      a half-completed T1 (4-fold vertex) = 1/2
#         :pairs   L + G               one T1 = 2 (the even-valued bars of Figs. 4b, 5b)
#         :bubbles bubbles whose neighbour list changed; one T1 = 4
#       Any other unit is an ArgumentError.
#   topology_distribution(n) -> (; n, ρ)
#       ρ(n), the fraction of bubbles with n sides (04b p.5823): `n` the sorted distinct
#       values (Vector{Int}), `ρ` their fractions. Empty input is an ArgumentError.
#   central_moment(x, m = 2)
#       μ_m ≡ Σ_v ρ(v)(v − ⟨v⟩)^m (04b p.5823) = (1/N) Σ (x − x̄)^m, the population moment.
#   topology_moments(σ, lat; neighborhood = VonNeumann(1)) -> (; mean_n, mu2_n, mean_a, mu2_a)
#       ⟨n⟩, μ2(n), ⟨a⟩, μ2(a) over the bubbles that own at least one site (an id with no
#       site is not a bubble); a in sites, n from side_counts.
#   power_spectrum(x; dt = 1) -> (; f, S)
#       Eq. (9) (04b p.5827), p_N(f) = ∫dt∫dτ e^{−ifτ} N(t)N(t+τ): by Wiener–Khinchin the
#       periodogram S_k = |Σ_{t=0}^{L−1} x_t e^{−2πi k t / L}|² / L at f_k = k / (L·dt),
#       k = 1:L÷2 (cycles per MCS for dt = 1 MCS; Nyquist 0.5, spec §2.8). The f = 0 bin is
#       left out (so a constant offset does not change S); no window (the paper's low-f
#       ringing, Fig. 8, is a raw-periodogram artefact).
#   spectral_exponent(f, S; range) -> α
#       S ∝ f^−α: α = −(ordinary least-squares slope of log10 S on log10 f) over the bins
#       with range[1] ≤ f ≤ range[2] (V10–V13 fit over 10⁻⁴–10⁻²). Fewer than 2 bins in
#       range is an ArgumentError.
#   mean_t1(N; bubbles, strain)
#       N̄ (04b p.5829, Fig. 9), "the average number of T1 events per bubble per unit
#       shear": sum(N) / (bubbles · strain). The strain is the caller's (A-9); N is in the
#       caller's counting unit (A-15). bubbles ≤ 0 or strain ≤ 0 is an ArgumentError.
#   yield_strain(strain, N; threshold = 1, window = 1) -> Real or nothing
#       04b p.5830: the strain "at which the first T1 avalanches occur". The avalanche
#       starts at the first sample i with N[i] > 0 and sum(N[i:min(i + window − 1, end)])
#       ≥ threshold; the result is strain[i]. No avalanche: `nothing`. Different lengths:
#       DimensionMismatch; threshold ≤ 0 or window < 1: ArgumentError. The displacement →
#       strain conversion (A-9; spec §3.2 calibration ε ≈ c·β·t) is the caller's.
#
# Readings chosen where the spec is ambiguous (flagged for the spec owner):
#  (a) Eq. 8's Σ_{i,j} counts each unordered pair once. Only φ/φ(0) is plotted, so the
#      factor 2 of the ordered reading cancels.
#  (b) A Closed() y wall is not a side. Evidence: the 256² brick wall (16² bricks, common
#      bond, periodic x, closed y) then has 32 four-sided boundary bubbles and 224 hexagons,
#      μ2(n) = 7/16 = 0.4375, the paper's ordered baseline 0.437 (Fig. 11(c); spec V1b).
#      Counting the wall as a side would give 0.109.
#  (c) μ2(a)'s unit is not stated. The paper's values (7.25, 21.33 for ≈ 256-site bubbles)
#      cannot be variances in sites²; areas here are in sites and any rescaling is a
#      P6.4r calibration.
#  (d) A-15: three units are offered; `:pairs` matches the even-valued bars, `:t1`'s halves
#      match the half-integers of the Fig. 5 inset. The choice stays a P6.4r calibration.
#  (e) The yield strain follows the paper's definition (first T1 avalanche), not the yield
#      point of a stress–strain curve; φ ("Stress", Fig. 11(c)) is not an input.
#
# Today this fails with `UndefVarError` for every name above (none exists in
# PottsModels.Analysis). The `cell_graph` wrap checks pass on the base (controls).
using StableRNGs: StableRNG

const P64B2 = PottsModels.Analysis

# A picture: rows top (y = Y) to bottom (y = 1), σ[x, y].
p64b2_pic(rows) = (Y = length(rows); [rows[Y - y + 1][x] for x in eachindex(rows[1]), y in 1:Y])

# An L×L tiling of w×w bricks; odd brick rows (0-based, from y = 1) shifted by `offset` in x
# with wrap ("a brick wall arranged in common bond", 04b p.5823, for offset = w ÷ 2; a plain
# square grid for offset = 0). Brick row r, column c has id r·(L ÷ w) + c + 1.
p64b2_bricks(L, w; offset = w ÷ 2) =
    [(r = (y - 1) ÷ w; r * (L ÷ w) + mod(x - 1 - (isodd(r) ? offset : 0), L) ÷ w + 1) for x in 1:L, y in 1:L]

# Independent φ oracle: explicit offset lists, each unordered pair once (offsets o > 0
# lexicographically), wrap on periodic axes, pairs leaving a closed axis skipped.
const P64B2_VN = ((1, 0), (0, 1), (-1, 0), (0, -1))
const P64B2_N4 = ((1, 0), (0, 1), (-1, 0), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1), (2, 0), (0, 2), (-2, 0),
    (0, -2), (1, 2), (2, 1), (-1, 2), (2, -1), (1, -2), (-2, 1), (-1, -2), (-2, -1))
function p64b2_phi(σ, offsets, periodic)
    X, Y = size(σ)
    φ = 0
    for x in 1:X, y in 1:Y, o in offsets
        (o[1] > 0 || (o[1] == 0 && o[2] > 0)) || continue
        u, v = x + o[1], y + o[2]
        periodic[1] ? (u = mod1(u, X)) : (1 <= u <= X || continue)
        periodic[2] ? (v = mod1(v, Y)) : (1 <= v <= Y || continue)
        φ += σ[x, y] != σ[u, v]
    end
    return φ
end

const P64B2_FOAM = Lattice((256, 256); boundary = (Periodic(), Closed()))        # 04b p.5822
const P64B2_NOWRAP = Lattice((256, 256); boundary = (Closed(), Closed()))        # wrong rule

@testset "P6.4b2: surface" begin
    for name in (:stored_energy, :side_counts, :contact_changes, :t1_events, :topology_distribution, :central_moment,
        :topology_moments, :power_spectrum, :spectral_exponent, :mean_t1, :yield_strain)
        @test isdefined(P64B2, name) && Base.ispublic(P64B2, name)
    end
end

# ---------------------------------------------------------------------------------------
# Neighbour lists and n on hexagonal (brick-wall) foams
# ---------------------------------------------------------------------------------------

@testset "P6.4b2: hexagonal foam, every bubble n = 6, μ2(n) = 0" begin
    # 64², 16² bricks in common bond, periodic on both axes: 4 rows of 4. Every brick meets
    # its two row neighbours and two bricks above and two below (offset 8 = half a brick,
    # so no corner-only contacts), all distinct: n = 6.
    lat = Lattice((64, 64); boundary = (Periodic(), Periodic()))
    σ = p64b2_bricks(64, 16)
    g = P64B2.cell_graph(σ, lat)
    @test g[1] == [2, 4, 5, 8, 13, 16]       # row 0 col 0: 4, 2 (row); 5, 8 (row 1 above, wrapped); 13, 16 (row 3 below)
    n = P64B2.side_counts(σ, lat)
    @test n == fill(6, 16) && n == length.(g)
    @test P64B2.topology_distribution(n) == (n = [6], ρ = [1.0])
    @test P64B2.central_moment(n) == 0
    m = P64B2.topology_moments(σ, lat)
    @test m.mean_n == 6 && m.mu2_n == 0 && m.mean_a == 256 && m.mu2_a == 0
    # Moore(1) sees the same six: the half-brick offset leaves no corner-only contacts
    @test P64B2.side_counts(σ, lat; neighborhood = Moore(1)) == fill(6, 16)
    # control: a plain square grid (no offset) has n = 4 under VonNeumann(1) but n = 8 under
    # Moore(1) (corner contacts), the inflation spec §2.8 warns about
    sq = p64b2_bricks(64, 16; offset = 0)
    @test P64B2.side_counts(sq, lat) == fill(4, 16)
    @test P64B2.side_counts(sq, lat; neighborhood = Moore(1)) == fill(8, 16)
    @test P64B2.topology_moments(sq, lat).mean_n == 4
end

@testset "P6.4b2: the paper's 256² ordered foam (periodic x, closed y)" begin
    σ = p64b2_bricks(256, 16)                 # 16 rows × 16 bricks, ids 1:256
    n = P64B2.side_counts(σ, P64B2_FOAM)
    rows = [(id - 1) ÷ 16 for id in 1:256]
    @test all(n[id] == 6 for id in 1:256 if 0 < rows[id] < 15)      # interior: hexagons
    @test all(n[id] == 4 for id in 1:256 if rows[id] in (0, 15))     # boundary rows: 4 (the wall is not a side)
    g = P64B2.cell_graph(σ, P64B2_FOAM)
    # across the x seam: brick 16 (row 0, x 241:256) touches brick 1 (x 1:16) through the
    # wrap, and bricks 31 (x 233:248) and 32 (x 249:256 ∪ 1:8, itself wrapped) above
    @test g[16] == [1, 15, 31, 32]
    @test g[32] == [1, 16, 17, 31, 33, 48]
    @test g[1] == [2, 16, 17, 32]
    # ρ(n) and μ2(n): 32 four-sided, 224 six-sided; ⟨n⟩ = 5.75,
    # μ2(n) = (32·1.75² + 224·0.25²)/256 = (98 + 14)/256 = 7/16 (paper Fig. 11(c): ≈ 0.437)
    @test P64B2.topology_distribution(n) == (n = [4, 6], ρ = [0.125, 0.875])
    m = P64B2.topology_moments(σ, P64B2_FOAM)
    @test m.mean_n == 5.75
    @test m.mu2_n ≈ 7 / 16 atol = 1e-12
    @test m.mean_a == 256 && m.mu2_a == 0
    # negative control: a neighbour rule that ignores the wrap (closed x) loses the seam
    # contacts, and the answer changes
    gw = P64B2.cell_graph(σ, P64B2_NOWRAP)
    @test gw[16] == [15, 31, 32] && gw[1] == [2, 17, 32]
    nw = P64B2.side_counts(σ, P64B2_NOWRAP)
    @test nw[16] == 3 && nw[1] == 3 && nw != n
    @test !isapprox(P64B2.topology_moments(σ, P64B2_NOWRAP).mu2_n, 7 / 16; atol = 1e-3)
end

@testset "P6.4b2: ρ(n) and μ_m on known configurations" begin
    # n = 4, 5, 5, 6, 6, 6, 7, 7: ρ = 1/8, 2/8, 3/8, 2/8; ⟨n⟩ = 46/8 = 5.75;
    # μ2 = (1.75² + 2·0.75² + 3·0.25² + 2·1.25²)/8 = 7.5/8 = 0.9375;
    # μ3 = (−1.75³ − 2·0.75³ + 3·0.25³ + 2·1.25³)/8 = −2.25/8 = −0.28125
    n = [6, 4, 7, 5, 6, 7, 5, 6]
    d = P64B2.topology_distribution(n)
    @test d.n == [4, 5, 6, 7] && d.ρ ≈ [1, 2, 3, 2] ./ 8
    @test sum(d.ρ) ≈ 1
    @test P64B2.central_moment(n) ≈ 0.9375 && P64B2.central_moment(n, 2) ≈ 0.9375
    @test P64B2.central_moment(n, 3) ≈ -0.28125
    # the same moment written as Σ ρ(n)(n − ⟨n⟩)² from the distribution
    nbar = sum(d.n .* d.ρ)
    @test P64B2.central_moment(n) ≈ sum(d.ρ .* (d.n .- nbar) .^ 2)
    @test_throws ArgumentError P64B2.topology_distribution(Int[])

    # Three stripes on 6×4: bubble 1 is column 1 (4 sites), 2 is columns 2:3 (8), 4 is
    # columns 4:6 (12); id 3 owns no site and is not a bubble. a = 4, 8, 12: ⟨a⟩ = 8,
    # μ2(a) = (16 + 0 + 16)/3 = 32/3.
    σ = p64b2_pic([[1, 2, 2, 4, 4, 4] for _ in 1:4])
    closed = Lattice((6, 4); boundary = (Closed(), Closed()))
    wrap = Lattice((6, 4); boundary = (Periodic(), Closed()))
    # closed: n = 1, 2, 1 → ⟨n⟩ = 4/3, μ2(n) = (2·(1/3)² + (2/3)²)/3 = 2/9
    @test P64B2.side_counts(σ, closed)[[1, 2, 4]] == [1, 2, 1]
    mc = P64B2.topology_moments(σ, closed)
    @test mc.mean_n ≈ 4 / 3 && mc.mu2_n ≈ 2 / 9 && mc.mean_a == 8 && mc.mu2_a ≈ 32 / 3
    # periodic x: 1 and 4 also meet across the seam → n = 2, 2, 2, μ2(n) = 0
    mp = P64B2.topology_moments(σ, wrap)
    @test P64B2.side_counts(σ, wrap)[[1, 2, 4]] == [2, 2, 2]
    @test mp.mean_n == 2 && mp.mu2_n == 0 && mp.mean_a == 8 && mp.mu2_a ≈ 32 / 3
    @test P64B2.side_counts(σ, wrap) == length.(P64B2.cell_graph(σ, wrap))
end

# ---------------------------------------------------------------------------------------
# φ, Eq. (8)
# ---------------------------------------------------------------------------------------

@testset "P6.4b2: stored energy φ (Eq. 8)" begin
    # Two halves of a 16×16 lattice (x ≤ 8 → 1). A straight vertical wall crossed by the
    # VonNeumann(1) shell: 16 pairs. By NeighborOrder(4) (offsets with dx > 0: (1,0), (1,±1),
    # (2,0), (1,±2), (2,±1)): Σ dx·(16 − |dy|) = 16 + 2·15 + 2·16 + 2·14 + 4·15 = 166 with y
    # closed (11L − 10), 11·16 = 176 with y periodic.
    σ = [x <= 8 ? 1 : 2 for x in 1:16, y in 1:16]
    foam = Lattice((16, 16); boundary = (Periodic(), Closed()))     # two walls: x 8|9 and the seam 16|1
    nowrap = Lattice((16, 16); boundary = (Closed(), Closed()))     # one wall
    torus = Lattice((16, 16); boundary = (Periodic(), Periodic()))
    @test P64B2.stored_energy(σ, foam; neighborhood = VonNeumann(1)) == 32
    @test P64B2.stored_energy(σ, nowrap; neighborhood = VonNeumann(1)) == 16
    @test P64B2.stored_energy(σ, foam) == 332                       # default: NeighborOrder(4)
    @test P64B2.stored_energy(σ, nowrap) == 166
    @test P64B2.stored_energy(σ, torus) == 352
    @test P64B2.stored_energy(σ, foam; θ = 2) == 664
    @test P64B2.stored_energy(fill(7, 16, 16), foam) == 0
    # independent oracle on a random 12×10 foam (ids 1:5): the brute-force pair count, each
    # unordered pair once
    rng = StableRNG(0x64b2)
    r = rand(rng, 1:5, 12, 10)
    lat = Lattice((12, 10); boundary = (Periodic(), Closed()))
    @test P64B2.stored_energy(r, lat) == p64b2_phi(r, P64B2_N4, (true, false))
    @test P64B2.stored_energy(r, lat; neighborhood = VonNeumann(1)) == p64b2_phi(r, P64B2_VN, (true, false))
    # negative controls: the oracle without the wrap, and the ordered-pair (double) count,
    # are different numbers and would be caught
    @test p64b2_phi(r, P64B2_N4, (false, false)) != P64B2.stored_energy(r, lat)
    @test 2 * p64b2_phi(r, P64B2_N4, (true, false)) != P64B2.stored_energy(r, lat)
    # the ordered 256² foam: interior hexagonal walls, wrap included
    b = p64b2_bricks(256, 16)
    @test P64B2.stored_energy(b, P64B2_FOAM) == p64b2_phi(b, P64B2_N4, (true, false))
    @test P64B2.stored_energy(b, P64B2_FOAM; neighborhood = VonNeumann(1)) == p64b2_phi(b, P64B2_VN, (true, false))
end

# ---------------------------------------------------------------------------------------
# T1 detection (A-15 counting unit)
# ---------------------------------------------------------------------------------------

# A scripted T1 on 6×6, VonNeumann(1). Before: 1 (left) and 2 (right) share a wall between
# 3 (top) and 4 (bottom). After: 3 and 4 meet in the middle, 1 and 2 have parted.
const P64B2_BEFORE = p64b2_pic([
    [3, 3, 3, 3, 3, 3],
    [3, 3, 3, 3, 3, 3],
    [1, 1, 1, 2, 2, 2],
    [1, 1, 1, 2, 2, 2],
    [4, 4, 4, 4, 4, 4],
    [4, 4, 4, 4, 4, 4]])
const P64B2_AFTER = p64b2_pic([
    [3, 3, 3, 3, 3, 3],
    [1, 1, 3, 3, 2, 2],
    [1, 1, 3, 3, 2, 2],
    [1, 1, 4, 4, 2, 2],
    [4, 4, 4, 4, 4, 4],
    [4, 4, 4, 4, 4, 4]])

@testset "P6.4b2: one scripted T1 is one T1 in every unit" begin
    lat = Lattice((6, 6); boundary = (Closed(), Closed()))
    g0 = P64B2.cell_graph(P64B2_BEFORE, lat)
    g1 = P64B2.cell_graph(P64B2_AFTER, lat)
    @test g0 == [[2, 3, 4], [1, 3, 4], [1, 2], [1, 2]]               # the oracle, by hand
    @test g1 == [[3, 4], [3, 4], [1, 2, 4], [1, 2, 3]]
    @test P64B2.contact_changes(g0, g1) == (lost = [(1, 2)], gained = [(3, 4)])
    @test P64B2.t1_events(g0, g1) == 1                               # default unit :t1
    @test P64B2.t1_events(g0, g1; unit = :t1) == 1
    @test P64B2.t1_events(g0, g1; unit = :pairs) == 2
    @test P64B2.t1_events(g0, g1; unit = :bubbles) == 4
    # the reverse swap is also one T1
    @test P64B2.contact_changes(g1, g0) == (lost = [(3, 4)], gained = [(1, 2)])
    @test P64B2.t1_events(g1, g0) == 1
    # no change, zero in every unit
    for u in (:t1, :pairs, :bubbles)
        @test P64B2.t1_events(g0, g0; unit = u) == 0
        @test P64B2.t1_events(g1, deepcopy(g1); unit = u) == 0
    end
    @test P64B2.contact_changes(g0, g0) == (lost = Tuple{Int, Int}[], gained = Tuple{Int, Int}[])
    @test_throws ArgumentError P64B2.t1_events(g0, g1; unit = :events)

    # Two independent T1s side by side (the second with ids 5:8) on 12×6: 2, 4, 8. The
    # contacts across the join (3–7, 2–5, 4–8) are the same before and after.
    two(a) = vcat(a, a .+ 4)                                         # σ[x, y]: x is the first axis
    lat2 = Lattice((12, 6); boundary = (Closed(), Closed()))
    h0 = P64B2.cell_graph(two(P64B2_BEFORE), lat2)
    h1 = P64B2.cell_graph(two(P64B2_AFTER), lat2)
    @test P64B2.contact_changes(h0, h1) == (lost = [(1, 2), (5, 6)], gained = [(3, 4), (7, 8)])
    @test P64B2.t1_events(h0, h1; unit = :t1) == 2
    @test P64B2.t1_events(h0, h1; unit = :pairs) == 4
    @test P64B2.t1_events(h0, h1; unit = :bubbles) == 8

    # A T1 through a transient 4-fold vertex, as two per-MCS steps (hand-written lists): the
    # 1–2 contact goes first, the 3–4 contact comes one MCS later. Each step is half a T1
    # in :t1 (the half-integers of the Fig. 5 inset), one pair change, two bubbles.
    mid = [[3, 4], [3, 4], [1, 2], [1, 2]]
    @test P64B2.contact_changes(g0, mid) == (lost = [(1, 2)], gained = Tuple{Int, Int}[])
    @test P64B2.t1_events(g0, mid) == 0.5 && P64B2.t1_events(mid, g1) == 0.5
    @test P64B2.t1_events(g0, mid; unit = :pairs) == 1 && P64B2.t1_events(mid, g1; unit = :bubbles) == 2
    @test P64B2.t1_events(g0, mid) + P64B2.t1_events(mid, g1) == P64B2.t1_events(g0, g1)
end

@testset "P6.4b2: T1 detection across the periodic x seam" begin
    # The scripted T1 inside an 8-wide strip with a fifth bubble in columns 7:8, then
    # shifted by 4 in x so the T1 straddles the seam. On the periodic-x lattice, shifting is
    # a symmetry: the same one T1.
    pad(a) = vcat(a, fill(5, 2, 6))
    s0 = circshift(pad(P64B2_BEFORE), (4, 0))
    s1 = circshift(pad(P64B2_AFTER), (4, 0))
    foam = Lattice((8, 6); boundary = (Periodic(), Closed()))
    g0, g1 = P64B2.cell_graph(s0, foam), P64B2.cell_graph(s1, foam)
    @test g0[5] == g1[5] == [1, 2, 3, 4]
    @test P64B2.contact_changes(g0, g1) == (lost = [(1, 2)], gained = [(3, 4)])
    @test P64B2.t1_events(g0, g1) == 1 && P64B2.t1_events(g0, g1; unit = :bubbles) == 4
    # The 6-wide pictures themselves on a periodic-x lattice: 1 and 2 still meet across the
    # seam after the swap, so only the 3–4 contact is new (half a T1). Ignoring the wrap
    # (closed x) reports a full T1: the wrong rule changes the answer.
    w = Lattice((6, 6); boundary = (Periodic(), Closed()))
    gw0, gw1 = P64B2.cell_graph(P64B2_BEFORE, w), P64B2.cell_graph(P64B2_AFTER, w)
    @test P64B2.contact_changes(gw0, gw1) == (lost = Tuple{Int, Int}[], gained = [(3, 4)])
    @test P64B2.t1_events(gw0, gw1) == 0.5
    c = Lattice((6, 6); boundary = (Closed(), Closed()))
    @test P64B2.t1_events(P64B2.cell_graph(P64B2_BEFORE, c), P64B2.cell_graph(P64B2_AFTER, c)) == 1
end

# ---------------------------------------------------------------------------------------
# Spectra, Eq. (9)
# ---------------------------------------------------------------------------------------

# x_t = Σ_k a_k cos(2π k t / L + ϕ_k), t = 0:L−1, k = 1:L÷2−1: its periodogram is exactly
# S_k = L a_k² / 4 (and 0 at the Nyquist bin).
function p64b2_synth(L, a, ϕ)
    x = zeros(L)
    for k in eachindex(a), t in 0:(L - 1)
        x[t + 1] += a[k] * cos(2π * k * t / L + ϕ[k])
    end
    return x
end

@testset "P6.4b2: power spectrum (Eq. 9) of signals with known spectra" begin
    L = 4096
    t = 0:(L - 1)
    # a pure tone at bin 64 with amplitude 3: S_64 = 9L/4, every other bin ≈ 0
    x = 3 .* cos.(2π * 64 .* t ./ L)
    P = P64B2.power_spectrum(x)
    @test P.f ≈ (1:(L ÷ 2)) ./ L                                    # cycles per sample, up to Nyquist 0.5
    @test length(P.S) == L ÷ 2 && P.f[end] == 0.5
    @test argmax(P.S) == 64
    @test P.S[64] ≈ 9L / 4 rtol = 1e-9
    @test maximum(P.S[k] for k in eachindex(P.S) if k != 64) < 1e-9 * P.S[64]
    # the f = 0 bin is left out: a constant offset changes nothing
    @test P64B2.power_spectrum(x .+ 5).S ≈ P.S atol = 1e-6
    # the Nyquist tone (−1)^t: S = L at f = 0.5
    Q = P64B2.power_spectrum([(-1.0)^s for s in t])
    @test Q.S[end] ≈ L && maximum(Q.S[1:(end - 1)]) < 1e-9 * L
    # dt: one sample per 2 MCS halves f (cycles per MCS); odd lengths stop below Nyquist
    @test P64B2.power_spectrum(x; dt = 2).f ≈ (1:(L ÷ 2)) ./ (2L)
    @test length(P64B2.power_spectrum(randn(StableRNG(1), 4095)).f) == 2047

    # exact power laws S ∝ f^−α, random phases: α recovered exactly by the fit, and the
    # levels equal L a²/4 (pins the normalisation)
    ϕ = 2π .* rand(StableRNG(2), L ÷ 2 - 1)
    k = 1:(L ÷ 2 - 1)
    for α in (0.0, 0.8, 0.95, 2.0)
        a = (k ./ L) .^ (-α / 2)
        S = P64B2.power_spectrum(p64b2_synth(L, a, ϕ))
        @test S.S[k] ≈ L .* a .^ 2 ./ 4 rtol = 1e-6
        @test P64B2.spectral_exponent(S.f, S.S; range = (1e-3, 1e-1)) ≈ α atol = 1e-6
    end
    # white noise is flat; its running sum (a random walk) is f^−2 (the V13 exclusion)
    w = randn(StableRNG(3), 2^14)
    Sw = P64B2.power_spectrum(w)
    @test abs(P64B2.spectral_exponent(Sw.f, Sw.S; range = (1e-3, 0.5))) < 0.1
    Sr = P64B2.power_spectrum(cumsum(w))
    @test 1.8 < P64B2.spectral_exponent(Sr.f, Sr.S; range = (1e-3, 1e-1)) < 2.2
    # the fit uses only the bins in range: a tone outside it does not move α
    Sp = P64B2.power_spectrum(p64b2_synth(L, (k ./ L) .^ (-0.5), ϕ) .+ 100 .* cos.(2π * 1500 .* t ./ L))
    @test P64B2.spectral_exponent(Sp.f, Sp.S; range = (1e-3, 1e-1)) ≈ 1 atol = 1e-6
    @test_throws ArgumentError P64B2.spectral_exponent(P.f, P.S; range = (0.3, 0.30001))
end

# ---------------------------------------------------------------------------------------
# N̄ and the yield strain
# ---------------------------------------------------------------------------------------

@testset "P6.4b2: N̄, T1s per bubble per unit shear" begin
    @test P64B2.mean_t1([0, 2, 0, 4]; bubbles = 4, strain = 0.5) == 3.0      # 6 / (4 · 0.5)
    @test P64B2.mean_t1(zeros(Int, 10); bubbles = 256, strain = 2) == 0
    @test P64B2.mean_t1([0.5, 1.5]; bubbles = 2, strain = 1) == 1.0          # :t1 halves
    @test_throws ArgumentError P64B2.mean_t1([1]; bubbles = 0, strain = 1)
    @test_throws ArgumentError P64B2.mean_t1([1]; bubbles = 4, strain = 0)
end

@testset "P6.4b2: yield strain, the first T1 avalanche" begin
    strain = 0.01 .* (0:99)
    N = zeros(Int, 100)
    N[41] = 1                                                        # an isolated T1 at strain 0.40
    N[61:63] = [2, 1, 2]                                             # a burst from strain 0.60
    @test P64B2.yield_strain(strain, N) ≈ 0.40
    @test P64B2.yield_strain(strain, N; threshold = 2) ≈ 0.60
    # window: the burst's 5 T1s over 5 samples pass threshold 4; the lone T1 does not, and
    # the avalanche starts at its first T1, not before it
    @test P64B2.yield_strain(strain, N; threshold = 4, window = 5) ≈ 0.60
    @test P64B2.yield_strain(strain, N; threshold = 6, window = 5) === nothing
    @test P64B2.yield_strain(strain, zeros(Int, 100)) === nothing            # never yields
    # disordered foam under boundary shear (Fig. 6): T1s in the first bin → zero yield strain
    M = zeros(Int, 50); M[1] = 88
    @test P64B2.yield_strain(0.1 .* (0:49), M) == 0
    # the ordered bulk-shear calibration of spec §3.2: ε = c·β·t, c = 0.0258, β = 0.01,
    # first T1 at 4300 MCS → ε_y ≈ 1.11 (Fig. 11(a))
    t = 0:9999
    T1 = zeros(Int, 10_000); T1[4301] = 2; T1[4302:4400] .= 2
    @test P64B2.yield_strain(0.0258 * 0.01 .* t, T1) ≈ 1.1094
    @test_throws DimensionMismatch P64B2.yield_strain(strain, zeros(Int, 99))
    @test_throws ArgumentError P64B2.yield_strain(strain, N; threshold = 0)
    @test_throws ArgumentError P64B2.yield_strain(strain, N; window = 0)
end

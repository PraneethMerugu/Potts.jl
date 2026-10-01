# P6.2a (ROADMAP Phase 6, step 2; review §3 R2 and R16): the `InsertUntil` layout and the
# code-definition analysis primitives behind Akeeb's metrics (spec 10 §5.3.3 O1–O8).
# Frozen (AUTONOMY §7.3).
#
# Surface fixed by the coordinator:
#
#   InsertUntil(kind; into, fraction = nothing, number = nothing, seed, region = nothing (the whole lattice),
#               misses = :retry)                                          (Potts, src/layouts.jl)
#       A layout layer. Draws sites uniformly from `region` with `StableRNG(seed)`. A draw HITS
#       when the site's owner is a live cell whose kind is in `into`: a new one-site cell of
#       `kind` is painted there. Any other draw (medium, another kind, an inserted cell) MISSES.
#       `misses = :retry`: a miss changes nothing. `misses = :count`: a miss adds one to the
#       count without creating a cell (CompuCell3D's empty "ghost" cells, D-068); ghosts are
#       never allocated. counted = hits (+ misses under :count). Exactly one stop rule:
#         number = n     stop once counted ≥ n
#         fraction = r   stop once K + counted ≥ r·(N + counted), where N is the number of
#                        live cells and K the number of live `kind` cells painted before
#                        this layer
#       The rule is evaluated before the first draw and after every HIT only (CC3D recomputes
#       the ratio only after a hit, spec 10 §5.3.6), so under :count the final count may
#       overshoot by the misses since the last hit (CC3D's 391/392 inventories).
#       Throws an ArgumentError if `region` holds no site of an `into` kind (instead of
#       looping forever), and for a bad stop rule or `misses` value.
#
#   layout(l, lat; report = true) -> (point, report)                     (Potts, src/layouts.jl)
#       `point == layout(l, lat)`; `report` has one row per leaf layer in paint order. The
#       `p62a_tally` helper below keeps the rows of the InsertUntil layers as
#       `(; painted, misses, counted)` NamedTuples, in paint order (the former
#       `layout_tally`, removed in P6.1a6). `misses` counts missed draws in both modes.
#
#   PottsModels.Analysis                     (lib/PottsModels/src/analysis/, D-051 item 6)
#       find_peaks(x; distance = nothing, prominence = nothing, width = nothing,
#                  rel_height = 0.5) -> Vector{Int}
#           A port of SciPy 1.7.x `scipy.signal.find_peaks` (BSD-3, D-069), 1-based. Local
#           maxima (plateau midpoint (left + right) ÷ 2; the first and last samples are never
#           peaks), then the distance filter (higher peaks first; ties in the order of NumPy
#           ≤ 1.22's default, UNSTABLE, introsort `argsort`, which is insertion sort, hence
#           stable, only for ≤ 16 peaks), then prominence ≥, then width ≥ (at `rel_height`).
#           `wlen` is always `nothing`.
#       peak_prominences(x, peaks) -> (; prominences, left_bases, right_bases)   (1-based)
#       peak_widths(x, peaks; rel_height = 0.5) -> (; widths, width_heights, left_ips, right_ips)
#       merge_peaks(peaks, gap) -> Vector{Int}   keep p iff p − (last kept) > gap (the
#           authors' merge, gap = 15; the first peak is always kept)
#       column_tops([pred,] σ) -> Vector{Int}    per x = σ's first index: the largest y (second
#           index) whose owner c ≠ 0 satisfies pred(c) (default: any cell); 0 if none
#       trapz(x, y)                              trapezoid rule, as numpy.trapz(y, x)
#       cell_graph(σ; periodic = (false, …), neighborhood = VonNeumann(1)) -> Vector{Vector{Int}}
#           g[c] = sorted distinct cells sharing a lattice-neighbour site pair with cell c
#           (c in 1:maximum(σ); medium is not a cell). An adjacency-list view of
#           CorePotts' `contact_graph` (a different name: that one is exported by CorePotts)
#       reachable(g, seeds) -> Vector{Int}       sorted cells reachable from `seeds` (BFS)
#       components(g, cells) -> Vector{Vector{Int}}   connected components of the subgraph
#           induced by `cells`, each sorted, ordered by their smallest member
#       centroids(σ) -> Vector{NTuple{N, Float64}}    mean site coordinate of each cell
#
# Every expected value below is derived by hand in the comments and was cross-checked
# against an independent literal transcription of SciPy 1.7.x `_peak_finding(_utils)` and
# NumPy 1.21 `aquicksort_double`.
using Potts: CorePotts

p62a_get(op, key) = only(last(p) for p in op if isequal(first(p), key))
# The InsertUntil rows of the layout report as (; painted, misses, counted), in paint order.
function p62a_tally(l, lat)
    op, report = layout(l, lat; report = true)
    return op, [(; r.painted, r.misses, r.counted) for r in report if r.type === :InsertUntil]
end
# Operating points hold symbolic keys, so `==` on them is symbolic: compare the values.
p62a_same(a, b) = p62a_get(a, ownership) == p62a_get(b, ownership) && p62a_get(a, kind) == p62a_get(b, kind)

# A lattice from a picture: rows top (y = Y) to bottom (y = 1), σ[x, y].
p62a_lattice(rows) = (Y = length(rows); [rows[Y - y + 1][x] for x in eachindex(rows[1]), y in 1:Y])

# ---------------------------------------------------------------------------------------------
# find_peaks: known answers (D-069). Indices are 1-based; SciPy's 0-based answers are shifted.
# ---------------------------------------------------------------------------------------------

@testset "P6.2a: find_peaks local maxima, plateaus and edges" begin
    (; find_peaks) = PottsModels.Analysis
    #        1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17
    x = [5, 1, 3, 3, 3, 1, 4, 4, 4, 4, 0, 2, 2, 7, 1, 6, 6]
    # 1: the first sample (the global maximum) is never a peak.
    # 3:5 odd plateau (3,3,3) between 1 and 1: peak at (3 + 5) ÷ 2 = 4.
    # 7:10 even plateau (4,4,4,4) between 1 and 0: peak at (7 + 10) ÷ 2 = 8 (rounded down;
    #   SciPy 0-based (6 + 9) // 2 = 7, i.e. 8).
    # 12:13 plateau (2,2) climbs on to 7: not a maximum. 14 (7 between 2 and 1) is a peak.
    # 16:17 plateau (6,6) runs into the last sample: never a peak.
    @test find_peaks(x) == [4, 8, 14]
    @test find_peaks(Float64.(x)) == [4, 8, 14]
    @test find_peaks(ones(5)) == Int[]                  # flat: no sample has a smaller neighbour
    @test find_peaks([1, 2]) == Int[]                   # both samples are edges
    @test find_peaks([1, 3, 1]) == [2]
    @test find_peaks([9, 1, 9]) == Int[]                # the edges are the highest samples
end

@testset "P6.2a: find_peaks distance filter and its priority order" begin
    (; find_peaks) = PottsModels.Analysis
    # SciPy `_select_by_peak_distance`: iterate `argsort(heights)` from the END (highest
    # first); each kept peak removes its neighbours closer than ceil(distance) samples.
    # NumPy's argsort of ≤ 16 values is an insertion sort: equal heights keep position
    # order, so among equal heights the RIGHTMOST peak is processed first.
    w = [0, 1, 0, 1, 0, 1, 0, 1, 0]                    # peaks 2, 4, 6, 8 (equal height 1)
    # distance 3: process 8 (kills 6), skip 6, process 4 (kills 2), skip 2 -> [4, 8]
    # (leftmost-first would give [2, 6]).
    @test find_peaks(w; distance = 3) == [4, 8]
    @test find_peaks(w; distance = 2.5) == [4, 8]      # ceil(2.5) = 3
    @test find_peaks(w; distance = 2) == [2, 4, 6, 8]  # gaps of 2 are not < 2
    @test find_peaks(w; distance = 1) == [2, 4, 6, 8]
    # A higher peak wins over position: peaks 2, 4, 6(h 2), 8. 6 is processed first and
    # kills 4 and 8; then 8, 4 are skipped; 2 is 4 from 6 and kept -> [2, 6].
    @test find_peaks([0, 1, 0, 1, 0, 2, 0, 1, 0]; distance = 3) == [2, 6]
    @test_throws ArgumentError find_peaks(w; distance = 0.5)   # SciPy: distance must be ≥ 1

    # 16 equal peaks (insertion sort, stable): 0-based peaks 1, 3, …, 31, indices j = 0…15.
    # Rightmost first: keep j = 15, 13, …, 1 -> positions 2j + 1 = 3, 7, …, 31 -> 1-based
    # 4, 8, …, 32.
    s16 = [isodd(i) ? 1 : 0 for i in 0:32]
    @test find_peaks(s16; distance = 3) == collect(4:4:32)
    # 17 equal peaks: NumPy 1.17–1.22 `aquicksort` partitions once (pr − pl = 16 > 15).
    # All keys equal, so median-of-3 swaps nothing; pm = 8 is swapped with 15, then pi and
    # pj swap (1,14) (2,13) (3,12) (4,11) (5,10) (6,9) (7,8), stop at pi = 8 > pj = 7, and
    # the pivot is swapped back (8 <-> 15). Both halves (0:7 and 9:16) are then insertion
    # sorted with no moves, so argsort = [0,14,13,12,11,10,9,15,8,6,5,4,3,2,1,7,16].
    # Processed from the end: 16 (kills 15), 7 (kills 6, 8), 1 (kills 0, 2), 3 (kills 4),
    # 5, 9 (kills 10), 11 (kills 12), 13 (kills 14). Kept j = {1,3,5,7,9,11,13,16} ->
    # 0-based positions 3, 7, …, 27, 33 -> 1-based 4, 8, …, 28, 34. A stable sort would keep
    # 2, 6, …, 34 instead: this pins SciPy's actual (unstable) tie order.
    s17 = [isodd(i) ? 1 : 0 for i in 0:34]
    @test find_peaks(s17; distance = 3) == [4, 8, 12, 16, 20, 24, 28, 34]
end

@testset "P6.2a: peak prominences with nested peaks and base selection" begin
    (; find_peaks, peak_prominences) = PottsModels.Analysis
    #    1  2  3   4  5  6  7  8  9 10 11
    x = [0, 3, 1, 10, 4, 6, 2, 7, 1, 1, 1]
    # Local maxima 2, 4, 6, 8 (9:11 is a valley plateau). Bases: scan outwards while
    # x ≤ x[peak], keeping the lowest sample; ties keep the one NEAREST the peak (strict <).
    #   2 (h 3):  left min 0 at 1; right min 1 at 3 (10 stops the scan). prom 3 − max(0,1) = 2
    #   4 (h 10): left min 0 at 1; right: 4@5, 2@7, 1@9 (1@10, 1@11 are ties) -> base 9.
    #             prom 10 − max(0, 1) = 9
    #   6 (h 6):  left 4@5 (10 stops); right 2@7 (7 stops). prom 6 − max(4, 2) = 2
    #   8 (h 7):  left 2@7 (10 stops, after 6 ≤ 7 and 4); right 1@9. prom 7 − max(2, 1) = 5
    pk = find_peaks(x)
    @test pk == [2, 4, 6, 8]
    pr = peak_prominences(x, pk)
    @test pr.prominences == [2.0, 9.0, 2.0, 5.0]
    @test pr.left_bases == [1, 1, 5, 7]
    @test pr.right_bases == [3, 9, 7, 9]
    @test find_peaks(x; prominence = 5) == [4, 8]      # prominence ≥ 5, inclusive
    @test find_peaks(x; prominence = 9) == [4]
    @test find_peaks(x; prominence = 9.5) == Int[]
end

@testset "P6.2a: peak widths at rel_height 0.5 with interpolation" begin
    (; find_peaks, peak_prominences, peak_widths) = PottsModels.Analysis
    x = [0, 3, 1, 10, 4, 6, 2, 7, 1, 1, 1]              # as above
    pk = [2, 4, 6, 8]
    # height = x[p] − prom/2; walk out while height < x[i] (not past the bases), then
    # interpolate linearly where x[i] < height.
    #   2: h = 3 − 1 = 2.   left stops at 1 (x 0): 1 + (2 − 0)/(3 − 0) = 5/3;
    #                       right stops at base 3 (x 1): 3 − (2 − 1)/(3 − 1) = 2.5;   w = 5/6
    #   4: h = 10 − 4.5 = 5.5. left at 3 (x 1): 3 + 4.5/9 = 3.5;
    #                       right at 5 (x 4): 5 − 1.5/6 = 4.75;                      w = 1.25
    #   6: h = 6 − 1 = 5.   left at 5 (x 4): 5 + 1/2 = 5.5; right at 7 (x 2): 7 − 3/4 = 6.25; w = 0.75
    #   8: h = 7 − 2.5 = 4.5. left at 7 (x 2): 7 + 2.5/5 = 7.5;
    #                       right at 9 (x 1): 9 − 3.5/6 = 101/12;                    w = 11/12
    wd = peak_widths(x, pk)
    @test wd.widths ≈ [5 / 6, 5 / 4, 3 / 4, 11 / 12]
    @test wd.width_heights ≈ [2.0, 5.5, 5.0, 4.5]
    @test wd.left_ips ≈ [5 / 3, 3.5, 5.5, 7.5]
    @test wd.right_ips ≈ [2.5, 4.75, 6.25, 101 / 12]
    @test peak_widths(x, pk; rel_height = 0.5).widths ≈ wd.widths
    @test find_peaks(x; width = 1) == [4]               # widths ≥ 1
    @test find_peaks(x; width = 0.8) == [2, 4, 8]       # 5/6, 5/4, 11/12 ≥ 0.8 > 3/4
    # A triangle [0, 2, 4, 2, 0], peak 3, prominence 4:
    #   rel 0.5:  h = 2 falls exactly on samples 2 and 4 (no interpolation): w = 2
    #   rel 1.0:  h = 0, the walk stops at the bases 1 and 5: w = 4
    #   rel 0.25: h = 3, 2 + (3 − 2)/(4 − 2) = 2.5 and 4 − 0.5 = 3.5: w = 1
    t = [0, 2, 4, 2, 0]
    @test peak_prominences(t, [3]).prominences == [4.0]
    @test peak_widths(t, [3]).widths ≈ [2.0]
    @test peak_widths(t, [3]).left_ips ≈ [2.0]
    @test peak_widths(t, [3]; rel_height = 1.0).widths ≈ [4.0]
    w25 = peak_widths(t, [3]; rel_height = 0.25)
    @test w25.widths ≈ [1.0] && w25.left_ips ≈ [2.5] && w25.right_ips ≈ [3.5]
    @test_throws ArgumentError peak_widths(t, [3]; rel_height = -0.1)
end

@testset "P6.2a: find_peaks filter order distance → prominence → width" begin
    (; find_peaks) = PottsModels.Analysis
    #    1  2   3  4  5  6   7   8   9  10  11 12 13 14 15
    x = [0, 0, 30, 0, 2, 8, 14, 18, 20, 18, 14, 8, 2, 0, 0]
    # A narrow spike S at 3 (h 30) and a wide hill W at 9 (h 20), 6 samples apart.
    #   S: prom 30 (bases 2, 4); h 15: ips 2 + 15/30 = 2.5 and 4 − 15/30 = 3.5, width 1.
    #   W: prom 20 − max(0, 0) = 20 (left base 4, right base 14); h 10: ips 6 + 2/6 and
    #      12 − 2/6, width 16/3 ≈ 5.33.
    # Distance 10 runs FIRST and removes W (lower, 6 < 10 from S); S then fails width ≥ 5.
    @test find_peaks(x; prominence = 10, distance = 10, width = 5) == Int[]
    @test find_peaks(x; prominence = 10, width = 5) == [9]    # without distance W survives
    @test find_peaks(x; prominence = 10, distance = 10) == [3]
end

@testset "P6.2a: the authors' finger merge" begin
    (; merge_peaks) = PottsModels.Analysis
    # keep p iff p − last > 15, `last` = the last KEPT peak (−∞ at the start):
    # 5 kept; 20 − 5 = 15 dropped; 21 − 5 = 16 kept; 37 − 21 = 16 kept; 52 − 37 = 15
    # dropped; 53 − 37 = 16 kept.
    @test merge_peaks([5, 20, 21, 37, 52, 53], 15) == [5, 21, 37, 53]
    @test merge_peaks(Int[], 15) == Int[]
    @test merge_peaks([7], 15) == [7]
    @test merge_peaks([1, 17, 33], 15) == [1, 17, 33]
end

# ---------------------------------------------------------------------------------------------
# Per-column profiles and areas, contact graph and clusters (spec 10 §5.3.3 O1–O4, O6–O8)
# ---------------------------------------------------------------------------------------------

# 10 × 7, x periodic, y closed. Kinds: F = follower, L = leader.
#   1 F (2:3, 1:2)   2 L (3,3)   3 F (3,4) (3,5) (4,5)   4 F (6:7, 1:2)   5 L (10,1)
#   6 L (6,6)   7 F (9,6)   8 F (8,4)   9 L (9,4)   10 L (10,3)   11 L (1,3)   12 F (5,3)
const P62A_ROWS = [
    #1   2  3  4  5  6  7  8  9  10       x
    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],     # y 7
    [0, 0, 0, 0, 0, 6, 0, 0, 7, 0],     # y 6
    [0, 0, 3, 3, 0, 0, 0, 0, 0, 0],     # y 5
    [0, 0, 3, 0, 0, 0, 0, 8, 9, 0],     # y 4
    [11, 0, 2, 0, 12, 0, 0, 0, 0, 10],  # y 3
    [0, 1, 1, 0, 0, 4, 4, 0, 0, 0],     # y 2
    [0, 1, 1, 0, 0, 4, 4, 0, 0, 5],     # y 1
]
const P62A_LEADER = [false, true, false, false, true, true, false, false, true, true, true, false]

@testset "P6.2a: contact graph, main tumour, clusters, singles (O1, O2, O6–O8)" begin
    (; cell_graph, reachable, components, centroids) = PottsModels.Analysis
    σ = p62a_lattice(P62A_ROWS)
    @test size(σ) == (10, 7) && σ[10, 1] == 5 && σ[1, 3] == 11 && σ[4, 5] == 3
    # O1: von Neumann site pairs, x periodic. Edges: 1–2 (3,2)-(3,3); 2–3 (3,3)-(3,4);
    # 8–9 (8,4)-(9,4); 10–11 through the wrap (10,3)-(1,3). 12 touches 4 only diagonally,
    # 5 (10,1) would touch (1,1) through the wrap, but (1,1) is medium.
    g = cell_graph(σ; periodic = (true, false))
    @test length(g) == 12
    @test g == [[2], [1, 3], [2], Int[], Int[], Int[], Int[], [9], [8], [11], [10], Int[]]
    # without the wrap, 10 and 11 are apart
    @test cell_graph(σ)[10] == Int[] && cell_graph(σ)[11] == Int[]
    # Moore(1) adds the diagonal pairs 4–12 (6,2)-(5,3), 1–11 (2,2)-(1,3), 9–10 (9,4)-(10,3)
    gm = cell_graph(σ; periodic = (true, false), neighborhood = Moore(1))
    @test gm[1] == [2, 11] && gm[4] == [12] && gm[10] == [9, 11] && gm[12] == [4]

    # O2: seeds are the cells owning a site in row y = 1 with x ∈ 1:X−1 (the authors'
    # range(0, dim.x − 1) skips the last column): 1 and 4, not 5 at (10, 1).
    seeds = sort!(unique(σ[x, 1] for x in 1:9 if σ[x, 1] != 0))
    @test seeds == [1, 4]
    M = reachable(g, seeds)
    @test M == [1, 2, 3, 4]
    @test reachable(g, [8]) == [8, 9] && reachable(g, Int[]) == Int[]
    comps = components(g, 1:12)
    @test comps == [[1, 2, 3], [4], [5], [6], [7], [8, 9], [10, 11], [12]]
    rest = setdiff(1:12, M)
    @test components(g, rest) == [[5], [6], [7], [8, 9], [10, 11], [12]]
    @test components(g, [2, 3, 8]) == [[2, 3], [8]]            # induced: 9 is left out

    # O8 clusters: components outside M with ≥ 2 cells and ≥ 1 follower. {8, 9} counts;
    # the leader-only pair {10, 11} never does (D17).
    clusters = filter(c -> length(c) >= 2 && any(i -> !P62A_LEADER[i], c), components(g, rest))
    @test clusters == [[8, 9]]
    @test [(sum(P62A_LEADER[c]), sum(.!P62A_LEADER[c])) for c in clusters] == [(1, 1)]

    # yCOM: 1 → (1+1+2+2)/4 = 1.5, 2 → 3, 3 → (4+5+5)/3 = 14/3, 4 → 1.5, 5 → 1, 6 → 6,
    # 7 → 6, 8 → 4, 9 → 4, 10 → 3, 11 → 3, 12 → 3. xCOM of 1 is 2.5, of 3 is 10/3.
    com = centroids(σ)
    @test length(com) == 12
    @test [c[2] for c in com] ≈ [1.5, 3, 14 / 3, 1.5, 1, 6, 6, 4, 4, 3, 3, 3]
    @test com[1][1] ≈ 2.5 && com[3][1] ≈ 10 / 3
    ymin = minimum(com[c][2] for c in M)
    @test ymin == 1.5
    # O6 singles: leaders with no neighbour and yCOM > 1.5: 6 only (5 lies below the line;
    # 2, 9, 10, 11 have neighbours; the isolated followers 7 and 12 are not counted, D16).
    singles = [c for c in 1:12 if P62A_LEADER[c] && isempty(g[c]) && com[c][2] > ymin]
    @test singles == [6]
    # O7 detached: cells outside M with yCOM > 1.5 (M is closed under adjacency, so none
    # touches M): 6, 7, 8, 9, 10, 11, 12, not 5.
    detached = [c for c in rest if com[c][2] > ymin]
    @test detached == [6, 7, 8, 9, 10, 11, 12]
    @test length(detached) >= length(singles)             # the per-run invariant (§5.3.3)
end

@testset "P6.2a: per-column profiles and areas (O3, O4)" begin
    (; cell_graph, reachable, column_tops, trapz) = PottsModels.Analysis
    σ = p62a_lattice(P62A_ROWS)
    M = reachable(cell_graph(σ; periodic = (true, false)), [1, 4])
    # top_main(x): highest site of a cell in M = {1,2,3,4}; 0 where there is none
    main = column_tops(in(M), σ)
    @test main == [0, 2, 5, 5, 0, 2, 2, 0, 0, 0]
    # top_out(x): highest site of any cell: 11 at y3; 1; 3; 3; 12 at y3; 6 at y6; 4; 8 at
    # y4; 7 at y6; 10 at y3
    out = column_tops(σ)
    @test out == [3, 2, 5, 5, 3, 6, 2, 4, 6, 3]
    @test column_tops(c -> c == 7, σ) == [0, 0, 0, 0, 0, 0, 0, 0, 6, 0]
    # Kept columns (both profiles exist): x = 2, 3, 4, 6, 7; base = min top_main = 2.
    keep = findall(x -> main[x] > 0 && out[x] > 0, 1:10)
    @test keep == [2, 3, 4, 6, 7]
    base = minimum(main[keep])
    # invasive: trapz over x = [2,3,4,6,7] of [0,3,3,0,0] = 1.5 + 3 + 2·(3+0)/2 + 0 = 7.5
    # infiltrative: [0,3,3,4,0] -> 1.5 + 3 + 2·(3+4)/2 + (4+0)/2 = 13.5
    # (by array index instead of x the gap 4 → 6 would give 6.0 and 10.0)
    @test trapz(keep, main[keep] .- base) == 7.5
    @test trapz(keep, out[keep] .- base) == 13.5
    @test trapz([0.0, 1.0], [2.0, 4.0]) == 3.0
    @test trapz([3], [5]) == 0 && trapz(Int[], Int[]) == 0
end

# ---------------------------------------------------------------------------------------------
# InsertUntil (R2)
# ---------------------------------------------------------------------------------------------

# 36 followers of 4 × 4 in the lower 24 × 24 of a 24 × `h` lattice. A fraction 1/4 of
# leaders needs n with 4n ≥ 36 + n, so the quota is n = 12 (11/47 < 1/4 ≤ 12/48). No
# follower can lose all 16 sites to 12 one-site insertions, so the live count stays 36.
p62a_followers() = Tiling((4, 4); region = (1:24, 1:24), kinds = [:follower])
p62a_leaders(seed; misses = :retry, region = nothing) =
    InsertUntil(:leader; into = [:follower], fraction = 1 // 4, seed, misses, region)

@testset "P6.2a: InsertUntil stops at the ratio" begin
    for seed in 1:5
        op, tallies = p62a_tally(overlay(p62a_followers(), p62a_leaders(seed)), (24, 24))
        σ, kinds = p62a_get(op, ownership), p62a_get(op, kind)
        t = only(tallies)
        @test t.painted == 12 && t.counted == 12
        @test count(==(:leader), kinds) == 12 && count(==(:follower), kinds) == 36
        @test kinds[1:36] == fill(:follower, 36)                 # ids follow layer order
        @test all(c -> count(==(c), σ) == 1, 37:48)              # one-site leaders
        @test count(>(0), σ) == 24 * 24                          # nothing became medium
        @test p62a_same(op, layout(overlay(p62a_followers(), p62a_leaders(seed)), (24, 24)))
    end
    # `number`: exactly n cells under :retry
    op, tallies = p62a_tally(overlay(p62a_followers(),
        InsertUntil(:leader; into = [:follower], number = 5, seed = 1)), (24, 24))
    @test count(==(:leader), p62a_get(op, kind)) == 5 && only(tallies).counted == 5
    # Already satisfied: a second layer counts the 12 leaders of the first (12 ≥ 48/4) and
    # draws nothing.
    op, tallies = p62a_tally(overlay(p62a_followers(), p62a_leaders(1), p62a_leaders(2)), (24, 24))
    @test count(==(:leader), p62a_get(op, kind)) == 12
    @test tallies[2] == (; painted = 0, misses = 0, counted = 0)
    @test p62a_get(op, ownership) == p62a_get(layout(overlay(p62a_followers(), p62a_leaders(1)), (24, 24)), ownership)
end

@testset "P6.2a: InsertUntil inserts only on allowed kinds" begin
    # 49 cells of 2 × 2, spacing 1, alternating a/b (25 a, 24 b), 245 medium sites.
    tiles = Tiling((2, 2); spacing = 1, kinds = [:a, :b])
    base = layout(tiles, (21, 21))
    σ0, k0 = p62a_get(base, ownership), p62a_get(base, kind)
    @test length(k0) == 49 && count(==(:a), k0) == 25
    for seed in 1:5
        op = layout(overlay(tiles, InsertUntil(:x; into = [:a], number = 10, seed)), (21, 21))
        σ, ks = p62a_get(op, ownership), p62a_get(op, kind)
        xs = findall(i -> σ[i] > 0 && ks[σ[i]] == :x, CartesianIndices(σ))
        @test length(xs) == 10
        @test all(i -> σ0[i] > 0 && k0[σ0[i]] == :a, xs)            # only on former a sites
        @test count(==(0), σ) == count(==(0), σ0)                   # medium untouched
        bsites = findall(i -> σ0[i] > 0 && k0[σ0[i]] == :b, CartesianIndices(σ0))
        @test all(i -> σ[i] > 0 && ks[σ[i]] == :b, bsites)          # b untouched
        @test count(==(:b), ks) == 24
    end
    # `into` may list several kinds; a kind never listed is never overwritten
    op = layout(overlay(tiles, InsertUntil(:x; into = [:a, :b], number = 30, seed = 7)), (21, 21))
    @test count(==(:x), p62a_get(op, kind)) == 30
    @test count(==(0), p62a_get(op, ownership)) == 245
    # a region with no allowed site throws instead of looping, in both modes
    for m in (:retry, :count)
        @test_throws ArgumentError layout(overlay(tiles,
            InsertUntil(:x; into = [:c], number = 1, seed = 1, misses = m)), (21, 21))
        @test_throws ArgumentError layout(overlay(tiles,
            InsertUntil(:x; into = [:a], fraction = 1 // 4, seed = 1, misses = m, region = (3:3, 1:21))), (21, 21))
    end
    # bad arguments
    @test_throws ArgumentError InsertUntil(:x; into = [:a], seed = 1)                       # no rule
    @test_throws ArgumentError InsertUntil(:x; into = [:a], number = 3, fraction = 1 // 4, seed = 1)
    @test_throws ArgumentError InsertUntil(:x; into = [:a], number = 3, seed = 1, misses = :ghost)
    @test_throws ArgumentError InsertUntil(:x; into = [:a], fraction = 3 // 2, seed = 1)
    @test_throws ArgumentError InsertUntil(:x; into = [:a], fraction = 0, seed = 1)
end

@testset "P6.2a: InsertUntil counted misses (CC3D ghosts, D-068)" begin
    # Draw over 24 × 48 while followers fill only the lower half: about half the draws miss.
    ts = map(1:20) do seed
        op, tallies = p62a_tally(overlay(p62a_followers(), p62a_leaders(seed; misses = :count)), (24, 48))
        t = only(tallies)
        ks = p62a_get(op, kind)
        @test count(==(:leader), ks) == t.painted                 # ghosts are never cells
        @test length(ks) == 36 + t.painted
        @test t.painted + t.misses == t.counted                   # every draw counts
        @test 4 * t.counted >= 36 + t.counted                     # quota reached (inventory)
        @test 12 <= t.counted <= 12 + t.misses                    # overshoot only by misses
        @test t.painted <= 12
        t
    end
    # Stops earlier in painted count: painted = 12 needs 12 hits in a row (p ≈ 2⁻¹²).
    @test count(t -> t.painted < 12, ts) >= 18
    # The rule is checked only after a hit: when the count reaches 12 on a miss (p ≈ 1/2)
    # it overshoots. At least one of 20 runs does (failure p ≈ 2⁻²⁰).
    @test any(t -> t.counted > 12, ts)
    # The same draws under :retry paint the full quota.
    for seed in 1:20
        t = only(last(p62a_tally(overlay(p62a_followers(), p62a_leaders(seed)), (24, 48))))
        @test t.painted == 12 && t.counted == 12
    end
end

@testset "P6.2a: InsertUntil is reproducible under a seed" begin
    l(seed) = overlay(p62a_followers(), p62a_leaders(seed; misses = :count))
    a, ta = p62a_tally(l(3), (24, 48))
    b, tb = p62a_tally(l(3), (24, 48))
    @test p62a_same(a, b) && ta == tb
    @test p62a_same(layout(l(3), (24, 48)), a)
    σs = [p62a_get(layout(l(s), (24, 48)), ownership) for s in 1:5]
    @test length(unique(σs)) == 5
    # the follower layer does not depend on the insertion seed
    @test all(σ -> count(>(0), σ) == 24 * 24, σs)
end

@testset "P6.2a: InsertUntil composes with Tiling through overlay (Akeeb slab, D-068)" begin
    # The authors' slab: 3 × 3 followers over x 1:498, y 1:21 plus the clipped 2 × 3 column
    # at x 499:500 -> 166·7 + 7 = 1169. Leaders on x 2:500, y 2:20 (0-based 1…499, 1…19:
    # 9481 sites) until 1/4 of the inventory: 4n ≥ 1169 + n -> n = 390.
    slab = overlay(Tiling((3, 3); region = (1:498, 1:21), kinds = [:follower]),
        Tiling((2, 3); region = (499:500, 1:21), kinds = [:follower]))
    seeding(seed, m) = overlay(slab,
        InsertUntil(:leader; into = [:follower], fraction = 1 // 4, seed, misses = m, region = (2:500, 2:20)))
    @test length(p62a_get(layout(slab, (500, 40)), kind)) == 1169
    # Several leaders in one follower can cut it in pieces, and `overlay` warns: silenced.
    quiet(f) = Base.CoreLogging.with_logger(f, Base.CoreLogging.NullLogger())
    t = only(last(quiet(() -> p62a_tally(seeding(1, :retry), (500, 40)))))
    @test t.painted == 390 && t.counted == 390
    # Emulation: the spec's 20,000-run seeding simulation gives 7.9 ± 2.8 empty leaders and
    # inventory 390 in 96.1 % of runs (spec 10 §5.3.6; analytic Σ_{n<390} n/9481 ≈ 8.0).
    # 200 seeds: the mean miss count has SE 0.2, so ±1.0 is 5 SE; P(390) ≥ 0.9 is 4.5 SD.
    ts = quiet(() -> [only(last(p62a_tally(seeding(s, :count), (500, 40)))) for s in 1:200])
    @test abs(sum(t -> t.misses, ts) / 200 - 7.9) <= 1.0
    @test count(t -> t.counted == 390, ts) >= 180
    @test all(t -> t.painted + t.misses == t.counted && 390 <= t.counted <= 390 + t.misses, ts)
    op = quiet(() -> layout(seeding(1, :count), (500, 40)))
    @test count(==(:follower), p62a_get(op, kind)) == 1169               # no follower erased
end

# ---------------------------------------------------------------------------------------------
# Consistency with the authors' released sample runs (spec 10 §5.3.4, D-069)
# ---------------------------------------------------------------------------------------------

# `docs/references` is gitignored: CI and fresh worktrees do not have it. Point
# POTTS_REFERENCES at a checkout that does, or the check is skipped.
const P62A_SAMPLES = joinpath(get(ENV, "POTTS_REFERENCES", joinpath(@__DIR__, "..", "..", "..", "..", "docs", "references")),
    "codebases", "10_Akeeb2026_Leader_Follower_Invasion_Model", "Sample")

@testset "P6.2a: fingers and areas reproduce the authors' sample runs" begin
    # Each sample run writes, at MCS 700, the kept-column profile (BoundaryData: X,
    # Main_Tumor, Outermost, lowest point) and its metrics (Metrics_Data row MCS 700). Our
    # metric on their profile must give their numbers exactly: fingers 12 / 12 / 0 / 0.
    runs = [("Multimodal_invasion", "2_24_0.5"), ("Bulk_Invasion", "-5_30_0"), ("No_Invasion", "-5_0_0"),
        ("Single_cell_invasion", "8_21_0.9")]
    if !isdir(P62A_SAMPLES)
        @test_skip isdir(P62A_SAMPLES)
    else
        (; find_peaks, merge_peaks, trapz) = PottsModels.Analysis
        for (dir, tag) in runs
            rows = [parse.(Int, split(l, ',')) for l in readlines(joinpath(P62A_SAMPLES, dir, "PositionData_$tag",
                "BoundaryData_$tag.csv"))[2:end]]
            xs, main, out = getindex.(rows, 1), getindex.(rows, 2), getindex.(rows, 3)
            metrics = split(only(l for l in readlines(joinpath(P62A_SAMPLES, dir, "Metrics_Data_$tag.csv"))
                                 if startswith(l, "700,")), ',')
            invasive, infiltrative, fingers = parse(Float64, metrics[2]), parse(Float64, metrics[3]),
            parse(Int, metrics[4])
            base = minimum(main)
            @test all(r -> r[4] == base, rows)
            @test length(merge_peaks(find_peaks(main; prominence = 10, distance = 10, width = 5), 15)) == fingers
            @test trapz(xs, main .- base) == invasive
            @test trapz(xs, out .- base) == infiltrative
        end
    end
end

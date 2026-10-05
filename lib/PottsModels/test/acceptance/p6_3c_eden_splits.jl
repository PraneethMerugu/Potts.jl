# P6.3c (ROADMAP Phase 6, step 3; research/initial-state-review.md §2 (§5.8a TST seeding),
# §4; initial-state-vocabulary.md §5.4–§5.6; model-specs/01_merks.md §7.6; D-057, D-063,
# D-091, D-093, D-138): the TST seeding vocabulary. `Eden` (seed-and-grow), a host-routine
# `Splits` (not the lifecycle division routine), `RandomPoints(replace = true)`, and
# `shortfall` with its first `:allow` consumer (01b de novo: seeds drawn with replacement
# merge, so fewer cells than requested is the published behaviour). Frozen (AUTONOMY §7.3);
# decision D-141.
#
# Surface fixed by D-141 (Potts, src/layouts.jl):
#
#   RandomPoints(n; region = <whole lattice>, replace = false, seed)          (amends D-138)
#       `replace = true`: with the region's in-domain sites in column-major order s₁…sₘ and
#       `rng = Potts.layer_rng(seed)`, point k is s_{rand(rng, 1:m)}, k = 1…n, one draw each,
#       no redraw: duplicates are allowed and `n > m` is allowed. `n > 0` with `m = 0` is an
#       `ArgumentError` (nothing to draw from); `n = 0` gives no points. `replace = false` is
#       D-138's rule unchanged (so the two agree up to the first repeated site).
#       `remake(p; replace = …)` works.
#
#   Eden(points; rounds, region = <whole lattice>, kinds, seed, neighborhood = nothing,
#        shortfall = :error, splits = :warn)                                   (exported)
#       TST `GrowInCells` (01 §7.6; ca.cpp:1071-1163) as a layer.
#       Seeding. `points` is a point pattern as for `Voronoi` (`RandomPoints`, `Center()`, a
#       `Point`, or a vector of `Point`s and `Center()`s). Each point is mapped to index
#       coordinates (inverse embedding) and rounded half up per axis, `floor(xᵢ + 1/2)`
#       (TST's sizex/2 centre: `Center()` on 200² is site (101, 101)); along a periodic axis
#       the index wraps (mod1). In point order, a point whose site is inside the lattice, in
#       `region` ∩ domain and still medium in the paint so far becomes a new one-site cell;
#       any other point is not placed (outside, out of region/domain, on an earlier layer's
#       cell, or on a site an earlier point of this layer took: coinciding seeds merge).
#       `kinds` is cycled over the cells created, in creation order; ids in creation order.
#       Growth. `rounds` synchronous rounds. Let G be the cells this layer created and
#       `offs = CorePotts.relation(nbh, core_lattice).offsets` (canonical order), where `nbh`
#       is `neighborhood`, or the lattice's neighbourhood when `nothing` (Moore(1) for a dims
#       tuple). In each round, every site x of `region` ∩ domain, in column-major order, that
#       is medium at the start of the round and has at least one neighbour (`CorePotts.shift`
#       through every offset) owned by a cell of G at the start of the round draws
#       `j = rand(rng, 1:length(offs))` with `rng = Potts.layer_rng(seed, :eden)` (one rng for
#       the whole layer, drawn across rounds); if `shift(x, offs[j])` is inside and owned by a
#       cell of G at the start of the round, x joins that cell at the end of the round. Sites
#       with no such neighbour draw nothing. (The law is TST's: every medium site draws one of
#       the 8 neighbours uniformly and copies it only if it is a growing cell; sites with no
#       growing neighbour can never change, so skipping their draws changes the stream only.)
#       Eden only fills: it never paints a site an earlier layer owns, nor outside `region`
#       or the domain. There is no `into` keyword (the review's "defer"; TST grows into
#       medium only; Voronoi is the same, D-138).
#       Report row: type `:Eden`, `requested` = number of points, `painted` = cells created
#       (points placed), `misses` = requested − painted, `counted` = painted, `clipped` =
#       D-138's region rule (0 for the whole lattice), `dropped`/`splits` as for every layer.
#       `ArgumentError`: rounds < 0, empty `kinds`, a seed outside 0:typemax(UInt64), a bad
#       `shortfall` or `splits`, a `neighborhood` that is not a `CorePotts.RelationSpec`, an
#       empty point list, a point or shape of another dimension (at layout).
#       `remake(e; rounds = …)` works.
#
#   Splits(layer, k; shortfall = :error, splits = :warn)                       (exported)
#       TST `DivideCells` (ca.cpp:901-1002) as a host routine wrapping one layer; it shares
#       only the split geometry with the lifecycle division (AlongMinorAxis), not its
#       routine (no CPMState, no trackers). `0 ≤ k ≤ 30`. It paints `layer` into its own
#       report row (a delegating layer, D-091), then makes k passes. Pass j visits the
#       cells created inside this row (by `layer` or by earlier passes) in id order as they
#       stand at the start of the pass; each cell with ≥ 2 sites is cut in two and its
#       daughter is allocated (`new_cell!`, kind = the mother's) right after the cut, so pass
#       j's daughters follow in the order of their mothers. Cells of earlier layers are
#       never touched.
#       The cut: site coordinates are Cartesian (`embed`) and, along periodic axes, the
#       image nearest the cell's first site in column-major order (displacement in
#       [-n/2, n/2): ties to the lower image). c = centroid; C = Σ (p − c)(p − c)ᵀ; v = the
#       unit eigenvector of C's largest eigenvalue (in 2D CorePotts' AlongMinorAxis rule:
#       v ∝ (λ − C₂₂, C₁₂) unless |C₁₂| ≤ eps·(|C₁₁| + |C₂₂|), then e₁ if C₁₁ ≥ C₂₂ else e₂;
#       in general, when the largest eigenvalue is repeated, the first standard axis with a
#       nonzero projection on its eigenspace, projected), with its sign fixed so that its
#       first component of magnitude > 1e-9 is positive. A site p goes to the daughter iff
#       (p − c)·v > 0; sites on the plane stay with the mother (TST: `j > aa2 + bb2·i`).
#       One-piece check: at the end of its paint, every piece of this row that is not
#       connected under the lattice neighbourhood is counted in the row's `splits` and, under
#       `splits = :warn`, gets a `@warn` (containing "Splits"); `:allow` silences the warning,
#       not the count. (The overlay check of D-057/D-091 is unchanged: a cell is "cut" only by
#       a later layer.)
#       Report row: type `:Splits`, `requested` = m·2ᵏ (m = cells of `layer` that own a site
#       after it painted), `painted` = cells of this row owning a site after the passes,
#       `misses` = requested − painted, `counted` = painted, `clipped` = the inner layer's.
#       `ArgumentError`: k outside 0:30, bad `shortfall` or `splits`. `remake(s; k = …)`
#       works.
#
#   shortfall = :error | :warn | :allow  (Eden and Splits only, in this item)
#       When `painted < requested` at the end of the layer's own paint: `:error` throws an
#       `ArgumentError` whose message names the layer type, the word "shortfall", both
#       counts, and the remedy `shortfall = :allow`; `:warn` logs the same text as a warning
#       and paints; `:allow` paints silently. The report row is the same in all three modes.
#       It is never inferred from `replace` (01b's de novo layout passes `:allow` itself).
#       Cells dropped by later layers are not a shortfall (they are `dropped`).
#
#   No DSL name or keyword is added: layouts are problem data (D-057).
#
# Expected values. Every hand fixture is derived in the comments next to it. Where the result
# depends on the draws, the independent oracle below replays the D-141 rule on its own lattice
# arithmetic (only `Potts.layer_rng` and `CorePotts.relation` are shared; both are frozen by
# D-138 and the CorePotts suite). The 01 §7.6 bands come from the spec's independent Python
# re-implementation of TST (de novo ≈ 355 cells of ≈ 47 px, ≈ 17 000 px; sprout blob ≈ 1 850–
# 2 300 px → 128 cells of ≈ 15–18 px); the test author's stub measured, seeds 1:8, de novo
# 357–360 cells, mean 47.6 px; sprout blobs 1 816–2 439 (mean 2 166), 128 cells each.
using Potts: CorePotts
using StableRNGs: StableRNG

# ---------------------------------------------------------------------------------------------
# Helpers (independent of the code under test)
# ---------------------------------------------------------------------------------------------

p63c_σ(op) = op[1].second
p63c_kinds(op) = op[2].second
p63c_sites(σ, c) = Set(Tuple.(findall(==(c), σ)))
# two layouts paint the same (the operating point's keys are symbolic, so no `==` on it)
p63c_same(a, b) = p63c_σ(a) == p63c_σ(b) && p63c_kinds(a) == p63c_kinds(b)
p63c_quiet(f) = @test_logs min_level = Base.CoreLogging.Warn f()   # no warning while painting

# A custom layer painting given site sets, one cell each (the public paint protocol, D-091).
struct P63cSites <: Potts.AbstractLayout
    cells::Vector{Vector{Tuple{Vararg{Int}}}}
    kinds::Vector{Any}
end
P63cSites(cells, kinds = fill(:c, length(cells))) = P63cSites([Tuple{Vararg{Int}}[Tuple(x) for x in c] for c in cells], Any[kinds...])
function Potts.paint!(op::Potts.LayoutState, l::P63cSites, lat)
    for (k, c) in enumerate(l.cells)
        id = Potts.new_cell!(op, l.kinds[k])
        for x in c
            Potts.assign!(op, x, id)
        end
    end
    return nothing
end

# Moore(1) in 2D, CorePotts' canonical order (squared length, then lexicographic).
const P63C_MOORE2 = ((-1, 0), (0, -1), (0, 1), (1, 0), (-1, -1), (-1, 1), (1, -1), (1, 1))
p63c_offs(spec, lat) = [Tuple(Int.(o)) for o in CorePotts.relation(spec, lat).offsets]

# The neighbour of x at o, or nothing (periodic axes wrap, closed axes end).
function p63c_nb(x, o, dims, per)
    N = length(dims)
    y = ntuple(d -> x[d] + o[d], N)
    y = ntuple(d -> per[d] ? mod1(y[d], dims[d]) : y[d], N)
    return all(d -> 1 <= y[d] <= dims[d], 1:N) ? y : nothing
end

# RandomPoints(replace = true) oracle: `sites` in column-major order.
p63c_rp(sites, n, seed) = (rng = StableRNG(UInt64(seed)); [sites[rand(rng, 1:length(sites))] for _ in 1:n])
# replace = false (D-138): redraw while taken.
function p63c_rp_distinct(sites, n, seed)
    rng = StableRNG(UInt64(seed)); taken = Set{Int}(); out = eltype(sites)[]
    for _ in 1:n
        i = rand(rng, 1:length(sites))
        while i in taken
            i = rand(rng, 1:length(sites))
        end
        push!(taken, i); push!(out, sites[i])
    end
    return out
end

# Eden oracle. σ0: the paint before the layer (ids 1:base); allowed: region ∩ domain (Bool
# array); seeds: site tuples or `nothing` (point outside the lattice), in point order.
# `deterministic = true` is the negative-control variant: a site joins its first growing
# neighbour every round (a different growth law).
function p63c_eden(σ0, allowed, seeds, rounds, seed, kinds, offs, per; deterministic = false, stream = :eden)
    dims = size(σ0)
    σ = Int.(σ0)
    base = maximum(σ; init = 0)
    nk = Any[]
    for x in seeds
        x === nothing && continue
        (allowed[x...] && σ[x...] == 0) || continue
        push!(nk, kinds[mod1(length(nk) + 1, length(kinds))])
        σ[x...] = base + length(nk)
    end
    rng = stream === nothing ? Potts.layer_rng(seed) : Potts.layer_rng(seed, stream)
    grows(y) = y !== nothing && σ[y...] > base
    for _ in 1:rounds
        new = copy(σ)
        for I in CartesianIndices(σ)
            x = Tuple(I)
            (allowed[I] && σ[I] == 0) || continue
            any(o -> grows(p63c_nb(x, o, dims, per)), offs) || continue
            if deterministic
                o = offs[findfirst(o -> grows(p63c_nb(x, o, dims, per)), offs)]
                new[I] = σ[p63c_nb(x, o, dims, per)...]
            else
                y = p63c_nb(x, offs[rand(rng, 1:length(offs))], dims, per)
                grows(y) && (new[I] = σ[y...])
            end
        end
        σ = new
    end
    return σ, nk
end

# Pieces of cell c that are not connected under `offs` (wrapping along `per`): 0 or 1.
function p63c_split(σ, c, offs, per)
    idx = Tuple.(findall(==(c), σ))
    isempty(idx) && return 0
    seen = Set([idx[1]]); st = [idx[1]]
    while !isempty(st)
        q = pop!(st)
        for o in offs
            y = p63c_nb(q, o, size(σ), per)
            y !== nothing && σ[y...] == c && !(y in seen) && (push!(seen, y); push!(st, y))
        end
    end
    return length(seen) < length(idx) ? 1 : 0
end

p63c_box(r...) = vec([Tuple(x) for x in CartesianIndices(r)])

# ---------------------------------------------------------------------------------------------
# Surface
# ---------------------------------------------------------------------------------------------

@testset "P6.3c surface" begin
    @test Base.isexported(Potts, :Eden) && Base.isexported(Potts, :Splits)
    @test Potts.Eden <: Potts.AbstractLayout && Potts.Splits <: Potts.AbstractLayout
    # a host layer, not the lifecycle routine: CorePotts has no such names
    @test !isdefined(CorePotts, :Eden) && !isdefined(CorePotts, :Splits)
    # name clash control (D-056): not names of Potts' SciML/geometry dependencies
    @test !isdefined(Potts.SciMLBase, :Eden) && !isdefined(Potts.SciMLBase, :Splits)
    # RandomPoints keeps its D-138 positional surface and gains `replace`
    @test RandomPoints(3; seed = 1, replace = true) isa Any
    @test RandomPoints(3; seed = 1, replace = false) isa Any
end

# ---------------------------------------------------------------------------------------------
# RandomPoints(replace = true)
# ---------------------------------------------------------------------------------------------

@testset "RandomPoints(replace = true): draw rule" begin
    # (target, region (or nothing), in-domain region sites column-major, n)
    dom = Lattice((6, 6); boundary = Closed(), domain = x -> x[1] <= x[2])
    cases = [
        ((6, 5), nothing, p63c_box(1:6, 1:5), 20),                     # n = 20 < m = 30
        ((7, 7), (2:4, 3:5), p63c_box(2:4, 3:5), 12),                  # n = 12 > m = 9
        ((4, 4, 4), (1:2, 1:2, 1:2), p63c_box(1:2, 1:2, 1:2), 10),     # 3D, n > m = 8
        (dom, nothing, [x for x in p63c_box(1:6, 1:6) if x[1] <= x[2]], 25),   # domain: m = 21
        (Lattice((5, 4)), nothing, p63c_box(1:5, 1:4), 30),            # periodic, n > m = 20
    ]
    for (target, region, sites, n) in cases, seed in (1, 2, 3, 0x0123456789abcdef)
        p = region === nothing ? RandomPoints(n; replace = true, seed) : RandomPoints(n; region, replace = true, seed)
        got = Potts.points(p, target)
        @test length(got) == n
        want = p63c_rp(sites, n, seed)
        @test got == [Point{length(x), Float64}(Float64.(x)) for x in want]
        @test Potts.points(p, target) == got                          # deterministic in the seed
    end
    # pigeonhole: 12 points on 9 sites must repeat (hand: 12 > 9)
    pts = Potts.points(RandomPoints(12; region = (2:4, 3:5), replace = true, seed = 5), (7, 7))
    @test length(unique(pts)) <= 9 && length(pts) == 12
    @test all(p -> 2 <= p[1] <= 4 && 3 <= p[2] <= 5, pts)
    # replace = false still refuses n > m (D-138) and stays distinct
    @test_throws ArgumentError Potts.points(RandomPoints(12; region = (2:4, 3:5), seed = 5), (7, 7))
    @test allunique(Potts.points(RandomPoints(9; region = (2:4, 3:5), seed = 5), (7, 7)))
    # the two rules share one stream: they agree up to (excluding) the first repeated draw
    for seed in 1:20
        sites = p63c_box(1:5, 1:5)
        with = p63c_rp(sites, 10, seed)
        k = findfirst(i -> with[i] in with[1:(i - 1)], 2:10)
        k === nothing && continue
        a = Potts.points(RandomPoints(10; region = (1:5, 1:5), replace = true, seed), (5, 5))
        b = Potts.points(RandomPoints(10; region = (1:5, 1:5), seed), (5, 5))
        @test a[1:k] == b[1:k]                    # k = (first repeat index) − 1
        @test a != b                               # negative control: the redraw rule differs
        @test b == [Point{2, Float64}(Float64.(x)) for x in p63c_rp_distinct(sites, 10, seed)]
    end
    # a shape region wrapping through a periodic edge (D-138): Circle(Point(1, 1), 1) on a
    # periodic 9 × 9 holds (1,1) (2,1) (9,1) (1,2) (1,9); column-major: (1,1) (2,1) (9,1) (1,2) (1,9)
    pp = Potts.points(RandomPoints(30; region = Circle(Point(1.0, 1.0), 1.0), replace = true, seed = 4), Lattice((9, 9)))
    want = p63c_rp([(1, 1), (2, 1), (9, 1), (1, 2), (1, 9)], 30, 4)
    @test pp == [Point{2, Float64}(Float64.(x)) for x in want]
    # hex: draws are index sites, returned Cartesian (q + r/2, r√3/2)
    hx = Lattice((5, 4); geometry = Hexagonal(), boundary = Closed())
    hp = Potts.points(RandomPoints(15; replace = true, seed = 9), hx)
    want = p63c_rp(p63c_box(1:5, 1:4), 15, 9)
    @test all(i -> isapprox(collect(hp[i]), [want[i][1] + want[i][2] / 2, want[i][2] * sqrt(3) / 2]; atol = 1e-12), 1:15)
    # edge cases
    @test isempty(Potts.points(RandomPoints(0; replace = true, seed = 1), (3, 3)))
    nodom = Lattice((6, 6); boundary = Closed(), domain = x -> x[1] <= 3)
    @test_throws ArgumentError Potts.points(RandomPoints(2; region = (5:6, 1:6), replace = true, seed = 1), nodom)
    @test isempty(Potts.points(RandomPoints(0; region = (5:6, 1:6), replace = true, seed = 1), nodom))
    @test_throws ArgumentError RandomPoints(-1; replace = true, seed = 1)
    @test_throws ArgumentError RandomPoints(2; replace = true, seed = -1)
end

@testset "RandomPoints(replace = true): remake" begin
    p = RandomPoints(12; region = (2:4, 3:5), seed = 5)
    q = remake(p; replace = true)
    @test Potts.points(q, (7, 7)) == Potts.points(RandomPoints(12; region = (2:4, 3:5), replace = true, seed = 5), (7, 7))
    @test Potts.points(remake(q; seed = 6), (7, 7)) == Potts.points(RandomPoints(12; region = (2:4, 3:5), replace = true, seed = 6), (7, 7))
    @test Potts.points(remake(remake(q; replace = false); n = 9), (7, 7)) == Potts.points(RandomPoints(9; region = (2:4, 3:5), seed = 5), (7, 7))
    @test_throws ArgumentError remake(q; n = -1)
    @test_throws ArgumentError remake(q; seed = -1)
end

# ---------------------------------------------------------------------------------------------
# Eden: hand fixtures
# ---------------------------------------------------------------------------------------------

@testset "Eden: seeding (rounds = 0)" begin
    # two points → two one-site cells, kinds cycled over the cells created
    op, rep = layout(Eden([Point(2.0, 3.0), Point(5.0, 5.0)]; rounds = 0, kinds = [:a, :b], seed = 1), (6, 6); report = true)
    σ = p63c_σ(op)
    @test σ[2, 3] == 1 && σ[5, 5] == 2 && count(!=(0), σ) == 2
    @test p63c_kinds(op) == [:a, :b]
    r = only(rep)
    @test (r.type, r.requested, r.painted, r.dropped, r.misses, r.counted, r.clipped, r.splits) == (:Eden, 2, 2, 0, 0, 2, 0, 0)
    # rounding half up: Center() on 6×6 is (3.5, 3.5) → (4, 4); on 5×5 (3, 3); on 200² (101, 101)
    @test findall(!=(0), p63c_σ(layout(Eden(Center(); rounds = 0, kinds = [:a], seed = 1), (6, 6)))) == [CartesianIndex(4, 4)]
    @test findall(!=(0), p63c_σ(layout(Eden(Center(); rounds = 0, kinds = [:a], seed = 1), (5, 5)))) == [CartesianIndex(3, 3)]
    @test findall(!=(0), p63c_σ(layout(Eden(Center(); rounds = 0, kinds = [:a], seed = 1), (200, 200)))) == [CartesianIndex(101, 101)]
    @test findall(!=(0), p63c_σ(layout(Eden(Point(2.5, 2.49); rounds = 0, kinds = [:a], seed = 1), (6, 6)))) == [CartesianIndex(3, 2)]
    # 3D and hex: index (2, 3, 1) and hex index (3, 2) = Cartesian (3 + 1, √3)
    @test findall(!=(0), p63c_σ(layout(Eden([Point(2.0, 3.0, 1.0)]; rounds = 0, kinds = [:a], seed = 1), (4, 4, 4)))) == [CartesianIndex(2, 3, 1)]
    hx = Lattice((6, 6); geometry = Hexagonal(), boundary = Closed())
    @test findall(!=(0), p63c_σ(layout(Eden([Point(4.0, sqrt(3))]; rounds = 0, kinds = [:a], seed = 1), hx))) == [CartesianIndex(3, 2)]
    # a point off a closed lattice is not placed; on a periodic axis it wraps: x = 0 → 6
    op, rep = layout(Eden([Point(0.0, 3.0), Point(2.0, 2.0)]; rounds = 0, kinds = [:a], seed = 1, shortfall = :allow), (6, 6); report = true)
    @test findall(!=(0), p63c_σ(op)) == [CartesianIndex(2, 2)] && (rep[1].requested, rep[1].painted, rep[1].misses) == (2, 1, 1)
    op = layout(Eden([Point(0.0, 3.0), Point(2.0, 2.0)]; rounds = 0, kinds = [:a], seed = 1), Lattice((6, 6)))
    @test p63c_σ(op)[6, 3] == 1 && p63c_σ(op)[2, 2] == 2
    # coinciding points merge: the first creates the cell; kinds cycle over cells, not points
    pts = [Point(2.0, 2.0), Point(2.0, 2.0), Point(4.0, 4.0)]
    op, rep = layout(Eden(pts; rounds = 0, kinds = [:a, :b], seed = 1, shortfall = :allow), (6, 6); report = true)
    @test p63c_σ(op)[2, 2] == 1 && p63c_σ(op)[4, 4] == 2 && p63c_kinds(op) == [:a, :b]
    @test (rep[1].requested, rep[1].painted, rep[1].misses, rep[1].counted) == (3, 2, 1, 2)
end

@testset "Eden: one growth draw (hole and strip fixtures)" begin
    @test p63c_offs(Moore(1), CorePotts.Lattice((5, 5))) == collect(P63C_MOORE2)   # the oracle's order
    # Hole: closed 3×3, the 8 ring sites are seeds (ids in this order); the centre is the only
    # frontier site and every neighbour grows, so round 1 paints it with the cell at
    # (2, 2) + offs[j], j the layer's first draw. 9 sites, 8 cells.
    ring = [(1, 1), (2, 1), (3, 1), (1, 2), (3, 2), (1, 3), (2, 3), (3, 3)]
    for seed in 1:6
        op = layout(Eden([Point(Float64.(x)) for x in ring]; rounds = 1, kinds = [:a], seed), (3, 3))
        σ = p63c_σ(op)
        j = rand(Potts.layer_rng(seed, :eden), 1:8)
        y = (2 + P63C_MOORE2[j][1], 2 + P63C_MOORE2[j][2])
        @test count(!=(0), σ) == 9 && maximum(σ) == 8
        @test σ[2, 2] == findfirst(==(y), ring)
        @test [σ[x...] for x in ring] == 1:8
    end
    # Strip: closed 60×1, one seed at (1, 1). Every round the only frontier site is the one
    # right of the blob; its single in-lattice growing neighbour is offset (-1, 0) = offs[1],
    # so it is painted iff that round's draw is 1. After R rounds the blob is 1 + #{draws == 1}.
    for seed in 1:6, R in (1, 40)
        rng = Potts.layer_rng(seed, :eden)
        want = 1 + count(==(1), [rand(rng, 1:8) for _ in 1:R])
        σ = p63c_σ(layout(Eden(Point(1.0, 1.0); rounds = R, kinds = [:a], seed), (60, 1)))
        @test count(==(1), σ) == want && all(==(1), σ[1:want, 1]) && all(==(0), σ[(want + 1):end, 1])
    end
    # negative control: a deterministic Eden would fill 41 sites in 40 rounds
    @test count(==(1), p63c_σ(layout(Eden(Point(1.0, 1.0); rounds = 40, kinds = [:a], seed = 1), (60, 1)))) < 20
    # Periodic strip (8, 1), x periodic, y closed: seed (1, 1). Frontier in column-major order:
    # (2, 1) [growing neighbour at (-1, 0) = offs[1]] then (8, 1) [at (+1, 0) through the wrap
    # = offs[4]]; one draw each.
    per = Lattice((8, 1); boundary = (Periodic(), Closed()))
    for seed in 1:12
        rng = Potts.layer_rng(seed, :eden)
        j1, j2 = rand(rng, 1:8), rand(rng, 1:8)
        σ = p63c_σ(layout(Eden(Point(1.0, 1.0); rounds = 1, kinds = [:a], seed), per))
        @test σ[2, 1] == (j1 == 1 ? 1 : 0) && σ[8, 1] == (j2 == 4 ? 1 : 0) && all(==(0), σ[3:7, 1])
    end
    # closed control: (8, 1) is never a frontier site in round 1
    @test all(s -> p63c_σ(layout(Eden(Point(1.0, 1.0); rounds = 1, kinds = [:a], seed = s), (8, 1)))[8, 1] == 0, 1:12)
    # the stream is layer_rng(seed, :eden): at least one hole seed differs under layer_rng(seed)
    @test any(1:6) do seed
        j = rand(Potts.layer_rng(seed), 1:8)
        σ = p63c_σ(layout(Eden([Point(Float64.(x)) for x in ring]; rounds = 1, kinds = [:a], seed), (3, 3)))
        σ[2, 2] != findfirst(==((2 + P63C_MOORE2[j][1], 2 + P63C_MOORE2[j][2])), ring)
    end
end

@testset "Eden: fills medium only; region, domain and clipping" begin
    # a seed on an earlier cell is not placed; the tile is never painted over in 20 rounds
    l(sf) = overlay(Tiling((2, 2); region = (3:4, 3:4), kinds = [:x]),
                    Eden([Point(3.0, 3.0), Point(1.0, 1.0)]; rounds = 20, kinds = [:e], seed = 1, shortfall = sf))
    op, rep = layout(l(:allow), (6, 6); report = true)
    σ = p63c_σ(op)
    @test all(==(1), σ[3:4, 3:4]) && count(==(1), σ) == 4 && σ[1, 1] == 2
    @test (rep[2].type, rep[2].requested, rep[2].painted, rep[2].misses) == (:Eden, 2, 1, 1)
    @test rep[1].splits == 0 && rep[2].splits == 0
    @test_throws ArgumentError layout(l(:error), (6, 6))
    # with a Frame first (TST's border): the frame is never grown into
    op = layout(overlay(Frame(:border; width = 1), Eden(Center(); rounds = 30, kinds = [:e], seed = 2)), (12, 12))
    σ = p63c_σ(op)
    @test all(==(1), σ[1, :]) && all(==(1), σ[end, :]) && all(==(1), σ[:, 1]) && all(==(1), σ[:, end])
    @test p63c_kinds(op) == [:border, :e]
    # region box: growth stays inside 3:6 × 3:6
    σ = p63c_σ(layout(Eden(Center(); region = (3:6, 3:6), rounds = 30, kinds = [:a], seed = 3), (10, 10)))
    @test all(x -> 3 <= x[1] <= 6 && 3 <= x[2] <= 6, findall(!=(0), σ)) && count(!=(0), σ) >= 1
    # a seed outside the region is not placed
    op, rep = layout(Eden([Point(1.0, 1.0)]; region = (3:6, 3:6), rounds = 3, kinds = [:a], seed = 1, shortfall = :allow), (10, 10); report = true)
    @test all(==(0), p63c_σ(op)) && (rep[1].requested, rep[1].painted) == (1, 0)
    # shape region clipped by the closed corner: Circle(Point(1, 1), 2) holds the 13 integer
    # points with dx² + dy² ≤ 4; the in-lattice ones have dx, dy ≥ 0: (0,0) (1,0) (2,0) (0,1)
    # (0,2) (1,1) = 6, so clipped = 7 and growth stays on those 6 sites
    disc = Circle(Point(1.0, 1.0), 2.0)
    op, rep = layout(Eden(Point(1.0, 1.0); region = disc, rounds = 25, kinds = [:a], seed = 4), (10, 10); report = true)
    @test rep[1].clipped == 7
    @test issubset(Set(Tuple.(findall(!=(0), p63c_σ(op)))), Set([(1, 1), (2, 1), (3, 1), (1, 2), (1, 3), (2, 2)]))
    # domain: x + y ≤ 7 on a closed 6×6; the box 3:6 × 3:6 (16 sites) keeps (3,3) (3,4) (4,3):
    # clipped = 13 and growth stays on those 3 sites
    dom = Lattice((6, 6); boundary = Closed(), domain = x -> x[1] + x[2] <= 7)
    op, rep = layout(Eden(Point(3.0, 3.0); region = (3:6, 3:6), rounds = 25, kinds = [:a], seed = 5), dom; report = true)
    @test rep[1].clipped == 13
    @test issubset(Set(Tuple.(findall(!=(0), p63c_σ(op)))), Set([(3, 3), (3, 4), (4, 3)]))
    # whole lattice: clipped 0, even with a domain
    @test only(last(layout(Eden(Point(2.0, 2.0); rounds = 2, kinds = [:a], seed = 1), dom; report = true))).clipped == 0
    # a later layer over an Eden cell: dropped, not a shortfall
    op, rep = layout(overlay(Eden([Point(2.0, 2.0), Point(5.0, 5.0)]; rounds = 0, kinds = [:a], seed = 1),
                             Tiling((1, 1); region = (2:2, 2:2), kinds = [:t])), (6, 6); report = true)
    @test (rep[1].requested, rep[1].painted, rep[1].dropped) == (2, 2, 1) && p63c_kinds(op) == [:a, :t]
end

# ---------------------------------------------------------------------------------------------
# Eden: the oracle on square / hex / 3D, periodic / closed / domain
# ---------------------------------------------------------------------------------------------

@testset "Eden: oracle ($name)" for (name, target, dims, per, spec, layer_spec) in [
        ("square closed, Moore", (30, 30), (30, 30), (false, false), Moore(1), nothing),
        ("square periodic, Moore", Lattice((20, 20)), (20, 20), (true, true), Moore(1), nothing),
        ("square closed, VonNeumann keyword", (20, 20), (20, 20), (false, false), VonNeumann(1), VonNeumann(1)),
        ("hex closed", Lattice((20, 20); geometry = Hexagonal(), boundary = Closed()), (20, 20), (false, false), Moore(1), nothing),
        ("hex periodic", Lattice((20, 20); geometry = Hexagonal()), (20, 20), (true, true), Moore(1), nothing),
        ("3D closed", (8, 8, 8), (8, 8, 8), (false, false, false), Moore(1), nothing),
        ("3D periodic", Lattice((8, 8, 8)), (8, 8, 8), (true, true, true), Moore(1), nothing),
        ("square domain", Lattice((20, 20); boundary = Closed(), domain = x -> (x[1] - 10)^2 + (x[2] - 10)^2 <= 64), (20, 20), (false, false), Moore(1), nothing),
    ]
    N = length(dims)
    clat = target isa Tuple ? CorePotts.Lattice(target; boundary = Closed()) : target
    offs = p63c_offs(spec, clat)
    mask = clat.mask === nothing ? trues(dims) : Array(clat.mask)
    region = vec([Tuple(x) for x in CartesianIndices(dims) if mask[x]])
    for seed in 1:3, (n, rounds) in ((6, 4), (3, 9))
        p = RandomPoints(n; replace = true, seed = 10 + seed)
        seeds = p63c_rp(region, n, 10 + seed)
        kw = layer_spec === nothing ? (;) : (; neighborhood = layer_spec)
        op, rep = layout(Eden(p; rounds, kinds = [:a, :b, :c], seed, shortfall = :allow, kw...), target; report = true)
        want, wk = p63c_eden(zeros(Int, dims), mask, seeds, rounds, seed, [:a, :b, :c], offs, per)
        @test p63c_σ(op) == want
        @test p63c_kinds(op) == wk
        r = only(rep)
        @test (r.requested, r.painted, r.misses, r.counted) == (n, length(unique(seeds)), n - length(unique(seeds)), length(unique(seeds)))
        # every cell is one piece under the growth neighbourhood (sites join a neighbour)
        @test all(c -> p63c_split(want, c, offs, per) == 0, 1:maximum(want))
        # negative control: the deterministic growth law gives another σ
        rounds >= 4 && @test p63c_σ(op) != first(p63c_eden(zeros(Int, dims), mask, seeds, rounds, seed, [:a, :b, :c], offs, per; deterministic = true))
    end
    # with an earlier layer (a frame on closed axes, or a block on periodic ones)
    first_layer = all(per) ? Tiling(ntuple(_ -> 2, N); region = ntuple(_ -> 1:2, N), kinds = [:t]) : Frame(:f; width = 1)
    op0 = layout(first_layer, target)
    σ0 = Int.(p63c_σ(op0))
    seeds = p63c_rp(region, 5, 77)
    op = layout(overlay(first_layer, Eden(RandomPoints(5; replace = true, seed = 77); rounds = 5, kinds = [:e], seed = 8, shortfall = :allow,
        (layer_spec === nothing ? (;) : (; neighborhood = layer_spec))...)), target)
    want, _ = p63c_eden(σ0, mask, seeds, 5, 8, [:e], offs, per)
    @test p63c_σ(op) == want
    @test all(i -> σ0[i] == 0 || p63c_σ(op)[i] == σ0[i], eachindex(σ0))      # earlier cells untouched
end

@testset "Eden: invariants and determinism" begin
    pts = RandomPoints(8; region = (10:30, 10:30), replace = true, seed = 3)
    e(R; seed = 1) = Eden(pts; rounds = R, kinds = [:a], seed, shortfall = :allow)
    σ6 = p63c_σ(layout(e(6), (40, 40)))
    σ9 = p63c_σ(layout(e(9), (40, 40)))
    # same seed: the first 6 rounds are the same draws, so every site painted at 6 keeps its owner
    @test all(i -> σ6[i] == 0 || σ9[i] == σ6[i], eachindex(σ6))
    @test count(!=(0), σ9) > count(!=(0), σ6)
    @test p63c_σ(layout(e(6), (40, 40))) == σ6                                 # deterministic
    @test p63c_σ(layout(e(6; seed = 2), (40, 40))) != σ6                       # the seed matters
    # Moore growth moves one Chebyshev step per round: each cell stays within 6 of its seed
    seeds = unique(p63c_rp(p63c_box(10:30, 10:30), 8, 3))
    for (c, s) in enumerate(seeds)
        @test all(x -> maximum(abs.(Tuple(x) .- s)) <= 6, findall(==(c), σ6))
    end
    @test count(!=(0), σ6) <= length(seeds) * 13^2
    # remake
    @test p63c_σ(layout(remake(e(6); rounds = 9), (40, 40))) == σ9
    @test p63c_σ(layout(remake(e(6); seed = 2), (40, 40))) == p63c_σ(layout(e(6; seed = 2), (40, 40)))
    @test_throws ArgumentError remake(e(6); rounds = -1)
end

@testset "Eden: argument errors" begin
    @test_throws ArgumentError Eden(Center(); rounds = -1, kinds = [:a], seed = 1)
    @test_throws ArgumentError Eden(Center(); rounds = 1, kinds = Symbol[], seed = 1)
    @test_throws ArgumentError Eden(Center(); rounds = 1, kinds = [:a], seed = -1)
    @test_throws ArgumentError Eden(Center(); rounds = 1, kinds = [:a], seed = 1, shortfall = :sometimes)
    @test_throws ArgumentError Eden(Center(); rounds = 1, kinds = [:a], seed = 1, splits = :never)
    @test_throws ArgumentError Eden(Center(); rounds = 1, kinds = [:a], seed = 1, neighborhood = "moore")
    @test_throws ArgumentError Eden(Point{2, Float64}[]; rounds = 1, kinds = [:a], seed = 1)
    @test_throws ArgumentError layout(Eden(Point(1.0, 1.0, 1.0); rounds = 1, kinds = [:a], seed = 1), (5, 5))
    @test_throws ArgumentError layout(Eden(Center(); region = Sphere(Point(2.0, 2.0, 2.0), 1.0), rounds = 1, kinds = [:a], seed = 1), (5, 5))
end

# ---------------------------------------------------------------------------------------------
# shortfall and its first :allow consumer
# ---------------------------------------------------------------------------------------------

@testset "shortfall: :error, :warn, :allow" begin
    # 10 points with replacement on the 9 sites of 1:3 × 1:3: at least one merge (pigeonhole)
    p = RandomPoints(10; region = (1:3, 1:3), replace = true, seed = 2)
    made = length(unique(p63c_rp(p63c_box(1:3, 1:3), 10, 2)))
    @test made <= 9
    e(sf) = Eden(p; rounds = 2, kinds = [:a], seed = 1, shortfall = sf)
    err = try
        layout(e(:error), (6, 6)); nothing
    catch x
        x
    end
    @test err isa ArgumentError
    msg = sprint(showerror, err)
    @test occursin("Eden", msg) && occursin("shortfall", msg) && occursin("shortfall = :allow", msg)
    @test occursin(Regex("\\b10\\b"), msg) && occursin(Regex("\\b$(made)\\b"), msg)
    @test_throws ArgumentError layout(Eden(p; rounds = 2, kinds = [:a], seed = 1), (6, 6))   # the default is :error
    a, ra = p63c_quiet(() -> layout(e(:allow), (6, 6); report = true))
    w, rw = @test_logs (:warn, r"shortfall") layout(e(:warn), (6, 6); report = true)
    @test p63c_same(a, w) && ra == rw
    @test (ra[1].requested, ra[1].painted, ra[1].misses) == (10, made, 10 - made)
    @test maximum(p63c_σ(a)) == made
    # no shortfall, no message, in every mode
    q = RandomPoints(3; region = (1:3, 1:3), seed = 2)                         # distinct
    for sf in (:error, :warn, :allow)
        p63c_quiet(() -> layout(Eden(q; rounds = 2, kinds = [:a], seed = 1, shortfall = sf), (6, 6)))
    end
    @test remake(e(:error); shortfall = :allow) isa Potts.AbstractLayout
    @test p63c_same(layout(remake(e(:error); shortfall = :allow), (6, 6)), a)
end

@testset "01b de novo (01 §7.6): the :allow consumer, and the GrowInCells law" begin
    # TST denovo_*.par: 200², a one-site border, 360 seeds with replacement over the 198²
    # interior, 10 synchronous Eden rounds, no division.
    denovo(s; sf = :allow) = overlay(Frame(:border; width = 1),
        Eden(RandomPoints(360; region = (2:199, 2:199), replace = true, seed = s);
             rounds = 10, kinds = [:endothelial], seed = 100 + s, shortfall = sf))
    # seed 1 draws a coinciding pair (the oracle's count): the default refuses, :allow paints
    @test length(unique(p63c_rp(p63c_box(2:199, 2:199), 360, 1))) < 360
    @test_throws ArgumentError layout(denovo(1; sf = :error), (200, 200))
    means = Float64[]
    for s in 1:8
        op, rep = layout(denovo(s), (200, 200); report = true)
        σ = p63c_σ(op)
        cells = rep[2].painted
        @test cells == length(unique(p63c_rp(p63c_box(2:199, 2:199), 360, s)))
        @test 350 <= cells <= 360 && maximum(σ) == cells + 1
        area = count(>(1), σ)
        @test 16_000 <= area <= 18_000                  # spec: ≈ 17 000 px
        push!(means, area / cells)
        @test all(==(1), σ[1, :]) && all(==(1), σ[:, 200])     # the border is untouched
    end
    @test 45.5 <= sum(means) / 8 <= 49.5                 # spec: ≈ 47–48 px per cell
    # TST sprout: one seed at the centre (101, 101), 50 rounds → one blob of ≈ 1 850–2 300 px,
    # then 7 divisions → 128 cells of ≈ 15–18 px.
    blob(s) = Eden(Center(); rounds = 50, kinds = [:endothelial], seed = s)
    sizes = Int[]
    for s in 1:8
        σ = p63c_σ(layout(overlay(Frame(:border; width = 1), blob(s)), (200, 200)))
        push!(sizes, count(==(2), σ))
        @test σ[101, 101] == 2 && 1_500 <= sizes[end] <= 2_800
        op, rep = layout(overlay(Frame(:border; width = 1), Splits(blob(s), 7; splits = :allow)), (200, 200); report = true)
        σs = p63c_σ(op)
        @test maximum(σs) == 129 && count(>(1), σs) == sizes[end]            # sites conserved
        @test (rep[2].type, rep[2].requested, rep[2].painted, rep[2].misses) == (:Splits, 128, 128, 0)
        @test 11 <= sizes[end] / 128 <= 22
    end
    @test 1_900 <= sum(sizes) / 8 <= 2_400
    # negative control: a deterministic Eden fills the Chebyshev ball, 101² = 10 201 sites
    # (rows 51:151 lie inside the 2:199 interior), far outside the band
    σ0 = Int.(p63c_σ(layout(Frame(:border; width = 1), (200, 200))))
    allowed = σ0 .== 0
    det, _ = p63c_eden(σ0, allowed, [(101, 101)], 50, 1, [:e], collect(P63C_MOORE2), (false, false); deterministic = true)
    @test count(==(2), det) == 101^2
end

# ---------------------------------------------------------------------------------------------
# Splits: hand fixtures
# ---------------------------------------------------------------------------------------------

@testset "Splits: the cut (square)" begin
    # 4 × 2 box x ∈ 3:6, y ∈ 4:5: C = diag(10, 2), long axis e₁, centroid x = 4.5 → the
    # daughter (id 2) is x ∈ 5:6, the mother keeps x ∈ 3:4
    t = Tiling((4, 2); region = (3:6, 4:5), kinds = [:a])
    op, rep = layout(Splits(t, 1), (8, 8); report = true)
    σ = p63c_σ(op)
    @test p63c_sites(σ, 1) == Set(p63c_box(3:4, 4:5)) && p63c_sites(σ, 2) == Set(p63c_box(5:6, 4:5))
    @test p63c_kinds(op) == [:a, :a]
    r = only(rep)
    @test (r.type, r.requested, r.painted, r.dropped, r.misses, r.counted, r.clipped, r.splits) == (:Splits, 2, 2, 0, 0, 2, 0, 0)
    # k = 2: each 2 × 2 half is isotropic (C = diag(1, 1), the e₁ tie rule): cell 1 keeps
    # x = 3 and its daughter (id 3) takes x = 4; cell 2 keeps x = 5, daughter 4 takes x = 6
    σ = p63c_σ(layout(Splits(t, 2), (8, 8)))
    @test [p63c_sites(σ, c) for c in 1:4] == [Set(p63c_box(x:x, 4:5)) for x in (3, 5, 4, 6)]
    # negative control: cutting along the long axis instead would give the rows y = 4 / y = 5
    @test p63c_sites(p63c_σ(layout(Splits(t, 1), (8, 8))), 1) != Set(p63c_box(3:6, 4:4))
    # 3 × 5 box x ∈ 1:3, y ∈ 1:5: C = diag(10, 30), centroid (2, 3); the row y = 3 lies on the
    # plane and stays with the mother: mother 9 sites (y ≤ 3), daughter 6 (y ∈ 4:5)
    σ = p63c_σ(layout(Splits(Tiling((3, 5); region = (1:3, 1:5), kinds = [:a]), 1), (6, 7)))
    @test p63c_sites(σ, 1) == Set(p63c_box(1:3, 1:3)) && p63c_sites(σ, 2) == Set(p63c_box(1:3, 4:5))
    # diagonal (1,1)…(4,4): C = [5 5; 5 5], v = (1, 1)/√2, centroid (2.5, 2.5) → daughter (3,3) (4,4)
    σ = p63c_σ(layout(Splits(P63cSites([[(1, 1), (2, 2), (3, 3), (4, 4)]]), 1), (5, 5)))
    @test p63c_sites(σ, 2) == Set([(3, 3), (4, 4)])
    # anti-diagonal: v ∝ (1, −1) with a positive first component → daughter (3,2) (4,1)
    σ = p63c_σ(layout(Splits(P63cSites([[(1, 4), (2, 3), (3, 2), (4, 1)]]), 1), (5, 5)))
    @test p63c_sites(σ, 2) == Set([(3, 2), (4, 1)])
end

@testset "Splits: hex, 3D, periodic" begin
    # Hex rhombus q ∈ 2:4, r ∈ 2:3 (6 sites). In Cartesian coordinates (q + r/2, r√3/2) the
    # covariance is tilted (per site: var x = var q + var r/4 = 2/3 + 1/16, var y = 3/16,
    # cov = √3/16 > 0), so v ≈ (0.982, 0.189); the centroid is (4.25, 2.5·√3/2). Projections:
    # (2,2) −1.31, (3,2) −0.33, (4,2) +0.65, (2,3) −0.65, (3,3) +0.33, (4,3) +1.31 →
    # daughter {(4,2), (3,3), (4,3)}. Index-space covariance (diag(2/3, 1/4)) would give the
    # daughter {(4,2), (4,3)} (negative control).
    hx = Lattice((6, 6); geometry = Hexagonal(), boundary = Closed())
    σ = p63c_σ(layout(Splits(P63cSites([p63c_box(2:4, 2:3)]), 1), hx))
    @test p63c_sites(σ, 2) == Set([(4, 2), (3, 3), (4, 3)])
    @test p63c_sites(σ, 1) == Set([(2, 2), (3, 2), (2, 3)])
    @test p63c_sites(σ, 2) != Set([(4, 2), (4, 3)])
    # 3D 2 × 2 × 4: C = diag(2, 2, 20), centroid z = 2.5 → daughter z ∈ 3:4
    σ = p63c_σ(layout(Splits(Tiling((2, 2, 4); region = (1:2, 1:2, 1:4), kinds = [:a]), 1), (3, 3, 5)))
    @test p63c_sites(σ, 2) == Set(p63c_box(1:2, 1:2, 3:4)) && p63c_sites(σ, 1) == Set(p63c_box(1:2, 1:2, 1:2))
    # 3D 3 × 2 × 2: long axis x, centroid x = 2 (on the plane: mother) → daughter x = 3
    σ = p63c_σ(layout(Splits(Tiling((3, 2, 2); region = (1:3, 1:2, 1:2), kinds = [:a]), 1), (4, 3, 3)))
    @test p63c_sites(σ, 2) == Set(p63c_box(3:3, 1:2, 1:2))
    # 3D isotropic 2 × 2 × 2 (the tie rule: e₁) → daughter x = 2
    σ = p63c_σ(layout(Splits(Tiling((2, 2, 2); region = (1:2, 1:2, 1:2), kinds = [:a]), 1), (3, 3, 3)))
    @test p63c_sites(σ, 2) == Set(p63c_box(2:2, 1:2, 1:2))
    # Periodic 10 × 10: a cell on x ∈ {9, 10, 1, 2}, y ∈ 4:5 across the edge. First site in
    # column-major order is (1, 4); nearest images x = 9 → −1, 10 → 0: unwrapped −1, 0, 1, 2,
    # centroid 0.5 → daughter x ∈ {1, 2}, mother x ∈ {9, 10}
    cell = [(x, y) for y in 4:5 for x in (1, 2, 9, 10)]
    σ = p63c_σ(layout(Splits(P63cSites([cell]), 1), Lattice((10, 10))))
    @test p63c_sites(σ, 2) == Set([(x, y) for y in 4:5 for x in (1, 2)])
    # closed control: the same sites unwrapped as 1, 2, 9, 10 (centroid 5.5) → daughter {9, 10}
    σ = p63c_σ(layout(Splits(P63cSites([cell]), 1), (10, 10)))
    @test p63c_sites(σ, 2) == Set([(x, y) for y in 4:5 for x in (9, 10)])
end

@testset "Splits: ids, kinds, conservation, earlier layers" begin
    # two cells of kinds :a and :b, k = 1 → ids 1 (a), 2 (b), 3 (a, daughter of 1), 4 (b)
    two = P63cSites([p63c_box(1:4, 1:2), p63c_box(1:2, 5:8)], [:a, :b])
    op = layout(Splits(two, 1), (8, 8))
    σ = p63c_σ(op)
    @test p63c_kinds(op) == [:a, :b, :a, :b]
    @test p63c_sites(σ, 3) == Set(p63c_box(3:4, 1:2)) && p63c_sites(σ, 4) == Set(p63c_box(1:2, 7:8))
    # k = 2: pass 2 visits 1, 2, 3, 4 → daughters 5, 6, 7, 8 of the same kinds
    op = layout(Splits(two, 2), (8, 8))
    @test p63c_kinds(op) == [:a, :b, :a, :b, :a, :b, :a, :b]
    σ = p63c_σ(op)
    # cell 1 (x 1:2, y 1:2) → mother x = 1, daughter 5 x = 2; cell 2 (x 1:2, y 5:6) → 6 is x = 2
    @test p63c_sites(σ, 5) == Set(p63c_box(2:2, 1:2)) && p63c_sites(σ, 6) == Set(p63c_box(2:2, 5:6))
    # conservation: Eden blobs split 3 times keep their sites, each piece inside its blob
    inner = Eden(RandomPoints(4; region = (5:35, 5:35), seed = 9); rounds = 8, kinds = [:p, :q], seed = 3)
    σin = p63c_σ(layout(inner, (40, 40)))
    op, rep = layout(Splits(inner, 3; splits = :allow), (40, 40); report = true)
    σs = p63c_σ(op)
    @test (σs .!= 0) == (σin .!= 0)
    @test all(c -> length(unique(σin[σs .== c])) == 1, 1:maximum(σs))
    @test maximum(σs) == 32 && (rep[1].requested, rep[1].painted) == (32, 32)
    @test p63c_kinds(op) == [k for _ in 1:16 for k in (:p, :q)]     # each daughter takes its mother's kind
    # k = 0 is the inner layer
    op0, rep0 = layout(Splits(inner, 0), (40, 40); report = true)
    @test p63c_σ(op0) == σin && (rep0[1].requested, rep0[1].painted) == (4, 4)
    # an earlier layer is never split; the Splits row reports only its own cells
    op, rep = layout(overlay(Tiling((4, 2); region = (1:4, 1:2), kinds = [:t]),
                             Splits(Tiling((4, 2); region = (1:4, 5:6), kinds = [:s]), 1)), (6, 8); report = true)
    σ = p63c_σ(op)
    @test p63c_sites(σ, 1) == Set(p63c_box(1:4, 1:2)) && p63c_kinds(op) == [:t, :s, :s]
    @test [(r.type, r.requested, r.painted) for r in rep] == [(:Tiling, 1, 1), (:Splits, 2, 2)]
    # clipped is the inner layer's: the corner disc of the Eden fixture (7)
    disc = Circle(Point(1.0, 1.0), 2.0)
    _, rep = layout(Splits(Eden(Point(1.0, 1.0); region = disc, rounds = 25, kinds = [:a], seed = 4), 0), (10, 10); report = true)
    @test rep[1].clipped == 7
end

@testset "Splits: one-piece check" begin
    # U open upwards: columns x = 1 and x = 3 at y ∈ 1:6, joined by (2, 1) (13 sites).
    # Σ(x − 2)² = 12, Σ(y − 43/13)² ≈ 40.8, covariance 0 → long axis e₂, centroid y ≈ 3.31 →
    # daughter = y ∈ 4:6 in both columns: two pieces two columns apart, not connected under
    # Moore(1). The mother {(1,1:3), (2,1), (3,1:3)} is one piece.
    U = P63cSites([vcat([(1, y) for y in 1:6], [(3, y) for y in 1:6], [(2, 1)])])
    op, rep = @test_logs (:warn, r"Splits") layout(Splits(U, 1), (5, 8); report = true)
    @test p63c_sites(p63c_σ(op), 2) == Set(vcat([(1, y) for y in 4:6], [(3, y) for y in 4:6]))
    @test rep[1].splits == 1
    op2, rep2 = p63c_quiet(() -> layout(Splits(U, 1; splits = :allow), (5, 8); report = true))
    @test p63c_same(op2, op) && rep2[1].splits == 1
    # negative control: a convex cell splits into one-piece halves, no warning, splits = 0
    _, rep3 = p63c_quiet(() -> layout(Splits(Tiling((4, 2); region = (3:6, 4:5), kinds = [:a]), 2), (8, 8); report = true))
    @test rep3[1].splits == 0
end

@testset "Splits: shortfall and argument errors" begin
    # a one-site cell cannot be cut: requested 2·2 = 4, painted 3 (cell 2 → (5,5) and (6,5))
    l(sf) = Splits(P63cSites([[(2, 2)], [(5, 5), (6, 5)]]), 1; shortfall = sf)
    @test_throws ArgumentError layout(l(:error), (8, 8))
    err = try
        layout(l(:error), (8, 8)); nothing
    catch x
        x
    end
    msg = sprint(showerror, err)
    @test occursin("Splits", msg) && occursin("shortfall", msg) && occursin(r"\b4\b", msg) && occursin(r"\b3\b", msg)
    op, rep = p63c_quiet(() -> layout(l(:allow), (8, 8); report = true))
    @test (rep[1].requested, rep[1].painted, rep[1].misses) == (4, 3, 1)
    σ = p63c_σ(op)
    @test σ[2, 2] == 1 && σ[5, 5] == 2 && σ[6, 5] == 3
    @test p63c_same(first(@test_logs (:warn, r"shortfall") layout(l(:warn), (8, 8); report = true)), op)
    # k = 2: nothing left to cut (three one-site cells): requested 8, painted 3
    _, rep = layout(Splits(P63cSites([[(2, 2)], [(5, 5), (6, 5)]]), 2; shortfall = :allow), (8, 8); report = true)
    @test (rep[1].requested, rep[1].painted) == (8, 3)
    # arguments
    t = Tiling((4, 2); region = (3:6, 4:5), kinds = [:a])
    @test_throws ArgumentError Splits(t, -1)
    @test_throws ArgumentError Splits(t, 31)
    @test_throws ArgumentError Splits(t, 1; shortfall = :maybe)
    @test_throws ArgumentError Splits(t, 1; splits = :never)
    @test p63c_same(layout(remake(Splits(t, 1); k = 2), (8, 8)), layout(Splits(t, 2), (8, 8)))
    @test_throws ArgumentError remake(Splits(t, 1); k = -1)
end

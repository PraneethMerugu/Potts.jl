# `Scattered`'s overlap
# test against an occupancy mask.
#
# Surface: unchanged. `Scattered(n, size; region, kinds, seed, gap = 1, splits = :warn)` and
# its `paint!` keep their documented behaviour (D-057): the same `StableRNG(seed)` draw per
# box (one `rand(rng, first(r):(last(r) - s + 1))` per axis, in axis order), the same
# acceptance rule (Chebyshev gap, measured both ways round a periodic axis, hexagonal
# lattices in axial indices), the same 10,000-draw jam error and the same early area-bound
# error. Only the cost of the overlap test changes: today every draw is checked against every
# placed box (O(placed), src/layouts.jl `_apart`), the item checks it against an occupancy
# mask whose gap dilation wraps on periodic axes.
#
# How the layout is checked, with no recorded value: the documented draw rule is written out
# again here, independently of the mask (`scattered_oracle`: the same `StableRNG` stream, one draw
# per axis, a box rejected when it lands within `gap` of a placed box under the closed metric or
# the periodic one, at most 10,000 draws per box). The oracle's σ, kinds and jam index are
# compared with the library's over the case grid below, 26 cases at three gaps and five seeds
# (2D square, 3D and hexagonal; closed, periodic on every axis and on one axis; whole-lattice,
# offset and edge regions that span a periodic ring; rings of 12 and 8 sites; unit boxes; dense
# requests; the D-087 Merks-like request of 282 boxes of 7² in 500²), plus layered cases
# (Scattered over a Tiling, and over another Scattered).
#
# The acceptance rule itself is stated per axis and covered by hand cases before the grid
# runs: two boxes may be placed together when at least one axis clears their extents by `gap`
# (on a closed axis `|a - b| >= size + gap`; on a periodic axis both arcs of the ring must
# clear), because the mask a draw is tested against is the Cartesian product of the per-axis
# dilated windows, and a draw is refused only when its box overlaps that product in every
# axis. The boundary is pinned both ways (`size + gap` accepted, one site short refused) and
# the wrap is pinned separately at gap 0 and gap 1. The rule is then checked on the oracle's
# own boxes (every pair, under the periodic metric), every box is checked to lie inside the
# region, and the report's row is reconciled with a recount from σ.
#
# One property is asserted on top: a periodic axis changes the placement for gap ≥ 1 (at least
# one seed of the grid differs from the closed layout) and never for gap 0 (every seed agrees),
# for each closed/periodic pair of the grid.
#
# Robustness to machine load: each figure is the MINIMUM over several runs after a warm-up
# (compilation is excluded by a small call with the same types), with a `GC.gc()` before
# every run so no run pays for a previous run's garbage. Load only adds time, so the minimum
# estimates the unloaded cost; a run under the bound ends the loop early (min ≤ bound is
# decided by the first such run), which also keeps the failing (today's) run short.

@testsetup module ScatteredMaskSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using StableRNGs: StableRNG
# D-138: PottsModels no longer depends on StableRNGs
scattered_get(op, key) = only(last(p) for p in op if isequal(first(p), key))
scattered_σ(l, target) = scattered_get(layout(l, target), ownership)
scattered_bnd(b::Symbol) = b === :P ? Periodic() : Closed()
scattered_bnd(b::Tuple) = map(scattered_bnd, b)
# the layout target: a closed square lattice as plain dims, everything else as a `Lattice`
function scattered_target(geom, dims, bnd)
    geom === :sq && bnd === :C && return dims
    geom === :hex && return Lattice(dims; boundary = scattered_bnd(bnd), geometry = Hexagonal())
    return Lattice(dims; boundary = scattered_bnd(bnd))
end
const SEEDS = (1, 2, 3, 0x9e3779b97f4a7c15, typemax(UInt64))
const GAPS = (0, 1, 2)
# name => (geometry, dims, boundary, n (or one n per gap), box size, region, kinds)
# boundary :C closed, :P periodic, or one symbol per axis
const CASES = [
    # 2D square
    "sq closed" => (:sq, (24, 18), :C, (16, 9, 6), (3, 4), nothing, [:a, :b, :c]),
    "sq periodic" => (:sq, (24, 18), :P, (16, 9, 6), (3, 4), nothing, [:a, :b, :c]),
    "sq periodic x" => (:sq, (24, 18), (:P, :C), (16, 9, 6), (3, 4), nothing, [:a, :b, :c]),
    "sq periodic y" => (:sq, (24, 18), (:C, :P), (16, 9, 6), (3, 4), nothing, [:a, :b, :c]),
    "sq offset region" => (:sq, (40, 30), :C, (20, 12, 8), (4, 2), (7:33, 4:25), [:a, :b]),
    "sq offset region periodic" => (:sq, (40, 30), :P, (20, 12, 8), (4, 2), (7:33, 4:25), [:a, :b]),
    # the region spans the periodic x ring and sits on the y edge: the gap wraps x = 40 → 1
    "sq edge region periodic" => (:sq, (40, 30), :P, (22, 12, 9), (3, 3), (1:40, 1:9), [:a]),
    "sq edge region periodic x" => (:sq, (40, 30), (:P, :C), (22, 12, 9), (3, 3), (1:40, 22:30), [:a]),
    # a ring of 12 with boxes of 3: the dilation of one box covers most of the ring
    "sq small ring" => (:sq, (12, 30), :P, (18, 10, 6), (3, 2), (1:12, 5:24), [:a, :b]),
    # a ring of 8 with boxes of 3: gap 2 never separates along x (δ ≥ 5 and δ ≤ 3)
    "sq tight ring" => (:sq, (8, 40), (:P, :C), (14, 9, 5), (3, 3), nothing, [:a]),
    "sq unit boxes" => (:sq, (15, 15), :C, (150, 35, 14), (1, 1), nothing, [:a, :b]),
    "sq unit boxes periodic" => (:sq, (15, 15), :P, (150, 35, 14), (1, 1), nothing, [:a, :b]),
    # dense requests: many rejected draws before each late box
    "sq dense" => (:sq, (20, 20), :C, (66, 29, 13), (2, 2), nothing, [:a]),
    "sq dense periodic" => (:sq, (20, 20), :P, (66, 29, 13), (2, 2), nothing, [:a]),
    "merks-like" => (:sq, (500, 500), :C, 282, (7, 7), (85:415, 85:415), [:endothelial]),
    # 3D
    "cube closed" => (:sq, (14, 12, 10), :C, (32, 11, 6), (3, 3, 2), nothing, [:a, :b, :c]),
    "cube periodic" => (:sq, (14, 12, 10), :P, (32, 11, 6), (3, 3, 2), nothing, [:a, :b, :c]),
    "cube periodic z" => (:sq, (14, 12, 10), (:C, :C, :P), (32, 11, 6), (3, 3, 2), nothing, [:a, :b, :c]),
    "cube edge region periodic" => (:sq, (14, 12, 10), :P, (12, 4, 3), (3, 3, 2), (1:14, 1:12, 7:10), [:a]),
    "cube dense" => (:sq, (12, 12, 12), :C, (110, 28, 11), (2, 2, 2), nothing, [:a]),
    "cube dense periodic" => (:sq, (12, 12, 12), :P, (110, 28, 11), (2, 2, 2), nothing, [:a]),
    # hexagonal (axial indices; boxes are rhombi)
    "hex closed" => (:hex, (20, 16), :C, (15, 9, 6), (3, 3), nothing, [:a, :b, :c]),
    "hex periodic" => (:hex, (20, 16), :P, (15, 9, 6), (3, 3), nothing, [:a, :b, :c]),
    "hex periodic x" => (:hex, (20, 16), (:P, :C), (15, 9, 6), (3, 3), nothing, [:a, :b, :c]),
    "hex edge region periodic" => (:hex, (20, 16), :P, (9, 4, 3), (2, 3), (1:20, 11:16), [:a]),
    "hex dense periodic" => (:hex, (20, 20), :P, (66, 28, 13), (2, 2), nothing, [:a]),
]
scattered_n(n::Integer, gi) = n
scattered_n(n::Tuple, gi) = n[gi]
layer(c, gi, seed) = Scattered(scattered_n(c[4], gi), c[5]; region = c[6], kinds = c[7], seed, gap = GAPS[gi])
# Layered cases: Scattered over a Tiling (it overwrites tiles; on hex one is dropped) and two
# Scattered layers. `scattered_second` gives the second layer's parameters for the oracle:
# (n, size, kinds, seed offset).
const LAYERED = [
    "sq tiling+scattered periodic" => (
        (:sq, (40, 30), :P),
        (s, g) -> overlay(
            Tiling((4, 4); spacing = 1, kinds = [:t], splits = :allow),
            Scattered(8, (3, 3); kinds = [:s], seed = s, gap = g, splits = :allow)
        ),
        (8, (3, 3), [:s], UInt64(0)),
    ),
    "hex tiling+scattered closed" => (
        (:hex, (30, 26), :C),
        (s, g) -> overlay(
            Tiling((3, 3); spacing = 1, kinds = [:t], splits = :allow),
            Scattered(8, (3, 3); kinds = [:s], seed = s, gap = g, splits = :allow)
        ),
        (8, (3, 3), [:s], UInt64(0)),
    ),
    "cube scattered+scattered periodic" => (
        (:sq, (24, 20, 16), :P),
        (s, g) -> overlay(
            Scattered(10, (3, 3, 2); kinds = [:a], seed = s, gap = g, splits = :allow),
            Scattered(6, (4, 2, 3); kinds = [:b], seed = s ⊻ 0x5555, gap = g, splits = :allow)
        ),
        (6, (4, 2, 3), [:b], UInt64(0x5555)),
    ),
]
# ---------------------------------------------------------------------------------------------
# The documented draw rule, written out again (no mask, no recorded value)
# ---------------------------------------------------------------------------------------------
scattered_per(b::Symbol, N) = ntuple(_ -> b === :P, N)
scattered_per(b::Tuple, N) = map(x -> x === :P, b)
function scattered_geom(dims, bnd, region)
    N = length(dims)
    reg = region === nothing ? ntuple(d -> 1:dims[d], N) : region
    return (dims, scattered_per(bnd, N), reg)
end
"""
The documented acceptance rule, per axis: the boxes may be placed together when at least one
axis clears their own extents by `gap`. On a closed axis that is `|a[d] - b[d]| >= size[d] + gap`;
on a periodic axis, with `δ = mod(b[d] - a[d], dims[d])`, both arcs of the ring must clear,
`δ - size[d] >= gap` and `dims[d] - δ - size[d] >= gap`. One clear axis is enough because the
mask the layout tests a draw against is the Cartesian product of the per-axis dilated windows:
a draw is refused when its box overlaps that product in every axis, so it is placed when some
axis is `gap` clear. The predicate below is that rule, written out.
"""
apart(a, b, size, dims, per, gap) =
    any(
    ntuple(
        d -> per[d] ? (δ = mod(b[d] - a[d], dims[d]); δ - size[d] >= gap && dims[d] - δ - size[d] >= gap) :
            (abs(a[d] - b[d]) >= size[d] + gap), length(dims)
    )
)
"""Mark the sites of `blocked` (region indices) that are within `gap` of the box at `o`,
wrapping a periodic axis and dropping a closed one's sites outside the lattice."""
function mark_blocked!(blocked, region, dims, per, gap, o, size)
    N = length(dims)
    grown = ntuple(d -> (o[d] - gap):(o[d] + size[d] - 1 + gap), N)
    for I in CartesianIndices(grown)
        J = ntuple(d -> per[d] ? mod1(I[d], dims[d]) : I[d], N)
        all(ntuple(d -> 1 <= J[d] <= dims[d], N)) || continue
        all(ntuple(d -> first(region[d]) <= J[d] <= last(region[d]), N)) || continue
        blocked[ntuple(d -> J[d] - first(region[d]) + 1, N)...] = true
    end
    return blocked
end
"""The documented rule: `n` boxes of `size` in `region`, one `rand` per axis in axis order from
`StableRNG(seed)`, a draw rejected when it lands within `gap` of a placed box, 10,000 draws
per box. Returns the corner of every placed box and the index of the box that jams (0: none)."""
function scattered_oracle(n, size, dims, per, region, seed, gap)
    N = length(dims)
    rng = StableRNG(UInt64(seed))
    ranges = ntuple(d -> first(region[d]):(last(region[d]) - size[d] + 1), N)
    blocked = falses(map(length, region))
    placed = NTuple{N, Int}[]
    for k in 1:n
        ok = false
        for _ in 1:10_000
            o = ntuple(d -> rand(rng, ranges[d]), N)
            hit = false
            for I in CartesianIndices(ntuple(d -> o[d]:(o[d] + size[d] - 1), N))
                blocked[ntuple(d -> I[d] - first(region[d]) + 1, N)...] && (hit = true; break)
            end
            hit && continue
            push!(placed, o)
            mark_blocked!(blocked, region, dims, per, gap, o, size)
            ok = true
            break
        end
        ok || return (; placed = NTuple{N, Int}[], jammed = k)
    end
    return (; placed, jammed = 0)
end
"""σ of the oracle's boxes: cell `k` (id `k`) on the box of the `k`-th placed corner."""
function oracle_σ(placed, size, dims)
    N = length(dims)
    σ = zeros(Int32, dims)
    for (k, o) in enumerate(placed)
        σ[ntuple(d -> o[d]:(o[d] + size[d] - 1), N)...] .= k
    end
    return σ
end
"""The cells' kinds: `kinds` cycled over the boxes, in placement order."""
kinds_of(placed, kinds) = [kinds[mod1(k, length(kinds))] for k in eachindex(placed)]
scattered_error(l, x) =
try
    layout(l, x)
    "no error"
catch e
    e isa ArgumentError || rethrow()
    sprint(showerror, e)
end
# The best (minimum) of up to `runs` timed calls of `f`, a `GC.gc()` before each; stops at
# the first run for which `done(best)` holds. Returns `(best seconds, value of the last call)`.
function scattered_best(f, runs, done)
    best = Inf
    val = nothing
    for _ in 1:runs
        GC.gc()
        t = @elapsed (val = f())
        best = min(best, t)
        done(best) && break
    end
    return best, val
end
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "scattered mask Scattered occupancy mask" setup = [ScatteredMaskSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "scattered mask Scattered occupancy mask" begin
        @testset "the acceptance predicate on hand cases" begin
            # closed: exactly size + gap apart is accepted, one site closer is refused
            @test apart((1,), (6,), (3,), (20,), (false,), 2)     # 1 + 3 + 2 == 6
            @test !apart((1,), (5,), (3,), (20,), (false,), 2)    # 1 + 3 + 2 > 5
            @test apart((1,), (4,), (3,), (20,), (false,), 0)     # adjacent boxes at gap 0
            # one clear axis is enough: overlapping on x, 2 clear sites on y
            @test apart((1, 1), (2, 5), (3, 3), (20, 20), (false, false), 0)
            @test !apart((1, 1), (2, 3), (3, 3), (20, 20), (false, false), 0)
            # periodic: the wrap arc is an arc too, so gap 0 keeps boxes apart across it and gap 1 refuses
            @test apart((1,), (6,), (3,), (8,), (true,), 0)       # arcs of 2 and 0 sites
            @test !apart((1,), (6,), (3,), (8,), (true,), 1)      # the wrap arc is 0 sites
            @test apart((1,), (5,), (2,), (8,), (true,), 1)       # arcs of 2 and 2 sites
            @test !apart((1,), (7,), (2,), (8,), (true,), 1)      # arcs of 4 and 0 sites
        end
        @testset "the documented draw rule, re-derived here ($name, gap $(GAPS[gi]))" for
            (name, c) in CASES, gi in eachindex(GAPS)
            target = scattered_target(c[1], c[2], c[3])
            dims, per, region = scattered_geom(c[2], c[3], c[6])
            n, size, kinds, gap = scattered_n(c[4], gi), c[5], c[7], GAPS[gi]
            N = length(dims)
            for seed in SEEDS
                want = scattered_oracle(n, size, dims, per, region, seed, gap)
                l = layer(c, gi, seed)
                if want.jammed != 0
                    @test occursin("could not place box $(want.jammed) of $n", scattered_error(l, target))
                    continue
                end
                op, rows = layout(l, target; report = true)
                got = scattered_get(op, ownership)
                @test got == oracle_σ(want.placed, size, dims)
                @test scattered_get(op, kind) == kinds_of(want.placed, kinds)
                # every box lies inside the region, and the gap holds under the periodic metric
                @test all(o -> all(ntuple(d -> first(region[d]) <= o[d] <= last(region[d]) - size[d] + 1, N)), want.placed)
                @test all(
                    apart(want.placed[i], want.placed[j], size, dims, per, gap)
                        for i in eachindex(want.placed) for j in (i + 1):lastindex(want.placed)
                )
                # no two boxes overlap, and the report row is a recount from σ
                @test count(!=(0), got) == n * prod(size)
                r = only(rows)
                @test (r.requested, r.painted, r.dropped, r.misses) == (n, n, 0, 0)
            end
        end

        @testset "a periodic axis changes the placement for gap ≥ 1, and never for gap 0" begin
            C = Dict(CASES)
            pairs = (
                ("sq periodic", "sq closed"), ("sq periodic x", "sq closed"), ("sq periodic y", "sq closed"),
                ("sq dense periodic", "sq dense"), ("sq unit boxes periodic", "sq unit boxes"),
                ("cube periodic", "cube closed"), ("cube periodic z", "cube closed"),
                ("cube dense periodic", "cube dense"), ("hex periodic", "hex closed"),
                ("hex periodic x", "hex closed"),
            )
            for (p, cl) in pairs, gi in eachindex(GAPS)
                σp = [scattered_σ(layer(C[p], gi, s), scattered_target(C[p][1], C[p][2], C[p][3])) for s in SEEDS]
                σc = [scattered_σ(layer(C[cl], gi, s), scattered_target(C[cl][1], C[cl][2], C[cl][3])) for s in SEEDS]
                if GAPS[gi] == 0
                    @test all(i -> σp[i] == σc[i], eachindex(σp))
                else
                    @test any(i -> σp[i] != σc[i], eachindex(σp))
                end
            end
        end

        @testset "a layered Scattered lands where the rule puts it ($name, gap $(GAPS[gi]))" for
            (name, (geo, build, second)) in LAYERED, gi in eachindex(GAPS)
            dims, per, region = scattered_geom(geo[2], geo[3], nothing)
            n, size, kinds, off = second
            target = scattered_target(geo...)
            for seed in SEEDS
                gap = GAPS[gi]
                want = scattered_oracle(n, size, dims, per, region, seed ⊻ off, gap)
                want.jammed == 0 || continue      # the second layer is placed: its jam is the fixture's
                op = layout(build(seed, gap), target)
                kid, kk = scattered_get(op, ownership), scattered_get(op, kind)
                painted = Set(I for I in CartesianIndices(kid) if kid[I] != 0 && kk[kid[I]] === kinds[1])
                want_σ = oracle_σ(want.placed, size, dims)
                @test painted == Set(I for I in CartesianIndices(want_σ) if want_σ[I] != 0)
            end
        end

        @testset "refusals and the draw limit" begin
            # the jam error at the same box (the same draws up to it), and the area bound
            @test occursin(
                r"could not place box 18 of 25\b",
                scattered_error(Scattered(25, (3, 3); kinds = [:a], seed = 7, gap = 1), (20, 20))
            )
            @test occursin(
                r"could not place box 18 of 25\b",
                scattered_error(
                    Scattered(25, (3, 3); kinds = [:a], seed = 7, gap = 1),
                    Lattice((20, 20); boundary = Periodic(), geometry = Hexagonal())
                )
            )
            @test occursin(
                r"could not place box 16 of 20\b",
                scattered_error(Scattered(20, (2, 2, 2); kinds = [:a], seed = 7, gap = 2), Lattice((12, 12, 12); boundary = Periodic()))
            )
            @test occursin(
                "cannot fit", scattered_error(
                    Scattered(21, (3, 3); kinds = [:a], seed = 1, gap = 2),
                    Lattice((8, 40); boundary = (Periodic(), Closed()))
                )
            )
            # the documented 10,000-draw limit, from both sides: a box placed late is placed, one
            # past the limit jams
            for (n, s) in ((7, 1290), (6, 2329))
                l = Scattered(n, (30, 30); kinds = [:a], seed = s, gap = 1)
                @test count(!=(0), scattered_get(layout(l, (100, 100)), ownership)) == n * 900
            end
            @test occursin(
                r"could not place box 6 of 6\b",
                scattered_error(Scattered(6, (30, 30); kinds = [:a], seed = 9909, gap = 1), (100, 100))
            )
        end

        @testset "cost" begin
            cubes = Scattered(10_000, (5, 5, 5); kinds = [:a], seed = 1, gap = 1)
            per3 = Lattice((200, 200, 200); boundary = Periodic())
            sq(n) = Scattered(n, (7, 7); kinds = [:a], seed = 1, gap = 1)
            # warm-up: the same method instances on small lattices
            layout(Scattered(2, (5, 5, 5); kinds = [:a], seed = 1, gap = 1), (20, 20, 20))
            layout(Scattered(2, (5, 5, 5); kinds = [:a], seed = 1, gap = 1), Lattice((20, 20, 20); boundary = Periodic()))
            layout(sq(2), (40, 40))

            t, _ = scattered_best(() -> layout(cubes, (200, 200, 200)), 5, <=(0.05))
            @test 1000t <= 50                          # ms; ≈ 480 at a5a2819

            t, _ = scattered_best(() -> layout(cubes, per3), 5, <=(0.05))
            @test 1000t <= 50                          # ms; ≈ 860 at a5a2819

            # time per placed box does not grow with the number placed (same density)
            ts, _ = scattered_best(() -> layout(sq(4_000), (949, 949)), 7, _ -> false)
            tl, _ = scattered_best(() -> layout(sq(40_000), (3000, 3000)), 3, t -> (t / 40_000) / (ts / 4_000) <= 2.5)
            ratio = (tl / 40_000) / (ts / 4_000)
            @test ratio <= 2.5                         # ≈ 9.8 at a5a2819
        end
    end
end

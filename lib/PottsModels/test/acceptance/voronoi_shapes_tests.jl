# Sources: research/initial-state-review.md §2 S2, §3 Q1/Q3/Q5;
# D-056, D-057, D-063, D-091, D-093, D-094): `VoronoiBall` becomes the core layer `Voronoi`
# over the first initial-state vocabulary (`Sphere`/`Circle`/`HyperSphere`, `Point`,
# `RandomPoints`, `Center()`), shape layers clip to the domain and report `clipped`, and
# StableRNGs leaves PottsModels. ; decision D-138.
#
# Surface fixed by D-138 (Potts, src/layouts.jl unless noted):
#
#   Shapes (Q1). Potts imports from GeometryBasics, explicitly and only, `HyperSphere`,
#   `Circle` (= HyperSphere{2}), `Sphere` (= HyperSphere{3}) and `Point`, and exports these
#   same bindings (Makie re-exports the same ones, so `using Potts, CairoMakie` stays
#   unambiguous, D-056). Nothing else of GeometryBasics is imported or exported: index boxes
#   stay tuples of unit ranges (no `Rect`), and GeometryBasics' `volume`, `area`, `direction`,
#   `origin`, `radius`, `widths`, `centered` never become Potts bindings. GeometryBasics is a
#   Potts dependency; CorePotts does not depend on it.
#     Coordinates: a shape lives in Cartesian coordinates, the lattice's embedding of the
#     lattice index (`CorePotts.embed`: the identity on square lattices, `(q + r/2, r√3/2)` on
#     hexagonal ones), as CorePotts' domain predicates already are.
#     Membership is closed and is GeometryBasics' own: site `x` is in shape `s` iff
#     `Point(embed(x)) ∈ s` for the site or one of its periodic images (`x + k .* dims`,
#     `k` nonzero only along periodic axes). So a shape wraps through a periodic edge and is
#     clipped at a closed edge and at the domain.
#   `clipped` (Q5, amends D-057 for shape layers): let U be the index points x ∈ ℤᴺ with
#     `xᵈ ∈ 1:dims[d]` along every periodic axis d that lie in the shape (as above). A shape
#     layer's `clipped` is |U| minus the number of points of U that are in-domain lattice
#     sites: the shape's sites lost to closed edges and to the domain (0 for a shape inside
#     the lattice's domain, and nothing is lost through a periodic edge). Sites the layer
#     skips because an earlier layer owns them are NOT clipped.
#
#   Center()                                                     (exported)
#       A point: the centre of the lattice, `embed((size(lat) .+ 1) ./ 2)`.
#   RandomPoints(n; region = <whole lattice>, seed)              (exported)
#       `n` distinct sites of `region` (a shape or a tuple of unit ranges) that lie in the
#       domain, drawn uniformly: with the region's in-domain sites in column-major lattice
#       order s₁…sₘ and `rng = Potts.layer_rng(seed)`, draw `i = rand(rng, 1:m)` and redraw
#       while sᵢ was already drawn; points in draw order (VoronoiBall's draw rule, D-063).
#       `ArgumentError`: n < 0, n > m, a seed outside 0:typemax(UInt64). `remake(p; seed)`
#       works. (`replace` is `eden_splits_tests.jl`'s.)
#   Potts.points(pattern, x) -> Vector{Point{N, Float64}}       (public, not exported)
#       The Cartesian points of a pattern on target `x` (anything `layout` takes):
#       `RandomPoints`, `Center()`, or a vector of `Point`s and `Center()`s.
#   Voronoi(points; region = <whole lattice>, lloyd = 0, kinds, splits = :warn)   (exported)
#       One cell per generator (`points` as for `Potts.points`), ids in generator order,
#       `kinds` cycled over them. It FILLS: it paints only the sites of `region` that are in
#       the domain and still medium (Morpheus InitVoronoi's rule; an earlier layer's cells are
#       never cut). Each such site goes to the nearest generator, Euclidean in the
#       embedding, minimum image along periodic axes, ties to the lowest generator.
#       `lloyd = k`: k times, every generator that owns a site moves to the centroid of its
#       sites (minimum image along periodic axes), and the sites are reassigned.
#       Then, as `VoronoiBall` (D-063): every cell is made one piece under the geometry's
#       nearest-neighbour steps (2N axis steps on square lattices, the 6 neighbours on
#       hexagonal ones), wrapping on periodic axes; a stray piece joins the neighbouring cell
#       whose largest piece it touches most; a cell's largest piece never moves.
#       Report row: type `:Voronoi`, requested = painted = the generators, dropped = those
#       left with no site, misses 0, counted = painted, `clipped` as above.
#       `ArgumentError`: lloyd < 0, empty `kinds`, no generator, a bad `splits`, a shape or
#       point of another dimension than the lattice. `remake(v; lloyd = …)` works.
#   VoronoiBall (Q3). `Voronoi(RandomPoints(n; region = ball, seed); region = ball, lloyd = it,
#       kinds)`, with `ball = HyperSphere(Point(embed(center)), radius)` (`center` defaulting to
#       the lattice centre), paints the σ and kinds `PottsModels.VoronoiBall(n; radius, center,
#       kinds, seed, iterations = it)` painted at 8eb9d210, so `VoronoiBall` is removed with no
#       alias (D-028), from PottsModels and not added to Potts. On a periodic lattice this holds
#       when no periodic edge cuts the ball (VoronoiBall clipped there, a shape wraps).
#       `graner_glazier_aggregate(n; seed, margin)` returns the same (σ, kinds) as at 8eb9d210.
#   Report (amends D-091): every row gains `clipped` (0 for `Tiling` with `partial = :skip`,
#       `Scattered`, `Frame`, `InsertUntil`); `record!(op; …, clipped = 0)` sets it for a
#       custom layer.
#   Potts.layer_rng(seed) / layer_rng(seed, stream)              (public, not exported)
#       `StableRNG(UInt64(seed))` / `StableRNG(Potts._substream_seed(seed, stream))` (D-093's
#       planned wrapper). PottsModels' `akeeb_state` draws its clocks from
#       `Potts.layer_rng(seed, :clock)` with byte-identical output, and StableRNGs leaves
#       PottsModels' [deps] and [compat] (it stays a Potts dependency); no PottsModels source
#       names `StableRNG`. The files that called `PottsModels.StableRNG` import it from
#       StableRNGs in the test environment under D-138 (`substream_seeds_tests.jl`, `layout_protocol_tests.jl`, `akeeb_inventory_tests.jl`), and `layout_protocol_tests.jl`'s
#       VoronoiBall check names `Voronoi`.
#   No DSL name or keyword is added: layouts are problem data (D-057).
#

@testsetup module VoronoiShapesSetup
include(joinpath(@__DIR__, "..", "shared", "common.jl"))
using Potts: CorePotts
using SHA: sha256
using StableRNGs: StableRNG
using TOML: TOML
# ---------------------------------------------------------------------------------------------
# Helpers (independent of the code under test)
# ---------------------------------------------------------------------------------------------
voronoi_σ(op) = op[1].second
voronoi_kinds(op) = op[2].second
digest(σ) = bytes2hex(sha256(reinterpret(UInt8, vec(htol.(σ)))))
# (dims, periodic flags, hexagonal?, domain mask or nothing) of a layout target
meta(dims::Tuple) = (dims, map(_ -> false, dims), false, nothing)
meta(l::Lattice) = (l.dims, l.periodic, l.geometry isa Hexagonal, l.mask)
cart(x, hex) = hex ? (x[1] + x[2] / 2, x[2] * sqrt(3) / 2) : Float64.(Tuple(x))
voronoi_indomain(mask, x) = all(d -> 1 <= x[d], eachindex(x)) && (mask === nothing || mask[x...])
# the images of index point x along periodic axes (k ∈ -1:1 suffices for the small shapes here)
function images(x, dims, per)
    return [
        ntuple(d -> x[d] + k[d] * dims[d], length(dims))
            for k in Iterators.product(ntuple(d -> per[d] ? (-1:1) : (0:0), length(dims))...)
    ]
end
# closed ball membership in Cartesian coordinates, any periodic image
inball(x, c, r, dims, per, hex) = any(y -> sqrt(sum(abs2, cart(y, hex) .- c)) <= r, images(x, dims, per))
function ballsites(c, r, target)
    m = meta(target)
    return [x for x in CartesianIndices(m[1]) if (m[4] === nothing || m[4][x]) && inball(Tuple(x), c, r, m[1], m[2], m[3])]
end
# nearest generator (Cartesian generators g), minimum image, ties to the lowest index
function voronoi_nearest(x, gens, dims, per, hex)
    best, o = Inf, 0
    for (k, g) in enumerate(gens)
        d = minimum(y -> sum(abs2, cart(y, hex) .- Tuple(g)), images(Tuple(x), dims, per))
        d < best && (best = d; o = k)
    end
    return o, best
end
const SQ2 = ((1, 0), (-1, 0), (0, 1), (0, -1))
const HEX1 = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, -1), (-1, 1))
const CUBE = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))
"""Cells of σ that are not one piece under the index steps (wrapping along `per`)."""
function split_cells(σ, steps, per)
    dims = size(σ)
    bad = 0
    for c in 1:maximum(σ)
        idx = findall(==(c), σ)
        isempty(idx) && continue
        seen = Set([idx[1]]); st = [idx[1]]
        while !isempty(st)
            q = pop!(st)
            for o in steps
                y = ntuple(d -> q[d] + o[d], length(dims))
                y = ntuple(d -> per[d] ? mod1(y[d], dims[d]) : y[d], length(dims))
                p = CartesianIndex(y)
                checkbounds(Bool, σ, p) && σ[p] == c && !(p in seen) && (push!(seen, p); push!(st, p))
            end
        end
        bad += length(seen) < length(idx)
    end
    return bad
end
quiet(f) = @test_logs min_level = Base.CoreLogging.Warn f()
# no warning while painting

# ---------------------------------------------------------------------------------------------
# Case table (verbatim the pins script's cases.jl)
# ---------------------------------------------------------------------------------------------

# VoronoiBall cases: (name, n, radius, center (lattice indices, `nothing` = the lattice
# centre), kinds, iterations, target). Each runs for every seed in SEEDS.
const SEEDS = 1:4
voronoi_hex(dims; kw...) = Lattice(dims; geometry = Hexagonal(), kw...)
const CASES = [
    ("square 2D, closed, given centre", 40, 15.5, (20, 21), [:a, :b], 30, (40, 42)),
    ("square 2D, closed, lattice centre, no Lloyd", 25, 9.0, nothing, [1], 0, (30, 30)),
    ("square 2D, closed, 5 Lloyd steps, 3 kinds", 60, 12.3, nothing, [:x, :y, :z], 5, (30, 30)),
    ("square 2D, irrational radius (graner_glazier_aggregate's)", 50, sqrt(40 * 50 / π), (31.0, 31.0), Int32[1, 2], 30, (61, 61)),
    ("hex, closed", 150, 10.3, (10, 15), [:a], 30, voronoi_hex((30, 30); boundary = Closed())),
    ("3D, closed", 100, 8.2, nothing, [1], 30, (19, 19, 19)),
    ("square 2D, closed, ball cut by the lattice edge", 30, 12.0, (5, 20), [:a], 30, (40, 40)),
    (
        "square 2D, closed, ball cut by the domain", 30, 12.0, (20, 20), [:a], 30,
        Lattice((40, 40); boundary = Closed(), domain = x -> x[1] + x[2] <= 44),
    ),
    ("square 2D, periodic, interior ball", 30, 10.0, (20, 20), [:a, :b], 30, Lattice((40, 40))),
    ("hex, periodic, interior ball", 40, 8.0, (11, 15), [:a], 30, voronoi_hex((30, 30))),
    ("3D, periodic, interior ball", 60, 6.5, nothing, [1, 2], 30, Lattice((19, 19, 19))),
]
const NEW_EXPORTS = (:Voronoi, :RandomPoints, :Center, :HyperSphere, :Circle, :Sphere, :Point)
const NEW_PUBLIC = (:points, :layer_rng)
const GB_KEPT_OUT = (
    :Rect, :Rect2, :Rect3, :Vec, :Cylinder, :volume, :area, :direction, :origin, :radius,
    :widths, :centered,
)
"""The (module, name) pairs where a loaded module exports `name` bound to something else than `ref.name`."""
function clashes(ref::Module, names, mods = Base.loaded_modules_array())
    bad = Tuple{Module, Symbol}[]
    for m in mods, n in names
        (m === ref || m === Main) && continue
        isdefined(m, n) && Base.isexported(m, n) && getfield(m, n) !== getfield(ref, n) && push!(bad, (m, n))
    end
    return bad
end
module Clash                  # negative control for the clash check: a different `Center`
    export Center
    const Center = 1
end
# ---------------------------------------------------------------------------------------------
# Shapes: closed Cartesian membership, wrap, clipping (exercised through RandomPoints with
# n = every site of the region, so the drawn set IS the region)
# ---------------------------------------------------------------------------------------------
"""The set of Cartesian points of a region: draw all of its sites (n = m) and check n = m + 1 throws."""
function voronoi_region(region, target, m)
    pts = Potts.points(RandomPoints(m; region, seed = 7), target)
    @test_throws ArgumentError Potts.points(RandomPoints(m + 1; region, seed = 7), target)
    return Set(Tuple(p) for p in pts)
end
# ---------------------------------------------------------------------------------------------
# RandomPoints and Center()
# ---------------------------------------------------------------------------------------------
"""The documented draw rule, independently: region sites column-major, StableRNG(seed), redraw if taken."""
function voronoi_draws(sites, n, seed)
    rng = StableRNG(UInt64(seed))
    taken = falses(length(sites))
    out = eltype(sites)[]
    for _ in 1:n
        i = rand(rng, 1:length(sites))
        while taken[i]
            i = rand(rng, 1:length(sites))
        end
        taken[i] = true
        push!(out, sites[i])
    end
    return out
end
# ---------------------------------------------------------------------------------------------
# Voronoi reproduces VoronoiBall (Q3) and graner_glazier_aggregate
# ---------------------------------------------------------------------------------------------
function as_voronoi(n, r, c, kinds, it, target, seed; lloyd = it)
    dims, _, hex, _ = meta(target)
    ci = c === nothing ? map(d -> (d + 1) / 2, dims) : Float64.(Tuple(c))
    ball = HyperSphere(Point(cart(ci, hex)), Float64(r))
    return Voronoi(RandomPoints(n; region = ball, seed); region = ball, lloyd, kinds)
end
function nearest_image(x, gens, dims, per, hex)
    best, o, best_y = Inf, 0, Tuple(x)
    for (k, g) in enumerate(gens)
        for y in images(Tuple(x), dims, per)
            d = sum(abs2, cart(y, hex) .- Tuple(g))
            if d < best
                best, o, best_y = d, k, y
            end
        end
    end
    return o, best_y
end
function voronoi_oracle(gens, target, region_sites)
    dims, per, hex, _ = meta(target)
    σ = zeros(Int32, dims)
    for x in region_sites
        σ[x] = first(voronoi_nearest(Tuple(x), gens, dims, per, hex))
    end
    return σ
end
function lloyd_oracle(gens, target, region_sites, lloyd)
    dims, per, hex, _ = meta(target)
    cur = [Float64.(Tuple(g)) for g in gens]
    wrap(g, n, p) = p && !(0.5 <= g < n + 0.5) ? g - n * fld(g - 0.5, n) : g
    for _ in 1:lloyd
        sums = [zeros(length(dims)) for _ in eachindex(cur)]
        counts = zeros(Int, length(cur))
        for x in region_sites
            k, y = nearest_image(x, cur, dims, per, hex)
            counts[k] += 1
            for d in eachindex(dims)
                sums[k][d] += y[d]
            end
        end
        for k in eachindex(cur)
            counts[k] > 0 || continue
            idx_mean = ntuple(d -> wrap(sums[k][d] / counts[k], dims[d], per[d]), length(dims))
            cur[k] = cart(idx_mean, hex)
        end
    end
    return voronoi_oracle(cur, target, region_sites)
end
"""Share of painted sites whose nearest cell centroid (min image) is their own cell's (square lattice)."""
function own_centroid_share(σ, per)
    dims = size(σ)
    n = maximum(σ)
    cen = Vector{NTuple{length(dims), Float64}}(undef, n)
    for c in 1:n
        idx = findall(==(c), σ)
        x0 = Tuple(idx[1])
        unw = [
            ntuple(d -> per[d] ? x[d] - dims[d] * round((x[d] - x0[d]) / dims[d]) : Float64(x[d]), length(dims))
                for x in Tuple.(idx)
        ]
        cen[c] = ntuple(d -> sum(getindex.(unw, d)) / length(unw), length(dims))
    end
    sites = findall(!=(0), σ)
    near(x) = argmin(c -> minimum(y -> sum(abs2, y .- cen[c]), images(Tuple(x), dims, per)), 1:n)
    return count(x -> near(x) == σ[x], sites) / length(sites)
end
struct Clipper <: AbstractLayout
    clipped::Union{Nothing, Int}
end
function Potts.paint!(op::Potts.LayoutState, l::Clipper, lat)
    id = Potts.new_cell!(op, :c)
    Potts.assign!(op, (1:2, 1:2), id)
    if l.clipped === nothing
        Potts.record!(op; requested = 1, painted = 1)
    else
        Potts.record!(op; requested = 1, painted = 1, clipped = l.clipped)
    end
    return nothing
end
struct Silent <: AbstractLayout end
Potts.paint!(op::Potts.LayoutState, ::Silent, lat) = (Potts.assign!(op, (3:3, 3:3), Potts.new_cell!(op, :d)); nothing)
include(joinpath(@__DIR__, "..", "shared", "export_visible.jl"))
end

@testitem "voronoi shapes: surface (exports, public names, GeometryBasics bindings)" setup = [VoronoiShapesSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------------
    # Surface, names and dependencies
    # ---------------------------------------------------------------------------------------------
    @testset "voronoi shapes: surface (exports, public names, GeometryBasics bindings)" begin
        for n in NEW_EXPORTS                               # the opt-in layout vocabulary
            @test Base.isexported(Potts.Layouts, n)
        end
        for n in NEW_PUBLIC
            @test Base.ispublic(Potts, n) && !Base.isexported(Potts, n)
        end
        GB = parentmodule(HyperSphere)
        @test nameof(GB) === :GeometryBasics
        for n in (:HyperSphere, :Circle, :Sphere, :Point)
            @test getfield(Potts.Layouts, n) === getfield(GB, n)  # the same binding as GeometryBasics' (and Makie's)
        end
        @test Circle === HyperSphere{2} && Sphere === HyperSphere{3}
        for n in GB_KEPT_OUT                               # index boxes stay ranges; no clashing GB names
            @test !Base.isexported(Potts, n) && !Base.isexported(Potts.Layouts, n)
            @test !(isdefined(Potts, n) && isdefined(GB, n) && getfield(Potts, n) === getfield(GB, n))
        end
        # no package of the D-056 list (Makie, SciMLBase, ModelingToolkit, Graphs; plus Symbolics
        # and GeometryBasics), where loaded, exports a different binding under a new name; the
        # check bites. (DomainSets, loaded through ModelingToolkit, exports its own `Sphere` and
        # `Point`: a known clash for `using DomainSets` users, documented in D-138.)
        d056 = [
            m for m in Base.loaded_modules_array() if nameof(m) in
                (:Makie, :CairoMakie, :SciMLBase, :ModelingToolkit, :ModelingToolkitBase, :Graphs, :Symbolics, :GeometryBasics)
        ]
        @test length(d056) >= 3                                  # SciMLBase, ModelingToolkitBase, GeometryBasics at least
        @test isempty(clashes(Potts.Layouts, NEW_EXPORTS, d056))
        @test clashes(Potts.Layouts, (:Center,), [Clash]) == [(Clash, :Center)]
        # no DSL name: layouts are problem data (D-057)
        @test !any(n -> n in keys(Potts.DSL), (NEW_EXPORTS..., NEW_PUBLIC...))
        # VoronoiBall is gone (Q3: Voronoi reproduces it), with no alias (D-028)
        @test !isdefined(PottsModels, :VoronoiBall) && !isdefined(Potts, :VoronoiBall)
        @test Base.isexported(PottsModels, :graner_glazier_aggregate)
    end
end

@testitem "voronoi shapes: StableRNGs leaves PottsModels; GeometryBasics is Potts's only" setup = [VoronoiShapesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "voronoi shapes: StableRNGs leaves PottsModels; GeometryBasics is Potts's only" begin
        root = pkgdir(Potts)
        pm = TOML.parsefile(joinpath(pkgdir(PottsModels), "Project.toml"))
        @test !haskey(pm["deps"], "StableRNGs") && !haskey(get(pm, "compat", Dict()), "StableRNGs")
        @test !isdefined(PottsModels, :StableRNG) && !isdefined(PottsModels, :StableRNGs)
        pr = TOML.parsefile(joinpath(root, "Project.toml"))
        @test haskey(pr["deps"], "StableRNGs") && haskey(pr["deps"], "GeometryBasics") && haskey(pr["compat"], "GeometryBasics")
        cp = TOML.parsefile(joinpath(root, "lib", "CorePotts", "Project.toml"))
        @test !haskey(cp["deps"], "GeometryBasics")
        # no PottsModels source names StableRNG(s) (docstrings and comments may)
        names = Set{Symbol}()
        function walk(ex)
            if ex isa Symbol
                return push!(names, ex)
            elseif ex isa Expr
                return foreach(walk, ex.args)
            else
                return nothing
            end
        end
        srcs = String[]
        for (dir, _, fs) in walkdir(joinpath(pkgdir(PottsModels), "src")), f in fs
            endswith(f, ".jl") && push!(srcs, joinpath(dir, f))
        end
        @test length(srcs) >= 5
        foreach(f -> walk(Meta.parseall(read(f, String))), srcs)
        @test :akeeb_state in names                               # the scan sees the sources
        @test !(:StableRNG in names) && !(:StableRNGs in names)
        @test :StableRNG in (walk(Meta.parseall("rng = StableRNG(1)")); names)   # … and would see a use
    end
end

@testitem "voronoi shapes: layer_rng and the Akeeb clocks" setup = [VoronoiShapesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "voronoi shapes: layer_rng and the Akeeb clocks" begin
        for s in (0, 1, 0x05cd2609, typemax(UInt64))
            @test rand(Potts.layer_rng(s), 5) == rand(StableRNG(UInt64(s)), 5)
            @test Potts.layer_rng(s) isa StableRNG
            @test rand(Potts.layer_rng(s, :clock), 5) == rand(StableRNG(Potts._substream_seed(s, :clock)), 5)
            @test rand(Potts.layer_rng(s, :clock), 5) != rand(Potts.layer_rng(s), 5)
            @test rand(Potts.layer_rng(s, "clock"), 5) == rand(Potts.layer_rng(s, :clock), 5)
        end
        @test rand(Potts.layer_rng(1), 5) != rand(Potts.layer_rng(2), 5)
        @test_throws ArgumentError Potts.layer_rng(-1)
        @test_throws ArgumentError Potts.layer_rng(-1, :clock)
        # akeeb_state's clock column is a draw from that seed's :clock stream: other seeds differ
        clocks = [
            only(p.second for p in akeeb_state(; lattice = (99, 60), seed, pp = 0.5) if isequal(p.first, :clock))
                for seed in 1:2
        ]
        @test clocks[1] != clocks[2]
    end
end

@testitem "voronoi shapes: closed membership in Cartesian coordinates" setup = [VoronoiShapesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "voronoi shapes: closed membership in Cartesian coordinates" begin
        c2 = Point(10.0, 10.0)
        # r = 3 on the square lattice. Lattice points with dx² + dy² ≤ 9: dx = 0: 7; dx = ±1: 2·5;
        # dx = ±2: 2·5; dx = ±3: 2·1 → 29. An open or half-open rule drops the 4 axis points
        # at distance exactly 3 → 25.
        disk = voronoi_region(Circle(c2, 3.0), (20, 20), 29)
        @test length(disk) == 29 && (13.0, 10.0) in disk && (10.0, 7.0) in disk && !((12.0, 13.0) in disk)
        @test Set(Tuple(Float64.(Tuple(x))) for x in ballsites((10.0, 10.0), 3.0, (20, 20))) == disk
        # 3D, r = 2: 1 + 6 (|v|² = 1) + 12 (2) + 8 (3) + 6 (4) = 33
        ball = voronoi_region(Sphere(Point(5.0, 5.0, 5.0), 2.0), (9, 9, 9), 33)
        @test (7.0, 5.0, 5.0) in ball && !((6.0, 6.0, 7.0) in ball)
        # hexagonal: round in the embedding. |embed(dq, dr)|² = dq² + dq·dr + dr²: 1 for the 6
        # neighbours, 3 for the next 6, 4 beyond. Centre (10, 10) is Cartesian (15, 5√3).
        hexl = Lattice((20, 20); geometry = Hexagonal(), boundary = Closed())
        hc = Point(15.0, 10 * sqrt(3) / 2)
        h1 = voronoi_region(Circle(hc, 1.5), hexl, 7)        # centre + 6 neighbours
        h2 = voronoi_region(Circle(hc, 1.8), hexl, 13)       # + the 6 at distance √3
        @test issubset(h1, h2)
        @test Set(Tuple(cart(Tuple(x), true)) for x in ballsites(Tuple(hc), 1.8, hexl)) == h2
        # in axial indices the same radius would be a different set (control: the embedding matters)
        @test length(ballsites((10.0, 10.0), 1.8, (20, 20))) != 13
    end
end

@testitem "voronoi shapes: shapes clip at closed edges and the domain, wrap through periodic ones" setup = [VoronoiShapesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "voronoi shapes: shapes clip at closed edges and the domain, wrap through periodic ones" begin
        # quarter disk at the corner: dx, dy ≥ 0 of the 29: 4 + 3 + 3 + 1 = 11
        corner = Circle(Point(1.0, 1.0), 3.0)
        @test length(voronoi_region(corner, (20, 20), 11)) == 11
        # periodic on both axes: the whole disk, wrapped (29 sites, some at x or y near 20)
        wr = voronoi_region(corner, Lattice((20, 20)), 29)
        @test (19.0, 1.0) in wr && (20.0, 20.0) in wr && (1.0, 18.0) in wr
        # periodic in x only: dy ≥ 0 half of the 29: dx = 0: 4, ±1: 2·3, ±2: 2·3, ±3: 2·1 → 18
        @test length(voronoi_region(corner, Lattice((20, 20); boundary = (Periodic(), Closed())), 18)) == 18
        # the domain x ≤ 10 keeps dx ≤ 0 of the disk at (10, 10): 7 + 5 + 5 + 1 = 18
        dom = Lattice((20, 20); boundary = Closed(), domain = x -> x[1] <= 10)
        @test all(p -> p[1] <= 10, voronoi_region(Circle(Point(10.0, 10.0), 3.0), dom, 18))
        # a shape with no site on the lattice
        @test_throws ArgumentError Potts.points(RandomPoints(1; region = Circle(Point(-50.0, -50.0), 1.0), seed = 1), (20, 20))
        # a shape of the wrong dimension
        @test_throws ArgumentError Potts.points(RandomPoints(1; region = Sphere(Point(5.0, 5.0, 5.0), 2.0), seed = 1), (20, 20))
    end
end

@testitem "voronoi shapes: RandomPoints draws distinct in-domain region sites (VoronoiBall's rule)" setup = [VoronoiShapesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "voronoi shapes: RandomPoints draws distinct in-domain region sites (VoronoiBall's rule)" begin
        cases = [
            ((30, 30), Circle(Point(15.0, 14.0), 9.0), 40, false),
            ((30, 30), (5:20, 3:9), 25, false),
            ((30, 30), nothing, 50, false),
            (voronoi_hex((24, 24); boundary = Closed()), Circle(Point(18.0, 10.0), 6.0), 30, true),
            ((12, 12, 12), Sphere(Point(6.0, 6.5, 6.0), 4.0), 60, false),
            (Lattice((30, 30); boundary = Closed(), domain = x -> (x[1] - 15)^2 + (x[2] - 15)^2 <= 100), nothing, 40, false),
            (Lattice((30, 30)), Circle(Point(2.0, 29.0), 5.0), 30, false),      # wraps
        ]
        for (target, region, n, hex) in cases, seed in (1, 2, 99)
            dims, per, _, mask = meta(target)
            sites = if region === nothing
                [x for x in CartesianIndices(dims) if mask === nothing || mask[x]]
            elseif region isa Tuple
                [x for x in CartesianIndices(region) if mask === nothing || mask[x]]
            else
                ballsites(Tuple(region.center), region.r, target)
            end
            pts = Potts.points(RandomPoints(n; region, seed), target)
            @test pts isa Vector{<:Point} && eltype(pts) === Point{length(dims), Float64}
            @test [Tuple(p) for p in pts] == [cart(Tuple(x), hex) for x in voronoi_draws(sites, n, seed)]
            @test allunique(pts)
            @test Potts.points(RandomPoints(n; region, seed), target) == pts                # deterministic
        end
        t = (30, 30)
        @test Potts.points(RandomPoints(10; seed = 1), t) != Potts.points(RandomPoints(10; seed = 2), t)
        @test Potts.points(remake(RandomPoints(10; seed = 1); seed = 2), t) == Potts.points(RandomPoints(10; seed = 2), t)
        @test isempty(Potts.points(RandomPoints(0; seed = 1), t))
        @test_throws ArgumentError RandomPoints(-1; seed = 1)
        @test_throws ArgumentError RandomPoints(3; seed = -1)
        @test_throws ArgumentError Potts.points(RandomPoints(901; seed = 1), t)            # 900 sites
        @test length(Potts.points(RandomPoints(900; seed = 1), t)) == 900
    end
end

@testitem "voronoi shapes: Center is the lattice centre (Cartesian)" setup = [VoronoiShapesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "voronoi shapes: Center() is the lattice centre (Cartesian)" begin
        @test Potts.points(Center(), (40, 42)) == [Point(20.5, 21.5)]
        @test Potts.points(Center(), (19, 19, 19)) == [Point(10.0, 10.0, 10.0)]
        hx = only(Potts.points(Center(), voronoi_hex((30, 30))))
        @test all(isapprox.(Tuple(hx), (15.5 + 15.5 / 2, 15.5 * sqrt(3) / 2); atol = 1.0e-12))
        @test Potts.points([Center(), Point(1.0, 2.0)], (10, 10)) == [Point(5.5, 5.5), Point(1.0, 2.0)]
    end
end

@testitem "voronoi shapes: Voronoi over a ball paints every requested cell" setup = [VoronoiShapesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "voronoi shapes: Voronoi over a ball paints every requested cell" begin
        for (name, n, r, c, kinds, it, target) in CASES, seed in SEEDS
            op, rep = layout(as_voronoi(n, r, c, kinds, it, target, seed), target; report = true)
            @test only(rep).type === :Voronoi && only(rep).requested == n && only(rep).painted == n && only(rep).dropped == 0
        end
        # the layout follows the seed, and Lloyd steps match the hand-recomputed centroid oracle
        (name, n, r, c, kinds, it, target) = CASES[1]
        dig(seed; kw...) = digest(voronoi_σ(layout(as_voronoi(n, r, c, kinds, it, target, seed; kw...), target)))
        @test dig(1) == dig(1) && dig(1) != dig(2)
        if it != 0
            dims, _, hex, _ = meta(target)
            ci = c === nothing ? map(d -> (d + 1) / 2, dims) : Float64.(Tuple(c))
            gens = Potts.points(as_voronoi(n, r, c, kinds, it, target, 1).points, target)
            sites = ballsites(cart(ci, hex), Float64(r), target)
            @test voronoi_σ(layout(as_voronoi(n, r, c, kinds, it, target, 1), target)) ==
                lloyd_oracle(gens, target, sites, it)
            @test dig(1; lloyd = 0) != dig(1)
        end
        # explicit closed and periodic Lloyd geometric oracle (1 and 3 iterations)
        P = Point
        for (target, gens) in (
                    ((20, 16), [P(3.0, 4.0), P(16.0, 5.0), P(8.0, 13.0), P(17.0, 14.0)]),
                    (Lattice((20, 16)), [P(2.0, 3.0), P(11.0, 9.0), P(19.0, 14.0)]),
                ), lloyd in (1, 3)
            dims, per, _, _ = meta(target)
            oracle = lloyd_oracle(gens, target, CartesianIndices(dims), lloyd)
            @test split_cells(oracle, SQ2, per) == 0
            @test voronoi_σ(layout(Voronoi(gens; lloyd, kinds = [:a]), target)) == oracle
        end
    end
end

@testitem "voronoi shapes: nearest generator, minimum image, ties to the lowest (2D, 3D, periodic)" setup = [VoronoiShapesSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------------
    # Voronoi against a brute-force oracle (lloyd = 0, explicit generators)
    # ---------------------------------------------------------------------------------------------
    @testset "voronoi shapes: nearest generator, minimum image, ties to the lowest (2D, 3D, periodic)" begin
        P = Point
        fixtures = [
            ("square closed", (20, 16), [P(4.0, 4.0), P(15.0, 5.0), P(9.0, 12.0), P(17.0, 14.0)], SQ2),
            ("square periodic", Lattice((20, 16)), [P(2.0, 3.0), P(11.0, 9.0), P(19.0, 14.0)], SQ2),
            ("square periodic x", Lattice((20, 16); boundary = (Periodic(), Closed())), [P(2.0, 3.0), P(11.0, 9.0), P(19.0, 14.0)], SQ2),
            ("3D closed", (8, 8, 8), [P(2.0, 2.0, 2.0), P(7.0, 3.0, 5.0), P(4.0, 7.0, 7.0)], CUBE),
            ("3D periodic", Lattice((8, 8, 8)), [P(1.0, 1.0, 1.0), P(5.0, 4.0, 6.0)], CUBE),
        ]
        for (label, target, gens, steps) in fixtures
            dims, per, _, _ = meta(target)
            oracle = voronoi_oracle(gens, target, CartesianIndices(dims))
            @test split_cells(oracle, steps, per) == 0          # fixture: no repair needed
            op, rep = layout(Voronoi(gens; kinds = [:a]), target; report = true)
            @test voronoi_σ(op) == oracle
            @test only(rep).clipped == 0 && only(rep).painted == length(gens)
            if any(per)          # negative control: ignoring the wrap gives another tessellation
                @test voronoi_oracle(gens, dims, CartesianIndices(dims)) != oracle
            end
        end
        # ties: with generators (3, 5) and (7, 5) the column x = 5 is equidistant; it goes to the
        # lower generator, whichever order they are given in
        σ1 = voronoi_σ(layout(Voronoi([P(3.0, 5.0), P(7.0, 5.0)]; kinds = [:a]), (9, 9)))
        σ2 = voronoi_σ(layout(Voronoi([P(7.0, 5.0), P(3.0, 5.0)]; kinds = [:a]), (9, 9)))
        @test all(==(1), σ1[1:5, :]) && all(==(2), σ1[6:9, :])
        @test all(==(2), σ2[1:4, :]) && all(==(1), σ2[5:9, :])
    end
end

@testitem "voronoi shapes: hexagonal Voronoi is nearest in the embedding" setup = [VoronoiShapesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "voronoi shapes: hexagonal Voronoi is nearest in the embedding" begin
        hexl = voronoi_hex((16, 16); boundary = Closed())
        hexp = voronoi_hex((16, 16))
        gens = [Point(6.3, 3.1), Point(17.0, 4.2), Point(12.2, 10.9), Point(20.6, 12.0)]
        for target in (hexl, hexp)
            dims, per, _, _ = meta(target)
            σ = voronoi_σ(layout(Voronoi(gens; kinds = [:a]), target))
            @test all(x -> σ[x] > 0, CartesianIndices(dims))
            # assigned generator is a nearest one (up to rounding)
            @test all(
                x -> (
                    d = voronoi_nearest(Tuple(x), [gens[σ[x]]], dims, per, true)[2];
                    d <= voronoi_nearest(Tuple(x), gens, dims, per, true)[2] + 1.0e-9
                ), CartesianIndices(dims)
            )
            @test split_cells(σ, HEX1, per) == 0
        end
        # control: the axial-index tessellation differs (the embedding matters)
        @test voronoi_σ(layout(Voronoi(gens; kinds = [:a]), hexl)) != voronoi_oracle(gens, (16, 16), CartesianIndices((16, 16)))
    end
end

@testitem "voronoi shapes: every cell is one piece (2D, hex, 3D; closed and periodic)" setup = [VoronoiShapesSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------------
    # Lloyd and connectivity
    # ---------------------------------------------------------------------------------------------
    @testset "voronoi shapes: every cell is one piece (2D, hex, 3D; closed and periodic)" begin
        sq = Circle(Point(12.5, 12.5), 10.3)
        hb = Circle(Point(cart((10, 15), true)), 10.3)
        cb = Sphere(Point(10.0, 10.0, 10.0), 8.2)
        cases = [
            ((24, 24), sq, 60, SQ2),
            (voronoi_hex((30, 30); boundary = Closed()), hb, 150, HEX1),
            ((19, 19, 19), cb, 100, CUBE),
            (Lattice((24, 24)), nothing, 40, SQ2),
            (voronoi_hex((20, 20)), nothing, 40, HEX1),
        ]
        for (target, region, n, steps) in cases
            dims, per, hex, _ = meta(target)
            raw_split = 0
            for seed in 1:30
                σ = voronoi_σ(layout(Voronoi(RandomPoints(n; region, seed); region, kinds = [:a]), target))
                @test split_cells(σ, steps, per) == 0
                # the plain nearest-generator labelling is not always one piece, so the repair is tested
                gens = Potts.points(RandomPoints(n; region, seed), target)
                sites = findall(!=(0), σ)
                raw_split += split_cells(voronoi_oracle(gens, target, sites), steps, per) > 0
            end
            @test raw_split >= 1
        end
    end
end

@testitem "voronoi shapes: Lloyd moves generators to centroids (closed and through the wrap)" setup = [VoronoiShapesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "voronoi shapes: Lloyd moves generators to centroids (closed and through the wrap)" begin
        for target in ((30, 30), Lattice((30, 30)))
            dims, per, _, _ = meta(target)
            s0 = s30 = 0.0
            straddle = 0
            for seed in 1:6
                v(k) = Voronoi(RandomPoints(15; seed); lloyd = k, kinds = [:a])
                σ30 = voronoi_σ(layout(v(30), target))
                s0 += own_centroid_share(voronoi_σ(layout(v(0), target)), per) / 6
                s30 += own_centroid_share(σ30, per) / 6
                straddle += split_cells(σ30, SQ2, map(_ -> false, dims)) > 0
            end
            @test s30 > 0.99                 # centroidal (a Lloyd step that ignores the wrap: ≈ 0.96 when written)
            @test s30 > s0 + 0.05            # and Lloyd is what made it so (s0 ≈ 0.84)
            any(per) && @test straddle >= 1  # cells do cross the periodic edges (the wrap is exercised)
        end
    end
end

@testitem "voronoi shapes: Voronoi fills medium only (an earlier layer is never cut)" setup = [VoronoiShapesSetup] tags = [:pottsmodels, :acceptance] begin
    # ---------------------------------------------------------------------------------------------
    # Composition, report, clipped, kinds, errors, remake
    # ---------------------------------------------------------------------------------------------
    @testset "voronoi shapes: Voronoi fills medium only (an earlier layer is never cut)" begin
        disk = Circle(Point(10.5, 10.5), 8.0)
        block = Tiling((4, 4); region = (9:12, 9:12), kinds = [:block])
        vor = Voronoi(RandomPoints(10; region = disk, seed = 1); region = disk, kinds = [:v])
        op, rep = quiet(() -> layout(overlay(block, vor), (20, 20); report = true))
        σ, k = voronoi_σ(op), voronoi_kinds(op)
        disk_sites = Set(ballsites((10.5, 10.5), 8.0, (20, 20)))
        @test all(==(1), σ[9:12, 9:12]) && k[1] === :block && count(==(1), σ) == 16
        @test Set(findall(>(1), σ)) == setdiff(disk_sites, Set(CartesianIndices((9:12, 9:12))))
        @test rep[2].type === :Voronoi && rep[2].splits == 0 && rep[1].splits == 0
        # control: alone, the Voronoi covers the block's sites
        alone = voronoi_σ(layout(vor, (20, 20)))
        @test all(>(0), alone[9:12, 9:12])
    end
end

@testitem "voronoi shapes: report rows carry clipped" setup = [VoronoiShapesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "voronoi shapes: report rows carry clipped" begin
        P = Point
        corner = Circle(P(1.0, 1.0), 3.0)
        g2 = [P(1.0, 1.0), P(3.0, 2.0)]
        r(l, t) = only(last(layout(l, t; report = true)))
        # closed corner: 29 disk points, 11 on the lattice → 18 clipped
        row = r(Voronoi(g2; region = corner, kinds = [:a]), (20, 20))
        @test (row.type, row.requested, row.painted, row.dropped, row.misses, row.counted, row.clipped, row.splits) ==
            (:Voronoi, 2, 2, 0, 0, 2, 18, 0)
        # periodic: the disk wraps, nothing is clipped, all 29 sites painted
        op, rep = layout(Voronoi(g2; region = corner, kinds = [:a]), Lattice((20, 20)); report = true)
        @test only(rep).clipped == 0 && count(!=(0), voronoi_σ(op)) == 29
        # domain x ≤ 10 at (10, 10): 18 of 29 in the domain → 11 clipped
        dom = Lattice((20, 20); boundary = Closed(), domain = x -> x[1] <= 10)
        @test r(Voronoi([P(9.0, 10.0)]; region = Circle(P(10.0, 10.0), 3.0), kinds = [:a]), dom).clipped == 11
        # hex corner, r = 1.8 at index (1, 1): 13 points (|v|² ∈ {0, 1, 3}); offsets with
        # dq, dr ≥ 0 on the lattice: (0,0), (1,0), (0,1), (1,1) → 4 painted, 9 clipped
        hexl = voronoi_hex((20, 20); boundary = Closed())
        hc = Circle(P(cart((1, 1), true)), 1.8)
        op, rep = layout(Voronoi([P(cart((1, 1), true))]; region = hc, kinds = [:a]), hexl; report = true)
        @test only(rep).clipped == 9 && count(!=(0), voronoi_σ(op)) == 4
        # 3D corner, r = 2 at (1, 1, 1): offsets ≥ 0 of the 33: 1 + 3 + 3 + 1 + 3 = 11 → 22 clipped
        op, rep = layout(Voronoi([P(1.0, 1.0, 1.0)]; region = Sphere(P(1.0, 1.0, 1.0), 2.0), kinds = [:a]), (9, 9, 9); report = true)
        @test only(rep).clipped == 22 && count(!=(0), voronoi_σ(op)) == 11
        # a shape inside the lattice clips nothing
        @test r(Voronoi(g2; region = Circle(P(10.0, 10.0), 3.0), kinds = [:a]), (20, 20)).clipped == 0
        # a generator with no site is dropped: every site of the small disk is nearer (1, 1)
        row = r(Voronoi([P(1.0, 1.0), P(15.0, 15.0)]; region = Circle(P(3.0, 3.0), 2.0), kinds = [:a]), (20, 20))
        @test (row.requested, row.painted, row.dropped) == (2, 2, 1)
        # the other built-in layers report clipped = 0
        rows = last(
            layout(
                overlay(
                    Tiling((3, 3); region = (1:9, 1:9), kinds = [:t]),
                    Scattered(2, (2, 2); region = (12:19, 12:19), kinds = [:s], seed = 1),
                    Frame(:w), InsertUntil(:i; into = [:t], number = 2, seed = 1)
                ), (20, 20); report = true
            )
        )
        @test [x.type for x in rows] == [:Tiling, :Scattered, :Frame, :InsertUntil]
        @test all(x -> x.clipped == 0, rows)
    end
end

@testitem "voronoi shapes: record!(…; clipped) for a custom layer" setup = [VoronoiShapesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "voronoi shapes: record!(…; clipped) for a custom layer" begin
        rows = last(layout(overlay(Clipper(3), Clipper(nothing), Silent()), (6, 6); report = true))
        @test [x.clipped for x in rows] == [3, 0, 0]
    end
end

@testitem "voronoi shapes: kinds, ids, Center generators" setup = [VoronoiShapesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "voronoi shapes: kinds, ids, Center() generators" begin
        P = Point
        gens = [P(2.0, 2.0), P(18.0, 2.0), P(10.0, 18.0)]
        op = layout(Voronoi(gens; kinds = [:a, :b]), (20, 20))
        σ = voronoi_σ(op)
        @test voronoi_kinds(op) == [:a, :b, :a]
        @test σ[2, 2] == 1 && σ[18, 2] == 2 && σ[10, 18] == 3          # ids in generator order
        # Center() as a generator: one cell at the lattice centre owns a disk around it
        disk = Circle(P(10.5, 10.5), 4.0)
        σc = voronoi_σ(layout(Voronoi([Center(), P(1.0, 1.0)]; region = disk, kinds = [:c]), (20, 20)))
        @test σc[10, 10] == 1 && σc[11, 11] == 1 && count(==(1), σc) == length(ballsites((10.5, 10.5), 4.0, (20, 20)))
        @test voronoi_σ(layout(Voronoi(Center(); region = disk, kinds = [:c]), (20, 20))) == σc
        # a tuple-of-ranges region still means an index box
        σb = voronoi_σ(layout(Voronoi(gens; region = (3:12, 4:9), kinds = [:a]), (20, 20)))
        @test findall(!=(0), σb) == vec(collect(CartesianIndices((3:12, 4:9))))
    end
end

@testitem "voronoi shapes: errors and remake" setup = [VoronoiShapesSetup] tags = [:pottsmodels, :acceptance] begin
    @testset "voronoi shapes: errors and remake" begin
        P = Point
        g = [P(2.0, 2.0), P(8.0, 8.0)]
        @test_throws ArgumentError Voronoi(g; lloyd = -1, kinds = [:a])
        @test_throws ArgumentError Voronoi(g; kinds = Symbol[])
        @test_throws ArgumentError Voronoi(g; kinds = [:a], splits = :bogus)
        @test Voronoi(g; kinds = [:a], splits = :allow) isa AbstractLayout
        @test_throws ArgumentError layout(Voronoi(P{2, Float64}[]; kinds = [:a]), (10, 10))           # no generator
        @test_throws ArgumentError layout(Voronoi([P(1.0, 2.0, 3.0)]; kinds = [:a]), (10, 10))        # 3D point, 2D lattice
        @test_throws ArgumentError layout(Voronoi(g; region = Sphere(P(5.0, 5.0, 5.0), 2.0), kinds = [:a]), (10, 10))
        # 29 sites < 200
        @test_throws ArgumentError layout(
            Voronoi(RandomPoints(200; region = Circle(P(5.0, 5.0), 3.0), seed = 1); kinds = [:a]), (10, 10)
        )
        v = Voronoi(RandomPoints(12; seed = 3); kinds = [:a, :b])
        @test voronoi_σ(layout(remake(v; lloyd = 5), (20, 20))) == voronoi_σ(layout(Voronoi(RandomPoints(12; seed = 3); lloyd = 5, kinds = [:a, :b]), (20, 20)))
        @test voronoi_σ(layout(remake(v; lloyd = 5), (20, 20))) != voronoi_σ(layout(v, (20, 20)))
        @test_throws ArgumentError remake(v; lloyd = -1)
        @test voronoi_σ(layout(remake(v; points = RandomPoints(12; seed = 4)), (20, 20))) ==
            voronoi_σ(layout(Voronoi(RandomPoints(12; seed = 4); kinds = [:a, :b]), (20, 20)))
    end
end

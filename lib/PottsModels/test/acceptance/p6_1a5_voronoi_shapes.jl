# P6.1a5 (ROADMAP Phase 6, step 1; research/initial-state-review.md §2 S2, §3 Q1/Q3/Q5;
# D-056, D-057, D-063, D-091, D-093, D-094): `VoronoiBall` becomes the core layer `Voronoi`
# over the first initial-state vocabulary (`Sphere`/`Circle`/`HyperSphere`, `Point`,
# `RandomPoints`, `Center()`), shape layers clip to the domain and report `clipped`, and
# StableRNGs leaves PottsModels. Frozen (AUTONOMY §7.3); decision D-138.
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
#       works. (`replace` is P6.3c's.)
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
#       names `StableRNG`. Frozen files that called `PottsModels.StableRNG` are re-frozen
#       under D-138 to import it from StableRNGs in the test environment (p6_0w, p6_1a6,
#       p6_2a2), and p6_1a6's VoronoiBall check names `Voronoi`.
#   No DSL name or keyword is added: layouts are problem data (D-057).
#
# Expected values. The P61A5_PINS / P61A5_GG_PINS / P61A5_AKEEB_PINS digests were computed at
# 8eb9d210 (the tree before this item) by the test author's scratch script pins_today.jl,
# which includes the case table below verbatim: SHA-256 of σ's little-endian Int32 bytes (as in
# p6_1a6), SHA-256 of the kinds joined by ',', and the number of painted sites. The hand
# counts (29 / 25 / 11 / 18 / 33 / 13 / 4 / 11 / 22 ...) are derived in the comments where
# they are used.
using Potts: CorePotts
using SHA: sha256
using StableRNGs: StableRNG
using TOML: TOML

# ---------------------------------------------------------------------------------------------
# Helpers (independent of the code under test)
# ---------------------------------------------------------------------------------------------

p61a5_σ(op) = op[1].second
p61a5_kinds(op) = op[2].second
p61a5_digest(σ) = bytes2hex(sha256(reinterpret(UInt8, vec(htol.(σ)))))
p61a5_kdigest(k) = bytes2hex(sha256(join(string.(k), ',')))

# (dims, periodic flags, hexagonal?, domain mask or nothing) of a layout target
p61a5_meta(dims::Tuple) = (dims, map(_ -> false, dims), false, nothing)
p61a5_meta(l::Lattice) = (l.dims, l.periodic, l.geometry isa Hexagonal, l.mask)
p61a5_cart(x, hex) = hex ? (x[1] + x[2] / 2, x[2] * sqrt(3) / 2) : Float64.(Tuple(x))
p61a5_indomain(mask, x) = all(d -> 1 <= x[d], eachindex(x)) && (mask === nothing || mask[x...])

# the images of index point x along periodic axes (k ∈ -1:1 suffices for the small shapes here)
p61a5_images(x, dims, per) = [ntuple(d -> x[d] + k[d] * dims[d], length(dims))
                              for k in Iterators.product(ntuple(d -> per[d] ? (-1:1) : (0:0), length(dims))...)]
# closed ball membership in Cartesian coordinates, any periodic image
p61a5_inball(x, c, r, dims, per, hex) = any(y -> sqrt(sum(abs2, p61a5_cart(y, hex) .- c)) <= r, p61a5_images(x, dims, per))
p61a5_ballsites(c, r, target) = (m = p61a5_meta(target);
    [x for x in CartesianIndices(m[1]) if (m[4] === nothing || m[4][x]) && p61a5_inball(Tuple(x), c, r, m[1], m[2], m[3])])

# nearest generator (Cartesian generators g), minimum image, ties to the lowest index
function p61a5_nearest(x, gens, dims, per, hex)
    best, o = Inf, 0
    for (k, g) in enumerate(gens)
        d = minimum(y -> sum(abs2, p61a5_cart(y, hex) .- Tuple(g)), p61a5_images(Tuple(x), dims, per))
        d < best && (best = d; o = k)
    end
    return o, best
end

const P61A5_SQ2 = ((1, 0), (-1, 0), (0, 1), (0, -1))
const P61A5_HEX1 = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, -1), (-1, 1))
const P61A5_CUBE = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))
"""Cells of σ that are not one piece under the index steps (wrapping along `per`)."""
function p61a5_split_cells(σ, steps, per)
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
p61a5_quiet(f) = @test_logs min_level = Base.CoreLogging.Warn f()   # no warning while painting

# ---------------------------------------------------------------------------------------------
# Case table (verbatim the pins script's cases.jl)
# ---------------------------------------------------------------------------------------------

# VoronoiBall cases: (name, n, radius, center (lattice indices, `nothing` = the lattice
# centre), kinds, iterations, target). Each runs for every seed in P61A5_SEEDS.
const P61A5_SEEDS = 1:4
p61a5_hex(dims; kw...) = Lattice(dims; geometry = Hexagonal(), kw...)
const P61A5_CASES = [
    ("square 2D, closed, given centre", 40, 15.5, (20, 21), [:a, :b], 30, (40, 42)),
    ("square 2D, closed, lattice centre, no Lloyd", 25, 9.0, nothing, [1], 0, (30, 30)),
    ("square 2D, closed, 5 Lloyd steps, 3 kinds", 60, 12.3, nothing, [:x, :y, :z], 5, (30, 30)),
    ("square 2D, irrational radius (graner_glazier_aggregate's)", 50, sqrt(40 * 50 / π), (31.0, 31.0), Int32[1, 2], 30, (61, 61)),
    ("hex, closed", 150, 10.3, (10, 15), [:a], 30, p61a5_hex((30, 30); boundary = Closed())),
    ("3D, closed", 100, 8.2, nothing, [1], 30, (19, 19, 19)),
    ("square 2D, closed, ball cut by the lattice edge", 30, 12.0, (5, 20), [:a], 30, (40, 40)),
    ("square 2D, closed, ball cut by the domain", 30, 12.0, (20, 20), [:a], 30,
        Lattice((40, 40); boundary = Closed(), domain = x -> x[1] + x[2] <= 44)),
    ("square 2D, periodic, interior ball", 30, 10.0, (20, 20), [:a, :b], 30, Lattice((40, 40))),
    ("hex, periodic, interior ball", 40, 8.0, (11, 15), [:a], 30, p61a5_hex((30, 30))),
    ("3D, periodic, interior ball", 60, 6.5, nothing, [1, 2], 30, Lattice((19, 19, 19))),
]
# graner_glazier_aggregate(n; seed, margin) cases (it was built on VoronoiBall)
const P61A5_GG = [(50, s, 60) for s in 1:4]
append!(P61A5_GG, [(200, 1, 60), (200, 2, 60), (200, 1, 10), (1000, 1, 60)])

# ---------------------------------------------------------------------------------------------
# Pins at 8eb9d210: (case, seed) => (σ digest, kinds digest, painted sites)
# ---------------------------------------------------------------------------------------------

const P61A5_PINS = Dict(
    ("square 2D, closed, given centre", 1) => ("e308508ea128b382b4b41e473da932adfe2eca8ecbae9c5ea03744c239e69bf8", "575b5afcb43d5e79689f11bedc84c9111be69a17f22576f6c0f33eecef18a701", 749),
    ("square 2D, closed, given centre", 2) => ("cd7d81ee14f1a11414111de5f2c56f76528da0a6229cb5dc9dcd9c15c5774d93", "575b5afcb43d5e79689f11bedc84c9111be69a17f22576f6c0f33eecef18a701", 749),
    ("square 2D, closed, given centre", 3) => ("e93e8bfa38375e80bf0002cedde4f4d05c783a17fbe49061cf5702e3ddf75573", "575b5afcb43d5e79689f11bedc84c9111be69a17f22576f6c0f33eecef18a701", 749),
    ("square 2D, closed, given centre", 4) => ("dd0d7e1481339275e26843c020d3646f9236d3a89b4b19c77fe6254f6eb14ae2", "575b5afcb43d5e79689f11bedc84c9111be69a17f22576f6c0f33eecef18a701", 749),
    ("square 2D, closed, lattice centre, no Lloyd", 1) => ("d063b3f46afbac728473720954db4de0ad13211925fc7903ced7a0e3efbda178", "ad068e74fd415756c9a6a4feba7425375a32dc428cd0be9509d3069835e6505a", 256),
    ("square 2D, closed, lattice centre, no Lloyd", 2) => ("65a8dc524ae7ef6fcdbddca531a6791b0dc18aaf348246c1ce35e86f82d92662", "ad068e74fd415756c9a6a4feba7425375a32dc428cd0be9509d3069835e6505a", 256),
    ("square 2D, closed, lattice centre, no Lloyd", 3) => ("e43f4825243a4227a53b8339e27d0240591033a7e9bbbe58e93dcefb171f10a6", "ad068e74fd415756c9a6a4feba7425375a32dc428cd0be9509d3069835e6505a", 256),
    ("square 2D, closed, lattice centre, no Lloyd", 4) => ("f6111fb63bc7ae80d9972c0a1e715ea717934a0acc4760ba52244bd18c9836e5", "ad068e74fd415756c9a6a4feba7425375a32dc428cd0be9509d3069835e6505a", 256),
    ("square 2D, closed, 5 Lloyd steps, 3 kinds", 1) => ("df22cf2eef04526c6b3ae27eb7a06253aac5929927409abc30a85f4d3c6b0b96", "c3685551b78e3e28396a4473e7aacf3c4eedf5bc97c45c9512503daf7b607bfb", 468),
    ("square 2D, closed, 5 Lloyd steps, 3 kinds", 2) => ("9c1d0f0828b9197621a2163114b774fba44eb6cbd67462d102a090196f6cea37", "c3685551b78e3e28396a4473e7aacf3c4eedf5bc97c45c9512503daf7b607bfb", 468),
    ("square 2D, closed, 5 Lloyd steps, 3 kinds", 3) => ("0d33ff868b681003589853a6d7e8b321d920e522551ec433b123f4a0cd9b2458", "c3685551b78e3e28396a4473e7aacf3c4eedf5bc97c45c9512503daf7b607bfb", 468),
    ("square 2D, closed, 5 Lloyd steps, 3 kinds", 4) => ("8aacf317c105d88d569027a07a6d5baf4b9346e8322c375d3e0e219ece7d24e7", "c3685551b78e3e28396a4473e7aacf3c4eedf5bc97c45c9512503daf7b607bfb", 468),
    ("square 2D, irrational radius (graner_glazier_aggregate's)", 1) => ("c9cac4c53b406bc0aa1f2515abc6adc9fb64630fa9f072c0e0c3d3ade7a63751", "bd1110bafcb794917256eb71fa9374fef1b33ecc08281b320be852081db4b80f", 2001),
    ("square 2D, irrational radius (graner_glazier_aggregate's)", 2) => ("62d8944ffcd61936a500dd3362ce3c5fa7682f8ceb5d33b7c242f43f162745f8", "bd1110bafcb794917256eb71fa9374fef1b33ecc08281b320be852081db4b80f", 2001),
    ("square 2D, irrational radius (graner_glazier_aggregate's)", 3) => ("0bcdc9d5ca819b588023a1c7903e65651f46fe2a187df676156b8ab10bd31d4f", "bd1110bafcb794917256eb71fa9374fef1b33ecc08281b320be852081db4b80f", 2001),
    ("square 2D, irrational radius (graner_glazier_aggregate's)", 4) => ("a6550b4d9c8289d53dadeed1a7b9e5b40c1db836fcdfc576fdbf636fe093d6e2", "bd1110bafcb794917256eb71fa9374fef1b33ecc08281b320be852081db4b80f", 2001),
    ("hex, closed", 1) => ("d5e34bfa2d5523c0f5ca135d62d00332aa518ed7983a603b29e3a912f03d5bb6", "764b8427550b017f3577345bb7eb72f758959e26163999b62b448691527a5a25", 360),
    ("hex, closed", 2) => ("76858d9e778354d73cdd0a12b0d807cc6c7319cb3755c7efa761bf29fc90881a", "764b8427550b017f3577345bb7eb72f758959e26163999b62b448691527a5a25", 360),
    ("hex, closed", 3) => ("7a6e2079e0b2b320835da2233c00e482fa1b0f5c65687ed7d01adc4f34ebbd95", "764b8427550b017f3577345bb7eb72f758959e26163999b62b448691527a5a25", 360),
    ("hex, closed", 4) => ("4c3981930ec898a746878ab97490c4351c026980e1304ee15195d8af8aa19f09", "764b8427550b017f3577345bb7eb72f758959e26163999b62b448691527a5a25", 360),
    ("3D, closed", 1) => ("afca0f7c3d61a89f9ae900255cb45407e7bf3d5a6d867d7acf3449813a4400f0", "489be4fd2598e79a8a935213ea3093837af96a48c439e4ef4d75ca5f61da1076", 2325),
    ("3D, closed", 2) => ("ac85d7c1cc39bafc954171ab99593c40fedb94a1cf116a22f9674f8fa24e3fe9", "489be4fd2598e79a8a935213ea3093837af96a48c439e4ef4d75ca5f61da1076", 2325),
    ("3D, closed", 3) => ("dc381e00279794c9fa75c3eceaf21c65e991024c4a16b76e8a49629d7c06fe7a", "489be4fd2598e79a8a935213ea3093837af96a48c439e4ef4d75ca5f61da1076", 2325),
    ("3D, closed", 4) => ("2ad5c4c1a3f3f1f390af75dbaed6b689b704f735e29de6e0e21bafedef0a1424", "489be4fd2598e79a8a935213ea3093837af96a48c439e4ef4d75ca5f61da1076", 2325),
    ("square 2D, closed, ball cut by the lattice edge", 1) => ("f71658dacf1e6952c3f15a8bb46d494bcd1a6ce4d4a45cafaaf5327ba7beedbd", "45ca4819113c7f7acfa6c0fc4d0938a7bbfe676babcfdadaec2196b30b04d1b6", 325),
    ("square 2D, closed, ball cut by the lattice edge", 2) => ("585bba9bc81209fa688d3c09e8eb6da9aa18d41b27387c006be72cd7b4bf3b0f", "45ca4819113c7f7acfa6c0fc4d0938a7bbfe676babcfdadaec2196b30b04d1b6", 325),
    ("square 2D, closed, ball cut by the lattice edge", 3) => ("728267352bcdfb29c82be17635b942b700aee14f6fad986fb5ba2bce66319bb1", "45ca4819113c7f7acfa6c0fc4d0938a7bbfe676babcfdadaec2196b30b04d1b6", 325),
    ("square 2D, closed, ball cut by the lattice edge", 4) => ("94ec31099ed29632a5629daf530286ad5062992a5c842a7f45406159db632d4b", "45ca4819113c7f7acfa6c0fc4d0938a7bbfe676babcfdadaec2196b30b04d1b6", 325),
    ("square 2D, closed, ball cut by the domain", 1) => ("673bf68dbf9574274b44861fdcc322ec858c99b6c8ae9d254e3ffd3e81dc00a9", "45ca4819113c7f7acfa6c0fc4d0938a7bbfe676babcfdadaec2196b30b04d1b6", 295),
    ("square 2D, closed, ball cut by the domain", 2) => ("6ce0a5e621071f1511899586bad29bb1cc3443bb165bab7d093c58e6c56fcb33", "45ca4819113c7f7acfa6c0fc4d0938a7bbfe676babcfdadaec2196b30b04d1b6", 295),
    ("square 2D, closed, ball cut by the domain", 3) => ("600683c8e6166a5f4051ec703a16fd5ca137d8fa92183e1cfab99a44f2fea513", "45ca4819113c7f7acfa6c0fc4d0938a7bbfe676babcfdadaec2196b30b04d1b6", 295),
    ("square 2D, closed, ball cut by the domain", 4) => ("64abe747b736243ef1f87b7278ff6c8cb927aa228542278b4f27c20c718b57ae", "45ca4819113c7f7acfa6c0fc4d0938a7bbfe676babcfdadaec2196b30b04d1b6", 295),
    ("square 2D, periodic, interior ball", 1) => ("c7d3293c9fef58d449a10e358eed72538872381f31d6970295a61e989fe9a822", "cd39b99f4fbb9dadb25bdf03e2b17605249e4faf3740d1696ce9b49490281914", 317),
    ("square 2D, periodic, interior ball", 2) => ("3fcbea2d849d6472b90db7b9ef8742937aca58592e0a80e186ff8e71cd7b94ad", "cd39b99f4fbb9dadb25bdf03e2b17605249e4faf3740d1696ce9b49490281914", 317),
    ("square 2D, periodic, interior ball", 3) => ("7e6cbb0500d02e1a02671557127a8ff8f6b1dffd82af7c86d43deb08a430509d", "cd39b99f4fbb9dadb25bdf03e2b17605249e4faf3740d1696ce9b49490281914", 317),
    ("square 2D, periodic, interior ball", 4) => ("a618acf384b8439022e3a5fb34eec872a557d8479f6c2f3a2565454b910f8d09", "cd39b99f4fbb9dadb25bdf03e2b17605249e4faf3740d1696ce9b49490281914", 317),
    ("hex, periodic, interior ball", 1) => ("d8a8d7aa616d0867b2fe21a9ca23d25378541fe8862dd5f55ec95d0e87ae90e3", "1139c6ae173873ab8947f05b183898fa93233cafd21ce96695dd6f8531d8e4df", 241),
    ("hex, periodic, interior ball", 2) => ("9c14284168b918a7298c99232b9cdbff1c767394187d6f47bdc1ea9af90bb363", "1139c6ae173873ab8947f05b183898fa93233cafd21ce96695dd6f8531d8e4df", 241),
    ("hex, periodic, interior ball", 3) => ("cd878b97be66fe4526c1d8dc5aa4f3a0b8a77ac4bc289397beb8830a9f4eea72", "1139c6ae173873ab8947f05b183898fa93233cafd21ce96695dd6f8531d8e4df", 241),
    ("hex, periodic, interior ball", 4) => ("428fcc894400345689a1736c4faa1e44341a363e6d474dd5b90a68748a6eec11", "1139c6ae173873ab8947f05b183898fa93233cafd21ce96695dd6f8531d8e4df", 241),
    ("3D, periodic, interior ball", 1) => ("6ad30212194fd596190dc37ee83344838874f48b70d2e83a08afea914b6d9862", "5f803c5d61cecc334ac5a5e7cfc2748443a62d6f11192b49b07d425aea914c79", 1189),
    ("3D, periodic, interior ball", 2) => ("16ec3ac35a9b902ed3d5c32dda37690e1b89a06e0793f1bbf1c12a895474520b", "5f803c5d61cecc334ac5a5e7cfc2748443a62d6f11192b49b07d425aea914c79", 1189),
    ("3D, periodic, interior ball", 3) => ("b37362d2327de7af7232bddd1484f90f6b648717d876381aff768d2a25c1c697", "5f803c5d61cecc334ac5a5e7cfc2748443a62d6f11192b49b07d425aea914c79", 1189),
    ("3D, periodic, interior ball", 4) => ("bd4e4d9e780bbe3dd184eddaac6225f955b9cd1f6889a44cb60881c555702832", "5f803c5d61cecc334ac5a5e7cfc2748443a62d6f11192b49b07d425aea914c79", 1189),
)
const P61A5_GG_PINS = Dict(
    (50, 1, 60) => ("de98145baeae1d011e709a44a01f02b0b8f68255073fce79ac57ae3b15bf74bb", "bd1110bafcb794917256eb71fa9374fef1b33ecc08281b320be852081db4b80f", 173),
    (50, 2, 60) => ("0c92864c587e279edd7cd8fabd63105211c48514bd4cd536a8e1a15fb08b8268", "bd1110bafcb794917256eb71fa9374fef1b33ecc08281b320be852081db4b80f", 173),
    (50, 3, 60) => ("35e9cecaaf9494dc6843cf91af5ab3f62f36435494a73dead9afc62066a881b8", "bd1110bafcb794917256eb71fa9374fef1b33ecc08281b320be852081db4b80f", 173),
    (50, 4, 60) => ("e2af124bb4e01c40d9a0c81f6d4fbf06f92175ef7eec00c8b8a1f78ac26c9cdd", "bd1110bafcb794917256eb71fa9374fef1b33ecc08281b320be852081db4b80f", 173),
    (200, 1, 60) => ("5f0e638e089f8bea167ff9f8589a4b39001f799eea3303bddb896d768dcb7dea", "d7162b620feaa0747973139a110a9fa036993fd3c8d407d76443b9a3856ba80b", 223),
    (200, 2, 60) => ("441c36578744e3a77612e35ac9f576ee3cf09fda37f671b354f0d783e72d0927", "d7162b620feaa0747973139a110a9fa036993fd3c8d407d76443b9a3856ba80b", 223),
    (200, 1, 10) => ("637e070aa6101222a7ddb7ea9c45f4688de5c9599cac29ba0c22d177db43b142", "d7162b620feaa0747973139a110a9fa036993fd3c8d407d76443b9a3856ba80b", 123),
    (1000, 1, 60) => ("d76c8f3d55eda46ed8fe83c3685098d90dacd9d64798bb96e58797636bda0df7", "1be89756b456ad17a13888210217cb977b9ebe409e93344a6ce3d8b5a8d7144f", 347),
)
const P61A5_AKEEB_PINS = Dict(
    (1, 0.5) => "792f28e977ffb9ca1a402eb3e96cfed1f4140c83bb8555c09490c7d7f7b6984f",
    (1, 1.0) => "e3c13641839b7b51fab021b5e1320e760d4077259b86fc9cd5e1ecf40a65a157",
    (2, 0.5) => "126b065045a7355dd3633edec1c605ac09ff37130eda945ea661ec1f8497fa9f",
    (2, 1.0) => "a43b9937f40cafdba284962ecf5872dee5006886a013b2a6ca6f5638872a1a2c",
    (0x05cd2609, 0.5) => "f6f8e56f28c8e2500eb541ac884292e8e853d14bec249f7ade2d75a447802189",
    (0x05cd2609, 1.0) => "fb44c0fbf5ea87434ded8840906943b4d3b6c5c5fb436660829a3ccb472c882b",
)
# GG pins are (n, seed, margin) => (σ digest, kinds digest, lattice side); Akeeb pins are
# (seed, pp) => SHA-256 of the clock column's little-endian Float64 bytes, lattice (99, 60).

const P61A5_NEW_EXPORTS = (:Voronoi, :RandomPoints, :Center, :HyperSphere, :Circle, :Sphere, :Point)
const P61A5_NEW_PUBLIC = (:points, :layer_rng)
const P61A5_GB_KEPT_OUT = (:Rect, :Rect2, :Rect3, :Vec, :Cylinder, :volume, :area, :direction, :origin, :radius,
    :widths, :centered)

"""The (module, name) pairs where a loaded module exports `name` bound to something else than `ref.name`."""
function p61a5_clashes(ref::Module, names, mods = Base.loaded_modules_array())
    bad = Tuple{Module, Symbol}[]
    for m in mods, n in names
        (m === ref || m === Main) && continue
        isdefined(m, n) && Base.isexported(m, n) && getfield(m, n) !== getfield(ref, n) && push!(bad, (m, n))
    end
    return bad
end
module P61A5Clash                  # negative control for the clash check: a different `Center`
export Center
const Center = 1
end

# ---------------------------------------------------------------------------------------------
# Surface, names and dependencies
# ---------------------------------------------------------------------------------------------

@testset "P6.1a5: surface (exports, public names, GeometryBasics bindings)" begin
    for n in P61A5_NEW_EXPORTS
        @test Base.isexported(Potts, n)
    end
    for n in P61A5_NEW_PUBLIC
        @test Base.ispublic(Potts, n) && !Base.isexported(Potts, n)
    end
    GB = parentmodule(Potts.HyperSphere)
    @test nameof(GB) === :GeometryBasics
    for n in (:HyperSphere, :Circle, :Sphere, :Point)
        @test getfield(Potts, n) === getfield(GB, n)          # the same binding as GeometryBasics' (and Makie's)
    end
    @test Potts.Circle === Potts.HyperSphere{2} && Potts.Sphere === Potts.HyperSphere{3}
    for n in P61A5_GB_KEPT_OUT                               # index boxes stay ranges; no clashing GB names
        @test !Base.isexported(Potts, n)
        @test !(isdefined(Potts, n) && isdefined(GB, n) && getfield(Potts, n) === getfield(GB, n))
    end
    # no package of the D-056 list (Makie, SciMLBase, ModelingToolkit, Graphs; plus Symbolics
    # and GeometryBasics), where loaded, exports a different binding under a new name; the
    # check bites. (DomainSets, loaded through ModelingToolkit, exports its own `Sphere` and
    # `Point`: a known clash for `using DomainSets` users, documented in D-138.)
    d056 = [m for m in Base.loaded_modules_array() if nameof(m) in
            (:Makie, :CairoMakie, :SciMLBase, :ModelingToolkit, :ModelingToolkitBase, :Graphs, :Symbolics, :GeometryBasics)]
    @test length(d056) >= 3                                  # SciMLBase, ModelingToolkitBase, GeometryBasics at least
    @test isempty(p61a5_clashes(Potts, P61A5_NEW_EXPORTS, d056))
    @test p61a5_clashes(Potts, (:Center,), [P61A5Clash]) == [(P61A5Clash, :Center)]
    # no DSL name: layouts are problem data (D-057)
    @test !any(n -> n in keys(Potts.DSL), (P61A5_NEW_EXPORTS..., P61A5_NEW_PUBLIC...))
    # VoronoiBall is gone (Q3: Voronoi reproduces it), with no alias (D-028)
    @test !isdefined(PottsModels, :VoronoiBall) && !isdefined(Potts, :VoronoiBall)
    @test Base.isexported(PottsModels, :graner_glazier_aggregate)
end

@testset "P6.1a5: StableRNGs leaves PottsModels; GeometryBasics is Potts's only" begin
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
    walk(ex) = ex isa Symbol ? push!(names, ex) : ex isa Expr ? foreach(walk, ex.args) : nothing
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

@testset "P6.1a5: layer_rng and the Akeeb clocks" begin
    for s in (0, 1, 0x5cd2609, typemax(UInt64))
        @test rand(Potts.layer_rng(s), 5) == rand(StableRNG(UInt64(s)), 5)
        @test Potts.layer_rng(s) isa StableRNG
        @test rand(Potts.layer_rng(s, :clock), 5) == rand(StableRNG(Potts._substream_seed(s, :clock)), 5)
        @test rand(Potts.layer_rng(s, :clock), 5) != rand(Potts.layer_rng(s), 5)
        @test rand(Potts.layer_rng(s, "clock"), 5) == rand(Potts.layer_rng(s, :clock), 5)
    end
    @test rand(Potts.layer_rng(1), 5) != rand(Potts.layer_rng(2), 5)
    @test_throws ArgumentError Potts.layer_rng(-1)
    @test_throws ArgumentError Potts.layer_rng(-1, :clock)
    # akeeb_state's clocks are byte-identical to 8eb9d210
    for ((seed, pp), d) in P61A5_AKEEB_PINS
        op = akeeb_state(; lattice = (99, 60), seed, pp)
        clocks = only(p.second for p in op if isequal(p.first, :clock))
        @test bytes2hex(sha256(reinterpret(UInt8, htol.(clocks)))) == d
    end
    # negative control: the pins tell the streams apart
    @test length(unique(values(P61A5_AKEEB_PINS))) == length(P61A5_AKEEB_PINS)
end

# ---------------------------------------------------------------------------------------------
# Shapes: closed Cartesian membership, wrap, clipping (exercised through RandomPoints with
# n = every site of the region, so the drawn set IS the region)
# ---------------------------------------------------------------------------------------------

"""The set of Cartesian points of a region: draw all of its sites (n = m) and check n = m + 1 throws."""
function p61a5_region(region, target, m)
    pts = Potts.points(RandomPoints(m; region, seed = 7), target)
    @test_throws ArgumentError Potts.points(RandomPoints(m + 1; region, seed = 7), target)
    return Set(Tuple(p) for p in pts)
end

@testset "P6.1a5: closed membership in Cartesian coordinates" begin
    c2 = Potts.Point(10.0, 10.0)
    # r = 3 on the square lattice. Lattice points with dx² + dy² ≤ 9: dx = 0: 7; dx = ±1: 2·5;
    # dx = ±2: 2·5; dx = ±3: 2·1 → 29. An open or half-open rule drops the 4 axis points
    # at distance exactly 3 → 25.
    disk = p61a5_region(Potts.Circle(c2, 3.0), (20, 20), 29)
    @test length(disk) == 29 && (13.0, 10.0) in disk && (10.0, 7.0) in disk && !((12.0, 13.0) in disk)
    @test Set(Tuple(Float64.(Tuple(x))) for x in p61a5_ballsites((10.0, 10.0), 3.0, (20, 20))) == disk
    # 3D, r = 2: 1 + 6 (|v|² = 1) + 12 (2) + 8 (3) + 6 (4) = 33
    ball = p61a5_region(Potts.Sphere(Potts.Point(5.0, 5.0, 5.0), 2.0), (9, 9, 9), 33)
    @test (7.0, 5.0, 5.0) in ball && !((6.0, 6.0, 7.0) in ball)
    # hexagonal: round in the embedding. |embed(dq, dr)|² = dq² + dq·dr + dr²: 1 for the 6
    # neighbours, 3 for the next 6, 4 beyond. Centre (10, 10) is Cartesian (15, 5√3).
    hexl = Lattice((20, 20); geometry = Hexagonal(), boundary = Closed())
    hc = Potts.Point(15.0, 10 * sqrt(3) / 2)
    h1 = p61a5_region(Potts.Circle(hc, 1.5), hexl, 7)        # centre + 6 neighbours
    h2 = p61a5_region(Potts.Circle(hc, 1.8), hexl, 13)       # + the 6 at distance √3
    @test issubset(h1, h2)
    @test Set(Tuple(p61a5_cart(Tuple(x), true)) for x in p61a5_ballsites(Tuple(hc), 1.8, hexl)) == h2
    # in axial indices the same radius would be a different set (control: the embedding matters)
    @test length(p61a5_ballsites((10.0, 10.0), 1.8, (20, 20))) != 13
end

@testset "P6.1a5: shapes clip at closed edges and the domain, wrap through periodic ones" begin
    # quarter disk at the corner: dx, dy ≥ 0 of the 29: 4 + 3 + 3 + 1 = 11
    corner = Potts.Circle(Potts.Point(1.0, 1.0), 3.0)
    @test length(p61a5_region(corner, (20, 20), 11)) == 11
    # periodic on both axes: the whole disk, wrapped (29 sites, some at x or y near 20)
    wr = p61a5_region(corner, Lattice((20, 20)), 29)
    @test (19.0, 1.0) in wr && (20.0, 20.0) in wr && (1.0, 18.0) in wr
    # periodic in x only: dy ≥ 0 half of the 29: dx = 0: 4, ±1: 2·3, ±2: 2·3, ±3: 2·1 → 18
    @test length(p61a5_region(corner, Lattice((20, 20); boundary = (Periodic(), Closed())), 18)) == 18
    # the domain x ≤ 10 keeps dx ≤ 0 of the disk at (10, 10): 7 + 5 + 5 + 1 = 18
    dom = Lattice((20, 20); boundary = Closed(), domain = x -> x[1] <= 10)
    @test all(p -> p[1] <= 10, p61a5_region(Potts.Circle(Potts.Point(10.0, 10.0), 3.0), dom, 18))
    # a shape with no site on the lattice
    @test_throws ArgumentError Potts.points(RandomPoints(1; region = Potts.Circle(Potts.Point(-50.0, -50.0), 1.0), seed = 1), (20, 20))
    # a shape of the wrong dimension
    @test_throws ArgumentError Potts.points(RandomPoints(1; region = Potts.Sphere(Potts.Point(5.0, 5.0, 5.0), 2.0), seed = 1), (20, 20))
end

# ---------------------------------------------------------------------------------------------
# RandomPoints and Center()
# ---------------------------------------------------------------------------------------------

"""The documented draw rule, independently: region sites column-major, StableRNG(seed), redraw if taken."""
function p61a5_draws(sites, n, seed)
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

@testset "P6.1a5: RandomPoints draws distinct in-domain region sites (VoronoiBall's rule)" begin
    cases = [
        ((30, 30), Potts.Circle(Potts.Point(15.0, 14.0), 9.0), 40, false),
        ((30, 30), (5:20, 3:9), 25, false),
        ((30, 30), nothing, 50, false),
        (p61a5_hex((24, 24); boundary = Closed()), Potts.Circle(Potts.Point(18.0, 10.0), 6.0), 30, true),
        ((12, 12, 12), Potts.Sphere(Potts.Point(6.0, 6.5, 6.0), 4.0), 60, false),
        (Lattice((30, 30); boundary = Closed(), domain = x -> (x[1] - 15)^2 + (x[2] - 15)^2 <= 100), nothing, 40, false),
        (Lattice((30, 30)), Potts.Circle(Potts.Point(2.0, 29.0), 5.0), 30, false),      # wraps
    ]
    for (target, region, n, hex) in cases, seed in (1, 2, 99)
        dims, per, _, mask = p61a5_meta(target)
        sites = region === nothing ? [x for x in CartesianIndices(dims) if mask === nothing || mask[x]] :
                region isa Tuple ? [x for x in CartesianIndices(region) if mask === nothing || mask[x]] :
                p61a5_ballsites(Tuple(region.center), region.r, target)
        pts = Potts.points(RandomPoints(n; region, seed), target)
        @test pts isa Vector{<:Potts.Point} && eltype(pts) === Potts.Point{length(dims), Float64}
        @test [Tuple(p) for p in pts] == [p61a5_cart(Tuple(x), hex) for x in p61a5_draws(sites, n, seed)]
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

@testset "P6.1a5: Center() is the lattice centre (Cartesian)" begin
    @test Potts.points(Center(), (40, 42)) == [Potts.Point(20.5, 21.5)]
    @test Potts.points(Center(), (19, 19, 19)) == [Potts.Point(10.0, 10.0, 10.0)]
    hx = only(Potts.points(Center(), p61a5_hex((30, 30))))
    @test all(isapprox.(Tuple(hx), (15.5 + 15.5 / 2, 15.5 * sqrt(3) / 2); atol = 1e-12))
    @test Potts.points([Center(), Potts.Point(1.0, 2.0)], (10, 10)) == [Potts.Point(5.5, 5.5), Potts.Point(1.0, 2.0)]
end

# ---------------------------------------------------------------------------------------------
# Voronoi reproduces VoronoiBall (Q3) and graner_glazier_aggregate
# ---------------------------------------------------------------------------------------------

function p61a5_as_voronoi(n, r, c, kinds, it, target, seed; lloyd = it)
    dims, _, hex, _ = p61a5_meta(target)
    ci = c === nothing ? map(d -> (d + 1) / 2, dims) : Float64.(Tuple(c))
    ball = Potts.HyperSphere(Potts.Point(p61a5_cart(ci, hex)), Float64(r))
    return Voronoi(RandomPoints(n; region = ball, seed); region = ball, lloyd, kinds)
end

@testset "P6.1a5: Voronoi over a ball paints VoronoiBall's σ and kinds (8eb9d210)" begin
    for (name, n, r, c, kinds, it, target) in P61A5_CASES, seed in P61A5_SEEDS
        dσ, dk, painted = P61A5_PINS[(name, seed)]
        op, rep = layout(p61a5_as_voronoi(n, r, c, kinds, it, target, seed), target; report = true)
        @test p61a5_digest(p61a5_σ(op)) == dσ
        @test p61a5_kdigest(p61a5_kinds(op)) == dk
        @test count(!=(0), p61a5_σ(op)) == painted
        @test only(rep).type === :Voronoi && only(rep).requested == n && only(rep).painted == n && only(rep).dropped == 0
    end
    # negative controls: the pins depend on the seed and on Lloyd
    @test allunique(first(v) for v in values(P61A5_PINS))
    (name, n, r, c, kinds, it, target) = P61A5_CASES[1]
    @test p61a5_digest(p61a5_σ(layout(p61a5_as_voronoi(n, r, c, kinds, it, target, 1; lloyd = 0), target))) !=
          first(P61A5_PINS[(name, 1)])
end

@testset "P6.1a5: graner_glazier_aggregate is unchanged (8eb9d210)" begin
    for (n, seed, margin) in P61A5_GG
        dσ, dk, L = P61A5_GG_PINS[(n, seed, margin)]
        σ, k = graner_glazier_aggregate(n; seed, margin)
        @test size(σ) == (L, L)
        @test p61a5_digest(σ) == dσ && p61a5_kdigest(k) == dk
    end
end

# ---------------------------------------------------------------------------------------------
# Voronoi against a brute-force oracle (lloyd = 0, explicit generators)
# ---------------------------------------------------------------------------------------------

function p61a5_oracle(gens, target, region_sites)
    dims, per, hex, _ = p61a5_meta(target)
    σ = zeros(Int32, dims)
    for x in region_sites
        σ[x] = first(p61a5_nearest(Tuple(x), gens, dims, per, hex))
    end
    return σ
end

@testset "P6.1a5: nearest generator, minimum image, ties to the lowest (2D, 3D, periodic)" begin
    P = Potts.Point
    fixtures = [
        ("square closed", (20, 16), [P(4.0, 4.0), P(15.0, 5.0), P(9.0, 12.0), P(17.0, 14.0)], P61A5_SQ2),
        ("square periodic", Lattice((20, 16)), [P(2.0, 3.0), P(11.0, 9.0), P(19.0, 14.0)], P61A5_SQ2),
        ("square periodic x", Lattice((20, 16); boundary = (Periodic(), Closed())), [P(2.0, 3.0), P(11.0, 9.0), P(19.0, 14.0)], P61A5_SQ2),
        ("3D closed", (8, 8, 8), [P(2.0, 2.0, 2.0), P(7.0, 3.0, 5.0), P(4.0, 7.0, 7.0)], P61A5_CUBE),
        ("3D periodic", Lattice((8, 8, 8)), [P(1.0, 1.0, 1.0), P(5.0, 4.0, 6.0)], P61A5_CUBE),
    ]
    for (label, target, gens, steps) in fixtures
        dims, per, _, _ = p61a5_meta(target)
        oracle = p61a5_oracle(gens, target, CartesianIndices(dims))
        @test p61a5_split_cells(oracle, steps, per) == 0          # fixture: no repair needed
        op, rep = layout(Voronoi(gens; kinds = [:a]), target; report = true)
        @test p61a5_σ(op) == oracle
        @test only(rep).clipped == 0 && only(rep).painted == length(gens)
        if any(per)          # negative control: ignoring the wrap gives another tessellation
            @test p61a5_oracle(gens, dims, CartesianIndices(dims)) != oracle
        end
    end
    # ties: with generators (3, 5) and (7, 5) the column x = 5 is equidistant; it goes to the
    # lower generator, whichever order they are given in
    σ1 = p61a5_σ(layout(Voronoi([P(3.0, 5.0), P(7.0, 5.0)]; kinds = [:a]), (9, 9)))
    σ2 = p61a5_σ(layout(Voronoi([P(7.0, 5.0), P(3.0, 5.0)]; kinds = [:a]), (9, 9)))
    @test all(==(1), σ1[1:5, :]) && all(==(2), σ1[6:9, :])
    @test all(==(2), σ2[1:4, :]) && all(==(1), σ2[5:9, :])
end

@testset "P6.1a5: hexagonal Voronoi is nearest in the embedding" begin
    hexl = p61a5_hex((16, 16); boundary = Closed())
    hexp = p61a5_hex((16, 16))
    gens = [Potts.Point(6.3, 3.1), Potts.Point(17.0, 4.2), Potts.Point(12.2, 10.9), Potts.Point(20.6, 12.0)]
    for target in (hexl, hexp)
        dims, per, _, _ = p61a5_meta(target)
        σ = p61a5_σ(layout(Voronoi(gens; kinds = [:a]), target))
        @test all(x -> σ[x] > 0, CartesianIndices(dims))
        # assigned generator is a nearest one (up to rounding)
        @test all(x -> (d = p61a5_nearest(Tuple(x), [gens[σ[x]]], dims, per, true)[2];
                        d <= p61a5_nearest(Tuple(x), gens, dims, per, true)[2] + 1e-9), CartesianIndices(dims))
        @test p61a5_split_cells(σ, P61A5_HEX1, per) == 0
    end
    # control: the axial-index tessellation differs (the embedding matters)
    @test p61a5_σ(layout(Voronoi(gens; kinds = [:a]), hexl)) != p61a5_oracle(gens, (16, 16), CartesianIndices((16, 16)))
end

# ---------------------------------------------------------------------------------------------
# Lloyd and connectivity
# ---------------------------------------------------------------------------------------------

@testset "P6.1a5: every cell is one piece (2D, hex, 3D; closed and periodic)" begin
    sq = Potts.Circle(Potts.Point(12.5, 12.5), 10.3)
    hb = Potts.Circle(Potts.Point(p61a5_cart((10, 15), true)), 10.3)
    cb = Potts.Sphere(Potts.Point(10.0, 10.0, 10.0), 8.2)
    cases = [
        ((24, 24), sq, 60, P61A5_SQ2),
        (p61a5_hex((30, 30); boundary = Closed()), hb, 150, P61A5_HEX1),
        ((19, 19, 19), cb, 100, P61A5_CUBE),
        (Lattice((24, 24)), nothing, 40, P61A5_SQ2),
        (p61a5_hex((20, 20)), nothing, 40, P61A5_HEX1),
    ]
    for (target, region, n, steps) in cases
        dims, per, hex, _ = p61a5_meta(target)
        raw_split = 0
        for seed in 1:30
            σ = p61a5_σ(layout(Voronoi(RandomPoints(n; region, seed); region, kinds = [:a]), target))
            @test p61a5_split_cells(σ, steps, per) == 0
            # the plain nearest-generator labelling is not always one piece, so the repair is tested
            gens = Potts.points(RandomPoints(n; region, seed), target)
            sites = findall(!=(0), σ)
            raw_split += p61a5_split_cells(p61a5_oracle(gens, target, sites), steps, per) > 0
        end
        @test raw_split >= 1
    end
end

"""Share of painted sites whose nearest cell centroid (min image) is their own cell's (square lattice)."""
function p61a5_own_centroid_share(σ, per)
    dims = size(σ)
    n = maximum(σ)
    cen = Vector{NTuple{length(dims), Float64}}(undef, n)
    for c in 1:n
        idx = findall(==(c), σ)
        x0 = Tuple(idx[1])
        unw = [ntuple(d -> per[d] ? x[d] - dims[d] * round((x[d] - x0[d]) / dims[d]) : Float64(x[d]), length(dims))
               for x in Tuple.(idx)]
        cen[c] = ntuple(d -> sum(getindex.(unw, d)) / length(unw), length(dims))
    end
    sites = findall(!=(0), σ)
    near(x) = argmin(c -> minimum(y -> sum(abs2, y .- cen[c]), p61a5_images(Tuple(x), dims, per)), 1:n)
    return count(x -> near(x) == σ[x], sites) / length(sites)
end

@testset "P6.1a5: Lloyd moves generators to centroids (closed and through the wrap)" begin
    for target in ((30, 30), Lattice((30, 30)))
        dims, per, _, _ = p61a5_meta(target)
        s0 = s30 = 0.0
        straddle = 0
        for seed in 1:6
            v(k) = Voronoi(RandomPoints(15; seed); lloyd = k, kinds = [:a])
            σ30 = p61a5_σ(layout(v(30), target))
            s0 += p61a5_own_centroid_share(p61a5_σ(layout(v(0), target)), per) / 6
            s30 += p61a5_own_centroid_share(σ30, per) / 6
            straddle += p61a5_split_cells(σ30, P61A5_SQ2, map(_ -> false, dims)) > 0
        end
        @test s30 > 0.99                 # centroidal (a Lloyd step that ignores the wrap: ≈ 0.96 at the freeze)
        @test s30 > s0 + 0.05            # and Lloyd is what made it so (s0 ≈ 0.84)
        any(per) && @test straddle >= 1  # cells do cross the periodic edges (the wrap is exercised)
    end
end

# ---------------------------------------------------------------------------------------------
# Composition, report, clipped, kinds, errors, remake
# ---------------------------------------------------------------------------------------------

@testset "P6.1a5: Voronoi fills medium only (an earlier layer is never cut)" begin
    disk = Potts.Circle(Potts.Point(10.5, 10.5), 8.0)
    block = Tiling((4, 4); region = (9:12, 9:12), kinds = [:block])
    vor = Voronoi(RandomPoints(10; region = disk, seed = 1); region = disk, kinds = [:v])
    op, rep = p61a5_quiet(() -> layout(overlay(block, vor), (20, 20); report = true))
    σ, k = p61a5_σ(op), p61a5_kinds(op)
    disk_sites = Set(p61a5_ballsites((10.5, 10.5), 8.0, (20, 20)))
    @test all(==(1), σ[9:12, 9:12]) && k[1] === :block && count(==(1), σ) == 16
    @test Set(findall(>(1), σ)) == setdiff(disk_sites, Set(CartesianIndices((9:12, 9:12))))
    @test rep[2].type === :Voronoi && rep[2].splits == 0 && rep[1].splits == 0
    # control: alone, the Voronoi covers the block's sites
    alone = p61a5_σ(layout(vor, (20, 20)))
    @test all(>(0), alone[9:12, 9:12])
end

@testset "P6.1a5: report rows carry clipped" begin
    P = Potts.Point
    corner = Potts.Circle(P(1.0, 1.0), 3.0)
    g2 = [P(1.0, 1.0), P(3.0, 2.0)]
    r(l, t) = only(last(layout(l, t; report = true)))
    # closed corner: 29 disk points, 11 on the lattice → 18 clipped
    row = r(Voronoi(g2; region = corner, kinds = [:a]), (20, 20))
    @test (row.type, row.requested, row.painted, row.dropped, row.misses, row.counted, row.clipped, row.splits) ==
          (:Voronoi, 2, 2, 0, 0, 2, 18, 0)
    # periodic: the disk wraps, nothing is clipped, all 29 sites painted
    op, rep = layout(Voronoi(g2; region = corner, kinds = [:a]), Lattice((20, 20)); report = true)
    @test only(rep).clipped == 0 && count(!=(0), p61a5_σ(op)) == 29
    # domain x ≤ 10 at (10, 10): 18 of 29 in the domain → 11 clipped
    dom = Lattice((20, 20); boundary = Closed(), domain = x -> x[1] <= 10)
    @test r(Voronoi([P(9.0, 10.0)]; region = Potts.Circle(P(10.0, 10.0), 3.0), kinds = [:a]), dom).clipped == 11
    # hex corner, r = 1.8 at index (1, 1): 13 points (|v|² ∈ {0, 1, 3}); offsets with
    # dq, dr ≥ 0 on the lattice: (0,0), (1,0), (0,1), (1,1) → 4 painted, 9 clipped
    hexl = p61a5_hex((20, 20); boundary = Closed())
    hc = Potts.Circle(P(p61a5_cart((1, 1), true)), 1.8)
    op, rep = layout(Voronoi([P(p61a5_cart((1, 1), true))]; region = hc, kinds = [:a]), hexl; report = true)
    @test only(rep).clipped == 9 && count(!=(0), p61a5_σ(op)) == 4
    # 3D corner, r = 2 at (1, 1, 1): offsets ≥ 0 of the 33: 1 + 3 + 3 + 1 + 3 = 11 → 22 clipped
    op, rep = layout(Voronoi([P(1.0, 1.0, 1.0)]; region = Potts.Sphere(P(1.0, 1.0, 1.0), 2.0), kinds = [:a]), (9, 9, 9); report = true)
    @test only(rep).clipped == 22 && count(!=(0), p61a5_σ(op)) == 11
    # a shape inside the lattice clips nothing
    @test r(Voronoi(g2; region = Potts.Circle(P(10.0, 10.0), 3.0), kinds = [:a]), (20, 20)).clipped == 0
    # a generator with no site is dropped: every site of the small disk is nearer (1, 1)
    row = r(Voronoi([P(1.0, 1.0), P(15.0, 15.0)]; region = Potts.Circle(P(3.0, 3.0), 2.0), kinds = [:a]), (20, 20))
    @test (row.requested, row.painted, row.dropped) == (2, 2, 1)
    # the other built-in layers report clipped = 0
    rows = last(layout(overlay(Tiling((3, 3); region = (1:9, 1:9), kinds = [:t]),
        Scattered(2, (2, 2); region = (12:19, 12:19), kinds = [:s], seed = 1),
        Frame(:w), InsertUntil(:i; into = [:t], number = 2, seed = 1)), (20, 20); report = true))
    @test [x.type for x in rows] == [:Tiling, :Scattered, :Frame, :InsertUntil]
    @test all(x -> x.clipped == 0, rows)
end

struct P61A5Clipper <: AbstractLayout
    clipped::Union{Nothing, Int}
end
function Potts.paint!(op::Potts.LayoutState, l::P61A5Clipper, lat)
    id = Potts.new_cell!(op, :c)
    Potts.assign!(op, (1:2, 1:2), id)
    l.clipped === nothing ? Potts.record!(op; requested = 1, painted = 1) :
        Potts.record!(op; requested = 1, painted = 1, clipped = l.clipped)
    return nothing
end
struct P61A5Silent <: AbstractLayout end
Potts.paint!(op::Potts.LayoutState, ::P61A5Silent, lat) = (Potts.assign!(op, (3:3, 3:3), Potts.new_cell!(op, :d)); nothing)

@testset "P6.1a5: record!(…; clipped) for a custom layer" begin
    rows = last(layout(overlay(P61A5Clipper(3), P61A5Clipper(nothing), P61A5Silent()), (6, 6); report = true))
    @test [x.clipped for x in rows] == [3, 0, 0]
end

@testset "P6.1a5: kinds, ids, Center() generators" begin
    P = Potts.Point
    gens = [P(2.0, 2.0), P(18.0, 2.0), P(10.0, 18.0)]
    op = layout(Voronoi(gens; kinds = [:a, :b]), (20, 20))
    σ = p61a5_σ(op)
    @test p61a5_kinds(op) == [:a, :b, :a]
    @test σ[2, 2] == 1 && σ[18, 2] == 2 && σ[10, 18] == 3          # ids in generator order
    # Center() as a generator: one cell at the lattice centre owns a disk around it
    disk = Potts.Circle(P(10.5, 10.5), 4.0)
    σc = p61a5_σ(layout(Voronoi([Center(), P(1.0, 1.0)]; region = disk, kinds = [:c]), (20, 20)))
    @test σc[10, 10] == 1 && σc[11, 11] == 1 && count(==(1), σc) == length(p61a5_ballsites((10.5, 10.5), 4.0, (20, 20)))
    @test p61a5_σ(layout(Voronoi(Center(); region = disk, kinds = [:c]), (20, 20))) == σc
    # a tuple-of-ranges region still means an index box
    σb = p61a5_σ(layout(Voronoi(gens; region = (3:12, 4:9), kinds = [:a]), (20, 20)))
    @test findall(!=(0), σb) == vec(collect(CartesianIndices((3:12, 4:9))))
end

@testset "P6.1a5: errors and remake" begin
    P = Potts.Point
    g = [P(2.0, 2.0), P(8.0, 8.0)]
    @test_throws ArgumentError Voronoi(g; lloyd = -1, kinds = [:a])
    @test_throws ArgumentError Voronoi(g; kinds = Symbol[])
    @test_throws ArgumentError Voronoi(g; kinds = [:a], splits = :bogus)
    @test Voronoi(g; kinds = [:a], splits = :allow) isa AbstractLayout
    @test_throws ArgumentError layout(Voronoi(P{2, Float64}[]; kinds = [:a]), (10, 10))           # no generator
    @test_throws ArgumentError layout(Voronoi([P(1.0, 2.0, 3.0)]; kinds = [:a]), (10, 10))        # 3D point, 2D lattice
    @test_throws ArgumentError layout(Voronoi(g; region = Potts.Sphere(P(5.0, 5.0, 5.0), 2.0), kinds = [:a]), (10, 10))
    @test_throws ArgumentError layout(Voronoi(RandomPoints(200; region = Potts.Circle(P(5.0, 5.0), 3.0), seed = 1);
        kinds = [:a]), (10, 10))                                                                  # 29 sites < 200
    v = Voronoi(RandomPoints(12; seed = 3); kinds = [:a, :b])
    @test p61a5_σ(layout(remake(v; lloyd = 5), (20, 20))) == p61a5_σ(layout(Voronoi(RandomPoints(12; seed = 3); lloyd = 5, kinds = [:a, :b]), (20, 20)))
    @test p61a5_σ(layout(remake(v; lloyd = 5), (20, 20))) != p61a5_σ(layout(v, (20, 20)))
    @test_throws ArgumentError remake(v; lloyd = -1)
    @test p61a5_σ(layout(remake(v; points = RandomPoints(12; seed = 4)), (20, 20))) ==
          p61a5_σ(layout(Voronoi(RandomPoints(12; seed = 4); kinds = [:a, :b]), (20, 20)))
end

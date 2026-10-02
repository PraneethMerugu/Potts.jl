# P6.1a7 (ROADMAP Phase 6, step 1; after P6.1a6/D-091; D-057, D-087): `Scattered`'s overlap
# test against an occupancy mask. Frozen (AUTONOMY §7.3).
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
# Accept (ROADMAP): σ identical to the pre-change version over a seed grid, closed and
# periodic (the dilation wraps), 2D, 3D and hex; 10⁴ cubes of 5³ at 200³ under 50 ms.
#
# Expected values. Every digest below was computed on the tree before this item (feat/p6-1a7
# at a5a2819, the P6.1a6 merge) by /tmp/p61a7/digests_today.jl, which `include`s
# /tmp/p61a7/cases.jl; the "Case table" section below is a verbatim copy of cases.jl. Per
# (case, gap) and per seed in P61A7_SEEDS, a record is
#     SHA-256 of σ's little-endian Int32 bytes (as in p6_1a6), SHA-256 of the kinds joined
#     by ',', and the report rows (type, requested, painted, dropped, misses, counted, splits)
# and the expected value is the SHA-256 of the five records joined by '\n'. So σ, kinds and
# the report row are all pinned. The generator also
#   - re-derived every σ from an independent brute-force implementation of the documented
#     draw rule (same StableRNG stream, pairwise Chebyshev test) and found it identical;
#   - counted the rejected draws per seed (the "misses" of random sequential placement; the
#     report's `misses` field is 0 for Scattered): every case has some, the dense cases
#     hundreds (up to 827 for 110 cubes of 2³ in 12³);
#   - checked that the wrap decides draws: for every periodic case with gap ≥ 1 the
#     placement under the closed rule differs for at least one seed (dense periodic cases:
#     5 of 5 seeds; regions on the lattice edge spanning a periodic ring: 1–3 of 5), and
#     with gap 0 it never does (a box never reaches past the lattice, so only the dilation
#     can wrap). The table itself shows it: periodic ≠ closed digests for gap ≥ 1, equal
#     for gap 0 (asserted below as a check on the grid, not on the implementation).
# The grid: 5 seeds × gap ∈ {0, 1, 2} × closed, periodic on every axis and on one axis, in
# 2D square, 3D and hexagonal lattices; whole-lattice, offset and edge regions (an edge
# region spans a periodic ring, so boxes at both ends interact through the wrap); a ring of 12
# and of 8 sites where one box's dilation covers most or all of the ring (gap 2 on the
# 8-ring can never separate along that axis); unit boxes; dense requests near the jam;
# a Merks-like request (D-087: 282 boxes of 7² with gap 1 in the central region of 500²);
# two layered cases (Scattered over a Tiling, and over another Scattered). The jam error
# pins the index of the box that fails (the draw sequence up to it); the 10,000-draw limit is
# pinned from both sides (boxes placed at draw 9,845 and 7,191 must succeed, one that would
# be placed at draw 14,042 must throw); and the area bound still throws.
#
# Timing. `layout` (the user-visible call, so the paint plus the linear passes of `layout`
# itself: allocation, split check, compaction, ≈ 5 ms at 200³) of 10⁴ cubes of 5³, gap 1,
# seed 1, at 200³ must take ≤ 50 ms: today ≈ 480 ms closed (≈ 860 ms periodic). The same
# request on a fully periodic 200³ lattice has the same bound (author's addition, so the
# wrap is not left on a slow path). A per-object scaling check: 4·10⁴ squares of 7² at 3000²
# against 4·10³ at 949² (the same density, 225 sites per box): the time per placed box at
# the larger size is at most 2.5× that at the smaller (today ≈ 9.8×: O(placed) per draw).
# A mask stand-in (/tmp/p61a7/mask_stub.jl: same draws, a BitArray of placed boxes, the
# dilated window scanned with mod1 on periodic axes) passes every assertion here at ≈ 29 ms
# closed, ≈ 28 ms periodic and a ratio ≈ 1.15 on the authoring machine (Apple silicon,
# single thread).
# Robustness to machine load: each figure is the MINIMUM over several runs after a warm-up
# (compilation is excluded by a small call with the same types), with a `GC.gc()` before
# every run so no run pays for a previous run's garbage. Load only adds time, so the minimum
# estimates the unloaded cost; a run under the bound ends the loop early (min ≤ bound is
# decided by the first such run), which also keeps the failing (today's) run short. The σ of
# every timed call is checked against today's digest, so a fast but different placement
# fails.
using SHA: sha256

# ---------------------------------------------------------------------------------------------
# Case table (verbatim from /tmp/p61a7/cases.jl)
# ---------------------------------------------------------------------------------------------

p61a7_get(op, key) = only(last(p) for p in op if isequal(first(p), key))
p61a7_hex(v) = bytes2hex(sha256(v))
p61a7_digest(σ) = p61a7_hex(reinterpret(UInt8, vec(htol.(Int32.(σ)))))
p61a7_row(r) = (r.type, r.requested, r.painted, r.dropped, r.misses, r.counted, r.splits)
p61a7_bnd(b::Symbol) = b === :P ? Periodic() : Closed()
p61a7_bnd(b::Tuple) = map(p61a7_bnd, b)
# the layout target: a closed square lattice as plain dims, everything else as a `Lattice`
function p61a7_target(geom, dims, bnd)
    geom === :sq && bnd === :C && return dims
    geom === :hex && return Lattice(dims; boundary = p61a7_bnd(bnd), geometry = Hexagonal())
    return Lattice(dims; boundary = p61a7_bnd(bnd))
end
# One seed's record: SHA-256 of σ's little-endian Int32 bytes, SHA-256 of the kinds joined
# by ',', and the report rows; then one config's digest = SHA-256 of the seeds' records.
function p61a7_record(l, x)
    op, rows = layout(l, x; report = true)
    return string(p61a7_digest(p61a7_get(op, ownership)), " ",
        p61a7_hex(join(string.(p61a7_get(op, kind)), ",")), " ", join(map(string ∘ p61a7_row, rows), ";"))
end

const P61A7_SEEDS = (1, 2, 3, 0x9e3779b97f4a7c15, typemax(UInt64))
const P61A7_GAPS = (0, 1, 2)
# name => (geometry, dims, boundary, n (or one n per gap), box size, region, kinds)
# boundary :C closed, :P periodic, or one symbol per axis
const P61A7_CASES = [
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
    # dense requests: many rejected draws (misses) before each late box
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
p61a7_n(n::Integer, gi) = n
p61a7_n(n::Tuple, gi) = n[gi]
p61a7_layer(c, gi, seed) = Scattered(p61a7_n(c[4], gi), c[5]; region = c[6], kinds = c[7], seed, gap = P61A7_GAPS[gi])
function p61a7_config_digest(c, gi)
    x = p61a7_target(c[1], c[2], c[3])
    return p61a7_hex(join((p61a7_record(p61a7_layer(c, gi, s), x) for s in P61A7_SEEDS), "\n"))
end

# Layered cases: Scattered over a Tiling (it overwrites tiles; on hex one is dropped) and
# two Scattered layers; the report rows of both layers enter the record.
const P61A7_LAYERED = [
    "sq tiling+scattered periodic" => ((:sq, (40, 30), :P),
        (s, g) -> overlay(Tiling((4, 4); spacing = 1, kinds = [:t], splits = :allow),
            Scattered(8, (3, 3); kinds = [:s], seed = s, gap = g, splits = :allow))),
    "hex tiling+scattered closed" => ((:hex, (30, 26), :C),
        (s, g) -> overlay(Tiling((3, 3); spacing = 1, kinds = [:t], splits = :allow),
            Scattered(8, (3, 3); kinds = [:s], seed = s, gap = g, splits = :allow))),
    "cube scattered+scattered periodic" => ((:sq, (24, 20, 16), :P),
        (s, g) -> overlay(Scattered(10, (3, 3, 2); kinds = [:a], seed = s, gap = g, splits = :allow),
            Scattered(6, (4, 2, 3); kinds = [:b], seed = s ⊻ 0x5555, gap = g, splits = :allow))),
]
function p61a7_layered_digest(c, gi)
    x = p61a7_target(c[1]...)
    return p61a7_hex(join((p61a7_record(c[2](s, P61A7_GAPS[gi]), x) for s in P61A7_SEEDS), "\n"))
end

# ---------------------------------------------------------------------------------------------
# Expected values (a5a2819, /tmp/p61a7/digests_today.jl; comments: rejected draws per seed, and
# for periodic cases the number of seeds whose placement the wrap decides)
# ---------------------------------------------------------------------------------------------

const P61A7_EXPECTED = Dict{Tuple{String, Int}, String}(
    ("sq closed", 0) => "bac255c09ae7a515aff2db676d92bad5833413faf89aaa4091f88466cf1b354b",   # misses [132, 56, 26, 15, 16]
    ("sq closed", 1) => "3e598fe1580b265729d45c6db76195ffbd4ee9ff142de9be1865add2ff89fe8e",   # misses [10, 9, 3, 9, 34]
    ("sq closed", 2) => "19d8926d9a4063e27ac84a9afad16f044e1e64a54779eb298db4c00fd94a203b",   # misses [7, 10, 0, 4, 8]
    ("sq periodic", 0) => "bac255c09ae7a515aff2db676d92bad5833413faf89aaa4091f88466cf1b354b",   # misses [132, 56, 26, 15, 16] wrap decides 0/5
    ("sq periodic", 1) => "4cbfaddc4f22cb39f206b991aa77d2ecbf8887b84869aafc91b6a28affb7ba9b",   # misses [10, 54, 11, 9, 34] wrap decides 3/5
    ("sq periodic", 2) => "bde184cb39261ebacbb85940585c3d5b3a8bb3b94d7eed0bbd0a8cf7671b069a",   # misses [7, 12, 10, 12, 8] wrap decides 3/5
    ("sq periodic x", 0) => "bac255c09ae7a515aff2db676d92bad5833413faf89aaa4091f88466cf1b354b",   # misses [132, 56, 26, 15, 16] wrap decides 0/5
    ("sq periodic x", 1) => "5ebe85553d2d9cc59cb9b7df5308ec84f3c9444418c219deb8527e2dc9a77b72",   # misses [10, 54, 11, 9, 34] wrap decides 2/5
    ("sq periodic x", 2) => "ecb5a6ed7c820327c863191eb804a76dc86bf34643aa16d27356670933323f72",   # misses [7, 12, 10, 4, 8] wrap decides 2/5
    ("sq periodic y", 0) => "bac255c09ae7a515aff2db676d92bad5833413faf89aaa4091f88466cf1b354b",   # misses [132, 56, 26, 15, 16] wrap decides 0/5
    ("sq periodic y", 1) => "28d1e3f1d3de1edd7ad416b2fa5bd4ca462de6a06091528e40ea6c7c6bff38e4",   # misses [10, 9, 3, 9, 34] wrap decides 1/5
    ("sq periodic y", 2) => "d73c887e5464521b874be901dee4b37273a796d44604a77b51c59119f16636b1",   # misses [7, 10, 0, 12, 8] wrap decides 1/5
    ("sq offset region", 0) => "3bb4188a42c0f7b16763a49033155d08b20d369ec40a7f29cf1ff891e874c4d5",   # misses [10, 17, 8, 16, 10]
    ("sq offset region", 1) => "97a093285fca65ff56e61295dc3f0de600e995cd082a934d62369700460654ff",   # misses [12, 6, 1, 10, 8]
    ("sq offset region", 2) => "e9ff4b66f3a830db60f79b74737da9ae873243b29f8857b6a259f9f33fd87f63",   # misses [7, 4, 1, 1, 4]
    ("sq offset region periodic", 0) => "3bb4188a42c0f7b16763a49033155d08b20d369ec40a7f29cf1ff891e874c4d5",   # misses [10, 17, 8, 16, 10] wrap decides 0/5
    ("sq offset region periodic", 1) => "97a093285fca65ff56e61295dc3f0de600e995cd082a934d62369700460654ff",   # misses [12, 6, 1, 10, 8] wrap decides 0/5
    ("sq offset region periodic", 2) => "e9ff4b66f3a830db60f79b74737da9ae873243b29f8857b6a259f9f33fd87f63",   # misses [7, 4, 1, 1, 4] wrap decides 0/5
    ("sq edge region periodic", 0) => "e36ff108da1c7fa2132a6089e5efe6af70c4647d29f7b3921efe26e617622726",   # misses [111, 120, 141, 196, 67] wrap decides 0/5
    ("sq edge region periodic", 1) => "b05758afa3018e23f375314cf12108b51b67842b4ab07a92d48e97053023a765",   # misses [30, 13, 7, 29, 41] wrap decides 1/5
    ("sq edge region periodic", 2) => "ac126dd9ace27f64f628b663f86940d4bc9c3446cb1e5ce0974763324caf5068",   # misses [55, 10, 17, 96, 59] wrap decides 3/5
    ("sq edge region periodic x", 0) => "dbc2c9f8079787ec48cd531871d1ab52993a3101c0ff1e7d03573883ced5ea38",   # misses [111, 120, 141, 196, 67] wrap decides 0/5
    ("sq edge region periodic x", 1) => "477c8b5ad965f7eaa83c859f17705282d7515e3cccfc62fec4a6759ec420460e",   # misses [30, 13, 7, 29, 41] wrap decides 1/5
    ("sq edge region periodic x", 2) => "2817f849709481f9b2da7d2da98b685599d6528933ebc69ca4299e8247f47c2e",   # misses [55, 10, 17, 96, 59] wrap decides 3/5
    ("sq small ring", 0) => "a7143bbc5e18a8ab248898b2d0f4df3a3326b9b4c6be66dc1d33dc553e42d194",   # misses [26, 37, 21, 27, 36] wrap decides 0/5
    ("sq small ring", 1) => "137fa447594f8e14d6890f9dc58fc0af7ff534bcbebe17acaf6b7df75468aa7d",   # misses [43, 12, 9, 15, 38] wrap decides 2/5
    ("sq small ring", 2) => "6b462569b5c9e3c1851c54f3665a8f7f2311f93bf1f8a3a765f8b3f3b7662975",   # misses [8, 6, 3, 17, 11] wrap decides 4/5
    ("sq tight ring", 0) => "7136057b720760d7d1fc6892eeb6d16883b5aad5bf928871aaa5307e2ab83676",   # misses [31, 17, 8, 28, 9] wrap decides 0/5
    ("sq tight ring", 1) => "6153a13c9e8fa8cb813ed6162a98624432409484abfb385e97a01a96be76a7b2",   # misses [46, 7, 22, 23, 10] wrap decides 3/5
    ("sq tight ring", 2) => "e15d9aa2b3b0c4b27063a5928cc1471d457c6577d9d79edf0a0da9cf24108484",   # misses [2, 1, 9, 3, 14] wrap decides 2/5
    ("sq unit boxes", 0) => "becf2df95586f14fe2052881a3fdacedb487d10b627677f599232e36911331b6",   # misses [85, 114, 99, 120, 108]
    ("sq unit boxes", 1) => "9ff62d532edcd4d474f93499fc2b65834e6e29a0ded4b714bac5035e15100282",   # misses [38, 73, 64, 44, 64]
    ("sq unit boxes", 2) => "926789f0698d1f73d3c0e0d687e479dd5a0bc4ec8eb26f55f02ce4fafc5e7d76",   # misses [34, 10, 12, 6, 31]
    ("sq unit boxes periodic", 0) => "becf2df95586f14fe2052881a3fdacedb487d10b627677f599232e36911331b6",   # misses [85, 114, 99, 120, 108] wrap decides 0/5
    ("sq unit boxes periodic", 1) => "48b42e6a03eea4a807df19e296123617c03d431f203085cea2f852be5a107853",   # misses [73, 73, 64, 104, 69] wrap decides 5/5
    ("sq unit boxes periodic", 2) => "2688522efc282902c7be1ff7b4969168bb007b37e548dcb54522ca9f4d010453",   # misses [34, 82, 33, 7, 41] wrap decides 4/5
    ("sq dense", 0) => "a3a63f49344d328bc2225c73b4413d21323add3a52d4efc7e5fea637cf139fa0",   # misses [357, 425, 309, 368, 349]
    ("sq dense", 1) => "97a3fb1bd817735083eba360d0ca468d81dc6fd004871851f6f77d4ddff680ac",   # misses [100, 393, 224, 161, 104]
    ("sq dense", 2) => "66318d46337b188efeac4ad7487f6d562db28fbcacbef7d400512c7614c7d93f",   # misses [14, 25, 61, 11, 20]
    ("sq dense periodic", 0) => "a3a63f49344d328bc2225c73b4413d21323add3a52d4efc7e5fea637cf139fa0",   # misses [357, 425, 309, 368, 349] wrap decides 0/5
    ("sq dense periodic", 1) => "4ba059ff73609cca4eafde6ccdea1753fc71aedaca6aaa65027af0b524d592ce",   # misses [225, 281, 471, 169, 227] wrap decides 5/5
    ("sq dense periodic", 2) => "0ba8c23a5f811cdd2a6b1c828fd6128adf57b12d1621e56e842a700d4d3ef0fa",   # misses [57, 57, 140, 61, 39] wrap decides 5/5
    ("merks-like", 0) => "c12612b52ea0a6ebdd1df330904ec2c6556664485d71c6bd7c7c7549004580a4",   # misses [60, 91, 80, 83, 63]
    ("merks-like", 1) => "e8da1c643acf70968a82a00ed1e99a3cfd5db35ccf3efdcabb0c5efa0b94e7d9",   # misses [92, 123, 97, 142, 95]
    ("merks-like", 2) => "4d76e8915eb857c174d6840f60d82142a05603bc60ee39676aebe1beca6b61ce",   # misses [135, 168, 186, 204, 143]
    ("cube closed", 0) => "25894df3cf5dcba4215a6323535210ce14e82c7eadc32e3b098b005c536537ec",   # misses [83, 134, 64, 61, 39]
    ("cube closed", 1) => "255e976124d41feca4e26d16597ee641d7a1b23aa7b307b91d1d6f6dee60bca5",   # misses [28, 22, 23, 20, 36]
    ("cube closed", 2) => "aad92b035f67bc454b0d6af4590d7bb420b7222a163c7a86e8c566d1d45f87d6",   # misses [13, 6, 4, 2, 21]
    ("cube periodic", 0) => "25894df3cf5dcba4215a6323535210ce14e82c7eadc32e3b098b005c536537ec",   # misses [83, 134, 64, 61, 39] wrap decides 0/5
    ("cube periodic", 1) => "052eda5f0abc9739cd04a5b7999a9c0437867435aab3f0499e66a5404c94bf6e",   # misses [85, 25, 64, 47, 78] wrap decides 5/5
    ("cube periodic", 2) => "6ebfd2dce33d8ad33841e0995b269ecdd7ecba3ee5b9fd78ebe17e8e92569b9f",   # misses [28, 25, 22, 13, 16] wrap decides 5/5
    ("cube periodic z", 0) => "25894df3cf5dcba4215a6323535210ce14e82c7eadc32e3b098b005c536537ec",   # misses [83, 134, 64, 61, 39] wrap decides 0/5
    ("cube periodic z", 1) => "292e79632f249ba0c6108634178c00fc4e94f9ca979285beed8c6fdb2bdc0a9a",   # misses [85, 25, 24, 24, 43] wrap decides 5/5
    ("cube periodic z", 2) => "74791d070e05268c78beca5c4e9fbab057fbf345a8bd79c584b1410e99e8ff14",   # misses [13, 6, 4, 2, 21] wrap decides 1/5
    ("cube edge region periodic", 0) => "05a89c0b914d0ef35b92c50683318406b15689ab3df1accdd2e547feaff612c5",   # misses [13, 41, 36, 8, 29] wrap decides 0/5
    ("cube edge region periodic", 1) => "1b9196b3a401d4c687828863a182e402a4706ef9b415b08c60eca2af1d9d69e4",   # misses [1, 8, 0, 5, 8] wrap decides 1/5
    ("cube edge region periodic", 2) => "019e7a99ffd9ae534848fe32b7bd8f895e053a088b24d652114d3d9c3264bbe3",   # misses [0, 4, 12, 4, 9] wrap decides 2/5
    ("cube dense", 0) => "c1d420a635b998989d57a5efbe5649b26ffcb5b00987e3323195fd7687548d20",   # misses [595, 781, 764, 487, 599]
    ("cube dense", 1) => "fc3433e4ed7b8d7dbbfaa2d58fcc515b656b0a54575a81e4c6b612792225c9c4",   # misses [89, 63, 129, 54, 90]
    ("cube dense", 2) => "34ac00443bac7d909d52bb07e9c9589b145cbfa2c3f860b30a11433c71a9598f",   # misses [10, 15, 20, 12, 14]
    ("cube dense periodic", 0) => "c1d420a635b998989d57a5efbe5649b26ffcb5b00987e3323195fd7687548d20",   # misses [595, 781, 764, 487, 599] wrap decides 0/5
    ("cube dense periodic", 1) => "f810bb1a8a9ef3f393aa0f7c43d0e5bbb75e83dbf236d9bf9f089bd044797dff",   # misses [827, 142, 215, 89, 143] wrap decides 5/5
    ("cube dense periodic", 2) => "058f7e1fb8073bcf56fb15c13ea4b98de813bca4fac4e0e618f125de00945c46",   # misses [72, 275, 102, 49, 60] wrap decides 5/5
    ("hex closed", 0) => "352d271ad098f26209c1b50fbc12adab828ad4722b278ae5fe98e2e81adf600b",   # misses [19, 20, 37, 11, 15]
    ("hex closed", 1) => "9ac11391db0d05fadde60f0aa3f3618f90bcf7c767353cd2a6ed0e58b400731e",   # misses [10, 56, 19, 5, 27]
    ("hex closed", 2) => "e8cc95875f16d39b344042506d3ab64bbeabd5750b0abe8d9ad934731abc344e",   # misses [7, 5, 2, 2, 18]
    ("hex periodic", 0) => "352d271ad098f26209c1b50fbc12adab828ad4722b278ae5fe98e2e81adf600b",   # misses [19, 20, 37, 11, 15] wrap decides 0/5
    ("hex periodic", 1) => "4868d0d8fd682fc28df3db712312d80f4aecc0e3e3f0e705adef1aed907b32f6",   # misses [14, 56, 22, 72, 39] wrap decides 4/5
    ("hex periodic", 2) => "6fa72d16a3873a3839e9292ca074a976409480ea80677ee188eca2767f3c2da5",   # misses [13, 5, 25, 8, 18] wrap decides 3/5
    ("hex periodic x", 0) => "352d271ad098f26209c1b50fbc12adab828ad4722b278ae5fe98e2e81adf600b",   # misses [19, 20, 37, 11, 15] wrap decides 0/5
    ("hex periodic x", 1) => "5fc9bfcf62837e2646327d1604a9fda6b7cc09443e2b4615acdd558712e74fa8",   # misses [10, 56, 19, 8, 27] wrap decides 1/5
    ("hex periodic x", 2) => "5096bbb4d91da4bdea5b04a2b9f654b672d2c46ad064d68c8f7f63dbe0064ec3",   # misses [7, 5, 6, 2, 18] wrap decides 1/5
    ("hex edge region periodic", 0) => "292cb75736212896fddad2c5d8a105f0f999e042a954251366eac762cfca200e",   # misses [14, 15, 7, 16, 12] wrap decides 0/5
    ("hex edge region periodic", 1) => "8800d5b65142940928f3b907ac5e17ac8c318a0a24a0b25e3aa61654ab29fe32",   # misses [8, 5, 0, 2, 5] wrap decides 1/5
    ("hex edge region periodic", 2) => "698902e0ec6646cc4952d7e0d6607b5e2eb1ca38a66250e218f991ed38771c89",   # misses [8, 0, 0, 8, 3] wrap decides 2/5
    ("hex dense periodic", 0) => "a3a63f49344d328bc2225c73b4413d21323add3a52d4efc7e5fea637cf139fa0",   # misses [357, 425, 309, 368, 349] wrap decides 0/5
    ("hex dense periodic", 1) => "c6a6e4978a4eb0b4beec131ddb12bc21edc45b56e0fa6f29b86f4df2d5c06656",   # misses [131, 281, 340, 144, 150] wrap decides 5/5
    ("hex dense periodic", 2) => "0ba8c23a5f811cdd2a6b1c828fd6128adf57b12d1621e56e842a700d4d3ef0fa",   # misses [57, 57, 140, 61, 39] wrap decides 5/5
    ("sq tiling+scattered periodic", 0) => "40d3c2df89fc8089930019de51172f661139404bb0d74840f673672c85be095f",   # seed 1 rows [(:Tiling, 48, 48, 0, 0, 48, 0), (:Scattered, 8, 8, 0, 0, 8, 0)]
    ("sq tiling+scattered periodic", 1) => "b67c9eb56c55487670e258b27600dd48b722eab12b26cbf2fe06299b56b1f30b",   # seed 1 rows [(:Tiling, 48, 48, 0, 0, 48, 0), (:Scattered, 8, 8, 0, 0, 8, 0)]
    ("sq tiling+scattered periodic", 2) => "4689bec428abeaabd1d5d2bf167b37cc5a8fefe921e0c8d06ffc1d5d7d2f7de3",   # seed 1 rows [(:Tiling, 48, 48, 0, 0, 48, 0), (:Scattered, 8, 8, 0, 0, 8, 0)]
    ("hex tiling+scattered closed", 0) => "b5399b823454d166545949cada2eca3a9a2f70819cf9cd41197b3cffb4b51878",   # seed 1 rows [(:Tiling, 42, 42, 1, 0, 42, 0), (:Scattered, 8, 8, 0, 0, 8, 0)]
    ("hex tiling+scattered closed", 1) => "d393b4c1f6b9ce23a007e85cde90de3eb312c12ea0d744281af4106256d7faab",   # seed 1 rows [(:Tiling, 42, 42, 1, 0, 42, 0), (:Scattered, 8, 8, 0, 0, 8, 0)]
    ("hex tiling+scattered closed", 2) => "de271fd585bca9c895e2d6ce7116da2353c69e99d5e33ab018518b5b92bcefdf",   # seed 1 rows [(:Tiling, 42, 42, 1, 0, 42, 0), (:Scattered, 8, 8, 0, 0, 8, 0)]
    ("cube scattered+scattered periodic", 0) => "c82c73e85e09de8277c97ffa3903c58b47be6fc2fecb97dc3868e329e2abd93f",   # seed 1 rows [(:Scattered, 10, 10, 0, 0, 10, 0), (:Scattered, 6, 6, 0, 0, 6, 0)]
    ("cube scattered+scattered periodic", 1) => "330faf1e2609ce5e9e2114803233586886266e8845ca6e4eb7a6eca59d99d7ac",   # seed 1 rows [(:Scattered, 10, 10, 0, 0, 10, 0), (:Scattered, 6, 6, 0, 0, 6, 0)]
    ("cube scattered+scattered periodic", 2) => "d8b297491ee8d3e8c023f7328238e2fc880e835371263cbb66d4649305059f1c",   # seed 1 rows [(:Scattered, 10, 10, 0, 0, 10, 0), (:Scattered, 6, 6, 0, 0, 6, 0)]
)
# Merks-like, gap 1: SHA-256 of σ per seed
const P61A7_MERKS = [
    1 => "ec9c25a22b2cd9750f3906beaeed3cf10391ce842ac0d7b38bbf3d4d97bc15a2",
    2 => "961cb54ed44f7debc10d99bb32ed1bbd8d737cce9d332f44afa972c8f8acaddb",
    3 => "8fd1532db28129056006c48fc083d52de0011baa650e7e97c3493a4d5770d197",
    4 => "8c066036c7ce2b4d81d3bd7c302460849f85c89594607a074b26e35dab68599e",
]
# the timed requests (seed 1, gap 1): SHA-256 of σ
const P61A7_TIMED = Dict(
    "cubes closed" => "a71085a5ac1301b964938fe3c5769a61bb3c85b8c0dc562a61ecaa656535c890",
    "cubes periodic" => "38826b9023717c93989cb96790823a6fff99b7b251fc1ad14552562dc5b92e6d",
    "squares 4e3" => "9f86cbf74176e5458304ae0859ab0d3f483cb763c505cdc849624269af05e373",
    "squares 4e4" => "778c602028a9f0b5a8eaa03b7329a7c3cd5e96cf128fc985f1324476f453653d",
)
# the 10,000-draw limit: Scattered(n, (30, 30); kinds = [:a], seed, gap = 1) at 100², closed,
# where one box is placed only after 9,845 (n = 7, seed 1290) or 7,191 (n = 6, seed 2329)
# draws, and seed 9909 jams at box 6 (it would be placed at draw 14,042); draw counts by
# brute force, /tmp/p61a7/search_late.jl
const P61A7_LIMIT = Dict(
    (7, 1290) => "77deb452ba0fdc49e2ab9b1164cd344d00b6bac5e956c54ff0e41e19a9dac5c5",
    (6, 2329) => "85cf2f1a2d78ab61701d216a07be682564d6e2be6e62af55a88979f9549ed111",
)

p61a7_error(l, x) =
    try
        layout(l, x)
        "no error"
    catch e
        e isa ArgumentError || rethrow()
        sprint(showerror, e)
    end

# The best (minimum) of up to `runs` timed calls of `f`, a `GC.gc()` before each; stops at
# the first run for which `done(best)` holds. Returns `(best seconds, value of the last call)`.
function p61a7_best(f, runs, done)
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

@testset "P6.1a7 Scattered occupancy mask" begin
    @testset "σ, kinds and report rows as at a5a2819" begin
        @testset "$name" for (name, c) in P61A7_CASES
            for gi in eachindex(P61A7_GAPS)
                @test (gi, p61a7_config_digest(c, gi)) == (gi, P61A7_EXPECTED[(name, P61A7_GAPS[gi])])
            end
        end
        @testset "$name" for (name, c) in P61A7_LAYERED
            for gi in eachindex(P61A7_GAPS)
                @test (gi, p61a7_layered_digest(c, gi)) == (gi, P61A7_EXPECTED[(name, P61A7_GAPS[gi])])
            end
        end
        @test length(P61A7_EXPECTED) == 3 * (length(P61A7_CASES) + length(P61A7_LAYERED))
        # the grid discriminates (a check on the table): the wrap changes the placement for
        # gap ≥ 1 and cannot for gap 0
        E = P61A7_EXPECTED
        for (p, c) in (("sq periodic", "sq closed"), ("sq periodic x", "sq closed"), ("sq periodic y", "sq closed"),
                ("sq dense periodic", "sq dense"), ("sq unit boxes periodic", "sq unit boxes"),
                ("cube periodic", "cube closed"), ("cube periodic z", "cube closed"), ("cube dense periodic", "cube dense"),
                ("hex periodic", "hex closed"), ("hex periodic x", "hex closed"))
            @test E[(p, 0)] == E[(c, 0)]
            @test E[(p, 1)] != E[(c, 1)] && E[(p, 2)] != E[(c, 2)]
        end
        # Merks-like (D-087), one σ digest per seed
        for (s, d) in P61A7_MERKS
            l = Scattered(282, (7, 7); region = (85:415, 85:415), kinds = [:endothelial], seed = s, gap = 1)
            @test (s, p61a7_digest(p61a7_get(layout(l, (500, 500)), ownership))) == (s, d)
        end
        # the jam error at the same box (the same draws up to it), and the area bound
        @test occursin(r"could not place box 18 of 25\b",
            p61a7_error(Scattered(25, (3, 3); kinds = [:a], seed = 7, gap = 1), (20, 20)))
        @test occursin(r"could not place box 18 of 25\b",
            p61a7_error(Scattered(25, (3, 3); kinds = [:a], seed = 7, gap = 1),
                Lattice((20, 20); boundary = Periodic(), geometry = Hexagonal())))
        @test occursin(r"could not place box 16 of 20\b",
            p61a7_error(Scattered(20, (2, 2, 2); kinds = [:a], seed = 7, gap = 2), Lattice((12, 12, 12); boundary = Periodic())))
        @test occursin("cannot fit", p61a7_error(Scattered(21, (3, 3); kinds = [:a], seed = 1, gap = 2),
            Lattice((8, 40); boundary = (Periodic(), Closed()))))
        # the documented 10,000-draw limit, from both sides
        for ((n, s), d) in P61A7_LIMIT
            l = Scattered(n, (30, 30); kinds = [:a], seed = s, gap = 1)
            @test (n, s, p61a7_digest(p61a7_get(layout(l, (100, 100)), ownership))) == (n, s, d)
        end
        @test occursin(r"could not place box 6 of 6\b",
            p61a7_error(Scattered(6, (30, 30); kinds = [:a], seed = 9909, gap = 1), (100, 100)))
    end

    @testset "cost" begin
        cubes = Scattered(10_000, (5, 5, 5); kinds = [:a], seed = 1, gap = 1)
        per3 = Lattice((200, 200, 200); boundary = Periodic())
        sq(n) = Scattered(n, (7, 7); kinds = [:a], seed = 1, gap = 1)
        # warm-up: the same method instances on small lattices
        layout(Scattered(2, (5, 5, 5); kinds = [:a], seed = 1, gap = 1), (20, 20, 20))
        layout(Scattered(2, (5, 5, 5); kinds = [:a], seed = 1, gap = 1), Lattice((20, 20, 20); boundary = Periodic()))
        layout(sq(2), (40, 40))

        t, op = p61a7_best(() -> layout(cubes, (200, 200, 200)), 5, <=(0.050))
        @test p61a7_digest(p61a7_get(op, ownership)) == P61A7_TIMED["cubes closed"]
        @test 1000t <= 50                          # ms; ≈ 480 at a5a2819

        t, op = p61a7_best(() -> layout(cubes, per3), 5, <=(0.050))
        @test p61a7_digest(p61a7_get(op, ownership)) == P61A7_TIMED["cubes periodic"]
        @test 1000t <= 50                          # ms; ≈ 860 at a5a2819

        # time per placed box does not grow with the number placed (same density)
        ts, op = p61a7_best(() -> layout(sq(4_000), (949, 949)), 7, _ -> false)
        @test p61a7_digest(p61a7_get(op, ownership)) == P61A7_TIMED["squares 4e3"]
        tl, op = p61a7_best(() -> layout(sq(40_000), (3000, 3000)), 3, t -> (t / 40_000) / (ts / 4_000) <= 2.5)
        @test p61a7_digest(p61a7_get(op, ownership)) == P61A7_TIMED["squares 4e4"]
        ratio = (tl / 40_000) / (ts / 4_000)
        @test ratio <= 2.5                         # ≈ 9.8 at a5a2819
    end
end

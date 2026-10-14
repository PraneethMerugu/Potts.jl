# P6.5c (ROADMAP Phase 6, step 5; third step of Fortuna, reproduction 14), part A of 3: the
# initial-state vocabulary (R2). `Interior`, `Fill`, `Objects`, `Group`, `set_column!`, and
# `layout` emitting `cluster` and per-cell columns. Frozen (AUTONOMY §7.3).
# Part B, `p6_5c_predicate_source.jl`: the predicate-sourced PDE source (R5). Part C,
# `p6_5c_msd_furth.jl`: MSD and the modified Fürth fits (R16).
#
# Spec: docs/design/research/p6-5c-brief.md (the spec owner's brief, 2026-10-14) §1.A, §3.A,
# §4.A, §4.D. Decisions: D-087 (`Fill`/`Objects`/`Group` replace `Plane`/`Spheres`, no named
# aliases, docs recipes), D-138 (GeometryBasics round shapes, CLOSED membership with
# r·(1 + 1e-12), `clipped`, no `Rect`), D-141 (seed-and-grow, `[−L/2, L/2)` ties), D-091
# (the layout protocol and the report row schema), D-057 (the split check), D-135 (kind
# classes are not layer kinds), D-233 (E1: kind-conditional expression defaults, already
# merged), D-048 (oracles and negative controls).
#
# ROADMAP (P6.5c row): "R2 `Plane`, `Spheres`; … Initial-state vocabulary … `Fill`,
# `Objects(Sphere…)` and `Group` (with `set_column!`) in place of `Plane`/`Spheres`; amends
# D-075 §3.3, user-approved 2026-10-01 (D-087); the docs show `Plane`/`Spheres` recipes."
#
# =========================================================================================
# THE PUBLIC API THESE TESTS EXPECT (brief §3.A; names, signatures, semantics)
# =========================================================================================
#
# A1. `Interior(s)` (exported). `s` a `HyperSphere{N}` (`Circle`, `Sphere`); anything else,
#     and `Interior(Interior(s))`, is an `ArgumentError`; centre finite, radius finite ≥ 0
#     (as `_shape_arg`). MEMBERSHIP (strict): site x is inside iff
#         norm(center − embed(x)) < r·(1 − 1e-12)
#     for x or one of its periodic images. A site at exactly r (hex sites with √3/2 rounding
#     included) is OUT. Wrapping, clipping at closed edges and at the domain, and `clipped`
#     are D-138's with U = the index points strictly inside. Accepted wherever a shape is:
#     the `Objects` shape and the `region =` of `Fill`, `RandomPoints`, `Voronoi`, `Eden`.
#     r = 0 is the empty set.
# A2. `Fill(kind; region = <whole lattice>, splits = :warn)` (exported). One cell of `kind`
#     owning every in-domain site of `region` (`nothing`, a shape or `Interior`, or a tuple
#     of unit ranges in lattice indices), overwriting earlier layers (no `into`). Report
#     row `:Fill`: requested = painted = 1, misses 0, counted 1, `clipped` per D-138 (box
#     sites outside the domain count), dropped 1 if a later layer removes every site.
#     `ArgumentError`s: a region with no in-domain site ("Fill: the region has no site in the
#     lattice's domain"), a box outside the lattice (the existing `_region` message), a
#     dimension mismatch, a bad `splits`, a vector `kind`. `remake(f; region)` works.
#     RNG-free.
# A3. `Objects(shape, points = nothing; kinds, splits = :warn)` (exported). One cell per
#     copy: without `points` the shape where it is; with `points` (`RandomPoints`,
#     `Center()`, a `Point`, a vector of `Point`s/`Center()`s) copy k is the shape
#     TRANSLATED by point k's Cartesian vector (templates centred at the origin). Ids in
#     copy order, `kinds` cycled. Overwrites earlier layers; WITHIN the layer the FIRST copy
#     wins. Row `:Objects`: requested = painted = copies, misses 0, counted = painted,
#     dropped = copies with no site after the whole layout, clipped = Σ per-copy D-138
#     counts (sites lost to an earlier copy are not clipped). `ArgumentError`s: empty
#     `kinds`, a shape that is not round, an empty point vector, a dimension mismatch (at
#     `layout`), a bad `splits`. `remake(o; points)` works.
# A4. `Group(layers...)` (exported). Paints its children exactly like `overlay` (each child
#     a leaf row; no row and no column of its own; ids in paint order). Every cell allocated
#     while a child paints belongs to the group; the surviving ones form ONE cluster. Allowed
#     as the top-level layout or a member of a top-level `overlay`; inside another `Group`
#     (directly or through an `overlay`), as `Splits`' inner layer, or inside a custom
#     layer's `paint!` it is an `ArgumentError`. `Group()` is an `ArgumentError`; `remake`
#     of a `Group` is the existing "does not support remake" `ArgumentError`.
# A5. `Potts.set_column!(op::LayoutState, name::Symbol, id::Integer, value)` (public, NOT
#     exported). Records `value` for cell `id` (must be in 1:ncells(op), else an
#     `ArgumentError` naming the id and ncells); `name ∈ (:ownership, :kind)` is an
#     `ArgumentError`; setting twice overwrites; a call outside a layer's `paint!` is an
#     `ArgumentError`. `:cluster`: labels compared with `isequal`, equal labels form one
#     cluster, a `Group`'s label never equals a user label. Other names: per-cell columns
#     emitted as `name => values` (a model's cell variable, e.g. `:V_target`).
# A6. `layout(l, x)` returns `[ownership => σ, kind => kinds, (cluster => ids)?,
#     (name => values)…]`:
#     - `cluster` iff some cell got a label (by `Group` or `set_column!`): ids[c] = the final
#       id of the lowest-id surviving cell with the same label; an unlabelled cell gets its
#       own final id (so a layout with one `Group` first reads 1 for the group's cells);
#     - user columns, one per name in order of first `set_column!`, compacted with the cells,
#       element type `identity.` of the values; if a surviving cell lacks a value for a user
#       column, an `ArgumentError` at the end of `layout` naming the column and the missing
#       cells' final ids (brief Q-5; `:cluster` exempt: an unset cell is its own cluster);
#     - with neither, exactly today's two entries, byte for byte (pinned below);
#     - `report = true` returns `(point, rows)`, rows unchanged in schema.
# A7. `_layer_kinds` covers `Fill`, `Objects` and `Group`: `layout(…, sys)` rejects a kind
#     class (D-135) before painting.
# A8. Docs (D-087): `docs/src/manual/layouts.md` lists `Fill`, `Objects`, `Group` in the
#     built-in-layers table and shows a `Fill(` plane recipe, an `Objects(` sphere recipe and
#     a `Group(` compartment example (brief §4.D docs check).
#
# Hand counts. Every count below was re-derived by the test author by brute force (an
# exhaustive scan of every lattice site with the membership rule, exact integer squared
# distances where the centre and r² are integers) on the freeze base 588ad407; they agree
# with the brief's [probe] counts. The test computes the same oracles itself
# (`p65c_oracle_sites`), independently of the code under test (no bounding box, no
# `_region_sites`).
#
# Sections: 1 names; 2 strict vs closed membership (A1 table); 3 `Interior` validation and
# use as a region; 4 clipping, wrap and domain (A2); 5 `Fill` basics (A3); 6 `Objects` basics
# (A4); 7 `Group` and `cluster` (A5 a–f); 8 `set_column!` (A5 h); 9 `Group` into
# `PottsProblem` (A5 g); 10 the Fortuna geometry (A6); 11 the 2D analogue; 12 determinism and
# laziness (A7); 13 the kinds check; 14 docs.
#
# Controls (pass on the freeze base) are marked `control`; assertions that fail today
# carry `DEFECT CHECK` (one per testset marks the first, the rest of the testset fails
# with it). `negative control` marks a check that the rule under test matters (the other
# rule, or the mechanism off, gives a different answer); it may use the new names. The new names do not exist on the freeze base, so a testset that uses
# them errors at its first use (UndefVarError); the file itself loads.
using Test, Potts, PottsModels
using Potts: CorePotts
using SHA: sha256
using StableRNGs: StableRNG

# ---------------------------------------------------------------------------------------
# 0. Helpers (independent of the code under test)

p65c_σ(op) = op[1].second
p65c_kinds(op) = op[2].second
# the entry of an operating point with key `key` (`cluster`, a Symbol), or nothing
p65c_entry(op, key) = (i = findfirst(p -> isequal(p.first, key), op); i === nothing ? nothing : op[i].second)
p65c_cluster(op) = p65c_entry(op, Potts.cluster)
p65c_digest(σ) = bytes2hex(sha256(reinterpret(UInt8, vec(htol.(σ)))))
p65c_kdigest(k) = bytes2hex(sha256(join(string.(k), ',')))
p65c_sites(σ, id) = Set(Tuple.(findall(==(id), σ)))
# the partition of 1:n into classes of equal label
p65c_partition(labels) = Set(Set(findall(==(l), labels)) for l in unique(labels))
# `layout(l, x; report = true)` (a call `@test_logs` can wrap)
p65c_report(l, x) = layout(l, x; report = true)

# Cartesian embedding of an index point (the identity on square lattices; axial (q, r) →
# (q + r/2, r·√3/2) on hexagonal ones)
p65c_cart(x, hex) = hex ? (x[1] + x[2] / 2, x[2] * sqrt(3) / 2) : Float64.(Tuple(x))

# Brute-force oracle: every lattice site of `dims` (in the domain `mask`, if any) whose
# squared distance to `c` (any periodic image; k ∈ -1:1 suffices here) satisfies `inside`.
# `inside(d2)` is the rule: exact for integer d2 (square lattice, integer centre), the
# brief's tolerance rule on Float64 distances otherwise.
function p65c_oracle_sites(dims, c, inside; per = map(_ -> false, dims), hex = false, mask = nothing)
    N = length(dims)
    out = Set{NTuple{N, Int}}()
    for I in CartesianIndices(dims)
        x = Tuple(I)
        mask === nothing || mask(x) || continue
        ks = Iterators.product(ntuple(d -> per[d] ? (-1:1) : (0:0), N)...)
        any(k -> inside(sum(abs2, p65c_cart(x .+ k .* dims, hex) .- c)), ks) && push!(out, x)
    end
    return out
end
# the rules: exact integer forms and the brief's tolerance forms
p65c_strict_int(r2) = d2 -> round(Int, d2) < r2
p65c_closed_int(r2) = d2 -> round(Int, d2) <= r2
p65c_strict_tol(r) = d2 -> sqrt(d2) < r * (1 - 1e-12)
p65c_closed_tol(r) = d2 -> sqrt(d2) <= r * (1 + 1e-12)
# the hexagonal squared distance between site-centred points is a² + ab + b² (exact)
p65c_hex_count(r2; strict) = count(((a, b),) -> (q = a^2 + a * b + b^2; strict ? q < r2 : q <= r2),
    Iterators.product(-10:10, -10:10))

const P65C_ROW_KEYS = (:layer, :type, :requested, :painted, :dropped, :misses, :counted, :clipped, :splits)

# A custom layer (D-091 protocol) that paints one site per entry of `labels` along row
# `y`, starting at column `x0`, and, for each non-`nothing` label, calls
# `set_column!(op, name, id, label)`. `twice`: set the first cell's value twice (the second
# value must win).
struct P65cLabels <: Potts.AbstractLayout
    name::Symbol
    labels::Vector{Any}
    y::Int
    x0::Int
    kind::Symbol
    twice::Bool
end
P65cLabels(name, labels; y = 1, x0 = 1, kind = :a, twice = false) = P65cLabels(name, Any[labels...], y, x0, kind, twice)
function Potts.paint!(op::Potts.LayoutState, l::P65cLabels, lat)
    for (k, lab) in enumerate(l.labels)
        id = Potts.new_cell!(op, l.kind)
        Potts.assign!(op, (l.x0 + k - 1, l.y), id)
        if lab !== nothing
            l.twice && k == 1 && Potts.set_column!(op, l.name, id, :overwritten_value)
            Potts.set_column!(op, l.name, id, lab)
        end
    end
    Potts.record!(op; requested = length(l.labels), painted = length(l.labels))
    return nothing
end
# custom layers that misuse `set_column!` (each call must throw)
struct P65cBadColumn <: Potts.AbstractLayout
    mode::Symbol
end
function Potts.paint!(op::Potts.LayoutState, l::P65cBadColumn, lat)
    id = Potts.new_cell!(op, :a)
    Potts.assign!(op, (1, 1), id)
    l.mode === :kind && Potts.set_column!(op, :kind, id, :b)
    l.mode === :ownership && Potts.set_column!(op, :ownership, id, 3)
    l.mode === :unallocated && Potts.set_column!(op, :V_target, id + 1, 1.0)
    l.mode === :zero && Potts.set_column!(op, :V_target, 0, 1.0)
    return nothing
end
# a custom layer setting `:q` (Int), then `:cluster` and `:r` (String) on three cells
struct P65cMulti <: Potts.AbstractLayout end
function Potts.paint!(op::Potts.LayoutState, ::P65cMulti, lat)
    ids = [Potts.new_cell!(op, :a) for _ in 1:3]
    foreach(k -> Potts.assign!(op, (k, 1), ids[k]), 1:3)
    foreach(k -> Potts.set_column!(op, :q, ids[k], k), 1:3)
    Potts.set_column!(op, :cluster, ids[1], :x)
    Potts.set_column!(op, :cluster, ids[3], :x)
    foreach(k -> Potts.set_column!(op, :r, ids[k], ("s", "t", "u")[k]), 1:3)
    return nothing
end
# a custom layer that keeps its `op` (to call `set_column!` after the layout is painted)
const P65C_KEPT = Ref{Any}(nothing)
struct P65cKeep <: Potts.AbstractLayout end
function Potts.paint!(op::Potts.LayoutState, ::P65cKeep, lat)
    id = Potts.new_cell!(op, :a)
    Potts.assign!(op, (1, 1), id)
    P65C_KEPT[] = op
    return nothing
end
# a custom layer that paints a `Group` inside its own `paint!` (must throw)
struct P65cPaintsGroup <: Potts.AbstractLayout end
Potts.paint!(op::Potts.LayoutState, ::P65cPaintsGroup, lat) =
    Potts.paint!(op, Group(Fill(:a; region = (1:2, 1:2))), lat)

# the error message of `f()` ("" if it does not throw an ArgumentError)
p65c_msg(f) = try
    f()
    ""
catch e
    e isa ArgumentError ? e.msg : ""
end

# ---------------------------------------------------------------------------------------
# 1. Names

@testset "P6.5c initial state: the new names are exported, `set_column!` is public" begin
    for n in (:Interior, :Fill, :Objects, :Group)
        @test Base.isexported(Potts, n)                          # DEFECT CHECK
    end
    @test Base.ispublic(Potts, :set_column!)                     # DEFECT CHECK
    @test !Base.isexported(Potts, :set_column!)                  # public, not exported (control today: absent)
    # D-087: no named aliases for the replaced layers; D-138: no `Rect`
    for n in (:Plane, :Spheres, :Rect)
        @test !isdefined(Potts, n)                               # control
    end
    @test Base.isexported(Potts, :Sphere) && Base.isexported(Potts, :Circle)   # control (D-138)
end

# ---------------------------------------------------------------------------------------
# 2. Strict vs closed membership: the brief's A1 table (centre on a site, lattice large
#    enough, closed). `Fill(:a; region = shape)` paints exactly the oracle's sites.

# (label, dims, centre index, shape builder, r², strict count, closed count, hex?)
const P65C_A1 = [
    ("2D square, r = 1", (21, 21), (11, 11), 1.0, 1, 1, 5, false),
    ("2D square, r = 2", (21, 21), (11, 11), 2.0, 4, 9, 13, false),
    ("2D square, r = 3", (21, 21), (11, 11), 3.0, 9, 25, 29, false),
    ("2D square, r = 5", (21, 21), (11, 11), 5.0, 25, 69, 81, false),
    ("3D cubic, r = 1", (13, 13, 13), (7, 7, 7), 1.0, 1, 1, 7, false),
    ("3D cubic, r = 2", (13, 13, 13), (7, 7, 7), 2.0, 4, 27, 33, false),
    ("3D cubic, r = 3", (13, 13, 13), (7, 7, 7), 3.0, 9, 93, 123, false),
    ("hex, r = 1", (21, 21), (11, 11), 1.0, 1, 1, 7, true),
    ("hex, r = √3", (21, 21), (11, 11), sqrt(3.0), 3, 7, 13, true),
    ("hex, r = 2", (21, 21), (11, 11), 2.0, 4, 13, 19, true),
]
p65c_shape(c, r) = length(c) == 2 ? Circle(Point(Float64.(c)...), r) : Sphere(Point(Float64.(c)...), r)
p65c_target(dims, hex) = hex ? Lattice(dims; geometry = Hexagonal(), boundary = Closed()) :
                         Lattice(dims; boundary = Closed())

@testset "P6.5c initial state: strict (`Interior`) vs closed membership, the A1 table ($(case[1]))" for case in P65C_A1
    label, dims, ci, r, r2, nstrict, nclosed, hex = case
    c = p65c_cart(ci, hex)
    # the oracle reproduces the table (exact integer squared distances), and the hex counts
    # agree with the a² + ab + b² form
    os = p65c_oracle_sites(dims, c, p65c_strict_int(r2); hex)
    oc = p65c_oracle_sites(dims, c, p65c_closed_int(r2); hex)
    @test length(os) == nstrict && length(oc) == nclosed         # control (oracle)
    hex && @test p65c_hex_count(r2; strict = true) == nstrict && p65c_hex_count(r2; strict = false) == nclosed
    # the tolerance rules give the same sets (no site sits within 1e-12 of r but off it)
    @test os == p65c_oracle_sites(dims, c, p65c_strict_tol(r); hex)
    @test oc == p65c_oracle_sites(dims, c, p65c_closed_tol(r); hex)
    @test nstrict != nclosed                                     # negative control: the rules differ
    target = p65c_target(dims, hex)
    s = p65c_shape(c, r)
    # today's closed rule, through an existing shape layer (a single Voronoi generator fills
    # its region): the closed column
    v = layout(Voronoi([Point(c...)]; region = s, kinds = [:a]), target)
    @test p65c_sites(p65c_σ(v), 1) == oc                         # control
    # `Interior`: the strict column
    op = layout(Fill(:a; region = Interior(s)), target)          # DEFECT CHECK
    @test p65c_sites(p65c_σ(op), 1) == os
    @test p65c_kinds(op) == [:a]
    # `Fill` with the closed shape: the closed column
    @test p65c_sites(p65c_σ(layout(Fill(:a; region = s), target)), 1) == oc
    # `Objects` with the shape where it is: the same sets
    @test p65c_sites(p65c_σ(layout(Objects(Interior(s); kinds = [:a]), target)), 1) == os
    @test p65c_sites(p65c_σ(layout(Objects(s; kinds = [:a]), target)), 1) == oc
end

# ---------------------------------------------------------------------------------------
# 3. `Interior`: validation, r = 0, and use as the region of existing layers

@testset "P6.5c initial state: `Interior` validation and r = 0" begin
    s = Circle(Point(5.0, 5.0), 2.0)
    @test Interior(s) isa Any                                    # DEFECT CHECK
    @test Interior(Sphere(Point(1.0, 2.0, 3.0), 1.5)) isa Any
    @test Interior(HyperSphere(Point(1.0, 2.0, 3.0, 4.0), 1.0)) isa Any
    # not a round shape
    @test_throws ArgumentError Interior(Point(1.0, 2.0))
    @test_throws ArgumentError Interior((1:3, 1:3))
    @test occursin("round shape", p65c_msg(() -> Interior((1:3, 1:3))))
    # no nesting
    @test_throws ArgumentError Interior(Interior(s))
    # D-138's shape check: finite centre, finite non-negative radius
    @test_throws ArgumentError Interior(Circle(Point(NaN, 5.0), 2.0))
    @test_throws ArgumentError Interior(Circle(Point(5.0, 5.0), Inf))
    @test_throws ArgumentError Interior(Circle(Point(5.0, 5.0), -1.0))
    # r = 0: the empty set, so a `Fill` of it has no site and throws (the closed r = 0 shape
    # is the centre site)
    z = Interior(Circle(Point(5.0, 5.0), 0.0))
    @test_throws ArgumentError layout(Fill(:a; region = z), (10, 10))
    @test count(==(1), p65c_σ(layout(Fill(:a; region = Circle(Point(5.0, 5.0), 0.0)), (10, 10)))) == 1
end

@testset "P6.5c initial state: `Interior` as the region of RandomPoints, Voronoi and Eden" begin
    reg = Interior(Circle(Point(6.0, 6.0), 2.0))                 # strict: the 3×3 block 5:7 × 5:7 (9 sites)
    block = Set((x, y) for x in 5:7, y in 5:7)
    @test p65c_oracle_sites((12, 12), (6.0, 6.0), p65c_strict_int(4)) == block   # control (oracle)
    # RandomPoints draws only strict sites: 9 distinct points exist, 10 do not
    pts = Potts.points(RandomPoints(9; region = reg, seed = 3), (12, 12))        # DEFECT CHECK
    @test Set(map(p -> (round(Int, p[1]), round(Int, p[2])), pts)) == block
    @test_throws ArgumentError Potts.points(RandomPoints(10; region = reg, seed = 3), (12, 12))
    # Voronoi fills exactly the strict sites
    v = layout(Voronoi([Point(6.0, 6.0)]; region = reg, kinds = [:a]), (12, 12))
    @test p65c_sites(p65c_σ(v), 1) == block
    # Eden grows inside the strict region only: with enough rounds it fills it
    e = layout(Eden([Point(6.0, 6.0)]; rounds = 50, region = reg, kinds = [:a], seed = 1), (12, 12))
    @test p65c_sites(p65c_σ(e), 1) == block
    # negative control: the closed region (13 sites) is larger
    @test count(==(1), p65c_σ(layout(Voronoi([Point(6.0, 6.0)]; region = Circle(Point(6.0, 6.0), 2.0), kinds = [:a]), (12, 12)))) == 13
end

# ---------------------------------------------------------------------------------------
# 4. Clipping, wrap and the domain (brief §4.A2)

@testset "P6.5c initial state: clipping and wrap (Fill of a shape at the corner)" begin
    closed5 = Lattice((5, 5); boundary = Closed())
    per5 = Lattice((5, 5); boundary = Periodic())
    c = Circle(Point(1.0, 1.0), 2.0)
    # oracles: closed r = 2 has 13 points, 6 of them with x, y ≥ 1; strict has 9, 4 with x, y ≥ 1
    @test length(p65c_oracle_sites((5, 5), (1.0, 1.0), p65c_closed_int(4))) == 6            # control
    @test length(p65c_oracle_sites((5, 5), (1.0, 1.0), p65c_closed_int(4); per = (true, true))) == 13
    @test length(p65c_oracle_sites((5, 5), (1.0, 1.0), p65c_strict_int(4))) == 4
    @test length(p65c_oracle_sites((5, 5), (1.0, 1.0), p65c_strict_int(4); per = (true, true))) == 9
    for (shape, lat, per, n, clipped, rule) in (
            (c, closed5, (false, false), 6, 7, p65c_closed_int(4)),
            (c, per5, (true, true), 13, 0, p65c_closed_int(4)),
            (Interior(c), closed5, (false, false), 4, 5, p65c_strict_int(4)),         # DEFECT CHECK (Interior)
            (Interior(c), per5, (true, true), 9, 0, p65c_strict_int(4)))
        op, rows = layout(Fill(:a; region = shape), lat; report = true)               # DEFECT CHECK (Fill)
        @test p65c_sites(p65c_σ(op), 1) == p65c_oracle_sites((5, 5), (1.0, 1.0), rule; per)
        @test count(==(1), p65c_σ(op)) == n
        @test only(rows).clipped == clipped
        @test only(rows).type === :Fill
    end
end

@testset "P6.5c initial state: the domain (never painted outside, counted as clipped)" begin
    dom = Lattice((10, 10); boundary = Closed(), domain = x -> x[1] <= 5)
    # a box region: its 20 sites, 10 in the domain, 10 clipped
    op, rows = layout(Fill(:a; region = (1:10, 1:2)), dom; report = true)              # DEFECT CHECK
    @test p65c_sites(p65c_σ(op), 1) == Set((x, y) for x in 1:5, y in 1:2)
    @test only(rows).clipped == 10
    # the default region is the domain's sites: 50 sites, nothing clipped
    op2, rows2 = layout(Fill(:bg), dom; report = true)
    @test count(==(1), p65c_σ(op2)) == 50 && only(rows2).clipped == 0
    @test all(p65c_σ(op2)[6:10, :] .== 0)
    # a shape cut by the domain: closed r = 2 at (5, 5) has 13 sites, 9 with x ≤ 5 (4 clipped)
    op3, rows3 = layout(Fill(:a; region = Circle(Point(5.0, 5.0), 2.0)), dom; report = true)
    want = p65c_oracle_sites((10, 10), (5.0, 5.0), p65c_closed_int(4); mask = x -> x[1] <= 5)
    @test length(want) == 9                                      # control (oracle)
    @test p65c_sites(p65c_σ(op3), 1) == want && only(rows3).clipped == 4
    # Objects: the same clip per copy
    op4, rows4 = layout(Objects(Interior(Circle(Point(0.0, 0.0), 2.0)), [Point(5.0, 5.0)]; kinds = [:a]), dom; report = true)
    want4 = p65c_oracle_sites((10, 10), (5.0, 5.0), p65c_strict_int(4); mask = x -> x[1] <= 5)
    @test length(want4) == 6                                     # control (oracle): 9 strict, 3 at x = 6
    @test p65c_sites(p65c_σ(op4), 1) == want4 && only(rows4).clipped == 3
end

@testset "P6.5c initial state: a box Fill beyond the lattice throws" begin
    @test_throws ArgumentError layout(Fill(:a; region = (1:12, 1:1)), (10, 10))       # DEFECT CHECK
    @test occursin("outside the lattice", p65c_msg(() -> layout(Fill(:a; region = (0:3, 1:1)), (10, 10))))
    # control: the existing layers' message for the same box
    @test occursin("outside the lattice", p65c_msg(() -> layout(Tiling((1, 1); region = (1:12, 1:1), kinds = [:a]), (10, 10))))
end

# ---------------------------------------------------------------------------------------
# 5. `Fill` basics (brief §4.A3; 2D 10×10 closed)

@testset "P6.5c initial state: Fill basics (row, background, overwrite)" begin
    op, rows = layout(Fill(:w; region = (1:10, 1:1)), (10, 10); report = true)        # DEFECT CHECK
    @test length(op) == 2                                        # no cluster, no column
    @test p65c_sites(p65c_σ(op), 1) == Set((x, 1) for x in 1:10)
    @test count(>(0), p65c_σ(op)) == 10 && p65c_kinds(op) == [:w]
    @test only(rows) == (; layer = 1, type = :Fill, requested = 1, painted = 1, dropped = 0, misses = 0, counted = 1,
        clipped = 0, splits = 0)
    @test keys(only(rows)) == P65C_ROW_KEYS                      # the D-091 schema
    # no region: every site
    bg = layout(Fill(:bg), (10, 10))
    @test all(==(1), p65c_σ(bg)) && p65c_kinds(bg) == [:bg]
    # overwrite: the later layer takes its sites, ids follow layer order
    o2, r2 = layout(overlay(Fill(:bg), Fill(:w; region = (1:10, 1:1))), (10, 10); report = true)
    @test count(==(1), p65c_σ(o2)) == 90 && count(==(2), p65c_σ(o2)) == 10
    @test p65c_kinds(o2) == [:bg, :w]
    @test all(r -> r.type === :Fill && r.dropped == 0 && r.splits == 0, r2)
    # a later layer removing every site: dropped
    o3, r3 = layout(overlay(Fill(:a; region = (1:2, 1:2)), Fill(:b; region = (1:3, 1:3))), (10, 10); report = true)
    @test p65c_kinds(o3) == [:b] && r3[1].dropped == 1 && r3[2].dropped == 0
    # deterministic, RNG-free
    @test isequal(layout(Fill(:a; region = Circle(Point(4.0, 4.0), 2.5)), (10, 10)),
        layout(Fill(:a; region = Circle(Point(4.0, 4.0), 2.5)), (10, 10)))
    # remake(f; region)
    f = Fill(:a; region = (1:2, 1:2))
    g = remake(f; region = (3:5, 3:5))
    @test count(==(1), p65c_σ(layout(g, (10, 10)))) == 9
    @test count(==(1), p65c_σ(layout(f, (10, 10)))) == 4         # the original is unchanged
end

@testset "P6.5c initial state: Fill cutting a cell warns and counts a split" begin
    cut = overlay(Fill(:a; region = (1:10, 4:6)), Fill(:b; region = (5:5, 1:10)))
    op, rows = @test_logs (:warn, r"split cell 1") match_mode = :any p65c_report(cut, (10, 10))   # DEFECT CHECK
    @test count(==(1), p65c_σ(op)) == 27                          # 30 − the 3 sites of column x = 5
    @test rows[2].splits == 1 && rows[1].splits == 0
    # `splits = :allow` on the cutting layer: no warning, the row still counts it
    allow = overlay(Fill(:a; region = (1:10, 4:6)), Fill(:b; region = (5:5, 1:10), splits = :allow))
    op2, rows2 = @test_logs p65c_report(allow, (10, 10))
    @test rows2[2].splits == 1
    # negative control: a cut that leaves one piece does not warn
    edge = overlay(Fill(:a; region = (1:10, 4:6)), Fill(:b; region = (1:1, 1:10)))
    @test_logs layout(edge, (10, 10))
end

@testset "P6.5c initial state: Fill errors" begin
    far = Circle(Point(-10.0, -10.0), 1.0)
    @test_throws ArgumentError layout(Fill(:a; region = far), (10, 10))               # DEFECT CHECK
    @test occursin("Fill: the region has no site in the lattice's domain", p65c_msg(() -> layout(Fill(:a; region = far), (10, 10))))
    dom = Lattice((10, 10); boundary = Closed(), domain = x -> x[1] <= 5)
    @test_throws ArgumentError layout(Fill(:a; region = (7:9, 1:3)), dom)            # box entirely outside the domain
    @test_throws ArgumentError Fill([:a, :b])                    # Fill paints one cell
    @test_throws ArgumentError Fill(:a; splits = :maybe)
    @test_throws ArgumentError layout(Fill(:a; region = (1:2,)), (10, 10))            # dimension mismatch
    @test_throws ArgumentError layout(Fill(:a; region = Sphere(Point(1.0, 1.0, 1.0), 2.0)), (10, 10))
end

# ---------------------------------------------------------------------------------------
# 6. `Objects` basics (brief §4.A4; 2D closed 10×8 unless stated)

@testset "P6.5c initial state: Objects translate a template, the first copy wins" begin
    tpl = Interior(Circle(Point(0.0, 0.0), 2.0))                 # strict r = 2: a 3×3 block
    op, rows = layout(Objects(tpl, [Point(3.0, 3.0), Point(5.0, 3.0)]; kinds = [:a, :b]), (10, 8); report = true)  # DEFECT CHECK
    σ = p65c_σ(op)
    @test p65c_kinds(op) == [:a, :b]
    @test p65c_sites(σ, 1) == Set((x, y) for x in 2:4, y in 2:4)  # 9 sites
    @test p65c_sites(σ, 2) == Set((x, y) for x in 5:6, y in 2:4)  # 6: the shared column x = 4 stays with copy 1
    r = only(rows)
    @test (r.type, r.requested, r.painted, r.dropped, r.misses, r.counted, r.clipped) == (:Objects, 2, 2, 0, 0, 2, 0)
    # swapping the points swaps the winner (negative control for a last-wins rule)
    sw = p65c_σ(layout(Objects(tpl, [Point(5.0, 3.0), Point(3.0, 3.0)]; kinds = [:a, :b]), (10, 8)))
    @test p65c_sites(sw, 1) == Set((x, y) for x in 4:6, y in 2:4)
    @test p65c_sites(sw, 2) == Set((x, y) for x in 2:3, y in 2:4)
    # the layer overwrites an earlier Fill on its 15 sites
    o2 = layout(overlay(Fill(:bg), Objects(tpl, [Point(3.0, 3.0), Point(5.0, 3.0)]; kinds = [:a, :b])), (10, 8))
    @test count(==(1), p65c_σ(o2)) == 65 && count(==(2), p65c_σ(o2)) == 9 && count(==(3), p65c_σ(o2)) == 6
    # kinds cycle over the copies
    o3 = layout(Objects(tpl, [Point(2.0, 2.0), Point(6.0, 2.0), Point(2.0, 6.0)]; kinds = [:a, :b]), (10, 8))
    @test p65c_kinds(o3) == [:a, :b, :a]
end

@testset "P6.5c initial state: Objects without points, Center(), a Point, 3D, hex" begin
    # no points: the shape where it is (strict r = 3: 25 sites)
    op = layout(Objects(Interior(Circle(Point(5.0, 5.0), 3.0)); kinds = [:c]), (10, 10))     # DEFECT CHECK
    @test p65c_sites(p65c_σ(op), 1) == p65c_oracle_sites((10, 10), (5.0, 5.0), p65c_strict_int(9))
    @test count(==(1), p65c_σ(op)) == 25
    # Center() on a 11×11 lattice is (6, 6); a single Point
    oc = layout(Objects(Interior(Circle(Point(0.0, 0.0), 2.0)), Center(); kinds = [:c]), (11, 11))
    @test p65c_sites(p65c_σ(oc), 1) == Set((x, y) for x in 5:7, y in 5:7)
    op1 = layout(Objects(Interior(Circle(Point(0.0, 0.0), 2.0)), Point(3.0, 4.0); kinds = [:c]), (11, 11))
    @test p65c_sites(p65c_σ(op1), 1) == Set((x, y) for x in 2:4, y in 3:5)
    # 3D: strict r = 2 has 27 sites
    o3 = layout(Objects(Interior(Sphere(Point(0.0, 0.0, 0.0), 2.0)), [Point(5.0, 5.0, 5.0)]; kinds = [:s]), (10, 10, 10))
    @test count(==(1), p65c_σ(o3)) == 27
    @test p65c_sites(p65c_σ(o3), 1) == p65c_oracle_sites((10, 10, 10), (5.0, 5.0, 5.0), p65c_strict_int(4))
    # the docs' Spheres recipe: two balls of strict r = 3 (93 sites each)
    o4 = layout(Objects(Interior(Sphere(Point(0.0, 0.0, 0.0), 3.0)), [Point(5.0, 5.0, 5.0), Point(13.0, 5.0, 5.0)]; kinds = [:cell]),
        (20, 10, 10))
    @test count(==(1), p65c_σ(o4)) == 93 && count(==(2), p65c_σ(o4)) == 93
    # hex: a disc of r = √3 at a site has 7 sites (the site and its 6 neighbours)
    hexl = Lattice((21, 21); geometry = Hexagonal(), boundary = Closed())
    c = p65c_cart((11, 11), true)
    oh = layout(Objects(Interior(Circle(Point(0.0, 0.0), sqrt(3.0))), [Point(c...)]; kinds = [:h]), hexl)
    @test p65c_sites(p65c_σ(oh), 1) == p65c_oracle_sites((21, 21), c, p65c_strict_int(3); hex = true)
    @test count(==(1), p65c_σ(oh)) == 7
end

@testset "P6.5c initial state: Objects clipping, a dropped copy, RandomPoints, remake" begin
    tpl = Interior(Circle(Point(0.0, 0.0), 1.5))                 # strict r = 1.5: 3×3 (√2 < 1.5)
    # copy 2 lies entirely off the closed lattice: allocated, painted nothing, dropped
    op, rows = layout(Objects(tpl, [Point(3.0, 3.0), Point(-10.0, -10.0)]; kinds = [:a]), (10, 10); report = true)  # DEFECT CHECK
    r = only(rows)
    @test (r.requested, r.painted, r.dropped, r.clipped) == (2, 2, 1, 9)
    @test p65c_kinds(op) == [:a] && count(==(1), p65c_σ(op)) == 9
    # a copy at the corner: 4 of its 9 sites on the lattice, 5 clipped; sites lost to an
    # earlier copy are not clipped
    _, rows2 = layout(Objects(tpl, [Point(1.0, 1.0), Point(2.0, 1.0)]; kinds = [:a]), (10, 10); report = true)
    @test only(rows2).clipped == 5 + 3                           # copy 1: 5; copy 2 at (2,1): its y = 0 row (3 sites)
    # RandomPoints: reproducible, and the copies sit at `Potts.points` of the pattern
    shp = Interior(Circle(Point(0.0, 0.0), 2.0))
    o = Objects(shp, RandomPoints(3; seed = 7); kinds = [:a])
    a1, a2 = layout(o, (20, 20)), layout(o, (20, 20))
    @test isequal(a1, a2)
    pts = Potts.points(RandomPoints(3; seed = 7), (20, 20))
    want = falses(20, 20)
    for p in pts, x in 1:20, y in 1:20
        (x - p[1])^2 + (y - p[2])^2 < 4 && (want[x, y] = true)
    end
    @test (p65c_σ(a1) .> 0) == want
    # remake(o; points) changes the layout
    b = layout(remake(o; points = RandomPoints(3; seed = 8)), (20, 20))
    @test p65c_σ(b) != p65c_σ(a1)
    @test Potts.points(RandomPoints(3; seed = 8), (20, 20)) != pts       # control
end

@testset "P6.5c initial state: Objects errors" begin
    s = Interior(Circle(Point(0.0, 0.0), 2.0))
    @test_throws ArgumentError Objects(s, [Point(1.0, 1.0)]; kinds = Symbol[])       # DEFECT CHECK
    @test_throws ArgumentError Objects((1:2, 1:2), [Point(1.0, 1.0)]; kinds = [:a])   # not round
    @test_throws ArgumentError Objects(Point(1.0, 1.0); kinds = [:a])
    @test_throws ArgumentError Objects(s, Point{2, Float64}[]; kinds = [:a])         # no points
    @test_throws ArgumentError Objects(s, [Point(1.0, 1.0)]; kinds = [:a], splits = :maybe)
    @test_throws ArgumentError layout(Objects(Interior(Sphere(Point(0.0, 0.0, 0.0), 2.0)), [Point(3.0, 3.0, 3.0)]; kinds = [:a]), (10, 10))
    @test_throws ArgumentError layout(Objects(s, [Point(3.0, 3.0, 3.0)]; kinds = [:a]), (10, 10))
end

# ---------------------------------------------------------------------------------------
# 7. `Group` and `cluster` (brief §4.A5 a–f; 2D 10×10 closed)

const P65C_BODY = () -> Group(Objects(Interior(Circle(Point(5.0, 5.0), 3.0)); kinds = [:cyto]),
    Fill(:nuc; region = (5:6, 5:6)))

@testset "P6.5c initial state: Group emits one cluster (a, b)" begin
    # (a) the group first: cyto 1 (25 − 4 = 21), nuc 2 (4), wall 3 (10)
    l = overlay(P65C_BODY(), Fill(:wall; region = (1:10, 1:1)))                      # DEFECT CHECK
    op, rows = layout(l, (10, 10); report = true)
    σ = p65c_σ(op)
    @test p65c_kinds(op) == [:cyto, :nuc, :wall]
    @test count(==(1), σ) == 21 && count(==(2), σ) == 4 && count(==(3), σ) == 10
    @test p65c_sites(σ, 2) == Set((x, y) for x in 5:6, y in 5:6)
    @test length(op) == 3
    @test isequal(op[3].first, Potts.cluster)
    @test p65c_cluster(op) == [1, 1, 3]
    # the report: three leaf rows, the schema unchanged, no row for the group
    @test [r.type for r in rows] == [:Objects, :Fill, :Fill]
    @test all(r -> keys(r) == P65C_ROW_KEYS, rows)
    @test all(r -> r.dropped == 0 && r.splits == 0, rows)
    # (b) the group second: wall 1, cyto 2, nuc 3
    ob = layout(overlay(Fill(:wall; region = (1:10, 1:1)), P65C_BODY()), (10, 10))
    @test p65c_kinds(ob) == [:wall, :cyto, :nuc]
    @test p65c_cluster(ob) == [1, 2, 2]
    # the group alone (top level)
    og = layout(P65C_BODY(), (10, 10))
    @test p65c_cluster(og) == [1, 1]
    # negative control: the same cells without `Group` emit no cluster (today's two entries)
    on = layout(overlay(Objects(Interior(Circle(Point(5.0, 5.0), 3.0)); kinds = [:cyto]), Fill(:nuc; region = (5:6, 5:6)),
            Fill(:wall; region = (1:10, 1:1))), (10, 10))
    @test length(on) == 2 && p65c_cluster(on) === nothing
    @test p65c_σ(on) == σ
end

@testset "P6.5c initial state: several groups, a dropped first member (c, d)" begin
    g(k, x) = Group(Fill(Symbol(:a, k); region = (x:(x + 1), 1:2)), Fill(Symbol(:b, k); region = (x:(x + 1), 3:4)))
    # (c) two groups on disjoint regions
    op = layout(overlay(g(1, 1), g(2, 5)), (10, 10))                                 # DEFECT CHECK
    @test p65c_kinds(op) == [:a1, :b1, :a2, :b2]
    @test p65c_cluster(op) == [1, 1, 3, 3]
    # many compartment cells in plain Julia: one Group per cell
    op3 = layout(overlay((g(k, x) for (k, x) in enumerate((1, 4, 7)))...), (10, 10))
    @test p65c_cluster(op3) == [1, 1, 3, 3, 5, 5]
    # a group and an unlabelled cell between groups
    op4 = layout(overlay(g(1, 1), Fill(:w; region = (1:10, 10:10)), g(2, 5)), (10, 10))
    @test p65c_cluster(op4) == [1, 1, 3, 4, 4]
    # (d) the first member fully overwritten: `b` becomes id 1
    od, rows = layout(Group(Fill(:a; region = (2:4, 2:4)), Fill(:b; region = (2:4, 2:4))), (10, 10); report = true)
    @test p65c_kinds(od) == [:b] && p65c_cluster(od) == [1]
    @test rows[1].dropped == 1 && rows[2].dropped == 0
    # a group member overwritten by a later layer outside the group
    oe = layout(overlay(Group(Fill(:a; region = (1:2, 1:2)), Fill(:b; region = (5:6, 5:6))), Fill(:c; region = (1:3, 1:3))), (10, 10))
    @test p65c_kinds(oe) == [:b, :c] && p65c_cluster(oe) == [1, 2]
end

# Today's output for layouts without `Group` or `set_column!`, recorded on the freeze base
# 588ad407 (the digests of σ's little-endian Int32 bytes and of the kinds joined by ',').
const P65C_REGRESSION = [
    (() -> layout(Tiling((3, 3); spacing = 1, kinds = [:a, :b]), (12, 10)),
        "4f39c81899867055160278380b2b6247299b149ac982ca1535d76e689d63824d",
        "6130e5ecd37355cc4e159f7a039ba13d886d2f9727ee5382e4736d8e3b6895b3", 6),
    (() -> layout(Voronoi(RandomPoints(6; seed = 3); lloyd = 2, kinds = [:a, :b, :c]), Lattice((16, 14); boundary = (Periodic(), Closed()))),
        "f6e4e435b7624f628895029c14553c41e2375500846fe6f23f3ab3aa713d14f3",
        "43b4c2c848d32648738ac7e95b89d3c5dd1e618ebeb407b70e992dd449beb57c", 6),
]

@testset "P6.5c initial state: a layout without Group is unchanged (e)" begin
    for (f, dσ, dk, n) in P65C_REGRESSION
        op = f()
        @test op isa Vector{Pair{Any, Array}}                    # control
        @test length(op) == 2                                    # control
        @test isequal(op[1].first, ownership) && isequal(op[2].first, kind)     # control
        @test eltype(p65c_σ(op)) == Int32 && p65c_kinds(op) isa Vector{Symbol}   # control
        @test p65c_digest(p65c_σ(op)) == dσ && p65c_kdigest(p65c_kinds(op)) == dk && maximum(p65c_σ(op)) == n   # control
    end
    # a layout of the new layers without a group: two entries too
    @test length(layout(overlay(Fill(:bg), Objects(Interior(Circle(Point(5.0, 5.0), 2.0)); kinds = [:a])), (10, 10))) == 2   # DEFECT CHECK
end

@testset "P6.5c initial state: Group placement errors (f)" begin
    @test_throws ArgumentError Group()                           # DEFECT CHECK
    inner = () -> Group(Fill(:a; region = (1:2, 1:2)))
    @test_throws ArgumentError layout(Group(inner()), (10, 10))
    @test_throws ArgumentError layout(Group(overlay(inner(), Fill(:b; region = (5:6, 5:6)))), (10, 10))
    @test_throws ArgumentError layout(Splits(inner(), 1), (10, 10))
    @test_throws ArgumentError layout(P65cPaintsGroup(), (10, 10))
    @test occursin("does not support remake", p65c_msg(() -> remake(inner())))
    # negative control: a Group nested in nested overlays at the top level is a member of the
    # (flattened) top-level overlay, so it is allowed
    @test p65c_cluster(layout(overlay(overlay(inner(), Fill(:b; region = (5:6, 5:6)))), (10, 10))) == [1, 2]
end

# ---------------------------------------------------------------------------------------
# 8. `set_column!` (brief §4.A5 h, Q-5)

@testset "P6.5c initial state: set_column! labels clusters" begin
    op = layout(P65cLabels(:cluster, [:x, :x, :y]), (10, 10))                        # DEFECT CHECK
    @test p65c_kinds(op) == [:a, :a, :a]
    @test p65c_cluster(op) == [1, 1, 3]
    # labels compare with isequal; an unset cell is its own cluster
    @test p65c_cluster(layout(P65cLabels(:cluster, Any[1.0, nothing, 1.0, "u", "u"]), (10, 10))) == [1, 2, 1, 4, 4]
    # a Group's label never equals a user label (here the user labels are 1 and 2)
    og = layout(overlay(Group(Fill(:g; region = (1:2, 5:6)), Fill(:h; region = (3:4, 5:6))),
            P65cLabels(:cluster, [1, 1, 2]; y = 1)), (10, 10))
    @test p65c_cluster(og) == [1, 1, 3, 3, 5]
    # setting twice overwrites
    @test p65c_cluster(layout(P65cLabels(:cluster, [:x, :x]; twice = true), (10, 10))) == [1, 1]
end

@testset "P6.5c initial state: set_column! emits user columns" begin
    op = layout(P65cLabels(:V_target, [10.0, 20.0, 30.0]), (10, 10))                 # DEFECT CHECK
    @test length(op) == 3 && p65c_cluster(op) === nothing
    @test op[3].first === :V_target
    @test op[3].second == [10.0, 20.0, 30.0] && op[3].second isa Vector{Float64}
    # `cluster` comes before the user columns; user columns in order of first set_column!;
    # `identity.` element types
    o2 = layout(P65cMulti(), (10, 10))
    @test length(o2) == 5
    @test isequal(o2[3].first, Potts.cluster) && o2[3].second == [1, 2, 1]
    @test o2[4].first === :q && o2[4].second == [1, 2, 3] && o2[4].second isa Vector{Int}
    @test o2[5].first === :r && o2[5].second == ["s", "t", "u"] && o2[5].second isa Vector{String}
    # setting twice overwrites
    @test layout(P65cLabels(:V_target, [5.0, 6.0]; twice = true), (10, 10))[3].second == [5.0, 6.0]
    # compaction: a cell removed by a later layer takes its value with it
    o3 = layout(overlay(P65cLabels(:V_target, [10.0, 20.0, 30.0]), P65cLabels(:V_target, [99.0]; x0 = 2)), (10, 10))
    @test p65c_kinds(o3) == [:a, :a, :a]
    @test p65c_σ(o3)[1:3, 1] == [1, 3, 2]                         # cell 2 dropped; the later cell is id 3
    @test o3[3].second == [10.0, 30.0, 99.0]
end

@testset "P6.5c initial state: an incomplete user column is an ArgumentError (Q-5)" begin
    # 2 of 3 cells
    @test_throws ArgumentError layout(P65cLabels(:V_target, Any[10.0, nothing, 30.0]), (10, 10))   # DEFECT CHECK
    msg = p65c_msg(() -> layout(P65cLabels(:V_target, Any[10.0, nothing, 30.0]), (10, 10)))
    @test occursin("V_target", msg) && occursin("2", msg)        # the column and the missing cell's final id
    # a cell of another layer that survives without a value
    @test_throws ArgumentError layout(overlay(P65cLabels(:V_target, [10.0]), Fill(:w; region = (1:10, 10:10))), (10, 10))
    # negative control: the missing cell is dropped by a later layer, so the column is complete
    @test layout(overlay(P65cLabels(:V_target, Any[10.0, nothing]), P65cLabels(:V_target, [7.0]; x0 = 2)), (10, 10))[3].second ==
          [10.0, 7.0]
    # `:cluster` is exempt
    @test p65c_cluster(layout(overlay(P65cLabels(:cluster, [:x]), Fill(:w; region = (1:10, 10:10))), (10, 10))) == [1, 2]
end

@testset "P6.5c initial state: set_column! errors" begin
    @test_throws ArgumentError layout(P65cBadColumn(:kind), (10, 10))                 # DEFECT CHECK
    @test_throws ArgumentError layout(P65cBadColumn(:ownership), (10, 10))
    @test_throws ArgumentError layout(P65cBadColumn(:unallocated), (10, 10))
    @test_throws ArgumentError layout(P65cBadColumn(:zero), (10, 10))
    msg = p65c_msg(() -> layout(P65cBadColumn(:unallocated), (10, 10)))
    @test occursin("2", msg) && occursin("ncells", msg)          # names the id and ncells
    # outside a layer's paint!
    layout(P65cKeep(), (10, 10))
    @test P65C_KEPT[] isa Potts.LayoutState                      # control
    @test_throws ArgumentError Potts.set_column!(P65C_KEPT[], :V_target, 1, 1.0)
end

# ---------------------------------------------------------------------------------------
# 9. `Group` into `PottsProblem` (brief §4.A5 g, h)

@potts_model P65cComp begin
    @kinds medium cyto nuc wall[frozen]
    @parameters V_cell = 30.0
    @variables V_target(cell) = ifelse(kind == nuc, 0.2, 0.8) * V_cell
    @lattice Lattice((10, 10); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells(cyto, nuc) => (volume - V_target)^2
        contacts => ifelse(cluster[owner] == cluster[owner′], 1.0, 3.0)
    end
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model P65cPlain begin
    @kinds medium cyto nuc wall[frozen]
    @parameters V_cell = 30.0
    @variables V_target(cell) = ifelse(kind == nuc, 0.2, 0.8) * V_cell
    @lattice Lattice((10, 10); boundary = Closed(), neighborhood = Moore(1))
    @energy cells(cyto, nuc) => (volume - V_target)^2
    @sweep Metropolis(; temperature = 1.0)
end

# section 7's layout (a) by hand: the strict disc r = 3 at (5, 5), the nucleus 5:6 × 5:6,
# the wall row y = 1
function p65c_hand_σ()
    σ = zeros(Int32, 10, 10)
    for x in p65c_oracle_sites((10, 10), (5.0, 5.0), p65c_strict_int(9))
        σ[x...] = 1
    end
    σ[5:6, 5:6] .= 2
    σ[:, 1] .= 3
    return σ
end

@testset "P6.5c initial state: a Group layout builds a compartment problem (g)" begin
    sys = P65cComp(; name = :pc)
    l = overlay(P65C_BODY(), Fill(:wall; region = (1:10, 1:1)))
    op = layout(l, sys)                                          # DEFECT CHECK
    @test p65c_cluster(op) == [1, 1, 3]
    prob = PottsProblem(sys, op, (0, 1))                         # no hand-written cluster
    cl = Array(prob.u0.cell.cluster)[1:3]
    # the partition equals the layout's (root ids may differ: `prefer`)
    @test p65c_partition(cl) == p65c_partition([1, 1, 3])
    @test cl[1] == cl[2] && cl[3] != cl[1]
    # the kind defaults (E1) apply to the layout's cells: cyto 24, nuc 6
    @test Array(prob.u0.cell.V_target)[1:2] == [24.0, 6.0]
    # the same cells entered by hand (today's way) give the same partition and σ
    @test p65c_σ(op) == p65c_hand_σ()
    ph = PottsProblem(sys, [ownership => p65c_hand_σ(), kind => [:cyto, :nuc, :wall], Potts.cluster => [1, 1, 3]], (0, 1))
    @test p65c_partition(Array(ph.u0.cell.cluster)[1:3]) == p65c_partition(cl)
    # a model without compartments rejects the layout's cluster (the existing error)
    plain = P65cPlain(; name = :pp)
    @test occursin("uses no compartments", p65c_msg(() -> PottsProblem(plain, layout(l, plain), (0, 1))))
end

@testset "P6.5c initial state: the compartment model with a hand-written cluster (controls)" begin
    sys = P65cComp(; name = :pc)
    σ = p65c_hand_σ()
    @test count(==(1), σ) == 21 && count(==(2), σ) == 4 && count(==(3), σ) == 10    # control
    ph = PottsProblem(sys, [ownership => σ, kind => [:cyto, :nuc, :wall], Potts.cluster => [1, 1, 3]], (0, 1))
    cl = Array(ph.u0.cell.cluster)[1:3]
    @test cl[1] == cl[2] && cl[3] != cl[1]                       # control
    @test Array(ph.u0.cell.V_target)[1:2] == [24.0, 6.0]         # control (E1, P6.5b)
    plain = P65cPlain(; name = :pp)
    @test occursin("uses no compartments",                       # control: the existing error
        p65c_msg(() -> PottsProblem(plain, [ownership => σ, kind => [:cyto, :nuc, :wall], Potts.cluster => [1, 1, 3]], (0, 1))))
end

@testset "P6.5c initial state: a set_column! column overrides the kind default (h)" begin
    sys = P65cPlain(; name = :pp)
    op = layout(overlay(P65cLabels(:V_target, [11.0, 12.0]; kind = :cyto), P65cLabels(:V_target, [13.0]; kind = :nuc, x0 = 5)), sys)   # DEFECT CHECK
    prob = PottsProblem(sys, op, (0, 1))
    @test Array(prob.u0.cell.V_target)[1:3] == [11.0, 12.0, 13.0]
    # control: without the column the kind defaults apply (cyto 24, nuc 6)
    σ = zeros(Int32, 10, 10); σ[1, 1] = 1; σ[2, 1] = 2; σ[5, 1] = 3
    p0 = PottsProblem(sys, [ownership => σ, kind => [:cyto, :cyto, :nuc]], (0, 1))
    @test Array(p0.u0.cell.V_target)[1:3] == [24.0, 24.0, 6.0]
end

# ---------------------------------------------------------------------------------------
# 10. The Fortuna geometry (brief §4.A6, the A8 recipe; code geometry, integer R;
#     lattice (Periodic, Periodic, Closed); order Group(cytoplasm, nucleus), substrate, lid)

p65c_fortuna_lattice(L, Lz) = Lattice((L, L, Lz); boundary = (Periodic(), Periodic(), Closed()))
# the A8 recipe, verbatim but for `shape` (the closed control swaps the shape)
function p65c_fortuna_layout(R, L, Lz, target; strict = true)
    c = (L ÷ 2 + 1, L ÷ 2 + 1, R + 1)                            # our z = R + 1 ⇒ bottom layer z = 2
    ball = Sphere(Point(Float64.(c)...), Float64(R))
    body = Group(Objects(strict ? Interior(ball) : ball; kinds = [:cytoplasm]),
        Fill(:nucleus; region = map(a -> (a - 3):(a + 2), c)))   # 6³, offsets −3…+2
    return layout(overlay(body, Fill(:substrate; region = (1:L, 1:L, 1:1)),
            Fill(:lid; region = (1:L, 1:L, Lz:Lz))), target; report = true)
end

# (R, L, Lz, centre, strict ball, z-range, sites at z = 2, nucleus box, cytoplasm,
#  closed ball, closed z-range, closed cytoplasm after the planes)
const P65C_FORTUNA = [
    (10, 80, 21, (41, 41, 11), 4139, 2:20, 61, (38:43, 38:43, 8:13), 3923, 4169, 1:21, 3951),
    (15, 120, 31, (61, 61, 16), 13997, 2:30, 89, (58:63, 58:63, 13:18), 13781, 14147, 1:31, 13929),
]

@testset "P6.5c initial state: the Fortuna start, R = $(case[1])" for case in P65C_FORTUNA
    R, L, Lz, c, nball, zr, nz2, nbox, ncyto, nclosed, zrc, ncytoc = case
    lat = p65c_fortuna_lattice(L, Lz)
    # the oracle (exact integer distances; the ball never reaches a periodic edge)
    ball = p65c_oracle_sites((L, L, Lz), Float64.(c), p65c_strict_int(R^2))
    @test length(ball) == nball                                  # control (oracle)
    @test Set(x[3] for x in ball) == Set(zr)
    @test count(x -> x[3] == 2, ball) == nz2
    box = Set(Tuple(I) for I in CartesianIndices(nbox))
    @test length(box) == 216 && box ⊆ ball                       # control: the nucleus lies wholly inside
    closed = p65c_oracle_sites((L, L, Lz), Float64.(c), p65c_closed_int(R^2))
    @test length(closed) == nclosed && Set(x[3] for x in closed) == Set(zrc)   # control
    @test length(closed) - nball == (R == 10 ? 30 : 150)         # the brief: the closed ball adds 30 / 150
    # the layout
    (op, rows) = @test_logs p65c_fortuna_layout(R, L, Lz, lat)   # DEFECT CHECK; no split warning
    σ = p65c_σ(op)
    @test p65c_kinds(op) == [:cytoplasm, :nucleus, :substrate, :lid]
    @test p65c_sites(σ, 1) == setdiff(ball, box)                 # the cytoplasm
    @test count(==(1), σ) == ncyto
    @test p65c_sites(σ, 2) == box
    @test count(==(1), view(σ, :, :, 2)) == nz2                  # the contact disc (x² + y² < 2R − 1)
    @test count(==(3), σ) == L^2 && all(==(3), view(σ, :, :, 1))
    @test count(==(4), σ) == L^2 && all(==(4), view(σ, :, :, Lz))
    @test !any(==(1), view(σ, :, :, 1)) && !any(==(1), view(σ, :, :, Lz))      # no cytoplasm on either plane
    @test p65c_cluster(op) == [1, 1, 3, 4]
    @test all(r -> r.dropped == 0 && r.splits == 0, rows)
    @test [r.type for r in rows] == [:Objects, :Fill, :Fill, :Fill]
    # negative control: the closed Sphere puts one site on each plane and adds 30 / 150
    # sites, so the cytoplasm count distinguishes the rules
    (opc, _) = p65c_fortuna_layout(R, L, Lz, lat; strict = false)
    @test count(==(1), p65c_σ(opc)) == ncytoc
    @test ncytoc != ncyto
end

@testset "P6.5c initial state: the Fortuna ball at a non-integer radius and centre" begin
    # the audited ruling's arithmetic (P6.5d's choice; included so non-integer centres and
    # radii are covered): R = 15, φ_n = 0.15, φ_l = 0.05, V = (4π/3)·15³
    V = (4π / 3) * 15^3
    @test V ≈ 14137.17 atol = 0.01                               # control
    lat = p65c_fortuna_lattice(120, 31)
    for (φl, r0, n, ztop, nz2) in ((0.05, 14.012856, 11512, 29, 89), (0.30, 12.402584, 7980, 25, 69))
        r = cbrt(((1 - 0.15 - φl) * V + 216) / (4π / 3))
        @test r ≈ r0 atol = 1e-6                                 # control
        c = (61.0, 61.0, r + 1)
        os = p65c_oracle_sites((120, 120, 31), c, p65c_strict_tol(r))
        oc = p65c_oracle_sites((120, 120, 31), c, p65c_closed_tol(r))
        @test length(os) == n && length(oc) == n + 1             # control (oracle): the point at distance r on z = 1
        @test only(setdiff(oc, os)) == (61, 61, 1)
        op = layout(Objects(Interior(Sphere(Point(c...), r)); kinds = [:cytoplasm]), lat)      # DEFECT CHECK
        σ = p65c_σ(op)
        @test p65c_sites(σ, 1) == os
        @test count(==(1), σ) == n
        @test findall(z -> any(==(1), view(σ, :, :, z)), 1:31) == collect(2:ztop)
        @test count(==(1), view(σ, :, :, 2)) == nz2
        # the closed rule includes the z = 1 point
        @test count(==(1), p65c_σ(layout(Objects(Sphere(Point(c...), r); kinds = [:cytoplasm]), lat))) == n + 1
    end
end

# The kinds and targets of a Fortuna-shaped model built from the layout alone (R = 10).
@potts_model P65cFortuna begin
    @kinds medium substrate[frozen] lid[frozen] cytoplasm lamellipodium nucleus
    @parameters begin
        R = 10.0
        φ_n = 0.15
        φ_l = 0.05
    end
    @variables V_target(cell) = ifelse(kind == nucleus, φ_n,
        ifelse(kind == lamellipodium, φ_l, ifelse(kind == cytoplasm, 1 - φ_n - φ_l, 0.0))) * (4 / 3 * 3.141592653589793 * R^3)
    @lattice Lattice((80, 80, 21); boundary = (Periodic(), Periodic(), Closed()), neighborhood = Moore(1))
    @energy begin
        cells(cytoplasm, lamellipodium, nucleus) => (volume - V_target)^2
        contacts => ifelse(cluster[owner] == cluster[owner′], 1.0, 3.0)
    end
    @sweep Metropolis(; temperature = 1.0)
end

@testset "P6.5c initial state: the Fortuna start builds the problem (kinds, targets, one cluster)" begin
    sys = P65cFortuna(; name = :fo)
    (op, _) = p65c_fortuna_layout(10, 80, 21, sys)               # DEFECT CHECK
    prob = PottsProblem(sys, op, (0, 1))
    u0 = prob.u0
    V = 4 / 3 * π * 10^3
    kd = Array(u0.cell.kind)
    vol = Array(u0.cell.volume)
    vt = Array(u0.cell.V_target)
    alive = findall(>(0), vol)
    @test length(alive) == 4
    @test vol[1:4] == [3923, 216, 6400, 6400]
    # targets fixed from t = 0 by the kind defaults: cytoplasm (1 − φ_n − φ_l)V, nucleus φ_n V
    @test vt[1] ≈ 0.80 * V rtol = 1e-12
    @test vt[2] ≈ 0.15 * V rtol = 1e-12
    # no lamellipodium cell at t = 0 (kind index 4 of `medium substrate lid cytoplasm lamellipodium nucleus`)
    @test !any(c -> kd[c] == 4, alive)
    # one cluster {cytoplasm, nucleus}; the planes alone
    cl = Array(u0.cell.cluster)
    @test cl[1] == cl[2] && length(unique(cl[1:4])) == 3
end

# ---------------------------------------------------------------------------------------
# 11. The 2D analogue: a disc tangent to the substrate line

@testset "P6.5c initial state: a 2D cell on a substrate line reproduces the strict count" begin
    for (r, n, nclosed) in ((3, 25, 29), (5, 69, 81))
        c = (11.0, r + 1.0)                                      # bottom row y = 2
        l = overlay(Objects(Interior(Circle(Point(c...), Float64(r))); kinds = [:cell]), Fill(:sub; region = (1:21, 1:1)))
        op = layout(l, Lattice((21, 21); boundary = (Periodic(), Closed())))          # DEFECT CHECK
        @test count(==(1), p65c_σ(op)) == n
        @test !any(==(1), view(p65c_σ(op), :, 1))
        # negative control: the closed disc touches the line (one site) and loses it
        lc = overlay(Objects(Circle(Point(c...), Float64(r)); kinds = [:cell]), Fill(:sub; region = (1:21, 1:1)))
        @test count(==(1), p65c_σ(layout(lc, Lattice((21, 21); boundary = (Periodic(), Closed()))))) == nclosed - 1
    end
end

# ---------------------------------------------------------------------------------------
# 12. Determinism and laziness (brief §4.A7)

@testset "P6.5c initial state: deterministic; Objects scans per-copy boxes" begin
    l = overlay(Fill(:bg), Objects(Interior(Circle(Point(0.0, 0.0), 2.5)), RandomPoints(20; seed = 11); kinds = [:a, :b]),
        Group(Fill(:c; region = (1:3, 1:3)), Fill(:d; region = (4:5, 1:3))))
    a = layout(l, (40, 40))                                      # DEFECT CHECK
    @test isequal(a, layout(l, (40, 40)))
    # 10⁴ copies of a strict r = 2 ball (27 sites each) on 200³: O(Σ bounding boxes), not
    # O(sites × copies), so it finishes. Explicit points from a fixed stream (the test's
    # own); the first copy wins, so the oracle paints copies in order onto unowned sites.
    rng = StableRNG(5)
    pts = [Point(Float64(rand(rng, 1:200)), Float64(rand(rng, 1:200)), Float64(rand(rng, 1:200))) for _ in 1:10_000]
    t = @elapsed op = layout(Objects(Interior(Sphere(Point(0.0, 0.0, 0.0), 2.0)), pts; kinds = [:s]), (200, 200, 200))
    @info "P6.5c initial state: 10⁴ Objects copies on 200³ took $(round(t; digits = 2)) s (informational)"
    want = zeros(Int32, 200, 200, 200)
    offs = [(i, j, k) for i in -1:1, j in -1:1, k in -1:1]       # strict r = 2: the 3³ block
    for (n, p) in enumerate(pts)
        q = round.(Int, Tuple(p))
        for o in offs
            x = q .+ o
            all(d -> 1 <= x[d] <= 200, 1:3) || continue
            want[x...] == 0 && (want[x...] = n)
        end
    end
    # copies left with no site are compacted away, so compare the partitions: the same
    # painted sites, and the (σ, oracle) id pairs one-to-one
    σ = p65c_σ(op)
    @test (σ .> 0) == (want .> 0)
    pairs_ = unique(zip(vec(σ), vec(want)))
    @test length(pairs_) == length(unique(σ)) == length(unique(want))
    # first wins: ids increase with the oracle's copy index (copies in order)
    @test issorted(sort(filter(p -> p[1] > 0, pairs_)), by = last)
end

# ---------------------------------------------------------------------------------------
# 13. The kinds check (brief §3.A7, D-135)

@potts_model P65cClasses begin
    @kinds medium cyto nuc g = (cyto, nuc)
    @lattice Lattice((10, 10))
    @energy cells => (volume - 4.0)^2
    @sweep Metropolis(; temperature = 1.0)
end

@testset "P6.5c initial state: a kind class is not a layer kind" begin
    sys = P65cClasses(; name = :kc)
    @test occursin("kind class", p65c_msg(() -> layout(Tiling((2, 2); kinds = [:g]), sys)))     # control (existing layers)
    @test occursin("kind class", p65c_msg(() -> layout(Fill(:g; region = (1:2, 1:2)), sys)))   # DEFECT CHECK
    @test occursin("kind class", p65c_msg(() -> layout(Objects(Interior(Circle(Point(3.0, 3.0), 2.0)); kinds = [:g]), sys)))
    @test occursin("kind class", p65c_msg(() -> layout(Group(Fill(:cyto; region = (1:2, 1:2)), Fill(:g; region = (3:4, 1:2))), sys)))
    @test length(layout(Fill(:cyto; region = (1:2, 1:2)), sys)) == 2
end

# ---------------------------------------------------------------------------------------
# 14. Docs (brief §3.A8, §4.D; D-087)

@testset "P6.5c initial state: the layouts manual shows the recipes" begin
    md = read(joinpath(@__DIR__, "..", "..", "..", "..", "docs", "src", "manual", "layouts.md"), String)
    @test occursin("Voronoi", md)                                # control: the page exists and lists today's layers
    for n in ("Fill", "Objects", "Group")
        @test occursin(Regex("^\\|\\s*`$(n)", "m"), md)           # DEFECT CHECK: a row of the built-in-layers table
    end
    # the Plane recipe: any `Fill` whose region is a one-layer z slab (spec owner, D-244)
    @test occursin(r"Fill\(:\w+;[^\n]*region\s*=\s*\([^()\n]+,[^()\n]+,\s*([\w+\-]+):\1\s*\)", md)
    @test occursin("Objects(Interior(Sphere(", md)               # the Spheres recipe
    @test occursin("Group(", md)                                 # the compartment example
end

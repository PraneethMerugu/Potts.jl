# P6.1a6 (ROADMAP Phase 6, step 1; D-075 amends D-057; research/initial-state-review.md §4):
# the layout protocol `paint!(op::LayoutState, l, lat)`, the layout report, `Tiling(partial)`
# and `splits`. Frozen (AUTONOMY §7.3).
#
# Surface fixed by the coordinator (Potts, src/layouts.jl, unless noted):
#
#   Potts.paint!(op::Potts.LayoutState, l, lat)                          (public, the one method)
#       The extension method of every layer. `op` is opaque: a layer reads and writes it only
#       through the accessors below, and reads the lattice only through the lattice queries
#       (no `LatticeSpec` field). `Tiling`, `Scattered`, `Frame`, `InsertUntil`, `overlay` and
#       PottsModels' `VoronoiBall` are rewritten on it. The return value is ignored.
#       `paint!(σ, kinds, l, lat)` is removed with no alias (D-028): no 4-argument `paint!`
#       method is left in Potts or PottsModels.
#   State accessors (public):
#       new_cell!(op, kind) -> id      allocates the next id, `ncells(op) + 1`; ids are those
#                                      of the paint so far (compaction happens after the paint)
#       assign!(op, x, id) -> Int      paints site `x` (a tuple of integers) or the box `x` (a
#                                      tuple of unit ranges) with cell `id`; returns the number of
#                                      sites written
#       owner(op, x) -> Integer        the current owner of site `x` (0 = medium)
#       kindof(op, id)                 the kind given to `new_cell!`
#       ncells(op) -> Int              ids allocated so far
#       record!(op; requested, painted, misses = 0)   the current leaf layer's report entry
#   Lattice queries (public): `size(lat)` (Base), `isperiodic(lat, d)`, `indomain(lat, x)`.
#
#   layout(l, x; report = false)
#       `report = true` returns `(point, report)`, `point == layout(l, x)` (the same SII
#       operating point `[ownership => σ, kind => kinds]`). `report` is a vector of rows, one
#       per LEAF layer in paint order (an `overlay` contributes its flattened leaves). Every
#       row has the properties
#         type       nameof the leaf layer's type, a Symbol (`:Tiling`, `:InsertUntil`, …)
#         requested  Tiling: boxes placed; Scattered: n; Frame: 1; InsertUntil with
#                    `number = n`: n; a custom layer: what it passed to `record!`
#         painted    cells the layer created
#         dropped    of those, the cells left with no site after the whole layout
#         misses     InsertUntil: missed draws (both modes); a custom layer: its `record!`
#                    value (default 0); other layers 0
#         counted    InsertUntil: what its stop rule counted (painted, + misses under :count);
#                    Tiling, Scattered, Frame: painted
#         splits     cells cut ONLY by this layer (a cut = this layer took at least one of
#                    the cell's sites) whose remaining sites are disconnected after the whole
#                    layout, counted whatever the layer's `splits` setting
#       Rows may carry more properties (`layer`, `clipped`, …). `layout_tally` is removed
#       with no alias (D-028).
#
#   Tiling(size; spacing = 0, region = <whole lattice>, kinds, partial = :skip, splits = :warn)
#       `partial = :skip` (default) places whole boxes only, as today. `partial = :clip` also
#       starts boxes up to the end of the region and keeps the part of each box inside
#       region ∩ lattice (a region may then reach beyond the lattice). Any other value throws
#       an ArgumentError.
#   splits = :warn | :allow on Tiling, Scattered, Frame and InsertUntil (default :warn; any
#       other value throws an ArgumentError). `layout` warns (a message matching
#       r"split cell") once per cell that later layers cut into disconnected pieces, unless
#       EVERY layer that cut that cell has `splits = :allow`.
#   remake(l::AbstractLayout; kw...) (SciMLBase's, exported by Potts) re-runs the keyword
#       constructor with the layer's own keywords overridden by `kw`, so it validates.
#
#   PottsModels: akeeb_layout(; lattice, seed, slab, seeding) is
#       overlay(Tiling((3, 3); region = (1:X, 1:3cld(slab, 3)), kinds = [:follower], partial = :clip),
#               InsertUntil(:leader; into = [:follower], fraction = 1 // 4, seed, misses,
#                           region = (2:X, 2:(slab - 1)), splits = :allow))
#       (`_AkeebSlab` is deleted), and `akeeb_state` paints it with no logger of its own
#       (D-082's `NullLogger` is deleted): it emits no log record.
#
# Expected values. The Akeeb digests below were computed on the tree before this item
# (ec544d8) with `layout_tally(akeeb_layout(; lattice, seed, seeding), lattice)` and
# `akeeb_state`, by /tmp/p61a6/digests_today.jl: SHA-256 of σ's little-endian Int32 bytes,
# the follower count (kinds are `nf` followers then `painted` leaders) and the tally. Every
# other expected value is derived by hand in the comments; the one draw-dependent count (the
# report fixture's misses) is also recomputed from the documented draw rule.
using Potts: CorePotts
using StableRNGs: StableRNG   # D-138: PottsModels no longer depends on StableRNGs
using SHA: sha256

p61a6_get(op, key) = only(last(p) for p in op if isequal(first(p), key))
p61a6_σ(op) = p61a6_get(op, ownership)
p61a6_kinds(op) = p61a6_get(op, kind)
p61a6_digest(σ) = bytes2hex(sha256(reinterpret(UInt8, vec(htol.(σ)))))
p61a6_rows(l, x) = last(layout(l, x; report = true))
p61a6_row(r) = (r.requested, r.painted, r.dropped, r.misses, r.counted, r.splits)
p61a6_ins(rep) = only(r for r in rep if r.type === :InsertUntil)
function p61a6_logs(f)
    lg = Test.TestLogger(min_level = Base.CoreLogging.Debug)
    Base.CoreLogging.with_logger(f, lg)
    return lg.logs
end
function p61a6_quietly(f)                 # f(), with its log records captured, not printed
    v = nothing
    Base.CoreLogging.with_logger(() -> (v = f()), Test.TestLogger(min_level = Base.CoreLogging.Debug))
    return v
end
p61a6_splitwarns(f) = count(r -> r.level == Base.CoreLogging.Warn && occursin(r"split cell", string(r.message)),
    p61a6_logs(f))

# ---------------------------------------------------------------------------------------------
# Custom layers, written against the new protocol only
# ---------------------------------------------------------------------------------------------

const P61A6_SEEN = Any[]

# One cell on a column (column 1 on a periodic x axis, else column 2) over every in-domain
# site not owned by a cell of kind `avoid`, then one 2 × 2 box cell in the upper corner.
struct P61a6Probe <: Potts.AbstractLayout
    kind::Symbol
    avoid::Symbol
end
function Potts.paint!(op::Potts.LayoutState, l::P61a6Probe, lat)
    X, Y = size(lat)
    push!(P61A6_SEEN, (Potts.ncells(op), Potts.isperiodic(lat, 1), Potts.isperiodic(lat, 2)))
    a = Potts.new_cell!(op, l.kind)
    x = Potts.isperiodic(lat, 1) ? 1 : 2
    n = 0
    for y in 1:Y
        Potts.indomain(lat, (x, y)) || continue
        c = Potts.owner(op, (x, y))
        c != 0 && Potts.kindof(op, c) === l.avoid && continue
        n += Potts.assign!(op, (x, y), a)
    end
    b = Potts.new_cell!(op, l.kind)
    m = Potts.assign!(op, ((X - 1):X, (Y - 1):Y), b)
    push!(P61A6_SEEN, (a, b, n, m))
    Potts.record!(op; requested = 2, painted = 2)
    return nothing
end

# A layer that logs a warning of its own while painting one cell at `at`.
struct P61a6Loud <: Potts.AbstractLayout
    at::NTuple{2, Int}
end
function Potts.paint!(op::Potts.LayoutState, l::P61a6Loud, lat)
    @warn "P61a6 loud layer at $(l.at)"
    Potts.assign!(op, l.at, Potts.new_cell!(op, :loud))
    Potts.record!(op; requested = 1, painted = 1)
    return nothing
end

# Negative controls for the field-access check (never painted).
struct P61a6Peek <: Potts.AbstractLayout end
function Potts.paint!(op::Potts.LayoutState, l::P61a6Peek, lat)
    Potts.assign!(op, (1, 1), Potts.new_cell!(op, :p))
    return lat.dims
end
struct P61a6PeekAlias <: Potts.AbstractLayout end
function Potts.paint!(op::Potts.LayoutState, l::P61a6PeekAlias, lat)
    L = lat
    d = getfield(L, :domain)
    return d
end

# `getproperty`/`getfield` calls on the `lat` argument (or a plain alias of it) in the
# lowered code of the `paint!` method for layer type `T`. Lowered code reads slots and
# globals into SSA values (`%1 = lat; %2 = Base.getproperty; %3 = (%2)(%1, :dims)`), so
# operands are resolved through them.
function p61a6_lat_field_reads(T)
    m = only(methods(Potts.paint!, (Any, T, Any)))
    ci = Base.uncompressed_ast(m)
    lat = findfirst(==(:lat), ci.slotnames)
    lat === nothing && error("the paint! method of $T has no argument named `lat`")
    resolve(x) = x isa Core.SSAValue ? resolve(ci.code[x.id]) : x
    rhs(st) = st isa Expr && st.head === :(=) ? st.args[2] : st
    alias = Set{Int}([lat])
    for _ in 1:length(ci.code), st in ci.code                 # plain aliases `L = lat`, to a fixpoint
        st isa Expr && st.head === :(=) && st.args[1] isa Core.SlotNumber || continue
        v = resolve(st.args[2])
        v isa Core.SlotNumber && v.id in alias && push!(alias, st.args[1].id)
    end
    reads = Any[]
    for st in ci.code
        ex = rhs(st)
        ex isa Expr && ex.head === :call && length(ex.args) >= 2 || continue
        f = resolve(ex.args[1])
        f isa GlobalRef && f.name in (:getproperty, :getfield) || continue
        o = resolve(ex.args[2])
        o isa Core.SlotNumber && o.id in alias && push!(reads, ex)
    end
    return reads
end

# ---------------------------------------------------------------------------------------------
# Akeeb: byte identity with the tree before this item
# ---------------------------------------------------------------------------------------------

# (lattice, seeding, seed, sha256(σ), followers, (painted, misses, counted)) at ec544d8
const P61A6_AKEEB = [
    ((500, 300), :authors, 0x5cd2609, "1210fbcf0bd50ba1cf4c8e7ee034a6eccb13f70b6985fcd5d4dac73aac91457a", 1169, (383, 7, 390)),
    ((500, 300), :authors, 1, "eff0a9f521a0ef8feddc65737b24d6c450423423ad40fb80e71cea8ea9b5316d", 1169, (385, 5, 390)),
    ((500, 300), :authors, 2, "de60a92b430ffabf2ec39ec47098356c6901d23c64e9f3b109d32937e0abaf16", 1169, (382, 8, 390)),
    ((500, 300), :authors, 3, "4040c458992e809bad1e76f4aec5cd0decb83c9dc5c6e5911fb4a9e3ff542280", 1169, (382, 8, 390)),
    ((500, 300), :retry, 0x5cd2609, "8debf2bba43219c8105dc5a756f390324bf9404e3208c5e5305e755f494c1e2c", 1169, (390, 7, 390)),
    ((500, 300), :retry, 1, "8ae5744e2e22023650baf836739166e9670e19812000105f98276291769f315d", 1169, (390, 6, 390)),
    ((500, 300), :retry, 2, "a97fc085e6a389c2b94e11232cfebced56562179c9f92bb85ae53f1b9c11af71", 1169, (390, 8, 390)),
    ((500, 300), :retry, 3, "c3e4b7cc718c74902c0d67e1a0d44cf8ed18302ce5ed49b51755715db3d7a3f5", 1169, (390, 8, 390)),
    ((99, 60), :authors, 0x5cd2609, "6f8ef5ab80258b1d36d81bbb8228b8bd1c39681cda32bd9f31b9a0d8f449f32c", 231, (76, 1, 77)),
    ((99, 60), :authors, 1, "3e63cfab938326d2f33888d2be4fa35a641dcfdcb7003a880700bf76814d3dc3", 231, (77, 1, 78)),
    ((99, 60), :authors, 2, "ebf44ca99d29c6f0eb35044c7a7f6e14fd1b8bf0b5c5a63b3f50016567fd79f1", 231, (77, 0, 77)),
    ((99, 60), :authors, 3, "4d997ebbcd793e5cb167f89312d89d48a64635ff1da8cb3b7a48a965fbbafa27", 231, (74, 3, 77)),
    ((99, 60), :retry, 0x5cd2609, "3ce84e78b0093b0bc054df622d1b6badf0cdbdd6a9ba248c0c8bf7db0db91cbc", 231, (77, 1, 77)),
    ((99, 60), :retry, 1, "3e63cfab938326d2f33888d2be4fa35a641dcfdcb7003a880700bf76814d3dc3", 231, (77, 1, 77)),
    ((99, 60), :retry, 2, "ebf44ca99d29c6f0eb35044c7a7f6e14fd1b8bf0b5c5a63b3f50016567fd79f1", 231, (77, 0, 77)),
    ((99, 60), :retry, 3, "48524e9e11e77d925172f6859a3ed9159f60dd9bebce5a3eb8d6af5e1c62f4e1", 231, (77, 3, 77)),
]

# The published slab written with public layers only (ROADMAP P6.1a6).
p61a6_akeeb(X, slab, seed, misses; splits = :allow) = overlay(
    Tiling((3, 3); region = (1:X, 1:(3 * cld(slab, 3))), kinds = [:follower], partial = :clip),
    InsertUntil(:leader; into = [:follower], fraction = 1 // 4, seed, misses, region = (2:X, 2:(slab - 1)), splits))

@testset "P6.1a6: Akeeb σ, kinds and inventory are byte-identical to the tree before" begin
    @test !isdefined(PottsModels, :_AkeebSlab)
    for (lat, seeding, seed, dσ, nf, tally) in P61A6_AKEEB
        misses = seeding === :authors ? :count : :retry
        np = tally[1]
        expected_kinds = [fill(:follower, nf); fill(:leader, np)]
        # akeeb_layout through the report
        op, rep = layout(PottsModels.akeeb_layout(; lattice = lat, seed, seeding), lat; report = true)
        σ = p61a6_σ(op)
        @test σ isa Matrix{Int32} && size(σ) == lat
        @test p61a6_digest(σ) == dσ
        @test p61a6_kinds(op) == expected_kinds
        r = p61a6_ins(rep)
        @test (r.painted, r.misses, r.counted) == tally
        t = only(x for x in rep if x.type === :Tiling)
        @test t.painted == nf && t.dropped == 0                  # no follower erased
        # the public-layer expression gives the same cells and the same inventory
        op2, rep2 = layout(p61a6_akeeb(lat[1], 21, seed, misses), lat; report = true)
        @test p61a6_σ(op2) == σ && p61a6_kinds(op2) == expected_kinds
        @test p61a6_row(p61a6_ins(rep2)) == p61a6_row(r)
        # akeeb_state paints the same cells
        st = akeeb_state(; lattice = lat, seed, seeding)
        @test p61a6_digest(p61a6_σ(st)) == dσ && p61a6_kinds(st) == expected_kinds
    end
    # x is periodic in the model: painting on the system gives the closed-lattice cells
    sys = AkeebInvasion(; name = :p61a6, lattice = (99, 60))
    for (seeding, dσ) in ((:authors, "3e63cfab938326d2f33888d2be4fa35a641dcfdcb7003a880700bf76814d3dc3"),
            (:retry, "3e63cfab938326d2f33888d2be4fa35a641dcfdcb7003a880700bf76814d3dc3"))
        @test p61a6_digest(p61a6_σ(layout(PottsModels.akeeb_layout(; lattice = (99, 60), seed = 1, seeding), sys))) == dσ
    end
    # negative control: the digest sees a single changed site
    σ = copy(p61a6_σ(layout(PottsModels.akeeb_layout(; lattice = (99, 60), seed = 1), (99, 60))))
    σ[50, 40] = 1
    @test p61a6_digest(σ) != "3e63cfab938326d2f33888d2be4fa35a641dcfdcb7003a880700bf76814d3dc3"
end

# ---------------------------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------------------------

@testset "P6.1a6: akeeb_state logs nothing; a layer's own warning surfaces" begin
    # seed 1 at 500 × 300: the leaders cut follower 713 into pieces (the control below)
    @test isempty(p61a6_logs(() -> akeeb_state(; seed = 1)))
    @test isempty(p61a6_logs(() -> akeeb_state()))
    @test isempty(p61a6_logs(() -> akeeb_state(; lattice = (99, 60), seed = 3, seeding = :retry)))
    @test isempty(p61a6_logs(() -> layout(PottsModels.akeeb_layout(; seed = 1), (500, 300))))
    # control: the same layers with `splits = :warn` on the leaders do warn
    @test p61a6_splitwarns(() -> layout(p61a6_akeeb(500, 21, 1, :count; splits = :warn), (500, 300))) >= 1
    # an unrelated warning raised inside a layer is not swallowed, with or without the Akeeb layers
    logs = p61a6_logs(() -> layout(overlay(PottsModels.akeeb_layout(; seed = 1), P61a6Loud((250, 200))), (500, 300)))
    @test length(logs) == 1
    @test only(logs).level == Base.CoreLogging.Warn && occursin("P61a6 loud layer at (250, 200)", string(only(logs).message))
    @test_logs (:warn, r"P61a6 loud layer") layout(P61a6Loud((2, 2)), (4, 4))
    # akeeb_state installs no logger of its own (D-082's NullLogger is gone)
    src = Meta.parseall(read(joinpath(pkgdir(PottsModels), "src", "akeeb.jl"), String))
    body = nothing
    walk(f, ex) = (f(ex); ex isa Expr && foreach(a -> walk(f, a), ex.args))
    walk(src) do ex
        ex isa Expr && ex.head === :function && ex.args[1] isa Expr &&
            occursin("akeeb_state", string(ex.args[1])) && (body = ex.args[2])
    end
    @test body !== nothing
    syms = Symbol[]
    walk(ex -> ex isa Symbol && push!(syms, ex), body)
    @test :akeeb_layout in syms                                      # control: the walk sees the body
    @test !(:NullLogger in syms) && !(:with_logger in syms)
end

# ---------------------------------------------------------------------------------------------
# The protocol: a custom layer through the public accessors
# ---------------------------------------------------------------------------------------------

@testset "P6.1a6: a custom layer on paint!(op::LayoutState, l, lat)" begin
    for n in (:LayoutState, :paint!, :new_cell!, :assign!, :owner, :kindof, :ncells, :record!, :isperiodic, :indomain)
        @test isdefined(Potts, n) && Base.ispublic(Potts, n)
    end
    @test !Base.ispublic(Potts, :_warn_split)                        # control: internals are not
    # No LatticeSpec field in the custom layers; the checker sees field reads (controls)
    @test isempty(p61a6_lat_field_reads(P61a6Probe))
    @test isempty(p61a6_lat_field_reads(P61a6Loud))
    @test length(p61a6_lat_field_reads(P61a6Peek)) == 1
    @test length(p61a6_lat_field_reads(P61a6PeekAlias)) == 1

    # Closed 6 × 6: nine 2 × 2 tiles (ids x-fastest, kinds keep, a, keep, …), then the probe.
    # Column 2 is owned by tiles 1 (keep), 4 (a), 7 (keep): the stripe (cell 10) takes
    # (2, 3) and (2, 4) from tile 4, which keeps (1, 3:4). The box (cell 11) covers tile 9
    # = (5:6, 5:6), which is dropped: ids 10, 11 become 9, 10.
    base = Tiling((2, 2); kinds = [:keep, :a])
    function expected(stripe_x, keep_x)
        e = zeros(Int32, 6, 6)
        for k in 1:9
            cx, cy = mod1(k, 3), cld(k, 3)
            e[(2cx - 1):(2cx), (2cy - 1):(2cy)] .= k
        end
        e[stripe_x, 3:4] .= 9
        e[keep_x, 3:4] .= 4
        e[5:6, 5:6] .= 10
        return e
    end
    kinds10 = [:keep, :a, :keep, :a, :keep, :a, :keep, :a, :s, :s]
    for (lat, per, sx, kx) in (((6, 6), false, 2, 1), (Lattice((6, 6); boundary = Closed()), false, 2, 1),
            (Lattice((6, 6); boundary = (Periodic(), Closed())), true, 1, 2))
        empty!(P61A6_SEEN)
        op, rep = layout(overlay(base, P61a6Probe(:s, :keep)), lat; report = true)
        @test P61A6_SEEN == [(9, per, false), (10, 11, 2, 4)]
        @test p61a6_σ(op) == expected(sx, kx)
        @test p61a6_kinds(op) == kinds10
        @test length(rep) == 2 && [r.type for r in rep] == [:Tiling, :P61a6Probe]
        @test p61a6_row(rep[1]) == (9, 9, 1, 0, 9, 0)
        @test (rep[2].requested, rep[2].painted, rep[2].dropped, rep[2].misses, rep[2].splits) == (2, 2, 0, 0, 0)
    end
    # A domain: (2, 3) is outside, so the stripe skips it and paints 5 sites.
    mask = trues(6, 6)
    mask[2, 3] = false
    empty!(P61A6_SEEN)
    op = layout(P61a6Probe(:s, :keep), Lattice((6, 6); boundary = Closed(), domain = mask))
    @test P61A6_SEEN == [(0, false, false), (1, 2, 5, 4)]
    σ = zeros(Int32, 6, 6)
    σ[2, [1, 2, 4, 5, 6]] .= 1
    σ[5:6, 5:6] .= 2
    @test p61a6_σ(op) == σ && p61a6_kinds(op) == [:s, :s]
end

# ---------------------------------------------------------------------------------------------
# The report
# ---------------------------------------------------------------------------------------------

@testset "P6.1a6: layout(l, x; report = true), one row per leaf layer" begin
    # Closed 8 × 4, rows y 1:3 painted, y = 4 medium.
    #   L1 Tiling 3 × 3 clipped over (1:8, 1:3): c1 = x 1:3, c2 = x 4:6, c3 = x 7:8 (clipped)
    #   L2 Tiling 2 × 3 over (7:8, 1:3), kind b: covers c3, which is dropped (cut, not split)
    #   L3 Tiling 1 × 3 over (5:5, 1:3), kind x: cuts c2 into x = 4 and x = 6 (a split, one
    #      warning: L3 is the only layer that cut c2)
    #   L4 InsertUntil(:y; into = [:a], number = 1, misses = :count) over (2:2, 3:4): draw 1
    #      is (2, 3) (c1, a hit), draw 2 is (2, 4) (medium, a miss). It stops after the first
    #      hit; c1 keeps 8 connected sites. counted = 1 + misses.
    # Final ids: c1 = 1, c2 = 2, b = 3, x = 4, y = 5.
    S = 8
    l(s3) = overlay(Tiling((3, 3); region = (1:8, 1:3), kinds = [:a], partial = :clip),
        Tiling((2, 3); region = (7:8, 1:3), kinds = [:b]),
        Tiling((1, 3); region = (5:5, 1:3), kinds = [:x], splits = s3),
        InsertUntil(:y; into = [:a], number = 1, seed = S, misses = :count, region = (2:2, 3:4)))
    # the misses from the documented draw rule: StableRNG(seed), rand(rng, 1:length(sites))
    rng = StableRNG(S)
    m = 0
    while rand(rng, 1:2) == 2
        m += 1
    end
    @test m == 2                                                     # recorded at ec544d8
    op, rep = p61a6_quietly(() -> layout(l(:warn), (8, 4); report = true))
    σ = Int32[1 1 1 2 4 2 3 3
              1 1 1 2 4 2 3 3
              1 5 1 2 4 2 3 3
              0 0 0 0 0 0 0 0]'
    @test p61a6_σ(op) == σ && p61a6_kinds(op) == [:a, :a, :b, :x, :y]
    @test [r.type for r in rep] == [:Tiling, :Tiling, :Tiling, :InsertUntil]
    #                     requested painted dropped misses counted splits
    @test p61a6_row.(rep) == [(3, 3, 1, 0, 3, 0),
                              (1, 1, 0, 0, 1, 0),
                              (1, 1, 0, 0, 1, 1),
                              (1, 1, 0, m, 1 + m, 0)]
    @test p61a6_σ(p61a6_quietly(() -> layout(l(:warn), (8, 4)))) == σ   # the same point without the report
    @test p61a6_σ(p61a6_quietly(() -> layout(l(:warn), (8, 4); report = false))) == σ
    # the split is reported whatever the setting; only the warning depends on it
    @test p61a6_splitwarns(() -> layout(l(:warn), (8, 4))) == 1
    @test p61a6_splitwarns(() -> layout(l(:allow), (8, 4))) == 0
    @test p61a6_row.(p61a6_rows(l(:allow), (8, 4))) == p61a6_row.(rep)
    # a single leaf is one row; a nested overlay is flattened
    @test p61a6_row.(p61a6_rows(Frame(:w), (5, 5))) == [(1, 1, 0, 0, 1, 0)]
    @test length(p61a6_rows(overlay(overlay(Frame(:w), Tiling((1, 1); region = (3:3, 3:3), kinds = [:a])),
        Scattered(1, (1, 1); region = (2:2, 2:2), kinds = [:z], seed = 1)), (5, 5))) == 3
    # Scattered requests n and paints n
    @test p61a6_row.(p61a6_rows(Scattered(3, (2, 2); kinds = [:a], seed = 1), (20, 20))) == [(3, 3, 0, 0, 3, 0)]
    # InsertUntil under :retry: painted = counted = number, misses as drawn
    tiles = Tiling((2, 2); spacing = 1, kinds = [:a, :b])
    r = p61a6_rows(overlay(tiles, InsertUntil(:x; into = [:a], number = 10, seed = 3)), (21, 21))
    @test p61a6_row(r[1]) == (49, 49, 0, 0, 49, 0) && p61a6_row(r[2]) == (10, 10, 0, 55, 10, 0)
end

# ---------------------------------------------------------------------------------------------
# Tiling(partial)
# ---------------------------------------------------------------------------------------------

@testset "P6.1a6: Tiling(partial = :skip | :clip)" begin
    row(op) = vec(p61a6_σ(op)[:, 1])
    # 7 wide, boxes of 3: :clip keeps the 1-wide box 7:7, :skip (default) leaves column 7 empty
    clip = layout(Tiling((3, 3); region = (1:7, 1:3), kinds = [:a], partial = :clip), (7, 3))
    @test p61a6_σ(clip) == repeat(Int32[1, 1, 1, 2, 2, 2, 3], 1, 3) && p61a6_kinds(clip) == [:a, :a, :a]
    skip = layout(Tiling((3, 3); region = (1:7, 1:3), kinds = [:a], partial = :skip), (7, 3))
    @test p61a6_σ(skip) == repeat(Int32[1, 1, 1, 2, 2, 2, 0], 1, 3) && p61a6_kinds(skip) == [:a, :a]
    @test p61a6_σ(layout(Tiling((3, 3); region = (1:7, 1:3), kinds = [:a]), (7, 3))) == p61a6_σ(skip)
    @test p61a6_row.(p61a6_rows(Tiling((3, 3); region = (1:7, 1:3), kinds = [:a], partial = :clip), (7, 3))) ==
          [(3, 3, 0, 0, 3, 0)]
    # clipped at the region, not only at the lattice (the CompuCell3D difference): region 2:6
    @test row(layout(Tiling((3, 3); region = (2:6, 1:3), kinds = [:a], partial = :clip), (7, 3))) ==
          Int32[0, 1, 1, 1, 2, 2, 0]
    @test row(layout(Tiling((3, 3); region = (2:6, 1:3), kinds = [:a]), (7, 3))) == Int32[0, 1, 1, 1, 0, 0, 0]
    # region ∩ lattice: a region reaching past the lattice is clipped at the lattice …
    @test p61a6_σ(layout(Tiling((3, 3); region = (1:9, 1:3), kinds = [:a], partial = :clip), (7, 3))) == p61a6_σ(clip)
    # … and still throws under :skip (D-057)
    @test_throws ArgumentError layout(Tiling((3, 3); region = (1:9, 1:3), kinds = [:a]), (7, 3))
    # 2D with spacing 1 on 6 × 4: starts x ∈ {1, 4}, y ∈ {1, 4}; the top row of boxes is
    # clipped to y = 4; ids x-fastest, kinds cycled a, b
    σ = Int32[1 1 0 2 2 0
              1 1 0 2 2 0
              0 0 0 0 0 0
              3 3 0 4 4 0]'
    op = layout(Tiling((2, 2); spacing = 1, region = (1:6, 1:4), kinds = [:a, :b], partial = :clip), (6, 4))
    @test p61a6_σ(op) == σ && p61a6_kinds(op) == [:a, :b, :a, :b]
    op = layout(Tiling((2, 2); spacing = 1, region = (1:6, 1:4), kinds = [:a, :b]), (6, 4))
    σ[:, 4] .= 0
    @test p61a6_σ(op) == σ && p61a6_kinds(op) == [:a, :b]
    @test_throws ArgumentError Tiling((3, 3); kinds = [:a], partial = :bogus)
end

# ---------------------------------------------------------------------------------------------
# splits
# ---------------------------------------------------------------------------------------------

@testset "P6.1a6: splits = :warn | :allow, exempt only if every cutter allows" begin
    # Closed 5 × 3 with a bar cell on (1:5, 2). `mid` takes (3, 2) and splits the bar into
    # (1:2, 2) and (4:5, 2); `tip` takes (5, 2) and leaves it connected.
    lat = (5, 3)
    bar = Tiling((5, 1); region = (1:5, 2:2), kinds = [:a])
    mid(s) = Tiling((1, 1); region = (3:3, 2:2), kinds = [:m], splits = s)
    tip(s) = Tiling((1, 1); region = (5:5, 2:2), kinds = [:e], splits = s)
    w(ls...) = p61a6_splitwarns(() -> layout(overlay(bar, ls...), lat))
    @test w(Tiling((1, 1); region = (3:3, 2:2), kinds = [:m])) == 1             # default :warn
    @test w(mid(:warn)) == 1
    @test w(mid(:allow)) == 0
    @test w(tip(:warn)) == 0                                                     # cut, not split
    @test w(mid(:allow), tip(:allow)) == 0
    @test w(mid(:allow), tip(:warn)) == 1      # a :warn layer also cut the split cell
    @test w(tip(:warn), mid(:allow)) == 1      # in either order
    # per cell: a :warn layer that cuts ANOTHER cell does not withdraw the exemption.
    # Two bars on y = 1 and y = 3; `mid` (allow) splits bar 1, `tip` (warn) trims bar 2.
    bars = Tiling((5, 1); spacing = (0, 1), region = (1:5, 1:3), kinds = [:a])
    w2(ls...) = p61a6_splitwarns(() -> layout(overlay(bars, ls...), lat))
    m1(s) = Tiling((1, 1); region = (3:3, 1:1), kinds = [:m], splits = s)
    t3(s) = Tiling((1, 1); region = (5:5, 3:3), kinds = [:e], splits = s)
    @test w2(m1(:allow), t3(:warn)) == 0
    @test w2(m1(:warn), t3(:allow)) == 1
    # every shipped layer takes the keyword and validates it
    @test Tiling((1, 1); kinds = [:a], splits = :allow) isa AbstractLayout
    @test Scattered(1, (1, 1); kinds = [:a], seed = 1, splits = :allow) isa AbstractLayout
    @test Frame(:w; splits = :allow) isa AbstractLayout
    @test InsertUntil(:x; into = [:a], number = 1, seed = 1, splits = :allow) isa AbstractLayout
    @test_throws ArgumentError Tiling((1, 1); kinds = [:a], splits = :maybe)
    @test_throws ArgumentError Scattered(1, (1, 1); kinds = [:a], seed = 1, splits = :maybe)
    @test_throws ArgumentError Frame(:w; splits = :maybe)
    @test_throws ArgumentError InsertUntil(:x; into = [:a], number = 1, seed = 1, splits = :maybe)
    # InsertUntil(splits = :allow): an inserted site that splits a 3 × 1 host is silent
    host = Tiling((3, 1); region = (1:3, 2:2), kinds = [:h])
    ins(s) = InsertUntil(:x; into = [:h], number = 1, seed = 1, region = (2:2, 2:2), splits = s)
    @test p61a6_splitwarns(() -> layout(overlay(host, ins(:warn)), (3, 3))) == 1
    @test p61a6_splitwarns(() -> layout(overlay(host, ins(:allow)), (3, 3))) == 0
end

# ---------------------------------------------------------------------------------------------
# remake
# ---------------------------------------------------------------------------------------------

@testset "P6.1a6: remake(::AbstractLayout; kw...) re-runs the keyword constructor" begin
    s1 = Scattered(4, (2, 2); kinds = [:a], seed = 1)
    s2 = remake(s1; seed = 2)
    @test s2 isa Scattered
    σ(l) = p61a6_σ(layout(l, (20, 20)))
    @test σ(s2) == σ(Scattered(4, (2, 2); kinds = [:a], seed = 2))
    @test σ(s2) != σ(s1)                                             # control: the seed matters
    @test σ(remake(s1)) == σ(s1)
    @test_throws ArgumentError remake(s1; seed = -1)
    @test_throws ArgumentError remake(s1; gap = -1)
    @test_throws ArgumentError remake(s1; splits = :maybe)

    # 49 tiles of 2 × 2 (25 a); 10 insertions into a. Under :count, seed 3 stops at
    # (painted 2, misses 16, counted 18); under :retry (10, 55, 10) (both at ec544d8).
    tiles = Tiling((2, 2); spacing = 1, kinds = [:a, :b])
    iu = InsertUntil(:x; into = [:a], number = 10, seed = 3, misses = :count)
    tally(l) = (r = p61a6_ins(p61a6_rows(overlay(tiles, l), (21, 21))); (r.painted, r.misses, r.counted))
    @test tally(iu) == (2, 16, 18)
    iu2 = remake(iu; misses = :retry)
    @test iu2 isa InsertUntil
    @test tally(iu2) == (10, 55, 10) == tally(InsertUntil(:x; into = [:a], number = 10, seed = 3, misses = :retry))
    @test p61a6_σ(layout(overlay(tiles, iu2), (21, 21))) ==
          p61a6_σ(layout(overlay(tiles, InsertUntil(:x; into = [:a], number = 10, seed = 3)), (21, 21)))
    @test tally(remake(iu2; misses = :count)) == tally(iu)                    # round trip
    @test_throws ArgumentError remake(iu; misses = :ghost)
    @test_throws ArgumentError remake(iu; fraction = 1 // 4)                  # two stop rules
    @test_throws ArgumentError remake(iu; seed = -1)

    t = Tiling((3, 3); region = (1:7, 1:3), kinds = [:a])
    @test length(p61a6_kinds(layout(remake(t; partial = :clip), (7, 3)))) == 3
    @test length(p61a6_kinds(layout(t, (7, 3)))) == 2
    @test_throws ArgumentError remake(t; partial = :bogus)
    @test_throws ArgumentError remake(Frame(:w); width = 0)
end

# ---------------------------------------------------------------------------------------------
# Removals (D-028: no alias)
# ---------------------------------------------------------------------------------------------

@testset "P6.1a6: paint!(σ, kinds, …) and layout_tally are gone" begin
    @test !(isdefined(Potts, :layout_tally) && (Base.ispublic(Potts, :layout_tally) || Base.isexported(Potts, :layout_tally)))
    @test !(isdefined(PottsModels, :layout_tally) && Base.ispublic(PottsModels, :layout_tally))
    @test Base.ispublic(Potts, :paint!)
    ms = [m for m in methods(Potts.paint!) if m.module in (Potts, PottsModels)]
    @test length(ms) >= 6               # Tiling, Scattered, Frame, InsertUntil, overlay, Voronoi (VoronoiBall's successor, D-138)
    @test all(m -> m.nargs == 4, ms)    # #self#, op, l, lat: no paint!(σ, kinds, l, lat)
    for T in (Tiling, Scattered, Frame, InsertUntil, typeof(overlay(Frame(:w), Frame(:v))), Potts.Voronoi)
        @test isempty(methods(Potts.paint!, (AbstractArray, Any, T, Any)))
        @test any(m -> m.nargs == 4, methods(Potts.paint!, (Potts.LayoutState, T, Potts.LatticeSpec)))
    end
    # VoronoiBall's successor paints (on the new protocol; D-138: `VoronoiBall(n; radius, kinds, seed)`
    # is `Voronoi(RandomPoints(n; region = ball, seed); region = ball, lloyd = 30, kinds)`)
    ball = Potts.Circle(Potts.Point(12.5, 12.5), 8.0)
    op = layout(Potts.Voronoi(Potts.RandomPoints(4; region = ball, seed = 1); region = ball, lloyd = 30, kinds = Int32[1, 2]), (24, 24))
    @test sort(unique(p61a6_σ(op))) == 0:4 && length(p61a6_kinds(op)) == 4
end

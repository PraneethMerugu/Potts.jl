# Layouts (P6.1a): spec-level properties with independent checks (D-048).
using PottsModels: akeeb_state
using Test: Test

_op(op, key) = only(last(p) for p in op if isequal(first(p), key))
# operating points compared by value (their keys are symbolic)
_same(a, b) = _op(a, ownership) == _op(b, ownership) && _op(a, kind) == _op(b, kind)
_sites(σ, c) = findall(==(c), σ)
# the smallest Chebyshev distance between two site sets (brute force)
_cheb(a, b) = minimum(maximum(abs.(Tuple(x - y))) for x in a, y in b)
# every pair of distinct cells is more than `gap` sites apart (Chebyshev)
_separated(σ, gap) = (n = maximum(σ);
    all(_cheb(_sites(σ, a), _sites(σ, b)) > gap for a in 1:n for b in (a + 1):n))

@potts_model HexLayoutProbe begin
    @kinds medium wall[frozen] cell
    @parameters begin
        J[kind, kind] = [0 0 8; 0 0 12; 8 12 4]
    end
    @lattice Lattice((18, 14); boundary = Closed(), geometry = Hexagonal(), neighborhood = Hex(1))
    @energy begin
        cells(cell) => (volume - 9)^2
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model PeriodicLayoutProbe begin
    @kinds medium cell
    @lattice Lattice((12, 12); boundary = Periodic())
    @energy contacts => 0
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model ChannelLayoutProbe begin
    @kinds medium wall cell
    @lattice Lattice((11, 11); boundary = (Periodic(), Closed()))
    @energy contacts => 0
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model DomainLayoutProbe begin
    @kinds medium cell
    @lattice Lattice((10, 10); boundary = Closed(), domain = OnIndices(x -> x[1] <= 5))
    @energy contacts => 0
    @sweep Metropolis(; temperature = 1.0)
end

# a disk domain (Cartesian predicate) with a frozen wall kind; the same model with a mobile
# wall is the negative control for "the frame stays put"
@potts_model DiskFrameProbe begin
    @kinds medium wall[frozen] cell
    @parameters begin
        J[kind, kind] = [0 0 8; 0 0 12; 8 12 4]
    end
    @lattice Lattice((24, 24); boundary = Closed(), domain = x -> (x[1] - 12.5)^2 + (x[2] - 12.5)^2 <= 10.5^2)
    @energy begin
        cells(cell) => (volume - 9)^2
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model DiskMobileWallProbe begin
    @kinds medium wall cell
    @parameters begin
        J[kind, kind] = [0 0 8; 0 0 12; 8 12 4]
    end
    @lattice Lattice((24, 24); boundary = Closed(), domain = x -> (x[1] - 12.5)^2 + (x[2] - 12.5)^2 <= 10.5^2)
    @energy begin
        cells(cell) => (volume - 9)^2
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = 4.0)
end

# brute-force frame oracle: in-domain sites with a site outside the domain, or beyond a
# closed lattice edge, within Chebyshev distance `w` (through the wrap on periodic axes)
function _frame_oracle(mask, per, w)
    dims = size(mask)
    return [mask[i] &&
            any(CartesianIndices(ntuple(_ -> (-w):w, ndims(mask)))) do o
        j = Tuple(i) .+ Tuple(o)
        all(d -> per[d] || 1 <= j[d] <= dims[d], 1:ndims(mask)) || return true
        !mask[CartesianIndex(map((x, n, p) -> p ? mod1(x, n) : x, j, dims, per))]
    end for i in CartesianIndices(mask)]
end

# two distinct cells touch (Moore(1)), through the wrap on axes marked periodic
function _touching(σ, per)
    n = size(σ)
    for i in CartesianIndices(σ), d in CartesianIndices(ntuple(_ -> -1:1, ndims(σ)))
        j = Tuple(i + d)
        all(k -> per[k] || 1 <= j[k] <= n[k], 1:ndims(σ)) || continue
        s = σ[CartesianIndex(map((x, m, p) -> p ? mod1(x, m) : x, j, n, per))]
        σ[i] != 0 && s != 0 && σ[i] != s && return true
    end
    return false
end

@testset "layouts: Tiling" begin
    # counts, volumes and bounds, checked against the arithmetic of whole boxes
    for (sz, sp, reg, dims) in (((3, 2), (1, 0), (2:19, 4:11), (20, 12)), ((4, 4), (2, 2), (1:17, 1:17), (17, 17)),
        ((2, 3, 2), (1, 1, 0), (1:9, 2:10, 1:6), (10, 10, 6)))
        op = layout(Tiling(sz; spacing = sp, region = reg, kinds = [:a, :b, :c]), dims)
        σ, k = _op(op, ownership), _op(op, kind)
        nper = map((r, s, p) -> fld(length(r) - s, s + p) + 1, reg, sz, sp)
        @test size(σ) == dims && eltype(σ) == Int32
        @test maximum(σ) == prod(nper) == length(k)
        @test all(c -> length(_sites(σ, c)) == prod(sz), 1:maximum(σ))
        @test all(i -> all(d -> i[d] in reg[d], 1:length(dims)), findall(>(0), σ))
        @test k == [(:a, :b, :c)[mod1(c, 3)] for c in 1:maximum(σ)]
        # column-major placement: cell 2 follows cell 1 along the first axis
        @test minimum(_sites(σ, 2))[1] - minimum(_sites(σ, 1))[1] == sz[1] + sp[1]
    end
    # boxes with spacing 0 tile the region exactly
    σ = _op(layout(Tiling((3, 3); kinds = [:a]), (9, 12)), ownership)
    @test all(>(0), σ) && maximum(σ) == 12
    @test layout(Tiling(3; kinds = [:a]), (7,))[1][2] == Int32[1, 1, 1, 2, 2, 2, 0]   # 1D, integer size
end

@testset "layouts: invalid arguments" begin
    err(f) = try
        f(); ""
    catch e
        e isa ArgumentError ? e.msg : rethrow()
    end
    @test occursin("outside the lattice", err(() -> layout(Tiling((2, 2); region = (1:5, 1:11), kinds = [:a]), (10, 10))))
    @test occursin("outside the lattice", err(() -> layout(Tiling((2, 2); region = (0:5, 1:5), kinds = [:a]), (10, 10))))
    @test occursin("2D, the lattice 3D", err(() -> layout(Tiling((2, 2); kinds = [:a]), (10, 10, 10))))
    @test occursin("region has 3 ranges", err(() -> Tiling((2, 2); region = (1:5, 1:5, 1:5), kinds = [:a])))
    @test occursin("empty", err(() -> Tiling((2, 2); region = (1:5, 5:4), kinds = [:a])))
    @test occursin("unit ranges", err(() -> Tiling((2, 2); region = (1:2:9, 1:5), kinds = [:a])))
    @test occursin("positive", err(() -> Tiling((2, 0); kinds = [:a])))
    @test occursin("non-negative", err(() -> Tiling((2, 2); spacing = -1, kinds = [:a])))
    @test occursin("`kinds` is empty", err(() -> Tiling((2, 2); kinds = Symbol[])))
    @test occursin("no box of size (6, 2) fits", err(() -> layout(Tiling((6, 2); region = (1:5, 1:5), kinds = [:a]), (10, 10))))
    @test occursin("width must be at least 1", err(() -> Frame(:w; width = 0)))
    @test occursin("gap must be non-negative", err(() -> Scattered(2, (2, 2); kinds = [:a], seed = 1, gap = -1)))
    @test occursin("do not fit", err(() -> layout(Scattered(1, (6, 6); kinds = [:a], seed = 1), (5, 20))))
    @test occursin("positive", err(() -> layout(Frame(:w), (0, 4))))
    # negative control: a valid call raises nothing
    @test err(() -> layout(Tiling((2, 2); region = (1:10, 1:10), kinds = [:a]), (10, 10))) == ""
end

@testset "layouts: Frame and overlay precedence" begin
    for (dims, w) in (((9, 7), 1), ((10, 12), 2), ((6, 7, 8), 1))
        σ = _op(layout(Frame(:w; width = w), dims), ownership)
        inner = prod(dims .- 2w)
        @test count(==(1), σ) == prod(dims) - inner && count(==(0), σ) == inner
    end
    tiles = Tiling((2, 2); kinds = [:a])                  # 9 cells on 6×6
    # tiles under a frame: corners keep 1 site, edges 2, the centre 4; the frame is last
    op = layout(overlay(tiles, Frame(:w)), (6, 6))
    σ, k = _op(op, ownership), _op(op, kind)
    @test k == [fill(:a, 9); :w]
    @test [length(_sites(σ, c)) for c in 1:9] == [1, 2, 1, 2, 4, 2, 1, 2, 1]
    @test length(_sites(σ, 10)) == 20
    # negative control: the frame under the tiles keeps nothing (tiles cover the lattice)
    op = layout(overlay(Frame(:w), tiles), (6, 6))
    @test _op(op, kind) == fill(:a, 9) && [length(_sites(_op(op, ownership), c)) for c in 1:9] == fill(4, 9)
    # a fully covered cell is dropped and ids stay consecutive
    op = layout(overlay(Tiling((1, 1); region = (1:1, 1:1), kinds = [:x]), Tiling((1, 1); region = (3:3, 3:3), kinds = [:y]),
        Frame(:w)), (5, 5))
    @test _op(op, kind) == [:y, :w] && sort(unique(_op(op, ownership))) == Int32[0, 1, 2]
    # a later layer that cuts a cell in two warns, naming the cell (Moore(1) neighbourhood)
    bar = Tiling((6, 2); region = (1:6, 3:4), kinds = [:a])
    cutter = Tiling((2, 2); region = (3:4, 3:4), kinds = [:b])
    @test_logs (:warn, r"split cell 1 \(kind a\)") layout(overlay(bar, cutter), (6, 6))
    # negative control: trimming its end leaves it connected, no warning
    @test_logs min_level = Base.CoreLogging.Warn layout(overlay(bar, Tiling((2, 2); region = (5:6, 3:4), kinds = [:b])), (6, 6))
    # overlay is associative (nested overlays flatten)
    a, b = Frame(:w), Tiling((3, 3); spacing = 1, region = (2:19, 2:19), kinds = [:a])
    c = Scattered(3, (2, 2); region = (2:19, 2:19), kinds = [:s], seed = 4)
    ref = layout(overlay(a, b, c), (20, 20))
    @test _same(layout(overlay(overlay(a, b), c), (20, 20)), ref) && _same(layout(overlay(a, overlay(b, c)), (20, 20)), ref)
    @test !_same(layout(overlay(c, b, a), (20, 20)), ref)             # negative control: order matters
end

@testset "layouts: Scattered" begin
    # 3D, gap 2: every pair of cells is more than two sites apart, volumes by counting
    for seed in 1:3
        σ = _op(layout(Scattered(8, (3, 3, 3); region = (2:19, 2:19, 2:19), kinds = [:a, :b], seed, gap = 2), (20, 20, 20)),
            ownership)
        @test maximum(σ) == 8 && all(c -> length(_sites(σ, c)) == 27, 1:8)
        @test all(i -> all(d -> 2 <= i[d] <= 19, 1:3), findall(>(0), σ))
        @test _separated(σ, 2)
    end
    # negative control: the separation check catches two touching boxes
    σ = zeros(Int32, 10, 10); σ[1:2, 1:2] .= 1; σ[4:5, 4:5] .= 2
    @test _separated(σ, 1) && !_separated(σ, 2)
    # gap 0 allows touching boxes but never overlap: a denser packing keeps full volumes
    σ = _op(layout(Scattered(8, (2, 2); kinds = [:a], seed = 3, gap = 0), (8, 8)), ownership)
    @test maximum(σ) == 8 && all(c -> length(_sites(σ, c)) == 4, 1:8)
    # deterministic in the seed (StableRNG): pinned lower corners, stable across Julia versions
    corners(seed) = (σ = _op(layout(Scattered(3, (2, 2); kinds = [:a], seed), (30, 30)), ownership);
        [Tuple(minimum(_sites(σ, c))) for c in 1:3])
    @test corners(7) == corners(7)
    @test corners(7) != corners(8)
    @test corners(7) == [(2, 27), (6, 8), (13, 6)]
    @test_throws ArgumentError layout(Scattered(26, (4, 4); kinds = [:a], seed = 1), (24, 24))   # area bound
    # within the area bound (300·25 ≤ 101²) but random sequential placement jams
    msg = try
        layout(Scattered(300, (4, 4); kinds = [:a], seed = 1), (100, 100)); ""
    catch e
        e.msg
    end
    @test occursin(r"could not place box \d+ of 300", msg) && occursin("jammed", msg)
    # seeds are UInt64: seeds above typemax(Int) work and differ; negative seeds are rejected
    big = layout(Scattered(3, (2, 2); kinds = [:a], seed = typemax(UInt64)), (30, 30))
    @test maximum(_op(big, ownership)) == 3 && _op(big, ownership) != _op(layout(Scattered(3, (2, 2); kinds = [:a], seed = 0), (30, 30)), ownership)
    @test_throws ArgumentError Scattered(3, (2, 2); kinds = [:a], seed = -1)
end

@testset "layouts: wrap-aware area bound" begin
    msg(dims) = try
        layout(Scattered(10, (3, 3); kinds = [:cell], seed = 1), dims); ""
    catch e
        e.msg
    end
    # 10 boxes of 3×3 with gap 1 need 160 sites of room: a 12×12 torus has 144
    @test occursin("cannot fit", msg(PeriodicLayoutProbe(; name = :p)))
    # control: closed 12×12 has 13² = 169 of room, so the bound passes and placement jams
    @test occursin("could not place", msg((12, 12)))
    # the grown box side is clamped to the ring too: one 3×3 box with gap 10 always fits a
    # 12×12 torus (it was rejected as 13² > 12²)
    one = layout(Scattered(1, (3, 3); kinds = [:cell], seed = 1, gap = 10), PeriodicLayoutProbe(; name = :p))
    @test count(==(1), _op(one, ownership)) == 9 && maximum(_op(one, ownership)) == 1
    # control: two such boxes are infeasible (each needs the whole ring on some axis)
    @test_throws "cannot fit" layout(Scattered(2, (3, 3); kinds = [:cell], seed = 1, gap = 10),
        PeriodicLayoutProbe(; name = :p))
end

@testset "layouts: periodic lattices" begin
    sys = PeriodicLayoutProbe(; name = :p)
    per = (true, true)
    sc(seed) = layout(Scattered(4, (3, 3); kinds = [:cell], seed), sys)
    # the gap holds through the wrap on a periodic system
    @test !any(seed -> _touching(_op(sc(seed), ownership), per), 1:100)
    @test all(seed -> all(c -> count(==(c), _op(sc(seed), ownership)) == 9, 1:4), 1:100)
    # negative control: the same layers laid on a closed 12×12 lattice touch through the
    # wrap for some seeds (the gap is only enforced inside the lattice there)
    @test any(seed -> _touching(_op(layout(Scattered(4, (3, 3); kinds = [:cell], seed), (12, 12)), ownership), per), 1:100)
    # Tiling: on a periodic axis the last box closer than `spacing` to the first is skipped
    t = Tiling((3, 3); spacing = 1, kinds = [:cell])
    @test maximum(_op(layout(t, PeriodicLayoutProbe(; name = :q)), ownership)) == 9       # 12 = 3·4: all fit
    ch = ChannelLayoutProbe(; name = :c)                                               # 11×11, x periodic
    σ = _op(layout(t, ch), ownership)
    @test maximum(σ) == 2 * 3 && !_touching(σ, (true, false))
    @test maximum(_op(layout(t, (11, 11)), ownership)) == 9                            # control: closed keeps 3×3
    @test _touching(_op(layout(t, (11, 11)), ownership), (true, false))
    # Frame: walls only across the closed axis (a channel); no edge when all axes wrap
    σ = _op(layout(Frame(:wall), ch), ownership)
    @test findall(==(1), σ) == findall(i -> i[2] in (1, 11), CartesianIndices(σ))
    @test_throws ArgumentError layout(Frame(:wall), sys)
end

@testset "layouts: lattices, systems and problems" begin
    # hexagonal lattice: indices are axial, dims come from the lattice
    sys = HexLayoutProbe(; name = :h)
    l = overlay(Frame(:wall), Tiling((3, 3); spacing = 1, region = (3:16, 3:12), kinds = [:cell]))
    op = layout(l, sys)
    σ = _op(op, ownership)
    @test size(σ) == (18, 14) && maximum(σ) == 1 + 3 * 2
    @test _same(layout(l, mtkcompile(sys)), op) && _same(layout(l, (18, 14)), op) &&
          _same(layout(l, Lattice((18, 14); boundary = Closed(), geometry = Hexagonal())), op)
    prob = PottsProblem(sys, op, (0, 5))
    @test prob.lattice.geometry isa Hexagonal
    u = solve(prob, SequentialCPM(proposal = Hex(1))).u[end]
    @test Array(u.σ)[σ .== 1] == σ[σ .== 1]                            # the frozen frame stays
    @test u.cell.volume == [count(==(c), u.σ) for c in 1:maximum(σ)]
    # a lattice domain: cells must lie inside it
    lat = Lattice((10, 10); domain = OnIndices(x -> x[1] <= 5))
    @test _op(layout(Tiling((2, 2); region = (1:5, 1:10), kinds = [:a]), lat), ownership)[6:end, :] == zeros(Int32, 5, 10)
    @test _op(layout(Frame(:w), lat), ownership) == _frame_oracle(lat.mask, (true, true), 1)   # P6.1a2 (periodic)
    # the same domain from a model's @lattice (LatticeSpec path)
    dsys = DomainLayoutProbe(; name = :d)
    @test _op(layout(Tiling((2, 2); region = (1:5, 1:10), kinds = [:cell]), dsys), ownership)[6:end, :] == zeros(Int32, 5, 10)
    @test_throws r"outside the lattice domain" layout(Tiling((2, 2); kinds = [:cell]), dsys)
end

@testset "layouts: Frame on a lattice domain (P6.1a2)" begin
    sys = DiskFrameProbe(; name = :disk)
    mask = Potts.lattice(sys).domain
    for w in (1, 2)
        σ = _op(layout(Frame(:wall; width = w), sys), ownership)
        ring = σ .== 1
        @test ring == _frame_oracle(mask, (false, false), w)
        # a ring: inside the domain, not the whole domain, and it seals the interior (no
        # interior site is a Moore(1) neighbour of a site outside the domain)
        inner = mask .& .!ring
        @test !any(ring .& .!mask) && any(inner)
        @test !any(i -> inner[i] && any(o -> (j = i + o; !checkbounds(Bool, mask, j) || !mask[j]),
            CartesianIndices((-w:w, -w:w))), CartesianIndices(mask))
        # the ring is w sites thick along the axes through the centre (row 12 of the disk: 2:23)
        row = findall(mask[:, 12])
        @test findall(ring[:, 12]) == [row[1:w]; row[(end - w + 1):end]]
    end
    # negative controls: the oracle distinguishes widths, and the unmasked rule on the same
    # dims lies entirely outside the disk (the old behaviour, which the domain check rejects)
    @test _frame_oracle(mask, (false, false), 1) != _frame_oracle(mask, (false, false), 2)
    @test !any(mask .& (_op(layout(Frame(:wall), (24, 24)), ownership) .== 1))
    # a domain that meets closed lattice edges and a periodic wrap
    half = OnIndices(x -> x[1] <= 6)
    σ = _op(layout(Frame(:w), Lattice((12, 12); boundary = (Periodic(), Closed()), domain = half)), ownership)
    @test findall(==(1), σ) == findall(i -> i[1] <= 6 && (i[1] in (1, 6) || i[2] in (1, 12)), CartesianIndices(σ))
    σ = _op(layout(Frame(:w), Lattice((12, 12); boundary = Periodic(), domain = half)), ownership)
    @test findall(==(1), σ) == findall(i -> i[1] in (1, 6), CartesianIndices(σ))           # x = 1 meets 12 by wrap
    @test_throws r"no boundary" layout(Frame(:w), Lattice((6, 6); boundary = Periodic(), domain = trues(6, 6)))
    # hex (axial indices): a concave domain (a disk minus a wedge) gets the oracle ring, and
    # no in-domain site off the ring has a Hex(1) neighbour outside the domain (it seals)
    domain_frame(mask, bnd, w; geometry = Potts.CorePotts.Square()) =
        _op(layout(Frame(:w; width = w), Potts.lattice_spec(size(mask); boundary = bnd, domain = mask, geometry)),
            ownership) .== 1
    pacman = [(x - 9)^2 + (y - 9)^2 <= 49 && !(x > 9 && abs(y - 9) <= 2) for x in 1:18, y in 1:18]
    hexlat = Lattice((18, 18); boundary = Closed(), geometry = Hexagonal())
    hoffs = Potts.CorePotts.relation(Hex(1), hexlat).offsets
    for w in 1:3
        ring = domain_frame(pacman, Closed(), w; geometry = Hexagonal())
        @test ring == _frame_oracle(pacman, (false, false), w)
        inner = pacman .& .!ring
        @test any(inner)
        @test all(i -> !inner[i] || all(o -> ((in, y) = Potts.CorePotts.shift(hexlat, Tuple(i), o); in && pacman[y...]), hoffs),
            CartesianIndices(pacman))
    end
    # 3D with mixed boundaries: random masks against the oracle
    rng = Potts.StableRNG(3)
    for _ in 1:40
        per = (rand(rng, Bool), rand(rng, Bool), rand(rng, Bool))
        m3 = rand(rng, rand(rng, 3:8), rand(rng, 3:8), rand(rng, 3:8)) .> rand(rng, (0.05, 0.2, 0.5))
        (any(m3) && !(all(m3) && all(per))) || continue
        w = rand(rng, 1:3)
        @test domain_frame(m3, map(p -> p ? Periodic() : Closed(), per), w) == _frame_oracle(m3, per, w)
    end
    # a frozen frame on the disk: the model runs and the frame stays put
    l = overlay(Frame(:wall), Tiling((3, 3); spacing = 1, region = (6:19, 6:19), kinds = [:cell]))
    op = layout(l, sys)
    σ0 = _op(op, ownership)
    @test maximum(σ0) == 1 + 9
    for alg in (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
        u = solve(PottsProblem(sys, op, (0, 20)), alg).u[end]
        σ = Array(u.σ)
        @test (σ .== 1) == (σ0 .== 1)                                       # the frame stays
        @test σ != σ0 && all(σ[.!mask] .== 0)                               # cells move, never leave the disk
        @test u.cell.volume[1:maximum(σ0)] == [count(==(c), σ) for c in 1:maximum(σ0)]
    end
    # negative control: the same frame with a mobile wall kind moves
    u = solve(PottsProblem(DiskMobileWallProbe(; name = :mob), op, (0, 20)), SequentialCPM(; proposal = Moore(1))).u[end]
    @test (Array(u.σ) .== 1) != (σ0 .== 1)
end

# The extension API: a layout defined outside Potts, through public names only.
module ScratchLayouts
using Potts: Potts, AbstractLayout
using CorePotts: CorePotts
"""Paint the given sites as one cell of kind `k`."""
struct Sites{N} <: AbstractLayout
    idx::Vector{NTuple{N, Int}}
    k::Symbol
end
function Potts.paint!(op::Potts.LayoutState, l::Sites, lat)
    clat = Potts.core_lattice(lat)                      # CorePotts view, e.g. for `shift`
    id = Potts.new_cell!(op, l.k)
    for i in l.idx
        _, j = CorePotts.shift(clat, i, ntuple(_ -> Int32(0), length(i)))
        Potts.assign!(op, Tuple(j), id)
    end
    Potts.record!(op; requested = 1, painted = 1)
end
# every qualified access above, as ExplicitImports' `check_all_qualified_accesses_are_public` sees them
const QUALIFIED = ((Potts, :paint!), (Potts, :LayoutState), (Potts, :core_lattice), (Potts, :new_cell!),
    (Potts, :assign!), (Potts, :record!), (CorePotts, :shift))
end

_warnings(f) = [r.message for r in Test.collect_test_logs(f; min_level = Base.CoreLogging.Warn)[1]]

@testset "layouts: extension API and split warnings" begin
    @test all(((m, n),) -> Base.ispublic(m, n), ScratchLayouts.QUALIFIED)
    @test !Base.ispublic(Potts, :_disconnected)                        # control: internals are not
    S = ScratchLayouts.Sites
    op = layout(overlay(Frame(:w), S([(3, 3), (4, 4)], :a)), (6, 6))
    @test _op(op, kind) == [:w, :a] && findall(==(2), _op(op, ownership)) == CartesianIndex.([(3, 3), (4, 4)])
    # hex: the axial diagonal (1, 1) is not a hex neighbour, the anti-diagonal (1, -1) is
    box = Tiling((2, 2); region = (1:2, 1:2), kinds = [:a])
    hexlat = Lattice((6, 6); boundary = Closed(), geometry = Hexagonal())
    @test length(_warnings(() -> layout(overlay(box, S([(1, 2), (2, 1)], :b)), hexlat))) == 1
    @test isempty(_warnings(() -> layout(overlay(box, S([(1, 1), (2, 2)], :b)), hexlat)))
    @test isempty(_warnings(() -> layout(overlay(box, S([(1, 2), (2, 1)], :b)), (6, 6))))   # square Moore(1): joined
    # a bar across a periodic axis stays connected through the wrap when cut once
    bar = Tiling((12, 1); region = (1:12, 2:2), kinds = [:a])
    mid = Tiling((1, 1); region = (5:5, 2:2), kinds = [:b])
    @test isempty(_warnings(() -> layout(overlay(bar, mid), PeriodicLayoutProbe(; name = :p))))
    @test length(_warnings(() -> layout(overlay(bar, mid), (12, 12)))) == 1                # control: closed splits
    # cost: one pass over σ, boxes trimmed by a frame are skipped (was 22 s at 200³)
    layout(overlay(Tiling((5, 5, 5); kinds = [:a]), Frame(:w; width = 3)), (12, 12, 12))
    t = @elapsed layout(overlay(Tiling((5, 5, 5); kinds = [:a]), Frame(:w; width = 3)), (60, 60, 60))
    @test t < 5
    # many genuinely split cells still flood-fill in linear time (warmed on a small 2D call)
    _warnings(() -> layout(overlay(Tiling((3, 3); kinds = [:a]), Tiling((1, 1); spacing = 2, region = (2:11, 2:11), kinds = [:b])),
        (12, 12)))
    t = @elapsed layout(overlay(Tiling((3, 3); kinds = [:a]), Tiling((1, 1); spacing = 2, region = (2:299, 2:299), kinds = [:b])),
        (300, 300))
    @test t < 5
    # P6.1a4: the lattice-sized `visited` array is allocated only for a flood fill. Every
    # cut cell below is a box trimmed by a frame, so the check allocates only per-cell
    # buffers (4096 cells), far below the 80³ Int32 array (2 MB).
    lat = Potts.lattice_spec((80, 80, 80); boundary = Closed())
    σ = _op(layout(overlay(Tiling((5, 5, 5); kinds = [:a]), Frame(:w; width = 3)), lat), ownership)
    check = [trues(maximum(σ) - 1); false]       # every tile, not the frame
    split = Int[]
    Potts._disconnected(c -> push!(split, c), σ, check, lat)
    bytes = @allocated Potts._disconnected(c -> push!(split, c), σ, check, lat)
    @test isempty(split) && bytes < sizeof(Int32) * 80^3 ÷ 4
    # … and a genuinely split cell among them is found (and allocates the array)
    σ2 = copy(σ)
    c = σ2[6, 6, 6]
    σ2[6:10, 6:10, 8] .= 0                       # a medium slab through tile `c` = (6:10)³
    Potts._disconnected(c -> push!(split, c), σ2, check, lat)
    @test split == [c]
    @test (@allocated Potts._disconnected(c -> nothing, σ2, check, lat)) >= sizeof(Int32) * 80^3
end

@testset "layouts reproduce an existing state's geometry" begin
    # the follower slab of `akeeb_state` is a 3×3 Tiling of the rows `y ≤ slab`; its
    # leaders then overwrite single follower sites
    X, Y, slab = 30, 30, 21
    ref = akeeb_state(; lattice = (X, Y), slab)
    σr, kr = _op(ref, ownership), _op(ref, kind)
    nf = count(==(:follower), kr)
    op = layout(Tiling((3, 3); region = (1:X, 1:slab), kinds = [:follower]), (X, Y))
    σ = _op(op, ownership)
    @test _op(op, kind) == kr[1:nf]
    followers = σr .<= nf                                     # medium and follower sites
    @test σ[followers] == σr[followers]
    @test all(σ[.!followers] .> 0)                            # every leader sits on a tile
    # negative control: a tiling one row shorter differs
    @test _op(layout(Tiling((3, 3); region = (1:X, 1:(slab - 3)), kinds = [:follower]), (X, Y)), ownership) != σ
end

# ---------------------------------------------------------------------------------------------
# InsertUntil (P6.2a, review §3 R2)
# ---------------------------------------------------------------------------------------------

@potts_model InsertProbe begin
    @kinds medium host guest
    @parameters begin
        J[kind, kind] = [0 8 8; 8 4 6; 8 6 4]
    end
    @lattice Lattice((16, 16); boundary = Closed(), domain = OnIndices(x -> x[1] + x[2] <= 26))
    @energy begin
        cells(host) => (volume - 16)^2
        cells(guest) => (volume - 4)^2
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = 4.0)
end

# the point and the InsertUntil rows of the layout report as (; painted, misses, counted)
function _tally(l, x)
    op, rep = layout(l, x; report = true)
    return op, [(; r.painted, r.misses, r.counted) for r in rep if r.type === :InsertUntil]
end
_kind_sites(op, k) = (σ = _op(op, ownership); ks = _op(op, kind); findall(i -> σ[i] > 0 && ks[σ[i]] == k, CartesianIndices(σ)))

@testset "layouts: InsertUntil stop rules (hand-derived counts)" begin
    # 16 hosts of 1 site and 4 guests of 9 sites. fraction 1/2 of guests, inserting guests into
    # hosts: every hit kills a host, so N + counted stays 20 and the rule 4 + c ≥ 10 needs 6
    # hits. Negative control: without the death, N would grow to 20 + c and need 12 hits.
    hosts = Tiling((1, 1); spacing = 1, region = (1:8, 1:8), kinds = [:host])        # 16 one-site cells
    guests = Tiling((3, 3); spacing = 1, region = (11:18, 11:18), kinds = [:guest])   # 4 cells
    l = overlay(hosts, guests, InsertUntil(:guest; into = [:host], fraction = 1 // 2, seed = 5))
    op, t = _tally(l, (20, 20))
    @test only(t).painted == 6 && only(t).counted == 6
    ks = _op(op, kind)
    @test count(==(:host), ks) == 10 && count(==(:guest), ks) == 10
    # `number` counts hits (retry) exactly; `number = 0` draws nothing
    for n in (0, 1, 7)
        op, t = _tally(overlay(hosts, InsertUntil(:guest; into = [:host], number = n, seed = 1)), (20, 20))
        @test only(t) == (; painted = n, misses = only(t).misses, counted = n)
        @test length(_kind_sites(op, :guest)) == n
    end
    # running out of allowed sites before the rule is met throws (16 hosts, 17 wanted)
    @test_throws ArgumentError layout(overlay(hosts, InsertUntil(:guest; into = [:host], number = 17, seed = 1)), (20, 20))
    @test length(_kind_sites(layout(overlay(hosts, InsertUntil(:guest; into = [:host], number = 16, seed = 1)), (20, 20)),
        :guest)) == 16
    # inserted cells are never drawn again as hits, even when their kind is allowed
    op, t = _tally(overlay(hosts, InsertUntil(:host; into = [:host], number = 16, seed = 2)), (20, 20))
    @test only(t).painted == 16 && count(==(:host), _op(op, kind)) == 16     # every host replaced once
    @test_throws ArgumentError layout(overlay(hosts, InsertUntil(:host; into = [:host], number = 17, seed = 2)), (20, 20))
    # no InsertUntil layer: no InsertUntil row; the point equals `layout`
    op, t = _tally(hosts, (20, 20))
    @test isempty(t) && _same(op, layout(hosts, (20, 20)))
end

@testset "layouts: InsertUntil draws uniformly over the region" begin
    # 4 one-site hosts in a 2 × 2 region; one insertion per seed lands on each about 1/4 of the time
    hosts = Tiling((1, 1); region = (3:4, 3:4), kinds = [:host])
    hits = zeros(Int, 4)
    for seed in 1:2000
        op = layout(overlay(hosts, InsertUntil(:guest; into = [:host], number = 1, seed, region = (3:4, 3:4))), (6, 6))
        i = only(_kind_sites(op, :guest))
        hits[LinearIndices((2, 2))[i[1] - 2, i[2] - 2]] += 1
    end
    @test all(h -> abs(h - 500) < 5 * sqrt(2000 * 0.25 * 0.75), hits)         # 5 SD
    # under :count with the region twice the hosts' area, about half the draws miss
    ts = [only(last(_tally(overlay(hosts,
        InsertUntil(:guest; into = [:host], number = 4, seed, misses = :count, region = (3:4, 3:6))), (6, 6))))
          for seed in 1:400]
    @test all(t -> t.painted + t.misses == t.counted && t.counted >= 4, ts)
    frac = sum(t -> t.misses, ts) / sum(t -> t.painted + t.misses, ts)
    @test 0.35 < frac < 0.65
end

@testset "layouts: InsertUntil on hex, 3D and domain lattices" begin
    # hex: axial indices, as every layer
    hexlat = Lattice((12, 12); boundary = Closed(), geometry = Hexagonal())
    op = layout(overlay(Tiling((3, 3); kinds = [:a, :b]), InsertUntil(:x; into = [:b], number = 5, seed = 3)), hexlat)
    base = layout(Tiling((3, 3); kinds = [:a, :b]), hexlat)
    σ0, k0 = _op(base, ownership), _op(base, kind)
    xs = _kind_sites(op, :x)
    @test length(xs) == 5 && all(i -> k0[σ0[i]] == :b, xs)
    # 3D
    op = layout(overlay(Tiling((2, 2, 2); kinds = [:a]), InsertUntil(:x; into = [:a], fraction = 1 // 5, seed = 4)), (6, 6, 6))
    @test count(==(:x), _op(op, kind)) == 7                                  # 27 + n ≤ 5n ⇒ n = 7
    # a domain: draws outside it land on medium and miss
    sys = InsertProbe(; name = :ins)
    op, t = _tally(overlay(Tiling((4, 4); region = (1:12, 1:12), kinds = [:host]),
        InsertUntil(:guest; into = [:host], number = 6, seed = 9)), sys)
    @test only(t).painted == 6 && only(t).misses > 0
    @test all(i -> i[1] + i[2] <= 26, findall(>(0), _op(op, ownership)))
    # the operating point runs
    prob = PottsProblem(sys, op, (0, 5))
    @test Symbol(solve(prob, SequentialCPM()).retcode) === :Success
    # bad regions
    @test_throws ArgumentError layout(overlay(Tiling((2, 2); kinds = [:a]),
        InsertUntil(:x; into = [:a], number = 1, seed = 1, region = (1:30, 1:4))), (8, 8))
    @test_throws ArgumentError layout(overlay(Tiling((2, 2); kinds = [:a]),
        InsertUntil(:x; into = [:a], number = 1, seed = 1, region = (1:4,))), (8, 8))
    @test_throws ArgumentError InsertUntil(:x; into = [:a], number = 1, seed = 1, region = (1:0, 1:3))
    @test_throws ArgumentError InsertUntil(:x; into = Symbol[], number = 1, seed = 1)
    @test_throws ArgumentError InsertUntil(:x; into = [:a], number = -1, seed = 1)
    @test_throws ArgumentError InsertUntil(:x; into = [:a], fraction = 1, seed = 1)
end

# ---------------------------------------------------------------------------------------------
# Shapes, point patterns and Voronoi (P6.1a5, D-138); the frozen acceptance file holds the
# hand counts, the VoronoiBall pins and the brute-force oracle
# ---------------------------------------------------------------------------------------------

@testset "layouts: layer_rng" begin
    @test rand(Potts.layer_rng(5), 3) == rand(Potts.layer_rng(UInt8(5)), 3)
    @test rand(Potts.layer_rng(5, :a), 3) != rand(Potts.layer_rng(5, :b), 3)
    @test rand(Potts.layer_rng(5, :a), 3) != rand(Potts.layer_rng(6, :a), 3)
    @test_throws ArgumentError Potts.layer_rng(typemax(UInt64) + big(1))
    @test_throws ArgumentError RandomPoints(1; seed = typemax(UInt64) + big(1))
end

@testset "layouts: Voronoi is equivariant under periodic translation" begin
    P = Potts.Point
    gens = [P(3.3, 4.1), P(14.2, 7.7), P(8.6, 15.4), P(18.1, 17.9), P(1.2, 12.6)]
    lat = Lattice((20, 20))
    for lloyd in (0, 5)
        σ = _op(layout(Voronoi(gens; lloyd, kinds = [:a]), lat), ownership)
        for s in ((7, 0), (0, 11), (13, 6))
            moved = [P(mod(g[1] + s[1], 20), mod(g[2] + s[2], 20)) for g in gens]
            @test _op(layout(Voronoi(moved; lloyd, kinds = [:a]), lat), ownership) == circshift(σ, s)
        end
        # a generator given through another period is the same generator
        far = [P(g[1] + 40, g[2] - 20) for g in gens]
        @test _op(layout(Voronoi(far; lloyd, kinds = [:a]), lat), ownership) == σ
    end
    # control: on a closed lattice a translation changes the tessellation
    σc = _op(layout(Voronoi(gens; kinds = [:a]), (20, 20)), ownership)
    moved = [P(mod(g[1] + 7, 20), g[2]) for g in gens]
    @test _op(layout(Voronoi(moved; kinds = [:a]), (20, 20)), ownership) != circshift(σc, (7, 0))
end

@testset "layouts: shapes on periodic 3D lattices and boxes on domains" begin
    # a sphere through the corner of a periodic cube wraps into all 8 corners, clips nothing
    op, rep = layout(Voronoi(Center(); region = Potts.Sphere(Potts.Point(1.0, 1.0, 1.0), 2.0), kinds = [:a]),
        Lattice((10, 10, 10)); report = true)
    σ = _op(op, ownership)
    @test count(!=(0), σ) == 33 && only(rep).clipped == 0
    @test all(x -> σ[x...] == 1, Iterators.product((1, 10), (1, 10), (1, 10)))
    # on a closed cube the same sphere keeps the 11 points with offsets ≥ 0
    @test only(last(layout(Voronoi(Center(); region = Potts.Sphere(Potts.Point(1.0, 1.0, 1.0), 2.0), kinds = [:a]),
        (10, 10, 10); report = true))).clipped == 22
    # a box region on a domain clips its out-of-domain sites
    dom = Lattice((10, 10); boundary = Closed(), domain = x -> x[1] <= 5)
    op, rep = layout(Voronoi(Center(); region = (3:8, 1:2), kinds = [:a]), dom; report = true)
    @test count(!=(0), _op(op, ownership)) == 6 && only(rep).clipped == 6
    # a single Point is a one-generator pattern
    @test Potts.points(Potts.Point(2, 3), (5, 5)) == [Potts.Point(2.0, 3.0)]
end

@testset "layouts: Voronoi repair leaves a piece cut off by the domain" begin
    # the domain splits the lattice into two strips; one generator: its cell is everything,
    # in two pieces with no neighbouring cell, and the repair leaves it so
    dom = Lattice((12, 6); boundary = Closed(), domain = x -> x[1] <= 4 || x[1] >= 8)
    σ = _op(layout(Voronoi([Potts.Point(2.0, 3.0)]; kinds = [:a]), dom), ownership)
    @test count(==(1), σ) == 4 * 6 + 5 * 6
    # two generators, one per strip: one piece each, nothing moves
    σ2 = _op(layout(Voronoi([Potts.Point(2.0, 3.0), Potts.Point(10.0, 3.0)]; kinds = [:a]), dom), ownership)
    @test all(==(1), σ2[1:4, :]) && all(==(2), σ2[8:12, :])
end

@testset "layouts: Voronoi arguments and remake" begin
    @test_throws ArgumentError Voronoi([1, 2]; kinds = [:a])
    @test_throws ArgumentError Voronoi(:nope; kinds = [:a])
    @test_throws ArgumentError Voronoi(Center(); region = Potts.Circle(Potts.Point(1.0, 1.0), -1.0), kinds = [:a])
    @test_throws ArgumentError Voronoi(Center(); region = Potts.Circle(Potts.Point(NaN, 1.0), 1.0), kinds = [:a])
    @test_throws ArgumentError RandomPoints(3; region = (1:0, 1:2), seed = 1)
    @test_throws ArgumentError remake(RandomPoints(3; seed = 1); bogus = 1)
    @test_throws ArgumentError layout(Voronoi(Center(); region = (1:4,), kinds = [:a]), (8, 8))
    @test Potts.points(remake(RandomPoints(3; seed = 1); n = 5), (8, 8)) == Potts.points(RandomPoints(5; seed = 1), (8, 8))
end

@testset "layouts: shape membership is closed up to rounding (site-centred discs)" begin
    hexpos(x) = (x[1] + x[2] / 2, x[2] * sqrt(3) / 2)
    hexl = Lattice((24, 24); geometry = Hexagonal(), boundary = Closed())
    # exact oracle: the axial offset (a, b) has squared Cartesian length a² + ab + b², an integer
    for (r2, n) in ((1, 7), (3, 13), (4, 19), (7, 31)), c in ((12, 12), (9, 14), (15, 10))
        disc = Potts.Circle(Potts.Point(hexpos(c)), sqrt(r2))
        σ = _op(layout(Voronoi([Potts.Point(hexpos(c))]; region = disc, kinds = [:a]), hexl), ownership)
        exact = Set(x for x in CartesianIndices((24, 24)) if (a = x[1] - c[1]; b = x[2] - c[2]; a^2 + a * b + b^2 <= r2))
        @test length(exact) == n
        @test Set(findall(!=(0), σ)) == exact
    end
    # square and 3D: integer distances are exact, so nothing changes (29 and 33 points)
    σs = _op(layout(Voronoi([Potts.Point(10.0, 10.0)]; region = Potts.Circle(Potts.Point(10.0, 10.0), 3.0), kinds = [:a]), (20, 20)), ownership)
    @test count(!=(0), σs) == 29
    σ3 = _op(layout(Voronoi([Potts.Point(5.0, 5.0, 5.0)]; region = Potts.Sphere(Potts.Point(5.0, 5.0, 5.0), 2.0), kinds = [:a]), (9, 9, 9)), ownership)
    @test count(!=(0), σ3) == 33
    # control: the tolerance is relative and tiny, a radius just below the ring excludes it
    disc = Potts.Circle(Potts.Point(hexpos((12, 12))), 1 - 1e-9)
    @test count(!=(0), _op(layout(Voronoi([Potts.Point(hexpos((12, 12)))]; region = disc, kinds = [:a]), hexl), ownership)) == 1
end

@testset "layouts: generator points must be finite" begin
    for bad in (Potts.Point(NaN, 1.0), Potts.Point(Inf, 1.0), Potts.Point(1e300, 1.0))
        @test_throws ArgumentError Voronoi([bad]; kinds = [:a])
        @test_throws ArgumentError Voronoi(bad; kinds = [:a])
        @test_throws ArgumentError Potts.points([bad], (10, 10))
    end
end

# ---------------------------------------------------------------------------------------------
# Eden, Splits, RandomPoints(replace = true), shortfall (P6.3c, D-141); the frozen acceptance
# file holds the hand fixtures, the growth oracle and the spec 01 bands
# ---------------------------------------------------------------------------------------------

using LinearAlgebra: Symmetric, eigen

@testset "layouts: Eden fills its connected component, and only it" begin
    # enough rounds fill every site reachable from the seed: one cell owning the lattice
    σ = _op(layout(Eden(Center(); rounds = 400, kinds = [:a], seed = 1), (15, 15)), ownership)
    @test all(==(1), σ)
    # a domain of two strips (x ≤ 5, x ≥ 9): a seed in the left strip fills it, never the right
    dom = Lattice((14, 6); boundary = Closed(), domain = x -> x[1] <= 5 || x[1] >= 9)
    σ = _op(layout(Eden(Potts.Point(2.0, 3.0); rounds = 400, kinds = [:a], seed = 2), dom), ownership)
    @test all(==(1), σ[1:5, :]) && all(==(0), σ[6:14, :])
    # control: on the full lattice the same seed reaches the right side
    @test all(==(1), _op(layout(Eden(Potts.Point(2.0, 3.0); rounds = 400, kinds = [:a], seed = 2), (14, 6)), ownership))
    # a periodic lattice: the blob crosses the edge from a seed at the corner
    σ = _op(layout(Eden(Potts.Point(1.0, 1.0); rounds = 12, kinds = [:a], seed = 3), Lattice((20, 20))), ownership)
    @test σ[20, 20] == 1 || σ[20, 1] == 1 || σ[1, 20] == 1
end

@testset "layouts: Eden's neighbourhood sets its reach" begin
    # growth moves one neighbourhood step per round: within R of the seed in the graph metric
    # of the growth neighbourhood (L1 for VonNeumann(1), Chebyshev for Moore(1))
    R = 8
    seed_site = (20, 20)
    for s in 1:3
        vn = _op(layout(Eden(Potts.Point(20.0, 20.0); rounds = R, kinds = [:a], seed = s, neighborhood = VonNeumann(1)), (40, 40)), ownership)
        mo = _op(layout(Eden(Potts.Point(20.0, 20.0); rounds = R, kinds = [:a], seed = s), (40, 40)), ownership)
        @test all(x -> sum(abs.(Tuple(x) .- seed_site)) <= R, findall(==(1), vn))
        @test all(x -> maximum(abs.(Tuple(x) .- seed_site)) <= R, findall(==(1), mo))
    end
    # a diagonal domain (x = y): VonNeumann(1) has no step inside it, Moore(1) grows along it
    diag = Lattice((20, 20); boundary = Closed(), domain = x -> x[1] == x[2])
    e = Eden(Potts.Point(10.0, 10.0); rounds = 60, kinds = [:a], seed = 1)
    @test count(==(1), _op(layout(remake(e; neighborhood = VonNeumann(1)), diag), ownership)) == 1
    @test count(==(1), _op(layout(e, diag), ownership)) > 5
    # a model's own neighbourhood is the default: Hex(1) on the hexagonal probe equals the keyword
    sys = HexLayoutProbe(; name = :h)
    e = Eden(RandomPoints(4; seed = 2); rounds = 4, kinds = [:cell], seed = 5)
    @test _same(layout(e, sys), layout(remake(e; neighborhood = Hex(1)), sys))
    @test !_same(layout(e, sys), layout(remake(e; neighborhood = Hex(2)), sys))
end

# An independent recursive oracle for Splits on a 1 × n strip: every cut is across x, at the
# centroid, the daughter taking the sites right of it; daughters follow their mothers.
function _strip_splits(n, k)
    cells = [collect(1:n)]
    for _ in 1:k
        for c in 1:length(cells)
            S = cells[c]
            length(S) >= 2 || continue
            m = sum(S) / length(S)
            push!(cells, filter(>(m), S))
            cells[c] = filter(<=(m), S)
        end
    end
    return cells
end

@testset "layouts: Splits passes on a strip (recursive oracle)" begin
    for (n, k) in ((16, 4), (13, 3), (7, 5), (1, 2))
        op, rep = layout(Splits(Tiling((n, 1); kinds = [:a]), k; shortfall = :allow), (n, 1); report = true)
        σ = _op(op, ownership)
        want = filter(!isempty, _strip_splits(n, k))
        @test [findall(==(c), vec(σ)) for c in 1:maximum(σ)] == want
        @test (only(rep).requested, only(rep).painted) == (2^k, length(want))
    end
    # 2^k sites: every cell ends with one site, no shortfall
    @test isempty(_warnings(() -> layout(Splits(Tiling((16, 1); kinds = [:a]), 4), (16, 1))))
end

# The cut by an independent eigendecomposition: daughter = sites on the positive side of the
# sign-fixed top eigenvector of the Cartesian scatter matrix.
function _eig_cut(S, emb)
    P = [collect(emb(x)) for x in S]
    c = sum(P) / length(P)
    C = sum((p - c) * (p - c)' for p in P)
    v = eigen(Symmetric(C)).vectors[:, end]
    v[findfirst(x -> abs(x) > 1e-9, v)] < 0 && (v = -v)
    return Set(S[i] for i in eachindex(S) if sum((P[i] - c) .* v) > 0)
end

@testset "layouts: Splits cuts across the long axis (eigen oracle, $name)" for (name, target, emb) in (
        ("square", (40, 40), x -> Float64.(x)),
        ("hex", Lattice((40, 40); geometry = Hexagonal(), boundary = Closed()), x -> (x[1] + x[2] / 2, x[2] * sqrt(3) / 2)),
        ("3D", (14, 14, 14), x -> Float64.(x)))
    for s in 1:4
        inner = Eden(Center(); rounds = 5, kinds = [:a], seed = s)
        σ0 = _op(layout(inner, target), ownership)
        S = Tuple.(findall(==(1), σ0))
        σ = _op(layout(Splits(inner, 1; splits = :allow), target), ownership)
        @test Set(Tuple.(findall(==(2), σ))) == _eig_cut(S, emb)
        @test count(==(1), σ) + count(==(2), σ) == length(S)
    end
end

@testset "layouts: Splits delegates one report row" begin
    # an overlay inside Splits paints into the Splits row: 2 boxes, 2 passes → 8 cells
    inner = overlay(Tiling((4, 4); region = (1:4, 1:4), kinds = [:a]), Tiling((4, 4); region = (6:9, 1:4), kinds = [:b]))
    op, rep = layout(overlay(Frame(:w), Splits(inner, 2)), (12, 6); report = true)
    @test [(r.type, r.requested, r.painted, r.misses) for r in rep] == [(:Frame, 1, 1, 0), (:Splits, 8, 8, 0)]
    @test _op(op, kind) == [:w, :a, :b, :a, :b, :a, :b, :a, :b]
    # the inner layer cuts an earlier cell into two pieces: the overlay check (a later layer
    # cut it) counts it in the Splits row and warns; the Splits cells themselves are one piece
    bar = overlay(Tiling((6, 6); kinds = [:t]), Splits(Tiling((2, 6); region = (3:4, 1:6), kinds = [:s]), 1))
    w = _warnings(() -> layout(bar, (6, 6)))
    @test length(w) == 1 && occursin("later layers split cell 1", w[1])
    @test last(layout(bar, (6, 6); report = true))[2].splits == 1
    # shortfall :warn names the layer and both counts
    l = Splits(Tiling((1, 1); kinds = [:a]), 2; shortfall = :warn)
    w = _warnings(() -> layout(l, (1, 1)))
    @test length(w) == 1 && occursin("Splits: shortfall", w[1]) && occursin("4", w[1]) && occursin("1 painted", w[1])
end

@testset "layouts: RandomPoints(replace = true) with Voronoi and Eden" begin
    # coinciding generators: the later one ties every site to the lower one and is dropped
    p = RandomPoints(12; region = (2:4, 2:4), replace = true, seed = 5)
    pts = Potts.points(p, (8, 8))
    @test length(unique(pts)) < 12
    op, rep = layout(Voronoi(p; kinds = [:a]), (8, 8); report = true)
    @test only(rep).painted == 12 && only(rep).dropped == 12 - length(unique(pts))
    # Eden merges them instead: one cell per distinct site (a shortfall it must be told to allow)
    @test_throws ArgumentError layout(Eden(p; rounds = 0, kinds = [:a], seed = 1), (8, 8))
    op, rep = layout(Eden(p; rounds = 0, kinds = [:a], seed = 1, shortfall = :allow), (8, 8); report = true)
    @test only(rep).painted == length(unique(pts)) == maximum(_op(op, ownership))
    @test Set(Tuple.(findall(!=(0), _op(op, ownership)))) == Set(map(x -> Int.(Tuple(x)), pts))
end

# A custom layer painting given site sets, one cell of kind :c each.
struct _SiteSets <: AbstractLayout
    cells::Vector{Vector{NTuple{N, Int}}} where {N}
end
function Potts.paint!(op::Potts.LayoutState, l::_SiteSets, lat)
    for c in l.cells
        id = Potts.new_cell!(op, :c)
        foreach(x -> Potts.assign!(op, x, id), c)
    end
    return nothing
end

# Exact cut oracle (2D, BigFloat at 512 bits): the daughter is the sites with (p − c)·v > 0,
# with exact zeros (|·| < 1e-60 at this precision) on the plane.
function _exact_daughter_2d(S)
    setprecision(BigFloat, 512) do
        P = [BigFloat.(s) for s in S]
        n = length(P)
        c = (sum(p[1] for p in P) / n, sum(p[2] for p in P) / n)
        a = sum((p[1] - c[1])^2 for p in P); d = sum((p[2] - c[2])^2 for p in P)
        b = sum((p[1] - c[1]) * (p[2] - c[2]) for p in P)
        λ = (a + d) / 2 + sqrt(((a - d) / 2)^2 + b^2)
        v = abs(b) > 1e-60 ? [λ - d, b] : (a >= d ? [big(1.0), big(0.0)] : [big(0.0), big(1.0)])
        v ./= sqrt(sum(abs2, v))
        v[findfirst(x -> abs(x) > 1e-9, v)] < 0 && (v .*= -1)
        Set(S[i] for i in eachindex(S) if (P[i][1] - c[1]) * v[1] + (P[i][2] - c[2]) * v[2] > 1e-60)
    end
end

@testset "layouts: Splits keeps sites on the plane with the mother (exact oracle)" begin
    # the review's reproducer: (4, 4) lies exactly on the plane, the inexact centroid
    # (23/5, 19/5) and axis would put it at ±1e-16
    S = [(4, 3), (5, 3), (4, 4), (5, 4), (5, 5)]
    @test _exact_daughter_2d(S) == Set([(5, 4), (5, 5)])
    σ = _op(layout(Splits(_SiteSets([S]), 1), (8, 8)), ownership)
    @test Set(Tuple.(findall(==(2), σ))) == _exact_daughter_2d(S) && σ[4, 4] == 1
    # random small cells (a random walk on 9×9; the cells with an exact on-plane site matter)
    rng = Test.Random.Xoshiro(11)
    onplane = 0
    for _ in 1:3000
        x = (5, 5); cell = Set([x])
        for _ in 1:rand(rng, 1:12)
            x = (clamp(x[1] + rand(rng, -1:1), 1, 9), clamp(x[2] + rand(rng, -1:1), 1, 9)); push!(cell, x)
        end
        length(cell) >= 2 || continue
        Sv = sort!(collect(cell); by = s -> (s[2], s[1]))
        want = _exact_daughter_2d(Sv)
        σ = _op(layout(Splits(_SiteSets([Sv]), 1; splits = :allow), (9, 9)), ownership)
        @test Set(Tuple.(findall(==(2), σ))) == want
    end
    # 3D: three layers z = 1:3 of the same L tromino (x, y centroid 4/3, inexact); exactly,
    # C is diagonal with the largest variance along z (6 against 2), so the plane is z = 2:
    # mother z ≤ 2, daughter z = 3
    L = [(1, 1), (2, 1), (1, 2)]
    S3 = [(x, y, z) for z in 1:3 for (x, y) in L]
    σ = _op(layout(Splits(_SiteSets([S3]), 1), (3, 3, 3)), ownership)
    @test Set(Tuple.(findall(==(2), σ))) == Set(s for s in S3 if s[3] == 3)
end

@testset "layouts: Splits names the cell by its id in the result" begin
    # the review's reproducer: on a periodic 10 × 3 lattice the cell spans more than half of x,
    # so it is unwrapped about (9, 1) and torn; an earlier one-site cell is painted over and
    # dropped, so the Splits cells (paint ids 2, 3) are 1, 2 in the result
    cell = [(9, 1); [(x, 2) for x in 2:9]]
    l = overlay(_SiteSets([[(5, 3)]]), Splits(_SiteSets([cell]), 1), _SiteSets([[(5, 3)]]))
    per = Lattice((10, 3))
    # Unwrapped, x = 2:4 sit at 12:14: the daughter is x ≥ 9 of the unwrapped cell, i.e.
    # (9, 1), (9, 2), (2, 2), (3, 2): two pieces, x = 9 and x = 2:3 (x = 10 and 1 between them
    # are not the cell's). Result id 2 (paint id 3).
    σ = _op(layout(l, per), ownership)
    @test Set(Tuple.(findall(==(2), σ))) == Set([(9, 1), (9, 2), (2, 2), (3, 2)])
    w = _warnings(() -> layout(l, per))
    @test length(w) == 1 && occursin("cell 2 ", w[1])
    # on a closed lattice the same cell is cut into two one-piece halves: no warning
    @test isempty(_warnings(() -> layout(l, (10, 3))))
    # a cell that is not one piece: two sites far apart, k = 0 (Splits cut nothing)
    two = _SiteSets([[(1, 1), (6, 1)]])
    l = overlay(_SiteSets([[(3, 3)]]), Splits(two, 0), _SiteSets([[(3, 3)]]))
    w = _warnings(() -> layout(l, (8, 3)))
    σ = _op(layout(l, (8, 3)), ownership)
    @test length(w) == 1 && occursin("cell $(σ[1, 1]) ", w[1]) && occursin("Splits", w[1])
    @test σ[1, 1] == 1                           # renumbered: paint id 2 is result id 1
    @test occursin("is not one piece", w[1]) && !occursin("divisions", w[1])
    _, rep = layout(l, (8, 3); report = true)
    @test rep[2].splits == 1
    # nested Splits share one row and count a cell in pieces once
    _, rep = layout(Splits(Splits(two, 0; splits = :allow), 0; splits = :allow), (8, 3); report = true)
    @test only(rep).splits == 1
    # the outer setting decides: an inner :warn under an outer :allow is silent
    @test isempty(_warnings(() -> layout(Splits(Splits(two, 0), 0; splits = :allow), (8, 3))))
    # a cell dropped by a later layer is counted but not warned about
    l = overlay(Splits(two, 0), Tiling((8, 1); region = (1:8, 1:1), kinds = [:t]))
    @test isempty(_warnings(() -> layout(l, (8, 3))))
    @test last(layout(l, (8, 3); report = true))[1].splits == 1
end

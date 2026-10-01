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
    mask = sys.lattice.domain
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

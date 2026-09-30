# Layouts (P6.1a): spec-level properties with independent checks (D-048).
using PottsModels: akeeb_state

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
    @test_throws ArgumentError layout(Frame(:w), lat)
    # the same domain from a model's @lattice (LatticeSpec path)
    dsys = DomainLayoutProbe(; name = :d)
    @test _op(layout(Tiling((2, 2); region = (1:5, 1:10), kinds = [:cell]), dsys), ownership)[6:end, :] == zeros(Int32, 5, 10)
    @test_throws r"outside the lattice domain" layout(Tiling((2, 2); kinds = [:cell]), dsys)
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

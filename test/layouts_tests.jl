# Layouts: spec-level properties with independent checks (D-048).

@testitem "layouts: Tiling" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
    using Potts.Layouts
    @testset "layouts: Tiling" begin
        # counts, volumes and bounds, checked against the arithmetic of whole boxes
        for (sz, sp, reg, dims) in (
                ((3, 2), (1, 0), (2:19, 4:11), (20, 12)), (
                    (4, 4), (2, 2), (1:17, 1:17), (17, 17),
                ),
                ((2, 3, 2), (1, 1, 0), (1:9, 2:10, 1:6), (10, 10, 6)),
            )
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
        # 1D, integer size
        @test layout(Tiling(3; kinds = [:a]), (7,))[1][2] == Int32[1, 1, 1, 2, 2, 2, 0]
    end
end

@testitem "layouts: invalid arguments" setup = [LayoutsSetup] tags = [
    :potts,
    :layouts,
] begin
    using Potts.Layouts
    @testset "layouts: invalid arguments" begin
        function err(f)
            return try
                f()
                ""
            catch e
                e isa ArgumentError ? e.msg : rethrow()
            end
        end
        @test_throws ArgumentError layout(
            Tiling((2, 2); region = (1:5, 1:11), kinds = [:a]), (
                10, 10,
            )
        )
        @test_throws ArgumentError layout(
            Tiling((2, 2); region = (0:5, 1:5), kinds = [:a]), (
                10, 10,
            )
        )
        @test_throws ArgumentError layout(Tiling((2, 2); kinds = [:a]), (10, 10, 10))
        @test_throws ArgumentError Tiling((2, 2); region = (1:5, 1:5, 1:5), kinds = [:a])
        @test_throws ArgumentError Tiling((2, 2); region = (1:5, 5:4), kinds = [:a])
        @test_throws ArgumentError Tiling((2, 2); region = (1:2:9, 1:5), kinds = [:a])
        @test_throws ArgumentError Tiling((2, 0); kinds = [:a])
        @test_throws ArgumentError Tiling((2, 2); spacing = -1, kinds = [:a])
        @test_throws ArgumentError Tiling((2, 2); kinds = Symbol[])
        @test_throws ArgumentError layout(
            Tiling((6, 2); region = (1:5, 1:5), kinds = [:a]), (
                10, 10,
            )
        )
        @test_throws ArgumentError Frame(:w; width = 0)
        @test_throws ArgumentError Scattered(2, (2, 2); kinds = [:a], seed = 1, gap = -1)
        @test_throws ArgumentError layout(
            Scattered(1, (6, 6); kinds = [:a], seed = 1), (
                5, 20,
            )
        )
        @test_throws ArgumentError layout(Frame(:w), (0, 4))
        # not a size, a lattice or a model
        @test_throws ArgumentError layout(Frame(:w), "10×10")
        # negative control: a valid call raises nothing
        @test err(
            () -> layout(
                Tiling((2, 2); region = (1:10, 1:10), kinds = [:a]), (
                    10, 10,
                )
            )
        ) == ""
    end
end

@testitem "layouts: Frame and overlay precedence" setup = [LayoutsSetup] tags = [
    :potts, :layouts,
] begin
    using Potts.Layouts
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
        # negative control: the frame under the tiles keeps nothing (tiles cover the
        # lattice)
        op = layout(overlay(Frame(:w), tiles), (6, 6))
        @test _op(op, kind) == fill(:a, 9) &&
            [length(_sites(_op(op, ownership), c)) for c in 1:9] == fill(4, 9)
        # a fully covered cell is dropped and ids stay consecutive
        op = layout(
            overlay(
                Tiling((1, 1); region = (1:1, 1:1), kinds = [:x]), Tiling(
                    (1, 1); region = (3:3, 3:3), kinds = [:y]
                ),
                Frame(:w)
            ), (5, 5)
        )
        @test _op(op, kind) == [:y, :w] &&
            sort(unique(_op(op, ownership))) == Int32[0, 1, 2]
        # a later layer that cuts a cell in two warns, naming the cell (Moore(1)
        # neighbourhood)
        bar = Tiling((6, 2); region = (1:6, 3:4), kinds = [:a])
        cutter = Tiling((2, 2); region = (3:4, 3:4), kinds = [:b])
        @test_logs (:warn, r"split cell 1 \(kind a\)") layout(overlay(bar, cutter), (6, 6))
        # negative control: trimming its end leaves it connected, no warning
        @test_logs min_level = Base.CoreLogging.Warn layout(
            overlay(bar, Tiling((2, 2); region = (5:6, 3:4), kinds = [:b])), (6, 6)
        )
        # overlay is associative (nested overlays flatten)
        a, b = Frame(:w), Tiling((3, 3); spacing = 1, region = (2:19, 2:19), kinds = [:a])
        c = Scattered(3, (2, 2); region = (2:19, 2:19), kinds = [:s], seed = 4)
        ref = layout(overlay(a, b, c), (20, 20))
        @test _same(layout(overlay(overlay(a, b), c), (20, 20)), ref) &&
            _same(layout(overlay(a, overlay(b, c)), (20, 20)), ref)
        # negative control: order matters
        @test !_same(layout(overlay(c, b, a), (20, 20)), ref)
    end
end

@testitem "layouts: Scattered" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
    using Potts.Layouts
    @testset "layouts: Scattered" begin
        # 3D, gap 2: every pair of cells is more than two sites apart, volumes by counting
        for seed in 1:3
            σ = _op(
                layout(
                    Scattered(
                        8, (3, 3, 3); region = (2:19, 2:19, 2:19),
                        kinds = [:a, :b], seed, gap = 2
                    ),
                    (20, 20, 20)
                ),
                ownership
            )
            @test maximum(σ) == 8 && all(c -> length(_sites(σ, c)) == 27, 1:8)
            @test all(i -> all(d -> 2 <= i[d] <= 19, 1:3), findall(>(0), σ))
            @test _separated(σ, 2)
        end
        # negative control: the separation check catches two touching boxes
        σ = zeros(Int32, 10, 10)
        σ[1:2, 1:2] .= 1
        σ[4:5, 4:5] .= 2
        @test _separated(σ, 1) && !_separated(σ, 2)
        # gap 0 allows touching boxes but never overlap: a denser packing keeps full volumes
        σ = _op(
            layout(Scattered(8, (2, 2); kinds = [:a], seed = 3, gap = 0), (8, 8)),
            ownership
        )
        @test maximum(σ) == 8 && all(c -> length(_sites(σ, c)) == 4, 1:8)
        # deterministic in the seed (StableRNG): the same seed gives the same corners,
        # another differs
        function corners(seed)
            σ = _op(layout(Scattered(3, (2, 2); kinds = [:a], seed), (30, 30)), ownership)
            return [Tuple(minimum(_sites(σ, c))) for c in 1:3]
        end
        @test corners(7) == corners(7)
        @test corners(7) != corners(8)
        ly_throws(
            ArgumentError, ["cannot fit the region", "reduce `n`"],
            () -> layout(Scattered(26, (4, 4); kinds = [:a], seed = 1), (24, 24))
        )   # area bound
        # within the area bound (300·25 ≤ 101²) but random sequential placement jams
        @test_throws ArgumentError layout(
            Scattered(300, (4, 4); kinds = [:a], seed = 1), (
                100, 100,
            )
        )
        # seeds are UInt64: seeds above typemax(Int) work and differ; negative seeds are
        # rejected
        big = layout(Scattered(3, (2, 2); kinds = [:a], seed = typemax(UInt64)), (30, 30))
        @test maximum(_op(big, ownership)) == 3 &&
            _op(big, ownership) !=
            _op(layout(Scattered(3, (2, 2); kinds = [:a], seed = 0), (30, 30)), ownership)
        ly_throws(
            ArgumentError, ["seed must be in 0:typemax(UInt64)"],
            () -> Scattered(3, (2, 2); kinds = [:a], seed = -1)
        )
    end
end

@testitem "layouts: wrap-aware area bound" setup = [LayoutsSetup] tags = [
    :potts,
    :layouts,
] begin
    using Potts.Layouts
    @testset "layouts: wrap-aware area bound" begin
        # 10 boxes of 3×3 with gap 1 need 160 sites of room: a 12×12 torus has 144
        @test_throws ArgumentError layout(
            Scattered(10, (3, 3); kinds = [:cell], seed = 1),
            PeriodicLayoutProbe(; name = :p)
        )
        # control: closed 12×12 has 13² = 169 of room, so the bound passes and placement
        # jams
        @test_throws ArgumentError layout(
            Scattered(10, (3, 3); kinds = [:cell], seed = 1), (
                12, 12,
            )
        )
        # the grown box side is clamped to the ring too: one 3×3 box with gap 10 always fits
        # a 12×12 torus (it was rejected as 13² > 12²)
        one = layout(
            Scattered(1, (3, 3); kinds = [:cell], seed = 1, gap = 10),
            PeriodicLayoutProbe(; name = :p)
        )
        @test count(==(1), _op(one, ownership)) == 9 && maximum(_op(one, ownership)) == 1
        # control: two such boxes are infeasible (each needs the whole ring on some axis)
        ly_throws(
            ArgumentError, ["cannot fit the region", "reduce `n`"],
            () -> layout(
                Scattered(2, (3, 3); kinds = [:cell], seed = 1, gap = 10),
                PeriodicLayoutProbe(; name = :p)
            )
        )
    end
end

@testitem "layouts: periodic lattices" setup = [LayoutsSetup] tags = [
    :potts,
    :layouts,
] begin
    using Potts.Layouts
    @testset "layouts: periodic lattices" begin
        sys = PeriodicLayoutProbe(; name = :p)
        per = (true, true)
        sc(seed) = layout(Scattered(4, (3, 3); kinds = [:cell], seed), sys)
        # the gap holds through the wrap on a periodic system
        @test !any(seed -> _touching(_op(sc(seed), ownership), per), 1:100)
        @test all(seed -> all(c -> count(==(c), _op(sc(seed), ownership)) == 9, 1:4), 1:100)
        # negative control: the same layers laid on a closed 12×12 lattice touch through the
        # wrap for some seeds (the gap is only enforced inside the lattice there)
        @test any(
            seed -> _touching(
                _op(
                    layout(Scattered(4, (3, 3); kinds = [:cell], seed), (12, 12)),
                    ownership
                ),
                per
            ),
            1:100
        )
        # Tiling: on a periodic axis the last box closer than `spacing` to the first is
        # skipped
        t = Tiling((3, 3); spacing = 1, kinds = [:cell])
        # 12 = 3·4: all fit
        @test maximum(_op(layout(t, PeriodicLayoutProbe(; name = :q)), ownership)) == 9
        # 11×11, x periodic
        ch = ChannelLayoutProbe(; name = :c)
        σ = _op(layout(t, ch), ownership)
        @test maximum(σ) == 2 * 3 && !_touching(σ, (true, false))
        # control: closed keeps 3×3
        @test maximum(_op(layout(t, (11, 11)), ownership)) == 9
        @test _touching(_op(layout(t, (11, 11)), ownership), (true, false))
        # Frame: walls only across the closed axis (a channel); no edge when all axes wrap
        σ = _op(layout(Frame(:wall), ch), ownership)
        @test findall(==(1), σ) == findall(i -> i[2] in (1, 11), CartesianIndices(σ))
        ly_throws(
            ArgumentError, ["the lattice has no boundary", "use `Closed()`"],
            () -> layout(Frame(:wall), sys)
        )
    end
end

@testitem "layouts: lattices, systems and problems" setup = [LayoutsSetup] tags = [
    :potts, :layouts,
] begin
    using Potts.Layouts
    @testset "layouts: lattices, systems and problems" begin
        # hexagonal lattice: indices are axial, dims come from the lattice
        sys = HexLayoutProbe(; name = :h)
        l = overlay(
            Frame(:wall),
            Tiling((3, 3); spacing = 1, region = (3:16, 3:12), kinds = [:cell])
        )
        op = layout(l, sys)
        σ = _op(op, ownership)
        @test size(σ) == (18, 14) && maximum(σ) == 1 + 3 * 2
        @test _same(layout(l, mtkcompile(sys)), op) && _same(layout(l, (18, 14)), op) &&
            _same(
            layout(l, Lattice((18, 14); boundary = Closed(), geometry = Hexagonal())),
            op
        )
        prob = PottsProblem(sys, op, (0, 5))
        @test prob.lattice.geometry isa Hexagonal
        u = solve(prob, SequentialCPM(proposal = Hex(1))).u[end]
        # the frozen frame stays
        @test Array(u.ownership)[σ .== 1] == σ[σ .== 1]
        @test u.cell.volume == [count(==(c), u.ownership) for c in 1:maximum(σ)]
        # a lattice domain: cells must lie inside it
        lat = Lattice((10, 10); domain = OnIndices(x -> x[1] <= 5))
        @test _op(
            layout(Tiling((2, 2); region = (1:5, 1:10), kinds = [:a]), lat),
            ownership
        )[6:end, :] ==
            zeros(Int32, 5, 10)
        @test _op(layout(Frame(:w), lat), ownership) ==
            _frame_oracle(lat.mask, (true, true), 1)   # periodic
        # the same domain from a model's @lattice (LatticeSpec path)
        dsys = DomainLayoutProbe(; name = :d)
        @test _op(
            layout(Tiling((2, 2); region = (1:5, 1:10), kinds = [:cell]), dsys),
            ownership
        )[6:end, :] ==
            zeros(Int32, 5, 10)
        ly_throws(
            ArgumentError, ["outside the lattice domain", "in-domain sites"],
            () -> layout(Tiling((2, 2); kinds = [:cell]), dsys)
        )
    end
end

@testitem "layouts: Frame on a lattice domain" setup = [LayoutsSetup] tags = [
    :potts,
    :layouts,
] begin
    using Potts.Layouts
    @testset "layouts: Frame on a lattice domain" begin
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
            @test !any(
                i -> inner[i] && any(
                    o -> (j = i + o; !checkbounds(Bool, mask, j) || !mask[j]),
                    CartesianIndices(((-w):w, (-w):w))
                ), CartesianIndices(mask)
            )
            # the ring is w sites thick along the axes through the centre (row 12 of the
            # disk: 2:23)
            row = findall(mask[:, 12])
            @test findall(ring[:, 12]) == [row[1:w]; row[(end - w + 1):end]]
        end
        # negative controls: the oracle distinguishes widths, and the unmasked rule on the
        # same dims lies entirely outside the disk (the old behaviour, which the domain
        # check rejects)
        @test _frame_oracle(mask, (false, false), 1) !=
            _frame_oracle(mask, (false, false), 2)
        @test !any(mask .& (_op(layout(Frame(:wall), (24, 24)), ownership) .== 1))
        # a domain that meets closed lattice edges and a periodic wrap
        half = OnIndices(x -> x[1] <= 6)
        σ = _op(
            layout(
                Frame(:w),
                Lattice((12, 12); boundary = (Periodic(), Closed()), domain = half)
            ),
            ownership
        )
        @test findall(==(1), σ) ==
            findall(
            i -> i[1] <= 6 && (i[1] in (1, 6) || i[2] in (1, 12)),
            CartesianIndices(σ)
        )
        σ = _op(
            layout(Frame(:w), Lattice((12, 12); boundary = Periodic(), domain = half)),
            ownership
        )
        # x = 1 meets 12 by wrap
        @test findall(==(1), σ) == findall(i -> i[1] in (1, 6), CartesianIndices(σ))
        ly_throws(
            ArgumentError, ["the lattice has no boundary", "Closed()"],
            () -> layout(
                Frame(:w),
                Lattice((6, 6); boundary = Periodic(), domain = trues(6, 6))
            )
        )
        # hex (axial indices): a concave domain (a disk minus a wedge) gets the oracle ring,
        # and no in-domain site off the ring has a Hex(1) neighbour outside the domain (it
        # seals)
        function domain_frame(mask, bnd, w; geometry = Potts.CorePotts.Square())
            return _op(
                layout(
                    Frame(:w; width = w),
                    Potts.lattice_spec(size(mask); boundary = bnd, domain = mask, geometry)
                ),
                ownership
            ) .== 1
        end
        pacman = [
            (x - 9)^2 + (y - 9)^2 <= 49 && !(x > 9 && abs(y - 9) <= 2)
                for x in 1:18, y in 1:18
        ]
        hexlat = Lattice((18, 18); boundary = Closed(), geometry = Hexagonal())
        hoffs = Potts.CorePotts.relation(Hex(1), hexlat).offsets
        for w in 1:3
            ring = domain_frame(pacman, Closed(), w; geometry = Hexagonal())
            @test ring == _frame_oracle(pacman, (false, false), w)
            inner = pacman .& .!ring
            @test any(inner)
            @test all(
                i -> !inner[i] || all(
                    o -> (
                        (in, y) = Potts.CorePotts.shift(hexlat, Tuple(i), o);
                        in && pacman[y...]
                    ),
                    hoffs
                ),
                CartesianIndices(pacman)
            )
        end
        # 3D with mixed boundaries: random masks against the oracle
        rng = Potts.StableRNG(3)
        for _ in 1:40
            per = (rand(rng, Bool), rand(rng, Bool), rand(rng, Bool))
            m3 = rand(rng, rand(rng, 3:8), rand(rng, 3:8), rand(rng, 3:8)) .>
                rand(rng, (0.05, 0.2, 0.5))
            (any(m3) && !(all(m3) && all(per))) || continue
            w = rand(rng, 1:3)
            @test domain_frame(m3, map(p -> p ? Periodic() : Closed(), per), w) ==
                _frame_oracle(m3, per, w)
        end
        # a frozen frame on the disk: the model runs and the frame stays put
        l = overlay(
            Frame(:wall),
            Tiling((3, 3); spacing = 1, region = (6:19, 6:19), kinds = [:cell])
        )
        op = layout(l, sys)
        σ0 = _op(op, ownership)
        @test maximum(σ0) == 1 + 9
        for alg in (
                SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(;
                    proposal = Moore(1)
                ),
            )
            u = solve(PottsProblem(sys, op, (0, 20)), alg).u[end]
            σ = Array(u.ownership)
            # the frame stays
            @test (σ .== 1) == (σ0 .== 1)
            # cells move, never leave the disk
            @test σ != σ0 && all(σ[.!mask] .== 0)
            @test u.cell.volume[1:maximum(σ0)] == [count(==(c), σ) for c in 1:maximum(σ0)]
        end
        # negative control: the same frame with a mobile wall kind moves
        u = solve(
            PottsProblem(DiskMobileWallProbe(; name = :mob), op, (0, 20)),
            SequentialCPM(; proposal = Moore(1))
        ).u[end]
        @test (Array(u.ownership) .== 1) != (σ0 .== 1)
    end
end

@testitem "layouts: extension API and split warnings" setup = [LayoutsSetup] tags = [
    :potts, :layouts, :timing,
] begin
    using Potts.Layouts
    @testset "layouts: extension API and split warnings" begin
        @test all(((m, n),) -> Base.ispublic(m, n), ScratchLayouts.QUALIFIED)
        # control: internals are not
        @test !Base.ispublic(Potts, :_disconnected)
        S = ScratchLayouts.Sites
        op = layout(overlay(Frame(:w), S([(3, 3), (4, 4)], :a)), (6, 6))
        @test _op(op, kind) == [:w, :a] &&
            findall(==(2), _op(op, ownership)) == CartesianIndex.([(3, 3), (4, 4)])
        # hex: the axial diagonal (1, 1) is not a hex neighbour, the anti-diagonal (1, -1)
        # is
        box = Tiling((2, 2); region = (1:2, 1:2), kinds = [:a])
        hexlat = Lattice((6, 6); boundary = Closed(), geometry = Hexagonal())
        @test length(
            _warnings(() -> layout(overlay(box, S([(1, 2), (2, 1)], :b)), hexlat))
        ) ==
            1
        @test isempty(
            _warnings(() -> layout(overlay(box, S([(1, 1), (2, 2)], :b)), hexlat))
        )
        @test isempty(
            _warnings(
                () -> layout(
                    overlay(box, S([(1, 2), (2, 1)], :b)), (
                        6, 6,
                    )
                )
            )
        )   # square Moore(1): joined
        # a bar across a periodic axis stays connected through the wrap when cut once
        bar = Tiling((12, 1); region = (1:12, 2:2), kinds = [:a])
        mid = Tiling((1, 1); region = (5:5, 2:2), kinds = [:b])
        @test isempty(
            _warnings(
                () -> layout(
                    overlay(bar, mid), PeriodicLayoutProbe(;
                        name = :p
                    )
                )
            )
        )
        # control: closed splits
        @test length(_warnings(() -> layout(overlay(bar, mid), (12, 12)))) == 1
        # cost: one pass over σ, boxes trimmed by a frame are skipped (was 22 s at 200³)
        layout(overlay(Tiling((5, 5, 5); kinds = [:a]), Frame(:w; width = 3)), (12, 12, 12))
        # the best of up to 3 timed calls: a busy machine slows one call, the regression
        # slows all
        function best_under(f, limit)
            t = Inf
            for _ in 1:3
                t = min(t, @elapsed f())
                t < limit && break
            end
            return t
        end
        t = best_under(
            () -> layout(
                overlay(Tiling((5, 5, 5); kinds = [:a]), Frame(:w; width = 3)), (
                    60, 60, 60,
                )
            ),
            5
        )
        @test t < 5
        # many genuinely split cells still flood-fill in linear time (warmed on a small 2D
        # call)
        _warnings(
            () -> layout(
                overlay(
                    Tiling((3, 3); kinds = [:a]),
                    Tiling((1, 1); spacing = 2, region = (2:11, 2:11), kinds = [:b])
                ),
                (12, 12)
            )
        )
        t = best_under(
            () -> layout(
                overlay(
                    Tiling((3, 3); kinds = [:a]), Tiling(
                        (1, 1); spacing = 2, region = (2:299, 2:299),
                        kinds = [:b]
                    )
                ), (300, 300)
            ), 5
        )
        @test t < 5
        # The lattice-sized `visited` array is allocated only for a flood fill. Every
        # cut cell below is a box trimmed by a frame, so the check allocates only per-cell
        # buffers (4096 cells), far below the 80³ Int32 array (2 MB).
        lat = Potts.lattice_spec((80, 80, 80); boundary = Closed())
        σ = _op(
            layout(overlay(Tiling((5, 5, 5); kinds = [:a]), Frame(:w; width = 3)), lat),
            ownership
        )
        check = [trues(maximum(σ) - 1); false]       # every tile, not the frame
        split = Int[]
        Potts._disconnected(c -> push!(split, c), σ, check, lat)
        bytes = @allocated Potts._disconnected(c -> push!(split, c), σ, check, lat)
        @test isempty(split) && bytes < sizeof(Int32) * 80^3 ÷ 4
        # … and a genuinely split cell among them is found (and allocates the array)
        σ2 = copy(σ)
        c = σ2[6, 6, 6]
        # a medium slab through tile `c` = (6:10)³
        σ2[6:10, 6:10, 8] .= 0
        Potts._disconnected(c -> push!(split, c), σ2, check, lat)
        @test split == [c]
        @test (@allocated Potts._disconnected(c -> nothing, σ2, check, lat)) >=
            sizeof(Int32) * 80^3
    end
end

@testitem "layouts reproduce an existing state's geometry" setup = [LayoutsSetup] tags = [
    :potts, :layouts,
] begin
    using Potts.Layouts
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
        # medium and follower sites
        followers = σr .<= nf
        @test σ[followers] == σr[followers]
        # every leader sits on a tile
        @test all(σ[.!followers] .> 0)
        # negative control: a tiling one row shorter differs
        @test _op(
            layout(
                Tiling((3, 3); region = (1:X, 1:(slab - 3)), kinds = [:follower]), (
                    X, Y,
                )
            ),
            ownership
        ) != σ
    end
end

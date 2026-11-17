# Layouts (P6.3c, D-141): Eden, RandomPoints(replace = true), shortfall and Splits.

@testitem "layouts: Eden fills its connected component, and only it" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
    using Potts.Layouts
    @testset "layouts: Eden fills its connected component, and only it" begin
        # enough rounds fill every site reachable from the seed: one cell owning the lattice
        σ = _op(layout(Eden(Center(); rounds = 400, kinds = [:a], seed = 1), (15, 15)), ownership)
        @test all(==(1), σ)
        # a domain of two strips (x ≤ 5, x ≥ 9): a seed in the left strip fills it, never the right
        dom = Lattice((14, 6); boundary = Closed(), domain = x -> x[1] <= 5 || x[1] >= 9)
        σ = _op(layout(Eden(Point(2.0, 3.0); rounds = 400, kinds = [:a], seed = 2), dom), ownership)
        @test all(==(1), σ[1:5, :]) && all(==(0), σ[6:14, :])
        # control: on the full lattice the same seed reaches the right side
        @test all(==(1), _op(layout(Eden(Point(2.0, 3.0); rounds = 400, kinds = [:a], seed = 2), (14, 6)), ownership))
        # a periodic lattice: the blob crosses the edge from a seed at the corner
        σ = _op(layout(Eden(Point(1.0, 1.0); rounds = 12, kinds = [:a], seed = 3), Lattice((20, 20))), ownership)
        @test σ[20, 20] == 1 || σ[20, 1] == 1 || σ[1, 20] == 1
    end
end

@testitem "layouts: Eden's neighbourhood sets its reach" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
    using Potts.Layouts
    @testset "layouts: Eden's neighbourhood sets its reach" begin
        # growth moves one neighbourhood step per round: within R of the seed in the graph metric
        # of the growth neighbourhood (L1 for VonNeumann(1), Chebyshev for Moore(1))
        R = 8
        seed_site = (20, 20)
        for s in 1:3
            vn = _op(layout(Eden(Point(20.0, 20.0); rounds = R, kinds = [:a], seed = s, neighborhood = VonNeumann(1)), (40, 40)), ownership)
            mo = _op(layout(Eden(Point(20.0, 20.0); rounds = R, kinds = [:a], seed = s), (40, 40)), ownership)
            @test all(x -> sum(abs.(Tuple(x) .- seed_site)) <= R, findall(==(1), vn))
            @test all(x -> maximum(abs.(Tuple(x) .- seed_site)) <= R, findall(==(1), mo))
        end
        # a diagonal domain (x = y): VonNeumann(1) has no step inside it, Moore(1) grows along it
        diag = Lattice((20, 20); boundary = Closed(), domain = x -> x[1] == x[2])
        e = Eden(Point(10.0, 10.0); rounds = 60, kinds = [:a], seed = 1)
        @test count(==(1), _op(layout(remake(e; neighborhood = VonNeumann(1)), diag), ownership)) == 1
        @test count(==(1), _op(layout(e, diag), ownership)) > 5
        # a model's own neighbourhood is the default: Hex(1) on the hexagonal probe equals the keyword
        sys = HexLayoutProbe(; name = :h)
        e = Eden(RandomPoints(4; seed = 2); rounds = 4, kinds = [:cell], seed = 5)
        @test _same(layout(e, sys), layout(remake(e; neighborhood = Hex(1)), sys))
        @test !_same(layout(e, sys), layout(remake(e; neighborhood = Hex(2)), sys))
    end
end

@testitem "layouts: Splits passes on a strip (recursive oracle)" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
    using Potts.Layouts
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
end

@testitem "layouts: Splits cuts across the long axis (eigen oracle, name)" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
    using Potts.Layouts
    @testset "layouts: Splits cuts across the long axis (eigen oracle, $name)" for (name, target, emb) in (
            ("square", (40, 40), x -> Float64.(x)),
            ("hex", Lattice((40, 40); geometry = Hexagonal(), boundary = Closed()), x -> (x[1] + x[2] / 2, x[2] * sqrt(3) / 2)),
            ("3D", (14, 14, 14), x -> Float64.(x)),
        )
        for s in 1:4
            inner = Eden(Center(); rounds = 5, kinds = [:a], seed = s)
            σ0 = _op(layout(inner, target), ownership)
            S = Tuple.(findall(==(1), σ0))
            σ = _op(layout(Splits(inner, 1; splits = :allow), target), ownership)
            @test Set(Tuple.(findall(==(2), σ))) == _eig_cut(S, emb)
            @test count(==(1), σ) + count(==(2), σ) == length(S)
        end
    end
end

@testitem "layouts: Splits delegates one report row" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
    using Potts.Layouts
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
end

@testitem "layouts: RandomPoints(replace = true) with Voronoi and Eden" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
    using Potts.Layouts
    @testset "layouts: RandomPoints(replace = true) with Voronoi and Eden" begin
        # coinciding generators: the later one ties every site to the lower one and is dropped
        p = RandomPoints(12; region = (2:4, 2:4), replace = true, seed = 5)
        pts = Potts.points(p, (8, 8))
        @test length(unique(pts)) < 12
        op, rep = layout(Voronoi(p; kinds = [:a]), (8, 8); report = true)
        @test only(rep).painted == 12 && only(rep).dropped == 12 - length(unique(pts))
        # Eden merges them instead: one cell per distinct site (a shortfall it must be told to allow)
        ly_throws(
            ArgumentError, ["Eden: shortfall", "pass `shortfall = :allow`"],
            () -> layout(Eden(p; rounds = 0, kinds = [:a], seed = 1), (8, 8))
        )
        op, rep = layout(Eden(p; rounds = 0, kinds = [:a], seed = 1, shortfall = :allow), (8, 8); report = true)
        @test only(rep).painted == length(unique(pts)) == maximum(_op(op, ownership))
        @test Set(Tuple.(findall(!=(0), _op(op, ownership)))) == Set(map(x -> Int.(Tuple(x)), pts))
    end
end

@testitem "layouts: Splits keeps sites on the plane with the mother (exact oracle)" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
    using Potts.Layouts
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
end

@testitem "layouts: Splits names the cell by its id in the result" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
    using Potts.Layouts
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
end

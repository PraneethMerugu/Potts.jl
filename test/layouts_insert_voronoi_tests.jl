# Layouts (P6.1a5, P6.2a, D-138): InsertUntil, layer_rng, point patterns and Voronoi.

@testitem "layouts: InsertUntil stop rules (hand-derived counts)" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
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
        ly_throws(
            ArgumentError, ["ran out of sites", "reduce `fraction`/`number`"],
            () -> layout(overlay(hosts, InsertUntil(:guest; into = [:host], number = 17, seed = 1)), (20, 20))
        )
        @test length(
            _kind_sites(
                layout(overlay(hosts, InsertUntil(:guest; into = [:host], number = 16, seed = 1)), (20, 20)),
                :guest
            )
        ) == 16
        # inserted cells are never drawn again as hits, even when their kind is allowed
        op, t = _tally(overlay(hosts, InsertUntil(:host; into = [:host], number = 16, seed = 2)), (20, 20))
        @test only(t).painted == 16 && count(==(:host), _op(op, kind)) == 16     # every host replaced once
        ly_throws(
            ArgumentError, ["ran out of sites", "reduce `fraction`/`number`"],
            () -> layout(overlay(hosts, InsertUntil(:host; into = [:host], number = 17, seed = 2)), (20, 20))
        )
        # no InsertUntil layer: no InsertUntil row; the point equals `layout`
        op, t = _tally(hosts, (20, 20))
        @test isempty(t) && _same(op, layout(hosts, (20, 20)))
    end
end

@testitem "layouts: InsertUntil draws uniformly over the region" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
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
        ts = [
            only(
                last(
                    _tally(
                        overlay(
                            hosts,
                            InsertUntil(:guest; into = [:host], number = 4, seed, misses = :count, region = (3:4, 3:6))
                        ), (6, 6)
                    )
                )
            )
                for seed in 1:400
        ]
        @test all(t -> t.painted + t.misses == t.counted && t.counted >= 4, ts)
        frac = sum(t -> t.misses, ts) / sum(t -> t.painted + t.misses, ts)
        @test 0.35 < frac < 0.65
    end
end

@testitem "layouts: InsertUntil on hex, 3D and domain lattices" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
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
        op, t = _tally(
            overlay(
                Tiling((4, 4); region = (1:12, 1:12), kinds = [:host]),
                InsertUntil(:guest; into = [:host], number = 6, seed = 9)
            ), sys
        )
        @test only(t).painted == 6 && only(t).misses > 0
        @test all(i -> i[1] + i[2] <= 26, findall(>(0), _op(op, ownership)))
        # the operating point runs
        prob = PottsProblem(sys, op, (0, 5))
        @test Symbol(solve(prob, SequentialCPM()).retcode) === :Success
        # bad regions
        ly_throws(
            ArgumentError, ["lies outside the lattice", "keep each axis range within 1:n"],
            () -> layout(overlay(Tiling((2, 2); kinds = [:a]), InsertUntil(:x; into = [:a], number = 1, seed = 1, region = (1:30, 1:4))), (8, 8))
        )
        ly_throws(
            ArgumentError, ["the layout is 1D, the lattice 2D", "match the layout dimension"],
            () -> layout(overlay(Tiling((2, 2); kinds = [:a]), InsertUntil(:x; into = [:a], number = 1, seed = 1, region = (1:4,))), (8, 8))
        )
        ly_throws(
            ArgumentError, ["is empty", "pass non-empty ranges"],
            () -> InsertUntil(:x; into = [:a], number = 1, seed = 1, region = (1:0, 1:3))
        )
        ly_throws(
            ArgumentError, ["`kinds` is empty", "supply at least one kind"],
            () -> InsertUntil(:x; into = Symbol[], number = 1, seed = 1)
        )
        ly_throws(
            ArgumentError, ["`number` must be a non-negative integer"],
            () -> InsertUntil(:x; into = [:a], number = -1, seed = 1)
        )
        ly_throws(
            ArgumentError, ["`fraction` must lie strictly between 0 and 1"],
            () -> InsertUntil(:x; into = [:a], fraction = 1, seed = 1)
        )
    end
end

# ---------------------------------------------------------------------------------------------
# Shapes, point patterns and Voronoi (P6.1a5, D-138); the frozen acceptance file holds the
# hand counts, the VoronoiBall pins and the brute-force oracle
# ---------------------------------------------------------------------------------------------
@testitem "layouts: layer_rng" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
    @testset "layouts: layer_rng" begin
        @test rand(Potts.layer_rng(5), 3) == rand(Potts.layer_rng(UInt8(5)), 3)
        @test rand(Potts.layer_rng(5, :a), 3) != rand(Potts.layer_rng(5, :b), 3)
        @test rand(Potts.layer_rng(5, :a), 3) != rand(Potts.layer_rng(6, :a), 3)
        ly_throws(
            ArgumentError, ["seed must be in 0:typemax(UInt64)", "pass a non-negative integer seed"],
            () -> Potts.layer_rng(typemax(UInt64) + big(1))
        )
        ly_throws(
            ArgumentError, ["seed must be in 0:typemax(UInt64)", "pass a non-negative integer seed"],
            () -> RandomPoints(1; seed = typemax(UInt64) + big(1))
        )
    end
end

@testitem "layouts: Voronoi is equivariant under periodic translation" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
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
end

@testitem "layouts: shapes on periodic 3D lattices and boxes on domains" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
    @testset "layouts: shapes on periodic 3D lattices and boxes on domains" begin
        # a sphere through the corner of a periodic cube wraps into all 8 corners, clips nothing
        op, rep = layout(
            Voronoi(Center(); region = Potts.Sphere(Potts.Point(1.0, 1.0, 1.0), 2.0), kinds = [:a]),
            Lattice((10, 10, 10)); report = true
        )
        σ = _op(op, ownership)
        @test count(!=(0), σ) == 33 && only(rep).clipped == 0
        @test all(x -> σ[x...] == 1, Iterators.product((1, 10), (1, 10), (1, 10)))
        # on a closed cube the same sphere keeps the 11 points with offsets ≥ 0
        @test only(
            last(
                layout(
                    Voronoi(Center(); region = Potts.Sphere(Potts.Point(1.0, 1.0, 1.0), 2.0), kinds = [:a]),
                    (10, 10, 10); report = true
                )
            )
        ).clipped == 22
        # a box region on a domain clips its out-of-domain sites
        dom = Lattice((10, 10); boundary = Closed(), domain = x -> x[1] <= 5)
        op, rep = layout(Voronoi(Center(); region = (3:8, 1:2), kinds = [:a]), dom; report = true)
        @test count(!=(0), _op(op, ownership)) == 6 && only(rep).clipped == 6
        # a single Point is a one-generator pattern
        @test Potts.points(Potts.Point(2, 3), (5, 5)) == [Potts.Point(2.0, 3.0)]
    end
end

@testitem "layouts: Voronoi repair leaves a piece cut off by the domain" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
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
end

@testitem "layouts: Voronoi arguments and remake" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
    @testset "layouts: Voronoi arguments and remake" begin
        ly_throws(
            ArgumentError, ["a point list holds `Point`s and `Center()`s"],
            () -> Voronoi([1, 2]; kinds = [:a])
        )
        ly_throws(ArgumentError, ["is not a point pattern"], () -> Voronoi(:nope; kinds = [:a]))
        ly_throws(
            ArgumentError, ["finite center and a finite, non-negative radius"],
            () -> Voronoi(Center(); region = Potts.Circle(Potts.Point(1.0, 1.0), -1.0), kinds = [:a])
        )
        ly_throws(
            ArgumentError, ["finite center and a finite, non-negative radius"],
            () -> Voronoi(Center(); region = Potts.Circle(Potts.Point(NaN, 1.0), 1.0), kinds = [:a])
        )
        ly_throws(
            ArgumentError, ["is empty", "pass non-empty ranges"],
            () -> RandomPoints(3; region = (1:0, 1:2), seed = 1)
        )
        ly_throws(
            ArgumentError, ["has no argument `bogus`", "pass valid constructor keywords"],
            () -> remake(RandomPoints(3; seed = 1); bogus = 1)
        )
        ly_throws(
            ArgumentError, ["the region has 1 ranges, the lattice is 2D"],
            () -> layout(Voronoi(Center(); region = (1:4,), kinds = [:a]), (8, 8))
        )
        @test Potts.points(remake(RandomPoints(3; seed = 1); n = 5), (8, 8)) == Potts.points(RandomPoints(5; seed = 1), (8, 8))
    end
end

@testitem "layouts: shape membership is closed up to rounding (site-centred discs)" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
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
        disc = Potts.Circle(Potts.Point(hexpos((12, 12))), 1 - 1.0e-9)
        @test count(!=(0), _op(layout(Voronoi([Potts.Point(hexpos((12, 12)))]; region = disc, kinds = [:a]), hexl), ownership)) == 1
    end
end

@testitem "layouts: generator points must be finite" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
    @testset "layouts: generator points must be finite" begin
        for bad in (Potts.Point(NaN, 1.0), Potts.Point(Inf, 1.0), Potts.Point(1.0e300, 1.0))
            ly_throws(ArgumentError, ["point coordinates must be finite and below 1e15"], () -> Voronoi([bad]; kinds = [:a]))
            ly_throws(ArgumentError, ["point coordinates must be finite and below 1e15"], () -> Voronoi(bad; kinds = [:a]))
            ly_throws(ArgumentError, ["point coordinates must be finite and below 1e15"], () -> Potts.points([bad], (10, 10)))
        end
    end
end


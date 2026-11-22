# Layouts: shapes placed at random to a density (InsertUntil with Bar, Rod and round
# shapes; Fibers), chains of linked cells along polylines (Chains), and the jittered Tiling.

@testitem "layouts: bars and round shapes to a density" setup = [LayoutsSetup] tags = [
    :potts, :layouts,
] begin
    using Potts.Layouts
    cells_of(σ) = [count(==(c), σ) for c in 1:maximum(σ; init = 0)]
    # an axis-aligned bar of integer size is exactly length × width sites, wherever it lies
    for θ in (0.0, π / 2), seed in 1:5
        σ = _op(layout(InsertUntil(Bar(6, 2); kinds = [:f], number = 3, angles = [θ], seed), (20, 20)), ownership)
        @test cells_of(σ) == [12, 12, 12]
        # the long side runs along the drawn direction
        ext = maximum(i[θ == 0 ? 1 : 2] for i in _sites(σ, 1)) -
            minimum(i[θ == 0 ? 1 : 2] for i in _sites(σ, 1))
        @test ext == 5
    end
    for dir in ([0, 0, 1], [1, 0, 0])
        σ = _op(layout(InsertUntil(Bar(6, 2); kinds = [:f], number = 2, angles = [dir], seed = 3), (12, 12, 12)), ownership)
        @test cells_of(σ) == [24, 24]
    end
    # a round shape is the sites of the shape at the anchor: 13 sites for r = 2
    σ = _op(layout(InsertUntil(Circle(Point(0.0, 0.0), 2.0); kinds = [:c], number = 4, seed = 2), (30, 30)), ownership)
    @test cells_of(σ) == fill(13, 4)
    # density: at least ρ, and less than ρ plus one copy's share; copies never overlap
    for (shape, big) in ((Bar(6, 2), 21), (Circle(Point(0.0, 0.0), 2.0), 13)), ρ in (0.1, 0.3), seed in 1:3
        op, rep = layout(InsertUntil(shape; kinds = [:a, :b], density = ρ, seed), (40, 40); report = true)
        σ = _op(op, ownership)
        f = count(>(0), σ) / 1600
        @test ρ <= f < ρ + big / 1600
        r = only(rep)
        @test r.counted == r.painted == maximum(σ) && r.dropped == 0
        @test all(<=(big), cells_of(σ))
        # kinds cycle over the copies
        @test _op(op, kind) == [isodd(c) ? :a : :b for c in 1:maximum(σ)]
    end
    # a fixed seed repeats the layout; another seed changes it
    l(seed) = InsertUntil(Bar(5, 2); kinds = [:f], density = 0.2, seed)
    @test _same(layout(l(4), (30, 30)), layout(l(4), (30, 30)))
    @test !_same(layout(l(4), (30, 30)), layout(l(5), (30, 30)))
end

@testitem "layouts: InsertUntil shapes over earlier layers" setup = [LayoutsSetup] tags = [
    :potts, :layouts,
] begin
    using Potts.Layouts
    hosts = Tiling((4, 4); spacing = 4, kinds = [:host])
    bars = InsertUntil(Bar(6, 1); kinds = [:f], number = 20, seed = 1)
    op = layout(overlay(hosts, bars), (40, 40))
    σ, ks = _op(op, ownership), _op(op, kind)
    # occupied = :all (default): no host loses a site
    @test all(c -> count(==(c), σ) == 16, findall(==(:host), ks))
    # occupied = [] paints over the hosts, which then lose sites (negative control)
    op = layout(overlay(hosts, InsertUntil(Bar(6, 1); kinds = [:f], number = 20, occupied = (), seed = 1, splits = :allow)), (40, 40))
    σ, ks = _op(op, ownership), _op(op, kind)
    @test any(c -> count(==(c), σ) < 16, findall(==(:host), ks))
    # occupied blocks only the kinds named: walls stay, the fluid is painted over
    op = layout(
        overlay(Fill(:fluid), Frame(:wall), InsertUntil(Bar(6, 2); kinds = [:f], number = 10, angles = [0.0], occupied = [:wall], seed = 2, splits = :allow)),
        (30, 30)
    )
    σ, ks = _op(op, ownership), _op(op, kind)
    @test count(i -> ks[σ[i]] == :wall, eachindex(σ)) == 30 * 30 - 28 * 28
    @test count(i -> ks[σ[i]] == :f, eachindex(σ)) == 10 * 12
    # a fully blocked region jams: a typed error naming the cause
    err = ly_throws(ArgumentError, [], () -> layout(overlay(Fill(:fluid), bars), (20, 20)))
    @test occursin("jammed", err.msg)
    # collective: every copy paints one cell; with occupied = () the copies may overlap
    op, rep = layout(InsertUntil(Bar(6, 2); kinds = [:m], density = 0.3, occupied = (), collective = true, seed = 3), (30, 30); report = true)
    σ = _op(op, ownership)
    @test maximum(σ) == 1 && count(==(1), σ) >= 0.3 * 900 && only(rep).painted == 1
    @test only(rep).counted > 0.3 * 900 / 12              # overlaps need more copies
    # partial: :reject keeps every copy whole on a closed lattice, :clip cuts at the edge
    function whole(partial)
        l = InsertUntil(Bar(6, 2); kinds = [:f], number = 12, angles = [0.0], partial, seed = 7)
        σ = _op(layout(l, (14, 30)), ownership)
        return [count(==(c), σ) for c in 1:12]
    end
    @test all(==(12), whole(:reject))
    @test any(<(12), whole(:clip))
    # a domain: copies stay in it
    sys = DomainLayoutProbe(; name = :d)
    σ = _op(layout(InsertUntil(Bar(3, 1); kinds = [:cell], number = 6, seed = 1), sys), ownership)
    @test all(i -> i[1] <= 5, findall(>(0), σ))
    # a region: copies stay in it and the density is of the region
    op = layout(InsertUntil(Bar(4, 1); kinds = [:f], density = 0.25, region = (11:30, 1:20), seed = 1), (30, 30))
    σ = _op(op, ownership)
    @test all(i -> i[1] >= 11 && i[2] <= 20, findall(>(0), σ))
    @test 0.25 <= count(>(0), σ) / 400 < 0.25 + 5 / 400
end

@testitem "layouts: InsertUntil shapes cross periodic seams" setup = [LayoutsSetup] tags = [
    :potts, :layouts,
] begin
    using Potts.Layouts
    sys = PeriodicLayoutProbe(; name = :p)            # 12 × 12, periodic
    op = layout(InsertUntil(Bar(6, 2); kinds = [:cell], number = 8, angles = [0.0, π / 2], seed = 5), sys)
    σ = _op(op, ownership)
    # every copy is whole (no edge to clip at), and some copy runs across a seam
    @test [count(==(c), σ) for c in 1:8] == fill(12, 8)
    across(c) = (s = _sites(σ, c); any(d -> 1 in getindex.(s, d) && 12 in getindex.(s, d), 1:2))
    @test any(across, 1:8)
    # the channel: periodic along 1, closed along 2; :reject never cuts at the closed edge
    sys = ChannelLayoutProbe(; name = :c)              # 11 × 11
    σ = _op(layout(InsertUntil(Bar(5, 1); kinds = [:cell], number = 10, angles = [π / 2], seed = 1), sys), ownership)
    @test [count(==(c), σ) for c in 1:10] == fill(5, 10)
end

@testitem "layouts: rods are linked chains, head first" setup = [LayoutsSetup] tags = [
    :potts, :layouts,
] begin
    using Potts.Layouts
    rod = Rod(4; length = 3, width = 2, link = :chain)
    op, rep = layout(InsertUntil(rod; kinds = [:seg], number = 5, angles = [0.0], seed = 2), (40, 40); report = true)
    σ = _op(op, ownership)
    # 5 rods of 4 segments, each 3 × 2 sites
    @test maximum(σ) == 20 && [count(==(c), σ) for c in 1:20] == fill(6, 20)
    @test only(rep).counted == 5 && only(rep).painted == 20
    links = _op(op, :chain)
    @test links == [(4(r - 1) + i, 4(r - 1) + i + 1) for r in 1:5 for i in 1:3]
    # the head is at the front along the direction (+axis 1 for angle 0)
    cx(c) = sum(i[1] for i in _sites(σ, c)) / count(==(c), σ)
    @test all(r -> issorted([cx(4(r - 1) + i) for i in 1:4]; rev = true), 1:5)
    # density counts every segment's sites
    op = layout(InsertUntil(rod; kinds = [:seg], density = 0.2, seed = 3), (40, 40))
    @test 0.2 <= count(>(0), _op(op, ownership)) / 1600 < 0.2 + 30 / 1600
    # no link argument, no links
    op = layout(InsertUntil(Rod(3; length = 2, width = 1); kinds = [:seg], number = 2, seed = 1), (20, 20))
    @test !any(p -> isequal(first(p), :chain), op)
    # 3D rods
    σ = _op(layout(InsertUntil(rod; kinds = [:seg], number = 2, angles = [[0, 1, 0]], seed = 1), (16, 16, 16)), ownership)
    @test [count(==(c), σ) for c in 1:8] == fill(12, 8)
end

@testitem "layouts: rod links reach the problem in order" setup = [LayoutsSetup] tags = [
    :potts, :layouts,
] begin
    using Potts.Layouts
    using Potts: CorePotts
    @potts_model RodChainProbe begin
        @kinds medium seg
        @relationship chain(cell, cell) ordered = true
        @lattice Lattice((30, 30); neighborhood = Moore(1))
        @energy cells => (volume - 6)^2
        @sweep Metropolis(; temperature = 2.0)
    end
    sys = RodChainProbe(; name = :r)
    op = layout(InsertUntil(Rod(4; length = 3, width = 2, link = :chain); kinds = [:seg], number = 3, seed = 3), sys)
    u = solve(PottsProblem(sys, op, (0, 1)), SequentialCPM()).u[end]
    s = CorePotts.link_store(u.cell, :chain)
    @test CorePotts.chain_rank.(Ref(s), 1:12) == repeat(1:4, 3)
end

@testitem "layouts: Fibers" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
    using Potts.Layouts
    angles = deg2rad.([0, 30, -30, 45, -45, 60, -60, 90])
    for ρ in (0.1, 0.4), seed in 1:2
        op, rep = layout(
            overlay(Fill(:fluid), Fibers(:matrix; length = 6, width = 2, angles, density = ρ, seed, splits = :allow)),
            (50, 50); report = true
        )
        σ, ks = _op(op, ownership), _op(op, kind)
        f = count(i -> σ[i] > 0 && ks[σ[i]] == :matrix, eachindex(σ)) / 2500
        @test ρ <= f < ρ + 21 / 2500
        @test count(==(:matrix), ks) == 1
        @test rep[2].type === :Fibers && rep[2].painted == 1
    end
    # the same layer as InsertUntil with a Bar and the Fibers defaults
    a = Fibers(:m; length = 6, width = 2, angles, density = 0.3, seed = 1)
    b = InsertUntil(Bar(6, 2); kinds = [:m], density = 0.3, angles, occupied = (), collective = true, partial = :clip, seed = 1)
    @test _same(layout(a, (30, 30)), layout(b, (30, 30)))
    @test_throws ArgumentError Fibers(:m; length = 6, seed = 1)                  # no stop rule
    @test_throws ArgumentError Fibers(:m; length = 0, density = 0.1, seed = 1)
    @test_throws ArgumentError Fibers([:m, :n]; length = 6, density = 0.1, seed = 1)
end

@testitem "layouts: Chains along polylines" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
    using Potts.Layouts
    # a straight chain on lattice lines: 12 × 2 sites in 4 equal cells, linked head first
    line = [Point(4.5, 10.5), Point(16.5, 10.5)]
    op, rep = layout(Chains(line; segments = 4, width = 2, kinds = [:seg], link = :chain), (20, 20); report = true)
    σ = _op(op, ownership)
    @test [count(==(c), σ) for c in 1:4] == fill(6, 4)
    @test _op(op, :chain) == [(1, 2), (2, 3), (3, 4)]
    @test all(i -> i[1] in 5:7, _sites(σ, 1))                # cell 1 at the first point
    @test only(rep).clipped == 0
    # kinds cycle along each chain from the head: a pinned head
    op = layout(Chains([line, line .+ Ref(Point(0.0, 5.0))]; segments = 3, width = 1, kinds = [:pin, :seg, :seg]), (20, 20))
    @test _op(op, kind) == [:pin, :seg, :seg, :pin, :seg, :seg]
    # a U: every cell gets a share, links follow the path
    u = [Point(30.0, 10.5), Point(10.0, 10.5), Point(10.0, 22.5), Point(30.0, 22.5)]
    op = layout(Chains(u; segments = 13, width = 2, kinds = [:seg], link = :chain), (40, 40))
    σ = _op(op, ownership)
    @test maximum(σ) == 13 && all(c -> count(==(c), σ) > 0, 1:13)
    @test 100 <= count(>(0), σ) <= 104                       # 52 × 2, less a corner or two
    # the first chain wins a crossing; the second keeps the rest
    cross = [[Point(2.5, 10.5), Point(18.5, 10.5)], [Point(10.5, 2.5), Point(10.5, 18.5)]]
    σ = _op(layout(Chains(cross; segments = 1, width = 1, kinds = [:seg]), (20, 20)), ownership)
    @test count(==(1), σ) == 16 && count(==(2), σ) == 15
    # periodic: a chain wraps through the seam; closed: the part beyond the edge is clipped
    seam = [Point(8.5, 6.5), Point(16.5, 6.5)]
    σ = _op(layout(Chains(seam; segments = 2, width = 1, kinds = [:cell]), PeriodicLayoutProbe(; name = :p)), ownership)
    @test count(>(0), σ) == 8 && σ[1, 7] > 0 && σ[12, 7] > 0
    op, rep = layout(Chains(seam; segments = 2, width = 1, kinds = [:cell]), (12, 12); report = true)
    @test count(>(0), _op(op, ownership)) == 4 && only(rep).clipped == 4
    # 3D: a square cross-section
    σ = _op(layout(Chains([Point(3.5, 6.5, 6.5), Point(9.5, 6.5, 6.5)]; segments = 2, width = 2, kinds = [:seg]), (12, 12, 12)), ownership)
    @test [count(==(c), σ) for c in 1:2] == [12, 12]
    # a later layer that empties a cell drops its links, with one warning
    w = _warnings(() -> layout(overlay(Chains(line; segments = 4, width = 2, kinds = [:seg], link = :chain), Fill(:seg; region = (5:7, 1:20))), (20, 20)))
    @test any(m -> occursin("dropped", m), w)
    @test_throws ArgumentError Chains([Point(1.0, 1.0)]; segments = 1, width = 1, kinds = [:a])
    @test_throws ArgumentError Chains([Point(1.0, 1.0), Point(1.0, 1.0)]; segments = 1, width = 1, kinds = [:a])
    @test_throws ArgumentError Chains(line; segments = 0, width = 1, kinds = [:a])
    @test_throws ArgumentError Chains(line; segments = 1, width = 0, kinds = [:a])
end

@testitem "layouts: jittered Tiling" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
    using Potts.Layouts
    base = _op(layout(Tiling((3, 3); spacing = 4, kinds = [:c]), (40, 40)), ownership)
    n = maximum(base)
    corner(σ, c) = Tuple(minimum(_sites(σ, c)))
    for seed in 1:4
        σ = _op(layout(Tiling((3, 3); spacing = 4, jitter = 2, seed, kinds = [:c]), (40, 40)), ownership)
        # the same boxes, each whole and moved at most 2 sites per axis
        @test maximum(σ) == n && all(c -> count(==(c), σ) == 9, 1:n)
        @test all(c -> all(abs.(corner(σ, c) .- corner(base, c)) .<= 2), 1:n)
    end
    moved = _op(layout(Tiling((3, 3); spacing = 4, jitter = 2, seed = 1, kinds = [:c]), (40, 40)), ownership)
    @test moved != base
    # jitter 0 is the plain tiling
    @test _op(layout(Tiling((3, 3); spacing = 4, jitter = 0, kinds = [:c]), (40, 40)), ownership) == base
    @test_throws ArgumentError Tiling((3, 3); spacing = 4, jitter = 3, seed = 1, kinds = [:c])
    @test_throws ArgumentError Tiling((3, 3); spacing = 4, jitter = 1, kinds = [:c])
end

@testitem "layouts: InsertUntil shape arguments" setup = [LayoutsSetup] tags = [:potts, :layouts] begin
    using Potts.Layouts
    b = Bar(6, 2)
    @test_throws ArgumentError Bar(0, 2)
    @test_throws ArgumentError Bar(6, Inf)
    @test_throws ArgumentError Rod(0; length = 2, width = 1)
    @test_throws ArgumentError InsertUntil(b; kinds = [:f], seed = 1)
    @test_throws ArgumentError InsertUntil(b; kinds = [:f], density = 0.1, number = 2, seed = 1)
    @test_throws ArgumentError InsertUntil(b; kinds = [:f], density = 1.5, seed = 1)
    @test_throws ArgumentError InsertUntil(b; kinds = [:f, :g], number = 1, collective = true, seed = 1)
    @test_throws ArgumentError InsertUntil(Rod(2; length = 2, width = 1); kinds = [:f], number = 1, collective = true, seed = 1)
    @test_throws ArgumentError InsertUntil(b; kinds = [:f], number = 1, partial = :trim, seed = 1)
    @test_throws ArgumentError InsertUntil(b; kinds = [:f], number = 1, angles = [], seed = 1)
    @test_throws ArgumentError InsertUntil(b; kinds = [:f], number = 1, occupied = :wall, seed = 1)
    # bars are 2D or 3D; the round shape must match the lattice
    @test_throws ArgumentError layout(InsertUntil(b; kinds = [:f], number = 1, seed = 1), (10,))
    @test_throws ArgumentError layout(InsertUntil(Circle(Point(0.0, 0.0), 2.0); kinds = [:f], number = 1, seed = 1), (10, 10, 10))
    # remake keeps the layer
    l = InsertUntil(b; kinds = [:f], density = 0.2, seed = 1)
    @test _same(layout(remake(l; seed = 1), (20, 20)), layout(l, (20, 20)))
end

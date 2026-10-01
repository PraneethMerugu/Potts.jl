# P6.2a2 (ROADMAP Phase 6, step 2; spec 10 V-A1(a); D-068, D-073, D-075): `akeeb_state` is
# built on `InsertUntil` (`misses = :count`, `fraction = 1//4`), draws only from StableRNG,
# and exposes the counted leader inventory. Frozen (AUTONOMY §7.3).
#
# Surface fixed by the coordinator:
#
#   akeeb_layout(; lattice = (500, 300), seed = 0x5cd2609, slab = 21, seeding = :authors)
#       -> AbstractLayout                                  (PottsModels, public or exported)
#     The published initial slab as a layout value. Its cells are the follower slab of
#     `akeeb_state` (3 × 3 tiles over the rows y ≤ slab, rounded up to whole tiles, clipped
#     at the right edge), then ONE leader layer
#         InsertUntil(:leader; into = [:follower], fraction = 1 // 4, seed,
#                     misses = (seeding === :authors ? :count : :retry),
#                     region = (2:X, 2:(slab - 1)))
#     (the draw ranges of the authors' CCIecmSteppables.py S:70–71; the seed is passed
#     through unchanged). The counted inventory (spec 10 V-A1(a)) is that layer's tally,
#     read with the public layout report (P6.1a6; `p62a2_tally` below keeps its
#     InsertUntil rows as `(; painted, misses, counted)`):
#         only(last(p62a2_tally(akeeb_layout(; lattice, seed, slab, seeding), lattice)))
#     `painted` = leaders created, `misses` = missed draws (the authors' empty "ghost"
#     leaders under :authors, D-068), `counted` = the CC3D inventory (390 at 500 × 300,
#     occasionally 391 or 392 under :authors). Bad `seeding` throws an ArgumentError.
#
#   akeeb_state(; lattice, pp, seed, slab, seeding)
#       -> [ownership => σ, kind => kinds, :clock => …, :rate => …, :cue => …]
#     Keys and order unchanged (the frozen papers.jl reads `o[2].second`). `σ` and `kinds`
#     are exactly `layout(akeeb_layout(; lattice, seed, slab, seeding), lattice)`.
#     Clocks are drawn from `StableRNG(seed + 1)`, one cell at a time in id order: a leader
#     draws nothing (clock −1); a follower draws u = rand(rng), and its clock is −1 if
#     u > pp, else Float64(rand(rng, 0:74)). This is today's recipe with MersenneTwister
#     replaced by StableRNG (D-075: StableRNG only), so the state is the same on every
#     Julia version. `akeeb_state` logs no warning: several leaders inside one follower can
#     cut it, which `overlay` warns about, but that is the published slab, not a user error.
#
# Expected values are structural (the CC3D quota 4n ≥ 1169 + n gives n = 390 at
# 500 × 300; 4n ≥ 231 + n gives 77 at 99 × 60). No value depends on a particular draw
# beyond "some draw missed", whose failure probability is exp(−Σ_{n<390} n/9481) ≈ 3e-4
# per seed at 500 × 300.
using Potts: CorePotts

p62a2_get(op, key) = only(last(p) for p in op if isequal(first(p), key))
p62a2_quiet(f) = Base.CoreLogging.with_logger(f, Base.CoreLogging.NullLogger())
# The InsertUntil rows of the layout report as (; painted, misses, counted), in paint order.
function p62a2_tally(l, lat)
    op, report = layout(l, lat; report = true)
    return op, [(; r.painted, r.misses, r.counted) for r in report if r.type === :InsertUntil]
end

# Independent oracle for the follower slab: today's hand loop (ids x-fastest, row by row),
# written through the public layout extension API `Potts.paint!` (P6.1a6 protocol).
struct P62a2Slab <: Potts.AbstractLayout
    X::Int
    slab::Int
end
function Potts.paint!(op::Potts.LayoutState, l::P62a2Slab, lat)
    n = 0
    for y in 1:3:(l.slab), x in 1:3:(l.X)
        Potts.assign!(op, (x:min(x + 2, l.X), y:(y + 2)), Potts.new_cell!(op, :follower))
        n += 1
    end
    Potts.record!(op; requested = n, painted = n)
    return nothing
end
p62a2_oracle(X, slab, seed, misses) = overlay(P62a2Slab(X, slab),
    InsertUntil(:leader; into = [:follower], fraction = 1 // 4, seed, misses, region = (2:X, 2:(slab - 1))))

# The clock recipe on StableRNG(seed + 1) over the kinds as returned (id order).
function p62a2_clocks(kinds, pp, seed; rng = PottsModels.StableRNG(seed + 1))
    return [k === :leader || rand(rng) > pp ? -1.0 : Float64(rand(rng, 0:74)) for k in kinds]
end

# Equal partitions up to relabelling the followers, and identical leader ids and sites.
function p62a2_same_cells(σa, ka, σo, ko)
    nf = count(==(:follower), ko)
    count(==(:follower), ka) == nf || return false
    sort(ka) == sort(ko) || return false
    (σa .> nf) == (σo .> nf) || return false                     # leader sites
    σa[σa .> nf] == σo[σo .> nf] || return false                 # leader ids, in paint order
    (σa .== 0) == (σo .== 0) || return false
    pairs = Set(zip(σa[0 .< σa .<= nf], σo[0 .< σo .<= nf]))     # follower id bijection
    return length(pairs) == nf && length(Set(first.(pairs))) == nf && length(Set(last.(pairs))) == nf
end

@testset "P6.2a2: akeeb_layout is public and akeeb_state keeps its shape" begin
    @test isdefined(PottsModels, :akeeb_layout) && Base.ispublic(PottsModels, :akeeb_layout)
    @test PottsModels.akeeb_layout(; lattice = (99, 60), seed = 1) isa Potts.AbstractLayout
    o = akeeb_state(; lattice = (99, 60), seed = 1)
    @test length(o) == 5 && isequal(first(o[1]), ownership) && isequal(first(o[2]), kind)
    @test [first(p) for p in o[3:5]] == [:clock, :rate, :cue]
    @test o[1].second isa Matrix{Int32} && o[2].second isa Vector{Symbol}
    @test o[3].second isa Vector{Float64} && o[4].second isa Vector{Float64} && o[5].second isa Matrix{Float64}
    doc = string(@doc akeeb_state)
    @test occursin("StableRNG", doc) && !occursin("MersenneTwister", doc)
    @test_throws ArgumentError akeeb_state(; seeding = :other)
    @test_throws ArgumentError PottsModels.akeeb_layout(; seeding = :other)
    @test_throws ArgumentError akeeb_state(; lattice = (30, 21))          # no row above the slab
end

@testset "P6.2a2: akeeb_state is InsertUntil(fraction = 1//4, misses = :count) on the slab" begin
    # lattices: the published one, the tests' 99 × 60, and slabs that are and are not whole tiles
    cases = [((500, 300), 21, 0x5cd2609), ((500, 300), 21, 7), ((99, 60), 21, 3), ((60, 40), 15, 11),
        ((61, 40), 13, 5)]
    for (lat, slab, seed) in cases, (seeding, misses) in ((:authors, :count), (:retry, :retry))
        o = p62a2_quiet(() -> akeeb_state(; lattice = lat, slab, seed, seeding))
        σ, ks = p62a2_get(o, ownership), p62a2_get(o, kind)
        ref, tref = p62a2_quiet(() -> p62a2_tally(p62a2_oracle(lat[1], slab, seed, misses), lat))
        @test p62a2_same_cells(σ, ks, p62a2_get(ref, ownership), p62a2_get(ref, kind))
        # the counted inventory through the public API: one InsertUntil layer, the same tally
        op, t = p62a2_quiet(() -> p62a2_tally(PottsModels.akeeb_layout(; lattice = lat, slab, seed, seeding), lat))
        @test t == tref && length(t) == 1
        @test p62a2_get(op, ownership) == σ && p62a2_get(op, kind) == ks       # akeeb_state paints it
        @test count(==(:leader), ks) == only(t).painted
    end
end

@testset "P6.2a2: V-A1(a) counted inventory at 500 × 300 (D-068 ghosts)" begin
    lat, nf = (500, 300), 1169                          # 166·7 + 7 followers
    for seed in (0x5cd2609, 1)
        o = p62a2_quiet(() -> akeeb_state(; lattice = lat, seed))
        σ, ks = p62a2_get(o, ownership), p62a2_get(o, kind)
        t = only(last(p62a2_quiet(() -> p62a2_tally(PottsModels.akeeb_layout(; lattice = lat, seed), lat))))
        np = count(==(:leader), ks)
        # followers: all 1169, none erased, ids first
        @test count(==(:follower), ks) == nf && ks[1:nf] == fill(:follower, nf)
        @test all(c -> any(==(c), σ), 1:nf)
        # inventory: every draw counts; ghosts are never cells (D-066 X2)
        @test t.painted == np && length(ks) == nf + np
        @test t.counted == t.painted + t.misses
        # leader fraction: the inventory meets the quarter, overshooting only by trailing misses
        @test 4 * t.counted >= nf + t.counted && 390 <= t.counted <= 390 + t.misses
        # the authors' empty leaders exist, so the painted fraction stays below a quarter
        @test t.misses > 0 && 4 * np < nf + np
        # one-site leaders, ids in paint order, on follower pixels of the draw region
        slab = p62a2_get(layout(P62a2Slab(500, 21), lat), ownership)
        @test sort(σ[σ .> nf]) == (nf + 1):(nf + np)
        sites = findall(σ .> nf)
        @test all(i -> 2 <= i[1] <= 500 && 2 <= i[2] <= 20 && slab[i] > 0, sites)
        # D-068: a ghost changes nothing but the count. Under :retry the same stream paints the
        # full quota, and the :authors leaders are exactly its first `np` leaders
        or = p62a2_quiet(() -> akeeb_state(; lattice = lat, seed, seeding = :retry))
        σr, kr = p62a2_get(or, ownership), p62a2_get(or, kind)
        tr = only(last(p62a2_quiet(() -> p62a2_tally(PottsModels.akeeb_layout(; lattice = lat, seed, seeding = :retry), lat))))
        @test count(==(:leader), kr) == 390 == tr.painted == tr.counted
        @test σr[sites] == σ[sites] && tr.misses >= t.misses
        @test count(>(nf), σr) == 390 && all(i -> σr[i] <= nf + np, sites)
    end
end

@testset "P6.2a2: StableRNG only, reproducible" begin
    for (lat, seed, pp) in (((500, 300), 0x5cd2609, 0.5), ((99, 60), 2, 0.5), ((99, 60), 4, 0.9), ((99, 60), 4, 0.0))
        a = p62a2_quiet(() -> akeeb_state(; lattice = lat, seed, pp))
        b = p62a2_quiet(() -> akeeb_state(; lattice = lat, seed, pp))
        @test all(i -> isequal(a[i], b[i]), 1:5)
        ks = p62a2_get(a, kind)
        clocks = p62a2_get(a, :clock)
        # the clock stream is StableRNG(seed + 1) in id order
        @test clocks == p62a2_clocks(ks, pp, seed)
        # negative control: the oracle depends on the stream (another StableRNG seed differs)
        pp > 0 && @test p62a2_clocks(ks, pp, seed) != p62a2_clocks(ks, pp, seed; rng = PottsModels.StableRNG(seed + 2))
        @test p62a2_get(a, :rate) == [k === :leader ? 0.0 : 0.015 for k in ks]
        @test p62a2_get(a, :cue) == [Float64(y - 1) for x in 1:lat[1], y in 1:lat[2]]
        pp == 0 && @test all(==(-1.0), clocks)
    end
    # distinct seeds give distinct slabs
    σs = [p62a2_get(akeeb_state(; lattice = (99, 60), seed), ownership) for seed in 1:4]
    @test length(unique(σs)) == 4
    # akeeb_state is quiet at the published size. At seed 1 the leaders cut a follower in
    # two (a bare `overlay` of the oracle slab and the leader layer warns there)
    @test_logs min_level = Base.CoreLogging.Warn akeeb_state()
    @test_logs min_level = Base.CoreLogging.Warn akeeb_state(; seed = 1)
    @test_logs (:warn, r"split cell") layout(p62a2_oracle(500, 21, 1, :count), (500, 300))  # not vacuous
end

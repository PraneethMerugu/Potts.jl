# The CorePotts core tests (the inline testsets of the old runtests.jl): relations, RNG,
# ΔH against brute force, trackers, both algorithms.
@testsetup module CP_corepotts
using Test, CorePotts, StaticArrays, Statistics, Random
using SciMLBase: SciMLBase, ReturnCode, remake
using CorePotts: RNGKey, draw, uniform, bounded, stream_id, cell_entity, coordinates, linear_index, shift
include("shared/gg_model.jl")
include(joinpath(@__DIR__, "..", "..", "..", "test", "shared", "props.jl"))

    invdist(o) = 1 / sqrt(sum(abs2, o))

    σ0, kinds0 = blocks((36, 36), 5)
    lat = Lattice((36, 36))
    prob = PottsProblem(GG, initial_state(σ0, kinds0), lat, (0, 20), gg_params(); seed = 7)
include("shared/export_all.jl")
end

@testitem "relations" setup = [CP_corepotts] tags = [:corepotts, :core] begin
    @testset "relations" begin
        l2 = Lattice((20, 20)); l3 = Lattice((12, 12, 12))
        @test length(relation(VonNeumann(1), l2)) == 4
        @test length(relation(VonNeumann(1), l3)) == 6
        @test length(relation(Moore(1), l2)) == 8
        @test length(relation(Moore(1), l3)) == 26
        @test length(relation(Moore(1; include_self = true), l2)) == 9
        # CompuCell3D NeighborOrder counts (cumulative distance shells)
        @test [length(relation(NeighborOrder(k), l2)) for k in 1:6] == [4, 8, 12, 20, 24, 28]
        @test [length(relation(NeighborOrder(k), l3)) for k in 1:6] == [6, 18, 26, 32, 56, 80]
        # canonical order: nondecreasing squared length
        r = relation(NeighborOrder(4), l2)
        @test issorted([sum(abs2, o) for o in r.offsets])
        # aliasing on small periodic axes is rejected; closed axes are fine
        @test_throws ArgumentError relation(Moore(1), Lattice((2, 10)))
        @test length(relation(Moore(1), Lattice((2, 10); boundary = Closed()))) == 8
        @test length(relation(Ball(1.5), l2)) == 8
        @test length(relation(Stencil([(1, 0), (0, 1)]), l2)) == 2
    end
end

@testitem "rng" setup = [CP_corepotts] tags = [:corepotts, :core] begin
    @testset "rng" begin
        # (seed, replica) tuples never collide (the XOR-key bug)
        @test RNGKey(1, 2) != RNGKey(2, 1)
        @test RNGKey(1, 0) != RNGKey(0, 1)
        @test RNGKey(7) == RNGKey(7, 0, 0)
        for T in (Float32, Float64)
            @test 0 < uniform(T, 0x00000000) < uniform(T, typemax(UInt32)) < 1
        end
        @test extrema(bounded(rand(UInt32), 6) for _ in 1:10_000) == (0, 5)
        @test stream_id("a.b") == stream_id(:var"a.b") != stream_id("a.c")
        k = RNGKey(3)
        s = UInt32(1)
        @test draw(k, 1, 2, s) == draw(k, 1, 2, s) != draw(k, 1, 3, s)
        @test draw(k, 1, 2, s) != draw(k, 1, 2, s + 0x1) != draw(k, 1, 2, s, 1)
        xs = [uniform(Float64, draw(k, 0, i, UInt32(7))[1]) for i in 1:100_000]
        @test length(xs) >= required_n(1 / sqrt(12), 0.005; alpha = 1.0e-3, power = 0.9)
        @test stat_accept(xs; mu0 = 0.5, margin = 0.005, alpha = 1.0e-3).pass
        @test !stat_accept(xs .+ 0.01; mu0 = 0.5, margin = 0.005, alpha = 1.0e-3).pass # negative control
        v_xs = (xs .- 0.5) .^ 2
        @test stat_accept(v_xs; mu0 = 1 / 12, margin = 0.002, alpha = 1.0e-3).pass
    end
end

@testitem "rng: Philox4x32-10 KAT and address keying (D6)" setup = [CP_corepotts] tags = [:corepotts, :core] begin
@testset "rng: Philox4x32-10 KAT and address keying (D6)" begin
    # Official Random123 (Salmon et al. 2011) Philox4x32-10 known-answer vectors
    kat_vectors = (
        ((0x00000000, 0x00000000, 0x00000000, 0x00000000), (0x00000000, 0x00000000),
         (0x6627e8d5, 0xe169c58d, 0xbc57ac4c, 0x9b00dbd8)),
        ((0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff), (0xffffffff, 0xffffffff),
         (0x408f276d, 0x41c83b0e, 0xa20bc7c6, 0x6d5451fd)),
        ((0x243f6a88, 0x85a308d3, 0x13198a2e, 0x03707344), (0xa4093822, 0x299f31d0),
         (0xd16cfe09, 0x94fdcceb, 0x5001e420, 0x24126ea1)),
    )
    for (ctr, key, expected) in kat_vectors
        @test CorePotts.philox4x32(ctr..., key...) == expected
    end

    # Independent re-implementation of Philox4x32-10, RNGKey, stream_id, and draw address keying
    function ref_philox4x32(c0::UInt32, c1::UInt32, c2::UInt32, c3::UInt32, k0::UInt32, k1::UInt32)
        M0 = UInt64(0xD2511F53); M1 = UInt64(0xCD9E8D57)
        W0 = UInt32(0x9E3779B9); W1 = UInt32(0xBB67AE85)
        for _ in 1:10
            p0 = M0 * UInt64(c0)
            p1 = M1 * UInt64(c2)
            hi0 = UInt32(p0 >> 32); lo0 = UInt32(p0 & 0xffffffff)
            hi1 = UInt32(p1 >> 32); lo1 = UInt32(p1 & 0xffffffff)
            c0, c1, c2, c3 = xor(hi1, c1, k0), lo1, xor(hi0, c3, k1), lo0
            k0 = (k0 + W0) % UInt32
            k1 = (k1 + W1) % UInt32
        end
        return (c0, c1, c2, c3)
    end
    function ref_key(seed::Integer, replica::Integer = 0, repeat::Integer = 0)
        s = UInt64(seed)
        r0, r1, _, _ = ref_philox4x32(UInt32(s & 0xffffffff), UInt32(s >> 32),
            UInt32(replica), UInt32(repeat), 0x43505331, 0x6b657931)
        return (r0, r1)
    end
    function ref_draw(k0::UInt32, k1::UInt32, mcs::Integer, entity::Integer, stream::UInt32, local_idx::Integer = 0)
        e = UInt64(entity)
        hi = UInt32(e >> 32)
        lo = UInt32(e & 0xffffffff)
        eff_k0 = hi == 0 ? k0 : xor(k0, (hi * UInt32(0xBB67AE85)) % UInt32)
        return ref_philox4x32(UInt32(mcs & 0xffffffff), lo, stream, UInt32(local_idx & 0xffffffff), eff_k0, k1)
    end
    function ref_fnv1a(s::AbstractString)
        h = UInt32(0x811c9dc5)
        for b in codeunits(s)
            h = (xor(h, UInt32(b)) * UInt32(0x01000193)) % UInt32
        end
        return h
    end

    for (ctr, key, expected) in kat_vectors
        @test ref_philox4x32(ctr..., key...) == expected
    end
    for name in ("CorePotts.proposal", "CorePotts.sequential_target", "CorePotts.color_order",
                 "CorePotts.block", "CorePotts.boundary_site", "custom.stream")
        @test stream_id(name) == ref_fnv1a(name)
    end
    for seed in (0, 1, 7, 0x0123456789abcdef), replica in (0, 3), rep in (0, 5)
        rk = RNGKey(seed, replica, rep)
        ek = ref_key(seed, replica, rep)
        @test (rk.k0, rk.k1) == ek
        for mcs in (0, 1, 42), ent in (UInt64(0), UInt64(17), UInt64(1) << 32, (UInt64(9) << 32) | 0xdeadbeef),
            st in (CorePotts.STREAM_PROPOSAL, CorePotts.STREAM_BLOCK), loc in (0, 1, 13)
            @test draw(rk, mcs, ent, st, loc) == ref_draw(ek..., mcs, ent, st, loc)
        end
    end
end
end

@testitem "rng: 64-bit entities do not wrap" setup = [CP_corepotts] tags = [:corepotts, :core] begin
    @testset "rng: 64-bit entities do not wrap" begin
        k = RNGKey(3)
        s = UInt32(7)
        philox = CorePotts.philox4x32
        # below 2³² the entity draws exactly as the 32-bit counter word did
        for e in (0, 1, 12345, typemax(UInt32) - 1, typemax(UInt32))
            @test draw(k, 9, e, s, 2) == philox(UInt32(9), UInt32(e), s, UInt32(2), k.k0, k.k1)
        end
        @test draw(k, 1, Int32(5), s) == draw(k, 1, 5, s) == draw(k, 1, UInt64(5), s)
        # cell entities: the old 32-bit value below 2²⁴, no aliasing at or above it
        old_cell(id, g) = (UInt32(id) << 8) | (UInt32(g) & 0xff)
        for id in (1, 2, 1000, 2^24 - 1), g in (1, 2, 255, 256, 300)
            @test cell_entity(id, g) == old_cell(id, g)
        end
        @test cell_entity(Int32(7), Int32(3)) == cell_entity(7, 3)
        for id in (5, 2^20 + 3), m in (1, 2, 255)
            @test cell_entity(id + m * 2^24, 1) != cell_entity(id, 1)
            @test draw(k, 4, cell_entity(id + m * 2^24, 1), s) != draw(k, 4, cell_entity(id, 1), s)
        end
        # site indices at or above 2³²
        for i in (0, 7, 2^31)
            @test draw(k, 4, i + 2^32, s) != draw(k, 4, i, s)
            @test draw(k, 4, i + 2^32, s) != draw(k, 4, i + 2^33, s)
        end
        # high-word entities are still uniform and independent of their low-word partners
        hi = [uniform(Float64, draw(k, 0, i + (i << 32), s)[1]) for i in 1:100_000]
        lo = [uniform(Float64, draw(k, 0, i, s)[1]) for i in 1:100_000]
        @test stat_accept(hi; mu0 = 0.5, margin = 0.005, alpha = 1.0e-3).pass
        @test !stat_accept(hi .- 0.01; mu0 = 0.5, margin = 0.005, alpha = 1.0e-3).pass # negative control
        @test stat_accept((hi .- 0.5) .^ 2; mu0 = 1 / 12, margin = 0.002, alpha = 1.0e-3).pass
        @test abs(cor(hi, lo)) < 0.01
    end
end

@testitem "rng: two-word site picks (D-247)" setup = [CP_corepotts] tags = [:corepotts, :core] begin
    @testset "rng: two-word site picks (D-247)" begin
        rng = Random.Xoshiro(5)
        b64 = CorePotts.bounded64
        # exactly ⌊x·n / 2⁶⁴⌋ for the 64-bit x = hi·2³² + lo, always in 0:n-1
        for _ in 1:2000
            hi, lo, n = rand(rng, UInt32), rand(rng, UInt32), rand(rng, 1:(2^40))
            @test b64(hi, lo, n) == Int(div(((BigInt(hi) << 32) + lo) * n, BigInt(2)^64))
            @test 0 <= b64(hi, lo, n) < n
        end
        @test b64(typemax(UInt32), typemax(UInt32), 10^12) == 10^12 - 1
        # up to 2³² sites it refines the one-word pick: the same site, or the next one when the
        # low word carries (probability about n / 2³³), so small runs barely change
        for _ in 1:2000
            hi, lo, n = rand(rng, UInt32), rand(rng, UInt32), rand(rng, 1:(2^32))
            @test b64(hi, lo, n) - bounded(hi, n) in (0, 1)
        end
        @test b64(UInt32(0), UInt32(0), 7) == 0
        # the bias it removes: at n = 10⁹ the one-word map gives 2³² - 4n sites five inputs and
        # the rest four, so those sites are drawn 34.3 % of the time instead of their 29.5 %
        n = 10^9
        five(t) = cld((t + 1) * 2^32, n) - cld(t * 2^32, n) == 5
        share = (2^32 - 4n) / n
        one = mean(_ -> five(bounded(rand(rng, UInt32), n)), 1:400_000)
        two = mean(_ -> five(b64(rand(rng, UInt32), rand(rng, UInt32), n)), 1:400_000)
        @test abs(one - 5 * (2^32 - 4n) / 2^32) < 0.003          # negative control: the bias is real
        @test abs(two - share) < 0.003                           # and gone with two words
        @test !CorePotts._two_word_pick(2^24) && CorePotts._two_word_pick(2^24 + 1)
        # end to end, forced on a small lattice: trackers and the tracked ΔH stay exact
        σ, kinds = blocks((30, 30), 5)
        lat = Lattice((30, 30))
        on = CPMFunction(gg_delta_H; temperature = gg_temperature, track = CorePotts.TrackDeltaH{Float64}())
        prob = PottsProblem(on, initial_state(σ, kinds), lat, (0, 15), gg_params())
        H(u) = total_H(u, lat, prob.contact, gg_params())
        for alg in (SequentialCPM(), SequentialCPM(; skip_interior = true))
            base = [solve(remake(prob; seed), alg) for seed in 1:12]
            CorePotts._FORCE_TWO_WORD_PICK[] = true
            wide = try
                [solve(remake(prob; seed), alg) for seed in 1:12]
            finally
                CorePotts._FORCE_TWO_WORD_PICK[] = false
            end
            for sol in wide[1:4]
                u0, u = sol.u[1], sol.u[end]
                @test sol.stats.accepted_ΔH == H(u) - H(u0) && abs(H(u) - H(u0)) > 100
                vol = zeros(Int32, length(kinds))
                foreach(s -> s > 0 && (vol[s] += 1), u.σ)
                @test vol == u.cell.volume
            end
            base_acc = Float64[s.stats.accepted for s in base]
            wide_acc = Float64[s.stats.accepted for s in wide]
            @test stat_accept(wide_acc .- base_acc; mu0 = 0.0, margin = 0.05 * mean(base_acc), alpha = 1.0e-3).pass
            # negative control: a colder temperature T = 5.0 drops accepted copies outside margin
            cold = [solve(remake(prob; seed, p = merge(gg_params(), (; T = 5.0))), alg).stats.accepted for seed in 1:12]
            @test !stat_accept(Float64.(cold) .- base_acc; mu0 = 0.0, margin = 0.05 * mean(base_acc), alpha = 1.0e-3).pass
            @test solve(remake(prob; seed = 1), alg).u[end].σ == base[1].u[end].σ  # unforced: unchanged
        end
        # the hook reaches the caller's choice of regime, which is the sweep context's type:
        # marked contexts take two words, others one, and each method is its map
        @test CorePotts._pick_regime(CorePotts._with_two_word_pick((; mcs = 0))) === CorePotts.TwoWordPick() &&
              CorePotts._pick_regime((; mcs = 0)) === nothing
        # review (MEDIUM): the key is not an identifier, so a relation named `pick` neither
        # selects a regime nor is shadowed by one; it ran before D-247 and still runs
        @test CorePotts._pick_regime((; mcs = 0, pick = 1)) === nothing
        @test CorePotts._with_two_word_pick((; pick = 1)).pick === 1
        let lat = Lattice((30, 30)), (σ, kinds) = blocks((30, 30), 5)
            f = CPMFunction(gg_delta_H; temperature = gg_temperature)
            prob = PottsProblem(f, initial_state(σ, kinds), lat, (0, 3), gg_params(); relations = (; pick = Moore(1)))
            for alg in (SequentialCPM(), SequentialCPM(; skip_interior = true)), force in (false, true)
                CorePotts._FORCE_TWO_WORD_PICK[] = force
                sol = try
                    solve(prob, alg)
                finally
                    CorePotts._FORCE_TWO_WORD_PICK[] = false
                end
                @test SciMLBase.successful_retcode(sol)
            end
            # `mcs` is the sweep's own context field (D-188), so a relation may not take it
            @test_throws r"relation names .*`mcs`.* are reserved" PottsProblem(f, initial_state(σ, kinds), lat, (0, 3),
                gg_params(); relations = (; mcs = Moore(1)))
        end
        for (hi, lo, n) in ((0xffffffff, 0xffffffff, 10^9), (0x89abcdef, 0x01234567, 2^24 + 3), (0x00000001, 0x80000000, 7))
            @test CorePotts.site_pick(nothing, hi, lo, n) == CorePotts.bounded(hi, n)
            @test CorePotts.site_pick(CorePotts.TwoWordPick(), hi, lo, n) == CorePotts.bounded64(hi, lo, n)
            @test CorePotts._boundary_pick(nothing, hi, nothing, 0, 1, n) == CorePotts.bounded(hi, n)
        end
        CorePotts._FORCE_TWO_WORD_PICK[] = true
        @test CorePotts._two_word_pick(10)
        CorePotts._FORCE_TWO_WORD_PICK[] = false
        @test !CorePotts._two_word_pick(10)
        # the wiring, exactly, unforced above 2²⁴ sites: on 4100² every site borders the other
        # of two interleaved cells, a constraint that refuses every copy records each
        # attempt's target, and σ never changes, so the targets replay test-side from `draw`
        L = 4100
        big = Lattice((L, L))
        n = L * L
        @test n > CorePotts.PICK_ONE_WORD_MAX
        K = 300_000
        rec, cnt = zeros(Int, K), Ref(0)
        record(st, p, prop, ctx) = (cnt[] < K && (cnt[] += 1; rec[cnt[]] = prop.target); false)
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = record)
        σb = Int32[1 + (i + j) % 2 for i in 1:L, j in 1:L]
        bprob = PottsProblem(f, initial_state(σb, Int32[1, 2]), big, (0, 1), gg_params(); seed = 2)
        key = RNGKey(2)
        # SequentialCPM: attempt a's target from its draw's first and fourth words
        solve(bprob, SequentialCPM())
        @test cnt[] == K
        seq(m, a, wide) = (w = draw(key, m, a, CorePotts.STREAM_SEQUENTIAL_TARGET);
            (wide ? CorePotts.bounded64(w[1], w[4], n) : bounded(w[1], n)) + 1)
        ms = filter(m -> all(a -> rec[a] == seq(m, a, true), 1:K), 0:1)       # the MCS index used
        @test length(ms) == 1
        m = only(ms)
        @test count(a -> rec[a] != seq(m, a, false), 1:K) > 100       # one word differs (~0.2 %)
        # the boundary sweep: every site is in B (no skips), pick j from draw j's second word
        # and local index 1's first word, over B's list
        cnt[] = 0
        integ = init(bprob, SequentialCPM(; skip_interior = true); save_start = false)
        step!(integ)
        @test cnt[] == K && integ.cache.n == n
        list = integ.cache.list
        bnd(j, wide) = (w = draw(key, m, j, CorePotts.STREAM_BOUNDARY_SITE);
            lo = draw(key, m, j, CorePotts.STREAM_BOUNDARY_SITE, 1)[1];
            Int(list[(wide ? CorePotts.bounded64(w[2], lo, n) : bounded(w[2], n)) + 1]))
        @test all(j -> rec[j] == bnd(j, true), 1:K)
        @test count(j -> rec[j] != bnd(j, false), 1:K) > 100
    end
end

@testitem "block layout keeps concurrent sub-regions apart" setup = [CP_corepotts] tags = [:corepotts, :core] begin
    @testset "block layout keeps concurrent sub-regions apart" begin
        # in every phase, sites of two blocks' active sub-regions are farther apart than the
        # footprint the layout was built for, (k - 1)·b (periodic minimum image)
        for (dims, bnd, b, k) in (((12, 12), Periodic(), 1, 4), ((13, 11), Periodic(), 1, 3),
                ((13, 7), Periodic(), 2, 2), ((10, 9), Closed(), 1, 3), ((7, 5, 6), Periodic(), 1, 2),
                ((40, 17), Periodic(), 1, 8), ((31, 29), Periodic(), 2, 3))
            lat = Lattice(dims; boundary = bnd)
            l = CorePotts.BlockLayout(dims, b, k)
            N = length(dims)
            for ph in 1:(k^N)
                regs = [CorePotts.block_region(l, blk, ph) for blk in 1:CorePotts.nblocks(l)]
                sites = [[lo .+ Tuple(c) for c in CartesianIndices(side)] for (lo, side) in regs]
                for i in eachindex(sites), j in (i + 1):length(sites), x in sites[i], y in sites[j]
                    dist = maximum(ntuple(N) do d
                        δ = abs(x[d] - y[d])
                        lat.periodic[d] ? min(δ, dims[d] - δ) : δ
                    end)
                    @test dist > (k - 1) * b
                end
            end
        end
    end
end

@testitem "ΔH equals brute-force energy difference (N-D, spec)" setup = [CP_corepotts] tags = [:corepotts, :core] begin
    @testset "ΔH equals brute-force energy difference ($N-D, $spec)" for (N, dims, spec) in (
            (2, (24, 24), Moore(1)), (2, (24, 21), NeighborOrder(3)),
            (3, (12, 12, 12), Moore(1)), (3, (10, 10, 10), NeighborOrder(2)))
        σ, kinds = blocks(dims, 3)
        lat = Lattice(dims)
        st = initial_state(σ, kinds)
        p = merge(gg_params(), (; V0 = 20.0))
        ctx = (; lattice = lat, proposal = relation(VonNeumann(1), lat),
            contact = relation(spec, lat))
        checked = 0
        for t in 1:nsites(lat), dir in 1:length(ctx.proposal)
            x = coordinates(lat, t)
            inside, y = shift(lat, x, ctx.proposal.offsets[dir])
            s = linear_index(lat, y)
            a, b = st.σ[t], st.σ[s]
            (inside && a != b) || continue
            prop = Proposal(t, s, x, dir, a, b)
            before = total_H(st, lat, ctx.contact, p)
            dH = gg_delta_H(st, p, prop, ctx)
            after_state = deepcopy(st)
            after_state.σ[t] = b
            CorePotts.commit_volume!(after_state, p, prop, ctx)
            @test dH ≈ total_H(after_state, lat, ctx.contact, p) - before atol = 1e-9
            checked += 1
            checked >= 300 && break
        end
        @test checked >= 100
    end
end

@testitem "ΔH with surface, weighted contact (length(dims)-D, cspec, sspec)" setup = [CP_corepotts] tags = [:corepotts, :core] begin
    @testset "ΔH with surface, weighted contact ($(length(dims))-D, $cspec, $sspec)" for (
            dims, cspec, sspec) in (
            ((20, 20), Moore(1), VonNeumann(1)),
            ((20, 18), Weighted(NeighborOrder(2), invdist), Moore(1)),
            ((10, 10, 10), Weighted(Moore(1), invdist), Weighted(NeighborOrder(2), invdist)),
            ((12, 12, 11), VonNeumann(1), Moore(1)))
        σ, kinds = blocks(dims, 3)
        lat = Lattice(dims; boundary = length(dims) == 2 ? Periodic() : (Periodic(), Closed(), Periodic()))
        st = surface_state(σ, kinds, lat, sspec)
        p = gs_params()
        ctx = (; lattice = lat, proposal = relation(VonNeumann(1), lat),
            contact = relation(cspec, lat), surface = relation(sspec, lat))
        @test st.cell.surface ≈ brute_surface(st.σ, lat, ctx.surface, length(kinds))
        st32 = surface_state(σ, kinds, lat, sspec; T = Float32)
        checked = 0
        for t in 1:7:nsites(lat), dir in 1:length(ctx.proposal)
            inside, y = shift(lat, coordinates(lat, t), ctx.proposal.offsets[dir])
            s = linear_index(lat, y)
            (inside && st.σ[t] != st.σ[s]) || continue
            prop = Proposal(t, s, coordinates(lat, t), dir, st.σ[t], st.σ[s])
            before = total_H_surface(st, lat, ctx, p)
            dH = gs_delta_H(st, p, prop, ctx)
            after = deepcopy(st)
            after.σ[t] = prop.new
            gs_commit!(after, p, prop, ctx)          # after the write, as the algorithms do
            @test dH ≈ total_H_surface(after, lat, ctx, p) - before atol = 1e-6
            @test after.cell.surface ≈ brute_surface(after.σ, lat, ctx.surface, length(kinds))
            @test gs_delta_H(st32, p, prop, ctx) ≈ dH rtol = 1e-5 atol = 1e-2   # Float32 tracker
            checked += 1
            checked >= 150 && break
        end
        @test checked >= 50
    end
end

@testitem "surface trackers survive a run (nameof(typeof(alg)))" setup = [CP_corepotts] tags = [:corepotts, :core] begin
    @testset "surface trackers survive a run ($(nameof(typeof(alg))))" for alg in (
            SequentialCPM(), CheckerboardCPM())
        σ, kinds = blocks((30, 30), 5)
        lat = Lattice((30, 30))
        sspec = Weighted(Moore(1), invdist)
        sprob = PottsProblem(GS, surface_state(σ, kinds, lat, sspec), lat, (0, 30), gs_params();
            relations = (; surface = sspec))
        sol = solve(sprob, alg)
        @test sol.retcode == ReturnCode.Success
        u = sol.u[end]
        @test u.σ != σ
        @test u.cell.surface ≈ brute_surface(u.σ, lat, relation(sspec, lat), length(kinds)) rtol = 1e-12
        bad = PottsProblem(GS, sprob.u0, lat, (0, 1), gs_params();
            relations = (; surface = Moore(1; include_self = true)))
        @test_throws ArgumentError init(bad, alg)
    end
end

@testitem "nameof(typeof(alg)) with typeof(alg.proposal)" setup = [CP_corepotts] tags = [:corepotts, :core] begin
    for alg in (SequentialCPM(), CheckerboardCPM(), CheckerboardCPM(; proposal = Moore(1)))
        @testset "$(nameof(typeof(alg))) with $(typeof(alg.proposal))" begin
            sol = solve(prob, alg; saveat = [5, 10])
            @test sol.retcode == ReturnCode.Success
            @test sol.t == [0, 5, 10, 20]
            last_state = sol.u[end]
            @test last_state.σ != σ0
            vol = zeros(Int32, length(kinds0))
            for s in last_state.σ
                s > 0 && (vol[s] += 1)
            end
            @test vol == last_state.cell.volume            # tracker == recomputation
            @test solve(prob, alg).u[end].σ == last_state.σ             # same seed, same run
            @test solve(remake(prob; seed = 8), alg).u[end].σ != last_state.σ
            @test sol(10).σ == sol.u[3].σ
            @test sol.u[1].σ == σ0 && sol.u[2].σ != sol.u[end].σ     # snapshots, not aliases
            @test sol.u[1].σ !== sol.u[end].σ
            @test_throws ArgumentError sol(11)
            @test sol.stats.attempts == 20 * nsites(lat)
        end
    end
end

@testitem "warm step allocation and recompilation" setup = [CP_corepotts] tags = [:corepotts, :core, :timing] begin
    @testset "warm step allocation and recompilation" begin
        integ = init(prob, SequentialCPM(); save_start = false)
        step!(integ)
        @test @allocated(step!(integ)) == 0
        integ = init(prob, CheckerboardCPM(); save_start = false)
        step!(integ); step!(integ)
        @test @allocated(step!(integ)) == 0                # the host executor (PG-13)
        # (a `p` other than `prob.p`: the first remake that changes the parameters compiles the
        # remake hooks, once for every problem type since TS1c)
        solve(remake(prob; p = merge(gg_params(), (; T = 5.0)), seed = 1), CheckerboardCPM())
        # (and `solve` with `SequentialCPM`, which the testsets before this one did in the old
        # single-process run; TS1b: this item runs alone too)
        solve(prob, SequentialCPM())
        cold = merge(gg_params(), (; T = 4.0, λ = 2.0))
        stats = @timed solve(remake(prob; p = cold, seed = 2), CheckerboardCPM())
        @test stats.compile_time == 0
        stats = @timed solve(remake(prob; p = cold, seed = 3), SequentialCPM())
        @test stats.compile_time == 0
    end
end

@testitem "non-finite ΔH fails the solve" setup = [CP_corepotts] tags = [:corepotts, :core] begin
    @testset "non-finite ΔH fails the solve" begin
        bad = CPMFunction((st, p, prop, ctx) -> NaN; temperature = gg_temperature)
        bprob = PottsProblem(bad, initial_state(σ0, kinds0), lat, (0, 3), gg_params())
        @test solve(bprob, SequentialCPM()).retcode == ReturnCode.Failure
        @test (@test_logs (:warn, r"energy change was not finite") solve(bprob, CheckerboardCPM())).retcode == ReturnCode.Failure
    end
end

@testitem "checkerboard and sequential sort alike" setup = [CP_corepotts] tags = [:corepotts, :core] begin
    @testset "checkerboard and sequential sort alike" begin
        # differential adhesion: heterotypic fraction falls under both dynamics
        function hetero(st)
            u = c = 0
            for i in 1:nsites(lat), off in relation(Moore(1), lat).offsets
                inside, y = shift(lat, coordinates(lat, i), off)
                a, b = st.σ[i], st.σ[linear_index(lat, y)]
                (a == b || a == 0 || b == 0) && continue
                c += 1; u += st.cell.kind[a] != st.cell.kind[b]
            end
            return u / c
        end
        σr = zeros(Int32, 36, 36)
        for i in 0:5, j in 0:5
            σr[(6i + 1):(6i + 6), (6j + 1):(6j + 6)] .= 6i + j + 1
        end
        kr = Int32[isodd(i + (i ÷ 6)) ? 1 : 2 for i in 1:36]
        sprob = PottsProblem(GG, initial_state(σr, kr), lat, (0, 60),
            merge(gg_params(), (; V0 = 36.0)))
        h0 = hetero(initial_state(σr, kr))
        hs = [hetero(solve(remake(sprob; seed), SequentialCPM()).u[end]) for seed in 1:4]
        hc = [hetero(solve(remake(sprob; seed), CheckerboardCPM()).u[end]) for seed in 1:4]
        @test mean(hs) < h0 - 0.05
        @test mean(hc) < h0 - 0.05
    end
end

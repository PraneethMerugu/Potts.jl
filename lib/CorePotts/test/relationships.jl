# Relationships: links, link energies, host rules, lifecycle interaction (ROADMAP M2.9).

function brute_link_energy(σ, lat, cell, E)
    H = 0.0
    for a in axes(cell.links, 2), k in axes(cell.links, 1)
        b = cell.links[k, a]
        (b == 0 || b < a) && continue                          # each link once
        μa, _ = brute_geometry(σ, lat, a); μb, _ = brute_geometry(σ, lat, b)
        δ = map((x, y, n) -> (d = x - y; d - n * round(d / n)), μa, μb, lat.dims)
        H += E(a, b, k, sqrt(sum(abs2, δ)))
    end
    return H
end

@testset "relationships" begin
    @testset "link bookkeeping" begin
        cell = empty_links(2, 4; rest = Float64)
        @test add_link!(cell, 1, 2; rest = 5.0)
        @test !add_link!(cell, 2, 1)                            # already linked
        @test add_link!(cell, 1, 3; rest = 7.0)
        @test !add_link!(cell, 1, 4)                            # row of 1 is full
        @test linked(cell, 2, 1) && linked(cell, 3, 1) && !linked(cell, 2, 3)
        @test link_count(cell, 1) == 2
        @test cell.link_rest[link_slot(cell, 3, 1), 3] == 7.0
        @test remove_link!(cell, 2, 1) && !linked(cell, 1, 2)
        @test cell.link_rest[link_slot(cell, 1, 3), 1] == 7.0 && link_count(cell, 1) == 1
        remove_incident!(cell, 3)
        @test all(iszero, cell.links)
    end

    @testset "link_delta equals the brute-force energy change" begin
        σ, kinds = blocks((30, 30), 5; gap = 0)
        σ = circshift(σ, (2, 2))
        lat = Lattice((30, 30))
        n = length(kinds)
        cell = merge(init_moments(σ, lat, n), empty_links(4, n; rest = Float64))
        for (a, b) in ((1, 2), (1, 6), (2, 3), (7, 8), (8, 13), (13, 1))
            add_link!(cell, a, b; rest = 4.0 + a)
        end
        st = initial_state(σ, kinds; cell)
        E(a, b, k, d) = 0.7 * (d - st.cell.link_rest[k, a])^2
        ctx = (; lattice = lat, proposal = relation(VonNeumann(1), lat))
        checked = 0; pair_checked = 0
        for t in 1:nsites(lat), dir in 1:4
            inside, y = shift(lat, coordinates(lat, t), ctx.proposal.offsets[dir])
            s = linear_index(lat, y)
            a, b = st.σ[t], st.σ[s]
            (a != b && (link_count(st.cell, a) > 0 || link_count(st.cell, b) > 0)) || continue
            prop = Proposal(t, s, coordinates(lat, t), dir, a, b)
            before = brute_link_energy(st.σ, lat, st.cell, E)
            dH = link_delta(Float64, st.cell, ctx, prop, E)
            after = deepcopy(st); after.σ[t] = b
            commit_volume!(after, nothing, prop, ctx); commit_moments!(after.cell, lat, prop)
            @test dH ≈ brute_link_energy(after.σ, lat, after.cell, E) - before atol = 1e-9
            checked += 1; pair_checked += linked(st.cell, a, b)
            checked >= 200 && break
        end
        @test checked >= 100 && pair_checked >= 5
    end

    @testset "a spring pulls linked cells to its rest length" begin
        lat = Lattice((60, 30))
        σ = zeros(Int32, 60, 30); σ[5:10, 12:17] .= 1; σ[40:45, 12:17] .= 2
        cell = merge(init_moments(σ, lat, 2), empty_links(1, 2; rest = Float64))
        add_link!(cell, 1, 2; rest = 12.0)
        function dH(st, p, prop, ctx)
            J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
            E(v, c) = p.λ * (v - p.V0)^2
            S(a, b, k, d) = p.k * (d - st.cell.link_rest[k, a])^2
            return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) +
                   link_delta(Float64, st.cell, ctx, prop, S)
        end
        commit!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx); commit_moments!(st.cell, ctx.lattice, prop))
        f = CPMFunction(dH; commit!, temperature = gg_temperature,
            claims = (st, p, prop, ctx) -> link_claims(st.cell, prop, Val(1)))
        @test link_claims(cell, Proposal(1, 1, (1, 1), 1, Int32(1), Int32(0)), Val(1)) == (Int32(2), Int32(0))
        d0 = centroid_distance(Float64, initial_state(σ, [1, 1]; cell).cell, lat, 1, 2)
        ds = map(1:6) do seed
            u = solve(PottsProblem(f, initial_state(σ, [1, 1]; cell), lat, (0, 1000),
                merge(gg_params(), (; V0 = 36.0, k = 2.0)); seed), CheckerboardCPM()).u[end]
            centroid_distance(Float64, u.cell, lat, 1, 2)
        end
        @test d0 ≈ 25.0 atol = 5                             # periodic min image: 35 → 25
        @test abs(mean(ds) - 12.0) < 2.5            # ≈13 at equilibrium (entropic stretch)
    end

    @testset "host rule links touching cells; lifecycle policies" begin
        σ, kinds = blocks((30, 30), 5; gap = 0)
        lat = Lattice((30, 30))
        n = length(kinds)
        vn = relation(VonNeumann(1), lat)
        function link_touching!(cell, st, p, ctx, mcs)
            g = contact_graph(st.σ, ctx.lattice, vn, length(cell.kind))
            for a in eachindex(cell.kind), b in neighbors(g, a)
                a < b && add_link!(cell, a, b; age = Int32(mcs))
            end
        end
        remove_first(st, p, ctx, key, mcs, c) = mcs == 1 && c == 1 ? EVENT_REMOVE :
                                                mcs == 1 && c == 2 ? EVENT_DIVIDE : EVENT_NONE
        st = with_capacity(initial_state(σ, kinds;
            cell = merge(init_moments(σ, lat, n), empty_links(8, n; age = Int32))), n + 4)
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = frozen_dynamics,
            phases = Phases(after_mcs = (HostPhase(link_touching!; every = 100),)),
            lifecycle = Lifecycle(remove_first))
        u = solve(PottsProblem(f, st, lat, (0, 2), gg_params()), SequentialCPM()).u[end]
        g0 = contact_graph(σ, lat, vn, n)
        for a in 3:n, b in neighbors(g0, a)                    # untouched pairs stay linked
            (b == 1 || b == 2) && continue
            @test linked(u.cell, a, b)
        end
        @test link_count(u.cell, 1) == 0                        # removed: incident links dropped
        @test all(b -> !linked(u.cell, b, 1), 1:(n + 4))
        daughter = findfirst(c -> c > n && u.cell.volume[c] > 0, 1:(n + 4))
        @test daughter !== nothing && link_count(u.cell, daughter) == 0
        @test link_count(u.cell, 2) > 0                         # the parent keeps its links
    end

    # -----------------------------------------------------------------------------------
    # Several named relationships (P6.0b): one adjacency per name, payloads per variable

    @testset "named link stores are independent" begin
        cell = merge(empty_links(2, 4, :bond; rest = Float64), empty_links(1, 4, :tether; len = Float64))
        @test keys(cell) == (:links__bond, :link_rest, :links__tether, :link_len)
        @test CorePotts.adjacency_name(:bond) === :links__bond
        B = (; links = cell.links__bond, link_rest = cell.link_rest)
        Tt = (; links = cell.links__tether, link_len = cell.link_len)
        @test add_link!(B, 1, 2; rest = 5.0) && add_link!(Tt, 1, 2; len = 9.0)    # same pair, both stores
        @test add_link!(B, 1, 3; rest = 7.0)
        @test !add_link!(Tt, 1, 3; len = 1.0)                                      # tether row of 1 full
        @test link_count(B, 1) == 2 && link_count(Tt, 1) == 1
        @test CorePotts.link_store(cell, :tether).links === cell.links__tether
        @test remove_link!(B, 1, 2) && !linked(B, 1, 2) && linked(Tt, 1, 2)       # removal is per store
        @test cell.link_len[link_slot(Tt, 1, 2), 1] == 9.0
        # a new link's payloads not given start at zero (a slot's old value is not inherited)
        @test add_link!(B, 1, 4)
        @test cell.link_rest[link_slot(B, 1, 4), 1] == 0.0
    end

    @testset "link_delta per store: two relationships sum exactly" begin
        σ, kinds = blocks((30, 30), 5; gap = 0)
        σ = circshift(σ, (2, 2))
        lat = Lattice((30, 30))
        n = length(kinds)
        cell = merge(init_moments(σ, lat, n), empty_links(3, n, :bond; rest = Float64),
            empty_links(3, n, :tether; len = Float64))
        B = (; links = cell.links__bond, link_rest = cell.link_rest)
        Tt = (; links = cell.links__tether, link_len = cell.link_len)
        for (a, b) in ((1, 2), (2, 3), (7, 8), (13, 1))
            add_link!(B, a, b; rest = 4.0 + a)
        end
        for (a, b) in ((2, 7), (1, 6), (8, 13), (3, 4))                          # 1, 2, 3, 7, 8, 13 in both
            add_link!(Tt, a, b; len = 9.0 - a / 4)
        end
        st = initial_state(σ, kinds; cell)
        E1(a, b, k, d) = 0.7 * (d - st.cell.link_rest[k, a])^2
        E2(a, b, k, d) = 1.3 * (d - st.cell.link_len[k, a])^2
        brute(u) = brute_link_energy(u.σ, lat, CorePotts.link_store(u.cell, :bond), E1) +
                   brute_link_energy(u.σ, lat, CorePotts.link_store(u.cell, :tether), E2)
        ctx = (; lattice = lat, proposal = relation(VonNeumann(1), lat))
        checked = 0; both = 0; one_store_off = 0
        for t in 1:nsites(lat), dir in 1:4
            inside, y = shift(lat, coordinates(lat, t), ctx.proposal.offsets[dir])
            s = linear_index(lat, y)
            a, b = st.σ[t], st.σ[s]
            a != b || continue
            (link_count(B, a) + link_count(B, b) > 0 && link_count(Tt, a) + link_count(Tt, b) > 0) || continue
            prop = Proposal(t, s, coordinates(lat, t), dir, a, b)
            dB = link_delta(Float64, st.cell, CorePotts.link_store(st.cell, :bond), ctx, prop, E1)
            dT = link_delta(Float64, st.cell, CorePotts.link_store(st.cell, :tether), ctx, prop, E2)
            after = deepcopy(st); after.σ[t] = b
            commit_volume!(after, nothing, prop, ctx); commit_moments!(after.cell, lat, prop)
            truth = brute(after) - brute(st)
            @test dB + dT ≈ truth atol = 1e-9
            one_store_off += !isapprox(dB, truth; atol = 1e-6)                   # negative control
            checked += 1; both += linked(B, a, b) || linked(Tt, a, b)
            checked >= 200 && break
        end
        @test checked >= 100 && both >= 5 && one_store_off >= checked ÷ 2
    end

    @testset "shared read claims: a chain of two relationships relaxes under checkerboard" begin
        lat = Lattice((64, 30))
        σ = zeros(Int32, 64, 30); σ[5:10, 12:17] .= 1; σ[30:35, 12:17] .= 2; σ[55:60, 12:17] .= 3
        cell = merge(init_moments(σ, lat, 3), empty_links(1, 3, :bond; rest = Float64),
            empty_links(1, 3, :tether; len = Float64))
        add_link!((; links = cell.links__bond, link_rest = cell.link_rest), 1, 2; rest = 12.0)
        add_link!((; links = cell.links__tether, link_len = cell.link_len), 2, 3; len = 18.0)
        function dH(st, p, prop, ctx)
            J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
            E(v, c) = p.λ * (v - p.V0)^2
            S1(a, b, k, d) = p.k * (d - st.cell.link_rest[k, a])^2
            S2(a, b, k, d) = p.k * (d - st.cell.link_len[k, a])^2
            return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) +
                   link_delta(Float64, st.cell, (; links = st.cell.links__bond), ctx, prop, S1) +
                   link_delta(Float64, st.cell, (; links = st.cell.links__tether), ctx, prop, S2)
        end
        commit!(st, p, prop, ctx) = (commit_volume!(st, p, prop, ctx); commit_moments!(st.cell, ctx.lattice, prop))
        reads(st, p, prop, ctx) = (link_claims((; links = st.cell.links__bond), prop, Val(1))...,
            link_claims((; links = st.cell.links__tether), prop, Val(1))...)
        f = CPMFunction(dH; commit!, temperature = gg_temperature, reads)
        @test CorePotts.has_reads(f) && !CorePotts.has_reads(GG)
        # P6.0b3: without reads, the write-claim buffers are `nothing`, i.e. ghost kernel
        # arguments, so the kernels compile to the pre-P6.0b signature (a dead buffer
        # argument cost 3 % on Metal); with reads they are real per-cell buffers.
        p = merge(gg_params(), (; V0 = 36.0, k = 2.0))
        let cache(g) = init(PottsProblem(g, initial_state(σ, [1, 1, 1]; cell = deepcopy(cell)), lat, (0, 1), p),
                CheckerboardCPM(); save_start = false).cache
            @test cache(GG).wclaims === (nothing, nothing)
            @test all(w -> w isa Vector{UInt32} && length(w) == 3, cache(f).wclaims)
        end
        for alg in (SequentialCPM(), CheckerboardCPM())
            ds = map(1:4) do seed
                u = solve(PottsProblem(f, initial_state(σ, [1, 1, 1]; cell = deepcopy(cell)), lat, (0, 1500), p; seed), alg).u[end]
                (centroid_distance(Float64, u.cell, lat, 1, 2), centroid_distance(Float64, u.cell, lat, 2, 3))
            end
            @test abs(mean(first.(ds)) - 12.0) < 2.5 && abs(mean(last.(ds)) - 18.0) < 2.5
        end
    end

    @testset "lifecycle clears every relationship's links" begin
        σ, kinds = blocks((30, 30), 5; gap = 0)
        lat = Lattice((30, 30))
        n = length(kinds)
        vn = relation(VonNeumann(1), lat)
        function link_both!(cell, st, p, ctx, mcs)
            g = contact_graph(st.σ, ctx.lattice, vn, length(cell.kind))
            for a in eachindex(cell.kind), b in neighbors(g, a)
                a < b || continue
                add_link!(CorePotts.link_store(cell, :bond), a, b)
                add_link!(CorePotts.link_store(cell, :tether), a, b)
            end
        end
        remove_first(st, p, ctx, key, mcs, c) = mcs == 1 && c == 1 ? EVENT_REMOVE :
                                                mcs == 1 && c == 2 ? EVENT_DIVIDE : EVENT_NONE
        st = with_capacity(initial_state(σ, kinds;
            cell = merge(init_moments(σ, lat, n), empty_links(8, n, :bond), empty_links(8, n, :tether))), n + 4)
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = frozen_dynamics,
            phases = Phases(after_mcs = (HostPhase(link_both!; every = 100),)), lifecycle = Lifecycle(remove_first))
        u = solve(PottsProblem(f, st, lat, (0, 2), gg_params()), SequentialCPM()).u[end]
        daughter = findfirst(c -> c > n && u.cell.volume[c] > 0, 1:(n + 4))
        for r in (:bond, :tether)
            L = CorePotts.link_store(u.cell, r)
            @test link_count(L, 1) == 0 && all(b -> !linked(L, b, 1), 1:(n + 4))
            @test daughter !== nothing && link_count(L, daughter) == 0
            @test link_count(L, 2) > 0 && link_count(L, 3) > 0
        end
    end

    # -----------------------------------------------------------------------------------
    # The checkerboard claim protocol with shared reads (`CPMFunction(…; reads)`)

    @testset "claim protocol: writers exclude readers, readers share" begin
        # the propose/commit rule on explicit copies (priority, writes, reads): which commit
        function protocol(copies, ncell)
            claim = zeros(UInt32, ncell); wclaim = zeros(UInt32, ncell)
            for (w, W, R) in copies
                foreach(c -> (CorePotts._claim!(claim, Int32(c), w); CorePotts._claim!(wclaim, Int32(c), w)), W)
                foreach(c -> CorePotts._claim!(claim, Int32(c), w), R)
            end
            return [all(c -> CorePotts._won(claim, Int32(c), w), W) &&
                    all(c -> CorePotts._unwritten(wclaim, Int32(c), w), R) for (w, W, R) in copies]
        end
        # a pure reader below a writer of what it reads must not commit (a stale read) …
        @test protocol([(UInt32(5), (1,), (2,)), (UInt32(9), (2,), ())], 2) == [false, true]
        # … and a writer below a reader of what it writes must not either
        @test protocol([(UInt32(9), (1,), (2,)), (UInt32(5), (2,), ())], 2) == [true, false]
        @test protocol([(UInt32(5), (1,), (3,)), (UInt32(9), (2,), (3,))], 3) == [true, true]   # shared read
        # randomized: no committed copy writes what another committed copy writes or reads,
        # and the top priority always commits
        rng = Xoshiro(3)
        bad = 0; stuck = 0; shared = 0
        for _ in 1:20_000
            ncell = rand(rng, 2:6); n = rand(rng, 2:6)
            prios = UInt32.(randperm(rng, 1000)[1:n])
            copies = [(prios[i], Tuple(rand(rng, 0:ncell, rand(rng, 1:3))), Tuple(rand(rng, 0:ncell, rand(rng, 0:4))))
                      for i in 1:n]
            ok = protocol(copies, ncell)
            for i in 1:n, j in 1:n
                (i != j && ok[i] && ok[j]) || continue
                Wi = filter(>(0), collect(copies[i][2]))
                touched = filter(>(0), [collect(copies[j][2]); collect(copies[j][3])])
                bad += !isempty(intersect(Wi, touched))
                shared += !isempty(intersect(filter(>(0), collect(copies[i][3])), filter(>(0), collect(copies[j][3]))))
            end
            stuck += !ok[argmax(first.(copies))]
        end
        @test bad == 0 && stuck == 0
        @test shared > 1000                              # readers did share (the test has teeth)
    end

    @testset "claim protocol in the real propose/commit kernels" begin
        # one moving site (3, 3) of cell 1 amid cell 2; cell 3 elsewhere is a shared read
        lat = Lattice((6, 6))
        σ = fill(Int32(2), 6, 6); σ[3, 3] = 1; σ[6, 6] = 3
        f = CPMFunction((st, p, prop, ctx) -> -100.0; temperature = (st, p, prop, ctx) -> 1.0,
            reads = (st, p, prop, ctx) -> (Int32(3),))
        integ = init(PottsProblem(f, initial_state(σ, Int32[1, 1, 1]), lat, (0, 1), (;)), CheckerboardCPM())
        color = CorePotts.Color{2}((3, 3), (1, 1), (1, 1))
        fresh() = (zeros(UInt32, 1), zeros(Int, 1), zeros(UInt32, 3), zeros(UInt32, 3))
        prio, source, claim, wclaim = fresh()
        st = deepcopy(integ.state)
        CorePotts.propose_body!(1, prio, source, claim, wclaim, zeros(UInt32, 1), st, integ.kf, integ.p,
            integ.ctx, integ.law, integ.key, 0, color, 1)
        won = prio[1]
        @test won != 0 && st.σ[source[1]] == 2
        @test claim == [won, won, won]                  # old, new and the read are all claimed
        @test wclaim == [won, won, 0]                   # only old and new are written
        # commit: a higher-priority WRITER of the read cell 3 vetoes the copy …
        commit(claim, wclaim) = (s = deepcopy(integ.state);
            CorePotts.commit_body!(1, s, claim, zeros(UInt32, 3), wclaim, zeros(UInt32, 3), prio, source,
                integ.kf, integ.p, integ.ctx, color, 0, 1); s.σ[3, 3])
        @test commit([won, won, won + 1], [won, won, won + 1]) == 1
        # … a higher-priority READER of cell 3 does not (reads are checked against writes only)
        @test commit([won, won, won + 1], [won, won, 0]) == 2
        # and losing a written cell still vetoes
        @test commit([won + 1, won, won], [won + 1, won, 0]) == 1
    end
end

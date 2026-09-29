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
            u = solve(CPMProblem(f, initial_state(σ, [1, 1]; cell), lat, (0, 1000),
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
        u = solve(CPMProblem(f, st, lat, (0, 2), gg_params()), SequentialCPM()).u[end]
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
end

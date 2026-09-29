# Compartments (ROADMAP M2.10a, D-036).

"""Nucleus/cytoplasm pairs: a `side`-box of kind 1 with a central nucleus of kind 2."""
function compartment_cells(dims, side, core)
    σ, kinds = blocks(dims, side; gap = 2)
    ncl = length(kinds)
    cluster = collect(Int32, 1:ncl)
    for c in 1:ncl
        idx = findall(==(c), σ)
        lo = minimum(idx); off = (side - core) ÷ 2
        box = ntuple(d -> (lo[d] + off):(lo[d] + off + core - 1), length(dims))
        σ[box...] .= ncl + c
        push!(cluster, c)
    end
    return σ, vcat(fill(Int32(1), ncl), fill(Int32(2), ncl)), cluster
end

function compartment_model(; λc = 1.0, Vc = 64.0, λs = 0.0, Sc = 32.0, Jint = 2.0, claims = true)
    function dH(st, p, prop, ctx)
        J(a, b) = same_cluster(st.cell, a, b) ? p.Jint : @inbounds p.J[kindidx(st, a), kindidx(st, b)]
        E(v, c) = p.λ * (v - @inbounds(p.V0[st.cell.kind[c]]))^2
        EC(v, k) = p.λc * (v - p.Vc)^2
        ES(s, k) = p.λs * (s - p.Sc)^2
        return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E) +
               cluster_volume_delta(st.cell, prop, EC) +
               cluster_surface_delta(st.cell, prop, cluster_surface_change(st.σ, st.cell, ctx, prop), ES)
    end
    function commit!(st, p, prop, ctx)
        δ = cluster_surface_change(st.σ, st.cell, ctx, prop)
        commit_volume!(st, p, prop, ctx)
        commit_cluster_volume!(st.cell, prop)
        commit_cluster_surface!(st.cell, prop, δ)
        haskey(st.cell, :m1) && commit_moments!(st.cell, ctx.lattice, prop)
        return nothing
    end
    p = (; J = SMatrix{3, 3}(0.0, 16, 30, 16, 14, 30, 30, 30, 14), Jint, λ = 1.0,
        V0 = (48.0, 16.0), λc, Vc, λs, Sc, T = 10.0)
    cl = claims ? (st, p, prop, ctx) -> cluster_claims(st.cell, prop) : nothing
    alive(st, p, prop, ctx) = forbid_extinction(st.cell.volume, prop)
    f = claims ? CPMFunction(dH; commit!, temperature = gg_temperature, constraint = alive, claims = cl) :
        CPMFunction(dH; commit!, temperature = gg_temperature, constraint = alive)
    return f, p
end

@testset "compartments" begin
    @testset "cluster bookkeeping" begin
        lat = Lattice((10, 10))
        σ = zeros(Int32, 10, 10); σ[2:4, 2:4] .= 1; σ[3, 3] = 2; σ[7:8, 7:8] .= 3
        c = init_clusters(σ, [5, 5, 1, 9], lat; relation = VonNeumann(1))
        @test c.cluster == Int32[1, 1, 3, 4]              # lowest live member; dead slot 4 alone
        @test c.cluster_volume == Int32[9, 0, 4, 0]
        @test c.cluster_surface ≈ [12.0, 0.0, 8.0, 0.0]     # the nucleus is internal
        @test same_cluster(c, 1, 2) && !same_cluster(c, 1, 3) && !same_cluster(c, 1, 0)
    end

    @testset "cluster deltas equal brute-force energy differences" begin
        lat = Lattice((12, 12))
        r = relation(Moore(1), lat)
        ctx = (; lattice = lat, surface = r)
        rng = Random.Xoshiro(7)
        EC(v, k) = 0.7 * (v - 20.0)^2
        ES(s, k) = 0.3 * (s - 15.0)^2
        worst = 0.0
        for trial in 1:400
            σ = Int32.(rand(rng, 0:5, 12, 12))
            cluster = rand(rng, 1:5, 5)
            cell = init_clusters(σ, cluster, lat; relation = r)
            x = (rand(rng, 1:12), rand(rng, 1:12))
            t = linear_index(lat, x)
            new = Int32(rand(rng, 0:5))
            new == σ[t] && continue
            prop = Proposal(t, t, x, 1, σ[t], new)
            H(σ) = (cv = recompute_cluster_volume(σ, cell.cluster); cs = recompute_cluster_surface(σ, cell.cluster, lat, r);
                sum(k -> cell.cluster[k] == k ? EC(cv[k], k) + ES(cs[k], k) : 0.0, 1:5))
            σ2 = copy(σ); σ2[t] = new
            δ = cluster_surface_change(σ, cell, ctx, prop)
            dH = cluster_volume_delta(cell, prop, EC) + cluster_surface_delta(cell, prop, δ, ES)
            worst = max(worst, abs(dH - (H(σ2) - H(σ))))
            commit_cluster_volume!(cell, prop); commit_cluster_surface!(cell, prop, δ)
            @test cell.cluster_volume == recompute_cluster_volume(σ2, cell.cluster)
            @test cell.cluster_surface ≈ recompute_cluster_surface(σ2, cell.cluster, lat, r)
        end
        @test worst < 1e-9
    end

    @testset "compartments stay together; trackers exact ($(nameof(typeof(alg))))" for alg in (
            SequentialCPM(), CheckerboardCPM())
        σ, kinds, cluster = compartment_cells((48, 48), 8, 4)
        lat = Lattice((48, 48))
        n = length(kinds)
        function run(Jint)
            f, p = compartment_model(; λs = 0.05, Jint)
            st = initial_state(σ, kinds; cell = init_clusters(σ, cluster, lat; relation = Moore(1)))
            return solve(CPMProblem(f, st, lat, (0, 150), p; relations = (; surface = Moore(1))), alg).u[end]
        end
        m = n ÷ 2
        function internal_fraction(u)       # nuclei's interface shared with their own cytoplasm
            g = contact_graph(u.σ, lat, relation(VonNeumann(1), lat), n)
            internal = sum(c -> contact(g, c, c - m), (m + 1):n)
            total = sum(c -> contact(g, c, 0) + sum(b -> contact(g, c, b), neighbors(g, c); init = 0), (m + 1):n)
            return internal / total
        end
        u = run(2.0)
        @test u.cell.cluster_volume == recompute_cluster_volume(u.σ, u.cell.cluster)
        @test u.cell.cluster_surface ≈ recompute_cluster_surface(u.σ, u.cell.cluster, lat, Moore(1))
        control = run(14.0)                 # internal contacts no better than homotypic ones
        @info "nucleus interface with its own cytoplasm" alg internal = internal_fraction(u) control = internal_fraction(control)
        @test internal_fraction(u) > 0.9
        @test internal_fraction(u) > internal_fraction(control) + 0.1
    end

    @testset "clusters divide as a unit" begin
        lat = Lattice((40, 40))
        σ = zeros(Int32, 40, 40); σ[11:30, 15:22] .= 1; σ[18:23, 17:20] .= 2   # elongated in x
        cluster = Int32[1, 1]
        tr(st, p, ctx, key, mcs, c) = mcs == 0 ? EVENT_DIVIDE : EVENT_NONE
        half!(st, p, ctx, key, mcs, parent, daughter) =
            (st.cell.mass[daughter] = st.cell.mass[parent] /= 2; nothing)
        cell = merge(init_moments(σ, lat, 2), init_clusters(σ, cluster, lat), (; mass = [8.0, 2.0]))
        st = with_capacity(initial_state(σ, Int32[1, 2]; cell), 6)
        @test st.cell.cluster == Int32[1, 1, 3, 4, 5, 6]
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = frozen_dynamics,
            lifecycle = Lifecycle(tr; clusters = true, divide! = half!))
        sol = solve(CPMProblem(f, st, lat, (0, 1), gg_params()), SequentialCPM())
        u = sol.u[end]
        @test sol.stats.lifecycle.divisions == 2
        @test u.cell.volume[1:4] == Int32[68, 12, 68, 12]              # one plane through the cluster
        @test u.cell.cluster[1:4] == Int32[1, 1, 3, 3]                 # daughters form cluster 3
        @test u.cell.cluster_volume[[1, 3]] == Int32[80, 80]
        @test u.cell.mass[1:4] == [4.0, 1.0, 4.0, 1.0]
        side(c) = unique(coordinates(lat, i)[1] > 20.5 for i in 1:nsites(lat) if u.σ[i] == c)
        @test length(side(3)) == 1 && side(3) == side(4) != side(1) == side(2)

        # without `clusters`, compartments divide on their own and daughters stay in the cluster
        f2 = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = frozen_dynamics,
            lifecycle = Lifecycle((st, p, ctx, key, mcs, c) -> mcs == 0 && c == 2 ? EVENT_DIVIDE : EVENT_NONE))
        u2 = solve(CPMProblem(f2, st, lat, (0, 1), gg_params()), SequentialCPM()).u[end]
        @test u2.cell.cluster[1:3] == Int32[1, 1, 1]

        # removing the root re-roots the cluster
        f3 = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = frozen_dynamics,
            lifecycle = Lifecycle((st, p, ctx, key, mcs, c) -> mcs == 0 && c == 1 ? EVENT_REMOVE : EVENT_NONE))
        u3 = solve(CPMProblem(f3, st, lat, (0, 1), gg_params()), SequentialCPM()).u[end]
        @test u3.cell.cluster[1:2] == Int32[1, 2] && u3.cell.cluster_volume[2] == 24
        # a dead root keeps naming its cluster: its id is never handed to a daughter
        σd = zeros(Int32, 40, 40); σd[3:8, 3:8] .= 2; σd[11:30, 15:22] .= 3; σd[18:23, 17:20] .= 4
        cd = merge(init_moments(σd, lat, 4), init_clusters(σd, Int32[1, 2, 3, 4], lat), (; mass = ones(4)))
        std = with_capacity(initial_state(σd, Int32[1, 2, 1, 2]; cell = cd), 8)
        std.cell.cluster[1:4] .= Int32[1, 1, 3, 3]          # cell 1 (the root of {1, 2}) has died
        std.cell.cluster_volume .= recompute_cluster_volume(σd, std.cell.cluster)
        fd = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = frozen_dynamics,
            lifecycle = Lifecycle((st, p, ctx, key, mcs, c) -> mcs == 0 && c == 3 ? EVENT_DIVIDE : EVENT_NONE;
                clusters = true))
        ud = solve(CPMProblem(fd, std, lat, (0, 1), gg_params()), SequentialCPM()).u[end]
        @test ud.cell.cluster[2] == 2                         # re-rooted at its surviving member
        @test ud.cell.cluster[3] == ud.cell.cluster[4] == 3
        daughters = findall(c -> c > 4 && ud.cell.volume[c] > 0, 1:8)
        @test length(daughters) == 2 && all(c -> ud.cell.cluster[c] == daughters[1], daughters)
        @test !(ud.cell.cluster[2] in ud.cell.cluster[daughters])

        # a live root stays the root when a lower id is reused (the cluster keeps its kind)
        σr = zeros(Int32, 40, 40); σr[11:30, 15:22] .= 2; σr[18:23, 17:20] .= 3   # slot 1 empty
        cr = merge(init_moments(σr, lat, 3), init_clusters(σr, Int32[1, 2, 2], lat))
        str = with_capacity(initial_state(σr, Int32[1, 1, 2]; cell = cr), 4)
        @test str.cell.cluster[1:3] == Int32[1, 2, 2]
        fr = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = frozen_dynamics,
            lifecycle = Lifecycle((st, p, ctx, key, mcs, c) -> mcs == 0 && c == 3 ? EVENT_DIVIDE : EVENT_NONE))
        ur = solve(CPMProblem(fr, str, lat, (0, 1), gg_params()), SequentialCPM()).u[end]
        @test ur.cell.volume[1] > 0 && ur.cell.cluster[1:3] == Int32[2, 2, 2]

        # init: the root is the lowest member of a preferred kind
        @test init_clusters(σr, Int32[1, 2, 2], lat; kind = Int32[1, 2, 1], prefer = (1,)).cluster == Int32[1, 3, 3]
    end
end

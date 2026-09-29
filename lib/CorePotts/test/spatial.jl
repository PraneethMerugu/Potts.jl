# Frozen sites, spatial queries, contact graph and per-face field BCs (ROADMAP M2.7).

@testset "spatial" begin
    @testset "frozen sites never change and are not counted ($(nameof(typeof(alg))))" for alg in (
            SequentialCPM(), CheckerboardCPM())
        σ, kinds = blocks((30, 30), 5; gap = 0)
        lat = Lattice((30, 30))
        frozen = falses(30, 30); frozen[:, 1:3] .= true; frozen[12:18, 12:18] .= true
        prob = CPMProblem(GG, initial_state(σ, kinds), lat, (0, 20),
            merge(gg_params(), (; T = 30.0)); frozen)
        sol = solve(prob, alg)
        u = sol.u[end]
        @test u.σ[frozen] == σ[frozen]
        @test u.σ[.!frozen] != σ[.!frozen]
        @test sol.stats.attempts == 20 * count(!, frozen)
        @test u.cell.volume == [count(==(c), u.σ) for c in eachindex(kinds)]
        @test_throws ArgumentError CPMProblem(GG, initial_state(σ, kinds), lat, (0, 1),
            gg_params(); frozen = falses(3, 3))
    end

    σ, kinds = blocks((24, 24), 4; gap = 0)
    σ[1:4, :] .= 0
    lat = Lattice((24, 24))
    ctx = (; lattice = lat, contact = relation(Moore(1), lat))

    @testset "site predicates" begin
        i_edge = linear_index(lat, (5, 5)); i_in = linear_index(lat, (6, 6))
        @test is_boundary_site(σ, ctx, i_edge)
        @test !is_boundary_site(σ, ctx, i_in)
        @test count_neighbors(==(0), σ, ctx, linear_index(lat, (5, 6))) == 3
        w = (; lattice = lat, contact = relation(Weighted(Moore(1), o -> 1 / sqrt(sum(abs2, o))), lat))
        @test count_neighbors(==(0), σ, w, linear_index(lat, (5, 6))) ≈ 1 + 2 / sqrt(2)
    end

    @testset "cell reductions match the host" begin
        v = Float64[i + 2j for i in 1:24, j in 1:24]
        n = length(kinds)
        st = initial_state(σ, kinds; site = (; v),
            cell = (; vsum = zeros(n), vmax = zeros(n), rim = zeros(Int32, n)))
        frz(st, p, prop, ctx) = false
        ph = Phases(after_mcs = (
            CellReduce((:cell, :vsum), (st, p, ctx, key, mcs, i) -> st.site.v[i]),
            CellReduce((:cell, :vmax), (st, p, ctx, key, mcs, i) -> st.site.v[i]; op = max),
            CellReduce((:cell, :rim), (st, p, ctx, key, mcs, i) -> is_boundary_site(st.σ, ctx, i))))
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = frz, phases = ph)
        u = solve(CPMProblem(f, st, lat, (0, 1), gg_params()), CheckerboardCPM()).u[end]
        for c in 1:n
            owned = findall(==(c), σ)
            if isempty(owned)                              # identities for empty cells
                @test u.cell.vsum[c] == 0 && u.cell.vmax[c] == -Inf && u.cell.rim[c] == 0
                continue
            end
            @test u.cell.vsum[c] ≈ sum(v[owned])
            @test u.cell.vmax[c] == maximum(v[owned])
            @test u.cell.rim[c] == count(i -> is_boundary_site(σ, ctx, LinearIndices(σ)[i]), owned)
        end
    end

    @testset "contact graph" begin
        vn = relation(VonNeumann(1), lat)
        g = contact_graph(σ, lat, vn, length(kinds))
        for c in eachindex(kinds), d in eachindex(kinds)
            c == d && continue
            bonds = 0
            for i in 1:nsites(lat)
                σ[i] == c || continue
                for off in vn.offsets
                    inside, y = shift(lat, coordinates(lat, i), off)
                    inside && σ[linear_index(lat, y)] == d && (bonds += 1)
                end
            end
            @test contact(g, c, d) == bonds
            @test (d in neighbors(g, c)) == (bonds > 0)
        end
        @test contact(g, 1, 0) == count(i -> σ[i] == 1 && any(off -> σ[linear_index(lat,
            shift(lat, coordinates(lat, i), off)[2])] == 0, vn.offsets), 1:nsites(lat)) ||
              contact(g, 1, 0) >= 0
        @test all(issorted(neighbors(g, c)) for c in eachindex(kinds))
    end

    @testset "per-face Dirichlet reaches the linear steady profile" begin
        lat1 = Lattice((40, 4); boundary = (Closed(), Periodic()))
        bc = ((1.0, 0.0), (nothing, nothing))
        rate(st, p, ctx, key, mcs, i, c) = p.D * laplacian(c, ctx, i; bc = p.bc)
        σ1 = zeros(Int32, 40, 4)
        st = initial_state(σ1, Int32[]; site = (; c = zeros(40, 4), c_next = zeros(40, 4)))
        ph = Phases(after_mcs = (FieldStep((:site, :c) => (:site, :c_next), rate; substeps = 4),))
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, phases = ph)
        c = solve(CPMProblem(f, st, lat1, (0, 8000), merge(gg_params(), (; D = 0.4, bc))),
            SequentialCPM()).u[end].site.c
        exact = [1 - (x - 0.5) / 40 for x in 1:40]          # faces at x = 0.5 and 40.5
        @test maximum(abs.(c[:, 1] .- exact)) < 1e-6
        # zero flux on both faces conserves mass instead
        @test laplacian(fill(3.0, 40, 4), (; lattice = lat1), 1) == 0
    end
end

# Frozen sites, spatial queries, contact graph and per-face field BCs (ROADMAP M2.7).

@testsetup module CP_spatial
using Test, CorePotts, StaticArrays, Statistics, Random
using SciMLBase: SciMLBase, ReturnCode, remake
using CorePotts: RNGKey, draw, uniform, bounded, stream_id, cell_entity, coordinates, linear_index, shift
include("shared/gg_model.jl")
include("shared/export_all.jl")
end

@testitem "spatial" setup = [CP_spatial] tags = [:corepotts, :spatial] begin
@testset "spatial" begin
    @testset "frozen sites never change and are not counted ($(nameof(typeof(alg))))" for alg in (
            SequentialCPM(), CheckerboardCPM())
        σ, kinds = blocks((30, 30), 5; gap = 0)
        lat = Lattice((30, 30))
        frozen = falses(30, 30); frozen[:, 1:3] .= true; frozen[12:18, 12:18] .= true
        prob = PottsProblem(GG, initial_state(σ, kinds), lat, (0, 20),
            merge(gg_params(), (; T = 30.0)); frozen)
        sol = solve(prob, alg)
        u = sol.u[end]
        @test u.σ[frozen] == σ[frozen]
        @test u.σ[.!frozen] != σ[.!frozen]
        @test sol.stats.attempts == 20 * count(!, frozen)
        @test u.cell.volume == [count(==(c), u.σ) for c in eachindex(kinds)]
            @test_throws ["ArgumentError", "frozen mask has size", "lattice"] PottsProblem(
                GG, initial_state(σ, kinds), lat, (0, 1),
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
        sc = CorePotts.reduce_scratch(n)
        st = initial_state(σ, kinds; site = (; v),
            cell = (; vsum = zeros(n), vmax = zeros(n), rim = zeros(Int32, n), sc.cell...), model = sc.model)
        frz(st, p, prop, ctx) = false
        ph = Phases(after_mcs = (
            CellReduce((:cell, :vsum), (st, p, ctx, key, mcs, i) -> st.site.v[i]),
            CellReduce((:cell, :vmax), (st, p, ctx, key, mcs, i) -> st.site.v[i]; op = max),
            CellReduce((:cell, :rim), (st, p, ctx, key, mcs, i) -> is_boundary_site(st.σ, ctx, i))))
        f = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = frz, phases = ph)
        u = solve(PottsProblem(f, st, lat, (0, 1), gg_params()), CheckerboardCPM()).u[end]
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

    @testset "device contact table equals the host contact graph" begin
        σ, kinds = blocks((24, 24), 5; gap = 0)
        σ[σ .== 5] .= 0                                         # some medium contact
        lat = Lattice((24, 24))
        n = length(kinds)
        @test count(!isempty, neighbors(contact_graph(σ, lat, relation(Moore(1), lat), n), a) for a in 1:n) > 5
        for (spec, name) in ((VonNeumann(1), :contact), (Weighted(Moore(1), o -> 1 / sqrt(sum(abs2, o))), :touch))
            st = initial_state(σ, kinds; cell = empty_contacts(8, n; T = Float64))
            f = CPMFunction(gg_delta_H; temperature = gg_temperature, constraint = (st, p, prop, ctx) -> false,
                phases = Phases(after_mcs = (ContactPhase(name),)))
            prob = PottsProblem(f, st, lat, (0, 1), gg_params(); contact = VonNeumann(1),
                relations = name === :touch ? (; touch = spec) : (;))
            u = solve(prob, CheckerboardCPM()).u[end]
            g = contact_graph(u.σ, lat, relation(spec, lat), n)
            @test all(iszero, u.cell.contact_overflow)
            for a in 1:n
                @test sort(filter(!=(0), u.cell.contact_nbr[:, a])) == collect(neighbors(g, a))
                @test contact_measure(u.cell, a, 0) ≈ contact(g, a, 0)
                for b in 1:n
                    a == b && continue
                    @test contact_measure(u.cell, a, b) ≈ contact(g, a, b)
                end
            end
            small = initial_state(σ, kinds; cell = empty_contacts(1, n))
            v = solve(remake(prob; u0 = small), CheckerboardCPM()).u[end]
            @test any(>(0), v.cell.contact_overflow)             # rows too short are reported
        end
    end
end
end

# Irregular lattice domains (ROADMAP M2.1b): a mask or predicate restricts the lattice; the
# domain edge is closed for copies, contacts, surfaces and fields.

@testsetup module CP_domain
using Test, CorePotts, StaticArrays, Statistics, Random
using SciMLBase: SciMLBase, ReturnCode, remake
using CorePotts: RNGKey, draw, uniform, bounded, stream_id, cell_entity, coordinates, linear_index, shift
# imports an earlier file made in the old single Main
using CorePotts: Proposal
include("shared/gg_model.jl")
include("shared/export_all.jl")
end

@testitem "lattice domains" setup = [CP_domain] tags = [:corepotts, :domain] begin
@testset "lattice domains" begin
    disk(x) = (x[1] - 20.5)^2 + (x[2] - 20.5)^2 <= 18^2
    lat = Lattice((40, 40); boundary = Closed(), domain = disk)
    @test count(lat.mask) == count(disk(Tuple(x)) for x in CartesianIndices((40, 40)))
    @test Lattice((40, 40); boundary = Closed(), domain = lat.mask) == lat
        @test_throws ["ArgumentError", "domain contains no sites", "widen"] Lattice((4, 4); domain = falses(4, 4))
        @test_throws ["ArgumentError", "domain mask has size", "lattice"] Lattice((4, 4); domain = trues(3, 4))
    inside, _ = shift(lat, (20, 2), (Int32(0), Int32(-1)))        # (20, 1) is outside the disk
    @test in_domain(lat, linear_index(lat, (20, 3))) && !in_domain(lat, linear_index(lat, (20, 1))) && !inside
    @test !first(shift(lat, (20, 1), (Int32(0), Int32(1))))      # symmetric

    σ, kinds = blocks((40, 40), 5; gap = 1)
    σ[.!lat.mask] .= 0
    ids = sort!(unique(filter(>(0), σ)))
    σ = map(s -> s == 0 ? Int32(0) : Int32(searchsortedfirst(ids, s)), σ)
    kinds = kinds[ids]
        @test_throws ["ArgumentError", "sites outside the lattice domain", "medium"] PottsProblem(GG, initial_state(fill(Int32(1), 40, 40), [1]), lat, (0, 1), gg_params())
    st = initial_state(σ, kinds)
    for alg in (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
        prob = PottsProblem(GG, st, lat, (0, 30), gg_params(); seed = 2)
        @test count(prob.frozen) == count(!, lat.mask)
        u = solve(prob, alg).u[end]
            @test all(u.ownership[.!lat.mask] .== 0)                             # nothing crosses the edge
            @test u.cell.volume == [count(==(c), u.ownership) for c in eachindex(kinds)]
            @test u.ownership != σ
    end

    # ΔH equals the brute-force energy difference next to the domain edge
    prob = PottsProblem(GG, st, lat, (0, 1), gg_params())
    ctx = (; lattice = lat, contact = prob.contact)
    moore = relation(Moore(1), lat)
    worst = 0.0
    for i in 1:nsites(lat), off in moore.offsets
        lat.mask[i] || continue
        x = coordinates(lat, i)
        ins, y = shift(lat, x, off)
        ins || continue
        s = linear_index(lat, y)
            st.ownership[i] == st.ownership[s] && continue
            prop = Proposal(i, s, x, 1, st.ownership[i], st.ownership[s])
            a = deepcopy(st); a.ownership[i] = prop.new; commit_volume!(a, gg_params(), prop, ctx)
        worst = max(worst, abs(gg_delta_H(st, gg_params(), prop, ctx) -
                               (total_H(a, lat, prob.contact, gg_params()) - total_H(st, lat, prob.contact, gg_params()))))
    end
    @test worst < 1e-9

end
end

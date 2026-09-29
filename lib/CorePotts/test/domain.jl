# Irregular lattice domains (ROADMAP M2.1b): a mask or predicate restricts the lattice; the
# domain edge is closed for copies, contacts, surfaces and fields.

@testset "lattice domains" begin
    disk(x) = (x[1] - 20.5)^2 + (x[2] - 20.5)^2 <= 18^2
    lat = Lattice((40, 40); boundary = Closed(), domain = disk)
    @test count(lat.mask) == count(disk(Tuple(x)) for x in CartesianIndices((40, 40)))
    @test Lattice((40, 40); boundary = Closed(), domain = lat.mask) == lat
    @test_throws ArgumentError Lattice((4, 4); domain = falses(4, 4))
    @test_throws ArgumentError Lattice((4, 4); domain = trues(3, 4))
    inside, _ = shift(lat, (20, 2), (Int32(0), Int32(-1)))        # (20, 1) is outside the disk
    @test in_domain(lat, linear_index(lat, (20, 3))) && !in_domain(lat, linear_index(lat, (20, 1))) && !inside
    @test !first(shift(lat, (20, 1), (Int32(0), Int32(1))))      # symmetric

    σ, kinds = blocks((40, 40), 5; gap = 1)
    σ[.!lat.mask] .= 0
    ids = sort!(unique(filter(>(0), σ)))
    σ = map(s -> s == 0 ? Int32(0) : Int32(searchsortedfirst(ids, s)), σ)
    kinds = kinds[ids]
    @test_throws ArgumentError CPMProblem(GG, initial_state(fill(Int32(1), 40, 40), [1]), lat, (0, 1), gg_params())
    st = initial_state(σ, kinds)
    for alg in (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
        prob = CPMProblem(GG, st, lat, (0, 30), gg_params(); seed = 2)
        @test count(prob.frozen) == count(!, lat.mask)
        u = solve(prob, alg).u[end]
        @test all(u.σ[.!lat.mask] .== 0)                             # nothing crosses the edge
        @test u.cell.volume == [count(==(c), u.σ) for c in eachindex(kinds)]
        @test u.σ != σ
    end

    # ΔH equals the brute-force energy difference next to the domain edge
    prob = CPMProblem(GG, st, lat, (0, 1), gg_params())
    ctx = (; lattice = lat, contact = prob.contact)
    moore = relation(Moore(1), lat)
    worst = 0.0
    for i in 1:nsites(lat), off in moore.offsets
        lat.mask[i] || continue
        x = coordinates(lat, i)
        ins, y = shift(lat, x, off)
        ins || continue
        s = linear_index(lat, y)
        st.σ[i] == st.σ[s] && continue
        prop = Proposal(i, s, x, 1, st.σ[i], st.σ[s])
        a = deepcopy(st); a.σ[i] = prop.new; commit_volume!(a, gg_params(), prop, ctx)
        worst = max(worst, abs(gg_delta_H(st, gg_params(), prop, ctx) -
                               (total_H(a, lat, prob.contact, gg_params()) - total_H(st, lat, prob.contact, gg_params()))))
    end
    @test worst < 1e-9

    # diffusion conserves mass inside the domain (zero flux at its edge)
    rate(st, p, ctx, key, mcs, i, c) = 0.2 * laplacian(c, ctx, i)
    ph = Phases(after_mcs = (FieldStep((:site, :c) => (:site, :c_next), rate; substeps = 2),))
    c0 = zeros(40, 40); c0[18:23, 18:23] .= 1.0; c0[1, 1] = 7.0              # (1, 1) is outside
    sf = initial_state(zeros(Int32, 40, 40), Int32[]; site = (; c = c0, c_next = copy(c0)))
    fp = CPMProblem(CPMFunction(gg_delta_H; temperature = gg_temperature, phases = ph), sf, lat, (0, 200), gg_params())
    uf = solve(fp, SequentialCPM()).u[end]
    @test sum(uf.site.c[lat.mask]) ≈ 36.0
    @test uf.site.c[1, 1] == 7.0
    @test maximum(uf.site.c[lat.mask]) - minimum(uf.site.c[lat.mask]) < 0.05    # equilibrates inside
end

@testset "field faces vs domain edges" begin
    stripe = Lattice((9, 9); boundary = Closed(), domain = x -> 3 <= x[1] <= 7)
    c = zeros(9, 9)
    ctx = (; lattice = stripe)
    i = linear_index(stripe, (7, 5))
    @test laplacian(c, ctx, i; bc = ((0.0, 100.0), (nothing, nothing))) == 0.0     # domain edge: zero flux
    full = Lattice((9, 9); boundary = Closed())
    @test laplacian(c, (; lattice = full), linear_index(full, (9, 5)); bc = ((0.0, 100.0), (nothing, nothing))) == 200.0
end

# Symbolic front end (ROADMAP M3.1–M3.3): generated models equal the hand-written oracle
# ports proposal by proposal, and the derived ΔH equals H(after) − H(before) of the
# generated total energy.
using Random: Xoshiro
using InteractiveUtils: code_llvm

"""Random proposals (Moore(1) sources) on states along a trajectory of `prob`."""
function proposal_states(prob; mcs = (0, 5, 20), n = 400, rng = Xoshiro(11))
    sol = solve(remake(prob; tspan = (0, maximum(mcs))), SequentialCPM(; proposal = Moore(1)); saveat = collect(mcs))
    lat = prob.lattice
    moore = CorePotts.relation(Moore(1), lat)
    out = Tuple{Any, Any}[]
    for u in sol.u, _ in 1:n
        t = rand(rng, 1:length(u.σ)); x = CorePotts.coordinates(lat, t)
        d = rand(rng, 1:length(moore))
        ins, y = CorePotts.shift(lat, x, moore.offsets[d])
        ins || continue
        s = CorePotts.linear_index(lat, y)
        u.σ[t] == u.σ[s] && continue
        push!(out, (u, CorePotts.Proposal(t, s, x, d, u.σ[t], u.σ[s])))
    end
    return out
end

ctx_of(prob) = (; lattice = prob.lattice, contact = prob.contact, prob.relations...,
    (prob.spacing === nothing ? (;) : (; spacing = prob.spacing))...)

@testset "symbolic models equal the hand-written ports: $name" for (name, sym, hand) in (
        ("graner", () -> symbolic_graner_problem(; nmcs = 20), () -> graner_problem(; nmcs = 20)),
        ("wortel", symbolic_wortel_problem, wortel_problem),
        ("merks", symbolic_merks_problem, merks_problem),
        ("openvt", symbolic_openvt_problem, openvt_problem))
    sp, hp = sym(), hand()
    ctx = merge(ctx_of(hp), ctx_of(sp))
    worst_h = 0.0; worst_e = 0.0
    agree_c = true; agree_commit = true
    for (u, prop) in proposal_states(sp)
        dHs = sp.f.delta_H(u, sp.p, prop, ctx)
        dHh = hp.f.delta_H(u, hp.p, prop, ctx)
        worst_h = max(worst_h, abs(dHs - dHh))
        agree_c &= sp.f.constraint(u, sp.p, prop, ctx) == hp.f.constraint(u, hp.p, prop, ctx)
        # commit: both applied to copies after the ownership write
        a = deepcopy(u); b = deepcopy(u)
        a.σ[prop.target] = prop.new; b.σ[prop.target] = prop.new
        sp.f.commit!(a, sp.p, prop, ctx); hp.f.commit!(b, hp.p, prop, ctx)
        agree_commit &= all(k -> getfield(a.cell, k) == getfield(b.cell, k), intersect(keys(a.cell), keys(b.cell))) &&
                        all(k -> getfield(a.site, k) == getfield(b.site, k), intersect(keys(a.site), keys(b.site)))
        # self-check: ΔE equals H(after) − H(before)
        H0 = total_energy(sp, u)
        H1 = total_energy(sp, a)
        worst_e = max(worst_e, abs(energy_change(sp, u, prop) - (H1 - H0 + Potts._killing_credit(sp, u, prop, a))))
    end
    @test worst_h < 1e-9
    @test agree_c
    @test agree_commit
    @test worst_e < 1e-9
    # trajectories agree too (same address-keyed randomness, same functions)
    tspan = (0, 15)
    us = solve(remake(sp; tspan, seed = 5), SequentialCPM(; proposal = Moore(1))).u[end]
    uh = solve(remake(hp; tspan, seed = 5), SequentialCPM(; proposal = Moore(1))).u[end]
    @test us.σ == uh.σ
end

@testset "symbolic surface: generated code" begin
    ex = Potts.generated_code(SORTING)
    @test_throws ArgumentError PottsProblem(SORTING, [ownership => zeros(Int32, 72, 72), kind => Int[]], (0, 1); expression = Val(true))
    s = string(ex.delta_H)
    @test occursin("p.J", s) && occursin("st.cell.volume", s)
    @test !occursin("^", s)                          # the volume term was expanded to closed form
    prob = symbolic_graner_problem(; nmcs = 5)
    @test remake(prob; p = [:λ => 2.0]).f === prob.f                  # parameters change, code does not
    @test_throws ArgumentError PottsProblem(SORTING, [ownership => zeros(Int32, 4, 4)], (0, 1))
    @test_throws ArgumentError PottsProblem(SORTING, [ownership => zeros(Int32, 72, 72), kind => Int[],
        first(filter(x -> Potts.info(x).name === :J, SORTING.sys.parameters)) => [0 1 1; 2 0 1; 1 1 0]], (0, 1))
end

@testset "rebuilding a problem reuses the generated code" begin
    a = symbolic_wortel_problem(; seed = 1)
    b = symbolic_wortel_problem(; seed = 2)
    @test typeof(a.f) === typeof(b.f)
    @test a.f.fingerprint == b.f.fingerprint
end

@testset "remake with symbolic maps; the sweep law" begin
    prob = symbolic_graner_problem(; nmcs = 5)
    λ = first(filter(x -> Potts.info(x).name === :λ, SORTING.sys.parameters))
    q = remake(prob; p = [λ => 3.0])
    @test q.p.λ == 3.0 && q.p.V₀ == prob.p.V₀ && q.f === prob.f
    @test remake(prob; p = Dict(:T => 2)).p.T === 2.0              # converted to the scalar type
    @test_throws ArgumentError remake(prob; p = [:nope => 1.0])
    σ, kinds = graner_state()
    r = remake(prob; u0 = [ownership => circshift(σ, (3, 0)), kind => kinds])
    @test r.u0.σ == circshift(σ, (3, 0)) && r.u0.cell.volume == prob.u0.cell.volume
    @test prob.f.acceptance === Metropolis()
end

@testset "remake: whole parameter objects, keep sentinels, non-maps (D-115)" begin
    prob = symbolic_graner_problem(; nmcs = 5)
    # a whole object of this problem's type is taken as given
    q = remake(prob; p = [:λ => 3.0])
    @test remake(prob; p = q.p).p === q.p
    # another model's object: an ArgumentError naming the differing names, not a later failure
    other = symbolic_wortel_problem()
    err = try
        remake(prob; p = other.p); nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("λₛ", err.msg) && occursin("S₀", err.msg)                # names WORTEL has, SORTING lacks
    @test prob.p.λ == symbolic_graner_problem(; nmcs = 5).p.λ        # source unchanged
    # a Float32 problem's object: values taken, converted to this problem's scalar type
    p32 = remake(symbolic_graner_problem(; nmcs = 5, T = Float32); p = [:λ => 4.0, :T => 3.0])
    @test eltype(p32.p.V₀) === Float32
    r = remake(prob; p = p32.p)
    @test typeof(r.p) === typeof(prob.p)
    @test r.p.λ === 4.0 && r.p.T === 3.0 && r.p.V₀ == Float64.(p32.p.V₀)
    @test solve(remake(r; tspan = (0, 1)), SequentialCPM()).u[end].cell.volume isa AbstractVector
    # SciML keep sentinels
    @test remake(q; p = missing).p === q.p
    @test remake(q; p = nothing).p === q.p
    @test remake(prob; u0 = nothing).u0.σ == prob.u0.σ
    @test remake(prob; u0 = missing).u0.cell.volume == prob.u0.cell.volume
    integ = init(prob, SequentialCPM())
    step!(integ)
    reinit!(integ, nothing)
    @test integ.state.σ == prob.u0.σ && integ.t == 0
    # non-states and non-maps: ArgumentErrors, not MethodErrors or silent replacement
    @test_throws ArgumentError remake(prob; u0 = 3.0)
    @test_throws ArgumentError remake(prob; u0 = [1, 2])
    @test_throws ArgumentError reinit!(integ, "state")
    @test_throws ArgumentError remake(prob; p = 3.0)
end

@potts_model Spring begin
    @kinds medium blob
    @parameters begin
        λ = 1.0
        V₀ = 36.0
        T = 10.0
        k = 2.0
        J[kind, kind] = [0 16; 16 2]
    end
    @variables rest(edge) = 12.0
    @relationship bond(cell, cell) capacity = 1
    @lattice Lattice((60, 30); neighborhood = Moore(1))
    @energy begin
        cells(blob) => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
        edges(bond) => k * (distance - rest)^2
    end
    @sweep Metropolis(; temperature = T)
end

@potts_model Tissue begin
    @kinds medium leader follower
    @parameters begin
        T = 10.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    end
    @variables age(edge) = 0.0
    @relationship bond(cell, cell) capacity = 8
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy contacts => J[kind, kind′]
    @link bond when = new_contact(a, b) && (kind[a] == leader), every = 100
    @unlink bond when = distance > 100.0
    @sweep Metropolis(; temperature = T)
end

@testset "relationships: springs and link rules" begin
    σ = zeros(Int32, 60, 30); σ[5:10, 12:17] .= 1; σ[40:45, 12:17] .= 2
    prob = PottsProblem(Spring(; name = :spring), [ownership => σ, kind => [:blob, :blob], :bond => [(1, 2)]], (0, 1000))
    @test CorePotts.linked(CorePotts.link_store(prob.u0.cell, :bond), 1, 2) && prob.u0.cell.link_rest[1, 1] == 12.0
    # self-check with edge energies (partner centroids move with the copy)
    worst = 0.0
    for (u, prop) in proposal_states(remake(prob; tspan = (0, 5)); mcs = (0, 5), n = 300)
        a = deepcopy(u); a.σ[prop.target] = prop.new
        prob.f.commit!(a, prob.p, prop, ctx_of(prob))
        worst = max(worst, abs(energy_change(prob, u, prop) - (total_energy(prob, a) - total_energy(prob, u) + Potts._killing_credit(prob, u, prop, a))))
    end
    @test worst < 1e-9
    ds = map(1:4) do seed
        u = solve(remake(prob; seed), CheckerboardCPM()).u[end]
        CorePotts.centroid_distance(Float64, u.cell, prob.lattice, 1, 2)
    end
    @test abs(sum(ds) / 4 - 12.0) < 2.5                 # relaxes from 25 to the rest length

    σb = zeros(Int32, 30, 30)
    for (c, (i, j)) in enumerate(Iterators.product(1:5:26, 1:5:26))
        σb[i:(i + 4), j:(j + 4)] .= c
    end
    n = maximum(σb)
    kinds = [isodd(c) ? :leader : :follower for c in 1:n]
    tp = PottsProblem(Tissue(; name = :tissue), [ownership => σb, kind => kinds], (0, 1))
    u = solve(tp, SequentialCPM()).u[end]            # the rule ran once, after MCS 0's sweep
    g = CorePotts.contact_graph(u.σ, tp.lattice, tp.contact, n)
    nlinks = 0
    bonds = CorePotts.link_store(u.cell, :bond)
    for a in 1:n, b in (a + 1):n
        touching = b in CorePotts.neighbors(g, a)
        led = isodd(a) || isodd(b)
        @test CorePotts.linked(bonds, a, b) == (touching && led)
        nlinks += CorePotts.linked(bonds, a, b)
    end
    @test nlinks > 20
end

# ---------------------------------------------------------------------------------------
# Regressions from the review of the symbolic layer

function selfcheck(prob; n = 300)
    worst = 0.0
    for (u, prop) in proposal_states(remake(prob; tspan = (0, 3)); mcs = (0, 3), n)
        a = deepcopy(u); a.σ[prop.target] = prop.new
        prob.f.commit!(a, prob.p, prop, ctx_of(prob))
        worst = max(worst, abs(energy_change(prob, u, prop) - (total_energy(prob, a) - total_energy(prob, u) + Potts._killing_credit(prob, u, prop, a))))
    end
    return worst
end

# ---------------------------------------------------------------------------------------
# Several named relationships (P6.0b): a link store, law, claim set and rules per name

@potts_model Chain begin
    @kinds medium blob
    @parameters begin
        k₁ = 0.7
        k₂ = 1.3
        J[kind, kind] = [0 16; 16 2]
    end
    @variables begin
        rest(bond) = 6.0
        len(tether) = 9.0
    end
    @relationship bond(cell, cell) capacity = 2
    @relationship tether(cell, cell) capacity = 2
    @lattice Lattice((36, 16); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells => (volume - 36)^2
        contacts => J[kind, kind′]
        edges(bond) => k₁ * (distance - rest)^2
        edges(tether) => k₂ * (distance - len)^2
    end
    @sweep Metropolis(; temperature = 8.0)
end

@potts_model HexChain begin
    @kinds medium blob
    @variables begin
        rest(bond) = 5.0
        len(tether) = 8.0
    end
    @relationship bond(cell, cell) capacity = 2
    @relationship tether(cell, cell) capacity = 2
    @lattice Lattice((36, 16); geometry = Hexagonal(), neighborhood = Hex(1))
    @energy begin
        cells => (volume - 30)^2
        contacts => 6.0
        edges(bond) => 0.7 * (distance - rest)^2
        edges(tether) => 1.3 * (distance - len)^2
    end
    @sweep Metropolis(; temperature = 8.0)
end

# the same model without link energies: the difference of total energies is the link energy
@potts_model ChainNoLinks begin
    @kinds medium blob
    @parameters J[kind, kind] = [0 16; 16 2]
    @lattice Lattice((36, 16); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells => (volume - 36)^2
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = 8.0)
end

# four touching 6×6 cells in a row; 2 has a bond partner (1) and a tether partner (3)
function chain_state()
    σ = zeros(Int32, 36, 16)
    for c in 1:4
        σ[(6c - 3):(6c + 2), 6:11] .= c
    end
    return σ
end
const CHAIN_LINKS = (:bond => [(1, 2), (3, 4)], :tether => [(2, 3), (1, 4)])

# ΔH of random copies on relation `rel` against H(after) − H(before), over a short trajectory
function edge_selfcheck(prob, rel; n = 600)
    sol = solve(remake(prob; tspan = (0, 4)), SequentialCPM(; proposal = rel); saveat = [0, 2, 4])
    lat = prob.lattice
    R = CorePotts.relation(rel, lat)
    rng = Xoshiro(7)
    worst = 0.0; linked_pairs = 0
    for u in sol.u, _ in 1:n
        t = rand(rng, 1:length(u.σ)); x = CorePotts.coordinates(lat, t)
        ins, y = CorePotts.shift(lat, x, R.offsets[rand(rng, 1:length(R))])
        ins || continue
        s = CorePotts.linear_index(lat, y)
        u.σ[t] == u.σ[s] && continue
        prop = CorePotts.Proposal(t, s, x, 1, u.σ[t], u.σ[s])
        a = deepcopy(u); a.σ[t] = prop.new
        prob.f.commit!(a, prob.p, prop, ctx_of(prob))
        worst = max(worst, abs(energy_change(prob, u, prop) - (total_energy(prob, a) - total_energy(prob, u) + Potts._killing_credit(prob, u, prop, a))))
        linked_pairs += any(r -> CorePotts.linked(CorePotts.link_store(u.cell, r), prop.old, prop.new), (:bond, :tether))
    end
    return worst, linked_pairs
end

@testset "several relationships: stores, brute-force ΔH, oracle" begin
    prob = PottsProblem(Chain(; name = :chain), [ownership => chain_state(), CHAIN_LINKS...], (0, 20))
    u0 = prob.u0
    @test keys(u0.cell) ⊇ (:links__bond, :links__tether, :link_rest, :link_len)
    B, Tt = CorePotts.link_store(u0.cell, :bond), CorePotts.link_store(u0.cell, :tether)
    @test CorePotts.linked(B, 1, 2) && CorePotts.linked(B, 3, 4) && !CorePotts.linked(B, 2, 3)
    @test CorePotts.linked(Tt, 2, 3) && CorePotts.linked(Tt, 1, 4) && !CorePotts.linked(Tt, 1, 2)
    @test u0.cell.link_rest[CorePotts.link_slot(B, 2, 1), 2] == 6.0      # each store its own payload
    @test u0.cell.link_len[CorePotts.link_slot(Tt, 2, 3), 2] == 9.0
    # brute force: copies across bonded and tethered pairs, and cells with partners in both
    for (p, rel) in ((prob, Moore(1)),
            (PottsProblem(HexChain(; name = :hex), [ownership => chain_state(), CHAIN_LINKS...], (0, 20)), Hex(1)))
        worst, npairs = edge_selfcheck(p, rel)
        @test worst < 1e-9
        @test npairs > 20
    end
    # independent oracle: total energy minus the link-free model is Σ over both stores
    bare = PottsProblem(ChainNoLinks(; name = :bare), [ownership => chain_state()], (0, 20))
    u = solve(prob, SequentialCPM()).u[end]
    link_energy(store, k, ℓ) = sum(k * (CorePotts.centroid_distance(Float64, u.cell, prob.lattice, a, b) - ℓ)^2
                                   for (a, b) in store)
    oracle = link_energy(((1, 2), (3, 4)), 0.7, 6.0) + link_energy(((2, 3), (1, 4)), 1.3, 9.0)
    diff = total_energy(prob, u) - total_energy(bare, u)
    @test diff ≈ oracle rtol = 1e-10
    @test !isapprox(diff, link_energy(((1, 2), (3, 4)), 0.7, 6.0); rtol = 1e-3)    # negative control: one store
end

# The checkerboard claim protocol (CorePotts `checkerboard.jl`) on explicit copies: `writes`
# (old, new) and shared `reads`, highest priority first. Returns which copies commit.
function claim_protocol(copies, ncell)
    claim = zeros(UInt32, ncell); wclaim = zeros(UInt32, ncell)
    for (w, writes, reads) in copies
        foreach(c -> (CorePotts._claim!(claim, Int32(c), w); CorePotts._claim!(wclaim, Int32(c), w)), writes)
        foreach(c -> CorePotts._claim!(claim, Int32(c), w), reads)
    end
    return [all(c -> CorePotts._won(claim, Int32(c), w), writes) &&
            all(c -> CorePotts._unwritten(wclaim, Int32(c), w), reads) for (w, writes, reads) in copies]
end

@testset "several relationships: the claim set holds partners from every relationship" begin
    prob = PottsProblem(Chain(; name = :chain), [ownership => chain_state(), CHAIN_LINKS...], (0, 20))
    u = deepcopy(prob.u0); ctx = ctx_of(prob); lat = prob.lattice
    site(c) = CorePotts.linear_index(lat, (6c - 3, 5))                # a medium site below cell c
    target(c) = CorePotts.linear_index(lat, (6c - 3, 6))              # cell c's bottom-left site
    # X: medium invades cell 2 (moves 2's centroid); Y: medium invades cell 3
    X = CorePotts.Proposal(target(2), site(2), CorePotts.coordinates(lat, target(2)), 1, Int32(2), Int32(0))
    Y = CorePotts.Proposal(target(3), site(3), CorePotts.coordinates(lat, target(3)), 1, Int32(3), Int32(0))
    reads = prob.f.reads(u, prob.p, X, ctx)
    # (old's bond slots, new's bond slots, old's tether slots, new's tether slots); new = medium
    @test reads == Int32.((1, 0, 0, 0, 3, 0, 0, 0))                    # bond partner 1, tether partner 3
    @test prob.f.claims === CorePotts.no_claims                        # link partners are shared reads
    readsY = prob.f.reads(u, prob.p, Y, ctx)
    wX, wY = (2, 0), (3, 0)
    for (pX, pY) in ((UInt32(5), UInt32(9)), (UInt32(9), UInt32(5)))
        ok = claim_protocol([(pX, wX, reads), (pY, wY, readsY)], 4)
        @test count(ok) == 1                                          # X reads 3, which Y writes
    end
    # negative control: a claim set with the bond store only misses 3, so both commit ...
    bond_only(prop) = CorePotts.link_claims(CorePotts.link_store(u.cell, :bond), prop, Val(2))
    @test bond_only(X) == Int32.((1, 0, 0, 0))
    @test all(claim_protocol([(UInt32(5), wX, bond_only(X)), (UInt32(9), wY, bond_only(Y))], 4))
    # ... although X's ΔH depends on Y: committing Y first changes it (a stale read)
    dX = energy_change(prob, u, X)
    v = deepcopy(u); v.σ[Y.target] = Y.new; prob.f.commit!(v, prob.p, Y, ctx)
    @test abs(energy_change(prob, v, X) - dX) > 1e-3
    # two copies that only share a partner (both read 2) commit together
    Z = CorePotts.Proposal(target(1), site(1), CorePotts.coordinates(lat, target(1)), 1, Int32(1), Int32(0))
    readsZ = prob.f.reads(u, prob.p, Z, ctx)
    @test 2 in readsZ && 2 in readsY
    @test all(claim_protocol([(UInt32(5), (1, 0), readsZ), (UInt32(9), wY, readsY)], 4))
    @test count(claim_protocol([(UInt32(5), (1, 0, readsZ...), ()), (UInt32(9), (3, 0, readsY...), ())], 4)) == 1  # exclusive: one
end

@potts_model TwoRules begin
    @kinds medium leader follower
    @parameters J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    @variables begin
        age(bond) = 1.0
        strength(tether) = 2.0
    end
    @relationship bond(cell, cell) capacity = 8
    @relationship tether(cell, cell) capacity = 8
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy contacts => J[kind, kind′]
    @link bond when = new_contact(a, b) && kind[a] == leader && kind[b] == leader
    @link tether when = new_contact(a, b) && kind[a] == follower && kind[b] == follower, every = 2
    @unlink tether when = strength > 1.5, every = 3
    @sweep Metropolis(; temperature = 10.0)
end

@testset "several relationships: link rules fire per relationship" begin
    σb = zeros(Int32, 30, 30)
    for (c, (i, j)) in enumerate(Iterators.product(1:5:26, 1:5:26))
        σb[i:(i + 4), j:(j + 4)] .= c
    end
    n = maximum(σb)
    kinds = [isodd(c) ? :leader : :follower for c in 1:n]
    tp = PottsProblem(TwoRules(; name = :two), [ownership => σb, kind => kinds], (0, 1))
    @test tp.f.reads === CorePotts.no_claims          # link rules run on the host: nothing to claim
    u = solve(tp, SequentialCPM()).u[end]            # after MCS 0: every rule ran once
    g = CorePotts.contact_graph(u.σ, tp.lattice, tp.contact, n)
    B, Tt = CorePotts.link_store(u.cell, :bond), CorePotts.link_store(u.cell, :tether)
    nb = nt = 0
    for a in 1:n, b in (a + 1):n
        touching = b in CorePotts.neighbors(g, a)
        @test CorePotts.linked(B, a, b) == (touching && isodd(a) && isodd(b))
        @test !CorePotts.linked(Tt, a, b)             # linked, then unlinked (strength 2 > 1.5) at MCS 0
        nb += CorePotts.linked(B, a, b)
    end
    @test nb > 5 && all(==(1.0), u.cell.link_age[B.links .!= 0])
    # the tether rule on its own: at MCS 2 the link rule runs, the unlink rule does not (every 3)
    u2 = solve(remake(tp; tspan = (0, 3)), SequentialCPM()).u[end]
    T2 = CorePotts.link_store(u2.cell, :tether)
    g2 = CorePotts.contact_graph(u2.σ, tp.lattice, tp.contact, n)
    for a in 1:n, b in (a + 1):n
        touching = b in CorePotts.neighbors(g2, a)
        CorePotts.linked(T2, a, b) && (nt += 1; @test iseven(a) && iseven(b))
    end
    @test nt > 5 && all(==(2.0), u2.cell.link_strength[T2.links .!= 0])
    @test u2.cell.links__bond != u2.cell.links__tether
end

@potts_model AmbiguousEdge begin
    @kinds medium blob
    @variables rest(edge) = 1.0
    @relationship bond(cell, cell) capacity = 1
    @relationship tether(cell, cell) capacity = 1
    @lattice Lattice((8, 8); neighborhood = Moore(1))
    @energy edges(bond) => distance - rest
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model UnknownRelationship begin
    @kinds medium blob
    @variables rest(bnod) = 1.0
    @relationship bond(cell, cell) capacity = 1
    @lattice Lattice((8, 8); neighborhood = Moore(1))
    @energy edges(bond) => distance - rest
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model CrossRead begin
    @kinds medium blob
    @variables len(tether) = 1.0
    @relationship bond(cell, cell) capacity = 1
    @relationship tether(cell, cell) capacity = 1
    @lattice Lattice((8, 8); neighborhood = Moore(1))
    @energy edges(bond) => distance - len
    @link tether when = len > 0.0
    @sweep Metropolis(; temperature = 1.0)
end

# a base whose `rest(edge)` means its only relationship, extended by a second relationship
@potts_model SpringTether begin
    @extend base = Spring()
    @variables len(tether) = 18.0
    @relationship tether(cell, cell) capacity = 1
    @energy edges(tether) => 1.5 * (distance - len)^2
end
@potts_model CellRelationship begin
    @kinds medium blob
    @relationship cell(cell, cell) capacity = 1
    @lattice Lattice((8, 8); neighborhood = Moore(1))
    @energy contacts => 1.0
    @sweep Metropolis(; temperature = 1.0)
end

@testset "several relationships: @extend keeps a base's `x(edge)` bound to its relationship" begin
    c = mtkcompile(SpringTether(; name = :st))
    @test [r.name for r in c.relationships] == [:tether, :bond]
    @test [Potts.info(x).name for x in c.edge_vars[:bond]] == [:rest]
    @test [Potts.info(x).name for x in c.edge_vars[:tether]] == [:len]
    σ = zeros(Int32, 60, 30); σ[5:10, 12:17] .= 1; σ[20:25, 12:17] .= 2; σ[40:45, 12:17] .= 3
    prob = PottsProblem(c, [ownership => σ, kind => [:blob, :blob, :blob], :bond => [(1, 2)], :tether => [(2, 3)]], (0, 20))
    @test prob.u0.cell.link_rest[1, 1] == 12.0 && prob.u0.cell.link_len[1, 2] == 18.0
    @test selfcheck(prob) < 1e-9
    # the rule is per body: one body declaring two relationships still may not use `x(edge)`
    @test_throws "ambiguous" mtkcompile(AmbiguousEdge(; name = :a))
end

@testset "programmatic extend: a re-declared edge variable keeps the base's relationship" begin
    base = Spring(; name = :s)                       # `rest(edge)`: `bond`
    rest_sym = only(Potts.Symbolics.@variables rest(Potts.t))
    ext(scope; rels = [Potts.relationship(:tether; capacity = 1)]) = Potts.PottsSystem(; name = :x,
        kinds = base.kinds, lattice = base.lattice, sweep = base.sweep, relationships = rels,
        variables = Any[Potts.variable(rest_sym, scope; default = 9.0)])
    σ = zeros(Int32, 60, 30); σ[5:10, 12:17] .= 1; σ[20:25, 12:17] .= 2
    op = [ownership => σ, kind => [:blob, :blob], :bond => [(1, 2)]]
    for (scope, rels) in ((:edge, [Potts.relationship(:tether; capacity = 1)]), (:edge, Potts.RelationshipSpec[]),
                          (:edge, [Potts.relationship(:tether), Potts.relationship(:glue)]), (:bond, Potts.RelationshipSpec[]))
        c = mtkcompile(extend(ext(scope; rels), base))
        @test [Potts.info(x).name for x in c.edge_vars[:bond]] == [:rest]
        @test all(r -> isempty(c.edge_vars[r]), filter(!=(:bond), collect(keys(c.edge_vars))))
        prob = PottsProblem(c, op, (0, 5))
        @test prob.u0.cell.link_rest[1, 1] == prob.u0.cell.link_rest[1, 2] == 9.0   # the extension's default
        @test total_energy(prob) == total_energy(PottsProblem(base, [op; :rest => 9.0], (0, 5)))
    end
    # a nested extension (of an extension) keeps it too
    c = mtkcompile(extend(ext(:edge; rels = Potts.RelationshipSpec[]), extend(ext(:edge), base; name = :mid)))
    @test [Potts.info(x).name for x in c.edge_vars[:bond]] == [:rest] && isempty(c.edge_vars[:tether])
    # another relationship: rejected when built, naming the variable and both relationships
    @test_throws ArgumentError extend(ext(:tether), base)
    @test_throws r"`rest`.*`bond`.*`tether`" extend(ext(:tether), base)
    # control: without the base's variable, `rest(tether)` is the extension's own
    c = mtkcompile(ext(:tether))
    @test [Potts.info(x).name for x in c.edge_vars[:tether]] == [:rest]
end

# a body built on its own (no @extend), whose `rest(edge)` binds to its only relationship
# `tether`, then extended functionally over `Spring` (`rest(edge)` on `bond`)
@potts_model EdgeBody begin
    @kinds medium blob
    @variables begin
        rest(edge) = 9.0
        len(tether) = 18.0
    end
    @relationship tether(cell, cell) capacity = 1
    @lattice Lattice((60, 30); neighborhood = Moore(1))
    @energy edges(tether) => 1.5 * (distance - len)^2
    @sweep Metropolis(; temperature = 10.0)
end
@potts_model EdgeBodyExtend begin                     # the `@extend` form of the same
    @extend base = Spring()
    @variables begin
        rest(edge) = 9.0
        len(tether) = 18.0
    end
    @relationship tether(cell, cell) capacity = 1
    @energy edges(tether) => 1.5 * (distance - len)^2
end
@potts_model RestOnTether begin                        # `rest(edge)`: `tether`
    @kinds medium blob
    @variables rest(edge) = 5.0
    @relationship tether(cell, cell) capacity = 1
    @lattice Lattice((60, 30); neighborhood = Moore(1))
    @energy edges(tether) => (distance - rest)^2
    @sweep Metropolis(; temperature = 10.0)
end
@potts_model TwoBasesOneEdgeName begin
    @extend a = Spring()
    @extend b = RestOnTether()
end
@potts_model RestAsCell begin                          # an inherited edge variable as a cell variable
    @extend base = Spring()
    @variables rest(cell) = 9.0
end
@potts_model VolumeGoalBase begin
    @kinds medium blob
    @variables goal(cell) = 36.0
    @lattice Lattice((60, 30); neighborhood = Moore(1))
    @energy cells(blob) => (volume - goal)^2
    @sweep Metropolis(; temperature = 10.0)
end
@potts_model GoalAsEdge begin                        # an inherited cell variable as an edge variable
    @extend base = VolumeGoalBase()
    @variables goal(edge) = 1.0
    @relationship bond(cell, cell) capacity = 1
end

@testset "extend: a body's implicitly bound edge variable takes the base's relationship" begin
    σ = zeros(Int32, 60, 30); σ[5:10, 12:17] .= 1; σ[20:25, 12:17] .= 2; σ[40:45, 12:17] .= 3
    op = [ownership => σ, kind => [:blob, :blob, :blob], :bond => [(1, 2)], :tether => [(2, 3)]]
    # alone, the body's `rest(edge)` is its only relationship's (control)
    body = EdgeBody(; name = :x)
    @test sort([Potts.info(x).name for x in mtkcompile(body).edge_vars[:tether]]) == [:len, :rest]
    # the mark of an implicit binding is not code: settling it keeps the fingerprint
    settled = Potts.PottsSystem(; (f => getfield(body, f) for f in fieldnames(Potts.PottsSystem))...,
        variables = map(Potts._settle_edge_scope, body.variables))
    @test any(x -> haskey(Potts.info(x).options, :implicit_relationship), body.variables)
    @test !any(x -> haskey(Potts.info(x).options, :implicit_relationship), settled.variables)
    bop = [ownership => σ, kind => [:blob, :blob, :blob], :tether => [(2, 3)]]
    @test PottsProblem(body, bop, (0, 5)).f.fingerprint == PottsProblem(settled, bop, (0, 5)).f.fingerprint
    sys = extend(EdgeBody(; name = :x), Spring(; name = :s))
    c = mtkcompile(sys)
    @test [Potts.info(x).name for x in c.edge_vars[:bond]] == [:rest]
    @test [Potts.info(x).name for x in c.edge_vars[:tether]] == [:len]
    oracle = mtkcompile(EdgeBodyExtend(; name = :x))
    @test [Potts.info(x).name for x in oracle.edge_vars[:bond]] == [:rest]
    p, q = PottsProblem(c, op, (0, 5)), PottsProblem(oracle, op, (0, 5))
    @test p.u0.cell.link_rest[1, 1] == 9.0 && p.u0.cell.link_len[1, 2] == 18.0
    @test total_energy(p) == total_energy(q) == 3264 + 72 + 6
    # an explicit `rest(tether)` is still a move, and rejected
    @test_throws r"`rest`.*`bond`.*`tether`" extend(RestOnTether(; name = :x) |> s -> Potts.PottsSystem(; name = :x,
        kinds = s.kinds, lattice = s.lattice, sweep = s.sweep, relationships = s.relationships,
        variables = Any[Potts.variable(only(Potts.Symbolics.@variables rest(Potts.t)), :tether; default = 5.0)]),
        Spring(; name = :s))
    # once merged, a binding is settled: a second base declaring `rest` elsewhere is an error
    @test_throws ArgumentError extend(extend(EdgeBody(; name = :x), Spring(; name = :s)), RestOnTether(; name = :t))
end

@testset "extend: edge variables of bases and changes of scope are checked" begin
    @test_throws "bases `a` and `b` both declare edge variable `rest`, on `bond` and `tether`" TwoBasesOneEdgeName(; name = :m)
    @test_throws ArgumentError RestAsCell(; name = :m)
    @test_throws r"`rest` is an edge variable of `bond`.*a cell variable.*change its scope" RestAsCell(; name = :m)
    @test_throws r"`goal` is a cell variable.*an edge variable.*change its scope" GoalAsEdge(; name = :m)
end

@testset "several relationships: names are checked" begin
    @test_throws "ambiguous" mtkcompile(AmbiguousEdge(; name = :a))
    @test_throws "neither a scope" mtkcompile(UnknownRelationship(; name = :u))
    @test_throws "an edge variable of relationship `tether`" mtkcompile(CrossRead(; name = :c))
    c = Chain(; name = :c)
    @test_throws "declared twice" mtkcompile(Potts.PottsSystem(; name = :dup, kinds = [:medium, :blob],
        lattice = c.lattice, relationships = [Potts.relationship(:bond), Potts.relationship(:bond)], sweep = c.sweep))
    @test isequal(mtkcompile(Spring(; name = :s)).edge_vars[:bond], Spring(; name = :s).variables)   # `rest(edge)`: the only one
    @test_throws "is a variable scope" mtkcompile(CellRelationship(; name = :cr))
end

function two_kind_blocks()
    σ = zeros(Int32, 24, 24)
    for (c, (i, j)) in enumerate(Iterators.product(2:6:20, 2:6:20))
        σ[i:(i + 4), j:(j + 4)] .= c
    end
    return σ, [isodd(c) ? 1 : 2 for c in 1:maximum(σ)]
end

@potts_model CellVarContacts begin
    @kinds medium A B
    @parameters begin
        λ = 1.0
        T = 8.0
        J[kind, kind] = [0 10 10; 10 2 6; 10 6 2]
    end
    @variables x(cell) = 1.0
    @lattice Lattice((24, 24); neighborhood = Moore(1))
    @relations near = Moore(1)
    @energy begin
        cells(A, B) => λ * (volume - 25)^2 + 0.3 * (surface - 20)^2
        contacts => J[kind, kind′] + x                      # bare cell variable: x[owner]
        contacts(near) => 0.5 * x[owner] * x[owner′]
    end
    @sweep Metropolis(; temperature = T)
end

@testset "review regressions" begin
    σ, kinds = two_kind_blocks()
    n = length(kinds)
    xs = collect(1.0:n)
    prob = PottsProblem(CellVarContacts(; name = :cv), [ownership => σ, kind => kinds,
        first(filter(v -> Potts.info(v).name === :x, CellVarContacts(; name = :cv).variables)) => xs], (0, 3))
    @test selfcheck(prob) < 1e-9           # cell variables mirrored; surface δ fused once
    ex = Potts.generated_code(CellVarContacts(; name = :cv))
    @test count("δs_old +=", string(ex.delta_H)) == 1

    # quantities that change with the copy are rejected outside cell terms
    @test_throws ArgumentError mtkcompile(Potts.PottsSystem(; name = :bad, kinds = [:medium, :A],
        lattice = Potts.lattice_spec((8, 8)), energies = [Potts.energy(Potts.contacts => Potts._index(Potts.B.volume, Potts.B.owner))],
        sweep = Potts.sweep_spec(:metropolis; temperature = 1.0)))
    @test_throws ArgumentError mtkcompile(Potts.PottsSystem(; name = :bad, kinds = [:medium, :A],
        lattice = Potts.lattice_spec((8, 8)), energies = [Potts.energy(Potts.sites => 0.1 * Potts._index(Potts.B.volume, Potts.B.owner))],
        sweep = Potts.sweep_spec(:metropolis; temperature = 1.0)))
    @test_throws ArgumentError mtkcompile(Potts.PottsSystem(; name = :bad, kinds = [:medium, :A],
        lattice = Potts.lattice_spec((8, 8)), energies = [Potts.energy(Potts.cells(0) => Potts.B.volume)],
        sweep = Potts.sweep_spec(:metropolis; temperature = 1.0)))
end

@potts_model TwoDivisions begin
    @kinds medium A B
    @parameters begin
        T = 5.0
        J[kind, kind] = [0 10 10; 10 2 6; 10 6 2]
    end
    @variables begin
        m(cell) = 8.0
        q(cell) = 5.0
        y(cell) = 0.0
    end
    @lattice Lattice((24, 24); neighborhood = Moore(1))
    @energy contacts => J[kind, kind′]
    @on_copy y[new] ~ 1.0                     # new may be the medium: nothing to write
    @divide cells(A) when = mcs == 0, m => Split()
    @divide cells(B) when = mcs == 1000, q => 0.0
    @constraint no_extinction
    @sweep Metropolis(; temperature = T)
end

@testset "division rules are per kind; on-copy writes skip the medium" begin
    σ, kinds = two_kind_blocks()
    prob = PottsProblem(TwoDivisions(; name = :td), [ownership => σ, kind => kinds], (0, 2))
    u = solve(prob, SequentialCPM(; proposal = Moore(1))).u[end]      # retractions happen: no BoundsError
    nA = count(==(1), kinds)
    @test count(>(0), u.cell.volume) == length(kinds) + nA
    @test all(==(5.0), u.cell.q[u.cell.volume .> 0])                  # B's rule never ran on A cells
    @test all(c -> u.cell.m[c] == (kinds[c] == 1 ? 4.0 : 8.0), 1:length(kinds))
end

@potts_model FloatModel begin
    @kinds medium A
    @parameters begin
        λ = 1.0
        T = 8.0
    end
    @variables c(field) = 0.0
    @lattice Lattice((16, 16); neighborhood = Moore(1))
    @energy cells(A) => λ * (surface - 4 * sqrt(volume))^2 + log(2) * volume / 3
    @drive copy => -2 * (c[target] - c[source]) / 3
    @equations D(c) ~ 0.1 * Δ(c) - c / 10 + exp(-1) * (kind == A)
    @sweep Metropolis(; temperature = T)
end

@testset "Float32 models never touch Float64" begin
    σ = zeros(Int32, 16, 16); σ[5:10, 5:10] .= 1
    prob = PottsProblem(FloatModel(; name = :fm), [ownership => σ, kind => [1]], (0, 2); T = Float32, field_solver = ExplicitEuler())
    ctx = ctx_of(prob)
    prop = CorePotts.Proposal(4 + 16 * 5, 5 + 16 * 5, (4, 6), 1, Int32(0), Int32(1))
    io = IOBuffer()
    code_llvm(io, prob.f.delta_H, typeof.((prob.u0, prob.p, prop, ctx)); debuginfo = :none)
    @test !occursin("double", String(take!(io)))
    @test prob.f.delta_H(prob.u0, prob.p, prop, ctx) isa Float32
    @test selfcheck(PottsProblem(FloatModel(; name = :fm), [ownership => σ, kind => [1]], (0, 2); field_solver = ExplicitEuler())) < 1e-9
end

@potts_model Helpers begin
    @kinds medium A
    firstor0(v) = isempty(v) ? 0.0 : v[1]            # plain Julia: lazy ternary, real indexing
    w = zeros(2)
    w[1] = 3.0                                        # indexed assignment is not rewritten
    total = sum(w[i] for i in eachindex(w))           # an ordinary generator
    ok = w[1] > 0 && firstor0(Float64[]) == 0.0       # short-circuit on real values
    @parameters begin
        λ = firstor0(w) + total
        T = ok ? 5.0 : 1.0
    end
    @lattice Lattice((8, 8); neighborhood = Moore(1))
    @energy cells(A) => λ * volume
    @sweep Metropolis(; temperature = T)
end

@testset "macro: plain Julia stays plain; keyword overrides" begin
    sys = Helpers(; name = :h)
    vals = Dict(Potts.info(p).name => Potts.info(p).default for p in sys.parameters)
    @test vals[:λ] == 6.0 && vals[:T] == 5.0
    sys2 = Helpers(; name = :h, λ = 2.0)
    @test Potts.info(first(sys2.parameters)).default == 2.0
    # constructing a model twice yields the same generated code (gathers numbered per model)
    σ = zeros(Int32, 8, 8); σ[2:3, 2:3] .= 1
    a = PottsProblem(WortelAct(; name = :w, lattice = (8, 8)), [ownership => σ, kind => [1]], (0, 1))
    b = PottsProblem(WortelAct(; name = :w, lattice = (8, 8)), [ownership => σ, kind => [1]], (0, 1))
    @test a.f.fingerprint == b.f.fingerprint && typeof(a.f) === typeof(b.f)
end

@potts_model Census begin
    @kinds medium dark light
    @parameters begin
        λ = 1.0
        T = 10.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    end
    @variables begin
        act(site) = 0.0
        total(model) = 0.0
        ndark(model) = 0.0
    end
    @lattice Lattice((24, 24); neighborhood = Moore(1))
    @energy begin
        cells(dark, light) => λ * (volume - 25)^2
        contacts => J[kind, kind′]
    end
    @on_copy act[target] ~ 1.0
    @after_mcs begin
        total ~ sum(act[s] for s in sites)
        ndark ~ count(true for c in cells(dark))
    end
    @observed begin
        mean_volume ~ mean(volume for c in cells)
        dark_area ~ sum(volume for c in cells(dark))
        big ~ volume > 25
        excess ~ dark_area - 25 * ndark
    end
    @sweep Metropolis(; temperature = T)
end

@testset "model variables, populations, observed and SII" begin
    σ, kinds = two_kind_blocks()
    sys = Census(; name = :census)
    prob = PottsProblem(sys, [ownership => σ, kind => kinds], (0, 6))
    sol = solve(prob, SequentialCPM(; proposal = Moore(1)); saveat = [2, 4, 6])
    named(n) = only(filter(x -> Potts.info(x).name === n, vcat(sys.variables, [o.var for o in sys.observed], sys.parameters)))
    live(u) = findall(>(0), u.cell.volume)
    @test sol[named(:total)] == [sum(u.site.act) for u in sol.u]
    @test sol[named(:ndark)][2:end] == [count(c -> kinds[c] == 1, live(u)) for u in sol.u[2:end]]   # t = 0: default
    @test sol[named(:ndark)][1] == 0
    @test sol[named(:mean_volume)] ≈ [sum(u.cell.volume[live(u)]) / length(live(u)) for u in sol.u]
    @test sol[named(:dark_area)] == [sum(u.cell.volume[c] for c in live(u) if kinds[c] == 1; init = 0) for u in sol.u]
    @test sol[named(:big)][end] == (sol.u[end].cell.volume .> 25)
    @test sol[named(:excess)] == sol[named(:dark_area)] .- 25 .* sol[named(:ndark)]
    @test prob.p isa Potts.PottsParameters && isbits(prob.p)
    @test sol[Potts.kind][1] == kinds                                   # built-ins observe too
    @test sol[named(:act)][end] == sol.u[end].site.act
    @test observe(prob, named(:mean_volume)) ≈ 25.0
    SII = Potts.SymbolicIndexingInterface
    @test SII.getp(prob, named(:λ))(prob) == 1.0
    @test SII.getp(sol, named(:T))(sol) == 10.0
end

@potts_model LibrarySorting begin
    @kinds medium dark light
    @parameters begin
        λ = 1.0
        V₀ = 40.0
        T = 10.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    end
    @lattice Lattice((72, 72); boundary = Periodic(), neighborhood = Moore(1))
    @energy begin
        Volume(dark, light; target = V₀, strength = λ)
        Adhesion(J)
    end
    @sweep Metropolis(; temperature = T)
end

@potts_model KindTemperature begin
    @kinds medium wall[frozen] dark light
    @parameters begin
        Tk[kind] = [0.0, 0.0, 5.0, 20.0]
        J[kind, kind] = [0 30 16 16; 30 0 30 30; 16 30 2 11; 16 30 11 14]
    end
    @variables c(field) = 0.0
    @lattice Lattice((24, 24); neighborhood = Moore(1))
    @energy begin
        Volume(dark, light; target = 25.0, strength = 1.0)
        Adhesion(J)
    end
    @drive Chemotaxis(c; strength = 3.0, kinds = (dark,))
    @sweep Metropolis(; temperature = Tk[kind], combine = min)
end

@testset "library one-liners, per-kind temperature, frozen kinds" begin
    a = symbolic_graner_problem(; nmcs = 5)
    σ, kinds = graner_state()
    b = PottsProblem(LibrarySorting(; name = :lib), [ownership => σ, kind => kinds], (0, 5))
    @test all(((u, prop),) -> a.f.delta_H(u, a.p, prop, ctx_of(a)) == b.f.delta_H(u, b.p, prop, ctx_of(b)),
        proposal_states(a; mcs = (0, 5), n = 200))

    σk = zeros(Int32, 24, 24); σk[:, 1:2] .= 1                 # a wall along one side
    for (c, (i, j)) in enumerate(Iterators.product(2:6:20, 6:6:18))
        σk[i:(i + 4), j:(j + 4)] .= c + 1
    end
    n = maximum(σk)
    kinds = [c == 1 ? :wall : isodd(c) ? :dark : :light for c in 1:n]
    prob = PottsProblem(KindTemperature(; name = :kt), [ownership => σk, kind => kinds], (0, 20))
    ctx = ctx_of(prob)
    Tof(old, new) = prob.f.temperature(prob.u0, prob.p, CorePotts.Proposal(1, 2, (1, 1), 1, Int32(old), Int32(new)), ctx)
    dark_cell = findfirst(==(:dark), kinds); light_cell = findfirst(==(:light), kinds)
    @test Tof(dark_cell, light_cell) == 5.0 && Tof(light_cell, dark_cell) == 5.0     # min of the two
    @test Tof(0, light_cell) == 20.0 && Tof(dark_cell, 0) == 5.0                     # medium never contributes
    u = solve(prob, SequentialCPM(; proposal = Moore(1))).u[end]
    @test u.σ[:, 1:2] == σk[:, 1:2] && u.cell.volume[1] == 48                       # the wall never moves
    @test u.σ != σk
end

# Compartments (D-036) in the authoring surface: the CorePotts nucleus/cytoplasm test model.
@potts_model Compartments begin
    @kinds medium cytoplasm nucleus
    @parameters begin
        J[kind, kind] = [0 16 16; 16 14 30; 16 30 14]
        Jint = 2.0
        V₀[kind] = [0.0, 48.0, 16.0]
        λ = 1.0
        λc = 1.0
        Vc = 64.0
        λs = 0.1
        Sc = 32.0
        T = 10.0
    end
    @variables mass(cell) = 2.0
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy begin
        cells => λ * (volume - V₀[kind])^2
        contacts => ifelse(cluster[owner] == cluster[owner′], Jint, J[kind, kind′])
        clusters(cytoplasm) => λc * (cluster_volume - Vc)^2 + λs * (cluster_surface - Sc)^2
    end
    @constraint no_extinction
    @divide clusters(cytoplasm) when = (mcs == 2) && (cluster_volume >= 56), along = (1.0, 0.0), mass => Split()
    @sweep Metropolis(; temperature = T)
end

function compartment_state()
    σ = zeros(Int32, 30, 30)
    n = 0
    for i in 1:10:21, j in 1:10:21
        n += 1
        σ[i:(i + 7), j:(j + 7)] .= n
    end
    for c in 1:n
        idx = findall(==(c), σ); lo = minimum(idx)
        σ[(lo[1] + 2):(lo[1] + 5), (lo[2] + 2):(lo[2] + 5)] .= n + c
    end
    return σ, vcat(fill(:cytoplasm, n), fill(:nucleus, n)), vcat(1:n, 1:n)
end

@testset "compartments in the authoring surface" begin
    σ, kinds, groups = compartment_state()
    prob = PottsProblem(Compartments(; name = :comp), [ownership => σ, kind => kinds, cluster => groups], (0, 1))
    u0 = prob.u0
    @test Array(u0.cell.cluster)[1:18] == vcat(1:9, 1:9)
    @test Array(u0.cell.cluster_volume)[1:9] == fill(64, 9)
    @test Array(u0.cell.cluster_surface) ≈ CorePotts.recompute_cluster_surface(σ, u0.cell.cluster, prob.lattice, Moore(1)) &&
          allequal(Array(u0.cell.cluster_surface)[1:9])      # nuclei are internal
    # the hand-written CorePotts model (lib/CorePotts/test/compartments.jl)
    Jt = [0 16 16; 16 14 30; 16 30 14]
    ki(st, a) = a == 0 ? 1 : Int(st.cell.kind[a]) + 1
    function hand(st, p, prop, ctx)
        J(a, b) = CorePotts.same_cluster(st.cell, a, b) ? 2.0 : Float64(Jt[ki(st, a), ki(st, b)])
        E(v, c) = (v - (48.0, 16.0)[st.cell.kind[c]])^2
        EC(v, k) = st.cell.kind[k] == 1 ? (v - 64.0)^2 : 0.0
        ES(s, k) = st.cell.kind[k] == 1 ? 0.1 * (s - 32.0)^2 : 0.0
        return CorePotts.contact_delta(st.σ, ctx, prop, J) + CorePotts.volume_delta(st.cell.volume, prop, E) +
               CorePotts.cluster_volume_delta(st.cell, prop, EC) +
               CorePotts.cluster_surface_delta(st.cell, prop, CorePotts.cluster_surface_change(st.σ, st.cell, ctx, prop), ES)
    end
    ctx = ctx_of(prob)
    states = proposal_states(remake(prob; tspan = (0, 1)); mcs = (0, 1), n = 400)
    @test maximum(((u, prop),) -> abs(prob.f.delta_H(u, prob.p, prop, ctx) - hand(u, prob.p, prop, ctx)), states) < 1e-9
    @test selfcheck(remake(prob; tspan = (0, 1))) < 1e-9
    # trackers stay exact through a run
    u = solve(prob, SequentialCPM(; proposal = Moore(1))).u[end]
    cl = Array(u.cell.cluster)
    @test Array(u.cell.cluster_volume) == CorePotts.recompute_cluster_volume(Array(u.σ), cl)
    @test Array(u.cell.cluster_surface) ≈ CorePotts.recompute_cluster_surface(Array(u.σ), cl, prob.lattice, Moore(1))
    # checkerboard claims the clusters of old and new
    t = findfirst(==(Int32(10)), σ)      # a nucleus site of cluster 1
    @test prob.f.claims(u0, prob.p, CorePotts.Proposal(LinearIndices(σ)[t], 1, Tuple(t), 1, Int32(10), Int32(5)), ctx) == (1, 5)
    # a cluster divides as a unit: both daughters keep a nucleus and a cytoplasm
    sol = solve(remake(prob; tspan = (0, 4)), SequentialCPM(; proposal = Moore(1)))
    v = sol.u[end]
    live = findall(>(0), Array(v.cell.volume))
    @test length(live) == 36
    roots = unique(Array(v.cell.cluster)[live])
    @test length(roots) == 18
    @test all(r -> sort(Array(v.cell.kind)[filter(c -> v.cell.cluster[c] == r, live)]) == [1, 2], roots)
    @test sum(Array(v.cell.mass)[live]) ≈ 36.0          # every member split its mass
    @test sort(Array(v.cell.mass)[live]) == fill(1.0, 36)
end

@testset "compartment validation" begin
    @test_throws ArgumentError mtkcompile(Potts.PottsSystem(; name = :x, kinds = [:medium, :ka],
        lattice = Potts.lattice_spec((8, 8)), sweep = Potts.sweep_spec(:metropolis; temperature = 1.0),
        energies = [Potts.EnergyTerm(Potts.CellDomain(Int[]), Potts.B.cluster_volume^2)]))
    @test_throws ArgumentError mtkcompile(Potts.PottsSystem(; name = :x, kinds = [:medium, :ka],
        lattice = Potts.lattice_spec((8, 8)), sweep = Potts.sweep_spec(:metropolis; temperature = 1.0),
        energies = [Potts.EnergyTerm(Potts.ContactDomain(:contact), Potts.B.cluster_volume)]))
    # P6.0a: cell and cluster divisions mix per kind, but one kind divides by one domain
    divsys(cellk, clusterk) = Potts.PottsSystem(; name = :x, kinds = [:medium, :ka, :kb],
        lattice = Potts.lattice_spec((8, 8)), sweep = Potts.sweep_spec(:metropolis; temperature = 1.0),
        divisions = [Potts.divide(cellk; when = Potts.B.volume > 1), Potts.divide(clusterk; when = Potts.B.volume > 1)])
    err = try
        mtkcompile(divsys(Potts.cells(1), Potts.clusters(1, 2)))
    catch e
        e
    end
    @test err isa ArgumentError && occursin("`ka`", err.msg) && !occursin("`kb`", err.msg)
    @test_throws ArgumentError mtkcompile(divsys(Potts.cells, Potts.clusters(2)))      # bare `cells` is every kind
    @test mtkcompile(divsys(Potts.cells(2), Potts.clusters(1))) isa Potts.CompiledPottsSystem
end

# P6.0a: a nucleus dividing alone inside a cluster runs only its cell rule, and its daughter
# stays in the cluster; the cluster division runs only the cluster rule
@potts_model NucleusDivision begin
    @kinds medium cytoplasm nucleus
    @parameters begin
        J[kind, kind] = [0 16 16; 16 14 30; 16 30 14]
        Jint = 2.0
        V₀[kind] = [0.0, 48.0, 16.0]
        λ = 10.0
        λc = 1.0
        Vc = 64.0
        T = 10.0
    end
    @variables begin
        mass(cell) = 2.0
        ndiv(cell) = 0.0
    end
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy begin
        cells => λ * (volume - V₀[kind])^2
        contacts => ifelse(cluster[owner] == cluster[owner′], Jint, J[kind, kind′])
        clusters(cytoplasm) => λc * (cluster_volume - Vc)^2
    end
    @constraint no_extinction
    @divide clusters(cytoplasm) when = (mcs == 2) && (cluster_volume >= 56), along = (1.0, 0.0), mass => Split()
    @divide cells(nucleus) when = (mcs == 3) && (volume >= 2), along = (0.0, 1.0), ndiv => ndiv + 1
    @sweep Metropolis(; temperature = T)
end

function check_nucleus_division(v)
    live = findall(>(0), Array(v.cell.volume))
    kd = Array(v.cell.kind)
    cl = Array(v.cell.cluster)
    roots = unique(cl[live])
    @test length(live) == 54 && length(roots) == 18
    @test all(r -> sort(kd[filter(c -> cl[c] == r, live)]) == [1, 2, 2], roots)   # nuclei stay inside
    @test all(==(1), Array(v.cell.mass)[live])                    # Split once, by the cluster rule
    cnt = Array(v.cell.ndiv)
    @test all(c -> cnt[c] == (kd[c] == 2 ? 1 : 0), live)           # the cell rule once, nuclei only
    @test Array(v.cell.cluster_volume) == CorePotts.recompute_cluster_volume(Array(v.σ), cl)
    @test Array(v.cell.volume) == [count(==(c), Array(v.σ)) for c in eachindex(kd)]
end

@testset "cell and cluster divisions in one model" begin
    σ, kinds, groups = compartment_state()
    prob = PottsProblem(NucleusDivision(; name = :nd), [ownership => σ, kind => kinds, cluster => groups], (0, 5))
    @test selfcheck(remake(prob; tspan = (0, 1))) < 1e-9
    for alg in (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
        check_nucleus_division(solve(prob, alg).u[end])
    end
end

get(ENV, "POTTS_GPU", "") == "metal" && @eval using Metal
get(ENV, "POTTS_GPU", "") == "metal" && @testset "cell and cluster divisions in one model on Metal" begin
    σ, kinds, groups = compartment_state()
    prob = PottsProblem(NucleusDivision(; name = :nd), [ownership => σ, kind => kinds, cluster => groups], (0, 5);
        T = Float32)
    check_nucleus_division(solve(prob, CheckerboardCPM(; proposal = Moore(1)); backend = Metal.MetalBackend()).u[end])
end

@testset "ensembles and callbacks of generated problems" begin
    prob = symbolic_graner_problem(; nmcs = 5)
    alg = SequentialCPM(; proposal = Moore(1))
    ens = solve(EnsembleProblem(prob; output_func = (sol, ctx) -> (total_energy(prob, sol.u[end]), false)),
        alg, EnsembleThreads(); trajectories = 4)
    @test length(unique(ens.u)) == 4
    @test ens.u[3] == total_energy(prob, solve(remake(prob; replica = 3), alg).u[end])
    # a callback that quenches the temperature through a symbolic parameter map
    cold = remake(prob; p = [:T => 0.0])
    quench = DiscreteCallback((u, t, integ) -> t == 2, integ -> (integ.p = cold.p))
    integ = init(prob, alg; callback = quench)
    foreach(_ -> step!(integ), 1:3)
    @test integ.p.T == 0.0
end

@potts_model ClusterCensus begin
    @kinds medium cytoplasm nucleus
    @parameters T = 10.0
    @variables total(model) = 0.0
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy cells => (volume - 40.0)^2
    @after_mcs total ~ sum(cluster_volume for c in cells)
    @divide cells(nucleus) when = (cluster == id) && (mcs == 100), along = (1.0, 0.0)
    @sweep Metropolis(; temperature = T)
end

@testset "compartment review regressions" begin
    σ, kinds, groups = compartment_state()
    # populations read the bound cell's cluster trackers
    p = PottsProblem(ClusterCensus(; name = :cc), [ownership => σ, kind => kinds, cluster => groups], (0, 1))
    u = solve(p, SequentialCPM(; proposal = Moore(1))).u[end]
    @test u.model.total[1] == sum(u.cell.cluster_volume[u.cell.cluster[c]] for c in 1:18 if u.cell.volume[c] > 0)
    # roots are chosen among the kinds that name clusters, whatever the numbering
    n = 9
    σn = map(s -> s == 0 ? s : Int32(s <= n ? s + n : s - n), σ)     # nuclei first
    pn = PottsProblem(Compartments(; name = :comp), [ownership => σn, kind => vcat(kinds[(n + 1):end], kinds[1:n]),
        cluster => groups], (0, 1))
    @test Array(pn.u0.cell.cluster)[1:18] == vcat(n + 1:2n, n + 1:2n)
    @test total_energy(pn) ≈ total_energy(PottsProblem(Compartments(; name = :comp),
        [ownership => σ, kind => kinds, cluster => groups], (0, 1)))
    # remake with a new state recomputes the frozen mask
    σk = zeros(Int32, 24, 24); σk[:, 1:2] .= 1; σk[10:14, 10:14] .= 2
    kt = PottsProblem(KindTemperature(; name = :kt), [ownership => σk, kind => [:wall, :dark]], (0, 5))
    σk2 = zeros(Int32, 24, 24); σk2[:, 23:24] .= 1; σk2[10:14, 10:14] .= 2
    kt2 = remake(kt; u0 = [ownership => σk2, kind => [:wall, :dark]])
    @test kt2.frozen == (σk2 .== 1)
    # clusters used only in a division condition or an observed quantity still get storage
    base = (; name = :x, kinds = [:medium, :ka], lattice = Potts.lattice_spec((8, 8)),
        sweep = Potts.sweep_spec(:metropolis; temperature = 1.0))
    @test mtkcompile(Potts.PottsSystem(; base..., divisions = [Potts.divide(Potts.cells(1);
        when = Potts.B.cluster == Potts.B.id)])).uses_clusters
    @test mtkcompile(Potts.PottsSystem(; base..., observed = [Potts.ObservedEq(Potts.observed_var(:cv),
        Potts.B.cluster_volume)])).uses_clusters
end

@potts_model DiskSorting begin
    @kinds medium dark light
    @parameters begin
        T = 10.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    end
    @variables c(field) = 0.0
    @lattice Lattice((40, 40); boundary = Closed(), domain = x -> (x[1] - 20.5)^2 + (x[2] - 20.5)^2 <= 18^2)
    @energy begin
        Volume(dark, light; target = 25.0)
        Adhesion(J)
    end
    @equations D(c) ~ 0.2 * Δ(c) + 0.01 * (kind == dark)
    @sweep Metropolis(; temperature = T)
end

@testset "irregular lattice domains in the surface" begin
    sys = DiskSorting(; name = :disk)
    mask = sys.lattice.domain
    σ, kinds = two_kind_blocks()
    σd = zeros(Int32, 40, 40); σd[9:32, 9:32] .= σ
    @test all(mask[σd .> 0])
    prob = PottsProblem(sys, [ownership => σd, kind => kinds], (0, 30); field_solver = ExplicitEuler())
    @test count(prob.frozen) == count(!, mask)
    @test selfcheck(prob) < 1e-9
    u = solve(prob, CheckerboardCPM(; proposal = Moore(1))).u[end]
    @test all(u.σ[.!mask] .== 0) && all(u.site.c[.!mask] .== 0)
    @test sum(u.site.c) > 0
    σbad = copy(σd); σbad[1, 1] = 1
    @test_throws ArgumentError PottsProblem(sys, [ownership => σbad, kind => kinds], (0, 1); field_solver = ExplicitEuler())
end

# Composition: a chemotactic extension of the Graner model and an obstacle kind added to it.
@potts_model ChemoSorting begin
    @extend λ, V₀, dark = base = Sorting()
    @parameters χ = 50.0
    @variables c(field) = 0.0
    @drive Chemotaxis(c; strength = χ, kinds = (dark,))
    @equations D(c) ~ 0.1 * Δ(c) + 0.02 * (kind == dark) - 0.01 * c
    @observed mean_excess ~ sum((volume - V₀) for n in cells) * λ
end

@potts_model WalledSorting begin
    @extend base = Sorting(; lattice = (40, 40), T = 6.0)
    @kinds medium dark light wall[frozen]
    @parameters J[kind, kind] = [0 16 16 30; 16 2 11 30; 16 11 14 30; 30 30 30 0]
end

@testset "composition: extend and @extend" begin
    ext = ChemoSorting(; name = :chemo)
    @test ext.kinds == [:medium, :dark, :light]
    @test Set(Potts.info(x).name for x in ext.parameters) == Set([:λ, :V₀, :T, :J, :χ])
    @test length(ext.energies) == 2 && length(ext.drives) == 1 && ext.lattice == SORTING.sys.lattice
    σ, kinds = graner_state()
    a = symbolic_graner_problem(; nmcs = 5)
    b = PottsProblem(ext, [ownership => σ, kind => kinds], (0, 5); field_solver = ExplicitEuler())
    # without the drive the extension's energy is the base's
    @test all(((u, prop),) -> energy_change(a, u, prop) == energy_change(b, u, prop), proposal_states(a; mcs = (0, 5), n = 100))
    @test b.p.χ == 50.0 && haskey(b.u0.site, :c)
    @test selfcheck(b) < 1e-9
    sol = solve(b, SequentialCPM(; proposal = Moore(1)))
    @test length(sol[:mean_excess]) == length(sol.t)
    @test sol[:volume][end] == [Float64(v) for v in sol.u[end].cell.volume] && sol[:c][end] == sol.u[end].site.c
    # an added frozen kind and a redeclared (wider) contact table; base overrides by keyword
    w = WalledSorting(; name = :walled)
    @test w.kinds == [:medium, :dark, :light, :wall] && w.frozen_kinds == [3]
    @test count(x -> Potts.info(x).name === :J, w.parameters) == 1 && size(Potts.info(only(filter(x -> Potts.info(x).name === :J, w.parameters))).default) == (4, 4)
    @test w.lattice.dims == (40, 40)
    σw = zeros(Int32, 40, 40); σw[:, 1] .= 1; σw[10:15, 10:15] .= 2; σw[20:25, 20:25] .= 3
    pw = PottsProblem(w, [ownership => σw, kind => [:wall, :dark, :light]], (0, 10))
    @test pw.p.T == 6.0 && count(pw.frozen) == 40
    @test_throws ArgumentError extend(PottsSystem(; name = :x, kinds = [:medium, :light], lattice = SORTING.sys.lattice,
        sweep = SORTING.sys.sweep), SORTING.sys)
    @test_throws ArgumentError Potts.lookup(SORTING.sys, :nope)
end

# D-114: a bound vector parameter redeclared takes the extension's default or keyword.
# Fixture: cell 1 (A, volume 9) and cell 2 (B, volume 12) on a 12×12 von Neumann lattice;
# the base without the `d` terms is 9 + 52 + 10.5 = 71.5, and the `d` terms add 9 d₁ + 12 d₂.
@potts_model ExtVecBase begin
    @kinds medium A B
    @parameters begin
        λ = 1.0
        V₀ = 9.0
        J[kind, kind] = [0 2 2; 2 1 4; 2 4 1]
        d[1:2] = [1.0, 2.0]
    end
    @variables x(cell) = 0.5
    @lattice Lattice((12, 12); neighborhood = VonNeumann(1))
    @energy begin
        cells(A, B) => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
        cells(A, B) => x * volume
        cells(A) => d[1] * volume
        cells(B) => d[2] * volume
    end
    @sweep Metropolis(; temperature = 10.0)
end

@potts_model ExtVecRedecl begin
    @extend d = base = ExtVecBase()
    @parameters d[1:2] = [3.0, 4.0]
end

@testset "@extend: a bound vector parameter redeclared keeps its own default (D-114)" begin
    σ = zeros(Int32, 12, 12); σ[3:5, 3:5] .= 1; σ[6:8, 3:6] .= 2
    E(m) = total_energy(PottsProblem(m, [ownership => σ, kind => [:A, :B]], (0, 2); seed = 7))
    @test E(ExtVecBase(; name = :b)) == 104.5                           # 71.5 + 9 + 24
    @test E(ExtVecRedecl(; name = :e)) == 146.5                         # 71.5 + 27 + 48
    @test E(ExtVecRedecl(; name = :e, d = [0.0, 0.0])) == 71.5
    # `#…` names are the constructor's own; a declaration of one is rejected
    @test_throws r"cannot start with `#`" Potts._potts_model(:HashName, quote @parameters var"##kw#λ" = 4.0 end, @__MODULE__)
end

@potts_model BadSiteVar begin
    @kinds medium A
    @parameters T = 1.0
    @variables x(site) = 0.0
    @lattice Lattice((8, 8))
    @energy begin
        cells(A) => (volume - 10.0)^2
        cells(A) => x                      # a site variable without a site
    end
    @sweep Metropolis(; temperature = T)
end
const BAD_ENERGY_LINE = @__LINE__() - 4

@potts_model BadDrive begin
    @kinds medium A
    @parameters T = 1.0
    @lattice Lattice((8, 8))
    @drive copy => volume                  # `volume` changes with the copy
    @sweep Metropolis(; temperature = T)
end
const BAD_DRIVE_LINE = @__LINE__() - 3

@testset "diagnostics name the statement and its source line" begin
    msg(f) = try
        f(); ""
    catch e
        sprint(showerror, e)
    end
    m = msg(() -> mtkcompile(BadSiteVar(; name = :bad)))
    @test occursin("needs a site", m) && occursin("in @energy cells(1) => x", m) &&
          occursin("symbolic.jl:$BAD_ENERGY_LINE", m)
    m = msg(() -> mtkcompile(BadDrive(; name = :bad)))
    @test occursin("`volume` is not available in a drive", m) && occursin("symbolic.jl:$BAD_DRIVE_LINE", m)
    # locations survive `extend`
    m = msg(() -> mtkcompile(extend(PottsSystem(; name = :e, kinds = [:medium, :A], lattice = Potts.lattice_spec((8, 8)),
        sweep = Potts.sweep_spec(:metropolis; temperature = 1.0)), BadSiteVar(; name = :bad))))
    @test occursin("symbolic.jl:$BAD_ENERGY_LINE", m)
end

# Components (M4.1): MTK systems instantiated per cell, advanced by a batched cell ODE kernel.
using Potts.ModelingToolkitBase: System, @parameters
const _tc = Potts.t
Potts.ModelingToolkitBase.@variables y_c(_tc) = 1.0 m_c(_tc) = 0.0
@parameters k_c = 0.3 τ_c = 20.0 r_c = 1.0
@named decay = System([Potts.D(y_c) ~ -k_c * y_c], _tc)
@named clock = System([Potts.D(m_c) ~ r_c / τ_c], _tc)

function component_model()
    @potts_model Decaying begin
        @kinds medium A B
        @parameters T = 1.0
        @components begin
            decay = decay
        end
        @components cells(A) clock = clock
        @equations clock.r_c ~ volume / 25
        @lattice Lattice((20, 20))
        @energy cells => (volume - 25.0)^2
        @divide cells(A) when = clock.m_c >= 1, along = (1.0, 0.0), clock.m_c => 0.0
        @sweep Metropolis(; temperature = T)
    end
    return Decaying(; name = :decaying)
end

@testset "components: MTK systems per cell" begin
    σ = zeros(Int32, 20, 20); σ[3:7, 3:7] .= 1; σ[12:16, 12:16] .= 2
    op = [ownership => σ, kind => [:A, :B]]
    frozen(sys) = PottsProblem(sys, op, (0, 10); T = Float64)
    for (solver, exact, tol) in ((Potts.ExplicitEuler(), t -> (1 - 0.3)^t, 1e-12),
            (Potts.RK4(substeps = 2), t -> (1 + (z = -0.15) + z^2 / 2 + z^3 / 6 + z^4 / 24)^(2t), 1e-12))
        sys = component_model()
        cs = mtkcompile(sys)
        @test Set(Potts.info(v).name for v in cs.sys.variables) == Set([:decay₊y_c, :clock₊m_c])
        @test Set(Potts.info(v).name for v in cs.sys.parameters) == Set([:T, :decay₊k_c, :clock₊τ_c])   # r_c is coupled
        # no copies (T = 0 and frozen cells) so the volume coupling is exact
        prob = remake(PottsProblem(cs, op, (0, 10); ode_solver = solver); p = [:T => 1e-9])
        sol = solve(prob, SequentialCPM(); saveat = 0:10)
        ys = [u.cell.decay₊y_c[1] for u in sol.u]
        @test maximum(abs.(ys .- exact.(0:10))) < tol
        @test all(u -> u.cell.decay₊y_c[2] == u.cell.decay₊y_c[1], sol.u)            # every kind
        @test sol.u[end].cell.clock₊m_c[2] == 0.0                                     # kind-scoped
        @test sol[:decay₊y_c][end] == sol.u[end].cell.decay₊y_c
    end
    # coupling and division: the clock runs at volume/25/τ per MCS and resets on division
    sys = component_model()
    prob = remake(PottsProblem(sys, op, (0, 12)); p = [:T => 1e-9, Symbol("clock₊τ_c") => 8.0])
    sol = solve(prob, SequentialCPM(); saveat = 0:12)
    m = [u.cell.clock₊m_c[1] for u in sol.u]
    @test m[1:8] == (0:7) ./ 8                          # exact: 1/8 per MCS at volume 25
    @test m[9] == 0.0 && sol.u[9].cell.clock₊m_c[3] == 0.0 && count(>(0), sol.u[9].cell.volume) == 3
    @test_throws ArgumentError mtkcompile(Potts.PottsSystem(; name = :x, kinds = [:medium, :A],
        lattice = Potts.lattice_spec((8, 8)), sweep = Potts.sweep_spec(:metropolis; temperature = 1.0),
        components = [Potts.ComponentSpec(:clock, clock, Potts.CellDomain(Int[]))],
        equations = [Potts.Symbolics.variable(Symbol("clock₊nope")) ~ 1.0]))
end

# First-class 3D: the same surface, N-generic generated code.
@potts_model Sorting3D begin
    @kinds medium dark light
    @parameters begin
        λ = 1.0
        V₀ = 64.0
        λₛ = 0.01
        S₀ = 430.0                         # a 4³ cube has 432 NeighborOrder(2) bonds
        T = 12.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    end
    @variables begin
        c(field) = 0.0
        mass(cell) = 1.0
    end
    @lattice Lattice((24, 24, 24); boundary = Closed(), neighborhood = NeighborOrder(2),
        domain = x -> sum(abs2, x .- 12.5) <= 11.5^2)
    @energy begin
        cells(dark, light) => λ * (volume - V₀)^2 + λₛ * (surface - S₀)^2
        contacts => J[kind, kind′]
    end
    @drive copy => -2.0 * (c[target] - c[source]) * (kind[new] == dark)
    @equations D(c) ~ 0.1 * Δ(c) + 0.05 * (kind == dark) - 0.01 * c
    @divide cells(dark) when = (mcs == 3) && (volume >= 40), along = principal_axis(), mass => Split()
    @sweep Metropolis(; temperature = T)
end

@testset "3D models" begin
    σ = zeros(Int32, 24, 24, 24)
    n = 0
    for i in 8:5:13, j in 8:5:13, k in 8:5:13
        n += 1
        σ[i:(i + 3), j:(j + 3), k:(k + 3)] .= n
    end
    kinds = [isodd(c) ? :dark : :light for c in 1:n]
    prob = PottsProblem(Sorting3D(; name = :s3), [ownership => σ, kind => kinds], (0, 6); field_solver = ExplicitEuler())
    @test ndims(prob.lattice) == 3 && length(prob.contact) == 18                      # NeighborOrder(2) in 3D
    @test selfcheck(prob) < 1e-9
    for alg in (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
        u = solve(prob, alg).u[end]
        live = findall(>(0), u.cell.volume)
        @test length(live) > n                                                      # dark cells divided in 3D
        @test u.cell.volume == [count(==(c), u.σ) for c in eachindex(u.cell.volume)]
        @test u.cell.surface ≈ CorePotts.recompute_surface(u.σ, prob.lattice, prob.relations.surface, length(u.cell.volume);
            T = eltype(u.cell.surface))
        @test sum(u.cell.mass[live]) ≈ n
        @test all(u.σ[.!prob.lattice.mask] .== 0)
    end
end

@parameters k_nd
@named nodefault = System([Potts.D(y_c) ~ -k_nd * y_c], _tc)

@potts_model TwoClocks begin
    @kinds medium A B
    @parameters T = 1.0
    @components cells(A) fast = clock
    @components cells(B) slow = clock
    @components dec = decay
    @equations begin
        slow.r_c ~ 0.5
        dec.k_c ~ fast.m_c / 10                      # a coupling reading another component
    end
    @observed om(cell) ~ slow.m_c
    @lattice Lattice((20, 20))
    @energy cells => (volume - 25.0)^2
    @sweep Metropolis(; temperature = T)
end

@testset "component and domain review regressions" begin
    σ = zeros(Int32, 20, 20); σ[3:7, 3:7] .= 1; σ[12:16, 12:16] .= 2
    op = [ownership => σ, kind => [:A, :B]]
    # components are named by their binding, whatever the system is called
    p = remake(PottsProblem(TwoClocks(; name = :two), op, (0, 4)); p = [:T => 1e-9])
    @test Set(propertynames(p.p)) == Set([:T, :fast₊τ_c, :fast₊r_c, :slow₊τ_c])
    sol = solve(p, SequentialCPM(); saveat = 0:4)
    u = sol.u[end]
    @test u.cell.fast₊m_c ≈ [4 / 20, 0] && u.cell.slow₊m_c ≈ [0, 0.5 * 4 / 20]
    @test sol[:om][end] == u.cell.slow₊m_c
    @test u.cell.dec₊y_c[1] ≈ prod(1 - m / 10 for m in (0:3) ./ 20)             # Euler with k = m(t)/10
    # couplings target component parameters only
    @potts_model BadCoupling begin
        @kinds medium A
        @parameters T = 1.0
        @components clock = clock
        @equations clock.m_c ~ volume
        @lattice Lattice((8, 8))
        @sweep Metropolis(; temperature = T)
    end
    @test_throws ArgumentError mtkcompile(BadCoupling(; name = :b))
    # component values without defaults must be given
    @potts_model NoDefault begin
        @kinds medium A
        @parameters T = 1.0
        @components nd = nodefault
        @lattice Lattice((8, 8))
        @sweep Metropolis(; temperature = T)
    end
    σ8 = zeros(Int32, 8, 8); σ8[3:5, 3:5] .= 1
    @test_throws ArgumentError PottsProblem(NoDefault(; name = :n), [ownership => σ8, kind => [1]], (0, 1))
    pn = PottsProblem(NoDefault(; name = :n), [ownership => σ8, kind => [1], Symbol("nd₊k_nd") => 0.5], (0, 1))
    @test pn.p.nd₊k_nd == 0.5
    # kind tables must cover every kind (an extension adding kinds)
    @potts_model MoreKinds begin
        @extend base = Sorting()
        @kinds medium dark light extra
    end
    σg, kg = graner_state()
    @test_throws ArgumentError PottsProblem(MoreKinds(; name = :m), [ownership => σg, kind => kg], (0, 1))
    # models with domains fingerprint by content: checkpoints resume across rebuilds
    σd = zeros(Int32, 40, 40); σd[9:32, 9:32] .= first(two_kind_blocks())
    kd = last(two_kind_blocks())
    p1 = PottsProblem(DiskSorting(; name = :disk), [ownership => σd, kind => kd], (0, 6); field_solver = ExplicitEuler())
    p2 = PottsProblem(DiskSorting(; name = :disk), [ownership => σd, kind => kd], (0, 6); field_solver = ExplicitEuler())
    @test p1.f.fingerprint == p2.f.fingerprint && DiskSorting(; name = :a).lattice == DiskSorting(; name = :b).lattice
    integ = init(p1, SequentialCPM()); foreach(_ -> step!(integ), 1:3)
    ck = checkpoint(integ)
    @test solve!(init(p2, SequentialCPM(); checkpoint = ck)).u[end].σ == solve(p1, SequentialCPM()).u[end].σ
    # site populations stay inside the domain
    @test observe(p1, Potts._fold_iter(count, s -> true, Potts.sites, nothing)) == count(DiskSorting(; name = :d).lattice.domain)
end

module UserFunctions
using Potts
using Potts: Symbolics
hill(x, K) = x^2 / (K^2 + x^2)
Symbolics.@register_symbolic hill(x, K)
@potts_model Hill begin
    @kinds medium A
    @parameters T = 5.0
    @variables g(cell) = 0.5
    @lattice Lattice((16, 16))
    @energy cells => (volume - 20.0 * hill(g, 0.5))^2
    @after_mcs g ~ Pre(g) + 0.1 * hill(volume, 10.0)
    @sweep Metropolis(; temperature = T)
end
end

@testset "user-registered functions in generated code" begin
    σ = zeros(Int32, 16, 16); σ[5:9, 5:9] .= 1
    p = PottsProblem(UserFunctions.Hill(; name = :h), [ownership => σ, kind => [1]], (0, 5))
    @test selfcheck(p) < 1e-9
    u = solve(p, SequentialCPM()).u[end]
    @test u.cell.g[1] > 0.5
end

@potts_model Noisy begin
    @kinds medium A
    @parameters T = 1.0
    @variables begin
        u(cell) = 0.0
        w(site) = 0.0
        tally(model) = 0.0
    end
    @lattice Lattice((16, 16))
    @after_mcs begin
        u ~ rand()
        w ~ rand()
        tally ~ Pre(tally) + rand()
    end
    @divide cells(A) when = (mcs == 2) && (rand() < 0.5), along = RandomPlane()
    @sweep Metropolis(; temperature = T)
end

@testset "rand(): counter-based draws in updates and divisions" begin
    σ = zeros(Int32, 16, 16)
    for (c, (i, j)) in enumerate(Iterators.product(1:4:13, 1:4:13))
        σ[i:(i + 2), j:(j + 2)] .= c
    end
    p = PottsProblem(Noisy(; name = :n), [ownership => σ, kind => fill(1, 16)], (0, 4); seed = 3)
    s1 = solve(p, SequentialCPM(); saveat = 0:4)
    s2 = solve(p, CheckerboardCPM(); saveat = 0:4)
    live = findall(c -> s1.u[end].cell.volume[c] > 0 && s2.u[end].cell.volume[c] > 0, 1:16)
    @test s1.u[end].cell.u[live] == s2.u[end].cell.u[live] && s1.u[end].site.w == s2.u[end].site.w &&
          s1.u[end].model.tally == s2.u[end].model.tally                                # schedule-independent
    @test s1.u[2].cell.u != s1.u[3].cell.u                                                # fresh every MCS
    w = s1.u[end].site.w
    @test length(unique(w)) == length(w) && abs(sum(w) / length(w) - 0.5) < 0.05          # per site, uniform
    @test 0 < s1.stats.lifecycle.divisions < 16                                           # about half divide
    @test s1.u[end].cell.u != solve(remake(p; seed = 4), SequentialCPM()).u[end].cell.u
    @potts_model RandomEnergy begin
        @kinds medium A
        @parameters T = 1.0
        @lattice Lattice((8, 8))
        @energy cells => (volume - 10 * rand())^2
        @sweep Metropolis(; temperature = T)
    end
    @test_throws ArgumentError mtkcompile(RandomEnergy(; name = :r))
end

@potts_model Persistent begin
    @kinds medium A
    @parameters μ = 0.0 T = 2.0
    @variables begin
        px(cell) = 0.0
        py(cell) = 0.0
        cx(cell) = 0.0
        cy(cell) = 0.0
    end
    @lattice Lattice((48, 48); neighborhood = Moore(1))
    @energy begin
        Volume(A; target = 25.0, strength = 2.0)
        contacts => 4 * (kind != kind′)
    end
    @drive copy => -μ * (px[new] * displacement(new, 1) + py[new] * displacement(new, 2) +
                         px[old] * displacement(old, 1) + py[old] * displacement(old, 2))
    @after_mcs begin
        px ~ ifelse(mcs == 0, 0.0, 0.8 * Pre(px) + 0.2 * (centroid(1) - Pre(cx)))
        py ~ ifelse(mcs == 0, 0.0, 0.8 * Pre(py) + 0.2 * (centroid(2) - Pre(cy)))
        cx ~ centroid(1)
        cy ~ centroid(2)
    end
    @observed x(cell) ~ centroid(1)
    @sweep Metropolis(; temperature = T)
end

@testset "centroid/displacement: persistent motility" begin
    σ = zeros(Int32, 48, 48)
    σ[22:26, 22:26] .= 1
    p = PottsProblem(Persistent(; name = :p), [ownership => σ, kind => [1]], (0, 1); seed = 1)
    st, lat = p.u0, p.lattice
    mean_x(σ, d) = sum(i -> CorePotts.coordinates(lat, i)[d], findall(==(1), vec(σ))) / count(==(1), σ)
    @test CorePotts.centroid(Float64, st.cell, lat, 1) == (mean_x(σ, 1), mean_x(σ, 2))
    for (x, new, old) in (((27, 24), 1, 0), ((22, 23), 0, 1))           # add / remove a site
        prop = CorePotts.Proposal{2}(0, 0, x, 0, Int32(old), Int32(new))
        σ2 = copy(σ); σ2[x...] = new
        for k in 1:2
            @test Potts._displacement_axis(Float64, st.cell, lat, prop, 1, k) ≈ mean_x(σ2, k) - mean_x(σ, k)
            @test Potts._displacement_axis(Float64, st.cell, lat, prop, 2, k) == 0
        end
    end
    s = solve(p, SequentialCPM())
    @test s[:x][end][1] ≈ s.u[end].cell.cx[1]
    function travel(μ)
        d = map(1:6) do seed
            u = solve(remake(p; p = [:μ => μ], tspan = (0, 60), seed), SequentialCPM()).u[end]
            hypot(u.cell.cx[1] - 24, u.cell.cy[1] - 24)
        end
        return sum(d) / length(d)
    end
    @test travel(1000.0) > 2 * travel(0.0)
    @potts_model BadCentroid begin
        @kinds medium A
        @lattice Lattice((8, 8))
        @drive copy => centroid(1)
        @sweep Metropolis(; temperature = 1.0)
    end
    @test_throws Exception mtkcompile(BadCentroid(; name = :b))
end

@testset "symbolic setters: setp and setu on integrators" begin
    σ = zeros(Int32, 48, 48); σ[22:26, 22:26] .= 1
    p = PottsProblem(Persistent(; name = :p), [ownership => σ, kind => [1]], (0, 6); seed = 2)
    integ = init(p, SequentialCPM())
    step!(integ)
    # parameters: same isbits type (nothing recompiles), effective from the next MCS
    P = typeof(integ.p)
    integ.ps[:μ] = 700
    @test integ.ps[:μ] === 700.0 && typeof(integ.p) === P
    setp(integ, :μ)(integ, 800.0)
    @test getp(integ, :μ)(integ) == 800.0
    @test_throws ArgumentError setp(p, :μ)(p, 1.0)                       # problems: remake
    # state: declared variables write through to the live state; built-ins are read-only
    integ[:px] = [0.5]
    @test integ.state.cell.px == [0.5] && integ[:px] == [0.5] && getu(integ, :px)(integ) == [0.5]
    setu(integ, :py)(integ, -0.25)
    @test integ.state.cell.py == [-0.25]
    @test_throws DimensionMismatch (integ[:px] = [1.0, 2.0])
    @test_throws Exception (integ[:volume] = [3])
    # a built-in in a list setter is read-only, not unknown (D-116); nothing is set
    for f in (() -> setu(integ, [:kind, :μ]), () -> setp(integ, [:μ, :volume]))
        e = try
            f(); nothing
        catch err
            err
        end
        @test e isa ArgumentError && occursin("read-only", sprint(showerror, e))
    end
    e = try
        setu(integ, [:zz, :μ]); nothing
    catch err
        err
    end
    @test e isa ArgumentError && !occursin("read-only", sprint(showerror, e))   # control: unknown
    @test integ.ps[:μ] == 800.0
    sol = solve!(integ)
    @test sol[:x][end][1] ≈ sol.u[end].cell.cx[1]                     # observed still derived
    @test sol[:px][end] == sol.u[end].cell.px
    SII = Potts.SymbolicIndexingInterface
    @test SII.is_variable(p.f.sys, :px) && !SII.is_variable(p.f.sys, :volume) && SII.is_observed(p.f.sys, :volume)
    @potts_model Counter begin
        @kinds medium A
        @variables n(model) = 0.0
        @lattice Lattice((8, 8))
        @after_mcs n ~ Pre(n) + 1
        @sweep Metropolis(; temperature = 1.0)
    end
    σc = zeros(Int32, 8, 8); σc[3:5, 3:5] .= 1
    ic = init(PottsProblem(Counter(; name = :c), [ownership => σc, kind => [1]], (0, 5)), SequentialCPM())
    step!(ic); step!(ic)
    @test ic[:n] == 2
    ic[:n] = 10
    step!(ic)
    @test ic[:n] == 11
end

@testset "centroid/displacement/rand review regressions" begin
    _bad(body) = eval(:(@potts_model _Bad begin
        @kinds medium A
        @variables cz(cell) = 0.0
        @lattice Lattice((8, 8))
        $(body)
        @sweep Metropolis(; temperature = 1.0)
    end))
    bad(body) = Base.invokelatest(_bad(body); name = :b)
    @test_throws ArgumentError mtkcompile(bad(:(@drive copy => -displacement(new, 3))))   # 2D: no axis 3
    @test_throws ArgumentError mtkcompile(bad(:(@after_mcs cz ~ centroid(3))))
    @test_throws ArgumentError mtkcompile(bad(:(@energy cells => 100 * (centroid(1) - 5)^2)))
    @test_throws ArgumentError mtkcompile(bad(:(@observed r ~ rand())))
    # empty cell slots observe a zero centroid, not NaN
    σ = zeros(Int32, 48, 48); σ[22:26, 22:26] .= 1
    p = PottsProblem(Persistent(; name = :p), [ownership => σ, kind => [1]], (0, 2); capacity = 4)
    x = solve(p, SequentialCPM())[:x][end]
    @test length(x) == 4 && x[2:4] == zeros(3) && !any(isnan, x)
end

# A model built inside an `@extend` base's body is a build of its own: it neither continues
# the outer numbering nor changes the lattice dimension `centroid()` reads afterwards.
@potts_model _Helper3D begin
    @kinds medium A
    @variables q(cell) = 0.0
    @lattice Lattice((6, 6, 6))
    @after_mcs q ~ rand() + rand()
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model _BuildsHelper begin
    @kinds medium A
    @variables p(cell)[1:2] = 0.0 w(cell) = 0.0
    @lattice Lattice((12, 8))
    helper = _Helper3D(; name = :h)
    @after_mcs w ~ rand()
    @after_mcs p ~ centroid()
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model _ExtendsBuilder begin
    @kinds medium A
    @variables v(cell) = 0.0
    @extend b = _BuildsHelper()
    @after_mcs v ~ rand()
    @sweep Metropolis(; temperature = 1.0)
end

@testset "a model built inside an @extend base has its own build state" begin
    draws(sys) = sort!([parse(Int, m[1]) for m in eachmatch(r"random_uniform\((\d+)\)", string(sys.updates))])
    s = _ExtendsBuilder(; name = :o)                 # threw a DimensionMismatch (3D helper's dim leaked)
    @test draws(s) == [1, 2]                         # base's draw, then the extension's: the helper's two draws are its own
    @test draws(_Helper3D(; name = :h)) == [1, 2]
    @test length(s.lattice.dims) == 2
    @test count(u -> occursin("cell_centroid", string(u.eq)), s.updates) == 2   # p is 2D, not 3D
    @test draws(_BuildsHelper(; name = :b)) == [1]   # serial build of the base alone is unchanged
end

@potts_model Lags begin
    @kinds medium A
    @variables begin
        n(model) = 0.0
        lag3(model) = -1.0
        w(site) = 0.0
        wlag(site) = -1.0
        u(cell) = 0.0
    end
    @lattice Lattice((8, 8))
    @after_mcs begin
        n ~ Pre(n) + 1
        lag3 ~ Pre(n, 3)
        w ~ Pre(w) + 1
        wlag ~ Pre(w, 2) - Pre(w, 1)
    end
    @sweep Metropolis(; temperature = 1.0)
end

@testset "history lags: Pre(x, k)" begin
    σ = zeros(Int32, 8, 8); σ[3:5, 3:5] .= 1
    p = PottsProblem(Lags(; name = :l), [ownership => σ, kind => [1]], (0, 8))
    @test size(p.u0.history.n) == (1, 3) && size(p.u0.history.w) == (8, 8, 2)
    sol = solve(p, SequentialCPM(); saveat = 0:8)
    for m in 1:8                       # after m MCS: n = m; lag3 = n at the end of MCS m - 1 - 3
        u = sol.u[m + 1]
        @test u.model.n[1] == m
        @test u.model.lag3[1] == max(m - 3, 0)
        @test all(==(m == 1 ? 0 : -1), u.site.wlag)                 # w(end m - 3) - w(end m - 2)
    end
    for body in (:(@after_mcs u ~ Pre(u, 2)), :(@energy cells => Pre(volume, 2)), :(@observed q ~ Pre(n, 2)))
        m = eval(:(@potts_model _BadLag begin
            @kinds medium A
            @variables begin
                u(cell) = 0.0
                n(model) = 0.0
            end
            @lattice Lattice((8, 8))
            $(body)
            @sweep Metropolis(; temperature = 1.0)
        end))
        @test_throws ArgumentError mtkcompile(Base.invokelatest(m; name = :b))
    end
end

@potts_model Integrals begin
    @kinds medium A
    @variables begin
        w(site) = 0.0
        mass(cell) = 0.0
        hot(cell) = 0.0
        n(model) = 0.0
    end
    @lattice Lattice((20, 20))
    @energy cells => (volume - 16)^2
    @after_mcs begin
        mass ~ integral(w)
        hot ~ integral(w > 0.5) / volume
        n ~ Pre(n) + 1
    end
    @observed begin
        cmass(cell) ~ integral(w)
        occupied(cell) ~ integral(1)
    end
    @sweep Metropolis(; temperature = 2.0)
end

@testset "integral(x): per-cell site reductions" begin
    σ = zeros(Int32, 20, 20); σ[3:6, 3:6] .= 1; σ[12:15, 12:15] .= 2
    w0 = [Float64(i + j) / 40 for i in 1:20, j in 1:20]
    p = PottsProblem(Integrals(; name = :i), [ownership => σ, kind => [1, 1], :w => w0], (0, 5))
    @test p[:cmass] ≈ [sum(w0[σ .== k]) for k in 1:2] && p[:occupied] == [16, 16]   # valid at t0
    sol = solve(p, SequentialCPM(); saveat = 0:5)
    for u in sol.u[2:end]
        @test u.cell.mass ≈ [sum(w0[u.σ .== k]) for k in 1:2]
        @test u.cell.hot ≈ [count(>(0.5), w0[u.σ .== k]) / count(==(k), u.σ) for k in 1:2]
    end
    @test sol[:occupied][end] == sol.u[end].cell.volume                              # integral(1) == volume
    uc = solve(p, CheckerboardCPM()).u[end]
    @test uc.cell.mass ≈ [sum(w0[uc.σ .== k]) for k in 1:2]
    for (body, msg) in ((:(@energy cells => integral(w)), "energies"), (:(@drive copy => integral(w)), "@before_mcs"),
            (:(@on_copy w[target] += integral(w)), "every accepted copy"),                     # D-129, `+=` form
            (:(@on_copy w[target] ~ sum(integral(w) for c in cells if c == new)), "@on_copy"),
            (:(@on_copy w[ifelse(sum(integral(w) for c in cells if c == new) > 0, target, source)] ~ 1.0), "every accepted copy"),
            (:(@on_copy y[ifelse(sum(integral(w) for c in cells if c == new) > 0, new, old)] ~ 1.0), "every accepted copy"))
        m = eval(:(@potts_model _BadIntegral begin
            @kinds medium A
            @variables w(site) = 0.0 y(cell) = 0.0
            @lattice Lattice((8, 8))
            $(body)
            @sweep Metropolis(; temperature = 1.0)
        end))
        err = try mtkcompile(Base.invokelatest(m; name = :b)); nothing catch e; e end
        @test err isa ArgumentError && occursin("integral", sprint(showerror, err)) &&
              occursin(msg, sprint(showerror, err))
    end
end

@potts_model PersistentVec begin
    @kinds medium A
    @parameters μ = 0.0 T = 2.0
    @lattice Lattice((48, 48); neighborhood = Moore(1))
    @variables begin
        pol(cell)[1:2] = 0.0
        c(cell)[1:2] = 0.0
    end
    @energy begin
        Volume(A; target = 25.0, strength = 2.0)
        contacts => 4 * (kind != kind′)
    end
    @drive copy => -μ * (dot(pol[new], displacement(new)) + dot(pol[old], displacement(old)))
    @after_mcs begin
        pol ~ ifelse(mcs == 0, 0.0, 1.0) .* (0.8 * Pre(pol) + 0.2 * (centroid() - Pre(c)))
        c ~ centroid()
    end
    @observed speed(cell) ~ norm(pol)
    @sweep Metropolis(; temperature = T)
end

@potts_model VectorBits begin
    @kinds medium A
    @parameters begin
        d[1:2] = [1.0, 0.0]
        T = 1.0
    end
    @lattice Lattice((12, 12))
    @variables begin
        g(site)[1:2] = [0.5, -0.5]
        m(model)[1:2] = 0.0
        q(cell)[1:3] = [1.0, 2.0, 3.0]
    end
    @energy cells => (volume - 9)^2
    @after_mcs begin
        m ~ Pre(m) + d
        g ~ normalize(g)
    end
    @divide cells(A) when = mcs == 1, q => Split()
    @sweep Metropolis(; temperature = T)
end

@testset "vector quantities" begin
    σ = zeros(Int32, 48, 48); σ[22:26, 22:26] .= 1
    for μ in (0.0, 1000.0)
        a = solve(PottsProblem(Persistent(; name = :a, μ), [ownership => σ, kind => [1]], (0, 30); seed = 5), SequentialCPM())
        b = solve(PottsProblem(PersistentVec(; name = :b, μ), [ownership => σ, kind => [1]], (0, 30); seed = 5), SequentialCPM())
        @test a.u[end].σ == b.u[end].σ                                          # same model, same run
        @test a.u[end].cell.px ≈ b.u[end].cell.pol_1 && a.u[end].cell.cy ≈ b.u[end].cell.c_2
        @test b[:speed][end] ≈ hypot.(b.u[end].cell.pol_1, b.u[end].cell.pol_2)
    end
    σ2 = zeros(Int32, 12, 12); σ2[4:6, 4:6] .= 1
    p = PottsProblem(VectorBits(; name = :v), [ownership => σ2, kind => [1]], (0, 3); capacity = 4)
    @test p.p.d_1 == 1.0 && p.p.d_2 == 0.0 && p.u0.cell.q_3[1] == 3.0 && all(==(0.5), p.u0.site.g_1)
    u = solve(p, SequentialCPM()).u[end]
    @test u.model.m_1[1] == 3 && u.model.m_2[1] == 0
    @test all(x -> x ≈ sqrt(0.5), u.site.g_1) && all(x -> x ≈ -sqrt(0.5), u.site.g_2)
    live = findall(>(0), u.cell.volume)
    @test length(live) == 2 && sum(u.cell.q_2[live]) ≈ 2.0                    # Split() per component
    q = remake(p; p = [:d => [0.0, 2.0]])
    @test q.p.d_1 == 0.0 && q.p.d_2 == 2.0
    r = PottsProblem(VectorBits(; name = :v, d = [5.0, 6.0]), [ownership => σ2, kind => [1], :q => [(7.0, 8.0, 9.0)],
        :g => fill(1.0, 12, 12, 2)], (0, 1))
    @test r.p.d_2 == 6.0 && r.u0.cell.q_2[1] == 8.0 && all(==(1.0), r.u0.site.g_2)
    @test_throws ArgumentError PottsProblem(VectorBits(; name = :v), [ownership => σ2, kind => [1], :q => [1.0, 2.0]], (0, 1))
end

@potts_model Fresh begin
    @kinds medium A
    @parameters k = 1.0
    @variables begin
        w(site) = 1.0
        mb(cell) = 0.0
        n(model) = 0.0
        d1(site) = -1.0
    end
    @lattice Lattice((16, 16))
    @energy cells => (volume - 44)^2
    @before_mcs mb ~ integral(k * w)
    @after_mcs begin
        w ~ Pre(w) + 1
        n ~ Pre(n) + 1
        d1 ~ Pre(n, 1) - Pre(n, 2)
    end
    @divide cells(A) when = volume > 40, along = RandomPlane()
    @observed begin
        cmass(cell) ~ integral(w)
        occ(cell) ~ integral(1)
    end
    @sweep Metropolis(; temperature = 1.0)
end

@testset "integral and lag review regressions" begin
    σ = zeros(Int32, 16, 16); σ[3:8, 3:8] .= 1
    p = PottsProblem(Fresh(; name = :f), [ownership => σ, kind => [1]], (0, 4); capacity = 8)
    sol = solve(p, SequentialCPM(); saveat = 0:4)
    brute(u, x) = [sum(x[u.σ .== c]; init = 0.0) for c in eachindex(u.cell.volume)]
    names = [Potts._integral_name(x) for x in Potts._integrals(p.f.sys.csys.sys)]
    for (t, u) in zip(sol.t, sol.u)
        @test sol[:cmass][t + 1] ≈ brute(u, u.site.w)                 # observed: the saved state itself
        @test sol[:occ][t + 1] == u.cell.volume                        # after division too
        fresh = Potts._fresh_integrals(Float64, u, p.p, p.f.sys.ctx, t, Potts._integral_phases(p.f.sys.csys, Float64), names)
        @test all(n -> getfield(u.cell, n) ≈ getfield(fresh.cell, n), names)   # stored = recomputed at the boundary
    end
    @test sol.stats.lifecycle.divisions >= 1
    @test sol.u[3].model.n[1] == 2 && all(==(1), sol.u[3].site.d1)       # Pre(n, 1) - Pre(n, 2) = 1
    # before-MCS reads see the state at the MCS boundary (at init: the initial state), also after remake
    u1 = solve(remake(p; tspan = (0, 1)), SequentialCPM()).u[end]
    @test u1.cell.mb[1] ≈ 36
    q = remake(p; p = [:k => 5.0], u0 = [ownership => σ, kind => [1], :w => 2.0], tspan = (0, 1))
    @test q[:cmass] ≈ [72; zeros(7)]
    @test solve(q, SequentialCPM()).u[end].cell.mb[1] ≈ 5 * 72
end

# P6.0m (D-042): an integral read in a block that writes its operand bare folds the new
# values; readers after the block (equations, the temperature) see them too.
@potts_model FreshIntegrals begin
    @kinds medium A
    @variables begin
        w(site) = 0.0
        u(site) = 0.0
        sb(cell) = 0.0
        sa(cell) = 0.0
        s2(cell) = 0.0
        r(cell) = 0.0
    end
    @lattice Lattice((12, 12))
    @energy cells => (volume - 16)^2
    @before_mcs begin
        w ~ Pre(w) + 1
        sb ~ integral(w)
    end
    @after_mcs begin
        u ~ Pre(u) + 1
        sa ~ integral(u) + integral(w)
    end
    @after_mcs Every(2) s2 ~ integral(2u)
    @equations D(r) ~ integral(u)
    @sweep Metropolis(; temperature = 0.0)
end

@testset "integral(x) is fresh after a write in the same block (P6.0m, D-042)" begin
    # a 4×4 cell at T = 0 keeps its 16 sites (every copy costs +1); after MCS k, w = u = k
    σ = zeros(Int32, 12, 12); σ[4:7, 4:7] .= 1
    for alg in (SequentialCPM(), CheckerboardCPM())
        sol = solve(PottsProblem(FreshIntegrals(; name = :f), [ownership => σ, kind => [:A]], (0, 4)), alg; saveat = 0:4)
        k = 0:4
        @test [Array(u.cell.volume)[1] for u in sol.u] == fill(16, 5)
        @test [Array(u.cell.sb)[1] for u in sol.u] == 16.0 .* k                    # before block
        @test [Array(u.cell.sa)[1] for u in sol.u] == 32.0 .* k                    # after block, two integrals
        # gated reader (Every(2) runs in MCS 1, 3): 2·16k fresh; stale would be 0, 0, 0, 64, 64
        @test [Array(u.cell.s2)[1] for u in sol.u] == [0, 32, 32, 96, 96]
        # the equation (explicit Euler, dt = 1) integrates the fresh value: Σ_{j ≤ k} 16 j
        @test [Array(u.cell.r)[1] for u in sol.u] == [16.0 * sum(1:j; init = 0) for j in k]
        @test [16.0 * sum(0:(j - 1); init = 0) for j in k] != [16.0 * sum(1:j; init = 0) for j in k]   # stale differs
    end
    # no extra pass: w (not written after the sweep) once at the start of the after block;
    # u once before `sa` (which also serves the ODE); 2u gated with its reader; w once before `sb`
    c = mtkcompile(FreshIntegrals(; name = :f))
    ph = Potts._phases(c, Float64, Dict{Any, Any}(Potts._unwrap(x) => Potts.info(x).default for x in c.sys.parameters),
        Potts._resolve_solvers(c))
    reduces(t) = count(x -> x isa CorePotts.CellReduce || (x isa Potts._Gated && x.phase isa CorePotts.CellReduce), t)
    @test reduces(ph.before_mcs) == 1                  # w written, sb reads it
    @test reduces(ph.after_mcs) == 3
    @test count(x -> x isa Potts._Gated && x.phase isa CorePotts.CellReduce, ph.after_mcs) == 1
end

# P6.0m3 (D-042, D-076): `integral(Pre(w))` is its own slot, refreshed at the start of the
# after block (σ post-sweep, w at its block-start value). It needs no `w__pre` snapshot and
# is left intact when another read does snapshot `w`; in @before_mcs the boundary refresh is
# already the block-start fold.
@potts_model IntegralPre begin
    @kinds medium A
    @variables begin
        w(site) = 0.0
        v(site) = 0.0
        x(site) = 0.0
        s(cell) = 0.0
        sb(cell) = 0.0
        f(cell) = 0.0
    end
    @lattice Lattice((12, 12))
    @energy cells => (volume - 16)^2
    @before_mcs begin
        sb ~ integral(Pre(x))
        x ~ Pre(x) + 1
    end
    @after_mcs begin
        v ~ Pre(w)                              # another update reads Pre(w): snapshots w
        s ~ integral(Pre(w)) + integral(Pre(v))
        w ~ Pre(w) + 1
        f ~ integral(w)
    end
    @sweep Metropolis(; temperature = 0.0)
end

@testset "integral(Pre(w)) folds the block-start values (P6.0m3, D-042)" begin
    σ = zeros(Int32, 12, 12); σ[4:7, 4:7] .= 1
    c = mtkcompile(IntegralPre(; name = :ip))
    @test (:site, :w) in c.pre_snapshots[:after_mcs]                    # from `v`, not from `s`
    @test !any(t -> last(t) === :v, c.pre_snapshots[:after_mcs])       # `v` read only in an integral
    @test isempty(c.pre_snapshots[:before_mcs])
    # a snapshotted `Pre(w)` both outside and inside an integral: only the outside one is rewritten
    w = only(filter(x -> Potts.info(x).name === :w, c.sys.variables))
    snap = Dict{Symbol, Any}(:w => Potts._standin(:site, :w__pre))
    iw = Potts._unwrap(Potts._integral(Potts.Pre(w)))
    @test isequal(Potts._to_snapshots(Potts._unwrap(Potts.Pre(w) + iw), snap, _ -> false), Potts._unwrap(snap[:w] + iw))
    ph = Potts._phases(c, Float64, Dict{Any, Any}(), Potts._resolve_solvers(c))
    reduces(t) = count(x -> x isa CorePotts.CellReduce, t)
    @test reduces(ph.before_mcs) == 0                  # the boundary refresh serves `sb`
    # Pre(w), Pre(v) at the start (read by the after block); w after its writer. Pre(x) is
    # read only by the before block: fresh from the previous boundary (D-120)
    @test reduces(ph.after_mcs) == 3
    i1 = findfirst(x -> x isa CorePotts.CellReduce, ph.after_mcs)
    @test i1 < findfirst(x -> x isa CorePotts.CopyPhase, ph.after_mcs)  # refreshed before the snapshot copy
    for alg in (SequentialCPM(), CheckerboardCPM())
        sol = solve(PottsProblem(IntegralPre(; name = :ip), [ownership => σ, kind => [:A]], (0, 4)), alg; saveat = 0:4)
        k = 0:4
        @test [Array(u.cell.volume)[1] for u in sol.u] == fill(16, 5)
        # s = Σ w_start + Σ v_start; w_start = k - 1, v_start = k - 2 (v lags w by one MCS)
        @test [Array(u.cell.s)[1] for u in sol.u] == [j == 0 ? 0.0 : 16.0 * ((j - 1) + max(j - 2, 0)) for j in k]
        @test [Array(u.cell.f)[1] for u in sol.u] == 16.0 .* k                       # fresh (D-076)
        @test [Array(u.cell.sb)[1] for u in sol.u] == [16.0 * max(j - 1, 0) for j in k]  # before block
    end
    integ = init(PottsProblem(IntegralPre(; name = :ip), [ownership => σ, kind => [:A]], (0, 100)), SequentialCPM())
    warm() = (step!(integ); @allocated step!(integ))
    @test minimum(warm() for _ in 1:5) == 0

    # misuse: an integral mixing Pre and bare reads of block-written variables; and
    # `integral(Pre(w))` outside update blocks, where Pre is the stored value
    for body in (:(@after_mcs begin
                     w ~ Pre(w) + 1
                     s ~ integral(Pre(w) + w)
                 end),
                 :(@after_mcs begin
                     w ~ Pre(w) + 1
                     s ~ integral(Pre(w) * f)
                     f ~ Pre(f)
                 end),
                 :(@equations D(r) ~ integral(Pre(w))),
                 :(@divide cells(A) when = integral(Pre(w)) > 100),
                 :(@observed q(cell) ~ integral(Pre(w))))
        m = eval(:(@potts_model _BadIntegralPre begin
            @kinds medium A
            @variables begin
                w(site) = 0.0
                f(site) = 0.0
                s(cell) = 0.0
                r(cell) = 0.0
            end
            @lattice Lattice((8, 8))
            @energy cells => (volume - 16)^2
            $(body)
            @sweep Metropolis(; temperature = 1.0)
        end))
        @test_throws ArgumentError mtkcompile(Base.invokelatest(m; name = :b))
    end
    p = PottsProblem(IntegralPre(; name = :ip), [ownership => σ, kind => [:A]], (0, 1))
    @test_throws ArgumentError p[Potts._integral(Potts.Pre(w))]
end

# P6.0m: the ring rule is TST's `ConnectivityPreservedP` (Merks reference), not CC3D's local
# rule, so D-074 leaves it alone: at most one arc (zero included) or exactly two ring cells
@potts_model ArcOrPair begin
    @kinds medium A
    @lattice Lattice((12, 12); neighborhood = Moore(1))
    @energy cells => (volume - 1)^2
    @constraint connectivity(A; rule = :arc_or_pair)
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model LocalOne begin
    @kinds medium A
    @lattice Lattice((12, 12); neighborhood = Moore(1))
    @energy cells => (volume - 1)^2
    @constraint connectivity(A)
    @sweep Metropolis(; temperature = 1.0)
end

@testset "connectivity(rule = :arc_or_pair) keeps TST's zero-arc pass (P6.0m, D-074 scope)" begin
    allows(M, σ, x, y) = (p = PottsProblem(M(; name = :r), [ownership => σ, kind => fill(:A, maximum(σ))], (0, 1));
        prop = CorePotts.Proposal(CorePotts.linear_index(p.lattice, x), CorePotts.linear_index(p.lattice, y), x, 1, σ[x...], σ[y...]);
        p.f.constraint(p.u0, p.p, prop, Potts._host_ctx(p)))
    σ = zeros(Int32, 12, 12); σ[6, 6] = 1
    @test allows(ArcOrPair, σ, (6, 6), (7, 6))            # the last site: 0 arcs pass
    @test !allows(LocalOne, σ, (6, 6), (7, 6))            # negative control: the local rule rejects it
    σ[2:3, 2:3] .= 1
    @test allows(ArcOrPair, σ, (6, 6), (7, 6))            # an isolated fragment: 0 arcs pass
    @test !allows(LocalOne, σ, (6, 6), (7, 6))
    σ = zeros(Int32, 12, 12); σ[3:9, 6] .= 1
    @test !allows(ArcOrPair, σ, (6, 6), (6, 7))           # a bridge, one cell on the ring: 2 arcs
    σ[6, 5] = 2
    @test !allows(ArcOrPair, σ, (6, 6), (6, 5))           # 2 arcs, two cells but medium on the ring: refused
    σ = fill(Int32(2), 12, 12); σ[3:9, 6] .= 1
    @test allows(ArcOrPair, σ, (6, 6), (6, 5))            # 2 arcs, exactly two cells and no medium: the pair
    σ = zeros(Int32, 12, 12); σ[3:6, 3:6] .= 1
    @test allows(ArcOrPair, σ, (6, 4), (7, 4))            # an ordinary boundary copy: 1 arc
end

# P6.0m (D-075): `Chemotaxis`'s `when` defaults to `new != 0`; `when = true` is every copy;
# `kinds` requires `kind[new] ∈ kinds`, so retractions stay 0 with `kinds` given
@testset "Chemotaxis `when` (P6.0m, D-075)" begin
    function chemo(dr)
        m = eval(:(@potts_model _ChemoWhen begin
            @kinds medium A
            @variables c(site) = 0.0
            @lattice Lattice((12, 12))
            @energy cells => (volume - 16)^2
            @drive $dr
            @sweep Metropolis(; temperature = 1.0)
        end))
        σ = zeros(Int32, 12, 12); σ[4:7, 4:7] .= 1
        p = PottsProblem(Base.invokelatest(m; name = :c), [ownership => σ, kind => [:A], :c => [Float64(i) for i in 1:12, j in 1:12]], (0, 1))
        d(x, y) = (prop = CorePotts.Proposal(CorePotts.linear_index(p.lattice, x), CorePotts.linear_index(p.lattice, y), x, 1, σ[x...], σ[y...]);
            p.f.delta_H(p.u0, p.p, prop, Potts._host_ctx(p)) - energy_change(p, p.u0, prop))
        return d((7, 5), (8, 5)), d((8, 5), (7, 5))     # (retraction, extension)
    end
    @test all(isapprox.(chemo(:(Chemotaxis(c; strength = 1.0, when = true))), (1.0, -1.0)))      # every copy
    @test all(isapprox.(chemo(:(Chemotaxis(c; strength = 1.0))), (0.0, -1.0)))                    # default new != 0
    @test all(isapprox.(chemo(:(Chemotaxis(c; strength = 1.0, when = old == 0))), (0.0, -1.0)))   # extensions only
    @test all(isapprox.(chemo(:(Chemotaxis(c; strength = 1.0, kinds = (A,), when = true))), (0.0, -1.0)))   # S2
end

# A relation may not take a run-context name CorePotts reserves (`lattice`, `mobility`,
# `spacing`): mtkcompile refuses it with CorePotts' error, before codegen; the declarable
# roles `contact` and `proposal` still build
@testset "reserved relation names are refused at mtkcompile" begin
    function build(name, spec; read = true)
        energy = read ? :(@energy cells => 0.1 * count(owner[n] == id for n in $name(40))) :
                 :(@energy cells => (volume - 16)^2)
        m = Core.eval(@__MODULE__, quote
            @potts_model $(gensym(:Reserved)) begin
                @kinds medium cell
                @lattice Lattice((12, 12); spacing = (1.0, 1.0))
                @relations $name = $spec
                $energy
                @sweep Metropolis(; temperature = 1.0)
            end
        end)
        sys = Base.invokelatest(m; name = :r)
        σ = zeros(Int32, 12, 12); σ[3:6, 3:6] .= 1
        return Base.invokelatest(PottsProblem, sys, [ownership => σ, kind => [:cell]], (0, 1))
    end
    for name in (:spacing, :lattice, :mobility)
        @test_throws r"relation names .*`spacing` are reserved" build(name, :(Moore(2)))
    end
    @test build(:far, :(Moore(2))) isa CorePotts.PottsProblem                       # control: any other name
    @test build(:contact, :(Moore(2)); read = false) isa CorePotts.PottsProblem     # declarable roles build
    @test build(:proposal, :(Moore(1)); read = false) isa CorePotts.PottsProblem
end

# P6.0m (D-075 Q8): `a` and `b` are reserved for every declaration, and for a programmatic
# PottsSystem; the error suggests `a₀`/`b₀`
@testset "`a` and `b` are reserved globally (P6.0m, D-075 Q8)" begin
    expand(body) = Potts._potts_model(:X, body, @__MODULE__)
    for decl in (:(@kinds medium a), :(@kinds medium A b), :(@observed b ~ volume), :(@relations a = Moore(1)),
                 :(@structural_parameters a = 1), :(@relationship b(cell, cell) capacity = 1))
        body = decl.args[1] === Symbol("@kinds") ? quote $decl end : quote @kinds medium A; $decl end
        @test_throws r"`[ab]` is reserved.*`[ab]₀`" expand(body)
    end
    @test expand(quote @kinds medium ka kb; @observed b₀ ~ volume end) isa Expr     # control
    V = Potts.B.volume
    prog(; kinds = [:medium, :cell], variables = Any[]) = Potts.PottsSystem(; name = :prog, kinds,
        lattice = Potts.lattice_spec((12, 12)), variables, energies = [Potts.energy(Potts.cells(1) => (V - 16)^2)],
        sweep = Potts.sweep_spec(:metropolis; temperature = 1.0))
    @test prog() isa Potts.PottsSystem                                               # control
    @test_throws r"variable `b`: `b` is reserved" prog(; variables = Any[Potts.variable(only(Potts.Symbolics.@variables b(Potts.t)), :cell; default = 0.0)])
    @test_throws r"kind `a`: `a` is reserved" prog(; kinds = [:medium, :a])
end

@potts_model Compound begin
    @kinds medium A
    @variables begin
        n(model) = 0.0
        g(model) = 1.0
        hits(site) = 0.0
        v(cell)[1:2] = 0.0
    end
    @lattice Lattice((10, 10))
    @energy cells => (volume - 9)^2
    @on_copy hits[target] += 1
    @after_mcs begin
        n += 1
        n += 2
        n -= 0.5
        g *= 2
        v += [1.0, -1.0]
    end
    @sweep Metropolis(; temperature = 4.0)
end

@potts_model CompoundBase begin
    @kinds medium A
    @variables n(model) = 0.0
    @lattice Lattice((10, 10))
    @after_mcs n += 1
    @observed twice ~ 2n
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model CompoundExt begin
    @extend n = base = CompoundBase()
    @kinds medium A
    @after_mcs n += 10                 # replaces the base's update of `n`
    @observed twice ~ 3n               # and its observed `twice`
end

@testset "compound assignments, single writers, replacement" begin
    σ = zeros(Int32, 10, 10); σ[4:6, 4:6] .= 1
    sol = solve(PottsProblem(Compound(; name = :c), [ownership => σ, kind => [1]], (0, 4)), SequentialCPM())
    u = sol.u[end]
    @test u.model.n[1] == 4 * 2.5 && u.model.g[1] == 16
    @test u.cell.v_1[1] == 4 && u.cell.v_2[1] == -4
    @test sum(u.site.hits) == sol.stats.accepted                            # one per accepted copy
    s2 = solve(PottsProblem(CompoundExt(; name = :e), [ownership => σ, kind => [1]], (0, 3)), SequentialCPM())
    @test s2.u[end].model.n[1] == 30 && s2[:twice][end] == 90
    bad(body) = Base.invokelatest(eval(:(@potts_model _BadW begin
        @kinds medium A
        @variables n(model) = 0.0
        @lattice Lattice((8, 8))
        $(body)
        @sweep Metropolis(; temperature = 1.0)
    end)); name = :b)
    @test_throws ArgumentError mtkcompile(bad(:(@after_mcs begin
        n ~ 1.0
        n ~ 2.0
    end)))                                                                  # two writers
    @test_throws LoadError bad(:(@after_mcs begin
        n ~ 1.0
        n += 2.0
    end))                                                                  # at macro expansion
    @test_throws LoadError bad(:(@after_mcs begin
        n += 1.0
        n *= 2.0
    end))                                                                  # at macro expansion
    ok = Base.invokelatest(eval(:(@potts_model _OkW begin
        @kinds medium A
        @variables n(model) = 0.0
        @lattice Lattice((8, 8))
        @after_mcs n += 1
        @after_mcs Every(5) n ~ 0.0
        @sweep Metropolis(; temperature = 1.0)
    end)); name = :ok)
    @test mtkcompile(ok) isa CompiledPottsSystem                             # another cadence
end

Potts.ModelingToolkitBase.@variables drug_c(_tc) = 0.0
@parameters drug_k = 0.2 drug_dose = 0.0
@named drug = System([Potts.D(drug_c) ~ drug_dose - drug_k * drug_c], _tc)

@potts_model Systemic begin
    @kinds medium A
    @variables g(model) = 1.0
    @components model pk = drug
    @equations begin
        D(g) ~ -0.5 * g
        pk.drug_dose ~ count(true for c in cells)           # dosing ∝ the number of live cells
    end
    @lattice Lattice((20, 20))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0)
end

@testset "model-scope ODEs and components" begin
    σ = zeros(Int32, 20, 20); σ[2:4, 2:4] .= 1; σ[10:12, 10:12] .= 2; σ[15:17, 3:5] .= 3
    p = PottsProblem(Systemic(; name = :s), [ownership => σ, kind => [1, 1, 1]], (0, 10); ode_solver = RK4(substeps = 4))
    @test :pk₊drug_c in propertynames(p.u0.model) && :pk₊drug_k in propertynames(p.p)
    for alg in (SequentialCPM(), CheckerboardCPM())
        u = solve(p, alg).u[end]
        x = 0.5 / 4
        @test u.model.g[1] ≈ (1 - x + x^2 / 2 - x^3 / 6 + x^4 / 24)^40 rtol = 1e-12  # RK4, 4 substeps per MCS
        @test u.model.pk₊drug_c[1] ≈ 3 / 0.2 * (1 - exp(-0.2 * 10)) rtol = 1e-5
    end
    @test_throws ArgumentError PottsProblem(Systemic(; name = :s), [ownership => σ, kind => [1, 1, 1], :g => nothing], (0, 1))
end

@potts_model HexSorting begin
    @kinds medium dark light
    @parameters begin
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
        Dc = 0.1
    end
    @variables begin
        c(field) = 0.0
        cx(cell) = 0.0
    end
    @lattice Lattice((30, 30); geometry = Hexagonal(), neighborhood = Hex(2))
    @energy begin
        cells => (volume - 19)^2 + 0.2 * (surface - 60)^2
        contacts => J[kind, kind′]
    end
    @equations D(c) ~ Dc * Δ(c)
    @after_mcs cx ~ centroid(1)
    @sweep Metropolis(; temperature = 8.0)
end

@testset "hexagonal lattices in the surface" begin
    σ = zeros(Int32, 30, 30); c0 = zeros(30, 30); c0[15, 15] = 100.0
    n = 0
    for q in 4:6:26, r in 4:6:26
        n += 1
        for x in CartesianIndices(σ)
            CorePotts._hexdist(Tuple(x) .- (q, r)) <= 2 && (σ[x] = n)
        end
    end
    p = PottsProblem(HexSorting(; name = :h), [ownership => σ, kind => [isodd(k) ? :dark : :light for k in 1:n], :c => c0], (0, 20);
        field_solver = ExplicitEuler())
    @test p.lattice.geometry isa Hexagonal && length(p.contact) == 18
    for alg in (SequentialCPM(proposal = Hex(1)), CheckerboardCPM(proposal = Hex(1)))
        u = solve(p, alg).u[end]
        @test u.cell.volume == [count(==(k), u.σ) for k in 1:n]
        @test u.cell.surface ≈ CorePotts.recompute_surface(u.σ, p.lattice, p.relations.surface, n)
        @test sum(u.site.c) ≈ 100                                          # zero-sum 6-point Laplacian
        pos = [embed(p.lattice, Float64.(Tuple(x))) for x in CartesianIndices(u.σ)]
        k = findfirst(>(0), u.cell.volume)
        mine = pos[u.σ .== k]
        @test u.cell.cx[k] ≈ sum(first, mine) / length(mine) atol = 1e-9   # centroid() is Cartesian (no wrap here)
    end
end

@potts_model CadenceBase begin
    @kinds medium A
    @variables n(model) = 0.0
    @lattice Lattice((8, 8))
    @after_mcs n += 1
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model CadenceExt begin
    @extend n = base = CadenceBase()
    @kinds medium A
    @after_mcs Every(5) n ~ 0.0             # replaces the base's update despite the cadence (D-045)
end

@testset "replacement is by target; a changed cadence warns (D-045)" begin
    σ = zeros(Int32, 8, 8); σ[3:5, 3:5] .= 1
    sys = @test_logs (:warn, r"replaces the base's Every\(1\)") CadenceExt(; name = :c)
    @test solve(PottsProblem(sys, [ownership => σ, kind => [1]], (0, 4)), SequentialCPM()).u[end].model.n[1] == 0
end

# ---------------------------------------------------------------------------------------
# P6.0e: contact energies read site values `x` (at s) and `x′` (at s′)

using Statistics: Statistics

@potts_model SiteContacts begin
    @structural_parameters begin
        dims = (24, 24)
        geometry = CorePotts.Square()
        near = Moore(1)
        far = Moore(2)
    end
    @kinds medium A B
    @parameters begin
        λ = 1.0
        T = 6.0
        β = 3.0
        γ = 0.4
        J[kind, kind] = [0 10 10; 10 2 6; 10 6 2]
    end
    @variables cue(site) = 0.0
    @lattice Lattice(dims; geometry, neighborhood = near)
    @relations wide = far
    @energy begin
        cells(A, B) => λ * (volume - 16)^2
        # asymmetric in s/s′ and in the kinds: the compiler averages it with its mirror
        contacts => J[kind, kind′] + β * cue * (1 + cue′)^2 * (kind == A)
        contacts(wide) => weight * γ * (cue - 2 * cue′) * (owner′ != 0)
    end
    @sweep Metropolis(; temperature = T)
end

"""Blocks of `side`ⁿ cells (kinds A/B alternating) with medium gaps, and a random cue."""
function site_contact_state(dims; side = 4, rng = Xoshiro(3))
    σ = zeros(Int32, dims...)
    n = 0
    for corner in Iterators.product((1:(side + 1):(d - side) for d in dims)...)
        n += 1
        σ[(c:(c + side - 1) for c in corner)...] .= n
    end
    return σ, [isodd(c) ? :A : :B for c in 1:n], rand(rng, dims...)
end

site_contact_problem(sys, dims; tspan = (0, 4), side = 4, kw...) =
    ((σ, kinds, cue) = site_contact_state(dims; side);
     PottsProblem(sys, [ownership => σ, kind => kinds, :cue => cue], tspan; kw...))

const SITE_CONTACT_CASES = (
    ("square", () -> SiteContacts(; name = :sq), (24, 24), Moore(1)),
    ("hex", () -> SiteContacts(; name = :hx, geometry = Hexagonal(), near = Hex(1), far = Hex(2)), (24, 24), Hex(1)),
    ("3D", () -> SiteContacts(; name = :cube, dims = (11, 11, 11)), (11, 11, 11), Moore(1)))

"""ΔH of random copies against H(after) − H(before); `dH` defaults to the generated ΔH."""
function site_selfcheck(prob, rel; n = 400, dH = (u, prop) -> energy_change(prob, u, prop))
    sol = solve(remake(prob; tspan = (0, 4)), SequentialCPM(; proposal = rel); saveat = [0, 2, 4])
    lat = prob.lattice
    R = CorePotts.relation(rel, lat)
    rng = Xoshiro(5)
    worst = 0.0
    for u in sol.u, _ in 1:n
        t = rand(rng, 1:length(u.σ)); x = CorePotts.coordinates(lat, t)
        ins, y = CorePotts.shift(lat, x, R.offsets[rand(rng, 1:length(R))])
        ins || continue
        s = CorePotts.linear_index(lat, y)
        u.σ[t] == u.σ[s] && continue
        prop = CorePotts.Proposal(t, s, x, 1, u.σ[t], u.σ[s])
        a = deepcopy(u); a.σ[t] = prop.new
        prob.f.commit!(a, prob.p, prop, ctx_of(prob))
        worst = max(worst, abs(dH(u, prop) - (total_energy(prob, a) - total_energy(prob, u) + Potts._killing_credit(prob, u, prop, a))))
    end
    return worst
end

# the generated ΔH with the pair's site reads exchanged (`x[target]` ↔ `x[s′]`): a mutant
# lowering that confuses `x` and `x′`
function swapped_sites_delta(sys)
    swap(ex) = ex isa Expr ?
               (ex.head === :ref && ex.args[1] == :(st.site.cue) && ex.args[2] in (:target, :sn) ?
                Expr(:ref, ex.args[1], ex.args[2] === :target ? :sn : :target) : Expr(ex.head, map(swap, ex.args)...)) : ex
    code = Potts.generated_code(sys).delta_H
    @assert occursin("st.site.cue[sn]", string(code)) && occursin("st.site.cue[target]", string(code))
    return Potts._rgf(swap(code))
end

@testset "P6.0e contact terms read site values: $name" for (name, mk, dims, rel) in SITE_CONTACT_CASES
    sys = mk()
    prob = site_contact_problem(sys, dims)
    @test site_selfcheck(prob, rel) < 1e-9
    # negative control: exchanging x and x′ in the lowering breaks ΔH
    f = swapped_sites_delta(sys)
    @test site_selfcheck(prob, rel; dH = (u, prop) -> f(u, prob.p, prop, ctx_of(prob))) > 1e-3
    # site reads at s′ stay inside the contact radius: no extra reach, no extra claims
    c = mtkcompile(sys)
    @test c.footprint.read == CorePotts.radius(prob.relations.wide) == 2
    @test c.footprint.source_read == -1 && c.footprint.source_write == -1
end

@testset "P6.0e x′ outside contact terms is rejected" begin
    bad(E) = Potts.PottsSystem(; name = :bad, kinds = [:medium, :A], lattice = Potts.lattice_spec((8, 8)),
        variables = [c], energies = [Potts.energy(E)], sweep = Potts.sweep_spec(:metropolis; temperature = 1.0))
    c = Potts.variable(only(Potts.Symbolics.@variables c(Potts.t)), :site)
    @test_throws r"only available in contact terms" mtkcompile(bad(Potts.sites => Potts._primed(c)))
    @test mtkcompile(bad(Potts.contacts => c * Potts._primed(c))) isa Potts.CompiledPottsSystem
    @test_throws ArgumentError Potts._primed(Potts.variable(only(Potts.Symbolics.@variables m(Potts.t)), :cell))
    @test_throws r"`x′` is already declared as a variable \(the contact-pair value of `x`\)" Potts._potts_model(:X,
        quote @kinds medium A; @variables begin x(site) = 0.0; x′(site) = 0.0 end end, @__MODULE__)
end

# an on-copy write and a clear-on-ownership-change variable read by contact (and site) terms:
# ΔH sees the target's value after the copy (D-045)
@potts_model SiteContactsOnCopy begin
    @structural_parameters begin
        write = true
        clear = true
    end
    @kinds medium A
    @parameters begin
        T = 6.0
        β = 2.0
        γ = 1.5
        J[kind, kind] = [0 8; 8 3]
    end
    @variables begin
        mark(site) = 0.0
        tag(site) = 0.5, [clear_on_ownership_change = clear]
    end
    @lattice Lattice((20, 20); neighborhood = Moore(1))
    @energy begin
        cells(A) => (volume - 16)^2
        contacts => J[kind, kind′] + β * mark * (1 + mark′) * (owner != 0) + γ * (tag - tag′)^2
        sites => 0.3 * mark * (kind == A)
    end
    if write
        @on_copy mark[target] ~ 0.5 * mark[source] + 1.0
    end
    @sweep Metropolis(; temperature = T)
end

@potts_model SourceWriteContacts begin
    @kinds medium A
    @variables mark(site) = 0.0
    @lattice Lattice((8, 8))
    @energy contacts => mark * mark′
    @on_copy mark[source] ~ 1.0
    @sweep Metropolis(; temperature = 1.0)
end

@testset "P6.0e contact terms see on-copy writes and clears (D-045)" begin
    σ, kinds, cue = site_contact_state((20, 20); side = 4)
    mk(; kw...) = PottsProblem(SiteContactsOnCopy(; name = :oc, kw...),
        [ownership => σ, kind => fill(:A, length(kinds)), :mark => cue, :tag => 2 .* cue], (0, 4))
    prob = mk()
    @test site_selfcheck(prob, Moore(1)) < 1e-9
    # negative controls: ΔH of the model without the write (or the clear) misses the change
    # the committed copy makes
    nowrite, noclear = mk(; write = false), mk(; clear = false)
    @test site_selfcheck(prob, Moore(1); dH = (u, prop) -> energy_change(nowrite, u, prop)) > 1e-3
    @test site_selfcheck(prob, Moore(1); dH = (u, prop) -> energy_change(noclear, u, prop)) > 1e-3
    @test site_selfcheck(nowrite, Moore(1)) < 1e-9 && site_selfcheck(noclear, Moore(1)) < 1e-9
    # a write at the source changes pairs away from the target: rejected
    @test_throws r"which this on-copy update writes" mtkcompile(SourceWriteContacts(; name = :sw))
end

@testset "P6.0e checkerboard equals sequential; Float32 never touches Float64" begin
    prob = site_contact_problem(SiteContacts(; name = :sq), (24, 24); tspan = (0, 60))
    H(alg, seeds) = [total_energy(prob, solve(remake(prob; seed), alg; save_start = false).u[end]) for seed in seeds]
    xs, ys = H(SequentialCPM(), 1:8), H(CheckerboardCPM(), 11:18)
    t = (Statistics.mean(xs) - Statistics.mean(ys)) / sqrt(Statistics.var(xs) / 8 + Statistics.var(ys) / 8)
    @test abs(t) < 4
    @test Statistics.mean(xs) < total_energy(prob, prob.u0) - 100           # the runs relax: the statistic is not trivial
    p32 = site_contact_problem(SiteContacts(; name = :sq), (24, 24); T = Float32)
    @test eltype(p32.u0.site.cue) === Float32
    σ, kinds = p32.u0.σ, p32.u0.cell.kind
    prop = CorePotts.Proposal(5 + 24 * 3, 6 + 24 * 3, (5, 4), 1, σ[5, 4], σ[6, 4])
    io = IOBuffer()
    code_llvm(io, p32.f.delta_H, typeof.((p32.u0, p32.p, prop, ctx_of(p32))); debuginfo = :none)
    @test !occursin("double", String(take!(io)))
    @test p32.f.delta_H(p32.u0, p32.p, prop, ctx_of(p32)) isa Float32
end

# a population fold in a contact term reads its own bound site: `cue` and `kind` there are
# not the pair's (neither placed at `site` nor mirrored)
@potts_model SiteContactsFold begin
    @kinds medium A B
    @variables cue(site) = 0.0
    @lattice Lattice((24, 24); neighborhood = Moore(1))
    @energy begin
        cells(A, B) => (volume - 16)^2
        contacts => cue * cue′ * sum(cue * (kind == A) for s in sites) / 100
    end
    @sweep Metropolis(; temperature = 6.0)
end

@testset "P6.0e population folds in contact terms keep their own site" begin
    prob = site_contact_problem(SiteContactsFold(; name = :f), (24, 24))
    u, lat = prob.u0, prob.lattice
    m = sum(u.site.cue[i] for i in eachindex(u.σ) if u.σ[i] > 0 && u.cell.kind[u.σ[i]] == 1) / 100
    H = 0.0
    for i in eachindex(u.σ), o in prob.contact.offsets
        ins, y = CorePotts.shift(lat, CorePotts.coordinates(lat, i), o)
        j = CorePotts.linear_index(lat, y)
        ins && u.σ[i] != u.σ[j] && (H += u.site.cue[i] * u.site.cue[j] * m / 2)
    end
    E0 = sum((u.cell.volume[c] - 16)^2 for c in eachindex(u.cell.volume))
    @test total_energy(prob, u) ≈ H + E0 rtol = 1e-12
    @test site_selfcheck(prob, Moore(1)) < 1e-9
end

# `x′` in an extension: bound next to `x` by `@extend`, or named explicitly (scalar and vector)
@potts_model SiteContactsBase begin
    @kinds medium A B
    @parameters J[kind, kind] = [0 10 10; 10 2 6; 10 6 2]
    @variables begin
        cue(site) = 0.0
        v(site)[1:2] = 0.0
    end
    @lattice Lattice((24, 24); neighborhood = Moore(1))
    @energy begin
        cells(A, B) => (volume - 16)^2
        contacts => J[kind, kind′] + cue * cue′ + v[1] * v′[2]
    end
    @sweep Metropolis(; temperature = 6.0)
end
@potts_model SiteContactsExt1 begin
    @extend cue, v = base = SiteContactsBase()
    @energy contacts => 2 * cue * (1 + cue′)^2 + v[2] * v′[1]
end
@potts_model SiteContactsExt2 begin
    @extend cue, cue′, v′, A = base = SiteContactsBase()
    @energy contacts => 2 * cue * (1 + cue′)^2 * (kind == A) + v′[1]
end

@testset "P6.0e x′ in extensions" begin
    for sys in (SiteContactsExt1(; name = :e1), SiteContactsExt2(; name = :e2))
        σ, kinds, cue = site_contact_state((24, 24))
        prob = PottsProblem(sys, [ownership => σ, kind => kinds, :cue => cue, :v_1 => 1 .- cue, :v_2 => cue .^ 2], (0, 4))
        @test length(sys.energies) == 3             # the base's two terms and the extension's
        @test site_selfcheck(prob, Moore(1)) < 1e-9
    end
    @test Potts.lookup(SiteContactsBase(; name = :b), :v′) isa Potts.QuantityVector
    @test_throws ArgumentError Potts.lookup(SiteContactsBase(; name = :b), :J′)       # not a site variable
end

# two site terms and an on-copy write both read: each site term sees the written value
@potts_model TwoSiteTermsOnCopy begin
    @kinds medium A
    @variables mark(site) = 0.0
    @lattice Lattice((20, 20); neighborhood = Moore(1))
    @energy begin
        cells(A) => (volume - 16)^2
        sites => 0.7 * mark * (kind == A)
        sites => 0.2 * mark^2
    end
    @on_copy mark[target] ~ 0.5 * mark[source] + 1.0
    @sweep Metropolis(; temperature = 6.0)
end

@testset "P6.0e two site terms reading an on-copy write" begin
    σ, kinds, cue = site_contact_state((20, 20))
    prob = PottsProblem(TwoSiteTermsOnCopy(; name = :t), [ownership => σ, kind => fill(:A, length(kinds)), :mark => cue], (0, 4))
    @test site_selfcheck(prob, Moore(1)) < 1e-9
    # names a user cannot write stay out of the error text
    @test_throws r"^(?!.*site′).*not available in a contact term"s mtkcompile(Potts.PottsSystem(; name = :bad,
        kinds = [:medium, :A], lattice = Potts.lattice_spec((8, 8)), energies = [Potts.energy(Potts.contacts => Potts.B.target)],
        sweep = Potts.sweep_spec(:metropolis; temperature = 1.0)))
end

# an extension cannot declare `x′` beside an inherited site variable `x` (nor the reverse)
@testset "P6.0e `x′` stays reserved through @extend" begin
    ext(body) = Base.invokelatest(eval(Potts._potts_model(:PrimeClash, body, @__MODULE__)); name = :pc)
    msg = r"`cue′` is declared, but `cue′` already means the contact-pair value of the site variable `cue`"
    @test_throws msg ext(quote @extend cue, A = b = SiteContactsBase(); @parameters cue′ = 2.0 end)
    @test_throws msg ext(quote @extend cue, A = b = SiteContactsBase(); @variables cue′(cell) = 0.0 end)
    @test ext(quote @extend cue, A = b = SiteContactsBase(); @parameters cue2 = 2.0 end) isa Potts.PottsSystem   # control
end

# P6.0e2: `x′` of a quantity that is not a site/field variable is a Potts error, raised when
# the constructor reads the unbound `x′`; a local named `x′` is ordinary Julia
@potts_model PrimeBase begin
    @structural_parameters n = 2
    @kinds medium A
    @parameters begin
        J[kind, kind] = [0 4; 4 2]
        λ = 1.0
    end
    @variables begin
        m(cell) = 1.0
        c(site) = 0.0
    end
    @lattice Lattice((10, 10))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0)
end

@testset "P6.0e2 primes of non-site quantities" begin
    build(body) = Base.invokelatest(eval(Potts._potts_model(:PrimeProbe, body, @__MODULE__)); name = :pp)
    model(stmts...) = quote
        @structural_parameters n = 2
        @kinds medium A
        @parameters begin
            J[kind, kind] = [0 4; 4 2]
            λ = 1.0
        end
        @variables begin
            m(cell) = 1.0
            c(site) = 0.0
        end
        @lattice Lattice((10, 10))
        @energy cells => (volume - 9.0)^2
        $(stmts...)
        @sweep Metropolis(; temperature = 1.0)
    end
    phrase = "primes exist only for site/field variables"
    rejects(body, n, what) = try
        build(body)
        false
    catch e
        e isa ArgumentError && (msg = sprint(showerror, e); occursin(phrase, msg) && occursin("`$n`", msg) && occursin(what, msg))
    end
    # locals named `x′` (x declared) are ordinary Julia and build
    for st in (:(@energy cells(A) => let λ′ = 2λ; λ′ * volume end),
               :(@energy cells(A) => sum(volume * k for n′ in 1:n for k in 1:1)),
               :(@energy cells(A) => sum(volume * m′ for m′ in 1:2)),
               :(@energy cells(A) => ((λ′) -> λ′ * volume)(λ)),
               :(@energy cells(A) => (; m′ = 2.0).m′ * volume))
        @test mtkcompile(build(model(st))) isa CompiledPottsSystem
    end
    # declared non-site quantities, with the right description
    @test rejects(model(:(@energy contacts => J[kind, kind′] + m′)), "m′", "`m` is a cell variable; in a contact term, `m[owner′]`")
    @test rejects(model(:(@energy contacts => J[kind, kind′] + λ′)), "λ′", "`λ` is a parameter")
    @test rejects(model(:(@observed q ~ 1.0), :(@energy cells(A) => q′)), "q′", "`q` is an observed quantity")
    # inherited through @extend, named or not
    @test rejects(quote @extend m, c = b = PrimeBase(); @energy contacts => m′ end, "m′", "`m` is a cell variable; in a contact term")
    @test rejects(quote @extend PrimeBase(); @energy contacts => m′ end, "m′", "`m` is a cell variable")
    # controls: a site variable's prime and an unrelated unbound name keep their behaviour
    @test build(quote @extend c, J = b = PrimeBase(); @energy contacts => J[kind, kind′] + c′ end) isa Potts.PottsSystem
    @test_throws UndefVarError build(model(:(@energy cells(A) => zz′)))
    # an `@extend` base's arguments are the extension's own code: their primes are translated
    @test rejects(quote @parameters q = 1.0; @extend b = PrimeBase(; λ = q′) end, "q′", "`q` is a parameter")
end

# Component bindings (an MTK value given as an expression) are rejected by name only where
# Potts reads them; a binding of a continuous observed variable (its equation gives its
# value) or of a parameter the system does not use stays ignored
@testset "component bindings Potts does not read" begin
    t = Potts.t
    σ = zeros(Int32, 10, 10); σ[3:5, 3:5] .= 1
    op = [ownership => σ, kind => [:A]]
    function run(sys; scope = :(cells(A)), stmts = ())
        decl = Expr(:macrocall, Symbol("@components"), LineNumberNode(@__LINE__, Symbol(@__FILE__)), scope, :(comp = $sys))
        m = Base.invokelatest(eval, quote
            @potts_model BindProbe begin
                @kinds medium A
                $decl
                $(stmts...)
                @lattice Lattice((10, 10))
                @energy cells => (volume - 9.0)^2
                @sweep Metropolis(; temperature = 1.0e-6)
            end
            BindProbe(; name = :bp)
        end)
        mtkcompile(m)
        return solve(PottsProblem(m, op, (0, 2)), SequentialCPM())
    end
    rejected(sys, word; kw...) = try
        run(sys; kw...)
        false
    catch e
        e isa ArgumentError && (m = sprint(showerror, e); occursin("component `comp`", m) && occursin(word, m))
    end
    @parameters k = 0.3
    @parameters k2 = 2k
    Potts.ModelingToolkitBase.@variables y(t) = 1.0 o(t)
    # an unused bound parameter
    sol = run(System([Potts.D(y) ~ -k * y], t, [y], [k, k2]; name = :comp))
    @test sol.u[end].cell.comp₊y[1] ≈ (1 - 0.3)^2
    # negative controls: the same parameter used by the component, or read by the model, is rejected
    @test rejected(System([Potts.D(y) ~ -k2 * y], t, [y], [k, k2]; name = :comp), "k2")
    @test rejected(System([Potts.D(y) ~ -k * y], t, [y], [k, k2]; name = :comp), "k2";
        stmts = (:(@energy cells => comp.k2 * volume),))
    @test rejected(System([Potts.D(y) ~ -k * y], t, [y], [k, k2]; name = :comp), "k2"; scope = :model,
        stmts = (:(@energy cells => comp.k2 * volume),))
    @test rejected(System([Potts.D(y) ~ -k * y], t, [y], [k, k2]; name = :comp), "k2";
        stmts = (:(@observed ok2(cell) ~ comp.k2),))
    # control: at model scope, with nothing reading `comp.k2`, it builds
    sol = run(System([Potts.D(y) ~ -k * y], t, [y], [k, k2]; name = :comp); scope = :model)
    @test Symbol(sol.retcode) === :Success
    # an observed variable bound (or given an initial value) consistent with its equation
    Potts.ModelingToolkitBase.@variables ob(t) = 2y
    sol = run(System([ob ~ 2y, Potts.D(y) ~ -k * ob], t; name = :comp))
    @test sol.u[end].cell.comp₊y[1] ≈ (1 - 0.6)^2
    sol = run(System([o ~ 2y, Potts.D(y) ~ -k * o], t; name = :comp, initial_conditions = [o => 2y]))
    @test sol.u[end].cell.comp₊y[1] ≈ (1 - 0.6)^2
    # negative control: an unknown's initial value given as an expression is rejected
    @test rejected(System([o ~ 2y, Potts.D(y) ~ -k * o], t; name = :comp, initial_conditions = [y => 2k]), "2k")
end

# ---------------------------------------------------------------------------------------
# P6.0f: `Every(n)` per lifecycle rule

@potts_model RuleCadences begin
    @structural_parameters begin
        na = 1
        nb = 1
        dims = (48, 32)
        geometry = CorePotts.Square()
        near = Moore(1)
    end
    @kinds medium ka kb
    @variables x(cell) = 0.0
    @parameters T = 10.0
    @lattice Lattice(dims; geometry, neighborhood = near)
    @energy cells => (volume - 64.0)^2
    @constraint no_extinction
    @divide cells(ka) Every(na) when = volume >= 4, along = RandomPlane(), x => 1.0
    @divide cells(kb) Every(nb) when = volume >= 4, along = RandomPlane(), x => 2.0
    @sweep Metropolis(; temperature = T)
end

# one cell of each kind, `w` sites wide
function rule_cadence_state(dims; w = 12)
    σ = zeros(Int32, dims)
    idx(o) = ntuple(d -> d == 1 ? (o:(o + w - 1)) : (2:(1 + min(w, dims[d] - 2))), length(dims))
    σ[idx(2)...] .= 1
    σ[idx(dims[1] ÷ 2 + 2)...] .= 2
    return σ, [:ka, :kb]
end
live_kinds(u) = (v = Array(u.cell.volume); k = Array(u.cell.kind);
    (count(c -> v[c] > 0 && k[c] == 1, eachindex(v)), count(c -> v[c] > 0 && k[c] == 2, eachindex(v))))
# every live cell divides at each checked MCS: 2^(checked MCS in 0:N-1) cells
cadence_oracle(n, N) = 2^count(m -> m % n == 0, 0:(N - 1))
trigger_code(sys) = string(only(filter(e -> occursin("EVENT_DIVIDE", string(e)), Potts.generated_code(sys).phases)))

@testset "P6.0f per-rule cadence: counts against the oracle (square, hex, 3D; sequential, checkerboard)" begin
    for (label, sys_of, dims, prop) in (
            ("square", (na, nb) -> RuleCadences(; name = :rc, na, nb), (48, 32), Moore(1)),
            ("hex", (na, nb) -> RuleCadences(; name = :rc, na, nb, geometry = Hexagonal(), near = Hex(1)), (48, 32), Hex(1)),
            ("3D", (na, nb) -> RuleCadences(; name = :rc, na, nb, dims = (32, 14, 14)), (32, 14, 14), Moore(1)))
        σ, kinds = rule_cadence_state(dims)
        for (na, nb) in ((2, 3), (2, 4), (3, 3), (1, 1))
            prob = PottsProblem(sys_of(na, nb), [ownership => σ, kind => kinds], (0, 6); capacity = 128)
            # the whole-lifecycle cadence: the gcd, so a shared cadence skips the pass entirely
            @test prob.f.lifecycle.every == gcd(na, nb)
            for alg in (SequentialCPM(; proposal = prop), CheckerboardCPM(; proposal = prop)), N in (1, 3, 5)
                @test live_kinds(solve(remake(prob; tspan = (0, N)), alg).u[end]) == (cadence_oracle(na, N), cadence_oracle(nb, N))
            end
        end
    end
end

@testset "P6.0f per-rule cadence: generated gates" begin
    has_gate(code, n) = occursin("mcs % $n", code)
    # Every(1) and a shared cadence generate no modulo gate (zero cost when unused)
    @test !occursin("mcs %", trigger_code(RuleCadences(; name = :rc)))
    @test !occursin("mcs %", trigger_code(RuleCadences(; name = :rc, na = 3, nb = 3)))
    # mixed: gcd pass, gates only on the rules whose cadence is not the gcd
    c = trigger_code(RuleCadences(; name = :rc, na = 2, nb = 3))
    @test has_gate(c, 2) && has_gate(c, 3)
    c = trigger_code(RuleCadences(; name = :rc, na = 2, nb = 4))
    @test !has_gate(c, 2) && has_gate(c, 4)
end

@potts_model LinkCadence begin
    @kinds medium A
    @relationship bond(cell, cell) capacity = 1
    @lattice Lattice((8, 8))
    @link bond Every(7) when = new_contact(a, b)
    @sweep Metropolis(; temperature = 1.0)
end

@testset "P6.0f per-rule cadence: API, errors" begin
    V = Potts.B.volume
    dom = Potts.cells(1)
    @test Potts.divide(dom; when = V >= 4).every == 1
    @test Potts.divide(dom, Potts.Every(3); when = V >= 4).every == 3
    @test Potts.divide(dom; when = V >= 4, every = 3).every == 3                  # keyword form, as @link
    @test Potts.divide(dom, Potts.B.volume => 1.0, Potts.Every(3); when = V >= 4).every == 3   # anywhere
    @test_throws r"one cadence; got Every\(2\) and Every\(3\)" Potts.divide(dom, Potts.Every(2), Potts.Every(3); when = V >= 4)
    @test_throws r"one cadence" Potts.divide(dom, Potts.Every(2); when = V >= 4, every = 2)
    @test_throws r"`3` is neither a cadence `Every\(n\)` nor a state rule" Potts.divide(dom, 3; when = V >= 4)
    @test_throws ArgumentError Potts.divide(dom; when = V >= 4, every = 0)
    @test_throws r"`every = n` takes an integer n ≥ 1 or `Every\(n\)`; got 2.0" Potts.divide(dom; when = V >= 4, every = 2.0)
    @test_throws ArgumentError Potts.link_rule(:link, Potts.RelationshipRef(:bond); when = true, every = 2.0)
    @test occursin("divide  cells(1) Every(3) when", sprint(show, MIME"text/plain"(), Potts.PottsSystem(; name = :x, kinds = [:medium, :ka],
        lattice = Potts.lattice_spec((8, 8)), sweep = Potts.sweep_spec(:metropolis; temperature = 1.0),
        divisions = [Potts.divide(dom, Potts.Every(3); when = V >= 4)])))
    # the macro passes a cadence through to @link as well (it used to be dropped silently)
    rel = Potts.RelationshipRef(:bond)
    @test Potts.link_rule(:link, rel, Potts.Every(4); when = true).every == 4
    @test Potts.link_rule(:link, rel; when = true, every = 4).every == 4
    @test_throws r"`3` is not a cadence" Potts.link_rule(:link, rel, 3; when = true)
    @test only(LinkCadence(; name = :l).link_rules).every == 7
    # a division's description names a non-default cadence (errors located at the rule)
    @test Potts._describe(Potts.divide(dom, Potts.Every(3); when = V >= 4)) == "@divide cells(1) Every(3) when = volume >= 4"
    @test Potts._describe(Potts.divide(dom; when = V >= 4)) == "@divide cells(1) when = volume >= 4"
end

# Only the rule that fired writes the daughters' state (P6.0f review): rules sharing a kind
# are tried in model order, and the first whose cadence, kinds and `when` hold wins, its
# division and its state rules.
@potts_model SameKindCadences begin
    @structural_parameters begin
        na = 2
        nb = 3
        wa = 4           # rule a is met when volume ≥ wa, rule b when volume ≥ wb
        wb = 4
        xa = 1.0
        xb = 2.0
    end
    @kinds medium ka
    @variables x(cell) = 0.0
    @lattice Lattice((48, 32))
    @energy cells => (volume - 64.0)^2
    @constraint no_extinction
    @divide cells(ka) Every(na) when = volume >= wa, along = RandomPlane(), x => xa
    @divide cells(ka) Every(nb) when = volume >= wb, along = RandomPlane(), x => xb
    @sweep Metropolis(; temperature = 10.0)
end

@testset "P6.0f per-rule cadence: only the firing rule writes the daughters' state" begin
    σ = zeros(Int32, 48, 32); σ[2:13, 2:13] .= 1
    function run(sys, tspan; alg = SequentialCPM())
        u = solve(PottsProblem(sys, [ownership => σ, kind => [:ka]], tspan; capacity = 32), alg).u[end]
        live = findall(>(0), Array(u.cell.volume))
        return length(live), unique(Array(u.cell.x)[live])
    end
    sys = SameKindCadences(; name = :s)
    @test PottsProblem(sys, [ownership => σ, kind => [:ka]], (0, 1)).f.lifecycle.rules === Val(true)
    for alg in (SequentialCPM(), CheckerboardCPM())
        # MCS 0: both are checked and met; the first (Every(2), x = 1) wins
        @test run(sys, (0, 1); alg) == (2, [1.0])
        # MCS 2: only Every(2) is checked
        @test run(sys, (0, 3); alg) == (4, [1.0])
        # MCS 3: only Every(3) is checked, so its state 2 (absolute MCS numbers: 3 % 3 == 0)
        @test run(sys, (0, 4); alg) == (8, [2.0])
        @test run(sys, (3, 4); alg) == (2, [2.0])
        @test run(sys, (3, 5); alg) == (4, [1.0])                               # then MCS 4: Every(2)
    end
    # the review's case: a never-firing rule for the same kind must not write the state
    @test run(SameKindCadences(; name = :s, na = 1, nb = 2, wb = 10^9), (0, 1)) == (2, [1.0])
    @test run(SameKindCadences(; name = :s, na = 1, nb = 1, wb = 10^9), (0, 2)) == (4, [1.0])
    # rule order: both fire for every cell; the first wins (one division, its state)
    @test run(SameKindCadences(; name = :s, na = 1, nb = 1), (0, 2)) == (4, [1.0])
    @test run(SameKindCadences(; name = :s, na = 1, nb = 1, xa = 2.0, xb = 1.0), (0, 2)) == (4, [2.0])
    @test run(SameKindCadences(; name = :s, na = 1, nb = 1, wa = 10^9), (0, 2)) == (4, [2.0])  # a unmet: b
end

@testset "P6.0f per-rule cadence: disjoint rules generate plain events" begin
    sys = RuleCadences(; name = :rc, na = 2, nb = 3)
    @test !occursin("ruled_event", trigger_code(sys)) && !occursin("true &&", trigger_code(sys))
    σ, kinds = rule_cadence_state((48, 32))
    lc = PottsProblem(sys, [ownership => σ, kind => kinds], (0, 1)).f.lifecycle
    @test lc.rules === Val(false)
    # the state rules take no rule index
    ruled_rules(sys) = any(e -> occursin("daughter, rule)", string(e)), Potts.generated_code(sys).phases)
    @test !ruled_rules(sys)
    @test occursin("ruled_event", trigger_code(SameKindCadences(; name = :s))) && ruled_rules(SameKindCadences(; name = :s))
end

@testset "P6.0f per-rule cadence: absolute MCS after remake" begin
    σ, kinds = rule_cadence_state((48, 32))
    prob = PottsProblem(RuleCadences(; name = :rc, na = 2, nb = 3), [ownership => σ, kind => kinds], (0, 1); capacity = 128)
    oracle(n, t0, t1) = 2^count(m -> m % n == 0, t0:(t1 - 1))
    for (t0, t1) in ((3, 7), (1, 2), (5, 9))
        @test live_kinds(solve(remake(prob; tspan = (t0, t1)), SequentialCPM()).u[end]) == (oracle(2, t0, t1), oracle(3, t0, t1))
    end
end

# cluster rules at cadences that are not the gcd, sharing their kind (rule-carrying events
# on the cluster path: every member takes its root's rule)
@potts_model ClusterCadences begin
    @kinds medium cytoplasm nucleus
    @parameters begin
        J[kind, kind] = [0 16 16; 16 14 30; 16 30 14]
        V₀[kind] = [0.0, 48.0, 16.0]
    end
    @variables mass(cell) = 0.0
    @lattice Lattice((30, 30); neighborhood = Moore(1))
    @energy begin
        cells => (volume - V₀[kind])^2
        contacts => ifelse(cluster[owner] == cluster[owner′], 2.0, J[kind, kind′])
        clusters(cytoplasm) => (cluster_volume - 64.0)^2
    end
    @constraint no_extinction
    @divide clusters(cytoplasm) Every(3) when = cluster_volume >= 16, along = (1.0, 0.0), mass => 3.0
    @divide clusters(cytoplasm) Every(2) when = cluster_volume >= 16, along = (1.0, 0.0), mass => 5.0
    @sweep Metropolis(; temperature = 10.0)
end

@testset "P6.0f per-rule cadence: cluster rules" begin
    σ, kinds, groups = compartment_state()
    prob = PottsProblem(ClusterCadences(; name = :cc), [ownership => σ, kind => kinds, cluster => groups], (0, 1); capacity = 128)
    @test prob.f.lifecycle.every == 1 && prob.f.lifecycle.rules === Val(true)
    c = trigger_code(ClusterCadences(; name = :cc))
    @test occursin("mcs % 2", c) && occursin("mcs % 3", c)
    function run(tspan)
        u = solve(remake(prob; tspan), SequentialCPM(; proposal = Moore(1))).u[end]
        live = findall(>(0), Array(u.cell.volume))
        return length(unique(Array(u.cell.cluster)[live])), length(live), unique(Array(u.cell.mass)[live])
    end
    @test run((0, 1)) == (18, 36, [3.0])       # MCS 0: both checked, the first (Every(3)) wins
    @test run((0, 2)) == (18, 36, [3.0])       # MCS 1: neither
    @test run((0, 3))[[1, 3]] == (36, [5.0])   # MCS 2: Every(2) alone (a small nucleus may miss the plane)
    @test run((3, 4)) == (18, 36, [3.0])       # MCS 3: Every(3) alone
end

@potts_model CadenceDivBase begin
    @kinds medium ka kb
    @lattice Lattice((16, 16))
    @energy cells => (volume - 64.0)^2
    @divide cells(ka) Every(2) when = volume >= 4 + rand()
    @sweep Metropolis(; temperature = 1.0)
end

@potts_model CadenceDivOther begin
    @kinds medium ka kb
    @lattice Lattice((16, 16))
    @energy cells => (volume - 64.0)^2
    @divide cells(ka) Every(3) when = volume >= 8 + rand()
    @sweep Metropolis(; temperature = 1.0)
end

@testset "P6.0f per-rule cadence: extend accumulates division rules and warns on a new cadence" begin
    ext(body) = Base.invokelatest(eval(Potts._potts_model(:CadenceDivExt, body, @__MODULE__)); name = :e)
    sys = @test_logs (:warn, r"@divide cells\(1\) Every\(3\).*adds to the base's @divide cells\(1\) Every\(2\)") ext(quote
        @extend base = CadenceDivBase()
        @kinds medium ka kb
        @divide cells(ka) Every(3) when = volume >= 8 + rand()
    end)
    @test [d.every for d in sys.divisions] == [2, 3]                  # both rules stay, each with its cadence
    # two separately built models: extend renumbers the draws of `sys` and keeps its cadences
    other = @test_logs (:warn, r"adds to the base's") Potts.ModelingToolkitBase.extend(
        CadenceDivOther(; name = :o), CadenceDivBase(; name = :b))
    @test [d.every for d in other.divisions] == [2, 3]
    @test string(other.divisions[2].when) != string(CadenceDivOther(; name = :o).divisions[1].when)   # renumbered
    @test_logs ext(quote                                                    # same cadence: silent
        @extend base = CadenceDivBase()
        @kinds medium ka kb
        @divide cells(ka) Every(2) when = volume >= 8
    end)
    @test_logs ext(quote                                                    # other kinds: silent
        @extend base = CadenceDivBase()
        @kinds medium ka kb
        @divide cells(kb) Every(5) when = volume >= 8
    end)
end

@potts_model CadenceComponents begin
    @kinds medium A
    @components cells(A) clock = clock
    @lattice Lattice((20, 20))
    @energy cells => (volume - 25.0)^2
    @divide cells(A) Every(4) when = clock.m_c >= 1, along = (1.0, 0.0), clock.m_c => 0.0
    @sweep Metropolis(; temperature = 1.0)
end

@testset "P6.0f per-rule cadence survives @components" begin
    @test only(mtkcompile(CadenceComponents(; name = :cc)).divisions).every == 4
end

# ---------------------------------------------------------------------------------------
# Discrete-time components (P6.0k, D-065 Q9): MTK clocked (`Shift`) systems lowered into one
# per-cell tick phase per clock, after the ODEs. Oracles are hand-computed sequences.
using Potts.ModelingToolkitBase: ShiftIndex, Clock
const _kd = ShiftIndex(_tc, 0)
Potts.ModelingToolkitBase.@variables fz(_tc) = 1.0 dn(_tc) = 0.0 dA(_tc)::Bool = false dB(_tc)::Bool = false
@parameters dinc = 1.0 dwnt::Bool = false dsig::Bool = false du = 0.5

# a lag-2 recurrence: the older lag gets its own slot (`fib₊fzₜ₋₁`)
@named fib = System([fz(_kd) ~ fz(_kd - 1) + fz(_kd - 2)], _tc)
# a counter on a clock; `dinc` is coupled to a population fold in the model
counter(clock) = System([dn(clock) ~ dn(clock - 1) + dinc], _tc; name = :counter)
# a toggle driving a continuous component, and a Bool node sampling one
@named toggle = System([dA(_kd) ~ !dA(_kd - 1)], _tc)
@named sampler = System([dB(_kd) ~ dsig], _tc)
Potts.ModelingToolkitBase.@variables yx(_tc) = 1.0 xt(_tc) = 0.0
@parameters yr = 0.0
@named relax = System([Potts.D(yx) ~ -yr * yx, Potts.D(xt) ~ 1.0], _tc)
# asynchronous-style updating in MTK form (gap G9): a per-cell draw decides whether A updates
@named coin = System([dA(_kd) ~ ifelse(du < 0.5, !dA(_kd - 1), dA(_kd - 1))], _tc)

const _DISCRETE_SYS = Ref{Any}(nothing)

@potts_model DiscreteFib begin
    @kinds medium A
    @components cells(A) fib = fib
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0e-6)
end

function discrete_counter_model(clock; mcs_duration = 1.0, scope = :cells)
    _DISCRETE_SYS[] = counter(clock)
    if scope === :cells
        @potts_model DiscreteCounter begin
            @kinds medium A
            @components cells(A) ctr = _DISCRETE_SYS[]
            @lattice Lattice((12, 12))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = 1.0e-6, mcs_duration = mcs_duration)
        end
        return DiscreteCounter(; name = :ctr)
    else
        @potts_model DiscreteCensus begin
            @kinds medium A
            @components model ctr = _DISCRETE_SYS[]
            @equations ctr.dinc ~ count(true for c in cells)       # a model-scope coupling
            @lattice Lattice((12, 12))
            @energy cells => (volume - 9.0)^2
            @sweep Metropolis(; temperature = 1.0e-6, mcs_duration = mcs_duration)
        end
        return DiscreteCensus(; name = :census)
    end
end

@potts_model DiscreteHybrid begin
    @kinds medium A
    @variables seen(cell) = 0.0
    @components cells(A) begin
        tg = toggle
        smp = sampler
        rel = relax
    end
    @equations begin
        rel.yr ~ 0.1 * tg.dA                 # a Real parameter holds the latest tick (zero-order hold)
        smp.dsig ~ rel.xt > 2.5              # a Bool parameter samples the ODE state at the tick
    end
    @after_mcs seen ~ seen + tg.dA           # model statements read a node as 0/1
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0e-6)
end

@potts_model DiscreteCoin begin
    @kinds medium A
    @components cells(A) cn = coin
    @equations cn.du ~ rand()
    @lattice Lattice((40, 40))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0e-6)
end

function _discrete_blocks(n = 4, L = 12)
    σ = zeros(Int32, L, L)
    for (c, (i, j)) in enumerate(Iterators.take(((i, j) for i in 1:4:(L - 3), j in 1:4:(L - 3)), n))
        σ[(i + 1):(i + 3), (j + 1):(j + 3)] .= c
    end
    return σ
end

const _DISCRETE_ALGS = (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))

@testset "discrete components: lag-2 recurrence (Fibonacci oracle)" begin
    σ = _discrete_blocks(2)
    cs = mtkcompile(DiscreteFib(; name = :f))
    @test Set(Potts.info(v).name for v in cs.sys.variables) == Set([:fib₊fz, Symbol("fib₊fzₜ₋₁")])
    # the older lag has no MTK default: the operating point must give it
    @test_throws ArgumentError PottsProblem(cs, [ownership => σ, kind => [1, 1]], (0, 6))
    prob = PottsProblem(cs, [ownership => σ, kind => [1, 1], Symbol("fib₊fzₜ₋₁") => [0.0, 1.0]], (0, 6))
    fibs(a, b, n) = (out = [a]; for _ in 1:n
        a, b = a + b, a
        push!(out, a)
    end; out)
    for alg in _DISCRETE_ALGS
        sol = solve(prob, alg; saveat = 0:6)
        @test [u.cell.fib₊fz[1] for u in sol.u] == fibs(1.0, 0.0, 6)       # 1, 1, 2, 3, 5, 8, 13
        @test [u.cell.fib₊fz[2] for u in sol.u] == fibs(1.0, 1.0, 6)       # 1, 2, 3, 5, 8, 13, 21
        @test sol[Symbol("fib₊fzₜ₋₁")][end] == [8.0, 13.0]
    end
end

@testset "discrete components: clock periods, phases and mcs_duration" begin
    σ = _discrete_blocks(2)
    op = [ownership => σ, kind => [1, 1]]
    ticks(sys; n = 12) = [u.cell.ctr₊dn[1] for u in solve(PottsProblem(sys, op, (0, n)), SequentialCPM(); saveat = 0:n).u]
    # MTK clock time: ticks at t = phase + k·dt; the state saved at t has had that many ticks
    oracle(dt, phase, n) = [Float64(count(τ -> 0 < τ <= t, phase:dt:n)) for t in 0:n]
    @test ticks(discrete_counter_model(_kd)) == 0:12
    @test ticks(discrete_counter_model(ShiftIndex(Clock(1.0)))) == 0:12
    @test ticks(discrete_counter_model(ShiftIndex(Clock(3.0)))) == oracle(3, 0, 12)
    @test ticks(discrete_counter_model(ShiftIndex(Clock(3.0; phase = 1.0)))) == oracle(3, 1, 12)
    @test oracle(3, 1, 12) != oracle(3, 0, 12)                             # the phase is visible
    # the period is model time: Clock(1) at half an MCS per MCS is one tick every two MCS
    @test ticks(discrete_counter_model(ShiftIndex(Clock(1.0)); mcs_duration = 0.5)) == oracle(2, 0, 12)
    @test ticks(discrete_counter_model(_kd; mcs_duration = 0.5)) == 0:12  # a step count, no period
    for bad in (Clock(2.5), Clock(3.0; phase = 0.5), Clock(3.0; phase = 3.0))
        @test_throws ArgumentError mtkcompile(discrete_counter_model(ShiftIndex(bad)))
    end
end

@testset "discrete components: model scope" begin
    σ = _discrete_blocks(3)
    sys = discrete_counter_model(ShiftIndex(Clock(2.0)); scope = :model)
    prob = PottsProblem(sys, [ownership => σ, kind => [1, 1, 1]], (0, 8))
    @test :ctr₊dn in propertynames(prob.u0.model)
    for alg in _DISCRETE_ALGS
        sol = solve(prob, alg; saveat = 0:8)
        @test [u.model.ctr₊dn[1] for u in sol.u] == [3.0 * (t ÷ 2) for t in 0:8]   # 3 live cells per tick
    end
end

@testset "discrete components: hold, sample and the tick after the ODEs" begin
    σ = _discrete_blocks(2)
    prob = PottsProblem(DiscreteHybrid(; name = :h), [ownership => σ, kind => [1, 1], Symbol("tg₊dA") => [false, true]], (0, 8))
    for alg in _DISCRETE_ALGS
        sol = solve(prob, alg; saveat = 0:8)
        for c in 1:2
            A = [isodd(m + c - 1) for m in 0:8]                          # the toggle after m ticks
            @test [u.cell.tg₊dA[c] for u in sol.u] == Float64.(A)
            # the ODE of MCS m sees A after m ticks (held over the MCS): Euler with r = 0.1·A
            @test [u.cell.rel₊yx[c] for u in sol.u] ≈ [prod(1 - 0.1 * A[j + 1] for j in 0:(m - 1); init = 1.0) for m in 0:8] rtol = 1e-12
            # the tick of MCS m samples x = m + 1 (the ODE step of the same MCS came first)
            @test [u.cell.smp₊dB[c] for u in sol.u] == [t >= 3 ? 1.0 : 0.0 for t in 0:8]
            # after-MCS updates run before the tick: they read A after m ticks
            @test sol.u[end].cell.seen[c] == count(A[1:8])
        end
    end
end

@testset "discrete components: per-cell draws (asynchronous updating in MTK form)" begin
    σ = _discrete_blocks(100, 40)
    prob = PottsProblem(DiscreteCoin(; name = :c), [ownership => σ, kind => fill(1, 100)], (0, 40))
    sols = [solve(prob, alg; saveat = 0:40) for alg in _DISCRETE_ALGS]
    A = reduce(hcat, [u.cell.cn₊dA for u in sols[1].u])
    @test A == reduce(hcat, [u.cell.cn₊dA for u in sols[2].u])            # keyed draws: the sweep does not matter
    flips = count(A[:, 2:end] .!= A[:, 1:(end - 1)]) / length(A[:, 2:end])
    @test abs(flips - 0.5) < 4 * sqrt(0.25 / length(A[:, 2:end]))       # P(flip) = 1/2
    @test all(x -> x == 0 || x == 1, A)
end

@testset "discrete components: statements and couplings" begin
    bad(extra) = Base.invokelatest(eval(Potts._potts_model(:DiscreteBad, quote
        @kinds medium A
        @variables inp(cell) = 0.0
        @components cells(A) tg = toggle
        $extra
        @lattice Lattice((8, 8))
        @energy cells => (volume - 9.0)^2
        @sweep Metropolis(; temperature = 1.0)
    end, @__MODULE__)); name = :b)
    # a node evolves only by its ticks (control: the same model without the statement compiles)
    @test mtkcompile(bad(:(@after_mcs inp ~ 1.0))) isa CompiledPottsSystem
    @test_throws r"only its ticks write it" mtkcompile(bad(:(@after_mcs tg.dA ~ 1.0)))
    @test_throws r"not a parameter of a component" mtkcompile(bad(:(@equations tg.dA ~ inp)))
    # a Bool parameter coupled to a Real expression reads it as `!iszero`
    σ = _discrete_blocks(2, 8)
    _DISCRETE_SYS[] = sampler
    @potts_model DiscreteRealCoupling begin
        @kinds medium A
        @variables inp(cell) = 0.0
        @components cells(A) smp = _DISCRETE_SYS[]
        @equations smp.dsig ~ inp
        @lattice Lattice((8, 8))
        @energy cells => (volume - 9.0)^2
        @sweep Metropolis(; temperature = 1.0e-6)
    end
    u = solve(PottsProblem(DiscreteRealCoupling(; name = :r), [ownership => σ, kind => [1, 1], :inp => [0.0, 0.3]], (0, 1)),
        SequentialCPM()).u[end]
    @test u.cell.smp₊dB == [0.0, 1.0]
    # an uncoupled Bool parameter is a model parameter holding 0/1
    @potts_model DiscreteBoolParameter begin
        @kinds medium A
        @components cells(A) smp = _DISCRETE_SYS[]
        @lattice Lattice((8, 8))
        @energy cells => (volume - 9.0)^2
        @sweep Metropolis(; temperature = 1.0e-6)
    end
    p = PottsProblem(DiscreteBoolParameter(; name = :b), [ownership => σ, kind => [1, 1]], (0, 1))
    @test p.p.smp₊dsig === 0.0
    @test solve(remake(p; p = [Symbol("smp₊dsig") => true]), SequentialCPM()).u[end].cell.smp₊dB == [1.0, 1.0]
    # components travel through `extend`
    @potts_model DiscreteExtended begin
        @extend base = DiscreteFib()
        @kinds medium A
        @parameters λx = 2.0
        @energy cells => λx * (volume - 9.0)^2
    end
    ec = mtkcompile(DiscreteExtended(; name = :e))
    @test only(ec.discrete).name === :fib && length(ec.cell_terms) == 2
end

# Several tick phases (cell and model scope, clocks that coincide) read only pre-tick values:
# the result does not depend on declaration order (review P6.0k round 1).
Potts.ModelingToolkitBase.@variables dX(_tc)::Bool = false dM(_tc) = 0.0 dZ(_tc)::Bool = false dY(_tc)::Bool = false
@parameters ds::Bool = false dq = 0.0 dw::Bool = false
@named xcell = System([dX(_kd) ~ ds], _tc)
@named mmodel = System([dM(_kd) ~ dq], _tc)
@named zslow = System([dZ(ShiftIndex(Clock(2.0))) ~ !dZ(ShiftIndex(Clock(2.0)) - 1)], _tc)
@named yfast = System([dY(_kd) ~ dw], _tc)

@testset "discrete components: ticks on one MCS are Jacobi across phases" begin
    make(label, comps, eqs) = Base.invokelatest(eval(Potts._potts_model(:DiscreteOrder, quote
        @kinds medium A
        $(comps...)
        @equations begin
            $(eqs...)
        end
        @lattice Lattice((12, 12))
        @energy cells => (volume - 9.0)^2
        @sweep Metropolis(; temperature = 1.0e-6)
    end, @__MODULE__)); name = label)
    σ = _discrete_blocks(2)
    run(sys) = solve(PottsProblem(sys, [ownership => σ, kind => [1, 1]], (0, 5)), SequentialCPM(); saveat = 0:5)
    # cell and model scope on one clock: X reads M before the tick
    cc = :(@components cells(A) cc = xcell)
    mm = :(@components model mm = mmodel)
    eqs = (:(cc.ds ~ mm.dM > 0.5), :(mm.dq ~ 1.0 + count(true for c in cells)))
    for comps in ((cc, mm), (mm, cc))
        sol = run(make(:xm, comps, eqs))
        @test [u.model.mm₊dM[1] for u in sol.u] == [0.0; fill(3.0, 5)]
        @test [u.cell.cc₊dX[1] for u in sol.u] == [0.0, 0.0, 1.0, 1.0, 1.0, 1.0]   # one tick behind M
        @test :cc₊dX__tick in propertynames(sol.u[1].cell)                       # published after both
    end
    # two clocks coinciding on even t: Y reads Z before Z's tick
    zz = :(@components cells(A) zz = zslow)
    yy = :(@components cells(A) yy = yfast)
    for comps in ((zz, yy), (yy, zz))
        sol = run(make(:zy, comps, (:(yy.dw ~ zz.dZ),)))
        Z = [isodd(t ÷ 2) for t in 0:5]
        @test [u.cell.zz₊dZ[1] for u in sol.u] == Float64.(Z)
        @test [u.cell.yy₊dY[1] for u in sol.u] == Float64.([false; Z[1:5]])
    end
    # a single phase writes its slots directly (no scratch)
    @test !(:tg₊dA__tick in propertynames(PottsProblem(DiscreteHybrid(; name = :h), [ownership => σ, kind => [1, 1]], (0, 1)).u0.cell))
end

@testset "discrete components: a Bool node indexed by a cell" begin
    @potts_model DiscreteIndexed begin
        @kinds medium A
        @variables begin
            got(cell) = 0.0
            amp(cell) = 0.0
            neg(cell) = 0.0
            sel(cell) = 0.0
        end
        @components cells(A) tg = toggle
        @after_mcs begin
            got ~ 1.0 + tg.dA[id]                          # as a number: 0/1
            amp ~ ifelse(tg.dA[id] & (volume > 1), 1.0, 0.0)   # as a Bool
            neg ~ ifelse(!tg.dA[id], 1.0, 0.0)
            sel ~ ifelse(tg.dA[id], 1.0, 0.0)
        end
        @lattice Lattice((8, 8))
        @energy cells => (volume - 9.0)^2
        @sweep Metropolis(; temperature = 1.0e-6)
    end
    σ = _discrete_blocks(2, 8)
    u = solve(PottsProblem(DiscreteIndexed(; name = :i), [ownership => σ, kind => [1, 1], Symbol("tg₊dA") => [false, true]], (0, 1)),
        SequentialCPM()).u[end]
    # the updates run before the MCS-0 tick
    @test u.cell.got == [1.0, 2.0] && u.cell.amp == [0.0, 1.0] && u.cell.neg == [1.0, 0.0] && u.cell.sel == [0.0, 1.0]
end

# A tick reading another cell's node sees its pre-tick value (Jacobi across cells), under both
# algorithms: a shift register moves one cell per tick (review P6.0k round 2, B1).
@named shiftcell = System([dX(_kd) ~ ds], _tc)
@potts_model DiscreteShiftRegister begin
    @kinds medium A
    @components cells(A) xc = shiftcell
    @equations xc.ds ~ ifelse(id > 1, xc.dX[max(id - 1, 1)] > 0.5, true)
    @lattice Lattice((16, 16))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0e-6)
end
shift_register_oracle(m) = Float64[c <= m for c in 1:6]

@testset "discrete components: Jacobi across cells (shift register)" begin
    prob = PottsProblem(DiscreteShiftRegister(; name = :s), [ownership => _discrete_blocks(6, 16), kind => fill(1, 6)], (0, 4))
    @test :xc₊dX__tick in propertynames(prob.u0.cell)       # a cross-cell read ticks through scratch
    for alg in _DISCRETE_ALGS
        sol = solve(prob, alg; saveat = 0:4)
        @test [u.cell.xc₊dX for u in sol.u] == shift_register_oracle.(0:4)
    end
end

# Array variables: one scalar slot per element, `name₊z_i` (G11)
Potts.ModelingToolkitBase.@variables dz(_tc)[1:2]::Bool = [false, true]
@named ring = System([dz[1](_kd) ~ !dz[2](_kd - 1), dz[2](_kd) ~ dz[1](_kd - 1)], _tc)
@potts_model DiscreteArray begin
    @kinds medium A
    @components cells(A) ar = ring
    @lattice Lattice((8, 8))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 1.0e-6)
end

@testset "discrete components: array variables" begin
    cs = mtkcompile(DiscreteArray(; name = :a))
    @test Set(Potts.info(v).name for v in cs.sys.variables) == Set([:ar₊dz_1, :ar₊dz_2])
    sol = solve(PottsProblem(cs, [ownership => _discrete_blocks(1, 8), kind => [1]], (0, 5)), SequentialCPM(); saveat = 0:5)
    # (z1, z2) ← (!z2, z1) from the array default (0, 1): (0,1) → (0,0) → (1,0) → (1,1) → (0,1) → (0,0)
    @test [(u.cell.ar₊dz_1[1], u.cell.ar₊dz_2[1]) for u in sol.u] ==
          [(0.0, 1.0), (0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0), (0.0, 0.0)]
end

@testset "discrete components: an under-determined node" begin
    @named undet = System([dX(_kd) ~ ds & dY(_kd)], _tc)
    _DISCRETE_SYS[] = undet
    @potts_model DiscreteUndetermined begin
        @kinds medium A
        @components cells(A) ud = _DISCRETE_SYS[]
        @lattice Lattice((8, 8))
        @sweep Metropolis(; temperature = 1.0)
    end
    @test_throws r"every discrete variable needs an update" mtkcompile(DiscreteUndetermined(; name = :u))
end

# Gap G1: with full ModelingToolkit loaded (it replaces MTKBase's compiler, and its own
# rejects clocked systems), `PottsModelingToolkitExt` compiles discrete components through
# MTK's discrete-pass hook. Loading MTK is session-wide, so both sides run in fresh processes;
# they must generate the same code and the same trajectories.
@testset "discrete components with full ModelingToolkit loaded (G1)" begin
    script = joinpath(@__DIR__, "mtk_extension.jl")
    run_script(args...) = read(`$(Base.julia_cmd()) --startup-file=no --project=$(@__DIR__) $script $args`, String)
    lines(s) = filter(startswith("P60K|"), split(s, '\n'))
    base, full = lines(run_script()), lines(run_script("mtk"))
    @test length(base) == 4
    @test full == base
end

# P6.0r (D-083): free slots (capacity > n; kind 1, their own cluster roots) add nothing to H
@potts_model P60rFreeSlots begin
    @kinds medium cytoplasm nucleus
    @parameters begin
        V₀[kind] = [0.0, 6.0, 3.0]
    end
    @lattice Lattice((20, 20); boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells => (volume - V₀[kind])^2 + 0.3 * surface + 5.0
        contacts => 4.0
        clusters(cytoplasm) => 1.3 * (cluster_volume - 10.0)^2 + 2.0
    end
    @sweep Metropolis(; temperature = 8.0)
end
@testset "P6.0r: free slots add nothing to total_energy" begin
    σc = zeros(Int32, 20, 20); σc[5, 5] = 1; σc[5, 6] = 2; σc[12:14, 12:14] .= 3; σc[13, 13] = 4
    op = [ownership => σc, kind => [:cytoplasm, :nucleus, :cytoplasm, :nucleus], cluster => [1, 1, 3, 3]]
    a = PottsProblem(P60rFreeSlots(; name = :c), op, (0, 5))
    b = PottsProblem(P60rFreeSlots(; name = :c), op, (0, 5); capacity = 50)
    @test length(b.u0.cell.volume) == 50
    @test total_energy(b) ≈ total_energy(a)
end

# P6.0v3 (F1, D-101): the last after-MCS cell update moves into `Lifecycle.before` (one
# device launch with the trigger) exactly when the trigger reads what it writes only at its
# own cell; otherwise it stays a phase of its own
@potts_model P60v3FuseOwn begin
    @kinds medium A
    @variables g(cell) = 0.0
    @lattice Lattice((24, 24))
    @energy cells => (volume - 16.0)^2
    @after_mcs g ~ g + 1.0
    @divide cells(A) when = g >= 3.0, along = RandomPlane(), g => 0.0
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model P60v3FuseOther begin
    @kinds medium A
    @variables g(cell) = 0.0
    @lattice Lattice((24, 24))
    @energy cells => (volume - 16.0)^2
    @after_mcs g ~ g + 1.0
    @divide cells(A) when = g[3 - id] >= 3.0, along = RandomPlane(), g => 0.0
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model P60v3FuseNotLast begin
    @kinds medium A
    @parameters k = 0.1
    @variables begin
        g(cell) = 0.0
        y(cell) = 1.0
    end
    @lattice Lattice((24, 24))
    @energy cells => (volume - 16.0)^2
    @after_mcs g ~ g + 1.0
    @equations D(y) ~ -k * y
    @divide cells(A) when = g >= 3.0, along = RandomPlane(), g => 0.0
    @sweep Metropolis(; temperature = 1.0)
end
@testset "P6.0v3: a cell update fuses with the lifecycle trigger only when legal" begin
    R(ex, w...) = Potts._reads_own_only(ex, Set{Symbol}(w))
    @test R(:(st.cell.g[c] >= 3), :g)
    @test R(:(@inbounds(st.cell.g[c]) >= 3), :g)
    @test R(:(Potts._cellval(st.cell.g, c) >= 3), :g)
    @test R(:(st.cell.volume[d] > 0 && st.σ[1] == 0 && p.a * st.model.m[1] > 0), :g)   # unwritten values: any
    @test R(:(Potts._cellkind(st, c) == 1), :g)
    @test R(:(CorePotts.centroid(st.cell, c)), :g)
    # negative controls: another cell's value, the whole column, cell or state
    @test !R(:(st.cell.g[3 - c] >= 3), :g)
    @test !R(:(Potts._cellval(st.cell.g, d) >= 3), :g)
    @test !R(:(sum(st.cell.g)), :g)
    @test !R(:(f(st.cell, c)), :g)
    @test !R(:(f(st)), :g)
    @test !R(:(Potts._cellkind(st, c) == 1), :kind)
    @test !R(:(CorePotts.centroid(st.cell, c)), :m1)
    σ = zeros(Int32, 24, 24); σ[3:6, 3:6] .= 1; σ[15:18, 15:18] .= 2
    op = [ownership => σ, kind => [:A, :A]]
    cellphases(prob) = count(ph -> ph isa CorePotts.CellPhase, prob.f.phases.after_mcs)
    own = PottsProblem(P60v3FuseOwn(; name = :f), op, (0, 8); capacity = 16)
    @test own.f.lifecycle.before !== nothing && cellphases(own) == 0
    for M in (P60v3FuseOther, P60v3FuseNotLast)
        prob = PottsProblem(M(; name = :f), op, (0, 8); capacity = 16)
        @test prob.f.lifecycle.before === nothing
        @test cellphases(prob) >= 1
    end
    # same results: the update still runs every MCS before the trigger (g = 0, 1, 2 → 3:
    # every live cell divides at MCS 2, 6, …)
    for alg in (SequentialCPM(), CheckerboardCPM())
        sol = solve(own, alg; saveat = 1)
        @test sol.stats.lifecycle.divisions == 2 + 4
        @test sol.u[4].cell.g[1:4] == zeros(4)
    end
end

# ---------------------------------------------------------------------------------------
# P6.0ah (D-107): textually equal folds over different bound variables in one statement keep
# a canonical slot numbering (their key carries the variables' names), and integrals of
# such folds stay distinct and are not hoisted apart from their trackers. A salted
# `Base.hash` of the Potts operators stands for another package build (inert at salt 0).

const P60AH_TIE_SALT = Ref{UInt}(0)
for f in (Potts.population, Potts.gather, Potts.at, Potts.at2, Potts.cell_integral)
    @eval function Base.hash(g::typeof($f), h::UInt)
        P60AH_TIE_SALT[] == 0 && return invoke(hash, Tuple{Function, UInt}, g, h)
        return hash(P60AH_TIE_SALT[], hash(:p60ah_tie_salt, h))
    end
end
p60ah_tie_salted(f, s) = (P60AH_TIE_SALT[] = s; try f() finally P60AH_TIE_SALT[] = 0 end)

@potts_model P60ahTieModel begin
    @kinds medium A
    @variables z(cell) = 1.0 g(model) = 0.5
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(g) ~ 0.01 * sum(z[c] for c in cells) + 0.02 * sum(z[c] for c in cells)^2 + 0.03 * sum(z[c] for c in cells)^3 - 0.1g
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model P60ahTieCell begin
    @kinds medium A
    @variables z(cell) = 1.0 y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @equations D(y) ~ 0.01 * sum(z[c] for c in cells) * y + 0.02 * sum(z[c] for c in cells)^2 + 0.03 * sum(z[c] for c in cells)^3 - 0.1y
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model P60ahTieUpd begin
    @kinds medium A
    @variables z(cell) = 1.0 y(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @after_mcs y ~ 0.01 * sum(z[c] for c in cells) * y + 0.02 * sum(z[c] for c in cells)^2 + 0.03 * sum(z[c] for c in cells)^3
    @sweep Metropolis(; temperature = 1.0)
end
@potts_model P60ahTieIntegral begin
    @kinds medium A
    @variables c(site) = 1.0 y(cell) = 0.0 w(cell) = 0.0
    @lattice Lattice((12, 8))
    @energy cells => (volume - 16.0)^2
    @after_mcs begin
        y ~ integral(c * sum(volume[k] for k in cells))
        w ~ 2 * integral(c * sum(volume[k] for k in cells))
    end
    @sweep Metropolis(; temperature = 1.0)
end

function p60ah_tie_code(M, solver)
    strip!(ex) = (ex isa Expr || return ex; Base.remove_linenums!(ex);
        ex.head === :macrocall && length(ex.args) >= 2 && ex.args[2] isa LineNumberNode && (ex.args[2] = nothing);
        foreach(strip!, ex.args); ex)
    g = Potts.generated_code(M(; name = :x); ode_solver = solver)
    return [string(strip!(deepcopy(x))) for k in propertynames(g) for x in (getproperty(g, k) isa AbstractVector ?
                                                                         getproperty(g, k) : (getproperty(g, k),))]
end
function p60ah_tie_problem(M)
    s = zeros(Int32, 12, 8)
    s[3:6, 3:6] .= 1
    s[7:10, 3:6] .= 2
    return PottsProblem(M(; name = :x), [ownership => s, kind => [:A, :A]], (0, 3); seed = 7, ode_solver = Potts.RK4())
end

@testset "P6.0ah: equal folds over different variables, independent of operator hashes" begin
    for M in (P60ahTieModel, P60ahTieCell, P60ahTieUpd, P60ahTieIntegral), solver in (Potts.ExplicitEuler(), Potts.RK4())
        base = p60ah_tie_code(M, solver)
        @test all(s -> p60ah_tie_salted(() -> p60ah_tie_code(M, solver), s) == base, 1:4)
    end
    state(u) = (Array(u.σ), map(Array, u.cell), map(Array, u.site), map(Array, u.model))
    for M in (P60ahTieModel, P60ahTieCell, P60ahTieUpd, P60ahTieIntegral)
        prob = p60ah_tie_problem(M)
        u = state(solve(prob, SequentialCPM()).u[end])
        for s in 1:4
            p = p60ah_tie_salted(() -> p60ah_tie_problem(M), s)
            @test p.f.fingerprint == prob.f.fingerprint
            @test state(solve(p, SequentialCPM()).u[end]) == u
        end
    end
    # the two integrals are distinct trackers (each fold, hoisted to its own slot, keeps its
    # bound variable's name in the key): integral(c · Σ volume) = (Σ_cell volume)², w = 2y
    xs = Potts._integrals(Potts.ModelingToolkitBase.mtkcompile(P60ahTieIntegral(; name = :x)).sys)
    @test length(xs) == 2 && Potts._integral_name(xs[1]) != Potts._integral_name(xs[2])
    s = zeros(Int32, 12, 8)
    s[3:6, 3:6] .= 1
    u = solve(PottsProblem(P60ahTieIntegral(; name = :x), Any[ownership => s, kind => [:A]], (0, 3)), SequentialCPM()).u[end]
    @test u.cell.y == [Float64(u.cell.volume[1])^2]
    @test u.cell.w == 2 .* u.cell.y
end

# A change re-derives a computed parameter iff it is not named and an input is named or
# re-derived (transitively); every other value is kept. Diamond p₁ → p₂, (p₂, p₃) → p₄, p₃ → p₅.
@potts_model ParamDiamond begin
    @kinds medium A
    @parameters begin
        p₁ = 1.0
        p₂ = 2p₁
        p₃ = 3.0
        p₄ = p₂ + p₃
        p₅ = 5p₃
        λ = 1.0
    end
    @lattice Lattice((6, 6); neighborhood = VonNeumann(1))
    @energy begin
        cells(A) => λ * (volume - p₄)^2
    end
    @sweep Metropolis(; temperature = 1.0)
end

@testset "computed parameters follow only their inputs" begin
    σ = zeros(Int32, 6, 6)
    σ[2:3, 2:3] .= 1
    prob = PottsProblem(ParamDiamond(; name = :pd), Any[ownership => σ, kind => [:A]], (0, 1))
    vals(q) = map(n -> getp(q, n)(q), (p₁ = :p₁, p₂ = :p₂, p₃ = :p₃, p₄ = :p₄, p₅ = :p₅, λ = :λ))
    @test vals(prob) == (p₁ = 1.0, p₂ = 2.0, p₃ = 3.0, p₄ = 5.0, p₅ = 15.0, λ = 1.0)
    q = remake(prob; p = [:p₅ => 7.0, :p₂ => 10.0])
    @test vals(q) == (p₁ = 1.0, p₂ = 10.0, p₃ = 3.0, p₄ = 13.0, p₅ = 7.0, λ = 1.0)   # p₄ re-derived from p₂
    @test vals(remake(q; p = [:λ => 2.0])) == (p₁ = 1.0, p₂ = 10.0, p₃ = 3.0, p₄ = 13.0, p₅ = 7.0, λ = 2.0)
    @test vals(remake(q; p = [:p₁ => 2.0])) == (p₁ = 2.0, p₂ = 4.0, p₃ = 3.0, p₄ = 7.0, p₅ = 7.0, λ = 1.0)
    @test vals(remake(q; p = [:p₃ => 1.0])) == (p₁ = 1.0, p₂ = 10.0, p₃ = 1.0, p₄ = 11.0, p₅ = 5.0, λ = 1.0)
    @test vals(remake(q; p = [:p₄ => 0.0, :p₁ => 3.0])) == (p₁ = 3.0, p₂ = 6.0, p₃ = 3.0, p₄ = 0.0, p₅ = 7.0, λ = 1.0)
    integ = init(q, SequentialCPM())
    integ.ps[:λ] = 4.0
    @test (integ.ps[:p₂], integ.ps[:p₄], integ.ps[:p₅]) == (10.0, 13.0, 7.0)
    integ.ps[:p₃] = 2.0
    @test (integ.ps[:p₂], integ.ps[:p₄], integ.ps[:p₅]) == (10.0, 12.0, 10.0)
    @test vals(prob) == (p₁ = 1.0, p₂ = 2.0, p₃ = 3.0, p₄ = 5.0, p₅ = 15.0, λ = 1.0)   # source unchanged
end

# `setp` with several names is one change, whatever the order of the names and whatever it
# was built on (integrator, problem, function, model description); `integ.ps[[x, y]] = v` too.
@testset "setp with several parameters is one change" begin
    σ = zeros(Int32, 6, 6)
    σ[2:3, 2:3] .= 1
    prob = PottsProblem(ParamDiamond(; name = :pd), Any[ownership => σ, kind => [:A]], (0, 1))
    fresh() = init(prob, SequentialCPM())
    state(i) = (i.ps[:p₁], i.ps[:p₂], i.ps[:p₄], i.ps[:p₅])
    for build in (identity, _ -> prob, _ -> prob.f, _ -> prob.f.sys)
        i = fresh()
        setp(build(i), [:p₄, :p₁])(i, [0.0, 3.0])
        @test state(i) == (3.0, 6.0, 0.0, 15.0)                  # p₄ named: kept; p₂ follows p₁
        i = fresh()
        setp(build(i), (:p₁, :p₄))(i, (3.0, 0.0))
        @test state(i) == (3.0, 6.0, 0.0, 15.0)
    end
    i = fresh()
    i.ps[[:p₄, :p₁]] = [0.0, 3.0]
    @test state(i) == (3.0, 6.0, 0.0, 15.0)
    # negative control: one name at a time is two changes, so the order matters
    i = fresh()
    i.ps[:p₄] = 0.0
    i.ps[:p₁] = 3.0
    @test state(i) == (3.0, 6.0, 9.0, 15.0)
    # all or nothing: a bad value leaves the parameters unchanged
    i = fresh()
    @test_throws ArgumentError setp(i, [:p₁, :nope])
    @test_throws DimensionMismatch setp(i, [:p₁, :p₃])(i, [3.0])
    @test state(i) == (1.0, 2.0, 5.0, 15.0)
end

# One name, one category, for vectors: a vector claims its name and each component name
# (`vb_1`, `vb_2`); a quantity of another category, or a scalar of the same category, named
# like a component is rejected (in one model, through `@extend`/`extend`, programmatically).
@potts_model NameVecBase begin
    @kinds medium host
    @parameters vb[1:2] = [1.0, 2.0]
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 10.0)
end
@potts_model NameVecVarBase begin
    @kinds medium host
    @variables vb_1(cell) = 7.0
    @observed tot ~ sum(volume for n in cells)
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = 10.0)
end

@potts_model NameVecUse begin
    @kinds medium host
    @parameters vb[1:3] = [1.0, 2.0, 3.0]
    @variables vw(cell)[1:3] = [0.1, 0.2, 0.3]
    @after_mcs vw[3] ~ Pre(vw[3]) + vb[3]
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2 + vb[3] * vw[3]
    @sweep Metropolis(; temperature = 10.0)
end

@testset "one name, one category: vector components" begin
    function rejection(f, words...)
        try
            f()
        catch e
            while e isa LoadError
                e = e.error
            end
            e isa ArgumentError || return "not an ArgumentError: $(typeof(e))"
            msg = sprint(showerror, e)
            return all(w -> occursin(w, msg), words) ? :ok : "message: $msg"
        end
        return "accepted silently"
    end
    model(stmts) = Base.invokelatest(() -> Base.invokelatest(@eval(@potts_model NameVecExt begin
        $(stmts.args...)
    end); name = :ext))
    single(stmts) = model(quote
        $(stmts.args...)
        @lattice Lattice((12, 12))
        @energy cells => (volume - 9.0)^2
        @sweep Metropolis(; temperature = 10.0)
    end)
    vec = "a parameter (a component of the vector `vb`)"
    # across categories, both directions, attributing the base's side
    @test rejection(() -> model(quote @extend NameVecBase(); @variables vb_1(cell) = 7.0 end),
        "variable `vb_1`", vec, "in the base") === :ok
    @test rejection(() -> model(quote @extend NameVecVarBase(); @parameters vb[1:2] = [1.0, 2.0] end),
        "`vb_1`", "variable in the base", "component of the vector `vb`") === :ok
    # within one model (`@potts_model` alone does not see the component names)
    @test rejection(() -> single(quote @kinds medium host; @parameters vb[1:2] = [1.0, 2.0]; @variables vb_1(cell) = 7.0 end),
        "variable `vb_1`", vec) === :ok
    # a scalar of the same category named like a component would leave half a vector
    @test rejection(() -> model(quote @extend NameVecBase(); @parameters vb_1 = 5.0 end),
        "parameter `vb_1`", vec, "in the base") === :ok
    @test rejection(() -> single(quote @kinds medium host; @parameters begin vb[1:2] = [1.0, 2.0]; vb_2 = 3.0 end end),
        "`vb_2`", "component of the vector `vb`") === :ok
    # programmatic: `extend` and a hand-built `PottsSystem`
    base, var = NameVecBase(; name = :b), NameVecVarBase(; name = :v)
    @test rejection(() -> extend(var, base), "`vb_1`", "in the base `b`", "component of the vector `vb`") === :ok
    @test rejection(() -> Potts.PottsSystem(; name = :p, kinds = base.kinds, lattice = base.lattice, sweep = base.sweep,
        parameters = Any[base.parameters...], variables = Any[var.variables...]), "`vb_1`", vec) === :ok
    # the label reads `parameter `vb_2` (a component of the vector `vb`)`
    @test rejection(() -> single(quote @kinds medium host; @parameters begin vb_2 = 3.0; vb[1:2] = [1.0, 2.0] end end),
        "parameter `vb_2` (a component of the vector `vb`)") === :ok
    # an override vector may not be shorter than the base's (the base reads `vb[3]`, `vw[3]`)
    @test rejection(() -> model(quote @extend NameVecUse(); @parameters vb[1:2] = [5.0, 6.0] end),
        "`vb` has 3 components in the base", "`vb[1:2]` would drop `vb_3`") === :ok
    @test rejection(() -> model(quote @extend NameVecUse(); @variables vw(cell)[1:2] = [0.0, 0.0] end),
        "`vw` has 3 components in the base", "`vw[1:2]` would drop `vw_3`") === :ok
    m = model(quote @extend NameVecUse(); @parameters vb[1:4] = [5.0, 6.0, 7.0, 8.0]; @variables vw(cell)[1:3] = [1.0, 1.0, 1.0] end)
    s = zeros(Int32, 12, 12); s[3:5, 3:5] .= 1
    sol = solve(PottsProblem(m, [ownership => s, kind => [:host]], (0, 2)), SequentialCPM(; proposal = Moore(1)); saveat = 1)
    @test observe(sol, :vw_3)[end] == [1.0 + 2 * 7.0]
    # the article follows the category
    @test rejection(() -> model(quote @extend NameVecVarBase(); @parameters tot = 1.0 end),
        "already declared as an observed quantity") === :ok
    # controls: a vector override replaces the base's vector whole; other names are free
    m = model(quote @extend NameVecBase(); @parameters vb[1:3] = [4.0, 5.0, 6.0] end)
    @test sort([Potts.info(p).name for p in m.parameters]) == [:vb_1, :vb_2, :vb_3] &&
          all(p -> Potts.info(p).default == 3.0 + Potts.info(p).options.index, m.parameters)
    m = model(quote @extend NameVecBase(); @variables vb_3(cell) = 1.0; @parameters vb₁ = 1.0 end)
    @test Potts.info(Potts.lookup(m, :vb_3)).role === :cell && mtkcompile(m) isa Potts.CompiledPottsSystem
end

# ---------------------------------------------------------------------------------------
# P6.0ai (D-110): a population fold inside `integral(x)` that reads neither the site nor the
# cell is computed once per refresh of the integral (a model slot), not at every site. The
# slot must be current at every refresh: in a block after a write to what the fold reads, at
# the MCS boundary after the lifecycle, at init, and for observed integrals.

for (M, lat) in ((:P60aiSquare, :(Lattice((16, 16)))),
                 (:P60aiHex, :(Lattice((16, 16); geometry = Hexagonal(), neighborhood = Hex(1)))),
                 (:P60ai3D, :(Lattice((8, 8, 8)))))
    @eval @potts_model $M begin
        @kinds medium A
        @variables begin
            w(site) = 1.0
            v(cell) = 0.0
            s(cell) = 0.0
            bo(cell) = 0.0
            q(cell) = 0.0
            n(cell) = 0.0
            r(cell) = 0.0
        end
        @lattice $lat
        @energy cells => (volume - 16.0)^2
        @after_mcs begin
            v ~ Pre(v) + 1
            s ~ integral(w * sum(v[c] for c in cells))                       # reads v, new this block
            bo ~ integral(w * (1 - 2 * any(volume[c] > 17 for c in cells)))   # a Boolean fold
            q ~ integral(w * sum(w for x in sites))                          # a fold over sites
            n ~ integral(sum(w * volume[c] for c in cells))                  # reads the site: per site
            r ~ integral(sum(rand() * volume[c] for c in cells) * 1e-300 + w) # draws per site: per site
        end
        @observed o(cell) ~ integral(w * mean(volume[c] for c in cells))
        @divide cells(A) when = mcs == 2, along = RandomPlane()
        @sweep Metropolis(; temperature = 2.0)
    end
end

function p60ai_init(dims)
    σ = zeros(Int32, dims)
    if length(dims) == 2
        σ[3:6, 3:6] .= 1; σ[10:13, 9:12] .= 2
    else
        σ[2:3, 2:3, 2:5] .= 1; σ[5:6, 5:6, 3:6] .= 2
    end
    w = [1 + 0.5 * sin(I[1] / 3) * cos(sum(Tuple(I)[2:end]) / 5) for I in CartesianIndices(dims)]
    return σ, w
end

@testset "P6.0ai: integral folds are hoisted, fresh at every refresh ($M, $(nameof(typeof(alg))))" for
        (M, dims) in ((P60aiSquare, (16, 16)), (P60aiHex, (16, 16)), (P60ai3D, (8, 8, 8))),
        alg in (SequentialCPM(), CheckerboardCPM())
    c = mtkcompile(M(; name = :x))
    xs = Potts._integrals(c.sys; observed = true)
    hoisted = [!Potts._has_op(x, Potts.population) for x in xs]
    @test count(hoisted) == 4                    # s, bo, q and the observed o; not n, r
    @test count(!, hoisted) == 2
    @test length(Potts._integrals(c.sys)) == 5    # o is read only by `@observed`: not stored (D-120)
    σ0, w0 = p60ai_init(dims)
    prob = PottsProblem(M(; name = :x), [ownership => σ0, kind => [:A, :A], :w => w0], (0, 4); capacity = 8, seed = 3)
    @test count(n -> startswith(String(n), "__ifold_"), propertynames(prob.u0.model)) == 4
    @test !hasproperty(prob.u0.cell, Potts._integral_name(last(xs)))   # (o has its fold slot, no column)
    live(u) = findall(>(0), Array(u.cell.volume))
    per(u, f) = [sum((f(i) for i in findall(==(k), Array(u.σ))); init = 0.0) for k in eachindex(u.cell.volume)]
    obs(u) = (V = Array(u.cell.volume); L = live(u); mv = sum(V[L]) / length(L); per(u, i -> w0[i] * mv))
    @test prob[:o] ≈ obs(prob.u0)                                         # at init
    sol = solve(prob, alg; saveat = 0:4)
    names = [Potts._integral_name(x) for x in Potts._integrals(c.sys)]
    divided = false
    for t in 1:4
        u, prev = sol.u[t + 1], sol.u[t]
        V, v = Array(u.cell.volume), Array(u.cell.v)
        @test sol[:o][t + 1] ≈ obs(u)                                     # observed, after divisions too
        # stored = recomputed from the saved state (the MCS boundary refresh, after the lifecycle)
        fresh = Potts._fresh_integrals(Float64, u, sol.prob.p, sol.prob.f.sys.ctx, t,
                                       Potts._integral_phases(sol.prob.f.sys.csys, Float64), names)
        @test all(n -> getfield(u.cell, n) ≈ getfield(fresh.cell, n), names)
        if length(live(u)) != length(live(prev))                          # a division after the block
            divided = true
            continue
        end
        L = live(u)
        @test v[L] == fill(t, length(L))
        @test u.cell.s ≈ per(u, i -> w0[i] * sum(v[L]))                   # the fold sees the new v
        @test !(u.cell.s ≈ per(u, i -> w0[i] * sum(v[L] .- 1)))           # (the stale one differs)
        big = any(>(17), V[L])
        @test u.cell.bo ≈ per(u, i -> big ? -w0[i] : w0[i])
        @test u.cell.q ≈ per(u, i -> w0[i] * sum(w0))
        @test u.cell.n ≈ per(u, i -> w0[i] * sum(V[L]))
        @test u.cell.r ≈ per(u, i -> w0[i])
    end
    @test divided
end

# Every refresh point of a hoisted fold's slot: at init (read by a before-MCS update in the
# first MCS), a gated reader of a fold whose operand the block writes, an equation reading
# such an integral after the block, and a checkpoint continuation.
@potts_model P60aiRefresh begin
    @kinds medium A
    @variables begin
        w(site) = 1.0
        v(cell) = 0.0
        sb(cell) = 0.0
        s2(cell) = 0.0
        r(cell) = 0.0
    end
    @lattice Lattice((16, 16))
    @energy cells => (volume - 16.0)^2
    @before_mcs sb ~ integral(w * sum(volume[c] for c in cells))
    @after_mcs v ~ Pre(v) + 1
    @after_mcs Every(2) s2 ~ integral(w * sum(v[c] for c in cells))
    @equations D(r) ~ integral(sin(w) * sum(v[c] for c in cells))
    @observed o(cell) ~ integral(w * mean(volume[c] for c in cells))
    @sweep Metropolis(; temperature = 2.0)
end

@testset "P6.0ai: hoisted folds are fresh at every refresh point ($(nameof(typeof(alg))))" for
        alg in (SequentialCPM(), CheckerboardCPM())
    σ0, w0 = p60ai_init((16, 16))
    prob = PottsProblem(P60aiRefresh(; name = :x), [ownership => σ0, kind => [:A, :A], :w => w0], (0, 4); seed = 5)
    per(u, f) = [sum((f(i) for i in findall(==(k), Array(u.σ))); init = 0.0) for k in eachindex(u.cell.volume)]
    vsum(u) = sum(Array(u.cell.v)[Array(u.cell.volume) .> 0])
    # at init: the stored tracker of the before-MCS operand, and its reader in MCS 1
    names = [Potts._integral_name(x) for x in Potts._integrals(mtkcompile(P60aiRefresh(; name = :x)).sys)]
    sb0 = per(prob.u0, i -> w0[i] * 32)
    @test count(n -> getfield(prob.u0.cell, n) ≈ sb0, names) == 1      # the tracker, in u0
    sol = solve(prob, alg; saveat = 0:4)
    @test sol.u[2].cell.sb ≈ sb0                                     # MCS 1 reads the initial state
    @test !(sol.u[2].cell.sb ≈ sb0 .* 0)
    for t in 1:4
        u, prev = sol.u[t + 1], sol.u[t]
        @test vsum(u) == 2t
        # gated: fresh in MCS 1, 3 (mcs 0, 2), kept in MCS 2, 4
        @test u.cell.s2 ≈ (isodd(t) ? per(u, i -> w0[i] * vsum(u)) : prev.cell.s2)
        # the equation (explicit Euler, dt = 1) integrates the fresh integral of each MCS
        @test u.cell.r - prev.cell.r ≈ per(u, i -> sin(w0[i]) * vsum(u))
    end
    @test !(sol.u[2].cell.s2 ≈ per(sol.u[2], i -> w0[i] * 0))
    # a checkpoint continuation equals the uninterrupted run
    integ = init(prob, alg)
    foreach(_ -> step!(integ), 1:2)
    rest = solve!(init(prob, alg; checkpoint = checkpoint(integ))).u[end]
    @test rest.σ == sol.u[end].σ
    @test all(n -> getfield(rest.cell, n) == getfield(sol.u[end].cell, n), propertynames(rest.cell))
    @test all(n -> getfield(rest.model, n) == getfield(sol.u[end].model, n), propertynames(rest.model))
end

@testset "P6.0ai: observed integrals leave the state unchanged" begin
    σ0, w0 = p60ai_init((16, 16))
    prob = PottsProblem(P60aiRefresh(; name = :x), [ownership => σ0, kind => [:A, :A], :w => w0], (0, 2); seed = 5)
    slots = filter(n -> startswith(String(n), "__ifold_"), propertynames(prob.u0.model))
    @test length(slots) == 4
    mark!(u) = foreach(n -> fill!(getfield(u.model, n), -7.0), slots)
    unchanged(u, cell) = all(n -> all(==(-7.0), getfield(u.model, n)), slots) &&
                         all(n -> getfield(u.cell, n) == getfield(cell, n), propertynames(cell))
    oracle(u) = (V = u.cell.volume; L = V .> 0; mv = sum(V[L]) / count(L);
                 [sum((w0[i] * mv for i in findall(==(k), u.σ)); init = 0.0) for k in eachindex(V)])
    mark!(prob.u0); c0 = deepcopy(prob.u0.cell)
    @test prob[:o] ≈ oracle(prob.u0)
    @test unchanged(prob.u0, c0)
    sol = solve(prob, SequentialCPM())
    mark!(sol.u[end]); c1 = deepcopy(sol.u[end].cell)
    @test sol[:o][end] ≈ oracle(sol.u[end])
    @test unchanged(sol.u[end], c1)
    integ = init(prob, SequentialCPM()); step!(integ)
    mark!(integ.state); c2 = deepcopy(integ.state.cell)
    @test integ[:o] ≈ oracle(integ.state)
    @test unchanged(integ.state, c2)
end

# `div`/`÷` on parameters and cell quantities in step code, and a variable default computed
# with a function of parameters (D-117)
@potts_model P60aoDivEnergy begin
    @kinds medium A
    @parameters begin
        n = 7.0
        λ = 1.0
    end
    @variables begin
        goal(cell) = sqrt(n + 2)
    end
    @lattice Lattice((12, 12); neighborhood = VonNeumann(1))
    @energy begin
        cells(A) => λ * (volume - n ÷ 2 - goal)^2 + div(volume, 4)
    end
    @sweep Metropolis(; temperature = 10.0)
end

@testset "div and ÷ in energies; variable defaults with functions" begin
    σ = zeros(Int32, 12, 12); σ[3:5, 3:5] .= 1; σ[8:9, 8:9] .= 2
    prob = PottsProblem(P60aoDivEnergy(; name = :x), [ownership => σ, kind => [:A, :A]], (0, 20); seed = 3)
    @test prob.u0.cell.goal[1:2] == [3.0, 3.0]                       # sqrt(7 + 2)
    oracle(V, n) = sum((v - div(n, 2) - 3)^2 + div(v, 4) for v in V if v > 0)
    @test total_energy(prob) == oracle([9, 4], 7.0)                     # 9 + 2 + 4 + 1
    @test total_energy(remake(prob; p = [:n => 4.0])) == oracle([9, 4], 4.0)
    worst = 0.0
    for (u, prop) in proposal_states(prob; mcs = (0, 5), n = 300)
        a = deepcopy(u); a.σ[prop.target] = prop.new
        prob.f.commit!(a, prob.p, prop, ctx_of(prob))
        worst = max(worst, abs(energy_change(prob, u, prop) - (total_energy(prob, a) - total_energy(prob, u) + Potts._killing_credit(prob, u, prop, a))))
    end
    @test worst < 1e-9
    sol = solve(prob, SequentialCPM())
    @test total_energy(prob, sol.u[end]) ≈ oracle(sol.u[end].cell.volume[1:2], 7.0)
    # on numbers: Julia's `div` (integers stay integers; floats in their own type)
    @test Potts._intdiv(7, 2) === 3 && Potts._intdiv(Int32(7), 2) === 3 && Potts._intdiv(7.0, 2) === 3.0
    @test Potts._intdiv(7.5f0, 2.0f0) === 3.0f0 && Potts._intdiv(-7.5f0, 2) === -3.0f0
    # equal to Base where the quotient is exact in Float32 (|a / b| < 2^24)
    xs = Float32[0.3, -7.5, 1.0f5, 12.0, 5.0f-3, 9.0, -9.5]
    @test all(((a, b),) -> Potts._intdiv(a, b) === div(a, b), Iterators.product(xs, Float32[0.1, 2, -3, 1.5]))
    # zero derivative (piecewise constant)
    a, b = Potts.Symbolics.@variables a b
    @test isequal(Potts.Symbolics.derivative(Potts._intdiv(a, b), a), 0)
end

@testset "a model may not define its own `div` or `÷`" begin
    for def in (:(div(a, b) = a), :(function ÷(a::T, b) where {T}; a; end), :(div = max))
        err = try
            macroexpand(@__MODULE__, :(@potts_model LocalDiv begin
                $def
                @kinds medium A
            end))
            nothing
        catch e
            e
        end
        @test err isa ArgumentError && occursin("integer division", sprint(showerror, err))
    end
    # a field named `div` in a named tuple is not a definition
    @test Potts._div_definition(:(f(x) = (div = x ÷ 2,))) === nothing
end

# ---------------------------------------------------------------------------------------
# P6.0t (D-120): the start-of-after refresh covers the integrals read after the sweep, and
# a tick reads its population folds through slots (`__tickpop`), so an integral read only
# inside a tick's fold must still count as read after the sweep. Twin: the same fold over
# `volume` (w ≡ 1 makes `integral(w)` the volume); a stale integral lags one MCS.
@named p60t_ctr = System([dn(_kd) ~ dn(_kd - 1) + dinc], _tc)
for (M, x) in ((:P60tTickIntegral, :(integral(w))), (:P60tTickVolume, :volume))
    @eval @potts_model $M begin
        @kinds medium A
        @variables begin
            w(site) = 1.0
            u(site) = 0.0
            sa(cell) = 0.0
        end
        @components cells(A) ctr = p60t_ctr
        @equations ctr.dinc ~ sum($x^2 for c in cells)
        @after_mcs sa ~ integral(u)
        @lattice Lattice((16, 16))
        @energy cells => (volume - 9.0)^2
        @sweep Metropolis(; temperature = 20.0)
    end
end

@testset "P6.0t: an integral read only in a tick's population fold is fresh ($(nameof(typeof(alg))))" for
        alg in (SequentialCPM(), CheckerboardCPM())
    σ = zeros(Int32, 16, 16); σ[3:5, 3:5] .= 1; σ[10:12, 10:12] .= 2
    dn(M) = (sol = solve(PottsProblem(M(; name = :x), [ownership => σ, kind => [:A, :A]], (0, 12); seed = 1), alg; saveat = 0:12);
             [Array(u.cell.ctr₊dn)[1] for u in sol.u])
    a, b = dn(P60tTickIntegral), dn(P60tTickVolume)
    @test a == b
    @test length(unique(diff(b))) > 1                  # the volumes move: a lag would show
end

# Stored integrals keep the full gather's order (and the fingerprint) when no integral is
# read only by `@observed`: here `@observed` is the first statement to read pb.
@named p60t_rctr = System([dn(_kd) ~ dn(_kd - 1) + dinc], _tc)
@potts_model P60tOrder begin
    @kinds medium A
    @variables begin
        pa(site) = 1.0
        pb(site) = 1.0
    end
    @components cells(A) ctr = p60t_rctr
    @equations ctr.dinc ~ integral(pa)
    @observed o(cell) ~ integral(pa) + integral(pb)
    @lattice Lattice((16, 16))
    @energy cells => (volume - 9.0)^2
    @sweep Metropolis(; temperature = integral(pb) / 9)
end

@testset "P6.0t: stored integrals keep their order without observed-only readers" begin
    c = mtkcompile(P60tOrder(; name = :x))
    @test [Potts.info(x).name for x in Potts._integrals(c.sys)] == [:pa, :pb]
    @test isequal(Potts._integrals(c.sys; observed = true), Potts._integrals(c.sys))
    σ = zeros(Int32, 16, 16); σ[3:5, 3:5] .= 1; σ[10:12, 10:12] .= 2
    prob = PottsProblem(P60tOrder(; name = :x), [ownership => σ, kind => [:A, :A]], (0, 3); seed = 1)
    @test prob.f.fingerprint == 0x38850600cfaa35ae                     # as on 1289afae
end

@potts_model OnCopyIndexInline begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @on_copy y[ifelse(count(owner[n] == 1 for n in Moore(3)(target)) > 3, new, old)] ~ y[new] + 1.0
    @sweep Metropolis(; temperature = 2.0)
end
@potts_model OnCopyIndexNamed begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 12))
    @relations far = Moore(3)
    @energy cells => (volume - 9.0)^2
    @on_copy y[ifelse(count(owner[n] == 1 for n in far(target)) > 3, new, old)] ~ y[new] + 1.0
    @sweep Metropolis(; temperature = 2.0)
end
@potts_model OnCopyIndexPlain begin
    @kinds medium A
    @variables y(cell) = 0.0
    @lattice Lattice((12, 12))
    @energy cells => (volume - 9.0)^2
    @on_copy y[new] ~ y[new] + 1.0
    @sweep Metropolis(; temperature = 2.0)
end

@testset "a gather in an on-copy update's index: numbered, in the footprint, same as named" begin
    σ = zeros(Int32, 12, 12); σ[2:4, 2:4] .= 1; σ[7:9, 7:9] .= 2
    op = Any[ownership => σ, kind => [:A, :A]]
    run(mk) = (prob = PottsProblem(mk(; name = :g), op, (0, 6); seed = 7, capacity = 16);
               (prob, solve(prob, SequentialCPM(); saveat = 1)))
    (pi, si), (pn, sn) = run(OnCopyIndexInline), run(OnCopyIndexNamed)
    @test [u.σ for u in si.u] == [u.σ for u in sn.u]
    @test [u.cell.y for u in si.u] == [u.cell.y for u in sn.u]
    @test sum(si.u[end].cell.y) > 0                       # the update ran
    # the index's relation sets the read reach (Moore(3) → 3); the plain index stays at 1
    @test mtkcompile(OnCopyIndexInline(; name = :g)).footprint.read == 3
    @test mtkcompile(OnCopyIndexNamed(; name = :g)).footprint.read == 3
    @test mtkcompile(OnCopyIndexPlain(; name = :g)).footprint.read == 1
end

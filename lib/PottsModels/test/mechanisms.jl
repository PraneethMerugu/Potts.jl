# Ordinary tests of what each published model is for (D-048). Everything the models compute
# is re-derived here from the model's specification (its docstring and `@potts_model`
# source), not from production code:
#
# - drives and constraints: every sampled proposal's ΔH minus the energy change equals the
#   drive formula, and the constraint equals the connectivity rule re-implemented here;
# - effects: on-copy writes, after-MCS updates, field steps and division against direct
#   recomputation, on configurations where only the effect under test can act;
# - mechanisms with negative controls: the mechanism moves the outcome in the stated
#   direction, and switching it off removes the effect.
using Statistics: mean, median
include("akeeb_metrics.jl")

const CP = CorePotts

"""Interface proposals (source and target owned differently) on states along a trajectory of
`prob`, up to `n` per state, evenly spread: a vector of (u, prop, ctx)."""
function sampled_proposals(prob; nmcs = 6, n = 300, proposal = Moore(1))
    sol = solve(remake(prob; tspan = (0, nmcs)), SequentialCPM(; proposal); saveat = 0:2:nmcs)
    lat = prob.lattice
    ctx = (; lattice = lat, contact = prob.contact, prob.relations...)
    moore = CP.relation(Moore(1), lat)
    out = []
    for u in sol.u
        all_ = []
        for t in eachindex(u.σ), o in moore.offsets
            x = CP.coordinates(lat, t)
            inside, y = CP.shift(lat, x, o)
            inside || continue
            s = CP.linear_index(lat, y)
            u.σ[t] == u.σ[s] || push!(all_, (u, CP.Proposal(t, s, x, 1, u.σ[t], u.σ[s]), ctx))
        end
        append!(out, all_[round.(Int, range(1, length(all_); length = min(n, length(all_))))])
    end
    return out
end
drive(prob, u, prop, ctx) = prob.f.delta_H(u, prob.p, prop, ctx) - energy_change(prob, u, prop)
kindof(u, c) = c == 0 ? 0 : Int(u.cell.kind[c])

# Ring rules on the clockwise Moore ring around the target (out-of-lattice sites are
# medium). CC3D's `Connectivity` (`one_arc`): the losing cell's ring sites form exactly one
# arc (none, i.e. its last site or an isolated fragment, is rejected: D-074). The Merks et al.
# (2006) rule (`ring_rule`) also accepts several arcs when exactly two distinct cells occupy
# the ring.
const RING = ((-1, -1), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0))
function ring_owners(σ, x, periodic)
    X, Y = size(σ)
    return map(RING) do (dx, dy)
        u, v = x[1] + dx, x[2] + dy
        periodic[1] ? (u = mod1(u, X)) : (1 <= u <= X || return 0)
        periodic[2] ? (v = mod1(v, Y)) : (1 <= v <= Y || return 0)
        σ[u, v]
    end
end
arcs(σ, x, a, periodic) = (own = ring_owners(σ, x, periodic); n = count(k -> own[k] == a && own[mod1(k - 1, 8)] != a, 1:8);
    n == 0 && all(==(a), own) ? 1 : n)
one_arc(σ, x, a, periodic) = arcs(σ, x, a, periodic) == 1
ring_rule(σ, x, a, periodic) = one_arc(σ, x, a, periodic) || (arcs(σ, x, a, periodic) > 1 &&
                               length(unique(filter(>(0), collect(ring_owners(σ, x, periodic))))) == 2)

"""Cells whose sites are not one 8-connected piece (axes periodic as given)."""
function split_ids(σ, periodic)
    X, Y = size(σ); out = eltype(σ)[]
    for c in unique(σ)
        c == 0 && continue
        idx = findall(==(c), σ); seen = Set([idx[1]]); st = [idx[1]]
        while !isempty(st)
            q = pop!(st)
            for dx in -1:1, dy in -1:1
                x, y = q[1] + dx, q[2] + dy
                periodic[1] ? (x = mod1(x, X)) : (1 <= x <= X || continue)
                periodic[2] ? (y = mod1(y, Y)) : (1 <= y <= Y || continue)
                p = CartesianIndex(x, y)
                (σ[p] == c && !(p in seen)) && (push!(seen, p); push!(st, p))
            end
        end
        length(seen) < length(idx) && push!(out, c)
    end
    return out
end
split_cells(σ, periodic) = length(split_ids(σ, periodic))

blockstate(dims, blocks...) = (s = zeros(Int32, dims); foreach(((k, b),) -> s[b...] .= k, enumerate(blocks)); s)

@testset "Graner–Glazier" begin
    σ, k = graner_glazier_state()
    function hetero(σ)                     # dark–light fraction of cell–cell Moore bonds
        nx, ny = size(σ); he = ho = 0
        for y in 1:ny, x in 1:nx, (dx, dy) in ((1, 0), (0, 1), (1, 1), (1, -1))
            a = σ[x, y]; b = σ[mod1(x + dx, nx), mod1(y + dy, ny)]
            (a == b || a == 0 || b == 0) && continue
            k[a] == k[b] ? (ho += 1) : (he += 1)
        end
        return he / (he + ho)
    end
    h0 = hetero(σ)
    sorted(J) = [hetero(solve(PottsProblem(GranerGlazier(; name = :gg), [ownership => σ, kind => k, :J => J],
        (0, 300); seed), SequentialCPM(; proposal = Moore(1))).u[end].σ) for seed in 1:3]
    # differential adhesion sorts; equal adhesion does not; reversed adhesion mixes
    @test all(<(h0 - 0.1), sorted([0 16 16; 16 2 11; 16 11 14]))
    @test all(h -> abs(h - h0) < 0.05, sorted([0 16 16; 16 11 11; 16 11 11]))
    @test all(>(h0 + 0.2), sorted([0 16 16; 16 14 2; 16 2 14]))

    # at T → 0 only non-increasing copies are accepted: H never rises, for either algorithm
    # (for checkerboard this checks that same-color copies' ΔH add up exactly)
    cold = PottsProblem(GranerGlazier(; name = :gg), [ownership => σ, kind => k, :T => 1e-9], (0, 20))
    for alg in (SequentialCPM(; proposal = Moore(1)), CheckerboardCPM(; proposal = Moore(1)))
        Hs = [total_energy(cold, u) for u in solve(cold, alg; saveat = 1:20).u]
        @test all(diff(Hs) .<= 1e-9)
        @test Hs[end] < Hs[1]
    end
end

# The paper-size aggregate (P6.1b2) and its layout, `VoronoiBall`, checked against their
# definitions: a centroidal Voronoi tessellation of a Euclidean ball, every cell one piece.
"""Share of ball sites whose nearest cell centroid (Euclidean, embedded by `pos`) is their own cell's."""
function own_centroid_share(σ, pos)
    sites = [x for x in CartesianIndices(σ) if σ[x] != 0]
    P = [collect(pos(x)) for x in sites]
    n = maximum(σ)
    cen = [sum(P[i] for i in eachindex(sites) if σ[sites[i]] == c) ./ count(==(c), σ) for c in 1:n]
    return count(i -> argmin(c -> sum(abs2, P[i] .- cen[c]), 1:n) == σ[sites[i]], eachindex(sites)) / length(sites)
end
"""Cells whose sites are not one piece under the index offsets `offs` (no wrap)."""
function pieces_split(σ, offs)
    bad = 0
    for c in 1:maximum(σ)
        idx = findall(==(c), σ); isempty(idx) && continue
        seen = Set([idx[1]]); st = [idx[1]]
        while !isempty(st)
            q = pop!(st)
            for o in offs
                p = q + CartesianIndex(o)
                checkbounds(Bool, σ, p) && σ[p] == c && !(p in seen) && (push!(seen, p); push!(st, p))
            end
        end
        bad += length(seen) < length(idx)
    end
    return bad
end
const SQ2 = ((1, 0), (-1, 0), (0, 1), (0, -1))
const HEX1 = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, -1), (-1, 1))
const CUBE = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))
hexpos(x) = (x[1] + x[2] / 2, x[2] * sqrt(3) / 2)
"""The labels of the Voronoi cells before the connectivity repair (the internal first stage)."""
function raw_voronoi(l, clat, dims)
    owner, sites, _, _ = PottsModels._voronoi_cells(l, clat, nothing, dims)
    σ = zeros(Int32, dims)
    foreach(((i, x),) -> σ[x] = owner[i], enumerate(sites))
    return σ
end

@testset "VoronoiBall and the paper-size Graner–Glazier aggregate" begin
    # square, 2D: the ball is exactly the sites within `radius`; a centroidal tessellation
    op = layout(VoronoiBall(40; radius = 15.5, center = (20, 21), kinds = [:a, :b], seed = 3), (40, 42))
    σ = op[1].second
    @test Set(findall(!=(0), σ)) == Set(x for x in CartesianIndices(σ) if (x[1] - 20)^2 + (x[2] - 21)^2 <= 15.5^2)
    @test maximum(σ) == 40 && op[2].second == repeat([:a, :b], 20)
    @test own_centroid_share(σ, x -> Float64.(Tuple(x))) > 0.97
    rnd = zeros(Int32, size(σ)); ball = findall(!=(0), σ)            # control: random labels are not
    foreach(((i, x),) -> rnd[x] = mod1(i * 7919, 40), enumerate(ball))
    @test own_centroid_share(rnd, x -> Float64.(Tuple(x))) < 0.2
    @test layout(VoronoiBall(40; radius = 15.5, kinds = [:a], seed = 3, iterations = 0), (40, 42))[1].second != σ
    @test_throws ArgumentError layout(VoronoiBall(50; radius = 3, kinds = [:a], seed = 1), (10, 10))
    # hexagonal: round in the embedding, not in axial indices
    hex = Lattice((50, 50); geometry = Hexagonal())
    σh = layout(VoronoiBall(30; radius = 14, center = (25 - 12, 25), kinds = [:a], seed = 1), hex)[1].second
    xy = [hexpos(Tuple(x)) for x in findall(!=(0), σh)]
    @test all(v -> abs(maximum(getindex.(xy, v)) - minimum(getindex.(xy, v)) - 28) <= 2, 1:2)
    @test own_centroid_share(σh, x -> hexpos(Tuple(x))) > 0.97
    # 3D
    σ3 = layout(VoronoiBall(20; radius = 7, kinds = [1], seed = 2), (17, 17, 17))[1].second
    @test maximum(σ3) == 20 && count(!=(0), σ3) == count(x -> sum(abs2, Tuple(x) .- 9) <= 49, CartesianIndices(σ3))

    # the nearest-generator search against brute force
    for (l, clat, dims, pos) in (
            (VoronoiBall(60; radius = 12.3, kinds = [1], seed = 5), Lattice((30, 30); boundary = Closed()), (30, 30), Tuple),
            (VoronoiBall(25; radius = 9, kinds = [1], seed = 5, iterations = 0), Lattice((30, 30); boundary = Closed()), (30, 30), Tuple),
            (VoronoiBall(150; radius = 10.3, center = (10, 15), kinds = [1], seed = 2),
                Lattice((30, 30); geometry = Hexagonal(), boundary = Closed()), (30, 30), hexpos),
            (VoronoiBall(100; radius = 8.2, kinds = [1], seed = 4), Lattice((19, 19, 19); boundary = Closed()), (19, 19, 19), Tuple))
        owner, sites, _, gens = PottsModels._voronoi_cells(l, clat, nothing, dims)
        d2(x, g) = sum(abs2, collect(pos(Tuple(x))) .- collect(pos(g)))
        # a nearest generator (up to rounding: hex ties differ in the last bits)
        @test all(i -> d2(sites[i], gens[owner[i]]) <= minimum(k -> d2(sites[i], gens[k]), eachindex(gens)) + 1e-9,
            eachindex(sites))
        wrong = copy(owner); wrong[1] = mod1(wrong[1] + 1, length(gens))    # control: a wrong owner is caught
        @test !all(i -> d2(sites[i], gens[wrong[i]]) <= minimum(k -> d2(sites[i], gens[k]), eachindex(gens)) + 1e-9,
            eachindex(sites))
    end

    # every cell is one piece under the nearest-neighbour steps, over many seeds; the
    # Voronoi stage alone (before the repair) is not, so the check can fail
    for (mk, clat, dims, steps) in (
            (seed -> VoronoiBall(60; radius = 10.3, kinds = [1], seed), Lattice((24, 24); boundary = Closed()), (24, 24), SQ2),
            (seed -> VoronoiBall(150; radius = 10.3, center = (10, 15), kinds = [1], seed),
                Lattice((30, 30); geometry = Hexagonal(), boundary = Closed()), (30, 30), HEX1),
            (seed -> VoronoiBall(100; radius = 8.2, kinds = [1], seed), Lattice((19, 19, 19); boundary = Closed()), (19, 19, 19), CUBE))
        @test count(seed -> pieces_split(raw_voronoi(mk(seed), clat, dims), steps) > 0, 1:60) >= 2
        @test all(seed -> pieces_split(layout(mk(seed), clat)[1].second, steps) == 0, 1:60)
    end

    # sorting proceeds on the aggregate; symmetric contacts (no differential adhesion) do not sort
    σ, k = graner_glazier_aggregate(200; seed = 1)
    function hetero(σ)                     # dark–light fraction of cell–cell Moore bonds
        he = ho = 0
        for x in CartesianIndices(σ), d in ((1, 0), (0, 1), (1, 1), (1, -1))
            y = x + CartesianIndex(d)
            checkbounds(Bool, σ, y) || continue
            a, b = σ[x], σ[y]
            (a == b || a == 0 || b == 0) && continue
            k[a] == k[b] ? (ho += 1) : (he += 1)
        end
        return he / (he + ho)
    end
    h0 = hetero(σ)
    run(J) = [hetero(Array(solve(PottsProblem(GranerGlazier(; name = :gg, lattice = size(σ)),
        [ownership => σ, kind => k, :J => J], (0, 300); seed), SequentialCPM(; proposal = Moore(1))).u[end].σ)) for seed in 1:2]
    @test all(<(h0 - 0.1), run([0 16 16; 16 2 11; 16 11 14]))
    @test all(h -> abs(h - h0) < 0.05, run([0 16 16; 16 11 11; 16 11 11]))
end

# Merks' cell length (Eq. 5), from σ: 4√λ_max of the covariance of the cell's site coordinates
function merks_length(σ, c)
    x = [Float64.(Tuple(i)) for i in findall(==(c), σ)]
    isempty(x) && return 0.0
    m = (mean(first, x), mean(last, x))
    a, b, d = (mean(v -> (v[1] - m[1])^2, x), mean(v -> (v[1] - m[1]) * (v[2] - m[2]), x), mean(v -> (v[2] - m[2])^2, x))
    return 4sqrt(max((a + d) / 2 + sqrt(((a - d) / 2)^2 + b^2), 0.0))
end
"""Merks' Hamiltonian from σ alone (Eqs. 1, 4; J over Moore pairs, closed walls)."""
function merks_energy(σ, p)
    X, Y = size(σ)
    H = 0.0
    for x in 1:X, y in 1:Y, (dx, dy) in ((1, -1), (1, 0), (1, 1), (0, 1))
        u, v = x + dx, y + dy
        (1 <= u <= X && 1 <= v <= Y && σ[x, y] != σ[u, v]) || continue
        H += p.J[(σ[x, y] != 0) + 1, (σ[u, v] != 0) + 1]
    end
    for c in unique(σ)
        c == 0 && continue
        H += p.λ * (count(==(c), σ) - p.V₀)^2 + p.λ_L * (merks_length(σ, c) - p.L)^2
    end
    return H
end
"""Components of `mask` (4-connected): sizes and whether each touches the lattice edge."""
function components(mask)
    lab = zeros(Int, size(mask)); sizes = Int[]; edge = Bool[]; parts = Vector{CartesianIndex{2}}[]
    for I in CartesianIndices(mask)
        (mask[I] && lab[I] == 0) || continue
        push!(sizes, 0); push!(edge, false); push!(parts, CartesianIndex{2}[])
        k = length(sizes); lab[I] = k; st = [I]
        while !isempty(st)
            J = pop!(st); sizes[k] += 1; push!(parts[k], J)
            (J[1] in (1, size(mask, 1)) || J[2] in (1, size(mask, 2))) && (edge[k] = true)
            for d in ((1, 0), (-1, 0), (0, 1), (0, -1))
                K = J + CartesianIndex(d)
                checkbounds(Bool, mask, K) && mask[K] && lab[K] == 0 && (lab[K] = k; push!(st, K))
            end
        end
    end
    return sizes, edge, parts
end
_cross(o, a, b) = (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
"""Area of the convex hull of points (Andrew's monotone chain)."""
function hull_area(pts)
    P = sort(unique(pts))
    half(Q) = foldl((h, q) -> (while length(h) >= 2 && _cross(h[end - 1], h[end], q) <= 0; pop!(h); end; push!(h, q)), Q; init = eltype(Q)[])
    h = [half(P)[1:(end - 1)]; half(reverse(P))[1:(end - 1)]]
    return abs(sum(k -> h[k][1] * h[mod1(k + 1, end)][2] - h[mod1(k + 1, end)][1] * h[k][2], eachindex(h))) / 2
end
"""Largest cell cluster's area over the area of its convex hull (PLoS 2008 Fig. S1)."""
function compactness(σ)
    sizes, _, parts = components(σ .!= 0)
    best = parts[argmax(sizes)]
    return length(best) / hull_area([(i[1] + dx, i[2] + dy) for i in best for dx in 0:1 for dy in 0:1])
end

@testset "Merks vasculogenesis" begin
    L = 20
    σ0 = blockstate((L, L), (3:6, 3:6), (12:15, 4:7), (8:11, 13:16))
    c0 = [0.01 * (x + 2y) for x in 1:L, y in 1:L]
    op = [ownership => σ0, kind => fill(:endothelial, 3), :c => c0, :χ => 50.0, :V₀ => 16.0, :L => 6.0, :Dc => 0.08,
          :σc => 0.02, :δc => 0.01]
    prob = PottsProblem(MerksVasculogenesis(; name = :m, lattice = (L, L)), op, (0, 10))
    p = prob.p
    # chemotaxis on every copy: −χ (c[target] − c[source]) (Eq. 2); contact-inhibited, only
    # on extensions of a cell into the medium (PLoS 2008). The constraint is CC3D's one-arc
    # rule for endothelial losers.
    props = sampled_proposals(prob)
    @test length(props) > 500
    @test all(((u, prop, ctx),) -> isapprox(drive(prob, u, prop, ctx),
        -p.χ * (u.site.c[prop.target] - u.site.c[prop.source]); atol = 1e-9), props)
    ci = PottsProblem(MerksVasculogenesis(; name = :m, lattice = (L, L), contact_inhibited = true), op, (0, 10))
    @test all(sampled_proposals(ci)) do (u, prop, ctx)
        want = prop.old == 0 && prop.new != 0 ? -p.χ * (u.site.c[prop.target] - u.site.c[prop.source]) : 0.0
        isapprox(drive(ci, u, prop, ctx), want; atol = 1e-9)
    end
    @test all(((u, prop, ctx),) -> prob.f.constraint(u, p, prop, ctx) ==
                                   (prop.old == 0 || one_arc(u.σ, prop.x, prop.old, (false, false))), props)
    # the energy change is that of J adhesion, the area and the length constraint, with the
    # cell length recomputed from σ (Eq. 5)
    @test all(props) do (u, prop, ctx)
        a = copy(u.σ); a[prop.target] = prop.new
        isapprox(energy_change(prob, u, prop), merks_energy(a, p) - merks_energy(u.σ, p); rtol = 1e-9, atol = 1e-6)
    end

    # the field: after each sweep, two explicit Euler substeps of D Δc + α·[cell] − ε c·[medium]
    # (Eq. 6), zero flux at the closed walls, clipped at 0, using the post-sweep ownership
    function euler2(c, σ)
        X, Y = size(c)
        for _ in 1:2
            nb(x, y, u, v) = (1 <= u <= X && 1 <= v <= Y) ? c[u, v] : c[x, y]
            c = [max(c[x, y] + 0.5 * (p.Dc * (nb(x, y, x + 1, y) + nb(x, y, x - 1, y) + nb(x, y, x, y + 1) +
                                           nb(x, y, x, y - 1) - 4c[x, y]) + p.σc * (σ[x, y] != 0) -
                                      p.δc * c[x, y] * (σ[x, y] == 0)), 0.0)
                 for x in 1:X, y in 1:Y]
        end
        return c
    end
    sol = solve(prob, SequentialCPM(); saveat = 0:10)
    @test all(k -> isapprox(sol.u[k + 1].site.c, euler2(sol.u[k].site.c, sol.u[k + 1].σ); atol = 1e-12), 1:10)

    # an explicit substep count is a minimum: the paper's diffusion constant (D = 0.75 per
    # MCS, the default) needs 3 substeps, and 2 would diverge (it reached 1e65 by MCS 200)
    sp = zeros(Int32, 40, 40); sp[18:23, 18:23] .= 1
    fast = solve(PottsProblem(MerksVasculogenesis(; name = :m, lattice = (40, 40)),
        [ownership => sp, kind => [:endothelial]], (0, 200)), SequentialCPM()).u[end]
    @test all(isfinite, fast.site.c) && maximum(fast.site.c) < 1.5

    # mechanism: in a static gradient (no secretion, diffusion or decay) a cell climbs it for
    # χ > 0, descends for χ < 0, and does not drift for χ = 0
    G = 40
    cue = [0.05 * x for x in 1:G, y in 1:G]
    drift(χ) = map(1:8) do seed
        s = blockstate((G, G), (18:23, 18:23))
        u = solve(PottsProblem(MerksVasculogenesis(; name = :m, lattice = (G, G)),
            [ownership => s, kind => [:endothelial], :c => copy(cue), :Dc => 0.0, :δc => 0.0, :σc => 0.0,
             :χ => χ, :V₀ => 36.0, :λ => 1.0, :λ_L => 0.0, :T => 6.0, :J => zeros(2, 2)], (0, 200); seed),
            SequentialCPM()).u[end]
        mean(i[1] for i in findall(==(1), u.σ)) - 20.5
    end
    @test mean(drift(100.0)) > 10
    @test abs(mean(drift(0.0))) < 4
    @test mean(drift(-100.0)) < -10

    # mechanism (Fig. 6; the paper's title claim): at the paper's parameters elongated cells
    # (λ_L > 0, L = 30) form a network, a sparse cluster far from its convex hull, while
    # round cells (λ_L = 0) aggregate into compact islands
    function vasculo(λ_L, seed)
        u = solve(PottsProblem(MerksVasculogenesis(; name = :m, lattice = (140, 140)),
            [merks_state(; lattice = (140, 140), n = 100, seed); :λ_L => λ_L], (0, 1500); seed),
            SequentialCPM(); saveat = 1500).u[end]
        el = map(c -> (s = CP.shape(u.cell, CP.Lattice((140, 140)), c); s.elongation), 1:100)
        return (; compact = compactness(u.σ), largest = maximum(components(u.σ .!= 0)[1]), elongation = mean(el))
    end
    net, isl = [vasculo(5.0, s) for s in 1:3], [vasculo(0.0, s) for s in 1:3]
    @test mean(r -> r.compact, net) < 0.4 && mean(r -> r.compact, isl) > 0.5
    @test mean(r -> r.largest, net) > 2 * mean(r -> r.largest, isl)
    @test mean(r -> r.elongation, net) > 3 && mean(r -> r.elongation, isl) < 2
end

@testset "Wortel Act" begin
    L = 16
    σ0 = blockstate((L, L), (3:6, 3:6), (10:13, 9:12))
    prob = PottsProblem(WortelAct(; name = :w, lattice = (L, L)),
        [ownership => σ0, kind => [:cell, :cell], :λ => 5.0, :V₀ => 16.0, :λₛ => 0.5, :S₀ => 24.0, :λ_act => 20.0,
         :J => [0.0 10.0; 10.0 20.0], :T => 10.0], (0, 10))
    p = prob.p
    # the Act drive on every copy: −(λ_act/max_act)(GM(source) − GM(target)), GM(s) the
    # geometric mean of act over s and its Moore(1) sites owned like s (0 if any is 0; the
    # medium's is 0)
    function GM(u, i)
        X, Y = size(u.σ); x = CP.coordinates(prob.lattice, i)
        own = u.σ[i]
        own == 0 && return 0.0
        vals = [u.site.act[mod1(x[1] + dx, X), mod1(x[2] + dy, Y)] for dx in -1:1, dy in -1:1
                if u.σ[mod1(x[1] + dx, X), mod1(x[2] + dy, Y)] == own]
        return prod(vals)^(1 / length(vals))
    end
    props = sampled_proposals(prob)
    @test length(props) > 300
    @test all(props) do (u, prop, ctx)
        isapprox(drive(prob, u, prop, ctx), -(p.λ_act / p.max_act) * (GM(u, prop.source) - GM(u, prop.target)); atol = 1e-9)
    end
    # retractions from active sites are penalised: start fully active
    hot = remake(prob; u0 = [ownership => σ0, kind => [:cell, :cell], :act => p.max_act .* (σ0 .!= 0)])
    hprops = sampled_proposals(hot; nmcs = 0)
    @test count(((u, prop, ctx),) -> prop.new == 0 && GM(u, prop.target) > 0, hprops) > 10
    @test all(hprops) do (u, prop, ctx)
        isapprox(drive(hot, u, prop, ctx), -(p.λ_act / p.max_act) * (GM(u, prop.source) - GM(u, prop.target)); atol = 1e-9)
    end
    # connectivity is off by default; `connected = true` is the arc-or-pair ring rule
    @test all(((u, prop, ctx),) -> prob.f.constraint(u, p, prop, ctx), props)
    cprob = PottsProblem(WortelAct(; name = :w, lattice = (L, L), connected = true),
        [ownership => σ0, kind => [:cell, :cell], :λ => 5.0, :V₀ => 16.0, :λₛ => 0.5, :S₀ => 24.0, :λ_act => 20.0], (0, 10))
    @test all(((u, prop, ctx),) -> cprob.f.constraint(u, cprob.p, prop, ctx) ==
                                   (prop.old == 0 || ring_rule(u.σ, prop.x, prop.old, (true, true))), sampled_proposals(cprob))
    # on copy: every site a cell gains is fully active, a site the medium takes inactive;
    # nothing else changes
    @test all(props) do (u, prop, ctx)
        a = deepcopy(u); a.σ[prop.target] = prop.new
        prob.f.commit!(a, p, prop, ctx)
        want = copy(u.site.act); want[prop.target] = prop.new != 0 ? p.max_act : 0.0
        a.site.act == want
    end
    # after each MCS activity decays by one to zero: with the cell frozen (no copy can pay
    # the volume cost) the field is max(act₀ − k, 0) after k MCS
    act0 = [Float64(mod(x + y, 7)) for x in 1:L, y in 1:L] .* (σ0 .!= 0)
    frozen = PottsProblem(WortelAct(; name = :w, lattice = (L, L)),
        [ownership => σ0, kind => [:cell, :cell], :act => act0, :λ => 1e6, :V₀ => 16.0, :λ_act => 1.0], (0, 4))
    sol = solve(frozen, SequentialCPM(); saveat = 0:4)
    @test all(k -> sol.u[k + 1].σ == σ0 && sol.u[k + 1].site.act == max.(act0 .- k, 0.0), 0:4)

    # mechanism: Act makes a cell migrate persistently; without it the cell only jitters
    G = 80
    circ(σ, d) = (θ = [2π * (i[d] - 1) / G for i in findall(==(1), σ)]; atan(mean(sin.(θ)), mean(cos.(θ))) * G / 2π)
    mi(a) = a - G * round(a / G)                                     # periodic minimum image
    function net(λ_act)
        map(1:8) do seed
            s = blockstate((G, G), (35:44, 35:44))
            sol = solve(PottsProblem(WortelAct(; name = :w, lattice = (G, G)),
                [ownership => s, kind => [:cell], :J => [0.0 20.0; 20.0 0.0], :λ => 5.0, :V₀ => 100.0,
                 :λₛ => 0.5, :S₀ => 150.0, :T => 20.0, :λ_act => λ_act, :max_act => 40.0], (0, 300); seed),
                SequentialCPM(); saveat = 0:10:300)
            cs = [(circ(u.σ, 1), circ(u.σ, 2)) for u in sol.u]
            hypot(sum(k -> mi(cs[k + 1][1] - cs[k][1]), 1:(length(cs) - 1)),
                  sum(k -> mi(cs[k + 1][2] - cs[k][2]), 1:(length(cs) - 1)))
        end
    end
    on, off = net(200.0), net(0.0)
    @test median(on) > 8
    @test median(on) > 3 * median(off)
end

@testset "single-division fixture" begin
    # division at MCS 0 when the area has reached V₀, along x through the centroid, halving
    # the mass. The cell is frozen (no copy can pay the volume cost), so the partition is
    # exactly the sites right of the centroid.
    σ0 = blockstate((12, 8), (5:8, 4:5))                          # area 8, centroid x = 6.5
    run(V₀) = solve(PottsProblem(SingleDivisionFixture(; name = :o),
        [ownership => σ0, kind => [:epithelial], :λ => 1e6, :V₀ => V₀], (0, 1); capacity = 4),
        SequentialCPM(; proposal = Moore(1))).u[end]
    u = run(8.0)
    d = only(filter(c -> c != 1 && u.cell.volume[c] > 0, eachindex(u.cell.volume)))
    @test findall(==(1), u.σ) == findall(!iszero, blockstate((12, 8), (5:6, 4:5)))
    @test findall(==(d), u.σ) == findall(!iszero, blockstate((12, 8), (7:8, 4:5)))
    @test u.cell.mass[1] == u.cell.mass[d] == 4.0
    # under the normal dynamics the trigger reads the area after MCS 0's sweep, which is
    # what MCS 1 shows: one cell iff that area was below V₀, else two summing to it
    outcomes = map(1:40) do seed
        v = solve(PottsProblem(SingleDivisionFixture(; name = :o), [ownership => σ0, kind => [:epithelial], :V₀ => 7.0],
            (0, 1); capacity = 4, seed), SequentialCPM(; proposal = Moore(1))).u[end].cell.volume
        live = filter(>(0), v)
        (length(live), sum(live))
    end
    @test all(((n, a),) -> n == 1 ? a < 7 : (n == 2 && a >= 7), outcomes)
    @test any(o -> o[1] == 1, outcomes) && any(o -> o[1] == 2, outcomes)
    # no division after MCS 0
    late = solve(PottsProblem(SingleDivisionFixture(; name = :o), [ownership => σ0, kind => [:epithelial], :V₀ => 100.0],
        (0, 30); capacity = 4), SequentialCPM(; proposal = Moore(1)))
    @test late.stats.lifecycle.divisions == 0
end

@testset "OpenVT growing monolayer" begin
    live(u) = count(>(0), u.cell.volume)
    function grow(; L = 160, n = 840, every = 42, seed = 1, p...)
        op = [openvt_monolayer_state(; lattice = (L, L)); [k => v for (k, v) in p]]
        integ = init(PottsProblem(OpenVTGrowingMonolayer(; name = :m, lattice = (L, L)), op, (0, n); seed, capacity = 4096),
            SequentialCPM(); save_start = false, save_end = false)
        counts, us = Int[], []
        for k in 1:n
            step!(integ)
            k % every == 0 && (push!(counts, live(integ.state)); push!(us, deepcopy(integ.state)))
        end
        return counts, us
    end
    # growth law: an isolated cell's target area gains A₀/τ per MCS; with β > 1 it never grows
    _, us = grow(; L = 40, n = 30, every = 1)
    @test [u.cell.V_target[1] for u in us] ≈ 25 .+ (1:30) .* (25 / 84)
    _, us = grow(; L = 40, n = 30, every = 1, β = 2.0)
    @test all(u -> u.cell.V_target[1] == 25, us)
    # exponential growth with a doubling time of about τ (the area lags the target a little);
    # halving τ halves it
    doubling(c, every) = every * (length(c) - 1) / log2(c[end] / c[1])
    c84, _ = grow(; n = 840, every = 168)
    c42, _ = grow(; n = 420, every = 84, τ = 42.0)
    @test 84 <= doubling(c84[2:end], 168) <= 1.3 * 84
    @test 42 <= doubling(c42[2:end], 84) <= 1.3 * 42
    # contact inhibition (β = 0.95): compressed interior cells stop growing, so the colony
    # grows more slowly; without it every cell grows
    c0, u0 = grow()
    cβ, uβ = grow(; β = 0.95)
    quiescent(u) = count(c -> u.cell.volume[c] > 0 && u.cell.volume[c] < 0.95 * u.cell.V_target[c], eachindex(u.cell.volume))
    @test cβ[end] < 0.7 * c0[end]
    @test quiescent(uβ[end]) > 0.2 * cβ[end]
    # the division plane is uniform: the doubled angle between the first two daughters'
    # centroids has no preferred direction
    angles = map(1:40) do seed
        integ = init(PottsProblem(OpenVTGrowingMonolayer(; name = :m, lattice = (40, 40)),
            openvt_monolayer_state(; lattice = (40, 40)), (0, 300); seed, capacity = 16), SequentialCPM())
        while live(integ.state) < 2
            step!(integ)
        end
        σ, v = integ.state.σ, integ.state.cell.volume
        m = [(x = findall(==(c), σ); (mean(i[1] for i in x), mean(i[2] for i in x))) for c in findall(>(0), v)]
        d = m[2] .- m[1]
        2atan(d[2], d[1])
    end
    @test hypot(mean(cos.(angles)), mean(sin.(angles))) < 0.35
end

@testset "Akeeb invasion" begin
    W, H = 60, 40
    op = akeeb_state(; lattice = (W, H))
    prob = PottsProblem(AkeebInvasion(; name = :a, lattice = (W, H)), op, (0, 10); capacity = 600)
    p = prob.p
    leader(u, c) = c != 0 && u.cell.kind[c] == 1
    # the cue drive acts on copies involving a leader; connectivity (ring rule) and no
    # extinction for every cell
    props = sampled_proposals(prob)
    @test all(props) do (u, prop, ctx)
        want = leader(u, prop.new) || leader(u, prop.old) ? -p.μ * (u.site.cue[prop.target] - u.site.cue[prop.source]) : 0.0
        isapprox(drive(prob, u, prop, ctx), want; atol = 1e-9)
    end
    @test all(props) do (u, prop, ctx)
        want = prop.old == 0 || (u.cell.volume[prop.old] > 1 && one_arc(u.σ, prop.x, prop.old, (true, false)))
        prob.f.constraint(u, p, prop, ctx) == want
    end
    # after each MCS: running clocks tick, target volumes grow by `rate` below V_max; no
    # clock can pass clock_min within 10 MCS from ≤ 64, so nothing divides yet
    c0, r0 = op[3].second, op[4].second
    early = findall(c -> c <= 64, c0)
    u = solve(prob, SequentialCPM(; proposal = VonNeumann(1))).u[end]
    @test all(c -> u.cell.clock[c] == (c0[c] >= 0 ? c0[c] + 10 : c0[c]), early)
    @test all(c -> u.cell.V_target[c] ≈ 10 + 10r0[c], eachindex(c0))
    # mechanism: leaders climb the cue and lead the invasion; without the cue they stay in
    # the slab. Proliferation needs mitotic clocks (pp = 0: no division).
    function invade(μ; pp = 0.5, nmcs = 200)
        map(1:3) do seed
            o = akeeb_state(; lattice = (99, 60), pp, seed)
            u = solve(PottsProblem(AkeebInvasion(; name = :a, lattice = (99, 60)), [o; :μ => μ], (0, nmcs);
                capacity = 1000, seed), SequentialCPM(; proposal = VonNeumann(1))).u[end]
            akeeb_metrics(u.σ, u.cell.kind .== 1, length(o[2].second))
        end
    end
    on, off = invade(30.0), invade(0.0)
    @test all(m -> m.leader_mean_y > 28, on) && all(m -> m.leader_mean_y < 20, off)
    # CC3D connectivity keeps every cell in one piece under copies (the legacy `:merks` rule
    # split 4–6). Without clocks (pp = 0): a random-plane division may cut a non-convex
    # follower into pieces, as in CC3D (2 of 30 seeds with pp = 0.5, D-068 seeding)
    for seed in 1:3
        o = akeeb_state(; lattice = (99, 60), seed, pp = 0.0)
        u = solve(PottsProblem(AkeebInvasion(; name = :a, lattice = (99, 60)), o, (0, 200); capacity = 1000, seed),
            SequentialCPM(; proposal = VonNeumann(1))).u[end]
        @test split_cells(u.σ, (true, false)) == 0
    end
    # with clocks, every cell that becomes split does so in an MCS where it took part in a
    # division: either a cell born that MCS took most of its sites from it (a split mother),
    # or it was born that MCS with most of its sites from one cell (a split daughter)
    newly = map((3, 5, 6, 24)) do seed
        o = akeeb_state(; lattice = (99, 60), seed)
        sol = solve(PottsProblem(AkeebInvasion(; name = :a, lattice = (99, 60)), o, (0, 200); capacity = 1000,
            seed), SequentialCPM(; proposal = VonNeumann(1)); saveat = 1)
        n = 0
        for t in 2:length(sol.u)
            a, b = sol.u[t - 1], sol.u[t]
            was = Set(split_ids(a.σ, (true, false)))
            born = [d for d in eachindex(b.cell.volume) if b.cell.volume[d] > 0 &&
                    (d > length(a.cell.volume) || a.cell.volume[d] == 0)]
            from(d, m) = 2 * count(i -> a.σ[i] == m, findall(==(d), b.σ)) > b.cell.volume[d]
            for c in split_ids(b.σ, (true, false))
                c in was && continue
                n += 1
                mother = any(d -> from(d, c), born)
                daughter = c in born && any(m -> m != 0 && from(c, m), unique(a.σ[b.σ .== c]))
                @test mother || daughter
            end
        end
        n
    end
    @test sum(newly) >= 1
    @test all(m -> m.divisions > 0, invade(30.0; nmcs = 300)) && all(m -> m.divisions == 0, invade(30.0; pp = 0.0, nmcs = 300))
end

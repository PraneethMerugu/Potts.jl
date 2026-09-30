"""
    GranerGlazier(; name, lattice = (72, 72), λ, V₀, T, J)

Cell sorting by differential adhesion (Graner & Glazier, Phys. Rev. Lett. 69, 2013, 1992):
two cell kinds with an area constraint and kind-dependent contact energies on a periodic
lattice with Moore contacts and proposals. The defaults are the papers' (PRL p. 2015; PRE
p. 2139): `J_dd = 2`,
`J_dl = 11`, `J_ll = 14`, `J_cM = 16`, `λ = 1`, `V₀ = 40`, `T = 10`. They satisfy its sorting
hierarchy `J_dd < (J_dd + J_ll)/2 < J_dl < J_ll < J_M` (PRL Eq. 3), and light cells engulf
the dark ones.

Differences from the paper (Glazier & Graner, Phys. Rev. E 47, 2128, 1993):
- one MCS here is `N` copy attempts, the paper's is `16N`, so paper time `t` is ours `16t`;
- 64 cells (`graner_glazier_state`) against about 1000: bulk topology (⟨n⟩, moments) is not
  measurable, boundary fractions scale with perimeter/area, and sorting levels off after
  about 500 paper MCS instead of continuing to 10⁴. `scale` tiling makes more aggregates,
  not a bigger one;
- a periodic lattice (the paper does not say): fine for sorting, not for runs where cells
  detach and would wrap around;
- the model does not anneal. The paper measures on a copy annealed for 2 paper MCS at T = 0
  (32 of ours); `test/papers.jl` does the same;
- one `V₀` for both kinds: the cavity run (per-kind targets, non-neighbour copies) is not
  expressible yet.
"""
@potts_model GranerGlazier begin
    @structural_parameters begin
        lattice = (72, 72)
    end
    @kinds medium dark light
    @parameters begin
        λ = 1.0
        V₀ = 40.0
        T = 10.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    end
    @lattice Lattice(lattice; boundary = Periodic(), neighborhood = Moore(1))
    @relations proposal = Moore(1)          # the paper copies from the 8 neighbours
    @energy begin
        cells(dark, light) => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = T)
end

"""
    graner_glazier_state(scale = 1) -> (labels, kinds)

The 72×72 initial condition of PRE §II D3 (D-049 F-2; `data/graner/generate.jl`): a square
51×50 aggregate of 64 staggered rectangular cells of height 5 and various widths (mean area
40) is relaxed as one type for 400 paper MCS until boundary length and medium fraction are
flat, then each cell is dark or light with probability ½ (33 dark, 31 light). Tiled
`scale × scale` times. Kinds are numbers (1 = dark, 2 = light).
"""
function graner_glazier_state(scale::Integer = 1)
    dir = joinpath(@__DIR__, "..", "data", "graner")
    σ1 = Int32.(readdlm(joinpath(dir, "pre_equilibrated_ownership.tsv"), '\t', Int))
    k1 = Int32.(vec(readdlm(joinpath(dir, "cell_kinds.tsv"), '\t', Int)))
    nc = length(k1)
    σ = reduce(vcat, [reduce(hcat, [map(s -> s == 0 ? Int32(0) : s + Int32(nc * (i * scale + j)), σ1)
        for j in 0:(scale - 1)]) for i in 0:(scale - 1)])
    return σ, repeat(k1, scale^2)
end

"""
    graner_glazier_aggregate(n = 1000; seed = 1) -> (labels, kinds)

A paper-size initial condition (PRE 47, p. 2129: "about 1000 cells"): one round aggregate
of `n` cells of about `V₀ = 40` sites, dark (1) and light (2) randomly mixed in equal
numbers (±1), surrounded by a medium margin of 10 sites on a square lattice sized to fit
(use `lattice = size(labels)`). Built with the [`VoronoiBall`](@ref) layout (a centroidal
Voronoi tessellation of a disk of area `40n`), deterministic in `seed`.

The paper relaxes its aggregate as one cell type for 400 paper MCS before assigning types
(§II D3). The centroidal tessellation already has what that relaxation is for (compact,
nearly equal cells with straight boundaries), so no Potts relaxation is run: at `T = 10`
the boundaries roughen to their thermal shape within the first paper MCS.
"""
function graner_glazier_aggregate(n::Integer = 1000; seed::Integer = 1)
    radius = sqrt(40n / π)
    L = 2ceil(Int, radius) + 1 + 2 * 10
    op = layout(VoronoiBall(n; radius, kinds = Int32[1, 2], seed), (L, L))
    return op[1].second, op[2].second
end

"""
    VoronoiBall(n; radius, center = <lattice centre>, kinds, seed, iterations = 30)

A layout: the sites within `radius` of `center` (a ball), divided into `n` cells of about
equal volume. The cells are the lattice Voronoi regions of `n` generators, drawn at distinct
random ball sites with `StableRNG(seed)` and moved `iterations` times to the centroid of
their region (Lloyd's algorithm): compact, convex, nearly equal cells, like a relaxed foam.
`kinds` is cycled over the cells in generator order; the generators are random, so the kinds
are mixed at random in space and in equal numbers (±1 for two kinds).

`center` is in lattice indices (axial on a hexagonal lattice). Distances and centroids are
Euclidean in the lattice's Cartesian embedding (`embed`), so the ball and the cells are round
on hexagonal lattices too, and `radius` is in embedded lengths (lattice spacings). Any
dimension. Sites outside the lattice or its domain are not in the ball: a ball crossing a
boundary, periodic or not, is clipped, not wrapped. Throws an `ArgumentError` when the ball
has fewer than `n` sites.
"""
struct VoronoiBall{K} <: AbstractLayout
    n::Int
    radius::Float64
    center::Union{Nothing, Vector{Float64}}
    kinds::Vector{K}
    seed::UInt64
    iterations::Int
end
function VoronoiBall(n::Integer; radius::Real, center = nothing, kinds, seed::Integer, iterations::Integer = 30)
    n >= 1 || throw(ArgumentError("VoronoiBall: n must be positive, got $n"))
    radius > 0 || throw(ArgumentError("VoronoiBall: radius must be positive, got $radius"))
    iterations >= 0 || throw(ArgumentError("VoronoiBall: iterations must be non-negative, got $iterations"))
    0 <= seed <= typemax(UInt64) || throw(ArgumentError("VoronoiBall: seed must be in 0:typemax(UInt64), got $seed"))
    k = collect(kinds)
    isempty(k) && throw(ArgumentError("VoronoiBall: `kinds` is empty"))
    return VoronoiBall(Int(n), Float64(radius), center === nothing ? nothing : Float64.(collect(center)), k,
        UInt64(seed), Int(iterations))
end

_dist2(clat, x, g) = sum(abs2, embed(clat, map(-, x, g)))

# Nearest generator of every ball site. Each generator scans the index box of half-width
# `2h` around it, which holds its Cartesian `h`-ball on square and hexagonal lattices (their
# inverse embeddings have row norms 1 and 2/√3). A site whose nearest scanned generator lies
# within `h` has found its true nearest one; otherwise `h` doubles. Ties go to the lower
# generator. Returns the `h` that sufficed.
function _voronoi_assign!(owner, best, sites, index, gens, clat, h)
    dims = size(index)
    while true
        fill!(owner, 0)
        fill!(best, Inf)
        w = ceil(Int, 2h)
        for (k, g) in enumerate(gens)
            box = CartesianIndices(ntuple(d -> max(1, round(Int, g[d]) - w):min(dims[d], round(Int, g[d]) + w), length(dims)))
            for x in box
                i = index[x]
                i == 0 && continue
                d2 = _dist2(clat, Float64.(Tuple(x)), g)
                d2 < best[i] && (best[i] = d2; owner[i] = k)
            end
        end
        maximum(best) <= h^2 && return h
        h *= 2
    end
end

function Potts.paint!(σ, kinds, l::VoronoiBall, lat)
    clat = Potts.core_lattice(lat)
    dims = size(σ)
    N = length(dims)
    c = l.center === nothing ? map(d -> (d + 1) / 2, dims) : Tuple(l.center)
    length(c) == N || throw(ArgumentError("VoronoiBall: center has $(length(c)) coordinates, the lattice is $(N)D"))
    mask = lat.domain
    index = zeros(Int, dims)
    sites = CartesianIndex{N}[]
    for x in CartesianIndices(dims)
        (mask === nothing || mask[x]) || continue
        _dist2(clat, Float64.(Tuple(x)), c) <= l.radius^2 || continue
        push!(sites, x)
        index[x] = length(sites)
    end
    m, n = length(sites), l.n
    m >= n || throw(ArgumentError("VoronoiBall: the ball holds $m sites, fewer than the $n cells"))
    rng = StableRNG(l.seed)
    taken = falses(m)
    gens = Vector{NTuple{N, Float64}}(undef, n)
    for k in 1:n
        i = rand(rng, 1:m)
        while taken[i]
            i = rand(rng, 1:m)
        end
        taken[i] = true
        gens[k] = Float64.(Tuple(sites[i]))
    end
    owner, best = zeros(Int, m), zeros(m)
    sums, counts = zeros(N, n), zeros(Int, n)
    h = 2.0 * sqrt(m / n)
    for _ in 1:(l.iterations)
        h = _voronoi_assign!(owner, best, sites, index, gens, clat, h)
        h = max(1.0, 1.25sqrt(maximum(best)))       # the next pass starts near the need
        fill!(sums, 0.0)
        fill!(counts, 0)
        for (i, x) in enumerate(sites)
            k = owner[i]
            counts[k] += 1
            for d in 1:N
                sums[d, k] += x[d]
            end
        end
        for k in 1:n
            counts[k] > 0 && (gens[k] = ntuple(d -> sums[d, k] / counts[k], N))
        end
    end
    _voronoi_assign!(owner, best, sites, index, gens, clat, h)
    base = length(kinds)
    for k in 1:n
        push!(kinds, l.kinds[mod1(k, length(l.kinds))])
    end
    for (i, x) in enumerate(sites)
        σ[x] = Int32(base + owner[i])
    end
    return σ
end

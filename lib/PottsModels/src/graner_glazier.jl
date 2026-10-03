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

The 72×72 initial condition of PRE §II D3 (made by `data/graner/generate.jl`): a square
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
    graner_glazier_aggregate(n = 1000; seed = 1, margin = 60) -> (labels, kinds)

A paper-size initial condition (PRE 47, p. 2129: "about 1000 cells"): one round aggregate
of `n` cells of about `V₀ = 40` sites, dark (1) and light (2) randomly mixed in equal
numbers (±1; the paper does not state the fraction), surrounded by a medium margin of
`margin` sites on a square lattice of side `2⌈√(40n/π)⌉ + 1 + 2margin` (use
`lattice = size(labels)`). On the periodic `GranerGlazier` lattice the gap to the
aggregate's image is `2margin`. The default of 60 sites is for long runs: over thousands of
MCS the whole aggregate drifts, and with a small margin (10 sites) it reaches the lattice
edge and wraps across it (`n = 200`: after about 23 000 MCS for one run seed), and over
10⁴ paper MCS a 1000-cell aggregate joins its periodic image. Short runs can pass a smaller
`margin` to save lattice area (the lattice grows as the square of its side). The
aggregate is rebuilt on the larger lattice, not embedded: a different `margin` can move a
few boundary sites between cells (32 sites for `n = 1000`, `seed = 9`, margin 60 against
10), so compare margins statistically, not site by site. Built with the
[`VoronoiBall`](@ref) layout (a centroidal Voronoi tessellation of a disk of area `40n`),
deterministic in `seed`.

The paper relaxes its aggregate as one cell type for 400 paper MCS before assigning types
(§II D3); no Potts relaxation is run here. The cell areas are more spread than after that
relaxation: SD 7.6 (range 21–67) for `n = 1000`, against 1.6 for a Potts-relaxed aggregate.
The sorting time course does not see the difference: the heterotypic boundary fractions from
this start and from a relaxed one agree within 0.005 at 1, 10 and 100 paper MCS (6
seeds). The area term evens the cells out within the first MCS.
"""
function graner_glazier_aggregate(n::Integer = 1000; seed::Integer = 1, margin::Integer = 60)
    margin >= 0 || throw(ArgumentError("graner_glazier_aggregate: margin must be non-negative, got $margin"))
    radius = sqrt(40n / π)
    L = 2ceil(Int, radius) + 1 + 2margin
    op = layout(VoronoiBall(n; radius, kinds = Int32[1, 2], seed), (L, L))
    return op[1].second, op[2].second
end

"""
    VoronoiBall(n; radius, center = <lattice centre>, kinds, seed, iterations = 30)

A layout: the sites within `radius` of `center` (a ball), divided into `n` compact cells.
The cells are the lattice Voronoi regions of `n` generators, drawn at distinct random ball
sites with `StableRNG(seed)` and moved `iterations` times to the centroid of their region
(Lloyd's algorithm). Cell volumes are similar but not equal (in 2D, a volume SD of about a
fifth of the mean). A lattice Voronoi region can have stray single sites; each piece that is
not connected to its cell's largest piece is given to the neighbouring cell it shares the
most bonds with, so every cell is one piece under the nearest-neighbour steps of the
geometry (the shortest steps in the embedding: the 2N axis steps on a square lattice, the 6
neighbours on a hexagonal one), hence under any neighbourhood that contains them
(VonNeumann, Moore, Hex).
`kinds` is cycled over the cells in generator order; the generators are random, so the kinds
are mixed at random in space and in equal numbers (±1 for two kinds).

`center` is in lattice indices (axial on a hexagonal lattice). Distances and centroids are
Euclidean in the lattice's Cartesian embedding (`embed`), so the ball and the cells are round
on hexagonal lattices too. The embedding ignores the lattice spacing: `radius` is in lattice
spacings, and on a lattice with unequal spacings the ball is round in index units, not in
physical units. Any dimension. Sites outside the lattice or its domain are not in the ball:
a ball crossing a boundary, periodic or not, is clipped, not wrapped. Throws an
`ArgumentError` when the ball has fewer than `n` sites.
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

# Per axis, the index half-width of the box that holds a Cartesian ball of radius 1: the
# row norms of the inverse of the embedding matrix E (|xᵢ| = |(E⁻¹v)ᵢ| ≤ ‖rowᵢ(E⁻¹)‖ |v|).
# 1 on square lattices, 2/√3 for both axes on hexagonal ones. Derived from `embed`, which
# must be linear (checked), so a new geometry cannot silently break the exact search.
function _box_scale(clat, ::Val{N}) where {N}
    E = [Float64(embed(clat, ntuple(k -> Float64(k == j), N))[i]) for i in 1:N, j in 1:N]
    v = ntuple(k -> 0.5 + k, N)
    all(i -> isapprox(embed(clat, v)[i], sum(E[i, j] * v[j] for j in 1:N); atol = 1e-12), 1:N) ||
        throw(ArgumentError("VoronoiBall: the lattice embedding is not linear"))
    A = hcat(E, [Float64(i == j) for i in 1:N, j in 1:N])      # Gauss–Jordan: [E | I] → [I | E⁻¹]
    for c in 1:N
        p = c - 1 + argmax(abs.(A[c:N, c]))
        abs(A[p, c]) > 1e-12 || throw(ArgumentError("VoronoiBall: the lattice embedding is singular"))
        A[[c, p], :] = A[[p, c], :]
        A[c, :] ./= A[c, c]
        for r in 1:N
            r == c || (A[r, :] .-= A[r, c] .* A[c, :])
        end
    end
    return ntuple(i -> sqrt(sum(abs2, A[i, (N + 1):end])), Val(N))
end

# Nearest generator of every ball site. Each generator scans the index box that holds its
# Cartesian `h`-ball (`_box_scale`, plus ½ for rounding the generator's position). A site
# whose nearest scanned generator lies within `h` has found its true nearest one; otherwise
# `h` doubles. Ties go to the lower generator. Returns the `h` that sufficed.
function _voronoi_assign!(owner, best, index::Array{Int, N}, gens, clat, scale, h) where {N}
    dims = size(index)
    while true
        fill!(owner, 0)
        fill!(best, Inf)
        w = ceil.(Int, h .* scale .+ 0.5)
        for (k, g) in enumerate(gens)
            box = CartesianIndices(ntuple(d -> max(1, round(Int, g[d]) - w[d]):min(dims[d], round(Int, g[d]) + w[d]),
                Val(N)))
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

# The lattice Voronoi cells after Lloyd, before `_connect_pieces!`: the owner of every ball
# site (`sites[i]`, `index[x] = i`) and the final generators.
function _voronoi_cells(l::VoronoiBall, clat, mask, dims::NTuple{N, Int}) where {N}
    c = l.center === nothing ? map(d -> (d + 1) / 2, dims) : Tuple(l.center)
    length(c) == N || throw(ArgumentError("VoronoiBall: center has $(length(c)) coordinates, the lattice is $(N)D"))
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
    scale = _box_scale(clat, Val(N))
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
        _voronoi_assign!(owner, best, index, gens, clat, scale, h)
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
    _voronoi_assign!(owner, best, index, gens, clat, scale, h)
    return owner, sites, index, gens
end

# The nearest-neighbour steps of the geometry: the offsets in {-1, 0, 1}ᴺ of shortest
# embedded length (2N axis steps on square lattices, 6 on hexagonal ones).
function _nearest_steps(clat, ::Val{N}) where {N}
    offs = [o for o in Iterators.product(ntuple(_ -> -1:1, Val(N))...) if any(!=(0), o)]
    len = [_dist2(clat, Float64.(o), ntuple(_ -> 0.0, Val(N))) for o in offs]
    return [CartesianIndex(o) for (o, l) in zip(offs, len) if l <= minimum(len) + 1e-9]
end

# Make every cell one piece under the nearest-neighbour `steps`. Each pass labels the pieces; a piece that is
# not its cell's largest (a stray piece) that touches the largest piece of another cell goes
# to the cell whose largest piece it shares the most bonds with (ties: the lower id), and
# joins it. If no stray piece touches a largest piece, one stray piece goes to the neighbouring
# cell it shares the most bonds with, merging with that cell's piece. Either move lowers the
# number of stray sites or pieces, and never splits a cell, so the loop ends. A stray piece
# with no neighbouring cell (a ball split by the domain) stays. Returns the number of moves.
function _connect_pieces!(owner, sites, index, n, steps)
    m = length(sites)
    piece = zeros(Int, m)
    stack = Int[]
    moves = 0
    while true
        fill!(piece, 0)
        sizes, cellof = Int[], Int[]
        for i in 1:m
            piece[i] == 0 || continue
            push!(sizes, 0); push!(cellof, owner[i])
            p = length(sizes)
            piece[i] = p
            push!(stack, i)
            while !isempty(stack)
                j = pop!(stack)
                sizes[p] += 1
                for o in steps
                    y = sites[j] + o
                    checkbounds(Bool, index, y) || continue
                    k = index[y]
                    (k != 0 && piece[k] == 0 && owner[k] == owner[j]) || continue
                    piece[k] = p
                    push!(stack, k)
                end
            end
        end
        main = zeros(Int, n)
        for p in eachindex(sizes)
            g = cellof[p]
            (main[g] == 0 || sizes[p] > sizes[main[g]]) && (main[g] = p)
        end
        stray(p) = main[cellof[p]] != p
        any(stray, eachindex(sizes)) || return moves
        bonds = Dict{Int, Dict{Int, Int}}()                  # stray piece => cell => bonds
        tomain = Dict{Int, Dict{Int, Int}}()                 # … counting only largest pieces
        for i in 1:m
            p = piece[i]
            stray(p) || continue
            for o in steps
                y = sites[i] + o
                checkbounds(Bool, index, y) || continue
                k = index[y]
                (k != 0 && owner[k] != owner[i]) || continue
                b = get!(Dict{Int, Int}, bonds, p)
                b[owner[k]] = get(b, owner[k], 0) + 1
                if !stray(piece[k])
                    t = get!(Dict{Int, Int}, tomain, p)
                    t[owner[k]] = get(t, owner[k], 0) + 1
                end
            end
        end
        isempty(bonds) && return moves
        pick(b) = argmax(g -> (b[g], -g), collect(keys(b)))
        target = isempty(tomain) ? (p = minimum(keys(bonds)); Dict(p => pick(bonds[p]))) :
                 Dict(p => pick(t) for (p, t) in tomain)
        for i in 1:m
            g = get(target, piece[i], 0)
            g == 0 || (owner[i] = g)
        end
        moves += length(target)
    end
end

function Potts.paint!(op::Potts.LayoutState, l::VoronoiBall, lat)
    clat = Potts.core_lattice(lat)
    dims = size(lat)
    mask = [Potts.indomain(lat, Tuple(x)) for x in CartesianIndices(dims)]
    owner, sites, index, _ = _voronoi_cells(l, clat, all(mask) ? nothing : mask, dims)
    _connect_pieces!(owner, sites, index, l.n, _nearest_steps(clat, Val(length(dims))))
    ids = [Potts.new_cell!(op, l.kinds[mod1(k, length(l.kinds))]) for k in 1:(l.n)]
    for (i, x) in enumerate(sites)
        Potts.assign!(op, x, ids[owner[i]])
    end
    Potts.record!(op; requested = l.n, painted = l.n)
    return nothing
end

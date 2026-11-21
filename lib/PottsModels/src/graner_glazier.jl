"""
    GranerGlazier(; name, lattice = (72, 72), λ = 1.0, V₀ = 40.0, T = 10.0,
        J = [0 16 16; 16 2 11; 16 11 14])

Build the Graner–Glazier cell-sorting model: two cell kinds sort by differential adhesion.

The kinds are `medium`, `dark` and `light`. Each cell has the area energy
`λ (volume − V₀)²`, and each unlike pair of neighbors costs `J[kind, neighbor_kind]`. The
lattice is periodic with Moore contacts, and copies come from the 8 Moore neighbors.

The defaults are the papers' (PRL p. 2015; PRE p. 2139): `J_dd = 2`, `J_dl = 11`,
`J_ll = 14`, `J_cM = 16`, `λ = 1`, `V₀ = 40`, `T = 10`. They satisfy the sorting hierarchy
`J_dd < (J_dd + J_ll)/2 < J_dl < J_ll < J_M` (PRL Eq. 3), and light cells engulf the dark
ones.

Differences from the paper (Glazier & Graner 1993):
- one MCS here is `N` copy attempts, the paper's is `16N`, so paper time `t` is ours `16t`;
- 64 cells ([`graner_glazier_state`](@ref)) against about 1000: bulk topology (⟨n⟩,
  moments) is not measurable, boundary fractions scale with perimeter/area, and sorting
  levels off after about 500 paper MCS instead of continuing to 10⁴. `scale` tiling makes
  more aggregates, not a bigger one. [`graner_glazier_aggregate`](@ref) builds a
  paper-size start;
- a periodic lattice (the paper does not say): fine for sorting, not for runs where cells
  detach and would wrap around;
- the model does not anneal. The paper measures on a copy annealed for 2 paper MCS at
  T = 0 (32 of ours); `lib/PottsModels/test/papers_tests.jl` does the same;
- one `V₀` for both kinds: the paper's cavity run (per-kind targets, non-neighbor copies)
  is not expressible with this model.

# Keywords
- `name::Symbol`: the system name (`@named` passes it).
- `lattice = (72, 72)`: the lattice size (structural).
- `λ = 1.0`: the area strength.
- `V₀ = 40.0`: the target area, in sites.
- `T = 10.0`: the Metropolis temperature.
- `J = [0 16 16; 16 2 11; 16 11 14]`: the contact energies over (medium, dark, light).

# Returns
- `PottsSystem`: the model.

# Examples
```jldoctest
julia> using PottsModels, Potts

julia> GranerGlazier(; name = :sorting, T = 20.0) isa PottsSystem
true
```

# References
- Graner & Glazier, Phys. Rev. Lett. 69, 2013 (1992).
- Glazier & Graner, Phys. Rev. E 47, 2128 (1993).

See also [`graner_glazier_state`](@ref), [`graner_glazier_aggregate`](@ref).
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
        contacts => J[kind, neighbor_kind]
    end
    @sweep Metropolis(; temperature = T)
end

"""
    graner_glazier_state(scale = 1) -> (σ, kinds)

Return the 72×72 initial condition of the Graner–Glazier paper (PRE §II D3), tiled
`scale × scale` times.

The state was made by `data/graner/generate.jl`: a square 51×50 aggregate of 64 staggered
rectangular cells of height 5 and various widths (mean area 40) is relaxed as one type for
400 paper MCS until boundary length and medium fraction are flat, then each cell is dark or
light with probability ½ (33 dark, 31 light). It is read from `data/graner/`.

# Arguments
- `scale::Integer = 1`: the number of copies along each axis. The copies get new cell
  numbers.

# Returns
- `σ::Matrix{Int32}`: the ownership, of size `(72scale, 72scale)`.
- `kinds::Vector{Int32}`: the kind number of each cell (1 dark, 2 light).

Use them as `[ownership => σ, kind => kinds]`.

# Examples
```jldoctest
julia> using PottsModels

julia> σ, kinds = graner_glazier_state();

julia> size(σ), length(kinds)
((72, 72), 64)
```

See also [`GranerGlazier`](@ref), [`graner_glazier_aggregate`](@ref).
"""
function graner_glazier_state(scale::Integer = 1)
    dir = joinpath(@__DIR__, "..", "data", "graner")
    σ1 = Int32.(readdlm(joinpath(dir, "pre_equilibrated_ownership.tsv"), '\t', Int))
    k1 = Int32.(vec(readdlm(joinpath(dir, "cell_kinds.tsv"), '\t', Int)))
    nc = length(k1)
    σ = reduce(
        vcat, [
            reduce(
                hcat, [
                    map(s -> s == 0 ? Int32(0) : s + Int32(nc * (i * scale + j)), σ1)
                        for j in 0:(scale - 1)
                ]
            ) for i in 0:(scale - 1)
        ]
    )
    return σ, repeat(k1, scale^2)
end

"""
    graner_glazier_aggregate(n = 1000; seed = 1, margin = 60) -> (σ, kinds)

Return a paper-size Graner–Glazier initial condition: one round aggregate of `n` cells.

The paper has "about 1000 cells" (PRE 47, p. 2129). The cells have about `V₀ = 40` sites
each, and dark (1) and light (2) cells are randomly mixed in equal numbers (±1; the paper
does not state the fraction). The aggregate is built with the [`Voronoi`](@ref) layout
over a disk of area `40n`: `n` generators drawn by `RandomPoints` in the disk and 30 Lloyd
steps, which gives a centroidal Voronoi tessellation with every cell in one piece. The
kinds are cycled over the random generators. The result is deterministic in `seed`.

A medium margin of `margin` sites surrounds the aggregate on a square lattice of side
`2⌈√(40n/π)⌉ + 1 + 2margin`; use `lattice = size(σ)`. On the periodic `GranerGlazier`
lattice the gap to the aggregate's periodic image is `2margin`. The whole aggregate drifts.
With a margin of 10 sites and `n = 200`, a cell first reaches the lattice edge at
22 800, 30 900 and 29 000 MCS in the three of 17 run seeds that reach it within 40 000 MCS
(`lib/PottsModels/test/acceptance/graner_glazier_margin_tests.jl`). The default of 60 sites
is for long runs, such as the paper run (`n = 1000`, 160 000 MCS). Short runs can pass a
smaller `margin` to save lattice area. The aggregate is rebuilt on the larger lattice, not
embedded, so a different `margin` can move a few boundary sites between cells: compare
margins statistically, not site by site.

The paper relaxes its aggregate as one kind for 400 paper MCS before assigning kinds
(§II D3); no Potts relaxation is run here. The cell areas are more spread than after that
relaxation (SD 7.6 for `n = 1000`, against 1.6 for a Potts-relaxed aggregate), but the
heterotypic boundary fractions from this start and from a relaxed one agree within 0.005
at 1, 10 and 100 paper MCS (6 seeds; measured, see "Paper-size Graner–Glazier start" in
`docs/design/DECISIONS.md`). The area term evens the cells out within the first MCS.

# Arguments
- `n::Integer = 1000`: the number of cells.

# Keywords
- `seed::Integer = 1`: the seed of the generators.
- `margin::Integer = 60`: the medium margin, in sites. Throws an `ArgumentError` when
  negative.

# Returns
- `σ::Matrix{Int32}`: the ownership.
- `kinds::Vector{Int32}`: the kind number of each cell (1 dark, 2 light).

# Examples
```julia
using PottsModels, Potts
σ, kinds = graner_glazier_aggregate(1000; seed = 1)
sys = GranerGlazier(; name = :sorting, lattice = size(σ))
prob = PottsProblem(sys, [ownership => σ, kind => kinds], (0, 1000); seed = 1)
```

See also [`GranerGlazier`](@ref), [`graner_glazier_state`](@ref).
"""
function graner_glazier_aggregate(
        n::Integer = 1000; seed::Integer = 1,
        margin::Integer = 60
    )
    margin >= 0 ||
        throw(ArgumentError("graner_glazier_aggregate: margin must be non-negative, \
            got $margin"))
    radius = sqrt(40n / π)
    L = 2ceil(Int, radius) + 1 + 2margin
    c = (L + 1) / 2                                          # the lattice centre
    ball = Circle(Point(c, c), radius)
    op = layout(
        Voronoi(
            RandomPoints(n; region = ball, seed); region = ball, lloyd = 30,
            kinds = Int32[1, 2]
        ),
        (L, L)
    )
    return op[1].second, op[2].second
end

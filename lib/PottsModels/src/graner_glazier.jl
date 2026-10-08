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
[`Voronoi`](@ref) layout over a disk of area `40n` (`n` generators drawn by `RandomPoints` in
the disk, 30 Lloyd steps: a centroidal Voronoi tessellation, every cell one piece; D-063),
with the kinds cycled over the random generators, so dark and light are mixed at random in
equal numbers (±1). Deterministic in `seed`.

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
    c = (L + 1) / 2                                          # the lattice centre
    ball = Circle(Point(c, c), radius)
    op = layout(Voronoi(RandomPoints(n; region = ball, seed); region = ball, lloyd = 30, kinds = Int32[1, 2]), (L, L))
    return op[1].second, op[2].second
end

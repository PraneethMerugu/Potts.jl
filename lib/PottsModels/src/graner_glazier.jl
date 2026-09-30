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

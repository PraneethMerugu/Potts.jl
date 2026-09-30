"""
    GranerGlazier(; name, lattice = (72, 72), λ, V₀, T, J)

Cell sorting by differential adhesion (Graner & Glazier, Phys. Rev. Lett. 69, 2013, 1992):
two cell kinds with an area constraint and kind-dependent contact energies on a periodic
lattice with Moore contacts. The defaults are the paper's (PRL p. 2015): `J_dd = 2`,
`J_dl = 11`, `J_ll = 14`, `J_cM = 16`, `λ = 1`, `V₀ = 40`, `T = 10`. They satisfy its sorting
hierarchy `J_dd < (J_dd + J_ll)/2 < J_dl < J_ll < J_M` (PRL Eq. 3), and light cells engulf
the dark ones.

Differences from the paper (Glazier & Graner, Phys. Rev. E 47, 2128, 1993):
- one MCS here is `N` copy attempts, the paper's is `16N`, so paper time `t` is ours `16t`;
- 64 cells on a 72² torus (`graner_glazier_state`), against about 1000 in the paper, whose
  statistics are also taken after 2 MCS of T = 0 annealing on a copy.
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

The 72×72 initial condition of PRE §II D3 (D-049 F-2): 64 cells of area 40 relaxed as one
type, then 32 made dark and 32 light at random (`data/graner/generate.jl`), tiled
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

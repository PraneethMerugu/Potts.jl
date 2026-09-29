"""
    GranerGlazier(; name, lattice = (72, 72), λ, V₀, T, J)

Cell sorting by differential adhesion (Graner & Glazier, Phys. Rev. Lett. 69, 2013, 1992):
two cell kinds with an area constraint and kind-dependent contact energies on a periodic
lattice with Moore contacts. The defaults are the legacy `SCDPotts` parameters (dark and
light cells, `J = [0 16 16; 16 2 11; 16 11 14]`, `V₀ = 40`, `T = 10`).
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
    @energy begin
        cells(dark, light) => λ * (volume - V₀)^2
        contacts => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = T)
end

"""
    graner_glazier_state(scale = 1) -> (labels, kinds)

The legacy pre-equilibrated 72×72 initial condition (32 dark and 32 light cells), tiled
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

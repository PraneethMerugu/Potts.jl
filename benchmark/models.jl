# Benchmark models, hand-written against CorePotts (the symbolic layer will generate the same).
using CorePotts, StaticArrays, DelimitedFiles

kindidx(st, c) = c == 0 ? 1 : Int(@inbounds st.cell.kind[c]) + 1
function graner_delta_H(st, p, prop, ctx)
    J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
    E(v, c) = p.λ * (v - p.V0)^2
    return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E)
end
graner_temperature(st, p, prop, ctx) = p.T
const GRANER = CPMFunction(graner_delta_H; temperature = graner_temperature)

"""Graner–Glazier (PRL 69, 2013) parameters: kinds 1 = dark, 2 = light."""
graner_params(T = Float64) = (; J = SMatrix{3, 3, T}(0, 16, 16, 16, 2, 11, 16, 11, 14),
    λ = T(1), V0 = T(40), T = T(10))

"""The pre-equilibrated 72² SCDPotts baseline (64 cells), tiled `scale × scale` times."""
function graner_state(scale = 1)
    dir = joinpath(@__DIR__, "..", "lib", "PottsModels", "data", "graner")
    σ1 = Int32.(readdlm(joinpath(dir, "pre_equilibrated_ownership.tsv"), '\t', Int))
    k1 = Int32.(vec(readdlm(joinpath(dir, "cell_kinds.tsv"), '\t', Int)))
    nc = length(k1)
    σ = reduce(vcat, [reduce(hcat, [map(s -> s == 0 ? Int32(0) : s + Int32(nc * (i * scale + j)), σ1)
        for j in 0:(scale - 1)]) for i in 0:(scale - 1)])
    return σ, repeat(k1, scale^2)
end

function graner_problem(; scale = 1, nmcs = 100, T = Float64, seed = 97329219)
    σ, kinds = graner_state(scale)
    return CPMProblem(GRANER, initial_state(σ, kinds), Lattice(size(σ)), (0, nmcs),
        graner_params(T); contact = Moore(1), seed)
end

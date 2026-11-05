#     julia --project=lib/CorePotts/test -t 4 benchmark/kinetics/gpu_cost.jl <repo>   # ROCm
# Warm wall time per MCS of CheckerboardCPM variants on ROCm (P6.0bl), Graner–Glazier tiles.
using AMDGPU, KernelAbstractions, CorePotts, StaticArrays
# models.jl without DelimitedFiles (not in this environment)
readtsv(f) = permutedims(reduce(hcat, [parse.(Int, split(l, '\t')) for l in eachline(f) if !isempty(l)]))
kindidx(st, c) = c == 0 ? 1 : Int(@inbounds st.cell.kind[c]) + 1
function graner_delta_H(st, p, prop, ctx)
    J(a, b) = @inbounds p.J[kindidx(st, a), kindidx(st, b)]
    E(v, c) = p.λ * (v - p.V0)^2
    return contact_delta(st.σ, ctx, prop, J) + volume_delta(st.cell.volume, prop, E)
end
graner_temperature(st, p, prop, ctx) = p.T
const GRANER = CPMFunction(graner_delta_H; temperature = graner_temperature)
graner_params(T) = (; J = SMatrix{3, 3, T}(0, 16, 16, 16, 2, 11, 16, 11, 14), λ = T(1), V0 = T(40), T = T(10))
function graner_problem(; scale, nmcs, T)
    dir = joinpath(ARGS[1], "lib", "PottsModels", "data", "graner")
    σ1 = Int32.(readtsv(joinpath(dir, "pre_equilibrated_ownership.tsv")))
    k1 = Int32.(vec(readtsv(joinpath(dir, "cell_kinds.tsv"))))
    nc = length(k1)
    σ = reduce(vcat, [reduce(hcat, [map(s -> s == 0 ? Int32(0) : s + Int32(nc * (i * scale + j)), σ1)
        for j in 0:(scale - 1)]) for i in 0:(scale - 1)])
    return PottsProblem(GRANER, initial_state(σ, repeat(k1, scale^2)), Lattice(size(σ)), (0, nmcs),
        graner_params(T); contact = Moore(1))
end
const backend = ROCBackend()
arms = [("default", (;)), ("b1_k6", (; block = 1, parts = 6)), ("b1_k4", (; block = 1, parts = 4)),
    ("b2_k3", (; block = 2, parts = 3))]
for scale in (14, 28)
    for (name, kw) in arms
        prob = graner_problem(; scale, nmcs = 10^6, T = Float32)
        integ = init(prob, CheckerboardCPM(; proposal = Moore(1), kw...); backend, save_start = false)
        for _ in 1:20; step!(integ); end
        KernelAbstractions.synchronize(backend)
        n = 200
        t = @elapsed begin
            for _ in 1:n; step!(integ); end
            KernelAbstractions.synchronize(backend)
        end
        println(rpad("$(72scale)²", 7), rpad(name, 12), " ", round(1e3 * t / n, digits = 3), " ms/MCS  launches/MCS ",
            integ.stats.launches ÷ integ.stats.mcs)
    end
end

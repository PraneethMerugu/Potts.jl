# t = 1 paper MCS fractions against the dark fraction p (estimates the type fraction of the
# published runs from their t = 1 values). Not a verdict run.
using Potts, PottsModels, Random
include_string(Main, join(split(read("diag5.jl", String), "\n")[11:28], "\n"))   # bond_counts, annealed
const PAPER_MCS = 16
alg = SequentialCPM(; proposal = Moore(1))
for p in (0.45, 0.5, 0.55, 0.6)
    acc = Dict(:dd => 0.0, :ll => 0.0, :dl => 0.0)
    for s in 1:4
        σ0, k0 = graner_glazier_aggregate(1000; seed = 20 + s, margin = 10)
        k = copy(k0); perm = randperm(MersenneTwister(s), length(k))
        nd = round(Int, p * length(k)); k[perm[1:nd]] .= 1; k[perm[(nd + 1):end]] .= 2
        q = PottsProblem(GranerGlazier(; name = :f, lattice = size(σ0)), [ownership => σ0, kind => k], (0, PAPER_MCS); seed = s)
        σ = ownership(solve(q, alg; saveat = PAPER_MCS).u[end])
        b = bond_counts(annealed(σ, k), k); N = sum(values(b))
        for key in keys(acc); acc[key] += b[key] / N / 4; end
    end
    println("p = $p: dd $(round(acc[:dd]; digits=3)) ll $(round(acc[:ll]; digits=3)) dl $(round(acc[:dl]; digits=3))")
end

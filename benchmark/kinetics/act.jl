#     julia --project=lib/PottsModels/test -t <threads> benchmark/kinetics/act.jl <runs> [<nmcs> <out>]
# Act (P6.0bl): one Act cell (Niculescu et al. 2015; `WortelAct`, 200² torus, amoeboid
# defaults) at several λ_act, CheckerboardCPM against SequentialCPM. Sultan et al. (arXiv
# 2312.09317, Fig. 5B) found the Act cell's persistence the most sensitive to the
# checkerboard's update order. Observables per run (centroid every MCS, after BURN):
#   speed  mean |x(t + LAG) − x(t)| / LAG
#   pers   mean cosine between consecutive LAG-MCS displacements
#   msd    mean |x(t + 10 LAG) − x(t)|²
# Each run is one task, its checkerboard phases inline (CPU): the device kinetics follow the
# same phase law.
using Potts, PottsModels, Random, Printf
using Potts: CorePotts
using Statistics: mean, std, quantile
const NRUN = parse(Int, ARGS[1])
const NMCS = parse(Int, get(ARGS, 2, "1500"))
const OUT = expanduser(get(ARGS, 3, "~/lpwork/cbk/act-2026-11-05.tsv"))
const BURN, LAG, L = 100, 10, 200
const LAMBDAS = (100.0, 200.0, 300.0)
const ALGS = (("seq", SequentialCPM(; proposal = Moore(1))), ("cb", CheckerboardCPM(; proposal = Moore(1))))
CorePotts.BLOCK_GRAIN[] = typemax(Int)

function problem(λ_act, seed)
    σ = zeros(Int32, L, L)
    σ[89:111, 89:111] .= 1
    return PottsProblem(WortelAct(; name = :a, lattice = (L, L)), [ownership => σ, kind => [:cell], :λ_act => λ_act],
        (0, NMCS); seed)
end

# the centroid on the torus: the circular mean per axis
function centroid(σ)
    s = zeros(2), zeros(2)
    for I in CartesianIndices(σ)
        σ[I] == 1 || continue
        for d in 1:2
            θ = 2π * I[d] / L
            s[1][d] += cos(θ)
            s[2][d] += sin(θ)
        end
    end
    return [mod(atan(s[2][d], s[1][d]), 2π) * L / 2π for d in 1:2]
end
minimage(d) = d - L * round(d / L)

function run(alg, λ_act, seed)
    integ = init(problem(λ_act, seed), alg; save_start = false, save_end = false)
    x = zeros(2, NMCS)
    prev = centroid(Array(integ.state.σ))
    pos = copy(prev)
    for t in 1:NMCS
        step!(integ)
        c = centroid(Array(integ.state.σ))
        pos .+= minimage.(c .- prev)
        prev = c
        x[:, t] = pos
    end
    x = x[:, (BURN + 1):end]
    n = size(x, 2)
    d = [x[:, t + LAG] - x[:, t] for t in 1:LAG:(n - LAG)]
    speed = mean(v -> sqrt(sum(abs2, v)), d) / LAG
    cosines = [sum(d[i] .* d[i + 1]) / sqrt(sum(abs2, d[i]) * sum(abs2, d[i + 1])) for i in 1:(length(d) - 1)
               if sum(abs2, d[i]) > 0 && sum(abs2, d[i + 1]) > 0]
    msd = mean(t -> sum(abs2, x[:, t + 10LAG] - x[:, t]), 1:(n - 10LAG))
    return (speed, mean(cosines), msd)
end

boot(a, b; rng = Xoshiro(3)) = [mean(rand(rng, a, length(a))) / mean(rand(rng, b, length(b))) for _ in 1:4000]
open(OUT, "w") do io
    println(io, "lambda_act\talg\tseed\tspeed\tpers\tmsd")
end
for λ_act in LAMBDAS
    res = Dict{String, Matrix{Float64}}()
    for (name, alg) in ALGS
        R = zeros(NRUN, 3)
        wall = @elapsed Threads.@threads :dynamic for j in 1:NRUN
            R[j, :] .= run(alg, λ_act, 5_000 + j)
        end
        res[name] = R
        open(OUT, "a") do io
            foreach(j -> println(io, join((λ_act, name, 5_000 + j, R[j, :]...), '\t')), 1:NRUN)
        end
        @printf("λ_act %5.0f  %-4s  speed %.4f  pers %.3f  msd %.1f  wall %.0f s\n", λ_act, name,
            mean(R[:, 1]), mean(R[:, 2]), mean(R[:, 3]), wall)
    end
    for (k, obs) in enumerate(("speed", "pers", "msd"))
        a, b = res["cb"][:, k], res["seq"][:, k]
        q = boot(a, b)
        z = (mean(a) - mean(b)) / sqrt(std(a)^2 / length(a) + std(b)^2 / length(b))
        @printf("    %-5s r %.3f [%.3f, %.3f]  z %+.2f\n", obs, mean(a) / mean(b), quantile(q, 0.025), quantile(q, 0.975), z)
    end
end

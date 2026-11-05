#     julia --project=lib/PottsModels/test -t 12 benchmark/kinetics/k3_chain.jl <repo> <runs> [<variants> <out>]
# K3 (P6.0bl): the OpenVT P1b chain relaxation time T (D-218/D-224 protocol, λ = 2) for
# CheckerboardCPM variants on the CPU, against the record's 100 SequentialCPM runs.
include(joinpath(ARGS[1], "lib/PottsModels/reproductions/data/15/checkerboard-2026-10-10/run_checkerboard.jl"))
using Random, Printf
using Statistics: quantile
const VARIANTS = [("default", (;)), ("b1_k8", (; region = 1, parts = 8)), ("b1_k6", (; region = 1, parts = 6)),
    ("b1_k4", (; region = 1, parts = 4))]
const USE = split(get(ARGS, 3, join(first.(VARIANTS), ',')), ',')
const NRUN = parse(Int, ARGS[2])
seqT = [parse(Float64, split(l, '\t')[3]) for l in Iterators.drop(eachline(joinpath(CB_DIR, "calibration_sequential_p1b.tsv")), 1)]
prob = p1b_problem()
saves = 0:(CAL_BURNIN + CAL_TMAX)
boot(a, b; rng = Xoshiro(3)) = [mean(rand(rng, a, length(a))) / mean(rand(rng, b, length(b))) for _ in 1:4000]
out = expanduser(get(ARGS, 4, "~/lpwork/cbk/k3-2026-11-03.tsv"))
open(out, "w") do io
    println(io, "arm\tseed\tT_run")
end
for (name, kw) in filter(v -> first(v) in USE, VARIANTS)
    alg = CheckerboardCPM(; proposal = Moore(1), kw...)
    cache = Base.invokelatest(Potts.init, prob, alg).cache
    ncol = length(cache.order)
    W = fill(NaN, length(saves), NRUN)
    seed(j) = 216_000_000 + 1000 * findfirst(==(name), first.(VARIANTS)) + j
    wall = @elapsed Threads.@threads :dynamic for j in 1:NRUN
        sol = solve(remake(prob; seed = seed(j)), alg; saveat = saves, callback = openvt_release(CAL_BURNIN))
        p1b_walls_intact(sol.u[end]) || error("$name: a border row changed")
        W[:, j] = p1b_width.(sol.u)
    end
    Tc, Truns, _ = p1b_reduce(W)
    open(out, "a") do io
        foreach(j -> println(io, join((name, seed(j), Int(Truns[j])), '\t')), 1:NRUN)
    end
    b = boot(Truns, seqT)
    r, lo, hi = mean(Truns) / mean(seqT), quantile(b, 0.025), quantile(b, 0.975)
    verdict = (lo >= 0.95 && hi <= 1.05) ? "PASS" : (hi < 0.95 || lo > 1.05) ? "FAIL" : "UNDECIDED"
    @printf("%-10s colours %3d  T_run mean %6.1f (seq %.1f)  r %.3f [%.3f, %.3f]  %s  mean-curve T %.1f  wall %.0f s\n",
        name, ncol, mean(Truns), mean(seqT), r, lo, hi, verdict, Tc, wall)
end

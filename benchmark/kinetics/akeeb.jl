#     julia --project=lib/PottsModels/test -t 12 benchmark/kinetics/akeeb.jl <runs> <out> [<points> <arms>]   # ROCm for the checkerboard arms
# Akeeb invasion (P6.0bl): SequentialCPM (CPU) against stock CheckerboardCPM and the matching
# variant (GPU) at three paper points, the page's protocol (500 × 300, 701 MCS, the six
# invasion metrics of `akeeb_observables`, the authors' "MCS 700"), at the same MCS clock.
using Potts, PottsModels, AMDGPU, Random, Printf
using Statistics: mean, std, quantile
const NRUN = parse(Int, ARGS[1])
const OUT = expanduser(ARGS[2])
mkpath(OUT)
const POINTS = (P1 = (2.0, 24.0, 0.5), P4 = (-2.0, 15.0, 0.5), P5 = (5.0, 3.0, 0.5))     # (J_LF, λ, PP), the page's
const METRICS = (:invasive, :infiltrative, :singles, :fingers, :detached, :clusters)
const ARMS = [("seq", SequentialCPM(; proposal = VonNeumann(1)), false),
    ("cb", CheckerboardCPM(; proposal = VonNeumann(1)), true),
    ("cb_s3_r4_rep", CheckerboardCPM(; proposal = VonNeumann(1), stride = 3, retries = 4, colors = :replacement), true)]
problem(pt, seed) = (p = POINTS[pt]; PottsProblem(AkeebInvasion(; name = :akeeb, J = akeeb_contacts(p[1]), μ = p[2]),
    akeeb_state(; pp = p[3], seed = 0x5cd2609 + seed), (0, 701); capacity = 4000, seed))
function run_one(pt, alg, gpu, seed)
    sol = gpu ? solve(problem(pt, seed), alg; backend = ROCBackend(), save_start = false) :
          solve(problem(pt, seed), alg; save_start = false)
    o = akeeb_observables(sol.u[end])
    return Dict(String(m) => Float64(getproperty(o, m)) for m in METRICS)
end
const PTS = Tuple(Symbol.(split(get(ARGS, 3, join(keys(POINTS), ',')), ',')))
const USE = split(get(ARGS, 4, join(first.(ARMS), ',')), ',')
res = Dict{Tuple{Symbol, String}, Vector{Dict{String, Float64}}}()
for pt in PTS, (a, (name, alg, gpu)) in enumerate(ARMS)
    name in USE || continue
    seed(i) = 218_000_000 + 100_000 * a + 1000 * findfirst(==(pt), keys(POINTS)) + i
    run_one(pt, alg, gpu, seed(0))                         # compile
    v = Vector{Dict{String, Float64}}(undef, NRUN)
    wall = @elapsed if gpu
        for i in 1:NRUN
            v[i] = run_one(pt, alg, gpu, seed(i))
        end
    else
        Threads.@threads :dynamic for i in 1:NRUN
            v[i] = run_one(pt, alg, gpu, seed(i))
        end
    end
    res[(pt, name)] = v
    open(joinpath(OUT, "$(pt)_$(name).tsv"), "w") do io
        println(io, join(("seed", METRICS...), '\t'))
        foreach(i -> println(io, join((seed(i), (v[i][String(m)] for m in METRICS)...), '\t')), 1:NRUN)
    end
    @info "akeeb" pt name wall = round(wall; digits = 1)
end
# Welch z and the mean ratio of each arm against sequential, per point and metric
function compare(a, b)
    ma, mb = mean(a), mean(b)
    se = sqrt(var0(a) / length(a) + var0(b) / length(b))
    return ma, mb, se == 0 ? (ma == mb ? 0.0 : Inf) : (ma - mb) / se
end
var0(x) = length(x) > 1 ? std(x)^2 : 0.0
open(joinpath(OUT, "compare.tsv"), "w") do io
    println(io, join(("point", "arm", "metric", "mean_arm", "mean_seq", "ratio", "z"), '\t'))
    for pt in PTS, (name, _, _) in ARMS[2:end], m in METRICS
        haskey(res, (pt, name)) || continue
        a = [d[String(m)] for d in res[(pt, name)]]
        b = [d[String(m)] for d in res[(pt, "seq")]]
        ma, mb, z = compare(a, b)
        println(io, join((pt, name, m, ma, mb, mb == 0 ? NaN : ma / mb, z), '\t'))
        @printf("%s %-14s %-12s arm %9.4g  seq %9.4g  ratio %6.3f  z %6.2f\n", pt, name, m, ma, mb, mb == 0 ? NaN : ma / mb, z)
    end
end

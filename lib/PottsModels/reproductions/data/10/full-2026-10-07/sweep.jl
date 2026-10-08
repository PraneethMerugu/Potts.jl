# The full (J_LF, λ, PP) sweep of Akeeb, Marcus & Jiang (2026): 11 × 11 × 11 points × 10 runs,
# metrics at the authors' MCS 700 (our MCS 701), for V-A6 (phenotype fractions, area-equality
# classifier) and the V-A7 full-sweep |r| (P6.2d, D-156). Same model, start, algorithm and
# capacity as the page's ensembles; seeds 2 000 000 + 100 j + i (j = point, J_LF-major, then
# λ, then PP; i = replicate), disjoint from the page's.
# Usage: OUT=<dir> julia --project=docs -t 12 sweep.jl    (resumable: finished PP levels are kept)
using Potts, PottsModels, Dates, TOML
const OUT = ENV["OUT"]
const DATA = joinpath(OUT, "data", "10")
mkpath(DATA)
const FILE = joinpath(DATA, "sweep.tsv")
const JS, LS, PS = -5.0:1.0:5.0, 0.0:3.0:30.0, [k / 10 for k in 0:10]
const POINTS = [(j, l, p) for j in JS for l in LS for p in PS]
const NREP = 10
seed_of(jp, i) = 2_000_000 + 100jp + i
base = PottsProblem(AkeebInvasion(; name = :akeeb), akeeb_state(; seed = 1), (0, 701); capacity = 4000, seed = 1)
alg = SequentialCPM(; proposal = VonNeumann(1))
run_prob(pt, seed) = remake(base; u0 = akeeb_state(; pp = pt[3], seed), p = [:μ => pt[2], :J => akeeb_contacts(pt[1])],
    seed, tspan = (0, 701))
const M = (:invasive, :infiltrative, :singles, :fingers, :detached, :clusters)
done = Set{Float64}()
if isfile(FILE)
    for l in Iterators.drop(eachline(FILE), 1)
        push!(done, parse(Float64, split(l, '\t')[4]))
    end
else
    open(io -> println(io, join(("point", "J_LF", "lambda", "PP", "replicate", "seed", "retcode", M..., "divisions",
        "phenotype"), '\t')), FILE, "w")
end
started = now()
wall = 0.0
@info "sweep" started Threads.nthreads() length(POINTS) done
solve(run_prob(POINTS[1], 1), alg; saveat = [701])                     # compile
for pp in PS
    pp in done && continue                                              # a PP level is written whole
    jobs = [(jp, i) for (jp, pt) in enumerate(POINTS) if pt[3] == pp for i in 1:NREP]
    out = Vector{String}(undef, length(jobs))
    t = @elapsed Threads.@threads :dynamic for q in eachindex(jobs)
        jp, i = jobs[q]
        pt = POINTS[jp]
        sol = solve(run_prob(pt, seed_of(jp, i)), alg; saveat = [701])
        o = akeeb_observables(sol.u[end])
        out[q] = join((jp, pt..., i, seed_of(jp, i), Symbol(sol.retcode), (getproperty(o, m) for m in M)...,
            sol.stats.lifecycle.divisions, akeeb_phenotype(o)), '\t')
    end
    open(io -> foreach(l -> println(io, l), out), FILE, "a")
    global wall += t
    @info "PP level done" pp runs = length(jobs) wall_s = round(t; digits = 1) now()
end
open(joinpath(DATA, "sweep_provenance.toml"), "w") do io
    git(args...) = readchomp(Cmd(`git $args`; dir = ENV["WT"]))
    TOML.print(io, Dict("commit" => git("rev-parse", "HEAD"),
        "dirty" => !isempty(git("status", "--porcelain", "--untracked-files=no")),
        "script" => "lib/PottsModels/reproductions/data/10/full-2026-10-07/sweep.jl",
        "points" => length(POINTS), "replicates" => NREP, "seeds" => "2000000 + 100j + i",
        "algorithm" => "SequentialCPM(; proposal = VonNeumann(1))", "capacity" => 4000, "saves_our_mcs" => [701],
        "julia" => string(VERSION), "threads" => Threads.nthreads(), "machine" => Sys.MACHINE,
        "hostname" => gethostname(), "cpu" => Sys.cpu_info()[1].model, "affinity" => get(ENV, "POTTS_AFFINITY", ""),
        "started_last_session" => string(started), "wall_s_last_session" => round(wall; digits = 1), "finished" => string(now()), "item" => "P6.2d", "decision" => "D-156"))
end
@info "sweep done" now()

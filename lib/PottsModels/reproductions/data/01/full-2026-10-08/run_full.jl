# P6.3f: reproduction 01 FULL record (D-146, D-153, D-156). Not a frozen file.
#
# Runs every job of the FROZEN FULL tier of lib/PottsModels/test/reproductions/01_merks.jl
# (sha256 cc52d26c…, D-153), with the same functions, seeds, parameters and save times, but
# one replicate per job, resumable: each finished job writes rows/<key>.toml (observables)
# and snap/<key>.jls (σ at every save, UInt16). Rerunning skips finished jobs. When all jobs
# are done, `evaluate.jl` applies the frozen FULL rules to the rows (verdicts.tsv).
#
# The frozen test file is `include`d unchanged with POTTS_FULL_REPRODUCTION unset, so its
# observable checks and SMOKE tier run first (a sanity gate) and its p63d_* helpers are the
# ones used here.
#
# usage: julia -t 12 --project=lib/PottsModels/test <this file> <outdir>
using Potts, PottsModels, Test, TOML, Dates, Serialization
using Statistics: mean

const OUT = abspath(ARGS[1])
const ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", "..", "..", ".."))
const FROZEN = joinpath(ROOT, "lib", "PottsModels", "test", "reproductions", "01_merks.jl")
mkpath(joinpath(OUT, "rows")); mkpath(joinpath(OUT, "snap"))
logmsg(s...) = (println(stdout, "[", now(), "] ", s...); flush(stdout))

haskey(ENV, "POTTS_FULL_REPRODUCTION") && delete!(ENV, "POTTS_FULL_REPRODUCTION")
haskey(ENV, "REPRO") && delete!(ENV, "REPRO")
logmsg("including the frozen test (observable checks + SMOKE) ", FROZEN)
t_smoke = @elapsed include(FROZEN)
logmsg("frozen test SMOKE done in ", round(t_smoke; digits = 1), " s")

# ------------------------------------------------------------------------------------------
# The jobs: exactly the frozen FULL tier's calls (test lines 302–394)
# ------------------------------------------------------------------------------------------
Jm(Jcc) = [0.0 20.0 0.0; 20.0 Jcc 100.0; 0.0 100.0 0.0]
struct Job
    key::String
    row::String
    seed::Int
    meta::Dict{String, Any}
    cost::Float64          # site-MCS, for longest-first scheduling
    run::Function          # () -> Dict{Int, Matrix} or Float64 (walk)
end
jobs = Job[]
S06, S08, S502 = 500^2, 202^2, 502^2
H = [480, 1080, 1440, 2880, 5760]
for s in 1001:1010
    push!(jobs, Job("E1_std_s$s", "V-E1", s, Dict("arm" => "standard"), S06 * 5760, () -> p63d_run06(s, H)))
end
for s in 1101:1110
    push!(jobs, Job("E1_round_s$s", "V-E1", s, Dict("arm" => "λ_L = 0"), S06 * 1440, () -> p63d_run06(s, [1440]; p = [:λ_L => 0.0])))
end
for (k, L) in enumerate((10.0, 20.0, 30.0, 40.0, 50.0)), i in 1:10
    s = 1200 + 10(k - 1) + i
    push!(jobs, Job("E5_L$(Int(L))_s$s", "V-E5", s, Dict("L" => L), S06 * 5760, () -> p63d_run06(s, [5760]; p = [:L => L])))
end
for (k, Jcc) in enumerate((20.0, 5.0, 1.0)), i in 1:10
    s = 1300 + 10(k - 1) + i
    push!(jobs, Job("E6_J$(Int(Jcc))_s$s", "V-E6", s, Dict("J_cc" => Jcc), S06 * 5760, () -> p63d_run06(s, [5760]; p = [:J => Jm(Jcc)])))
end
for s in 1401:1410
    push!(jobs, Job("E10_el_s$s", "V-E10", s, Dict("arm" => "elongated"), 160^2 * 2000, () -> p63d_walk(s)))
end
for s in 1411:1420
    push!(jobs, Job("E10_ro_s$s", "V-E10", s, Dict("arm" => "round"), 160^2 * 2000, () -> p63d_walk(s; p = [:L => 10.0, :λ_L => 50.0])))
end
for (j, r) in enumerate(0.0:0.1:1.0), i in 1:10
    s = 3000 + 100j + i
    push!(jobs, Job("C3_r$(j - 1)_s$s", "V-C3", s, Dict("ratio" => r), S08 * 10_100,
        () -> p63d_run08(s, [10_000, 10_100]; p = [:χcc => 500.0 * r])))
end
pts4 = [(0.0, true), (20.0, true), (40.0, true), (60.0, true), (80.0, true),
    (0.0, false), (5.0, false), (10.0, false), (15.0, false), (20.0, false), (40.0, false)]
for (k, (J, ci)) in enumerate(pts4), i in 1:10
    s = 4000 + 100k + i
    push!(jobs, Job("C4_k$(k)_s$s", "V-C4", s, Dict("J_cc" => J, "CI" => ci), S08 * 5100,
        () -> p63d_run08(s, [5000, 5100]; p = [:J => Jm(J); ci ? Pair[] : [:χcc => 500.0]])))
end
pts5 = [((0.0, true), 0.9), ((500.0, true), 0.35), ((5000.0, true), 0.2), ((0.0, false), 0.95), ((5000.0, false), 0.7)]
for (k, ((χ, ci), want)) in enumerate(pts5), i in 1:10
    s = 5000 + 100k + i
    push!(jobs, Job("C5_k$(k)_s$s", "V-C5", s, Dict("χcM" => χ, "CI" => ci, "paper" => want), S08 * 5100,
        () -> p63d_run08(s, [5000, 5100]; p = [:χcM => χ; ci ? Pair[] : [:χcc => χ]])))
end
ss = [0.0, 0.025, 0.05, 0.075, 0.1, 0.125, 0.15, 0.175, 0.2, 0.25]
for (k, sv) in enumerate(ss), i in 1:10
    s = 7000 + 100k + i
    push!(jobs, Job("C7_k$(k)_s$s", "V-C7", s, Dict("s" => sv, "CI" => true), S08 * 5100,
        () -> p63d_run08(s, [5000, 5100]; p = [:s => sv])))
end
for (k, sv) in enumerate((0.0, 0.1, 0.25)), i in 1:10
    s = 7500 + 100k + i
    push!(jobs, Job("C7n_k$(k)_s$s", "V-C7", s, Dict("s" => sv, "CI" => false), S08 * 5100,
        () -> p63d_run08(s, [5000, 5100]; p = [:s => sv, :χcc => 500.0])))
end
for (k, (T, mode)) in enumerate(((50.0, :extension_only), (50.0, :extension_retraction),
                                  (800.0, :extension_only), (800.0, :extension_retraction))), i in 1:10
    s = 9000 + 100k + i
    push!(jobs, Job("C9_k$(k)_s$s", "V-C9", s, Dict("T" => T, "mode" => string(mode)), S08 * 5100,
        () -> p63d_run08(s, [5000, 5100]; p = [:T => T], mode)))
end
for i in 1:10
    s = 12_000 + i
    push!(jobs, Job("C12_ci_s$s", "V-C12", s, Dict("CI" => true), S08 * 19_300, () -> p63d_run08(s, [100, 19_300]; p = Pair[])))
    s2 = 12_100 + i
    push!(jobs, Job("C12_no_s$s2", "V-C12", s2, Dict("CI" => false), S08 * 19_300, () -> p63d_run08(s2, [100, 19_300]; p = [:χcc => 500.0])))
end
for i in 1:5
    s = 20_000 + i
    push!(jobs, Job("C1_ci_s$s", "V-C1", s, Dict("CI" => true), S502 * 10_100, () -> p63d_run08(s, [10_000, 10_100]; denovo = true)))
    s2 = 20_100 + i
    push!(jobs, Job("C1_no_s$s2", "V-C1", s2, Dict("CI" => false), S502 * 10_100,
        () -> p63d_run08(s2, [10_000, 10_100]; denovo = true, p = [:χcc => 500.0])))
end
@assert allunique(j.key for j in jobs)
@assert length(jobs) == 20 + 50 + 30 + 20 + 110 + 110 + 50 + 100 + 30 + 40 + 20 + 10

# ------------------------------------------------------------------------------------------
# Per-job observables (the frozen p63d_* functions) and atomic writes
# ------------------------------------------------------------------------------------------
function observe(job, res, wall)
    d = Dict{String, Any}("key" => job.key, "row" => job.row, "seed" => job.seed, "wall_s" => round(wall; digits = 2),
        "thread" => Threads.threadid(), "finished" => string(now()))
    merge!(d, job.meta)
    if res isa Real                                   # V-E10 walk: par / perp
        d["anisotropy"] = Float64(res)
    else
        for (t, σ) in sort(collect(res))
            nw = p63d_network(σ)
            d["C_$t"] = p63d_compactness(σ)
            d["share_$t"] = nw.share
            d["lacunae_$t"] = nw.lacunae
            d["network_$t"] = p63d_isnetwork(nw)
        end
        if job.row == "V-C12"
            d["displacement_sites"] = p63d_displacement(res[100], res[19_300])
        end
    end
    return d
end
function atomic(f, path)
    tmp = path * ".tmp"
    open(f, tmp, "w")
    mv(tmp, path; force = true)
end
rowpath(j) = joinpath(OUT, "rows", j.key * ".toml")
todo = sort(filter(j -> !isfile(rowpath(j)), jobs); by = j -> -j.cost)
logmsg("jobs: ", length(jobs), " total, ", length(jobs) - length(todo), " done, ", length(todo), " to run on ",
    Threads.nthreads(), " threads; remaining work ", round(sum(j -> j.cost, todo; init = 0.0) / 1e9; digits = 2), " G site-MCS")

ch = Channel{Job}(length(todo))
foreach(j -> put!(ch, j), todo); close(ch)
failures = Threads.Atomic{Int}(0)
@sync for w in 1:Threads.nthreads()
    Threads.@spawn for job in ch
        try
            logmsg("start ", job.key)
            wall = @elapsed res = job.run()
            if !(res isa Real)
                atomic(joinpath(OUT, "snap", job.key * ".jls")) do io
                    serialize(io, Dict(t => UInt16.(σ) for (t, σ) in res))
                end
            end
            d = observe(job, res, wall)
            atomic(io -> TOML.print(io, d), rowpath(job))
            logmsg("done ", job.key, " in ", round(wall; digits = 1), " s")
        catch e
            Threads.atomic_add!(failures, 1)
            logmsg("FAILED ", job.key, ": ", sprint(showerror, e, catch_backtrace()))
        end
    end
end
logmsg("ALL JOBS FINISHED; failures = ", failures[])

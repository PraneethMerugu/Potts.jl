# P6.4r κ_b: reproduction 04 (foam) bulk-scale scan runner (D-203, D-205). Not a frozen file.
#
# Runs exactly the jobs of the FROZEN SCAN tier of
# lib/PottsModels/test/reproductions/04_foam_kb_scan.jl (`p64kb_scan`): the 5 ordered foams
# (`p64r_foam(:ordered, k)`), τ = 1/mean(ū) over them, then 23 κ_b × 5 β × 3 replicates =
# 345 runs of the frozen `p64kb_run(foam k, κ_b·β, P64KB_CAP[β], p64kb_seed(j, k), τ)`,
# longest cap first. Unlike the frozen tier it is resumable: each finished job is written to
# <out>/jobs/<key>.jls and a rerun skips it.
#
# Output in <out>: scan.tsv (frozen `p64kb_write`, the layout the record tier reads),
# decision.toml (the frozen format the record tier compares) and provenance.toml (no host
# name or paths, D-195). The frozen decision `p64kb_analyse` is applied and its κ_b (or
# `nothing`) printed. Copy scan.tsv, decision.toml and provenance.toml to
# lib/PottsModels/reproductions/data/04/kb-scan-<date>/ (exactly one may exist).
#
# The frozen test is `include`d unchanged (with P64KB_SCAN, P64KB_OUT, POTTS_FULL_REPRODUCTION
# and REPRO unset), so its oracles, decision-rule tests and SMOKE run first as a gate (it also
# includes 04_foam.jl and runs its SMOKE and record tiers; a few minutes on the Mac).
#
# Usage, from the checkout root (<out> must be outside reproductions/data/04):
#
#   julia --project=lib/PottsModels/test lib/PottsModels/reproductions/data/04/run_kb_scan.jl \
#       --out <dir> [--threads N] [--dry-run] [--tiny N]
#
# `--threads N` re-launches Julia with N threads. Jobs run one per thread. `--dry-run` lists
# the jobs and the cost and runs nothing but the gate. `--tiny N` (a harness check, not a
# result) runs the first N jobs of the schedule with the cap cut to 30 paper MCS into
# <out>/jobs-tiny/ and writes no scan.tsv.
using Potts, PottsModels, Test, TOML, Dates, Serialization, SHA
using Statistics: mean, median

# ------------------------------------------------------------------------------------------
# Arguments
# ------------------------------------------------------------------------------------------
const USAGE = "usage: --out <dir> [--threads N] [--dry-run] [--tiny N]"
function parse_args(args)
    o = Dict{String, Any}("out" => "", "threads" => 0, "dry" => false, "tiny" => 0)
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--dry-run"
            o["dry"] = true
        elseif a in ("--out", "--threads", "--tiny") && i < length(args)
            o[a[3:end]] = a == "--out" ? args[i + 1] : parse(Int, args[i + 1])
            i += 1
        elseif startswith(a, "--out=")
            o["out"] = String(a[7:end])
        elseif startswith(a, "--threads=") || startswith(a, "--tiny=")
            k, v = split(a[3:end], '='; limit = 2)
            o[k] = parse(Int, v)
        else
            error("run_kb_scan.jl: unknown argument $a ($USAGE)")
        end
        i += 1
    end
    isempty(o["out"]) && error("run_kb_scan.jl: --out <dir> is required ($USAGE)")
    return o
end
const OPT = parse_args(ARGS)

function without_threads(args)
    rest = String[]
    skip = false
    for a in args
        skip && (skip = false; continue)
        a == "--threads" && (skip = true; continue)
        startswith(a, "--threads=") && continue
        push!(rest, a)
    end
    return rest
end
if OPT["threads"] > 0 && OPT["threads"] != Threads.nthreads()
    rest = without_threads(ARGS)
    cmd = `$(Base.julia_cmd()) --threads=$(OPT["threads"]) --project=$(Base.active_project()) $(abspath(PROGRAM_FILE)) $rest`
    exit(success(run(ignorestatus(cmd))) ? 0 : 1)
end

const OUT = abspath(OPT["out"])
const ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", "..", ".."))
const DATA04 = joinpath(ROOT, "lib", "PottsModels", "reproductions", "data", "04")
const FROZEN = joinpath(ROOT, "lib", "PottsModels", "test", "reproductions", "04_foam_kb_scan.jl")
const FROZEN_D190 = joinpath(ROOT, "lib", "PottsModels", "test", "reproductions", "04_foam.jl")
(OUT == DATA04 || startswith(OUT, DATA04 * "/")) &&
    error("run_kb_scan.jl: --out must be outside reproductions/data/04 (the frozen record tiers read it)")
const TINY = OPT["tiny"] > 0
const JOBS = joinpath(OUT, TINY ? "jobs-tiny" : "jobs")
const TINY_CAP = 30                                  # paper MCS, --tiny only
mkpath(JOBS)
logmsg(s...) = (println(stdout, "[", now(), "] ", s...); flush(stdout))

# ------------------------------------------------------------------------------------------
# The frozen test: definitions, oracles, decision-rule tests and SMOKE (the gate)
# ------------------------------------------------------------------------------------------
for k in ("P64KB_SCAN", "P64KB_OUT", "POTTS_FULL_REPRODUCTION", "REPRO", "P64R_RECORD_OUT")
    haskey(ENV, k) && delete!(ENV, k)
end
logmsg("including the frozen test (oracles + SMOKE) ", relpath(FROZEN, ROOT), " with ", Threads.nthreads(), " threads")
const GATE = Test.DefaultTestSet("04 κ_b frozen test (SMOKE gate)")
Test.push_testset(GATE)
t_smoke = try
    @elapsed include(FROZEN)
finally
    Test.pop_testset()
end
let bad = String[]
    for ts in GATE.results
        ts isa Test.DefaultTestSet || (push!(bad, "a result outside any testset: $ts"); continue)
        c = Test.get_test_counts(ts)
        nonpass = c.fails + c.errors + c.cumulative_fails + c.cumulative_errors
        nonpass == 0 || push!(bad, "$(ts.description): $nonpass failed or errored")
    end
    isempty(bad) || error("κ_b runner: the frozen test's gate failed:\n  " * join(bad, "\n  "))
end
P64R_SHEAR_READY || error("κ_b runner: the shear model is not on this tree")
logmsg("frozen test gate passed in ", round(t_smoke; digits = 1), " s")

# ------------------------------------------------------------------------------------------
# Jobs: exactly the calls of the frozen `p64kb_scan`
# ------------------------------------------------------------------------------------------
struct Job
    key::String
    cost::Float64          # our MCS at the cap (worst case; longest first)
    run::Function
end
jobpath(key) = joinpath(JOBS, key * ".jls")
done(key) = isfile(jobpath(key))
function save(key, x)
    tmp = jobpath(key) * ".tmp-$(Threads.threadid())"
    serialize(tmp, x)
    mv(tmp, jobpath(key); force = true)
end
load(key) = deserialize(jobpath(key))

function run_pool(jobs, stage)
    todo = sort(filter(j -> !done(j.key), jobs); by = j -> -j.cost)
    logmsg(stage, ": ", length(jobs), " jobs, ", length(jobs) - length(todo), " already done, ", length(todo), " to run")
    isempty(todo) && return String[]
    ch = Channel{Job}(length(todo))
    foreach(j -> put!(ch, j), todo)
    close(ch)
    failed = String[]
    lk = ReentrantLock()
    n = Threads.Atomic{Int}(0)
    t0 = time()
    @sync for _ in 1:Threads.nthreads()
        Threads.@spawn for j in ch
            try
                tj = @elapsed res = j.run()
                save(j.key, res)
                k = Threads.atomic_add!(n, 1) + 1
                logmsg(stage, " ", k, "/", length(todo), " ", j.key, " ", round(tj; digits = 1), " s (",
                    round((time() - t0) / 3600; digits = 2), " h elapsed)")
            catch e
                lock(lk) do
                    push!(failed, j.key)
                end
                logmsg(stage, " FAILED ", j.key, ": ", sprint(showerror, e))
            end
        end
    end
    return failed
end

# (κ_b index i, κ_b, β index j, β, replicate k), as `p64kb_scan`'s job list
const SCAN = [(i, κ, j, β, k) for (i, κ) in enumerate(P64KB_GRID) for (j, β) in enumerate(P64KB_BETAS) for k in 1:P64KB_N]
@assert length(SCAN) == 345 == length(P64KB_GRID) * length(P64KB_BETAS) * P64KB_N
foamkey(k) = "foam_ordered_$(k)"
runkey(i, j, k) = "kb_$(lpad(i, 2, '0'))_$(j)_$(k)"           # i = grid index 1..23 (κ_b = κ_D190·2^((i−9)/2))
cap(β) = TINY ? TINY_CAP : P64KB_CAP[β]

let τ = 3.447, ms = 6.2e-3                                    # D-190 FULL: τ, ms per our MCS per thread
    worst = sum(p64r_ours(P64KB_CAP[β], τ) for (_, _, _, β, _) in SCAN)
    longest = maximum(p64r_ours(c, τ) for c in values(P64KB_CAP))
    nt = Threads.nthreads()
    logmsg("jobs: ", P64KB_TAU_FOAMS, " ordered foams, then ", length(SCAN), " runs (", length(P64KB_GRID), " κ_b × ",
        length(P64KB_BETAS), " β × ", P64KB_N, " replicates); worst case (all to the cap) ",
        round(worst / 1e6; digits = 1), "e6 of our MCS at τ ≈ ", τ, " ≈ ", round(worst * ms / 3600; digits = 1),
        " thread-h ≈ ", round(worst * ms / 3600 / nt; digits = 1), " h on ", nt, " threads (the header's ≈ 2 h expected ",
        "on 24 with early stops); longest job ", longest, " our MCS ≈ ", round(Int, longest * ms / 60), " min")
end
if OPT["dry"]
    for (i, κ, j, β, k) in sort(SCAN; by = x -> -P64KB_CAP[x[4]])
        println("  ", runkey(i, j, k), "\tκ_b = ", round(κ; sigdigits = 5), "\tβ = ", β, "\tβ_model = ",
            round(κ * β; sigdigits = 5), "\tk = ", k, "\tseed = ", p64kb_seed(j, k), "\tcap = ", P64KB_CAP[β])
    end
    logmsg("dry run: nothing run")
    exit(0)
end

# ------------------------------------------------------------------------------------------
# Stage 1: the 5 ordered foams, τ
# ------------------------------------------------------------------------------------------
const T_START = now()
p64r_template(false, P64R_L)
p64r_template(true, P64R_L)
failed = run_pool([Job(foamkey(k), 1_010.0, () -> p64r_foam(:ordered, k)) for k in 1:P64KB_TAU_FOAMS], "foams")
isempty(failed) || error("κ_b runner: foam jobs failed: $failed (rerun to resume)")
const FOAMS = [load(foamkey(k)) for k in 1:P64KB_TAU_FOAMS]
const τ = 1 / mean(row["ubar"] for (_, row) in FOAMS)
logmsg("τ = ", τ, " (foam seeds ", [r["seed"] for (_, r) in FOAMS], ")")

# ------------------------------------------------------------------------------------------
# Stage 2: the scan runs, longest cap first
# ------------------------------------------------------------------------------------------
JS = [Job(runkey(i, j, k), p64r_ours(cap(β), τ), () -> begin
          r = p64kb_run(FOAMS[k][1], κ * β, cap(β), p64kb_seed(j, k), τ)
          Dict{String, Any}("kappa_b" => κ, "beta" => β, "beta_model" => κ * β, "k" => k, "seed" => p64kb_seed(j, k),
              "tau" => τ, "cap" => cap(β), "mcs_run" => r.mcs_run, "t_first" => r.t_first, "t1_total" => r.t1_total)
      end) for (i, κ, j, β, k) in SCAN]
if TINY
    JS = sort(JS; by = j -> -P64KB_CAP[P64KB_BETAS[parse(Int, split(j.key, '_')[3])]])[1:min(OPT["tiny"], end)]
end
failed = run_pool(JS, TINY ? "tiny runs (cap $TINY_CAP)" : "runs")
isempty(failed) || error("κ_b runner: $(length(failed)) run jobs failed: $failed (rerun to resume)")
rows = Dict{String, Any}[load(j.key) for j in JS]
sort!(rows; by = r -> (r["kappa_b"], r["beta"], r["k"]))

if TINY
    for r in rows
        logmsg("tiny ", join(("$c = $(r[c])" for (c, _) in P64KB_COLS), ", "))
    end
    logmsg("--tiny: harness check only; no scan.tsv written")
    exit(0)
end

# ------------------------------------------------------------------------------------------
# The record: scan.tsv, decision.toml (frozen formats), provenance.toml; the decision
# ------------------------------------------------------------------------------------------
@assert length(rows) == 345
A = p64kb_analyse(rows)
p64kb_write(OUT, rows)
@assert p64kb_read(joinpath(OUT, "scan.tsv")) == rows
open(joinpath(OUT, "decision.toml"), "w") do io                 # as the frozen SCAN tier writes it
    println(io, "kappa_b = $(A.kappa_b === nothing ? "\"nothing\"" : A.kappa_b)")
    println(io, "path = \"$(A.path)\"\nreason = \"$(A.reason)\"\nkhat = $(repr(A.khat))")
end
git(args...) = try
    readchomp(Cmd(`git $args`; dir = ROOT))
catch
    "unknown"
end
open(joinpath(OUT, "provenance.toml"), "w") do io
    TOML.print(io, Dict(
        "item" => "P6.4r κ_b", "decision" => "D-203", "protocol" => "D-205",
        "commit" => git("rev-parse", "HEAD"), "commit_date" => git("log", "-1", "--format=%cs"),
        "dirty" => !isempty(git("status", "--porcelain", "--untracked-files=no")),
        "frozen_test" => "lib/PottsModels/test/reproductions/04_foam_kb_scan.jl",
        "frozen_sha256" => bytes2hex(open(sha256, FROZEN)),
        "frozen_d190_sha256" => bytes2hex(open(sha256, FROZEN_D190)),
        "runner" => "lib/PottsModels/reproductions/data/04/run_kb_scan.jl",
        "julia" => string(VERSION), "threads" => Threads.nthreads(),
        "machine" => "$(strip(Sys.cpu_info()[1].model)) ($(Sys.MACHINE)), CPU, $(Sys.CPU_THREADS) hardware threads",
        "started" => string(T_START), "finished" => string(now()),
        "wall_s_this_launch" => round((now() - T_START).value / 1000; digits = 1),
        "seeds" => Dict("foam" => "p64r_prep_seed(:ordered, k, try) (D-190)",
            "run" => "p64kb_seed(j, k) = p64r_run_seed(13, j, k) = 5_000_000 + 1_000_000·13 + 10j + k",
            "foam_seeds" => [r["seed"] for (_, r) in FOAMS]),
        "jobs" => Dict("foams" => P64KB_TAU_FOAMS, "runs" => length(rows)),
        "tau" => τ, "kappa_d190" => P64KB_KAPPA_D190,
        "algorithm" => "BoundarySiteCPM(), proposals NeighborOrder(4) (DV1)",
        "result" => Dict("kappa_b" => A.kappa_b === nothing ? "nothing" : A.kappa_b, "path" => string(A.path),
            "reason" => string(A.reason), "khat" => A.khat, "P" => A.P)))
end
for (β, m190) in P64KB_D190_MED
    logmsg("harness control at κ_D190, β = ", β, ": median t_first ", A.med[9, findfirst(≈(β), P64KB_BETAS)],
        " (D-190 record ", m190, ", ±25 %)")
end
logmsg("record written to ", OUT, " (copy scan.tsv, decision.toml, provenance.toml to reproductions/data/04/kb-scan-<date>/)")
logmsg("D-203 decision: path = ", A.path, ", reason = ", A.reason, ", khat = ", A.khat, ", P = ", A.P)
println("κ_b = ", A.kappa_b === nothing ? "nothing" : A.kappa_b)

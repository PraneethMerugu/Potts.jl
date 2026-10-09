# P6.4r: reproduction 04 (foam, Jiang et al. 1999) FULL record runner (D-146, D-190). Not a
# frozen file.
#
# Runs every job of the FROZEN FULL tier of lib/PottsModels/test/reproductions/04_foam.jl
# (`p64r_full`, D-190) with the same functions, seeds, parameters and job list, but
# resumable and load-balanced: each finished job is written to <out>/jobs/<key>.jls, and a
# rerun skips the finished ones. The stages are the frozen ones, in order:
#
#   1. foams (40: ordered 1–10, five each of d081 d095 d107 d165 d172 d202), then τ (A-5);
#   2. the κ calibration loops (165, J = 3), then κ (A-1); κ undefined stops the run;
#   3. every other run (530 loops, 15 steady, 200 bulk), longest first.
#
# The record is assembled exactly as `p64r_full` assembles it, written with the frozen
# `p64r_write`, and judged with the frozen `p64r_verdicts` into verdicts.tsv in the frozen
# format; provenance.toml is added. The record goes to <out>/record/; copy it to
# lib/PottsModels/reproductions/data/04/full-<date>/ (exactly one full-* directory may
# exist there), add deviations.tsv for every FAIL row (D-154), and the record tier of the
# frozen test re-derives every row from it.
#
# The frozen test file is `include`d unchanged with POTTS_FULL_REPRODUCTION and REPRO unset,
# so its oracles and SMOKE tier run first, as a sanity gate (about a minute). The only
# failure tolerated there is the record tier's own, which fails by design while no record
# exists.
#
# Usage, from the checkout root (keep <out> outside reproductions/data/04 while running):
#
#   julia --project=lib/PottsModels/test lib/PottsModels/reproductions/data/04/run_full.jl \
#       --out <dir> [--threads N] [--stage foams|cal|all] [--dry-run]
#
# `--threads N` re-launches Julia with N threads (or pass `julia -t N` yourself). Jobs run
# one per thread; a job is single-threaded. `--dry-run` lists the jobs and the cost estimate
# and runs nothing (it still runs the SMOKE gate).
using Potts, PottsModels, Test, TOML, Dates, Serialization, SHA
using Statistics: mean, median, std

# ------------------------------------------------------------------------------------------
# Arguments
# ------------------------------------------------------------------------------------------
function parse_args(args)
    o = Dict{String, Any}("out" => "", "threads" => 0, "stage" => "all", "dry" => false)
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--dry-run"
            o["dry"] = true
        elseif a in ("--out", "--threads", "--stage") && i < length(args)
            o[a[3:end]] = a == "--threads" ? parse(Int, args[i + 1]) : args[i + 1]
            i += 1
        elseif startswith(a, "--threads=")
            o["threads"] = parse(Int, split(a, '=')[2])
        elseif startswith(a, "--out=") || startswith(a, "--stage=")
            k, v = split(a[3:end], '='; limit = 2)
            o[k] = String(v)
        else
            error("run_full.jl: unknown argument $a (usage: --out <dir> [--threads N] [--stage foams|cal|all] [--dry-run])")
        end
        i += 1
    end
    isempty(o["out"]) && error("run_full.jl: --out <dir> is required")
    o["stage"] in ("foams", "cal", "all") || error("run_full.jl: --stage must be foams, cal or all")
    return o
end
const OPT = parse_args(ARGS)

# --threads N: re-launch with N threads (same project, same arguments otherwise)
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
const JOBS = joinpath(OUT, "jobs")
const ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", "..", ".."))
const FROZEN = joinpath(ROOT, "lib", "PottsModels", "test", "reproductions", "04_foam.jl")
mkpath(JOBS)
logmsg(s...) = (println(stdout, "[", now(), "] ", s...); flush(stdout))
startswith(OUT, joinpath(ROOT, "lib", "PottsModels", "reproductions", "data", "04", "full-")) &&
    error("run_full.jl: write to a directory outside reproductions/data/04/full-* (the frozen record tier reads those)")

# ------------------------------------------------------------------------------------------
# The frozen test: definitions, oracles and SMOKE (the sanity gate)
# ------------------------------------------------------------------------------------------
haskey(ENV, "POTTS_FULL_REPRODUCTION") && delete!(ENV, "POTTS_FULL_REPRODUCTION")
haskey(ENV, "REPRO") && delete!(ENV, "REPRO")
haskey(ENV, "P64R_RECORD_OUT") && delete!(ENV, "P64R_RECORD_OUT")
logmsg("including the frozen test (oracles + SMOKE) ", FROZEN, " with ", Threads.nthreads(), " threads")
const GATE = Test.DefaultTestSet("04 frozen test (SMOKE gate)")
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
        nonpass == 0 && continue
        startswith(ts.description, "04 FULL record") && nonpass == 1 && continue   # no record yet: fails by design
        push!(bad, "$(ts.description): $nonpass failed or errored")
    end
    isempty(bad) || error("04 runner: the frozen test's SMOKE gate failed:\n  " * join(bad, "\n  "))
end
P64R_SHEAR_READY || error("04 runner: P6.4a1 (`direction`) is not on this tree; FULL needs the shear model")
logmsg("frozen test SMOKE gate passed in ", round(t_smoke; digits = 1), " s")

# ------------------------------------------------------------------------------------------
# Jobs: exactly the calls of the frozen `p64r_full`
# ------------------------------------------------------------------------------------------
struct Job
    key::String
    cost::Float64          # our MCS (estimate, for longest-first scheduling)
    run::Function          # () -> result, as `p64r_full`'s closure returns it
end
jobpath(key) = joinpath(JOBS, key * ".jls")
done(key) = isfile(jobpath(key))
function save(key, x)
    tmp = jobpath(key) * ".tmp-$(Threads.threadid())"
    serialize(tmp, x)
    mv(tmp, jobpath(key); force = true)
end
load(key) = deserialize(jobpath(key))

"""Run `jobs` on a pool of Threads.nthreads() tasks, longest first; finished ones are skipped."""
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

tag!(d; kw...) = (for (k, v) in kw
    d[string(k)] = v
end; d)
τ_GUESS = 1 / p64r_ubar(p64r_brick(P64R_L))          # for cost estimates before the foams exist

foam_jobs = [[(:ordered, k) for k in 1:10]; [(f, k) for f in keys(P64R_FOAMS) if f !== :ordered for k in 1:P64R_REPS]]
foamkey(f, k) = "foam_$(f)_$(k)"
J1 = [Job(foamkey(f, k), f === :ordered ? 1_010.0 : 3_000.0, () -> p64r_foam(f, k)) for (f, k) in foam_jobs]
cal_jobs = [(i, r, k) for (i, r) in enumerate(P64R_CAL_R) for k in 1:P64R_REPS]
loop_jobs = [[("scan", J, J * r, P64R_T0, 100j + i) for (j, J) in enumerate(P64R_SCAN_J) for (i, r) in enumerate(P64R_SCAN_R)];
             [("v3", 3.0, gp, P64R_T0, i) for (i, gp) in enumerate((1.0, 3.5, 7.0))];
             [("v4", J, 7.0, P64R_T0, i) for (i, J) in enumerate((1.0, 5.0, 10.0))];
             [("v6", 3.0, 4.0, T, i) for (i, T) in enumerate(P64R_V6_T)]]
loop_jobs = [(j..., k) for j in loop_jobs for k in 1:P64R_REPS]
steady_jobs = [[("v2", :ordered, P64R_TV2)]; [("v9", :d165, P64R_TV9)]; [("v9c", :ordered, P64R_TV9)]]
steady_jobs = [(j..., k) for j in steady_jobs for k in 1:P64R_REPS]
bulk_jobs = [[("spec", f, β, P64R_TSPEC) for f in (:ordered, :d081, :d165) for β in P64R_BETAS];
             [("v14", f, β, P64R_T14) for f in (:d165, :d172, :d107, :d095) for β in P64R_BETAS14];
             [("v16", f, 0.01, P64R_T16) for f in (:d081, :d165, :d172, :d202)]; [("v16c", :d165, 0.0, P64R_T16)]]
bulk_jobs = [(j..., i, k) for (i, j) in enumerate(bulk_jobs) for k in 1:P64R_REPS]
@assert length(J1) == 40 && length(cal_jobs) == 165 && length(loop_jobs) == 530 && length(steady_jobs) == 15 &&
        length(bulk_jobs) == 200
calkey(i, k) = "cal_$(i)_$(k)"
loopkey(set, i, k) = "loop_$(set)_$(i)_$(k)"
steadykey(set, k) = "steady_$(set)_$(k)"
bulkkey(set, i, k) = "bulk_$(set)_$(i)_$(k)"
lowsize(f) = prod(P64R_FOAMS[f].L) / prod(P64R_L)                     # 320² foams cost 1.56×
cyc(τ) = P64R_CYCLES * p64r_ours(P64R_PERIOD, τ)

let τ = τ_GUESS
    ours = length(J1) * 2000 + (length(cal_jobs) + length(loop_jobs)) * cyc(τ) +
           sum(p64r_ours(T, τ) * lowsize(f) for (_, f, T, _) in steady_jobs) +
           sum(p64r_ours(T, τ) * lowsize(f) for (_, f, _, T, _, _) in bulk_jobs)
    logmsg("jobs: 40 foams, 165 calibration loops, 530 loops, 15 steady, 200 bulk; ≈ ",
        round(ours / 1e6; digits = 1), "e6 of our MCS at τ ≈ ", round(τ; digits = 2), " (the brick wall's; the record's τ is ",
        "measured on the relaxed foams); at 4 ms/MCS ≈ ", round(Int, ours * 4e-3 / 3600), " CPU-h, ≈ ",
        round(ours * 4e-3 / 3600 / Threads.nthreads(); digits = 1), " h on ", Threads.nthreads(), " threads")
end
OPT["dry"] && (logmsg("dry run: nothing run"); exit(0))

# ------------------------------------------------------------------------------------------
# Stage 1: foams, τ
# ------------------------------------------------------------------------------------------
const T_START = now()
# templates are built once, outside the threaded pool (as `p64r_full` does)
for L in (P64R_L, P64R_L_LOW), s in (false, true)
    p64r_template(s, L)
end
failed = run_pool(J1, "foams")
isempty(failed) || error("04 runner: foam jobs failed: $failed (rerun to resume)")
R = Dict{String, Vector{Dict{String, Any}}}(k => Dict{String, Any}[] for k in keys(P64R_SCHEMA))
F = Dict{Tuple{Symbol, Int}, Any}()
for (f, k) in foam_jobs
    st, row = load(foamkey(f, k))
    F[(f, k)] = st
    push!(R["foams"], row)
end
τ = p64r_tau(R)
logmsg("τ = ", τ, "; PREP accepted ", count(r -> r["ok"], R["foams"]), "/40")
OPT["stage"] == "foams" && (logmsg("--stage foams: stopping"); exit(0))

# ------------------------------------------------------------------------------------------
# Stage 2: κ calibration
# ------------------------------------------------------------------------------------------
J2 = [Job(calkey(i, k), cyc(τ), () -> tag!(p64r_loop(F[(:ordered, k)], 3.0, 3.0 * r, P64R_T0,
          p64r_run_seed(P64R_BLOCK.cal, i, k), τ); set = "cal", r, gp = NaN, k)) for (i, r, k) in cal_jobs]
failed = run_pool(J2, "calibration")
isempty(failed) || error("04 runner: calibration jobs failed: $failed (rerun to resume)")
append!(R["loops"], [load(calkey(i, k)) for (i, r, k) in cal_jobs])
κ = p64r_kappa(R)
push!(R["calibration"], Dict{String, Any}("kappa" => κ.kappa, "r_star" => κ.r_star, "tau" => τ))
logmsg("κ = ", κ.kappa, ", r* = ", κ.r_star)
if isnan(κ.kappa)
    p64r_write(joinpath(OUT, "partial"), R)
    error("04 FULL: no first-T1 crossing at J = 3 on the calibration grid; κ cannot be calibrated " *
          "(a science question; the foams and calibration loops are in $(joinpath(OUT, "partial")))")
end
OPT["stage"] == "cal" && (logmsg("--stage cal: stopping"); exit(0))

# ------------------------------------------------------------------------------------------
# Stage 3: every other run, longest first
# ------------------------------------------------------------------------------------------
J3 = Job[]
for (set, J, gp, T, i, k) in loop_jobs
    push!(J3, Job(loopkey(set, i, k), cyc(τ), () -> tag!(p64r_loop(F[(:ordered, k)], J, κ.kappa * gp, T,
        p64r_run_seed(getfield(P64R_BLOCK, Symbol(set)), i, k), τ); set, r = gp / J, gp, k)))
end
for (set, f, T, k) in steady_jobs
    push!(J3, Job(steadykey(set, k), p64r_ours(T, τ) * lowsize(f), () -> tag!(p64r_steady(F[(f, k)], κ.kappa * 7.0, T,
        p64r_run_seed(getfield(P64R_BLOCK, Symbol(set)), 0, k), τ); set, foam = string(f), k)))
end
for (set, f, β, T, i, k) in bulk_jobs
    push!(J3, Job(bulkkey(set, i, k), p64r_ours(T, τ) * lowsize(f) * (set == "spec" ? 1.2 : 1.0), () -> begin
        run, W, S = p64r_bulk(F[(f, k)], β, κ.kappa, T, p64r_run_seed(getfield(P64R_BLOCK, Symbol(set)), i, k), τ;
            spectra = set == "spec")
        (tag!(run; set, foam = string(f), k), [tag!(w; set, foam = string(f), beta = β, k) for w in W],
            [tag!(s; foam = string(f), beta = β, k) for s in S])
    end))
end
failed = run_pool(J3, "runs")
isempty(failed) || error("04 runner: $(length(failed)) run jobs failed: $failed (rerun to resume)")

# assemble in `p64r_full`'s order
append!(R["loops"], [load(loopkey(set, i, k)) for (set, _, _, _, i, k) in loop_jobs])
append!(R["steady"], [load(steadykey(set, k)) for (set, _, _, k) in steady_jobs])
for (set, _, _, _, i, k) in bulk_jobs
    run, W, S = load(bulkkey(set, i, k))
    push!(R["bulk"], run)
    run["set"] == "v14" || append!(R["windows"], W)
    append!(R["spectra"], S)
end

# ------------------------------------------------------------------------------------------
# The record: tables, verdicts (frozen format), provenance
# ------------------------------------------------------------------------------------------
REC = joinpath(OUT, "record")
V = p64r_verdicts(R)
p64r_write(REC, R)
open(joinpath(REC, "verdicts.tsv"), "w") do io
    println(io, "id\tkind\tvalue\tband\tresult")
    for v in V
        println(io, join((v.id, v.kind, repr(v.value), v.band, v.ok ? "PASS" : "FAIL"), '\t'))
    end
end
git(args...) = try
    readchomp(Cmd(`git $args`; dir = ROOT))
catch
    "unknown"
end
open(joinpath(REC, "provenance.toml"), "w") do io
    TOML.print(io, Dict(
        "item" => "P6.4r", "decision" => "D-190",
        "commit" => git("rev-parse", "HEAD"), "commit_date" => git("log", "-1", "--format=%cs"),
        "dirty" => !isempty(git("status", "--porcelain", "--untracked-files=no")),
        "frozen_test" => "lib/PottsModels/test/reproductions/04_foam.jl",
        "frozen_sha256" => bytes2hex(open(sha256, FROZEN)),
        "runner" => "lib/PottsModels/reproductions/data/04/run_full.jl",
        "julia" => string(VERSION), "threads" => Threads.nthreads(),
        "machine" => "$(strip(Sys.cpu_info()[1].model)) ($(Sys.MACHINE)), CPU, $(Sys.CPU_THREADS) hardware threads",
        "started" => string(T_START), "finished" => string(now()),
        "wall_s_this_launch" => round((now() - T_START).value / 1000; digits = 1),
        "seeds" => Dict("foam" => "p64r_prep_seed(f, k, try) = 4_000_000 + 100_000 code(f) + 100k + try",
            "run" => "p64r_run_seed(block, idx, k) = 5_000_000 + 1_000_000 block + 10 idx + k",
            "blocks" => Dict(string(k) => v for (k, v) in pairs(P64R_BLOCK))),
        "jobs" => Dict("foams" => 40, "calibration" => 165, "loops" => 530, "steady" => 15, "bulk" => 200),
        "tau" => τ, "kappa" => κ.kappa, "r_star" => κ.r_star,
        "algorithm" => "BoundarySiteCPM(), proposals NeighborOrder(4) (DV1)",
        "verdicts" => Dict("pass" => count(v -> v.kind !== :info && v.ok, V),
            "fail" => count(v -> v.kind !== :info && !v.ok, V))))
end
logmsg("record written to ", REC, ": ", count(v -> v.kind !== :info && v.ok, V), " PASS, ",
    count(v -> v.kind !== :info && !v.ok, V), " FAIL")
for v in V
    v.kind === :info || v.ok || logmsg("FAIL ", v.id, " ", v.kind, " ", repr(v.value), " (", v.band, ")")
end

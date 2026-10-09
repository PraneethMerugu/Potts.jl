# P6.3f: reproduction 01b (Merks et al. 2008, digitised Figs 5, 7–10, 12, 13) FULL record
# runner (D-146, D-202). Not a frozen file.
#
# Runs every job of the FROZEN FULL tier of lib/PottsModels/test/reproductions/01_merks_01b.jl
# (D-202): the 1030 sweep jobs and 300 series jobs of `p63f1b_jobs()`, each through the
# frozen `p63f1b_sweep_job` / `p63f1b_series_job`, so the functions, seeds, parameters and
# save times are the frozen ones. It differs from the frozen tier only in scheduling: one job
# per thread, longest first, and resumable (each finished job is <out>/jobs/<key>.jls; a
# rerun skips finished jobs).
#
# The frozen test is `include`d unchanged with POTTS_FULL_REPRODUCTION and REPRO unset, so
# its always and SMOKE tiers run first, as a sanity gate (about a minute); any failure or
# error there stops the runner.
#
# When every job is done, the record is assembled in the layout the frozen record tier reads,
# in <out>/full-01b-<date>/:
#   sweeps.tsv      key, fig, curve, x, seed, C_N, C_N100
#   series.tsv      key, arm, seed, t, C, dH            (t = 0:50:5100)
#   verdicts.tsv    row, check, ours, rule, result, control  (the frozen `p63f1b_verdicts`,
#                   applied to the means of the two files above as the record tier reads them)
#   job_walls.tsv   key, wall_s, finished
#   provenance.toml item, commit, dirty, frozen_test_sha256, runner_sha256, cpu, threads,
#                   julia, launches; no host name and no local path (D-195)
# Copy that directory to lib/PottsModels/reproductions/data/01/ (exactly one full-01b-*
# may exist there) and add deviations.tsv for every failing row (D-154); the record tier of
# the frozen test then recomputes every row from it.
#
# Usage, from the checkout root (keep <out> outside reproductions/data/01):
#
#   julia --project=lib/PottsModels/test lib/PottsModels/reproductions/data/01/run_full_01b.jl \
#       --out <dir> [--threads N] [--dry-run] [--only <regex>]
#
# `--threads N` re-launches Julia with N threads (or pass `julia -t N` yourself). A job is
# single-threaded. `--dry-run` runs the gate, lists the jobs and the cost estimate, and runs
# nothing. `--only <regex>` runs only the jobs whose key matches (a check run); the record is
# assembled only once every job is done.
using Potts, PottsModels, Test, TOML, Dates, Serialization, SHA
using Statistics: mean

# ------------------------------------------------------------------------------------------
# Arguments
# ------------------------------------------------------------------------------------------
const USAGE = "usage: run_full_01b.jl --out <dir> [--threads N] [--dry-run] [--only <regex>]"
function parse_args(args)
    o = Dict{String, Any}("out" => "", "threads" => 0, "dry" => false, "only" => "")
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--dry-run"
            o["dry"] = true
        elseif a in ("--out", "--threads", "--only") && i < length(args)
            o[a[3:end]] = a == "--threads" ? parse(Int, args[i + 1]) : args[i + 1]
            i += 1
        elseif occursin('=', a) && first(split(a, '=')) in ("--out", "--threads", "--only")
            k, v = split(a[3:end], '='; limit = 2)
            o[k] = k == "threads" ? parse(Int, v) : String(v)
        else
            error("run_full_01b.jl: unknown argument $a ($USAGE)")
        end
        i += 1
    end
    isempty(o["out"]) && error("run_full_01b.jl: --out <dir> is required ($USAGE)")
    return o
end
const OPT = parse_args(ARGS)

# --threads N: re-launch with N threads (same project, the other arguments unchanged)
function without_threads(args)
    rest, skip = String[], false
    for a in args
        skip && (skip = false; continue)
        a == "--threads" && (skip = true; continue)
        startswith(a, "--threads=") && continue
        push!(rest, a)
    end
    return rest
end
if OPT["threads"] > 0 && OPT["threads"] != Threads.nthreads()
    cmd = `$(Base.julia_cmd()) --threads=$(OPT["threads"]) --project=$(Base.active_project()) $(abspath(PROGRAM_FILE)) $(without_threads(ARGS))`
    exit(success(run(ignorestatus(cmd))) ? 0 : 1)
end

const ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", "..", ".."))
const DATA01 = joinpath(ROOT, "lib", "PottsModels", "reproductions", "data", "01")
const FROZEN_REL = "lib/PottsModels/test/reproductions/01_merks_01b.jl"
const RUNNER_REL = "lib/PottsModels/reproductions/data/01/run_full_01b.jl"
const FROZEN = joinpath(ROOT, FROZEN_REL)
const OUT = abspath(OPT["out"])
const JOBS = joinpath(OUT, "jobs")
startswith(rstrip(OUT, '/') * "/", DATA01 * "/") &&
    error("run_full_01b.jl: write to a directory outside reproductions/data/01 (the frozen record tier reads data/01/full-01b-*)")
mkpath(JOBS)
logmsg(s...) = (println(stdout, "[", now(), "] ", s...); flush(stdout))

git(args...) = try
    readchomp(Cmd(`git $args`; dir = ROOT))
catch
    "unknown"
end
const COMMIT = git("rev-parse", "HEAD")
const DIRTY = !isempty(git("status", "--porcelain", "--untracked-files=no"))
DIRTY && logmsg("WARNING: the checkout has uncommitted changes; the record will say dirty = true and the frozen record tier rejects it")

# ------------------------------------------------------------------------------------------
# The frozen test: always and SMOKE tiers (the sanity gate) and its definitions
# ------------------------------------------------------------------------------------------
haskey(ENV, "POTTS_FULL_REPRODUCTION") && delete!(ENV, "POTTS_FULL_REPRODUCTION")
haskey(ENV, "REPRO") && delete!(ENV, "REPRO")
logmsg("including the frozen test (always + SMOKE tiers) ", FROZEN_REL, " with ", Threads.nthreads(), " threads")
const GATE = Test.DefaultTestSet("01b frozen test (SMOKE gate)")
Test.push_testset(GATE)
t_gate = try
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
    isempty(bad) || error("01b runner: the frozen test's gate failed:\n  " * join(bad, "\n  "))
end
P63F1B_FULL && error("01b runner: the frozen FULL tier must not run inside the runner")
logmsg("frozen test gate passed in ", round(t_gate; digits = 1), " s")

# ------------------------------------------------------------------------------------------
# Jobs: exactly the frozen `p63f1b_jobs()`, run by the frozen job functions
# ------------------------------------------------------------------------------------------
# Cost in site-MCS; seconds from the 01 record (data/01/full-2026-10-08, PC, 12 threads):
# the 110 V-C4 jobs (Merks2008, 202², 5100 MCS) took 110.7 s on average, 5.3e-7 s/site-MCS.
const S_PER_SITE_MCS = 5.3e-7
struct Job
    key::String
    kind::Symbol           # :sweep or :series
    spec::NamedTuple
    cost::Float64          # site-MCS
end
const JL = p63f1b_jobs()
function make_jobs()
    jobs = Job[]
    for j in JL.sweeps
        set = p63f1b_setup(j.fig, j.curve, j.x)
        push!(jobs, Job(p63f1b_key(j), :sweep, j, prod(set.lattice) * (set.N + 100)))
    end
    for j in JL.series
        set = p63f1b_arm_setup(j.arm)
        push!(jobs, Job(p63f1b_key(j), :series, j, prod(set.lattice) * maximum(P63F1B_SERIES_T)))
    end
    return jobs
end
const ALL = make_jobs()
@assert length(ALL) == 1330 && allunique(j.key for j in ALL)
runjob(j::Job) = j.kind === :sweep ? p63f1b_sweep_job(j.spec) : p63f1b_series_job(j.spec)

jobpath(key) = joinpath(JOBS, key * ".jls")
isdone(key) = isfile(jobpath(key))
function save(key, x)
    tmp = jobpath(key) * ".tmp-$(Threads.threadid())"
    serialize(tmp, x)
    mv(tmp, jobpath(key); force = true)
end
load(key) = deserialize(jobpath(key))

const SELECTED = isempty(OPT["only"]) ? ALL : filter(j -> occursin(Regex(OPT["only"]), j.key), ALL)
isempty(SELECTED) && error("01b runner: --only $(OPT["only"]) matches no job")
let todo = filter(j -> !isdone(j.key), SELECTED), nt = Threads.nthreads()
    hrs(c) = c * S_PER_SITE_MCS / 3600
    groups = Dict{String, Vector{Job}}()
    for j in ALL
        g = j.kind === :series ? "F12/F13 series (502², 5100 MCS)" :
            j.spec.curve == "CI1024" ? "F10 CI1024 (402², 5100 MCS)" :
            j.spec.fig == "F5" ? "F5 (202², 10 100 MCS)" : "F7–F10 128-cell (202², 5100 MCS)"
        push!(get!(groups, g, Job[]), j)
    end
    for (g, js) in sort(collect(groups); by = first)
        logmsg("  ", rpad(g, 34), lpad(length(js), 5), " jobs  ", lpad(round(hrs(sum(j -> j.cost, js)); digits = 1), 6),
            " thread-h")
    end
    total, rem = sum(j -> j.cost, ALL), sum(j -> j.cost, todo; init = 0.0)
    # longest-first list scheduling bound: max(work / threads, longest job)
    wall(c, js) = isempty(js) ? 0.0 : max(hrs(c) / nt, hrs(maximum(j -> j.cost, js)))
    logmsg("jobs: ", length(ALL), " in all (", length(JL.sweeps), " sweep, ", length(JL.series), " series), ",
        round(hrs(total); digits = 1), " thread-h at ", S_PER_SITE_MCS, " s/site-MCS; selected ", length(SELECTED),
        ", done ", count(j -> isdone(j.key), SELECTED), ", to run ", length(todo), " (", round(hrs(rem); digits = 2),
        " thread-h, ≈ ", round(wall(rem, todo); digits = 2), " h on ", nt, " threads if a thread keeps the PC's per-job speed)")
    if OPT["dry"]
        for j in sort(todo; by = j -> -j.cost)[1:min(end, 5)]
            logmsg("  first: ", j.key, " (", round(j.cost * S_PER_SITE_MCS; digits = 0), " s)")
        end
        for j in sort(todo; by = j -> j.cost)[1:min(end, 3)]
            logmsg("  shortest: ", j.key, " (", round(j.cost * S_PER_SITE_MCS; digits = 0), " s)")
        end
        logmsg("dry run: nothing run")
        exit(0)
    end
end

# ------------------------------------------------------------------------------------------
# Run: one job per thread, longest first
# ------------------------------------------------------------------------------------------
const T_LAUNCH = now()
open(joinpath(OUT, "launches.tsv"), "a") do io
    filesize(joinpath(OUT, "launches.tsv")) == 0 && println(io, "started\tcommit\tdirty\tthreads\tonly")
    println(io, join((T_LAUNCH, COMMIT, DIRTY, Threads.nthreads(), OPT["only"]), '\t'))
end
function run_pool(jobs)
    todo = sort(filter(j -> !isdone(j.key), jobs); by = j -> -j.cost)
    isempty(todo) && return String[]
    ch = Channel{Job}(length(todo))
    foreach(j -> put!(ch, j), todo)
    close(ch)
    failed, lk = String[], ReentrantLock()
    n, t0 = Threads.Atomic{Int}(0), time()
    @sync for _ in 1:Threads.nthreads()
        Threads.@spawn for j in ch
            try
                tj = @elapsed res = runjob(j)
                save(j.key, Dict{String, Any}("result" => res, "wall_s" => tj, "finished" => string(now()),
                    "commit" => COMMIT))
                k = Threads.atomic_add!(n, 1) + 1
                logmsg(k, "/", length(todo), " ", j.key, " ", round(tj; digits = 1), " s (",
                    round((time() - t0) / 3600; digits = 2), " h elapsed)")
            catch e
                lock(() -> push!(failed, j.key), lk)
                logmsg("FAILED ", j.key, ": ", sprint(showerror, e))
            end
        end
    end
    return failed
end
failed = run_pool(SELECTED)
isempty(failed) || error("01b runner: $(length(failed)) jobs failed: $failed (rerun to resume)")
missing_ = count(j -> !isdone(j.key), ALL)
if missing_ > 0
    logmsg("selected jobs done; ", missing_, " of ", length(ALL), " jobs still to run, so no record is assembled")
    exit(0)
end

# ------------------------------------------------------------------------------------------
# The record (the frozen record tier's schema)
# ------------------------------------------------------------------------------------------
const REC = joinpath(OUT, "full-01b-$(Dates.today())")
mkpath(REC)
fmt(x) = x === nothing ? "nothing" : string(x)       # shortest round-trip form for Float64
tsvline(io, xs...) = println(io, join(map(string, xs), '\t'))
J = Dict(j.key => load(j.key) for j in ALL)
open(joinpath(REC, "sweeps.tsv"), "w") do io
    tsvline(io, "key", "fig", "curve", "x", "seed", "C_N", "C_N100")
    for j in JL.sweeps
        r = J[p63f1b_key(j)]["result"]
        tsvline(io, p63f1b_key(j), j.fig, j.curve, fmt(j.x), j.seed, fmt(r.C_N), fmt(r.C_N100))
    end
end
open(joinpath(REC, "series.tsv"), "w") do io
    tsvline(io, "key", "arm", "seed", "t", "C", "dH")
    for j in JL.series
        rs = J[p63f1b_key(j)]["result"]
        @assert [q.t for q in rs] == collect(P63F1B_SERIES_T)
        for q in rs
            tsvline(io, p63f1b_key(j), j.arm, j.seed, q.t, fmt(q.C), fmt(q.dH))
        end
    end
end
open(joinpath(REC, "job_walls.tsv"), "w") do io
    tsvline(io, "key", "wall_s", "finished")
    for j in ALL
        tsvline(io, j.key, round(J[j.key]["wall_s"]; digits = 2), J[j.key]["finished"])
    end
end
# verdicts: the frozen rules on the means of the files just written, read back as the record
# tier reads them
msweep, mseries = p63f1b_means(p63f1b_tsv(joinpath(REC, "sweeps.tsv")), p63f1b_tsv(joinpath(REC, "series.tsv")))
V = p63f1b_verdicts(msweep, mseries)
clean(s) = replace(s, r"[\t\n]" => " ")
open(joinpath(REC, "verdicts.tsv"), "w") do io
    tsvline(io, "row", "check", "ours", "rule", "result", "control")
    for v in V
        tsvline(io, clean(v.row), clean(v.check), clean(v.ours), clean(v.rule), v.ok ? "PASS" : "FAIL", v.control)
    end
end
launches = filter(!isempty, readlines(joinpath(OUT, "launches.tsv")))[2:end]
job_commits = unique(string(J[j.key]["commit"]) for j in ALL)
walls = [J[j.key]["wall_s"] for j in ALL]
fins = sort([J[j.key]["finished"] for j in ALL])
rows = filter(v -> !v.control && !startswith(v.check, "point "), V)
ctls = filter(v -> v.control, V)
open(joinpath(REC, "provenance.toml"), "w") do io
    TOML.print(io, Dict{String, Any}(
        "item" => "P6.3f", "decision" => "D-202", "decisions" => ["D-146", "D-154", "D-157", "D-195", "D-202"],
        "commit" => COMMIT, "commit_date" => git("log", "-1", "--format=%cs"),
        "dirty" => DIRTY || any(l -> split(l, '\t')[3] == "true", launches),
        "job_commits" => job_commits,
        "frozen_test" => FROZEN_REL, "frozen_test_sha256" => bytes2hex(open(sha256, FROZEN)),
        "runner" => RUNNER_REL, "runner_sha256" => bytes2hex(open(sha256, @__FILE__)),
        "julia" => string(VERSION), "threads" => Threads.nthreads(),
        "cpu" => String(strip(Sys.cpu_info()[1].model)), "arch" => string(Sys.ARCH), "os" => string(Sys.KERNEL),
        "backend" => "CPU", "algorithm" => "SequentialCPM(), field_solver = ExplicitEuler(substeps = 15)",
        "env" => "POTTS_FULL_REPRODUCTION and REPRO unset in the runner; the frozen FULL tier's jobs run one per thread",
        "jobs" => length(ALL), "sweep_jobs" => length(JL.sweeps), "series_jobs" => length(JL.series),
        "seeds" => "pre-registered in the frozen test (P63F1B_BASE + 100k + i; series base + i); per job in sweeps.tsv and series.tsv",
        "launches" => [replace(l, '\t' => " ") for l in launches],
        "first_job_finished" => first(fins), "last_job_finished" => last(fins),
        "thread_s_sum_of_jobs" => round(sum(walls); digits = 1),
        "record_written" => string(now()),
        "verdicts" => Dict("rows_pass" => count(v -> v.ok, rows), "rows_fail" => count(v -> !v.ok, rows),
            "controls_failing_as_required" => count(v -> !v.ok, ctls), "controls" => length(ctls))))
end
logmsg("record written to ", REC, ": ", count(v -> v.ok, rows), " of ", length(rows), " rows pass; ",
    count(v -> !v.ok, ctls), " of ", length(ctls), " controls fail as required")
for v in V
    (!startswith(v.check, "point ") && v.ok == v.control) &&
        logmsg(v.control ? "CONTROL PASSED (must fail) " : "FAIL ", v.row, " ", v.check, " ", v.ours, " (", v.rule, ")")
end
logmsg("next: copy ", basename(REC), " to lib/PottsModels/reproductions/data/01/ and add deviations.tsv ",
    "(row, check, suspected_cause, author_question) for every FAIL row (D-154)")

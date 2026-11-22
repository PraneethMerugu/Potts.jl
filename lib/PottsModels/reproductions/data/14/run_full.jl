# The Fortuna reproduction runner: the short qualitative tier (with the calibration of c)
# and the FULL record that `protocol.jl` checks.
#
# Two stages, each a launch of its own:
#   1. `--stage qtier`: the c calibration, the short checks and the timing
#      (`qtier_calibration`, `qtier_controls`, `qtier_timing`). It writes <out>/qtier.toml:
#      the commit, the chosen c, the calibration rows, the ns per copy attempt at R = 10,
#      15, 20, every check and `pass`. Exit status 0 only if every check passed. After a
#      pass it makes one info-only run at the first set (the chosen c, seed 1, 2 × 10⁴ MCS)
#      with the diagnostics of record.jl: qtier_first_set_track.tsv.gz,
#      qtier_first_set_diag.tsv.gz and qtier_first_set_diag.toml.
#   2. `--stage full` (the default): refuses to start unless <out>/qtier.toml exists,
#      passed, and names this commit with a clean tree. Then the 700 FULL runs (68 sets, 10⁵
#      MCS each) at the calibrated c, one run per thread, in priority order (the persistence
#      set, the Fig 6 grid at R = 15, the rest of Table 2, the rest of Fig 5; longest first
#      inside each group), and the record: sets.tsv, runs.tsv, msd_runs.tsv, msd.tsv,
#      fits.tsv, oracle.tsv, scal.tsv, verdicts.tsv, job_walls.tsv, provenance.toml,
#      README.md, videos.toml, the info-only seam.tsv and nucleus_shape.tsv, and copies of
#      run_full.jl, record.jl and evaluate.jl. The runner then runs the record check on it.
#
# Resume safety. Every finished run is written to <out>/jobs/<key>.jls with its metadata:
# commit, dirty flag, the sha256 of the workspace Manifest.toml (gitignored, so the commit
# alone does not pin the dependency versions), the Julia version, c, tmax, cadence, trial
# flag and seed. A rerun reuses a job file only when every field equals this launch's, and
# refuses to start otherwise (remove <out>/jobs or choose another --out). A FULL launch
# refuses a dirty tree: tracked changes anywhere, or untracked files under lib/ or src/.
# The track of each run goes to <out>/tracks/<key>.tsv.gz (gzip TSV) and its diagnostics to
# <out>/tracks/<key>_diag.tsv.gz (every 50 MCS); the tracks go to the batch's release, not
# to git.
#
# The record goes to <out>/record/. Copy it to
# lib/PottsModels/reproductions/data/14/full-<date>/ (exactly one full-* directory may exist
# there), add deviations.tsv for every FAIL row (<out>/record/deviations_todo.tsv lists them
# with empty `cause` and `question` columns), and run evaluate.jl, which recomputes every
# row.
#
# Usage, from the checkout root (<out> outside the checkout's lib/ and src/, and outside
# reproductions/data/14):
#
#   julia --project=lib/PottsModels/test lib/PottsModels/reproductions/data/14/run_full.jl \
#       --out <dir> --stage qtier [--threads N]
#   julia --project=lib/PottsModels/test lib/PottsModels/reproductions/data/14/run_full.jl \
#       --out <dir> [--threads N] [--dry-run]
#
# `--threads N` re-launches Julia with N threads. Runs go one per thread; a run is
# single-threaded. `--dry-run` lists the jobs and the cost estimate and runs nothing.
#
# A trial, to check the scripts on short runs (never a record): `--trial --reps 1 --tmax 100
# --scal-tmax 100`. It writes only to <out>/trial/, runs every set with `reps` replicates of
# `tmax` MCS, runs its own short c calibration instead of the qtier stage (c = 0.1 if no c
# passes: short runs have no volume window), allows a dirty tree, marks provenance.toml
# `trial = true` and checks that the record parses.
using Potts, PottsModels, Test, TOML, Dates, Serialization, SHA
using CodecZlib: GzipCompressorStream
using Statistics: mean, std
# ------------------------------------------------------------------------------------------
# Arguments
const USAGE = "usage: --out <dir> [--stage qtier|full] [--threads N] [--dry-run] " *
    "[--trial --reps n --tmax T --scal-tmax T]"
function parse_args(args)
    o = Dict{String, Any}(
        "out" => "", "threads" => 0, "stage" => "full", "dry" => false, "trial" => false,
        "reps" => 0, "tmax" => 0, "scal-tmax" => 0,
    )
    valued = ("out", "threads", "stage", "reps", "tmax", "scal-tmax")
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--dry-run"
            o["dry"] = true
        elseif a == "--trial"
            o["trial"] = true
        elseif startswith(a, "--") && occursin('=', a) &&
                split(a[3:end], '='; limit = 2)[1] in valued
            k, v = split(a[3:end], '='; limit = 2)
            o[k] = String(v)
        elseif startswith(a, "--") && a[3:end] in valued && i < length(args)
            o[a[3:end]] = args[i + 1]
            i += 1
        else
            error("run_full.jl: unknown argument $a ($USAGE)")
        end
        i += 1
    end
    for k in ("threads", "reps", "tmax", "scal-tmax")
        o[k] isa AbstractString && (o[k] = parse(Int, o[k]))
    end
    isempty(o["out"]) && error("run_full.jl: --out <dir> is required ($USAGE)")
    o["stage"] in ("qtier", "full") || error("run_full.jl: --stage must be qtier or full")
    (o["reps"] > 0 || o["tmax"] > 0 || o["scal-tmax"] > 0) && !o["trial"] &&
        error("run_full.jl: --reps, --tmax and --scal-tmax need --trial")
    o["trial"] && o["stage"] == "qtier" &&
        error("run_full.jl: --trial runs its own c calibration; it has no qtier stage")
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

const T_START = now()
const TRIAL = OPT["trial"]
const QTIER = OPT["stage"] == "qtier"
const BASE = abspath(OPT["out"])
const OUT = TRIAL ? joinpath(BASE, "trial") : BASE    # a trial never writes outside <out>/trial
const JOBS = joinpath(OUT, "jobs")
const TRACKS = joinpath(OUT, "tracks")
const REC = joinpath(OUT, "record")
const QTIER_FILE = joinpath(OUT, "qtier.toml")
const ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", "..", ".."))
const DATA14 = joinpath(ROOT, "lib", "PottsModels", "reproductions", "data", "14")
logmsg(s...) = (println(stdout, "[", now(), "] ", s...); flush(stdout))
inside(p, d) = startswith(p * "/", rstrip(d, '/') * "/")
startswith(BASE, joinpath(DATA14, "full-")) &&
    error("run_full.jl: write to a directory outside reproductions/data/14/full-* (the record check reads those)")
for d in ("lib", "src")
    inside(BASE, joinpath(ROOT, d)) &&
        error("run_full.jl: --out must be outside the checkout's $d/ (its files would make the tree dirty)")
end

git(args...) = try
    readchomp(Cmd(`git $args`; dir = ROOT))
catch
    "unknown"
end
# dirty: tracked changes anywhere, or untracked files under lib/ or src/ (gitignored files,
# such as the workspace Manifest.toml, do not count)
const COMMIT = git("rev-parse", "HEAD")
const DIRTY_FILES = filter(
    !isempty,
    [
        split(git("status", "--porcelain", "--untracked-files=no"), '\n');
        split(git("status", "--porcelain", "--untracked-files=all", "--", "lib", "src"), '\n')
    ]
)
const DIRTY = !isempty(DIRTY_FILES) || COMMIT == "unknown"
if DIRTY && !TRIAL && !OPT["dry"]
    error(
        "run_full.jl: the checkout is dirty or not a git checkout (commit $COMMIT); a record needs a clean commit. " *
            "Changes:\n  " * join(unique(DIRTY_FILES), "\n  ")
    )
end
const MANIFEST = joinpath(ROOT, "Manifest.toml")
const MANIFEST_SHA = isfile(MANIFEST) ? bytes2hex(open(sha256, MANIFEST)) : "none"
const JULIA = string(VERSION)
logmsg(
    "commit ", COMMIT, DIRTY ? " (dirty)" : " (clean)", ", Manifest.toml sha256 ", MANIFEST_SHA,
    ", Julia ", JULIA, TRIAL ? ", trial in $OUT" : ""
)
if QTIER && OPT["dry"]
    logmsg(
        "dry run of --stage qtier, nothing run. It would run the c calibration and the first-set ",
        "checks (R = 10, φ_l = 0.05, λ_F = 150; c in the order 0.1, 0.3, 1.0 until volume_window ",
        "passes; 3 runs of 2 × 10⁴ MCS per c), confined_set (R = 15, φ_l = 0.30, λ_F = 125), ",
        "no_drive_control (λ_F = 0) and timing (R = 10, ",
        "15, 20) on ", Threads.nthreads(), " threads, then write ", QTIER_FILE,
        DIRTY ? ". This checkout is dirty: the real launch would refuse to start." : "."
    )
    exit(0)
end

# the protocol and the recorder
include(joinpath(@__DIR__, "protocol.jl"))
const P = FortunaProtocol
include(joinpath(@__DIR__, "record.jl"))
# a cheap gate: the protocol's oracle still resolves S = 0.02 with both fits
let rows = P.oracle()
    all(m -> P.method_passes(rows, m), P.METHODS) ||
        error("run_full.jl: the S-resolution oracle fails; not running")
end
# ------------------------------------------------------------------------------------------
# Stage qtier: the checks and numbers to <out>/qtier.toml
if QTIER
    mkpath(OUT)
    cal = P.qtier_calibration()
    logmsg("c calibration: ", cal.scal, " → c = ", cal.c)
    ctl = isfinite(cal.c) ? P.qtier_controls(cal.c, cal.first_set_disp) :
        (; checks = Pair{String, Bool}[], confined_disp = NaN, no_drive_disp = NaN)
    checks = [cal.checks; ctl.checks]
    pass = isfinite(cal.c) && all(last, checks)
    tns = isfinite(cal.c) ? P.qtier_timing(cal.c) : Dict{String, Float64}()
    for (label, ok) in checks
        logmsg(ok ? "PASS " : "FAIL ", label)
    end
    scal = [
        Dict(
            "c" => r.c, "cyto" => r.cyto, "nucleus" => r.nucleus, "lam" => r.lam,
            "pass" => r.pass,
        ) for r in cal.scal
    ]
    open(QTIER_FILE, "w") do io
        TOML.print(
            io, Dict(
                "commit" => COMMIT, "dirty" => DIRTY, "pass" => pass,
                "manifest_sha256" => MANIFEST_SHA, "c" => cal.c, "first_set_disp_sites" => cal.first_set_disp,
                "confined_disp_sites" => ctl.confined_disp, "no_drive_disp_sites" => ctl.no_drive_disp, "scal" => scal,
                "ns_per_attempt" => tns, "checks" => Dict(first.(checks) .=> last.(checks)),
                "threads" => Threads.nthreads(), "julia" => JULIA,
                "cpu" => strip(Sys.cpu_info()[1].model), "finished" => string(now()),
            )
        )
    end
    logmsg("qtier ", pass ? "PASSED" : "FAILED", ": c = ", cal.c, ", ns per attempt ", tns, "; written to ", QTIER_FILE)
    # info only, after the verdict: one run at the first set with the chosen c, seed 1,
    # 2 × 10⁴ MCS, with the seam and nucleus-shape series
    if pass
        try
            firstset = P.problem(10, 0.05, 150; c = cal.c, seed = 1, T = 20_000)
            L, _, Lz = P.dims(10, 0.05)
            rec, dg = record_run(firstset; T = 20_000, every = 10, L, Lz, fast = false)
            write_series(joinpath(OUT, "qtier_first_set_track.tsv.gz"), rec, TRACK_COLS)
            write_series(joinpath(OUT, "qtier_first_set_diag.tsv.gz"), dg, DIAG_COLS)
            d = diag_summary(dg, 20_000)
            open(joinpath(OUT, "qtier_first_set_diag.toml"), "w") do io
                TOML.print(
                    io, Dict(
                        "info" => "one info-only run at the first set; not part of the qtier verdict",
                        "R" => 10, "phi" => 0.05, "lambda" => 150, "c" => cal.c, "seed" => 1,
                        "tmax" => 20_000, "commit" => COMMIT, "manifest_sha256" => MANIFEST_SHA,
                        "julia" => JULIA,
                        "seam" => Dict(
                            "samples" => d.samples, "flagged" => d.flagged, "fraction" => d.fraction,
                            "max_pairs" => d.max_pairs, "lam_unreached_mean" => d.unreached_mean,
                            "lam_unreached_max" => d.unreached_max,
                        ),
                        "nucleus_second_half" => Dict("eig_ratio" => d.eig_ratio, "surface" => d.surface),
                    )
                )
            end
            logmsg(
                "first-set info run: seam-flagged samples ", d.flagged, " of ", d.samples,
                ", nucleus eig ratio ", round(d.eig_ratio; digits = 3), ", surface ",
                round(d.surface; digits = 3), " (second half)"
            )
        catch e
            logmsg("first-set info run failed (info only; the qtier verdict stands): ", sprint(showerror, e))
        end
    end
    exit(pass ? 0 : 1)
end
# ------------------------------------------------------------------------------------------
# The job list and the qtier record
const TMAX = TRIAL && OPT["tmax"] > 0 ? OPT["tmax"] : P.TMAX
const SCAL_T = TRIAL && OPT["scal-tmax"] > 0 ? OPT["scal-tmax"] : 20_000
const SET_IDS = collect(eachindex(P.SETS))
nreps(i) = TRIAL && OPT["reps"] > 0 ? min(OPT["reps"], P.replicates(P.SETS[i])) : P.replicates(P.SETS[i])
const RUNS = [(i, k) for i in SET_IDS for k in 1:nreps(i)]
TRIAL || @assert length(RUNS) == 700
runkey(i, k) = "s$(lpad(i, 2, '0'))_r$(lpad(k, 2, '0'))"
jobpath(key) = joinpath(JOBS, key * ".jls")
function save(path, x)
    tmp = path * ".tmp-$(Threads.threadid())"
    serialize(tmp, x)
    return mv(tmp, path; force = true)
end

# the qtier record of this commit (FULL only); a trial makes its own short calibration below
const QREC = if TRIAL
    nothing
else
    isfile(QTIER_FILE) || error(
        "run_full.jl: no $QTIER_FILE. Run `--stage qtier` with the same --out first; FULL starts " *
            "only after the qtier stage passes at this commit"
    )
    q = TOML.parsefile(QTIER_FILE)
    get(q, "pass", false) === true || error("run_full.jl: the qtier stage in $QTIER_FILE did not pass; FULL does not start")
    get(q, "commit", "") == COMMIT && get(q, "dirty", true) === false ||
        error(
        "run_full.jl: $QTIER_FILE was made at commit $(get(q, "commit", "?")) (dirty = $(get(q, "dirty", "?"))), " *
            "this checkout is $COMMIT; rerun `--stage qtier`"
    )
    get(q, "manifest_sha256", "") == MANIFEST_SHA && get(q, "julia", "") == JULIA ||
        error(
        "run_full.jl: $QTIER_FILE was made with Manifest.toml sha256 $(get(q, "manifest_sha256", "?")) and Julia " *
            "$(get(q, "julia", "?")), this launch has $MANIFEST_SHA and $JULIA; rerun `--stage qtier`"
    )
    q
end

# cost: sites × MCS × ns per copy attempt (the qtier timing per R when there is one, else
# 110 ns, an estimate; the record's wall_time row reports real wall times)
ns_attempt(R) = QREC === nothing ? 110.0 :
    Float64(get(QREC["ns_per_attempt"], string(R), maximum(values(QREC["ns_per_attempt"]))))
cost(i) = (s = P.SETS[i]; prod(P.dims(s[1], s[2])) * TMAX * ns_attempt(s[1]) * 1.0e-9)    # seconds
let total = sum(cost(i) for (i, _) in RUNS)
    logmsg(
        length(RUNS), " runs of ", TMAX, " MCS in ", length(SET_IDS), " sets ≈ ", round(total / 3600; digits = 1),
        " core-hours ≈ ", round(total / 3600 / Threads.nthreads(); digits = 1), " h on ", Threads.nthreads(), " threads (",
        QREC === nothing ? "110 ns per copy attempt, an estimate" : "the qtier ns per copy attempt", ")"
    )
end
if OPT["dry"]
    for (i, s) in enumerate(P.SETS)
        logmsg(
            "set ", i, " ", P.set_id(s), " n = ", nreps(i), " every = ", P.every(s), " lattice ",
            P.dims(s[1], s[2]), " seeds ", P.seed(i, 1), "…", P.seed(i, nreps(i))
        )
    end
    logmsg("dry run: nothing run")
    exit(0)
end
mkpath(JOBS)
mkpath(TRACKS)
# ------------------------------------------------------------------------------------------
# c: the qtier stage's (FULL), or a short calibration with the same procedure and seeds
# (trial)
const SCAL_KEYS = ("cyto", "nucleus", "lam")
scal_meta(j) = (;
    commit = COMMIT, dirty = DIRTY, manifest_sha256 = MANIFEST_SHA, julia = JULIA, c = P.C_GRID[j], scal_tmax = SCAL_T, trial = TRIAL,
    seeds = [P.qseed(j, k) for k in 1:3],
)
function trial_scal()
    rows = NamedTuple[]
    sys = P.system(10, 0.05)
    fortuna_layout(10, 0.05, sys)                              # the cache, before the threaded map
    for (j, c) in enumerate(P.C_GRID)
        path = joinpath(OUT, "scal_$(j).jls")
        row = if isfile(path)
            r = deserialize(path)
            get(r, :meta, nothing) == scal_meta(j) ||
                error(
                "run_full.jl: $path was made with $(get(r, :meta, "no metadata")), this launch has $(scal_meta(j)); " *
                    "remove it to rerun the calibration"
            )
            r
        else
            logmsg("c calibration (trial): c = ", c, ", 3 runs of ", SCAL_T, " MCS")
            rs = P.qruns(10, 0.05, 150, c, j; T = SCAL_T)
            dvs = [P.volume_errors(r, 10, 0.05) for r in rs]
            r = (;
                c, cyto = mean(d.cyto for d in dvs), nucleus = mean(d.nucleus for d in dvs), lam = mean(d.lam for d in dvs),
                pass = P.volumes_ok(dvs), meta = scal_meta(j),
            )
            save(path, r)
            r
        end
        push!(rows, row)
        row.pass && break
    end
    return rows
end
const SCAL = if QREC === nothing
    trial_scal()
else
    [
        (;
            c = Float64(r["c"]), cyto = Float64(r["cyto"]), nucleus = Float64(r["nucleus"]), lam = Float64(r["lam"]),
            pass = r["pass"],
        ) for r in QREC["scal"]
    ]
end
const C = if QREC !== nothing
    Float64(QREC["c"])
elseif last(SCAL).pass
    last(SCAL).c
else
    logmsg("c calibration (trial): no c passed (short runs have no volume window); c = 0.1")
    0.1
end
QREC === nothing || (isempty(SCAL) || last(SCAL).c != C || !last(SCAL).pass) &&
    error("run_full.jl: $QTIER_FILE's calibration rows do not end at its c = $C")
logmsg("c = ", C)
# ------------------------------------------------------------------------------------------
# The FULL runs
job_meta(i, k) = (;
    commit = COMMIT, dirty = DIRTY, manifest_sha256 = MANIFEST_SHA, julia = JULIA, c = C, tmax = TMAX, every = P.every(P.SETS[i]),
    trial = TRIAL, seed = P.seed(i, k),
)
"""The job file of run (i, k) if it exists and was made by an identical launch; an error if it
exists with other metadata; `nothing` if it does not exist."""
function load_job(i, k)
    path = jobpath(runkey(i, k))
    isfile(path) || return nothing
    r = deserialize(path)
    m = get(r, :meta, nothing)
    m == job_meta(i, k) && return r
    error(
        "run_full.jl: $path was made with $(m === nothing ? "no metadata" : m), this launch has $(job_meta(i, k)). " *
            "Job files are never reused across commits, dependency versions, Julia versions, c, tmax, cadence, trial or seed: remove $JOBS or choose another --out"
    )
end
# check every existing job file before running anything
const DONE = Set(j for j in RUNS if load_job(j...) !== nothing)

# systems and start layouts, built once on this task before any threaded work
const SYS = Dict{Tuple{Int, Float64}, Any}()
for (i, _) in RUNS
    R, φ, _ = P.SETS[i]
    haskey(SYS, (R, φ)) && continue
    sys = P.system(R, φ)
    SYS[(R, φ)] = (sys, fortuna_layout(R, φ, sys))
end

# the fast recorder records exactly what the observe-based one does (60 MCS at R = 10, 15)
for (R, φ) in ((10, 0.05), (15, 0.05))
    sys, lay = haskey(SYS, (R, φ)) ? SYS[(R, φ)] : (s = P.system(R, φ); (s, fortuna_layout(R, φ, s)))
    L, _, Lz = P.dims(R, φ)
    ok = check_recorder(P.problem(R, φ, 150; c = C, seed = 7, T = 60, sys, layout = lay); T = 60, L, Lz)
    ok || error("run_full.jl: the fast recorder disagrees with the observe-based one at R = $R; not running")
    logmsg("recorder check at R = ", R, ": the fast and observe-based paths agree on 60 MCS")
end

"""Run replicate `k` of set `i` at c = `C` and reduce it: the runs.tsv row and the MSD row."""
function run_one(i, k)
    s = P.SETS[i]
    R, φ, λ = s
    L, _, Lz = P.dims(R, φ)
    every = P.every(s)
    seed = P.seed(i, k)
    sys, lay = SYS[(R, φ)]
    prob = P.problem(R, φ, λ; c = C, seed, T = TMAX, sys, layout = lay)
    t0 = time()
    rec, dg = record_run(prob; T = TMAX, every, L, Lz)
    wall = time() - t0
    write_series(joinpath(TRACKS, runkey(i, k) * ".tsv.gz"), rec, TRACK_COLS)
    write_series(joinpath(TRACKS, runkey(i, k) * "_diag.tsv.gz"), dg, DIAG_COLS)
    w = findall(t -> t % P.DT == 0, rec.t)                      # the 50-MCS samples
    tr = P.A.unwrap_track(collect(zip(rec.nx, rec.ny)), (L, L), true)
    tr50 = [p ./ R for p in tr[w]]                               # R units
    n = length(tr50)
    lags = filter(<(n), P.LAGS)                             # all of them at 10⁵ MCS; a trial has fewer
    m = fill(NaN, length(P.LAGS))
    isempty(lags) || (m[1:length(lags)] = P.A.mean_squared_displacement(tr50; lags))
    dv = P.volume_errors(rec, R, φ)
    return (;
        set = i, rep = k, seed, R, phi = φ, lambda = λ, every, disp = P.displacement(rec, L) / R,
        detached = P.detached(rec.t[w], rec.lam_cyto[w], rec.alive[w]),
        lam_deaths = round(Int, rec.births[end]) - rec.alive[end], lid_touch = any(rec.lid),
        dv_cyto = dv.cyto, dv_nuc = dv.nucleus, dv_lam = dv.lam, wall_s = wall, msd = m, diag = diag_summary(dg, TMAX),
        meta = job_meta(i, k),
    )
end

function run_pool(todo)
    logmsg("FULL: ", length(RUNS), " runs, ", length(RUNS) - length(todo), " already done, ", length(todo), " to run")
    isempty(todo) && return String[]
    ch = Channel{Tuple{Int, Int}}(length(todo))
    foreach(j -> put!(ch, j), todo)
    close(ch)
    failed = String[]
    lk = ReentrantLock()
    n = Threads.Atomic{Int}(0)
    t0 = time()
    @sync for _ in 1:Threads.nthreads()
        Threads.@spawn for (i, k) in ch
            key = runkey(i, k)
            try
                res = run_one(i, k)
                save(jobpath(key), res)
                c = Threads.atomic_add!(n, 1) + 1
                logmsg(
                    "run ", c, "/", length(todo), " ", key, " ", P.set_id(P.SETS[i]), " ", round(res.wall_s; digits = 1),
                    " s, disp ", round(res.disp; digits = 2), " R (", round((time() - t0) / 3600; digits = 2), " h elapsed)"
                )
            catch e
                lock(lk) do
                    push!(failed, key)
                end
                logmsg("run FAILED ", key, ": ", sprint(showerror, e, catch_backtrace()))
            end
        end
    end
    return failed
end

# priority order, so a cut-short batch keeps the priority sets: the persistence set, the Fig
# 6 grid (R = 15), the rest of Table 2, the rest of Fig 5; longest first inside each group
const T2_KEYS = Set(P.set_key(r) for r in P.read_tsv(joinpath(P.REFS, "table2.tsv")))
function priority(i)
    s = P.SETS[i]
    s == P.PERSISTENCE_SET && return 0
    s[1] == 15 && haskey(P.REGIME_MAP, (s[2], s[3])) && return 1
    s in T2_KEYS && return 2
    return 3
end
const TODO = sort(filter(j -> !(j in DONE), RUNS); by = j -> (priority(j[1]), -cost(j[1]), j[1], j[2]))
const FAILED = run_pool(TODO)
isempty(FAILED) || error("run_full.jl: $(length(FAILED)) runs failed: $(join(FAILED, ", ")); rerun to retry them")
# ------------------------------------------------------------------------------------------
# The record
mkpath(REC)
const RES = sort([something(load_job(i, k)) for (i, k) in RUNS]; by = r -> (r.set, r.rep))
const COMMITS_SEEN = sort(unique(r.meta.commit for r in RES))
if !TRIAL && (COMMITS_SEEN != [COMMIT] || any(r -> r.meta.dirty, RES))
    error(
        "run_full.jl: the runs were made at commits $COMMITS_SEEN (dirty: $(any(r -> r.meta.dirty, RES))); " *
            "a record needs every run clean at $COMMIT"
    )
end
b01(x::Bool) = x ? "1" : "0"
function write_tsv(name, header, rows)
    return open(joinpath(REC, name), "w") do io
        println(io, join(header, '\t'))
        for r in rows
            println(io, join(r, '\t'))
        end
    end
end
s64(x) = string(Float64(x))                                      # round-trips exactly

write_tsv(
    "runs.tsv", (
        "set", "rep", "seed", "R", "phi", "lambda", "every", "disp", "detached", "lam_deaths", "lid_touch",
        "dv_cyto", "dv_nuc", "dv_lam", "wall_s",
    ),
    [
        (
            r.set, r.rep, r.seed, r.R, r.phi, r.lambda, r.every, s64(r.disp), b01(r.detached), r.lam_deaths, b01(r.lid_touch),
            s64(r.dv_cyto), s64(r.dv_nuc), s64(r.dv_lam), s64(round(r.wall_s; digits = 2)),
        ) for r in RES
    ]
)
write_tsv(
    "msd_runs.tsv", ("set", "rep", ("m_$l" for l in P.LAGS)...),
    [(r.set, r.rep, (s64(x) for x in r.msd)...) for r in RES]
)
write_tsv(
    "job_walls.tsv", ("set", "rep", "seed", "R", "phi", "lambda", "wall_s"),
    [(r.set, r.rep, r.seed, r.R, r.phi, r.lambda, s64(round(r.wall_s; digits = 2))) for r in RES]
)
write_tsv("scal.tsv", ("c", SCAL_KEYS..., "pass"), [(s64(r.c), s64(r.cyto), s64(r.nucleus), s64(r.lam), b01(r.pass)) for r in SCAL])
write_tsv(
    "oracle.tsv", ("method", "P", "S_true", "seed", "S", "D", "P_fit"),
    [(r.method, s64(r.P), s64(r.S_true), r.seed, s64(r.S), s64(r.D), s64(r.P_fit)) for r in P.oracle()]
)
# sets.tsv first without the derived columns: `verdicts` needs the file
const SET_HEAD = ("set", "R", "phi", "lambda", "n", "every", "L", "Lz", "regime", "detach", "disp_mean", "disp_se")
set_cols(i) = (s = P.SETS[i]; d = P.dims(s[1], s[2]); (i, s[1], s[2], s[3], P.replicates(s), P.every(s), d[1], d[3]))
write_tsv("sets.tsv", SET_HEAD, [(set_cols(i)..., "", "", "", "") for i in eachindex(P.SETS)])

logmsg("record: recomputing the verdicts")
const V, RR = P.verdicts(REC, P.REFS)
write_tsv(
    "sets.tsv", SET_HEAD,
    [(set_cols(i)..., RR.regime[i], RR.detach[i], s64(RR.disp[i]), s64(RR.disp_se[i])) for i in eachindex(P.SETS)]
)
write_tsv(
    "msd.tsv", ("set", "lag_mcs", "msd"),
    [(i, P.DT * l, s64(RR.ens[i][j])) for i in eachindex(P.SETS) for (j, l) in enumerate(P.LAGS)]
)
const FITIX = [findfirst(==(l), P.LAGS) for l in P.FIT_LAGS]
const MR = P.msd_runs(REC)
logmsg("record: fits and bootstrap SE(S) for ", length(RR.fits), " (set, method) pairs")
# `offset`: the fit's intercept, which the persistence collapse subtracts
write_tsv(
    "fits.tsv", ("set", "method", "S", "P", "D", "D_fast", "v_eff", "se_S", "excluded", "offset"),
    [
        (
            i, method, s64(f.S), s64(f.P), s64(f.D), s64(f.D_fast), s64(f.v_eff),
            s64(P.resolved(f) ? P.bootstrap_se(MR[i][:, FITIX], method) : NaN),
            P.excluded(P.FIT_DT, RR.ens[i][FITIX], f), s64(f.offset),
        )
            for ((i, method), f) in sort(collect(RR.fits); by = first)
    ]
)
clean(x) = replace(repr(x), '\t' => ' ', '\n' => ' ')
const GATING = [v for v in V if v.kind === :row]
write_tsv(
    "verdicts.tsv", ("id", "kind", "value", "band", "result"),
    [(v.id, v.kind, clean(v.value), v.band, v.ok ? "PASS" : "FAIL") for v in GATING]
)
write_tsv(
    "deviations_todo.tsv", ("id", "ours", "paper", "cause", "question"),
    [(v.id, clean(v.value), v.band, "", "") for v in GATING if !v.ok]
)
write_tsv("info.tsv", ("id", "value", "band"), [(v.id, clean(v.value), v.band) for v in V if v.kind === :info])
# the info-only diagnostics (record.jl; the record check does not read them)
write_tsv(
    "seam.tsv", ("set", "rep", "samples", "flagged", "fraction", "max_pairs", "lam_unreached_mean", "lam_unreached_max"),
    [
        (
            r.set, r.rep, r.diag.samples, r.diag.flagged, s64(r.diag.fraction), r.diag.max_pairs, s64(r.diag.unreached_mean),
            r.diag.unreached_max,
        ) for r in RES
    ]
)
write_tsv(
    "nucleus_shape.tsv", ("set", "rep", "eig_ratio", "surface"),
    [(r.set, r.rep, s64(r.diag.eig_ratio), s64(r.diag.surface)) for r in RES]
)
finmean(v) = (w = filter(isfinite, collect(v)); isempty(w) ? NaN : mean(w))
const DIAG_SETS = [
    (
        i = i, s = P.SETS[i], runs = length(rs), seam_runs = count(r -> r.diag.flagged > 0, rs),
        seam_frac = finmean(r.diag.fraction for r in rs), eig = finmean(r.diag.eig_ratio for r in rs),
        surf = finmean(r.diag.surface for r in rs),
    )
        for (i, rs) in ((i, filter(r -> r.set == i, RES)) for i in eachindex(P.SETS))
]
r3(x) = isfinite(x) ? string(round(x; digits = 3)) : "NaN"

const NPASS, NFAIL = count(v -> v.ok, GATING), count(v -> !v.ok, GATING)
open(joinpath(REC, "provenance.toml"), "w") do io
    TOML.print(
        io, Dict(
            "trial" => TRIAL,
            "commit" => COMMIT, "commit_date" => git("log", "-1", "--format=%cs"), "dirty" => DIRTY || any(r -> r.meta.dirty, RES),
            "commits_seen" => COMMITS_SEEN, "manifest_sha256" => MANIFEST_SHA,
            "protocol" => "lib/PottsModels/reproductions/data/14/protocol.jl",
            "runner" => "lib/PottsModels/reproductions/data/14/run_full.jl",
            "julia" => JULIA, "threads" => Threads.nthreads(),
            "machine" => "$(Sys.MACHINE), $(Sys.CPU_THREADS) hardware threads",
            "cpu" => strip(Sys.cpu_info()[1].model),
            "started" => string(T_START), "finished" => string(now()),
            "wall_s_this_launch" => round((now() - T_START).value / 1000; digits = 1),
            "c" => C, "c_status" => TRIAL ? "trial calibration (not a record)" :
                "calibrated (qtier stage): the first c of $(collect(P.C_GRID)) that passes volume_window",
            "qtier" => QREC === nothing ? Dict{String, Any}() :
                Dict(
                    "ns_per_attempt" => QREC["ns_per_attempt"], "first_set_disp_sites" => QREC["first_set_disp_sites"],
                    "finished" => QREC["finished"], "threads" => QREC["threads"]
                ),
            "tmax" => TMAX, "runs" => length(RUNS), "sets" => length(SET_IDS),
            "algorithm" => "SequentialCPM(), proposals VonNeumann(1), field_solver ExplicitEuler(substeps = 1)",
            "seeds" => Dict(
                "run" => "P.seed(i, k) = 1_400_000_000 + 1000i + k",
                "scal" => "P.qseed(block, k) = 1_490_000_000 + 1000block + k, block = position of c in the grid"
            ),
            "verdicts" => Dict("pass" => NPASS, "fail" => NFAIL)
        )
    )
end
open(joinpath(REC, "videos.toml"), "w") do io
    println(io, "# The batch's videos: name, release URL and sha256 of each, added by the")
    println(io, "# coordinator when the release is published. The runner makes no videos.")
end
for f in ("run_full.jl", "record.jl", "evaluate.jl")
    cp(joinpath(@__DIR__, f), joinpath(REC, f); force = true)
end
QREC === nothing || cp(QTIER_FILE, joinpath(REC, "qtier.toml"); force = true)   # verbatim, for audit
open(joinpath(REC, "README.md"), "w") do io
    print(
        io, """
        # Fortuna et al. (2020): the FULL record

        Made by `run_full.jl` and `record.jl` (copies are here) at the commit in
        `provenance.toml`, with the protocol
        `lib/PottsModels/reproductions/data/14/protocol.jl`. `evaluate.jl` recomputes every
        row from these files.

        - c = $(C), the calibrated value of the qtier stage (`scal.tsv`). The qtier stage
          passed at the same commit before the FULL runs started; its timing is in
          `provenance.toml`.
        - $(length(RUNS)) runs of $(TMAX) MCS in $(length(SET_IDS)) sets; $(NPASS) gating
          rows pass and $(NFAIL) fail (`verdicts.tsv`). Every FAIL row needs a
          `deviations.tsv` entry; `deviations_todo.tsv` lists them. Info rows are in
          `info.tsv`.
        - The tracked point is the nucleus center of mass in x and y, periodic-unwrapped, in
          R units. The MSD uses the whole track sampled every 50 MCS.
        - At P ≫ 10⁴ MCS both fit methods underestimate P by about 20 % (the protocol's
          oracle; P = 23265 and 26853 in Table 2). This is inside the ±50 % band of
          `table2/`.
        - `qtier.toml` is the qtier stage's record, copied verbatim.
        - The per-run tracks (`tracks/<set>_<rep>.tsv.gz`, gzip TSV, columns
          $(join(TRACK_COLS, ", "))) are in the batch's release, not in git: the centroids
          (x, y, z) of the nucleus (n), the lamellipodium (l) and the cytoplasm (c), Πx, Πy,
          lam_cyto, the three volumes, the lamellipodium alive flag, lam_births and the lid
          flag. They are sampled every MCS for the 36 sets with λ_F ∈ {150, 175, 200} and
          every 10 MCS otherwise. Read one with
          `readdlm(GzipDecompressorStream(open(path)), '\\t'; header = true)`.
        - Info only, not gated (`record.jl` documents both):
          `tracks/<set>_<rep>_diag.tsv.gz`, every $(DIAG_EVERY) MCS, holds the seam-contact
          counts and the nucleus shape. `seam.tsv` and `nucleus_shape.tsv` give them per run
          (the shape as the mean over the second half).

        ## Diagnostics per set (info only)

        | set | R | φ_l | λ_F | runs | runs with a seam contact | mean flagged fraction | nucleus eig ratio | nucleus surface |
        |---|---|---|---|---|---|---|---|---|
        $(join(["| $(d.i) | $(d.s[1]) | $(d.s[2]) | $(d.s[3]) | $(d.runs) | $(d.seam_runs) | $(r3(d.seam_frac)) | $(r3(d.eig)) | $(r3(d.surf)) |" for d in DIAG_SETS], "\n"))
        """
    )
end
logmsg("record written to ", REC, ": ", NPASS, " PASS, ", NFAIL, " FAIL")
for v in GATING
    v.ok || logmsg("FAIL ", v.id, " ", clean(v.value), " (", v.band, ")")
end

# the record check on what was written (a trial checks only that it parses)
const CHECK = Test.DefaultTestSet("Fortuna record check")
try
    Test.@with_testset CHECK P.check_record(REC)
catch e
    logmsg("record check errored: ", sprint(showerror, e))
    TRIAL || rethrow()
end
let c = Test.get_test_counts(CHECK)
    logmsg(
        "record check: ", c.passes + c.cumulative_passes, " pass, ", c.fails + c.cumulative_fails, " fail, ",
        c.errors + c.cumulative_errors, " error, ", c.broken + c.cumulative_broken,
        " broken (FAIL rows without deviations.tsv fail here until deviations.tsv lists them)"
    )
end

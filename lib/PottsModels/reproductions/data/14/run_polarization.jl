# The runner of the polarization study (Thomas et al. 2022) on the Fortuna model: the runs of
# `polarization_protocol.jl`, one track per run. `analyze_polarization.jl` makes the record
# from the tracks.
#
# Each run writes <out>/tracks/<key>.tsv.gz (every MCS: t, the nucleus, lamellipodium and CN
# centroids, Πx, Πy, lam_cyto and the three compartment volumes; gzip TSV) and then
# <out>/tracks/<key>.toml (seed, c, tmax, commit, dirty flag, Julia version, wall time). A
# rerun skips a run whose .toml exists with the same seed, c and tmax, and refuses to start if
# one exists with other values. The tracks go to the batch's release, not to git.
#
# c is not stated: pass the c that the Fortuna calibration chose (qtier.toml of
# run_full.jl). A launch that is not a trial refuses a dirty tree.
#
# Usage, from the checkout root (<out> outside the checkout's lib/ and src/):
#
#   julia -t N --project=lib/PottsModels/test \
#       lib/PottsModels/reproductions/data/14/run_polarization.jl --out <dir> --c <c>
#
# Runs go one per thread, longest first. A trial checks the scripts on short runs (never a
# record): `--trial --reps 1 --tmax 300 [--sets 1,12]`; c defaults to 0.1 there, and it
# writes only to <out>/trial/.
using Potts, PottsModels, TOML, Dates
using CodecZlib: GzipCompressorStream

const USAGE = "usage: --out <dir> --c <c> [--sets i,j,…] [--trial --reps n --tmax T]"
function parse_args(args)
    o = Dict{String, Any}("out" => "", "c" => "", "sets" => "", "reps" => "", "tmax" => "", "trial" => false)
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--trial"
            o["trial"] = true
        elseif startswith(a, "--") && haskey(o, a[3:end]) && i < length(args)
            o[a[3:end]] = args[i + 1]
            i += 1
        else
            error("run_polarization.jl: unknown argument $a ($USAGE)")
        end
        i += 1
    end
    isempty(o["out"]) && error("run_polarization.jl: --out <dir> is required ($USAGE)")
    (!isempty(o["reps"]) || !isempty(o["tmax"])) && !o["trial"] &&
        error("run_polarization.jl: --reps and --tmax need --trial")
    isempty(o["c"]) && !o["trial"] &&
        error("run_polarization.jl: --c is required (the c of the Fortuna calibration)")
    return o
end
const OPT = parse_args(ARGS)

include(joinpath(@__DIR__, "protocol.jl"))              # FortunaProtocol: KIND, for record.jl
include(joinpath(@__DIR__, "record.jl"))                # record_run, write_series
include(joinpath(@__DIR__, "polarization_protocol.jl"))
const PP = FortunaPolarizationProtocol

const TRIAL = OPT["trial"]
const C = isempty(OPT["c"]) ? 0.1 : parse(Float64, OPT["c"])
const REPS = isempty(OPT["reps"]) ? PP.REPS : parse(Int, OPT["reps"])
const TMAX = isempty(OPT["tmax"]) ? PP.TMAX : parse(Int, OPT["tmax"])
const SET_IDS = isempty(OPT["sets"]) ? collect(eachindex(PP.SETS)) : parse.(Int, split(OPT["sets"], ','))
const OUT = TRIAL ? joinpath(abspath(OPT["out"]), "trial") : abspath(OPT["out"])
const TRACKS = joinpath(OUT, "tracks")
const ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", "..", ".."))
for d in ("lib", "src")
    startswith(OUT * "/", joinpath(ROOT, d) * "/") &&
        error("run_polarization.jl: --out must be outside the checkout's $d/")
end
git(args...) = try
    readchomp(Cmd(`git $args`; dir = ROOT))
catch
    "unknown"
end
const COMMIT = git("rev-parse", "HEAD")
const DIRTY = !isempty(git("status", "--porcelain", "--untracked-files=no")) ||
    !isempty(git("status", "--porcelain", "--untracked-files=all", "--", "lib", "src")) ||
    COMMIT == "unknown"
DIRTY && !TRIAL && error("run_polarization.jl: the checkout is dirty; a record needs a clean commit")
logmsg(s...) = (println(stdout, "[", now(), "] ", s...); flush(stdout))
mkpath(TRACKS)

const COLS = (:t, :nx, :ny, :lx, :ly, :cx, :cy, :Πx, :Πy, :lam_cyto, :vc, :vn, :vl)
runkey(i, k) = "set$(lpad(i, 2, '0'))_rep$(lpad(k, 2, '0'))"
meta(i, k) = Dict("seed" => PP.seed(i, k), "c" => C, "tmax" => TMAX)
function done(i, k)
    p = joinpath(TRACKS, runkey(i, k) * ".toml")
    isfile(p) || return false
    m = TOML.parsefile(p)
    all(kv -> m[kv[1]] == kv[2], meta(i, k)) ||
        error("run_polarization.jl: $p was made with other settings; choose another --out")
    return isfile(joinpath(TRACKS, runkey(i, k) * ".tsv.gz"))
end

const RUNS = [(i, k) for i in SET_IDS for k in 1:REPS]
const TODO = sort(filter(j -> !done(j...), RUNS); by = j -> (-PP.SETS[j[1]][1], j))
# systems and start layouts, built on this task before any threaded work
const SYS = Dict{Tuple{Int, Float64}, Any}()
for (i, _) in TODO
    R, φ, _ = PP.SETS[i]
    haskey(SYS, (R, φ)) && continue
    sys = PP.system(R, φ)
    SYS[(R, φ)] = (sys, PP.start(R, sys))
end
logmsg(
    length(RUNS), " runs (", length(SET_IDS), " sets × ", REPS, " replicates, ", TMAX, " MCS, c = ", C,
    "), ", length(RUNS) - length(TODO), " done, ", length(TODO), " to run on ", Threads.nthreads(),
    " threads; commit ", COMMIT, DIRTY ? " (dirty)" : "", TRIAL ? "; trial" : ""
)

function run_one(i, k)
    R, φ, λ = PP.SETS[i]
    L, _, Lz = fortuna_lattice(R, φ)
    sys, lay = SYS[(R, φ)]
    prob = PP.problem(R, φ, λ; c = C, seed = PP.seed(i, k), T = TMAX, sys, layout = lay)
    t0 = time()
    rec, _ = record_run(prob; T = TMAX, every = PP.EVERY, L, Lz, diag = false)
    write_series(joinpath(TRACKS, runkey(i, k) * ".tsv.gz"), rec, COLS)
    m = merge(
        meta(i, k), Dict(
            "set" => i, "rep" => k, "R" => R, "phi" => φ, "lambda" => λ, "commit" => COMMIT,
            "dirty" => DIRTY, "julia" => string(VERSION), "wall_s" => time() - t0,
            "trial" => TRIAL,
        )
    )
    open(io -> TOML.print(io, m), joinpath(TRACKS, runkey(i, k) * ".toml"), "w")
    return time() - t0
end

const FAILED = Threads.Atomic{Int}(0)
Threads.@threads :dynamic for j in TODO
    try
        w = run_one(j...)
        logmsg(runkey(j...), " ", PP.set_id(PP.SETS[j[1]]), " done in ", round(w; digits = 1), " s")
    catch e
        Threads.atomic_add!(FAILED, 1)
        logmsg(runkey(j...), " FAILED: ", sprint(showerror, e))
    end
end
FAILED[] == 0 || error("run_polarization.jl: $(FAILED[]) runs failed")
logmsg("all ", length(RUNS), " runs are in ", TRACKS)

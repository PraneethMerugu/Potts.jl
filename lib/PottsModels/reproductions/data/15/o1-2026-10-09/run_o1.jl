# P6.15j: the D-146 offline record of the OpenVT O1 per-cell time series (spec 15 §3.1 O1,
# §4.0 A3, §4.0.1; D-204, D-206): cases (a), (b), (e) and (f) of the P6.15f record re-run from
# their recorded seeds, with one `x,y,i,n` file per save.
#
# The protocol, seeds, lattices and recorder are the frozen F3/F8 test's
# `lib/PottsModels/test/reproductions/15_openvt_f3_f8.jl`, evaluated from its source as the
# P6.15f runner does: every top-level `P615F_*` constant and `p615f_*` function of that file is
# loaded verbatim. `p615f_run` is loaded a second time as `o1_run`, with one change made to
# its parsed source: its `record(integ)` also writes the save's O1 file
# (`PottsModels.openvt_frame`, `write_openvt(…, :O1, …)`) after `p615f_row`. The O1 stamps are
# therefore the timeseries.tsv saves by construction (MCS 0, every 39 MCS and the stop), and
# each run's series is checked against the P6.15f record row by row (MCS, N, r, A, C, w, g,
# exactly) before anything is written here.
#
# Writes:
# - into the bulk directory `OPENVT_PACKAGE_BULK` (outside git, never committed):
#   `Potts.jl_centroids_<case>.zip` per case (members `centroids/<case>/potts_<case>_s<seed>_<MCS:06d>.csv`,
#   sorted, no directory entries, no extra attributes), and the 100 O2 files
#   `Potts.jl_5T_MonolayerGrowth_1000_Data/cell_data_no_inhibition_<k>.csv` of case (b);
# - into the staging directory `OPENVT_O1_STAGE` (default `<bulk>/o1-stage`, must be empty or
#   absent): the loose O1 files the archives are made from (delete it afterwards);
# - into this directory: runs.tsv, o1_manifest.tsv, archives.tsv, o2_manifest.tsv and
#   provenance.toml. README.md is written by hand.
#
# O2 (case (b) at 1000 cells): with `F5_O2_DIR` set to the P6.15e runner's output directory,
# its files are copied (from `F5_O2_DIR` or its `Potts.jl_5T_MonolayerGrowth_1000_Data/`); they
# are kept only if every one has the F5 record's cell count and the same x, y as this re-run's
# stop file of that seed. Otherwise (or without `F5_O2_DIR`) they are written from the re-run's
# stop states with `openvt_snapshot` and `write_openvt(…, :O2, …)`. `provenance.toml` says which.
#
# Needs Info-ZIP `zip` and `unzip` on PATH. From the repository root:
#
#     OPENVT_PACKAGE_BULK=<bulk dir> F5_O2_DIR=<F5 o2 dir> POTTS_AFFINITY="taskset -c 0-11,16-27" \
#         taskset -c 0-11,16-27 julia -t 12 --project=lib/PottsModels/test \
#         lib/PottsModels/reproductions/data/15/o1-2026-10-09/run_o1.jl
#
# `OPENVT_O1_SMOKE=true` instead re-runs case (b) seed 15001 to MCS 780 into a temporary
# directory, checks its 21 saves against the record and writes nothing here or in the bulk
# directory (a check that the current code still reproduces the record).
using Potts, PottsModels, Test
using Potts: CorePotts
using Statistics: mean
using Dates, TOML, SHA

const started = now()
const DIR = @__DIR__
const ROOT = normpath(joinpath(DIR, "..", "..", "..", "..", "..", ".."))
const TEST = joinpath(ROOT, "lib", "PottsModels", "test", "reproductions", "15_openvt_f3_f8.jl")
const PKGTEST = joinpath(ROOT, "lib", "PottsModels", "test", "reproductions", "15_openvt_package.jl")
const DATA = normpath(joinpath(DIR, ".."))
const SMOKE = get(ENV, "OPENVT_O1_SMOKE", "false") == "true"

# ---- the frozen test's constants and rules, verbatim ---------------------------------------------
_defname(ex) = ex isa Expr && ex.head === :const ? _defname(ex.args[1]) :
               ex isa Expr && ex.head in (:(=), :function) ? (a = ex.args[1]; a isa Symbol ? a :
                                                              a isa Expr && a.head === :call ? a.args[1] :
                                                              a isa Expr && a.head === :where ? a.args[1].args[1] :
                                                              nothing) : nothing
const RUN_DEF = Ref{Any}(nothing)
for ex in Meta.parseall(read(TEST, String)).args
    ex isa Expr || continue
    n = _defname(ex)
    (n isa Symbol && startswith(string(n), r"p615f_|P615F_")) || continue
    Core.eval(@__MODULE__, ex)
    n === :p615f_run && (RUN_DEF[] = deepcopy(ex))
end

# ---- p615f_run with its recorder extended by the O1 file --------------------------------------
# `record(integ) = push!(rec, p615f_row(…))` becomes `(push!(rec, p615f_row(…)); o1_save(integ, c, seed); rec)`
function _extend_record!(ex)
    ex isa Expr || return 0
    if ex.head === :(=) && ex.args[1] == :(record(integ))
        ex.args[2] = Expr(:block, :(local out = $(ex.args[2])), :(o1_save(integ, c, seed)), :out)
        return 1
    end
    return sum(_extend_record!, ex.args; init = 0)
end
let def = RUN_DEF[]
    def === nothing && error("run_o1: no p615f_run in $(TEST)")
    _extend_record!(def) == 1 || error("run_o1: p615f_run's `record(integ) = …` not found exactly once")
    def.args[1].args[1] === :p615f_run || error("run_o1: unexpected p615f_run signature")
    def.args[1].args[1] = :o1_run
    Core.eval(@__MODULE__, def)
end

const STAGE = Ref("")
# one O1 file per save; `c` carries the case name (`c.case`), added by `run_job`
function o1_save(integ, c, seed)
    fr = PottsModels.openvt_frame(integ.u; β = c.beta, γ = c.gamma)
    dir = mkpath(joinpath(STAGE[], "centroids", c.case))
    write_openvt(joinpath(dir, openvt_filename(:O1; c.case, seed, mcs = Int(integ.t))), :O1, fr)
    return nothing
end

# ---- the P6.15f record ---------------------------------------------------------------------------
function record_dir(item)
    ds = [d for d in sort(readdir(DATA))
          if isfile(joinpath(DATA, d, "provenance.toml")) &&
             get(TOML.parsefile(joinpath(DATA, d, "provenance.toml")), "item", "") == item]
    isempty(ds) && error("run_o1: no $item record in $(DATA)")
    return joinpath(DATA, last(ds))
end
const F3F8 = record_dir("P6.15f")
const F5 = record_dir("P6.15e")
const TS = p615f_tsv(joinpath(F3F8, "timeseries.tsv"))
const RUNS3 = p615f_tsv(joinpath(F3F8, "runs.tsv"))
const NB3 = p615f_tsv(joinpath(F3F8, "neighbors.tsv"))
const RUNS5 = p615f_tsv(joinpath(F5, "runs.tsv"))
# (case, seed) => the record's saves as (mcs, N, r, A, C, w, g)
function record_rows(case, seed)
    rr = [r for r in TS if r["case"] == case && parse(Int, r["seed"]) == seed]
    return sort([(parse(Int, r["mcs"]), parse(Int, r["N"]), p615f_f64(r["r"]), p615f_f64(r["A"]), p615f_f64(r["C"]),
                     p615f_f64(r["w"]), p615f_f64(r["g"])) for r in rr]; by = first)
end
# the differences between a run's series and the record's rows (empty when equal, NaN = NaN)
function series_diff(s, want)
    got = [(round(Int, s.t[j] * P615F_CYCLE), s.N[j], s.r[j], s.A[j], s.C[j], s.w[j], s.g[j]) for j in eachindex(s.t)]
    out = String[]
    length(got) == length(want) || push!(out, "$(length(got)) saves, the record $(length(want))")
    for (a, b) in zip(got, want)
        all(isequal(x, y) for (x, y) in zip(a, b)) || (push!(out, "save $(a) ≠ record $(b)"); length(out) > 5 && break)
    end
    return out
end

# ---- the runs ------------------------------------------------------------------------------------
const CASE_ORDER = (:a, :e, :f, :b)                    # the large lattices first (load balance)
const LATTICES = Dict(c.L => maximum(d.cells for d in values(P615F_CASES) if d.L == c.L) for c in values(P615F_CASES))
probs = Dict(L => p615f_problem(L, cells) for (L, cells) in LATTICES)
function run_job(case, k; tmax = nothing)
    c = merge(P615F_CASES[case], (; case = string(case)))
    seed = c.seed(k)
    wall = @elapsed r = o1_run(probs[c.L], seed, c; tmax)
    want = record_rows(c.case, seed)
    tmax === nothing || (want = want[1:min(end, length(r.series.t))])     # the smoke check's prefix
    diff = series_diff(r.series, want)
    fr = PottsModels.openvt_frame(r.u; β = c.beta, γ = c.gamma)
    return (; case = c.case, k, seed, r.retcode, mcs = Int(r.mcs), N = r.series.N[end], saves = length(r.series.t), wall,
        diff, n = fr.n, x = fr.x, y = fr.y, o2 = case === :b ? PottsModels.openvt_snapshot(r.u) : nothing)
end

const BULK = abspath(get(ENV, "OPENVT_PACKAGE_BULK", ""))
function in_git(path)
    d = abspath(path)
    while true
        ispath(joinpath(d, ".git")) && return true
        p = dirname(d)
        p == d && return false
        d = p
    end
end

if SMOKE
    STAGE[] = mktempdir()
    o1_run(probs[400], 1, merge(P615F_CASES.b, (; L = 400, case = "warmup")); cells = 2, tmax = 50)
    r = run_job(:b, 1; tmax = 780)
    files = readdir(joinpath(STAGE[], "centroids", "b"))
    @info "smoke" r.seed r.saves files = length(files) wall = round(r.wall; digits = 1) diff = r.diff
    (isempty(r.diff) && length(files) == r.saves == 21) || error("run_o1 smoke: the re-run differs from the record")
    println("smoke OK: 21 saves of case (b) seed $(r.seed) equal the record")
    exit(0)
end

(haskey(ENV, "OPENVT_PACKAGE_BULK") && !isempty(ENV["OPENVT_PACKAGE_BULK"])) ||
    error("run_o1: set OPENVT_PACKAGE_BULK to a directory outside git")
in_git(BULK) && error("run_o1: the bulk directory $(BULK) is inside a git checkout")
mkpath(BULK)
STAGE[] = abspath(get(ENV, "OPENVT_O1_STAGE", joinpath(BULK, "o1-stage")))
(isdir(STAGE[]) && !isempty(readdir(STAGE[]))) && error("run_o1: the staging directory $(STAGE[]) is not empty")
in_git(STAGE[]) && error("run_o1: the staging directory $(STAGE[]) is inside a git checkout")
mkpath(STAGE[])

# compile both lattices (results discarded, outside the staging directory)
let s = STAGE[]
    STAGE[] = mktempdir()
    for L in keys(probs)
        o1_run(probs[L], 1, merge(P615F_CASES.b, (; L, case = "warmup")); cells = 2, tmax = 50)
    end
    STAGE[] = s
end
jobs = [(case, k) for case in CASE_ORDER for k in 1:P615F_CASES[case].runs]
res = Vector{Any}(undef, length(jobs))
sim_s = @elapsed Threads.@threads :greedy for j in eachindex(jobs)
    res[j] = run_job(jobs[j]...)
    r = res[j]
    @info "run" r.case r.k r.seed r.retcode r.mcs r.N r.saves wall = round(r.wall; digits = 1) same = isempty(r.diff)
end

# ---- the record reproduced? -------------------------------------------------------------------------
bad = String[]
for r in res
    isempty(r.diff) || push!(bad, "($(r.case)) seed $(r.seed): " * join(r.diff, "; "))
    r3 = only(x for x in RUNS3 if x["case"] == r.case && parse(Int, x["seed"]) == r.seed)
    (string(r.mcs) == r3["mcs"] && string(r.N) == r3["N"] && string(r.saves) == r3["saves"]) ||
        push!(bad, "($(r.case)) seed $(r.seed): stop $(r.mcs), N $(r.N), $(r.saves) saves ≠ runs.tsv")
    nb = [x for x in NB3 if x["case"] == r.case && parse(Int, x["seed"]) == r.seed]
    isempty(nb) && continue
    want = Dict(parse(Int, x["n"]) => parse(Int, x["count"]) for x in nb)
    got = Dict(n => count(==(n), r.n) for n in unique(r.n))
    got == want || push!(bad, "($(r.case)) seed $(r.seed): final neighbour histogram ≠ neighbors.tsv")
end
isempty(bad) || error("run_o1: the re-run does not reproduce the P6.15f record (the staged files are kept):\n" *
                      join(first(bad, 40), "\n"))

# ---- O2 (case (b) at 1000 cells) -----------------------------------------------------------------------
const O2HEAD = "Potts.jl_5T_MonolayerGrowth_1000_Data"
const O2DIR = joinpath(BULK, O2HEAD)
o2name(k) = "cell_data_no_inhibition_$(k).csv"
resb = Dict(r.k => r for r in res if r.case == "b")
runs5 = Dict(parse(Int, x["k"]) => x for x in RUNS5 if x["case"] == "b")
# an O2 file agrees with the F5 record (cell count, f = 0 count) and with this re-run's stop (x, y)
function o2_ok(path, k)
    o = read_openvt(path, :O2)
    r, r5 = resb[k], runs5[k]
    return length(o.x) == parse(Int, r5["N"]) == length(r.x) && count(==(0.0), o.f) == parse(Int, r5["n_f0"]) &&
           o.x == r.x && o.y == r.y
end
o2_source = "re-run stop states (openvt_snapshot, write_openvt :O2)"
rm(O2DIR; recursive = true, force = true)
mkpath(O2DIR)
f5dir = get(ENV, "F5_O2_DIR", "")
if !isempty(f5dir)
    src = isfile(joinpath(f5dir, o2name(1))) ? f5dir : joinpath(f5dir, O2HEAD)
    if all(k -> isfile(joinpath(src, o2name(k))), keys(resb)) && all(k -> o2_ok(joinpath(src, o2name(k)), k), keys(resb))
        foreach(k -> cp(joinpath(src, o2name(k)), joinpath(O2DIR, o2name(k))), keys(resb))
        o2_source = "the P6.15e runner's files (F5_O2_DIR), checked against this re-run"
    else
        @warn "F5_O2_DIR files missing or not equal to the re-run; writing O2 from the re-run" src
    end
end
if !isfile(joinpath(O2DIR, o2name(1)))
    for (k, r) in resb
        write_openvt(joinpath(O2DIR, o2name(k)), :O2, r.o2)
    end
end
all(k -> o2_ok(joinpath(O2DIR, o2name(k)), k), keys(resb)) || error("run_o1: the O2 files fail their checks")

# ---- manifests, archives ----------------------------------------------------------------------------
sha(path) = bytes2hex(open(sha256, path))
# rows, code counts and sha256 of one O1 file
function o1_scan(path)
    buf = read(path)
    ls = split(String(copy(buf)), '\n'; keepempty = false)
    ls[1] == "x,y,i,n" || error("run_o1: $path: header $(ls[1])")
    cnt = zeros(Int, 4)
    for l in @view ls[2:end]
        cnt[parse(Int, split(l, ',')[3]) + 1] += 1
    end
    return (; rows = length(ls) - 1, bytes = length(buf), i = cnt, sha = bytes2hex(sha256(buf)))
end
o1 = Tuple{String, Int, Int, String}[]               # case, seed, mcs, member
for r in res
    for f in readdir(joinpath(STAGE[], "centroids", r.case))
        m = match(r"^potts_([a-z]+)_s(\d+)_(\d{6})\.csv$", f)
        (m !== nothing && m.captures[1] == r.case) || error("run_o1: stray staged file $f")
        parse(Int, m.captures[2]) == r.seed || continue
        push!(o1, (r.case, r.seed, parse(Int, m.captures[3]), "centroids/$(r.case)/$f"))
    end
end
sort!(o1; by = last)
length(o1) == sum(r.saves for r in res) || error("run_o1: $(length(o1)) O1 files for $(sum(r.saves for r in res)) saves")
scans = Vector{Any}(undef, length(o1))
Threads.@threads for j in eachindex(o1)
    scans[j] = o1_scan(joinpath(STAGE[], o1[j][4]))
end
# each file's rows and growing share are the record's N and g at that save
want = Dict((x["case"], parse(Int, x["seed"]), parse(Int, x["mcs"])) => x for x in TS)
for (e, s) in zip(o1, scans)
    w = want[(e[1], e[2], e[3])]
    (s.rows == parse(Int, w["N"]) && isequal(s.i[1] / s.rows, p615f_f64(w["g"]))) ||
        error("run_o1: $(e[4]): $(s.rows) rows, i = 0 share $(s.i[1] / s.rows); the record N $(w["N"]), g $(w["g"])")
end

const CASES = sort(unique(first.(o1)))
zipname(case) = "Potts.jl_centroids_$(case).zip"
for case in CASES
    z = joinpath(BULK, zipname(case))
    rm(z; force = true)
    sh = "find centroids/$case -type f | LC_ALL=C sort | zip -X -D -9 -q -@ " * Base.shell_escape(z)
    run(Cmd(`sh -c $sh`; dir = STAGE[]))
    members = [e[4] for e in o1 if e[1] == case]
    readlines(`unzip -Z1 $z`) == members || error("run_o1: $(zipname(case)): members differ from the manifest")
end

function tsv(path, header, rows)
    open(path, "w") do io
        println(io, join(header, '\t'))
        foreach(r -> println(io, join(r, '\t')), rows)
    end
end
tsv(joinpath(DIR, "runs.tsv"), ("case", "k", "seed", "mcs", "N", "saves"),
    sort([(r.case, r.k, r.seed, r.mcs, r.N, r.saves) for r in res]; by = r -> (r[1], r[2])))
tsv(joinpath(DIR, "o1_manifest.tsv"), ("case", "seed", "mcs", "file", "rows", "bytes", "i0", "i1", "i2", "i3", "sha256"),
    [(e[1], e[2], e[3], e[4], s.rows, s.bytes, s.i..., s.sha) for (e, s) in zip(o1, scans)])
tsv(joinpath(DIR, "archives.tsv"), ("case", "archive", "members", "bytes", "sha256"),
    [(c, zipname(c), count(e -> e[1] == c, o1), filesize(joinpath(BULK, zipname(c))), sha(joinpath(BULK, zipname(c))))
     for c in CASES])
tsv(joinpath(DIR, "o2_manifest.tsv"), ("k", "file", "rows", "bytes", "sha256"),
    [(k, "$(O2HEAD)/$(o2name(k))", length(resb[k].x), filesize(joinpath(O2DIR, o2name(k))), sha(joinpath(O2DIR, o2name(k))))
     for k in sort(collect(keys(resb)))])

finished = now()
git(args...) = readchomp(Cmd(`git $args`; dir = ROOT))
manifest = joinpath(ROOT, "Manifest.toml")
open(joinpath(DIR, "provenance.toml"), "w") do io
    TOML.print(io,
        Dict(
            "commit" => git("rev-parse", "HEAD"), "commit_date" => git("log", "-1", "--format=%cs"),
            "dirty_tracked" => !isempty(git("status", "--porcelain", "--untracked-files=no")),
            "test" => "lib/PottsModels/test/reproductions/15_openvt_f3_f8.jl", "test_sha256" => sha(TEST),
            "package_test" => "lib/PottsModels/test/reproductions/15_openvt_package.jl", "package_test_sha256" => sha(PKGTEST),
            "reproduces" => basename(F3F8), "runner" => relpath(@__FILE__, ROOT), "runner_sha256" => sha(@__FILE__),
            "manifest_sha256" => isfile(manifest) ? sha(manifest) : "missing",
            "julia" => string(VERSION), "threads" => Threads.nthreads(), "machine" => Sys.MACHINE,
            "cpu" => Sys.cpu_info()[1].model, "affinity" => get(ENV, "POTTS_AFFINITY", ""),
            "seeds" => join(("($c) $(P615F_CASES[c].seed(1))–$(P615F_CASES[c].seed(P615F_CASES[c].runs))" for c in CASE_ORDER),
                "; "),
            "o1_files" => length(o1), "o1_rows" => sum(s.rows for s in scans), "o1_bytes" => sum(s.bytes for s in scans),
            "o1_zip_bytes" => sum(filesize(joinpath(BULK, zipname(c))) for c in CASES), "o2_source" => o2_source,
            "started" => string(started), "finished" => string(finished),
            "wall_s" => round(Dates.value(finished - started) / 1000; digits = 1), "simulation_s" => round(sim_s; digits = 1),
            "cpu_s_runs" => round(sum(r.wall for r in res); digits = 1),
            "item" => "P6.15j", "decisions" => ["D-146", "D-204", "D-206"]);
        sorted = true)
end
@info "done" wall_s = Dates.value(finished - started) / 1000 sim_s files = length(o1) zips = [zipname(c) for c in CASES]

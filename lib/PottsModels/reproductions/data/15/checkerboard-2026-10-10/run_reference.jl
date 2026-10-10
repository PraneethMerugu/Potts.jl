# P6.15m m3 (pre-step; D-218): the CPU SequentialCPM replay of every P6.15f seed of cases
# (a), (b) and (f), with the division and live counts the `lost` metric needs
# (lost = divisions + 1 − live). Writes `reference_runs.tsv` (case k seed mcs N divisions
# live) into this directory, the schema of the frozen test
# `lib/PottsModels/test/reproductions/15_openvt_checkerboard.jl`.
#
# The protocol, seeds and recorder are the frozen F3/F8 test's
# `lib/PottsModels/test/reproductions/15_openvt_f3_f8.jl`, evaluated from its source as the
# P6.15f and O1 runners do: every top-level `P615F_*` constant and `p615f_*` function of that
# file is loaded verbatim. `p615f_run` is loaded a second time as `ref_run`, with one change
# made to its parsed source: its returned named tuple also carries `stats = sol.stats` (the
# lifecycle counts). The run itself is unchanged, so this is the P6.15f run (D-029: same seed,
# same backend). Each run's series is checked against the P6.15f timeseries.tsv save by save
# (MCS, N, r, A, C, w, g, exactly), and its stop MCS and N against the P6.15f runs.tsv;
# `live` (cells with volume > 0 at the stop) must equal N. Any difference fails the collect
# step, and nothing is written.
#
# Two steps, so that the runs can be spread over single-threaded processes:
#
#     # run jobs (case:k ...) in this process; one row per job appended to <part.tsv>
#     taskset -c <core> julia -t 1 --project=lib/PottsModels/test \
#         lib/PottsModels/reproductions/data/15/checkerboard-2026-10-10/run_reference.jl job <part.tsv> a:1 b:7 …
#     # check every part against the P6.15f record and write reference_runs.tsv here
#     julia --project=lib/PottsModels/test \
#         lib/PottsModels/reproductions/data/15/checkerboard-2026-10-10/run_reference.jl collect <part.tsv> …
#
# `include`d (not run as the program) it only defines `ref_job`, `ref_jobs`, `ref_check`,
# `ref_write` and the loaded P6.15f definitions, for the m3 main runner to call.
using Potts, PottsModels
using Potts: CorePotts
using Statistics: mean

const REF_DIR = @__DIR__
const REF_ROOT = normpath(joinpath(REF_DIR, "..", "..", "..", "..", "..", ".."))
const REF_TEST = joinpath(REF_ROOT, "lib", "PottsModels", "test", "reproductions", "15_openvt_f3_f8.jl")
const REF_F3F8 = normpath(joinpath(REF_DIR, "..", "f3-f8-2026-10-08"))   # P615M_SEQ_REF
const REF_CASES = (:a, :b, :f)
const REF_HEADER = ("case", "k", "seed", "mcs", "N", "divisions", "live")

# ---- the frozen F3/F8 test's constants and rules, verbatim -------------------------------------
_refdefname(ex) = ex isa Expr && ex.head === :const ? _refdefname(ex.args[1]) :
                  ex isa Expr && ex.head in (:(=), :function) ? (a = ex.args[1]; a isa Symbol ? a :
                                                                 a isa Expr && a.head === :call ? a.args[1] :
                                                                 a isa Expr && a.head === :where ? a.args[1].args[1] :
                                                                 nothing) : nothing
const REF_RUN_DEF = Ref{Any}(nothing)
for ex in Meta.parseall(read(REF_TEST, String)).args
    ex isa Expr || continue
    n = _refdefname(ex)
    (n isa Symbol && startswith(string(n), r"p615f_|P615F_")) || continue
    isdefined(@__MODULE__, n) || Core.eval(@__MODULE__, ex)
    n === :p615f_run && (REF_RUN_DEF[] = deepcopy(ex))
end

# ---- p615f_run returning the solution's stats too ------------------------------------------------
# `return (; retcode = …, u = sol.u[end])` becomes `return merge((; retcode = …), (; stats = sol.stats))`
function _ref_extend_return!(ex)
    ex isa Expr || return 0
    if ex.head === :return
        ex.args[1] = :(merge($(ex.args[1]), (; stats = sol.stats)))
        return 1
    end
    return sum(_ref_extend_return!, ex.args; init = 0)
end
let def = REF_RUN_DEF[]
    def === nothing && error("run_reference: no p615f_run in $(REF_TEST)")
    _ref_extend_return!(def) == 1 || error("run_reference: p615f_run has not exactly one `return`")
    def.args[1].args[1] === :p615f_run || error("run_reference: unexpected p615f_run signature")
    def.args[1].args[1] = :ref_run
    Core.eval(@__MODULE__, def)
end

# ---- one replay --------------------------------------------------------------------------------------
const REF_PROBS = Dict{Int, Any}()
ref_problem(L) = get!(() -> p615f_problem(L, maximum(d.cells for d in values(P615F_CASES) if d.L == L)), REF_PROBS, L)
# compile a lattice's run (result discarded)
ref_warmup(L) = (ref_run(ref_problem(L), 1, merge(P615F_CASES.b, (; L)); cells = 2, tmax = 50); nothing)

# the P6.15f saves of one run as (mcs, N, r, A, C, w, g)
const REF_TS = Ref{Any}(nothing)
function ref_record_rows(case, seed)
    REF_TS[] === nothing && (REF_TS[] = p615f_tsv(joinpath(REF_F3F8, "timeseries.tsv")))
    rr = [r for r in REF_TS[] if r["case"] == case && parse(Int, r["seed"]) == seed]
    return sort([(parse(Int, r["mcs"]), parse(Int, r["N"]), p615f_f64(r["r"]), p615f_f64(r["A"]), p615f_f64(r["C"]),
                     p615f_f64(r["w"]), p615f_f64(r["g"])) for r in rr]; by = first)
end
# the number of saves that differ from the record (NaN = NaN), and a count mismatch as one more
function ref_series_diff(s, want)
    got = [(round(Int, s.t[j] * P615F_CYCLE), s.N[j], s.r[j], s.A[j], s.C[j], s.w[j], s.g[j]) for j in eachindex(s.t)]
    return (length(got) != length(want)) + count(((a, b),) -> !all(isequal(x, y) for (x, y) in zip(a, b)), zip(got, want))
end

"""Replay run `k` of `case` (P6.15f's seed, protocol and SequentialCPM) and count its divisions."""
function ref_job(case::Symbol, k::Integer)
    c = P615F_CASES[case]
    seed = c.seed(k)
    wall = @elapsed r = ref_run(ref_problem(c.L), seed, c)
    live = count(>(0), Array(r.u.cell.volume))
    return (; case = string(case), k = Int(k), seed, retcode = r.retcode, mcs = Int(r.mcs), N = r.series.N[end],
        divisions = r.stats.lifecycle.divisions, live, saves = length(r.series.t),
        series_diff = ref_series_diff(r.series, ref_record_rows(string(case), seed)), wall)
end
"""Every (case, k) of the replay: all P6.15f runs of cases a, b and f."""
ref_jobs() = [(case, k) for case in REF_CASES for k in 1:P615F_CASES[case].runs]

# ---- check and write ---------------------------------------------------------------------------------
const REF_PART_HEADER = ("case", "k", "seed", "retcode", "mcs", "N", "divisions", "live", "saves", "series_diff", "wall_s")
"""Problems of the replay rows against the P6.15f runs.tsv (empty when it is the record's runs)."""
function ref_check(rows)
    runs3 = [r for r in p615f_tsv(joinpath(REF_F3F8, "runs.tsv")) if Symbol(r["case"]) in REF_CASES]
    bad = String[]
    key(r) = (string(r.case), Int(r.seed))
    got = Dict(key(r) => r for r in rows)
    length(got) == length(rows) || push!(bad, "duplicate runs")
    want = Set((r["case"], parse(Int, r["seed"])) for r in runs3)
    Set(keys(got)) == want || push!(bad, "runs differ from P6.15f's: missing $(setdiff(want, keys(got))), extra $(setdiff(keys(got), want))")
    for x in runs3
        r = get(got, (x["case"], parse(Int, x["seed"])), nothing)
        r === nothing && continue
        id = "($(x["case"])) seed $(x["seed"])"
        (string(r.k) == x["k"] && string(r.retcode) == x["retcode"] && string(r.mcs) == x["mcs"] &&
         string(r.N) == x["N"] && string(r.saves) == x["saves"]) ||
            push!(bad, "$id: k $(r.k) $(r.retcode) stop $(r.mcs) N $(r.N) saves $(r.saves) ≠ runs.tsv")
        r.series_diff == 0 || push!(bad, "$id: $(r.series_diff) saves differ from timeseries.tsv")
        r.live == r.N || push!(bad, "$id: live $(r.live) ≠ N $(r.N)")
        r.divisions + 1 >= r.live || push!(bad, "$id: divisions $(r.divisions) + 1 < live $(r.live)")
    end
    return bad
end
function ref_write(path, rows)
    open(path, "w") do io
        println(io, join(REF_HEADER, '\t'))
        for r in sort(collect(rows); by = r -> (string(r.case), r.k))
            println(io, join((r.case, r.k, r.seed, r.mcs, r.N, r.divisions, r.live), '\t'))
        end
    end
    return path
end

# ---- the program ---------------------------------------------------------------------------------------
function ref_main(args)
    mode = isempty(args) ? "" : args[1]
    if mode == "job"
        part, specs = args[2], args[3:end]
        jobs = [(Symbol(a), parse(Int, b)) for (a, b) in split.(specs, ':')]
        all(j -> j[1] in REF_CASES && 1 <= j[2] <= P615F_CASES[j[1]].runs, jobs) || error("run_reference: bad job in $specs")
        foreach(ref_warmup, unique(P615F_CASES[c].L for (c, _) in jobs))
        isfile(part) || open(io -> println(io, join(REF_PART_HEADER, '\t')), part, "w")
        for (c, k) in jobs
            r = ref_job(c, k)
            open(part, "a") do io
                println(io, join((r.case, r.k, r.seed, r.retcode, r.mcs, r.N, r.divisions, r.live, r.saves, r.series_diff,
                        round(r.wall; digits = 1)), '\t'))
            end
            @info "run" r.case r.k r.seed r.retcode r.mcs r.N r.divisions r.live lost = r.divisions + 1 - r.live same = r.series_diff == 0 wall = round(r.wall; digits = 1)
        end
    elseif mode == "collect"
        rows = [(; case = x["case"], k = parse(Int, x["k"]), seed = parse(Int, x["seed"]), retcode = x["retcode"],
                    mcs = parse(Int, x["mcs"]), N = parse(Int, x["N"]), divisions = parse(Int, x["divisions"]),
                    live = parse(Int, x["live"]), saves = parse(Int, x["saves"]), series_diff = parse(Int, x["series_diff"]),
                    wall = parse(Float64, x["wall_s"])) for p in args[2:end] for x in p615f_tsv(p)]
        bad = ref_check(rows)
        isempty(bad) || error("run_reference: the replay is not the P6.15f record:\n" * join(first(bad, 40), "\n"))
        out = ref_write(joinpath(REF_DIR, "reference_runs.tsv"), rows)
        for c in REF_CASES
            rc = [r for r in rows if r.case == string(c)]
            lost = [r.divisions + 1 - r.live for r in rc]
            @info "case $c" runs = length(rc) lost_mean = mean(lost) lost_min = minimum(lost) lost_max = maximum(lost) cpu_s = sum(r.wall for r in rc)
        end
        println("reference_runs.tsv: $(length(rows)) runs equal the P6.15f record (stop MCS, N, saves, series) -> $out")
    else
        error("run_reference: usage: run_reference.jl job <part.tsv> <case:k>... | collect <part.tsv>...")
    end
end
abspath(PROGRAM_FILE) == abspath(@__FILE__) && ref_main(ARGS)

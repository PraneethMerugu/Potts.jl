# P6.15f: the D-146 offline record of OpenVT Fig 3 ("Comparing monolayer growth over time":
# deterministic case (f), stochastic case (b)) and Fig 8 / V5 (cases (a) and (e)), with the
# γ = 10⁻⁴ negative control (spec 15 §4.0.1, §3.1 O1, §3.2, §4.0.2 F3/F8, §4.1 V5; D-173).
#
# The protocol, seeds, recorder and rules are the frozen test's
# `lib/PottsModels/test/reproductions/15_openvt_f3_f8.jl`, evaluated from its source: every
# top-level `P615F_*` constant and `p615f_*` function of that file (no testset, no SMOKE or
# FULL block) is loaded verbatim, so this runner cannot drift from it. Its sha256 is in
# `provenance.toml`. The test's record tier recomputes every verdict from the TSVs written here.
#
# Writes into this directory: runs.tsv, timeseries.tsv, neighbors.tsv (the frozen schema),
# verdicts.tsv, meta.toml, provenance.toml. `deviations.tsv` and the README are written by
# hand after the run (D-154).
#
#     POTTS_AFFINITY="taskset -c 0-11,16-27" taskset -c 0-11,16-27 julia -t 12 \
#         --project=lib/PottsModels/test lib/PottsModels/reproductions/data/15/f3-f8-2026-10-08/run_f3_f8.jl
using Potts, PottsModels, Test
using Potts: CorePotts
using Statistics: mean
using Dates, TOML, SHA, Serialization

const started = now()
const DIR = @__DIR__
const ROOT = normpath(joinpath(DIR, "..", "..", "..", "..", "..", ".."))
const TEST = joinpath(ROOT, "lib", "PottsModels", "test", "reproductions", "15_openvt_f3_f8.jl")

# ---- the frozen test's constants and rules, verbatim ---------------------------------------------
_defname(ex) = ex isa Expr && ex.head === :const ? _defname(ex.args[1]) :
               ex isa Expr && ex.head in (:(=), :function) ? (a = ex.args[1]; a isa Symbol ? a :
                                                              a isa Expr && a.head === :call ? a.args[1] :
                                                              a isa Expr && a.head === :where ? a.args[1].args[1] :
                                                              nothing) : nothing
for ex in Meta.parseall(read(TEST, String)).args
    ex isa Expr || continue
    n = _defname(ex)
    (n isa Symbol && startswith(string(n), r"p615f_|P615F_")) || continue
    Core.eval(@__MODULE__, ex)
end

const CASE_ORDER = (:a, :e, :f, :b, :control)          # the large lattices first (load balance)

# ---- the runs -----------------------------------------------------------------------------------------
# one problem per lattice (400², 1400²), sized for the largest stop count on it, as in the test
const LATTICES = Dict(c.L => maximum(d.cells for d in values(P615F_CASES) if d.L == c.L) for c in values(P615F_CASES))
probs = Dict(L => p615f_problem(L, cells) for (L, cells) in LATTICES)
# closest approach of a cell to the lattice edge (sites)
function edge_gap(σ)
    L1, L2 = size(σ)
    return minimum(min(I[1] - 1, I[2] - 1, L1 - I[1], L2 - I[2]) for I in findall(!=(0), σ))
end
function run_job(case, k)
    c = P615F_CASES[case]
    seed = c.seed(k)
    wall = @elapsed r = p615f_run(probs[c.L], seed, c)
    σ = Array(r.u.σ)
    n = case in (:a, :e) ? PottsModels.openvt_frame(r.u; β = c.beta, γ = c.gamma).n : Int[]
    return (; case = string(case), k, seed, r.retcode, r.mcs, r.series, n, wall, gap = edge_gap(σ))
end
# F3F8_CACHE (debugging only): a path where the run results are serialized after the runs, and
# read back instead of rerunning when it exists. A record is made without it (provenance says so).
const CACHE = get(ENV, "F3F8_CACHE", "")
const CACHED = !isempty(CACHE) && isfile(CACHE)
# compile both lattices (results discarded)
if !CACHED
    for L in keys(probs)
        p615f_run(probs[L], 1, merge(P615F_CASES.b, (; L)); cells = 2, tmax = 50)
    end
end
jobs = [(case, k) for case in CASE_ORDER for k in 1:P615F_CASES[case].runs]
res = Vector{Any}(undef, length(jobs))
if CACHED
    res = deserialize(CACHE)
    sim_s = NaN
else
    # :greedy hands out one job at a time (:dynamic splits the list into nthreads contiguous
    # chunks, which put all 20 large runs on one thread)
    sim_s = @elapsed Threads.@threads :greedy for j in eachindex(jobs)
        res[j] = run_job(jobs[j]...)
        r = res[j]
        @info "run" r.case r.k r.seed r.retcode r.mcs N = r.series.N[end] wall = round(r.wall; digits = 1) gap = r.gap
    end
end
!isempty(CACHE) && !CACHED && serialize(CACHE, res)
cfg(r) = P615F_CASES[Symbol(r.case)]

# ---- outputs ----------------------------------------------------------------------------------------
f64(x) = isnan(x) ? "nan" : repr(Float64(x))
open(joinpath(DIR, "runs.tsv"), "w") do io
    println(io, join(("case", "k", "seed", "beta", "gamma", "sigma_X", "lattice", "retcode", "mcs", "N", "cycles",
        "saves", "edge_gap_px", "wall_s"), '\t'))
    for r in res
        println(io, join((r.case, r.k, r.seed, cfg(r).beta, cfg(r).gamma, cfg(r).sigma_X, cfg(r).L, r.retcode, Int(r.mcs),
            r.series.N[end], round(r.mcs / P615F_CYCLE; digits = 6), length(r.series.t), r.gap, round(r.wall; digits = 2)), '\t'))
    end
end
open(joinpath(DIR, "timeseries.tsv"), "w") do io
    println(io, join(("case", "seed", "mcs", "N", "r", "A", "C", "w", "g"), '\t'))
    for r in res, j in eachindex(r.series.t)
        s = r.series
        println(io, join((r.case, r.seed, round(Int, s.t[j] * P615F_CYCLE), s.N[j], f64(s.r[j]), f64(s.A[j]), f64(s.C[j]),
            f64(s.w[j]), f64(s.g[j])), '\t'))
    end
end
open(joinpath(DIR, "neighbors.tsv"), "w") do io
    println(io, join(("case", "seed", "n", "count"), '\t'))
    for r in res
        isempty(r.n) && continue
        for n in sort(unique(r.n))
            println(io, join((r.case, r.seed, n, count(==(n), r.n)), '\t'))
        end
    end
end

# the verdicts, from the TSVs just written (as the test's record tier reads them)
ts = p615f_tsv(joinpath(DIR, "timeseries.tsv"))
S = Dict(string(case) => [p615f_cut(s, P615F_CASES[case].cells) for s in values(p615f_record_series(ts, string(case)))]
         for case in CASE_ORDER)
nb = p615f_tsv(joinpath(DIR, "neighbors.tsv"))
na = [r for r in nb if r["case"] == "a"]
nn = sort(unique(parse(Int, r["n"]) for r in na))
nb_a = (; n = nn, count = [sum(parse(Int, r["count"]) for r in na if parse(Int, r["n"]) == n) for n in nn])
ver = p615f_verdicts(S, nb_a)
# the same from the in-memory series (a check on the TSV round trip)
S_mem = Dict(string(case) => [p615f_cut(r.series, P615F_CASES[case].cells) for r in res if r.case == string(case)]
             for case in CASE_ORDER)
ver_mem = p615f_verdicts(S_mem, nb_a)
# (equal up to summation order: the TSV series are read back in seed-hash order)
all(k -> isapprox(Float64[ver[k][1]...], Float64[ver_mem[k][1]...]; rtol = 1e-12) && ver[k][2] == ver_mem[k][2],
    keys(ver)) ||
    @warn "the TSV round trip changed a verdict" ver ver_mem

# statistics for the verdict table
ST = Dict(c => p615f_stats(S[c], P615F_CASES[Symbol(c)].cells) for c in keys(S))
B = P615F_BAND
r4(x) = string(round(x; sigdigits = 4))
NAME = Dict("F3.1" => "max |L − L_TST| on t = 0.5:1:8.5 (log₂ N)", "F3.2" => "t̄_s / t̄_s,TST (time to 1000 cells)",
    "F3.3" => "max |r̄/r̄_TST − 1| on t = 4.5:1:8.5 and at the end", "F3.4" => "max |Ā/Ā_TST − 1| on t = 4.5:1:8.5 and at the end",
    "F3.5" => "min over k = 0:3 of sync(k)", "V5.1" => "slope of L on t = 4.5:1:8.5", "V5.2" => "max |L − t| on t = 0.5:1:8.5",
    "F8.1" => "min g over every save", "F8.2" => "min C/(2√(πA)); min w (saves with N ≥ 3)",
    "F8.3" => "mean n, pooled final histogram", "F8.4" => "mean g at the 10⁴-cell stop")
BANDS = Dict("F3.1" => "≤ $(B.logN)", "F3.2" => "[$(B.t_stop[1]), $(B.t_stop[2])]", "F3.3" => "≤ $(B.r)",
    "F3.4" => "≤ $(B.A)", "F3.5" => "≥ $(B.sync)", "V5.1" => "[$(B.slope[1]), $(B.slope[2])]", "V5.2" => "≤ $(B.offset)",
    "F8.1" => "== 1", "F8.2" => "≥ 1 − 1e-9; ≥ 0", "F8.3" => "[$(r4(B.nmean[1])), $(r4(B.nmean[2]))]",
    "F8.4" => "[$(r4(B.g_stop[1])), $(r4(B.g_stop[2]))]")
function reference(id, case)
    ref = case == "f" ? P615F_TST.f : P615F_TST.b
    tst = case == "f" ? "TST No_CI deterministic" : "TST No_CI stochastic"
    id == "F3.1" && return "$tst: L = $(join(r4.(ref.L), ", "))"
    id == "F3.2" && return "$tst: t̄_s = $(r4(ref.t_stop)) cycles"
    id == "F3.3" && return "$tst: r̄ = $(join(r4.(ref.r), ", ")); r̄_e = $(r4(ref.r_stop))"
    id == "F3.4" && return "$tst: Ā = $(join(r4.(ref.A), ", ")); Ā_e = $(r4(ref.A_stop))"
    id == "F3.5" && return "$tst: sync = $(join(r4.(ref.sync), ", "))"
    id == "V5.1" && return "TST No_CI: slope 1.000 (det.), $(r4(P615F_TST.b.slope)) (stoch.)"
    id == "V5.2" && return "TST No_CI: offset 0.5 (det.), $(r4(P615F_TST.b.offset)) (stoch.)"
    id == "F8.1" && return "β = γ = 0: every cell grows"
    id == "F8.2" && return "isoperimetric inequality"
    id == "F8.3" && return "legacy CompuCell3D $(r4(P615F_LEGACY.nmean[1])), Morpheus $(r4(P615F_LEGACY.nmean[2])) (β = 0.8, D4)"
    id == "F8.4" && return "legacy CompuCell3D $(r4(P615F_LEGACY.g_stop[1])), Morpheus $(r4(P615F_LEGACY.g_stop[2])) (β = 0.8, D4)"
end
fmtv(v::Tuple) = join((r4(x) for x in v), "; ")
fmtv(v) = r4(v)
open(joinpath(DIR, "verdicts.tsv"), "w") do io
    println(io, join(("target", "case", "paper", "ours", "band", "result"), '\t'))
    for pair in [P615F_PAIRS; P615F_CONTROL_PAIRS]
        id, case = pair
        v, ok = ver[pair]
        isctl = pair in P615F_CONTROL_PAIRS
        band = isctl ? "$(BANDS[id]) (control: must FAIL)" : BANDS[id]
        println(io, join(("$id $(NAME[id])", case, reference(id, case), fmtv(v), band, ok ? "PASS" : "FAIL"), '\t'))
    end
    ctl_ok = all(p -> !ver[p][2], P615F_CONTROL_PAIRS)
    f3 = all(ver[(id, c)][2] for (id, c) in P615F_PAIRS if startswith(id, "F3"))
    v5 = all(ver[(id, c)][2] for (id, c) in P615F_PAIRS if startswith(id, "V5"))
    f8 = v5 && all(ver[(id, c)][2] for (id, c) in P615F_PAIRS if startswith(id, "F8"))
    println(io, join(("Fig3 (all F3 rows)", "f, b", "pass", f3 ? "pass" : "fail", "every F3 row", f3 ? "PASS" : "FAIL"), '\t'))
    println(io, join(("V5 (V5.1, V5.2)", "a, e", "pass", v5 ? "pass" : "fail", "every V5 row", v5 ? "PASS" : "FAIL"), '\t'))
    println(io, join(("Fig8 (V5 and F8.1–F8.4)", "a, e", "pass", f8 ? "pass" : "fail", "every row", f8 ? "PASS" : "FAIL"), '\t'))
    println(io, join(("Controls fail as pre-registered", "control, b", "fail", ctl_ok ? "fail" : "a control passes",
        "F3.1, F3.2, V5.1 (control) and F3.5 (b) fail", ctl_ok ? "PASS" : "FAIL"), '\t'))
end

finished = now()
open(joinpath(DIR, "meta.toml"), "w") do io
    TOML.print(io, Dict(
        "item" => "P6.15f", "decisions" => ["D-146", "D-154", "D-157", "D-168", "D-173"],
        "algorithm" => "SequentialCPM(; proposal = Moore(1))",
        "model" => "OpenVTReferenceMonolayer (Table S1 defaults: A₀ = 50, λ = 2, T = 20, α = 50/775, μ_X = 2, σ_X = 0.4, J 20/10)",
        "initial" => "openvt_reference_state: one disc of radius √(A₀/π) at the lattice centre",
        "boundary" => "closed", "edge_guard" => "edge_guard(5; terminate = true)",
        "stop" => "stop_at_cells(n): end of the first MCS with ≥ n live cells",
        "saves" => "MCS 0, every 39 MCS and the stopping MCS; per save N and openvt_metrics r, A, C, w, g (R units)",
        "cases" => Dict(string(c) => Dict("beta" => P615F_CASES[c].beta, "gamma" => P615F_CASES[c].gamma,
            "sigma_X" => P615F_CASES[c].sigma_X, "lattice" => P615F_CASES[c].L, "cells" => P615F_CASES[c].cells,
            "runs" => P615F_CASES[c].runs, "seeds" => "$(P615F_CASES[c].seed(1))–$(P615F_CASES[c].seed(P615F_CASES[c].runs))")
                        for c in CASE_ORDER),
        "stats" => Dict(c => Dict("L" => ST[c].L, "r" => ST[c].r, "A" => ST[c].A, "t_stop" => ST[c].t_stop,
            "r_stop" => ST[c].r_stop, "A_stop" => ST[c].A_stop, "sync" => ST[c].sync, "slope" => ST[c].slope,
            "offset" => ST[c].offset) for c in keys(ST)),
        "threads" => Threads.nthreads(), "cycle_mcs" => P615F_CYCLE))
end
git(args...) = readchomp(Cmd(`git $args`; dir = ROOT))
manifest = joinpath(ROOT, "Manifest.toml")
open(joinpath(DIR, "provenance.toml"), "w") do io
    TOML.print(io, Dict(
        "commit" => git("rev-parse", "HEAD"), "commit_date" => git("log", "-1", "--format=%cs"),
        "dirty_tracked" => !isempty(git("status", "--porcelain", "--untracked-files=no")),
        "test" => "lib/PottsModels/test/reproductions/15_openvt_f3_f8.jl", "test_sha256" => bytes2hex(open(sha256, TEST)),
        "runner" => relpath(@__FILE__, ROOT), "runner_sha256" => bytes2hex(open(sha256, @__FILE__)),
        "manifest_sha256" => isfile(manifest) ? bytes2hex(open(sha256, manifest)) : "missing",
        "julia" => string(VERSION), "threads" => Threads.nthreads(), "machine" => Sys.MACHINE,
        "hostname" => gethostname(), "cpu" => Sys.cpu_info()[1].model, "affinity" => get(ENV, "POTTS_AFFINITY", ""),
        "seeds" => join(("($c) $(P615F_CASES[c].seed(1))–$(P615F_CASES[c].seed(P615F_CASES[c].runs))" for c in CASE_ORDER), "; "),
        "started" => string(started), "finished" => string(finished),
        "wall_s" => round(Dates.value(finished - started) / 1000; digits = 1), "simulation_s" => round(sim_s; digits = 1),
        "cpu_s_runs" => round(sum(r.wall for r in res); digits = 1),
        "item" => "P6.15f", "decisions" => ["D-146", "D-157", "D-173"], "cache_used" => CACHED))
end
for pair in [P615F_PAIRS; P615F_CONTROL_PAIRS]
    println(rpad(join(pair, " "), 14), ver[pair][2] ? "PASS  " : "FAIL  ", ver[pair][1])
end
@info "done" wall_s = Dates.value(finished - started) / 1000 sim_s

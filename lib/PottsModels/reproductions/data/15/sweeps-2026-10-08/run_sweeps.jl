# P6.15g: the D-146 offline record of OpenVT Fig 6 (time to 10⁴ cells against β at γ = 0 and
# against γ at β = 0), Table 1 (the thresholds at 1.1, 2, 5, 10 and 20× the uninhibited time)
# and Fig 7 (10⁴-cell colonies at β = 0 for the T1 γ values): spec 15 §3.5, §4.0.1 cases (a),
# (c), (d), §4.1 V1, V2, V2b, V3, V3b and §4.3; D-174 and its amendment (BoundarySiteCPM).
#
# The protocol, grid, seeds, jobs and rules are the frozen test's
# `lib/PottsModels/test/reproductions/15_openvt_sweeps.jl`, evaluated from its source: every
# top-level `P615G_*` constant and `p615g_*` function of that file (no testset, no SMOKE, G or
# FULL block) is loaded verbatim, so this runner cannot drift from it. Its sha256 is in
# `provenance.toml`. The runner drives `p615g_protocol` with an `exec` that runs each job
# through the test's own `p615g_job` (no reimplementation), and the test's record tier
# replays the protocol on `runs.tsv` and recomputes every verdict.
#
# Resumable. Each finished run is written at once to `$P615G_WORK/runs/<sweep>_<q>_<k>.toml`
# (written to a temporary name, then renamed), and a restart reads those files back instead of
# rerunning them. A run is a pure function of its seed, so a resumed protocol takes the same
# path. For every γ-sweep replicate 1 (and β = 0, replicate 1) the O5 rows of the final state
# go to `$P615G_WORK/o5/` and the serialized final state to `$P615G_WORK/states/` (for the
# Fig 7 lattice stills; not committed). Progress is appended to `$P615G_WORK/progress.log`.
#
# Writes into this directory (P615G_OUT, default the runner's directory): runs.tsv (the
# frozen schema), verdicts.tsv, points.tsv, table1.tsv, Potts.jl_time_to_10k_vs_{beta,gamma}.csv
# (O3), f7/ (O5, the five Fig 7 panels), meta.toml, provenance.toml. `deviations.tsv`, the
# figures and the README are written after the run (D-154).
#
#     P615G_WORK=~/potts-ci/p6-15g-run POTTS_AFFINITY="taskset -c 0-11,16-27" \
#         systemd-run --user --scope -p MemoryMax=48G taskset -c 0-11,16-27 julia -t 24 \
#         --project=lib/PottsModels/test lib/PottsModels/reproductions/data/15/sweeps-2026-10-08/run_sweeps.jl
#
# P615G_DRY=true (a light check of this runner's paths only, never a record): 200² lattices,
# a 30-cell stop and a 6000-MCS cap through the same job function; requires P615G_OUT and
# P615G_WORK outside the record directory.
using Potts, PottsModels, Test
using Potts: CorePotts
using Statistics: mean
using Dates, TOML, SHA, Serialization

const started = now()
const DIR = @__DIR__
const ROOT = normpath(joinpath(DIR, "..", "..", "..", "..", "..", ".."))
const TEST = joinpath(ROOT, "lib", "PottsModels", "test", "reproductions", "15_openvt_sweeps.jl")

# ---- the frozen test's constants and rules, verbatim ---------------------------------------------
_defname(ex) = ex isa Expr && ex.head === :const ? _defname(ex.args[1]) :
               ex isa Expr && ex.head in (:(=), :function) ? (a = ex.args[1]; a isa Symbol ? a :
                                                              a isa Expr && a.head === :call ? a.args[1] :
                                                              a isa Expr && a.head === :where ? a.args[1].args[1] :
                                                              nothing) : nothing
for ex in Meta.parseall(read(TEST, String)).args
    ex isa Expr || continue
    n = _defname(ex)
    (n isa Symbol && startswith(string(n), r"p615g_|P615G_")) || continue
    Core.eval(@__MODULE__, ex)
end

# ---- settings ------------------------------------------------------------------------------------
const DRY = get(ENV, "P615G_DRY", "false") == "true"
const OUT = abspath(expanduser(get(ENV, "P615G_OUT", DIR)))
const WORK = abspath(expanduser(get(ENV, "P615G_WORK", joinpath(ROOT, "..", "p6-15g-run"))))
DRY && (startswith(OUT, DIR) || startswith(WORK, DIR)) && error("P615G_DRY: set P615G_OUT and P615G_WORK outside the record directory")
startswith(WORK, DIR) && error("P615G_WORK must be outside the record directory (only small files are committed)")
const LAT = DRY ? (beta = 200, gamma = 200) : P615G_LATTICE
const CELLS = DRY ? 30 : P615G_CELLS
const CAP = DRY ? 6000 : P615G_CAP
for d in (OUT, joinpath(OUT, "f7"), joinpath(WORK, "runs"), joinpath(WORK, "o5"), joinpath(WORK, "states"))
    mkpath(d)
end
const PROGRESS = joinpath(WORK, "progress.log")
function logline(s)
    line = string(now(), "  ", s)
    open(io -> println(io, line), PROGRESS, "a")
    println(line)
    flush(stdout)
    return nothing
end

# ---- the runs ------------------------------------------------------------------------------------
# one problem per sweep lattice (the test's p615g_problem); jobs remake it per seed and parameters
const probs = Dict(sw => p615g_problem(LAT[sw]; cells = CELLS, cap = CAP) for sw in (:beta, :gamma))
# closest approach of a cell to the lattice edge (sites)
function edge_gap(σ)
    L1, L2 = size(σ)
    return minimum(min(I[1] - 1, I[2] - 1, L1 - I[1], L2 - I[2]) for I in findall(!=(0), σ))
end
runkey(sw, q, k) = "$(sw)_$(q)_$(k)"
runfile(sw, q, k) = joinpath(WORK, "runs", runkey(sw, q, k) * ".toml")
f7gamma(sw, q) = sw === :beta ? 0.0 : q / 10_000
keeps_state(sw, q, k) = k == 1 && (sw === :gamma || q == 0)
atomic_write(f, writer) = (tmp = f * ".tmp"; open(writer, tmp, "w"); mv(tmp, f; force = true); f)

const LK = ReentrantLock()
const DONE = Ref(0)
function run_one(sw, q, k)
    f = runfile(sw, q, k)
    isfile(f) && return TOML.parsefile(f)
    wall = @elapsed r = p615g_job(probs[sw], sw, q, k; cells = CELLS, cap = CAP)
    σ = Array(r.u.σ)
    gap = edge_gap(σ)
    if keeps_state(sw, q, k)
        o5 = p615g_o5(r.u; β = r.β, γ = r.γ)
        write_openvt(joinpath(WORK, "o5", openvt_filename(:O5; gamma = f7gamma(sw, q), mcs = r.mcs)), :O5, o5)
        atomic_write(joinpath(WORK, "states", runkey(sw, q, k) * ".jls"), io -> serialize(io, r.u))
    end
    d = Dict{String, Any}("sweep" => string(sw), "q" => q, "k" => k, "seed" => r.seed, "beta" => r.β, "gamma" => r.γ,
        "lattice" => LAT[sw], "retcode" => string(r.retcode), "mcs" => r.mcs, "N" => r.N, "capped" => r.capped,
        "edge_gap" => gap, "wall_s" => round(wall; digits = 2), "thread" => Threads.threadid())
    atomic_write(f, io -> TOML.print(io, d))
    lock(LK) do
        DONE[] += 1
        logline("run $(runkey(sw, q, k)) seed $(r.seed): $(r.retcode) MCS $(r.mcs) N $(r.N) capped $(r.capped) " *
                "t $(round(r.mcs / P615G_CYCLE; digits = 3)) gap $gap wall $(round(wall; digits = 1)) s [$(DONE[]) new this launch]")
    end
    return d
end
rtime(d) = d["capped"] ? Inf : d["mcs"] / P615G_CYCLE

# scheduling only (results do not depend on it): the longest jobs first, by the test's
# synthetic TST-shaped curve (capped → 20×) times the lattice area; `:greedy` hands out one job
# at a time
cost(sw, q) = (t = p615g_syn(sw, q); isfinite(t) ? t : p615g_tau(20.0)) * LAT[sw]^2
const STAGE_N = Ref(0)
function exec(jobs)
    STAGE_N[] += 1
    order = sort(eachindex(jobs); by = j -> -cost(jobs[j][1], jobs[j][2]))
    cached = count(j -> isfile(runfile(j...)), jobs)
    logline("stage $(STAGE_N[]): $(length(jobs)) jobs ($cached already on disk) on $(Threads.nthreads()) threads")
    out = Vector{Float64}(undef, length(jobs))
    Threads.@threads :greedy for j in order
        out[j] = rtime(run_one(jobs[j]...))
    end
    logline("stage $(STAGE_N[]) done")
    return out
end

# compile both lattices on a tiny run (results discarded)
if !all(isfile(runfile(sw, q, k)) for sw in (:beta, :gamma) for q in P615G_GRID[sw] for k in 1:p615g_n1(sw, q))
    tiny = p615g_problem(60; cells = 3, cap = 200)
    p615g_job(tiny, :beta, 0, 1; cells = 3, cap = 200)
end
logline("start: $(DRY ? "DRY " : "")lattices $(LAT), stop $CELLS cells, cap $CAP MCS, work $WORK, out $OUT")
const sim_s = @elapsed P = p615g_protocol(exec)
logline("protocol done: $(length(P.log)) runs")

# ---- outputs -------------------------------------------------------------------------------------
stage = Dict((e[2], e[3], e[4]) => e[1] for e in P.log)
rec = Dict((e[2], e[3], e[4]) => TOML.parsefile(runfile(e[2], e[3], e[4])) for e in P.log)
ordered = sort(collect(keys(rec)); by = x -> (x[1] === :beta ? 0 : 1, x[2], x[3]))
open(joinpath(OUT, "runs.tsv"), "w") do io
    println(io, join(("sweep", "q", "k", "seed", "stage", "beta", "gamma", "lattice", "retcode", "mcs", "N", "capped",
        "edge_gap", "wall_s"), '\t'))
    for j in ordered
        d = rec[j]
        println(io, join((d["sweep"], d["q"], d["k"], d["seed"], stage[j], repr(Float64(d["beta"])), repr(Float64(d["gamma"])),
            d["lattice"], d["retcode"], d["mcs"], d["N"], d["capped"], d["edge_gap"], d["wall_s"]), '\t'))
    end
end
# O3: one row per run of each sweep, the parameter value and the stopping MCS (NaN when capped)
for sw in (:beta, :gamma)
    js = filter(j -> j[1] === sw, ordered)
    data = NamedTuple{(sw, :mcs)}(([j[2] / 10_000 for j in js], [rec[j]["capped"] ? NaN : Float64(rec[j]["mcs"]) for j in js]))
    write_openvt(joinpath(OUT, openvt_filename(:O3; parameter = sw)), :O3, data)
end
# Fig 7 (O5): γ = 0 (β = 0, k = 1), γ = 1e-4 (k = 1) and the three T1 γ thresholds (k = 1)
qs7 = Int[p615g_threshold(P.S, :gamma, m, P.br[(:gamma, m)]) for m in (5.0, 10.0, 20.0) if P.br[(:gamma, m)] !== nothing]
panels = unique([(:beta, 0); (:gamma, 1); [(:gamma, q) for q in qs7]])
foreach(f -> rm(joinpath(OUT, "f7", f)), readdir(joinpath(OUT, "f7")))
inh = Dict{Int, Float64}()
for (sw, q) in panels
    name = openvt_filename(:O5; gamma = f7gamma(sw, q), mcs = rec[(sw, q, 1)]["mcs"])
    cp(joinpath(WORK, "o5", name), joinpath(OUT, "f7", name); force = true)
    sw === :gamma && (inh[q] = mean(read_openvt(joinpath(OUT, "f7", name), :O5).inhibited))
end
for q in qs7
    haskey(inh, q) || (inh[q] = NaN)
end

# the verdicts, by the test's rules, from the records just written (as its record tier reads them)
runs = p615g_tsv(joinpath(OUT, "runs.tsv"))
recr = Dict((Symbol(r["sweep"]), parse(Int, r["q"]), parse(Int, r["k"])) => r for r in runs)
PR = p615g_protocol(jobs -> [p615g_rtime(recr[j]) for j in jobs])
PR.log == P.log || error("the replay of runs.tsv differs from the run's protocol log")
ver = p615g_verdicts(PR, inh)
info = p615g_information(PR)

# ---- tables ------------------------------------------------------------------------------------
r4(x::Real) = isnan(x) ? "NaN" : isinf(x) ? "Inf" : string(round(x; sigdigits = 5))
r4(x::AbstractString) = x
r4(x::Tuple) = "(" * join(r4.(x), ", ") * ")"
r4(::Nothing) = "—"
bandtxt((lo, hi)) = "[$(r4(lo)), $(r4(hi))]"
pmean(sw, q) = p615g_mean(PR.S[(sw, q)])
open(joinpath(OUT, "points.tsv"), "w") do io
    println(io, join(("sweep", "q", "value", "n", "capped", "t_mean_cycles", "t_min", "t_max"), '\t'))
    for sw in (:beta, :gamma), q in p615g_points(PR.S, sw)
        t = PR.S[(sw, q)]
        fin = filter(isfinite, t)
        println(io, join((sw, q, q / 10_000, length(t), count(isinf, t), r4(p615g_mean(t)),
            isempty(fin) ? "Inf" : r4(minimum(fin)), any(isinf, t) ? "Inf" : r4(maximum(t))), '\t'))
    end
end
TST_ROW = Dict((:beta, m) => P615G_G.tst_beta[j] for (j, m) in enumerate(P615G_MULTS))
ART_ROW = Dict((:beta, m) => P615G_G.art_beta[j] for (j, m) in enumerate(P615G_MULTS))
for (j, m) in enumerate((5.0, 10.0, 20.0))
    TST_ROW[(:gamma, m)] = P615G_G.tst_gamma_runs[j]
    ART_ROW[(:gamma, m)] = P615G_G.art_gamma_means[j]
end
open(joinpath(OUT, "table1.tsv"), "w") do io
    println(io, join(("parameter", "multiple", "tau_cycles", "bracket_lo", "bracket_hi", "t_lo", "t_hi", "n_lo", "n_hi",
        "threshold", "interpolated", "relative_to_own_t0", "TST", "Artistoo", "spread", "band"), '\t'))
    for sw in (:beta, :gamma), m in P615G_MULTS
        row = p615g_row(sw, m)
        if sw === :gamma && m in (1.1, 2.0)
            println(io, join(("gamma", m, p615g_tau(m), "", "", "", "", "", "", ver[row][1] == "—" ? "—" : r4(ver[row][1]), "",
                r4(info.relative[row]), "—", "—", "—", "—"), '\t'))
            continue
        end
        b = PR.br[(sw, m)]
        th = p615g_threshold(PR.S, sw, m, b)
        sp = sw === :beta ? P615G_V2_SPREAD[m] : P615G_V3_SPREAD[m]
        println(io, join((sw, m, p615g_tau(m), b === nothing ? "" : b[1] / 10_000, b === nothing ? "" : b[2] / 10_000,
            b === nothing ? "" : r4(pmean(sw, b[1])), b === nothing ? "" : r4(pmean(sw, b[2])),
            b === nothing ? "" : length(PR.S[(sw, b[1])]), b === nothing ? "" : length(PR.S[(sw, b[2])]),
            th === nothing ? "—" : th / 10_000, r4(info.interp[row]), r4(info.relative[row]), TST_ROW[(sw, m)], ART_ROW[(sw, m)],
            bandtxt(sp), bandtxt(p615g_band(sw, m))), '\t'))
    end
end

NAME = Dict("V1" => "t̄ at β = γ = 0 (cycles)", "V3b" => "t̄ at γ = 1e-4 (cycles)",
    "F7.1" => "min inhibited fraction, replicate 1 at the T1 γ thresholds")
PAPER = Dict("V1" => "13.57 (Table 1 caption); TST plateau 13.77, Artistoo 13.856", "V3b" => "TST 61.37 (γ = 1e-4), Artistoo 63.09 (γ = 0.0195)",
    "F7.1" => "TST $(join(r4.(P615G_G.tst_f7), ", "))", "NC1" => "β = γ = 0 against the V3b band",
    "NC2" => "t̄(0.95)/TST 20.40 and t̄(1.0)/TST 32.11 (β offset 0.05)", "NC3" => "γ = 1e-4 against the V1 band")
BAND = Dict("V1" => bandtxt(P615G_V1_BAND), "V3b" => bandtxt(P615G_V3B_BAND), "F7.1" => "≥ $(P615G_F7_MIN)",
    "NC1" => "$(bandtxt(P615G_V3B_BAND)) (control: must FAIL)", "NC2" => "both in $(bandtxt(P615G_V2B_RATIO)) (control: must FAIL)",
    "NC3" => "$(bandtxt(P615G_V1_BAND)) (control: must FAIL)")
for (sw, m) in P615G_TARGETS
    row = p615g_row(sw, m)
    NAME[row] = "$(sw === :beta ? "β" : "γ") threshold at $(m)× (M's nearest rule on point means)"
    PAPER[row] = "lattice spread $(bandtxt(sw === :beta ? P615G_V2_SPREAD[m] : P615G_V3_SPREAD[m])); TST $(TST_ROW[(sw, m)]), Artistoo $(ART_ROW[(sw, m)])"
    BAND[row] = bandtxt(p615g_band(sw, m))
end
for m in (1.1, 2.0)
    row = "V3." * p615g_mid(m)
    NAME[row] = "γ threshold at $(m)× (bracket over γ > 0)"
    PAPER[row] = "— (the lattice γ → 0⁺ jump)"
    BAND[row] = "—"
end
for (q, ref) in zip(P615G_V2B, P615G_G.v2b)
    row = "V2b." * string(q / 10_000)
    NAME[row] = "t̄(β = $(q / 10_000)) / reference"
    PAPER[row] = "$(q in (8727, 9334) ? "Artistoo" : "TST") $ref cycles"
    BAND[row] = bandtxt(P615G_V2B_RATIO)
end
NAME["NC1"] = "V3b rule on γ = 0 (the β = 0 point)"
NAME["NC2"] = "V2b rule at a β offset of 0.05"
NAME["NC3"] = "V1 rule on γ = 1e-4"
open(joinpath(OUT, "verdicts.tsv"), "w") do io
    println(io, join(("target", "paper", "ours", "band", "result"), '\t'))
    for row in [P615G_ROWS; P615G_CONTROLS]
        v, ok = ver[row]
        println(io, join(("$row $(NAME[row])", PAPER[row], r4(v), BAND[row], ok ? "PASS" : "FAIL"), '\t'))
    end
end

# ---- meta and provenance -------------------------------------------------------------------------
finished = now()
walls = [Float64(d["wall_s"]) for d in values(rec)]
open(joinpath(OUT, "meta.toml"), "w") do io
    TOML.print(io, Dict(
        "item" => "P6.15g", "decisions" => ["D-146", "D-147", "D-154", "D-157", "D-174", "D-177"], "dry" => DRY,
        "algorithm" => "BoundarySiteCPM(; proposal = Moore(1))",
        "model" => "OpenVTReferenceMonolayer (Table S1 defaults: A₀ = 50, λ = 2, T = 20, α = 50/775, μ_X = 2, σ_X = 0.4, J 20/10), β and γ per point",
        "initial" => "openvt_reference_state: one disc of radius √(A₀/π) at the lattice centre",
        "boundary" => "closed", "edge_guard" => "edge_guard($(P615G_GUARD); terminate = true)",
        "stop" => "stop_at_cells($CELLS): end of the first MCS with ≥ $CELLS live cells, or the cap",
        "cap_mcs" => CAP, "cycle_mcs" => P615G_CYCLE, "lattice" => Dict(string(k) => v for (k, v) in pairs(LAT)),
        "seeds" => "β: 160 000 000 + 100 q + k; γ: 170 000 000 + 100 q + k (q = parameter × 10⁴)",
        "runs" => Dict("total" => length(rec), "grid" => count(==(:grid), values(stage)),
            "bisect" => count(==(:bisect), values(stage)), "final" => count(==(:final), values(stage)),
            "capped" => count(d -> d["capped"], values(rec))),
        "brackets" => Dict(p615g_row(tg...) => (PR.br[tg] === nothing ? "—" : collect(PR.br[tg] ./ 10_000)) for tg in P615G_TARGETS),
        "f7_panels" => [string(sw, " ", q / 10_000) for (sw, q) in panels],
        "information" => Dict("t0_own" => info.t0,
            "relative" => Dict(k => (v isa Real ? v : string(v)) for (k, v) in info.relative),
            "interpolated" => Dict(k => (isnan(v) ? "NaN" : v) for (k, v) in info.interp)),
        "threads" => Threads.nthreads()))
end
git(args...) = readchomp(Cmd(`git $args`; dir = ROOT))
manifest = joinpath(ROOT, "Manifest.toml")
open(joinpath(OUT, "provenance.toml"), "w") do io
    TOML.print(io, Dict(
        "commit" => git("rev-parse", "HEAD"), "commit_date" => git("log", "-1", "--format=%cs"),
        "dirty_tracked" => !isempty(git("status", "--porcelain", "--untracked-files=no")),
        "test" => "lib/PottsModels/test/reproductions/15_openvt_sweeps.jl", "test_sha256" => bytes2hex(open(sha256, TEST)),
        "runner" => relpath(@__FILE__, ROOT), "runner_sha256" => bytes2hex(open(sha256, @__FILE__)),
        "manifest_sha256" => isfile(manifest) ? bytes2hex(open(sha256, manifest)) : "missing",
        "julia" => string(VERSION), "threads" => Threads.nthreads(), "machine" => Sys.MACHINE,
        "hostname" => gethostname(), "cpu" => Sys.cpu_info()[1].model, "affinity" => get(ENV, "POTTS_AFFINITY", ""),
        "seeds" => "β: 160 000 000 + 100 q + k; γ: 170 000 000 + 100 q + k",
        "started" => string(started), "finished" => string(finished),
        "wall_s_this_launch" => round(Dates.value(finished - started) / 1000; digits = 1),
        "simulation_s_this_launch" => round(sim_s; digits = 1),
        "cpu_s_runs" => round(sum(walls); digits = 1), "core_hours_runs" => round(sum(walls) / 3600; digits = 2),
        "runs" => length(rec), "work" => WORK, "dry" => DRY,
        "item" => "P6.15g", "decisions" => ["D-146", "D-157", "D-174", "D-177"]))
end
for row in [P615G_ROWS; P615G_CONTROLS]
    println(rpad(row, 12), ver[row][2] ? "PASS  " : "FAIL  ", ver[row][1])
end
logline("done: $(length(rec)) runs, $(round(sum(walls) / 3600; digits = 2)) core-hours in runs")

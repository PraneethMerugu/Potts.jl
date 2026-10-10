# P6.15k (D-211 R2, D-212): the D-146 offline record of the Potts.jl row of M's new Figure 8
# (9 Oct 2026 draft), "Tissue Snapshots with Area Inhibition": one 10⁴-cell colony at each of
# our Table 1 β thresholds, β = 0.625, 0.9375, 0.9875, 1.007 and 1.0212 (1.1×, 2×, 5×, 10×,
# 20×; γ = 0), as O5 files.
#
# REPLAY. Each run is replicate 1 of that T1 β point of the sweeps record
# (`data/15/sweeps-2026-10-08/`, P6.15g), rerun from its seed with the sweeps test's own job:
# `p615k_job(P615KG.p615g_problem(1400), β)` = `p615g_job(prob, :beta, q, 1)`, q = β × 10⁴,
# seed 160 000 000 + 100 q + 1, `SequentialCPM(; skip_interior = true, proposal = Moore(1))`,
# closed 1400² lattice, `edge_guard(5; terminate = true)`, stop at the end of the first MCS with
# ≥ 10⁴ cells, cap 210 335 MCS. A run is a pure function of its seed, so every run must equal
# its row of the sweeps `runs.tsv` (stop MCS, N, return code); the runner stops with an error,
# before writing provenance, if one does not.
#
# The job functions are the frozen test's `lib/PottsModels/test/reproductions/15_openvt_d211.jl`,
# evaluated from its source: every top-level `P615K*` constant and `p615k_*` function of that
# file (which in turn loads the sweeps test's `p615g_*` definitions) is loaded verbatim, so this
# runner cannot drift from the test. Its sha256 is in `provenance.toml`.
#
# Writes into this directory (F8BETA_OUT, default the runner's directory): f8/ (the five O5
# files, `openvt_filename(:O5; beta, mcs)`), runs.tsv, meta.toml, provenance.toml and
# README.md, then runs `plot_f8_grid.jl` (fig8_grid.png, fig8_grid.tsv, fig8_hull.tsv,
# fig8_grid.toml). Wall time on the PC about 31 min with 5 threads (the 20× run, MCS 203 045,
# took 1849 s in the sweeps).
#     julia -t 5 --project=lib/PottsModels/test lib/PottsModels/reproductions/data/15/f8beta-2026-10-09/run_f8beta.jl
#
# Check mode (never a record): F8BETA_ONLY=<β,…> runs only those β and requires F8BETA_OUT
# outside this directory; it writes f8/ and runs.tsv there and checks the replay.
using Potts, PottsModels, Test, Printf
using Statistics: mean
using Dates, TOML, SHA

const started = now()
const DIR = @__DIR__
const ROOT = normpath(joinpath(DIR, "..", "..", "..", "..", "..", ".."))
const TEST = joinpath(ROOT, "lib", "PottsModels", "test", "reproductions", "15_openvt_d211.jl")

# ---- the frozen test's definitions, verbatim -------------------------------------------------------
_defname(ex) = ex isa Expr && ex.head === :const ? _defname(ex.args[1]) :
               ex isa Expr && ex.head in (:(=), :function) ? (a = ex.args[1]; a isa Symbol ? a :
                                                              a isa Expr && a.head === :call ? a.args[1] :
                                                              a isa Expr && a.head === :where ? a.args[1].args[1] :
                                                              nothing) : nothing
# parsed with the test's file name, so that its `@__DIR__` is the test directory
for ex in Meta.parseall(read(TEST, String); filename = TEST).args
    ex isa Expr || continue
    n = _defname(ex)
    (n isa Symbol && startswith(string(n), r"p615k_|P615K")) || continue
    Core.eval(@__MODULE__, ex)
end

# ---- settings ------------------------------------------------------------------------------------
const OUT = abspath(expanduser(get(ENV, "F8BETA_OUT", DIR)))
const ONLY = let s = strip(get(ENV, "F8BETA_ONLY", ""))
    isempty(s) ? nothing : parse.(Float64, split(s, ','))
end
ONLY === nothing || !startswith(OUT, DIR) ||
    error("F8BETA_ONLY is a check mode: set F8BETA_OUT outside the record directory")
ONLY === nothing || all(in(P615K_BETA), ONLY) || error("F8BETA_ONLY: β must be among $(P615K_BETA)")
const BETAS = ONLY === nothing ? P615K_BETA : ONLY
mkpath(joinpath(OUT, "f8"))
logline(s) = (println(string(now(), "  ", s)); flush(stdout); nothing)

function edge_gap(σ)
    L1, L2 = size(σ)
    return minimum(min(I[1] - 1, I[2] - 1, L1 - I[1], L2 - I[2]) for I in findall(!=(0), σ))
end

# ---- the runs ------------------------------------------------------------------------------------
const SWEEP = p615k_sweep_runs()
const prob = P615KG.p615g_problem(P615K_LATTICE)
logline("start: β = $(BETAS) on $(Threads.nthreads()) threads, lattice $(P615K_LATTICE)², cap $(P615KG.P615G_CAP) MCS, out $OUT")
res = Vector{Any}(undef, length(BETAS))
const LK = ReentrantLock()
# the longest runs first (scheduling only; results do not depend on it)
Threads.@threads :greedy for j in sort(eachindex(BETAS); by = j -> -BETAS[j])
    β = BETAS[j]
    wall = @elapsed r = p615k_job(prob, β)
    o5 = p615k_o5(r)
    name = p615k_o5_name(β, r.mcs)
    write_openvt(joinpath(OUT, "f8", name), :O5, o5)
    res[j] = (; r.seed, r.q, r.k, r.retcode, r.mcs, r.N, r.capped, β, gap = edge_gap(Array(r.u.σ)),
        inhibited = count(==(1), o5.inhibited), wall, name)
    lock(LK) do
        logline("β = $β seed $(r.seed): $(r.retcode) MCS $(r.mcs) N $(r.N) inhibited $(res[j].inhibited) " *
                "gap $(res[j].gap) wall $(round(wall; digits = 1)) s")
    end
end
const sim_s = sum(r.wall for r in res)

# ---- the replay check ----------------------------------------------------------------------------
bad = String[]
for r in res
    sr = SWEEP[("beta", r.q, 1)]
    ok = r.mcs == parse(Int, sr["mcs"]) && r.N == parse(Int, sr["N"]) && string(r.retcode) == sr["retcode"] &&
         r.seed == parse(Int, sr["seed"]) && !r.capped
    ok || push!(bad, "β = $(r.β): MCS $(r.mcs) N $(r.N) $(r.retcode), sweeps row MCS $(sr["mcs"]) N $(sr["N"]) $(sr["retcode"])")
end

# ---- runs.tsv (always; the five runs in multiple order) ---------------------------------------------
mult(β) = P615K_MULTS[findfirst(==(β), P615K_BETA)]
open(joinpath(OUT, "runs.tsv"), "w") do io
    println(io, join(P615K_H_RUNS, '\t'))
    for r in sort(res; by = r -> r.β)
        println(io, join((string(mult(r.β)), string(r.β), r.q, r.k, r.seed, P615K_LATTICE, string(r.retcode), r.mcs, r.N,
            r.capped, r.gap, r.inhibited, round(r.wall; digits = 2)), '\t'))
    end
end
isempty(bad) || error("the replay differs from the sweeps record:\n" * join(bad, '\n'))
logline("replay: every run equals its sweeps row")
if ONLY !== nothing
    logline("check mode: done (no record written)")
    exit(0)
end

# ---- meta, provenance, README ---------------------------------------------------------------------
finished = now()
shares = [r.inhibited / r.N for r in sort(res; by = r -> r.β)]
open(joinpath(OUT, "meta.toml"), "w") do io
    TOML.print(io, Dict(
        "item" => "P6.15k", "decisions" => ["D-146", "D-185", "D-211", "D-212"], "replay" => true,
        "replay_of" => "sweeps-2026-10-08 runs.tsv, sweep beta, k = 1, at the T1 β of table1.tsv",
        "algorithm" => "SequentialCPM(; skip_interior = true, proposal = Moore(1))",
        "model" => "OpenVTReferenceMonolayer (Table S1 defaults: A₀ = 50, λ = 2, T = 20, α = 50/775, μ_X = 2, σ_X = 0.4, J 20/10), γ = 0, β per run",
        "initial" => "openvt_reference_state: one disc of radius √(A₀/π) at the lattice centre",
        "boundary" => "closed", "edge_guard" => "edge_guard($(P615KG.P615G_GUARD); terminate = true)",
        "stop" => "stop_at_cells($(P615K_CELLS)): end of the first MCS with ≥ $(P615K_CELLS) live cells, or the cap",
        "cells" => P615K_CELLS, "cap_mcs" => P615KG.P615G_CAP, "lattice" => P615K_LATTICE, "cycle_mcs" => P615K_CYCLE,
        "betas" => P615K_BETA, "multiples" => P615K_MULTS,
        "seeds" => "160 000 000 + 100 q + 1, q = β × 10⁴ (the sweeps record's replicate 1)",
        "inhibited_shares" => shares, "threads" => Threads.nthreads()); sorted = true)
end
git(args...) = readchomp(Cmd(`git $args`; dir = ROOT))
manifest = joinpath(ROOT, "Manifest.toml")
sweeps_test = joinpath(ROOT, "lib", "PottsModels", "test", "reproductions", "15_openvt_sweeps.jl")
open(joinpath(OUT, "provenance.toml"), "w") do io
    TOML.print(io, Dict(
        "item" => "P6.15k", "decisions" => ["D-146", "D-157", "D-211", "D-212"],
        "commit" => git("rev-parse", "HEAD"), "commit_date" => git("log", "-1", "--format=%cs"),
        "dirty_tracked" => !isempty(git("status", "--porcelain", "--untracked-files=no")),
        "test" => "lib/PottsModels/test/reproductions/15_openvt_d211.jl", "test_sha256" => bytes2hex(open(sha256, TEST)),
        "sweeps_test_sha256" => bytes2hex(open(sha256, sweeps_test)),
        "runner" => relpath(@__FILE__, ROOT), "runner_sha256" => bytes2hex(open(sha256, @__FILE__)),
        "manifest_sha256" => isfile(manifest) ? bytes2hex(open(sha256, manifest)) : "missing",
        "julia" => string(VERSION), "threads" => Threads.nthreads(), "machine" => Sys.MACHINE,
        "cpu" => Sys.cpu_info()[1].model, "seeds" => "160 000 000 + 100 q + 1 (q = β × 10⁴)",
        "started" => string(started), "finished" => string(finished),
        "wall_s" => round(Dates.value(finished - started) / 1000; digits = 1),
        "cpu_s_runs" => round(sim_s; digits = 1), "runs" => length(res)); sorted = true)
end
prov = TOML.parsefile(joinpath(OUT, "provenance.toml"))
open(joinpath(OUT, "README.md"), "w") do io
    print(io, """
    # P6.15k: the Figure 8 β colonies (OpenVT monolayer, 9 Oct 2026 draft)

    M's new Figure 8, "Tissue Snapshots with Area Inhibition", shows one colony at 10⁴ cells per
    framework and Table 1 multiple (1.1×, 2×, 5×, 10×, 20× the uninhibited time), at that
    multiple's β threshold with γ = 0. Cells are coloured yellow (no inhibition) or red
    (area-inhibited, a < β), with the colony's concave hull in black (D-211 R2, D-212).

    Our row is at our Table 1 β values (`sweeps-2026-10-08/table1.tsv`). These colonies were not
    kept by the sweeps record, so each is **replayed**: replicate 1 of the sweeps record's run at
    that β, rerun from its seed (160 000 000 + 100 q + 1, q = β × 10⁴) with the sweeps test's
    own job function. A run is a pure function of its seed, and every run below stopped at the
    same MCS with the same cell count as its sweeps row, so each colony is one of the six runs
    behind its Table 1 point.

    ## Protocol

    - Model: `OpenVTReferenceMonolayer` with the Table S1 defaults, γ = 0, β as below.
    - `SequentialCPM(; skip_interior = true, proposal = Moore(1))` (equal in law to
      `SequentialCPM()`, D-177, D-198) on a closed $(P615K_LATTICE)² lattice with
      `edge_guard($(P615KG.P615G_GUARD); terminate = true)`; stop at the end of the first MCS
      with ≥ $(P615K_CELLS) cells; cap $(P615KG.P615G_CAP) MCS (20 × 13.57 cycles), never reached.
    - O5 of the final state: centroid and radius in R from the lattice centre, `inhibited` =
      inhibition code i > 0 (at γ = 0 that is area inhibition, a < β).

    ## Result

    | Multiple | β | Seed | Stop (MCS) | Cycles | N | Inhibited | Share | Edge gap (sites) |
    |---|---|---|---|---|---|---|---|---|
    """)
    for r in sort(res; by = r -> r.β)
        @printf(io, "| %s× | %s | %d | %d | %.2f | %d | %d | %.3f | %d |\n", replace(string(mult(r.β)), r"\.0$" => ""),
            string(r.β), r.seed, r.mcs, r.mcs / P615K_CYCLE, r.N, r.inhibited, r.inhibited / r.N, r.gap)
    end
    print(io, """

    Every run equals its row of `sweeps-2026-10-08/runs.tsv` (stop MCS, N, return code).

    ## Files

    | File | Content |
    |---|---|
    | `run_f8beta.jl` | the runner (evaluates the frozen test's job definitions) |
    | `plot_f8_grid.jl` | the figure and its tables, from `f8/` and `runs.tsv` |
    | `f8/Potts.jl_beta_<β>_<MCS>MCS.csv` | O5 of each colony: `x_pos`, `y_pos`, `radius_i` (R), `inhibited` (0/1) |
    | `runs.tsv` | one row per run: multiple, β, q, k, seed, lattice, return code, stop MCS, N, capped, closest approach to the edge, inhibited cells, wall time |
    | `fig8_grid.png` | the Potts.jl row of M's Figure 8 grid |
    | `fig8_grid.tsv`, `fig8_hull.tsv`, `fig8_grid.toml` | per colony N, inhibited, the hull's vertex count B and C/C_circle (metrics.cpp's concave hull, concavity 1.5); the hull vertices; the figure's form |
    | `meta.toml`, `provenance.toml` | protocol and provenance |

    The panels carry no number: M's panel label quantity is unstated and on our open question
    list (D-211 R5). C/C_circle of each colony is in `fig8_grid.tsv`.

    Run at commit `$(prov["commit"][1:8])` on $(prov["cpu"]), $(prov["threads"]) threads, Julia $(prov["julia"]),
    $(round(prov["wall_s"] / 60; digits = 1)) min in all.
    """)
end

# ---- the figure ----------------------------------------------------------------------------------
run(Cmd(`$(Base.julia_cmd()) --project=$(Base.active_project()) $(joinpath(DIR, "plot_f8_grid.jl"))`; dir = ROOT))
logline("done: $(length(res)) runs, $(round(sim_s / 3600; digits = 2)) core-hours in runs")

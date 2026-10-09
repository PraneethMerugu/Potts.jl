# D-185: the full-state cell areas behind the restyled F1 panel. `window.tsv` holds only
# the panel's 64 × 64 block, so cells cut by the window would get their clipped area. This
# reruns the same state as `run_f1.jl` (case (a) run 1, seed 15701, 1400², the D-173
# protocol of the frozen F3/F8 test, loaded the same way) and writes `window_cells.tsv`:
# for every cell in the block, its id, generation, full-state area (`volume`, sites),
# `A_star` and the `inhibited` flag (O5: inhibition code i > 0 at the case's β and γ).
#
# The rerun must stop at the record's MCS and N (`../f3-f8-2026-10-08/runs.tsv`), and its
# block must equal `window.tsv` (owners and generations) site for site; otherwise the script
# stops before writing anything.
#
#     taskset -c 0-5,16-21 julia -t 1 --project=lib/PottsModels/test \
#         lib/PottsModels/reproductions/data/15/f1-f4-2026-10-08/run_f1_areas.jl
using Potts, PottsModels, Test
using Potts: CorePotts
using Statistics: mean
using Dates, TOML, SHA

const started = now()
const DIR = @__DIR__
const ROOT = normpath(joinpath(DIR, "..", "..", "..", "..", "..", ".."))
const TEST = joinpath(ROOT, "lib", "PottsModels", "test", "reproductions", "15_openvt_f3_f8.jl")
const RECORD = joinpath(DIR, "..", "f3-f8-2026-10-08", "runs.tsv")

# ---- the frozen F3/F8 test's constants and rules, verbatim (as run_f1.jl) -------------------
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

const CASE = P615F_CASES.a
const K = 1
const SEED = CASE.seed(K)
rows = [split(l, '\t') for l in readlines(RECORD)]
hdr = Dict(String(h) => i for (i, h) in enumerate(rows[1]))
rec = only(r for r in rows[2:end] if r[hdr["case"]] == "a" && parse(Int, r[hdr["k"]]) == K)
parse(Int, rec[hdr["seed"]]) == SEED || error("the record's case (a) run 1 has seed $(rec[hdr["seed"]]), not $SEED")
const REC_MCS = parse(Int, rec[hdr["mcs"]])
const REC_N = parse(Int, rec[hdr["N"]])

# ---- the committed block ----------------------------------------------------------------------
win = [parse.(Int, split(l, '\t')) for l in readlines(joinpath(DIR, "window.tsv"))[2:end]]

# ---- the run ----------------------------------------------------------------------------------
cells_L = maximum(d.cells for d in values(P615F_CASES) if d.L == CASE.L)
prob = p615f_problem(CASE.L, cells_L)
wall = @elapsed r = p615f_run(prob, SEED, CASE)
u = r.u
N = count(>(0), Array(u.cell.volume))
mcs = Int(r.mcs)
@info "run" r.retcode mcs N wall
(r.retcode === :Terminated && mcs == REC_MCS && N == REC_N && r.series.N[end] == REC_N) ||
    error("the rerun differs from the record: retcode $(r.retcode), MCS $mcs (record $REC_MCS), N $N (record $REC_N)")

σ = Array(u.σ)
volume = Array(u.cell.volume)
A_star = Array(u.cell.A_star)
gen = Array(u.cell.generation)
for (x, y, o, g) in win
    σ[x, y] == o || error("site ($x, $y): the rerun's owner $(σ[x, y]) is not window.tsv's $o")
end
gens_match = all(w -> w[3] == 0 || gen[w[3]] == w[4], win)
gens_match || @warn "the state's generations differ from window.tsv's render-frame generations; window.tsv's are kept"
ids = sort!(unique(o for (_, _, o, _) in win if o > 0))
# the inhibited flag (O5) from the O1 code at the case's thresholds
fr = PottsModels.openvt_frame(u; β = CASE.beta, γ = CASE.gamma)
live = findall(>(0), volume)
code = Dict(c => fr.i[j] for (j, c) in enumerate(live))
open(joinpath(DIR, "window_cells.tsv"), "w") do io
    println(io, join(("id", "generation", "area", "A_star", "inhibited", "clipped_sites"), '\t'))
    for c in ids
        inside = count(w -> w[3] == c, win)
        println(io, join((c, only(unique(w[4] for w in win if w[3] == c)), volume[c], round(Float64(A_star[c]); digits = 6), Int(code[c] > 0), volume[c] - inside), '\t'))
    end
end

finished = now()
git(args...) = readchomp(Cmd(`git $args`; dir = ROOT))
open(joinpath(DIR, "window_cells.toml"), "w") do io
    TOML.print(io, Dict(
        "item" => "P6.15 rewrite (D-185)", "decisions" => ["D-146", "D-157", "D-175", "D-185"],
        "case" => "a", "run" => K, "seed" => SEED, "mcs" => mcs, "N" => N,
        "record_mcs" => REC_MCS, "record_N" => REC_N, "matches_record" => true, "matches_window" => true, "generations_match" => gens_match,
        "window_cells" => length(ids), "cut_by_window" => count(c -> volume[c] > count(w -> w[3] == c, win), ids),
        "commit" => git("rev-parse", "HEAD"), "dirty_tracked" => !isempty(git("status", "--porcelain", "--untracked-files=no")),
        "runner_sha256" => bytes2hex(open(sha256, @__FILE__)), "protocol_test_sha256" => bytes2hex(open(sha256, TEST)),
        "julia" => string(VERSION), "threads" => Threads.nthreads(), "cpu" => Sys.cpu_info()[1].model,
        "affinity" => get(ENV, "POTTS_AFFINITY", ""), "memory_cap" => get(ENV, "POTTS_MEMCAP", ""),
        "started" => string(started), "finished" => string(finished), "run_wall_s" => round(wall; digits = 1)))
end
@info "done" length(ids)

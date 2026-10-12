# D-229: the F1 panel reframed. The D-175 block (window_d175.tsv, centred where the 45° ray
# from the colony centroid leaves the colony) is about 56 % tissue, with the rim running
# corner to corner; the other frameworks' closeups are about 65–75 % tissue, with the rim
# entering through the top edge and leaving through the right edge. This reruns the same
# state as `run_f1.jl` and `run_f1_areas.jl` (case (a) run 1, seed 15701, 1400², the D-173
# protocol of the frozen F3/F8 test, loaded the same way), checks the D-175 block site for
# site, then moves the 64 × 64 window's centre inward along the same ray, `s` sites at a
# time (0, 0.5, …, 30), and keeps the candidate whose tissue share is nearest 70 % among
# those with a share in [65 %, 75 %] whose rim enters through the top edge and leaves
# through the right edge (top row and right column hold both tissue and medium; the left
# column and bottom row hold no medium). Writes:
#
# - window_candidates.tsv: every candidate (s, offset, tissue share, edge rule);
# - window.tsv: the chosen block (lattice site, owner id, generation), as window_d175.tsv;
# - window_cells.tsv, window_cells.toml: the chosen block's cells with their full-state area,
#   A*, the O5 `inhibited` flag and sites outside the window, and this run's provenance.
#
#     [F1_STATE=<path>] taskset -c 0-5,16-21 julia -t 1 --project=lib/PottsModels/test \
#         lib/PottsModels/reproductions/data/15/f1-f4-2026-10-08/run_f1_reframe.jl
using Potts, PottsModels, Test
using Potts: CorePotts
using Statistics: mean
using Dates, TOML, SHA, Serialization

const started = now()
const DIR = @__DIR__
const ROOT = normpath(joinpath(DIR, "..", "..", "..", "..", "..", ".."))
const TEST = joinpath(ROOT, "lib", "PottsModels", "test", "reproductions", "15_openvt_f3_f8.jl")
const RECORD = joinpath(DIR, "..", "f3-f8-2026-10-08", "runs.tsv")
const W = 64
const SHARE = (0.65, 0.75)
const TARGET = 0.70

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

# ---- the D-175 block ----------------------------------------------------------------------------
old = [parse.(Int, split(l, '\t')) for l in readlines(joinpath(DIR, "window_d175.tsv"))[2:end]]
const OLD_OFF = (minimum(w[1] for w in old) - 1, minimum(w[2] for w in old) - 1)

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
for (x, y, o, g) in old
    σ[x, y] == o || error("site ($x, $y): the rerun's owner $(σ[x, y]) is not window_d175.tsv's $o")
end
old_gens = all(w -> w[3] == 0 || gen[w[3]] == w[4], old)
state = get(ENV, "F1_STATE", "")
isempty(state) || serialize(state, (; mcs, σ, volume, A_star = Array(A_star), generation = gen))

# ---- the ray (the rule of openvt_f1_figure's rim window, PottsModelsMakieExt._rim_window) --------
sz = size(σ)
occ = findall(>(0), σ)
c = (mean(I[1] for I in occ), mean(I[2] for I in occ))
d = (1, 1) ./ sqrt(2)
const t = let t = 0.0
    for τ in 0:0.25:maximum(sz)
        I = round.(Int, c .+ τ .* d)
        all(1 .<= I .<= sz) || break
        σ[I...] > 0 && (t = τ)
    end
    t
end
offset(s) = Tuple(clamp.(round.(Int, c .+ (t - s) .* d .- (W + 1) / 2), 0, sz .- W))
offset(0) == OLD_OFF || error("the ray rule gives $(offset(0)) at s = 0, not the D-175 offset $OLD_OFF")

function judge(off)
    B = σ[off[1] .+ (1:W), off[2] .+ (1:W)]                 # B[i, j]: x = off[1] + i, y = off[2] + j
    share = count(>(0), B) / W^2
    both(v) = any(==(0), v) && any(>(0), v)
    top, right, left, bottom = B[:, W], B[W, :], B[1, :], B[:, 1]
    rule = both(top) && both(right) && !any(==(0), left) && !any(==(0), bottom)
    (; share, rule, top_medium = count(==(0), top), right_medium = count(==(0), right),
       left_medium = count(==(0), left), bottom_medium = count(==(0), bottom))
end
cands = [(; s, off = offset(s), judge(offset(s))...) for s in 0:0.5:30]
open(joinpath(DIR, "window_candidates.tsv"), "w") do io
    println(io, join(("s", "x0", "y0", "tissue_share", "top_right_rule", "top_medium", "right_medium", "left_medium", "bottom_medium"), '\t'))
    for k in cands
        println(io, join((k.s, k.off..., round(k.share; digits = 6), Int(k.rule), k.top_medium, k.right_medium, k.left_medium, k.bottom_medium), '\t'))
    end
end
ok = filter(k -> k.rule && SHARE[1] <= k.share <= SHARE[2], cands)
isempty(ok) && error("no candidate along the ray has a tissue share in $SHARE with the top-to-right rim")
best = ok[argmin([(abs(k.share - TARGET), k.s) for k in ok])]
@info "chosen" best.s best.off best.share

# ---- the chosen block ---------------------------------------------------------------------------
off = best.off
open(joinpath(DIR, "window.tsv"), "w") do io
    println(io, join(("x", "y", "owner", "generation"), '\t'))
    for j in 1:W, i in 1:W
        x, y = off[1] + i, off[2] + j
        o = σ[x, y]
        println(io, join((x, y, o, o == 0 ? 0 : gen[o]), '\t'))
    end
end
win = [(off[1] + i, off[2] + j, σ[off[1] + i, off[2] + j]) for j in 1:W for i in 1:W]
ids = sort!(unique(o for (_, _, o) in win if o > 0))
fr = PottsModels.openvt_frame(u; β = CASE.beta, γ = CASE.gamma)
live = findall(>(0), volume)
code = Dict(cc => fr.i[j] for (j, cc) in enumerate(live))
open(joinpath(DIR, "window_cells.tsv"), "w") do io
    println(io, join(("id", "generation", "area", "A_star", "inhibited", "clipped_sites"), '\t'))
    for cc in ids
        inside = count(w -> w[3] == cc, win)
        println(io, join((cc, gen[cc], volume[cc], round(Float64(A_star[cc]); digits = 6), Int(code[cc] > 0), volume[cc] - inside), '\t'))
    end
end

finished = now()
git(args...) = readchomp(Cmd(`git $args`; dir = ROOT))
open(joinpath(DIR, "window_cells.toml"), "w") do io
    TOML.print(io, Dict(
        "item" => "P6.15n (D-229)", "decisions" => ["D-146", "D-157", "D-175", "D-185", "D-229"],
        "case" => "a", "run" => K, "seed" => SEED, "mcs" => mcs, "N" => N,
        "record_mcs" => REC_MCS, "record_N" => REC_N, "matches_record" => true,
        "matches_d175_window" => true, "d175_generations_match" => old_gens, "d175_offset" => collect(OLD_OFF),
        "centroid" => collect(c), "rim_t" => t, "inset_s" => best.s, "window_offset" => collect(off), "window" => W,
        "tissue_share" => best.share, "tissue_share_band" => collect(SHARE), "tissue_share_target" => TARGET,
        "d175_tissue_share" => cands[1].share,
        "window_cells" => length(ids), "window_medium_sites" => count(w -> w[3] == 0, win),
        "cut_by_window" => count(cc -> volume[cc] > count(w -> w[3] == cc, win), ids),
        "commit" => git("rev-parse", "HEAD"), "dirty_tracked" => !isempty(git("status", "--porcelain", "--untracked-files=no")),
        "runner_sha256" => bytes2hex(open(sha256, @__FILE__)), "protocol_test_sha256" => bytes2hex(open(sha256, TEST)),
        "julia" => string(VERSION), "threads" => Threads.nthreads(), "cpu" => Sys.cpu_info()[1].model,
        "affinity" => get(ENV, "POTTS_AFFINITY", ""), "memory_cap" => get(ENV, "POTTS_MEMCAP", ""),
        "started" => string(started), "finished" => string(finished), "run_wall_s" => round(wall; digits = 1)))
end
@info "done" best.s off best.share length(ids)

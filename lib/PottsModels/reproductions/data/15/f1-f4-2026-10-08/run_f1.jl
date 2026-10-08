# P6.15h: OpenVT Fig 1, the Potts.jl panel and banner (G:results/introduction.tex:50-92;
# D-175), from the first state with N ≥ 10⁴ cells of case (a) run 1 (seed 15701, 1400², the
# D-173 protocol). One FULL rerun of the P6.15f record's run (`../f3-f8-2026-10-08/`):
#
# - the protocol is the frozen F3/F8 test's (`15_openvt_f3_f8.jl`): every top-level
#   `P615F_*` constant and `p615f_*` function is evaluated from its source, as
#   `run_f3_f8.jl` does, and the run is `p615f_run(p615f_problem(1400, 10⁴), 15701, case a)`,
#   the problem of that record (one problem per lattice, sized for the 10⁴ stop);
# - the run must stop at the MCS and N of case (a) run 1 in `../f3-f8-2026-10-08/runs.tsv`,
#   else the script stops before writing anything.
#
# Writes into this directory: fig1.png (`PottsModels.openvt_f1_figure(renderframe(u))`),
# fig1_colony.png (the whole colony, the panel's window shaded), window.tsv (the panel's
# 64 × 64 block: lattice site, owner id, generation), meta.toml and provenance.toml.
# F1_STATE (optional): a path where the full render frame is serialized (not committed).
#
#     taskset -c 0-11,16-27 julia -t 1 --project=lib/PottsModels/test \
#         lib/PottsModels/reproductions/data/15/f1-f4-2026-10-08/run_f1.jl
using Potts, PottsModels, Test
using Potts: CorePotts
using Statistics: mean
using CairoMakie, MakiePotts
using Dates, TOML, SHA, Serialization

const started = now()
const DIR = @__DIR__
const ROOT = normpath(joinpath(DIR, "..", "..", "..", "..", "..", ".."))
const TEST = joinpath(ROOT, "lib", "PottsModels", "test", "reproductions", "15_openvt_f3_f8.jl")
const F1TEST = joinpath(ROOT, "lib", "PottsModels", "test", "reproductions", "15_openvt_f1_f4.jl")
const RECORD = joinpath(DIR, "..", "f3-f8-2026-10-08", "runs.tsv")

# ---- the frozen F3/F8 test's constants and rules, verbatim -------------------------------------
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

# ---- the record's row for case (a) run 1 -------------------------------------------------------
const CASE = P615F_CASES.a
const K = 1
const SEED = CASE.seed(K)
rows = [split(l, '\t') for l in readlines(RECORD)]
hdr = Dict(String(h) => i for (i, h) in enumerate(rows[1]))
rec = only(r for r in rows[2:end] if r[hdr["case"]] == "a" && parse(Int, r[hdr["k"]]) == K)
parse(Int, rec[hdr["seed"]]) == SEED || error("the record's case (a) run 1 has seed $(rec[hdr["seed"]]), not $SEED")
const REC_MCS = parse(Int, rec[hdr["mcs"]])
const REC_N = parse(Int, rec[hdr["N"]])

# ---- the run --------------------------------------------------------------------------------------
# the record's problem on 1400²: sized for the largest stop count on that lattice
cells_L = maximum(d.cells for d in values(P615F_CASES) if d.L == CASE.L)
prob = p615f_problem(CASE.L, cells_L)
wall = @elapsed r = p615f_run(prob, SEED, CASE)
u = r.u
N = count(>(0), Array(u.cell.volume))
mcs = Int(r.mcs)
@info "run" r.retcode mcs N series_N = r.series.N[end] wall
(r.retcode === :Terminated && mcs == REC_MCS && N == REC_N && r.series.N[end] == REC_N) ||
    error("the rerun differs from the record: retcode $(r.retcode), MCS $mcs (record $REC_MCS), N $N (record $REC_N)")

# ---- the figure -----------------------------------------------------------------------------------
frame = renderframe(u; mcs)
fig = PottsModels.openvt_f1_figure(frame)
save(joinpath(DIR, "fig1.png"), fig; px_per_unit = 2)
ax = only(b for b in fig.content if b isa Axis)
w = only(p for p in ax.scene.plots if p isa PottsPlot).frame[]
g = frame_geometry(w)
off = round.(Int, g.origin ./ g.spacing)            # the block's offset in the lattice (spacing 1)
W = frame_size(w)[1]
σ = Array(u.σ)
owner(fr, I) = (o = owner_at(fr, I); o.kind === CellSite ? Int(o.id) : 0)
# the block is the lattice's, unchanged
all(I -> owner(w, I) == σ[off[1] + I[1], off[2] + I[2]], CartesianIndices((W, W))) ||
    error("the panel's block is not the state's")
open(joinpath(DIR, "window.tsv"), "w") do io
    println(io, join(("x", "y", "owner", "generation"), '\t'))
    for I in CartesianIndices((W, W))
        o = owner(w, I)
        gen = o == 0 ? 0 : Int(cell_metadata(w, owner_at(w, I)).identity.generation)
        println(io, join((off[1] + I[1], off[2] + I[2], o, gen), '\t'))
    end
end
ids = unique(filter(>(0), [owner(w, I) for I in CartesianIndices((W, W))]))

# the whole colony, the panel's block shaded (a filled square without a stroke)
occ = findall(!=(0), σ)
lo = minimum(occ); hi = maximum(occ)
pad = 20
lim = (max(1, min(lo[1], lo[2]) - pad) - 1, min(size(σ, 1), max(hi[1], hi[2]) + pad))
cfig = Figure(; size = (900, 900), backgroundcolor = :white)
cax = Axis(cfig[1, 1]; aspect = DataAspect(), title = "case (a) run 1, seed $SEED: MCS $mcs, N = $N; F1 window $(W)²")
hidedecorations!(cax); hidespines!(cax)
pottsplot!(cax, frame; encoding = CellIdentityEncoding(), medium_color = :white, boundaries = false)
poly!(cax, Rect2f(off[1], off[2], W, W); color = (:black, 0.25), strokewidth = 0)
limits!(cax, lim..., lim...)
save(joinpath(DIR, "fig1_colony.png"), cfig; px_per_unit = 2)

state = get(ENV, "F1_STATE", "")
isempty(state) || serialize(state, frame)

# ---- records -------------------------------------------------------------------------------------
finished = now()
open(joinpath(DIR, "meta.toml"), "w") do io
    TOML.print(io, Dict(
        "item" => "P6.15h", "decisions" => ["D-146", "D-156", "D-172", "D-173", "D-175"],
        "figure" => "OpenVT M Fig 1, Potts.jl panel and banner (PottsModels.openvt_f1_figure, window = $W)",
        "case" => "a", "run" => K, "seed" => SEED, "lattice" => CASE.L, "stop_cells" => CASE.cells,
        "beta" => CASE.beta, "gamma" => CASE.gamma, "sigma_X" => CASE.sigma_X,
        "algorithm" => "SequentialCPM(; proposal = Moore(1))",
        "problem" => "p615f_problem($(CASE.L), $cells_L) of the frozen F3/F8 test (capacity $(ceil(Int, 1.3cells_L) + 100))",
        "retcode" => string(r.retcode), "mcs" => mcs, "N" => N, "cycles" => mcs / P615F_CYCLE,
        "record_mcs" => REC_MCS, "record_N" => REC_N, "matches_record" => true,
        "window_offset" => collect(off), "window" => W, "window_cells" => length(ids),
        "window_medium_sites" => count(I -> owner(w, I) == 0, CartesianIndices((W, W))),
        "run_wall_s" => round(wall; digits = 1), "threads" => Threads.nthreads()))
end
git(args...) = readchomp(Cmd(`git $args`; dir = ROOT))
manifest = joinpath(ROOT, "Manifest.toml")
open(joinpath(DIR, "provenance.toml"), "w") do io
    TOML.print(io, Dict(
        "commit" => git("rev-parse", "HEAD"), "commit_date" => git("log", "-1", "--format=%cs"),
        "dirty_tracked" => !isempty(git("status", "--porcelain", "--untracked-files=no")),
        "test" => "lib/PottsModels/test/reproductions/15_openvt_f1_f4.jl", "test_sha256" => bytes2hex(open(sha256, F1TEST)),
        "protocol_test" => "lib/PottsModels/test/reproductions/15_openvt_f3_f8.jl",
        "protocol_test_sha256" => bytes2hex(open(sha256, TEST)),
        "record" => "lib/PottsModels/reproductions/data/15/f3-f8-2026-10-08/runs.tsv",
        "record_sha256" => bytes2hex(open(sha256, RECORD)),
        "runner" => relpath(@__FILE__, ROOT), "runner_sha256" => bytes2hex(open(sha256, @__FILE__)),
        "extension_sha256" => bytes2hex(open(sha256, joinpath(ROOT, "lib", "PottsModels", "ext", "PottsModelsMakieExt.jl"))),
        "manifest_sha256" => isfile(manifest) ? bytes2hex(open(sha256, manifest)) : "missing",
        "julia" => string(VERSION), "threads" => Threads.nthreads(), "machine" => Sys.MACHINE,
        "hostname" => gethostname(), "cpu" => Sys.cpu_info()[1].model, "affinity" => get(ENV, "POTTS_AFFINITY", ""),
        "memory_cap" => get(ENV, "POTTS_MEMCAP", ""),
        "started" => string(started), "finished" => string(finished),
        "wall_s" => round(Dates.value(finished - started) / 1000; digits = 1), "run_wall_s" => round(wall; digits = 1),
        "item" => "P6.15h", "decisions" => ["D-146", "D-157", "D-175"]))
end
@info "done" mcs N wall_s = Dates.value(finished - started) / 1000 window_offset = off cells_in_window = length(ids)

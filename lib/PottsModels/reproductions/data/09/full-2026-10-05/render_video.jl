# Re-render of the replicate-1 video of the 2026-10-05 FULL run (P6.0bf, D-156: no cell outlines).
#
# No states were saved by the FULL run, so replicate 1 is re-solved with the recorded seed and
# settings (`page_meta.toml`): `graner_glazier_aggregate(1000; seed = 1, margin = 60)`,
# `GranerGlazier` defaults, problem seed 1, `SequentialCPM(; proposal = Moore(1))`, to 2×10⁴
# paper MCS (16 MCS each). The solve, the saves and the video call are the page's video cell
# (`09_cell_sorting.jl`, §5 "Replicate 1 as a video") in its FULL form, without
# `boundaries = true`. The trajectory check: the annealed bond counts of the end state are
# compared with replicate 1 of `timeseries.tsv` at 20 000 (the page's own `bond_counts` and
# `annealed`, copied verbatim). Stills: the frame nearest 10, 10², 10³, 10⁴ and 2×10⁴ paper MCS.
#
#     julia --project=docs lib/PottsModels/reproductions/data/09/full-2026-10-05/render_video.jl <outdir>
using Potts, PottsModels, MakiePotts, CairoMakie
using Dates, TOML
CairoMakie.activate!(type = "png")

const OUT = abspath(get(ARGS, 1, "."))
const HERE = @__DIR__
const PAPER_MCS = 16
const SEED = 1
const MARGIN = 60
meta = TOML.parsefile(joinpath(HERE, "page_meta.toml"))
ts = Int.(meta["saves_paper_mcs"])
@assert meta["page_seed"] == SEED && meta["margin"] == MARGIN && meta["paper_mcs_per_mcs"] == PAPER_MCS
started = now()

σ0, k0 = graner_glazier_aggregate(1000; seed = meta["start_seeds"][1], margin = MARGIN)
gg = GranerGlazier(; name = :gg, lattice = size(σ0))
prob0 = PottsProblem(gg, [ownership => σ0, kind => k0], (0, 1); seed = SEED)
alg = SequentialCPM(; proposal = Moore(1))
prob = remake(prob0; tspan = (0, PAPER_MCS * 1000))

## the page's video cell (FULL), without `boundaries = true`
video_t = unique(round.(Int, PAPER_MCS .* exp10.(range(0, log10(last(ts)); length = 100))))
q1 = remake(prob; tspan = (0, PAPER_MCS * last(ts)), replica = prob.replica + 1)
q1 = remake(q1; u0 = [ownership => σ0, kind => k0])
wall = @elapsed video = solve(q1, alg; saveat = video_t)
file = joinpath(OUT, "09_cell_sorting_full-2026-10-05_replicate1.mp4")
rec = @elapsed record_potts(file, video; framerate = 12, title = "", figure = (; size = (420, 420)))

## trajectory check against the recorded time series (page helpers, verbatim)
function bond_counts(σ, k)
    n = Dict(:dd => 0, :ll => 0, :dl => 0, :dM => 0, :lM => 0)
    nx, ny = size(σ)
    for y in 1:ny, x in 1:nx, (dx, dy) in ((1, 0), (0, 1), (1, 1), (1, -1))
        a = σ[x, y]
        b = σ[mod1(x + dx, nx), mod1(y + dy, ny)]
        a == b && continue
        a == 0 && ((a, b) = (b, a))
        key = b == 0 ? (k[a] == 1 ? :dM : :lM) : k[a] == k[b] ? (k[a] == 1 ? :dd : :ll) : :dl
        n[key] += 1
    end
    return n
end
function annealed(σ, k, run; seed = 1)
    q = PottsProblem(GranerGlazier(; name = :anneal, lattice = size(σ)),
        [ownership => copy(σ), kind => k, :J => getp(run, :J)(run), :λ => getp(run, :λ)(run),
            :V₀ => getp(run, :V₀)(run), :T => 0.0], (0, 2PAPER_MCS); seed)
    return ownership(solve(q, SequentialCPM(); saveat = 2PAPER_MCS).u[end])
end
b = bond_counts(annealed(ownership(video.u[end]), k0, prob), k0)
total = sum(values(b))
rows = split.(readlines(joinpath(HERE, "timeseries.tsv")), '\t')
hdr = rows[1]
want = Dict(zip(hdr, only(r for r in rows[2:end] if r[1] == "1" && r[2] == string(last(ts)))))
check = Dict("mismatched_bonds" => (total, parse(Float64, want["mismatched_bonds"])))
for (key, col) in ((:dl, "F_dl"), (:dd, "F_dd"), (:ll, "F_ll"), (:dM, "F_dM"), (:lM, "F_lM"))
    check[col] = (b[key] / total, parse(Float64, want[col]))
end
same = all(((ours, rec),) -> isapprox(ours, rec; rtol = 1e-9, atol = 1e-12), values(check))
@info "trajectory check at $(last(ts)) paper MCS" same check

## stills
stills = String[]
for tp in (10, 100, 1000, 10_000, last(ts))
    i = argmin(abs.(video.t .- PAPER_MCS * tp))
    fig = Figure(size = (420, 440))
    ax = Axis(fig[1, 1]; aspect = DataAspect(), title = "replicate 1, t = $(round(Int, video.t[i] / PAPER_MCS)) paper MCS")
    hidedecorations!(ax)
    pottsplot!(ax, renderframe(video.u[i]))
    png = joinpath(OUT, "09_cell_sorting_full-2026-10-05_replicate1_t$(tp).png")
    save(png, fig)
    push!(stills, basename(png))
end

git(args...) = try
    readchomp(Cmd(`git $args`; dir = HERE))
catch
    ""
end
open(joinpath(OUT, "render_provenance.toml"), "w") do io
    TOML.print(io, Dict(
        "item" => "P6.0bf", "decision" => "D-156", "script" => "lib/PottsModels/reproductions/data/09/full-2026-10-05/render_video.jl",
        "commit" => git("rev-parse", "HEAD"), "dirty" => !isempty(git("status", "--porcelain", "--", "lib", "src")),
        "julia" => string(VERSION), "machine" => Sys.MACHINE, "cpu" => Sys.cpu_info()[1].model, "hostname" => gethostname(),
        "threads" => Threads.nthreads(), "backend" => "CPU", "algorithm" => string(alg),
        "start" => "graner_glazier_aggregate(1000; seed = 1, margin = $MARGIN)", "problem_seed" => SEED,
        "replica" => Int(q1.replica), "frames" => length(video.u), "framerate" => 12,
        "video" => basename(file), "video_mb" => round(filesize(file) / 2^20; digits = 2), "stills" => stills,
        "solve_wall_s" => round(wall; digits = 1), "record_wall_s" => round(rec; digits = 1),
        "started" => string(started), "finished" => string(now()),
        "trajectory_check" => Dict("paper_mcs" => last(ts), "matches_timeseries_tsv" => same,
            "ours" => Dict(k => v[1] for (k, v) in check), "recorded" => Dict(k => v[2] for (k, v) in check))); sorted = true)
end
@info "done" file same wall rec

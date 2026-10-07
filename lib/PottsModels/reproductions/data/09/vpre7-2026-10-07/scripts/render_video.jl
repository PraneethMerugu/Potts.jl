# P6.1h: video of the V-PRE7 temperature scan. Replicate 1 (start seed 3001, run seed 13001)
# at each of the eight temperatures, re-solved with the recorded settings and 100 log-spaced
# frames to 10⁴ paper MCS, drawn side by side (dark kind blue, light kind green, medium
# black; no cell outlines, D-156). Saving does not change a run: at every recorded save
# that is also a frame, the annealed heterotypic fraction and mismatched-bond count are
# compared with `timeseries.tsv`. Also writes stills of the grid at 10², 10³ and 10⁴.
#
#     julia -t <k> --project=docs scripts/render_video.jl <record dir> <outdir>
using Potts, PottsModels, MakiePotts, CairoMakie
using Dates, TOML
CairoMakie.activate!(type = "png")

const REC, OUT = abspath(ARGS[1]), abspath(ARGS[2])
const PAPER_MCS = 16
const START, RUN = 3001, 13001
const TS = (0.0, 2.0, 5.0, 10.0, 15.0, 20.0, 40.0, 80.0)
mkpath(OUT)
started = now()

function bond_counts(σ, k)        # the page's, verbatim
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
    ## page fix (P6.1h): a problem's cells are the labels 1:maximum(σ), so drop the kinds of
    ## vanished cells above the largest label left; with no cell left there is nothing to anneal
    top = maximum(σ)
    top == 0 && return copy(σ)
    q = PottsProblem(GranerGlazier(; name = :anneal, lattice = size(σ)),
        [ownership => copy(σ), kind => k[1:top], :J => getp(run, :J)(run), :λ => getp(run, :λ)(run),
            :V₀ => getp(run, :V₀)(run), :T => 0.0], (0, 2PAPER_MCS); seed)
    return ownership(solve(q, SequentialCPM(); saveat = 2PAPER_MCS).u[end])
end

σ0, k0 = graner_glazier_aggregate(1000; seed = START, margin = 60)
alg = SequentialCPM(; proposal = Moore(1))
video_t = unique(round.(Int, PAPER_MCS .* exp10.(range(0, 4; length = 100))))
probs = [PottsProblem(GranerGlazier(; name = :gg, lattice = size(σ0)), [ownership => σ0, kind => k0, :T => T],
    (0, PAPER_MCS * 10_000); seed = RUN) for T in TS]
solve(remake(probs[1]; tspan = (0, 1)), alg)
sols = Vector{Any}(undef, length(TS))
wall = @elapsed Threads.@threads for i in eachindex(TS)
    sols[i] = solve(probs[i], alg; saveat = video_t)
end

## trajectory check against the record
rows = split.(readlines(joinpath(REC, "timeseries.tsv")), '\t')
hdr = rows[1]
c(name) = findfirst(==(name), hdr)
check = Dict{String, Any}()
same = true
for (i, T) in enumerate(TS), r in rows[2:end]
    (parse(Float64, r[c("T")]) == T && r[c("start_seed")] == string(START)) || continue
    t = parse(Int, r[c("paper_mcs")])
    j = findfirst(==(PAPER_MCS * t), sols[i].t)
    j === nothing && continue
    b = bond_counts(annealed(ownership(sols[i].u[j]), k0, probs[i]), k0)
    N = sum(values(b))
    ok = N == parse(Float64, r[c("mismatched_bonds")]) && b[:dl] == parse(Float64, r[c("N_dl")])
    global same &= ok
    check["T$(Int(T))_t$t"] = ok
end
@info "trajectory check" same length(check)

## the grid video and stills (no outlines: pottsplot's default)
frame(i, j) = renderframe(sols[i]; index = j)
function grid(j)
    fig = Figure(size = (1200, 640))
    obs = Observable[]
    for (i, T) in enumerate(TS)
        o = Observable(frame(i, j))
        ax = Axis(fig[fld1(i, 4), mod1(i, 4)]; aspect = DataAspect(), title = "T = $(Int(T))")
        hidedecorations!(ax); hidespines!(ax)
        pottsplot!(ax, o)
        push!(obs, o)
    end
    lab = Label(fig[0, :], "t = $(round(Int, sols[1].t[j] / PAPER_MCS)) paper MCS"; fontsize = 18)
    return fig, obs, lab
end
file = joinpath(OUT, "09_cell_sorting_vpre7-2026-10-07_temperatures.mp4")
fig, obs, lab = grid(1)
rec = @elapsed record(fig, file, eachindex(video_t); framerate = 12) do j
    for i in eachindex(TS)
        obs[i][] = frame(i, j)
    end
    lab.text[] = "t = $(round(Int, sols[1].t[j] / PAPER_MCS)) paper MCS"
end
stills = String[]
for tp in (100, 1000, 10_000)
    j = argmin(abs.(sols[1].t .- PAPER_MCS * tp))
    f, _, _ = grid(j)
    png = joinpath(OUT, "09_cell_sorting_vpre7-2026-10-07_temperatures_t$(tp).png")
    save(png, f)
    push!(stills, basename(png))
end
git(args...) = try
    readchomp(Cmd(`git $args`; dir = REC))
catch
    ""
end
open(joinpath(OUT, "render_provenance.toml"), "w") do io
    TOML.print(io, Dict("item" => "P6.1h", "script" => "lib/PottsModels/reproductions/data/09/vpre7-2026-10-07/scripts/render_video.jl",
        "commit" => git("rev-parse", "HEAD"), "julia" => string(VERSION), "cpu" => Sys.cpu_info()[1].model,
        "hostname" => gethostname(), "threads" => Threads.nthreads(), "backend" => "CPU",
        "start" => "graner_glazier_aggregate(1000; seed = $START, margin = 60)", "problem_seed" => RUN,
        "temperatures" => collect(TS), "frames" => length(video_t), "framerate" => 12, "video" => basename(file),
        "video_mb" => round(filesize(file) / 2^20; digits = 2), "stills" => stills, "solve_wall_s" => round(wall; digits = 1),
        "record_wall_s" => round(rec; digits = 1), "started" => string(started), "finished" => string(now()),
        "trajectory_check" => Dict("matches_timeseries_tsv" => same, "saves" => check)); sorted = true)
end
@info "done" file same

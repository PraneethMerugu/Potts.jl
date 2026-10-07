# Shared helpers for the paper-run scripts (included by each `docs/paper_runs/<model>.jl`).
# Not part of the docs build: these scripts are run offline and their outputs committed.
using Potts, CorePotts, PottsModels, MakiePotts, CairoMakie
using Dates: now
import TOML

const REPO = dirname(dirname(@__DIR__))
const ASSETS = joinpath(REPO, "docs", "src", "assets", "paper_runs")
mkpath(ASSETS)

git_commit() = try
    strip(read(`git -C $REPO rev-parse --short HEAD`, String)) *
    (isempty(strip(read(`git -C $REPO status --porcelain -- lib src`, String))) ? "" : "-dirty")
catch
    "unknown"
end

"""
    Panel(name; encoding = CellTypeEncoding(), plot = (;), channels = u -> (), colorbar = nothing)

One panel of a paper-run video: a `pottsplot` of every saved state with `encoding` and the
recipe attributes `plot`. `channels(u)` returns the `RenderChannel`s the encoding needs
(e.g. a site field of the saved state `u`). `colorbar = (label, colormap, limits)` adds a
colour bar.
"""
Base.@kwdef struct Panel
    name::String = ""
    encoding = CellTypeEncoding()
    plot::NamedTuple = (;)
    channels::Function = u -> ()
    colorbar = nothing
end
Panel(name; kw...) = Panel(; name, kw...)

"""Record the saved states of `sol` as an mp4: one axis per panel, a fixed title, an MCS clock."""
function record_run(file, sol, panels; title, framerate = 30, size = (720, 760),
        clock = t -> "t = $t MCS", frames = eachindex(sol.u))
    frame(p, i) = renderframe(sol; index = i, channels = p.channels(sol.u[i]))
    fig = Figure(; size, fontsize = 14)
    Label(fig[0, 1:length(panels)], title; fontsize = 15, font = :bold, tellwidth = false)
    clk = Observable(clock(sol.t[first(frames)]))
    Label(fig[2, 1:length(panels)], clk; fontsize = 15, tellwidth = false)
    obs = map(enumerate(panels)) do (j, p)
        sub = fig[1, j] = GridLayout()
        ax = Axis(sub[1, 1]; title = p.name, aspect = DataAspect())
        hidedecorations!(ax)
        o = Observable(frame(p, first(frames)))
        pottsplot!(ax, o; encoding = p.encoding, p.plot...)
        tightlimits!(ax)
        if p.colorbar !== nothing
            label, cmap, limits = p.colorbar
            Colorbar(sub[1, 2]; colormap = cmap, limits, label, height = Relative(0.8))
        end
        o
    end
    tmp = joinpath(dirname(file), "." * basename(file))
    record(fig, tmp, frames; framerate) do i
        for (o, p) in zip(obs, panels)
            o[] = frame(p, i)
        end
        clk[] = clock(sol.t[i])
    end
    mv(tmp, file; force = true)
    return file
end

"""
    paper_run(name; prob, alg, saveat, title, panels, framerate, size, clock, frames, meta, solve_kw)

Warm up (a 2-MCS copy of `prob`), solve `prob` with `alg` saving at `saveat`, record
`docs/src/assets/paper_runs/<name>.mp4` (`record_run`), re-encode it with ffmpeg (H.264,
CRF 28, yuv420p) when it is larger than 5 MB, and write the sidecar `<name>.toml`.
`frames(sol)` picks the saved states to record (default: all); `title` may be a function of
`sol` and the recorded frame indices.
"""
function paper_run(name; prob, alg, saveat, title, panels, framerate = 30, size = (720, 760),
        clock = t -> "t = $t MCS", frames = sol -> eachindex(sol.u), meta = Dict{String, Any}(), solve_kw = (;))
    t0, t1 = prob.tspan
    solve(remake(prob; tspan = (t0, t0 + 2)), alg; solve_kw...)          # compile
    wall = @elapsed sol = solve(prob, alg; saveat, save_start = true, solve_kw...)
    @info "$name: solved $(t1 - t0) MCS in $(round(wall; digits = 1)) s, $(length(sol.u)) frames"
    mp4 = joinpath(ASSETS, "$name.mp4")
    idx = frames(sol)
    title isa Function && (title = title(sol, idx))
    meta isa Function && (meta = meta(sol, idx))
    rec = @elapsed record_run(mp4, sol, panels; title, framerate, size, clock, frames = idx)
    if filesize(mp4) > 5 * 2^20
        tmp = joinpath(ASSETS, ".$name.reenc.mp4")
        run(`$(CairoMakie.Makie.FFMPEG_jll.ffmpeg()) -v error -y -i $mp4 -c:v libx264 -crf 28 -preset slow -pix_fmt yuv420p -an $tmp`)
        mv(tmp, mp4; force = true)
    end
    info = merge(Dict{String, Any}(
            "title" => title,
            "lattice" => collect(Base.size(sol.u[1].σ)),
            "tspan" => [t0, t1],
            "frames" => length(idx),
            "recorded_mcs" => [sol.t[first(idx)], sol.t[last(idx)]],
            "framerate" => framerate,
            "seed" => Int(prob.seed),
            "algorithm" => string(alg),
            "backend" => "CPU",
            "cpu" => strip(Sys.cpu_info()[1].model),
            "machine" => Sys.MACHINE,
            "hostname" => gethostname(),
            "threads" => Threads.nthreads(),
            "solve_wall_s" => round(wall; digits = 1),
            "record_wall_s" => round(rec; digits = 1),
            "video_mb" => round(filesize(mp4) / 2^20; digits = 2),
            "git_commit" => git_commit(),
            "julia" => string(VERSION),
            "date" => string(now()),
            "script" => "docs/paper_runs/$name.jl"), meta)
    open(joinpath(ASSETS, "$name.toml"), "w") do io
        TOML.print(io, info; sorted = true)
    end
    @info "$name: wrote $mp4 ($(info["video_mb"]) MB)"
    return sol, info
end

# FULL run of the frozen page `lib/PottsModels/reproductions/10_akeeb.jl` (P6.2d; D-146 record).
# Usage, from the checkout root on the producing machine:
#   POTTS_FULL_REPRODUCTION=true WT=<checkout> OUT=<output dir> \
#       julia --project=docs -t 12 lib/PottsModels/reproductions/data/10/full-2026-10-07/run_wrapper.jl
# Literate executes the page in its own module with one export chunk appended after the last
# cell (D-146). One substitution is made in the executed text, and recorded in
# provenance.toml: the page's videos pass `boundaries = true`, and D-156 forbids drawing cell
# outlines, so the run renders them with `boundaries = false`. Rendering does not touch the
# simulations (the page's own check re-solves replicate 1 and compares it with the ensemble).
using Literate, Dates, TOML
const WT = ENV["WT"]
const OUT = ENV["OUT"]
const DATA = joinpath(OUT, "data", "10")
mkpath(DATA)
page = joinpath(WT, "lib", "PottsModels", "reproductions", "10_akeeb.jl")
const OUTLINES = "plot = (; boundaries = true,"
const NO_OUTLINES = "plot = (; boundaries = false,"
started = now()
@info "start" started Threads.nthreads() VERSION ENV["POTTS_FULL_REPRODUCTION"]
dump = """

#-
#hide
let dir = $(repr(DATA))
    clean(x) = replace(string(x), r"[\\t\\n]" => " ")
    open(joinpath(dir, "verdicts.tsv"), "w") do io
        println(io, join(("target", "paper", "ours", "tolerance", "class", "result"), '\\t'))
        for r in rows
            println(io, join(clean.((r.target, r.paper, r.ours, r.tol, r.class, display_result(r))), '\\t'))
        end
    end
    M = (:invasive, :infiltrative, :singles, :fingers, :detached, :clusters)
    open(joinpath(dir, "timeseries.tsv"), "w") do io
        println(io, join(("point", "J_LF", "lambda", "PP", "replicate", "seed", "paper_mcs", M..., "divisions"), '\\t'))
        for (k, name) in enumerate(keys(POINTS))
            haskey(runs, name) || continue
            for (i, r) in enumerate(runs[name]), t in sort(collect(keys(r.obs)))
                println(io, join((name, POINTS[name]..., i, seed_of(k, i), t, (getproperty(r.obs[t], m) for m in M)...,
                    r.divisions), '\\t'))
            end
        end
        for (i, r) in enumerate(runs_va0), t in sort(collect(keys(r.obs)))
            println(io, join(("VA0", POINTS.P1..., i, 100_000 + i, t, (getproperty(r.obs[t], m) for m in M)...,
                r.divisions), '\\t'))
        end
    end
    slice_runs === nothing || open(joinpath(dir, "slice.tsv"), "w") do io
        println(io, join(("slice_point", "J_LF", "lambda", "PP", "replicate", "seed", "paper_mcs", M..., "divisions"), '\\t'))
        for (j, s) in enumerate(slice_runs), (i, r) in enumerate(s.runs)
            println(io, join((j, s.k..., i, 1_000_000 + 100j + i, 700, (getproperty(r.obs[700], m) for m in M)...,
                r.divisions), '\\t'))
        end
    end
    open(joinpath(dir, "clusters.tsv"), "w") do io
        println(io, join(("point", "replicate", "cluster", "leaders", "followers"), '\\t'))
        for name in (:P1, :P2), (i, r) in enumerate(get(runs, name, []))
            o = r.obs[700]
            for (c, (l, f)) in enumerate(zip(o.cluster_leaders, o.cluster_followers))
                println(io, join((name, i, c, l, f), '\\t'))
            end
        end
    end
    open(joinpath(dir, "page_meta.toml"), "w") do io
        Main.TOML.print(io, Dict("replicates_per_point" => 10, "slice_points" => length(SLICE), "slice_replicates" => 10,
            "point_seeds" => "10000k + i (k = point index P1..P9, i = 1..10)", "va0_seeds" => "100000 + i",
            "slice_seeds" => "1000000 + 100j + i (j = slice point, J_LF-major)",
            "saves_our_mcs" => SAVES, "saves_paper_mcs" => SAVES .- 1, "threads" => Threads.nthreads(),
            "one_run_s" => t_one, "algorithm" => "SequentialCPM(; proposal = VonNeumann(1))", "capacity" => 4000))
    end
end
nothing #hide
"""
src = read(page, String)
@assert count(OUTLINES, src) == 1 "the page's video call changed; re-check the substitution"
t = @elapsed Literate.markdown(page, OUT; documenter = true, credit = false, execute = true,
    preprocess = s -> replace(s, OUTLINES => NO_OUTLINES) * dump)
git(args...) = readchomp(Cmd(`git $args`; dir = WT))
open(joinpath(DATA, "provenance.toml"), "w") do io
    TOML.print(io, Dict(
        "commit" => git("rev-parse", "HEAD"), "commit_date" => git("log", "-1", "--format=%cs"),
        "dirty" => !isempty(git("status", "--porcelain", "--untracked-files=no")),
        "page" => "lib/PottsModels/reproductions/10_akeeb.jl",
        "page_sha256" => first(split(readchomp(`sha256sum $page`))),
        "executed_substitution" => "$(OUTLINES) => $(NO_OUTLINES) (D-156: no cell outlines; rendering only)",
        "env" => "POTTS_FULL_REPRODUCTION=" * ENV["POTTS_FULL_REPRODUCTION"], "julia" => string(VERSION),
        "threads" => Threads.nthreads(), "machine" => Sys.MACHINE, "hostname" => gethostname(),
        "cpu" => Sys.cpu_info()[1].model, "affinity" => get(ENV, "POTTS_AFFINITY", ""),
        "started" => string(started), "finished" => string(now()), "wall_s" => round(t; digits = 1),
        "item" => "P6.2d", "decision" => "D-156"))
end
@info "done" now() wall_s = t

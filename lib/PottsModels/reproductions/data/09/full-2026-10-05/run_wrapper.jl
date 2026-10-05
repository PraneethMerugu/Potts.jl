using Literate, Dates, TOML
const WT = "/Users/praneethmerugu/Documents/Jiang/CPM 1.6/PottsEcosystem/PottsWorktrees/p6-1f-run"
const OUT = "/Users/praneethmerugu/Documents/Jiang/CPM 1.6/PottsEcosystem/PottsWorktrees/p6-1f-out"
const DATA = joinpath(OUT, "data", "09")
page = joinpath(WT, "lib", "PottsModels", "reproductions", "09_cell_sorting.jl")
started = now()
@info "start" started Threads.nthreads() VERSION ENV["POTTS_FULL_REPRODUCTION"]
# Appended export chunk (not part of the frozen page): runs in the page's own module after the
# last cell, so it sees the ensemble arrays and the verdict rows. The page is executed unchanged.
dump = """

#-
#hide
let dir = $(repr(DATA))
    open(joinpath(dir, "verdicts.tsv"), "w") do io
        println(io, join(("target", "paper", "ours", "tolerance", "class", "result"), '\\t'))
        clean(x) = replace(string(x), r"[\\t\\n]" => " ")
        for r in targets
            println(io, join(clean.((r.target, r.paper, r.ours, r.tol, r.class, r.result)), '\\t'))
        end
    end
    open(joinpath(dir, "timeseries.tsv"), "w") do io
        println(io, join(("replicate", "paper_mcs", "F_dl", "F_dd", "F_ll", "F_dM", "F_lM", "mismatched_bonds", "isolated"), '\\t'))
        for i in 1:n, (j, t) in enumerate(ts)
            println(io, join((i, t, (F[k][i, j] for k in keys5)..., Nmm[i, j], clear[i, j]), '\\t'))
        end
    end
    open(joinpath(dir, "clusters.tsv"), "w") do io
        println(io, join(("replicate", "paper_mcs", "dark_clusters", "largest_dark_cluster"), '\\t'))
        for i in 1:n, (c, t) in enumerate(cluster_t)
            println(io, join((i, t, ncluster[i, c], largest[i, c]), '\\t'))
        end
    end
    open(joinpath(dir, "page_meta.toml"), "w") do io
        Main.TOML.print(io, Dict("replicates" => n, "page_seed" => SEED, "start_seeds" => collect(1:n),
            "margin" => MARGIN, "paper_mcs_per_mcs" => PAPER_MCS, "saves_paper_mcs" => ts,
            "threads" => Threads.nthreads(), "algorithm" => "SequentialCPM(; proposal = Moore(1))"))
    end
end
nothing #hide
"""
t = @elapsed Literate.markdown(page, OUT; documenter = true, credit = false, execute = true,
    preprocess = s -> s * dump)
git(args...) = readchomp(Cmd(`git $args`; dir = WT))
open(joinpath(DATA, "provenance.toml"), "w") do io
    TOML.print(io, Dict(
        "commit" => git("rev-parse", "HEAD"), "commit_date" => git("log", "-1", "--format=%cs"),
        "dirty" => !isempty(git("status", "--porcelain")),
        "page" => "lib/PottsModels/reproductions/09_cell_sorting.jl",
        "page_sha256" => first(split(readchomp(`shasum -a 256 $page`))),
        "env" => "POTTS_FULL_REPRODUCTION=" * ENV["POTTS_FULL_REPRODUCTION"], "julia" => string(VERSION),
        "threads" => Threads.nthreads(), "machine" => Sys.MACHINE, "cpu" => Sys.cpu_info()[1].model,
        "started" => string(started), "finished" => string(now()), "wall_s" => round(t; digits = 1),
        "item" => "P6.1f", "decision" => "D-144"))
end
@info "done" now() wall_s = t

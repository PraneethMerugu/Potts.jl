# P6.3f: write provenance.toml for the reproduction 01 FULL record (D-146, D-156).
# usage (on the producing machine, in the run's worktree): julia provenance.jl <outdir> <logfile>
using TOML, Dates
const OUT, LOG = abspath(ARGS[1]), abspath(ARGS[2])
root = normpath(joinpath(@__DIR__, "..", "..", "..", "..", "..", ".."))
git(args...) = readchomp(Cmd(`git $args`; dir = root))
sha(p) = first(split(readchomp(`sha256sum $(joinpath(root, p))`)))
rows = [TOML.parsefile(joinpath(OUT, "rows", f)) for f in readdir(joinpath(OUT, "rows")) if endswith(f, ".toml")]
loglines = readlines(LOG)
launches = filter(startswith("launch "), loglines)
open(joinpath(OUT, "provenance.toml"), "w") do io
    TOML.print(io, Dict(
        "item" => "P6.3f", "decisions" => ["D-146", "D-153", "D-156"],
        "commit" => git("rev-parse", "HEAD"), "dirty" => !isempty(git("status", "--porcelain", "--untracked-files=no")),
        "frozen_test" => "lib/PottsModels/test/reproductions/01_merks.jl",
        "frozen_test_sha256" => sha("lib/PottsModels/test/reproductions/01_merks.jl"),
        "page" => "lib/PottsModels/reproductions/01_merks.jl",
        "page_sha256" => sha("lib/PottsModels/reproductions/01_merks.jl"),
        "runner" => "lib/PottsModels/reproductions/data/01/full-2026-10-08/run_full.jl",
        "env" => "POTTS_FULL_REPRODUCTION unset in the runner (the frozen FULL tier's jobs are run one replicate per job)",
        "julia" => string(VERSION), "hostname" => gethostname(), "machine" => Sys.MACHINE,
        "cpu" => strip(Sys.cpu_info()[1].model), "threads" => 12, "affinity" => "taskset -c 0-5,16-21; MemoryMax=40G",
        "launches" => launches, "jobs" => length(rows),
        "cpu_s_sum_of_jobs" => round(sum(r -> r["wall_s"], rows); digits = 1),
        "first_finished" => minimum(r -> r["finished"], rows), "last_finished" => maximum(r -> r["finished"], rows),
        "seeds" => "pre-registered in the frozen test; per job in replicates.tsv",
        "written" => string(now())))
end

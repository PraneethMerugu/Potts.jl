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
# per-job wall from the log (rows recovered from snapshots carry wall_s = -1)
logtext = read(LOG, String)
ts(s) = DateTime(s, dateformat"yyyy-mm-ddTHH:MM:SS.sss")
starts = Dict(m[2] => ts(m[1]) for m in eachmatch(r"\[(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3})\] start (\S+)", logtext))
ends = Dict(m[3] => ts(m[1]) for m in eachmatch(r"\[(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3})\] (done|FAILED) ([^\s:]+)", logtext))
walls = Dict{String, Float64}()
for r in rows
    k = r["key"]
    walls[k] = r["wall_s"] >= 0 ? r["wall_s"] :
               (haskey(starts, k) && haskey(ends, k) ? Dates.value(ends[k] - starts[k]) / 1000 : NaN)
end
open(joinpath(OUT, "job_walls.tsv"), "w") do io
    println(io, "key\twall_s\tsource")
    for r in sort(rows; by = r -> r["key"])
        println(io, r["key"], '\t', round(walls[r["key"]]; digits = 1), '\t', r["wall_s"] >= 0 ? "row" : "log")
    end
end
known = filter(!isnan, collect(values(walls)))
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
        "thread_s_sum_of_jobs" => round(sum(known); digits = 1), "jobs_with_known_wall" => length(known),
        "recovered_from_snapshot" => count(r -> get(r, "recovered_from_snapshot", false), rows),
        "first_job_start" => string(minimum(values(starts))), "last_job_end" => string(maximum(values(ends))),
        "seeds" => "pre-registered in the frozen test; per job in replicates.tsv",
        "written" => string(now())))
end

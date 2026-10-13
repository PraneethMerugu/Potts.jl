# Reproduction 04 (foam): the T1-neighbourhood check (spec 04 §5.6). Not a frozen file.
#
# One trajectory, two T1 detectors. Each run is the frozen D-205 bulk-shear run (R1,
# `P64RShearedFoam`, T → 0⁺, D-205 foams, τ, seeds and caps) and counts T1s per MCS from the
# bubble contact graph under both
#   vn1  VonNeumann(1), edge sharing (the current observable, spec 04 §2.8), and
#   no4  NeighborOrder(4), the 20-site interaction shell of Eq. 1 (the paper's own neighbours?),
# with the same `t1_events(unit = :t1)` and the same first-T1 rule (`p64kb_settled`). A run
# stops when both detectors have settled, or at the cap.
#
#   julia --project=lib/PottsModels/test lib/PottsModels/reproductions/data/04/run_t1_nbhd_check.jl \
#       --out <dir> [--threads N] [--dry-run] [--tiny N]
using Potts, PottsModels, Test, TOML, Dates, Serialization, SHA
using Statistics: mean, median

const USAGE = "usage: --out <dir> [--threads N] [--dry-run] [--tiny N]"
function parse_args(args)
    o = Dict{String, Any}("out" => "", "threads" => 0, "dry" => false, "tiny" => 0)
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--dry-run"
            o["dry"] = true
        elseif a in ("--out", "--threads", "--tiny") && i < length(args)
            o[a[3:end]] = a == "--out" ? args[i + 1] : parse(Int, args[i + 1])
            i += 1
        else
            error("run_t1_nbhd_check.jl: unknown argument $a ($USAGE)")
        end
        i += 1
    end
    isempty(o["out"]) && error("run_t1_nbhd_check.jl: --out <dir> is required ($USAGE)")
    return o
end
const OPT = parse_args(ARGS)

if OPT["threads"] > 0 && OPT["threads"] != Threads.nthreads()
    rest = let r = String[], drop = false
        for a in ARGS
            drop && (drop = false; continue)
            a == "--threads" && (drop = true; continue)
            push!(r, a)
        end
        r
    end
    cmd = `$(Base.julia_cmd()) --threads=$(OPT["threads"]) --project=$(Base.active_project()) $(abspath(PROGRAM_FILE)) $rest`
    exit(success(run(ignorestatus(cmd))) ? 0 : 1)
end

const OUT = abspath(OPT["out"])
const ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", "..", ".."))
const DATA04 = joinpath(ROOT, "lib", "PottsModels", "reproductions", "data", "04")
const FROZEN = joinpath(ROOT, "lib", "PottsModels", "test", "reproductions", "04_foam_kb_scan.jl")
(OUT == DATA04 || startswith(OUT, DATA04 * "/")) &&
    error("run_t1_nbhd_check.jl: --out must be outside reproductions/data/04")
const TINY = OPT["tiny"] > 0
const JOBS = joinpath(OUT, TINY ? "jobs-tiny" : "jobs")
mkpath(JOBS)
logmsg(s...) = (println(stdout, "[", now(), "] ", s...); flush(stdout))

# ------------------------------------------------------------------------------------------
# The frozen tests (D-190 helpers, D-205 rule) as the gate
# ------------------------------------------------------------------------------------------
for k in ("P64KB_SCAN", "P64KB_OUT", "POTTS_FULL_REPRODUCTION", "REPRO", "P64R_RECORD_OUT")
    haskey(ENV, k) && delete!(ENV, k)
end
logmsg("including the frozen tests (SMOKE gate) with ", Threads.nthreads(), " threads")
const GATE = Test.DefaultTestSet("04 T1-neighbourhood check gate")
Test.push_testset(GATE)
t_gate = try
    @elapsed include(FROZEN)
finally
    Test.pop_testset()
end
for ts in GATE.results
    c = Test.get_test_counts(ts)
    c.fails + c.errors + c.cumulative_fails + c.cumulative_errors == 0 ||
        error("T1-neighbourhood check: the frozen gate failed in $(ts.description)")
end
P64R_SHEAR_READY || error("T1-neighbourhood check: the shear model is not on this tree")
logmsg("frozen gate passed in ", round(t_gate; digits = 1), " s")

# ------------------------------------------------------------------------------------------
# Design (spec 04 §5.6)
# ------------------------------------------------------------------------------------------
const NB_I = collect(-4:2:4)
const NB_GRID = P64KB_KAPPA_D190 .* 2.0 .^ (NB_I ./ 2)
const DETECTORS = (vn1 = VonNeumann(1), no4 = NeighborOrder(4))
cap(β) = TINY ? 30 : P64KB_CAP[β]

"""One run, both detectors on the same trajectory."""
function nb_run(st, βm, capβ, seed, τ)
    lat = p64r_lat(size(st.σ))
    T = p64r_ours(capβ, τ)
    w = round(Int, 100τ)
    integ = init(p64r_problem(st, T; shear = true, β = βm, bulk = true, seed), P64R_ALG)
    g = map(nb -> P64R_AN.cell_graph(st.σ, lat; neighborhood = nb), DETECTORS)
    N = map(_ -> zeros(T), DETECTORS)
    for m in 1:T
        step!(integ)
        for k in keys(DETECTORS)
            g2 = P64R_AN.cell_graph(integ.u.σ, lat; neighborhood = DETECTORS[k])
            N[k][m] = P64R_AN.t1_events(g[k], g2; unit = :t1)
            g = merge(g, NamedTuple{(k,)}((g2,)))
        end
        (m % w == 0 || m == T) || continue
        d = map(n -> p64kb_settled(view(n, 1:m), τ, w; final = m == T), N)
        all(x -> x.done, d) || continue
        tf(x) = x.tf === nothing ? -1 : round(Int, x.tf)
        return (mcs_run = m, t_first_vn1 = tf(d.vn1), t1_total_vn1 = sum(view(N.vn1, 1:m)),
            t_first_no4 = tf(d.no4), t1_total_no4 = sum(view(N.no4, 1:m)),
            first_change_no4 = something(findfirst(>(0), view(N.no4, 1:m)), -1),
            first_change_vn1 = something(findfirst(>(0), view(N.vn1, 1:m)), -1))
    end
end

struct Job
    key::String
    cost::Float64
    run::Function
end
jobpath(key) = joinpath(JOBS, key * ".jls")
isdone(key) = isfile(jobpath(key))
function save(key, x)
    tmp = jobpath(key) * ".tmp-$(Threads.threadid())"
    serialize(tmp, x)
    mv(tmp, jobpath(key); force = true)
end
load(key) = deserialize(jobpath(key))

function run_pool(jobs, stage)
    todo = sort(filter(j -> !isdone(j.key), jobs); by = j -> -j.cost)
    logmsg(stage, ": ", length(jobs), " jobs, ", length(jobs) - length(todo), " done, ", length(todo), " to run")
    isempty(todo) && return String[]
    ch = Channel{Job}(length(todo))
    foreach(j -> put!(ch, j), todo)
    close(ch)
    failed = String[]
    lk = ReentrantLock()
    n = Threads.Atomic{Int}(0)
    t0 = time()
    @sync for _ in 1:Threads.nthreads()
        Threads.@spawn for j in ch
            try
                tj = @elapsed res = j.run()
                save(j.key, res)
                k = Threads.atomic_add!(n, 1) + 1
                logmsg(stage, " ", k, "/", length(todo), " ", j.key, " ", round(tj; digits = 1), " s (",
                    round((time() - t0) / 3600; digits = 2), " h)")
            catch e
                lock(() -> push!(failed, j.key), lk)
                logmsg(stage, " FAILED ", j.key, ": ", sprint(showerror, e))
            end
        end
    end
    return failed
end

runkey(i, j, k) = "nb_$(lpad(i, 2, '0'))_$(j)_$(k)"
const SCHED = [(i, κ, j, β, k) for (i, κ) in enumerate(NB_GRID) for (j, β) in enumerate(P64KB_BETAS) for k in 1:P64KB_N]
logmsg("T1-neighbourhood check: ", length(SCHED), " runs")
if OPT["dry"]
    logmsg("dry run: nothing run")
    exit(0)
end

const T_START = now()
p64r_template(true, P64R_L)
foamkey(k) = "foam_ordered_$(k)"
failed = run_pool([Job(foamkey(k), 1_010.0, () -> p64r_foam(:ordered, k)) for k in 1:P64KB_TAU_FOAMS], "foams")
isempty(failed) || error("foam jobs failed: $failed (rerun to resume)")
const FOAMS = [load(foamkey(k)) for k in 1:P64KB_TAU_FOAMS]
const τ = 1 / mean(row["ubar"] for (_, row) in FOAMS)
logmsg("τ = ", τ)

function job(i, κ, j, β, k)
    st = FOAMS[k][1]
    seed = p64kb_seed(j, k)
    return Job(runkey(i, j, k), Float64(p64r_ours(cap(β), τ)),
        () -> merge(nb_run(st, κ * β, cap(β), seed, τ),
            (; kappa_b = κ, beta = β, beta_model = κ * β, k, seed, tau = τ, cap = cap(β))))
end
const ALL = [job(s...) for s in SCHED]
const RUN = TINY ? ALL[1:min(OPT["tiny"], end)] : ALL
failed = run_pool(RUN, "runs")
isempty(failed) || error("runs failed: $failed (rerun to resume)")
TINY && (logmsg("tiny harness check done: ", length(RUN), " jobs"); exit(0))

const COLS = ["kappa_b", "beta", "beta_model", "k", "seed", "tau", "cap", "mcs_run", "t_first_vn1", "t1_total_vn1",
    "first_change_vn1", "t_first_no4", "t1_total_no4", "first_change_no4"]
open(joinpath(OUT, "scan.tsv"), "w") do io
    println(io, join(COLS, '\t'))
    for s in SCHED
        x = load(runkey(s[1], s[3], s[5]))
        println(io, join((getfield(x, Symbol(c)) for c in COLS), '\t'))
    end
end
open(joinpath(OUT, "provenance.toml"), "w") do io
    TOML.print(io, Dict("protocol" => "spec 04 §5.6", "commit" => readchomp(`git -C $ROOT rev-parse HEAD`),
        "frozen_sha256" => bytes2hex(sha256(read(FROZEN))), "runner_sha256" => bytes2hex(sha256(read(@__FILE__))),
        "threads" => Threads.nthreads(), "julia" => string(VERSION), "machine" => Sys.cpu_info()[1].model,
        "tau" => τ, "started" => string(T_START), "finished" => string(now())))
end
logmsg("done: ", OUT)

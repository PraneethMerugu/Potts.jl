# Reproduction 04 (foam): the Eq 2 screen runner (spec 04 §5.4). Not a frozen file.
#
# Runs the pre-registered screen of two readings of Eq 2 under bulk shear (Eq 7) against the
# frozen D-205 targets:
#   R2  force on bubbles: ΔH = −Σ_{c ∈ new, old} κ_b·β·(Y_c − y_mid)·ΔX_c (script-local model);
#   R3  the frozen displacement form (R1, `P64RShearedFoam`) at T ∈ {0.5, 1.5};
#   R3h the same at T ∈ {3, 5} on a grid extended down to i = −16 (spec 04 §5.5), with a
#       β = 0 thermal control at each T (κ_b = 0; reported, not passed to the decision rule).
# Everything else is D-205: the 5 ordered foams and τ, β ∈ P64KB_BETAS, 3 replicates with the
# seeds `p64kb_seed`, the caps `P64KB_CAP`, the early stop and t_first/T1 of `p64kb_run`, and the
# frozen decision rule `p64kb_analyse` applied unchanged to each table.
#
# The frozen tests are `include`d unchanged (their SMOKE tiers run first as a gate). Resumable:
# each finished job is written to <out>/jobs/<key>.jls and a rerun skips it.
#
#   julia --project=lib/PottsModels/test lib/PottsModels/reproductions/data/04/run_eq2_screen.jl \
#       --out <dir> [--threads N] [--only r2|r3|r3h] [--dry-run] [--tiny N]
#
# Without --only the original §5.4 set (r2, r3) runs; r3h runs only when asked for.
#
# `--tiny N` runs the first N jobs of the schedule with the cap cut to 30 paper MCS into
# <out>/jobs-tiny/ (a harness check, not a result) and writes no tables.
using Potts, PottsModels, Test, TOML, Dates, Serialization, SHA
using Statistics: mean, median

const USAGE = "usage: --out <dir> [--threads N] [--only r2|r3|r3h] [--dry-run] [--tiny N]"
function parse_args(args)
    o = Dict{String, Any}("out" => "", "threads" => 0, "dry" => false, "tiny" => 0, "only" => "")
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--dry-run"
            o["dry"] = true
        elseif a in ("--out", "--threads", "--tiny", "--only") && i < length(args)
            o[a[3:end]] = a in ("--out", "--only") ? args[i + 1] : parse(Int, args[i + 1])
            i += 1
        else
            error("run_eq2_screen.jl: unknown argument $a ($USAGE)")
        end
        i += 1
    end
    isempty(o["out"]) && error("run_eq2_screen.jl: --out <dir> is required ($USAGE)")
    o["only"] in ("", "r2", "r3", "r3h") || error("run_eq2_screen.jl: --only must be r2, r3 or r3h")
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
    error("run_eq2_screen.jl: --out must be outside reproductions/data/04")
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
const GATE = Test.DefaultTestSet("04 Eq 2 screen gate")
Test.push_testset(GATE)
t_gate = try
    @elapsed include(FROZEN)
finally
    Test.pop_testset()
end
for ts in GATE.results
    c = Test.get_test_counts(ts)
    c.fails + c.errors + c.cumulative_fails + c.cumulative_errors == 0 ||
        error("Eq 2 screen: the frozen gate failed in $(ts.description)")
end
P64R_SHEAR_READY || error("Eq 2 screen: the shear model is not on this tree")
logmsg("frozen gate passed in ", round(t_gate; digits = 1), " s")

# ------------------------------------------------------------------------------------------
# R2: force on bubbles (script-local model; spec 04 §5.4)
# ------------------------------------------------------------------------------------------
@potts_model Eq2R2Foam begin
    @structural_parameters begin
        lattice = (256, 256)
    end
    @kinds medium bubble
    @parameters begin
        J = 3.0
        Γ = 1.0
        T = 1.0e-6
        γ0 = 0.0
        β = 0.0
        bulk = 0.0
        periodic = 0.0
        ω = 2π / 4000
        ytop = 256.0
        ymid = 128.5
    end
    @variables begin
        A(cell) = 256.0
        cy(cell) = 0.0                       # centroid y at the end of the previous MCS
    end
    @lattice Lattice(lattice; boundary = (Periodic(), Closed()), neighborhood = NeighborOrder(4))
    @relations proposal = NeighborOrder(4)
    @energy begin
        contacts => J
        cells(bubble) => Γ * (volume - A)^2
    end
    @drive copy => -β * ((cy[new] - ymid) * displacement(new, 1) + (cy[old] - ymid) * displacement(old, 1))
    @after_mcs cy ~ centroid(2)
    @sweep Metropolis(; temperature = T)
end

"""Centroid y of ids 1:n (y is closed, so the plain mean)."""
function centroid_y(σ, n)
    s = zeros(n)
    c = zeros(Int, n)
    for y in axes(σ, 2), x in axes(σ, 1)
        k = σ[x, y]
        s[k] += y
        c[k] += 1
    end
    return s ./ c
end

const R2_TEMPLATE = Dict{Tuple{Int, Int}, Any}()
function r2_template(L)
    get!(R2_TEMPLATE, L) do
        σ = p64r_brick(L)
        n = Int(maximum(σ))
        sys = Eq2R2Foam(; name = :eq2_r2, lattice = L)
        PottsProblem(sys, Pair[ownership => σ, kind => fill(:bubble, n), :A => fill(256.0, n),
                :cy => centroid_y(σ, n), :ytop => Float64(L[2]), :ymid => (L[2] + 1) / 2], (0, 1); seed = 1)
    end
end
function r2_problem(st, tend; β, seed)
    L = size(st.σ)
    n = length(st.A)
    p = Pair{Symbol, Float64}[:J => P64R_J, :Γ => P64R_Γ, :T => P64R_T0, :γ0 => 0.0, :β => β, :bulk => 1.0,
        :periodic => 0.0, :ω => 2π / P64R_PERIOD, :ytop => Float64(L[2]), :ymid => (L[2] + 1) / 2]
    return remake(R2_TEMPLATE[L]; u0 = Pair[ownership => st.σ, kind => fill(:bubble, n), :A => st.A,
            :cy => centroid_y(st.σ, n)], p, tspan = (0, tend), seed)
end

"""One screen run: `p64kb_run`'s loop on a given problem builder."""
function screen_run(build, st, cap, τ)
    lat = p64r_lat(size(st.σ))
    T = p64r_ours(cap, τ)
    w = round(Int, 100τ)
    integ = init(build(T), P64R_ALG)
    g = P64R_AN.cell_graph(st.σ, lat)
    N = zeros(T)
    for m in 1:T
        step!(integ)
        g2 = P64R_AN.cell_graph(integ.u.σ, lat)
        N[m] = P64R_AN.t1_events(g, g2; unit = :t1)
        g = g2
        (m % w == 0 || m == T) || continue
        d = p64kb_settled(view(N, 1:m), τ, w; final = m == T)
        d.done && return (t_first = d.tf === nothing ? -1 : round(Int, d.tf), mcs_run = m, t1_total = sum(view(N, 1:m)))
    end
end

# ------------------------------------------------------------------------------------------
# Design (spec 04 §5.4)
# ------------------------------------------------------------------------------------------
const R2_I = collect(0:30)
const R2_GRID = P64KB_KAPPA_D190 .* 2.0 .^ (R2_I ./ 2)
const R3_I = collect(-8:2:14)
const R3_GRID = P64KB_KAPPA_D190 .* 2.0 .^ (R3_I ./ 2)
const R3_T = [0.5, 1.5]
const R3H_I = collect(-16:2:14)
const R3H_GRID = P64KB_KAPPA_D190 .* 2.0 .^ (R3H_I ./ 2)
const R3H_T = [3.0, 5.0]
# (family, name, grid, T); a name starting with "c_" is a β = 0 control, not a decision table.
const READINGS = [("r2", "r2", R2_GRID, nothing); [("r3", "r3_T$(T)", R3_GRID, T) for T in R3_T];
                  [("r3h", "r3_T$(T)", R3H_GRID, T) for T in R3H_T]; [("r3h", "c_T$(T)", [0.0], T) for T in R3H_T]]
iscontrol(r) = startswith(r, "c_")
cap(β) = TINY ? 30 : P64KB_CAP[β]

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

runkey(r, i, j, k) = "$(r)_$(lpad(i, 2, '0'))_$(j)_$(k)"
selected = [R[2:4] for R in READINGS if (OPT["only"] == "" ? R[1] in ("r2", "r3") : R[1] == OPT["only"])]
const SCHED = [(r, i, κ, j, β, k, Tv) for (r, grid, Tv) in selected for (i, κ) in enumerate(grid)
               for (j, β) in enumerate(P64KB_BETAS) for k in 1:P64KB_N]
logmsg("readings ", [R[1] for R in selected], ": ", length(SCHED), " runs")
if OPT["dry"]
    logmsg("dry run: nothing run")
    exit(0)
end

# ------------------------------------------------------------------------------------------
# Stage 0: the 5 ordered foams and τ (D-205), then the runs
# ------------------------------------------------------------------------------------------
const T_START = now()
p64r_template(false, P64R_L)
p64r_template(true, P64R_L)
r2_template(P64R_L)
foamkey(k) = "foam_ordered_$(k)"
failed = run_pool([Job(foamkey(k), 1_010.0, () -> p64r_foam(:ordered, k)) for k in 1:P64KB_TAU_FOAMS], "foams")
isempty(failed) || error("foam jobs failed: $failed (rerun to resume)")
const FOAMS = [load(foamkey(k)) for k in 1:P64KB_TAU_FOAMS]
const τ = 1 / mean(row["ubar"] for (_, row) in FOAMS)
logmsg("τ = ", τ)

function job(r, i, κ, j, β, k, Tv)
    st = FOAMS[k][1]
    seed = p64kb_seed(j, k)
    βm = κ * β
    build = Tv === nothing ? (tend -> r2_problem(st, tend; β = βm, seed)) :
            (tend -> p64r_problem(st, tend; shear = true, β = βm, bulk = true, T = Tv, seed))
    return Job(runkey(r, i, j, k), Float64(p64r_ours(cap(β), τ)), () -> merge(screen_run(build, st, cap(β), τ),
        (; reading = r, kappa_b = κ, beta = β, beta_model = βm, k, seed, tau = τ, cap = cap(β))))
end
const ALL = [job(s...) for s in SCHED]
const RUN = TINY ? ALL[1:min(OPT["tiny"], end)] : ALL
failed = run_pool(RUN, "runs")
isempty(failed) || error("runs failed: $failed (rerun to resume)")
TINY && (logmsg("tiny harness check done: ", length(RUN), " jobs"); exit(0))

# ------------------------------------------------------------------------------------------
# Tables and the frozen decision rule, one per reading
# ------------------------------------------------------------------------------------------
decisions = Dict{String, Any}()
for (r, grid, Tv) in selected
    rows = Dict{String, Any}[]
    for s in SCHED
        s[1] == r || continue
        x = load(runkey(s[1], s[2], s[4], s[6]))
        push!(rows, Dict{String, Any}("kappa_b" => x.kappa_b, "beta" => x.beta, "beta_model" => x.beta_model,
            "k" => x.k, "seed" => x.seed, "tau" => x.tau, "cap" => x.cap, "mcs_run" => x.mcs_run,
            "t_first" => x.t_first, "t1_total" => x.t1_total))
    end
    p64kb_write(joinpath(OUT, r), rows)
    if iscontrol(r)
        ny = count(x -> x["t_first"] >= 0, rows)
        decisions[r] = Dict("control" => "beta_model = 0", "yielded" => ny, "runs" => length(rows),
            "t1_total" => sum(x -> x["t1_total"], rows), "temperature" => Tv)
        logmsg(r, ": β = 0 control, ", ny, "/", length(rows), " yielded")
        continue
    end
    a = p64kb_analyse(rows; grid)
    decisions[r] = Dict("kappa_b" => something(a.kappa_b, "nothing"), "path" => string(a.path),
        "reason" => string(a.reason), "khat" => a.khat, "temperature" => something(Tv, P64R_T0))
    logmsg(r, ": κ_b = ", a.kappa_b, " (", a.path, ", ", a.reason, ")")
end
open(io -> TOML.print(io, decisions), joinpath(OUT, "decision.toml"), "w")
open(joinpath(OUT, "provenance.toml"), "w") do io
    TOML.print(io, Dict("protocol" => "spec 04 §5.4", "decision_rule" => "D-205 p64kb_analyse (frozen)",
        "commit" => readchomp(`git -C $ROOT rev-parse HEAD`), "frozen_sha256" => bytes2hex(sha256(read(FROZEN))),
        "runner_sha256" => bytes2hex(sha256(read(@__FILE__))), "threads" => Threads.nthreads(),
        "julia" => string(VERSION), "machine" => Sys.cpu_info()[1].model, "tau" => τ,
        "started" => string(T_START), "finished" => string(now())))
end
logmsg("done: ", OUT)

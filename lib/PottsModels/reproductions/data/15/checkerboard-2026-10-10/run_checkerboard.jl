# P6.15m m3 (ROADMAP; D-214, D-216, D-218, D-220): the characterisation record of the OpenVT
# entry "Potts.jl (checkerboard)", `CheckerboardCPM(; proposal = Moore(1))` on the PC's GPU
# (ROCm), against the CPU `SequentialCPM` entry "Potts.jl". The schema is the frozen test's
# `lib/PottsModels/test/reproductions/15_openvt_checkerboard.jl`; its `p615m_*` rules (per-seed
# metrics, the critical value crit(ν), the deviation checker) are loaded from its source
# verbatim, as the P6.15f protocol (`p615f_*`) is loaded from the frozen F3/F8 test by
# `run_reference.jl`, which this runner includes (the sequential replay, `reference_runs.tsv`,
# is that file's output and is not re-run here).
#
# Steps (one host process for the GPU steps, as D-214 asks):
#
#  1. calibrate  The F2 / Table S5 11-chain calibration at λ = 2 (P6.15b protocol: 150 × 5
#                periodic strip, 11 cells compressed to A_c = 25 for a 100-MCS burn-in,
#                `openvt_release(100)`, w₁₁ every MCS, T = the first MCS with mean w₁₁ ≥ 9 CD,
#                per-run crossings the same per run) under CheckerboardCPM on the GPU, 100
#                runs, seeds 214 200 000 + i. Writes calibration.tsv, timeseries_11chain.tsv
#                and <out>/calibration.toml: T_λ2, its sd, the Welch z against the sequential
#                record's λ = 2 crossings (calibration-2026-10-05) at crit(99), and so the
#                cycle and α (D-220: significant ⇒ cycle = 5·T_λ2, α = A₀/(5·T_λ2); else 775
#                and 50/775).
#  2. runs       Cases (a) 10, (b) 100 and (f) 100 runs of the P6.15f protocol (the frozen
#                F3/F8 test's problem, recorder, save cadence 39 MCS, stop at `cells`, edge
#                guard) under CheckerboardCPM on the GPU, with the cycle and α of step 1;
#                seeds 214 100 000 + k (b), 214 100 200 + k (f), 214 100 700 + k (a). Per
#                run: the device planner's form (read from the integrator; no host fallback),
#                divisions, live cells, the series and the O1 summary of the stop state.
#                Appends to <out>/runs_part.tsv, ts_part.tsv, o1_part.tsv (resumable).
#  3. collect    Writes runs.tsv, timeseries.tsv, metrics.tsv (both algorithms), comparison.tsv,
#                reference_o1.tsv, meta.toml and provenance.toml. The sequential arm's metrics:
#                F3–F8 from the P6.15f record's timeseries (cycle 775), `lost` from
#                reference_runs.tsv, O1 from the stop frame of each run in the O1 record's
#                bulk archives (`OPENVT_PACKAGE_BULK`, sha256-checked against
#                o1-2026-10-09/archives.tsv; cached in reference_o1.tsv).
#  4. status     After entry/deviations.tsv is written by hand (D-154): sets meta.toml's
#                status to "final" when the frozen deviation checker finds no problem with
#                final = true, else "provisional".
#
#     P615M_OUT=<dir> systemd-run --user --scope -q -p MemoryMax=24G taskset -c 0-3 \
#         julia -t 4 --project=lib/PottsModels/test \
#         lib/PottsModels/reproductions/data/15/checkerboard-2026-10-10/run_checkerboard.jl calibrate
#     … run_checkerboard.jl runs
#     OPENVT_PACKAGE_BULK=<dir> P615M_OUT=<dir> julia --project=lib/PottsModels/test … run_checkerboard.jl collect
#     julia --project=lib/PottsModels/test … run_checkerboard.jl status
include(joinpath(@__DIR__, "run_reference.jl"))     # p615f_* (P6.15f protocol), ref_*; Potts, PottsModels, Test
using AMDGPU
using Statistics: mean, std
using Dates, TOML, SHA

const CB_DIR = @__DIR__
const CB_ROOT = REF_ROOT
const CB_TEST = joinpath(CB_ROOT, "lib", "PottsModels", "test", "reproductions", "15_openvt_checkerboard.jl")
const CB_OUT = get(ENV, "P615M_OUT", joinpath(CB_DIR, "parts"))
const CB_A = PottsModels.Analysis

# ---- the frozen checkerboard test's constants and rules, verbatim -------------------------------
for ex in Meta.parseall(read(CB_TEST, String)).args
    ex isa Expr || continue
    n = _refdefname(ex)
    (n isa Symbol && startswith(string(n), r"p615m_|P615M_")) || continue
    isdefined(@__MODULE__, n) || Core.eval(@__MODULE__, ex)
end

# ---- protocol -------------------------------------------------------------------------------------
const CB_ALG = CheckerboardCPM(; proposal = Moore(1))
const CB_ALG_STR = "CheckerboardCPM(; proposal = Moore(1))"
const CB_REF_ALG_STR = "SequentialCPM(; proposal = Moore(1))"
const CB_EVERY = P615F_EVERY                         # 39 MCS, the P6.15f save cadence
const CB_CASES = (:a, :b, :f)
const CB_SEED = Dict(:b => k -> 214_100_000 + k, :f => k -> 214_100_200 + k, :a => k -> 214_100_700 + k)
cb_case(c::Symbol) = merge(P615F_CASES[c], (; seed = CB_SEED[c]))
# calibration (P6.15b protocol, λ = 2)
const CAL_LAMBDA = 2
const CAL_N = 100
cal_seed(i) = 214_200_000 + i
const CAL_BURNIN = 100
const CAL_CD = 10
const CAL_LEVEL = 9.0
const CAL_TMAX = 7 * 155                                 # MCS after the release: P6.15b's 7 T_S5(λ = 2)
const CAL_SEQ = normpath(joinpath(CB_DIR, "..", P615M_SEQ_CAL, "crossings.tsv"))
const A0 = 50.0                                          # A₀ (Table S1), α = A₀ / cycle (C1, C16)

cb_backend() = AMDGPU.ROCBackend()
cb_device() = (d = string(AMDGPU.device()); m = match(r"name=([^,)]+)", d); m === nothing ? d : String(m[1]) * " (" * d * ")")
cb_sync() = AMDGPU.synchronize()
cb_git(args...) = readchomp(Cmd(`git $args`; dir = CB_ROOT))
cb_dirty() = !isempty(cb_git("status", "--porcelain", "--untracked-files=no"))
cb_f64(x) = isnan(x) ? "nan" : repr(Float64(x))
cb_clean(x) = replace(string(x), r"[\t\n]" => " ")
function cb_env()
    return Dict("commit" => cb_git("rev-parse", "HEAD"), "dirty_tracked" => cb_dirty(), "julia" => string(VERSION),
        "threads" => Threads.nthreads(), "machine" => Sys.MACHINE, "cpu" => Sys.cpu_info()[1].model,
        "affinity" => get(ENV, "POTTS_AFFINITY", ""))
end

# ---- step 1: the chain calibration ------------------------------------------------------------------
function cal_main()
    mkpath(CB_OUT)
    started = now()
    backend = cb_backend()
    sys = OpenVTChain(; name = :p615m_chain11, lattice = (150, 5), λ = Float64(CAL_LAMBDA))
    prob = PottsProblem(sys, openvt_chain(11), (0, CAL_BURNIN + CAL_TMAX); seed = 1)
    saves = 0:(CAL_BURNIN + CAL_TMAX)
    # compile (result discarded)
    solve(remake(prob; seed = cal_seed(0), tspan = (0, CAL_BURNIN + 20)), CB_ALG; backend, saveat = 0:(CAL_BURNIN + 20),
        callback = openvt_release(CAL_BURNIN))
    W = fill(NaN, length(saves), CAL_N)
    area = fill(NaN, 2, CAL_N)
    sim = @elapsed for j in 1:CAL_N
        sol = solve(remake(prob; seed = cal_seed(j)), CB_ALG; backend, saveat = saves, callback = openvt_release(CAL_BURNIN))
        collect(sol.t) == collect(saves) || error("calibrate: saves $(sol.t[1])…$(sol.t[end]) ≠ $(saves)")
        for (k, u) in enumerate(sol.u)
            xs = CB_A.chain_centroids(Array(u.σ))
            W[k, j] = (maximum(xs) - minimum(xs)) / CAL_CD
        end
        for (r, u) in ((1, sol.u[CAL_BURNIN + 1]), (2, sol.u[end]))
            σ = Array(u.σ)
            area[r, j] = mean(count(==(c), σ) for c in 1:11)
        end
    end
    any(isnan, W) && error("calibrate: NaN width")
    t = collect((-CAL_BURNIN):CAL_TMAX)
    k = t .>= 0
    wbar = vec(mean(W; dims = 2))
    Tc = CB_A.crossing_time(t[k], wbar[k], CAL_LEVEL)
    Tc === nothing && error("calibrate: the mean curve does not reach $(CAL_LEVEL) CD in $(CAL_TMAX) MCS")
    Truns = [CB_A.crossing_time(t[k], W[k, j], CAL_LEVEL) for j in 1:CAL_N]
    any(isnothing, Truns) && error("calibrate: $(count(isnothing, Truns)) runs do not cross in $(CAL_TMAX) MCS")
    Truns = Float64.(Truns)
    Tseq = [p615m_f64(r["T_run"]) for r in p615m_tsv(CAL_SEQ) if parse(Float64, r["lambda"]) == CAL_LAMBDA]
    crit = p615m_crit(length(Tseq), length(Truns))
    cmp = PottsModels.openvt_spread_compare(Tseq, Truns; z = crit)
    cycle = p615m_cycle(cmp.beyond, Tc)
    α = A0 / cycle
    reason = cmp.beyond ?
             "T(λ = 2) = $Tc MCS under CheckerboardCPM against the sequential $(P615M_T_SEQ) MCS: significant (Welch z = $(round(cmp.z; digits = 2)), |z| > crit(ν = $(min(length(Tseq), length(Truns)) - 1)) = $(round(crit; digits = 2)); D-218 rule), so the cycle is 5 T = $(5Tc) MCS and α = A₀/(5 T) = 50/$(5Tc) px/MCS (D-220)" :
             "T(λ = 2) = $Tc MCS under CheckerboardCPM against the sequential $(P615M_T_SEQ) MCS: not significant (Welch z = $(round(cmp.z; digits = 2)), |z| ≤ crit(ν = $(min(length(Tseq), length(Truns)) - 1)) = $(round(crit; digits = 2)); D-218 rule), so the sequential cycle 775 MCS and α = 50/775 px/MCS are kept (D-220)"
    finished = now()
    # outputs: calibration.tsv and the mean curve into the record, the time scale into <out>
    r6(x) = round(x; digits = 6)
    open(joinpath(CB_DIR, "calibration.tsv"), "w") do io
        println(io, join(("lambda", "seed", "T_run", "area_compressed_t0", "area_compressed_end"), '\t'))
        for j in 1:CAL_N
            println(io, join((CAL_LAMBDA, cal_seed(j), Int(Truns[j]), r6(area[1, j]), r6(area[2, j])), '\t'))
        end
    end
    open(joinpath(CB_DIR, "timeseries_11chain.tsv"), "w") do io
        println(io, join(("lambda", "t_mcs", "t_over_T", "w11_mean", "w11_sd"), '\t'))
        s = vec(std(W; dims = 2))
        for (i, ti) in enumerate(t)
            println(io, join((CAL_LAMBDA, ti, r6(ti / Tc), r6(wbar[i]), r6(s[i])), '\t'))
        end
    end
    d = merge(cb_env(), Dict("T_lambda2" => Tc, "T_lambda2_sd" => std(Truns), "T_lambda2_run_mean" => mean(Truns),
        "T_runs" => length(Truns), "T_seq_run_mean" => mean(Tseq), "T_seq_runs" => length(Tseq), "z" => cmp.z, "crit" => crit,
        "beyond" => cmp.beyond, "cycle_mcs" => cycle, "alpha" => α, "alpha_text" => "50/$cycle", "cycle_reason" => reason,
        "tmax_mcs" => CAL_TMAX, "device" => cb_device(), "started" => string(started), "finished" => string(finished),
        "wall_s" => round(Dates.value(finished - started) / 1000; digits = 1), "simulation_s" => round(sim; digits = 1)))
    open(io -> TOML.print(io, d), joinpath(CB_OUT, "calibration.toml"), "w")
    @info "calibration" T_lambda2 = Tc sd = std(Truns) run_mean = mean(Truns) seq_mean = mean(Tseq) z = cmp.z crit beyond = cmp.beyond cycle α sim_s = sim
    println(reason)
    return d
end

# ---- step 2: the monolayer runs ---------------------------------------------------------------------
# the device planner's form: "fused" | "staged" (device) or "host" (no device plan / host planner)
function cb_form(integ)
    integ.lcache === nothing && return "none"
    integ.lcache.device === nothing && return "host"
    f = integ.lcache.device.form[]
    return f == 1 ? "fused" : f == 2 ? "staged" : "host"
end
const CB_PROBS = Dict{Int, Any}()
cb_problem(L) = get!(() -> p615f_problem(L, maximum(d.cells for d in values(P615F_CASES) if d.L == L)), CB_PROBS, L)
# the P6.15f run (`p615f_run`) under CheckerboardCPM on the GPU with this entry's cycle and α
function cb_run(prob, seed, c; cycle, α, cells = c.cells, tmax = nothing, backend = cb_backend())
    rec = NamedTuple[]
    record(integ) = push!(rec, p615f_row(integ.u, integ.t; c.beta, c.gamma))
    cb_rec = Potts.DiscreteCallback((u, t, integ) -> t % CB_EVERY == 0 || count(>(0), u.cell.volume) >= cells,
        record; initialize = (cb, u, t, integ) -> record(integ), save_positions = (false, false))
    p = [:β => c.beta, :γ => c.gamma, :σ_X => c.sigma_X, :α => α]
    pr = tmax === nothing ? remake(prob; seed, p) : remake(prob; seed, p, tspan = (0, tmax))
    integ = init(pr, CB_ALG; backend, save_start = false,
        callback = Potts.CorePotts.CallbackSet(cb_rec, PottsModels.stop_at_cells(cells),
            PottsModels.edge_guard(P615F_GUARD; terminate = true)))
    form0 = cb_form(integ)
    sol = solve!(integ)
    cb_sync()
    form1 = cb_form(integ)
    u = sol.u[end]
    vol = Array(u.cell.volume)
    fr = PottsModels.openvt_frame(u; β = c.beta, γ = c.gamma)
    o1 = (; n_mean = mean(fr.n), n_sd = std(fr.n), n6 = mean(fr.n .== 6), i0 = mean(fr.i .== 0), cells = length(fr.n))
    return (; retcode = Symbol(sol.retcode), mcs = Int(sol.t[end]), rec, divisions = sol.stats.lifecycle.divisions,
        live = count(>(0), vol), form = form0 == form1 ? form0 : "$form0→$form1",
        planner = (form0 in ("fused", "staged") && form1 in ("fused", "staged")) ? "device" : "host", o1)
end
const RUNS_PART_HEADER = ("case", "k", "seed", "retcode", "mcs", "N", "divisions", "live", "planner", "form", "saves", "wall_s")
const TS_HEADER = ("case", "seed", "mcs", "N", "r", "A", "C", "w", "g")
const O1_HEADER = ("case", "seed", "mcs", "cells", "n_mean", "n_sd", "n6", "i0")
cb_part(name) = joinpath(CB_OUT, name)
function cb_header!(path, h)
    isfile(path) || open(io -> println(io, join(h, '\t')), path, "w")
    return path
end
function runs_main()
    cal = TOML.parsefile(cb_part("calibration.toml"))
    cycle, α = cal["cycle_mcs"], cal["alpha"]
    env = cb_env()
    env["commit"] == cal["commit"] || error("runs: commit $(env["commit"]) ≠ the calibration's $(cal["commit"])")
    started = now()
    backend = cb_backend()
    rp = cb_header!(cb_part("runs_part.tsv"), RUNS_PART_HEADER)
    tp = cb_header!(cb_part("ts_part.tsv"), TS_HEADER)
    op = cb_header!(cb_part("o1_part.tsv"), O1_HEADER)
    done = Set((r["case"], parse(Int, r["k"])) for r in p615m_tsv(rp))
    jobs = [(c, k) for c in CB_CASES for k in 1:P615F_CASES[c].runs if !((string(c), k) in done)]
    @info "runs" cycle α todo = length(jobs) done = length(done)
    # compile both lattices (results discarded)
    for L in sort(unique(P615F_CASES[c].L for c in CB_CASES))
        cb_run(cb_problem(L), 1, merge(P615F_CASES.b, (; L)); cycle, α, cells = 2, tmax = 50, backend)
    end
    sim = 0.0
    for (c, k) in jobs
        cc = cb_case(c)
        seed = cc.seed(k)
        wall = @elapsed r = cb_run(cb_problem(cc.L), seed, cc; cycle, α, backend)
        sim += wall
        N = r.rec[end].N
        open(tp, "a") do io
            for x in r.rec
                println(io, join((c, seed, x.mcs, x.N, cb_f64(x.r), cb_f64(x.A), cb_f64(x.C), cb_f64(x.w), cb_f64(x.g)), '\t'))
            end
        end
        open(io -> println(io, join((c, seed, r.mcs, r.o1.cells, cb_f64(r.o1.n_mean), cb_f64(r.o1.n_sd), cb_f64(r.o1.n6),
                cb_f64(r.o1.i0)), '\t')), op, "a")
        open(io -> println(io, join((c, k, seed, r.retcode, r.mcs, N, r.divisions, r.live, r.planner, r.form, length(r.rec),
                round(wall; digits = 2)), '\t')), rp, "a")
        @info "run" c k seed r.retcode r.mcs N r.divisions r.live lost = r.divisions + 1 - r.live r.planner r.form wall = round(wall; digits = 1)
    end
    finished = now()
    log = cb_part("runs_sessions.tsv")
    cb_header!(log, ("started", "finished", "wall_s", "simulation_s", "jobs", "commit", "dirty_tracked", "device", "cpu", "machine",
        "julia", "threads", "affinity"))
    open(io -> println(io, join(cb_clean.((started, finished, round(Dates.value(finished - started) / 1000; digits = 1),
            round(sim; digits = 1), length(jobs), env["commit"], env["dirty_tracked"], cb_device(), env["cpu"], env["machine"],
            env["julia"], env["threads"], env["affinity"])), '\t')), log, "a")
    return nothing
end

# ---- step 3: collect ------------------------------------------------------------------------------
# the sequential arm's O1 summaries: the stop frame of every P6.15f run of a, b, f, read from the
# O1 record's bulk archives (sha256-checked) or from the cached reference_o1.tsv
function ref_o1()
    cache = joinpath(CB_DIR, "reference_o1.tsv")
    bulk = get(ENV, "OPENVT_PACKAGE_BULK", "")
    if isempty(bulk)
        isfile(cache) || error("collect: set OPENVT_PACKAGE_BULK (the O1 archives) or provide reference_o1.tsv")
        return Dict((r["case"], parse(Int, r["seed"])) => r for r in p615m_tsv(cache))
    end
    o1dir = normpath(joinpath(CB_DIR, "..", "o1-2026-10-09"))
    arch = Dict(r["case"] => r for r in p615m_tsv(joinpath(o1dir, "archives.tsv")))
    runs = [r for r in p615m_tsv(joinpath(o1dir, "runs.tsv")) if Symbol(r["case"]) in CB_CASES]
    out = Dict{Tuple{String, Int}, Dict{String, String}}()
    for c in string.(CB_CASES)
        zp = joinpath(bulk, arch[c]["archive"])
        bytes2hex(open(sha256, zp)) == arch[c]["sha256"] || error("collect: $zp differs from archives.tsv")
        for r in filter(r -> r["case"] == c, runs)
            seed, mcs = parse(Int, r["seed"]), parse(Int, r["mcs"])
            member = "centroids/$c/potts_$(c)_s$(seed)_$(lpad(mcs, 6, '0')).csv"
            lines = filter(!isempty, readlines(`unzip -p $zp $member`))
            h = split(lines[1], ',')
            rows = split.(lines[2:end], ',')
            n = [parse(Int, x[findfirst(==("n"), h)]) for x in rows]
            i = [parse(Int, x[findfirst(==("i"), h)]) for x in rows]
            length(n) == parse(Int, r["N"]) || error("collect: $member has $(length(n)) rows, N = $(r["N"])")
            out[(c, seed)] = Dict("case" => c, "seed" => string(seed), "mcs" => string(mcs), "cells" => string(length(n)),
                "n_mean" => cb_f64(mean(n)), "n_sd" => cb_f64(std(n)), "n6" => cb_f64(mean(n .== 6)), "i0" => cb_f64(mean(i .== 0)))
        end
    end
    open(cache, "w") do io
        println(io, join(O1_HEADER, '\t'))
        for key in sort(collect(keys(out)))
            println(io, join((out[key][h] for h in O1_HEADER), '\t'))
        end
    end
    return out
end
o1metrics(r) = Dict("O1.n_mean" => p615m_f64(r["n_mean"]), "O1.n_sd" => p615m_f64(r["n_sd"]), "O1.n6" => p615m_f64(r["n6"]),
    "O1.i0" => p615m_f64(r["i0"]))

function collect_main()
    cal = TOML.parsefile(cb_part("calibration.toml"))
    cycle = cal["cycle_mcs"]
    sess = p615m_tsv(cb_part("runs_sessions.tsv"))
    all(s -> s["commit"] == cal["commit"], sess) || error("collect: the run sessions are not all at the calibration's commit")
    rp = p615m_tsv(cb_part("runs_part.tsv"))
    length(Set((r["case"], r["k"]) for r in rp)) == length(rp) || error("collect: duplicate runs")
    for c in CB_CASES
        count(r -> r["case"] == string(c), rp) == P615F_CASES[c].runs || error("collect: case $c incomplete")
    end
    order(r) = (r["case"], parse(Int, r["k"]))
    sort!(rp; by = order)
    # runs.tsv
    open(joinpath(CB_DIR, "runs.tsv"), "w") do io
        println(io, join(("case", "k", "seed", "beta", "gamma", "sigma_X", "lattice", "retcode", "mcs", "N", "divisions", "live",
            "planner", "form", "cycles", "saves", "wall_s"), '\t'))
        for r in rp
            P = P615F_CASES[Symbol(r["case"])]
            println(io, join((r["case"], r["k"], r["seed"], P.beta, P.gamma, P.sigma_X, P.L, r["retcode"], r["mcs"], r["N"],
                r["divisions"], r["live"], r["planner"], r["form"], round(parse(Int, r["mcs"]) / cycle; digits = 6), r["saves"],
                r["wall_s"]), '\t'))
        end
    end
    # timeseries.tsv, in run order
    tsp = p615m_tsv(cb_part("ts_part.tsv"))
    rank = Dict((r["case"], r["seed"]) => i for (i, r) in enumerate(rp))
    sort!(tsp; by = r -> (rank[(r["case"], r["seed"])], parse(Int, r["mcs"])))
    open(joinpath(CB_DIR, "timeseries.tsv"), "w") do io
        println(io, join(TS_HEADER, '\t'))
        for r in tsp
            println(io, join((r[h] for h in TS_HEADER), '\t'))
        end
    end
    # per-seed metrics, both arms, read back from the tables as the frozen test reads them
    ts = p615m_tsv(joinpath(CB_DIR, "timeseries.tsv"))
    ref_ts = p615m_tsv(joinpath(REF_F3F8, "timeseries.tsv"))
    replay = p615m_tsv(joinpath(CB_DIR, "reference_runs.tsv"))
    o1cb = Dict((r["case"], parse(Int, r["seed"])) => r for r in p615m_tsv(cb_part("o1_part.tsv")))
    o1seq = ref_o1()
    lostof(rows) = Dict(parse(Int, r["seed"]) => parse(Int, r["divisions"]) + 1 - parse(Int, r["live"]) for r in rows)
    M = Dict{Tuple{String, String}, Dict{String, Dict{Int, Float64}}}()
    for c in string.(CB_CASES)
        P = P615M_CASES[c]
        for (alg, sers, lost, o1) in (
            ("sequential", p615m_record_series(ref_ts, c; cycle = P615M_CYCLE_SEQ), lostof([r for r in replay if r["case"] == c]), o1seq),
            ("checkerboard", p615m_record_series(ts, c; cycle), lostof([r for r in rp if r["case"] == c]), o1cb))
            T = Dict(k => Dict{Int, Float64}() for k in P615M_ALL)
            for (sd, s) in sers
                m = p615m_seed_metrics(s, P.cells)
                for k in P615M_METRICS
                    T[k][sd] = m[k]
                end
                T["lost"][sd] = lost[sd]
                for (k, v) in o1metrics(o1[(c, sd)])
                    T[k][sd] = v
                end
            end
            M[(alg, c)] = T
        end
    end
    open(joinpath(CB_DIR, "metrics.tsv"), "w") do io
        println(io, join(("algorithm", "case", "seed", "metric", "value"), '\t'))
        for alg in ("sequential", "checkerboard"), c in string.(CB_CASES)
            T = M[(alg, c)]
            for sd in sort(collect(keys(T["lost"]))), k in P615M_ALL
                println(io, join((alg, c, sd, k, cb_f64(T[k][sd])), '\t'))
            end
        end
    end
    # comparison.tsv at crit(ν)
    cmp = NamedTuple[]
    for c in string.(CB_CASES)
        Tr, Ta = M[("sequential", c)], M[("checkerboard", c)]
        zc = p615m_crit(length(Tr["lost"]), length(Ta["lost"]))
        tab = PottsModels.openvt_spread_table(Dict(k => p615m_vals(Tr[k]) for k in P615M_ALL),
            Dict(k => p615m_vals(Ta[k]) for k in P615M_ALL); z = zc)
        append!(cmp, [merge((; case = c, crit = zc), t) for t in tab])
    end
    open(joinpath(CB_DIR, "comparison.tsv"), "w") do io
        println(io, join(("case", "metric", "n_ref", "n_alt", "mean_ref", "mean_alt", "sd_ref", "sd_alt", "diff", "se", "z", "beyond"), '\t'))
        for t in cmp
            println(io, join((t.case, t.metric, t.n_ref, t.n_alt, cb_f64(t.mean_ref), cb_f64(t.mean_alt), cb_f64(t.sd_ref),
                cb_f64(t.sd_alt), cb_f64(t.diff), cb_f64(t.se), cb_f64(t.z), t.beyond), '\t'))
        end
    end
    # meta.toml (status from the deviations table when it exists; see `status`)
    write_meta(cal, cmp_status())
    # provenance.toml
    s1 = first(sess)
    started = cal["started"]
    finished = maximum(s["finished"] for s in sess)
    manifest = joinpath(CB_ROOT, "Manifest.toml")
    devices = unique([cal["device"]; [s["device"] for s in sess]])
    planners = unique(r["planner"] for r in rp)
    forms = unique(r["form"] for r in rp)
    prov = Dict(
        "item" => "P6.15m", "decisions" => ["D-008", "D-146", "D-214", "D-216", "D-218", "D-220"],
        "framework" => P615M_LABEL, "folder_token" => P615M_FOLDER,
        "algorithm" => CB_ALG_STR * " on the GPU (KernelAbstractions, ROCBackend)",
        "algorithm_reference" => CB_REF_ALG_STR * " on the CPU (the P6.15f record and its replay, reference_runs.tsv)",
        "backend" => "AMDGPU.ROCBackend() (ROCm, AMDGPU.jl $(pkgversion(AMDGPU)))", "device" => join(devices, "; "),
        "host_planner_fallback" => planners != ["device"], "lifecycle_forms" => join(forms, ", "),
        "commit" => cal["commit"], "dirty_tracked" => cal["dirty_tracked"] || any(s -> s["dirty_tracked"] == "true", sess),
        "runner" => relpath(@__FILE__, CB_ROOT), "runner_sha256" => bytes2hex(open(sha256, @__FILE__)),
        "reference_runner" => relpath(joinpath(CB_DIR, "run_reference.jl"), CB_ROOT),
        "reference_runner_sha256" => bytes2hex(open(sha256, joinpath(CB_DIR, "run_reference.jl"))),
        "test" => relpath(CB_TEST, CB_ROOT), "test_sha256" => bytes2hex(open(sha256, CB_TEST)),
        "protocol_test" => relpath(REF_TEST, CB_ROOT), "protocol_test_sha256" => bytes2hex(open(sha256, REF_TEST)),
        "manifest_sha256" => bytes2hex(open(sha256, manifest)),
        "julia" => cal["julia"], "machine" => "x86_64-linux-gnu", "cpu" => cal["cpu"], "threads" => cal["threads"],
        "affinity" => cal["affinity"],
        "seeds" => "calibration λ = 2: 214200001–214200100; (b) 214100001–214100100; (f) 214100201–214100300; (a) 214100701–214100710",
        "started" => started, "finished" => finished,
        "wall_s" => round(cal["wall_s"] + sum(parse(Float64, s["wall_s"]) for s in sess); digits = 1),
        "calibration_wall_s" => cal["wall_s"], "calibration_simulation_s" => cal["simulation_s"],
        "runs_wall_s" => round(sum(parse(Float64, s["wall_s"]) for s in sess); digits = 1),
        "runs_simulation_s" => round(sum(parse(Float64, s["simulation_s"]) for s in sess); digits = 1),
        "runs_gpu_s" => Dict(c => round(sum(parse(Float64, r["wall_s"]) for r in rp if r["case"] == c); digits = 1) for c in string.(CB_CASES)),
        "sessions" => length(sess), "o1_reference" => "the stop frames of o1-2026-10-09's bulk archives (sha256-checked), cached in reference_o1.tsv")
    open(io -> TOML.print(io, prov), joinpath(CB_DIR, "provenance.toml"), "w")
    nflag = count(t -> t.beyond, cmp)
    @info "collect" cycle nflag rows = length(cmp)
    for t in cmp
        t.beyond && println(rpad(t.case, 3), rpad(t.metric, 12), " z = ", round(t.z; digits = 2), "  ref ", round(t.mean_ref; sigdigits = 5),
            "  cb ", round(t.mean_alt; sigdigits = 5), "  crit ", round(t.crit; digits = 2))
    end
    return cmp
end

function write_meta(cal, status)
    meta = Dict(
        "item" => "P6.15m", "status" => status, "reference_record" => P615M_SEQ_REF, "reference_calibration" => P615M_SEQ_CAL,
        "framework" => P615M_LABEL, "algorithm" => CB_ALG_STR, "algorithm_reference" => CB_REF_ALG_STR,
        "every_mcs" => CB_EVERY,
        "model" => "OpenVTReferenceMonolayer (Table S1 defaults: A₀ = 50, λ = 2, T = 20, μ_X = 2, J 20/10), α = $(cal["alpha_text"]) px/MCS (this entry's cycle; D-220)",
        "initial" => "openvt_reference_state: one disc of radius √(A₀/π) at the lattice centre",
        "boundary" => "closed", "edge_guard" => "edge_guard(5; terminate = true)",
        "stop" => "stop_at_cells(n): end of the first MCS with ≥ n live cells",
        "saves" => "MCS 0, every 39 MCS and the stopping MCS; per save N and openvt_metrics r, A, C, w, g (R units)",
        "o1" => "the O1 frame (openvt_frame) of the stop state: mean and sample sd of n, share of n == 6, share of i == 0",
        "crit" => "two-sided Student t at α = 1e-3/103, ν = min(n_ref, n_alt) − 1 (D-218): $(round(p615m_crit(100, 100); digits = 4)) (b, f, calibration), $(round(p615m_crit(10, 10); digits = 4)) (a)",
        "cases" => Dict(string(c) => Dict("runs" => P615F_CASES[c].runs, "cells" => P615F_CASES[c].cells,
            "lattice" => P615F_CASES[c].L, "beta" => P615F_CASES[c].beta, "gamma" => P615F_CASES[c].gamma,
            "sigma_X" => P615F_CASES[c].sigma_X,
            "seeds" => "$(CB_SEED[c](1))–$(CB_SEED[c](P615F_CASES[c].runs))") for c in CB_CASES),
        "time" => Dict("T_lambda2" => cal["T_lambda2"], "T_lambda2_sd" => cal["T_lambda2_sd"], "T_runs" => cal["T_runs"],
            "T_lambda2_run_mean" => cal["T_lambda2_run_mean"], "T_seq" => P615M_T_SEQ, "T_seq_run_mean" => cal["T_seq_run_mean"],
            "z" => cal["z"], "crit" => cal["crit"], "beyond" => cal["beyond"], "cycle_mcs" => cal["cycle_mcs"],
            "alpha" => cal["alpha"], "alpha_text" => cal["alpha_text"], "cycle_reason" => cal["cycle_reason"],
            "protocol" => "P6.15b 11-chain: 150 × 5 periodic, Moore(1), λ = 2, burn-in 100 MCS at A_c = 25, openvt_release(100), w₁₁ every MCS to $(cal["tmax_mcs"]) MCS after the release; T = first MCS with mean w₁₁ ≥ 9 CD; per-run T the same per run",
            "seeds" => "$(cal_seed(1))–$(cal_seed(CAL_N))"))
    open(io -> TOML.print(io, meta), joinpath(CB_DIR, "meta.toml"), "w")
    return meta
end

# ---- step 4: status from the deviations table -----------------------------------------------------
function cmp_status()
    devf = joinpath(CB_DIR, "entry", "deviations.tsv")
    cf = joinpath(CB_DIR, "comparison.tsv")
    (isfile(devf) && isfile(cf)) || return "provisional"
    cmp = [merge(r, Dict("beyond" => r["beyond"] == "true", "mean_ref" => p615m_f64(r["mean_ref"]),
        "mean_alt" => p615m_f64(r["mean_alt"]))) for r in p615m_tsv(cf)]
    devs = p615m_tsv(devf)
    probs = p615m_deviation_problems(cmp, devs; final = true)
    isempty(probs) && return "final"
    @info "status: provisional" probs
    return "provisional"
end
function status_main()
    p = joinpath(CB_DIR, "meta.toml")
    meta = TOML.parsefile(p)
    meta["status"] = cmp_status()
    open(io -> TOML.print(io, meta), p, "w")
    println("status = ", meta["status"])
end

function cb_main(args)
    mode = isempty(args) ? "" : args[1]
    mode == "calibrate" ? cal_main() : mode == "runs" ? runs_main() : mode == "collect" ? collect_main() :
    mode == "status" ? status_main() : error("run_checkerboard: usage: run_checkerboard.jl calibrate | runs | collect | status")
    return nothing
end
abspath(PROGRAM_FILE) == abspath(@__FILE__) && cb_main(ARGS)

# P6.15m m3, supplementary diagnostic (D-220's colour ablation, re-run per D-221 and D-224): the
# contrast between the stock colouring and a 64-colour colouring of CheckerboardCPM, each arm at
# its own calibrated time unit, for every metric of comparison.tsv.
#
# Arms (GPU, ROCm):
#   stock   CheckerboardCPM(; proposal = Moore(1)): stride 2, 4 colours on the monolayers and on
#           the P1b calibration chain (D-224). It runs at the record's cycle (meta.toml [time]
#           cycle_mcs = 5 T_cb, read from the main runner's <out>/calibration.toml, so the same
#           P615M_OUT is used) and α = A₀/cycle; its chain counts are calibration.tsv's.
#   c64     the same with the colour stride widened by 6 (stride 8: 64 colours on the
#           monolayers; the read reach of `CorePotts.reach` + 6, redefined in this process only).
#           Its own P1b chain calibration (the main runner's protocol, λ = 2, 100 runs, its colour
#           count recorded) gives T_c64; it runs at cycle 5 T_c64 and α = A₀/(5 T_c64).
# Chain copy counts: the c64 chain runs are replayed on the CPU, one thread, through the main
# runner's counting colour loop (`cb_count_patch!`, `cb_count_runs`); each replay must equal its
# GPU run (crossing, committed copies = sites changed per MCS).
# Seeds: c64 calibration 214 900 000 + i; monolayer 214 950 000 + 1000 arm + 100 case + k (arm
# 1 stock, 2 c64; case 1 b, 2 f, 3 a); 20 runs of (b) and (f), 10 of (a) per arm (stage "n20").
# Power stage (stage "power", after the m3 review): 100 runs of (b) and (f) per arm, fresh seeds
# 215 100 000 + 10 000 arm + 1000 case + k (disjoint from every seed above). When the power
# parts exist, collect REPLACES the n20 runs of (b) and (f) with them (no pooling).
# Stage "a30" (D-227 item 1): 30 runs of (a) per arm, fresh seeds 215 200 000 + 10 000 arm +
# 1000 case + k; when its parts exist, collect replaces the 10 n20 runs of (a) with them.
# Colour counts are read from the integrator cache each arm builds (`cb_colours`, D-227 item 6).
# Each session records the runner's sha256; provenance gets one per stage (D-227 item 5; for a
# session logged without it, the sha256 of this file at that session's commit, via `git show`). The run,
# recorder and metrics are the main runner's (`run_checkerboard.jl`, included) and the frozen
# test's; the sequential arm is the record's.
#
#     P615M_OUT=<dir> taskset -c 0-3 julia -t 4 --project=lib/PottsModels/test …/run_ablation.jl calibrate   # GPU, c64 chain
#     P615M_OUT=<dir> taskset -c 4 julia -t 1 --project=lib/PottsModels/test …/run_ablation.jl count c64    # CPU
#     P615M_OUT=<dir> taskset -c 0-3 julia -t 4 --project=lib/PottsModels/test …/run_ablation.jl run stock   # GPU
#     P615M_OUT=<dir> taskset -c 0-3 julia -t 4 --project=lib/PottsModels/test …/run_ablation.jl run c64     # GPU
#     P615M_OUT=<dir> taskset -c 0-3 julia -t 4 --project=lib/PottsModels/test …/run_ablation.jl power stock # GPU, power stage
#     P615M_OUT=<dir> taskset -c 0-3 julia -t 4 --project=lib/PottsModels/test …/run_ablation.jl power c64   # GPU, power stage
#     P615M_OUT=<dir> taskset -c 0-3 julia -t 4 --project=lib/PottsModels/test …/run_ablation.jl a30 stock   # GPU, stage a30
#     P615M_OUT=<dir> taskset -c 0-3 julia -t 4 --project=lib/PottsModels/test …/run_ablation.jl a30 c64     # GPU, stage a30
#     P615M_OUT=<dir> julia --project=lib/PottsModels/test …/run_ablation.jl collect
#
# collect writes, into this directory: ablation.tsv (one row per case and metric, with the contrast
# arm's monolayer colour count `colours`: both arms'
# means, sds and differences from sequential, their z against sequential, the stock − c64
# contrast z, the critical values, the entry's diff and z), ablation_metrics.tsv (per seed),
# ablation_runs.tsv, ablation_calibration.tsv (the c64 chain crossings and copy counts), and the
# `[ablation]` block of provenance.toml.
include(joinpath(@__DIR__, "run_checkerboard.jl"))

const AB_ARMS = Dict("stock" => (; id = 1, extra = 0), "c64" => (; id = 2, extra = 6))
const AB_CASES = (; b = (; id = 1, runs = 20), f = (; id = 2, runs = 20), a = (; id = 3, runs = 10))
ab_seed(arm, c, k) = 214_950_000 + 1000AB_ARMS[arm].id + 100AB_CASES[c].id + k
ab_cal_seed(i) = 214_900_000 + i
# replacement stages: each REPLACES the n20 runs of its cases (no pooling)
const AB_STAGES = (; power = (; cases = (; b = (; id = 1, runs = 100), f = (; id = 2, runs = 100)), base = 215_100_000),
    a30 = (; cases = (; a = (; id = 3, runs = 30)), base = 215_200_000))
ab_stage_seed(stage, arm, c, k) = AB_STAGES[stage].base + 10_000AB_ARMS[arm].id + 1000AB_STAGES[stage].cases[c].id + k
ab_stage_part(stage, name) = cb_part(replace(name, ".tsv" => "_$(stage).tsv"))
ab_has_stage(stage) = isfile(ab_stage_part(stage, "ablation_runs_part.tsv"))
ab_runner_sha() = bytes2hex(open(sha256, @__FILE__))
ab_sha_at(commit) = bytes2hex(sha256(read(Cmd(`git show $(commit):$(relpath(@__FILE__, CB_ROOT))`; dir = CB_ROOT))))
const AB_RUNS_HEADER = ("arm", "colours", "cycle", "case", "k", "seed", "retcode", "mcs", "N", "divisions", "live", "planner", "form", "wall_s")

const AB_PATCHED = Ref("stock")
function ab_patch!(arm)
    extra = AB_ARMS[arm].extra
    AB_PATCHED[] = arm
    extra == 0 && return nothing
    @eval Potts.CorePotts function reach(fp::Footprint, proposal)
        rp = radius(proposal)
        read = max(fp.read, rp, fp.source_read >= 0 ? rp + fp.source_read : 0)
        write = max(fp.write, fp.source_write >= 0 ? rp + fp.source_write : 0)
        return read + $extra, write
    end
    return nothing
end
# the colours of the arm's own integrator cache (this process carries the arm's reach)
ab_colours(prob, arm) = (AB_PATCHED[] == arm || error("ablation: the process carries arm $(AB_PATCHED[]), not $arm"); cb_colours(prob))

# ---- the c64 chain calibration (GPU) on P1b: the main runner's protocol -------------------------------
function ab_calibrate()
    ab_patch!("c64")
    mkpath(CB_OUT)
    started = now()
    backend = cb_backend()
    prob = p1b_problem()
    saves = 0:(CAL_BURNIN + CAL_TMAX)
    Base.invokelatest() do
        solve(remake(prob; seed = ab_cal_seed(0), tspan = (0, CAL_BURNIN + 20)), CB_ALG; backend,
            saveat = 0:(CAL_BURNIN + 20), callback = openvt_release(CAL_BURNIN))
    end
    W = fill(NaN, length(saves), CAL_N)
    changed = fill(0, 2, CAL_N)
    sim = @elapsed for j in 1:CAL_N
        sol = Base.invokelatest() do
            solve(remake(prob; seed = ab_cal_seed(j)), CB_ALG; backend, saveat = saves, callback = openvt_release(CAL_BURNIN))
        end
        collect(sol.t) == collect(saves) || error("ablation calibrate: saves")
        p1b_walls_intact(sol.u[end]) || error("ablation calibrate: a border row changed")
        W[:, j] = p1b_width.(sol.u)
        changed[:, j] .= p1b_changed(sol)
    end
    Tc, Truns, _ = p1b_reduce(W)
    ncol = ab_colours(prob, "c64")
    open(cb_part("ablation_calibration_gpu.tsv"), "w") do io
        println(io, join(("arm", "colours", "lambda", "seed", "T_run", "committed_burnin", "committed_relax"), '\t'))
        for j in 1:CAL_N
            println(io, join(("c64", ncol, CAL_LAMBDA, ab_cal_seed(j), Int(Truns[j]), changed[1, j], changed[2, j]), '\t'))
        end
    end
    finished = now()
    d = merge(cb_env(), Dict("T_c64" => Tc, "T_c64_sd" => std(Truns), "T_c64_run_mean" => mean(Truns),
        "colours_chain" => ncol, "colours_monolayer" => ab_colours(cb_problem(400), "c64"), "cycle_mcs" => 5Tc, "alpha" => A0 / (5Tc),
        "device" => cb_device(), "started" => string(started), "finished" => string(finished), "simulation_s" => round(sim; digits = 1)))
    open(io -> TOML.print(io, d), cb_part("ablation_c64.toml"), "w")
    @info "c64 P1b chain" T_c64 = Tc sd = d["T_c64_sd"] run_mean = d["T_c64_run_mean"] colours = ncol cycle = 5Tc
end

# ---- c64 chain copy counts (CPU replay, one thread) ------------------------------------------------
function ab_count(arm)
    arm == "c64" || error("ablation count: only the c64 chain (the stock chain's counts are calibration.tsv's)")
    ab_patch!(arm)
    cb_count_patch!()
    gpu = Dict(parse(Int, r["seed"]) => r for r in p615m_tsv(cb_part("ablation_calibration_gpu.tsv")))
    rows = cb_count_runs(p1b_problem(), [ab_cal_seed(i) for i in 1:CAL_N])
    open(cb_part("ablation_calibration.tsv"), "w") do io
        println(io, join(("arm", "colours", "lambda", "seed", "T_run", "accepted_burnin", "committed_burnin", "accepted_relax",
            "committed_relax", "commit_fraction_relax"), '\t'))
        for r in rows
            g = gpu[r.seed]
            (string(r.T_cpu) == g["T_run"] && string(r.committed_burnin) == g["committed_burnin"] == string(r.changed_burnin) &&
             string(r.committed_relax) == g["committed_relax"] == string(r.changed_relax)) ||
                error("ablation count: the CPU replay of seed $(r.seed) is not its GPU run")
            println(io, join(("c64", g["colours"], CAL_LAMBDA, r.seed, r.T_cpu, r.accepted_burnin, r.committed_burnin, r.accepted_relax,
                r.committed_relax, cb_f64(r.committed_relax / r.accepted_relax)), '\t'))
        end
    end
end

# ---- the monolayer arms (GPU) ------------------------------------------------------------------
function ab_run(arm; stage = nothing)
    part = stage === nothing ? cb_part : name -> ab_stage_part(stage, name)
    cases = stage === nothing ? AB_CASES : AB_STAGES[stage].cases
    seedf = stage === nothing ? ab_seed : (a, c, k) -> ab_stage_seed(stage, a, c, k)
    ab_patch!(arm)
    mkpath(CB_OUT)
    if arm == "stock"
        cycle = TOML.parsefile(cb_part("calibration.toml"))["cycle_mcs"]     # the entry's cycle (step 1d)
    else
        cycle = TOML.parsefile(cb_part("ablation_c64.toml"))["cycle_mcs"]
    end
    α = A0 / cycle
    backend = cb_backend()
    ncol = ab_colours(cb_problem(400), arm)
    rp = cb_header!(part("ablation_runs_part.tsv"), AB_RUNS_HEADER)
    mp = cb_header!(part("ablation_metrics_part.tsv"), ("arm", "case", "seed", "metric", "value"))
    for L in (400, 1400)
        Base.invokelatest(cb_run, cb_problem(L), 1, merge(P615F_CASES.b, (; L)); cycle, α, cells = 2, tmax = 50, backend)
    end
    for c in keys(cases), k in 1:cases[c].runs
        cc = P615F_CASES[c]
        seed = seedf(arm, c, k)
        wall = @elapsed r = Base.invokelatest(cb_run, cb_problem(cc.L), seed, cc; cycle, α, backend)
        s = p615m_series([x.mcs for x in r.rec], [x.N for x in r.rec], [x.r for x in r.rec], [x.A for x in r.rec],
            [x.C for x in r.rec], [x.w for x in r.rec], [x.g for x in r.rec]; cycle)
        m = p615m_seed_metrics(s, cc.cells)
        m["lost"] = r.divisions + 1 - r.live
        m["O1.n_mean"], m["O1.n_sd"], m["O1.n6"], m["O1.i0"] = r.o1.n_mean, r.o1.n_sd, r.o1.n6, r.o1.i0
        open(io -> foreach(key -> println(io, join((arm, c, seed, key, cb_f64(m[key])), '\t')), P615M_ALL), mp, "a")
        open(io -> println(io, join((arm, ncol, cycle, c, k, seed, r.retcode, r.mcs, r.rec[end].N, r.divisions, r.live, r.planner,
                r.form, round(wall; digits = 2)), '\t')), rp, "a")
        @info "ablation run" arm ncol cycle c k seed r.mcs r.planner lost = m["lost"] wall = round(wall; digits = 1)
    end
    hdr = stage in (nothing, :power) ? ("arm", "finished", "commit", "dirty_tracked", "device") :
          ("arm", "finished", "commit", "dirty_tracked", "device", "runner_sha256")
    log = cb_header!(part("ablation_sessions.tsv"), hdr)
    env = cb_env()
    row = (arm, now(), env["commit"], env["dirty_tracked"], cb_device(), ab_runner_sha())[1:length(hdr)]
    open(io -> println(io, join(row, '\t')), log, "a")
end

# ---- collect --------------------------------------------------------------------------------------
function ab_collect()
    dirty0 = cb_dirty()  # before this step rewrites its own tracked outputs
    runs = p615m_tsv(cb_part("ablation_runs_part.tsv"))
    mets = p615m_tsv(cb_part("ablation_metrics_part.tsv"))
    c64 = TOML.parsefile(cb_part("ablation_c64.toml"))
    ncase = Dict(string(c) => AB_CASES[c].runs for c in keys(AB_CASES))
    stage_of = Dict(string(c) => "n20" for c in keys(AB_CASES))
    stsess = Dict("n20" => p615m_tsv(cb_part("ablation_sessions.tsv")))
    for st in keys(AB_STAGES)   # replace the n20 runs of the stage's cases (no pooling)
        ab_has_stage(st) || continue
        pc = string.(keys(AB_STAGES[st].cases))
        runs = [[r for r in runs if !(r["case"] in pc)]; p615m_tsv(ab_stage_part(st, "ablation_runs_part.tsv"))]
        mets = [[r for r in mets if !(r["case"] in pc)]; p615m_tsv(ab_stage_part(st, "ablation_metrics_part.tsv"))]
        stsess[string(st)] = p615m_tsv(ab_stage_part(st, "ablation_sessions.tsv"))
        foreach(c -> (ncase[string(c)] = AB_STAGES[st].cases[c].runs; stage_of[string(c)] = string(st)), keys(AB_STAGES[st].cases))
    end
    used = sort(unique(values(stage_of)))
    sess = reduce(vcat, [stsess[st] for st in used])
    stage_sha(st) = join(unique(haskey(s, "runner_sha256") ? s["runner_sha256"] : ab_sha_at(s["commit"]) for s in stsess[st]), ", ")
    stage_cases(st) = join(sort([c for (c, s) in stage_of if s == st]), ", ")
    c64chain = p615m_tsv(cb_part("ablation_calibration.tsv"))
    length(c64chain) == CAL_N || error("ablation collect: c64 chain counts incomplete")
    stockchain = [merge(r, Dict("arm" => "stock", "colours" => "4")) for r in p615m_tsv(joinpath(CB_DIR, "calibration.tsv"))]
    chain = [stockchain; c64chain]
    entry = Dict((r["case"], r["metric"]) => r for r in p615m_tsv(joinpath(CB_DIR, "comparison.tsv")))
    replay = p615m_tsv(joinpath(CB_DIR, "reference_runs.tsv"))
    o1seq = Dict((r["case"], parse(Int, r["seed"])) => r for r in p615m_tsv(joinpath(CB_DIR, "reference_o1.tsv")))
    ref_ts = p615m_tsv(joinpath(REF_F3F8, "timeseries.tsv"))
    vals = Dict{Tuple{String, String, String}, Dict{Int, Float64}}()
    for r in mets
        get!(vals, (r["arm"], r["case"], r["metric"]), Dict{Int, Float64}())[parse(Int, r["seed"])] = p615m_f64(r["value"])
    end
    # `colours`: the contrast arm's monolayer colour count (64)
    c64colours = parse(Int, only(unique(r["colours"] for r in runs if r["arm"] == "c64")))
    rows = NamedTuple[]
    for c in string.(keys(AB_CASES))
        P = P615M_CASES[c]
        sers = p615m_record_series(ref_ts, c; cycle = P615M_CYCLE_SEQ)
        lost = Dict(parse(Int, r["seed"]) => parse(Int, r["divisions"]) + 1 - parse(Int, r["live"]) for r in replay if r["case"] == c)
        ref = Dict(k => Float64[] for k in P615M_ALL)
        for sd in sort(collect(keys(sers)))
            m = p615m_seed_metrics(sers[sd], P.cells)
            m["lost"] = lost[sd]
            merge!(m, o1metrics(o1seq[(c, sd)]))
            foreach(k -> push!(ref[k], m[k]), P615M_ALL)
        end
        for k in P615M_ALL
            st, cs = p615m_vals(vals[("stock", c, k)]), p615m_vals(vals[("c64", c, k)])
            n = ncase[c]
            (length(st) == n && length(cs) == n) || error("ablation collect: $c $k has $(length(st)), $(length(cs)) runs")
            zr = p615m_crit(length(ref[k]), n)
            zc = p615m_crit(n, n)
            S = PottsModels.openvt_spread_compare(ref[k], st; z = zr)
            R = PottsModels.openvt_spread_compare(ref[k], cs; z = zr)
            X = PottsModels.openvt_spread_compare(cs, st; z = zc)            # stock − c64
            e = entry[(c, k)]
            push!(rows, (; case = c, metric = k, colours = c64colours, n_ref = S.n_ref, n_arm = n, mean_ref = S.mean_ref, sd_ref = S.sd_ref,
                mean_stock = S.mean_alt, sd_stock = S.sd_alt, diff_stock = S.diff, z_stock = S.z, beyond_stock = S.beyond,
                mean_c64 = R.mean_alt, sd_c64 = R.sd_alt, diff_c64 = R.diff, z_c64 = R.z, beyond_c64 = R.beyond, crit_ref = zr,
                contrast = X.diff, z_contrast = X.z, crit_contrast = zc, beyond_contrast = X.beyond,
                remainder_fraction = S.diff == 0 ? NaN : R.diff / S.diff,
                # the c64 remainder's resolution limit: crit · se of its difference from sequential
                resolution_c64 = zr * sqrt(S.sd_ref^2 / S.n_ref + R.sd_alt^2 / n),
                resolution_fraction = S.diff == 0 ? NaN : zr * sqrt(S.sd_ref^2 / S.n_ref + R.sd_alt^2 / n) / abs(S.diff),
                diff_entry = p615m_f64(e["diff"]), z_entry = p615m_f64(e["z"]), beyond_entry = e["beyond"]))
        end
    end
    H = (:case, :metric, :colours, :n_ref, :n_arm, :mean_ref, :sd_ref, :mean_stock, :sd_stock, :diff_stock, :z_stock, :beyond_stock,
        :mean_c64, :sd_c64, :diff_c64, :z_c64, :beyond_c64, :crit_ref, :contrast, :z_contrast, :crit_contrast, :beyond_contrast,
        :remainder_fraction, :resolution_c64, :resolution_fraction, :diff_entry, :z_entry, :beyond_entry)
    fmtv(x) = x isa AbstractFloat ? cb_f64(x) : string(x)
    open(joinpath(CB_DIR, "ablation.tsv"), "w") do io
        println(io, join(string.(H), '\t'))
        foreach(r -> println(io, join((fmtv(getfield(r, h)) for h in H), '\t')), rows)
    end
    open(joinpath(CB_DIR, "ablation_metrics.tsv"), "w") do io
        println(io, join(("arm", "case", "seed", "metric", "value"), '\t'))
        for arm in ("stock", "c64"), c in string.(keys(AB_CASES)), k in P615M_ALL
            d = vals[(arm, c, k)]
            foreach(sd -> println(io, join((arm, c, sd, k, cb_f64(d[sd])), '\t')), sort(collect(keys(d))))
        end
    end
    open(joinpath(CB_DIR, "ablation_runs.tsv"), "w") do io
        println(io, join(AB_RUNS_HEADER, '\t'))
        for r in sort(runs; by = r -> (r["arm"], r["case"], parse(Int, r["k"])))
            println(io, join((r[h] for h in AB_RUNS_HEADER), '\t'))
        end
    end
    cp(cb_part("ablation_calibration.tsv"), joinpath(CB_DIR, "ablation_calibration.tsv"); force = true)
    frac(a) = (rr = [r for r in chain if r["arm"] == a];
        sum(parse(Int, r["committed_relax"]) for r in rr) / sum(parse(Int, r["accepted_relax"]) for r in rr))
    fracb(a) = (rr = [r for r in chain if r["arm"] == a];
        sum(parse(Int, r["committed_burnin"]) for r in rr) / sum(parse(Int, r["accepted_burnin"]) for r in rr))
    colours_of(a) = only(unique(r["colours"] for r in chain if r["arm"] == a))
    mono_of(a) = only(unique(r["colours"] for r in runs if r["arm"] == a))
    pp = joinpath(CB_DIR, "provenance.toml")
    prov = TOML.parsefile(pp)
    prov["ablation"] = Dict(
        "runner" => relpath(@__FILE__, CB_ROOT), "runner_sha256" => ab_runner_sha(),
        "commit" => c64["commit"], "dirty_tracked" => c64["dirty_tracked"] || any(s -> s["dirty_tracked"] == "true", sess),
        "commits" => join(unique([c64["commit"]; [s["commit"] for s in sess]]), ", "),
        "collect_commit" => cb_git("rev-parse", "HEAD"), "collect_dirty_tracked" => dirty0,
        "device" => join(unique([c64["device"]; [s["device"] for s in sess]]), "; "),
        "host_planner_fallback" => any(r -> r["planner"] != "device", runs),
        "arms" => "stock: $(colours_of("stock")) colours on the chain, $(mono_of("stock")) on the monolayer, cycle $(only(unique(r["cycle"] for r in runs if r["arm"] == "stock"))); c64: $(colours_of("c64")) on the chain, $(mono_of("c64")) on the monolayer, cycle $(c64["cycle_mcs"]) = 5 T_c64",
        "T_c64" => c64["T_c64"], "T_c64_sd" => c64["T_c64_sd"], "T_c64_run_mean" => c64["T_c64_run_mean"],
        "cycle_c64" => c64["cycle_mcs"], "alpha_c64" => c64["alpha"],
        "chain_commit_fraction_stock" => frac("stock"), "chain_commit_fraction_c64" => frac("c64"),
        "chain_commit_fraction_burnin_stock" => fracb("stock"), "chain_commit_fraction_burnin_c64" => fracb("c64"),
        "chain_replays_equal_gpu" => true, "chain_committed_equal_changed_sites" => true,
        "chain" => "spec 15 §4.2 variant P1b (D-224) for both arms",
        "seeds" => "c64 chain 214900001–214900100; " * join(("stage $st ($(stage_cases(st))): " *
            (st == "n20" ? "214 950 000 + 1000 arm + 100 case + k" : "$(AB_STAGES[Symbol(st)].base) + 10 000 arm + 1000 case + k") for st in used), "; "),
        "runs_per_arm" => join(("$c $(ncase[c])" for c in string.(keys(AB_CASES))), ", "),
        "stages" => join(("$st: $(stage_cases(st))" for st in used), "; ") * " (each stage replaces the n20 runs of its cases; no pooling)",
        "runner_sha256_c64_calibration" => ab_sha_at(c64["commit"]),
        "runner_sha256_collect" => ab_runner_sha(),
        ("runner_sha256_" * st => stage_sha(st) for st in used)...,
        "decisions" => ["D-220", "D-221", "D-224"])
    open(io -> TOML.print(io, prov), pp, "w")
    mp = joinpath(CB_DIR, "meta.toml")
    @info "ablation" T_c64 = c64["T_c64"] cycle_c64 = c64["cycle_mcs"] chain_stock = frac("stock") chain_c64 = frac("c64") burnin_stock = fracb("stock") burnin_c64 = fracb("c64")
    for r in rows
        r.beyond_entry == "true" && println(rpad(r.case, 2), rpad(r.metric, 11), " entry z ", round(r.z_entry; digits = 2),
            " | stock z ", round(r.z_stock; digits = 2), r.beyond_stock ? "*" : "", " | c64 z ", round(r.z_c64; digits = 2),
            r.beyond_c64 ? "*" : "", " | contrast z ", round(r.z_contrast; digits = 2), r.beyond_contrast ? "*" : "",
            " | remainder ", round(r.remainder_fraction; digits = 2))
    end
end

function ab_main(args)
    isempty(args) && error("run_ablation.jl calibrate | count <arm> | run <arm> | power <arm> | a30 <arm> | collect")
    m = args[1]
    m == "calibrate" ? ab_calibrate() : m == "count" ? ab_count(args[2]) : m == "run" ? ab_run(args[2]) :
    m == "power" ? ab_run(args[2]; stage = :power) : m == "a30" ? ab_run(args[2]; stage = :a30) :
    m == "collect" ? ab_collect() : error("run_ablation.jl: bad mode $m")
    return nothing
end
abspath(PROGRAM_FILE) == abspath(@__FILE__) && ab_main(ARGS)

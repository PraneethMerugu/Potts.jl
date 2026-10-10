# P6.15m m3, supplementary diagnostic (D-220's colour ablation, re-run per D-221): the contrast
# between the stock colouring and a 64-colour colouring of CheckerboardCPM, each arm at its own
# calibrated time unit, for every metric of comparison.tsv.
#
# Arms (GPU, ROCm):
#   stock   CheckerboardCPM(; proposal = Moore(1)): stride 2, 4 colours on the 400² and 1400²
#           monolayers, 6 on the 150 × 5 periodic chain (5 is not a multiple of 2; D-221). It
#           runs at the record's cycle (meta.toml [time] cycle_mcs = 5 T_cb) and α = A₀/cycle.
#   c64     the same with the colour stride widened by 6 (stride 8: 64 colours on the
#           monolayers; the read reach of `CorePotts.reach` + 6, redefined in this process only).
#           Its own chain calibration (P6.15b protocol, λ = 2, 100 runs) gives T_c64; it runs at
#           cycle 5 T_c64 and α = A₀/(5 T_c64) (D-221 item 1).
# Chain copy counts (D-221 item 2): every chain run of both arms (the record's stock calibration
# seeds, the c64 calibration seeds) is replayed on the CPU, one thread, through the plain-loop
# colour path, with a counting method of `CorePotts.commit_body!` for host states (an accepted
# copy is one with a nonzero claim priority; it committed when its target site changed). Each
# replay's crossing must equal its GPU run's, so the counts are those runs'.
# Seeds: c64 calibration 214 500 000 + i; monolayer 214 400 000 + 1000 arm + 100 case + k (arm
# 1 stock, 2 c64; case 1 b, 2 f, 3 a); 20 runs of (b) and (f), 10 of (a) per arm. The run,
# recorder and metrics are the main runner's (`run_checkerboard.jl`, included) and the frozen
# test's; the sequential arm is the record's.
#
#     P615M_OUT=<dir> taskset -c 0-3 julia -t 4 --project=lib/PottsModels/test …/run_ablation.jl calibrate   # GPU, c64 chain
#     P615M_OUT=<dir> taskset -c 4 julia -t 1 --project=lib/PottsModels/test …/run_ablation.jl count stock  # CPU
#     P615M_OUT=<dir> taskset -c 5 julia -t 1 --project=lib/PottsModels/test …/run_ablation.jl count c64    # CPU (after calibrate)
#     P615M_OUT=<dir> taskset -c 0-3 julia -t 4 --project=lib/PottsModels/test …/run_ablation.jl run stock   # GPU
#     P615M_OUT=<dir> taskset -c 0-3 julia -t 4 --project=lib/PottsModels/test …/run_ablation.jl run c64     # GPU
#     P615M_OUT=<dir> julia --project=lib/PottsModels/test …/run_ablation.jl collect
#
# collect writes, into this directory: ablation.tsv (one row per case and metric: both arms'
# means, sds and differences from sequential, their z against sequential, the stock − c64
# contrast z, the critical values, the entry's diff and z), ablation_metrics.tsv (per seed),
# ablation_runs.tsv, ablation_calibration.tsv (the c64 chain crossings), ablation_chain.tsv
# (per chain run: colours, accepted and committed copies, the commit fraction), and the
# `[ablation]` block of provenance.toml.
include(joinpath(@__DIR__, "run_checkerboard.jl"))

const AB_ARMS = Dict("stock" => (; id = 1, extra = 0), "c64" => (; id = 2, extra = 6))
const AB_CASES = (; b = (; id = 1, runs = 20), f = (; id = 2, runs = 20), a = (; id = 3, runs = 10))
ab_seed(arm, c, k) = 214_400_000 + 1000AB_ARMS[arm].id + 100AB_CASES[c].id + k
ab_cal_seed(i) = 214_500_000 + i
const AB_RUNS_HEADER = ("arm", "colours", "cycle", "case", "k", "seed", "retcode", "mcs", "N", "divisions", "live", "planner", "form", "wall_s")

function ab_patch!(arm)
    extra = AB_ARMS[arm].extra
    extra == 0 && return nothing
    @eval Potts.CorePotts function reach(fp::Footprint, proposal)
        rp = radius(proposal)
        read = max(fp.read, rp, fp.source_read >= 0 ? rp + fp.source_read : 0)
        write = max(fp.write, fp.source_write >= 0 ? rp + fp.source_write : 0)
        return read + $extra, write
    end
    return nothing
end
ab_colours(prob, arm) = length(Potts.CorePotts.colors(prob.lattice, 2 + AB_ARMS[arm].extra))
ab_chain_problem() = PottsProblem(OpenVTChain(; name = :p615m_abl_chain11, lattice = (150, 5), λ = Float64(CAL_LAMBDA)),
    openvt_chain(11), (0, CAL_BURNIN + CAL_TMAX); seed = 1)
ab_width(u) = (xs = CB_A.chain_centroids(Array(u.σ)); (maximum(xs) - minimum(xs)) / CAL_CD)

# ---- the c64 chain calibration (GPU): the main runner's protocol ------------------------------------
function ab_calibrate()
    ab_patch!("c64")
    mkpath(CB_OUT)
    started = now()
    backend = cb_backend()
    prob = ab_chain_problem()
    saves = 0:(CAL_BURNIN + CAL_TMAX)
    Base.invokelatest() do
        solve(remake(prob; seed = ab_cal_seed(0), tspan = (0, CAL_BURNIN + 20)), CB_ALG; backend,
            saveat = 0:(CAL_BURNIN + 20), callback = openvt_release(CAL_BURNIN))
    end
    W = fill(NaN, length(saves), CAL_N)
    sim = @elapsed for j in 1:CAL_N
        sol = Base.invokelatest() do
            solve(remake(prob; seed = ab_cal_seed(j)), CB_ALG; backend, saveat = saves, callback = openvt_release(CAL_BURNIN))
        end
        collect(sol.t) == collect(saves) || error("ablation calibrate: saves")
        W[:, j] = [ab_width(u) for u in sol.u]
    end
    t = collect((-CAL_BURNIN):CAL_TMAX)
    k = t .>= 0
    Tc = CB_A.crossing_time(t[k], vec(mean(W; dims = 2))[k], CAL_LEVEL)
    Tc === nothing && error("ablation calibrate: no mean crossing")
    Truns = [CB_A.crossing_time(t[k], W[k, j], CAL_LEVEL) for j in 1:CAL_N]
    any(isnothing, Truns) && error("ablation calibrate: $(count(isnothing, Truns)) runs do not cross")
    open(cb_part("ablation_calibration.tsv"), "w") do io
        println(io, join(("arm", "colours", "lambda", "seed", "T_run"), '\t'))
        for j in 1:CAL_N
            println(io, join(("c64", ab_colours(prob, "c64"), CAL_LAMBDA, ab_cal_seed(j), Truns[j]), '\t'))
        end
    end
    finished = now()
    d = merge(cb_env(), Dict("T_c64" => Tc, "T_c64_sd" => std(Float64.(Truns)), "T_c64_run_mean" => mean(Float64.(Truns)),
        "colours_chain" => ab_colours(prob, "c64"), "cycle_mcs" => 5Tc, "alpha" => A0 / (5Tc), "device" => cb_device(),
        "started" => string(started), "finished" => string(finished), "simulation_s" => round(sim; digits = 1)))
    open(io -> TOML.print(io, d), cb_part("ablation_c64.toml"), "w")
    @info "c64 chain" T_c64 = Tc sd = d["T_c64_sd"] run_mean = d["T_c64_run_mean"] colours = d["colours_chain"] cycle = 5Tc
end

# ---- chain copy counts (CPU replay, one thread) --------------------------------------------------------
const AB_ACC = Ref(0)
const AB_COM = Ref(0)
function ab_count(arm)
    Threads.nthreads() == 1 || error("ablation count: run with one thread (the plain-loop colour path)")
    ab_patch!(arm)
    # counting method for host states: accepted = nonzero claim priority; committed = target changed
    @eval Potts.CorePotts function commit_body!(j, st::CPMState{<:Array}, rest...)
        prio, ctx, color = rest[5], rest[9], rest[10]
        won = @inbounds prio[j]
        t = won == 0 ? 0 : linear_index(ctx.lattice, color_site(color, j))
        before = t == 0 ? zero(eltype(st.σ)) : @inbounds(st.σ[t])
        invoke(commit_body!, Tuple{Any, Any, map(Core.Typeof, rest)...}, j, st, rest...)
        if won != 0
            $AB_ACC[] += 1
            @inbounds(st.σ[t]) != before && ($AB_COM[] += 1)
        end
        return nothing
    end
    prob = ab_chain_problem()
    ncol = ab_colours(prob, arm)
    if arm == "stock"
        want = Dict(parse(Int, r["seed"]) => parse(Int, r["T_run"]) for r in p615m_tsv(joinpath(CB_DIR, "calibration.tsv")))
        seeds = [cal_seed(i) for i in 1:CAL_N]
    else
        want = Dict(parse(Int, r["seed"]) => parse(Int, r["T_run"]) for r in p615m_tsv(cb_part("ablation_calibration.tsv")))
        seeds = [ab_cal_seed(i) for i in 1:CAL_N]
    end
    out = cb_part("ablation_chain_$arm.tsv")
    open(io -> println(io, join(("arm", "colours", "seed", "T_run_gpu", "T_run_cpu", "accepted_burnin", "committed_burnin",
        "accepted_relax", "committed_relax", "commit_fraction_relax"), '\t')), out, "w")
    saves = 0:(CAL_BURNIN + CAL_TMAX)
    for seed in seeds
        AB_ACC[] = 0; AB_COM[] = 0
        snap = Ref((0, 0))
        mark = Potts.DiscreteCallback((u, t, integ) -> t == CAL_BURNIN, integ -> (snap[] = (AB_ACC[], AB_COM[]); nothing);
            save_positions = (false, false))
        sol = Base.invokelatest() do
            solve(remake(prob; seed), CB_ALG; saveat = saves,
                callback = Potts.CorePotts.CallbackSet(mark, openvt_release(CAL_BURNIN)))
        end
        w = [ab_width(u) for u in sol.u]
        tr = CB_A.crossing_time(collect(0:CAL_TMAX), w[(CAL_BURNIN + 1):end], CAL_LEVEL)
        ab, cbn = snap[]
        ar, cr = AB_ACC[] - ab, AB_COM[] - cbn
        open(io -> println(io, join((arm, ncol, seed, want[seed], something(tr, -1), ab, cbn, ar, cr, cb_f64(cr / ar)), '\t')), out, "a")
        @info "chain count" arm ncol seed T_gpu = want[seed] T_cpu = tr commit_fraction = round(cr / ar; digits = 4)
    end
end

# ---- the monolayer arms (GPU) ------------------------------------------------------------------
function ab_run(arm)
    ab_patch!(arm)
    mkpath(CB_OUT)
    if arm == "stock"
        tm = TOML.parsefile(joinpath(CB_DIR, "meta.toml"))["time"]
        cycle = tm["cycle_mcs"]
    else
        cycle = TOML.parsefile(cb_part("ablation_c64.toml"))["cycle_mcs"]
    end
    α = A0 / cycle
    backend = cb_backend()
    ncol = ab_colours(cb_problem(400), arm)
    rp = cb_header!(cb_part("ablation_runs_part.tsv"), AB_RUNS_HEADER)
    mp = cb_header!(cb_part("ablation_metrics_part.tsv"), ("arm", "case", "seed", "metric", "value"))
    for L in (400, 1400)
        Base.invokelatest(cb_run, cb_problem(L), 1, merge(P615F_CASES.b, (; L)); cycle, α, cells = 2, tmax = 50, backend)
    end
    for c in keys(AB_CASES), k in 1:AB_CASES[c].runs
        cc = P615F_CASES[c]
        seed = ab_seed(arm, c, k)
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
    log = cb_header!(cb_part("ablation_sessions.tsv"), ("arm", "finished", "commit", "dirty_tracked", "device"))
    env = cb_env()
    open(io -> println(io, join((arm, now(), env["commit"], env["dirty_tracked"], cb_device()), '\t')), log, "a")
end

# ---- collect --------------------------------------------------------------------------------------
function ab_collect()
    runs = p615m_tsv(cb_part("ablation_runs_part.tsv"))
    mets = p615m_tsv(cb_part("ablation_metrics_part.tsv"))
    c64 = TOML.parsefile(cb_part("ablation_c64.toml"))
    sess = p615m_tsv(cb_part("ablation_sessions.tsv"))
    chain = [p615m_tsv(cb_part("ablation_chain_$a.tsv")) for a in ("stock", "c64")]
    chain = [chain[1]; chain[2]]
    length(chain) == 2CAL_N || error("ablation collect: chain counts incomplete")
    all(r -> r["T_run_gpu"] == r["T_run_cpu"], chain) || @warn "ablation collect: a CPU chain replay's crossing differs from its GPU run's"
    entry = Dict((r["case"], r["metric"]) => r for r in p615m_tsv(joinpath(CB_DIR, "comparison.tsv")))
    replay = p615m_tsv(joinpath(CB_DIR, "reference_runs.tsv"))
    o1seq = Dict((r["case"], parse(Int, r["seed"])) => r for r in p615m_tsv(joinpath(CB_DIR, "reference_o1.tsv")))
    ref_ts = p615m_tsv(joinpath(REF_F3F8, "timeseries.tsv"))
    vals = Dict{Tuple{String, String, String}, Dict{Int, Float64}}()
    for r in mets
        get!(vals, (r["arm"], r["case"], r["metric"]), Dict{Int, Float64}())[parse(Int, r["seed"])] = p615m_f64(r["value"])
    end
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
            n = AB_CASES[Symbol(c)].runs
            (length(st) == n && length(cs) == n) || error("ablation collect: $c $k has $(length(st)), $(length(cs)) runs")
            zr = p615m_crit(length(ref[k]), n)
            zc = p615m_crit(n, n)
            S = PottsModels.openvt_spread_compare(ref[k], st; z = zr)
            R = PottsModels.openvt_spread_compare(ref[k], cs; z = zr)
            X = PottsModels.openvt_spread_compare(cs, st; z = zc)            # stock − c64
            e = entry[(c, k)]
            push!(rows, (; case = c, metric = k, n_ref = S.n_ref, n_arm = n, mean_ref = S.mean_ref, sd_ref = S.sd_ref,
                mean_stock = S.mean_alt, sd_stock = S.sd_alt, diff_stock = S.diff, z_stock = S.z, beyond_stock = S.beyond,
                mean_c64 = R.mean_alt, sd_c64 = R.sd_alt, diff_c64 = R.diff, z_c64 = R.z, beyond_c64 = R.beyond, crit_ref = zr,
                contrast = X.diff, z_contrast = X.z, crit_contrast = zc, beyond_contrast = X.beyond,
                remainder_fraction = S.diff == 0 ? NaN : R.diff / S.diff,
                diff_entry = p615m_f64(e["diff"]), z_entry = p615m_f64(e["z"]), beyond_entry = e["beyond"]))
        end
    end
    H = (:case, :metric, :n_ref, :n_arm, :mean_ref, :sd_ref, :mean_stock, :sd_stock, :diff_stock, :z_stock, :beyond_stock,
        :mean_c64, :sd_c64, :diff_c64, :z_c64, :beyond_c64, :crit_ref, :contrast, :z_contrast, :crit_contrast, :beyond_contrast,
        :remainder_fraction, :diff_entry, :z_entry, :beyond_entry)
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
    open(joinpath(CB_DIR, "ablation_chain.tsv"), "w") do io
        h = ("arm", "colours", "seed", "T_run_gpu", "T_run_cpu", "accepted_burnin", "committed_burnin", "accepted_relax",
            "committed_relax", "commit_fraction_relax")
        println(io, join(h, '\t'))
        foreach(r -> println(io, join((r[x] for x in h), '\t')), chain)
    end
    frac(a) = (rr = [r for r in chain if r["arm"] == a];
        sum(parse(Int, r["committed_relax"]) for r in rr) / sum(parse(Int, r["accepted_relax"]) for r in rr))
    fracb(a) = (rr = [r for r in chain if r["arm"] == a];
        sum(parse(Int, r["committed_burnin"]) for r in rr) / sum(parse(Int, r["accepted_burnin"]) for r in rr))
    colours_of(a) = only(unique(r["colours"] for r in chain if r["arm"] == a))
    mono_of(a) = only(unique(r["colours"] for r in runs if r["arm"] == a))
    pp = joinpath(CB_DIR, "provenance.toml")
    prov = TOML.parsefile(pp)
    prov["colours"] = "6 colours on the 150 × 5 chain, 4 on the monolayer (stride 2; 5 is not a multiple of 2, D-221)"
    prov["ablation"] = Dict(
        "runner" => relpath(@__FILE__, CB_ROOT), "runner_sha256" => bytes2hex(open(sha256, @__FILE__)),
        "commit" => c64["commit"], "dirty_tracked" => c64["dirty_tracked"] || any(s -> s["dirty_tracked"] == "true", sess),
        "commits" => join(unique([c64["commit"]; [s["commit"] for s in sess]]), ", "),
        "device" => join(unique([c64["device"]; [s["device"] for s in sess]]), "; "),
        "host_planner_fallback" => any(r -> r["planner"] != "device", runs),
        "arms" => "stock: $(colours_of("stock")) colours on the chain, $(mono_of("stock")) on the monolayer, cycle $(only(unique(r["cycle"] for r in runs if r["arm"] == "stock"))); c64: $(colours_of("c64")) on the chain, $(mono_of("c64")) on the monolayer, cycle $(c64["cycle_mcs"]) = 5 T_c64",
        "T_c64" => c64["T_c64"], "T_c64_sd" => c64["T_c64_sd"], "T_c64_run_mean" => c64["T_c64_run_mean"],
        "cycle_c64" => c64["cycle_mcs"], "alpha_c64" => c64["alpha"],
        "chain_commit_fraction_stock" => frac("stock"), "chain_commit_fraction_c64" => frac("c64"),
        "chain_commit_fraction_burnin_stock" => fracb("stock"), "chain_commit_fraction_burnin_c64" => fracb("c64"),
        "chain_replays_equal_gpu" => all(r -> r["T_run_gpu"] == r["T_run_cpu"], chain),
        "seeds" => "c64 chain 214500001–214500100; monolayer 214 400 000 + 1000 arm + 100 case + k",
        "decisions" => ["D-220", "D-221"])
    open(io -> TOML.print(io, prov), pp, "w")
    mp = joinpath(CB_DIR, "meta.toml")
    meta = TOML.parsefile(mp)
    meta["colours"] = prov["colours"]
    open(io -> TOML.print(io, meta), mp, "w")
    @info "ablation" T_c64 = c64["T_c64"] cycle_c64 = c64["cycle_mcs"] chain_stock = frac("stock") chain_c64 = frac("c64") burnin_stock = fracb("stock") burnin_c64 = fracb("c64") replays_equal = prov["ablation"]["chain_replays_equal_gpu"]
    for r in rows
        r.beyond_entry == "true" && println(rpad(r.case, 2), rpad(r.metric, 11), " entry z ", round(r.z_entry; digits = 2),
            " | stock z ", round(r.z_stock; digits = 2), r.beyond_stock ? "*" : "", " | c64 z ", round(r.z_c64; digits = 2),
            r.beyond_c64 ? "*" : "", " | contrast z ", round(r.z_contrast; digits = 2), r.beyond_contrast ? "*" : "",
            " | remainder ", round(r.remainder_fraction; digits = 2))
    end
end

function ab_main(args)
    isempty(args) && error("run_ablation.jl calibrate | count <arm> | run <arm> | collect")
    m = args[1]
    m == "calibrate" ? ab_calibrate() : m == "count" ? ab_count(args[2]) : m == "run" ? ab_run(args[2]) :
    m == "collect" ? ab_collect() : error("run_ablation.jl: bad mode $m")
    return nothing
end
abspath(PROGRAM_FILE) == abspath(@__FILE__) && ab_main(ARGS)

# P6.15m m3, supplementary diagnostic (D-220's colour ablation applied to every metric): do the
# rows of comparison.tsv that D-220's findings do not name (shape, O1 topology, the case (f)
# end ratios) move to the sequential values when the claim-conflict thinning is removed?
#
# Two arms, both on the GPU at the sequential clock (cycle 775, α = 50/775), so that only the
# number of colours differs between them:
#   stock   CheckerboardCPM(; proposal = Moore(1)), 4 colours (stride 2), as the entry;
#   c64     the same with the colour stride widened by 6 (64 colours; D-220's ablation: the
#           read reach of `CorePotts.reach` + 6, redefined in this process only). Fewer
#           simultaneous proposals per colour, so few accepted copies lose a claim.
# Seeds 214 300 000 + 1000 arm + 100 case + k (arm 1 stock, 2 c64; case 1 b, 2 f, 3 a), disjoint
# from every record seed; 20 runs of (b) and (f), 10 of (a). The run, recorder, metrics and the
# critical value are the main runner's (`run_checkerboard.jl`, included) and the frozen test's.
# The sequential arm is the record's (P6.15f series, reference_runs.tsv, reference_o1.tsv).
#
#     P615M_OUT=<dir> taskset -c 0-3 julia -t 4 --project=lib/PottsModels/test …/run_ablation.jl run stock
#     P615M_OUT=<dir> taskset -c 0-3 julia -t 4 --project=lib/PottsModels/test …/run_ablation.jl run c64
#     P615M_OUT=<dir> julia --project=lib/PottsModels/test …/run_ablation.jl collect
#
# Writes ablation.tsv (arm colours cycle case metric n_ref n_alt mean_ref mean_alt diff z crit
# beyond diff_entry z_entry; the last two from comparison.tsv) and ablation_runs.tsv here.
include(joinpath(@__DIR__, "run_checkerboard.jl"))

const AB_ARMS = Dict("stock" => (; id = 1, extra = 0), "c64" => (; id = 2, extra = 6))
const AB_CASES = (; b = (; id = 1, runs = 20), f = (; id = 2, runs = 20), a = (; id = 3, runs = 10))
const AB_CYCLE = P615M_CYCLE_SEQ
ab_seed(arm, c, k) = 214_300_000 + 1000AB_ARMS[arm].id + 100AB_CASES[c].id + k
const AB_RUNS_HEADER = ("arm", "colours", "case", "k", "seed", "retcode", "mcs", "N", "divisions", "live", "planner", "form", "wall_s")

function ab_run(arm)
    extra = AB_ARMS[arm].extra
    if extra != 0
        @eval Potts.CorePotts function reach(fp::Footprint, proposal)
            rp = radius(proposal)
            read = max(fp.read, rp, fp.source_read >= 0 ? rp + fp.source_read : 0)
            write = max(fp.write, fp.source_write >= 0 ? rp + fp.source_write : 0)
            return read + $extra, write
        end
    end
    mkpath(CB_OUT)
    backend = cb_backend()
    ncol = length(Potts.CorePotts.colors(cb_problem(400).lattice, 2 + extra))
    α = A0 / AB_CYCLE
    rp = cb_header!(cb_part("ablation_runs_part.tsv"), AB_RUNS_HEADER)
    mp = cb_header!(cb_part("ablation_metrics_part.tsv"), ("arm", "case", "seed", "metric", "value"))
    for L in (400, 1400)
        Base.invokelatest(cb_run, cb_problem(L), 1, merge(P615F_CASES.b, (; L)); cycle = AB_CYCLE, α, cells = 2, tmax = 50, backend)
    end
    for c in keys(AB_CASES), k in 1:AB_CASES[c].runs
        cc = P615F_CASES[c]
        seed = ab_seed(arm, c, k)
        wall = @elapsed r = Base.invokelatest(cb_run, cb_problem(cc.L), seed, cc; cycle = AB_CYCLE, α, backend)
        s = p615m_series([x.mcs for x in r.rec], [x.N for x in r.rec], [x.r for x in r.rec], [x.A for x in r.rec],
            [x.C for x in r.rec], [x.w for x in r.rec], [x.g for x in r.rec]; cycle = AB_CYCLE)
        m = p615m_seed_metrics(s, cc.cells)
        m["lost"] = r.divisions + 1 - r.live
        m["O1.n_mean"], m["O1.n_sd"], m["O1.n6"], m["O1.i0"] = r.o1.n_mean, r.o1.n_sd, r.o1.n6, r.o1.i0
        open(io -> foreach(key -> println(io, join((arm, c, seed, key, cb_f64(m[key])), '\t')), P615M_ALL), mp, "a")
        open(io -> println(io, join((arm, ncol, c, k, seed, r.retcode, r.mcs, r.rec[end].N, r.divisions, r.live, r.planner, r.form,
                round(wall; digits = 2)), '\t')), rp, "a")
        @info "ablation run" arm ncol c k seed r.mcs r.planner lost = m["lost"] wall = round(wall; digits = 1)
    end
end

function ab_collect()
    runs = p615m_tsv(cb_part("ablation_runs_part.tsv"))
    mets = p615m_tsv(cb_part("ablation_metrics_part.tsv"))
    entry = Dict((r["case"], r["metric"]) => r for r in p615m_tsv(joinpath(CB_DIR, "comparison.tsv")))
    replay = p615m_tsv(joinpath(CB_DIR, "reference_runs.tsv"))
    o1seq = Dict((r["case"], parse(Int, r["seed"])) => r for r in p615m_tsv(joinpath(CB_DIR, "reference_o1.tsv")))
    ref_ts = p615m_tsv(joinpath(REF_F3F8, "timeseries.tsv"))
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
        for arm in ("stock", "c64")
            alt = Dict(k => [p615m_f64(r["value"]) for r in mets if r["arm"] == arm && r["case"] == c && r["metric"] == k] for k in P615M_ALL)
            n = length(alt["lost"])
            n == AB_CASES[Symbol(c)].runs || error("ablation: $arm $c has $n runs")
            ncol = only(unique(r["colours"] for r in runs if r["arm"] == arm))
            zc = p615m_crit(length(ref["lost"]), n)
            for t in PottsModels.openvt_spread_table(ref, alt; z = zc)
                e = entry[(c, t.metric)]
                push!(rows, (; arm, colours = ncol, cycle = AB_CYCLE, case = c, t.metric, t.n_ref, t.n_alt, t.mean_ref, t.mean_alt,
                    t.diff, t.z, crit = zc, t.beyond, diff_entry = p615m_f64(e["diff"]), z_entry = p615m_f64(e["z"]), beyond_entry = e["beyond"]))
            end
        end
    end
    open(joinpath(CB_DIR, "ablation.tsv"), "w") do io
        h = ("arm", "colours", "cycle", "case", "metric", "n_ref", "n_alt", "mean_ref", "mean_alt", "diff", "z", "crit", "beyond",
            "diff_entry", "z_entry", "beyond_entry")
        println(io, join(h, '\t'))
        for r in rows
            println(io, join((r.arm, r.colours, r.cycle, r.case, r.metric, r.n_ref, r.n_alt, cb_f64(r.mean_ref), cb_f64(r.mean_alt),
                cb_f64(r.diff), cb_f64(r.z), cb_f64(r.crit), r.beyond, cb_f64(r.diff_entry), cb_f64(r.z_entry), r.beyond_entry), '\t'))
        end
    end
    open(joinpath(CB_DIR, "ablation_runs.tsv"), "w") do io
        println(io, join(AB_RUNS_HEADER, '\t'))
        for r in sort(runs; by = r -> (r["arm"], r["case"], parse(Int, r["k"])))
            println(io, join((r[h] for h in AB_RUNS_HEADER), '\t'))
        end
    end
    for r in rows
        r.beyond_entry == "true" && println(rpad(r.arm, 6), rpad(r.case, 2), rpad(r.metric, 11), " entry z ", round(r.z_entry; digits = 2),
            "  ", r.arm, " z ", round(r.z; digits = 2), r.beyond ? " BEYOND" : "")
    end
end

ab_main(args) = isempty(args) ? error("run_ablation.jl run <stock|c64> | collect") :
                args[1] == "run" ? ab_run(args[2]) : args[1] == "collect" ? ab_collect() : error("run_ablation.jl: bad mode")
abspath(PROGRAM_FILE) == abspath(@__FILE__) && ab_main(ARGS)

#     julia --project=lib/PottsModels/test -t 4 benchmark/kinetics/k4_monolayer.jl <repo> <runs> [<cases> <out> <block,switches,parts>]   # ROCm
# K4 (P6.0bl): the OpenVT monolayer cases (b) and (f) under a CheckerboardCPM variant on the GPU,
# at SequentialCPM's own time unit (no calibration), compared with the sequential record by the
# P6.15m rules (per-seed metrics, crit(ν), PottsModels.openvt_spread_table).
include(joinpath(ARGS[1], "lib/PottsModels/reproductions/data/15/checkerboard-2026-10-10/run_checkerboard.jl"))
using Printf
# ARGS[5]: block,switches,parts (default: the CheckerboardCPM defaults)
const K4_SR = split(get(ARGS, 5, ""), ',', keepempty = false)
const K4_ALG = isempty(K4_SR) ? CheckerboardCPM(; proposal = Moore(1)) :
               CheckerboardCPM(; proposal = Moore(1), region = parse(Int, K4_SR[1]), switches = parse(Int, K4_SR[2]),
                   parts = parse(Int, K4_SR[3]))
const K4_OUT = expanduser(get(ARGS, 4, "~/lpwork/cbk/k4-2026-11-03"))
const K4_CASES = Tuple(Symbol.(split(get(ARGS, 3, "b,f"), ',')))
const K4_RUNS = parse(Int, ARGS[2])
mkpath(K4_OUT)
cycle = P615M_CYCLE_SEQ
α = A0 / cycle
k4_seed(c, k) = 217_000_000 + 1000 * findfirst(==(c), K4_CASES) + k
function k4_run(prob, seed, c; backend = cb_backend())
    rec = NamedTuple[]
    record(integ) = push!(rec, p615f_row(integ.u, integ.t; c.beta, c.gamma))
    cbr = Potts.DiscreteCallback((u, t, integ) -> t % CB_EVERY == 0 || count(>(0), u.cell.volume) >= c.cells,
        record; initialize = (cb, u, t, integ) -> record(integ), save_positions = (false, false))
    pr = remake(prob; seed, p = [:β => c.beta, :γ => c.gamma, :σ_X => c.sigma_X, :α => α])
    integ = init(pr, K4_ALG; backend, save_start = false,
        callback = Potts.CorePotts.CallbackSet(cbr, PottsModels.stop_at_cells(c.cells),
            PottsModels.edge_guard(P615F_GUARD; terminate = true)))
    sol = solve!(integ)
    cb_sync()
    u = sol.u[end]
    fr = PottsModels.openvt_frame(u; β = c.beta, γ = c.gamma)
    o1 = (; n_mean = mean(fr.n), n_sd = std(fr.n), n6 = mean(fr.n .== 6), i0 = mean(fr.i .== 0), cells = length(fr.n))
    return (; retcode = Symbol(sol.retcode), mcs = Int(sol.t[end]), rec, divisions = sol.stats.lifecycle.divisions,
        live = count(>(0), Array(u.cell.volume)), o1, committed = sol.stats.committed)
end
tsf, o1f, rf = joinpath(K4_OUT, "timeseries.tsv"), joinpath(K4_OUT, "o1.tsv"), joinpath(K4_OUT, "runs.tsv")
open(io -> println(io, join(TS_HEADER, '\t')), tsf, "w")
open(io -> println(io, join(O1_HEADER, '\t')), o1f, "w")
open(io -> println(io, join(("case", "k", "seed", "retcode", "mcs", "divisions", "live", "wall_s", "committed"), '\t')), rf, "w")
@info "K4" cycle α alg = K4_ALG
k4_run(cb_problem(400), 1, merge(P615F_CASES.b, (; cells = 2)))           # compile
for c in K4_CASES, k in 1:K4_RUNS
    cc = P615F_CASES[c]
    sd = k4_seed(c, k)
    wall = @elapsed r = k4_run(cb_problem(cc.L), sd, cc)
    open(tsf, "a") do io
        for x in r.rec
            println(io, join((c, sd, x.mcs, x.N, cb_f64(x.r), cb_f64(x.A), cb_f64(x.C), cb_f64(x.w), cb_f64(x.g)), '\t'))
        end
    end
    open(io -> println(io, join((c, sd, r.mcs, r.o1.cells, cb_f64(r.o1.n_mean), cb_f64(r.o1.n_sd), cb_f64(r.o1.n6),
        cb_f64(r.o1.i0)), '\t')), o1f, "a")
    open(io -> println(io, join((c, k, sd, r.retcode, r.mcs, r.divisions, r.live, round(wall; digits = 2), r.committed), '\t')), rf, "a")
    k % 10 == 0 && @info "run" c k r.mcs lost = r.divisions + 1 - r.live wall = round(wall; digits = 1)
end
# the comparison, as `collect_main` does it
ts = p615m_tsv(tsf)
rp = p615m_tsv(rf)
ref_ts = p615m_tsv(joinpath(REF_F3F8, "timeseries.tsv"))
replay = p615m_tsv(joinpath(CB_DIR, "reference_runs.tsv"))
o1v = Dict((r["case"], parse(Int, r["seed"])) => r for r in p615m_tsv(o1f))
o1seq = ref_o1()
lostof(rows) = Dict(parse(Int, r["seed"]) => parse(Int, r["divisions"]) + 1 - parse(Int, r["live"]) for r in rows)
nflag, nrow = 0, 0
for c in string.(K4_CASES)
    P = P615M_CASES[c]
    M = Dict{String, Any}()
    for (alg, sers, lost, o1) in (
        ("sequential", p615m_record_series(ref_ts, c; cycle = P615M_CYCLE_SEQ), lostof([r for r in replay if r["case"] == c]), o1seq),
        ("variant", p615m_record_series(ts, c; cycle), lostof([r for r in rp if r["case"] == c]), o1v))
        T = Dict(k => Dict{Int, Float64}() for k in P615M_ALL)
        for (sd, s) in sers
            m = p615m_seed_metrics(s, P.cells)
            foreach(k -> (T[k][sd] = m[k]), P615M_METRICS)
            T["lost"][sd] = lost[sd]
            foreach(((k, v),) -> (T[k][sd] = v), o1metrics(o1[(c, sd)]))
        end
        M[alg] = T
    end
    zc = p615m_crit(length(M["sequential"]["lost"]), length(M["variant"]["lost"]))
    tab = PottsModels.openvt_spread_table(Dict(k => p615m_vals(M["sequential"][k]) for k in P615M_ALL),
        Dict(k => p615m_vals(M["variant"][k]) for k in P615M_ALL); z = zc)
    open(joinpath(K4_OUT, "comparison_$c.tsv"), "w") do io
        println(io, join(("metric", "mean_ref", "mean_alt", "ratio", "z", "beyond"), '\t'))
        for t in tab
            println(io, join((t.metric, cb_f64(t.mean_ref), cb_f64(t.mean_alt), cb_f64(t.mean_alt / t.mean_ref), cb_f64(t.z), t.beyond), '\t'))
            @printf("%s %-10s seq %10.4g  variant %10.4g  ratio %6.3f  z %6.2f %s\n", c, t.metric, t.mean_ref, t.mean_alt,
                t.mean_alt / t.mean_ref, t.z, t.beyond ? "BEYOND" : "")
        end
    end
    global nflag += count(t -> t.beyond, tab)
    global nrow += length(tab)
    println("case $c: crit = $(round(zc; digits = 2)), $(count(t -> t.beyond, tab)) of $(length(tab)) beyond")
end
println("K4 total: $nflag of $nrow rows beyond crit (stock checkerboard record, cases a, b, f: 31 of 102)")

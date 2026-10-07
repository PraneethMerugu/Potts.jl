# P6.15e (ROADMAP Step 3b): the OpenVT monolayer benchmark's Fig 5, "100 runs of 1000 cells",
# case (b), target V4, with a negative control. Frozen (AUTONOMY §7.3). The protocol is
# spec 15 §4.0.1 case (b), §3.1 O2 and §3.4, and the pre-registered target is §4.1 V4
# (docs/design/research/model-specs/15_openvt_monolayer.md v3.1); every reference value
# below is copied from there. The pass margins, the peak rule, the seeds, the lattice, the
# control's γ and the SMOKE bands are the test author's (P6.15e; see the D-entry).
#
# V4 as spec 15 §4.1 states it. Pooled over 100 runs (TST_5T, Morpheus_5T; G zips):
#   "≈ 89% of cells at f = 0; nonzero f peaked at 0.25–0.35 with no cell above f = 0.56;
#    a peaked at 0.85–0.90, range 0.42–1.09; mean a = 0.85–0.86, mean f ≈ 0.03".
#   Proposed pass band: "the same; a negative control (γ > 0 shifts f mass)".
#
# How "the same" is read here (one row per clause; the margins are the test author's):
#
# | Row  | Statistic of the pooled cells                        | Consortium (V4) | Pass band            |
# |------|------------------------------------------------------|-----------------|----------------------|
# | V4.1 | fraction of cells with f == 0                        | ≈ 0.89          | [0.86, 0.92] (± 0.03)|
# | V4.2 | peak of the nonzero-f histogram (rule below)         | 0.25–0.35       | [0.22, 0.38] (± 0.03)|
# | V4.3 | max f                                                | ≤ 0.56          | ≤ 0.61 (+ 0.05)      |
# | V4.4 | peak of the a histogram (rule below)                 | 0.85–0.90       | [0.82, 0.93] (± 0.03)|
# | V4.5 | range of a: min a, max a                             | 0.42–1.09       | ⊂ [0.32, 1.19] (± 0.1)|
# | V4.6 | mean a                                               | 0.85–0.86       | [0.82, 0.89] (± 0.03)|
# | V4.7 | mean f                                               | ≈ 0.03          | [0.02, 0.04] (± 0.01)|
#
# V4 passes iff every row passes.
#
# Peak rule (V4.2, V4.4). Values are binned at width 0.01 as M's notebook does
# (`np.arange(-0.01, 1.01, 0.01)`, spec §3.4), extended to [0, 2): bin k (0-based) holds
# k/100 ≤ x < (k + 1)/100, k = floor(Int, 100x + 1e-9) (the 1e-9 puts values that are
# decimal bin edges up to rounding, e.g. 0.29 = 29/100, in their own bin). The peak is the
# centre (k + 0.5)/100 of the bin whose centred 5-bin running mean (bins k − 2 … k + 2,
# truncated at the ends) is largest; the first such bin on ties. For V4.2 the cells with
# f == 0 are removed from bin 0 (a cell with u ≥ 100 unlike pairs can have 0 < f < 0.01, so
# bin 0 also holds nonzero f: 26 cells of 10⁵ in the FULL record).
#
# Re-freeze (P6.15e, before merge): the first freeze dropped all of bin 0 for V4.2 and
# asserted that bin 0 held exactly the f == 0 cells; the FULL record falsified that premise
# (bin 0: 88 829 cells, f == 0: 88 803). The rule now drops exactly the f == 0 cells and the
# premise assertion is replaced by hf[1] ≥ n_f0. No band, seed, run or target changed; every
# V4 verdict of the record is the same under both rules.
#
# Negative control (D-048; spec V4 "γ > 0 shifts f mass"). The same runs with type-2
# contact inhibition γ = 1e-4 (any cell without medium contact stops growing: the lattice
# γ → 0⁺ case of V3b). Interior cells stop growing, relax to their reference area and stop
# dividing. Pre-registered: the control FAILS V4, at least on V4.6 (mean a > 0.89) and V4.4
# (a peak > 0.93).
#
# Protocol (case (b), spec §4.0.1): `OpenVTReferenceMonolayer` at its Table S1 defaults
# (β = γ = 0, σ_X = 0.4), one disc cell at the centre (`openvt_reference_state`), on a
# closed 400 × 400 lattice (M: an unbounded plane; the colony of 1000 cells has a radius of
# about 140 px, and `edge_guard(5; terminate = true)` fails a run that comes within 5 sites
# of the edge, which the record checks), `SequentialCPM(; proposal = Moore(1))`, stopped at
# the end of the first MCS with ≥ 1000 live cells (`stop_at_cells(1000)`; G11). The O2 rows
# (`openvt_snapshot`, spec §3.1: x, y, r in R from the lattice centre, f, a) of that state
# are the run's cells. Seeds: run k = 1 … 100 → 15_000 + k; control run k → 15_500 + k
# (20 runs); SMOKE → 95_000 + k.
#
# Tiers.
# - always: the peak rule and the V4 verdicts on synthetic pools with known answers.
# - SMOKE (the default; under a minute plus one model compilation): 2 + 2 runs to 300 cells
#   on 240 × 240; the O2 rows are consistent and the rules evaluate; the γ = 1e-4 control has
#   a higher mean a than case (b) (the mechanism the control rests on).
# - FULL record (always, cheap): reads the committed D-146 record
#   `reproductions/data/15/f5-2026-10-07/` (`runs.tsv`, `hist.tsv`), recomputes every V4
#   row from it with the rules of this file, and requires V4 to pass for case (b) and to fail
#   (on V4.4 and V4.6) for the control. A failing case (b) row must instead appear in the
#   record's `deviations.tsv` (D-154: our value | paper's value | suspected cause |
#   author-question status), and the row is then `@test_broken`.
# - FULL (POTTS_FULL_REPRODUCTION=true or REPRO=full, offline, D-146): reruns the 100 + 20
#   runs and requires the same verdicts.
using Potts, PottsModels, Test
using Statistics: mean

const P615E_FULL = get(ENV, "POTTS_FULL_REPRODUCTION", "false") == "true" || get(ENV, "REPRO", "") == "full"
const P615E_RECORD = joinpath(pkgdir(PottsModels), "reproductions", "data", "15", "f5-2026-10-07")

# ---------------------------------------------------------------------------------------------
# V4 (spec 15 §4.1), verbatim, and the pass bands (test author)
# ---------------------------------------------------------------------------------------------

const P615E_V4_PAPER = (f0 = "≈ 0.89", f_peak = "0.25–0.35", f_max = "≤ 0.56", a_peak = "0.85–0.90",
    a_range = "0.42–1.09", a_mean = "0.85–0.86", f_mean = "≈ 0.03")
const P615E_BAND = (f0 = (0.86, 0.92), f_peak = (0.22, 0.38), f_max = (-Inf, 0.61),
    a_peak = (0.82, 0.93), a_min = (0.32, Inf), a_max = (-Inf, 1.19), a_mean = (0.82, 0.89),
    f_mean = (0.02, 0.04))
const P615E_ROWS = (:f0, :f_peak, :f_max, :a_peak, :a_range, :a_mean, :f_mean)
const P615E_ROW_ID = (f0 = "V4.1", f_peak = "V4.2", f_max = "V4.3", a_peak = "V4.4", a_range = "V4.5",
    a_mean = "V4.6", f_mean = "V4.7")
const P615E_NBINS = 200                              # width 0.01 on [0, 2)
const P615E_N = 100                                  # M: 100 runs (C4)
const P615E_NCTL = 20
const P615E_CELLS = 1000
const P615E_L = 400
const P615E_GAMMA_CTL = 1e-4
p615e_seed(k) = 15_000 + k
p615e_seed_ctl(k) = 15_500 + k
p615e_seed_smoke(k) = 95_000 + k
const P615E_ALG = SequentialCPM(; proposal = Moore(1))

# ---------------------------------------------------------------------------------------------
# The rules
# ---------------------------------------------------------------------------------------------

p615e_bin(x) = floor(Int, 100x + 1e-9)               # 0-based bin of width 0.01
function p615e_hist(xs)
    h = zeros(Int, P615E_NBINS)
    for x in xs
        k = p615e_bin(x)
        0 <= k < P615E_NBINS || throw(ArgumentError("p615e_hist: $x outside [0, 2)"))
        h[k + 1] += 1
    end
    return h
end
# the peak: centre of the bin with the largest centred 5-bin running mean; `skip0` drops bin 0
function p615e_peak(h; skip0 = false)
    g = copy(h)
    skip0 && (g[1] = 0)
    n = length(g)
    s = [sum(g[max(1, k - 2):min(n, k + 2)]) / (min(n, k + 2) - max(1, k - 2) + 1) for k in 1:n]
    return (argmax(s) - 0.5) / 100
end

# Pooled summary of a set of cells: everything V4 reads
p615e_summary(f, a) = (; n = length(f), n_f0 = count(==(0), f), sum_f = sum(f; init = 0.0),
    sum_a = sum(a; init = 0.0), f_max = maximum(f), a_min = minimum(a), a_max = maximum(a),
    hf = p615e_hist(f), ha = p615e_hist(a))
function p615e_merge(ss)
    return (; n = sum(s.n for s in ss), n_f0 = sum(s.n_f0 for s in ss), sum_f = sum(s.sum_f for s in ss),
        sum_a = sum(s.sum_a for s in ss), f_max = maximum(s.f_max for s in ss),
        a_min = minimum(s.a_min for s in ss), a_max = maximum(s.a_max for s in ss),
        hf = sum(s.hf for s in ss), ha = sum(s.ha for s in ss))
end
p615e_in(x, (lo, hi)) = lo <= x <= hi
# V4: the statistics and the per-row verdicts of a pooled summary
function p615e_v4(s)
    hfn = copy(s.hf)
    hfn[1] -= s.n_f0                                 # nonzero f only
    v = (f0 = s.n_f0 / s.n, f_peak = p615e_peak(hfn), f_max = s.f_max,
        a_peak = p615e_peak(s.ha), a_min = s.a_min, a_max = s.a_max, a_mean = s.sum_a / s.n,
        f_mean = s.sum_f / s.n)
    B = P615E_BAND
    ok = (f0 = p615e_in(v.f0, B.f0), f_peak = p615e_in(v.f_peak, B.f_peak), f_max = p615e_in(v.f_max, B.f_max),
        a_peak = p615e_in(v.a_peak, B.a_peak),
        a_range = p615e_in(v.a_min, B.a_min) && p615e_in(v.a_max, B.a_max),
        a_mean = p615e_in(v.a_mean, B.a_mean), f_mean = p615e_in(v.f_mean, B.f_mean))
    return (; v, ok, pass = all(ok))
end

# One run of case (b) (γ = 0) or the control (γ > 0): the O2 rows of the stopping state
function p615e_problem(L)
    sys = OpenVTReferenceMonolayer(; name = Symbol(:p615e_m, L), lattice = (L, L))
    return PottsProblem(sys, openvt_reference_state(; lattice = (L, L)), (0, 100_000); capacity = 1500, seed = 1)
end
function p615e_run(prob, seed, γ; cells = P615E_CELLS)
    sol = solve(remake(prob; seed, p = [:γ => γ]), P615E_ALG;
        callback = Potts.CorePotts.CallbackSet(PottsModels.stop_at_cells(cells), PottsModels.edge_guard(5; terminate = true)))
    return (; retcode = Symbol(sol.retcode), mcs = sol.t[end], rows = PottsModels.openvt_snapshot(sol.u[end]))
end
function p615e_runs(prob, seeds, γ; cells = P615E_CELLS)
    out = Vector{Any}(undef, length(seeds))
    Threads.@threads :dynamic for j in eachindex(seeds)
        out[j] = p615e_run(prob, seeds[j], γ; cells)
    end
    return out
end

# ---------------------------------------------------------------------------------------------
# always: the rules on synthetic pools
# ---------------------------------------------------------------------------------------------

@testset "P6.15e rules: bins, peak, V4 verdicts on synthetic pools" begin
    @test p615e_bin(0.0) == 0 && p615e_bin(0.009999) == 0 && p615e_bin(0.01) == 1
    @test p615e_bin(0.29) == 29 && p615e_bin(29 / 100) == 29 && p615e_bin(0.3) == 30 && p615e_bin(1.09) == 109
    @test p615e_bin(1 / 3) == 33 && p615e_bin(0.5) == 50
    @test_throws ArgumentError p615e_hist([2.0])
    @test_throws ArgumentError p615e_hist([-0.001])
    # the peak is the bin centre of the smoothed maximum, not of a lone spike
    h = zeros(Int, P615E_NBINS)
    h[31:33] .= 10            # bins 30–32: a broad mode around 0.31
    h[71] = 25                # a lone spike at bin 70
    @test p615e_peak(h) ≈ 0.305                        # windows of bins 30, 31, 32 tie; first
    @test p615e_peak(h; skip0 = true) ≈ 0.305
    h[1] = 1000
    @test p615e_peak(h) ≈ 0.005                        # bins 0–2 (truncated window); first maximum
    @test p615e_peak(h; skip0 = true) ≈ 0.305          # bin 0 dropped
    # a pool built to sit inside every band passes; each clause can fail on its own
    f = [zeros(890); fill(0.30, 100); fill(0.31, 9); 0.55]
    a = [fill(0.86, 600); fill(0.85, 300); fill(0.5, 50); fill(1.05, 49); 0.43]
    s = p615e_summary(f, a)
    r = p615e_v4(s)
    @test r.pass && all(r.ok)
    @test r.v.f0 == 0.89 && r.v.f_peak ≈ 0.295 && r.v.a_peak ≈ 0.845   # first tied windows
    @test isapprox(r.v.f_mean, (30 + 2.79 + 0.55) / 1000) && 0.02 <= r.v.f_mean <= 0.04
    @test !p615e_v4(p615e_summary([zeros(800); fill(0.30, 200)], a)).ok.f0          # 80 % at f = 0
    @test !p615e_v4(p615e_summary([f[1:(end - 1)]; 0.7], a)).ok.f_max                # one cell above
    @test !p615e_v4(p615e_summary([zeros(890); fill(0.5, 110)], a)).ok.f_peak        # peak at 0.5
    @test !p615e_v4(p615e_summary(f, [a[1:(end - 1)]; 0.2])).ok.a_range              # a too low
    @test !p615e_v4(p615e_summary(f, fill(0.99, 1000))).ok.a_mean
    @test !p615e_v4(p615e_summary(f, fill(0.99, 1000))).ok.a_peak
    @test !p615e_v4(p615e_summary(f, fill(0.99, 1000))).pass
    # merging run summaries is pooling the cells
    m = p615e_merge([p615e_summary(f[1:500], a[1:500]), p615e_summary(f[501:end], a[501:end])])
    @test m.n == s.n && m.n_f0 == s.n_f0 && m.hf == s.hf && m.ha == s.ha && m.f_max == s.f_max &&
          m.a_min == s.a_min && m.a_max == s.a_max && m.sum_f ≈ s.sum_f && m.sum_a ≈ s.sum_a
end

# ---------------------------------------------------------------------------------------------
# SMOKE: 2 + 2 runs to 300 cells on 240 × 240
# ---------------------------------------------------------------------------------------------

if !P615E_FULL
    @testset "P6.15e SMOKE: case (b) and the γ control to 300 cells" begin
        prob = p615e_problem(240)
        b = p615e_runs(prob, [p615e_seed_smoke(k) for k in 1:2], 0.0; cells = 300)
        c = p615e_runs(prob, [p615e_seed_smoke(k) for k in 3:4], P615E_GAMMA_CTL; cells = 300)
        for r in [b; c]
            @test r.retcode === :Terminated                   # stopped by stop_at_cells, not the edge guard
            n = length(r.rows.f)
            @test 300 <= n <= 310
            @test all(x -> 0 <= x <= 1, r.rows.f) && all(>(0), r.rows.a) && all(>(0), r.rows.r)
            # the O2 lengths are in R from the centre: inside the lattice (120 px = 30.1 R)
            @test 10 < maximum(hypot.(r.rows.x, r.rows.y)) < 30
            @test count(==(0), r.rows.f) > 0
        end
        sb = p615e_merge([p615e_summary(r.rows.f, r.rows.a) for r in b])
        sc = p615e_merge([p615e_summary(r.rows.f, r.rows.a) for r in c])
        vb, vc = p615e_v4(sb), p615e_v4(sc)
        @info "P6.15e SMOKE" vb.v vc.v
        @test all(isfinite, values(vb.v)) && all(isfinite, values(vc.v))
        @test sb.n == sum(sb.hf) == sum(sb.ha) && sb.n_f0 <= sb.hf[1]
        # the control's mechanism: arrested interior cells relax toward their reference area
        @test vc.v.a_mean > vb.v.a_mean + 0.015          # measured 0.957 vs 0.925 on these seeds
        # and the control takes longer to reach 300 cells
        @test minimum(r.mcs for r in c) > maximum(r.mcs for r in b)
    end
end

# ---------------------------------------------------------------------------------------------
# FULL record (D-146): recompute V4 from the committed runs.tsv / hist.tsv
# ---------------------------------------------------------------------------------------------

function p615e_tsv(path)
    l = split.(readlines(path), '\t')
    return [Dict(zip(l[1], r)) for r in l[2:end]]
end
# the pooled summary of one case of the record: per-run scalars from runs.tsv, histograms
# from hist.tsv (summed over the distance bins)
function p615e_record_summary(runs, hist, case)
    rs = [r for r in runs if r["case"] == case]
    hf, ha = zeros(Int, P615E_NBINS), zeros(Int, P615E_NBINS)
    for h in hist
        h["case"] == case || continue
        k = parse(Int, h["bin"]) + 1
        (h["quantity"] == "f" ? hf : ha)[k] += parse(Int, h["count"])
    end
    P(x, T = Float64) = parse(T, x)
    return (; n = sum(P(r["N"], Int) for r in rs), n_f0 = sum(P(r["n_f0"], Int) for r in rs),
        sum_f = sum(P(r["sum_f"]) for r in rs), sum_a = sum(P(r["sum_a"]) for r in rs),
        f_max = maximum(P(r["f_max"]) for r in rs), a_min = minimum(P(r["a_min"]) for r in rs),
        a_max = maximum(P(r["a_max"]) for r in rs), hf, ha), rs
end

@testset "P6.15e FULL record: V4 (case (b), 100 runs of 1000 cells) and the negative control" begin
    runs_f, hist_f = joinpath(P615E_RECORD, "runs.tsv"), joinpath(P615E_RECORD, "hist.tsv")
    @test isfile(runs_f) && isfile(hist_f) && isfile(joinpath(P615E_RECORD, "provenance.toml"))
    if isfile(runs_f) && isfile(hist_f)
        runs, hist = p615e_tsv(runs_f), p615e_tsv(hist_f)
        sb, rb = p615e_record_summary(runs, hist, "b")
        sc, rc = p615e_record_summary(runs, hist, "control")
        # the record is the pre-registered protocol
        @test sort([parse(Int, r["seed"]) for r in rb]) == [p615e_seed(k) for k in 1:P615E_N]
        @test sort([parse(Int, r["seed"]) for r in rc]) == [p615e_seed_ctl(k) for k in 1:P615E_NCTL]
        @test all(r -> parse(Float64, r["gamma"]) == 0, rb) && all(r -> parse(Float64, r["gamma"]) == P615E_GAMMA_CTL, rc)
        @test all(r -> r["retcode"] == "Terminated" && parse(Int, r["N"]) >= P615E_CELLS, [rb; rc])
        @test all(r -> parse(Int, r["lattice"]) == P615E_L, [rb; rc])
        # the histograms hold every cell once per quantity; bin 0 of f holds the f == 0 cells
        for s in (sb, sc)
            @test sum(s.hf) == s.n == sum(s.ha)
            @test s.hf[1] >= s.n_f0
        end
        dev_f = joinpath(P615E_RECORD, "deviations.tsv")
        devs = isfile(dev_f) ? [d["target"] for d in p615e_tsv(dev_f)] : String[]
        vb = p615e_v4(sb)
        for row in P615E_ROWS
            id = P615E_ROW_ID[row]
            if vb.ok[row]
                @test vb.ok[row]
            else
                # a failing row is a D-154 deviation: it must be in the record's table
                @test any(startswith(id), devs)
                @test_broken vb.ok[row]
            end
        end
        # the committed verdicts agree with this recomputation
        ver = p615e_tsv(joinpath(P615E_RECORD, "verdicts.tsv"))
        for row in P615E_ROWS
            id = P615E_ROW_ID[row]
            rr = [r for r in ver if startswith(r["target"], id * " ") && r["case"] == "b"]
            @test length(rr) == 1 && only(rr)["result"] == (vb.ok[row] ? "PASS" : "FAIL")
        end
        # negative control: V4 fails, on V4.4 and V4.6 at least
        vc = p615e_v4(sc)
        @test !vc.pass
        @test !vc.ok.a_mean && vc.v.a_mean > P615E_BAND.a_mean[2]
        @test !vc.ok.a_peak && vc.v.a_peak > P615E_BAND.a_peak[2]
    end
end

# ---------------------------------------------------------------------------------------------
# FULL: rerun the 100 + 20 runs (offline, D-146)
# ---------------------------------------------------------------------------------------------

if P615E_FULL
    @testset "P6.15e FULL: V4 and the negative control, rerun" begin
        prob = p615e_problem(P615E_L)
        b = p615e_runs(prob, [p615e_seed(k) for k in 1:P615E_N], 0.0)
        c = p615e_runs(prob, [p615e_seed_ctl(k) for k in 1:P615E_NCTL], P615E_GAMMA_CTL)
        @test all(r -> r.retcode === :Terminated && length(r.rows.f) >= P615E_CELLS, [b; c])
        vb = p615e_v4(p615e_merge([p615e_summary(r.rows.f, r.rows.a) for r in b]))
        vc = p615e_v4(p615e_merge([p615e_summary(r.rows.f, r.rows.a) for r in c]))
        @info "P6.15e FULL" vb.v vc.v
        for row in P615E_ROWS
            @test vb.ok[row]
        end
        @test !vc.pass && !vc.ok.a_mean && !vc.ok.a_peak
    end
end

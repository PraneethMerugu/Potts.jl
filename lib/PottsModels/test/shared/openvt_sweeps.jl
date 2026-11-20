using Potts, PottsModels, Test
using Statistics: mean
const INHIBITION_FULL = get(ENV, "POTTS_FULL_REPRODUCTION", "false") == "true" ||
    get(ENV, "REPRO", "") == "full"
const REPO = get(ENV, "OPENVT_MONOLAYER_REPO", "")
const DATA = joinpath(pkgdir(PottsModels), "reproductions", "data", "15")
# ------------------------------------------------------------------------------------------
# Protocol constants (test author)
# ------------------------------------------------------------------------------------------
const CYCLE = 775
# MCS per cycle (5T, C1)
const INHIBITION_T0 = 13.57
# M's uninhibited time (Table 1 caption)
const MULTS = (1.1, 2.0, 5.0, 10.0, 20.0)
tau(m) = round(INHIBITION_T0 * m; digits = 4)
# 14.927, 27.14, 67.85, 135.7, 271.4
const CAP = 210_335
# 271.4 × 775 MCS: the 20× cap
const CELLS = 10_000
const GUARD = 5
const INHIBITION_ALG = SequentialCPM(; skip_interior = true, proposal = Moore(1))
const LATTICE = (beta = 1400, gamma = 1800)
const GRID = (
    beta = [
        0, 2500, 5000, 6000, 6500, 7000, 7500, 8000, 8500,
        8727, 9000, 9334, 9500, 9600, 9700, 9800, 9900,
        10_000, 10_060, 10_100, 10_150, 10_200, 10_250, 10_300,
    ],
    gamma = [
        1, 10, 100, 500, 1000, 1500, 2000, 3000, 4000,
        4500, 5000, 5500, 6000, 6500, 7000, 7500, 8000,
    ],
)
const V2B = [8727, 9000, 9334, 9500, 10_000]
# matched β of the V2b references
const INHIBITION_K = 2
const NFINAL = 6
const TARGETS = [
    (:beta, 1.1), (:beta, 2.0), (:beta, 5.0), (:beta, 10.0), (:beta, 20.0),
    (:gamma, 5.0), (:gamma, 10.0), (:gamma, 20.0),
]
function inhibition_n1(sweep, q)
    if sweep === :beta
        if q == 0
            return 10
        elseif q in V2B
            return 5
        else
            return 1
        end
    elseif q == 1
        return 5
    else
        return 1
    end
end
inhibition_seed(sweep, q, k) = (sweep === :beta ? 160_000_000 : 170_000_000) + 100q + k
params(sweep, q) = sweep === :beta ? (q / 10_000, 0.0) : (0.0, q / 10_000)
seed_smoke(k) = 95_400 + k
# ------------------------------------------------------------------------------------------
# Targets: the lattice spread (spec §4.1, from Table 1) and the pass bands (test author)
# ------------------------------------------------------------------------------------------
const V1_BAND = (0.9 * INHIBITION_T0, 1.1 * INHIBITION_T0)
const V2_SPREAD = Dict(
    1.1 => (0.687, 0.704), 2.0 => (0.936, 0.943), 5.0 => (0.9867, 0.9916),
    10.0 => (1.006, 1.011), 20.0 => (1.02, 1.024)
)
const V2_MARGIN = Dict(1.1 => 0.02, 2.0 => 0.02, 5.0 => 0.005, 10.0 => 0.005, 20.0 => 0.005)
const V3_SPREAD = Dict(5.0 => (0.076, 0.12), 10.0 => (0.45, 0.5), 20.0 => (0.715, 0.76))
const V3_MARGIN = 0.05
const V2B_RATIO = (0.75, 1.25)
const V3B_BAND = (61.0, 70.0)
const F7_MIN = 0.9
function inhibition_band(sweep, m)
    if sweep === :beta
        return (V2_SPREAD[m][1] - V2_MARGIN[m], V2_SPREAD[m][2] + V2_MARGIN[m])
    else
        return (V3_SPREAD[m][1] - V3_MARGIN, V3_SPREAD[m][2] + V3_MARGIN)
    end
end
inhibition_mid(m) = m == 1.1 ? "1.1x" : string(Int(m), "x")
inhibition_row(sweep, m) = (sweep === :beta ? "V2." : "V3.") * inhibition_mid(m)
const ROWS = [
    "V1"; ["V2." * inhibition_mid(m) for m in MULTS];
    ["V2b." * string(q / 10_000) for q in V2B];
    ["V3." * inhibition_mid(m) for m in MULTS]; "V3b"; "F7.1"
]
const CONTROLS = ["NC1", "NC2", "NC3"]
# ------------------------------------------------------------------------------------------
# Consortium constants from G (54f375f), computed with this file's rules on 2026-10-08:
# mrule on `results/TST/TST_time_to_10k_vs_{beta,gamma}.csv` and
# `results/Artistoo/Monolayer/time_to_10k_vs_{beta,gamma}.csv` (rows grouped by parameter
# value, mean time), and the TST final snapshots `results/TST/final_snapshot_data/*.csv`
# ------------------------------------------------------------------------------------------
const INHIBITION_G = (
    # thresholds at 1.1, 2, 5, 10, 20× (β) and 5, 10, 20× (γ), "—" at γ 1.1× and 2×, by M's
    # rule on the nearest run (`runs`, TST's Table 1 row) and on the nearest point mean
    # (`means`, Artistoo's row except its 1.1× β, and this file's rule); β rows are not
    # repeated
    tst_beta = [0.7037, 0.9361, 0.9867, 1.006, 1.02], art_beta = [
        0.698182, 0.937665, 0.987636, 1.005947, 1.020946,
    ],
    tst_gamma_runs = [0.12, 0.5, 0.75], tst_gamma_means = [0.12, 0.5113, 0.75],
    art_gamma_runs = [0.07562, 0.45, 0.7], art_gamma_means = [0.07562, 0.450193, 0.715045],
    # V2b references (5T) at the matched β (G's 0.872727 and 0.933368 for Artistoo)
    v2b = [18.59, 20.4, 25.59, 32.11, 105.76],
    # V3b: the first γ > 0 sample of each (TST γ = 1e-4; Artistoo γ = 0.0195)
    v3b = [61.37, 63.09],
    # V1 context: TST mean over β = 0.25–0.5 (5 runs), Artistoo mean over β ≤ 0.52 (6 runs)
    plateau = [13.77, 13.856],
    # TST final snapshots (10⁴ cells): inhibited fraction at γ = 0.12, 0.5, 0.75 (F7.1
    # premise)
    tst_f7 = [0.961008, 0.978402, 0.990002],
    # furthest centroid from the colony centre, px (R = 3.989 px): β = 1.02 and γ = 0.75
    rmax_px = (beta = 490.83, gamma = 602.3),
)
# ------------------------------------------------------------------------------------------
# The rules
# ------------------------------------------------------------------------------------------
function inhibition_mean(t)
    (
        isempty(t) && throw(ArgumentError("inhibition_mean: no runs"));
        any(isinf, t) ? Inf : mean(t)
    )
end
inhibition_in(x, (lo, hi)) = lo <= x <= hi
# the sampled points of one sweep, ascending (the γ sweep scans γ > 0 only)
inhibition_points(S, sweep) = sort([q for (sw, q) in keys(S) if sw === sweep])
# first adjacent pair (ascending) with t̄(lo) ≤ τ < t̄(hi), over the given points; nothing =
# "—"
function inhibition_bracket(S, sweep, m; points = inhibition_points(S, sweep))
    τ = tau(m)
    for i in 1:(length(points) - 1)
        a, b = inhibition_mean(S[(sweep, points[i])]),
            inhibition_mean(S[(sweep, points[i + 1])])
        a <= τ < b && return (points[i], points[i + 1])
    end
    return nothing
end
# M's rule on a bracket: the end nearest τ (ties, both Inf included, go to lo)
function threshold(S, sweep, m, br)
    br === nothing && return nothing
    τ = tau(m)
    lo, hi = br
    a, b = inhibition_mean(S[(sweep, lo)]), inhibition_mean(S[(sweep, hi)])
    return abs(b - τ) < abs(a - τ) ? hi : lo
end
# information: log-linear interpolation of τ between the bracket ends (NaN unless both
# finite)
function inhibition_interp(S, sweep, m, br)
    br === nothing && return NaN
    lo, hi = br
    a, b = inhibition_mean(S[(sweep, lo)]), inhibition_mean(S[(sweep, hi)])
    (isfinite(a) && isfinite(b) && b > a) || return NaN
    return (lo + (hi - lo) * (log(tau(m)) - log(a)) / (log(b) - log(a))) / 10_000
end
# M's rule on a plain sample table (G, and information on Potts' own table): values v,
# mean times t (Inf allowed); nearest to τ provided min t ≤ τ < max t; ties to the lower
# value
function mrule(v, t, τ)
    (minimum(t) <= τ < maximum(t)) || return nothing
    best = argmin(abs.(t .- τ))
    d = abs(t[best] - τ)
    return minimum(v[j] for j in eachindex(v) if abs(t[j] - τ) == d)
end
# group repeated parameter rows: sorted unique values, mean time per value
function group(v, t)
    u = sort(unique(v))
    return u, [mean(t[j] for j in eachindex(v) if v[j] == x) for x in u]
end
# ------------------------------------------------------------------------------------------
# The protocol (deterministic given the run times; the record tier replays it)
# ------------------------------------------------------------------------------------------

# `exec(jobs)` runs the jobs [(sweep, q, k)] and returns their times t (cycles; Inf =
# capped)
function inhibition_protocol(exec)
    S = Dict{Tuple{Symbol, Int}, Vector{Float64}}()
    log = Tuple{Symbol, Symbol, Int, Int}[]                         # (stage, sweep, q, k)
    function run!(jobs, stage)
        isempty(jobs) && return nothing
        t = exec(jobs)
        length(t) == length(jobs) ||
            throw(DimensionMismatch("inhibition_protocol: exec returned $(length(t)) \
                times"))
        for ((sw, q, k), x) in zip(jobs, t)
            v = get!(S, (sw, q), Float64[])
            length(v) == k - 1 ||
                throw(ArgumentError("inhibition_protocol: replicate $k of ($sw, $q) out \
                    of order"))
            push!(v, x)
            push!(log, (stage, sw, q, k))
        end
        return nothing
    end
    # 1. grid
    run!(
        [
            (sw, q, k) for sw in (:beta, :gamma) for q in GRID[sw]
                for k in 1:inhibition_n1(sw, q)
        ], :grid
    )
    # 2. brackets on the grid
    br = Dict{Tuple{Symbol, Float64}, Union{Nothing, Tuple{Int, Int}}}(
        tg =>
            inhibition_bracket(S, tg...)
            for tg in TARGETS
    )
    # 3. bisection
    for _ in 1:INHIBITION_K
        mids = Dict{Tuple{Symbol, Float64}, Int}()
        jobs = Tuple{Symbol, Int, Int}[]
        for tg in TARGETS
            b = br[tg]
            b === nothing && continue
            mid = (b[1] + b[2]) ÷ 2
            (mid == b[1] || mid == b[2]) && continue
            mids[tg] = mid
            j = (tg[1], mid, 1)
            (haskey(S, (tg[1], mid)) || j in jobs) || push!(jobs, j)
        end
        run!(jobs, :bisect)
        for tg in TARGETS
            haskey(mids, tg) || continue
            lo, hi = br[tg]
            mid = mids[tg]
            br[tg] = inhibition_mean(S[(tg[1], mid)]) <= tau(tg[2]) ? (mid, hi) : (lo, mid)
        end
    end
    # 4. final points: both ends to NFINAL replicates (a capped end stays as it is)
    jobs = Tuple{Symbol, Int, Int}[]
    for tg in TARGETS
        b = br[tg]
        b === nothing && continue
        for q in b
            x = S[(tg[1], q)]
            any(isinf, x) && continue
            for k in (length(x) + 1):NFINAL
                j = (tg[1], q, k)
                j in jobs || push!(jobs, j)
            end
        end
    end
    run!(jobs, :final)
    return (; S, log, br)
end
# every verdict: Dict(row => (value, ok)); `inh` maps a γ-sweep q to replicate 1's inhibited
# fraction (F7.1)
function inhibition_verdicts(P, inh)
    S, br = P.S, P.br
    out = Dict{String, Tuple{Any, Bool}}()
    t0 = inhibition_mean(S[(:beta, 0)])
    out["V1"] = (t0, inhibition_in(t0, V1_BAND))
    for (sw, m) in TARGETS
        th = threshold(S, sw, m, br[(sw, m)])
        x = th === nothing ? NaN : th / 10_000
        out[inhibition_row(sw, m)] = (
            x, th !== nothing && inhibition_in(x, inhibition_band(sw, m)),
        )
    end
    for (q, ref) in zip(V2B, INHIBITION_G.v2b)
        r = inhibition_mean(S[(:beta, q)]) / ref
        out["V2b." * string(q / 10_000)] = (r, inhibition_in(r, V2B_RATIO))
    end
    gpos = filter(>(0), inhibition_points(S, :gamma))
    for m in (1.1, 2.0)
        b = inhibition_bracket(S, :gamma, m; points = gpos)
        out["V3." * inhibition_mid(m)] = (b === nothing ? "—" : b ./ 10_000, b === nothing)
    end
    tj = inhibition_mean(S[(:gamma, 1)])
    out["V3b"] = (tj, inhibition_in(tj, V3B_BAND))
    qs = [threshold(S, :gamma, m, br[(:gamma, m)]) for m in (5.0, 10.0, 20.0)]
    f7 = any(isnothing, qs) ? NaN : minimum(inh[q] for q in qs)
    out["F7.1"] = (f7, f7 >= F7_MIN)
    # controls (each must fail)
    out["NC1"] = (t0, inhibition_in(t0, V3B_BAND))
    nc2 = (
        inhibition_mean(S[(:beta, 9500)]) / INHIBITION_G.v2b[2],
        inhibition_mean(S[(:beta, 10_000)]) / INHIBITION_G.v2b[4],
    )
    out["NC2"] = (nc2, all(r -> inhibition_in(r, V2B_RATIO), nc2))
    out["NC3"] = (tj, inhibition_in(tj, V1_BAND))
    return out
end
# information: interpolated thresholds and thresholds relative to Potts' own uninhibited
# time
function information(P)
    S, br = P.S, P.br
    t0 = inhibition_mean(S[(:beta, 0)])
    rel = Dict{String, Any}()
    for sw in (:beta, :gamma)
        qs = if sw === :beta
            inhibition_points(S, sw)
        else
            filter(>(0), inhibition_points(S, sw))
        end
        t = [inhibition_mean(S[(sw, q)]) for q in qs]
        for m in MULTS
            th = mrule(qs ./ 10_000, t, t0 * m)
            rel[(sw === :beta ? "V2." : "V3.") * inhibition_mid(m)] = if th === nothing
                "—"
            else
                th
            end
        end
    end
    interp = Dict(
        inhibition_row(tg...) => inhibition_interp(S, tg..., br[tg])
            for tg in TARGETS
    )
    return (; t0, relative = rel, interp)
end
# ------------------------------------------------------------------------------------------
# Jobs: one run per (sweep, q, k)
# ------------------------------------------------------------------------------------------
function problem(L; cells = CELLS, cap = CAP)
    sys = OpenVTReferenceMonolayer(; name = Symbol(:inhibition_m, L), lattice = (L, L))
    return PottsProblem(
        sys, openvt_reference_state(; lattice = (L, L)), (0, cap);
        capacity = ceil(Int, 1.3cells) + 100, seed = 1
    )
end
function inhibition_job(prob, sweep, q, k; cells = CELLS, cap = CAP)
    β, γ = params(sweep, q)
    seed = inhibition_seed(sweep, q, k)
    pr = remake(prob; seed, p = [:β => β, :γ => γ, :σ_X => 0.4], tspan = (0, cap))
    sol = solve(
        pr, INHIBITION_ALG;
        callback = Potts.CorePotts.CallbackSet(
            PottsModels.stop_at_cells(cells),
            PottsModels.edge_guard(GUARD; terminate = true)
        )
    )
    u = sol.u[end]
    N = count(>(0), Array(u.cell.volume))
    rc = Symbol(sol.retcode)
    mcs = Int(sol.t[end])
    capped = rc === :Success && N < cells && mcs == cap
    (rc === :Terminated && N >= cells) || capped ||
        throw(ErrorException("inhibition_job: ($sweep, $q, $k) ended $rc at MCS $mcs \
            with $N cells (edge guard?)"))
    return (;
        sweep, q, k, seed, β, γ, retcode = rc, mcs,
        N, capped, t = capped ? Inf : mcs / CYCLE, u,
    )
end
# the O5 rows of a final state (Fig 7)
function inhibition_o5(u; β, γ)
    o = PottsModels.openvt_snapshot(u)
    fr = PottsModels.openvt_frame(u; beta = β, gamma = γ)
    return (; x_pos = o.x, y_pos = o.y, radius_i = o.r, inhibited = Int.(fr.i .> 0))
end
# ------------------------------------------------------------------------------------------
# Record readers
# ------------------------------------------------------------------------------------------
function inhibition_tsv(path)
    l = split.(readlines(path), '\t')
    return [Dict(zip(l[1], r)) for r in l[2:end]]
end
ver_id(target) = first(split(target))
rtime(r) = r["capped"] == "true" ? Inf : parse(Int, r["mcs"]) / CYCLE
# ------------------------------------------------------------------------------------------
# always: the rules and the protocol on synthetic sweeps
# ------------------------------------------------------------------------------------------

# synthetic curves, log-linear through TST's Table 1 samples (spec §3.5) and its γ → 0⁺ jump
const SYN = (
    beta = (
        [0.0, 0.7037, 0.9361, 0.9867, 1.006, 1.02, 1.031],
        [13.7, 14.74, 27.07, 67.54, 133.52, 275.21, 598.11],
    ),
    gamma = ([1.0e-4, 0.12, 0.5, 0.75, 0.95], [61.37, 68.34, 132.14, 278.78, 566.08]),
)
function syn(sweep, q; shift = 0.0, scale = 1.0)
    sweep === :gamma && q == 0 && return 13.7 * scale
    x, y = SYN[sweep]
    v = q / 10_000 + shift
    v <= x[1] && return y[1] * scale
    v >= x[end] && return Inf
    i = findlast(<=(v), x)
    t = exp(log(y[i]) + (log(y[i + 1]) - log(y[i])) * (v - x[i]) / (x[i + 1] - x[i])) *
        scale
    return t > tau(20.0) ? Inf : t
end
syn_exec(; kw...) = jobs -> [syn(sw, q; kw...) for (sw, q, _) in jobs]
# ------------------------------------------------------------------------------------------
# G: recompute the consortium constants
# ------------------------------------------------------------------------------------------
function inhibition_csv(path)
    l = split.(filter(!isempty ∘ strip, readlines(path)), ',')
    v = [parse(Float64, r[1]) for r in l[2:end]]
    t = [parse(Float64, r[3]) for r in l[2:end]]
    # TST's "nan" rows were not run
    keep = isfinite.(t)
    return v[keep], t[keep]
end
function g_reference(G)
    R = joinpath(G, "results")
    th(v, t, ms) = [mrule(group(v, t)..., tau(m)) for m in ms]       # nearest point mean
    thr(v, t, ms) = [mrule(v, t, tau(m)) for m in ms]                     # nearest run
    tb = inhibition_csv(joinpath(R, "TST", "TST_time_to_10k_vs_beta.csv"))
    tg = inhibition_csv(joinpath(R, "TST", "TST_time_to_10k_vs_gamma.csv"))
    ab = inhibition_csv(joinpath(R, "Artistoo", "Monolayer", "time_to_10k_vs_beta.csv"))
    ag = inhibition_csv(joinpath(R, "Artistoo", "Monolayer", "time_to_10k_vs_gamma.csv"))
    at(v, t, x) = only(t[j] for j in eachindex(v) if v[j] == x)
    v2b = [
        at(ab..., 0.872727), at(tb..., 0.9),
        at(ab..., 0.933368), at(tb..., 0.95), at(tb..., 1.0),
    ]
    plateau = [
        mean(tb[2][j] for j in eachindex(tb[1]) if 0.25 <= tb[1][j] <= 0.5),
        mean(ab[2][j] for j in eachindex(ab[1]) if ab[1][j] <= 0.52),
    ]
    snap = joinpath(R, "TST", "final_snapshot_data")
    function snapshot(name)
        rows = [
            parse.(Float64, split(l, ','))
                for l in readlines(joinpath(snap, name))[2:end] if !isempty(strip(l))
        ]
        x, y = first.(rows), getindex.(rows, 2)
        cx, cy = mean(x), mean(y)
        return (;
            inh = mean(r[4] for r in rows),
            rmax = maximum(hypot.(x .- cx, y .- cy)) * sqrt(50 / π),
        )
    end
    f7 = [
        snapshot("TST_beta_0.0_gamma_$(g)_$(m)MCS.csv")
            for (g, m) in (("0.12", 52965), ("0.5", 103309), ("0.75", 216055))
    ]
    b102 = snapshot("TST_beta_1.02_gamma_0_213287MCS.csv")
    dash = [mrule(group(v, t)..., tau(m)) for (v, t) in (tg, ag) for m in (1.1, 2.0)]
    G3 = (5.0, 10.0, 20.0)
    return (;
        tst_beta = th(tb..., MULTS), art_beta = th(ab..., MULTS),
        beta_runs = (thr(tb..., MULTS), thr(ab..., MULTS)),
        tst_gamma_runs = thr(tg..., G3), tst_gamma_means = th(tg..., G3),
        art_gamma_runs = thr(ag..., G3), art_gamma_means = th(ag..., G3), v2b,
        v3b = [minimum(tg[2]), at(ag..., 0.0195)], plateau, tst_f7 = [s.inh for s in f7],
        rmax_px = (beta = b102.rmax, gamma = f7[3].rmax), dash,
    )
end
# ------------------------------------------------------------------------------------------
# FULL record (D-146): replay the protocol on the recorded times and recompute every row
# ------------------------------------------------------------------------------------------
function check(ver, devs; broken_ok)
    for row in ROWS
        haskey(ver, row) || (@test haskey(ver, row); continue)
        ok = ver[row][2]
        if ok
            @test ok
        elseif broken_ok
            # a failing row is a D-154 deviation: it must be in the record's table
            @test any(d -> ver_id(d["target"]) == row, devs)
            @test_broken ok
        else
            @test ok
        end
    end
    for c in CONTROLS
        @test !ver[c][2]                                     # the controls fail
    end
    return
end

# P6.15b: the D-146 offline record of the OpenVT F2 / Table S5 chain calibration (D-148).
#
# Re-runs exactly the FULL tier of the frozen test
# `lib/PottsModels/test/reproductions/15_openvt_calibration.jl` (spec 15 §4.2.3 P1–P12,
# §4.1 V6–V8) through the public API only, and writes the verdict table, the per-MCS time
# series, the per-run crossings, the spring–dashpot reference, the run metadata and the
# provenance into this directory. The frozen test is not edited and not included; its
# constants, seeds, run lengths, observables and pass bands are restated below verbatim.
#
#     julia -t 4 --project=lib/PottsModels/test \
#         lib/PottsModels/reproductions/data/15/calibration-2026-10-05/run_calibration.jl
#
# The one difference from the test: every run also saves the 100-MCS burn-in (spec P6
# "plus the burn-in at negative t"), i.e. saveat = 0:100+tmax instead of 100:100+tmax.
# Saving does not touch the RNG stream; the runner asserts that the t ≥ 0 slice is what
# the test computes on (and the verdict numbers are the test's: see README.md).
using Potts, PottsModels
using Statistics: mean, std
using Dates, TOML, SHA

const started = now()
const DIR = @__DIR__
const ROOT = normpath(joinpath(DIR, "..", "..", "..", "..", "..", ".."))
const TEST = joinpath(ROOT, "lib", "PottsModels", "test", "reproductions", "15_openvt_calibration.jl")
const A = PottsModels.Analysis

# ---- constants of the frozen test (spec 15 §4.2.2, §4.1 V6–V8; D-148) -----------------------
const RATE = 18.2816647214633
const CD = 10
const BURNIN = 100
const LEVEL = 9.0
const REF_T = collect(0:0.1:5)
const LAMBDAS = (1, 2, 3, 5)
const T_S5 = Dict(1 => 290, 2 => 155, 3 => 110, 5 => 75)
const MSE_S5 = Dict(1 => 7.570e-4, 2 => 2.664e-3, 3 => 4.433e-3, 5 => 1.378e-2)
const T_TOL = 0.15
const MSE_FACTOR = 3
const V7_SPREAD = (0.5 => (7.83, 7.87), 2.0 => (9.78, 9.80))
const V7_MARGIN = 0.1
const V8_W21 = (1 => (15.90, 16.25), 5 => (19.20, 19.57), 10 => (19.90, 19.96))
const V8_INNER = (1 => (7.20, 7.51), 5 => (9.46, 9.71), 10 => (9.92, 9.96))
const V8_MARGIN = 0.15
const V8_PLATEAU = (0.15, 0.22)
const V8_PLATEAU_BAND = (0.1, 0.3)
const PLATEAU_RISE = 0.05
const N = 100
seed11(λ, i) = 1000λ + i
seed21(i) = 21_000 + i
const ALG = SequentialCPM(; proposal = Moore(1))
const ALG_STR = "SequentialCPM(; proposal = Moore(1))"

function interp(s, w, r)      # linear interpolation, as the test's p615b_interp
    s[1] <= r <= s[end] || throw(ArgumentError("interp: $r outside [$(s[1]), $(s[end])]"))
    j = searchsortedlast(s, r)
    j == length(s) && return float(w[j])
    return w[j] + (w[j + 1] - w[j]) * (r - s[j]) / (s[j + 1] - s[j])
end
within(x, (lo, hi), m) = lo - m <= x <= hi + m
rowmean(M) = vec(mean(M; dims = 2))
rowsd(M) = vec(std(M; dims = 2))

# The test's p615b_runs, saving from MCS 0: returns spec time t = −100:tmax and per-run w
# (and the 21-chain's inner w₁₁) as time × run matrices, plus the compressed cells' mean
# area at t = 0 and t = tmax.
function runs(n, λ, seeds; tmax)
    L = n == 11 ? 150 : 250
    sys = OpenVTChain(; name = Symbol(:p615b_rec, n), lattice = (L, 5), λ = Float64(λ))
    prob = PottsProblem(sys, openvt_chain(n), (0, BURNIN + tmax); seed = first(seeds))
    saves = 0:(BURNIN + tmax)
    W = fill(NaN, length(saves), length(seeds))
    In = fill(NaN, length(saves), length(seeds))
    area = fill(NaN, 2, length(seeds))
    comp = n == 11 ? (1:11) : (6:16)
    Threads.@threads for j in eachindex(seeds)
        sol = solve(remake(prob; seed = seeds[j]), ALG; saveat = saves,
            callback = openvt_release(BURNIN))
        @assert collect(sol.t) == collect(saves)
        for (k, u) in enumerate(sol.u)
            xs = A.chain_centroids(u.σ)
            W[k, j] = (maximum(xs) - minimum(xs)) / CD
            n == 21 && (In[k, j] = (xs[16] - xs[6]) / CD)
        end
        for (r, u) in ((1, sol.u[BURNIN + 1]), (2, sol.u[end]))
            area[r, j] = mean(count(==(c), u.σ) for c in comp)
        end
    end
    @assert !any(isnan, W)
    return (; t = collect((-BURNIN):tmax), W, In, area)
end
post(r) = r.t .>= 0      # the test's slice (saves from MCS 100 = spec t = 0)

# ---- the run --------------------------------------------------------------------------------
fmt(x; d = 3) = string(round(x; digits = d))
fmte(x) = (e = floor(Int, log10(abs(x))); string(round(x / 10.0^e; digits = 2), "e", e))
verdict(ok) = ok ? "PASS" : "FAIL"
rows = NamedTuple[]
addrow!(target, paper, ours, tol, ok; class = "FULL") =
    push!(rows, (; target, paper, ours, tol, class, result = verdict(ok)))

rw = [spring_dashpot_width(x; rate = RATE) for x in REF_T]
T = Dict{Int, Int}()
R11 = Dict{Int, Any}()
sim_s = @elapsed begin
    for λ in LAMBDAS
        @info "11-chain" λ
        seeds = [seed11(λ, i) for i in 1:N]
        r = runs(11, λ, seeds; tmax = 7 * T_S5[λ])
        R11[λ] = (; r..., seeds)
    end
end
for λ in LAMBDAS
    r = R11[λ]
    k = post(r)
    t, wbar = r.t[k], rowmean(r.W[k, :])
    tc = A.crossing_time(t, wbar, LEVEL)
    tc === nothing || (T[λ] = tc)
    addrow!("V6 T(λ = $λ), MCS", "Table S5: $(T_S5[λ])", tc === nothing ? "no crossing" :
            "$tc ($(fmt(tc / T_S5[λ]; d = 3)) × S5)", "±15 %: [$(fmt(0.85T_S5[λ]; d = 1)), $(fmt(1.15T_S5[λ]; d = 1))]",
        tc !== nothing && abs(tc / T_S5[λ] - 1) <= T_TOL)
    covered = tc !== nothing && 5tc <= last(t)
    addrow!("V7 run covers 5 T (λ = $λ)", "— (run validity)", "5T = $(tc === nothing ? "—" : 5tc), run to $(last(t))",
        "5T ≤ 7 T_S5", covered)
    if covered
        m = A.relaxation_mse(t, wbar, tc, REF_T, rw)
        addrow!("V7 MSE vs spring–dashpot (λ = $λ)", "Table S5: $(fmte(MSE_S5[λ]))",
            "$(fmte(m)) ($(fmt(m / MSE_S5[λ]; d = 2)) × S5)", "≤ 3 × S5 = $(fmte(MSE_FACTOR * MSE_S5[λ]))",
            m <= MSE_FACTOR * MSE_S5[λ])
        R11[λ] = (; R11[λ]..., mse = m)
        if λ == 2
            for (s, spread) in V7_SPREAD
                v = interp(t ./ tc, wbar, s)
                ref = spring_dashpot_width(s; rate = RATE)
                addrow!("V7 w₁₁($(s) T) (λ = 2), CD", "lattice spread $(spread[1])–$(spread[2]) (TST, Morpheus-J10, Artistoo); reference $(fmt(ref; d = 2))",
                    fmt(v; d = 3), "spread ± 0.1: [$(fmt(spread[1] - V7_MARGIN; d = 2)), $(fmt(spread[2] + V7_MARGIN; d = 2))]",
                    within(v, spread, V7_MARGIN))
            end
        end
    end
end
Tvec = [get(T, λ, -1) for λ in LAMBDAS]
addrow!("V6 T strictly decreasing in λ", "290 > 155 > 110 > 75", join(Tvec, " > "), "strict",
    length(T) == length(LAMBDAS) && all(diff(Tvec) .< 0))

haskey(T, 2) || error("no T(2): V8 cannot run")
T2 = T[2]
@info "21-chain" T2
sim_s += @elapsed (R21 = runs(21, 2, [seed21(i) for i in 1:N]; tmax = 10T2))
k21 = post(R21)
t21 = R21.t[k21]
wbar21, ibar21 = rowmean(R21.W[k21, :]), rowmean(R21.In[k21, :])
for (kT, spread) in V8_W21
    v = wbar21[kT * T2 + 1]
    addrow!("V8 w₂₁($(kT) T) (λ = 2, T = $T2), CD", "lattice spread $(spread[1])–$(spread[2]) (CC3D, Morpheus-J10, TST, Artistoo)",
        fmt(v; d = 3), "spread ± 0.15: [$(fmt(spread[1] - V8_MARGIN; d = 2)), $(fmt(spread[2] + V8_MARGIN; d = 2))]",
        within(v, spread, V8_MARGIN))
end
for (kT, spread) in V8_INNER
    v = ibar21[kT * T2 + 1]
    addrow!("V8 inner w₁₁($(kT) T) (λ = 2, T = $T2), CD", "lattice spread $(spread[1])–$(spread[2]) (CC3D, Morpheus-J10, TST, Artistoo)",
        fmt(v; d = 3), "spread ± 0.15: [$(fmt(spread[1] - V8_MARGIN; d = 2)), $(fmt(spread[2] + V8_MARGIN; d = 2))]",
        within(v, spread, V8_MARGIN))
end
pe = A.crossing_time(t21, wbar21, wbar21[1] + PLATEAU_RISE)
addrow!("V8 plateau end (w̄₂₁ ≥ w̄₂₁(0) + 0.05), T",
    "$(V8_PLATEAU[1])–$(V8_PLATEAU[2]) T (lattice spread)",
    pe === nothing ? "none" : "$(fmt(pe / T2; d = 3)) ($pe MCS; w̄₂₁(0) = $(fmt(wbar21[1]; d = 3)))",
    "[$(V8_PLATEAU_BAND[1]), $(V8_PLATEAU_BAND[2])] T", pe !== nothing && V8_PLATEAU_BAND[1] <= pe / T2 <= V8_PLATEAU_BAND[2])

# extras (reported, not pass/fail): per-run crossing spread (P8) and P12
for λ in LAMBDAS
    r = R11[λ]
    k = post(r)
    tr = [something(A.crossing_time(r.t[k], r.W[k, j], LEVEL), -1) for j in 1:N]
    ok = filter(>=(0), tr)
    push!(rows, (; target = "P8 per-run crossing (λ = $λ), MCS", paper = "— (Morpheus `Event`)",
        ours = "median $(round(Int, sort(ok)[cld(length(ok), 2)])), mean $(fmt(mean(ok); d = 1)) ± $(fmt(std(ok); d = 1)) (SD), $(length(ok))/$N cross",
        tol = "—", class = "reported", result = "info"))
end
push!(rows, (; target = "P12 cycle 5 × T(2), MCS", paper = "775 (α, M)", ours = string(5T2), tol = "—",
    class = "reported", result = "info"))

# ---- outputs ---------------------------------------------------------------------------------
clean(x) = replace(string(x), r"[\t\n]" => " ")
open(joinpath(DIR, "verdicts.tsv"), "w") do io
    println(io, join(("target", "paper", "ours", "tolerance", "class", "result"), '\t'))
    for r in rows
        println(io, join(clean.((r.target, r.paper, r.ours, r.tol, r.class, r.result)), '\t'))
    end
end
r6(x) = round(x; digits = 6)
open(joinpath(DIR, "timeseries_11chain.tsv"), "w") do io
    println(io, join(("lambda", "t_mcs", "t_over_T", "w11_mean", "w11_sd"), '\t'))
    for λ in LAMBDAS
        r = R11[λ]
        m, s = rowmean(r.W), rowsd(r.W)
        for (k, t) in enumerate(r.t)
            println(io, join((λ, t, r6(t / T[λ]), r6(m[k]), r6(s[k])), '\t'))
        end
    end
end
open(joinpath(DIR, "crossings.tsv"), "w") do io
    println(io, join(("lambda", "seed", "T_run", "area_compressed_t0", "area_compressed_end"), '\t'))
    for λ in LAMBDAS
        r = R11[λ]
        k = post(r)
        for j in 1:N
            tr = A.crossing_time(r.t[k], r.W[k, j], LEVEL)
            println(io, join((λ, r.seeds[j], tr === nothing ? "NA" : tr, r6(r.area[1, j]), r6(r.area[2, j])), '\t'))
        end
    end
end
open(joinpath(DIR, "timeseries_21chain.tsv"), "w") do io
    println(io, join(("t_mcs", "t_over_T", "w21_mean", "w21_sd", "inner_w11_mean", "inner_w11_sd"), '\t'))
    m, s, mi, si = rowmean(R21.W), rowsd(R21.W), rowmean(R21.In), rowsd(R21.In)
    for (k, t) in enumerate(R21.t)
        println(io, join((t, r6(t / T2), r6(m[k]), r6(s[k]), r6(mi[k]), r6(si[k])), '\t'))
    end
end
open(joinpath(DIR, "reference.tsv"), "w") do io
    println(io, "t_over_T\tw")
    for (t, w) in zip(REF_T, rw)
        println(io, round(t; digits = 1), '\t', round(w; digits = 10))
    end
end
open(joinpath(DIR, "meta.toml"), "w") do io
    TOML.print(io, Dict(
        "item" => "P6.15b", "decisions" => ["D-148", "D-146"],
        "algorithm" => ALG_STR, "threads" => Threads.nthreads(),
        "lambdas" => collect(LAMBDAS), "replicates" => N,
        "seeds_11chain" => "1000λ + i, i = 1:100", "seeds_21chain" => "21000 + i, i = 1:100",
        "lattice_11chain" => [150, 5], "lattice_21chain" => [250, 5], "periodic" => [true, true],
        "CD_px" => CD, "burnin_mcs" => BURNIN, "release" => "openvt_release(100): A_c := A at the end of MCS 100 (t = 0)",
        "run_length_11chain_mcs" => Dict(string(λ) => 7T_S5[λ] for λ in LAMBDAS),
        "run_length_21chain_mcs" => 10T2, "T_S5" => Dict(string(λ) => T_S5[λ] for λ in LAMBDAS),
        "T_ours" => Dict(string(λ) => T[λ] for λ in LAMBDAS),
        "saves" => "every MCS from MCS 0 (spec t = −100) to the end; the test saves from MCS 100 (t = 0)",
        "level_CD" => LEVEL, "spring_dashpot_rate" => RATE, "plateau_rise_CD" => PLATEAU_RISE,
        "parameters" => "OpenVTChain defaults: T = 20, A = 50, A_c = 25 (burn-in), J_cc = 20, J_cm = 10, Moore(1)"))
end
finished = now()
git(args...) = readchomp(Cmd(`git $args`; dir = ROOT))
open(joinpath(DIR, "provenance.toml"), "w") do io
    TOML.print(io, Dict(
        "commit" => git("rev-parse", "HEAD"), "commit_date" => git("log", "-1", "--format=%cs"),
        "dirty_tracked" => !isempty(git("status", "--porcelain", "--untracked-files=no")),
        "test" => "lib/PottsModels/test/reproductions/15_openvt_calibration.jl",
        "test_sha256" => bytes2hex(open(sha256, TEST)),
        "runner" => relpath(@__FILE__, ROOT), "runner_sha256" => bytes2hex(open(sha256, @__FILE__)),
        "env" => "julia -t $(Threads.nthreads()) --project=lib/PottsModels/test (no POTTS_FULL_REPRODUCTION needed; the runner is the FULL tier)",
        "julia" => string(VERSION), "threads" => Threads.nthreads(), "machine" => Sys.MACHINE,
        "cpu" => Sys.cpu_info()[1].model, "started" => string(started), "finished" => string(finished),
        "wall_s" => round(Dates.value(finished - started) / 1000; digits = 1),
        "simulation_s" => round(sim_s; digits = 1),
        "item" => "P6.15b", "decisions" => ["D-148", "D-146"]))
end
for r in rows
    println(rpad(r.result, 5), "  ", r.target, "  ", r.ours)
end
@info "done" T wall_s = Dates.value(finished - started) / 1000 sim_s

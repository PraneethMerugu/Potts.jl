# P6.15e: the D-146 offline record of OpenVT Fig 5 ("100 runs of 1000 cells", case (b)) and
# its negative control (spec 15 §4.0.1 case (b), §3.1 O2, §3.4, §4.1 V4).
#
# Runs exactly the protocol of the frozen test
# `lib/PottsModels/test/reproductions/15_openvt_f5.jl` through the public API, and writes the
# per-run summaries (`runs.tsv`), the pooled histograms by distance bin (`hist.tsv`), the
# verdict table, the run metadata and the provenance into this directory, and the O2 files
# (the consortium submission format) into `F5_O2_DIR` (default `./o2`, not committed). The
# frozen test is not included; its constants, seeds and rules are restated below verbatim,
# and the test recomputes every verdict from runs.tsv / hist.tsv with its own rules.
#
#     POTTS_AFFINITY="taskset -c 0-11,16-27" taskset -c 0-11,16-27 julia -t 12 \
#         --project=lib/PottsModels/test lib/PottsModels/reproductions/data/15/f5-2026-10-07/run_f5.jl
using Potts, PottsModels
using Potts: CorePotts
using Statistics: mean
using Dates, TOML, SHA

const started = now()
const DIR = @__DIR__
const ROOT = normpath(joinpath(DIR, "..", "..", "..", "..", "..", ".."))
const TEST = joinpath(ROOT, "lib", "PottsModels", "test", "reproductions", "15_openvt_f5.jl")
const O2DIR = get(ENV, "F5_O2_DIR", joinpath(pwd(), "o2"))

# ---- constants of the frozen test --------------------------------------------------------------
const PAPER = (f0 = "≈ 0.89", f_peak = "0.25–0.35", f_max = "≤ 0.56", a_peak = "0.85–0.90",
    a_range = "0.42–1.09", a_mean = "0.85–0.86", f_mean = "≈ 0.03")
const BAND = (f0 = (0.86, 0.92), f_peak = (0.22, 0.38), f_max = (-Inf, 0.61),
    a_peak = (0.82, 0.93), a_min = (0.32, Inf), a_max = (-Inf, 1.19), a_mean = (0.82, 0.89),
    f_mean = (0.02, 0.04))
const ROWS = (:f0, :f_peak, :f_max, :a_peak, :a_range, :a_mean, :f_mean)
const ROW_ID = (f0 = "V4.1", f_peak = "V4.2", f_max = "V4.3", a_peak = "V4.4", a_range = "V4.5",
    a_mean = "V4.6", f_mean = "V4.7")
const ROW_NAME = (f0 = "fraction of cells with f = 0", f_peak = "peak of nonzero f", f_max = "max f",
    a_peak = "peak of a", a_range = "range of a", a_mean = "mean a", f_mean = "mean f")
const NBINS = 200
const N = 100
const NCTL = 20
const CELLS = 1000
const L = 400
const GAMMA_CTL = 1e-4
seed_b(k) = 15_000 + k
seed_ctl(k) = 15_500 + k
const ALG = SequentialCPM(; proposal = Moore(1))
const ALG_STR = "SequentialCPM(; proposal = Moore(1))"
const NDIST = 5                                   # M Fig 5: 5 distance bins (C11)

bin(x) = floor(Int, 100x + 1e-9)
function hist(xs)
    h = zeros(Int, NBINS)
    for x in xs
        k = bin(x)
        0 <= k < NBINS || error("value $x outside [0, 2)")
        h[k + 1] += 1
    end
    return h
end
function peak(h; skip0 = false)
    g = copy(h)
    skip0 && (g[1] = 0)
    n = length(g)
    s = [sum(g[max(1, k - 2):min(n, k + 2)]) / (min(n, k + 2) - max(1, k - 2) + 1) for k in 1:n]
    return (argmax(s) - 0.5) / 100
end
inb(x, (lo, hi)) = lo <= x <= hi
function v4(f, a)
    v = (f0 = count(==(0), f) / length(f), f_peak = peak(hist(f); skip0 = true), f_max = maximum(f),
        a_peak = peak(hist(a)), a_min = minimum(a), a_max = maximum(a), a_mean = mean(a), f_mean = mean(f))
    ok = (f0 = inb(v.f0, BAND.f0), f_peak = inb(v.f_peak, BAND.f_peak), f_max = inb(v.f_max, BAND.f_max),
        a_peak = inb(v.a_peak, BAND.a_peak), a_range = inb(v.a_min, BAND.a_min) && inb(v.a_max, BAND.a_max),
        a_mean = inb(v.a_mean, BAND.a_mean), f_mean = inb(v.f_mean, BAND.f_mean))
    return (; v, ok, pass = all(ok))
end

# ---- the runs -------------------------------------------------------------------------------------
sys = OpenVTReferenceMonolayer(; name = :p615e_rec, lattice = (L, L))
prob = PottsProblem(sys, openvt_reference_state(; lattice = (L, L)), (0, 100_000); capacity = 1500, seed = 1)
function run1(seed, γ)
    t = @elapsed sol = solve(remake(prob; seed, p = [:γ => γ]), ALG;
        callback = CorePotts.CallbackSet(PottsModels.stop_at_cells(CELLS), PottsModels.edge_guard(5; terminate = true)))
    u = sol.u[end]
    rows = PottsModels.openvt_snapshot(u)
    σ = Array(u.σ)
    gap = minimum(min(I[1] - 1, I[2] - 1, L - I[1], L - I[2]) for I in findall(!=(0), σ))   # sites to the edge
    # diagnostics for the V4.3 / V4.5 extremes: every cell outside the consortium's ranges
    # (f > 0.56 or a < 0.42 or a > 1.09), with its volume, A_star, the number of its unlike
    # Moore pairs and of its 4-connected pieces
    live = findall(>(0), Array(u.cell.volume))
    vol, Ast = Array(u.cell.volume), Array(u.cell.A_star)
    flag = [i for i in eachindex(live) if rows.f[i] > 0.56 || rows.a[i] < 0.42 || rows.a[i] > 1.09]
    diag = [(; id = live[i], f = rows.f[i], a = rows.a[i], volume = vol[live[i]], A_star = Ast[live[i]],
                d = hypot(rows.x[i], rows.y[i]), pieces = pieces(σ, live[i])) for i in flag]
    return (; seed, γ, retcode = Symbol(sol.retcode), mcs = sol.t[end], rows, wall = t, gap, diag)
end
# 4-connected pieces of cell c's sites
function pieces(σ, c)
    seen = falses(size(σ))
    n = 0
    for I in CartesianIndices(σ)
        (σ[I] == c && !seen[I]) || continue
        n += 1
        stack = [I]
        seen[I] = true
        while !isempty(stack)
            J = pop!(stack)
            for d in (CartesianIndex(1, 0), CartesianIndex(-1, 0), CartesianIndex(0, 1), CartesianIndex(0, -1))
                K = J + d
                (checkbounds(Bool, σ, K) && !seen[K] && σ[K] == c) || continue
                seen[K] = true
                push!(stack, K)
            end
        end
    end
    return n
end
jobs = [[("b", k, seed_b(k), 0.0) for k in 1:N]; [("control", k, seed_ctl(k), GAMMA_CTL) for k in 1:NCTL]]
res = Vector{Any}(undef, length(jobs))
run1(seed_b(1), 0.0)                              # compile (its result is recomputed below)
sim_s = @elapsed Threads.@threads :dynamic for j in eachindex(jobs)
    c, k, s, γ = jobs[j]
    res[j] = (; case = c, k, run1(s, γ)...)
    @info "run" c k s res[j].mcs res[j].wall length(res[j].rows.f)
end

# ---- outputs ----------------------------------------------------------------------------------------
r6(x) = round(x; digits = 6)
fmt(x; d = 3) = string(round(x; digits = d))
cases = ("b", "control")
pool(c, q) = reduce(vcat, [getfield(r.rows, q) for r in res if r.case == c])
V = Dict(c => v4(pool(c, :f), pool(c, :a)) for c in cases)

open(joinpath(DIR, "runs.tsv"), "w") do io
    println(io, join(("case", "k", "seed", "gamma", "lattice", "retcode", "mcs", "cycles", "N", "n_f0", "sum_f",
        "sum_a", "f_max", "a_min", "a_max", "d_max_R", "edge_gap_px", "wall_s"), '\t'))
    for r in res
        f, a = r.rows.f, r.rows.a
        d = hypot.(r.rows.x, r.rows.y)
        # sums at full precision (the test pools them); extremes are exact cell values
        println(io, join((r.case, r.k, r.seed, r.γ, L, r.retcode, r.mcs, r6(r.mcs / 775), length(f), count(==(0), f),
            repr(sum(f)), repr(sum(a)), repr(maximum(f)), repr(minimum(a)), repr(maximum(a)), r6(maximum(d)), r.gap,
            round(r.wall; digits = 2)), '\t'))
    end
end
open(joinpath(DIR, "extremes.tsv"), "w") do io
    println(io, join(("case", "k", "seed", "cell", "f", "a", "volume", "A_star", "d_R", "pieces"), '\t'))
    for r in res, x in r.diag
        println(io, join((r.case, r.k, r.seed, x.id, r6(x.f), r6(x.a), x.volume, r6(x.A_star), r6(x.d), x.pieces), '\t'))
    end
end
# histograms per case, quantity and distance bin (M Fig 5: 5 equal bins from 0 to 1.05 max d,
# d from the initial cell's centre, pooled over the case's runs; spec C11, C12)
dedges = Dict{String, Vector{Float64}}()
open(joinpath(DIR, "hist.tsv"), "w") do io
    println(io, join(("case", "quantity", "dbin", "d_lo_R", "d_hi_R", "bin", "x_lo", "count"), '\t'))
    for c in cases
        d = hypot.(pool(c, :x), pool(c, :y))
        e = collect(range(0, 1.05maximum(d); length = NDIST + 1))
        dedges[c] = e
        db = [min(NDIST, searchsortedlast(e, x)) for x in d]
        for q in (:f, :a), j in 1:NDIST
            h = hist(pool(c, q)[db .== j])
            for k in eachindex(h)
                h[k] > 0 && println(io, join((c, q, j, r6(e[j]), r6(e[j + 1]), k - 1, (k - 1) / 100, h[k]), '\t'))
            end
        end
    end
end
open(joinpath(DIR, "verdicts.tsv"), "w") do io
    println(io, join(("target", "case", "paper", "ours", "band", "result"), '\t'))
    for c in cases, row in ROWS
        v, ok = V[c].v, V[c].ok[row]
        ours = row === :a_range ? "$(fmt(v.a_min)) – $(fmt(v.a_max))" : fmt(getfield(v, row); d = 4)
        band = row === :a_range ? "[$(BAND.a_min[1]), $(BAND.a_max[2])]" :
               row === :f_max ? "≤ $(BAND.f_max[2])" : "[$(getfield(BAND, row)[1]), $(getfield(BAND, row)[2])]"
        println(io, join(("$(ROW_ID[row]) $(ROW_NAME[row])", c, "V4: $(getfield(PAPER, row)) (TST_5T, Morpheus_5T pooled)",
            ours, band, ok ? "PASS" : "FAIL"), '\t'))
    end
    println(io, join(("V4 (all rows)", "b", "pass", V["b"].pass ? "pass" : "fail", "every row", V["b"].pass ? "PASS" : "FAIL"), '\t'))
    println(io, join(("V4 negative control fails (V4.4, V4.6)", "control", "fails (γ > 0 shifts the distributions)",
        V["control"].pass ? "passes" : "fails", "V4 fails, V4.4 and V4.6 fail",
        (!V["control"].pass && !V["control"].ok.a_mean && !V["control"].ok.a_peak) ? "PASS" : "FAIL"), '\t'))
end
# O2 files (spec §3.1): x,y,r,f,a per cell, comma-separated, lengths in R
for (c, head) in (("b", "Potts.jl_5T_MonolayerGrowth_1000_Data"), ("control", "Potts.jl_5T_MonolayerGrowth_1000_Data_gamma1e-4"))
    d = joinpath(O2DIR, head)
    mkpath(d)
    for r in res
        r.case == c || continue
        open(joinpath(d, "cell_data_no_inhibition_$(r.k).csv"), "w") do io
            println(io, "x,y,r,f,a")
            for i in eachindex(r.rows.f)
                println(io, join((r.rows.x[i], r.rows.y[i], r.rows.r[i], r.rows.f[i], r.rows.a[i]), ','))
            end
        end
    end
end
finished = now()
open(joinpath(DIR, "meta.toml"), "w") do io
    TOML.print(io, Dict(
        "item" => "P6.15e", "decisions" => ["D-146", "D-147", "D-154"], "algorithm" => ALG_STR,
        "model" => "OpenVTReferenceMonolayer (Table S1 defaults: A₀ = 50, λ = 2, T = 20, α = 50/775, μ_X = 2, σ_X = 0.4, J 20/10)",
        "initial" => "openvt_reference_state: one disc of radius √(A₀/π) at the lattice centre",
        "lattice" => [L, L], "boundary" => "closed", "edge_guard" => "edge_guard(5; terminate = true)",
        "stop" => "stop_at_cells(1000): end of the first MCS with ≥ 1000 live cells",
        "case_b" => Dict("gamma" => 0.0, "beta" => 0.0, "runs" => N, "seeds" => "15000 + k, k = 1:100"),
        "control" => Dict("gamma" => GAMMA_CTL, "beta" => 0.0, "runs" => NCTL, "seeds" => "15500 + k, k = 1:20"),
        "o2_columns" => "x,y,r,f,a (x, y, r in R = √(A₀/π) from the lattice centre)",
        "distance_bins" => Dict(c => dedges[c] for c in cases),
        "threads" => Threads.nthreads(), "cycle_mcs" => 775))
end
git(args...) = readchomp(Cmd(`git $args`; dir = ROOT))
manifest = joinpath(ROOT, "Manifest.toml")
open(joinpath(DIR, "provenance.toml"), "w") do io
    TOML.print(io, Dict(
        "commit" => git("rev-parse", "HEAD"), "commit_date" => git("log", "-1", "--format=%cs"),
        "dirty_tracked" => !isempty(git("status", "--porcelain", "--untracked-files=no")),
        "test" => "lib/PottsModels/test/reproductions/15_openvt_f5.jl", "test_sha256" => bytes2hex(open(sha256, TEST)),
        "runner" => relpath(@__FILE__, ROOT), "runner_sha256" => bytes2hex(open(sha256, @__FILE__)),
        "manifest_sha256" => isfile(manifest) ? bytes2hex(open(sha256, manifest)) : "missing",
        "julia" => string(VERSION), "threads" => Threads.nthreads(), "machine" => Sys.MACHINE,
        "hostname" => gethostname(), "cpu" => Sys.cpu_info()[1].model, "affinity" => get(ENV, "POTTS_AFFINITY", ""),
        "seeds" => "case (b): 15000 + k, k = 1:100; control (γ = 1e-4): 15500 + k, k = 1:20",
        "started" => string(started), "finished" => string(finished),
        "wall_s" => round(Dates.value(finished - started) / 1000; digits = 1), "simulation_s" => round(sim_s; digits = 1),
        "cpu_s_runs" => round(sum(r.wall for r in res); digits = 1),
        "item" => "P6.15e", "decisions" => ["D-146", "D-147"]))
end
for c in cases
    println(c, ": pass = ", V[c].pass, "  ", V[c].v)
end
@info "done" wall_s = Dates.value(finished - started) / 1000 sim_s

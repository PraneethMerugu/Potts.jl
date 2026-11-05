# Kinetic closeness harness (P6.0bl, docs/design/research/checkerboard-kinetics.md): runs one
# arm (an algorithm or a control) on one case over many seeds, and compares every observable
# with SequentialCPM as the ratio r = mean(arm) / mean(reference), with a 95% bootstrap interval
# over seeds and the pre-registered verdict (§4).
#
#     julia --project=benchmark -t 16 benchmark/kinetics.jl run <case> <arm> <seeds> <out>
#     julia --project=benchmark benchmark/kinetics.jl compare <out> <case> <arm> [<reference>]
#
# Cases (Graner–Glazier, 144²: four tiles of the 72² baseline, 256 cells, T = 10, Moore(1)):
#   sort  K1, the two kinds: heterotypic boundary length H(t) / H(0) at fixed checkpoints
#   foam  K2, every cell light (one kind, no driving): volume and perimeter statistics,
#         centroid diffusion and the volume autocorrelation time
# Arms:
#   seq    SequentialCPM, the reference
#   seq2   SequentialCPM on disjoint seeds: the positive control
#   clock  SequentialCPM with 0.3 N attempts per MCS (run 0.3 t, labelled t): the clock control
#   cb     stock CheckerboardCPM: the negative control
#   cb_…   a CheckerboardCPM variant (`arm_alg`)
include("models.jl")
using Printf, Random, Statistics

const NMCS = 1000                 # labelled MCS per run
const EVERY = 10                  # labelled MCS between snapshots
const BURN = 200                  # labelled MCS left out of the stationary observables
const CHECKPOINTS = (50, 100, 200, 500, 1000)
const LAGS = 2:10                 # snapshot lags of the MSD fit
const ARMS = Dict("seq" => 1, "seq2" => 2, "clock" => 3, "cb" => 4)

const KINETIC = vcat(["committed", "D", "tauV"], ["H$(t)" for t in CHECKPOINTS])
const STATIC = ["vol_mean", "vol_sd", "per_mean", "per_sd"]
const MARGIN = Dict(vcat([o => 0.05 for o in KINETIC], [o => 0.02 for o in STATIC]))
# sorting never reaches a steady state, so its volume and perimeter statistics follow the
# sorting progress: they are not static observables there (controls of 2026-11-03)
const CASE_OBS = Dict("sort" => vcat(["committed"], ["H$(t)" for t in CHECKPOINTS]),
    "foam" => vcat(["committed", "D", "tauV"], STATIC))

# checkerboard variants: `cb` plus `_`-separated options, e.g. `cb_r2_rep_s3` (retries = 2, `sh`: cells = :shared,
# colors = :replacement, stride = 3)
function arm_alg(arm)
    arm in ("seq", "seq2", "clock") && return SequentialCPM(; proposal = Moore(1))
    tok = split(arm, '_')
    first(tok) == "cb" || throw(ArgumentError("unknown arm $arm"))
    kw = Dict{Symbol, Any}()
    for t in tok[2:end]
        t == "rep" ? (kw[:colors] = :replacement) : t == "sh" ? (kw[:cells] = :shared) : t == "blk" ? (kw[:scheme] = :blocks) :
        startswith(t, "b") ? (kw[:block] = parse(Int, t[2:end])) : startswith(t, "w") ? (kw[:switches] = parse(Int, t[2:end])) :
        startswith(t, "r") ? (kw[:retries] = parse(Int, t[2:end])) :
        startswith(t, "s") ? (kw[:stride] = parse(Int, t[2:end])) :
        throw(ArgumentError("unknown option $t in arm $arm"))
    end
    return CheckerboardCPM(; proposal = Moore(1), kw...)
end
arm_clock(arm) = arm == "clock" ? 0.3 : 1.0
# variants draw seeds disjoint from the controls' and from each other's
arm_seed(arm, i) = 1_000_000 * get(ARMS, arm, 100 + Int(hash(arm) % 1000)) + i

function case_state(case)
    σ, kinds = graner_state(2)
    case == "sort" && return σ, kinds
    case == "foam" && return σ, fill!(similar(kinds), Int32(2))
    throw(ArgumentError("unknown case $case"))
end

# sites whose owner differs from `prev`
function nchanged(σ, prev)
    n = 0
    @inbounds for i in eachindex(σ, prev)
        n += σ[i] != prev[i]
    end
    return n
end

# per-cell perimeter (von Neumann edges to another owner), heterotypic edge count, and the
# circular-mean centroid of every cell on the periodic lattice
function snapshot(σ, kinds, ncell)
    L1, L2 = size(σ)
    per = zeros(Int, ncell)
    het = 0
    cs = zeros(ncell, 4)                       # Σ cos, Σ sin along each axis
    @inbounds for j in 1:L2, i in 1:L1
        a = σ[i, j]
        for (ii, jj) in ((mod1(i + 1, L1), j), (i, mod1(j + 1, L2)))
            b = σ[ii, jj]
            a == b && continue
            a > 0 && (per[a] += 1)
            b > 0 && (per[b] += 1)
            a > 0 && b > 0 && kinds[a] != kinds[b] && (het += 1)
        end
        if a > 0
            θ1, θ2 = 2π * i / L1, 2π * j / L2
            cs[a, 1] += cos(θ1); cs[a, 2] += sin(θ1)
            cs[a, 3] += cos(θ2); cs[a, 4] += sin(θ2)
        end
    end
    cen = [mod(atan(cs[c, 2], cs[c, 1]), 2π) * L1 / 2π for c in 1:ncell],
          [mod(atan(cs[c, 4], cs[c, 3]), 2π) * L2 / 2π for c in 1:ncell]
    return per, het, cen
end

minimage(d, L) = d - L * round(d / L)

function run_one(case, arm, seed)
    σ0, kinds = case_state(case)
    f = arm_clock(arm)
    every, nmcs = round(Int, EVERY * f), round(Int, NMCS * f)
    lat = Lattice(size(σ0))
    prob = PottsProblem(GRANER, initial_state(σ0, kinds), lat, (0, nmcs), graner_params();
        contact = Moore(1), seed)
    integ = init(prob, arm_alg(arm); save_start = false, save_end = false)
    st = integ.state
    ncell = length(kinds)
    L1, L2 = size(σ0)
    prev = copy(st.σ)
    _, het0, cen = snapshot(st.σ, kinds, ncell)
    pos = (copy(cen[1]), copy(cen[2]))         # unwrapped centroids
    vols, pers, xs, ys, hets = Vector{Int32}[], Vector{Int}[], Vector{Float64}[], Vector{Float64}[], Int[]
    changed, counted = 0, 0
    wall = @elapsed for k in 1:nmcs
        copyto!(prev, st.σ)
        step!(integ)
        if k > BURN * f
            changed += nchanged(st.σ, prev)
            counted += 1
        end
        if k % every == 0
            per, het, c = snapshot(st.σ, kinds, ncell)
            for a in 1:2
                pos[a] .+= minimage.(c[a] .- cen[a], a == 1 ? L1 : L2)
                cen[a] .= c[a]
            end
            push!(vols, copy(st.cell.volume)); push!(pers, per); push!(hets, het)
            push!(xs, copy(pos[1])); push!(ys, copy(pos[2]))
        end
    end
    obs = Dict{String, Float64}("committed" => f * changed / counted, "wall" => wall / NMCS)
    for t in CHECKPOINTS
        obs["H$(t)"] = hets[t ÷ EVERY] / het0
    end
    keep = (BURN ÷ EVERY + 1):length(vols)
    alive = [c for c in 1:ncell if all(v -> v[c] > 0, vols)]
    v = [Float64(vols[s][c]) for s in keep for c in alive]
    p = [Float64(pers[s][c]) for s in keep for c in alive]
    obs["vol_mean"], obs["vol_sd"] = mean(v), std(v)
    obs["per_mean"], obs["per_sd"] = mean(p), std(p)
    # MSD over time origins in the stationary part, a linear fit over LAGS (labelled MCS)
    msd = map(LAGS) do l
        mean((xs[s + l][c] - xs[s][c])^2 + (ys[s + l][c] - ys[s][c])^2
             for s in first(keep):(last(keep) - l) for c in alive)
    end
    τ = EVERY .* LAGS
    obs["D"] = cov(τ, msd) / var(τ) / 4
    # integrated autocorrelation time of each cell's volume, cut at the first non-positive lag
    obs["tauV"] = mean(alive) do c
        x = [Float64(vols[s][c]) for s in keep]
        x .-= mean(x)
        v0 = sum(abs2, x)
        v0 == 0 && return 0.0
        acc = 0.5
        for l in 1:(length(x) ÷ 2)
            ρ = sum(x[i] * x[i + l] for i in 1:(length(x) - l)) / v0
            ρ <= 0 && break
            acc += ρ
        end
        2EVERY * acc
    end
    return obs
end

outfile(out, case, arm) = joinpath(out, "$(case)_$(arm).tsv")

function run_arm(case, arm, nseeds, out)
    mkpath(out)
    run_one(case, arm, arm_seed(arm, 0))      # compile outside the timed runs
    res = Vector{Dict{String, Float64}}(undef, nseeds)
    Threads.@threads :dynamic for i in 1:nseeds
        res[i] = run_one(case, arm, arm_seed(arm, i))
    end
    cols = sort(collect(keys(res[1])))
    open(outfile(out, case, arm), "w") do io
        println(io, join(vcat("seed", cols), '\t'))
        for i in 1:nseeds
            println(io, join(vcat(arm_seed(arm, i), [res[i][c] for c in cols]), '\t'))
        end
    end
    return res
end

function load(out, case, arm)
    d, h = readdlm(outfile(out, case, arm), '\t'; header = true)
    return Dict(String(h[j]) => Float64.(d[:, j]) for j in 2:size(d, 2))
end

function ratio_ci(a, b; n = 4000, rng = Xoshiro(20261103))
    r = mean(a) / mean(b)
    boot = [mean(rand(rng, a, length(a))) / mean(rand(rng, b, length(b))) for _ in 1:n]
    return r, quantile(boot, 0.025), quantile(boot, 0.975)
end

function compare(out, case, arm, ref = "seq")
    A, B = load(out, case, arm), load(out, case, ref)
    println("$case: $arm against $ref ($(length(A["wall"])) and $(length(B["wall"])) seeds)")
    println(rpad("observable", 12), rpad("arm", 12), rpad("ref", 12), rpad("r", 8),
        rpad("95% interval", 20), rpad("margin", 8), "verdict")
    rows = []
    for o in CASE_OBS[case]
        r, lo, hi = ratio_ci(A[o], B[o])
        m = MARGIN[o]
        verdict = (lo >= 1 - m && hi <= 1 + m) ? "PASS" : (hi < 1 - m || lo > 1 + m) ? "FAIL" :
                  "UNDECIDED"
        resolved = (hi - lo) / 2 <= m / 2
        resolved || (verdict *= " (unresolved)")
        @printf("%-12s%-12.4g%-12.4g%-8.3f[%.3f, %.3f]      %-8.2f%s\n", o, mean(A[o]), mean(B[o]),
            r, lo, hi, m, verdict)
        push!(rows, (o, mean(A[o]), mean(B[o]), r, lo, hi, m, verdict))
    end
    @printf("wall per labelled MCS: arm %.3g s, ref %.3g s (one thread per run)\n",
        mean(A["wall"]), mean(B["wall"]))
    open(joinpath(out, "compare_$(case)_$(arm)_vs_$(ref).tsv"), "w") do io
        println(io, join(("observable", "arm", "ref", "r", "lo", "hi", "margin", "verdict"), '\t'))
        foreach(r -> println(io, join(r, '\t')), rows)
    end
    return rows
end

if abspath(PROGRAM_FILE) == @__FILE__
    cmd = ARGS[1]
    if cmd == "run"
        run_arm(ARGS[2], ARGS[3], parse(Int, ARGS[4]), ARGS[5])
    elseif cmd == "compare"
        compare(ARGS[2:end]...)
    else
        throw(ArgumentError("usage: run <case> <arm> <seeds> <out> | compare <out> <case> <arm> [<ref>]"))
    end
end

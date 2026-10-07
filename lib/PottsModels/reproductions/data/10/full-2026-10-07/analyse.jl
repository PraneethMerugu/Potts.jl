# Verdicts of the full sweep (sweep.tsv): V-A6 phenotype fractions with the area-equality
# classifier, the V-A7 full-sweep |r|, and reported cross-checks (P6.2d, D-156).
# Usage: DATA=<dir with sweep.tsv> [POTTS_REFERENCES=<docs/references>] julia --project=docs analyse.jl
# Reference values are from the authors' dataset A (`Data/invasion_metrics.csv`, 13,305 runs),
# recomputed for spec 10 §5.3.1 and §5.3.5; pass rules R2 and R3 are spec 10 §5.3.3.
using Statistics, CairoMakie
const DATA = ENV["DATA"]
lines = collect(eachline(joinpath(DATA, "sweep.tsv")))
head = split(lines[1], '\t')
col(name) = findfirst(==(name), head)
recs = [split(l, '\t') for l in lines[2:end]]
num(r, c) = parse(Float64, r[col(c)])
@assert length(recs) == 13310 "the sweep is incomplete: $(length(recs)) of 13310 runs"
@assert all(r -> r[col("retcode")] == "Success", recs)
J, Λ, P = num.(recs, "J_LF"), num.(recs, "lambda"), num.(recs, "PP")
met = Dict(m => num.(recs, string(m)) for m in (:invasive, :infiltrative, :singles, :fingers, :detached, :clusters))
phen = Symbol.(getindex.(recs, col("phenotype")))
rep = Int.(num.(recs, "replicate"))

r3(pA, NA, pB, NB) = abs(pB - pA) <= max(3 * sqrt(pA * (1 - pA) / NA + pB * (1 - pB) / NB), 0.05)
r2(μA, seA, μB, seB, f) = abs(μB - μA) <= max(3 * sqrt(seA^2 + seB^2), 0.10 * abs(μA), f)
fmt(x) = string(round(x; digits = abs(x) >= 100 ? 0 : abs(x) >= 1 ? 2 : 3))
rows = []
add!(target, paper, ours, tol, class, ok) = push!(rows, (; target, paper, ours, tol, class,
    result = ok === nothing ? "reported" : class == "FULL" ? (ok ? "PASS" : "FAIL") : (ok ? "info: in band" : "info: out of band")))

## V-A6: dataset A classified (13,263 of 13,305; 42 unclassified), Fig. 5B per-replicate mean ± SD
const PHEN = (:none, :single, :bulk, :multimodal)
const PHEN_TEXT = (none = "No invasion", single = "Single-cell", bulk = "Bulk", multimodal = "Multimodal")
const A_COUNT = (none = 2950, single = 143, bulk = 2989, multimodal = 7181)
const A_FIG5B = (none = (22.24, 0.66), single = (1.08, 0.21), bulk = (22.54, 0.67), multimodal = (54.14, 0.48))
const PAPER = (none = 22, single = 1, bulk = 23, multimodal = 54)
const NA6 = sum(values(A_COUNT))
classified = phen .!= :unclassified
NB6 = count(classified)
perrep(ph) = [count(k -> rep[k] == i && phen[k] == ph, eachindex(phen)) / count(k -> rep[k] == i && classified[k], eachindex(phen))
              for i in 1:10]
fracs = Dict{Symbol, Float64}()
for ph in PHEN
    pA = A_COUNT[ph] / NA6
    pB = count(==(ph), phen) / NB6
    fracs[ph] = pB
    v = 100 .* perrep(ph)
    add!("V-A6 $(PHEN_TEXT[ph]) fraction", "$(PAPER[ph]) % (p.13); A $(fmt(100pA)) % (N = $NA6), Fig. 5B $(A_FIG5B[ph][1]) ± $(A_FIG5B[ph][2]) %",
        "$(fmt(100pB)) % (N = $NB6); per replicate $(fmt(mean(v))) ± $(fmt(std(v))) %", "R3", "FULL", r3(pA, NA6, pB, NB6))
end
pu = count(!, classified) / length(phen)
add!("V-A6 unclassified (dropped before the fractions)", "42 / 13,305 = 0.32 % (A)", "$(count(!, classified)) / $(length(phen)) = $(fmt(100pu)) %",
    "R3", "info", r3(42 / 13305, 13305, pu, length(phen)))

## V-A7 (full-sweep form): |r(PP, metric)| < 0.05 for every metric; paper |r| < 0.03
const A_R_PP = (invasive = -0.025, infiltrative = -0.026, singles = -0.004, fingers = 0.001, detached = -0.007, clusters = -0.002)
for m in keys(A_R_PP)
    r = cor(P, met[m])
    add!("V-A7 r(PP, $m), full sweep", "|r| < 0.03 (p.10–11); A $(A_R_PP[m])", fmt(r), "|r| < 0.05", "FULL", abs(r) < 0.05)
end
## reported: the paper's other correlations (p.10–11), A in parentheses
for (x, xs, m, paper, a) in ((Λ, "λ", :invasive, 0.70, 0.700), (Λ, "λ", :fingers, 0.80, 0.795), (J, "J_LF", :singles, 0.67, 0.672),
    (J, "J_LF", :infiltrative, 0.57, 0.567))
    r = cor(x, met[m])
    add!("r($xs, $m), full sweep", "$paper (p.10–11; A $a)", fmt(r), "± 0.05", "info", abs(r - a) <= 0.05)
end

## reported: the paper's full-sweep marginals (p.10–11), now runnable; mean ± SE
se(v) = std(v) / sqrt(length(v))
sets = (J_mid = -1 .<= J .<= 2, J_strong = J .<= -2, J_weak = J .> 2, λ_high = Λ .>= 20, λ_low = Λ .< 10, λ_24 = Λ .>= 24)
for (m, s, paper, f) in ((:fingers, :J_mid, 7.11, 1.0), (:fingers, :λ_high, 9.74, 1.0), (:fingers, :J_strong, 4.03, 1.0),
    (:fingers, :J_weak, 6.11, 1.0), (:singles, :J_weak, 175.79, 1.0), (:singles, :J_strong, 1.53, 1.0), (:singles, :J_mid, 53.06, 1.0),
    (:clusters, :J_mid, 1.69, 1.0), (:clusters, :J_weak, 1.78, 1.0))
    v = met[m][sets[s]]
    add!("full-sweep $m, $s", "$paper (p.10–11)", "$(fmt(mean(v))) ± $(fmt(se(v))) (N = $(length(v)))", "max(± 10 %, 1)", "info",
        abs(mean(v) - paper) <= max(0.10 * paper, f))
end
inc = mean(met[:clusters] .>= 1)
add!("full-sweep cluster incidence", "28.3 % (3763 / 13,310, p.10); A 28.6 %", "$(fmt(100inc)) %", "R3 against A", "info",
    r3(0.286, 13305, inc, length(phen)))

## the sweep's own PP = 0.5 slice against the page's V-A3–V-A5 references (an independent replicate)
slice = P .== 0.5
REF_SLICE = [(:fingers, :J_mid, 7.20, 0.24), (:fingers, :λ_high, 9.78, 0.15), (:fingers, :J_strong, 3.99, 0.22),
    (:fingers, :J_weak, 6.08, 0.20), (:singles, :J_weak, 175.94, 6.60), (:singles, :J_strong, 1.46, 0.22),
    (:singles, :J_mid, 52.94, 3.37), (:clusters, :J_mid, 1.63, 0.15), (:clusters, :J_weak, 1.77, 0.16),
    (:invasive, :J_strong, 5381, 206), (:invasive, :J_mid, 10301, 335), (:invasive, :J_weak, 6658, 192),
    (:invasive, :λ_high, 12173, 275), (:invasive, :λ_low, 2866, 53), (:infiltrative, :λ_high, 30351, 860),
    (:infiltrative, :λ_low, 3545, 133)]
for (m, s, μA, seA) in REF_SLICE
    v = met[m][slice .& sets[s]]
    add!("sweep slice $m, $s", "$μA ± $seA (A slice, SE)", "$(fmt(mean(v))) ± $(fmt(se(v))) (N = $(length(v)))", "R2", "info",
        r2(μA, seA, mean(v), se(v), m in (:invasive, :infiltrative) ? 0.0 : 1.0))
end

open(joinpath(DATA, "verdicts_sweep.tsv"), "w") do io
    println(io, join(("target", "paper", "ours", "tolerance", "class", "result"), '\t'))
    for r in rows
        println(io, join((r.target, r.paper, r.ours, r.tol, r.class, r.result), '\t'))
    end
end
foreach(r -> println(rpad(r.result, 18), r.target, " | ", r.ours, " | ", r.paper), rows)

## figure: Fig. 5B side by side, and the dominant phenotype over (J_LF, λ) at PP = 0.5
code = Dict(:none => 1, :single => 2, :bulk => 3, :multimodal => 4, :unclassified => 5)
colors = [:teal, :royalblue, :darkorange, :firebrick, :gray80]
function dominant(Js, Ls, ph)
    [let k = [code[ph[q]] for q in eachindex(ph) if Js[q] == j && Ls[q] == l]
        isempty(k) ? 5 : argmax(c -> count(==(c), k), 1:5)
    end for j in -5:5, l in 0:3:30]
end
fig = Figure(size = (1100, 380))
ax = Axis(fig[1, 1]; title = "Phenotype fractions (Fig. 5B)", ylabel = "%", xticks = (1:4, collect(values(PHEN_TEXT))))
barplot!(ax, (1:4) .- 0.2, [A_FIG5B[ph][1] for ph in PHEN]; width = 0.38, color = :gray60, label = "authors (A)")
barplot!(ax, (1:4) .+ 0.2, [100fracs[ph] for ph in PHEN]; width = 0.38, color = :red3, label = "ours")
axislegend(ax; position = :lt, framevisible = false)
mapB = dominant(J[slice], Λ[slice], phen[slice])
heat(pos, title, d) = (a = Axis(fig[1, pos]; title, xlabel = "J_LF", ylabel = "λ");
    heatmap!(a, -5:5, 0:3:30, d; colormap = colors, colorrange = (0.5, 5.5)); a)
refs = get(ENV, "POTTS_REFERENCES", "")
Afile = joinpath(refs, "codebases", "10_Akeeb2026_Leader_Follower_Invasion_Model", "Data", "phenotype_classification.csv")
if isfile(Afile)
    lab = Dict("No invasion" => :none, "Single cell invasion" => :single, "Bulk invasion" => :bulk, "Multimodal invasion" => :multimodal)
    A = [split(l, ',') for l in Iterators.drop(eachline(Afile), 1)]
    A = filter(r -> parse(Float64, r[3]) == 0.5, A)
    heat(2, "authors, PP = 0.5 (dominant)", dominant(parse.(Float64, getindex.(A, 1)), parse.(Float64, getindex.(A, 2)),
        [lab[r[10]] for r in A]))
end
heat(3, "ours, PP = 0.5 (dominant)", mapB)
Legend(fig[1, 4], [PolyElement(; color = c) for c in colors], ["No invasion", "Single-cell", "Bulk", "Multimodal", "unclassified"];
    framevisible = false)
save(joinpath(DATA, "10_akeeb_phenotypes.png"), fig)

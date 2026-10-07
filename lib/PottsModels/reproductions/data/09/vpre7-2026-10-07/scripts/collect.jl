# P6.1h: collect the V-PRE7 replicate files into the committed record and compute the verdicts.
#
#     julia scripts/collect.jl <runs dir> <record dir>
#
# Writes `timeseries.tsv` (every replicate and save, the replicate files concatenated in T,
# start-seed and time order), `summary.tsv` (per T and save: replicates, mean and SE of the
# five fractions, mean share of cells gone, isolation guard) and `verdicts.tsv` (the four
# V-PRE7 criteria of spec 09 §9.1). Ensemble statistic (spec §9.0): the mean over replicates
# of the per-replicate value. A save whose annealed copy has no mismatched bond (every cell
# gone) has F = 0 (no boundary of any kind). The page recomputes the same verdicts from
# `timeseries.tsv` and its test checks that they equal `verdicts.tsv`.
using Statistics: mean, std

runs, rec = ARGS[1], ARGS[2]
files = sort(filter(f -> endswith(f, ".tsv"), readdir(runs; join = true)))
header = split(readline(first(files)), '\t')
rows = Vector{Vector{SubString{String}}}()
for f in files
    l = split.(readlines(f), '\t')
    @assert l[1] == header f
    append!(rows, l[2:end])
end
col(name) = findfirst(==(name), header)
num(r, name) = parse(Float64, r[col(name)])
sort!(rows; by = r -> (num(r, "T"), num(r, "start_seed"), num(r, "paper_mcs")))
open(joinpath(rec, "timeseries.tsv"), "w") do io
    println(io, join(header, '\t'))
    foreach(r -> println(io, join(r, '\t')), rows)
end

frac(r, key) = num(r, "mismatched_bonds") == 0 ? 0.0 : num(r, "F_" * key)
gone(r) = 1 - (num(r, "alive_dark") + num(r, "alive_light")) / (num(r, "cells_dark") + num(r, "cells_light"))
Ts = sort(unique(num.(rows, "T")))
saves = sort(unique(num.(rows, "paper_mcs")))
at(T, t) = filter(r -> num(r, "T") == T && num(r, "paper_mcs") == t, rows)
m(T, t, key) = mean(frac(r, key) for r in at(T, t))
se(v) = length(v) > 1 ? std(v) / sqrt(length(v)) : NaN
r4(x) = round(x; digits = 4)

open(joinpath(rec, "summary.tsv"), "w") do io
    keys5 = ("dl", "dd", "ll", "dM", "lM")
    println(io, join(["T", "paper_mcs", "replicates", ("F_$(k)_mean\tF_$(k)_se" for k in keys5)...,
        "gone_mean", "gone_se", "isolated_all"], '\t'))
    for T in Ts, t in saves
        rs = at(T, t)
        isempty(rs) && continue
        cells = [(r4(mean(v)), r4(se(v))) for v in ([frac(r, k) for r in rs] for k in keys5)]
        g = gone.(rs)
        println(io, join([T, Int(t), length(rs), (string(a, '\t', b) for (a, b) in cells)...,
            r4(mean(g)), r4(se(g)), all(r -> r[col("isolated")] == "true", rs)], '\t'))
    end
end

# the four criteria (spec 09 §9.1 V-PRE7, verbatim)
d0 = abs(m(0.0, 2000, "dl") - m(0.0, 100, "dl"))
o2, o5, o10 = m(2.0, 1000, "dl"), m(5.0, 1000, "dl"), m(10.0, 1000, "dl")
late = filter(t -> 1000 <= t <= 10_000, saves)
f40 = [m(40.0, t, "dl") for t in late]
g80 = mean(gone.(at(80.0, 500)))
n_per_T = Dict(T => length(at(T, 1000)) for T in Ts)
pf(ok) = ok ? "PASS" : "FAIL"
open(joinpath(rec, "verdicts.tsv"), "w") do io
    println(io, join(("criterion", "ours", "rule", "result"), '\t'))
    println(io, join(("T = 0 frozen", "|F_dl(2000) − F_dl(100)| = $(r4(d0))", "< 0.02", pf(d0 < 0.02)), '\t'))
    println(io, join(("order at 10³", "F_dl(T=2) $(r4(o2)), F_dl(T=5) $(r4(o5)), F_dl(T=10) $(r4(o10))",
        "F_dl(T=2) > F_dl(T=5) > F_dl(T=10)", pf(o2 > o5 > o10)), '\t'))
    println(io, join(("T = 40 plateau", "min F_dl over [10³, 10⁴] = $(r4(minimum(f40))) (at $(Int(late[argmin(f40)])))",
        "> 0.07 at every save in [10³, 10⁴]", pf(minimum(f40) > 0.07)), '\t'))
    println(io, join(("T = 80 disintegration", "share of cells gone at 500 = $(r4(g80))", "> 0.5", pf(g80 > 0.5)), '\t'))
end
@info "collected" length(files) n_per_T

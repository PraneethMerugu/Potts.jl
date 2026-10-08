# P6.3f: apply the FROZEN FULL rules of lib/PottsModels/test/reproductions/01_merks.jl
# (lines 302–394, D-153) to the per-replicate rows written by run_full.jl. Not a frozen file;
# every condition below is a transcription of a frozen `@test`, in the same order.
# Writes verdicts.tsv, replicates.tsv and points.tsv (means per sweep point, at N and N + 100).
#
# usage: julia --project=lib/PottsModels/test evaluate.jl <outdir>
using TOML, Statistics

const OUT = abspath(ARGS[1])
rows = [TOML.parsefile(joinpath(OUT, "rows", f)) for f in readdir(joinpath(OUT, "rows")) if endswith(f, ".toml")]
@assert length(rows) == 590 "only $(length(rows)) of 590 jobs are done"
pick(pred) = sort(filter(pred, rows); by = r -> r["seed"])
crossing(xs, ys, level) = begin
    for k in 1:(length(xs) - 1)
        a, b = ys[k] - level, ys[k + 1] - level
        a == 0 && return xs[k]
        a * b < 0 && return xs[k] + (xs[k + 1] - xs[k]) * a / (a - b)
    end
    nothing
end
verdicts = Any[]
add!(row, test, value, rule, ok) = push!(verdicts, (row, test, value, rule, ok ? "PASS" : "FAIL"))
points = Any[]
function pt!(row, label, rs, t)
    a, b = [r["C_$t"] for r in rs], [r["C_$(t + 100)"] for r in rs]
    push!(points, (row, label, length(rs), mean(a), std(a), mean(b), std(b)))
end

# V-E1
std_ = pick(r -> r["row"] == "V-E1" && r["arm"] == "standard")
rnd = pick(r -> r["row"] == "V-E1" && r["arm"] == "λ_L = 0")
@assert length(std_) == 10 && length(rnd) == 10
n12 = count(r -> r["network_1440"], std_)
add!("V-E1", "network at 1440 MCS", "$n12/10", ">= 8/10", n12 >= 8)
l12, l48 = mean(r -> r["lacunae_1440"], std_), mean(r -> r["lacunae_5760"], std_)
add!("V-E1", "mean lacunae 5760 < 1440", "$l48 vs $l12", "<", l48 < l12)
s48 = mean(r -> r["share_5760"], std_)
add!("V-E1", "mean share at 5760", s48, ">= 0.9", s48 >= 0.9)
s12, sr = mean(r -> r["share_1440"], std_), mean(r -> r["share_1440"], rnd)
add!("V-E1", "control λ_L = 0 share at 1440", "$sr vs standard $s12", "<= standard - 0.2", sr <= s12 - 0.2)
# V-E5
for L in (10.0, 20.0, 30.0, 40.0, 50.0)
    rs = pick(r -> r["row"] == "V-E5" && r["L"] == L)
    @assert length(rs) == 10
    nnet = count(r -> r["network_5760"], rs)
    add!("V-E5", "L = $L px at 5760: networks", "$nnet/10", L <= 20 ? "islands >= 8/10" : "network >= 8/10",
        L <= 20 ? (10 - nnet >= 8) : (nnet >= 8))
end
# V-E6
for J in (20.0, 5.0, 1.0)
    rs = pick(r -> r["row"] == "V-E6" && r["J_cc"] == J)
    @assert length(rs) == 10
    nnet = count(r -> r["network_5760"], rs)
    add!("V-E6", "J_cc = $J at 5760: networks", "$nnet/10", ">= 8/10", nnet >= 8)
    if J == 1.0
        lj = mean(r -> r["lacunae_5760"], rs)
        add!("V-E6", "J_cc = 1 mean lacunae vs V-E1 at 5760", "$lj vs $l48", "<=", lj <= l48)
    end
end
# V-E10
el = [r["anisotropy"] for r in pick(r -> r["row"] == "V-E10" && r["arm"] == "elongated")]
ro = [r["anisotropy"] for r in pick(r -> r["row"] == "V-E10" && r["arm"] == "round")]
@assert length(el) == 10 && length(ro) == 10
add!("V-E10", "mean anisotropy, elongated", mean(el), "> 1.2", mean(el) > 1.2)
add!("V-E10", "mean anisotropy, round", mean(ro), "< 1.2 and < elongated", mean(ro) < 1.2 && mean(ro) < mean(el))
# V-C2, V-C3
ratios = collect(0.0:0.1:1.0)
C3 = [pick(r -> r["row"] == "V-C3" && r["ratio"] == x) for x in ratios]
@assert all(==(10) ∘ length, C3)
foreach(((x, rs),) -> pt!("V-C3", "ratio $x", rs, 10_000), zip(ratios, C3))
m = [mean(r -> r["C_10000"], rs) for rs in C3]
add!("V-C2", "mean C ratio 0 (CI) vs ratio 1 (no CI) at 10^4", "$(m[1]) vs $(m[end])", "< no CI - 0.3", m[1] < m[end] - 0.3)
low, high = mean(m[1:5]), mean(m[8:11])
add!("V-C3", "low plateau (ratio 0-0.4)", low, "0.35 ± 0.07", abs(low - 0.35) <= 0.07)
add!("V-C3", "high plateau (ratio 0.7-1)", high, "0.9 ± 0.07", abs(high - 0.9) <= 0.07)
add!("V-C3", "plateaus jointly (frozen @test)", "$low, $high", "both", abs(low - 0.35) <= 0.07 && abs(high - 0.9) <= 0.07)
mid = crossing(ratios, m, (low + high) / 2)
add!("V-C3", "midpoint", something(mid, "none"), "in [0.45, 0.65]", mid !== nothing && 0.45 <= mid <= 0.65)
# V-C4
pts4 = [(0.0, true), (20.0, true), (40.0, true), (60.0, true), (80.0, true),
    (0.0, false), (5.0, false), (10.0, false), (15.0, false), (20.0, false), (40.0, false)]
m4 = Dict{Any, Float64}()
for (J, ci) in pts4
    rs = pick(r -> r["row"] == "V-C4" && r["J_cc"] == J && r["CI"] == ci)
    @assert length(rs) == 10
    pt!("V-C4", "J_cc $J, CI $ci", rs, 5000)
    m4[(J, ci)] = mean(r -> r["C_5000"], rs)
end
ok = abs(m4[(20.0, true)] - 0.3) <= 0.1 && abs(m4[(40.0, true)] - 0.3) <= 0.1 && abs(m4[(80.0, true)] - 0.85) <= 0.1
add!("V-C4", "CI: C at J_cc 20, 40, 80", "$(m4[(20.0, true)]), $(m4[(40.0, true)]), $(m4[(80.0, true)])", "0.3, 0.3, 0.85 ± 0.1", ok)
ok = abs(m4[(0.0, false)] - 0.35) <= 0.1 && all(J -> abs(m4[(J, false)] - 0.83) <= 0.1, (15.0, 20.0, 40.0))
add!("V-C4", "no CI: C at J_cc 0, 15, 20, 40", join((m4[(J, false)] for J in (0.0, 15.0, 20.0, 40.0)), ", "), "0.35, 0.83, 0.83, 0.83 ± 0.1", ok)
ok = m4[(80.0, true)] - m4[(0.0, true)] > 0.3 && m4[(40.0, false)] - m4[(0.0, false)] > 0.3
add!("V-C4", "rise lowest to highest J_cc (CI, no CI)", "$(m4[(80.0, true)] - m4[(0.0, true)]), $(m4[(40.0, false)] - m4[(0.0, false)])", "> 0.3 both", ok)
# V-C5
pts5 = [((0.0, true), 0.9), ((500.0, true), 0.35), ((5000.0, true), 0.2), ((0.0, false), 0.95), ((5000.0, false), 0.7)]
for ((χ, ci), want) in pts5
    rs = pick(r -> r["row"] == "V-C5" && r["χcM"] == χ && r["CI"] == ci)
    @assert length(rs) == 10
    pt!("V-C5", "χcM $χ, CI $ci", rs, 5000)
    got = mean(r -> r["C_5000"], rs)
    add!("V-C5", "χcM = $χ, CI = $ci", got, "$want ± 0.1", abs(got - want) <= 0.1)
end
# V-C7
ss = [0.0, 0.025, 0.05, 0.075, 0.1, 0.125, 0.15, 0.175, 0.2, 0.25]
mci = map(ss) do s
    rs = pick(r -> r["row"] == "V-C7" && r["CI"] && r["s"] == s)
    @assert length(rs) == 10
    pt!("V-C7", "s $s, CI true", rs, 5000)
    mean(r -> r["C_5000"], rs)
end
mid = crossing(ss, mci, (mci[1] + mci[end]) / 2)
add!("V-C7", "CI midpoint in s", something(mid, "none"), "in [0.07, 0.15]", mid !== nothing && 0.07 <= mid <= 0.15)
for s in (0.0, 0.1, 0.25)
    rs = pick(r -> r["row"] == "V-C7" && !r["CI"] && r["s"] == s)
    @assert length(rs) == 10
    pt!("V-C7", "s $s, CI false", rs, 5000)
    got = mean(r -> r["C_5000"], rs)
    add!("V-C7", "no CI, s = $s", got, "0.95 ± 0.1", abs(got - 0.95) <= 0.1)
end
# V-C9
m9 = Dict{Any, Float64}()
for (T, mode) in ((50.0, "extension_only"), (50.0, "extension_retraction"), (800.0, "extension_only"), (800.0, "extension_retraction"))
    rs = pick(r -> r["row"] == "V-C9" && r["T"] == T && r["mode"] == mode)
    @assert length(rs) == 10
    pt!("V-C9", "T $T, $mode", rs, 5000)
    m9[(T, mode)] = mean(r -> r["C_5000"], rs)
end
add!("V-C9", "ext-only C(T = 50)", m9[(50.0, "extension_only")], "> 0.85", m9[(50.0, "extension_only")] > 0.85)
add!("V-C9", "ext-retr C(T = 50)", m9[(50.0, "extension_retraction")], "< 0.5", m9[(50.0, "extension_retraction")] < 0.5)
add!("V-C9", "both C(T = 800)", "$(m9[(800.0, "extension_only")]), $(m9[(800.0, "extension_retraction")])", "< 0.3 both",
    m9[(800.0, "extension_only")] < 0.3 && m9[(800.0, "extension_retraction")] < 0.3)
# V-C12
ci = [r["displacement_sites"] for r in pick(r -> r["row"] == "V-C12" && r["CI"])]
no = [r["displacement_sites"] for r in pick(r -> r["row"] == "V-C12" && !r["CI"])]
@assert length(ci) == 10 && length(no) == 10
add!("V-C12", "displacement ratio CI / no CI (100 -> 19300)", mean(ci) / mean(no), "in [1.5, 2.5]", 1.5 <= mean(ci) / mean(no) <= 2.5)
# V-C1
c1 = pick(r -> r["row"] == "V-C1" && r["CI"]); n1 = pick(r -> r["row"] == "V-C1" && !r["CI"])
@assert length(c1) == 5 && length(n1) == 5
k = count(r -> r["network_10000"], c1)
add!("V-C1", "CI networks at 10^4", "$k/5", ">= 4/5", k >= 4)
k = count(r -> r["share_10000"] < 0.5, n1)
add!("V-C1", "no CI share < 0.5 at 10^4", "$k/5", ">= 4/5", k >= 4)

clean(x) = replace(string(x isa AbstractFloat ? round(x; digits = 4) : x), r"[\t\n]" => " ")
open(joinpath(OUT, "verdicts.tsv"), "w") do io
    println(io, join(("row", "check", "ours", "rule", "result"), '\t'))
    foreach(v -> println(io, join(clean.(v), '\t')), verdicts)
end
open(joinpath(OUT, "points.tsv"), "w") do io
    println(io, join(("row", "point", "n", "mean_C_N", "std_C_N", "mean_C_N+100", "std_C_N+100"), '\t'))
    foreach(v -> println(io, join(clean.(v), '\t')), points)
end
cols = sort(unique(reduce(vcat, collect.(keys.(rows)))))
open(joinpath(OUT, "replicates.tsv"), "w") do io
    println(io, join(cols, '\t'))
    for r in sort(rows; by = r -> (r["row"], r["key"]))
        println(io, join((clean(get(r, c, "")) for c in cols), '\t'))
    end
end
npass = count(v -> v[5] == "PASS", verdicts)
println("verdicts: $npass PASS / $(length(verdicts)) checks")
foreach(v -> println(join(clean.(v), " | ")), verdicts)

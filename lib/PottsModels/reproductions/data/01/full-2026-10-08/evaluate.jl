# P6.3f: apply the FROZEN FULL rules of lib/PottsModels/test/reproductions/01_merks.jl
# (lines 302–394, D-153) to the per-replicate rows written by run_full.jl. Not a frozen file;
# every condition below is a transcription of a frozen `@test`, in the same order.
# Writes verdicts.tsv (the 37 checks, in the labels and format of the frozen page test,
# D-184), replicates.tsv (full precision) and points.tsv (means per sweep point, at N and N + 100).
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
# Replicate rows as strings, at full precision (shortest round-trip form), as the frozen page
# test (test/reproductions/01_merks_page.jl) reads them back.
cell(x) = x isa AbstractFloat ? repr(Float64(x)) : string(x)
R = [Dict{String, String}(k => cell(v) for (k, v) in r) for r in rows]
eqv(s, v::Bool) = s == string(v)
eqv(s, v::Real) = (x = tryparse(Float64, s); x !== nothing && x == v)
eqv(s, v::AbstractString) = s == v
sel(row; kw...) = sort(filter(r -> r["row"] == row && all(eqv(get(r, string(k), ""), v) for (k, v) in kw), R);
    by = r -> parse(Int, r["seed"]))
num(r, c) = parse(Float64, r[c])
flag(r, c) = r[c] == "true"
f3(x) = string(round(x; digits = 3))
mC(rs, t) = mean(r -> num(r, "C_$t"), rs)
points = Any[]
function pt!(row, label, rs, t)
    a, b = [parse(Float64, r["C_$t"]) for r in rs], [parse(Float64, r["C_$(t + 100)"]) for r in rs]
    push!(points, (row, label, length(rs), mean(a), std(a), mean(b), std(b)))
end
verdicts = Any[]
add!(row, check, ours, rule, ok, paper) = push!(verdicts, (row, check, ours, rule, ok ? "PASS" : "FAIL", paper))
# V-E1 (frozen: count(isnetwork, net(1440)) >= 8; mean lacunae 5760 < 1440; mean share 5760 >= 0.9; control)
std_ = sel("V-E1"; arm = "standard"); rnd = sel("V-E1"; arm = "λ_L = 0")
@assert length(std_) == 10 && length(rnd) == 10
n12 = count(r -> flag(r, "network_1440"), std_)
add!("V-E1", "network at 1440 MCS (12 h)", "$n12/$(length(std_))", ">= 8/10", n12 >= 8, "network at 12 h (01a Fig. 4)")
l12, l48 = mean(r -> num(r, "lacunae_1440"), std_), mean(r -> num(r, "lacunae_5760"), std_)
add!("V-E1", "mean lacunae at 5760 vs 1440 MCS", "$(f3(l48)) vs $(f3(l12))", "5760 < 1440", l48 < l12, "coarsens, 12 → 48 h (01a Figs. 4, 5)")
s48 = mean(r -> num(r, "share_5760"), std_)
add!("V-E1", "mean share at 5760 MCS (48 h)", f3(s48), ">= 0.9", s48 >= 0.9, "still one network at 48 h (01a Fig. 4)")
s12, sr = mean(r -> num(r, "share_1440"), std_), mean(r -> num(r, "share_1440"), rnd)
add!("V-E1", "control λ_L = 0: mean share at 1440 MCS vs standard", "$(f3(sr)) vs $(f3(s12))", "<= standard - 0.2", sr <= s12 - 0.2,
    "round cells form islands (01a p.50)")
# V-E5
for L in (10.0, 20.0, 30.0, 40.0, 50.0)
    rs = sel("V-E5"; L); @assert length(rs) == 10
    nnet = count(r -> flag(r, "network_5760"), rs)
    add!("V-E5", "L = $(Int(L)) px ($(Int(2L)) µm): networks at 5760 MCS", "$nnet/10", L <= 20 ? "islands in >= 8/10" : "networks in >= 8/10",
        L <= 20 ? (10 - nnet >= 8) : (nnet >= 8), L <= 20 ? "islands (01a Fig. 6)" : "network (01a Fig. 6)")
end
# V-E6
for Jcc in (20.0, 5.0, 1.0)
    rs = sel("V-E6"; J_cc = Jcc); @assert length(rs) == 10
    nnet = count(r -> flag(r, "network_5760"), rs)
    add!("V-E6", "J_cc = $(Int(Jcc)): networks at 5760 MCS", "$nnet/10", ">= 8/10", nnet >= 8, "network (01a Fig. 7)")
    if Jcc == 1.0
        lj = mean(r -> num(r, "lacunae_5760"), rs)
        add!("V-E6", "J_cc = 1: mean lacunae vs V-E1 standard at 5760 MCS", "$(f3(lj)) vs $(f3(l48))", "<=", lj <= l48,
            "not more lacunae (01a Fig. 7)")
    end
end
# V-E10
el = [num(r, "anisotropy") for r in sel("V-E10"; arm = "elongated")]
ro = [num(r, "anisotropy") for r in sel("V-E10"; arm = "round")]
@assert length(el) == 10 && length(ro) == 10
add!("V-E10", "elongated: mean anisotropy", f3(mean(el)), "> 1.2", mean(el) > 1.2, "faster along the long axis (01a Fig. 11)")
add!("V-E10", "round control: mean anisotropy", f3(mean(ro)), "< 1.2 and < elongated", mean(ro) < 1.2 && mean(ro) < mean(el), "isotropic")
# V-C2, V-C3
ratios = collect(0.0:0.1:1.0)
C3 = [sel("V-C3"; ratio = x) for x in ratios]
@assert all(==(10) ∘ length, C3)
foreach(((x, rs),) -> pt!("V-C3", "ratio $x", rs, 10_000), zip(ratios, C3))
m = [mC(rs, 10_000) for rs in C3]
add!("V-C2", "mean C at ratio 0 (CI) vs ratio 1 (no CI), 10⁴ MCS", "$(f3(m[1])) vs $(f3(m[end]))", "CI < no CI - 0.3", m[1] < m[end] - 0.3,
    "sprouts vs compact (01b Fig. 4)")
low, high = mean(m[1:5]), mean(m[8:11])
add!("V-C3", "low plateau (ratio 0–0.4)", f3(low), "0.35 ± 0.07", abs(low - 0.35) <= 0.07, "0.35 (01b Fig. 5)")
add!("V-C3", "high plateau (ratio 0.7–1)", f3(high), "0.9 ± 0.07", abs(high - 0.9) <= 0.07, "0.9 (01b Fig. 5)")
mid = crossing(ratios, m, (low + high) / 2)
add!("V-C3", "midpoint", mid === nothing ? "none" : f3(mid), "in [0.45, 0.65]", mid !== nothing && 0.45 <= mid <= 0.65, "≈ 0.5 (01b p.6)")
# V-C4
pts4 = [(0.0, true), (20.0, true), (40.0, true), (60.0, true), (80.0, true),
    (0.0, false), (5.0, false), (10.0, false), (15.0, false), (20.0, false), (40.0, false)]
for (J, ci) in pts4
    rs = sel("V-C4"; J_cc = J, CI = ci); @assert length(rs) == 10
    pt!("V-C4", "J_cc $J, CI $ci", rs, 5000)
end
m4(J, ci) = mC(sel("V-C4"; J_cc = J, CI = ci), 5000)
a = (m4(20.0, true), m4(40.0, true), m4(80.0, true))
add!("V-C4", "CI: mean C at J_cc = 20, 40, 80", join(f3.(a), ", "), "0.3, 0.3, 0.85 ± 0.1",
    abs(a[1] - 0.3) <= 0.1 && abs(a[2] - 0.3) <= 0.1 && abs(a[3] - 0.85) <= 0.1, "0.3, 0.3, 0.85 (01b Fig. 7)")
b = (m4(0.0, false), m4(15.0, false), m4(20.0, false), m4(40.0, false))
add!("V-C4", "no CI: mean C at J_cc = 0, 15, 20, 40", join(f3.(b), ", "), "0.35, 0.83, 0.83, 0.83 ± 0.1",
    abs(b[1] - 0.35) <= 0.1 && all(x -> abs(x - 0.83) <= 0.1, b[2:4]), "0.35, 0.83, 0.83, 0.83 (01b Fig. 7)")
rci, rno = m4(80.0, true) - m4(0.0, true), m4(40.0, false) - m4(0.0, false)
add!("V-C4", "rise from the lowest to the highest J_cc (CI; no CI)", "$(f3(rci)); $(f3(rno))", "> 0.3 both", rci > 0.3 && rno > 0.3,
    "both rise (01b Fig. 7)")
# V-C5
for ((χ, ci), want) in [((0.0, true), 0.9), ((500.0, true), 0.35), ((5000.0, true), 0.2), ((0.0, false), 0.95), ((5000.0, false), 0.7)]
    rs = sel("V-C5"; χcM = χ, CI = ci); @assert length(rs) == 10
    pt!("V-C5", "χcM $χ, CI $ci", rs, 5000)
    got = mC(rs, 5000)
    add!("V-C5", "χcM = $(Int(χ)), $(ci ? "CI" : "no CI"): mean C", f3(got), "$want ± 0.1", abs(got - want) <= 0.1, "$want (01b Fig. 8)")
end
# V-C7
ss = [0.0, 0.025, 0.05, 0.075, 0.1, 0.125, 0.15, 0.175, 0.2, 0.25]
mci = map(ss) do s
    rs = sel("V-C7"; s, CI = true); @assert length(rs) == 10
    pt!("V-C7", "s $s, CI true", rs, 5000)
    mC(rs, 5000)
end
mid7 = crossing(ss, mci, (mci[1] + mci[end]) / 2)
add!("V-C7", "CI: transition midpoint in s", mid7 === nothing ? "none" : f3(mid7), "in [0.07, 0.15]", mid7 !== nothing && 0.07 <= mid7 <= 0.15,
    "≈ 0.08–0.13 (01b Fig. 9)")
for s in (0.0, 0.1, 0.25)
    rs = sel("V-C7"; s, CI = false); @assert length(rs) == 10
    pt!("V-C7", "s $s, CI false", rs, 5000)
    got = mC(rs, 5000)
    add!("V-C7", "no CI, s = $s: mean C", f3(got), "0.95 ± 0.1", abs(got - 0.95) <= 0.1, "0.93–0.97 (01b Fig. 9)")
end
# V-C9
for (T, mode) in ((50.0, "extension_only"), (50.0, "extension_retraction"), (800.0, "extension_only"), (800.0, "extension_retraction"))
    rs = sel("V-C9"; T, mode); @assert length(rs) == 10
    pt!("V-C9", "T $T, $mode", rs, 5000)
end
m9(T, mode) = mC(sel("V-C9"; T, mode), 5000)
add!("V-C9", "extension-only, T = 50: mean C", f3(m9(50.0, "extension_only")), "> 0.85", m9(50.0, "extension_only") > 0.85, "≈ 1 (01b Fig. 11)")
add!("V-C9", "extension-retraction, T = 50: mean C", f3(m9(50.0, "extension_retraction")), "< 0.5", m9(50.0, "extension_retraction") < 0.5,
    "sprouts (01b Fig. 11)")
e8, r8 = m9(800.0, "extension_only"), m9(800.0, "extension_retraction")
add!("V-C9", "both modes, T = 800: mean C (ext-only; ext-retr)", "$(f3(e8)); $(f3(r8))", "< 0.3 both", e8 < 0.3 && r8 < 0.3, "break-up (01b Fig. 11)")
# V-C12 (D-200 item 1: from MCS 0, read from vc12_mcs0.tsv beside this script; it was MCS 100,
# the `displacement_sites` column)
v12 = let ls = filter(!isempty, readlines(joinpath(@__DIR__, "vc12_mcs0.tsv"))), h = split(ls[1], '\t')
    [Dict(String(a) => String(b) for (a, b) in zip(h, split(l, '\t'))) for l in ls[2:end]]
end
ci12 = [parse(Float64, r["displacement_sites_0"]) for r in v12 if r["CI"] == "true"]
no12 = [parse(Float64, r["displacement_sites_0"]) for r in v12 if r["CI"] == "false"]
@assert length(ci12) == 10 && length(no12) == 10
q = mean(ci12) / mean(no12)
add!("V-C12", "displacement ratio CI / no CI (MCS 0 to 19 300)", f3(q), "in [1.5, 2.5]", 1.5 <= q <= 2.5, "85 / 42 µm ≈ 2.0 (01b Fig. 6E)")
# V-C1
c1 = sel("V-C1"; CI = true); n1 = sel("V-C1"; CI = false)
@assert length(c1) == 5 && length(n1) == 5
k1 = count(r -> flag(r, "network_10000"), c1)
add!("V-C1", "CI: networks at 10⁴ MCS", "$k1/5", ">= 4/5", k1 >= 4, "network (01b Fig. 2D)")
k2 = count(r -> num(r, "share_10000") < 0.5, n1)
add!("V-C1", "no CI: share < 0.5 at 10⁴ MCS", "$k2/5", ">= 4/5", k2 >= 4, "islands (01b Fig. 2C)")
@assert length(verdicts) == 37

clean(x) = replace(string(x isa AbstractFloat ? round(x; digits = 4) : x), r"[\t\n]" => " ")
open(joinpath(OUT, "verdicts.tsv"), "w") do io
    println(io, join(("row", "check", "ours", "rule", "result", "paper"), '\t'))
    foreach(v -> println(io, join(clean.(v), '\t')), verdicts)
end
open(joinpath(OUT, "points.tsv"), "w") do io
    println(io, join(("row", "point", "n", "mean_C_N", "std_C_N", "mean_C_N+100", "std_C_N+100"), '\t'))
    foreach(v -> println(io, join(clean.(v), '\t')), points)
end
cols = sort(unique(reduce(vcat, collect.(keys.(rows)))))
open(joinpath(OUT, "replicates.tsv"), "w") do io
    println(io, join(cols, '\t'))
    for r in sort(R; by = r -> (r["row"], r["key"]))
        println(io, join((replace(get(r, c, ""), r"[\t\n]" => " ") for c in cols), '\t'))
    end
end
npass = count(v -> v[5] == "PASS", verdicts)
println("verdicts: $npass PASS / $(length(verdicts)) checks")
foreach(v -> println(join(clean.(v), " | ")), verdicts)

# The frozen V4 rules of `test/reproductions/15_openvt_f5.jl`, applied to the consortium's
# 1000-cell files (G at 54f375f): TST_5T (and Morpheus_5T for context). Information only: no
# verdict of this record changes. G files never enter git; the zips are unpacked into a
# scratch directory, and the pooled histograms for the figure go to `F5_G_OUT` (not committed).
#     OPENVT_MONOLAYER_REPO=$HOME/openvt/monolayergrowth F5_G_OUT=$HOME/potts-ci/p6-15e-out/g \
#         julia --project=lib/PottsModels/test lib/PottsModels/reproductions/data/15/f5-2026-10-07/v4_on_g.jl
using Statistics: mean, median

const ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", "..", "..", ".."))
const TEST = joinpath(ROOT, "lib", "PottsModels", "test", "reproductions", "15_openvt_f5.jl")
const G = ENV["OPENVT_MONOLAYER_REPO"]
const OUT = get(ENV, "F5_G_OUT", mktempdir())
mkpath(OUT)

# the frozen rules, verbatim: evaluate only the test file's P615E_/p615e_ constants and pure
# rule functions (no testsets, no runs)
module Rules
const KEEP = (:P615E_BAND, :P615E_NBINS, :p615e_bin, :p615e_hist, :p615e_peak, :p615e_summary, :p615e_merge,
    :p615e_in, :p615e_v4)
name(ex) = ex isa Expr && ex.head === :const ? name(ex.args[1]) :
           ex isa Expr && ex.head in (:(=), :function) ? (a = ex.args[1]; a isa Symbol ? a :
                                                          a isa Expr && a.head === :call ? a.args[1] :
                                                          a isa Expr && a.head === :where ? a.args[1].args[1] : nothing) : nothing
for ex in Meta.parseall(read(Main.TEST, String)).args
    ex isa Expr || continue
    name(ex) in KEEP && Core.eval(@__MODULE__, ex)
end
end

# rows of one framework: per file (f, a, x, y); `cols` = positions of x, y, f, a (1-based)
function readdir_rows(dir, delim, cols; header = true)
    files = sort(filter(f -> endswith(f, ".csv"), readdir(dir; join = true)))
    out = []
    for p in files
        ls = filter(!isempty ∘ strip, readlines(p))
        header && (ls = ls[2:end])
        x = Float64[]; y = Float64[]; f = Float64[]; a = Float64[]
        for l in ls
            v = parse.(Float64, split(strip(l), delim; keepempty = false))
            push!(x, v[cols[1]]); push!(y, v[cols[2]]); push!(f, max(v[cols[3]], 0.0)); push!(a, max(v[cols[4]], 0.0))
        end
        push!(out, (; x, y, f, a))
    end
    return out
end
unzip(zip) = (d = mktempdir(); run(`unzip -q -o $zip -d $d`); d)
csvdir(d) = (fs = [root for (root, _, files) in walkdir(d) if any(endswith(".csv"), files)]; only(fs))

sets = Dict{String, Any}()
tst = csvdir(unzip(joinpath(G, "results", "TST", "TST_5T_MonolayerGrowth_1000_Data.zip")))
# notebook: columns x, y, r, f, a by position, with f and a swapped for TST (spec §3.4, D8)
sets["TST_5T"] = readdir_rows(tst, ',', (1, 2, 5, 4))
mor = joinpath(G, "results", "Morpheus", "Monolayer", "Morpheus_MonolayerGrowth_1000_Data_5T_major2.zip")
if isfile(mor)
    # tab: time cell.id x y cell.radius f_i a_i (in R)
    sets["Morpheus_5T"] = readdir_rows(csvdir(unzip(mor)), '\t', (3, 4, 6, 7))
end

for name in sort(collect(keys(sets)))
    rs = sets[name]
    f = reduce(vcat, [r.f for r in rs]); a = reduce(vcat, [r.a for r in rs])
    # any value ≥ 2 would leave the frozen histogram range; report and clip (information only)
    nclip = count(>=(2), a) + count(>=(2), f)
    s = Rules.p615e_summary(min.(f, 1.999), min.(a, 1.999))
    r = Rules.p615e_v4(s)
    nz = filter(>(0), f)
    println(name, ": files ", length(rs), ", cells ", length(f), ", clipped ", nclip)
    println("  V4 stats ", r.v)
    println("  V4 rows  ", r.ok, "  pass = ", r.pass)
    println("  mean nonzero f ", mean(nz), ", median ", median(nz), "; f > 0.56: ", count(>(0.56), f),
        "; a < 0.42: ", count(<(0.42), a), "; mean f ", mean(f))
    q(p) = sort(a)[max(1, ceil(Int, p * length(a)))]
    println("  a quantiles 0.01 % ", q(1e-4), ", 0.1 % ", q(1e-3), ", 1 % ", q(1e-2), ", 5 % ", q(5e-2))
    for w in (1, 3, 5, 7, 9, 11)
        hn = copy(s.hf); hn[1] -= s.n_f0; h = w ÷ 2
        sm = [sum(hn[max(1, k - h):min(200, k + h)]) / (min(200, k + h) - max(1, k - h) + 1) for k in 1:200]
        print("  window $w peak ", (argmax(sm) - 0.5) / 100, ";")
    end
    println()
    # pooled histograms by distance bin from the pooled centroid mean (notebook, C12) for the
    # figure: units differ by framework (TST_5T is in px, D8), so the bins are in its own units
    x = reduce(vcat, [r.x for r in rs]); y = reduce(vcat, [r.y for r in rs])
    d = hypot.(x .- mean(x), y .- mean(y))
    e = collect(range(0, 1.05maximum(d); length = 6))
    db = [min(5, searchsortedlast(e, v)) for v in d]
    open(joinpath(OUT, "hist_$(name).tsv"), "w") do io
        println(io, join(("case", "quantity", "dbin", "d_lo_R", "d_hi_R", "bin", "x_lo", "count"), '\t'))
        for (qq, v) in (("f", f), ("a", a)), j in 1:5
            h = Rules.p615e_hist(min.(v[db .== j], 1.999))
            for k in eachindex(h)
                h[k] > 0 && println(io, join((name, qq, j, e[j], e[j + 1], k - 1, (k - 1) / 100, h[k]), '\t'))
            end
        end
    end
end
println("histograms in ", OUT)

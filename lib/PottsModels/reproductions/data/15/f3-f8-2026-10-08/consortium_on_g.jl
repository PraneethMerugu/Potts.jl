# The consortium overlay rows for plot_f3.jl and plot_f8.jl, from a local G clone (54f375f):
# - TST No_CI deterministic and stochastic (spec §4.4 F3; 100 runs each, lengths in R): N at
#   every save and the `openvt_metrics` r, A of every save (all cells growing), cut at the first
#   save with ≥ 1000 cells, by the frozen test's own readers;
# - the draft Fig 8 lattice curves `postprocessing/measurements_{compucell3d,morpheus}.csv`
#   and `neighbors_*.csv` (legacy β = 0.8 runs, legacy cycles, D4), lengths converted from px
#   to R with R_px = √(A₀/π) (CompuCell3D A₀ = 25, Morpheus A₀ = 50; spec C10).
# Information only: no verdict depends on it. G files never enter git; the outputs go to
# F3F8_G_OUT (default a temporary directory) and are not committed (D-168).
#     OPENVT_MONOLAYER_REPO=$HOME/openvt/monolayergrowth F3F8_G_OUT=$HOME/potts-ci/p6-15f-impl-out/g \
#         julia --project=lib/PottsModels/test lib/PottsModels/reproductions/data/15/f3-f8-2026-10-08/consortium_on_g.jl
using PottsModels, Test
using Statistics: mean

const ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", "..", "..", ".."))
const TEST = joinpath(ROOT, "lib", "PottsModels", "test", "reproductions", "15_openvt_f3_f8.jl")
const G = ENV["OPENVT_MONOLAYER_REPO"]
const OUT = get(ENV, "F3F8_G_OUT", mktempdir())
mkpath(OUT)

# the frozen test's constants and readers, verbatim
_defname(ex) = ex isa Expr && ex.head === :const ? _defname(ex.args[1]) :
               ex isa Expr && ex.head in (:(=), :function) ? (a = ex.args[1]; a isa Symbol ? a :
                                                              a isa Expr && a.head === :call ? a.args[1] :
                                                              a isa Expr && a.head === :where ? a.args[1].args[1] :
                                                              nothing) : nothing
for ex in Meta.parseall(read(TEST, String)).args
    ex isa Expr || continue
    n = _defname(ex)
    (n isa Symbol && startswith(string(n), r"p615f_|P615F_")) && !(n in (:P615F_ALG,)) || continue
    Core.eval(@__MODULE__, ex)
end

# TST: every save's metrics (the test's reader computes them only where the rules read)
function tst_full(kind)
    zip = joinpath(G, "results", "TST", "TST_No_CI_$(kind).zip")
    d = mktempdir()
    run(`unzip -q -o $zip -d $d`)
    out = []
    for (root, _, files) in walkdir(d)
        occursin("__MACOSX", root) && continue
        fs = filter(f -> startswith(f, "cell_data_no_inhibition_") && endswith(f, ".csv"), files)
        isempty(fs) && continue
        mcs = [parse(Int, f[(length("cell_data_no_inhibition_") + 1):(end - 4)]) for f in fs]
        p = sortperm(mcs)
        fs, mcs = fs[p], mcs[p]
        rows(f) = filter(!isempty ∘ strip, readlines(joinpath(root, f)))[2:end]
        N = [length(rows(f)) for f in fs]
        s = p615f_cut(p615f_series(mcs ./ P615F_CYCLE, N), 1000)
        r = fill(NaN, length(s.t)); A = fill(NaN, length(s.t))
        for j in eachindex(s.t)
            s.N[j] >= 3 || continue
            xy = [parse.(Float64, split(l, ',')[1:2]) for l in rows(fs[j])]
            m = openvt_metrics(first.(xy), last.(xy), ones(length(xy)))
            r[j], A[j] = m.r, m.A
        end
        push!(out, (; run = basename(root), s.t, s.N, r, A))
    end
    return sort(out; by = x -> x.run)
end
f(x) = isnan(x) ? "nan" : repr(x)
for kind in ("deterministic", "stochastic")
    runs = tst_full(kind)
    open(joinpath(OUT, "tst_$(kind).tsv"), "w") do io
        println(io, "run\tt\tN\tr\tA")
        for (k, s) in enumerate(runs), j in eachindex(s.t)
            println(io, join((k, s.t[j], s.N[j], f(s.r[j]), f(s.A[j])), '\t'))
        end
    end
    println(kind, ": ", length(runs), " runs")
end
const RPX = Dict("compucell3d" => sqrt(25 / π), "morpheus" => sqrt(50 / π))
for fw in ("compucell3d", "morpheus")
    pp = joinpath(G, "results", "postprocessing")
    l = split.(readlines(joinpath(pp, "measurements_$(fw).csv")), ',')
    col(name) = findfirst(==(name), l[1])
    R = RPX[fw]
    open(joinpath(OUT, "legacy_$(fw).tsv"), "w") do io
        println(io, "t\tN\tr\tA\tC\tw\tg")
        for row in l[2:end]
            v(name) = parse(Float64, row[col(name)])
            # header t,N,R,A,C,w,g (run_metrics.sh, D1): R is the mean radius r, in px
            println(io, join((v("t"), v("N"), v("R") / R, v("A") / R^2, v("C") / R, v("w") / R, v("g")), '\t'))
        end
    end
    cp(joinpath(pp, "neighbors_$(fw).csv"), joinpath(OUT, "neighbors_$(fw).csv"); force = true)
end
println("wrote ", OUT)

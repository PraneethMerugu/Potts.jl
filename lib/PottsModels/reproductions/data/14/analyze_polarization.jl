# Reduce the tracks of `run_polarization.jl` to the record of the polarization study (Thomas
# et al. 2022) with `polarization_protocol.jl`: sets.tsv, curves.tsv, msd.tsv,
# clouds.tsv.gz, verdicts.tsv and provenance.toml in <out>/record/ (the schema is in the
# protocol). It prints the verdict rows, and the exit status is 0 only if every gating row
# passed (a trial always exits 0). Copy the record to
# lib/PottsModels/reproductions/data/14/polarization-<date>/ and explain each FAIL row in a
# deviations.tsv there (id ours paper cause).
#
# Usage, from the checkout root:
#
#   julia --project=lib/PottsModels/test \
#       lib/PottsModels/reproductions/data/14/analyze_polarization.jl <out> [--warmup W]
#
# <out> is the --out of the runner (or <out>/trial for a trial). `--warmup W` replaces the
# 1000-MCS warm-up, for trials only; the record then is marked `trial = true`.
using Potts, PottsModels, TOML, Dates, Printf
using CodecZlib: GzipCompressorStream, GzipDecompressorStream

include(joinpath(@__DIR__, "polarization_protocol.jl"))
const PP = FortunaPolarizationProtocol

(length(ARGS) in (1, 3) && (length(ARGS) == 1 || ARGS[2] == "--warmup")) ||
    error("usage: analyze_polarization.jl <out> [--warmup W]")
const DIR = abspath(ARGS[1])
const TRACKS = joinpath(DIR, "tracks")
isdir(TRACKS) || error("analyze_polarization.jl: no tracks/ in $DIR")
const WARMUP = length(ARGS) == 3 ? parse(Int, ARGS[3]) : PP.WARMUP
const REC = joinpath(DIR, "record")
mkpath(REC)

function read_track(path)
    lines = open(io -> readlines(GzipDecompressorStream(io)), path)
    head = Symbol.(split(lines[1], '\t'))
    cols = [Float64[] for _ in head]
    for l in @view lines[2:end]
        for (c, x) in zip(cols, split(l, '\t'))
            push!(c, parse(Float64, x))
        end
    end
    nt = NamedTuple{Tuple(head)}(Tuple(cols))
    return merge(nt, (; t = round.(Int, nt.t)))
end

metas = [TOML.parsefile(joinpath(TRACKS, f)) for f in sort(readdir(TRACKS)) if endswith(f, ".toml")]
isempty(metas) && error("analyze_polarization.jl: no finished run in $TRACKS")
const TRIAL = any(m -> m["trial"], metas) || WARMUP != PP.WARMUP
key(m) = "set$(lpad(m["set"], 2, '0'))_rep$(lpad(m["rep"], 2, '0'))"
bysets = Dict{Int, Vector{Any}}()
for m in metas
    push!(get!(bysets, m["set"], Any[]), m)
end

rows, curves = Dict{Any, Any}(), Dict{Any, Any}()
setrows, curverows, msdrows, cloudrows = String[], String[], String[], String[]
fmt(x::Bool) = x ? "1" : "0"
fmt(x::Integer) = string(x)
fmt(x::Real) = isnan(x) ? "NaN" : @sprintf("%.6g", x)
for i in sort(collect(keys(bysets)))
    s = PP.SETS[i]
    R, φ, _ = s
    L, _, _ = fortuna_lattice(R, φ)
    ms = sort(bysets[i]; by = m -> m["rep"])
    runs = [PP.stationary(read_track(joinpath(TRACKS, key(m) * ".tsv.gz")), R, L; warmup = WARMUP) for m in ms]
    a = PP.analyze_set(runs)
    rows[s], curves[s] = a.row, a.curves
    push!(setrows, join([string(i), string(R), string(φ), string(s[3]), (fmt(v) for v in a.row)...], '\t'))
    for c in a.curves
        push!(curverows, join([string(i), (fmt(v) for v in c)...], '\t'))
    end
    for c in a.msd
        push!(msdrows, join([string(i), fmt(c.lag), fmt(c.msd)], '\t'))
    end
    for c in a.cloud
        push!(cloudrows, join([string(i), (fmt(v) for v in c)...], '\t'))
    end
    println(PP.set_id(s), ": ", length(runs), " runs, S = ", fmt(a.row.S), ", Δτ_opt = ", fmt(a.row.dtau))
end

function write_tsv(name, header, lines)
    open(joinpath(REC, name), "w") do io
        println(io, join(header, '\t'))
        foreach(l -> println(io, l), lines)
    end
    return nothing
end
const SET_HEAD = (
    "set", "R", "phi", "lambda", "n", "S", "P", "D", "resolved", "dtau", "alpha", "lag", "pi", "u",
    "eps", "sigma", "xi_CN_N", "xi_L_CN", "xi_L_N", "upar", "dtau_slope", "detached",
)
write_tsv("sets.tsv", SET_HEAD, setrows)
write_tsv("curves.tsv", ("set", "lag", "delta", "u", "upar", "xi_CN_N", "xi_L_CN", "xi_L_N"), curverows)
write_tsv("msd.tsv", ("set", "lag", "msd"), msdrows)
open(GzipCompressorStream, joinpath(REC, "clouds.tsv.gz"), "w") do io
    println(io, join(("set", "rep", "t", "pi", "u", "theta"), '\t'))
    foreach(l -> println(io, l), cloudrows)
end
V = PP.verdicts(rows, curves)
write_tsv(
    "verdicts.tsv", ("id", "kind", "value", "band", "result"),
    [join((v.id, string(v.kind), fmt(v.value), v.band, v.ok ? "PASS" : "FAIL"), '\t') for v in V]
)
open(joinpath(REC, "provenance.toml"), "w") do io
    TOML.print(
        io, Dict(
            "commits" => sort(unique(m["commit"] for m in metas)),
            "dirty" => any(m -> m["dirty"], metas), "c" => unique(m["c"] for m in metas),
            "tmax" => unique(m["tmax"] for m in metas), "warmup" => WARMUP, "trial" => TRIAL,
            "runs" => length(metas), "analyzed" => string(now()),
        )
    )
end
for v in V
    println(rpad(v.id, 40), " ", rpad(string(v.kind), 5), " ", fmt(v.value), "  ", v.band, "  ", v.ok ? "PASS" : "FAIL")
end
const NFAIL = count(v -> v.kind === :row && !v.ok, V)
println("record in ", REC, ": ", count(v -> v.kind === :row, V), " gating rows, ", NFAIL, " FAIL", TRIAL ? " (trial)" : "")
NFAIL == 0 || TRIAL || exit(1)

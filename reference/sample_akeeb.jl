# Legacy Akeeb leader/follower invasion samples for parity tests. Runs the SCDPotts
# runner (SCDPotts/scripts/run_akeeb_proliferative.jl, default parameters J_LF = 2,
# motility 30, PP = 0.5) once per seed into a scratch directory and writes
# reference/data/akeeb_parity.tsv: one row per seed of `akeeb_metrics` on the final state.
#
# usage (from PottsMonorepo/):
#   SCD_AKEEB_WIDTH=99 SCD_AKEEB_HEIGHT=60 SCD_AKEEB_MCS=400 NSEEDS=8 \
#     julia --project="../SCDPotts" reference/sample_akeeb.jl
using DelimitedFiles
ENV["SCD_AKEEB_WIDTH"] = get(ENV, "SCD_AKEEB_WIDTH", "99")
ENV["SCD_AKEEB_HEIGHT"] = get(ENV, "SCD_AKEEB_HEIGHT", "60")
ENV["SCD_AKEEB_MCS"] = get(ENV, "SCD_AKEEB_MCS", "400")
const SCD = normpath(joinpath(@__DIR__, "..", "..", "SCDPotts"))
include(joinpath(SCD, "scripts", "run_akeeb_proliferative.jl"))   # main() guarded
include(joinpath(@__DIR__, "akeeb_metrics.jl"))

nseeds = parse(Int, get(ENV, "NSEEDS", "8"))
nmcs = parse(Int, ENV["SCD_AKEEB_MCS"])
scratch = mktempdir()
rows = map(1:nseeds) do seed
    out = joinpath(scratch, "seed$seed")
    ENV["SCD_AKEEB_SEED"] = string(seed)
    ENV["SCD_AKEEB_OUTPUT"] = out
    t = @elapsed main()
    kinds = vec(readdlm(joinpath(out, "cell_kinds.tsv"), '\t', Int))
    σ = readdlm(joinpath(out, "ownership_$(lpad(nmcs, 4, '0')).tsv"), '\t', Int)
    m = akeeb_metrics(σ, kinds .== 1, length(kinds))
    println("seed $seed ($(round(t; digits = 1)) s): ", m); flush(stdout)
    (; seed, m...)
end
mkpath(joinpath(@__DIR__, "data"))
open(joinpath(@__DIR__, "data", "akeeb_parity.tsv"), "w") do io
    println(io, "# legacy SCDPotts run_akeeb_proliferative.jl, $(DIMS[1])×$(DIMS[2]), mcs=$nmcs, J_LF=2, motility=30, PP=0.5")
    println(io, join(keys(first(rows)), '\t'))
    for r in rows
        println(io, join(values(r), '\t'))
    end
end
println("wrote $(length(rows)) legacy samples")

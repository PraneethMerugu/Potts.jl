# V-C12 MCS-0 export (read-only; no new dynamics): per-replicate displacements, full precision.
# usage (repository root, at the record commit): julia --project=lib/PottsModels/test vc12_mcs0.jl <snapshot dir> > vc12_mcs0.tsv
using Serialization
using Statistics: mean
src = readlines("lib/PottsModels/test/reproductions/01_merks.jl")
include_string(Main, join(src[145:157], "\n"))   # frozen p63d_centroids, p63d_displacement
SNAP = ARGS[1]
println(join(["key", "row", "seed", "CI", "displacement_sites_0", "displacement_sites_100", "jump_sites_0_100"], "\t"))
for (tag, ci, seeds) in (("ci", true, 12_001:12_010), ("no", false, 12_101:12_110)), s in seeds
    k = "C12_$(tag)_s$s"
    snap = deserialize(joinpath(SNAP, k * ".jls"))
    σ0, σ1, σ2 = Int32.(snap[0]), Int32.(snap[100]), Int32.(snap[19_300])
    println(join([k, "V-C12", s, ci, repr(p63d_displacement(σ0, σ2)), repr(p63d_displacement(σ1, σ2)), repr(p63d_displacement(σ0, σ1))], "\t"))
end

# Negative control of the W-lite refusal matrix (test/wlite.jl): delete the 48 generated
# refusal methods, then print, per published model, the routes that build. Run in its own
# process (deleting methods invalidates code). Output: `NEGCTL <model> <count> <routes…>`.
using Potts, PottsModels
include(joinpath(@__DIR__, "shared", "wlite_matrix.jl"))
foreach(Base.delete_method, WLiteMatrix.refusal_methods())
const MTKB = Potts.ModelingToolkitBase
MTKB.@variables y(Potts.t) = 1.0
const decay = MTKB.System([MTKB.D_nounits(y) ~ -y], Potts.t; name = :decay)
for n in (:GranerGlazier, :WortelAct, :MerksVasculogenesis, :OpenVTGrowingMonolayer, :AkeebInvasion, :OpenVTChain,
          :OpenVTReferenceMonolayer, :Merks2006, :Merks2008, :ShearedFoam)
    b = WLiteMatrix.built(WLiteMatrix.matrix(getfield(PottsModels, n)(; name = :m), decay))
    println("NEGCTL ", n, " ", length(b), " ", join(replace.(b, " " => ""), " "))
end

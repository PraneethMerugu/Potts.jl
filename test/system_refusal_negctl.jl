# Negative control of the system container's refusal matrix (system_container_tests.jl): delete the 48 generated
# refusal methods, then print, per published model, the routes that build. Run in its own
# process (deleting methods invalidates code). Output: `NEGCTL <model> <count> <routes…>`.
using Potts, PottsModels
include(joinpath(@__DIR__, "shared", "refusal_matrix.jl"))
foreach(Base.delete_method, RefusalMatrix.refusal_methods())
const MTKB = Potts.ModelingToolkitBase
MTKB.@variables y(Potts.t) = 1.0
const decay = MTKB.System([MTKB.D_nounits(y) ~ -y], Potts.t; name = :decay)
for n in (
        :GranerGlazier, :WortelAct, :MerksVasculogenesis, :OpenVTGrowingMonolayer, :AkeebInvasion, :OpenVTChain,
        :OpenVTReferenceMonolayer, :Merks2006, :Merks2008, :ShearedFoam,
    )
    b = RefusalMatrix.built(RefusalMatrix.matrix(getfield(PottsModels, n)(; name = :m), decay))
    println("NEGCTL ", n, " ", length(b), " ", join(replace.(b, " " => ""), " "))
end

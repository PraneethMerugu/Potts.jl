# The hand-written CorePotts ports of the published models (benchmark/models.jl,
# ports/models.jl) and the same models built from lib/PottsModels
# (ports/symbolic_models.jl): test/symbolic_tests.jl compares them exactly. The old runner
# included these files into `Main` first; the items that read them declare this setup.
@testsetup module PortsSetup
using Potts, Test
using Potts: CorePotts
include(joinpath(@__DIR__, "..", "benchmark", "models.jl"))
include(joinpath(@__DIR__, "ports", "models.jl"))
include(joinpath(@__DIR__, "ports", "symbolic_models.jl"))
include(joinpath(@__DIR__, "shared", "export_visible.jl"))
end

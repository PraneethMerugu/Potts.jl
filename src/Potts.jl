"""
Symbolic cellular Potts modeling on ModelingToolkit and SciML.

Models are authored as a global Hamiltonian with `@potts_model` (see
`docs/design/AUTHORING.md`); `mtkcompile` derives the energy change of a copy and
`PottsProblem` generates the `CorePotts` functions. The numerical layer is re-exported.
"""
module Potts

using Adapt: Adapt
using CorePotts
using KernelAbstractions: KernelAbstractions
using CorePotts: CorePotts, Footprint, Lattice, Periodic, Closed, Moore
using ModelingToolkitBase: ModelingToolkitBase, Differential, Equation, Pre, @named, mtkcompile, extend
using PrecompileTools: PrecompileTools
using RuntimeGeneratedFunctions: RuntimeGeneratedFunctions
using SciMLBase: SciMLBase
using StaticArrays: SMatrix, SVector
using SymbolicUtils: SymbolicUtils
using Symbolics: Symbolics, Num
using SymbolicIndexingInterface: SymbolicIndexingInterface

RuntimeGeneratedFunctions.init(@__MODULE__)

const t = ModelingToolkitBase.t_nounits
const D = ModelingToolkitBase.D_nounits

for name in names(CorePotts)
    name === :CorePotts || @eval export $name
end
export @potts_model, @named, PottsSystem, CompiledPottsSystem, PottsProblem, mtkcompile, extend,
    total_energy, energy_change, parameters, variables, observe, Adaptive

include("vocabulary.jl")
include("system.jl")
include("macro.jl")
include("lower.jl")
include("schedule.jl")
include("compile.jl")
include("codegen.jl")
include("problem.jl")
include("observed.jl")
include("compose.jl")
include("components.jl")
include("precompile.jl")

"""Operating-point key for the kinds of the labelled cells (`kind => [:dark, :light, …]`)."""
const kind = B.kind
const cluster = B.cluster
export kind, cluster

end

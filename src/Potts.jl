"""
Symbolic cellular Potts modeling on ModelingToolkit and SciML.

Models are authored as a global Hamiltonian with `@potts_model` (see
`docs/design/AUTHORING.md`); `mtkcompile` derives the energy change of a copy and
`PottsProblem` generates the `CorePotts` functions. The numerical layer is re-exported.
"""
module Potts

using Adapt: Adapt
# The bare `using CorePotts` only backs the re-export loop below (`export $name` needs each
# exported CorePotts name to resolve in Potts); every name Potts itself uses is listed
# explicitly on the next line (ExplicitImports, P6.0j).
using CorePotts
using CorePotts: CorePotts, Footprint, Lattice, Periodic, Closed, Moore, init, saturating, saturating_linear
using KernelAbstractions: KernelAbstractions
using ModelingToolkitBase: ModelingToolkitBase, Differential, Equation, Pre, @named, mtkcompile, extend
using PrecompileTools: PrecompileTools
using RuntimeGeneratedFunctions: RuntimeGeneratedFunctions
using SciMLBase: SciMLBase
using StableRNGs: StableRNG
using StaticArrays: SMatrix, SVector
using SymbolicUtils: SymbolicUtils
using Symbolics: Symbolics, Num
using SymbolicIndexingInterface: SymbolicIndexingInterface

RuntimeGeneratedFunctions.init(@__MODULE__)

const t = ModelingToolkitBase.t_nounits
const D = ModelingToolkitBase.D_nounits

for name in names(CorePotts)
    (name === :CorePotts || !Base.isexported(CorePotts, name)) || @eval export $name
end
export @potts_model, @named, PottsSystem, CompiledPottsSystem, PottsProblem, mtkcompile, extend,
    total_energy, energy_change, generated_code, parameters, variables, observe, Adaptive

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

include("layouts.jl")
export AbstractLayout, Tiling, Scattered, Frame, InsertUntil, overlay, layout, layout_tally
# the layout extension API: `Potts.paint!(σ, kinds, l, lat::LatticeSpec)`, `core_lattice(lat)`
public paint!, core_lattice, LatticeSpec

end

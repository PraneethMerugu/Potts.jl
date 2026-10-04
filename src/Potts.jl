"""
Symbolic cellular Potts modeling on ModelingToolkit and SciML.

Models are authored as a global Hamiltonian with `@potts_model` (see
`docs/design/AUTHORING.md`); `mtkcompile` derives the energy change of a copy and
`PottsProblem` generates the `CorePotts` functions. The numerical layer is re-exported.
"""
module Potts

# The bare `using CorePotts` only backs the re-export loop below (`export $name` needs each
# exported CorePotts name to resolve in Potts); every name Potts itself uses is listed
# explicitly on the next line (ExplicitImports, P6.0j).
using CorePotts
using CorePotts: CorePotts, Footprint, Lattice, PottsProblem, Periodic, Closed, Moore, init, saturating, saturating_linear
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
export @potts_model, @named, PottsSystem, CompiledPottsSystem, mtkcompile, extend,
    total_energy, energy_change, generated_code, parameters, variables, observe, Adaptive, ExplicitEuler, RK4

include("seeds.jl")
include("vocabulary.jl")
include("system.jl")
include("macro.jl")
include("lower.jl")
include("schedule.jl")
include("compile.jl")
include("solvers.jl")
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
export AbstractLayout, Tiling, Scattered, Frame, InsertUntil, overlay, layout
# the layout extension API (D-091): `Potts.paint!(op::LayoutState, l, lat)`, the paint-state
# accessors and the lattice queries (`size(lat)` is Base's); `core_lattice(lat)`
public paint!, LayoutState, new_cell!, assign!, owner, kindof, ncells, record!, isperiodic, indomain,
    core_lattice, LatticeSpec
# a named set of kinds declared in `@kinds` (`g = (k, …)`); for programmatic `PottsSystem(; kind_classes)`
public KindClass

end

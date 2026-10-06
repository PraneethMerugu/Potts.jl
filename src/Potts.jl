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
using ConstructionBase: ConstructionBase
using CorePotts
using CorePotts: CorePotts, Footprint, Lattice, embed, PottsProblem, Periodic, Closed, Moore, init, solve, saturating, saturating_linear
using JumpProcesses: JumpProcesses
using KernelAbstractions: KernelAbstractions
using LinearAlgebra: Symmetric, eigen
using ModelingToolkitBase: ModelingToolkitBase, Differential, Equation, Pre, @named, mtkcompile, extend, complete
using PrecompileTools: PrecompileTools
using RuntimeGeneratedFunctions: RuntimeGeneratedFunctions
using SciMLBase: SciMLBase
using StableRNGs: StableRNG
using StaticArrays: SMatrix, SVector
using SymbolicUtils: SymbolicUtils
using Symbolics: Symbolics, Num
using SymbolicIndexingInterface: SymbolicIndexingInterface
# Last, on purpose (D-138): GeometryBasics' `OffsetInteger` `convert` methods invalidate the
# symbolic stack's cached code when GeometryBasics loads before it (`using Potts` 4.8 → 6.2 s;
# 4.9 s from here). Later dependencies go above this line.
using GeometryBasics: HyperSphere, Circle, Sphere, Point

RuntimeGeneratedFunctions.init(@__MODULE__)

const t = ModelingToolkitBase.t_nounits
const D = ModelingToolkitBase.D_nounits

for name in names(CorePotts)
    (name === :CorePotts || !Base.isexported(CorePotts, name)) || @eval export $name
end
export @potts_model, @named, PottsSystem, CompiledPottsSystem, mtkcompile, extend, complete,
    total_energy, energy_change, generated_code, parameters, variables, observe, Adaptive, ExplicitEuler, RK4

include("seeds.jl")
include("draws.jl")
include("vocabulary.jl")
include("system.jl")
include("macro.jl")
include("lower.jl")
include("schedule.jl")
include("compile.jl")
include("contact_folds.jl")
include("solvers.jl")
include("codegen.jl")
include("problem.jl")
include("analysis.jl")
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
# shapes and point patterns (D-138): GeometryBasics' round shapes and `Point` (the same
# bindings Makie re-exports), the lattice centre, random sites and the Voronoi layer
export HyperSphere, Circle, Sphere, Point, Center, RandomPoints, Voronoi
# TST-style seeding (D-141): seed-and-grow and host-side divisions
export Eden, Splits
public points, layer_rng
# the layout extension API (D-091): `Potts.paint!(op::LayoutState, l, lat)`, the paint-state
# accessors and the lattice queries (`size(lat)` is Base's); `core_lattice(lat)`
public lattice, paint!, LayoutState, new_cell!, assign!, owner, kindof, ncells, record!, isperiodic, indomain,
    core_lattice, LatticeSpec
# measurements of a state beside `total_energy` (D-139)
public boundary_lengths, anneal
# a named set of kinds declared in `@kinds` (`g = (k, …)`); for programmatic `PottsSystem(; kind_classes)`
public KindClass

# The session token (D-130, `_SESSION_TOKEN` in solvers.jl), drawn at every load: `__init__`
# runs when Potts loads, never into the precompile image. The draw is a child task's: the
# caller's own `rand` stream is unchanged by loading Potts, but spawning the task advances the
# caller's task-split state, so tasks spawned afterwards get other seeds than without Potts.
# When the caller seeded the global RNG before loading, the draw repeats across sessions and
# the token's uniqueness rests on `time_ns()` and `getpid()`.
function __init__()
    draw = fetch(schedule(Task(() -> rand(UInt64))))
    _SESSION_TOKEN[] = hash((draw, time_ns(), getpid()))
    return nothing
end

end

"""
Symbolic cellular Potts modeling on ModelingToolkit and SciML.

Models are authored as a global Hamiltonian with `@potts_model` (see
`docs/design/AUTHORING.md`); `mtkcompile` derives the energy change of a copy and
`PottsProblem` generates the `CorePotts` functions. The numerical layer is re-exported.
"""
module Potts

# The bare `using CorePotts` only backs the re-export loop below (`export $name` needs each
# exported CorePotts name to resolve in Potts); every name Potts itself uses is listed
# explicitly on the next line (ExplicitImports).
using ADTypes: AutoFiniteDiff
using ConstructionBase: ConstructionBase
using CorePotts
using CorePotts: CorePotts, Footprint, Lattice, embed, PottsProblem, Periodic, Closed, Moore, init, solve, step!, saturating, saturating_linear,
    ownership
# the compile workload's `@potts_model` body names these (precompile.jl)
using CorePotts: Metropolis, RandomPlane
using JumpProcesses: JumpProcesses
using KernelAbstractions: KernelAbstractions
using LatticeFields: LatticeFields, isfatal
using LatticeFields.Problems: ExplicitEuler, ExplicitMap, LatticeNewton, BackwardEuler, CrankNicolson, BDF2, QuasiSteady, FieldGroups, AbstractFieldAlgorithm,
                             substep_counts, steady_fields, field_series, field_report
using LatticeFields.Solvers: LatticePCG, LatticeGMRES, LatticeMultigrid, LatticeBlockSolve, VCycle
using LatticePDE: LatticePDE, laplacian, value_at, ismember, Coarse
using LinearAlgebra: Symmetric, eigen, svdvals
using ModelingToolkitBase: ModelingToolkitBase, Differential, Equation, Pre, @named, mtkcompile, complete, compose, extend,
    t_nounits as t
using PrecompileTools: PrecompileTools
using RuntimeGeneratedFunctions: RuntimeGeneratedFunctions
using SciMLBase: SciMLBase
using SciMLStructures: SciMLStructures
using SimpleNonlinearSolve: SimpleNonlinearSolve, SimpleNewtonRaphson
using StableRNGs: StableRNG
using StaticArrays: StaticArrays, SMatrix, SVector
using SymbolicUtils: SymbolicUtils
using Symbolics: Symbolics, Num
using SymbolicIndexingInterface: SymbolicIndexingInterface
# Last, on purpose (D-138): GeometryBasics' `OffsetInteger` `convert` methods invalidate the
# symbolic stack's cached code when GeometryBasics loads before it (`using Potts` 4.8 → 6.2 s;
# 4.9 s from here). Later dependencies go above this line.
using GeometryBasics: HyperSphere, Point

RuntimeGeneratedFunctions.init(@__MODULE__)

const D = ModelingToolkitBase.D_nounits

for name in names(CorePotts)
    (name === :CorePotts || !Base.isexported(CorePotts, name)) || @eval export $name
end
export @potts_model, @named, PottsSystem, CompiledPottsSystem, mtkcompile, compose, extend,
    total_energy, energy_change, generated_code, observe, Adaptive, ExplicitEuler, ExplicitMap,
    BackwardEuler, CrankNicolson, BDF2, QuasiSteady, LatticeNewton, FieldGroups, substep_counts, steady_fields, field_series, field_report, LatticePCG, LatticeGMRES, LatticeMultigrid, LatticeBlockSolve, Coarse
public VCycle                               # `LatticeMultigrid(; cycle = VCycle(ν₁, ν₂))` (not exported: a short name)
# the declared parameters and variables of a model (MTK's `parameters` lists the compiled ones);
# `RK4` (OrdinaryDiffEq exports a different `RK4`)
public declared_parameters, declared_variables, RK4

"""
    PottsCompileError <: Exception

Thrown when lowering or compiling a `PottsSystem` rejects a model expression or assignment
that cannot execute in the generated CPM kernels.
"""
struct PottsCompileError <: Exception
    msg::String
end
Base.showerror(io::IO, e::PottsCompileError) = print(io, e.msg)
public PottsCompileError

"""
    PottsSolveError <: Exception

Thrown when `anneal` stops with non-finite dynamics and cannot return a state.
"""
struct PottsSolveError <: Exception
    msg::String
end
Base.showerror(io::IO, e::PottsSolveError) = print(io, e.msg)
public PottsSolveError

include("seeds.jl")
include("draws.jl")
include("vocabulary.jl")
include("system.jl")
include("macro.jl")
include("lower.jl")
include("schedule.jl")
include("compile.jl")
include("sweep_spec.jl")
include("contact_folds.jl")
include("solvers.jl")
include("fields.jl")
include("field_components.jl")
include("field_vocabulary.jl")       # `using Potts.Fields`
include("codegen.jl")
include("problem.jl")
include("analysis.jl")
include("observed.jl")
include("compose.jl")
include("components.jl")
include("odes.jl")
include("initialization.jl")
include("precompile.jl")

"""Operating-point key for the kinds of the labeled cells (`kind => [:dark, :light, …]`)."""
const kind = B.kind
const cluster = B.cluster
export kind, cluster

include("layouts.jl")
# the initial-state vocabulary is opt-in: `using Potts.Layouts`
public Layouts
"""
    Potts.Layouts

The initial-state vocabulary: `layout` and its layers (`Tiling`, `Scattered`, `Frame`,
`InsertUntil`, `overlay`), shapes and point patterns (GeometryBasics' `HyperSphere`, `Circle`,
`Sphere` and `Point`, the lattice `Center`, `RandomPoints`, `Voronoi`), seed-and-grow and
divisions (`Eden`, `Splits`), and strict shapes, filled regions, translated copies and
compartment groups (`Interior`, `Fill`, `Objects`, `Group`). `using Potts.Layouts` brings
these names into scope; each layout word is also public as `Potts.name`.
"""
module Layouts

    using ..Potts: AbstractLayout, Tiling, Scattered, Frame, InsertUntil, overlay, layout, Center, RandomPoints,
        Voronoi, Eden, Splits, Interior, Fill, Objects, Group
    using GeometryBasics: HyperSphere, Circle, Sphere, Point

    export AbstractLayout, Tiling, Scattered, Frame, InsertUntil, overlay, layout
    export HyperSphere, Circle, Sphere, Point, Center, RandomPoints, Voronoi
    export Eden, Splits
    export Interior, Fill, Objects, Group

end
# the layout words, also public on Potts; `set_column!` is the custom layer's seam for
# per-cell columns
public AbstractLayout, Tiling, Scattered, Frame, InsertUntil, overlay, layout, Center, RandomPoints, Voronoi,
    Eden, Splits, Interior, Fill, Objects, Group
public set_column!
public points, layer_rng
# the layout extension API (D-091): `Potts.paint!(op::LayoutState, l, lat)`, the paint-state
# accessors and the lattice queries (`size(lat)` is Base's); `core_lattice(lat)`
public lattice, paint!, LayoutState, new_cell!, assign!, owner, kindof, ncells, record!, isperiodic, indomain,
    core_lattice, LatticeSpec
# measurements of a state beside `total_energy` (D-139)
public boundary_lengths, anneal
# a named set of kinds declared in `@kinds` (`g = (k, …)`); for programmatic `PottsSystem(; kind_classes)`
public KindClass
# the sweep as MTK-visible metadata (D-160): the Hamiltonian terms, the drives and the payload
# read with `ModelingToolkitBase.getmetadata(Potts.inner(sys), Potts.PottsSweepSpec, default)`
public hamiltonian, drives, PottsSweepSpec
# the container around MTK's System: the inner System, the field PDESystem, the payload; wrap_system
# and components (`compose` and `extend` are MTK's, exported above); the field bindings
public inner, fields, part, component, wrap_system, PottsPart, FieldBinding, resolve
# a plain PDESystem as the model's fields, its inputs bound to CPM expressions; the
# current values of those inputs, for SciML solvers of the PDESystem
public couple, field_inputs, is_kind
# the metadata key a model quantity carries (`[potts_entity = …]`) and its reader
public PottsEntity, get_potts_entity
# the model's cell and model ODEs as the MTK systems `mtkcompile` produced
public ode_system
# the model's cell and model initialization as MTK systems (`@initialization_equations`, D-170)
public initialization_system
# the update rules as written (D-164), with their cadence value and the contact-fold term
# they print
public updates, Every, count_contacts

# The session token (D-130, `_SESSION_TOKEN` in solvers.jl), made at every load: `__init__`
# runs when Potts loads, never into the precompile image. It reads the clock and the process
# id, never a random number generator: loading Potts leaves the caller's global and
# task RNG states as they were, so a seeded run draws the same numbers with or without it.
function __init__()
    _SESSION_TOKEN[] = hash((time_ns(), getpid(), objectid(Ref(0))))
    return nothing
end

end

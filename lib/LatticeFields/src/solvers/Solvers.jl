"""
    LatticeFields.Solvers

Implicit field solves: the cell-centered multigrid hierarchy with rule M and
the Any fold, the bottom V-cycle with a fixed-degree Chebyshev coarsest solve, PCG with one
fixed V(2,2) Chebyshev cycle as preconditioner, the stationary budgeted path, the residual
sentinel and `init = :steady`. Launch plans follow the Schedule/Exec contract.

The public interface (the coupled and standalone `linsolve = …` vocabulary and the field solvers'
building block): the operator `CellOperator` (faces, shift, masks with a value or a value
field, face-Dirichlet and Robin faces), the solver `FieldSolver` with `rebuild!`, `lift!`,
`solve!`, `steady!`, `tangent!`, `set_coefficients!`, the readers `field`, `solution_key`,
`solver_solution`, `scalars`, `iterations`, `sentinel`, and the inner solvers, LinearSolve.jl
algorithms `LatticePCG`, `LatticeGMRES`, `LatticeMultigrid` (stationary multigrid and `precs`
preconditioner), `VCycle`, `LatticeBlockSolve`, and `BoundOperator`, a field's operator as a
`LinearProblem`'s `A`. Messages name the user's field (`CellOperator(…; name)`).
"""
module Solvers

using ..IR: IR, AND, Access, BOOL, Ex, F32, F64, Grid, I32, INSIDE, INSIDE_OP, degenerate,
    KernelBuilder,
    Level, NOT, Program, ProgramBuilder, REAL, RUNTIME, Sel, Space, U8, access!,
    add!, cast,
    compare!, constant, constant!, eq, field!, fieldid, gate!, irerror, juliatype,
    kernel, leveldims, load, ncomp, node!, nsites, param, program, reduce!,
    restrict,
    runtime, select, store, table, table!
using ..Compile: LOWERING, TIME_SLOT, CompileOptions, body_function, compile_kernel,
    derive_function, semantic
using ..Schedule: Schedule, REDUCE_PHASES, WG, reduce_lds, reduction_blocks, supports
using ..Exec: Exec
using KernelAbstractions: KernelAbstractions as KA
using LinearSolve: LinearSolve
using SciMLBase: SciMLBase
using CommonSolve: CommonSolve
using LinearAlgebra: LinearAlgebra
using SparseArrays: SparseArrays
using Krylov: Krylov
using SciMLOperators: SciMLOperators

public CellOperator, FieldSolver, LatticePCG, LatticeGMRES, LatticeMultigrid, LatticeBlockSolve, BoundOperator,
    VCycle, RuleWeights, robin_parts, rebuild!,
    lift!, solve!, steady!, tangent!, set_coefficients!, field, solution_key, solver_solution,
    scalars, iterations, sentinel

include("levels.jl")
include("kernels.jl")
include("solve.jl")
include("linearsolve.jl")
include("exec.jl")

end # module Solvers

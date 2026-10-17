"""
    LatticeFields.Solvers

Implicit field solves (v3 §6.3–§6.4): the cell-centered multigrid hierarchy with rule M and
the Any fold, the bottom V-cycle with a fixed-degree Chebyshev coarsest solve, PCG with one
fixed V(2,2) Chebyshev cycle as preconditioner, the stationary budgeted path, the residual
sentinel and `init = :steady`. Launch plans follow the Schedule/Exec contract.
"""
module Solvers

using ..IR: IR, AND, Access, BOOL, Ex, F32, F64, Grid, I32, INSIDE, INSIDE_OP,
            KernelBuilder,
            Level, NOT, Program, ProgramBuilder, REAL, RUNTIME, Sel, Space, U8, access!,
            add!, cast,
            compare!, constant, constant!, eq, field!, fieldid, gate!, irerror, juliatype,
            kernel, leveldims, load, ncomp, node!, nsites, param, program, reduce!,
            restrict,
            runtime, select, store, table, table!
using ..Compile: LOWERING, TIME_SLOT, CompileOptions, body_function, compile_kernel,
                 derive_function, semantic
using ..Schedule: REDUCE_PHASES, WG, reduce_lds, reduction_blocks, supports

include("levels.jl")
include("kernels.jl")
include("solve.jl")

end # module Solvers

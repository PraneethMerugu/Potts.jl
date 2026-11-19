"""
    LatticeFields

Fields on lattices: the execution layer, IR, compiler passes and schedule of the field
compiler (v3 §2–§4). This file holds only `include` lines; each layer is a submodule in its
own directory.

  - [`Exec`](@ref LatticeFields.Exec): the host executor, the generic device wrapper,
    prebuilt launches, plan walks and parallel compile. CorePotts runs its kernels through it.
  - `IR`: the host-side field IR and its builder.
  - `Compile`: the passes from the semantic normal form to emitted bodies.
  - `Schedule`: step order, cost-model fusion and launch descriptions.
  - `Solvers`: implicit field solves (rule-M multigrid, PCG with a V(2,2) Chebyshev cycle,
    the stationary budgeted path).
  - `Problems`: stores, the binding of launch descriptions to `Exec` launches, and problems.
"""
module LatticeFields

"""
    isfatal(e) -> Bool

True for fatal runtime exceptions (`InterruptException`, `StackOverflowError`,
`OutOfMemoryError`) that must always be rethrown rather than swallowed by a broad
probe or diagnostic catch.
"""
isfatal(e) = e isa Union{InterruptException, StackOverflowError, OutOfMemoryError}

include("exec.jl")
include("ir/IR.jl")
include("compile/Compile.jl")
include("schedule/Schedule.jl")
include("solvers/Solvers.jl")
include("problems/Problems.jl")

public isfatal, Exec, IR, Compile, Schedule, Solvers, Problems

end # module LatticeFields

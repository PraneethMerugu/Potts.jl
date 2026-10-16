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
"""
module LatticeFields

include("exec.jl")
include("ir/IR.jl")
include("compile/Compile.jl")
include("schedule/Schedule.jl")

public Exec, IR, Compile, Schedule

end # module LatticeFields

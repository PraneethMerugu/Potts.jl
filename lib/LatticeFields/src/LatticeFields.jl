"""
    LatticeFields

Fields on lattices: the execution layer, IR, compiler, schedules, solvers and problems of
the field compiler (v3 design). This version holds the execution layer only,
[`Exec`](@ref LatticeFields.Exec): the host executor, the generic device wrapper, prebuilt
launches, plan walks and parallel compile. CorePotts runs its kernels through it.
"""
module LatticeFields

include("exec.jl")

public Exec

end # module LatticeFields

"""
    LatticeFields.Schedule

Step order (topological, Jacobi inside cycles), cost-model fusion (v3 §4.3), buffer binding,
launch descriptions for Exec and the field report.
"""
module Schedule

using ..IR: IR, FULL, Kernel, KernelBuilder, LOAD, CONST, PARAM, COORD, RUNTIME,
            INSIDE_OP, MASKED, Program, Reduction, Store, args, buildkeys, copy_node!,
            finish, irerror,
            lanebytes, nsites, with_kernels, cast!, isfloat, REAL, leveldims
using ..Compile: CompiledKernel, CompileOptions, LOWERING, compile_kernel, legality, reads,
                 writes, zero_offset
using KernelAbstractions: KernelAbstractions, @index, @kernel, @localmem, @synchronize

public plan

include("contract.jl")
include("cost.jl")
include("plan.jl")
include("workgroup.jl")

end # module Schedule

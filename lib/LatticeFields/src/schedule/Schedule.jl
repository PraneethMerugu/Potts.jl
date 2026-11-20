"""
    LatticeFields.Schedule

Step order (topological, Jacobi inside cycles), cost-model fusion, buffer binding,
launch descriptions for Exec and the fusion report.
"""
module Schedule

using ..IR: IR, FULL, Kernel, KernelBuilder, LOAD, CONST, PARAM, COORD, RUNTIME,
            INSIDE_OP, MASKED, Program, Reduction, Store, args, buildkeys, copy_node!,
            finish, irerror,
            lanebytes, nsites, with_kernels, cast!, isfloat, REAL, leveldims
using ..Compile: CompiledKernel, CompileOptions, LOWERING, compile_kernel, legality, reads,
                 writes, zero_offset
using KernelAbstractions: KernelAbstractions, @index, @kernel, @localmem, @synchronize
using ..Exec: Exec
using Polyester: @batch

public plan, fusion_report

include("contract.jl")
include("cost.jl")
include("plan.jl")
include("workgroup.jl")

end # module Schedule

"""
    LatticeFields.IR

The host-side field IR (v3 §3): grids, levels, placements, fields, tables, masks, flags,
accesses, hash-consed kernel DAGs, boundary rules and storage lanes; the interning builder,
the printer and the structural verifier.
"""
module IR

# The front-end contract (LatticePDE lowers through these): the data model, the program
# builder and the interning kernel builder.
public Grid, Program, ProgramBuilder, KernelBuilder, Space, Access, Sel, Coef, FaceRule,
       NodeValueRule, MaskDecl, Scalar, Bpolicy, Op, Epoch, field!, rule!, kernel, add!,
       program, node!, Ex, constant!, param!, runtime!, coord!, table!, call!, cast!, arith!,
       compare!, select!, cond!, load!, access!, store!, isfloat, print_program, CALLS,
       F16, F32, F64, U8, I32, U32, REAL, BOOL, RESOLVE, INSIDE, ZERO, CLAMP, STATIC, PERSIGMA,
       PERSTEP, INNER, ADD, MUL, NEG, DIV, FMA, MIN, MAX, ABS, POWI, SQRT, EXP, LOG, EQ, LT, LE,
       AND, OR, NOT, XOR, SELECT, COND, CAST, INSIDE_OP

include("types.jl")
include("builder.jl")
include("program.jl")
include("printer.jl")
include("verify.jl")

end # module IR

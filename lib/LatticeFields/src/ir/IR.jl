"""
    LatticeFields.IR

The host-side field IR: grids, levels, placements, fields, tables, masks, flags,
accesses, hash-consed kernel DAGs, boundary rules and storage lanes; the interning builder,
the printer and the structural verifier.
"""
module IR

# The front-end contract (LatticePDE lowers through these): the data model, the program
# builder and the interning kernel builder.
public Grid, Program, IRError, fieldid, ProgramBuilder, KernelBuilder, Space, Access, Sel, Coef, FaceRule,
       degenerate, FACE_RTOL, sitecoefs,
       NodeValueRule, MaskDecl, Scalar, Bpolicy, Op, Epoch, field!, rule!, kernel, add!,
       program, node!, Ex, constant!, param!, runtime!, coord!, table!, call!, cast!, arith!,
       compare!, select!, cond!, load!, access!, store!, isfloat, juliatype, print_program, CALLS,
       F16, F32, F64, U8, I32, U32, REAL, BOOL, RESOLVE, INSIDE, ZERO, CLAMP, STATIC, PERSIGMA,
       PERSTEP, INNER, ADD, MUL, NEG, DIV, FMA, MIN, MAX, ABS, POWI, SQRT, EXP, LOG, EQ, LT, LE,
       AND, OR, NOT, XOR, SELECT, COND, CAST, INSIDE_OP, Geometry, CUBIC, HEX, DomainEdgeRule, Level,
       RESTRICT, FULL, leveldims, nsites

include("types.jl")
include("builder.jl")
include("program.jl")
include("printer.jl")
include("verify.jl")

end # module IR

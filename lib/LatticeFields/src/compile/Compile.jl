"""
    LatticeFields.Compile

The compiler passes: legality, fold, semantic boundary resolution (passes 0–2,
the semantic normal form and fingerprint source), then POWI and parameter hoisting, types,
index lowering and emission (passes 3–6, with the debug emission flag), and the interval
coefficient evaluator.
"""
module Compile

using RuntimeGeneratedFunctions: RuntimeGeneratedFunctions, RuntimeGeneratedFunction,
    drop_expr
using SHA: sha1
using ..Exec: Exec
using ..IR: IR, Access, BOOL, CALL, CAST, CLAMP, COND, CONST, COORD, Coef, DIV,
    DomainEdgeRule,
    ELEMENT_SUM, EQ, EXP, F16, F32, F64, FMA, FULL, FaceRule, IDX, INSIDE,
    INSIDE_OP,
    ImmersedRule, Kernel, sitecoefs,
    KernelBuilder, LE, LOAD, LOG, LT, MASKED, MAX, MIN, MUL, NEG, NOT, Node,
    NodeValueRule, OR, Op,
    PARAM, POWI, Program, REAL, RESOLVE, RESTRICT, RESTRICTED, RUNTIME, SELECT,
    SQRT, Scalar, Sel,
    Space, Store, TABLE, XOR, ZERO, ABS, ADD, AND, BITTEST, access!, arith!, args,
    buildkeys,
    compare!, constant!, copy_node!, irerror, isfloat, isinteger_lane, juliatype,
    leveldims, coarsenable,
    loadtype, ncomp, nsites, node!, nodeargs, opname, param!, print_program,
    rebuild,
    remap_access,
    select!, verify, with_kernels, AbstractBoundaryRule, Ex, FieldDecl, FlagDecl,
    MaskDecl, _rulemap, cast!, load!

RuntimeGeneratedFunctions.init(@__MODULE__)

public CompileOptions, semantic, fingerprint_text, fuse_update, fuse_residual, lanecast,
    powi, value_type, primal, withvaltype, promote_dual, lanetype, npartials, dvalue,
    dpartial, dsetpartial, dreplace

include("numbers.jl")
include("semantic.jl")
include("fingerprint.jl")
include("fuse.jl")
include("hoist.jl")
include("emit.jl")
include("lower.jl")
include("interval.jl")

end # module Compile

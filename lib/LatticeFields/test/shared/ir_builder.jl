# Definitions of ir/builder_tests.jl that other test files use.
using LatticeFields.IR: Ex, KernelBuilder, IRError, verify, ADD, MUL, LOAD, REAL, nodeargs,
                        scmp
using LatticeFields.Compile: check_types

"""
A one-kernel program with stores `stores(kb, ids...)`; fields from `decls`.
"""
function tiny(decls, body; periodic = (true, true))
    pb = ProgramBuilder(Grid((4, 3)); periodic, nparams = 1)
    ids = [field!(pb, k; kw...) for (k, kw) in decls]
    kb = kernel(pb)
    body(kb, ids...)
    add!(pb, kb, "k")
    return program(pb)
end

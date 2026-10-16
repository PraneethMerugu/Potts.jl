"""
    LatticeFields.IR

The host-side field IR (v3 §3): grids, levels, placements, fields, tables, masks, flags,
accesses, hash-consed kernel DAGs, boundary rules and storage lanes; the interning builder,
the printer and the structural verifier.
"""
module IR

include("types.jl")
include("builder.jl")
include("program.jl")
include("printer.jl")
include("verify.jl")

end # module IR

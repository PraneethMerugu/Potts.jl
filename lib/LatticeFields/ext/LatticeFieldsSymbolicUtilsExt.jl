# Field reads by a symbolic term (`sol[c]` with `c` an unwrapped term, as `unknowns(sys)`
# returns them): the same reads as by a `Symbol` or a wrapped `Num`.
module LatticeFieldsSymbolicUtilsExt

using LatticeFields: Problems
using SymbolicUtils: BasicSymbolic

Base.getindex(sol::Problems.LatticeSolution, sym::BasicSymbolic) = Problems._lattice_getindex(sol, sym)

end # module LatticeFieldsSymbolicUtilsExt

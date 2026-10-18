# `setp` on an OrdinaryDiffEq integrator of a field program's ODE form names a symbol that is
# no parameter (an expression such as `2k`), as `setp` on the problem does (F1), instead of
# SII's "invalid index: nothing" when the setter runs.
module LatticeFieldsOrdinaryDiffEqCoreExt

using OrdinaryDiffEqCore: ODEIntegrator
using SymbolicIndexingInterface: SymbolicIndexingInterface as SII
using LatticeFields: Problems

const LatticeODEIntegrator = Problems.typewith(ODEIntegrator, :f, Problems.LatticeODEFunction)

function SII.setp(sys::LatticeODEIntegrator, sym; kw...)
    Problems.check_setp(sys, sym)
    return invoke(SII.setp, Tuple{Any, Any}, sys, sym; kw...)
end

end # module LatticeFieldsOrdinaryDiffEqCoreExt

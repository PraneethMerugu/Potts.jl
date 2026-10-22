# `setp` on an OrdinaryDiffEq integrator of a field program's ODE form names a symbol that is
# no parameter (an expression such as `2k`), as `setp` on the problem does (F1), instead of
# SII's "invalid index: nothing" when the setter runs; a value outside a parameter's declared
# bounds is refused when the setter runs, before it is written (F2-14).
module LatticeFieldsOrdinaryDiffEqCoreExt

using OrdinaryDiffEqCore: ODEIntegrator
using SymbolicIndexingInterface: SymbolicIndexingInterface as SII
using LatticeFields: Problems

const LatticeODEIntegrator = Problems.typewith(ODEIntegrator, :f, Problems.LatticeODEFunction)

function SII.setp(sys::LatticeODEIntegrator, sym; kw...)
    Problems.check_setp(sys, sym)
    s = invoke(SII.setp, Tuple{Any, Any}, sys, sym; kw...)
    return function (integ, v)
        kv = sym isa Union{AbstractArray, Tuple} ? collect(zip(sym, v)) : [sym => v]
        Problems.check_bounds(integ.p, SII.symbolic_container(integ.f), kv)   # (the function holds the index)
        return s(integ, v)
    end
end

end # module LatticeFieldsOrdinaryDiffEqCoreExt

# `setp` on an OrdinaryDiffEq integrator of a field program's ODE form names a symbol that is
# no parameter (an expression such as `2k`), as `setp` on the problem does (F1), instead of
# SII's "invalid index: nothing" when the setter runs; a value outside a parameter's declared
# bounds is refused when the setter runs, before it is written (F2-14). A write of an aux field
# is refused in the user's words (F3-00).
module LatticeFieldsOrdinaryDiffEqCoreExt

using OrdinaryDiffEqCore: ODEIntegrator
using SymbolicIndexingInterface: SymbolicIndexingInterface as SII
using LatticeFields: Problems

const LatticeODEIntegrator = Problems.typewith(ODEIntegrator, :f, Problems.LatticeODEFunction)

function SII.setp(sys::LatticeODEIntegrator, sym; kw...)
    Problems.check_setp(sys, sym)
    s = invoke(SII.setp, Tuple{Any, Any}, sys, sym; kw...)
    # (a resolved index, from SII's setter of an array symbol: the symbol's setter checks)
    sym isa Union{Problems.TableSlot, Problems.InputSlot, Integer} && return s
    return function (integ, v)
        kv = sym isa Union{AbstractArray, Tuple} ? collect(zip(sym, v)) : [sym => v]
        p = integ.p                                    # (the function holds the index)
        lp = p isa Problems.LatticeParameters
        Problems.check_bounds(lp ? p.values : p, SII.symbolic_container(integ.f), kv; tables = lp ? p.tables : Problems.rhs_tables(integ.f))
        return s(integ, v)
    end
end

# `integ[K] = v` of an aux field (`K ~ rhs`, observed on the ODE path) is refused in the user's
# words, as on the owned path (SII: "Invalid symbol … for `setsym`")
function SII.setsym(sys::LatticeODEIntegrator, sym)
    Problems.check_aux_write(SII.symbolic_container(sys.f), sym)
    return invoke(SII.setsym, Tuple{Any, Any}, sys, sym)
end

end # module LatticeFieldsOrdinaryDiffEqCoreExt

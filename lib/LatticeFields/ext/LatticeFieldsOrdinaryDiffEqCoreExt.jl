# `setp` on an OrdinaryDiffEq integrator of a field program's ODE form names a symbol that
# is no parameter (an expression such as `2k`), as `setp` on the problem does, instead of
# SII's "invalid index: nothing" when the setter runs; a value outside a parameter's
# declared bounds is refused when the setter runs, before it is written. A write of an aux
# field is refused in the user's words.
module LatticeFieldsOrdinaryDiffEqCoreExt

using OrdinaryDiffEqCore: OrdinaryDiffEqCore, ODEIntegrator, DefaultInit
using LinearAlgebra: UniformScaling
using SciMLBase: SciMLBase
using SymbolicIndexingInterface: SymbolicIndexingInterface as SII
using LatticeFields: Problems

const LatticeODEIntegrator = Problems.typewith(
    ODEIntegrator, :f,
    Problems.LatticeODEFunction
)

function SII.setp(sys::LatticeODEIntegrator, sym; kw...)
    Problems.check_setp(sys, sym)
    s = invoke(SII.setp, Tuple{Any, Any}, sys, sym; kw...)
    # (a resolved index, from SII's setter of an array symbol: the symbol's setter checks)
    sym isa Union{Problems.TableSlot, Problems.InputSlot, Integer} && return s
    return function (integ, v)
        kv = sym isa Union{AbstractArray, Tuple} ? collect(zip(sym, v)) : [sym => v]
        p = integ.p                                    # (the function holds the index)
        lp = p isa Problems.LatticeParameters
        ix = SII.symbolic_container(integ.f)
        Problems.check_bounds(
            lp ? p.values : p, ix, kv; tables = if lp
                p.tables
            else
                Problems.rhs_tables(integ.f)
            end
        )
        s(integ, v)
        # a write is a discrete event: every masked site takes its value now, as a mask
        # value may read the parameter, table or input written (its rate cannot carry the
        # jump)
        lp && Problems.sync_masks!(integ)
        return v
    end
end

# `integ[K] = v` of an aux field (`K ~ rhs`, observed on the ODE path) is refused in the
# user's words, as on the owned path (SII: "Invalid symbol … for `setsym`")
function SII.setsym(sys::LatticeODEIntegrator, sym)
    Problems.check_aux_write(SII.symbolic_container(sys.f), sym)
    return invoke(SII.setsym, Tuple{Any, Any}, sys, sym)
end

# A problem with steady rows `0 ~ rhs` (a mass matrix) starts from a consistent state:
# SciML's default (`CheckInit`) refuses an initial state whose steady rows are not solved,
# so the default here solves them (`Problems.steady_start!`: the owned QuasiSteady solve of
# those rows at t0, on the lattice). `initializealg = BrownFullBasicInit()` or `CheckInit()`
# given to `solve` dispatch to their own methods.
function OrdinaryDiffEqCore._initialize_dae!(
        integ::ODEIntegrator, prob::Problems.LatticeODEProblem, alg::DefaultInit,
        x::Val{true}
    )
    generic = Tuple{ODEIntegrator, SciMLBase.ODEProblem, DefaultInit, Val{true}}
    (
        SciMLBase.has_initializeprob(prob.f) || prob.f.mass_matrix isa UniformScaling ||
            Problems.lattice_metadata(prob) === nothing
    ) &&
        return invoke(OrdinaryDiffEqCore._initialize_dae!, generic, integ, prob, alg, x)
    Problems.steady_start!(integ.u, prob, integ.p, integ.t)
    return nothing
end

end # module LatticeFieldsOrdinaryDiffEqCoreExt

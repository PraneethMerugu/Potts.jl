# Definitions of the old runtests.jl (its preamble) that other test files use.
# LatticePDE vocabulary: registered operators, metadata keys and scans.
# Ported from design probes of the operators, maps and coupling on ModelingToolkitBase 1.77.
using Test, LatticePDE
using ModelingToolkitBase: ModelingToolkitBase as MTKB, @parameters, @variables,
    Differential, PDESystem,
    System, mtkcompile, ODEProblem, unknowns, parameters, ShiftIndex,
    Shift, Pre,
    t_nounits as t, D_nounits as D
using Symbolics: Symbolics, Num, Equation, unwrap, simplify, substitute, get_variables
using SymbolicUtils: SymbolicUtils, iscall, operation, arguments, unwrap_const
using DomainSets: Interval
using SciMLBase: SciMLBase
using LatticeFields: LatticeFields, Problems as LFP
# the byte-identity gate of the update pass runs in every owned `discretize` of the suite
get!(ENV, "LATTICEPDE_CHECK_FUSION", "1")

opof(e) = (u = unwrap(e); iscall(u) ? operation(u) : nothing)
function ops(e)                                     # every operation in the term tree
    out = Any[]
    walk(u) = iscall(u) && (push!(out, operation(u)); foreach(walk, arguments(u)))
    walk(unwrap(e))
    return out
end
has_op(e, f) = any(g -> g === f || (f isa Type && g isa f), ops(e))
dkg(e) = only(filter(f -> f isa DivKGrad, ops(e)))
vars(e) = Set(Symbolics.get_variables(e))
contains_var(e, v) = any(x -> isequal(x, unwrap(v)), vars(e))
# SymbolicUtils 4 wraps literals in Const
symzero(e) = (v = unwrap_const(unwrap(e)); v isa Number && iszero(v))

@parameters x y Dc = 1.0e-3 α = 1.0 ε = 0.5 K0 = 2.0
@parameters Dk[1:3] = [1.0, 2.0, 3.0] J[1:3, 1:3]
@variables c(..) o(..) K(..) kindₛ(..)::Int32 [input = true] vel(..)[1:2] [input = true]
ce, oe, Ke, ke, ve = c(t, x, y), o(t, x, y), K(t, x, y), kindₛ(t, x, y), vel(t, x, y)
dom = [t ∈ Interval(0.0, 1.0), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]

eqs = [
    D(ce) ~ Dc * laplacian(ce) + α * ismember(ke, (2,)) - ε * ce * ismember(ke, (1,)),
    D(oe) ~
        DivKGrad(:harmonic)(Ke, oe) - value_at(Dk, ke) * oe - Advect(Upwind1())(ve[1], oe),
    Ke ~ K0 * (1 + ismember(ke, (2, 3))) + value_at(J, ke, ke),
]
bcs = [ce ~ masked(ke == 3, 0.0), oe ~ masked(ismember(ke, (2, 3)), 1.0)]

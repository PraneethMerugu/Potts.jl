# Definitions of groups_coupling_tests.jl that other test files use.
using SymbolicIndexingInterface: setu, getp

@parameters gkc = 0.1 gDo = 0.3 gKt[1:2] = [1.0, 2.0]
@variables gpc(..) gpo(..) gpq(..)::Int32 [input = true, bounds = (1, 2)]
pce, poe, pqe = gpc(t, x, y), gpo(t, x, y), gpq(t, x, y)

@parameters gk = 300.0
@variables gr1(..) gr2(..)
r1e, r2e = gr1(t, x, y), gr2(t, x, y)
# the rotation c' = −k o, o' = k c (imaginary eigenvalues ±ik)
function rsys()
    return PDESystem(
        [D(r1e) ~ -gk * r2e, D(r2e) ~ gk * r1e], [gr1(0, x, y) ~ 1.0, gr2(0, x, y) ~ 0.0],
        [t ∈ Interval(0.0, 0.1), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)], [t, x, y],
        [
            r1e, r2e,
        ], [gk]; name = :rot
    )
end
# two groups (two algorithms: equal ones would be one group)
function rtwo(n)
    return FieldGroups(
        r1e => ExplicitEuler(; substeps = n), r2e =>
            ExplicitEuler(; substeps = n + 1)
    )
end

# Only groups in a loop of the group read graph are limited.
@parameters gwk = 300.0 gwr = 5.0
@variables gwc(..) gwu(..) gwo(..) gwv(..) gwa(..)
wce, wue, woe, wve, wae = gwc(t, x, y), gwu(t, x, y), gwo(t, x, y), gwv(t, x, y),
    gwa(t, x, y)
const GW_DOM = [t ∈ Interval(0.0, 0.1), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
gwdisc() = LatticeDiscretization(Grid((4, 4)); T = Float64)
gwerr(f) = (e = gerr(f); replace(e, r"\s+" => " "))
# the number after `key` in a message, verbatim (`dt ≤ 0.006666`)
gwnum(e, key) = parse(Float64, match(Regex(key * raw" ([0-9.eE+-]+)"), e).captures[1])

# Definitions of report_tests.jl that other test files use.
using OrdinaryDiffEqTsit5: Tsit5
using SciMLBase: SciMLBase, ReturnCode
using LatticeFields.IR: HEX

@parameters rD = 1e-3 rk = 0.1 ra = 0.3 rb = 0.2
@variables rc(..) ro(..)
rce, roe = rc(t, x, y), ro(t, x, y)
rdom(T) = [t ∈ Interval(0.0, T), x ∈ Interval(0.0, 1.0), y ∈ Interval(0.0, 1.0)]
# the §7.4 problem (a Dirichlet face, a Neumann face, periodic in y)
function rsys(; T = 1.0)
    return PDESystem(
        D(rce) ~ rD * laplacian(rce) - rk * rce,
        [rc(0, x, y) ~ 0.0, rc(t, 0, y) ~ 1.0, Differential(x)(rc(t, 1, y)) ~ 0.0, rc(t, x, 0) ~ rc(t, x, 1)],
        rdom(T), [t, x, y], [rce], [rD, rk]; name = :r)
end
# two fields that read each other (a loop of two groups under `FieldGroups`)
function rsys2(; T = 0.1)
    return PDESystem(
        [D(rce) ~ laplacian(rce) + ra * roe, D(roe) ~ -rb * roe + 0.1 * rce],
        [rc(0, x, y) ~ x * y, ro(0, x, y) ~ 1.0 + x, rc(t, 0, y) ~ rc(t, 1, y), rc(t, x, 0) ~ rc(t, x, 1),
         ro(t, 0, y) ~ ro(t, 1, y), ro(t, x, 0) ~ ro(t, x, 1)],
        rdom(T), [t, x, y], [rce, roe], [ra, rb]; name = :r2)
end
rprob(n; T = 1.0) = discretize(rsys(; T), LatticeDiscretization(Grid((n, n))))
rwarm(ig) = (step!(ig); step!(ig); @allocated step!(ig))   # (a function barrier)
# the text of a report line `label   text` (the first such line)
rline(rep, label) = (l = filter(s -> startswith(s, "  " * rpad(label, 11)), split(rep, '\n')); isempty(l) ? "" : String(l[1]))
rlines(rep, label) = [String(s) for s in split(rep, '\n') if startswith(s, "  " * rpad(label, 11))]

# Hand oracles
@parameters gF = 0.04 gk = 0.06
@variables rq(..) ru(..) rv(..) rcy(..) rcz(..)
rqe, rue, rve, rcye, rcze = rq(t, x, y), ru(t, x, y), rv(t, x, y), rcy(t, x, y), rcz(t, x, y)

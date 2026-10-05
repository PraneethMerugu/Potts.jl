# [Boundary lengths and annealed states](@id manual-analysis)

Two measurements of a state sit next to `total_energy` in Potts: the boundary length split
by kind pair, and the annealed copy of a state. They are public but not exported, so call
them as [`Potts.boundary_lengths`](@ref) and [`Potts.anneal`](@ref). Neither depends on a
particular model. Graner and Glazier use both to quantify cell sorting: the share of the
boundary that is heterotypic, measured on states annealed at ``T = 0``.

## Boundary lengths by kind pair

`Potts.boundary_lengths(prob, u)` counts the bonds of state `u` whose two sites belong to
different owners. A bond is an unordered pair of sites ``\{i, i + o\}``, where ``o`` is an
offset of the problem's contact relation (or of `relation = …`, for example `VonNeumann(1)`).
Periodic axes wrap; closed axes and the edge of a lattice domain do not. Each bond counts
once, with the relation's weight, so an unweighted relation gives integer counts.

Each bond is credited to the kinds of its two owners. The medium has the model's first
kind. The result has a key `(a, b)` for every pair of kinds, with `a` declared no later than
`b` in `@kinds`. Pairs without bonds have the value 0, and `(medium, medium)` is always 0.
Two cells of one kind count under `(k, k)`.

```@example analysis
using Potts, PottsModels

σ, kinds = graner_glazier_state()
prob = PottsProblem(GranerGlazier(; name = :gg), [ownership => σ, kind => kinds], (0, 200); seed = 1)
u = solve(prob, SequentialCPM()).u[end]
L = Potts.boundary_lengths(prob, u)
```

The boundary fractions ``L_{ab} / \sum L`` are the shares of the boundary between each
pair of kinds. Sorting lowers the heterotypic share `(dark, light)`:

```@example analysis
fractions(L) = Dict(k => v / sum(values(L)) for (k, v) in L)
(start = fractions(Potts.boundary_lengths(prob))[(:dark, :light)], now = fractions(L)[(:dark, :light)])
```

## The annealed copy

At a finite temperature the boundary fluctuates. Thermal roughness adds bonds that say
nothing about how the cells are arranged. Graner and Glazier therefore measure on an
annealed copy of each displayed state: the copy dynamics run at ``T = 0`` for a few MCS,
which removes the roughness without moving cells past each other. The run itself continues
from the unannealed state.

`Potts.anneal(prob, u; mcs, seed = 0, alg = SequentialCPM())` returns that copy: `u` after
`mcs` MCS of the problem's copy dynamics with the copy temperature 0 for every proposal,
whatever the model's temperature expression (a parameter, `3θ`, a per-kind table). Everything
else is the run's own: the parameters, the lattice and relations, the proposal, the
acceptance law and the full ``\Delta H``, drives included. With the built-in laws
(`Metropolis`, `Barker`) a copy at ``T = 0`` is accepted when ``\Delta H`` is below the
law's offset, and with probability ½ when it equals it; a custom law receives temperature 0
and follows its own rule.

Only copy attempts run. Before each MCS the derived quantities the energies read are
refreshed (integrals and population folds such as `mean(volume for c in cells)`), as in a
run. Other MCS phases, rules, updates, lifecycle events, ODE and field steps do not run, so
every other variable keeps its value; an energy that reads a cell variable maintained by an
update block sees it frozen at `u`'s value. `u` and `prob` are not modified, and the same
arguments give the same result. A non-finite ``\Delta H`` stops the dynamics, as in a run,
and `anneal` then throws an error instead of returning a partial state.

```@example analysis
annealed = [Potts.anneal(prob, u; mcs = 32, seed = s) for s in 1:4]
(unannealed = sum(values(L)),
 annealed = [sum(values(Potts.boundary_lengths(prob, a))) for a in annealed],
 heterotypic = [fractions(Potts.boundary_lengths(prob, a))[(:dark, :light)] for a in annealed])
```

For a model without drives and with acceptance offset 0, like `GranerGlazier`, an accepted
copy at ``T = 0`` never raises the energy, so the annealed copy's energy is no higher than
that of the state it started from. A drive, a positive offset or a custom law can accept
copies that raise ``H``.

```@example analysis
(H = total_energy(prob, u), annealed = total_energy.(Ref(prob), annealed))
```

With `alg = CheckerboardCPM()` the parallel sweep anneals the copy instead. Graner and
Glazier anneal for 2 of their MCS, which is 32 MCS of `GranerGlazier` (see its docstring).

## The energy identity

The boundary lengths are the exact decomposition of the contact term of `total_energy`.
For a model whose only energy is `contacts => J[kind, kind′]`,
``\sum_{(a, b)} J_{ab} L_{ab} = H``. This is a useful check of a measurement script:

```@example analysis
@potts_model ContactOnly begin
    @kinds medium A B
    @parameters J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    @lattice Lattice((20, 20); boundary = Closed(), neighborhood = Moore(1))
    @energy contacts => J[kind, kind′]
    @sweep Metropolis(; temperature = 1.0)
end

lab = zeros(Int32, 20, 20)
lab[3:9, 3:9] .= 1; lab[10:16, 3:9] .= 2; lab[6:14, 11:17] .= 3
contact = PottsProblem(ContactOnly(; name = :c), [ownership => lab, kind => [:A, :B, :A]], (0, 10))
J = Dict((:medium, :medium) => 0, (:medium, :A) => 16, (:medium, :B) => 16,
    (:A, :A) => 2, (:A, :B) => 11, (:B, :B) => 14)
Lc = Potts.boundary_lengths(contact)
(ΣJL = sum(J[k] * v for (k, v) in Lc), H = total_energy(contact))
```

With a weighted contact relation (`Weighted(Moore(1), w)` and
`contacts => weight * J[kind, kind′]`), the lengths carry the weights and the identity
still holds.

Fits, graph analysis and other measurements of saved states are plain Julia; see
`PottsModels.Analysis` in the [API](@ref api).

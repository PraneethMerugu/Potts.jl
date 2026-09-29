# Authoring surface specification

The user-facing language of the rewritten Potts. Principles:

1. **Author the Hamiltonian.** Users write `H` as sums over domains; the compiler derives
   ΔH. Named terms (`Volume`, …) are one-line library functions, not special objects.
2. **Coexist with ModelingToolkit.** A Potts model is an `AbstractSystem`; parameters,
   variables, equations, `Pre`, `Differential`, events, `compose`/`extend`, `@named`,
   `mtkcompile`, `remake`, SymbolicIndexingInterface and `EnsembleProblem` behave as in
   MTK. PDEs and ODEs are MTK equations; Potts only adds lattice operators and scopes.
3. **Dimension-generic and neighborhood-generic.** 1D, 2D and 3D lattices, per-axis
   boundaries and spacing, and neighborhoods of any order, are first class.
4. **Readable names.** Renames from the current packages are listed in §9.

---

## 1. A complete model

```julia
using Potts

@potts_model Sorting begin
    @structural_parameters begin
        lattice = (72, 72)
    end
    @kinds medium dark light
    @parameters begin
        λ  = 1.0
        V₀ = 40.0
        T  = 10.0
        J[kind, kind] = [0 16 16; 16 2 11; 16 11 14]
    end
    @lattice Lattice(lattice; boundary = Periodic(), neighborhood = Moore(1))
    @energy begin
        cells(dark, light) => λ * (volume - V₀)^2
        contacts           => J[kind, kind′]
    end
    @sweep Metropolis(; temperature = T, attempts_per_site = 16)
end

@named sys = Sorting()
prob = PottsProblem(sys, [ownership => labels, kind => kinds], (0, 100); seed = 1)
sol  = solve(prob, SequentialCPM())
sol[count(dark)]                    # symbolic indexing (SII)
sol[100][volume]                    # cell quantities at MCS 100
plot(sol, 100)                      # MakiePotts recipe
```

`@potts_model` mirrors `@mtkmodel`: a block of sections that produce a
`PottsSystem <: ModelingToolkitBase.AbstractSystem`. Everything the macro does is also
available as plain constructors (`PottsSystem(energies, equations, …; name)`); the macro
is sugar.

---

## 2. Sections

| Section | Purpose | MTK analogue |
|---|---|---|
| `@structural_parameters` | values baked into generated code (lattice size, orders) | same |
| `@kinds` | cell kinds; the first is the medium (kind 0); `[frozen]` marks obstacles | — |
| `@parameters` | numeric parameters, incl. kind-indexed arrays `J[kind, kind]` | same |
| `@variables` | state with a **scope** in the signature: `x(site)`, `x(cell)`, `x(model)`, `c(field)`, `e(edge)` | `@variables`, scope is Potts |
| `@lattice` | `Lattice(dims; boundary, neighborhood, spacing)` | — |
| `@energy` | Hamiltonian terms as `domain => expression` pairs | — |
| `@drive` | non-energetic proposal biases (`copy => expr`) | — |
| `@constraint` | hard proposal constraints | — |
| `@equations` | differential equations (`D(x) ~ …`, `∂t`) for fields, per-cell ODEs, model ODEs | same |
| `@before_mcs`, `@after_mcs`, `@on_copy` | discrete updates as equations with `Pre` | discrete events |
| `@divide`, `@retire`, `@create`, `@transition` | lifecycle rules | — |
| `@relationship`, `@link`, `@unlink` | cell–cell edges | — |
| `@components` | MTK subsystems (ODE/DAE) coupled to the model | same |
| `@observed` | derived quantities | `observed` |
| `@sweep` | protocol: `Metropolis(; temperature, attempts_per_site)` | solver options |

---

## 3. Lattices and neighborhoods

```julia
@lattice Lattice((128, 128, 64);
    boundary     = (Periodic(), Periodic(), Closed()),   # per axis, or one for all
    spacing      = (1.0, 1.0, 2.0),                       # anisotropic voxels
    neighborhood = Moore(2))                              # default relation for `contacts`
```

- Dimension comes from `dims`; all generated code is `N`-generic. 1D, 2D and 3D are
  tested; nothing in the compiler assumes `N == 2`.
- **Neighborhoods** are relations with an order or radius:
  - `Moore(k)`: Chebyshev distance ≤ k (order 1 = 8 neighbours in 2D, 26 in 3D)
  - `VonNeumann(k)`: Manhattan distance ≤ k
  - `Ball(r)`: Euclidean distance ≤ r, in lattice spacing units
  - `Shell(k)`: exactly order k (CompuCell3D "neighbor order" semantics)
  - `Stencil([(1,0), (0,1), …])`: explicit offsets
  - `Moore(2; weights = inverse_distance)` weighted relations for contact energies
- Named relations can be declared and referenced:
  ```julia
  @relations begin
      proposal = Moore(1)
      contact  = Moore(2; weights = inverse_distance)
      act      = VonNeumann(1)
  end
  @energy contacts(contact) => weight * J[kind, kind′]
  ```
- Boundaries: `Periodic()`, `Closed()` (no proposals across), `Wall(kind)` (a frozen
  ring of a kind), or a mask array for arbitrary domains.
- The compiler's footprint analysis (INTERNALS §2.4) reads the orders here to set the
  checkerboard stride, so higher-order neighborhoods just work on GPU, at the cost of
  more colours.

---

## 4. Energies (global H)

`@energy` declares terms of `H`. Each term has a **domain**, which fixes what the
expression may refer to:

| Domain | Sum over | Names in scope |
|---|---|---|
| `cells(kinds…)` | every cell of those kinds | `volume`, `surface`, `centroid`, `inertia`, `elongation`, `kind`, `id`, `generation`, any `x(cell)`; `x[c]` explicit |
| `sites` | every lattice site | `owner`, `kind`, `position`, any `x(site)`, fields `c` at the site |
| `contacts` / `contacts(relation)` | every neighbouring pair `(s, s′)` with `owner[s] ≠ owner[s′]` | `kind`, `kind′`, `owner`, `owner′`, `weight`, plus `x`/`x′` for site state |
| `edges(relationship)` | every relationship edge | `a`, `b` (cells), `distance`, edge state |
| `model` | once | model-scoped variables |

Examples:

```julia
@energy begin
    cells(dark, light) => λ * (volume - V₀)^2
    cells(dark)        => λₛ * (surface - S₀)^2
    cells(tumor)       => -κ * elongation                      # elongation constraint
    contacts           => J[kind, kind′]
    contacts(contact)  => weight * J[kind, kind′]              # weighted, order 2
    sites              => μ * c * (kind == tumor)              # field-coupled site energy
    edges(bond)        => k * (distance - ℓ₀)^2                # spring between linked cells
end
```

Library one-liners expand into the same pairs and remain available for discoverability:

```julia
Volume(dark, light; target = V₀, strength = λ)       # ≡ cells(dark, light) => λ*(volume-V₀)^2
Surface(dark; target = S₀, strength = λₛ)
Adhesion(J)                                           # ≡ contacts => J[kind, kind′]
Chemotaxis(c; strength = μ)                           # a @drive, see §5
```

**What the compiler does with H** (the "optimize it hard" list, INTERNALS §2.5):

1. For each term, determine which quantities a copy changes (tracker deltas
   `δvolume = ∓1`, `δsurface`, `δcentroid`, site values at the target, contact pairs
   around the target, incident edges) and substitute `q → q + δq`.
2. Form `E(after) − E(before)` symbolically and simplify. Polynomial terms collapse
   to closed forms: `λ(V−V₀)²` becomes `λ(±2(V−V₀) + 1)`.
3. Drop terms untouched by the proposal; classify the rest by domain.
4. Fuse all neighbourhood loops of the same relation into one loop.
5. Precompute pure kind tables (`J[kind, kind′]`) into constant memory; pure-kind
   contact terms plus integer-volume terms may additionally table Boltzmann factors.
6. CSE across all terms; parameters marked structural become literals.
7. Select trackers: only quantities that appear in some term are maintained.
8. **Self-verification:** because the user wrote `H`, the compiler also generates
   `total_energy(sys)`. The test suite checks `ΔH == H(after) − H(before)` on random
   flips of every model automatically. No hand-written oracle is needed.

---

## 5. Drives and constraints

```julia
@drive begin
    copy => μ * (c[target] - c[source])                        # chemotaxis
    copy => -(λ_act / max_act) * (geomean_act(source) - geomean_act(target))
end
@constraint begin
    connectivity(endothelial)                # local connectivity preserved
    volume[owner[target]] > 1                # no extinction (default; can be disabled)
end
```

Inside proposal-scoped expressions: `source`, `target` (sites), `owner[·]`, `kind[·]`,
`x[·]` for site state, `volume[owner[source]]` etc. for cell quantities. A drive is
added to ΔH with unit weight; `copy => expr` is the copy-attempt context.

---

## 6. State, dynamics and randomness

```julia
@variables begin
    act(site)   = 0.0, [clear_on_ownership_change = true]
    clock(cell) = 0.0
    c(field)    = 0.0
    total(model)
end

@on_copy   act[target] ~ max_act                       # after an accepted copy
@after_mcs act ~ max(Pre(act) - 1, 0)                  # synchronous, every MCS
@after_mcs Every(10) total ~ sum(act)                  # cadence
@before_mcs clock ~ Pre(clock) + rand(Normal(1, 0.1))  # addressed randomness
```

- Updates are equations; the left side is the variable at the new MCS, `Pre(x)` the
  previous value, `Pre(x, k)` k steps back (histories are inferred).
- Neighbourhood expressions are generator comprehensions over a relation, in any scope:
  ```julia
  geomean_act(s) = geomean(act[n] for n in Moore(1)(s) if owner[n] == owner[s])
  ```
  `sum`, `prod`, `mean`, `geomean`, `minimum`, `maximum`, `count`, `any`, `all` are
  recognised and lowered to unrolled loops with the right fold; `if` filters become
  masks.
- `rand(dist)` inside any expression is an addressed draw: reproducible, backend
  independent, keyed to the site/cell/MCS it belongs to.

### Differential equations, in MTK syntax

```julia
@equations begin
    D(c) ~ Dc * Δ(c) + σ * (kind == endothelial) - δ * c     # field PDE (c(field))
    D(g) ~ r * g * (1 - g / K)                                # per-cell ODE (g(cell))
    D(h) ~ -h                                                 # model ODE (h(model))
end
@sweep Metropolis(; temperature = T, mcs_duration = 1.0u"min", ode_solver = Tsit5(),
                  field_solver = ExplicitEuler(substeps = 4))
```

The variable's scope decides what the equation is: a field variable with `Δ`/`∇`
becomes a lattice PDE step, a cell variable becomes a batched per-cell ODE, a model
variable a scalar ODE. `D = Differential(t)` and `t` are MTK's; `Δ`, `∇`, `∇²` are
lattice operators registered by Potts. `MethodOfLines` remains available for PDEs that
should not use the built-in stencils.

---

## 7. Lifecycle and relationships

```julia
@divide  cells(tumor)  when = volume >= 2V₀,
                        along = principal_axis(),        # or RandomPlane(), Normal((0,0,1))
                        clock => 0.0, act => Split()      # state rules for daughters
@retire  cells(tumor)  when = volume == 0
@create  medium        when = rand(Bernoulli(p_seed)), kind = tumor, at = RandomSite()
@transition cells(follower) => leader  when = distance_to(front) < 2

@relationship bond(cell, cell)  distance = centroid_distance, capacity = 6
@link   bond  when = new_contact(a, b) && kind[a] == leader
@unlink bond  when = distance > ℓ_max
```

Rules are evaluated at the MCS boundary; conflicts resolve deterministically (stable
priority). Daughter state rules: `Split()` (conservative), `Copy()`, `Reset(v)`,
`Redraw(dist)`; the default is `Copy()`.

---

## 8. Composition, coupling, problems

```julia
@named growth = GrowthODE()                      # any MTK ODESystem
@potts_model Invasion begin
    @components growth = growth
    @equations  V₀[cell] ~ growth.V_target       # couple by equation
    ...
end

@named tumor  = Invasion(; lattice = (300, 300))
sys = compose(tumor, extend(...))                # MTK composition, namespacing
csys = mtkcompile(sys)

prob = PottsProblem(csys, [ownership => labels, kind => kinds, act => 0.0, λ => 1.0],
                    (0, 500); seed = 7)
sol  = solve(prob, CheckerboardCPM(); backend = MetalBackend(), saveat = 0:10:500)

remake(prob; p = [λ => 2.0])                     # zero recompilation
EnsembleProblem(prob; trajectories = 32)         # seeds vary; one compiled model
checkpoint(integrator); init(prob, alg; checkpoint = ck)
```

Operating points, `remake`, `getu`/`setp`, `observed`, ensembles and callbacks are
MTK/SciMLBase semantics unchanged.

---

## 9. Renames for readability

| Old | New |
|---|---|
| `CheckerboardSweepCPM` | `CheckerboardCPM` |
| `CPUBackend()`, `MetalBackend()` wrappers | `CPU()`, `MetalBackend()` from KernelAbstractions/Metal |
| `PottsInitialState(ownership = LabelledCells(labels; cells, medium))` | `ownership => labels, kind => kinds` in the operating point |
| `Protocol(Sweep(; temperature, attempts = AttemptsPerSite(16)))` | `@sweep Metropolis(; temperature, attempts_per_site = 16)` |
| `ContactEnergy([(a ↔ b) => J, …])` | `contacts => J[kind, kind′]` with a kind-indexed parameter |
| `HamiltonianTerm(:name; domain, anchor, expression)` | `@energy domain => expression` |
| `ProposalDrive(:name, expr; drive_scale)` | `@drive copy => expr` |
| `ProposalConstraint`, `LocalConnectivity(kind)` | `@constraint`, `connectivity(kind)` |
| `SiteState`, `CellState`, `FieldState`, `ModelState`, `HistoryState` | `@variables x(site)`, `x(cell)`, `c(field)`, `x(model)`, `Pre(x, k)` |
| `Synchronous(:name, Assign(x, e); phase = AfterMCS())` | `@after_mcs x ~ e` |
| `AcceptedCopy(:name, Assign(x, e); when)` | `@on_copy x[target] ~ e` (optionally `when = …`) |
| `LifecycleProcess(Divide(...))`, `RetireAtZero()` | `@divide`, `@retire` |
| `RelationshipState/Energy/Process` | `@relationship`, `edges(name) =>`, `@link/@unlink` |
| `gather(...; bind, at, over, where)` + `LocalMath.fold(...)` | generator comprehensions over relations |
| `ProposalContext(:copy)`, `SiteBinding`, `CellBinding` | bound names `source`, `target`, `owner[·]` |
| `Observation(:name, expr)` | `@observed name ~ expr` |
| `NativeComponent`/`ODEComponent(...)` | `@components` + coupling equations |
| `DiscreteFieldEuler(...)` | `field_solver = ExplicitEuler(substeps = n)` in `@sweep` |
| `PottsSavedState` | `sol[t]` state view with `[volume]`, `[act]`, `.ownership` |

---

## 10. The published models in the new surface

### Graner–Glazier sorting — §1 above.

### Wortel Act migration

```julia
@potts_model WortelAct begin
    @structural_parameters begin lattice = (150, 150) end
    @kinds medium endothelial
    @parameters begin
        λ = 1.0; V₀ = 500.0; λₛ = 0.05; S₀ = 320.0; T = 20.0
        λ_act = 200.0; max_act = 80.0
        J[kind, kind] = [0 20; 20 40]
    end
    @variables act(site) = 0.0, [clear_on_ownership_change = true]
    @lattice Lattice(lattice; boundary = Periodic(), neighborhood = Moore(1))
    @energy begin
        cells(endothelial) => λ * (volume - V₀)^2 + λₛ * (surface - S₀)^2
        contacts           => J[kind, kind′]
    end
    geomean_act(s) = geomean(act[n] for n in Moore(1)(s) if owner[n] == owner[s])
    @drive copy => -(λ_act / max_act) * (geomean_act(source) - geomean_act(target))
    @on_copy   act[target] ~ max_act
    @after_mcs act ~ max(Pre(act) - 1, 0)
    @constraint connectivity(endothelial)
    @sweep Metropolis(; temperature = T)
end
```

### Merks vasculogenesis (chemotaxis with a secreted field)

```julia
@potts_model Merks begin
    @structural_parameters begin lattice = (200, 200) end
    @kinds medium endothelial
    @parameters begin
        λ = 5.0; V₀ = 50.0; T = 50.0; μ = 500.0
        Dc = 1e-13; σ = 1.8e-4; δ = 1.8e-4
        J[kind, kind] = [0 25; 25 50]
    end
    @variables c(field) = 0.0
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells(endothelial) => λ * (volume - V₀)^2
        contacts           => J[kind, kind′]
    end
    @equations D(c) ~ Dc * Δ(c) + σ * (kind == endothelial) - δ * c
    @drive copy => -μ * (c[target] - c[source]) * (kind[source] == endothelial)
    @sweep Metropolis(; temperature = T, mcs_duration = 30.0u"s",
                      field_solver = ExplicitEuler(substeps = 15))
end
```

### OpenVT monolayer (growth and division)

```julia
@potts_model Monolayer begin
    @structural_parameters begin lattice = (100, 100) end
    @kinds medium epithelial
    @parameters begin λ = 1.0; V₀ = 40.0; T = 10.0; g = 0.5; J[kind,kind] = [0 8; 8 4] end
    @variables target(cell) = 40.0
    @lattice Lattice(lattice; boundary = Closed(), neighborhood = Moore(1))
    @energy begin
        cells(epithelial) => λ * (volume - target)^2
        contacts          => J[kind, kind′]
    end
    @after_mcs target ~ Pre(target) + g
    @divide cells(epithelial) when = target >= 2V₀, along = principal_axis(),
                              target => V₀
    @sweep Metropolis(; temperature = T)
end
```

### Akeeb–Marcus–Jiang leader/follower invasion (relationships + MTK ODE)

```julia
@named clock = ODESystem([D(m) ~ 1 / τ], t; name = :clock)   # mitotic clock, MTK

@potts_model Invasion begin
    @structural_parameters begin lattice = (500, 300) end
    @kinds medium leader follower
    @parameters begin λ = 1.0; V₀ = 40.0; T = 8.0; μ = 30.0; k = 0.5; ℓ₀ = 6.0
                      J[kind, kind] = [0 16 16; 16 4 6; 16 6 8] end
    @variables c(field) = 0.0
    @components clock = clock                     # per-cell instance (cell scope inferred)
    @lattice Lattice(lattice; boundary = (Closed(), Periodic()), neighborhood = Moore(1))
    @energy begin
        cells(leader, follower) => λ * (volume - V₀)^2
        contacts                => J[kind, kind′]
        edges(bond)             => k * (distance - ℓ₀)^2
    end
    @equations D(c) ~ Δ(c) - 0.1c + (kind == leader)
    @drive copy => -μ * (c[target] - c[source]) * (kind[source] == leader)
    @relationship bond(cell, cell)  distance = centroid_distance, capacity = 4
    @link   bond when = new_contact(a, b) && kind[a] == leader && kind[b] == follower
    @unlink bond when = distance > 2ℓ₀
    @divide cells(follower) when = clock.m >= 1, along = RandomPlane(), clock.m => 0
    @sweep Metropolis(; temperature = T, mcs_duration = 1.0u"min", ode_solver = Tsit5())
end
```

---

## 11. Extensibility

- **New energy or drive terms:** write the expression. No registry needed.
- **New library helpers:** functions returning `domain => expr` pairs.
- **New relations:** `Stencil(offsets)` or a subtype of `AbstractRelation` with
  `offsets(rel, N)`.
- **New lifecycle rules or state rules:** subtypes with an `expand` method (the one
  registry that remains).
- **Custom kernels:** the numerical layer (`CorePotts`) accepts hand-written
  `delta_H`/`commit!` functions for anything the symbolic layer cannot express.

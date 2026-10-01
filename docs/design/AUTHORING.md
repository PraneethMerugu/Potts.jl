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
    @sweep Metropolis(; temperature = T)     # the paper's 16 attempts/site = 16 MCS
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
| `@variables` | state with a **scope** in the signature: `x(site)`, `x(cell)`, `x(model)`, `c(field)`, `e(edge)` or `e(rel)` (an edge variable of `@relationship rel`) | `@variables`, scope is Potts |
| `@lattice` | `Lattice(dims; boundary, neighborhood, spacing)` | — |
| `@energy` | Hamiltonian terms as `domain => expression` pairs | — |
| `@drive` | non-energetic proposal biases (`copy => expr`) | — |
| `@constraint` | hard proposal constraints | — |
| `@equations` | differential equations (`D(x) ~ …`, `∂t`) for fields, per-cell ODEs, model ODEs | same |
| `@before_mcs`, `@after_mcs`, `@on_copy` | discrete updates as equations with `Pre` | discrete events |
| `@divide`, `@retire`, `@create`, `@transition` | lifecycle rules | — |
| `@relationship`, `@link`, `@unlink` | cell–cell edges | — |
| `@components` | MTK subsystems (ODE, or discrete-time clocked `Shift` systems such as Boolean networks) coupled to the model | same |
| `@observed` | derived quantities | `observed` |
| `@sweep` | protocol: `Metropolis(; temperature, offset)` (1 MCS = N attempts) | solver options |

**Conditional sections (implemented).** An `if`/`elseif`/`else` whose branches hold section
macros is evaluated when the model is constructed, so a structural parameter can switch
statements on or off:

```julia
@structural_parameters begin connected = false end
…
if connected
    @constraint connectivity(cell; rule = :arc_or_pair)
end
```

Declaring sections (`@structural_parameters`, `@kinds`, `@parameters`, `@variables`,
`@extend`) cannot be conditional.

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
- `geometry = Square()` (default, cubic in 3D) or `Hexagonal()` (2D; 7 published
  Morpheus models use it). Relations are defined per geometry.
  **Hexagonal (implemented).**
  - Sites are axial `(q, r)` on the usual array, placed at `(q + r/2, r·√3/2)`.
  - `Hex(k)` is the hex-distance ball: 6, 18, 36 neighbours. `Moore(k)` and
    `VonNeumann(k)` mean `Hex(k)` on these lattices. `Ball`/`NeighborOrder` use Euclidean
    distance in the embedding.
  - Cartesian quantities: `centroid`, `displacement`, shapes, principal axes, division
    planes and link distances.
  - `Δ` and `∇` use the 6-point stencils: exact for quadratic (`Δ`) and linear (`∇`)
    fields, with zero flux at closed faces.
  - Periodic axes make a rhombic torus. `position` and domain predicates see axial
    coordinates.
  - One spacing.
- `domain = mask` (Bool array or image via TiffImages.jl) or `domain = x -> expr`
  restricts the lattice to an irregular region; the domain edge is a boundary for both
  copies and fields.
- **Relation roles are separate.** `neighborhood` sets the contact and surface
  relations. The proposal relation defaults to the first shell (`VonNeumann(1)`: 4 in
  2D, 6 in 3D) unless the model sets `@relations proposal = …`. That becomes the
  problem's proposal; `SequentialCPM(; proposal)` and `CheckerboardCPM(; proposal)`
  override it per solve (D-049 F-1). Widening contact never widens proposals.
- **Neighborhoods** are relations with an order or radius:
  - `Moore(k)`: Chebyshev distance ≤ k (order 1 = 8 neighbours in 2D, 26 in 3D)
  - `VonNeumann(k)`: Manhattan distance ≤ k
  - `Ball(r)`: Euclidean distance ≤ r, in lattice spacing units
  - `NeighborOrder(k)`: all offsets in the first k distinct distance shells, cumulative
    (CompuCell3D `NeighborOrder`; 2D counts 4, 8, 12, 20, 24, 28; 3D 6, 18, 26, 32, 56, 80)
  - `Stencil([(1,0), (0,1), …])`: explicit offsets
  - `Moore(2; weights = inverse_distance)` weighted relations for contact energies
  - `include_self = true` adds the zero offset (e.g. Artistoo's Act geometric mean)
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
| `contacts` / `contacts(relation)` | every **unordered** neighbouring pair `{s, s′}` with `owner[s] ≠ owner[s′]`, counted once (CompuCell3D convention) | `kind`, `kind′`, `owner`, `owner′`, `weight`; any site or field variable as `x` (its value at `s`) and `x′` (at `s′`), read where the term is evaluated (see below); and **cell state of both owners** `y[owner]`, `y[owner′]` (makes the term non-local: its cells join the checkerboard claim set) |
| `edges(relationship)` | every edge of that relationship | `a`, `b` (cells; reserved: no declaration (kind, parameter, variable, observed, relation, relationship, component) may be named `a` or `b`, D-075 Q8, D-076), `distance`, that relationship's edge variables |
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

Site values in contact terms. A contact term may read any site or field variable `x` as
`x` (at `s`) and `x′` (at `s′`). An asymmetric term is averaged with its mirror
(`kind ↔ kind′`, `owner ↔ owner′`, `x ↔ x′`), like every contact term. The value read is the
site's current value. Updates, field equations and on-copy writes change it; the copy itself
does not. A copy changes only the owner of the target, so ΔH covers the contact pairs around
the target. An `@on_copy x[target] ~ …` write, and a variable with
`clear_on_ownership_change`, enter ΔH with their after-copy value at the target (D-045). An
on-copy write at the source, which would change pairs away from the target, is rejected. The
reads at `s′` lie within the contact radius, so they add no reach and no checkerboard claims.
`x′` exists only in contact terms.

```julia
@variables cue(site) = 0.0
@energy begin
    contacts        => J[kind, kind′] + β * (kind != kind′) * (cue + cue′) / 2   # cue-gated adhesion
    contacts(outer) => weight * γ * (cue - cue′)^2                               # any contact relation
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

**Connectivity values (implemented, D-051 R0).** Copy-scope integers about the losing cell
(`old`) around the target:
- `local_components`: its pieces in the target's neighbourhood after the copy;
- `ring_arcs`: its arcs on the 2D neighbour ring;
- `ring_cells`: distinct cells on that ring.

Connectivity rules are then ordinary statements:

| Rule | Statement |
|---|---|
| Hard (CC3D, Morpheus) | `@constraint connectivity(k)`, i.e. `local_components == 1` for losers of kind `k` (D-074: zero pieces, the last site or an isolated fragment, is rejected too, so such a cell cannot die by copies) |
| Ring rule (TST `ConnectivityPreservedP`, Merks) | `connectivity(k; rule = :arc_or_pair)`, i.e. `ring_arcs <= 1 \|\| ring_cells == 2` (zero arcs pass; D-074 covers the local rule only) |
| Soft penalty (Artistoo, CC3D strength, Merks E₀ under Metropolis) | `@drive copy => λ * (local_components > 1)` |

An unknown `rule` is an error.

**Chemotaxis family.** `Chemotaxis(c; strength, response, kinds, when)`:
- `response`: `identity`, `saturating(s)` = `c/(s + c)`, `saturating_linear(s)` =
  `c/(s c + 1)`, or any function;
- `when`: the copy condition, default `new != 0` (the gaining cell is a cell, so
  retractions get 0; D-075). `when = true` means every copy, retractions included; any
  other condition selects exactly its copies, e.g. `old == 0` for extensions only.
- `kinds`: additionally requires `kind[new] ∈ kinds`, so with `kinds` given retractions
  stay 0 whatever `when` says.

**Neighbourhood memory (Act family).** Write the mean as a fold:
`geomean(x[n] for n in Moore(1; include_self = true)(s) if owner[n] == owner[s])`. `mean`
and `log1p_geomean` give the other variants. CorePotts has `neighborhood_mean(x, σ, ctx,
site, owner; relation, fold)` for hand-written models.

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
  **Implemented:**
  - `Pre(x, k)` is the value at the end of the MCS `k` before the current one, i.e. at
    the MCS boundary after the lifecycle. `Pre(x, 1)` differs from `Pre(x)` when `x`
    changed earlier in the same MCS.
  - It works for site, field and model quantities, anywhere the MCS clock is available:
    updates, equations, division conditions and rules, and link rules.
  - Each lagged variable gets one ring buffer, as deep as its largest `k`. The rings
    start as the initial value and take the value at the MCS boundary (CorePotts
    `end_mcs` phases). A value changed after that, by a callback or a setter, reaches the
    ring at the next boundary.
  - Lags of cell variables are rejected, because rings would not follow capacity growth
    and division. Chain `Pre` instead.
  - Lags are also rejected in energies and `@observed`.
- **Compound assignments (implemented).** `x += e` is `x ~ Pre(x) + e` (also `-=`, `*=`,
  `/=`), including indexed on-copy targets (`hits[target] += 1`) and vectors. Every
  compound write of one target in a block folds into one update that reads the same
  previous value: `x += a; x -= b` gives `x ~ Pre(x) + a - b`.
- **One writer per target (implemented).** A target written twice in the same phase and
  cadence is an error that suggests `+=`. In `extend`, an extension's update of a target
  replaces the base's, and its equation or observed quantity of the same name replaces the
  base's. Structural replacement is therefore explicit: redeclare the target.
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

**Solvers are problem keywords (D-075, P6.0c; implemented).** The model states the
equations; the problem states how each field and ODE is integrated. The solvers are
compiled into the phase code when the problem is built (MethodOfLines' `discretize`
placement), so a different scheme is a different problem. They are not `@sweep` keywords
(`@sweep` with `field_solver` or `ode_solver` is an error naming the keyword) and not
algorithm fields.

```julia
prob = PottsProblem(sys, op, (0, 500);
    field_solver = ExplicitEuler(substeps = 15, lower = 0.0),   # required when the model has a field
    ode_solver = ExplicitEuler(),                                # the default: one step per MCS (D-038)
    solvers = [V => Adaptive(Rodas5P(); reltol = 1e-8)])         # per variable, keyed symbolically
prob2 = remake(prob; field_solver = ExplicitEuler(substeps = 30, lower = 0.0))
```

- `field_solver = ExplicitEuler(; substeps, lower)` has **no default**: a model with an
  integrated field (`D(c) ~ …`) needs it, even when `solvers` names every field, and a
  model without one rejects it. `substeps = nothing` takes the stable count from the
  diffusion coefficient; an explicit `n` is a minimum. `lower` clips after every substep. A
  published model's docstring gives its value (Merks: `ExplicitEuler(substeps = 2,
  lower = 0.0)`).
- `ode_solver` integrates every cell and model ODE (`D(x) ~ …`, components):
  `ExplicitEuler(; substeps)`, `RK4(; substeps)` or `Adaptive(alg; kwargs...)`. It has a
  default, so a model without ODEs accepts it silently (it changes nothing, fingerprint
  included), unlike `field_solver`. For an ODE, `ExplicitEuler()` is one step per MCS,
  the same as `ExplicitEuler(substeps = 1)`.
- `solvers = [x => solver, …]` overrides `ode_solver` (or, with an `ExplicitEuler`,
  `field_solver`) for the integrated variables it names: by the Potts variable, its name
  (`:x`), a component variable (`grn.x` or `Symbol("grn₊x")`), or a component system
  (`grn`: all its integrated unknowns). A key that is a parameter, a variable without an
  equation, or named twice is an error.
- **Jacobi across solvers.** The ODEs of one solver (equal specifications, by their
  canonical string) step together in one phase. When a scope has several such groups,
  each writes scratch slots `x__ode` and one publish per scope copies them back after the
  last group, so every rate's reads of its own cell's (or the model's) unknowns see the
  state at the start of the step, whatever the solvers or the equation order.
- **Jacobi across cells (P6.0n).** A cell ODE may read other cells' ODE unknowns: `y[j]`
  (`y[3 - id]`, `y[owner[n]]` in a gather) or a population fold over cells that stays in
  the ODE kernel because it reads `time` (folds without `time` are computed once before
  the ODEs). Every such read sees the other cell's state at the start of the MCS, held over
  the whole step (all stages and substeps), under both algorithms, on the GPU, whatever
  the cell labels: the cell ODEs then write scratch `x__ode` even with one solver group.
  Only a bare `y` and a literal `y[id]` outside folds are the cell's own unknown, which
  advances through the stages and substeps as usual; so does any index expression
  (`w[ifelse(y > 0.5, id, j)]` follows the stepped `y`). Every other indexed or fold read
  sees the start-of-step value, even when it lands on the cell itself: a gather's
  `y[owner[n]]` with `owner[n] == id`, `y[max(id, 1)]`, or the cell's own term of a fold
  left in the kernel. A cell scope with one group and no such reads writes its variables
  directly (no scratch; the code of such a model is unchanged). Cell ODEs run before model ODEs, which see the cells' new
  values (D-077 N3, unchanged).
- `remake(prob; field_solver | ode_solver | solvers = …)` rebuilds the code through the
  same codegen point and keeps `u0` (re-laid out for the scratch slots, values kept), `p`,
  the seed and the solver keywords it does not name. `remake(prob; p | u0 | seed)` never
  regenerates (`f` is the same object). Cost: a new specification on Merks 100² takes
  about 0.3 s of code generation plus 0.4 s of compilation at the first solve; an
  identical one reuses the compiled functions (a few ms). A first `Adaptive` algorithm also
  compiles OrdinaryDiffEq (seconds).
- The D-016 fingerprint hashes a canonical string of the resolved per-variable solvers
  (`Adaptive`'s algorithm by fully qualified type and fields, closures' captures
  included, and its sorted keywords; the `ExplicitEuler`/`RK4` fields), so a checkpoint
  loads only into an equally discretised problem; equal specifications built from fresh
  objects match. The algorithm's type and fields belong to the solver package, so the
  fingerprint can change with its version (as it does with Julia's).

**Adaptive and stiff solvers (implemented).**
`ode_solver = Adaptive(Rodas5P(); reltol = 1e-8)` (or a `solvers` entry) integrates cell
and model ODEs on the host with any SciML ODE algorithm. The user loads OrdinaryDiffEq;
Potts depends only on SciMLBase. An equation with `rand()` cannot be integrated
adaptively (the solver re-evaluates the rate at trial steps). The integrator's parameter
tuple is set to the current cell and MCS before each `reinit!` (P6.0c; before, the
initial-step guess evaluated the rate with the previous cell's tuple, a stale host
snapshot on a device), so adaptive trajectories changed within tolerance.
- One integrator is created on first use and re-initialized per cell and per MCS
  (`reinit!`, set `p`, `solve!` to `t + mcs_duration`).
- A device state is copied to the host and back once per MCS.
- The fixed-step `ExplicitEuler`/`RK4` stay the GPU-resident default.

**Model scope (implemented).**
- `D(x) ~ rhs` on a model variable advances with the problem's `ode_solver`, in a
  single-work-item kernel. The right side may use population folds, `mcs` and `time`.
- `@components model name = sys` instantiates an MTK system once for the whole model.
  Its unknowns are model variables and its parameters are model parameters, which can be
  coupled to model-scope expressions:
  `@equations pk.dose ~ count(true for c in cells)`.

```julia
@equations begin
    D(c) ~ Dc * Δ(c) + σ * (kind == endothelial) - δ * c     # field PDE (c(field))
    D(g) ~ r * g * (1 - g / K)                                # per-cell ODE (g(cell))
    D(h) ~ -h                                                 # model ODE (h(model))
end
@sweep Metropolis(; temperature = T, mcs_duration = 1.0u"min")
# …
prob = PottsProblem(sys, op, tspan; field_solver = ExplicitEuler(substeps = 4),
    ode_solver = Adaptive(Tsit5()))
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
priority).

**Cadence (P6.0f).** Each rule has its own `Every(n)`, written after the domain
(`@divide cells(ka) Every(2) when = …`) or as `every = n`
(`@link tether when = …, every = 10`); a rule gets one cadence, and the default is `Every(1)`.
A rule is checked at the MCS where `mcs % n == 0`, with MCS numbered from 0 as for updates.
So `Every(2)` and `Every(3)` rules in one model fire at MCS 0, 2, 4, … and at MCS 0, 3, 6, ….
The programmatic form is `Potts.divide(domain, Potts.Every(n); when = …)`. A model whose
rules all share one cadence pays nothing per MCS for it; the lifecycle pass is skipped
outright on the other MCS. Under `@extend`, division rules accumulate. An extension's rule
for kinds the base already divides at another cadence adds to the base's rule and does not
replace it: both rules apply, each at its own cadence (on an MCS where both are checked,
only the first match fires; see below), and a warning names the two.

**Several rules for one cell.** Rules are tried in model order (a base's before an
extension's), and the first rule whose cadence, kinds and `when` all hold for a cell wins:
it divides the cell, and only its daughter state rules run. A rule that was not checked, or
did not fire, never writes the daughters' state, even when it names the same kind.

Daughter state rules: `Split()` (conservative), `Copy()`, `Reset(v)`,
`Redraw(dist)`; the default is `Copy()`.

### Relationships

A model declares any number of named relationships (P6.0b). Each has its own link store,
capacity, edge variables, `edges(name)` terms, `@link`/`@unlink` rules and claim set:

```julia
@variables begin
    rest(bond) = 12.0            # an edge variable of `bond`
    len(tether) = 18.0           # … of `tether`
end
@relationship bond(cell, cell)   capacity = 1
@relationship tether(cell, cell) capacity = 2
@energy begin
    edges(bond)   => k₁ * (distance - rest)^2
    edges(tether) => k₂ * (distance - len)^2
end
@link   tether when = new_contact(a, b) && kind[a] == follower, every = 10
@unlink bond   when = distance > 30.0
```

- **Edge variables name their relationship as their scope**: `rest(bond)`. With exactly
  one relationship `rest(edge)` still means that one; with several it is an error
  ("ambiguous"), as is a scope that is neither a scope nor a relationship. An edge term or
  link rule reads only its own relationship's edge variables (another relationship's
  payload has no slot for its links).
- **Initial links** are given per name in the operating point:
  `PottsProblem(sys, [ownership => σ, :bond => [(1, 2)], :tether => [(2, 3)]], tspan)`. A
  new link's edge variables start at their defaults.
- **Storage.** Relationship `r` keeps its adjacency in the cell column `links__r`
  (`maxdeg × capacity`, 0 = empty slot; `CorePotts.adjacency_name(r)`), and each edge
  variable `x` its payload in `link_x` (edge variable names are unique per model, so a
  payload column belongs to one relationship). The columns are flat cell quantities, so
  capacity growth, division, checkpoints, device transfer and host phases treat them like
  any other. Generated code works on a *link store view*, a NamedTuple
  `(; links = st.cell.links__r, link_x = st.cell.link_x)` of the state's arrays: it costs
  nothing and is valid in kernels. Query links with `CorePotts.link_store(u.cell, :r)`,
  e.g. `CorePotts.linked(CorePotts.link_store(u.cell, :bond), 1, 2)`.
- **Checkerboard claims.** A copy's ΔH reads the centroids of the link partners of `old`
  and `new` in every relationship, so all of them are claimed; a claim set missing one
  relationship would let a concurrent copy move a partner whose centroid this copy read.
  Partners are *shared read claims* (`CPMFunction(…; reads)`): copies that only read a cell
  may commit together, a copy that writes it excludes them. Exclusive partner claims would
  also be exact, but they serialise a whole linked chain (a cell linked by two
  relationships ties both chains together).
- **Lifecycle.** Removed cells lose their links, daughters start unlinked, in every
  relationship.

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
MTK/SciMLBase semantics unchanged. Declared variables are SII variables: `integ[:px] = v`
and `setu` write into the live (device) state, while built-ins are read-only. `integ.ps[:λ] = v` takes
effect from the next MCS without recompiling; a problem's parameters change with `remake`.

**Extending models (implemented).** `@extend λ, dark = base = Sorting()` works like
MTK's `@extend`:
- It builds the base model (keywords override its parameters).
- It binds the listed names: parameters, variables, kinds, relations.
- It merges the base into the model being defined. Terms accumulate base first, and
  same-named parameters and variables are redeclared by the extension.
- An extension that declares no `@lattice`, `@sweep` or `@kinds` inherits the base's.
- The base's kinds must come first in the extension's `@kinds`, which may add more (for
  example `wall[frozen]`).

`extend(sys, base)` is the functional form. Quantities can also be read by name:
`sol[:volume]`, `sol[:c]`, `sol[:my_observed]`.

---

**Units (implemented).** Declare units with MTK metadata:
`λ = 1.0, [unit = u"J"]`, `J[kind, kind] = …, [unit = u"J"]`, `c(field) = 0.0, [unit = u"mol"]`.
With DynamicQuantities loaded (`PottsDynamicQuantitiesExt`, on MTK's unit inference),
`mtkcompile` checks the model:
- Every term of H (energies, drives, the temperature) has one unit.
- Each update's right side has its variable's unit, and each division rule matches its
  variable.
- Conditions and constraints are dimensionless.
- Equations and observed quantities are internally consistent. Equation rates are not
  compared with a time unit, because the MCS clock carries none.

Built-ins are unitless (lattice units). Folds keep the body's unit, except `count`, `any`
and `all`. Without units, or without DynamicQuantities, the check is skipped.

## 9. Renames for readability

| Old | New |
|---|---|
| `CheckerboardSweepCPM` | `CheckerboardCPM` |
| `CPUBackend()`, `MetalBackend()` wrappers | `CPU()`, `MetalBackend()` from KernelAbstractions/Metal |
| `PottsInitialState(ownership = LabelledCells(labels; cells, medium))` | `ownership => labels, kind => kinds` in the operating point |
| `Protocol(Sweep(; temperature, attempts = AttemptsPerSite(16)))` | `@sweep Metropolis(; temperature)`; 1 MCS = N attempts, so a paper's "16 attempts per site" is 16 MCS |
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
| `DiscreteFieldEuler(...)` | `PottsProblem(…; field_solver = ExplicitEuler(substeps = n))` |
| `PottsSavedState` | `sol[t]` state view with `[volume]`, `[act]`, `.ownership` |

---

## 10. The published models in the new surface

### Graner–Glazier sorting — §1 above.

The sources in `lib/PottsModels/src` are the reference (each docstring names the paper, the
parameter set and the remaining differences); D-049 records the fidelity decisions.

### Wortel Act migration (`WortelAct`, Artistoo semantics)

```julia
act_mean(s) = geomean(act[n] for n in Moore(1; include_self = true)(s) if owner[n] == owner[s])
@drive copy => -(λ_act / max_act) * (act_mean(source) - act_mean(target))     # every copy
@on_copy act[target] ~ ifelse(new != 0, max_act, 0.0)                          # gained sites active
@after_mcs act ~ max(Pre(act) - 1, 0)
if connected
    @constraint connectivity(cell; rule = :arc_or_pair)
end
```

### Merks vasculogenesis (`MerksVasculogenesis`, Merks et al. 2006)

```julia
@energy begin
    cells(endothelial) => λ * (volume - V₀)^2 + λ_L * (major_length - L)^2
    contacts => J[kind, kind′]
end
if contact_inhibited                                   # PLoS 2008 extension-only form
    @drive copy => ifelse((old == 0) && (kind[new] == endothelial), -χ * (c[target] - c[source]), 0.0)
else                                                   # 2006: every copy
    @drive copy => -χ * (c[target] - c[source])
end
@equations D(c) ~ Dc * Δ(c) + σc * (kind == endothelial) - δc * c * (kind == medium)
@constraint connectivity(endothelial; rule = :local)
```

Its problem gives the field solver (D-075): `PottsProblem(MerksVasculogenesis(…), op, tspan;
field_solver = ExplicitEuler(substeps = 2, lower = 0.0))`.

### OpenVT growing monolayer (`OpenVTGrowingMonolayer`, Artistoo parameter set)

```julia
@variables V_target(cell) = A₀
@energy begin
    cells(cell) => λ * (volume - V_target)^2
    contacts => J[kind, kind′]
end
@after_mcs V_target ~ ifelse(volume >= β * Pre(V_target), Pre(V_target) + A₀ / τ, Pre(V_target))
@divide cells(cell) when = volume >= 2A₀, along = RandomPlane(), V_target => A₀
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
    @sweep Metropolis(; temperature = T, mcs_duration = 1.0u"min")
end
# PottsProblem(…; field_solver = ExplicitEuler(), ode_solver = Adaptive(Tsit5()))
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

---

## 12. Additions from the Morpheus and CompuCell3D research

Sources: `research/morpheus-gaps.md` (50 published Morpheus models surveyed),
`research/cc3d-gaps.md` (reference manual + C++ source). Julia-only per D-030.

### 12.1 Energies and acceptance

```julia
@energy begin
    contacts(; per_length = true) => J[kind, kind′]       # Magno et al. 2015 normalization
    cells(tumor) => λₛ * (surface(; per_length = true) - S₀)^2
    contacts => Homophilic(cad; strength = α)              # min(cad[owner], cad[owner′])
    contacts => J[kind, kind′] - α * cad[owner] * cad[owner′]   # any adhesion-molecule law
    cells(tumor) => -dot(λ⃗, centroid)                      # external potential (CC3D exact form)
end
@sweep Metropolis(; temperature = T[kind], combine = min,  # per-kind/per-cell T; medium never contributes
                  offset = 0.0)                          # accept if ΔH ≤ offset; Morpheus yield Y ≡ offset = -Y
```

- `per_length = true` divides by the lattice/neighborhood constant so energies are per unit
  boundary length (square orders 1–4: 1.273, 3.074, 5.620, 11.31; computed for any relation).
- Temperature may be a scalar, `T[kind]`, or cell state; the copy uses
  `combine(T_source, T_target)` (default `min`), and medium never contributes.
- At `T ≤ 0`: accept if `ΔH < offset`, reject if `>`, accept with probability ½ at equality
  (CompuCell3D convention).
- Library one-liners: `Homophilic`, `Heterophilic`, `AdditiveAdhesion`, `Aspherity`,
  `ExternalPotential`, `FreezeMotion(kind)`, `Haptotaxis(field)`.

### 12.2 Motility and proposal-scope names

In `@drive`/`@bias`, in addition to `source`, `target`, `direction`:

| Name | Meaning |
|---|---|
| `δcentroid[new]`, `δcentroid[old]` | centroid shift of the gaining / losing cell if the copy is accepted |
| `normal` | outward surface normal at the target, from the contact relation |
| `velocity[c]`, `displacement[c]` | tracked motility quantities (per MCS, since birth) |

```julia
@variables polarity(cell)::SVector{2,Float64} = zeros(2)
@drive copy => -μ * dot(polarity[owner[source]], δcentroid[owner[source]])   # persistent/directed motion
@after_mcs polarity ~ normalize(α * Pre(polarity) + (1 - α) * velocity)      # persistence memory
```

**Implemented (scalar form).** `centroid(k)` is coordinate `k` of the cell's centroid (cell
scope: updates, division conditions and rules, observed; periodic-safe moment trackers).
`displacement(c, k)` is the exact shift of cell `c`'s centroid along axis `k` if the copy is
accepted (proposal scope; `c` is `new` or `old`, zero for the medium or any other cell).
Either one switches the moment trackers on. Axes are checked against the lattice at
`mtkcompile`; `centroid` is not allowed in energies (ΔH would miss the copy's shift — use
`displacement` in a drive) and is 0 for empty cell slots. Persistent motion in scalars:

```julia
@variables begin px(cell) = 0.0; py(cell) = 0.0; cx(cell) = 0.0; cy(cell) = 0.0 end
@drive copy => -μ * (px[new] * displacement(new, 1) + py[new] * displacement(new, 2) +
                     px[old] * displacement(old, 1) + py[old] * displacement(old, 2))
@after_mcs begin
    px ~ ifelse(mcs == 0, 0.0, α * Pre(px) + (1 - α) * (centroid(1) - Pre(cx)))
    py ~ ifelse(mcs == 0, 0.0, α * Pre(py) + (1 - α) * (centroid(2) - Pre(cy)))
    cx ~ centroid(1); cy ~ centroid(2)
end
```

(On periodic axes use a wrapped difference for the velocity.) The vector-valued names in
the table and the library motility terms are still to come.

Library: `DirectedMotion(direction; strength)`, `PersistentMotion(; memory, strength)`,
`Chemotaxis(c; law = Linear() | Saturating(s) | MichaelisMenten(K) | LogScaled(),
mode = Extension() | Retraction() | Reciprocal() | Interface(filter))`.

### 12.3 Cell-level reductions and neighbor-cell iteration

```julia
@observed begin
    exposure(cell)  ~ sum(contact(c, n) for n in neighbors(c) if kind[n] == medium)
    signal(cell)    ~ sum(delta[n] * contact(c, n) for n in neighbors(c)) / surface   # juxtacrine
    c_total(cell)   ~ integral(c)            # field integrated over the cell's sites
    c_mean(cell)    ~ mean(c)
    c_center(cell)  ~ c[centroid]
    n_tumor(model)  ~ count(cells(tumor))
end
```

- `neighbors(c)` iterates distinct neighbouring cells (face-sharing under the contact
  relation); `contact(c, n)` is their shared interface length. Built once per MCS at the
  boundary, so there is no hot-path cost.
- Reductions over a cell's sites (`sum`, `mean`, `integral`, `maximum`, …) and over
  populations are maintained or recomputed at the boundary as the compiler decides.
  **Implemented: `integral(x)`.**
  - It is the sum of the site expression `x` over the cell's sites, in cell scope:
    updates, equations, division conditions and rules, observed quantities, and the
    temperature.
  - For a mean, divide by `volume`. For a count, use `integral(x > θ)`.
  - Each distinct integral gets one cell array, recomputed by an atomic `CellReduce`
    kernel at the MCS boundary (`end_mcs`, after the lifecycle) and when an integrator
    starts (`at_init`, so `remake` is respected).
  - When after-MCS updates, equations, division rules or link rules read an integral,
    it is also recomputed right after the copy sweep.
  - Read in an update block that writes one of its variables bare, it folds the new
    values (D-042): it is recomputed after the writing stage, before the next stage that
    reads it (and before the equations, lifecycle or temperature that read it after the
    block). An integral whose variables no update writes costs no extra pass.
  - Observed integrals are computed from the queried state itself.
  - It is not maintained through copies: site values also change through updates and
    fields, so a maintained sum would drift, and a recompute costs one pass over the
    sites. For the same reason it is rejected in energies and drives.

### 12.4 Shape descriptors (CompuCell3D definitions)

`inertia` (tensor), `major_length`, `minor_length` (2D: `4√(λ/V)` of the inertia
eigenvalues), `semiaxes`, `orientation`, `elongation = major_length / minor_length`,
`eccentricity`. These names replace any informal "elongation".

**Implemented:** `major_length` is a cell built-in, readable in energies, cell updates,
division rules and observed quantities (D-049 F-3). It is `4√λ₁` of the covariance of the
cell's sites in 2D (Merks et al. 2006, Eq. 5) and `2√(5λ₁)` in 3D, from the exact moment
trackers. In an energy its ΔH is exact: `CorePotts.major_length_after` evaluates the length
with the target site added or removed. The length constraint is
`cells(k) => λ_L * (major_length - L)^2`.

### 12.5 Fields

```julia
@equations begin
    D(c) ~ ∇⋅(Dc[kind] * ∇(c)) - δ[kind] * c + secrete(σ; at = outer_rim(tumor))
    D(c) ~ … - uptake(c; vmax, K, by = kind == tumor)       # Michaelis–Menten, conservative
    0    ~ Do * Δ(o) - consume(o; rate = k, by = kind == tumor)   # quasi-steady (LinearSolve.jl)
end
@boundary c begin
    x => (Dirichlet(1.0), NoFlux())       # per axis, per face; default follows the lattice
end
```

- Kind-dependent coefficients use harmonic-mean faces.
- Secretion locations: `interior(kind)`, `rim(kind)`, `outer_rim(kind)`,
  `contact_with(kind_a, kind_b)`, `centroid(kind)`, with optional `clamp = cmax`.
- Substeps are chosen automatically from the stability limit; secretion is split
  across substeps.
- `@brownians` inside `@equations` gives cell SDEs and noisy fields (StochasticDiffEq).

### 12.6 Kind-scoped dynamics and intracellular models

```julia
@equations cells(tumor) begin                 # per-cell ODE block, own solver/step/time scale
    D(x) ~ k1 - k2 * x
end; solver = Tsit5(), dt = 0.1, time_scale = 1.0
@components cells(tumor) grn = grn                          # MTK discrete (clocked, `Shift`) System
@components cells(tumor) stoch = JumpSystem(...)            # or Catalyst.jl ReactionSystem
@components cells(tumor) sbml = SBMLToolkit.readSBML("model.xml")
```

**Implemented (D-038).**
- `@components cells(k) clock = sys` instantiates an MTK `System` per cell.
  - `clock.m` is the cell variable `clock₊m`. It can be read anywhere, and division
    rules can set it.
  - `@equations clock.r ~ volume / V₀` couples a component parameter to a cell-scope
    expression. Uncoupled parameters become model parameters (`clock₊τ`), which can be
    set by `remake(prob; p = [:clock₊τ => …])`.
- Cell ODEs advance with the problem's `PottsProblem(…; ode_solver = ExplicitEuler(substeps = n) |
  RK4(substeps = n) | Adaptive(alg))`, or per variable with `solvers` (§6).

**Discrete-time components: Boolean and discrete networks (P6.0k, D-065 Q9, implemented).**
A Boolean or discrete network is a plain MTK discrete-time `System`; Potts has no network
type and no truth-table helper.

```julia
using Potts.ModelingToolkitBase: System, ShiftIndex, Clock, @variables, @parameters, @named
k = ShiftIndex(Potts.t, 0)            # one tick per MCS; ShiftIndex(Clock(n * mcs_duration)): every n MCS
@variables A(Potts.t)::Bool = false B(Potts.t)::Bool = false C(Potts.t)::Bool = false
@parameters wnt::Bool = false
@named grn = System([A(k) ~ wnt | (B(k - 1) & !C(k - 1)),     # x(k-1): the previous tick (synchronous)
                     B(k) ~ A(k - 1),
                     C(k) ~ !(A(k) | B(k - 1))], Potts.t)       # x(k): A's new value (ordered by MTK)

@potts_model Tumour begin
    @kinds medium tumour
    @variables signal(cell) = 0.0
    @components cells(tumour) grn = grn
    @equations grn.wnt ~ signal > 0.5                 # a cell-scope coupling, sampled at the tick
    @divide cells(tumour) when = grn.A & (volume >= 40)
    ...
end
```

- **Storage.** Each discrete variable `x` becomes the cell (or, with `@components model`,
  model) variable `grn₊x`, holding the value of the latest tick. A `Bool` node is stored in
  the model's scalar type as exact 0/1, so `sol[:grn₊A]`, the operating point
  (`:grn₊A => [true, false, …]`), division copies and plotting treat it like any cell
  variable. Model statements read `grn.A` as a `Bool` (`grn.A & …`) or as 0/1 (`λ * grn.A`).
  A deeper lag (`z(k - 2)`) keeps its own slot, `grn₊zₜ₋₁`; an array variable `z[1:n]`
  has one slot per element, `grn₊z_1 … grn₊z_n`. A node read at another cell
  (`grn.A[j]`) is a `Bool` as well.
- **Timing.** One fused phase per clock runs at the end of the MCS: after the updates, the
  fields and the ODEs, before the link rules and the lifecycle; for live cells
  (`volume > 0`) of the component's kinds only. Ticks follow MTK clock time: `Clock(dt;
  phase)` ticks at `t = phase + k·dt` (after MCS `t - 1`, in units of `mcs_duration`), and
  `t = 0` is the initial state. So `Clock(2)` ticks after MCS 1, 3, …, one MCS later than
  `Every(2)` (MCS 0, 2, …): the state saved at `t` has had `t ÷ 2` ticks.
  `Clock(n; phase = 1)` ticks after MCS 0, n, …, as `Every(n)` does. `dt` and `phase`
  must be whole numbers of MCS, with `0 ≤ phase < dt`.
- **Update order is MTK's.** Every rule reads the state before the tick (a `x(k - 1)` read
  is synchronous); a same-step read `x(k)` sees the new value, because `mtkcompile`
  substitutes its rule. Several components on one clock and scope share one phase. Every
  component that ticks at a given MCS (cell or model scope, any clock) reads the other
  components' pre-tick values, whatever the declaration order: with more than one tick
  phase, new values go to scratch slots (`grn₊x__tick`) and are published after all ticks.
  The same holds across cells: a rule reading another cell's node (`grn.A[j]`, a gather, a
  link partner) sees its pre-tick value, through the same scratch slots.
- **Couplings (as D-038).** `@equations grn.p ~ expr` replaces a component parameter by a
  cell-scope expression (cell variables, `volume`, `integral`, population folds, other
  components' state, `rand()`). A `Bool` parameter coupled to a number reads it as
  `!iszero`; write thresholds explicitly (`signal > 0.5`). An uncoupled parameter is a
  model parameter (`grn₊wnt`, 0/1 for a `Bool`). A continuous component coupled to a node
  (`ode.k ~ grn.A`) holds the latest tick over the MCS (zero-order hold); a discrete one
  coupled to an ODE state (`grn.s ~ ode.x > 0.5`) samples it at the tick.
- **Initial values** come from the MTK defaults and the operating point. MTK's
  initialization is never run (it is ill-posed for Boolean maps). A node or lag without a
  default must be given in the operating point.
- **Rejected at `mtkcompile`**, with an `ArgumentError` naming the component: a node
  without an update of its own ("every discrete variable needs an update"); `D(x)` in a
  discrete component (use a continuous and a discrete component, coupled); `Sample`/`Hold`;
  implicit rules and algebraic loops of same-step reads; several clocks in one component
  (one component per clock); a `Bool` node given a non-`Bool` rule; a period or phase that
  is not a whole number of MCS; an update or equation writing a node.
- Write updates as `x(k) ~ f(x(k - 1))` (MTK rejects `x(k + 1) ~ f(x(k))`) and clocks as
  `Clock(dt; phase)`. `ShiftIndex()` (an inferred clock) is not available.
- Random-order asynchronous updating is written in MTK form: a per-cell draw
  `@equations grn.u ~ rand()` and rules `A(k) ~ ifelse(u < 1/3, f_A, A(k - 1))`.
- Loading full `ModelingToolkit` (11.45 or later; its compiler rejects clocked systems) is
  supported: the `PottsModelingToolkitExt` extension compiles discrete components through
  MTK's discrete-pass hook, with the same generated code. Full MTK also compiles
  continuous components itself; it may order their unknowns differently (so the cell
  variables are declared in another order), with the same results.

**Randomness (implemented).**
- `rand()` inside a model is a uniform draw in (0, 1), fresh every MCS for every cell or
  site. Each occurrence has its own counter-based Philox stream, keyed by
  `(seed, replica, repeat)`, so results are identical across schedules and backends.
- It is available in updates, equations, division conditions and rules, for example
  `@divide cells(f) when = clock > 75 + 50rand()`.
- It is an error in energies, drives and constraints, where a random ΔH would break
  detailed balance.

### 12.7 Lifecycle additions

```julia
@divide cells(tumor) when = clock >= τ,
    along = normal(orientation[c]),                 # plane oriented from cell state
    clock => (daughter == 1 ? 0.0 : rand(Uniform(0, 1)))   # `daughter` index; parent via Pre
@create tumor at = density(ρ(position)), when = rand(Bernoulli(p))
@retire cells(tumor) when = volume < 2, sites => neighbors    # or => medium
@terminate when = count(cells(tumor)) == 0
```

`side = RandomSide()` (default, CompuCell3D) or `CanonicalSide()`; `along =
minor_axis()` / `major_axis()` / `RandomPlane()` / `normal(v)`.

### 12.7a Compartments (D-036, implemented)

```julia
@energy begin
    contacts => ifelse(cluster[owner] == cluster[owner′], Jint, J[kind, kind′])
    clusters(cytoplasm) => λc * (cluster_volume - Vc)^2 + λs * (cluster_surface - Sc)^2
end
@divide clusters(cytoplasm) when = cluster_volume >= 2Vc, mass => Split()
PottsProblem(sys, [ownership => σ, kind => kinds, cluster => groups], tspan)
```

- **Clusters.** A cluster is named by its lowest live member (the root). `clusters(k)`
  selects the clusters whose root is of kind `k`.
- **Where the trackers can be read.** Cells can read their cluster's trackers in updates,
  division conditions and observed quantities.
  - They cannot read them in cell energies: those values change when other members copy,
    so a cell-local ΔH would be wrong.
  - `cluster` itself never changes on a copy, so any energy can use it.
- **Dividing clusters.** `@divide clusters(…)` divides a cluster as a unit:
  - Only the root's condition counts (`clusters(k)` matches the root's kind).
  - Every member splits along one plane through the cluster centroid.
  - The state rules apply to every member. The daughters form a new cluster.
- **Cell and cluster divisions in one model (P6.0a).** Each `@divide` rule divides by its
  own domain, in the same lifecycle pass: `cells(k)` divides the cell alone,
  `clusters(k)` the whole cluster of the root.
  - A kind is divided by one domain only: naming it in both a `cells(…)` and a
    `clusters(…)` rule (bare `cells`/`clusters` name every kind) is an error at
    `mtkcompile`.
  - A `cells(k)` rule divides a member of a multi-cell cluster alone, and its daughter
    joins the parent's cluster (a nucleus dividing inside its cytoplasm). A lone cell's
    daughter is a lone cell (its own cluster).
  - When a cluster divides, its members' own `cells(…)` divisions in that MCS are dropped
    (the members already divide with the cluster).
  - Each domain has one plane (`along`): the rules of one domain must agree; the two
    domains may differ.

### 12.8 Initialization, import and steering

- **Layouts (P6.1a, implemented).** Host-side initial conditions built from layers and
  returned as an operating point:

  ```julia
  tiles = Tiling((5, 5); spacing = 1, region = (3:28, 3:28), kinds = [:dark, :light])
  seeds = Scattered(6, (3, 3); region = (2:29, 2:29), kinds = [:dark], seed = 1)
  op = layout(overlay(Frame(:wall), seeds), (30, 30))  # [ownership => σ, kind => kinds]
  prob = PottsProblem(sys, op, (0, 100))              # or layout(…, sys): its lattice
  ```

  - `Tiling(size; spacing = 0, region, kinds)`: whole boxes filling `region` (a tuple of
    ranges; default the whole lattice) in column-major order; `kinds` is cycled. On a
    periodic axis a last box closer than `spacing` to the first (through the wrap) is
    skipped.
  - `Scattered(n, size; region, kinds, seed, gap = 1)`: `n` boxes at random positions, at
    least `gap` medium sites apart (Chebyshev; through the wrap on periodic axes; in axial
    coordinates on hex, which is conservative). Random sequential placement with
    `StableRNG(seed)` (`seed` is a `UInt64`). It throws an `ArgumentError` when the boxes
    cannot fit, and also when placement jams: that happens near half of the densest
    packing, so a feasible dense request can throw. Like every layer it overwrites
    earlier ones, so keep it off a `Frame` with a `region` (as above).
  - `Frame(kind; width = 1)`: one cell owning every site within `width` of the edge of
    each closed axis. Periodic axes have no edge: on `(Periodic(), Closed())` the frame is
    two walls that are still one (frozen) cell; all-periodic is an error. On a lattice
    with a domain (P6.1a2) it paints the domain boundary instead: every in-domain site
    within Chebyshev distance `width` (lattice indices, through the wrap on periodic axes)
    of an out-of-domain site or a closed lattice edge, e.g. a ring on a disk. Chebyshev is
    Moore(1) graph distance on square lattices and conservative on hex, so the ring seals
    the domain.
  - `InsertUntil(kind; into, fraction | number, seed, region, misses = :retry)` (P6.2a):
    one-site cells of `kind` inserted at sites drawn uniformly from `region` with
    `StableRNG(seed)`. A draw hits a site of a cell of a kind in `into` painted before this
    layer; anything else misses. `misses = :count` counts a miss towards the stop rule
    without creating a cell (CompuCell3D-style scripts' empty cells, D-068). One stop rule:
    `number = n` (counted ≥ n) or `fraction = r` (K + counted ≥ r·(N + counted), N and K
    the live cells, and those of `kind`, painted before the layer). The rule is checked
    before the first draw and after each hit only, so `:count` can overshoot by trailing
    misses. It throws when the region holds no allowed site or runs out of them.
    `layout_tally(l, lat)` returns the point and one `(; painted, misses, counted)` per
    `InsertUntil` layer.
  - `overlay(layers...)`: later layers overwrite earlier ones; ids follow layer order.
    Cells left with no site are dropped. Partly covered cells keep what remains, which can
    be disconnected pieces: `layout` warns, naming the cell, when the remaining sites are
    not connected under the lattice neighbourhood (linear time; cells still a box are
    skipped, and the lattice-sized visited array is allocated only for a flood fill).
  - `layout(l, dims)`: `dims` means a closed square lattice with `Moore(1)`. For a
    hexagonal, periodic, domain or non-Moore lattice pass the `PottsSystem` (or
    `CompiledPottsSystem`): the layouts use its boundaries, neighbourhood, domain and
    geometry. A CorePotts `Lattice` also works but has no neighbourhood, so `Moore(1)` is
    assumed. On a lattice with a domain, no cell may cover a site outside it.
  - Coordinates are lattice indices, so layouts are N-D. On a hexagonal lattice they are
    axial, and a box is a rhombus.
  - **Adding a layout.** Subtype `AbstractLayout` and add one method,
    `Potts.paint!(σ, kinds, l, lat)`. `paint!`, `LatticeSpec` and `core_lattice` are
    declared `public` (so a layout in another package passes ExplicitImports'
    qualified-access check), as are CorePotts' `shift`, `relation` and `embed`. `lat` is the model's `LatticeSpec`: `lat.dims`,
    boundaries, `lat.neighborhood`, the domain mask `lat.domain` and `lat.geometry`;
    `core_lattice(lat)` is the CorePotts `Lattice` for `shift`, `relation` and `embed`.
    The method paints ids `length(kinds) + 1, …` over `σ` (`Int32`, 0 = medium) and
    pushes their kinds. A random layout owns its seed, so adding a layer never changes
    another layer's draws. Planned: Eden growth and splits, BrickWall, Chains, Spheres,
    Fibres, Plane, FromImage/FromMask.
- **PIFF import/export** (pure Julia).
- **MorpheusML importer** (pure Julia, EzXML.jl + expression translation to Symbolics):
  makes the Morpheus model repository a test corpus.
- Live steering: a Makie panel bound to `setp` (MakiePotts).

### 12.9 CompuCell3D and Morpheus semantics matched for portability

| Topic | Rule |
|---|---|
| Neighbor order | `NeighborOrder(k)` cumulative distance shells |
| Proposals | uniform source site, uniform target within the proposal relation; same-cell and frozen picks consume an attempt |
| Contact H | unordered pairs counted once |
| Surface | unlike-neighbour pairs within the surface relation (lattice factor 1 on square) |
| Acceptance | `ΔH ≤ offset` → accept, else `exp(-(ΔH - offset)/T)`; T ≤ 0 tie → ½ |
| Temperature | per-cell ≥ per-kind ≥ global precedence; `combine` default `min` |
| External potential | `H = Σ λ⃗·x_COM`; positive component pushes toward negative coordinates |
| Chemotaxis default | source cell's parameters, falling back to target's |
| Uptake | subtract `max_amount` if `c > max_amount`, else `relative·c` (CompuCell3D `Uptake`) |
| Division | parent side randomized by default; neighbours share a face (no corner-only contact) |
| Morpheus yield | `offset = -yield` |

### 12.10 Deliberately skipped

Viscosity (experimental, hot-path), ConvergentExtension (documented as broken),
OrientedGrowth and Elasticity/Plasticity (covered by polarity and relationships),
InterfaceConstraint (per-copy tracker, unused in published models), per-flip energy
output, BoundaryWalker/BoxWatcher/OpenCL variants (implementation details), Python/C++
interop (D-030), plotting/logging plugins (MakiePotts covers them), ParamSweep
(`EnsembleProblem` covers it).

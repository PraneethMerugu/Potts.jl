# Morpheus → Potts: modeling features we lack

Date: 2026-09-29. Scope: high-level modeling features that Morpheus 2.4 / MorpheusML 5 has and
that `AUTHORING.md` + `research/legacy-spec-adjudication.md` do not yet provide. Filters: D-029
(no exactness-only features, no hot-path cost) and D-030 (Julia-only).

## Sources and method

- **MorpheusML reference.** It ships in the Morpheus GUI and is not hosted online.
  `morpheus.gitlab.io/docs/` redirects to a GitLab login. I used the full text dump in
  [sisyga/morpheus-skills `morpheus/references/morpheusml_doc.txt`](https://github.com/sisyga/morpheus-skills/blob/master/morpheus/references/morpheusml_doc.txt)
  (commit 5a51e93, 2026-09-20; cited below as **[ref: Element]**).
- **Morpheus source.** [gitlab.com/morpheus.lab/morpheus](https://gitlab.com/morpheus.lab/morpheus/-/tree/main/morpheus),
  branch `main`, last commit 2026-05-19. I used it to confirm formulas; paths are given as
  `plugins/...` or `core/...`.
- **Model repository.** [gitlab.com/morpheus.lab/model-repo](https://gitlab.com/morpheus.lab/model-repo),
  2026-07-22, 177 XML files. **Usage counts are over the 50 parseable Published Models** (51
  folders), counted per model, not per file. Model pages are at `https://morpheus.gitlab.io/model/mXXXX/`.
- **Excluded.** Items already in the brief's list and items already ADOPTED in
  `legacy-spec-adjudication.md` §3: yield/acceptance laws, vector state types, `aggregate(...)`,
  SDE/ODE components, OU mechanics, `RemoveCell`, lifecycle priorities, relationship extensions,
  and so on. They appear again only where Morpheus adds something new, which is marked **(new aspect)**.

Published-model IDs used below:

| ID | Model |
|---|---|
| M0006 / M0008 | Guidance by Followers / Robust Guidance by Followers |
| M7121–M7124 | MDCK EMT A–D |
| M7671–M7673 | human iPSC WT / CDH1-KD / ROCK1-KD |
| M9147 / M9148 | liver regeneration (CCl4) / hepatocellular carcinoma |
| M9999 | blastocyst |
| M1703 | Drosophila wing disc Dpp |
| M9495 | cytotoxic T lymphocytes |
| M9496 | APAP liver injury |
| M2051–M2053 | Morphodynamics circuits |
| M5932 / M5933 | growth regulation |
| M4377 | neuromast regeneration |
| M6696 | somitogenesis |
| M2984 | NSC telencephalon |
| M2986 | pancreas islet |
| M4283 | leaf polarity |
| M7675 | human ESC patterning |
| M6296 | airway infection |
| M6694 | Drosophila gap genes |
| M6749 | liver zonation |
| M0007 | tumor spheroid |
| M6342 | migration in complex environments |
| M9342 | porotaxis |
| M7682 | Rac/Rho/Paxillin MMO |
| M7678 | collective motion |
| M7683 | C. elegans aggregation |
| M0237 / M7681 | planarian regeneration |
| M2982 | BMP signaling |
| M7677 | bat & monkey immunity |

---

## Ranked summary

| # | Morpheus element | Group | Published models using it | Value | Perf cost |
|---|---|---|---|---|---|
| 1 | NeighborhoodReporter (cell scope, `scaling=length/cell`) | must | 25/50 | high | none (MCS boundary) |
| 2 | ShapeSurface `scaling="norm"` + `optimal` neighborhood | must | 38/39 CPM models | high | none (constant fold) |
| 3 | Mapper / VectorMapper (cell ← sites, population ← cells) | must | 22 (+4 VectorMapper) | high | none (MCS boundary) |
| 4 | DirectedMotion / PersistentMotion (`update-orientation`) | must | 8 + 5 | high | low |
| 5 | CellDivision `daughterID` + `Triggers` + `oriented` plane | must | Triggers 22, daughterID 7, oriented 5 | high | none |
| 6 | Kind-scoped `System` with own solver / time-step / time-scaling | must | 31 kind-scoped, 13 multi-rate, 8 time-scaling | high | none |
| 7 | HomophilicAdhesion / HeterophilicAdhesion / AddonAdhesion | must | 9 / 1 / 4 | high | low |
| 8 | Domain (expression / image geometry + domain-edge BCs) | must | 11 | high | none |
| 9 | MotilityReporter / DisplacementTracker | must | 12 | med-high | none |
| 10 | System `Euler-Maruyama` (noise in cell ODEs and field PDEs) | must | 3 | med-high | none |
| 11 | Lattice `class="hexagonal"` | nice | 7 | med-high | none in kernel; colouring work |
| 12 | Pure-Julia MorpheusML importer | nice | whole repo (177 files) | high, strategic | none |
| 13 | AddCell (Distribution, fractional Count, overwrite, Triggers) | nice | 4 | med | none |
| 14 | ClusteringTracker (cluster id per cell) | nice | 3 | med | none |
| 15 | VectorField (vector-valued lattice field) | nice | 4 | med | none |
| 16 | CellDeath `replace-with` (neighbor inherits sites) | nice | 0 (15 use plain lysis) | med | none |
| 17 | Time/StopCondition | nice | 0 | med | none |
| 18 | Mapper `Polarisation` | nice | 0 | low-med | none |
| 19 | InterfaceConstraint | skip | 0 | low | hot-path |
| 20 | InsertMedium | skip | 0 | low | — |
| 21 | External, PyMapper | skip | 1, 2 | — | — (D-030) |
| 22 | MonteCarloSampler `stepper="edgelist"` | skip | 1 | — | perf mechanism |
| 23 | Field `well-mixed` | skip | 2 | low | — |
| 24 | Gnuplotter, Logger, HistogramLogger, TiffPlotter, VtkPlotter, CellTracker, ContactLogger | skip | output only | — | — |
| 25 | Tagging, Description, Annotation, ParamSweep | skip | — | — | — |

---

## A. Must-have

### 1. Iterating over neighbor cells, weighted by interface length (NeighborhoodReporter, cell scope)

- **Doc:** [ref: NeighborhoodReporter], `plugins/reporters/neighborhood_reporter.h`; FAQ
  [Neighborhoods](https://morpheus.gitlab.io/faq/modeling/neighborhoods/).
- **What it does.** For each cell, it evaluates an expression on every neighbor cell and reduces
  the results with sum, average, min, max, variance or discrete.
  - `scaling="cell"`: each neighbor counts once.
  - `scaling="length"`: each neighbor is weighted by the shared interface length, measured with
    the ShapeSurface neighborhood.
  - `local.x` refers to the focal cell's own value.
  - `noflux-cell-medium` substitutes the cell's own value at medium interfaces.
  - Writing to a MembraneProperty keeps one value per boundary site.
- **Scientific use.** Juxtacrine and lateral signaling (Delta–Notch-like), contact-dependent
  fate, contact-length-weighted adhesion feedback, and collision rules. M0006/M0008 feed neighbor
  velocities weighted by contact length into a direction rule. In the published model that rule
  is Python (`PyMapper`), which this feature replaces with pure Julia.
- **Models.** 25/50: M0006, M0008, M7121–24, M7671–73, M9147, M9999, M1703, M9495, M9496,
  M2051–53, M5932, M5933, M4377, M6696, M7677, M0007, M4283, M6296.
  11 of these use `scaling="length"`.
- **Status.** The ROADMAP (M2.7) and the adjudication list "distinct-neighbor-cell vs
  contact-weighted queries", but AUTHORING has no syntax for them. Its comprehensions iterate over
  *sites* only. **(new aspect: authoring surface)**
- **Cost.** None on the hot path. The neighbor set and the contact lengths are built once per MCS
  by a KeyedReduce over contact-relation edges, and only when something references them.

```julia
@after_mcs notch  ~ sum(delta[n] * contact(c, n) for n in neighbors(c)) / surface   # scaling=length, mapping=average
@after_mcs n_ct2  ~ count(kind[n] == ct2 for n in neighbors(c))                      # scaling=cell,  mapping=sum
@after_mcs v_nbr  ~ mean(velocity[n] for n in neighbors(c); weights = contact(c, n), default = velocity[c])  # noflux-cell-medium
```

Here `c` is bound in cell-scoped updates, `neighbors(c)` includes medium unless filtered, and
`contact(c, n)` is the interface length.

### 2. Contact and surface energies per unit boundary length (ShapeSurface `scaling="norm"`, neighborhood `optimal`)

- **Doc:** [ref: ShapeSurface], [ref: Interaction], `core/cpm_shape.cpp`
  (`BoundaryLengthScaling`), and the
  [Morpheus 2.3 release notes](https://morpheus.gitlab.io/post/2023/01/09/morpheus-2.3-release-notes/),
  which made `optimal` the default.
- **What it does.** Raw neighbor-pair counts are divided by a lattice- and order-specific
  constant from Magno, Grieneisen & Marée (BMC Biophys 2015):
  - square lattice, orders 1–4: 1.273, 3.074, 5.620, 11.31
  - hexagonal and cubic lattices have their own tables.

  As a result, `J` and `surface` are in *node-length* units and do not depend on the neighborhood
  order. `optimal` selects the most isotropic order (4th square, 4th hex, 6th cubic).
- **Scientific use.** Isotropic cell shapes, and parameters that carry over across neighborhood
  orders and lattices. This is also what makes Morpheus's `SurfaceConstraint mode="aspherity"`
  meaningful: the target is a multiple of `2√(πV)` in node lengths. That mode is used in 27
  models.
- **Models.** 38 of the 39 published CPM models (116/120 CPM files repo-wide).
- **Status.** We have `weights = inverse_distance` but no per-length normalization. **(new)**
- **Cost.** None: the constant is folded at compile time.

```julia
@relations contact = NeighborOrder(4; per_length = true)        # Magno constant folded in
@energy begin
    contacts(contact)  => J[kind, kind′]                          # J per node length
    cells(epi)         => λₛ * (surface - a * 2sqrt(π * volume))^2 # aspherity mode, 2D
end
```

### 3. Reducing over a cell's sites and over populations (Mapper / VectorMapper)

- **Doc:** [ref: Mapper], [ref: VectorMapper], `plugins/reporters/mapper.h`.
- **What it does.**
  - Reduces the sites a cell occupies (a field, or a site or membrane quantity) to a cell
    property. Mappings: average, sum, min, max, variance.
  - Reduces cells, or a kind's cells, to a global value.
  - Pushes a cell property onto a field.
- **Scientific use.** A cell sensing its mean local ligand or oxygen, population totals such as
  viral load or number infected, and mean population velocity.
- **Models.** 22 (Mapper): M9496, M6749, M1703, M6694, M7675, M0007, M9147, M9148, M6296,
  M9999, M7121–24, M2073, M6696, M7682, M2982, M0006, M0008, M7912, M4377.
  4 (VectorMapper): M7678, M0007, M9147, M9148.
  Mappings used across published files: sum 166, average 111, max 24, min 23.
- **Status.** Adopted as `aggregate(expr; over = sites, by = owner)`, but AUTHORING has no
  surface for it. **(new aspect: syntax)**
- **Cost.** None if computed at the MCS boundary. Incremental maintenance is opt-in only.

```julia
@after_mcs U_cell ~ mean(U[s] for s in sites(c))            # Field → cell, mapping=average
@observed  n_inf  ~ count(infected[c] > 0 for c in cells(epi))
@observed  v̄      ~ mean(velocity[c] for c in cells(epi))    # VectorMapper, SVector
```

### 4. Motility biased along a cell vector (DirectedMotion, PersistentMotion)

- **Doc:** [ref: DirectedMotion], [ref: PersistentMotion]; `plugins/motility/directed_motion.cpp`
  (`dE = -strength·dot(update_direction, d)`) and `persistent_motion.cpp`
  (`p ← (1−Δt/τ)p + (Δt/τ)·normalize(Δcentroid)`).
- **What it does.** Adds `ΔH = −μ d̂·u`, where `u` is set by `update-orientation`:
  - `cell-mass-displacement` (default): the shift of the cell's centroid caused by the copy
  - `source-to-target`: the copy direction
  - `surface-normal`: the local outward normal of the cell boundary

  Flags restrict the bias to protrusions and/or retractions. PersistentMotion makes `d` the cell's
  own exponentially averaged displacement direction, with decay time `τ` and an observation window.
- **Scientific use.** Directed and persistent random walks, run-and-tumble, leader cells,
  polarity-driven migration, and calibrating persistence time.
- **Models.** DirectedMotion 8: M0006, M0008, M7121–24, M6342, M9342. PersistentMotion 5:
  M7678, M7671–73, M7121.
- **Status.** The adjudication adopts a bound `direction` (source→target) and SVector state.
  Missing are `δcentroid` and `normal` in proposal scope, and the library laws. **(new aspect)**
- **Cost.** Low. `δcentroid` is already produced by the moments-tracker delta, so the term adds
  a dot product. `normal` needs one neighborhood loop, and only when it is used.

```julia
@variables p(cell)::SVector{2} = zero(SVector{2})
@drive copy => -μ * (dot(p[new], δcentroid[new]) + dot(p[old], δcentroid[old]))   # new/old = gaining/losing cell
@after_mcs p ~ normalize((1 - 1/τ) * Pre(p) + (1/τ) * normalize(centroid - Pre(centroid)))
PersistentMotion(epi; strength = μ, decay_time = τ, window = 1, orientation = CentroidShift())  # library form
```

### 5. Division rules with a daughter index, parent expressions, and a plane from state (CellDivision `daughterID`, `Triggers`, `division-plane="oriented"`)

- **Doc:** [ref: CellDivision], `plugins/miscellaneous/cell_division.h`.
- **What it does.**
  - `Triggers` are rules run in each daughter after division. They can read the parent's values,
    for example `divisions + 1`.
  - `daughterID` binds 1 or 2, which enables asymmetric division.
  - `orientation` takes the plane normal from a vector expression of cell state.

  The same `Triggers` block exists for AddCell and ChangeCellType.
- **Scientific use.** Asymmetric fate or size (stem/progenitor), generation counters, and
  division plane oriented by polarity or tissue axis.
- **Models.** Triggers 22. daughterID 7: M7671–73, M6696, M9999, M2984, M4377.
  Oriented 5: M6696, M9999, M9147, M9148, M4283.
- **Status.** Our state rules are `Split/Copy/Reset/Redraw`, with no daughter index and no
  parent-referencing expression. `Normal((0,0,1))` is constant. **(new)**
- **Cost.** None (MCS-boundary lifecycle).

```julia
@divide cells(stem) when = volume >= 2V₀, along = Normal(polarity),
        Vt => (daughter == 1 ? 100.0 : 50.0), divisions => parent(divisions) + 1,
        kind => (daughter == 2 && rand(Bernoulli(p_asym)) ? progenitor : stem)
```

### 6. Kind-scoped equation blocks with their own solver, step and time scale (CellType-scoped `System`: `solver`, `time-step`, `time-scaling`)

- **Doc:** [ref: System], [ref: Scope], `core/system.h` (`timeStep() = time_step / time_scaling`).
- **What it does.** Each CellType owns Systems of ODEs and rules that run only for cells of that
  type. Every System has its own solver (Dormand–Prince, RK4, Heun, Euler, Euler–Maruyama), its
  own step, and a `time-scaling` that runs its clock faster or slower than model time.
- **Scientific use.** Intracellular networks present only in some kinds (a clock in progenitors,
  viral replication in infected cells), and multi-rate coupling of fast signaling with slow growth.
- **Models.** 31/50 place Systems inside CellTypes. 13 mix Systems with different
  solver/step/scaling. 8 use `time-scaling`: M2074, M2073, M9496, M2072, M7990, M2051–53.
- **Status.** AUTHORING has one global `ode_solver` in `@sweep` and cell ODEs over all cells.
  **(new)**
- **Cost.** None. It lowers cost, because only cells of that kind are batched.

```julia
@equations cells(infected; solver = Tsit5(), dt = 0.1, timescale = 0.1) begin
    D(V) ~ r * V * (1 - V / K) - δ * V
end
@equations model(; solver = Rodas5P()) begin D(h) ~ -h end
```

### 7. Contact energies from adhesion-molecule levels (HomophilicAdhesion, HeterophilicAdhesion, AddonAdhesion)

- **Doc:** [ref: HomophilicAdhesion], [ref: HeterophilicAdhesion], [ref: AddOnAdhesion]; sources
  in `plugins/interaction/homophilic_adhesion.cpp`, `heterophilic_adhesion.cpp` and
  `add_on_adhesion.cpp`.
- **What it does.** Adds a per-length contact term computed from cell or membrane properties of
  both cells:
  - homophilic: `s·min(a, a′)`, or equilibrium bonds when `equilibriumConstant` K is given
  - heterophilic: `s·(min(a₁,a₂′) + min(a₂,a₁′))`, or equilibrium bonds
  - additive: `−(s·a + s′·a′)/2`
- **Scientific use.** Cadherin-dependent sorting, EMT (E-cadherin loss), and knock-down
  phenotypes, with adhesion driven by an intracellular ODE state.
- **Models.** Homophilic 9: M7671–73, M7121, M9147, M9148, M2051–53. Addon 4: M7121–24.
  Heterophilic 1: M7121.
- **Status.** The `contacts` domain lists `owner`/`owner′` and site `x`/`x′`, but reading **cell**
  state of both owners there is not stated, and there are no library laws. F4 in the adjudication
  anticipates the claim-set consequence. **(new: library laws + explicit cell-state reads)**
- **Cost.** Low: two gathers per contact pair. The claim set stays `{old, new}` when the adhesive
  changes only at MCS boundaries. If the adhesive depends on copy-modified quantities, the claim
  set widens; warn in that case.

```julia
@energy contacts => J[kind, kind′] + s * min(cad[owner], cad[owner′])            # homophilic, saturated
@energy contacts => J[kind, kind′] + s * bonds(cad[owner], cad[owner′]; K = Kd)  # equilibrium binding
Homophilic(cad; strength = s, K = Kd)        # library one-liner; also Heterophilic(a₁, a₂), Additive(E)
```

`bonds(a, b; K)` is the standard equilibrium `p − √(p² − ab)` with `p = (a + b + 1/K)/2`.
Morpheus's homophilic code computes `p1 − √(p1 − a1·a2)·strength`, which looks like a bug. Do not
copy it.

### 8. Irregular simulation domains from an expression or image (Domain)

- **Doc:** [ref: Domain], [ref: Space] (CPM/Crypt example), `core/domain.h`.
- **What it does.** Restricts the whole simulation, both the CPM and the fields, to a region
  defined by a Boolean expression, a circle, a hexagon, or a TIFF mask. The domain edge acts as a
  boundary: no copies cross it, and fields get a homogeneous no-flux or constant condition there.
- **Scientific use.** Organ and tissue geometries (crypt, liver lobule, airway, planarian body),
  and porous or confined environments.
- **Models.** 11: M6296, M7675, M6694, M9496, M9147, M9148, M6342, M9342, M0237, M7681, M2982.
- **Status.** We have mask arrays for the CPM. Missing are declarative geometry and treating the
  domain edge as a BC face for fields (per-field BCs are already listed as a gap). **(new aspect)**
- **Cost.** None. The mask becomes site validity, and fields use a masked stencil.

```julia
@lattice Lattice((600, 600); domain = Domain(x -> norm(x .- 300) < 280; boundary = NoFlux()))
@lattice Lattice((600, 600); domain = Domain(load("crypt.tif") .> 0;  boundary = Dirichlet(0.0)))   # TiffImages.jl
```

### 9. Cell velocity and displacement (MotilityReporter, DisplacementTracker)

- **Doc:** [ref: MotilityReporter], [ref: DisplacementTracker].
- **What it does.** Gives per-cell velocity over a window (Δcentroid/Δt), displacement from the
  cell's initial position, and population mean-squared displacement.
- **Scientific use.** Motility calibration (MSD, persistence), and velocity-dependent rules such as
  mechanical guidance in M0006/M0008.
- **Models.** 12: M7671–73, M7121–24, M2073, M9342, M7683, M0006, M0008. DisplacementTracker is used
  in 4 models.
- **Status.** Unwrapped periodic moments are adopted, and `Pre(centroid, k)` gives a window.
  Missing are the birth snapshot and library observables. **(new aspect, small)**
- **Cost.** None: a ring buffer, kept only if referenced.

```julia
@observed velocity(cell)     ~ (centroid - Pre(centroid, w)) / (w * mcs_duration)
@observed displacement(cell) ~ centroid - at_birth(centroid)
@observed msd                ~ mean(norm2(displacement[c]) for c in cells(tcell))
```

### 10. Noise inside the model's own equations, for cells and fields (System `solver="Euler-Maruyama"`; `rand_norm` in a DiffEqn)

- **Doc:** [ref: System], `core/system.cpp` (the Euler solver auto-detects noise).
- **What it does.** Stochastic ODEs per cell, and stochastic reaction–diffusion where every site
  gets independent noise.
- **Scientific use.** Noisy gene circuits that break symmetry (ESC patterning), noise-driven Rho
  GTPase dynamics, and stochastic polarity.
- **Models.** 3: M7675 (field SPDE), M7682, M9342.
- **Status.** The adjudication adopts SDE *components* and OU mechanics. Missing is MTK
  `@brownians` inside `@equations` at field and cell scope. **(new aspect)**
- **Julia equivalent.**
  - MTK `@brownians`
  - StochasticDiffEq solvers for cell-scope SDEs (`EM`, `SRIW1`)
  - per-site addressed `Normal` draws × √dt for fields
- **Cost.** None on the hot path (an MCS-boundary stage).

```julia
@brownians ξ
@equations begin
    D(b) ~ β * b^2 / (1 + b^2 + nog^2) - b + σ * ξ     # b(field): independent per site
    D(r) ~ f(r, ρ) + σᵣ * ξ                           # r(cell): independent per cell
end
@sweep Metropolis(; temperature = T, sde_solver = EM(), field_solver = EulerMaruyama(substeps = 4))
```

---

## B. Nice-to-have

**11. Hexagonal lattice** (Lattice `class="hexagonal"`)
- **Doc:** [ref: Lattice]; Magno constants in `core/cpm_shape.cpp`.
- **Models.** 7: M0006, M0008, M9147, M9148, M4283, M2984, M7677.
- **Status.** DEFERRED in the adjudication. This evidence argues for promoting it, and it is a
  prerequisite for importing those models.
- **Cost.** None in the kernel: axial coordinates make it a plain stencil. The checkerboard
  colouring needs a hex-aware footprint.

```julia
@lattice Lattice((500, 1500); structure = Hexagonal(), boundary = Periodic(), neighborhood = NeighborOrder(1))
```

**12. Pure-Julia MorpheusML importer** (D-030 allows it)
- **Value.** The 177 repository files become a validation corpus, and users can migrate.
- **Design.** Parse with EzXML.jl, then translate muParser expressions into Symbolics
  (`if(c,a,b)` → `ifelse`, `rand_norm` → `rand(Normal())`, `cell.center` → `centroid`). Map
  plugins onto items 1–11. `PyMapper` and `External` elements are rejected with a clear error.
- **Depends on** 1–8 and 11.

```julia
sys = import_morpheusml("M0006_guidance-by-followers_model.xml")   # returns a PottsSystem
```

**13. Cell creation with spatial density, fractional counts, overwrite, and init rules** (AddCell)
- **Doc:** [ref: AddCell].
- **Models.** 4: M6296, M7121, M9496, M2986.
- **What it adds.** `Count` may be fractional (realised stochastically), `Distribution` is a
  spatial weight expression, `overwrite` places the cell over an existing cell, and `Triggers`
  initialize the new cell.
- **Cost.** None: one weighted draw over sites, only when a creation fires.

```julia
@create medium rate = 0.01, kind = tumor, overwrite = false,
        at = Weighted(exp(-norm2(position .- c₀) / 2σ^2)), birth_time => t
```

**14. Cluster labelling** (ClusteringTracker)
- **Doc:** [ref: ClusteringTracker].
- **Models.** 3: M2052, M2053, M7683.
- **What it does.** Connected components of same-kind cell adjacency, with a cluster id written to
  each cell.
- **Cost.** None: MCS-boundary label propagation, which also works on GPU.

```julia
@after_mcs Every(100) cluster ~ components(cells(ct1); adjacency = neighbors, exclude = frozen)
```

**15. Vector-valued lattice fields** (VectorField)
- **Doc:** [ref: VectorField].
- **Models.** 4: M9147, M9148, M0237, M7681.
- **What it adds.** Extends the adopted SVector state to field scope, with a component-wise `Δ`.
- **Cost.** None.

```julia
@variables P(field)::SVector{2} = zero(SVector{2})
@equations D(P) ~ Dp * Δ(P) - δ * P
```

**16. Lysed cell's sites go to a neighbor** (CellDeath `replace-with`)
- **Doc:** [ref: CellDeath].
- **What it does.** Instead of medium, the dead cell's sites go to the neighbor with the longest
  interface, or to a random neighbor weighted by interface. This supports tissues without medium.
- **Usage.** No published model uses the replace-with or shrinkage variants; 15 use plain lysis
  (adopted as `RemoveCell`).
- **Cost.** None.

```julia
@retire cells(epi) when = rand(Bernoulli(p_death)), fill = LongestInterfaceNeighbor()
```

**17. Stop condition** (Time/StopCondition)
- **Doc:** [ref: Time].
- **What it does.** Ends the run when a condition holds, which saves time in ensembles and
  simulation-based inference. It maps to SciML `terminate!` and gives `ReturnCode.Terminated`.
- **Usage.** No published model uses it.
- **Cost.** None.

```julia
@stop count(tumor) == 0
```

**18. Polarization vector of a distribution** (Mapper `Polarisation`)
- **Doc:** [ref: Mapper].
- **What it does.** Gives the direction of maximum membrane or field quantity relative to the
  centroid. It is sugar over item 3.

```julia
@after_mcs pol ~ sum((position[s] - centroid) * x[s] for s in boundary(c))
```

---

## C. Skip (with reason)

| Element | Reason |
|---|---|
| InterfaceConstraint | Needs a per-cell × per-kind interface-length tracker updated on every accepted copy, which is a hot-path cost. No published model uses it. Item 1 gives the same quantity at MCS granularity for feedback rules. |
| InsertMedium (Käfer 2007) | No published model uses it. The adopted site-kind conversion plus item 1 can express it later as a lifecycle rule. |
| External, PyMapper | D-030: no Python or shell runtimes. PyMapper (M0006/M0008) only iterated neighbor lists, which item 1 covers in Julia. |
| MonteCarloSampler `stepper="edgelist"` | A performance mechanism, not a modeling feature. Our algorithms own this. |
| Field `well-mixed` | Equivalent to a `c(model)` variable. Used in 2 models. |
| Gnuplotter, Logger, HistogramLogger, TiffPlotter, VtkPlotter, CellTracker (ISBI XML), ContactLogger, DependencyGraph | Output only. Covered by `saveat`, Tables, MakiePotts and the planned HDF5/Zarr sinks. A VTK sink could later be a small WriteVTK.jl extension. |
| Tagging, Description, Annotation | Metadata. MTK variable metadata and docstrings cover it. |
| ParamSweep | Covered by `EnsembleProblem` and `remake`. |
| Contact `negate`, Interaction `default` | Trivial with kind-indexed `J`. |

## D. Already expressible: add library one-liners, no engine work

| Morpheus | Our form |
|---|---|
| MetropolisKinetics `yield` (expression, may use `dir`) | Morpheus adds it to ΔH before the Boltzmann test (`core/cpm_sampler.cpp`: `dE = dInteraction + dCell + yield`). So it is exactly `@drive copy => Y` (10 models). The adopted `yield` option must use these additive semantics to import Morpheus parameters. |
| FreezeMotion (12 models) | `@constraint !(frozen[owner[target]] \|\| frozen[owner[source]])`. Suggest a `Freeze(when = expr)` helper. |
| Chemotaxis `contact-inhibition`, `retraction`, `protrusion` (10 models) | Masks in the drive, e.g. `* (kind[target] == medium)`. The saturating variant is already listed. |
| Protrusion (Act, 8 models) | Wortel example in AUTHORING §10. |
| Haptotaxis, SurfaceMotion | `@drive copy => -μ * a[target]`, `@drive copy => -μ * act[target] * (new != 0)` |
| SurfaceConstraint `mode="aspherity"` (27), `exponent` | A `cells =>` term. It needs item 2 for node-length units. |
| LengthConstraint (length / eccentricity) | `elongation` and inertia moments. |
| ChangeCellType (8), CellDeath lysis (15) | `@transition`, `@retire` / `RemoveCell`. Triggers need item 5's expression rules. |
| MechanicalLink | `@relationship` with `@link` / `@unlink when = rand(Bernoulli(p))`. |
| Function, Intermediate, Constant, VectorEquation | Julia functions, `@observed`, `@parameters`, SVector expressions. |
| NeighborhoodReporter at global/site scope | Site generator comprehensions over relations. |
| celltype.X.size, `cell.id > 0` counting | `count(kind)`. |
| SpaceSymbol | `position`. |

## E. Usage evidence for gaps already on the list (not re-proposed)

| Gap | Published models |
|---|---|
| Membrane properties (MembraneProperty/MembraneLattice) | 9 |
| Sampled events with trigger memory | 18 use Event. Counting Event and CellDivision `trigger` attributes, 14 models use `when-true` and 6 use `on-change`; 5 models set Condition `history`. |
| Initializer layouts | InitCellObjects 17, InitProperty 5, TIFFReader 2, InitVoronoi 1, CSVReader 0 |
| Per-field boundary conditions (BoundaryValue) | 4 |
| Delay states (DelayProperty) | 1 |
| Saturating chemotaxis | 1 (M9496) |
| SBML import | 0 published; 1 built-in example (MAPK_SBML). Julia route: SBMLToolkit.jl → MTK → `@components`. |

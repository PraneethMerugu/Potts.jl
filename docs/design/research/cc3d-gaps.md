# CompuCell3D feature gaps vs. the new Potts authoring surface

Sources: CC3D 4.x reference manual (`R/` = https://compucell3dreferencemanual.readthedocs.io/en/latest/),
which now also hosts the Python scripting manual. For plugins with no manual page, the source is
cited (`S/` = https://github.com/CompuCell3D/CompuCell3D/tree/master/CompuCell3D/core/CompuCell3D/).
Checked against `AUTHORING.md` and `INTERNALS.md` as of 2026-09-29.

Filters applied:
- Only modeling features. Anything whose main value is exactness, bitwise replay, or CPU scheduling was
  left out.
- Nothing that adds per-attempt cost for models that don't use it. "Hot-path" means the feature adds
  work to every copy attempt of a model that uses it.
- **Julia-only dependencies** (maintainer rule). CC3D features built on Python or C++ interop
  (RoadRunner, Antimony, MaBoSS, Tissue Forge, Python steering and steppables) are mapped to a Julia
  equivalent where one exists. Otherwise they go under Skip.
- Gaps we already knew about are not repeated here: multiple media, independent field grids, per-field
  BCs, MM exchange, saturating/log chemotaxis, staged protocols, sampled events, delays, membrane
  properties, OU pressure/tension, lagged histories, SBML import, compartments, exact
  connectivity/holes, initializer layouts, HDF5/Zarr, lineage, FPP links created during copies, and
  relationship retune.

Already expressible (no gap): per-cell λ/targets for "LocalFlex" plugins (via `x(cell)` variables),
Flex by-type tables (`J[kind,kind]`), chemotaxis towards given types (a `kind[·]` mask in `@drive`),
`WeightEnergyByDistance` (`weights = inverse_distance`), CC3D `Depth` (`Ball(r)`), frozen types, wall,
`Flip2DimRatio` (`attempts_per_site`), steppable frequency (`Every(n)`), parameter scans
(`EnsembleProblem`), restarts (`checkpoint`), cell creation and deletion, type change
(`@transition`), per-cell ODEs, and multi-field reaction–diffusion (MTK `@equations`).

---

## 1. Ranked gap table

Val = value (H/M). Cost = perf cost (none / low / hot-path). "none" means the work happens at the MCS
boundary or inside the field step, never per copy attempt.

### Must-have

| # | CC3D feature (doc) | What it does scientifically | Typical use | Val | Cost | Proposed syntax |
|---|---|---|---|---|---|---|
| 1 | **Per-type / per-cell FluctuationAmplitude + `FluctuationAmplitudeFunctionName`** (R/potts.html, R/setting_cell_membrane_fluctuation_ona_cell-by-cell_basis.html) | Temperature becomes a property of each cell (membrane motility). The copy uses `combine(T_source, T_target)`; medium never takes part. | Motile vs. stationary types (e.g. macrophage vs. bacteria), condensing vs. non-condensing, cells that "freeze" when they differentiate | H | low (one table or gather per attempt, and only when T is not a scalar) | `@parameters Tk[kind] = [0, 10, 5]`<br>`@sweep Metropolis(; temperature = Tk[kind], combine = min)`  # or `max`, `mean`<br>per cell: `temperature = T_cell` with `T_cell(cell)` |
| 2 | **NeighborTracker** (cell-neighbor list + common contact area) (R/neighbor_tracker.html, R/example_contact_events.html) | A cell-level graph: which cells touch, and over how much shared face area. CC3D counts face-sharing neighbors only, so corner contact does not count. | Juxtacrine signalling (Delta–Notch), contact inhibition, contact-triggered events such as T-cell/APC contact and phagocytosis ("only touching macrophages"), and contact-area-weighted exchange (the CC3D AdvectionDiffusion-on-cells idea) | H | none (rebuilt from the lattice at the MCS boundary, only if referenced) | `@after_mcs notch ~ Pre(notch) + k*sum(area(cell,b)*delta[b] for b in neighbors(cell))`<br>`@transition cells(bact) => dead when = all(kind[b] == macrophage for b in neighbors(cell))` |
| 3 | **FieldSecretor `amountSeenByCell`, `totalFieldIntegral`, COM sampling** (R/field_secretion.html, R/reference_field_secretor.html) | Integrates a field over a cell's sites, or samples it at the COM, so field levels can drive the cell. | Couples PDE fields to per-cell ODEs (receptor occupancy, O₂-driven growth and death) | H | none (segmented reduction at the MCS boundary) | cell scope: `integral(c)`, `mean(c)`, `c(centroid)`; model scope: `integral(c; over = sites)`<br>`@equations D(g) ~ kg*mean(o) - δg*g` |
| 4 | **AdhesionFlex / ContactLocalProduct / ContactMultiCad / ContactLocalFlex** (R/adhesion_flex_plugin.html; S/plugins/ContactLocalProduct, S/plugins/ContactMultiCad) | Contact energy computed from per-cell adhesion-molecule levels: `E = Σ_pairs −Σ_mn k_mn F(N_m(σ), N_n(σ′))`. `F` is user-defined (e.g. `min`). ContactLocalProduct uses `offset − N·N′·k`. | Cadherin-driven sorting where expression changes over time; EMT (dropping E-cad); differential adhesion coupled to gene networks | H | low (per-neighbour gather of cell state; loses the constant J-table optimisation, but only for this term) | Allow owner-indexed cell state in `contacts`:<br>`@variables N(cell)[1:3]`<br>`@energy contacts => -sum(k[m,n]*min(N[owner][m], N[owner′][n]) for m in 1:3, n in 1:3)`<br>helper: `AdhesionMolecules(N, k; binding = min)` |
| 5 | **Per-type diffusion/decay: DiffusionSolverFE `DiffusionCoefficient CellType`, `DoNotDiffuseTo`, `DoNotDecayIn`; RDFVM `DiffusivityByType` (harmonic-mean faces)** (R/diffusion_solver.html, R/flexible_diffusion_solver.html, R/reaction_diffusion_solver_fvm.html) | Diffusivity depends on what occupies each site (cells as barriers, dense tissue, medium), in conservative flux form. | ECM or tissue barriers, impermeable bacteria, ligand that decays only in medium | H | none (field step) | `@equations D(c) ~ ∇⋅(Dk[kind] * ∇(c)) - δk[kind]*c`<br>lowered as FV with face diffusivity `2DᵢDⱼ/(Dᵢ+Dⱼ)`; `Dk[kind] = 0` means "do not diffuse to" |
| 6 | **SteadyStateDiffusionSolver(2D)** (Helmholtz `∇²c − kc = F`) and large-D solvers (Kernel) (R/steady_state_diffusion_solver.html, R/kernel_diffusion_solver.html) | Quasi-static fields for fast diffusers (O₂, small molecules) where explicit Euler would need hundreds of substeps. | Tumour oxygenation, fast morphogens | H | none (one linear solve per MCS; GPU Krylov via LinearSolve.jl) | `@equations 0 ~ Do*Δ(o) - k*o - q*(kind == tumor)`<br>`@sweep Metropolis(...; field_solver = QuasiStatic(KrylovJL_CG()))`  # a `0 ~` equation over a field marks it quasi-static |
| 7 | **DiffusionSolverFE automatic stability rescaling + interleaved secretion** (R/diffusion_solver.html, R/diffusion_solver_settings.html) | Picks the number of substeps from the CFL bound (CC3D: `DΔt/Δx² < 0.16` in 3D) and splits secretion evenly across substeps. `DoNotScaleSecretion` restores the old secrete-then-diffuse behaviour. | Every field model; avoids silent instability | H | none | `field_solver = ExplicitEuler(substeps = Auto(safety = 0.9), source_splitting = :interleaved)`  # or `:lumped` (FlexibleDiffusionSolverFE) |
| 8 | **Secretion location modes** (`secreteInsideCell`, `…AtBoundary`, `secreteOutsideCellAtBoundary`, `…OnContactWith`, `…AtCOM`, `…ConstantConcentration`, `SecretionOnContact`) (R/reference_field_secretor.html, R/secretion.html) | Places the source term inside a cell, on its inner rim, on the ring just outside it, only where it touches given types, at its COM, or as a clamp. | Membrane-bound release, contact-dependent secretion (e.g. medium secretes on contact with amoeba), point sources | H | none (field step; site predicates are neighbourhood comprehensions at the MCS boundary) | library site predicates: `inside(k)`, `inner_rim(k)`, `outer_rim(k)`, `touching(k, k′)`, `at_centroid(k)`<br>`D(c) ~ … + σ*outer_rim(tumor; touching = medium) + σ₂*at_centroid(mac)`<br>clamp: `@after_mcs c ~ ifelse(inside(src), c₀, Pre(c))` |
| 9 | **Polarity / motility family: ImplicitMotility + BiasVectorSteppable (white, persistent `b ← αb + (1−α)ξ`, manual), CellOrientation, per-cell ExternalPotential `lambdaVec`** (S/plugins/ImplicitMotility, S/steppables/BiasVectorSteppable, S/plugins/CellOrientation, R/external_potential_plugin.html, R/cell_motility_applying_force_to_cells.html) | Active persistent random walks. ImplicitMotility gives `ΔE = −λ Σ_{src,tgt} unit(ΔCOM)·b`, where `b` is a per-cell polarity vector updated each MCS. | Leukocyte and fibroblast migration, collective migration, persistence-time fitting | H | low (uses δcentroid, which is already tracked) | needs **vector-valued cell state** and `δcentroid` in the copy context:<br>`@variables b(cell)[1:N] = zeros(N)`<br>`@drive copy => -λm*sum(dot(unit(δcentroid[c]), b[c]) for c in (owner[source], owner[target]))`<br>`@after_mcs b ~ α*Pre(b) + (1-α)*rand(UnitSphere(N))`<br>helper: `PersistentMotility(b; strength = λm, persistence = α)` |
| 10 | **LengthConstraint (2D, and 3D with `MinorTargetLength`) + MomentOfInertia semiaxes/orientation** (R/length_constraint.html, R/calculating_elongation_term.html, R/moment_of_inertia.html) | Holds cells at a target major length (and minor width in 3D) for elongated cells. CC3D definition in 2D: `L = 4√(λ_max(I)/V)`, where I is the inertia tensor about the COM. | Merks-style vasculogenesis, elongated epithelial and muscle cells | H | low (inertia deltas are already tracked when `inertia` is used) | publish named cell quantities with CC3D definitions: `major_length`, `minor_length`, `semiaxes`, `orientation`<br>`cells(ec) => λL*(major_length - L₀)^2 + λL*(minor_length - W₀)^2`  # 3D, same λ as CC3D<br>helper: `LengthConstraint(ec; target = L₀, minor = W₀, strength = λL)` |
| 11 | **Per-cell stochastic intracellular models** (Julia replacement for MaBoSS and stochastic RoadRunner) (R/maboss.html, R/sbml_solver.html) | Per-cell continuous-time Boolean networks (MaBoSS runs a CTMC over Boolean states) and stochastic reaction networks, coupled to cell and field state. | Cell-fate decisions, noisy gene expression, signalling-driven transitions | H | none (batched SSA or tau-leap per cell at the MCS boundary) | Julia only: ModelingToolkit `JumpSystem` / Catalyst.jl / JumpProcesses.jl as a per-cell `@components`:<br>`@named grn = JumpSystem([ConstantRateJump(r*(Bext*(1-B))*(1-A), [A ~ 1]), …], t, [A,B], [r,Bext])`<br>`@components grn = grn`  # per-cell instance<br>`@equations grn.Bext ~ touching(macrophage)` |
| 12 | **FocalPointPlasticity anchors** (`new_fpp_anchor`: cell-to-fixed-point spring) (R/focal_point_plasticity.html) | Tethers a cell's COM to a point in space with `λ(l − L)²` and breaks the tether at `MaxDistance`. | Substrate/ECM attachment, pinned tissue boundaries, traction assays | M-H | none (edge term; same machinery as `@relationship`) | `@relationship anchor(cell, point)  distance = norm(centroid - point), capacity = 1`<br>`@energy edges(anchor) => k*(distance - ℓ₀)^2`<br>`@link anchor when = kind == epi && touching(substrate), at = centroid`<br>`@unlink anchor when = distance > ℓmax` |

### Nice-to-have

| # | CC3D feature (doc) | What it does | Typical use | Val | Cost | Proposed syntax |
|---|---|---|---|---|---|---|
| 13 | **Acceptance options: `Offset`, `KBoltzman`, `AcceptanceFunctionName=FirstOrderExpansion`, custom acceptance expression** (R/potts.html; S/Potts3D/CustomAcceptanceFunction.cpp) | Changes the Metropolis kernel: `P = exp(−(ΔE−δ)/(kT))`, or `1−(ΔE−δ)/(kT)`, or any user function `f(T, ΔE)`. | Yield threshold for copies (offset), reproducing legacy models | M | none | `@sweep Metropolis(; temperature = T, offset = -0.1, kB = 1.2, acceptance = FirstOrder())`  # or `acceptance = (T, ΔH) -> …` |
| 14 | **ContactOrientation / OrientedContact** (S/plugins/ContactOrientation) | Anisotropic adhesion: `J + α|cos θ|`, where θ is the angle between (site − COM) and the cell's polarity vector. | Planar cell polarity, convergent extension (Zajac) | M | low–hot-path (per-neighbour trig, only in models that use it) | `contacts => J[kind,kind′] + α[kind]*abs(cosangle(position - centroid[owner], p[owner])) + α[kind′]*abs(cosangle(position′ - centroid[owner′], p[owner′]))`  (needs `position`/`position′` in contacts, and #9) |
| 15 | **RDFVM interface permeability (`SimplePermInt`, `PermIntCoefficient`, `PermIntBias`)** (R/reaction_diffusion_solver_fvm.html) | Membrane-limited transport across cell–cell and cell–medium interfaces with a directional bias: `F = (b c′ − a c)/Δx`. | Intracellular vs. extracellular pools, transporter asymmetry | M | none (field step) | `D(c) ~ ∇⋅(Dk[kind]*∇(c)) + membrane_flux(c; P = P[kind,kind′], bias = b[kind,kind′])` |
| 16 | **FluctuationCompensator** (R/fluctuation_compensator_addon.html) | Keeps the total amount of each species per cell and in medium unchanged across copies (Marée 2012), using a uniform correction per subdomain. | Intracellular fields in moving cells (polarity, Rac/Rho) | M | low (per-accepted-copy accumulation; rescale at MCS boundary) | `@variables u(field) = 0.0, [conserve = :per_cell]` |
| 17 | **Hexagonal lattice** (`LatticeType Hexagonal`, 3D rhombic dodecahedra) (R/lattice_type.html) | Less lattice anisotropy; order 1–2 is enough. | Isotropic shapes at low neighbour order | M | low (parity-dependent stencil tables) | `@lattice Lattice((200,200); geometry = Hexagonal(), neighborhood = CC3DOrder(1))` |
| 18 | **Mitosis options: along minor axis, parent-child position flag** (R/mitosis.html) | Division plane through the COM along the major or minor axis, a given normal, or a random plane. The side the parent keeps is randomised by default to avoid drift bias. | Hertwig's rule vs. its opposite, stem-cell asymmetry | M | none | `@divide cells(k) when = …, along = minor_axis(), parent_side = RandomSide()`  # or `Left()`/`Right()` |
| 19 | **PIFF / PIF initializer and PIFDumper** (R/pif_initializer.html, R/pif_dumper.html) | Plain-text `id type x1 x2 y1 y2 z1 z2` cell layouts. It is CC3D's model-exchange format. | Porting CC3D models and initial states | M | none | `labels, kinds = read_piff("init.piff"; kinds = sys)`; `write_piff(path, sol[t])` |
| 20 | **Per-cell connectivity toggle** (`cell.connectivityOn`, `setConnectivityStrength`) (R/connectivity.html) | Enforces connectivity only for chosen cells (e.g. elongating ones). | Cost control, cells that switch state | M | none | `@constraint connectivity(cells(ec) where needs_conn)`  (with `needs_conn(cell)`) |
| 21 | **Stop on condition** (`stop_simulation`, `set_max_mcs`) (R/steppable_frequency.html) | Ends a run on a model event. | Invasion reaches the edge, extinction | M | none | `@terminate when = count(tumor) == 0 \|\| maximum(centroid[1]) > L - 5`  (lowers to SciML `terminate!`) |
| 22 | **EnergyFunctionCalculator Statistics** (R/energy_function_calculator.html) | Mean and std of ΔE per energy term for accepted, rejected and all copies. | Parameter calibration: which term dominates | M | opt-in only (off by default; accumulators per attempt when on) | `solve(prob, alg; diagnostics = TermStatistics(every = 10))` |
| 23 | **Steering panel** (Julia replacement for Python steering) (R/steering_changing_python_parameters_using_UI.html) | Change parameters live while a simulation runs. | Teaching, exploration | M | none | MakiePotts: `steer(integrator, [λ => 0:0.1:5, T => 1:50])` built on `SymbolicIndexingInterface.setp` + Makie `SliderGrid` |
| 24 | **`DimensionType 2.5D`** (in-plane-only voxel copies; energies still use 3D neighbours) (S/Boundary/BoundaryStrategy.cpp; demo `Models/cellsort_2_5_D`) | Monolayer on a substrate with 3D contact energetics. | Epithelial sheets | M | none | `@relations proposal = Moore(1; axes = (1, 2))`  # a relation helper; nothing new in the engine |
| 25 | **Compartment add-ons** (extends the known "cell compartments" gap): ContactInternal, ClusterSurface, cluster mitosis, Polarization23, Curvature (R/compartments.html, R/dividing_clusters.html, R/curvature.html; S/plugins/ClusterSurface, S/plugins/Polarization23) | Internal vs. external J, a surface constraint on the whole cluster, dividing clusters as a unit, a polarity vector between two compartments' COMs, and bending stiffness of chained compartments. | Nucleus/cytoplasm models, Myxococcus, polarised epithelia | M | low | `contacts => ifelse(cluster == cluster′, Jint[kind,kind′], J[kind,kind′])`<br>`clusters(k) => λ*(cluster_surface - S₀)^2`<br>`@divide clusters(k) when = cluster_volume > 250, along = RandomPlane()` |

### Skip (with reason)

| CC3D feature | Reason |
|---|---|
| BoundaryWalker `MetropolisAlgorithm`, GlobalBoundaryPixelTracker, BoxWatcher, lattice resize/shift, OpenMP/OpenCL solver variants, FastDiffusionSolver2D | Performance and scheduling only. They conflict with uniform GPU checkerboard sweeps. BoundaryWalker is documented as not working with OpenMP. |
| Viscosity plugin (S/plugins/Viscosity) | Experimental, and it adds per-attempt neighbour-velocity loops (hot path). The source also returns 0 for the first 100 MCS. |
| ConvergentExtension (R/convergent_extension.html) | The manual calls it Tier-2 and says they had "difficulties … getting it to work". It recommends the filopodial-tension model (FPP-based) instead. |
| OrientedGrowth / OrientedGrowth2 (S/plugins/OrientedGrowth) | Specialised penalty on width across an axis. #10 + #9 express it. |
| Elasticity / Plasticity (S/plugins/Elasticity) | Superseded by FPP. `@relationship` + `edges(...)` already covers it. |
| KernelDiffusionSolver | Needs periodic BCs and ignores DoNotDiffuseTo. #6 (quasi-static/implicit) covers the use case. |
| AdvectionDiffusionSolver (on cell field) | Marked "experimental … not fully curated". The contact-area graph in #2 covers the cell-field idea. |
| FPP `ActivationEnergy` / link creation during pixel copies | Already a known gap, and it is hot-path. |
| Per-flip energy output (`OutputCoreFileNameSpinFlips`) | Hot-path I/O, and mostly useful for replay. |
| RandomSeed semantics | Bitwise replay is excluded by the filter. |
| Tracker plugins as user modules (VolumeTracker, SurfaceTracker, CenterOfMass, PixelTracker, BoundaryPixelTracker, NeighborTracker, CellTypeMonitor, BoundaryMonitor, MomentOfInertia) | Internal. Our compiler picks trackers from the Hamiltonian (INTERNALS §2.5). Only the quantities they expose are gaps (#2, #10). |
| ChemotaxisDicty | Specialised Dictyostelium variant (S/plugins/ChemotaxisDicty). General `@drive` covers it. |
| MaBoSS (Python/C++) | Replaced by #11: MTK `JumpSystem` / JumpProcesses.jl. There is no maintained pure-Julia MaBoSS `.bnd` parser, so no importer. |
| SBML Solver / libRoadRunner (C++) | Already a known gap. The Julia route is SBMLToolkit.jl → MTK/Catalyst `@components`. |
| Antimony / Tellurium / CellML (R/building_SBML_models_efficiently_with_Antimony_and_CellML.html) | No pure-Julia Antimony parser. The Julia counterpart is the Catalyst.jl `@reaction_network` DSL, which is authored directly with no importer. CellML: CellMLToolkit.jl exists; defer. |
| Tissue Forge interop | C++/Python and center-based. No Julia equivalent is needed for a CPM package. |
| Python steppables, `cell.dict`, extra visualization fields, attribute tracking | Replaced by `@before_mcs`/`@after_mcs`, `x(cell)` variables, `@observed`, and MakiePotts recipes. SciML callbacks are the escape hatch. |
| muParser expressions (BindingFormula, LinkConstituentLaw, AngularTerm, custom acceptance, InitialConcentrationExpression) | Native Julia expressions already do this better. |
| CC3DML import | Large surface for little gain. PIFF (#19) plus the semantics below give most of the portability. |

---

## 2. CC3D semantics to match for model portability

All of these come from the manual or source cited, not from assumptions.

### 2.1 NeighborOrder (and a correction to AUTHORING.md §3)

- CC3D sorts lattice offsets by Euclidean distance. **`NeighborOrder = k` includes every offset in the
  first k distinct distance shells.** It is cumulative, so it is a Euclidean ball with radius equal to
  the k-th distinct distance (S/Boundary/BoundaryStrategy.cpp,
  `getMaxNeighborIndexFromNeighborOrderNoGenImpl`; R/potts.html "Ranking of pixel neighbors").
  - 2D square: order 1 → 4, 2 → 8, 3 → 12, 4 → 20, 5 → 24, 6 → 28 neighbours (d² = 1, 2, 4, 5, 8, 9).
  - 3D cubic: order 1 → 6, 2 → 18, 3 → 26, 4 → 32, 5 → 56, 6 → 80 (d² = 1, 2, 3, 4, 5, 6).
  - So CC3D order 1 = `VonNeumann(1)`, not `Moore(1)`. 2D order 2 = `Moore(1)`, but **3D order 2 has 18
    neighbours, not Moore(1)'s 26**. 2D order 3 = `Ball(2)` (12), which is neither Moore nor von Neumann.
  - **AUTHORING.md's `Shell(k)` ("exactly order k (CompuCell3D neighbor order semantics)") is wrong.**
    CC3D orders are cumulative. Proposed fix: `CC3DOrder(k) ≡ Ball(√d²ₖ)`, with `d²ₖ` the k-th distinct
    squared distance. Keep `Shell(k)` only as "the k-th shell alone" and drop the CC3D claim.
  - Hex lattice: the same ranking uses hex distances, so order 1 = 6 neighbours in 2D.
- **Each module has its own order. They are independent, and each defaults to 1:**
  - Potts: the copy-source neighbourhood. `PottsParseData` default `neighborOrder = 1`. Alternatively
    `FlipNeighborMaxDistance`, a Euclidean depth (default 1.1).
  - Contact, AdhesionFlex, ContactLocalProduct and ContactMultiCad: `NeighborOrder` or `Depth`.
  - Surface: `NeighborOrder` inside the Surface plugin, since 4.6.0.
  - FPP (link search), BoundaryPixelTracker and Curvature: each has its own order.
  - Our `@relations` model this already. The importer and docs must map each module to its own relation.
- `2.5D`: voxel-copy offsets with z ≠ 0 are removed; energy neighbourhoods stay 3D.

### 2.2 Pixel-copy proposal and MCS (S/Potts3D/Potts3D.cpp `metropolisFast`)

- Attempts per MCS = `Nx·Ny·Nz·Flip2DimRatio` (default 1).
- Each attempt:
  1. Pick a uniformly random site `pt`. This is the source.
  2. If its owner is frozen, skip.
  3. Pick a uniformly random neighbour within the Potts order. This is the target.
  4. If the target has the same owner, or a frozen owner, skip.
  5. Evaluate ΔE for copying the source's owner into the target.
- **Skipped attempts still count against the attempt budget.**
- Medium can never be frozen.
- Frozen cells still count in contact energies (R/building_a_wall.html).

### 2.3 Acceptance (S/Potts3D/DefaultAcceptanceFunction.h, FirstOrderExpansionAcceptanceFunction.h)

- For T > 0: `P = 1` if `ΔE ≤ offset`, else `exp(−(ΔE − offset)/(kB·T))`.
  - Defaults: `offset = 0`, `kB = 1` (`<Offset>`, `<KBoltzman>`).
  - First-order variant: `max(0, 1 − (ΔE − offset)/(kB·T))`.
- For **T ≤ 0**: `P = 0` if ΔE > 0, **0.5 if ΔE == 0**, 1 if ΔE < 0. Note the tie rule.
- Connectivity plugins are a hard reject, applied after acceptance. "The value of Penalty is
  irrelevant."
  - ConnectivityGlobal is not applied to a cell that is already fragmented.

### 2.4 Fluctuation amplitude (R/potts.html; S/Potts3D/StandardFluctuationAmplitudeFunctions.cpp)

- Per-cell resolution order:
  1. `cell.fluctAmpl ≥ 0`
  2. the type value (`FluctuationAmplitudeParameters`)
  3. the global `FluctuationAmplitude`/`Temperature`
- `cell.fluctAmpl = −1` means "use the default".
- The copy's T is `combine(T_source, T_target)` with `combine ∈ {Min (default), Max, ArithmeticAverage}`.
  **Medium never contributes.** If one side is medium, the other side's value is used: Min/Max treat
  medium as ±∞, and ArithmeticAverage duplicates the non-medium value.
- Default global T: **0 in XML, 10 in PyCoreSpecs**.
- `Anneal = n`: after `Steps`, the global temperature is set to 0 and n more MCS run
  (S/Simulator.cpp `finish`). This maps to a final protocol stage.

### 2.5 Energy term definitions

- **Contact** (R/contact_plugin.html; S/plugins/Contact):
  - `H = Σ_{unordered neighbour pairs within order} J(τ,τ′)(1 − δ_{σ,σ′})`, where `J(τ,τ′)` is the
    energy for the two cells' types (τ = cell type, σ = cell id).
  - ΔE sums only over the target site's neighbours. Each unordered pair counts **once**, so an H over
    ordered pairs would need `J/2`.
  - Pairs within one cell are excluded. Two different cells of the same type do count.
  - `WeightEnergyByDistance` divides each term by the Euclidean offset length.
  - ContactInternal replaces J with `J_int` when `clusterId` matches (R/compartments.html).
- **Volume**: `λ(V − V₀)²`.
- **Surface**: `λ(S − S₀)²`. S counts unlike-neighbour site pairs within the Surface plugin's order,
  multiplied by the lattice factor. The factor is 1 on square lattices; on hex, S_unit ≈ 0.6204 in 2D
  and ≈ 0.445 in 3D (R/lattice_type.html). `ScaleSurface` rescales S.
- **LengthConstraint** (S/plugins/LengthConstraint):
  - 2D: `L = 4√(λ_max/V)`, with `λ_max = ½(Ixx+Iyy) + ½√((Ixx−Iyy)² + 4Ixy²)`, where I is the
    un-normalised inertia tensor about the COM. The energy is `λ(L − L₀)²`.
  - 3D: the same λ is applied to both the major length and `MinorTargetLength`.
  - Semiaxes come from inverting the ellipsoid inertia formulas `I = (1/5)(b²+c²)` etc.
  - Our `elongation` must be defined, or a `major_length` with this formula must be added.
- **Chemotaxis** (R/chemotaxis_plugin.html; S/plugins/Chemotaxis `merksChemotaxis`):
  - Base form: `ΔE = −λ (c(target) − c(source))`.
  - Default algorithm ("merks"): use the **source cell's** parameters if it chemotaxes (per-cell data
    first, then by type). Otherwise use the **target (retracting) cell's**. First match wins, once per
    field.
  - `Regular`: only a non-medium source counts. `Reciprocated`: both the source and target terms.
  - `ChemotactTowards`: the term is nonzero only if the other cell's type is in the list.
  - `SaturationCoef s`: `c/(s+c)`. `SaturationLinearCoef s`: `c/(sc+1)`.
  - `LogScaledCoef s`: λ is divided by `(s + c(COM))`.
- **ExternalPotential** (R/external_potential_plugin.html; S/plugins/ExternalPotential):
  - COM-based form: `ΔE = λ⃗·(ΔCOM_source + ΔCOM_target)`. This is exactly the global
    `H = Σ_cells λ⃗·x_COM`, so `cells => dot(λ, centroid)` already covers it once vector parameters exist.
  - **A positive component pushes in the negative direction.**
  - The pixel-based default sums over face neighbours of the target; λ must be about 10× smaller than
    in the COM form.
- **FPP** (R/focal_point_plasticity.html):
  - `E = Σ_links λ(l − L)²`, where l is the COM–COM distance.
  - A link breaks when `l > MaxDistance`.
  - Per-type-pair `MaxNumberOfJunctions`, optionally capped by `MaxTotalNumberOfLinks` per type.
  - Link tension is reported as `2λ(l − L)`.
  - A custom `LinkConstituentLaw` can replace the spring.
- **ImplicitMotility**: `ΔE = −λ Σ_{src,tgt} unit(ΔCOM)·b` (S/plugins/ImplicitMotility).

### 2.6 Fields and secretion

- **Units**: secretion and uptake amounts are added per pixel per MCS.
  - DiffusionSolverFE interleaves secretion across its automatic substeps (`DoNotScaleSecretion`
    turns this off).
  - FlexibleDiffusionSolverFE secretes once, then runs `ExtraTimesPerMCS` diffusion-only calls.
  - FlexibleDiffusionSolverFE rescales D by `DeltaT/DeltaX²`.
- **Uptake rule** (R/reference_field_secretor.html): if `c > max_amount`, subtract `max_amount`;
  otherwise subtract `relative_uptake·c`. The rule is discontinuous. Match it only in a
  `CC3DUptake(...)` helper, since the Michaelis–Menten (MM) exchange is already planned.
- **Field BCs** default to the Potts BCs. Per axis you can set `ConstantValue`, `ConstantDerivative` or
  `Periodic`, with Min/Max mixable. Periodic must apply to both ends. RDFVM defaults to zero flux.
- **RDFVM face diffusivity**: the harmonic mean `2DᵢDⱼ/(Dᵢ+Dⱼ)`. Precedence is
  `DiffusivityFieldEverywhere > DiffusivityFieldInMedium > DiffusivityByType > constant`.
- The steady-state solver solves `∇²c − kc = F` once per MCS.

### 2.7 Cells, neighbours, division

- **Neighbours**: NeighborTracker counts cells that share at least one pixel **face**; corner contact
  does not count. Common area = the number of shared faces.
- **Mitosis**: a plane through the COM (major axis, minor axis, a given normal, or random). Pixels on
  one side become the child. Parent/child side is randomised by default
  (`set_parent_child_position_flag(0)`). The `update_attributes` hook runs before the split.
  `clone_parent_2_child` copies everything, including `cell.dict`.
- **COM with periodic BCs**: the COM is updated incrementally by shifting the cell to the lattice
  centre, adding the pixel, shifting back, and wrapping (R/com_with_periodic_bc.html). Our centroid
  tracker should give identical values for wrapped cells.

---

## 3. What CC3D models commonly rely on

From the demos tree (`Demos/PluginDemos`, `SteppableDemos`, `CompuCellPythonTutorial`, `Models`) and the
manual's examples. The recurring set is:

- Contact + Volume (+ Surface)
- DiffusionSolverFE with per-type secretion
- Chemotaxis (by type and per cell, LogScaled)
- Python mitosis (random or major axis, `update_attributes`)
- NeighborTracker-driven contact events (EMT, phagocytosis, T-cell contact)
- FieldSecretor per-cell secretion and uptake, and `amountSeenByCell`
- FocalPointPlasticity (links, anchors, custom law, oscillators)
- LengthConstraint + Connectivity (elongation)
- Per-cell `fluctAmpl`
- SBML/Antimony per-cell ODEs (e.g. Delta–Notch)
- Blob/Uniform/PIF initializers

Items 1–10 above are what our surface is missing for that set.

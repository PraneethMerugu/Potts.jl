# Cell liveness in CompuCell3D, Morpheus and Artistoo, and a proposed amendment to D-035/D-037

Research for ROADMAP P6.5a (R6, "explicit liveness", D-053 item 6). The maintainer's rule
(2026-09-30): follow standard CPM liveness behaviour where performance allows.

**Revision 2** (after review round 1). Main changes:
- The recommended decision (D-066, §6.1) drops `retain_empty`. No model needs it, and it
  would change Fortuna's results (§5).
- A fully repaired `retain_empty` design is kept as Option B (§6.2).
- The numbers in §7 are measured.
- Every deviation is listed with its reason (§4.1).

**Contents.** §1 sources · §2 our current behaviour · §3 comparison table · §4 standard
behaviour, disagreements, our deviations · §5 tie-in to the 12 models · §6 proposed
decision (draft DECISIONS text) and Option B · §7 performance, measured · §8 benchmark
scripts · §9 open items.

---

## 1. Sources

Code is cited at a fixed commit. The survey itself reads code only; the few inferences
are marked. The performance numbers in §7 were measured.

| Tool | Repository @ commit | Path prefix used below |
|---|---|---|
| CompuCell3D 4.x | github.com/CompuCell3D/CompuCell3D @ `727d1fc` (tag 4.9.0) | `CompuCell3D/core/CompuCell3D/` |
| CompuCell3D 3.7.9 | same repo, **branch** `3.7.9` @ `ca3d647` (no 3.7.9 tag exists on the remote) | `CompuCell3D/core/CompuCell3D/` |
| Morpheus | gitlab.com/morpheus.lab/morpheus @ `1102780` (tag v2.4.1) | `morpheus/` |
| Artistoo | github.com/ingewortel/artistoo @ `e997d81` | `src/` |

Docs:
- CC3D, creating and deleting cells:
  https://pythonscriptingmanual.readthedocs.io/en/latest/creating_and_deleting_cells_cell_type_names.html
  and https://compucell3dreferencemanual.readthedocs.io/en/latest/creating_and_deleting_cells_cell_type_names.html
- Artistoo `killCell`: https://artistoo.net/class/src/grid/GridManipulator.js~GridManipulator.html
- Morpheus has no web page for `CellDeath`. Its in-app help is generated from
  `plugins/miscellaneous/cell_death.h:20-65` and `cell_death.xsd`, which are cited instead.

Our code is cited at `6ec712a` (branch `feat/p6-5a0`). The reference codebases are under
`docs/references/codebases/` in the main repo.

---

## 2. Our current behaviour (D-035, D-037, code)

**Alive means "owns a site".** No column stores liveness. There are two equivalent
encodings:
- `volume[c] > 0`, tested in:
  - the lifecycle trigger kernel (`lib/CorePotts/src/lifecycle.jl:147-154`);
  - the lifecycle free list (`:260`) and cluster member lists (`:270`);
  - cell ODEs (`src/codegen.jl:429`, `:514`) and cell updates (`src/codegen.jl:694`);
  - `cells(…)` folds (`src/lower.jl:295`);
  - cluster-root holding (`lib/CorePotts/src/compartments.jl:63`).
- `_live(σ, n)`, "some site carries this id" (`compartments.jl:34`). It is used by
  `init_clusters` (`:28`) and `_fix_clusters!` (`:174`). `_normalize_clusters!` makes
  every non-live slot its own cluster (`:57-59`).

**Geometry and emptiness checks.** These test for sites, which is a different question
from liveness:
- centroid, 0 for an empty slot (`src/lower.jl:187`);
- `major_length` (`geometry.jl:243`);
- link creation (`src/codegen.jl:631`).

**Death on the last site** is immediate and free: the copy's volume commit takes V to 0.

**Explicit removal.** `EVENT_REMOVE` sets the cell's sites to medium
(`lifecycle.jl:166-170`). The trackers are then rebuilt exactly (`:365`).

**Id reuse (D-035).**
- A slot is free when all of these hold (`lifecycle.jl:257-260`):
  - `volume == 0`;
  - it has no event this MCS;
  - it is not a cluster root that still names live members.
- Daughters take free ids lowest-first, and `generation` is incremented (`:342-344`).
  `generation` feeds cell-addressed randomness (`rng.jl:92-93`).
- Capacity is fixed per problem: `2n + 64` when the model divides (`src/problem.jl:334`).
  When it runs out, divisions are deferred with a warning (`lifecycle.jl:233-240`).

**Energy (D-037).**
- The ΔH of a last-site copy includes λ[(0−V₀)² − (1−V₀)²].
- `total_energy` sums cell terms over every slot (`src/codegen.jl:792`), so an emptied
  cell keeps E(V = 0).

**`no_extinction`** is opt-in:
- It is `forbid_extinction(volume, prop)` (`drives.jl:80`).
- Only Akeeb uses it (`lib/PottsModels/src/akeeb.jl:54`).
- `docs/design/AUTHORING.md:235`, in §5, still calls it a default. That line is stale
  against D-037.

**Bug (confirmed in review; queued as ROADMAP P6.0l).** Links are dropped only for
`EVENT_REMOVE` cells and daughters (`lifecycle.jl:358-359`). When a linked cell dies by
losing its last site through copies:
- its centroid is `m1/0`, which is NaN (`geometry.jl:125-131`);
- every `link_delta` of its surviving partner is NaN (`relationships.jl:169-173`);
- `exp(−NaN)` never accepts, so **the partner freezes silently**;
- `total_energy`'s edge loop (`src/codegen.jl:830-837`) **returns NaN**.

---

## 3. Comparison table

| Question | CC3D 4.x | CC3D 3.7.9 | Morpheus 2.4.1 | Artistoo | Potts.jl today |
|---|---|---|---|---|---|
| **Dies when it loses its last site through a copy?** | **Yes, immediately.** `--volume == 0` records the cell (`plugins/VolumeTracker/VolumeTrackerPlugin.cpp:84-96`). The stepper after that same copy attempt calls `destroyCellG` (`:99-113`; steppers run per attempt, `Potts3D/Potts3D.cpp:877, 909-912`) | Yes, same design (`VolumeTrackerPlugin.cpp:118-130, 142-150`; `Potts3D.cpp:676, 688`) | **Cannot happen.** A hard veto on every last-node copy for non-medium types (`core/celltype.cpp:652-654`), checked before ΔH (`core/cpm_sampler.cpp:461-477`) | **Yes, immediately in `setpixi`.** `delete cellvolume[t]; delete t2k[t]` (`models/CPM.js:396-403`; `GridBasedModel.js:155-168`) | Yes, immediately (the volume commit) |
| **Explicit removal** | `delete_cell` overwrites every pixel with medium, so the cell dies by the rule above (`cc3d/core/PySteppables.py:2636-2647`). Soft idiom in demos only: `targetVolume = 0` (e.g. `Demos/.../pressureFieldSteppables.py:27`) | `deleteCell`, same approach (`pythonSetupScripts/PySteppables.py:752-758`) | Retype to medium: `CPM::setCellType(id, Empty)` (`core/cpm.cpp:609-614`) → `MediumCellType::addCell` (`celltype.cpp:791-805`). `CellDeath`, once per MCS: lysis (immediate) or shrinkage (`plugins/miscellaneous/cell_death.cpp:76-172`) | `GridManipulator.killCell` (experimental) setpix's every pixel to 0 (`grid/GridManipulator.js:42-53`) | `EVENT_REMOVE` sets sites to medium (`lifecycle.jl:169`) |
| **Intermediate "dying" state** | No (a "Dead" type is user convention) | No | **Yes.** Shrinkage sets target 0 and keeps the cell in a `dying` set until `nNodes ≤ remove-volume` (default **3**, `cell_death.xsd:22`; `cell_death.cpp:83-98`) | No | No |
| **Ids reused?** | **No** for normal creation: `++recentlyCreatedCellId` (`Potts3D.cpp:334-339`). Yes for explicit-id creation (PIF) of a destroyed id (`:381-405`) | **Never**: explicit ids ≤ counter just increment (`Potts3D.cpp:388-389, 432-447`) | **No** by default: monotone `getFreeID` (`celltype.h:25`; `celltype.cpp:37-50, 470-490`). Explicit ids (XML, division `daughter_ids`) may reuse dead ones (`isFree`, `celltype.h:24`) | Monotone until the Uint16 wrap at 65534, **then dead ids are reused**, skipping live ones (`CPM.js:463-478`) | **Yes**: lowest-first among free slots (D-035) |
| **Generation counter** | None (`clusterId` monotone too, `:344-363`) | None | None | None | `generation` per slot, incremented on reuse |
| **Dead cell in energy** | Absent: object deleted, no pixels | Absent | Absent after removal. Shrinking cells are fully present | Absent: no pixels | ΔH: absent. `total_energy`: keeps E(V=0) (D-037) |
| **Dead cell in populations and iteration** | Removed from `CellInventory` (`CellInventory.cpp:79-84`) → `cell_list`, `cell_list_by_type` | Same | Removed from the type's `cell_ids` (`celltype.cpp:627-629`) → `getCellIDs`, `FocusRange`, population-size symbol (`:99`); and from storage (`:65-73`) | Dropped from `cellIDs()` = `Object.keys(cellvolume)` (`GridBasedModel.js:119-121`), so all stats skip it | Skipped by `volume > 0` in folds, ODEs, updates and triggers |
| **Neighbours, links, plotting** | NeighborTracker entries go as the common area reaches 0 (`NeighborTrackerPlugin.cpp:122-170`). FPP drops links **at the copy** that zeroes the volume (`FocalPointPlasticityPlugin.cpp:865-875`). The player sees no pixels | Same | Nodes reassigned via `setNode`, so interfaces update | `borderpixels` per pixel (`CPM.js:423-452`) | Contact graph from σ excludes it. Links **not** dropped on copy-death (§2 bug) |
| **Zero-volume live cell possible?** | **Yes.** `new_cell` / `createCell` enters the inventory at volume 0 (`PySteppables.py:2425-2435`; `Potts3D.cpp:363`). Destruction fires only on a *decrement* to 0, so an unpainted cell persists (inferred) | Yes (same) | Yes, transiently: daughters are created empty (`celltype.cpp:531-536`). Empty XML-initialised cells are dropped (`:251-253`) | **Yes.** `makeNewCellID` sets `cellvolume[id] = 0` (`CPM.js:476-477`), so the cell is in `cellIDs()` before painting | No |
| **Total H; does λ(V−V₀)² count at V=0?** | **No total H.** `totalEnergy` sums `localEnergy`, which is 0 for every plugin (`Potts3D.cpp:458-469`; `EnergyFunction.h:29`). Only the accepted ΔH is accumulated (`:868`) | Same | `CellType::hamiltonian` sums over `cell_ids`, empty ones included (`celltype.cpp:639-650`; `volume_constraint.cpp:26-31`), but **nothing calls it** | No total H; only `deltaH` (`CPM.js:278-284`) | `total_energy` over all slots (D-037) |
| **ΔH of the last-site copy** | Full λ[(0−V₀)² − (1−V₀)²], no special case (`plugins/Volume/VolumePlugin.cpp:153-155, 192-194, 236-238`) | Same (`VolumePlugin.cpp:226, 277, 320`) | Same formula (`volume_constraint.cpp:12-24`), but never evaluated because of the veto | Same (`hamiltonian/VolumeConstraint.js:60-83`) | Same |
| **Extinction guard** | None built in. 2D `Connectivity` adds a soft +64 to an isolated last pixel (`ConnectivityPlugin.cpp:102-106`). `ConnectivityGlobal`'s fast path dereferences an empty set on a last pixel (`:300`; looks like undefined behaviour, not run) | None | **Always on** (hard veto, above) | None by default. `HardVolumeRangeConstraint` with min ≥ 1 forbids it (`HardVolumeRangeConstraint.js:44-55`) but is not auto-added (`AutoAdderConfig.js:20-26`) | Opt-in `@constraint no_extinction` |

Outside our scope: Artistoo's `nr_cells` is decremented but never incremented
(`CPM.js:46, 402`), so its 65533-live-cells guard at `:464` never fires.

---

## 4. Standard behaviour (consensus), disagreements, and our deviations

**Consensus of all three tools:**
1. **Death is immediate on losing the last site**, at the copy that removes it (CC3D,
   Artistoo). Morpheus forbids that copy instead.
2. **Explicit removal is "give the sites away, then the cell is gone".** There is no
   "dead but on the lattice" state in core.
3. **A dead cell leaves every inventory at once:** energies, populations, per-cell
   iteration, neighbour and link tracking, plotting. It is never revived; a new cell is a
   new object.
4. **The volume ΔH of the last-site copy has no special case at V′ = 0.**
5. **No tool computes a total Hamiltonian that is ever used.**
6. **A cell is destroyed only when it *becomes* empty through a site change, never for
   *being* empty.** So unpainted new cells are alive (CC3D, Artistoo; transiently in
   Morpheus).
7. **Ids are monotone by default and there is no generation counter.** Every tool still
   reuses dead ids at some edge: explicit ids, or wrap-around.

**Where the tools disagree:**
- **Extinction.** CC3D and Artistoo allow a cell to lose its last site; Morpheus forbids it.
- **Dying state.** Only Morpheus has one (shrinkage).
- **Id reuse at the edges.** CC3D 4.x reuses dead ids for explicit ids; CC3D 3.7.9 never
  reuses; Morpheus reuses for explicit ids; Artistoo reuses after the Uint16 wrap.

### 4.1 Our deviations under the proposed D-066, with reasons

| # | Standard | Ours | Reason | Observable effect |
|---|---|---|---|---|
| X1 | Monotone ids (item 7) | Slot reuse, lowest-first, with `generation` (D-035 kept) | Performance. Every per-cell loop runs over capacity; monotone ids make capacity ≥ cumulative births, and growth reallocates on a warm MCS (§7, measured) | **None outside kernels.** The user-visible id is a monotone `birth` serial (§6.1 item 3) |
| X2 | Unpainted live cells exist (item 6) | `@create` allocates and paints in one host routine. A created cell that receives no site is not born | An unpainted cell has no centroid or shape. Its only occurrence in the 12 models is an artefact (Akeeb seeding, §5). Keeping "alive ⇔ owns a site" keeps every liveness test at zero cost | Akeeb: emulated exactly at init (§5) |
| X3 | Links of a dead cell dropped **at the killing copy** (CC3D FPP) | Dropped at the next boundary (§6.1 item 5). Until then the dead partner is skipped in `link_delta` and `total_energy` | Dropping inside the sweep writes the link store from the hot loop, a race on the checkerboard | Energetically none: a dead partner contributes 0 from the killing copy on. A stale link slot occupies the partner's degree until the boundary (bounded by the link-rule cadence) |
| — | (no standard) | `total_energy` over alive cells | Not a deviation: no tool uses a total H (item 5). This is our convention | — |

---

## 5. Tie-in to the 12 reference models

Spec ids are from `model-specs/README.md` §1.

### Model 14: Fortuna 2020 / Thomas / Dal Castel (CC3D). Depends on this decision.

The spec's G10 note asks for a `retain_empty` lamellipodium (14 §8). **The authors' code
does not keep an empty lamellipodium, and keeping one would change results.**

**14a (`codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py`).**
- The FRONT-creation step runs **every MCS** (`:121-164`). Whenever the cell has no FRONT
  and `pFRONT > 0`, a conversion calls `potts.createCell()`, paints the pixel at once
  (`:150-153`), gives the new FRONT a target of 1.5, and lowers CYTO's target by 1.5
  (`:155-157`).
- `CELLvol` is a sum of **target** volumes (`:127-138`, `CELLvol = cell.targetVolume +
  FRONTvol + NUCLvol`, where FRONTvol and NUCLvol are targets).
- So when FRONT empties, CC3D destroys it (§3). Its target leaves `CELLvol`; `pFRONT` is
  recomputed from FRONTvol = 0; a new FRONT is created with target 1.5 and CYTO loses
  another 1.5. **Every FRONT death permanently shrinks the cell's total target volume.**
- The detachment check that stops a failed run runs only every `deltaT = 50` MCS
  (`CellMig3D.py:41`; `CellMig3D_Steppables.py:303`) and only after MCS 10 (`:407`).
- An early 1-site FRONT (target 1.5) can lose its only site to any accepted copy. FRONT
  emptying is therefore **reachable**, and probably most likely early. Revision 1 said it
  was unreachable; that was overstated.

**Consequence for `retain_empty`.** With it, a retained empty FRONT keeps its target, so
`pFRONT ≤ 0`: there is no re-seeding and no loss of target volume. The empty FRONT stays
empty, because conversion is gated off and copies cannot reach a cell with no sites.
**This differs from the CC3D code.**

**14c (`codebases/14c_DalCastel2025_Single_Cell_Chemotaxis_2.3/SCellSign_DISTRIBUTED/Simulation/SCellSignSteppables.py`).**
- LAMEL is created **and painted** at start (`:54-55, 75`).
- `step` rebinds `LAMELcell` only inside `for LAMELcell in self.cellListByType(self.LAMEL)`
  (`:104-105`), then reads `get_cell_boundary_pixel_list(LAMELcell)` (`:122`).
- If LAMEL has died, the loop body never runs, `LAMELcell` is unbound, and the run ends
  with a Python error (inferred, not run). An empty LAMEL is a failed run in the authors'
  code, not a state to keep.

**Proposal.**
- 14a: FRONT is created on demand by `@convert` into the cluster (R8), and it dies when it
  empties. This is standard behaviour and matches CC3D, target loss included.
- 14c: a LAMEL death is a failed run (`@terminate`).
- **Check:** the port counts FRONT and LAMEL deaths per run (a per-kind death counter in
  `LifecycleStats`, or an observable). If they are frequent, that is a finding to report
  to the authors (spec §5 questions).

### Model 06: Jiang 2005 tumour. Depends on it.

- The necrotic core is "a special cell with ID 0" that "must exist before any death (or
  be created on first death)" (06 §G10, G14).
- Under the standard behaviour it is created at the first death by the retire-into routine
  (R8 `@retire … sites => ref`, creating the target if it is absent), and it is an
  ordinary cell from then on.
- No empty-but-alive state is needed.

### Model 10: Akeeb 2026 (CC3D 4.6.0). Depends on it.

**CC3D seeding** (`DEMO/Main_Simulation/cclc_math_path/Simulation/CCIecmSteppables.py:46-57`):
- It calls `self.new_cell(self.LC)` on **every** draw, and paints only when the pixel is a
  follower's (`c1.type == 2`, where FC = 2 and LC = 1 in `CCIecm.xml:38-39`).
- A draw that lands on an existing leader leaves an unpainted leader in the inventory.
- `i = LC/(LC+FC)` is recomputed only after a hit and counts those unpainted leaders, so
  the loop stops when the counted total reaches 390.
- Expected unpainted leaders: Σ_{n<390} n/9481 ≈ **8**, with 9481 = 499 × 19 drawable
  pixels. So there are ≈ **382 painted** leaders (inferred, not run).
- The unpainted ones are inert:
  - they never gain a pixel;
  - the growth and mitosis steps touch only FC (`:93-97`, `:118-129`);
  - they fail `yCOM > min_tumor_y` in the singles metric (`:504-513`).
- They are, however, counted in the CSV leader count (spec V-A1: "390 throughout").

**Our `akeeb_state`** (`lib/PottsModels/src/akeeb.jl:92-99`):
- It **retries** a missed draw (`1 <= σ[x, y] <= nf || continue`), so it paints **390**
  leaders. That is about 8 more than CC3D, about 2 %.

**Exact emulation at zero cost:**
- On a miss, count one leader toward the quota without creating or painting a cell. Stop
  after a hit once `4 * counted >= counted + nf`.
- Painted leaders are then 390 − misses, distributed as in CC3D.
- V-A1 then compares the **painted** leader count (≈ 382 ± sd) with CC3D. The CSV's 390
  also counts ≈ 8 unpainted leaders.
- This changes `akeeb_state`, so the gate's Akeeb case must be re-baselined in the same
  change.

Other Akeeb points:
- Akeeb uses `no_extinction` together with connectivity; that is unchanged.
- It has no deaths, so no id is ever freed.
- Its cross-frame cluster tracking by member ids (`:844-856`) is unaffected. It would also
  be safe under reuse, because it would read the `birth` id (§6.1 item 3).

### Models 08, 11, 09 and 01: nothing changes

- **08 FBCA** has deaths (open boundary, therapy, starvation) plus division.
- **11 Jafari Nivlouei** has apoptosis, necrosis, and removal of migrated cells.
- For both, dead cells leave populations today (`volume > 0`), and they will under D-066.
  Ids are reused today and will be reused under D-066. The user-visible `birth` id is the
  only addition.
- **09 Graner–Glazier** needs extinction allowed (λ scan, 09 V-PRE8). `no_extinction`
  stays opt-in.
- **01 Merks**: TST's apoptosis at area 0 (01 D-11) is death on emptying, as now.

### Models 04, 05, 07, 12, 13

These have no death (05 and 07 explicitly; 12 and 13 have a fixed cell count). 05's
`@create` recruitment gets new slots and `birth` ids.

**Summary.**
- None of the 12 models needs an empty-but-alive cell.
- 14 and 06 need cells created on demand (R8).
- 10 needs one change to its initial state.
- 08, 11, 09, 01, 04, 05, 07, 12 and 13 see no behavioural change.

---

## 6. Proposed decision

### 6.1 Recommended: D-066 (draft DECISIONS text)

```markdown
## D-066 Cell liveness is the standard CPM one: alive ⇔ owns a site (2026-09-30, P6.5a; amends D-035, D-037; revises D-053 item 6)

Survey: `research/liveness-survey.md` (CompuCell3D 3.7.9/4.9, Morpheus 2.4.1, Artistoo).
Standard: a cell dies at once when it loses its last site or is removed; a dead cell
leaves every energy, population, iteration, link and plot; the last-site copy pays the
full volume ΔH; there is no "dead but present" state.

1. **Alive** ⇔ the cell owns at least one site: `alive(c) ≡ volume[c] > 0`. `alive` is a
   read-only built-in with that meaning.
   - Birth happens in one of three ways:
     - the initial state;
     - a division daughter that receives at least one site (a daughter with none is not
       born, and its slot stays free, as now);
     - `@create`/`@convert` (R8), which allocate and paint in one host routine.
   - Death happens when a copy takes the last site (at once), when a lifecycle rule
     removes the cell (its sites go to medium or to the named target), or when a
     conversion takes its last site. Death is terminal for (id, generation).
   - There is no dying state and no empty-but-alive state. Morpheus-style shrinkage is a
     `@transition` to a kind with V₀ = 0 plus `@remove … when volume <= n`.
   - D-053 item 6 ("explicit liveness separate from volume > 0") is withdrawn. No tool
     keeps or kills cells on anything but site ownership, and none of the 12 models needs
     it (survey §5). Fortuna's lamellipodium and Jiang's necrotic core are created on
     demand, as in their authors' code.
2. **Deviations from the standard**, each with its reason (survey §4.1):
   - X1: slot ids are reused (performance; item 3).
   - X2: no unpainted live cells, because `@create` paints at allocation (liveness stays
     free; the only reference-model occurrence is an artefact).
   - X3: links of a copy-killed cell are dropped at the next boundary, not at the copy
     (a drop in the sweep would be a racy hot-loop write). This has no energy effect.
   The total-H convention (item 4) is not a deviation: no tool has a total H.
3. **Ids (amends D-035).**
   - Slots are reused lowest-first, with `generation` incremented, as now.
   - A slot is free when it is not alive, had no event this MCS, and is not the root of a
     cluster with alive members, as now.
   - References (R6) are **not** held. The lifecycle planner clears references to dead
     cells before it allocates ids, so a reference never aliases a new cell.
   - **`birth`, a monotone never-reused Int32 serial, is the user-visible id.**
     - Every model with a Lifecycle or `@create` gets `st.cell.birth`. Initial cells get
       1:n; the host planner assigns `max + 1` at each birth.
     - `id` in observables, saved solutions and SII, id-based tracking, plots and PIFF
       export (`write_piff(…; ids = birth)`) is `birth`.
     - Kernels index by slot. The `id` built-in in model expressions lowers to
       `birth[c]` (one load, only where it is read).
     - Models without births have `birth ≡ slot`, and no column.
4. **Energies (amends D-037).**
   - ΔH is unchanged: the last-site copy pays λ[(0−V₀)² − (1−V₀)²].
   - `total_energy` sums:
     - cell terms over alive cells;
     - cluster terms over the roots `r` (`cluster[r] == r`) of clusters with at least one
       alive member (a copy-killed root still names its cluster until `_fix_clusters!`);
     - edge terms over links whose two ends are both alive.
     A dead cell contributes nothing.
   - Self-check: `ΔE(copy) == H(after) − H(before) + E_cell(o, V = 0)
     [+ E_cluster(cluster[o], V = 0) if the copy emptied that cluster]`, where `o` is the
     old owner, when this copy killed it. It stays exact.
5. **Folds, populations, geometry, contacts, links, references.**
   - Folds, counts, cell ODEs and updates, lifecycle triggers, observables and plots range
     over alive cells. The code is unchanged: it already tests `volume > 0`.
   - Centroid, position, shape and `major_length` are defined for alive cells and are 0
     for dead slots, as now.
   - The contact graph is built from σ, so dead cells have no contacts.
   - Links:
     - `link_delta` and `total_energy` skip a partner with `volume == 0`. This reuses the
       load `centroid` already makes, and it fixes the NaN freeze (P6.0l).
     - Links incident to dead cells are dropped (a) in the lifecycle plan of an event
       MCS, before ids are allocated, and (b) at the start of each `@link`/`@unlink` host
       phase of that relationship, before new links are made, so a stale degree or
       `linked` never blocks creation.
     - A relationship with no link rules and no lifecycle never creates links; the skip
       alone suffices there.
   - References:
     - Dereferencing a dead referent (`x[ref]`, `kind[ref]`, `volume[ref]`, …) reads as
       `ref = 0`: kind 0 (medium), volume 0, and cell variables at their defaults. This
       costs one `volume[ref]` load and a select per dereference, in reference-reading
       code only.
     - References to dead cells are reset to 0 at the same boundaries as links.
     - A copy-killed slot's stale kind and cell variables are never observable: every read
       of a dead slot is either gated by liveness or goes through a dereference.
6. **`no_extinction`** stays opt-in (D-037; CC3D and Artistoo). Morpheus's always-on veto
   would break the Graner–Glazier λ scan.
   - `@constraint no_extinction` or `no_extinction(k…)` forbids a copy that takes the last
     site of a cell of kinds k… (default: every cell kind), i.e.
     `old == 0 || volume[old] > 1 || kind[old] ∉ K`.
   - A model ported from Morpheus adds it.
   - AUTHORING §5 is corrected (it calls no-extinction a default).
7. **Reproductions** (survey §5):
   - 14a: FRONT is created by `@convert` and dies when it empties, losing its target as in
     CC3D. The port counts FRONT deaths.
   - 14c: a LAMEL death ends the run (`@terminate`).
   - 06: the necrotic core is created at the first death.
   - 10: `akeeb_state` counts a missed draw toward the leader quota without painting,
     emulating CC3D's unpainted `new_cell`. Painted leaders ≈ 382; V-A1 compares painted
     leaders. The gate's Akeeb case is re-baselined in the same change.

Why: the standard behaviours are either already ours (immediate death, full ΔH, exclusion
through `volume > 0`) or cost nothing (the skip in `link_delta`, the `birth` serial,
host-side reference and link cleanup). The one costly standard, monotone slots, was
measured (survey §7): 0.7–3 ns per dead slot per MCS, plus a warm-MCS allocation at each
capacity growth. Only its user-visible part (`birth`) is adopted.
```

### 6.2 Option B (not recommended): `retain_empty`, repaired

This is the design to use if the maintainer wants paper-literal empty members despite §5.
It fixes the three problems found in review (B1 a–c).

- **Declaration and state.**
  - `@kinds k[retain_empty]` declares the kinds.
  - Such models get a `retained::Vector{Bool}` column. It is set at birth for those kinds
    and cleared on removal.
  - `alive(c) = volume[c] > 0 || retained[c]`. The extra load happens only on the
    `volume == 0` branch; models without such kinds have no column and today's code.
  - Kind 0 is **not** used as a dead marker. Kind tables index with `Int(k) + 1`
    (`src/lower.jl:241`), but CorePotts per-kind vectors are 1-indexed by kind, and name
    maps are built from `cell_kinds`, so a kind-0 cell slot is unsafe without an audit.
- **Cluster semantics** (fixes B1a). `alive(c)` replaces site ownership in:
  - `_live` and `_normalize_clusters!` (`compartments.jl:28, 34, 57-59, 174`);
  - the lifecycle member lists (`lifecycle.jl:270`);
  - `_referenced_clusters` (`compartments.jl:63`);
  - the trigger kernel (`lifecycle.jl:147-154`);
  - the free list (`:260`).
  An empty retained member therefore stays in its cluster at init and across events.
- **No implicit cluster death** (fixes B1b and B1c).
  - A retained cell dies only by explicit removal of itself or of its cluster, or by a
    transition to a non-retained kind while it is empty. A lone retained cell (Jiang's
    core) never dies implicitly.
  - To remove orphans, write `@remove cells(k) when cluster_volume == 0`. The ordinary
    trigger kernel evaluates it for every alive cell on checked MCS, so no new trigger
    and no new synchronisation are needed.
- **Divisions and transitions.**
  - An empty cell is never divided: the planner skips `volume == 0`, since there is no
    centroid.
  - A retained-kind daughter that receives no site is not born, as for any kind.
  - An empty retained cell that transitions to a non-retained kind dies at that event.
- **Geometry.**
  - Centroid, position, shape and `major_length` stay `volume > 0` checks (0 when empty).
  - Link creation stays `volume > 0` (an empty cell has no contacts).
  - Folds, ODEs, updates and triggers switch to `alive`.
  - An empty retained cell contributes E(V = 0) to `total_energy`.
- **Cost.** A measured +0.02 to +0.06 ns per slot per fold (§7, B1), in retain models
  only.
- **Deviation.** It contradicts consensus item 3 and changes Fortuna's results (§5).
  Adopting it needs a reproduction reason, which §5 does not find.

---

## 7. Performance, measured

**Setup.**
- Apple M1 Pro, Julia 1.12.6, single-threaded.
- Run under `tools/exclusive.sh` from the main repo (`PottsMonorepo` @ `71372a0`), with
  the `benchmark` project.
- Scripts are in §8 (`/tmp/liveness_bench/`). The full gate was not run.
- Gate context: CPU baselines of 13.7–94.3 ns/site and a 5 % tolerance
  (`benchmark/baseline.toml`, `benchmark/gate.jl:20`). There are 10 CPU cases plus 5
  Metal cases, which are flagged but not gated.

**B1: liveness tests in a fold.** Minimum time per slot for a fold that sums a Float64
per live slot. 20 % of slots are dead, either at the tail or scattered.

| Variant | tail, 10³ | tail, 10⁴ | random, 10³ | random, 10⁴ |
|---|---|---|---|---|
| `volume > 0` (today, D-066) | 0.817 | 0.821 | 0.729 | 0.842 |
| `volume > 0 \|\| kind ∈ R` | 0.850 | 0.868 | 0.788 | 0.818 |
| `volume > 0 \|\| retained[c]` (Option B) | 0.842 | 0.851 | 0.725 | 0.754 |
| stored `alive::Bool` | 0.854 | 0.884 | 0.729 | 0.846 |
| `volume > 0` + kind filter | 0.583 | 0.615 | 0.638 | 0.978 |
| `\|\| retained[c]` + kind filter | 0.638 | 0.634 | 0.696 | 0.732 |

All values are in ns/slot. Every encoding is within ±0.07 ns/slot of today's, which is
about run-to-run noise. At MCS cadence that is below 0.002 ns/site for Akeeb (308 cells,
5940 sites).

**How liveness is stored does not matter in folds.** A stored flag would cost something
only in the *sweep*, where a copy that empties a cell would have to clear it: a branch
plus a store, and on the checkerboard the value returned by the atomic decrement. That is
an implementation choice, not a standard to reject. D-066 needs no flag.

**B2: warm ns/site against capacity** (the tax of dead slots). 1× is the gate's capacity:
Akeeb 1000 slots for 308 initial cells (5940 sites); OpenVT 64 slots (10⁴ sites).

| Case | 1× | 2× | 4× | 16× | Slope (ns per dead slot per MCS) |
|---|---|---|---|---|---|
| akeeb_99x60 sequential | 47.78 | 47.75 | 47.64 | 49.50 | ≈ 0.7 |
| akeeb_99x60 checkerboard | 46.18 | 46.38 | **49.85** | **54.00** | ≈ 3.1 |
| openvt_monolayer_100 sequential | 14.00 | 14.02 | 14.03 | 14.11 | ≈ 1.1 |
| openvt_monolayer_100 checkerboard | 15.45 | 15.48 | 15.52 | 15.57 | ≈ 1.2 |

Values are ns/site. Every case had 0 warm allocations. The slope is Δ(ns/site) × sites /
Δ(slots), taken from 1× to 16×.

**Reading B2.**
- Dead slots cost 0.7–3 ns each per MCS.
- On Akeeb with checkerboard, 4× capacity is already **+7.9 %**, past the 5 % gate, and
  16× is +17 %.
- Monotone ids make the number of dead slots equal cumulative deaths plus headroom, which
  grows without bound in turnover models:
  - 08a: continuous expulsion plus division over thousands of MCS;
  - 06: growth with death;
  - 11: apoptosis and necrosis.
- The tax is (dead slots per site) × (0.7–3.1 ns). At 25 sites per cell, once cumulative
  deaths reach 10× the live count there are 0.4 dead slots per site, which costs
  0.3–1.2 ns/site per MCS. That is 1–8 % of a 15–50 ns/site model, and it keeps rising.

**B3: one capacity growth** (doubling with `with_capacity`, on the host).
- Akeeb, 1000 → 2000: min 8.1 µs, median 9.2 µs, **31 allocations, 169 KiB**.
- OpenVT, 64 → 128: 0.9 µs, 20 allocations, 9.3 KiB.
- This is a lower bound. It excludes rebuilding the `LifecycleCache`, history rings and
  link stores, GPU re-upload, and the integrator's `reinit!` shape change
  (`checkpoint.jl:65`).
- With monotone slots every doubling is a **warm-MCS allocation**, which the gate forbids
  (zero warm allocations). Doubling keeps it to O(log births) events, but never to zero.

**Assessment per item.**

| # | Standard behaviour | Cost in our design (measured where marked) | D-066 |
|---|---|---|---|
| P1 | Immediate death on the last site | None: the volume commit | Adopted (already ours) |
| P2 | Liveness test in cell loops | Any encoding ±0.07 ns/slot (B1) | `volume > 0`, unchanged code |
| P3 | Monotone slots | 0.7–3 ns per dead slot per MCS (B2); +7.9 % at 4× on Akeeb checkerboard; a warm allocation of 169 KiB or more per growth (B3); unbounded memory | **Deviation X1.** Reuse is kept; monotone `birth` serial as the user-visible id, zero warm cost (written by the host at birth) |
| P4 | A dead id never aliases a new cell | Reuse plus references | References cleared before allocation (host, event MCS only); dead referent reads as none (one load per dereference, reference-reading code only) |
| P5 | Links dropped at death | A drop at the copy is a hot-loop, racy write | **Deviation X3.** `volume == 0` skip, reusing the centroid's load; drop at the lifecycle plan and at link phases |
| P6 | Last-site ΔH with no special case | None | Adopted |
| P7 | `no_extinction(k…)` | `k_old` is already loaded (`src/codegen.jl:91`); one compile-time compare | Adopted |
| P8 | Total H over alive cells, death credit in the self-check | Host brute force and tests only | Adopted (convention) |
| P9 | Unpainted live cells | They would make centroid and shape undefined for alive cells, and add an emptiness check in every geometry read | **Deviation X2** |

**Net.** D-066 leaves every sweep and cell loop byte-identical except the `link_delta`
skip, which only relationship models have. The expected gate effect is none. The Akeeb
case moves only because its initial state changes (§5), so it is re-baselined in that
change.

---

## 8. Benchmark scripts (as run)

Run from the main repo root:

```sh
tools/exclusive.sh sh -c 'julia -t 1 --project=benchmark /tmp/liveness_bench/b1.jl; \
                          julia -t 1 --project=benchmark /tmp/liveness_bench/b23.jl'
```

**B1** (`/tmp/liveness_bench/b1.jl`). Plain Julia.

```julia
using BenchmarkTools, Random
function run(cap, layout)
    rng = Xoshiro(1)
    volume = Int32.(rand(rng, 1:60, cap))
    layout === :tail ? (volume[(4cap ÷ 5 + 1):end] .= 0) : (volume[randperm(rng, cap)[1:(cap ÷ 5)]] .= 0)
    kind = Int32.(rand(rng, 1:3, cap)); alive = volume .> 0; retained = zeros(Bool, cap)
    x = rand(rng, cap); R = (Int32(3),)
    f_vol(x, v) = (s = 0.0; @inbounds for c in eachindex(x); v[c] > 0 && (s += x[c]); end; s)
    f_der(x, v, k, R) = (s = 0.0; @inbounds for c in eachindex(x); (v[c] > 0 || k[c] in R) && (s += x[c]); end; s)
    f_ret(x, v, r) = (s = 0.0; @inbounds for c in eachindex(x); (v[c] > 0 || r[c]) && (s += x[c]); end; s)
    f_flag(x, a) = (s = 0.0; @inbounds for c in eachindex(x); a[c] && (s += x[c]); end; s)
    f_volk(x, v, k) = (s = 0.0; @inbounds for c in eachindex(x); kc = k[c]; (v[c] > 0 && (kc == 1 || kc == 3)) && (s += x[c]); end; s)
    f_retk(x, v, r, k) = (s = 0.0; @inbounds for c in eachindex(x); kc = k[c]; ((v[c] > 0 || r[c]) && (kc == 1 || kc == 3)) && (s += x[c]); end; s)
    # each: minimum(@benchmark(f(); samples = 3000, evals = 10)).time / cap
end
for layout in (:tail, :random), cap in (1_000, 10_000); run(cap, layout); end
```

**B2 and B3** (`/tmp/liveness_bench/b23.jl`). These use the gate's own `measure`.

```julia
using BenchmarkTools, Potts, PottsModels, CorePotts, Printf
include(joinpath(pwd(), "benchmark", "gate.jl"))      # `measure`; main() runs only as a script
ak = akeeb_state(; lattice = (99, 60)); ov = openvt_monolayer_state(; lattice = (100, 100))
lcases = [
  ("akeeb_99x60", 1000, cap -> () -> PottsProblem(AkeebInvasion(; name = :a, lattice = (99, 60)), ak, (0, 10^6); T = Float64, capacity = cap)),
  ("openvt_monolayer_100", 64, cap -> () -> PottsProblem(OpenVTGrowingMonolayer(; name = :o, lattice = (100, 100), τ = 1e6), ov, (0, 10^6); T = Float64, capacity = cap))]
for (name, base, mk) in lcases, alg in (SequentialCPM(), CheckerboardCPM()), mult in (1, 2, 4, 16)
    ns, allocs = measure(mk(mult * base), alg)                # warm ns/site, warm allocations
end
# B3: st = init(prob, SequentialCPM(); save_start = false, save_end = false) |> (i -> (step!(i); i.state))
#     @benchmark CorePotts.with_capacity($st, 2 * length($st.cell.kind))
```

---

## 9. Open items

1. **Maintainer confirmation that D-053 item 6 is withdrawn** (§6.1 item 1). That item
   asked for liveness separate from `volume > 0`. The survey finds it is neither standard
   nor needed, and that it would change Fortuna's results. Option B (§6.2) is the fallback.
2. **Akeeb re-baseline.** Emulating CC3D's unpainted leaders changes `akeeb_state` and the
   Akeeb gate case. Re-baseline both in that change, and restate V-A1 in the 10 spec as
   painted leaders ≈ 382.
3. **Fortuna diagnostics.** Count FRONT (14a) and LAMEL (14c) deaths in the port. If they
   are frequent, add a question for the authors: FRONT re-seeding loses target volume in
   14a.
4. **Morpheus ports.** None of the 12 models is one. A future Morpheus port adds
   `no_extinction`.
5. **Recipe.** `CellDeath`-style shrinkage (`remove-volume`, default 3) goes into the R3
   tutorial as the recipe for 11's unspecified apoptosis.
6. **Regression tests (P6.0l).**
   - Link two cells, let one go extinct by copies, and check that the partner still moves
     and `total_energy` is finite.
   - Self-check with a copy that kills a cluster root, and with one that kills a lone
     cell (the cluster death credit).
7. **CC3D 4.x `ConnectivityGlobal`.** Its fast path looks undefined on a last-pixel copy
   (`ConnectivityPlugin.cpp:300`). This matters only if we cite CC3D connectivity
   behaviour.

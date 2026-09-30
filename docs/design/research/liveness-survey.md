# Cell liveness in CompuCell3D, Morpheus and Artistoo, and a proposed amendment to D-035/D-037

Research for ROADMAP P6.5a (R6, "explicit liveness", D-053 item 6). The maintainer's rule
(2026-09-30): follow standard CPM liveness behaviour where performance allows.

**Revision 3** (after review rounds 1 and 2). Main changes:
- Status: **D-066 is PROPOSED**, pending the maintainer's sign-off on its need-based
  deviations (§6.1).
- The recommended decision drops `retain_empty`. No model needs it, and it would change
  Fortuna's results (§5). A repaired `retain_empty` design is kept as Option B (§6.2).
- `id` stays the slot in model code. A separate `birth` serial is the user-visible id
  (§6.1 item 3).
- The self-check credit now covers link energies (§6.1 item 4).
- The B2 numbers are corrected from the reviewer's interleaved rerun (§7).
- Akeeb is moved out of D-066 into an open item (§9).

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

A deviation is either **performance-based** (the standard would cost measurable warm-MCS
time or allocations, which D-065 Q6 allows us to avoid) or **need-based** (no
performance reason, so the maintainer must confirm it).

| # | Standard | Ours | Kind | Reason | Observable effect |
|---|---|---|---|---|---|
| X1 | Monotone ids, never reused (consensus item 7) | Slot reuse, lowest-first, with `generation` (D-035 kept). A monotone `birth` serial is the user-visible id | **Performance** (measured, §7) | Every per-cell loop runs over capacity. A dead slot costs about 3.0 ns per MCS (checkerboard) and about 1 ns (sequential). At 16× capacity Akeeb is +16.3 % and +5 %. With monotone ids every capacity growth allocates in a warm MCS (§7 B3) | None in outputs: users see `birth`. RNG streams are keyed by `generation & 0xff` (`rng.jl:92-93`), so they repeat after 256 reuses of one slot (see note) |
| X2 | Unpainted live cells exist (consensus item 6): CC3D `new_cell`, Artistoo `makeNewCellID`, and CC3D division children that receive no pixel | `@create`/`@convert` allocate and paint in one host routine. A created cell or division daughter that receives no site is **not born**, and its slot stays free | **Need-based, unmeasured** (maintainer sign-off) | Keeps "alive ⇔ owns a site", so no liveness state, no emptiness check in geometry, and no clearing of a flag on first paint. The only occurrence of an unpainted cell in the 12 models is Akeeb's seeding artefact (§5, §9). The cost of the alternative (an "unpainted" flag set at create and cleared on first paint) was not measured | Akeeb's initial state differs from CC3D by about 8 unpainted leaders (handed to P6.2b, §9). Empty division daughters (counted in `empty_daughters`) are not cells |
| X3 | Links of a dead cell dropped **at the killing copy** (CC3D FPP, `FocalPointPlasticityPlugin.cpp:865-875`) | Dropped at the next boundary (§6.1 item 5). Until then the dead partner is skipped in `link_delta` and `total_energy` | **Performance, not measured** | Dropping inside the sweep writes the link store from the hot loop and races on the checkerboard. The cost of that write was not measured | Energetically none after the killing copy. A stale link slot occupies the partner's degree until the boundary |
| — | `retain_empty` (D-053 item 6) | Dropped | **Standard behaviour** (consensus item 3), so no deviation. D-065 Q6 authorises it | Replacing D-053 item 6's semantics is listed for confirmation because it withdraws an earlier answer | Fortuna matches CC3D (§5) |
| — | (no standard) | `total_energy` over alive cells | Not a deviation | No tool uses a total H (item 5) | — |

**Note on X1 and RNG.** `cell_entity(id, generation)` packs `generation & 0xff`. After 256
reuses of one slot, a new cell replays an old cell's cell-addressed streams (also mixed
with `mcs`, so an exact replay also needs the same MCS). This is pre-existing (D-035) and
unlikely at our capacities. It can be fixed by widening the packing if a turnover model
reaches it.

---

## 5. Tie-in to the 12 reference models

Spec ids are from `model-specs/README.md` §1.

### Model 14: Fortuna 2020 / Thomas / Dal Castel (CC3D). Depends on this decision.

Spec 14 asks for a `retain_empty` lamellipodium (14 §8, lines 495 and 516). **The authors'
code keeps no empty lamellipodium, and keeping one would change results.**

**14a** (`codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py`):
- The FRONT-creation step runs **every MCS** (`:121-164`). Whenever there is no FRONT and
  `pFRONT > 0`, a conversion calls `potts.createCell()` and paints the pixel at once
  (`:150-153`). It gives FRONT a target of 1.5 and lowers CYTO's target by 1.5
  (`:155-157`).
- `CELLvol` is a sum of **target** volumes (`:127-138`).
- When FRONT empties, CC3D destroys it (§3), so its target leaves `CELLvol`. `pFRONT` is
  recomputed with FRONTvol = 0, and a new FRONT is created with target 1.5 while CYTO loses
  another 1.5. **Every FRONT death permanently shrinks the cell's total target.**
- The detachment check runs only every `deltaT = 50` MCS (`CellMig3D.py:41`;
  `CellMig3D_Steppables.py:303`) and only after MCS 10 (`:407`).
- An early 1-site FRONT can lose its site to any accepted copy. FRONT emptying is
  therefore **reachable**, and it is re-seeded at the next MCS.
- Spec 14 §2.9.5 (line 210) says "the detachment check … normally stops the run first".
  That is inconsistent with per-MCS re-seeding and is listed for correction (§5 spec
  edits).
- Under `retain_empty`, a retained empty FRONT would keep its target and `pFRONT ≤ 0`: no
  re-seeding, no target loss, and it stays empty. **This is not what the CC3D code does.**

**14c** (`codebases/14c_DalCastel2025_Single_Cell_Chemotaxis_2.3/SCellSign_DISTRIBUTED/Simulation/SCellSignSteppables.py`):
- LAMEL is created and painted at start (`:54-55, 75`).
- `step` binds `LAMELcell` only in `for LAMELcell in self.cellListByType(self.LAMEL)`
  (`:104-105`) and then reads `get_cell_boundary_pixel_list(LAMELcell)` (`:122`).
- A dead LAMEL leaves `LAMELcell` unbound, so the run fails (inferred, not run).

**Under D-066:**
- 14a: FRONT is created on demand by `@convert` into the cluster (R8), and it dies when it
  empties, as in CC3D, target loss included.
- 14c: a LAMEL death ends the run (`@terminate`).
- The port counts FRONT and LAMEL deaths per run.
- 14a's conversion runs every MCS through R8's shared routine. That routine is therefore a
  boundary where links, references and dead roots are cleaned up (§6.1 item 5).

### Model 06: Jiang 2005 tumour. Depends on it.

The necrotic core is "a special cell with ID 0" that "must exist before any death (or be
created on first death)" (06 §G10, line 341; G14). Under D-066, while no core exists, **the
first cell to die transitions into the core kind and becomes the core**.
- This needs no allocation. It is an R3 `@transition` plus R8's retire-into, which uses the
  core as `ref`.
- Its target volume is then set from its volume, and later deaths retire their sites into
  it (`@retire … sites => core`).
- The alternative is an explicit create-if-absent in R8. R8's priority order is remove >
  convert > transition > divide > create, so create runs last. And `sites => ref` with
  ref = 0 reads as "retire to medium". Create-if-absent would therefore need its own rule
  that runs before the retire. The transition route avoids this.
- No empty-but-alive state is needed.

### Model 10: Akeeb 2026 (CC3D 4.6.0). Affected, but handled outside D-066.

**CC3D seeding** (`DEMO/Main_Simulation/cclc_math_path/Simulation/CCIecmSteppables.py:46-57`):
- It calls `self.new_cell(self.LC)` on every draw but paints only on a follower's pixel
  (`c1.type == 2`; FC = 2 and LC = 1, `CCIecm.xml:38-39`).
- `i = LC/(LC+FC)` is recomputed only after a hit, and it counts the unpainted leaders.
- Expected unpainted leaders: Σ_{n<390} n/9481 ≈ **8**, so there are ≈ **382 painted**
  (inferred, not run).
- The unpainted leaders are inert:
  - they never gain a pixel;
  - growth and mitosis touch only FC (`:93-97`, `:118-129`);
  - they fail `yCOM > min_tumor_y` (`:504-513`).
- They are counted in the CSV leader count (spec V-A1, "390").

**Our `akeeb_state`** (`lib/PottsModels/src/akeeb.jl:92-99`) retries a missed draw, so it
paints **390**. `akeeb_state` also feeds the frozen `lib/PottsModels/test/papers.jl:142-163`.

**Handling.** Reproduction 10 is on HOLD, so D-066 does not change Akeeb. The possible
change (count a miss toward the quota without painting, and compare painted leaders in
V-A1) is handed to **P6.2b**, the maintainer-approved V-target audit, as an open item
(§9). Akeeb's `no_extinction` is unchanged, and it has no deaths.

### Models 05 and 07: matrix and fluid collectives

The specs ask for "retain_empty-like persistence" of the matrix and fluid collective cells
(05 G10, `05_bauer2009_ecm.md:266`; 07 G10, `07_bauer2007_sprouting.md:253`).
- These are huge, multiply connected cells, so losing every site through copies is
  implausible, and nothing needs them empty.
- Under D-066 they are ordinary cells.
- A zero-cost guard is available if wanted: `@constraint no_extinction(matrix, fluid)`.
  It is one compile-time compare on the already-loaded `k_old`.
- 05's `@create` recruitment gets new slots and `birth` ids.

### Model 13: Starruss myxobacteria

Rods are clusters of s segments with ordered, sibling-by-index relationships (13 §G10/G11,
lines 197, 202, 214).
- A segment can go extinct through copies. Its siblings' references would then read
  ref = 0 (medium) under D-066 item 5, and the rod would silently lose a segment.
- The paper keeps s fixed, so the port declares `@constraint no_extinction(segment kinds…)`.
  It also asserts a diagnostic: zero segment deaths per run.

### Models 08, 11, 09, 01: nothing changes

- **08 FBCA** and **11 Jafari Nivlouei** have deaths plus division. Dead cells already
  leave populations (`volume > 0`), ids are already reused, and nothing changes except
  that outputs show `birth` ids.
- **09 Graner–Glazier** needs extinction allowed (λ scan, 09 V-PRE8). `no_extinction` stays
  opt-in.
- **01 Merks**: TST's apoptosis at area 0 (01 D-11) is death on emptying, as now.

### Models 04 and 12

No death; nothing changes.

### Spec edits implied by D-066

These are listed only; the specs are not edited in this branch.

| File:line | Current text (gist) | Edit |
|---|---|---|
| `14_nucleus_migration.md:210` | "the detachment check … normally stops the run first" | FRONT emptying is reachable and re-seeded every MCS (`:121-164`); detachment is checked every 50 MCS after MCS 10. Each death loses FRONT's target from `CELLvol` |
| `14_nucleus_migration.md:495` | "retain_empty membership … persist as a cluster member with V = 0" | FRONT is created on demand by `@convert` (R8) and dies when it empties (D-066) |
| `14_nucleus_migration.md:516` | "retain_empty members" | "members created on demand; sibling lookups read ref = 0 when absent" |
| `README.md:122` (R6 row) | "Explicit liveness, separate from volume > 0 … retain-empty MISSING" | "Liveness = owns a site (D-066); `birth` ids; references cleared at boundaries" |
| `README.md:567` (step 5 row) | "retain-empty, explicit liveness (open question 6)" | "liveness per D-066 (no retain-empty)" |
| `06_jiang2005_tumor.md:341` (G10) | "retain_empty: the necrotic core … must exist before any death" | "the first dying cell transitions into the core (D-066)" |
| `05_bauer2009_ecm.md:266`, `07_bauer2007_sprouting.md:253` | "retain_empty-like persistence" | "ordinary cells; optional `no_extinction(matrix, fluid)`" |
| `13_starruss_myxobacteria.md` §G10 | — | Add "`no_extinction` on segments; diagnostic: zero segment deaths" |
| `10_akeeb_invasion.md` V-A1 | "Leaders constant (390 throughout)" | Left to P6.2b (§9) |
| `AUTHORING.md:235` (§5) | "no extinction (default; can be disabled)" | "opt-in `@constraint no_extinction(k…)`" |

---

## 6. Proposed decision

### 6.1 Recommended: D-066 (draft DECISIONS text)

```markdown
## D-066 Cell liveness is the standard CPM one: alive ⇔ owns a site (2026-09-30, P6.5a; PROPOSED — pending maintainer sign-off; amends D-035, D-037; replaces D-053 item 6's semantics)

Survey: `research/liveness-survey.md` (CompuCell3D 3.7.9/4.9, Morpheus 2.4.1, Artistoo).
D-065 Q6 authorises adopting the standard behaviour and keeping our faster mechanism
where the standard costs measurable warm-MCS time or allocations. The maintainer confirms
only the **need-based** items: X2, and dropping D-053 item 6's `retain_empty`/explicit
liveness.

Standard: a cell dies at once when it loses its last site or is removed; a dead cell
leaves every energy, population, iteration, link and plot; the last-site copy pays the
full volume ΔH; there is no "dead but present" state.

1. **Alive** ⇔ the cell owns at least one site: `alive(c) ≡ volume[c] > 0`. `alive` is a
   read-only built-in.
   - **Birth** happens in one of three ways:
     - the initial state;
     - a division daughter that receives at least one site;
     - `@create`/`@convert` (R8), which allocate and paint in one host routine.
     A daughter or created cell that receives no site is not born, and its slot stays
     free.
   - **Death** happens when a copy takes the last site (at once); when a lifecycle rule
     removes the cell (its sites go to medium or to `ref`); or when a conversion takes its
     last site. Death is terminal for (slot, generation).
   - There is no dying state and no empty-but-alive state. Morpheus-style shrinkage is a
     `@transition` to a kind with V₀ = 0 plus `@remove … when volume <= n`.
   - D-053 item 6's `retain_empty`/explicit liveness is dropped (need-based: no model
     needs it, and it would change Fortuna's results; survey §5).
2. **Deviations** (survey §4.1):

   | # | Standard | Ours | Kind | Reason |
   |---|---|---|---|---|
   | X1 | Monotone ids | Slot reuse + `generation`; monotone `birth` shown to users | Performance, measured | A dead slot costs ≈ 3.0 ns/MCS (checkerboard), ≈ 1 ns (sequential). Akeeb at 16× capacity: +16.3 % / +5 %. Every capacity growth allocates in a warm MCS |
   | X2 | Unpainted live cells (created cells, empty division children) | None: created and divided cells must receive a site to be born | Need-based, unmeasured; **maintainer sign-off** | Keeps liveness = site ownership, with no flag or emptiness checks. The only reference-model occurrence is Akeeb's seeding artefact |
   | X3 | Links dropped at the killing copy (CC3D FPP) | Dropped at the next boundary; dead partner skipped meanwhile | Performance, unmeasured | A drop in the sweep is a hot-loop write that races on the checkerboard. No energy effect |

   The total-H convention (item 4) is not a deviation: no tool has a total H.
3. **Ids (amends D-035).**
   - **Slots.** Reused lowest-first, with `generation` incremented. A slot is free when:
     - it is not alive;
     - it had no event this MCS;
     - it is not the root of a cluster with alive members (as now).
   - **`id`** in model expressions stays **the slot**: the `:cell` index sort, so `x[id]`,
     the cluster env's `:id => r`, and `cluster == id` are unchanged.
   - **`birth`** is a separate read-only built-in: a monotone, never-reused Int32 serial.
     - Its counter `next_birth` is stored in the state and checkpointed. It is not max+1,
       which would reissue a dead cell's serial.
     - Initial cells get 1:n.
     - The allocator (lifecycle plan and R8 routine) assigns `next_birth` and increments
       it.
     - `birth` is excluded from the daughter column copy (`lifecycle.jl:336-339`, like
       `generation`).
     - `with_capacity` grows it (new slots 0).
     - Models without births have no column (`birth ≡ slot`).
   - **User-visible outputs map slot → `birth`:**
     - observables and SII `id`;
     - `cluster`, as `birth[root]`;
     - plots and id-based tracking;
     - PIFF export (`write_piff(…; ids = birth)`).
   - **Saved solutions** store σ with slot ids and save the `birth` column alongside it
     (4 × capacity bytes per save, no per-site work). The σ → birth map is applied lazily
     on read, at O(sites) per accessed frame.
4. **Energies (amends D-037).**
   - ΔH is unchanged. The last-site copy pays the full cell-term change to the empty state.
   - `total_energy` sums:
     - cell terms over alive cells;
     - cluster terms over roots `r` (`cluster[r] == r`) of clusters with at least one
       alive member (a copy-killed root still names its cluster until `_fix_clusters!`);
     - edge terms over links whose two ends are both alive.
     A dead cell contributes nothing.
   - **Self-check**, for a copy whose old owner `o` it kills:

         ΔE(copy) == H(after) − H(before) + E_cell(o, empty state)
                     [+ E_cluster(cluster[o], empty state), if that cluster has no alive member left]
                     + Σ_{n linked to o} E_edge(o, n; d(centroid_o before the copy, centroid_n after the copy))

     - "Empty state" is o's tracked quantities after the copy (volume 0, surface 0, …).
     - The edge credit exists because `centroid_shift` returns 0 for a cell going to V = 0
       (`geometry.jl:146`). `link_delta` therefore leaves o's edges at o's pre-copy
       centroid, while H(after) drops them.
     - The check stays exact.
5. **Folds, geometry, contacts, links, references.**
   - Folds, counts, cell ODEs and updates, triggers, observables and plots range over
     alive cells (unchanged: `volume > 0`).
   - Centroid, position, shape and `major_length` are 0 for dead slots (unchanged).
   - The contact graph is built from σ.
   - **References** are cell variables of a declared reference type (e.g. `partner::CellRef`
     in `@variables`), so the allocator can find them.
     - Daughters copy reference variables like every other cell variable. A `divide!` rule
       may reset them.
     - Dereferencing a dead referent reads as `ref = 0`: kind 0 (medium), volume 0, cell
       variables at their defaults. It costs one `volume[ref]` load and a select, in
       reference-reading code only.
     - So `J[kind, kind[partner]]` silently uses the medium row once the partner is dead.
       Guard with `alive(partner)` where that matters.
   - **Links:** `link_delta` and `total_energy` skip a partner with `volume == 0`. This
     reuses `centroid`'s load and fixes the NaN freeze (P6.0l).
   - **Boundaries.** Dead cells' links are dropped, references to them are reset to 0, and
     dead roots are released:
     - (a) in the lifecycle plan of an event MCS;
     - (b) in R8's shared `@create`/`@convert`/`@retire` host routine (it runs every MCS
       in 14a);
     both before any id is allocated, so a reference never aliases a new cell;
     - (c) at the start of each `@link`/`@unlink` host phase, before links are created,
       so a stale degree or `linked` never blocks creation.
     A relationship with none of these never creates links; the skip suffices there.
6. **`no_extinction`** stays opt-in (D-037; CC3D and Artistoo). Morpheus's always-on veto
   would break the Graner–Glazier λ scan.
   - `no_extinction(k…)` forbids a copy that takes the last site of a cell of kinds k…
     (default: all cell kinds), i.e. `old == 0 || volume[old] > 1 || kind[old] ∉ K`.
   - Used by 10 and 13; offered to 05 and 07 (matrix, fluid); added by Morpheus ports.
   - AUTHORING §5 is corrected.
7. **Reproductions** (survey §5):
   - 14a: FRONT is created by `@convert` and dies when it empties, losing its target as in
     CC3D. The port counts FRONT deaths.
   - 14c: a LAMEL death ends the run.
   - 06: the first dying cell transitions into the necrotic-core kind.
   - 13: `no_extinction` on segments.
   - Spec edits: survey §5.

Why: the standard behaviours are already ours (immediate death, full ΔH, exclusion
through `volume > 0`) or free (the `link_delta` skip, `birth`, host-side cleanup). The one
measurably costly standard, monotone slots, is kept only in its user-visible form.
```

### 6.2 Option B (not recommended): `retain_empty`, repaired

This is the design to use if the maintainer rejects dropping it.

- **Declaration and state.**
  - `@kinds k[retain_empty]` declares the kinds.
  - Such models get a `retained::Vector{Bool}` column. It is set at birth for those kinds
    and cleared on removal.
  - `alive(c) = volume[c] > 0 || retained[c]`. The extra load happens only on the
    `volume == 0` branch; models without such kinds have no column.
  - Kind 0 is **not** a dead marker. Kind tables index with `Int(k) + 1`
    (`src/lower.jl:241`), but CorePotts per-kind vectors are 1-indexed by kind and name
    maps are built from `cell_kinds`.
- **Clusters.** `alive(c)` replaces site ownership in:
  - `_live` and `_normalize_clusters!` (`compartments.jl:28, 34, 57-59, 174`);
  - the lifecycle member lists (`lifecycle.jl:270`);
  - `_referenced_clusters` (`compartments.jl:63`);
  - the trigger kernel (`lifecycle.jl:147-154`);
  - the free list (`:260`).
- **No implicit cluster death.**
  - A retained cell dies only by explicit removal of itself or of its cluster, or by a
    transition to a non-retained kind while empty. A lone retained cell never dies
    implicitly.
  - Orphans are removed with `@remove cells(k) when cluster_volume == 0`, in the ordinary
    trigger kernel. No new trigger or synchronisation is needed.
- **Divisions and transitions.**
  - An empty cell is never divided.
  - A retained daughter that receives no site is not born.
  - An empty retained cell that transitions to a non-retained kind dies at that event.
- **Geometry and energy.**
  - Geometry and link creation stay `volume > 0` checks (0 when empty).
  - Folds, ODEs, updates and triggers use `alive`.
  - An empty retained cell contributes E(empty state) to `total_energy`.
- **Cost.** Within B1's noise band (§7).
- **Deviation.** It contradicts consensus item 3 and changes Fortuna's results (§5).

---

## 7. Performance, measured

**Setup.**
- Apple M1 Pro, Julia 1.12.6, single-threaded, under `tools/exclusive.sh`, from the main
  repo (`PottsMonorepo` @ `71372a0`) with the `benchmark` project.
- Scripts are in §8. The full gate was not run.
- Gate context: CPU baselines of 13.7–94.3 ns/site, 5 % tolerance, and zero warm
  allocations (`benchmark/gate.jl:8-20`). There are 10 CPU cases, plus 5 Metal cases that
  are flagged but not gated.

**B1: liveness tests in a fold.** Minimum time per slot, 20 % dead slots at the tail or
scattered, 10³ or 10⁴ slots.

| Variant | tail, 10³ | tail, 10⁴ | random, 10³ | random, 10⁴ |
|---|---|---|---|---|
| `volume > 0` (today, D-066) | 0.817 | 0.821 | 0.729 | 0.842 |
| `volume > 0 \|\| kind ∈ R` | 0.850 | 0.868 | 0.788 | 0.818 |
| `volume > 0 \|\| retained[c]` (Option B) | 0.842 | 0.851 | 0.725 | 0.754 |
| stored `alive::Bool` | 0.854 | 0.884 | 0.729 | 0.846 |
| `volume > 0` + kind filter | 0.583 | 0.615 | 0.638 | 0.978 |
| `\|\| retained[c]` + kind filter | 0.638 | 0.634 | 0.696 | 0.732 |

Values are in ns/slot. The run-to-run noise band is about **±0.35 ns/slot**: the same
`volume > 0` + kind-filter loop ranges from 0.58 to 0.98. No encoding is distinguishable
from today's. At MCS cadence even 0.35 ns/slot is under 0.02 ns/site for Akeeb (1000
slots on 5940 sites). How liveness is stored does not matter in folds. A stored flag
would cost something only if the sweep had to clear it, which is an implementation choice.

**B2: warm cost of dead slots.** Akeeb 99×60 (308 cells, 5940 sites, gate capacity
1000 = 1×).

My single pass (`/tmp/liveness_bench/b23.jl`), in ns/site:

| Case | 1× | 2× | 4× | 16× |
|---|---|---|---|---|
| akeeb sequential | 47.78 | 47.75 | 47.64 | 49.50 |
| akeeb checkerboard | 46.18 | 46.38 | 49.85 | 54.00 |
| openvt sequential (64 = 1×, 10⁴ sites) | 14.00 | 14.02 | 14.03 | 14.11 |
| openvt checkerboard | 15.45 | 15.48 | 15.52 | 15.57 |

All B2 cases had 0 warm allocations.

**The reviewer's interleaved rerun** (`/tmp/rev2_bench/cb.jl`: checkerboard 3 rounds,
sequential 2 rounds, capacities interleaved) is the one to use:

| Case | 2× | 4× | 16× |
|---|---|---|---|
| akeeb checkerboard | +1.3 % | +3.3 to +4.0 % | **+16.3 %** |
| akeeb sequential | — | +1.3 to +1.8 % | **+5 %** |

- My single-pass 4× checkerboard figure (+7.9 %) was an outlier.
- Slopes: about **3.0 ns per dead slot per MCS** on checkerboard, about **1 ns**
  sequential. OpenVT: about 1.1–1.2 ns (few slots, so small effect).

**B3: one capacity doubling** (`with_capacity`, host):
- Akeeb, 1000 → 2000: min 8.1 µs, median 9.2 µs, **31 allocations, 169 KiB**.
- OpenVT, 64 → 128: 0.9 µs, 20 allocations, 9.3 KiB.
- This is a lower bound: it excludes rebuilding the `LifecycleCache`, rings and link
  stores, GPU re-upload, and `reinit!` (`checkpoint.jl:65`).

**Conclusion, based on the 16× numbers and B3.**
- Monotone slots make dead slots equal cumulative deaths plus headroom.
- In turnover models (08a, 06, 11) that reaches 16× the gate capacity: +16 % checkerboard
  and +5 % sequential on Akeeb. Both are over the 5 % tolerance, and the cost keeps
  growing.
- Every capacity growth allocates in a warm MCS, which the gate forbids.
- Slot reuse (X1) is therefore a measured, performance-based deviation.

| # | Standard behaviour | Cost in our design | D-066 |
|---|---|---|---|
| P1 | Immediate death on the last site | None: the volume commit | Adopted (already ours) |
| P2 | Liveness test in cell loops | Any encoding within the ±0.35 ns/slot noise (B1) | `volume > 0`, unchanged |
| P3 | Monotone slots | ≈ 3.0 ns (checkerboard) / ≈ 1 ns (sequential) per dead slot per MCS; Akeeb +16.3 % / +5 % at 16×; a warm allocation of ≥ 169 KiB per growth (B3) | **X1**: reuse kept; `birth` shown to users (host writes at birth only) |
| P4 | A dead id never aliases a new cell | Reuse plus references | References reset at every allocator boundary; a dead referent reads as 0 (one load, reference code only) |
| P5 | Links dropped at death | A drop at the copy is a hot-loop write (unmeasured) | **X3**: skip, then drop at boundaries |
| P6 | Last-site ΔH with no special case | None | Adopted |
| P7 | `no_extinction(k…)` | One compile-time compare on the loaded `k_old` (`src/codegen.jl:91`) | Adopted |
| P8 | Total H over alive cells, self-check credits | Host and tests only | Adopted (convention) |
| P9 | Unpainted live cells | Not measured | **X2**, need-based |

**Net.** D-066 leaves every sweep and cell loop unchanged except the `link_delta` skip,
which only relationship models have. The expected gate effect is none.

---

## 8. Benchmark scripts (as run)

From the main repo root:

```sh
tools/exclusive.sh sh -c 'julia -t 1 --project=benchmark /tmp/liveness_bench/b1.jl; \
                          julia -t 1 --project=benchmark /tmp/liveness_bench/b23.jl'
```

**B1** (`/tmp/liveness_bench/b1.jl`):

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

**B2 and B3** (`/tmp/liveness_bench/b23.jl`; the reviewer's interleaved variant is
`/tmp/rev2_bench/cb.jl`):

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
# B3: st = (i = init(prob, SequentialCPM(); save_start = false, save_end = false); step!(i); i.state)
#     @benchmark CorePotts.with_capacity($st, 2 * length($st.cell.kind))
```

---

## 9. Open items

1. **Maintainer sign-off on D-066** (PROPOSED). The items to confirm are the need-based
   ones:
   - X2: no unpainted live cells or empty daughters;
   - dropping D-053 item 6's `retain_empty` and explicit liveness. Option B (§6.2) is the
     fallback.
   The rest is authorised by D-065 Q6.
2. **Akeeb seeding → P6.2b** (V-target audit; reproduction 10 is on HOLD).
   - CC3D paints ≈ 382 leaders and counts ≈ 8 unpainted ones in its "390".
   - Our `akeeb_state` retries misses and paints 390.
   - Possible change: count a missed draw toward the quota without painting, and restate
     V-A1 as painted leaders.
   - Any change to `akeeb_state` touches the frozen `lib/PottsModels/test/papers.jl:142-163`
     and the gate's Akeeb case. Both need re-baselining under that audit.
3. **Fortuna diagnostics.** Count FRONT (14a) and LAMEL (14c) deaths in the port. If they
   are frequent, ask the authors about target loss on re-seeding.
4. **`_fix_clusters!` re-rooting** (pre-existing, not caused by D-066). When a root dies
   and no live member shares its kind, `_normalize_clusters!` re-roots to the lowest live
   member of any kind (`compartments.jl:45-53`). Cluster terms are selected by the root's
   kind, so H jumps at that event. Worth a separate note or decision.
5. **RNG stream repetition** after 256 reuses of one slot (`rng.jl:92-93`, §4.1 note).
   Widen the packing if a turnover model reaches it.
6. **Regression tests (P6.0l and D-066).**
   - A linked cell goes extinct by copies: its partner keeps moving and `total_energy` is
     finite.
   - Self-check on a copy that kills a linked cell (edge credit), a cluster root, and a
     lone cell (cluster credit).
   - A dead `partner` reads kind 0.
   - The `birth` serial survives a checkpoint round trip and is not copied to daughters.
7. **Recipes and ports.**
   - `CellDeath`-style shrinkage (`remove-volume`, default 3) goes into the R3 tutorial
     for 11's apoptosis.
   - Morpheus ports add `no_extinction`.
8. **CC3D 4.x `ConnectivityGlobal`.** Its fast path looks undefined on a last-pixel copy
   (`ConnectivityPlugin.cpp:300`). This matters only if we cite it.

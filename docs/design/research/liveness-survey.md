# Cell liveness in CompuCell3D, Morpheus and Artistoo, and a proposed amendment to D-035/D-037

Research for ROADMAP P6.5a (R6, "explicit liveness", D-053 item 6). The maintainer's rule
(2026-09-30): follow standard CPM liveness behaviour where performance allows.

**Contents.** §1 sources · §2 our current behaviour · §3 comparison table · §4 standard
behaviour and disagreements · §5 tie-in to the 12 models · §6 proposed decision (draft
DECISIONS text) · §7 performance assessment · §8 micro-benchmark sketches · §9 open items.

---

## 1. Sources

All paths are cited at a fixed commit. Nothing was run; every claim comes from reading
the code (the few inferences are marked).

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

Our code is cited at `6ec712a` (branch `feat/p6-5a0`).

---

## 2. Our current behaviour (D-035, D-037, code)

- **Alive means `volume > 0`.** No column stores liveness. It is tested in:
  - the lifecycle trigger kernel (`lib/CorePotts/src/lifecycle.jl:147-154`);
  - cell ODEs (`src/codegen.jl:429`, `:514`);
  - cell updates (`src/codegen.jl:694`);
  - link creation (`src/codegen.jl:631`);
  - `cells(…)` folds (`src/lower.jl:295`);
  - centroids (`src/lower.jl:187`);
  - cluster-root holding (`lib/CorePotts/src/compartments.jl:63`).
- **Death on the last site is immediate and free.** The copy's volume commit takes the
  cell to 0, and from then on it is not alive.
- **Explicit removal:** `EVENT_REMOVE` sets the cell's sites to medium
  (`lifecycle.jl:166-170`). Trackers are then rebuilt exactly (`:365`).
- **Id reuse (D-035).**
  - A slot is free when `volume == 0`, it has no event this MCS, and it is not a cluster
    root still naming live members (`lifecycle.jl:257-260`).
  - Daughters take free ids lowest-first.
  - `generation` is incremented on reuse (`:342-344`) and feeds cell-addressed randomness
    (`rng.jl:92-93`).
  - Capacity is fixed per problem: `2n + 64` with divisions (`src/problem.jl:334`). When
    it is exhausted, divisions are deferred with a warning (`lifecycle.jl:233-240`, `:291`, `:305`).
- **Energy (D-037).**
  - ΔH of the copy that takes a cell's last site includes λ[(0−V₀)² − (1−V₀)²].
  - `total_energy` sums cell terms over **every slot**, so an emptied cell keeps
    `E(V = 0)` (`src/codegen.jl:792`). This keeps the self-check `ΔE == H(after) −
    H(before)` exact.
- **`no_extinction`** is opt-in (`@constraint no_extinction`, D-037). It is
  `forbid_extinction(volume, prop) = prop.old == 0 || volume[prop.old] > 1`
  (`lib/CorePotts/src/drives.jl:80`). Only Akeeb uses it (`lib/PottsModels/src/akeeb.jl:54`).
- **Stale doc.** AUTHORING §4 (`docs/design/AUTHORING.md:235`) still says "no extinction
  (default; can be disabled)", which contradicts D-037. It should be fixed with the new
  decision.
- **Latent bug found in this survey: links to a cell that dies by losing its last site.**
  - Links are dropped only for `EVENT_REMOVE` cells and daughters
    (`lifecycle.jl:358-359`, `_lifecycle_links!`).
  - A linked cell that dies through a copy keeps its links.
  - `centroid(n)` for that cell divides `m1` by `V = 0`, giving NaN
    (`geometry.jl:125-131`).
  - Both `link_delta` for its surviving partner (`relationships.jl:169-173`) and
    `total_energy`'s edge loop (`src/codegen.jl:830-837`) then read a NaN distance.
  - This is not reachable in any shipped model today, because none combines relationships
    with extinction, but it is exactly what a liveness definition must settle (§6 item 5).

---

## 3. Comparison table

| Question | CC3D 4.x | CC3D 3.7.9 | Morpheus 2.4.1 | Artistoo | Potts.jl today |
|---|---|---|---|---|---|
| **Dies when it loses its last site through a copy?** | **Yes, immediately.** `--volume == 0` records the cell (`plugins/VolumeTracker/VolumeTrackerPlugin.cpp:84-96`). The stepper after that same copy attempt calls `destroyCellG` (`:99-113`; steppers run per attempt, `Potts3D/Potts3D.cpp:877, 909-912`) | Yes, same design (`VolumeTrackerPlugin.cpp:118-130, 142-150`; `Potts3D.cpp:676, 688`) | **Cannot happen.** A hard veto on every last-node copy for non-medium types (`core/celltype.cpp:652-654`), checked before ΔH (`core/cpm_sampler.cpp:461-477`) | **Yes, immediately in `setpixi`.** `delete cellvolume[t]; delete t2k[t]` (`models/CPM.js:396-403`; `GridBasedModel.js:155-168`) | Yes, immediately (the volume commit) |
| **Explicit removal** | `delete_cell` overwrites every pixel with medium, so the cell dies by the rule above (`cc3d/core/PySteppables.py:2636-2647`). Soft idiom in demos only: `targetVolume = 0` (e.g. `Demos/.../pressureFieldSteppables.py:27`) | `deleteCell`, same approach (`pythonSetupScripts/PySteppables.py:752-758`) | Retype to medium: `CPM::setCellType(id, Empty)` (`core/cpm.cpp:609-614`) → `MediumCellType::addCell` (`celltype.cpp:791-805`). `CellDeath`, once per MCS: lysis (immediate) or shrinkage (`plugins/miscellaneous/cell_death.cpp:76-172`) | `GridManipulator.killCell` (experimental) setpix's every pixel to 0 (`grid/GridManipulator.js:42-53`) | `EVENT_REMOVE` sets sites to medium (`lifecycle.jl:169`) |
| **Intermediate "dying" state** | No (a "Dead" type is user convention) | No | **Yes.** Shrinkage sets target 0 and keeps the cell in a `dying` set until `nNodes ≤ remove-volume` (default **3**, `cell_death.xsd:22`; `cell_death.cpp:83-98`) | No | No |
| **Ids reused?** | **No** for normal creation: `++recentlyCreatedCellId` (`Potts3D.cpp:334-339`). Yes for explicit-id creation (PIF) of a destroyed id (`:381-405`) | **Never**: explicit ids ≤ counter just increment (`Potts3D.cpp:388-389, 432-447`) | **No** by default: monotone `getFreeID` (`celltype.h:25`; `celltype.cpp:37-50, 470-490`). Explicit ids (XML, division `daughter_ids`) may reuse dead ones (`isFree`, `celltype.h:24`) | Monotone until the Uint16 wrap at 65534, **then dead ids are reused**, skipping live ones (`CPM.js:463-478`) | **Yes**: lowest-first among free slots (D-035) |
| **Generation counter** | None (`clusterId` monotone too, `:344-363`) | None | None | None | `generation` per slot, incremented on reuse |
| **Dead cell in energy** | Absent: object deleted, no pixels | Absent | Absent after removal. Shrinking cells are fully present | Absent: no pixels | ΔH: absent. `total_energy`: keeps `E(V=0)` (D-037) |
| **Dead cell in populations and iteration** | Removed from `CellInventory` (`CellInventory.cpp:79-84`) → `cell_list`, `cell_list_by_type` | Same | Removed from the type's `cell_ids` (`celltype.cpp:627-629`) → `getCellIDs`, `FocusRange`, population-size symbol (`:99`); and from storage (`:65-73`) | Dropped from `cellIDs()` = `Object.keys(cellvolume)` (`GridBasedModel.js:119-121`), so all stats skip it | Skipped by `volume > 0` in folds, ODEs, updates and triggers |
| **Neighbours, links, plotting** | NeighborTracker entries go as the common area reaches 0 (`NeighborTrackerPlugin.cpp:122-170`). FPP drops links at `volume == 0` (`FocalPointPlasticityPlugin.cpp:865-875`). The player sees no pixels | Same | Nodes reassigned via `setNode`, so interfaces update | `borderpixels` per pixel (`CPM.js:423-452`). A stale `cellperimeters[t] = 0` is harmless (`PerimeterConstraint.js:142-148`) | Contact graph from σ excludes it. **Links are not dropped on copy-death** (§2) |
| **Zero-volume live cell possible?** | **Yes.** `new_cell` / `createCell` enters the inventory at volume 0 (`PySteppables.py:2425-2435`; `Potts3D.cpp:363`). Destruction fires only on a *decrement* to 0, so an unpainted cell persists (inferred) | Yes (same) | Yes, transiently: daughters are created empty (`celltype.cpp:531-536`). Empty XML-initialised cells are dropped (`:251-253`) | **Yes.** `makeNewCellID` sets `cellvolume[id] = 0` (`CPM.js:476-477`), so the cell is in `cellIDs()` before painting | No (only free slots have V = 0) |
| **Total H; does λ(V−V₀)² count at V=0?** | **No total H.** `totalEnergy` sums `localEnergy`, which is 0 for every plugin (`Potts3D.cpp:458-469`; `EnergyFunction.h:29`). Only the accepted ΔH is accumulated (`:868`) | Same | `CellType::hamiltonian` sums over `cell_ids`, empty ones included (`celltype.cpp:639-650`; `volume_constraint.cpp:26-31`), but **nothing calls it** | No total H; only `deltaH` (`CPM.js:278-284`) | `total_energy` over all slots (D-037) |
| **ΔH of the last-site copy** | Full λ[(0−V₀)² − (1−V₀)²], no special case (`plugins/Volume/VolumePlugin.cpp:153-155, 192-194, 236-238`) | Same (`VolumePlugin.cpp:226, 277, 320`) | Same formula (`volume_constraint.cpp:12-24`), but never evaluated because of the veto | Same (`hamiltonian/VolumeConstraint.js:60-83`) | Same |
| **Extinction guard** | None built in. 2D `Connectivity` adds a soft +64 to an isolated last pixel (`ConnectivityPlugin.cpp:102-106`). `ConnectivityGlobal`'s fast path dereferences an empty set on a last pixel (`:300`; looks like undefined behaviour, not run) | None | **Always on** (hard veto, above) | None by default. `HardVolumeRangeConstraint` with min ≥ 1 forbids it (`HardVolumeRangeConstraint.js:44-55`) but is not auto-added (`AutoAdderConfig.js:20-26`) | Opt-in `@constraint no_extinction` |

Also found, but outside our scope:
- Artistoo's `nr_cells` is decremented but never incremented (`CPM.js:46, 402`), so the
  65533-live-cells guard at `:464` never fires.

---

## 4. Standard behaviour (consensus) and disagreements

**Consensus of all three tools (and our code today):**
1. **Death is immediate on losing the last site.** It happens at the copy that removes
   that site, not deferred to the end of the MCS. Morpheus is the exception: it forbids
   the copy instead.
2. **Explicit removal is "give the sites away, then the cell is gone".**
   - CC3D and Artistoo overwrite the cell with medium.
   - Morpheus retypes it to medium or to a neighbour.
   - None has a separate "dead but on the lattice" state in core.
3. **A dead cell leaves every inventory at once.** It is gone from energies, populations,
   per-cell iteration, neighbour tracking and plotting. It is never revived: a new cell
   gets a new object.
4. **The volume ΔH of the last-site copy has no special case at V′ = 0.** The copy pays
   λ(0−V₀)² − λ(1−V₀)².
5. **No tool computes a total Hamiltonian that is ever used.** So "does a dead or empty
   cell contribute to H" has no standard answer. Our `total_energy` convention is ours to
   choose.
6. **A zero-volume cell can be alive.** A newly created, not-yet-painted cell is in the
   inventory in CC3D and Artistoo, and transiently in Morpheus. None of them destroys a
   cell for *being* empty, only for *becoming* empty through a site change.
7. **Ids are monotone by default and there is no generation counter.**

**Where they disagree:**

| Point | CC3D | Morpheus | Artistoo |
|---|---|---|---|
| Can the dynamics kill a cell at all? | Yes | **No** (hard veto) | Yes |
| Dying state | No | Shrinkage mode | No |
| Id reuse | Never for normal creation. Explicit ids may reuse dead ones (4.x only) | Explicit ids may reuse dead ones | After the Uint16 wrap |
| Empty unpainted cells | Persist forever, counted in `cell_list` | Removed at init only | Persist until painted and emptied |

**Reading of "standard".**
- Items 1–4 and 7 are the standard.
- Monotone ids are standard in *intent*. Every tool nevertheless reuses dead ids at some
  edge (explicit ids, or wrap-around), so no tool guarantees never-reuse.
- On extinction, CC3D and Artistoo (allowed) against Morpheus (forbidden) is a real split.
  Our opt-in `no_extinction` sits with the majority and with the published models (§5).

---

## 5. Tie-in to the 12 reference models

Which of the 12 depend on these semantics (spec ids from `model-specs/README.md` §1):

| # | Model | Depends on | How |
|---|---|---|---|
| 14 | Fortuna 2020 / Thomas / Dal Castel (CC3D) | **alive-but-empty; death on emptying** | The spec needs the lamellipodium (FRONT) to persist as a cluster member with V = 0 and its own target (14 §8, `retain_empty`). The CC3D code instead **creates FRONT lazily** on the first conversion and **destroys it** if its volume reaches 0; a new FRONT would then restart at target 1.5 (14 §2.9.5 "Edge case"; `codebases/14a_Fortuna2020_Crawling/Published/Simulation/CellMig3D_Steppables.py:149-164`). A retained-empty FRONT is therefore a documented deviation in that unreachable-in-practice edge case (the detachment check stops the run first, `CellMig3D_Steppables.py:407-411`). It needs: an alive empty member, a stable id held by its cluster, ODE/update state that keeps evolving, and a volume ΔH when it re-gains sites via `@convert` (no ΔH, host event) |
| 10 | Akeeb 2026 (CC3D 4.6.0) | **population counts include zero-volume cells; `no_extinction`** | Leader seeding (`DEMO/Main_Simulation/cclc_math_path/Simulation/CCIecmSteppables.py:46-57`) calls `self.new_cell(self.LC)` on **every** loop iteration but paints only when the drawn pixel is a follower's (`c1.type == 2`). A draw that lands on an existing leader leaves an **unpainted zero-volume leader in the inventory** (§3 row "zero-volume live cell"), and `len(cell_list_by_type(LC))` counts it. With 390 leaders drawn into ≈ 499 × 19 = 9481 follower pixels, the expected number of such phantom leaders is ≈ Σₙ n/9481 ≈ 390²/(2·9481) ≈ **8** (inferred, not run). So CC3D's "390 leaders" (sample `CellCount_2_24_0.5.csv` row 0; spec V-A1) is ≈ 382 painted plus ≈ 8 empty ones, which never die because they never lose a pixel. They are excluded from the singles metric only because `yCOM = 0` fails `yCOM > min_tumor_y` (`CCIecmSteppables.py:504-513`). Also, `no_extinction` + connectivity: the 1-site leaders are protected by the connectivity penalty in CC3D (10 §Connectivity, P2); our port uses `@constraint no_extinction`. Akeeb has no death, so ids are never freed and cross-frame cluster tracking by member ids (`CCIecmSteppables.py:844-856`) is unaffected by reuse |
| 06 | Jiang 2005 tumour | **an alive collective that starts empty** | Dead cells are absorbed into a necrotic core, "a special cell with ID 0" whose target volume grows by each dead cell's volume. The core "must exist before any death (or be created on first death)" (06 §G10, G14). This is an alive, empty cell kind until the first death, and it must not be connectivity-constrained |
| 08 | FBCA (Graudenzi/Maspero) | **death and turnover; populations exclude the dead** | Deletion at the open lower boundary, therapy death at p = 0.5/MCS and starvation death, together with division (08 §Death). Dominant-type population gates must exclude dead cells. This is the model where monotone ids would grow capacity without bound (§7) |
| 11 | Jafari Nivlouei 2021 | **death and turnover** | Apoptosis removal mode is UNSPECIFIED (target → 0 vs instant, 11 §N); necrosis is a kind transition; migrated cells are removed and counted. Either removal mode is expressible (`@remove` or a shrink transition) |
| 09 | Graner–Glazier / Osborne | **extinction must be allowed** | The λ scan relies on cells vanishing (λ = 0.1: all vanish; 09 V-PRE8). This confirms that `no_extinction` must stay opt-in (Morpheus's always-on veto would break this reproduction) |
| 01 | Merks | weak | TST marks a cell apoptosed at area 0 (01 D-11). This is death on emptying, and rare |
| 04, 05, 07, 12, 13 | — | none | No death described (05, 07 explicitly; 12, 13 fixed cell count). 05's `@create` recruitment needs new ids only |

**Summary.**
- 14 and 06 need **alive-but-empty cells**.
- 08 and 11 need **dead cells excluded from populations**, and their turnover is where
  **id reuse** matters for performance.
- 09 needs **extinction allowed by default**.
- 10 exposes a **CC3D quirk (phantom empty leaders)** that the reproduction must either
  match or list as a deviation (§9).

---

## 6. Proposed decision (draft text for DECISIONS)

> The number is to be assigned by the coordinator; the next free one at `6ec712a` is D-064.

```markdown
## D-064 Cell liveness: standard CPM semantics with a derived `alive` (2026-09-30, P6.5a; amends D-035 and D-037)

Survey: `research/liveness-survey.md` (CompuCell3D 3.7.9/4.9, Morpheus 2.4.1, Artistoo).
The standard is: a cell dies at once when it loses its last site or is removed; a dead
cell leaves every energy, population, iteration and contact structure; the last-site copy
pays the full volume ΔH; nothing has a "dead but present" state. We follow it, with two
recorded deviations (id reuse, total H).

1. **Alive.** A cell is alive from birth (initial state, division daughter, `@create`) to
   death. Death is terminal for that (id, generation).
   - A cell dies when a copy takes its last site (immediately, as CC3D and Artistoo),
     unless its kind is declared `@kinds k[retain_empty]`.
   - A cell dies when a lifecycle rule removes it (`@remove`/`@retire`; its sites go to
     medium or to the named target).
   - A `retain_empty` cell dies only by removal, or when no alive member of its cluster
     that is not `retain_empty` remains (checked at the lifecycle boundary).
   - There is no dying state in core. Morpheus-style shrinkage is a user `@transition` to
     a kind with V₀ = 0 plus `@remove … when volume <= n`.
   - Alive-but-empty cells exist only for `retain_empty` kinds. `@create` paints in the
     same host routine that allocates, so an unpainted created cell is never observable
     (deviation from CC3D's persistent unpainted `new_cell`, see item 6).
2. **Representation (derived, no new column).**
   `alive(c) = volume[c] > 0 || kind[c] ∈ R`, where R is the compile-time set of
   `retain_empty` kinds. With R = ∅ it compiles to `volume[c] > 0`, i.e. today's code.
   A removed `retain_empty` cell, and every free slot, carries kind 0 (the medium kind,
   never a cell's kind); `with_capacity` fills new slots with kind 0 instead of 1.
   `alive` becomes a built-in cell name (read-only).
3. **Ids (amends D-035).** Slots are still reused, lowest-first, with `generation`
   incremented. This is a recorded deviation from the monotone ids of all three tools
   (which themselves reuse dead ids at explicit-id creation or at wrap-around). A slot is
   free only when it is not alive, did not die in this MCS's event plan, and is not held.
   Held means: the root of a cluster with alive members (as now), or named by an alive
   cell's reference variable (R6 `partner`, `x[ref]`). The identity of a cell is
   (id, generation). An optional monotone `birth` serial (Int64, written at birth by the
   host) gives CC3D-style never-reused ids for output and analysis; it exists only if the
   model or an observable reads it.
4. **Energies (amends D-037).**
   - ΔH is unchanged. The copy that takes a cell's last site pays λ[(0−V₀)² − (1−V₀)²],
     as in all three tools. A `retain_empty` cell pays the same when it empties.
   - `total_energy` sums cell and cluster terms over **alive** cells and alive roots only.
     A dead cell contributes nothing. An alive empty cell contributes E(volume = 0).
   - The self-check becomes `ΔE == H(after) − H(before) + Σ E_c(volume = 0)` over the
     cells the copy killed (at most one: the old owner). It stays exact (0.0).
   - Deviation: no tool uses a total H, so this is our convention, not a standard.
5. **Folds, populations, contacts.**
   - `cells(…)` folds, `mean` counts, cell ODEs, cell updates, lifecycle triggers,
     observables and plots range over alive cells (`alive(c)` replaces `volume[c] > 0`).
     So `retain_empty` cells keep integrating their ODEs while empty.
   - The contact graph is built from σ, so dead and empty cells have no contacts.
   - Links incident to a dead cell are dropped:
     - at the next lifecycle or host boundary for copy-deaths;
     - at once for removals (as now).
     Until then, `link_delta` and `total_energy` skip a partner with volume 0. This fixes
     the NaN distance of a link to a copy-killed cell.
6. **`no_extinction`.** Stays opt-in (D-037), following CC3D and Artistoo. Morpheus's
   always-on veto would break the Graner–Glazier λ scan. It becomes
   `@constraint no_extinction(k…)`: forbid a copy that would **kill** an alive cell of
   kinds k… (default: every cell kind not in R), i.e.
   `old == 0 || volume[old] > 1 || kind[old] ∉ K`. Naming a `retain_empty` kind
   explicitly forbids emptying it too. A model ported from Morpheus adds
   `no_extinction` to match Morpheus's veto. Fix AUTHORING §4, which still calls it a
   default.
7. **Reproductions.** Fortuna's lamellipodium is `retain_empty` (CC3D recreates FRONT at
   target 1.5 after it empties; documented edge-case deviation). Jiang 2005's necrotic
   core is `retain_empty`. Akeeb's CC3D seeding leaves about 8 unpainted leaders in the
   inventory; the reproduction matches the painted count and lists the difference.

Why: the dynamics (death on emptying, full ΔH, exclusion everywhere) are the standard and
cost nothing, since `volume > 0` is already read where liveness is. The two costly parts
of the standard are not followed:
- Monotone ids make every per-cell loop range over every cell ever born, and capacity
  reallocate.
- A stored `alive` flag needs a write in the sweep's commit.
```

---

## 7. Performance assessment

The design constraints:
- a GPU-friendly SoA of cell slots (`st.cell.*`, length = capacity);
- zero warm allocations;
- the gate in ns/site per MCS: `benchmark/gate.jl`, 5 % tolerance. Baselines are
  13.7–94.3 ns/site CPU (`benchmark/baseline.toml`).

The sweep is O(sites) per MCS. Every per-cell kernel is O(capacity) per MCS. Cell-count
work therefore reaches ns/site as

    extra ns/site ≈ (#cell loops per MCS) × (capacity / sites) × (ns per slot per loop)

At about 25–100 sites per cell, an O(capacity) loop costs 1–4 % of an O(sites) loop.

| # | Standard behaviour | Cost in our design | Proposal |
|---|---|---|---|
| P1 | Immediate death on the last site | **None.** The volume commit already takes V to 0; `volume > 0` is the test | Adopt (it is what we do) |
| P2 | Explicit liveness distinct from V > 0 (empty-but-alive) | **Stored flag:** a new `alive::Vector{Bool}` column is one more load per slot per cell loop (small), and it must be *cleared* when a copy empties a cell. That is a branch plus a store in the commit path, and on the checkerboard it needs the post-value of the atomic volume decrement: a **hot-loop** change. **Derived** `volume > 0 \|\| kind ∈ R`: when R = ∅, identical code (zero). When R ≠ ∅, one compare on `kind[c]`, which the fold's kind test already loads; folds with no kind filter add one Int32 load per slot at MCS cadence only. The sweep never reads liveness: owners of sites are alive by construction | **Zero-cost realisation:** derived `alive` (§6 item 2). Only models that declare `retain_empty` (14, 06) pay the one compare |
| P3 | Monotone, never-reused ids | **Measurable, and grows with time.** Capacity must be at least the cumulative births. (a) Every per-cell kernel (trigger, ODEs, updates, folds, population phases, `rebuild_trackers!`) runs over all dead slots, so the cost above scales with births/live instead of 1. For a turnover model (08a: continuous expulsion plus division, thousands of MCS) this is unbounded. (b) When capacity is exhausted: either defer (wrong science) or grow. Growth reallocates every SoA column, link store and history ring (`with_capacity`, `phases.jl:140`), re-uploads to the GPU, and makes `reinit!` shapes differ (`checkpoint.jl:65`). That is a warm-path allocation on an event MCS. (c) Memory: GPU buffers sized for the peak cumulative count | **Keep reuse** as a recorded deviation (§6 item 3). Give standard-style monotone identity through the optional `birth` serial: an Int64 written only at birth by the host planner, never read in kernels unless the model reads `birth`. Zero warm cost |
| P4 | A dead id is never confused with a new cell | Reuse + references (R6) could point a stale reference at a new cell | **Hold** referenced ids (host scan of reference columns at event MCS only, O(capacity × #ref columns)). Zero warm cost. `generation` already distinguishes the rest |
| P5 | Dead cells leave contact and link structures | Links of copy-killed cells: dropping them in the sweep would be a hot-loop write. **Skip-if-empty** in `link_delta` reuses the `volume[n]` load that `centroid` already does. Dropping at the next boundary is host-only | Zero-cost realisation (§6 item 5) |
| P6 | Last-site ΔH with no special case | None (current code) | Adopt |
| P7 | `no_extinction` over kinds | `forbid_extinction` already loads `volume[old]`; `k_old` is already loaded for the kind tables (`src/codegen.jl:91`). A compile-time kind set adds one compare, or nothing when K = all kinds | Adopt (§6 item 6) |
| P8 | Total H over alive cells, death credit in the self-check | Host brute force and tests only | Adopt |
| P9 | Cluster death of `retain_empty` members | Host planner, event MCS only; the member lists are already built (`lifecycle.jl:266-271`) | Adopt |
| P10 | Kind 0 for free slots | `with_capacity` initial fill only. Kind tables already accept 0 (`owner_kind`, `fields.jl:95`) | Adopt. Check that no kind table indexes `kind[c]` of a free slot as ≥ 1 |

**Net.** With the proposal, models without `retain_empty` compile to byte-identical cell
loops. Models with it add one integer compare per slot per cell loop at MCS cadence. The
sweep is untouched in every model, so no gate case should move. The two rejected standard
mechanisms (P2 stored flag, P3 monotone ids) are the only ones with hot-path or growing
cost.

---

## 8. Micro-benchmark sketches (for the implementer; not run)

Run each single-threaded, like the gate.

**B1. Liveness test in a fold.** This is the per-slot cost of P2's variants. Plain Julia,
no Potts.

```julia
using BenchmarkTools, Random
cap = 10_000; rng = Xoshiro(1)
volume = Int32.(rand(rng, 0:60, cap)); volume[rand(rng, 1:cap, cap ÷ 5)] .= 0
kind   = Int32.(rand(rng, 0:3, cap)); alive = volume .> 0
x      = rand(rng, cap)
R = (Int32(3),)                                     # retain_empty kinds
f_vol(x, v)        = (s = 0.0; @inbounds for c in eachindex(x); v[c] > 0 && (s += x[c]); end; s)
f_der(x, v, k, R)  = (s = 0.0; @inbounds for c in eachindex(x); (v[c] > 0 || k[c] in R) && (s += x[c]); end; s)
f_flag(x, a)       = (s = 0.0; @inbounds for c in eachindex(x); a[c] && (s += x[c]); end; s)
f_derk(x, v, k, R) = (s = 0.0; @inbounds for c in eachindex(x)   # fold with a kind filter (kind ∈ {1,3})
        kc = k[c]; ((v[c] > 0 || kc in R) && (kc == 1 || kc == 3)) && (s += x[c]); end; s)
@btime f_vol($x, $volume); @btime f_der($x, $volume, $kind, $R)
@btime f_flag($x, $alive); @btime f_derk($x, $volume, $kind, $R)
# report ns/slot = time / cap. Expect f_der ≈ f_vol + ≤ 0.3 ns/slot; f_derk ≈ f_vol with kind filter.
```

**B2. The cost of dead slots (P3, monotone ids).** Warm ns/site against the capacity
multiple, using the gate's own measurement. This is exactly the tax monotone ids would
impose as births accumulate.

```julia
# julia --project=benchmark (single-threaded)
using BenchmarkTools, Potts, PottsModels
include("benchmark/gate.jl")      # defines `measure`; its `main` runs only as a script
σk = akeeb_state(; lattice = (99, 60))
ncell = length(σk[2].second)       # akeeb_state returns [ownership => σ, kind => kinds, …]
for mult in (1, 2, 5, 10, 20)
    make = () -> PottsProblem(AkeebInvasion(; name = :a, lattice = (99, 60)), σk, (0, 10^6);
        T = Float64, capacity = mult * ncell + 64)
    ns, allocs = measure(make, CheckerboardCPM())
    println(mult, "×  ", round(ns; digits = 2), " ns/site  allocs ", allocs)
end
# Slope of ns/site vs capacity/sites = the per-slot cost of the per-cell phases. Repeat
# with `OpenVTGrowingMonolayer` (lifecycle every MCS) to include the trigger kernel.
```

**B3. The `with_capacity` growth event (P3b).** The one-off cost and allocation of
doubling capacity mid-run, which monotone ids would make recurrent.

```julia
using CorePotts, BenchmarkTools
st = …                             # host CPMState of the B2 problem (integ.state)
@btime CorePotts.with_capacity($st, 2 * length($st.cell.kind))    # time + allocs per growth
```

**B4. Gate check after implementation.** Run `benchmark/gate.jl` unchanged. The
expectation is ratio ≤ 1.00 ± noise on all 10 CPU cases, because none declares
`retain_empty`.

---

## 9. Open items

1. **Akeeb phantom leaders.**
   - Should the reproduction reproduce CC3D's ≈ 8 zero-volume leaders (for example, a
     layout option that allocates cells without painting them), or seed 390 painted
     leaders and list the difference as a deviation?
   - Recommendation: seed painted leaders only, record the deviation, and check the spec
     V-A1 "Leaders constant (390 throughout)" against the painted count.
   - Needs a reproduction decision, not a core one.
2. **Morpheus-built models.** None of the 12 reproductions is a Morpheus port, as far as
   the specs say. If one is added, it needs `no_extinction` to match Morpheus.
3. **`remove-volume` shrinkage** (Morpheus `CellDeath`, default 3) is the natural recipe
   for 11's unspecified apoptosis. It goes into the R3 tutorial, not into core.
4. **CC3D 4.x `ConnectivityGlobal` fast path** looks undefined on a last-pixel copy
   (`ConnectivityPlugin.cpp:300`). This is irrelevant to us (our connectivity is our own)
   but worth a note if we cite CC3D connectivity behaviour.
5. **Latent link NaN (§2)** is fixed by §6 item 5. A regression test would: link two
   cells, let one go extinct by copies, and check that the partner's ΔH stays finite.

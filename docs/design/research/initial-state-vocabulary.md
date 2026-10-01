# Initial states: layout vocabulary and per-cell initial values (Morpheus-led)

> - **Status:** research input, reviewed (`initial-state-review.md`, 2026-10-01). Corrections are marked inline.
> - **Adopted:** P6.1a6 and P6.1a7. Everything else rides its model row or is deferred (see the review).
> - The Q1–Q10 answers are the peer session's proposals, not ratified, except where the review adopts them.

Date: 2026-10-01. Status: research and proposal, not ratified. Scope: (a) the layout
vocabulary that places cells, and (b) setting per-cell and per-site values at the start.
**Out of scope:** import and export (PIF/PIFF, TIFF, CSV and every other file format). This
note only says where a choice has to leave room for them (§5.9).

Every claim cites a source. **[unverified]** marks a claim I could not confirm from source.

**Sources.**
- **Morpheus source:** `gitlab.com/morpheus.lab/morpheus`, branch `main`, read with WebFetch
  (raw files). Cited as `M:<path>`, e.g. `M:plugins/initialization/init_cell_objects.cpp`.
  WebFetch summarises files, so the line numbers quoted from it are approximate ("~").
- **MorpheusML reference dump:**
  `raw.githubusercontent.com/sisyga/morpheus-skills/master/morpheus/references/morpheusml_doc.txt`
  (cited as **[ref]**). WebFetch got it **truncated**: the sections for InitCellObjects,
  InitCircle, InitRectangle, InitDistribute, InitHexLattice, InitPoissonDisc, InitVoronoi and
  AddCell were one-line index entries only. Their semantics below come from the source code,
  which is the better authority anyway.
- **Model pages:** `https://morpheus.gitlab.io/model/mXXXX/`.
- **Potts files:** paths relative to `PottsMonorepo/`.

---

## 0. Summary of recommendations

1. **Separate three things Morpheus already separates:**
   - a **shape**: what one object looks like (Morpheus `Box`/`Sphere`/`Ellipsoid`/`Cylinder`);
   - a **point pattern**: where the objects go (Morpheus `Arrangement`, InitRectangle,
     InitCircle, InitPoissonDisc, InitDistribute);
   - a **fill**: how space between seeds is assigned (Morpheus InitVoronoi; TST Eden).

   All three are plain Julia values. A layer combines them, and `overlay` composes layers.
   `Tiling`, `Scattered`, `Frame` and `InsertUntil` stay as the shipped conveniences.
2. **One layer protocol: `paint!(op::LayoutState, l, lat)`**, as D-075 already ratified, with
   a small public mutation API (`new_cell!`, `assign!`, `set_column!`, `add_link!`, `record!`).
   A custom layer never touches `LatticeSpec` fields. A custom shape needs two methods
   (`inside`, `bounds`) and then works in every shape-taking layer.
3. **Explicit write rules instead of XML order.** Two keywords, `into` and `resolve`, and the
   overlay rules settle who wins a site, both between layers and within one layer.
4. **Uniform fit-failure rule and report.** Every layer states what it was asked for.
   `shortfall = :error` is the default (Morpheus ≥ 2.0 also makes a population shortfall fatal). **[Corrected 2026-10-01, initial-state-review.md §1b F1: only when `size` is set (default 1), and against the CellType's cumulative cell count (`celltype.cpp:270-283, 420-421`); Morpheus' effective default is lenient, so it is not a precedent. `:error` stands on its own merits. The `shortfall` keyword is deferred to P6.3c.]** `layout(l, sys; report = true)` returns one row per layer (D-075 §3.2 item 4) and
   replaces `layout_tally`.
5. **Per-cell values stay model content.** They are expression defaults and
   `@initialization_equations` (D-075, R17). The symbols visible at init are `id`, `kind`,
   `volume`, `centroid`, `cluster`, `position`, parameters, other variables in dependency
   order, layout-emitted columns the model declares, and `rand()` from `Potts.init.<var>`
   streams. Layouts emit only *structure* (`cluster`, ranks, links), plus optional constant
   per-layer values. This is the Morpheus `Property value="expr"` model, and it covers every
   InitProperty use found.
6. **Keep painting simple but sub-quadratic:**
   - per-object bounding-box scans, not sites × objects (Morpheus scans every node against
     every object);
   - Poisson disc by Bridson's method on a background grid;
   - Voronoi by bucketed generators;
   - overlap tests in `Scattered` against an occupancy mask, not against every placed box.

---

## 1. Morpheus initializer catalogue

The Morpheus initializer plugins live in `M:morpheus/plugins/initialization/`. The directory
listing (GitLab API) is: `csv_reader`, `init_cell_lattice`, `init_cell_objects`,
`init_circle`, `init_distrib`, `init_hex_lattice`, `init_poisson_disc`, `init_rectangle`,
`init_voronoi`, `initpdedata.xsd`, `initpdeexpression.xsd`, `initspherecell.cpp`,
`remove_cells`, `tiff_reader`. Each is a `Population_Initializer` with
`vector<CELL_ID> run(CellType*)` (`M:…/init_cell_objects.h`, class declaration).

**Usage counts.**
- Prior count over the 50 published models (`research/morpheus-gaps.md:480`):
  InitCellObjects 17, InitProperty 5, TIFFReader 2, InitVoronoi 1, CSVReader 0.
- InitCircle and InitRectangle were **not counted** there. In my sample of 11 model pages,
  InitCircle appears in 4 (m1703, m2984, m9496, m2051) and InitRectangle in 3 (m0006, m7121,
  m7671). They are at least as common as InitCellObjects; recounting them is open (§7, Q10).

| Initializer | Attributes (XSD/source) | Exact semantics (from code) | Uses |
|---|---|---|---|
| **InitCellObjects** | `mode` (required; `order` or `distance`, default set to `distance` in code, ~l.345–350). One or more `Arrangement`s with `repetitions` (vec, default `1,1,1`), `displacements` (vec, default `1,1,1`) and `random_displacement` (double, optional). Each Arrangement holds one shape: `Point(center)`, `Box(origin, size, rotation=0)`, `Sphere(center, radius)`, `Ellipsoid(center, axes, rotation)`, `Cylinder(origin, length, radius)` or `Hexagon(center, radius, height, rotation)` (`M:…/init_cell_objects.xsd`). Every attribute is a math expression (`size.x`, parameters) | **Objects.** `arrangeObjectCombinatorial` loops z, y, x over `repetitions`, clones the template into a *new cell* (`celltype->createCell()`) and displaces it by `r*displacement` plus `(getRandom01()-0.5)*random_displacement` per axis. **Painting.** `setNodes` (~l.422–494) visits lattice positions, keeps only **empty** nodes (`CPM::getNode(pos) == getEmptyState()`), and collects every object whose `inside(orth_pos)` is true. `order`: the first candidate (lowest cell id, i.e. creation order) wins. `distance`: the candidate with maximal `affinity` wins, where affinity is a ~~normalised~~ depth: Sphere `1 − d/r`; Box/Ellipsoid/Hexagon `−distance` (signed distance inside) **[Corrected 2026-10-01, initial-state-review.md §1b F4: Sphere and Cylinder are normalised; Box and Hexagon use the raw depth in lattice units; Ellipsoid uses `1 − p` (`init_cell_objects.cpp:95-98, 150-152, 245-258, 338-345, 418-424`); mixed shapes compare unlike units]**; Cylinder `1 − d/r` within the length; Point `inside`. **Inside tests:** Sphere `|orth_distance(pos,c)|² ≤ r²`; Point `distance ≤ 0.5`; Box a rotated box test; Cylinder `|dp × L|/|L| ≤ r`. **Periodicity:** `orth_distance` handles periodic wrap. **Empty objects:** a cell left with 0 nodes prints "WARNING in InitCellObject: Cell n has zero size…Removing cell" and is removed | 17 |
| **InitRectangle** | `number-of-cells` (expr), `mode` = `regular`/`random`/`grid`, `Dimensions/origin`, `Dimensions/size`, `random-offset` (default 0) | **Single-node cells.** `regular`: serpentine rows, `i_lines = int(sqrt(size.y·n/size.x)+0.5)`, plus per-axis jitter of `random-offset`. `random`: `CPM::findEmptyNode(origin, origin+size)`. A node that is occupied or not writable returns `NO_CELL`, with **no retry** in regular/grid mode. At the end it prints "failed to create X cells". Origin and size are clamped to the lattice | ≥ 3 / 11 sampled |
| **InitCircle** | `number-of-cells`, `mode` = `regular`/`random`, `Dimensions/center`, `Dimensions/radius` | **Single-node cells.** `random`: uniform draws (`getRandomUint`) from a stored list of the nodes inside the circle. `regular`: concentric rings with alternate rings staggered by half a step (`alpha = 2π(j + 0.5·(i%2))/n_i`). An occupied node fails; the loop gives up after `max_fails = 4·n` failures and stops **short of n without error** | ≥ 4 / 11 sampled |
| **InitDistribute** | `number-of-cells`, `probability` (an expression of space), `mode` = `regular`/`random` | **Single-node cells.** Builds a CDF of `probability` over all nodes in one pass. `random`: inverse-transform sampling with `getRandom01()`. `regular`: evenly spaced quantiles. Only empty, writable nodes accept a cell. It warns "failed to create X cells" | [count unknown] |
| **InitPoissonDisc** | `number-of-cells` (scaled by the lattice aspect ratio) | "only implemented for 2D square lattices". It generates points with `PoissonGenerator::GeneratePoissonPoints` (own PRNG, `PoissonGenerator::DefaultPRNG`), scales them to the lattice and creates **single-node cells**. Occupied or out-of-bounds points are dropped **silently** (`if (new_cell != NO_CELL)`), so fewer cells come out with no warning. The algorithm and its minimum distance are not exposed. ~~[unverified: likely Bridson-style]~~ **[Confirmed 2026-10-01, initial-state-review.md §1c: Bridson (`init_poisson_disc.h:27,32`). Its `DefaultPRNG()` is seeded from `std::random_device` (`3rdparty/poisson-disc-generator/PoissonGenerator.h:52-57`), so it ignores the simulation seed and is not reproducible.]** | [count unknown] |
| **InitVoronoi** | none (`<InitVoronoi/>`) | Header doc: "Computes the Voronoi tesselation of the empty areas and sets cell IDs according to this tesselation. Assumes cell positions have already been initialized. Only uses non-occupied lattice nodes. Respects Domain." **Only seeds of this population's cell type** start at distance 0, and other types' nodes block the growth. It is an iterative 8-direction distance-transform sweep with a 5th-order neighbourhood, ~~Euclidean in orthogonal coordinates~~ **[Corrected 2026-10-01, initial-state-review.md §1c: a chamfer transform (sums of order-5 step lengths in orth coordinates), approximately Euclidean]**, run until convergence. **No maximum radius:** every reachable empty node is filled. Ties go to scan order. ~~Periodic wrap is not evident [unverified]~~ **[Corrected 2026-10-01, initial-state-review.md §1c: it wraps periodically; neighbour reads go through `Lattice_Data_Layer::get` → `Lattice::resolve` (`init_voronoi.cpp:169-170`, `lattice_data_layer.cpp:302-312`)]**; a source TODO doubts the Domain handling | 1 |
| **InitHexLattice** | `mode` = `left`/`right`, `randomness` (default 0) | Stamps cells shaped like the order-11 hex neighbourhood on a regular pattern. It *requires* a hex lattice of size (91, 91, 1) or a multiple ("This plugin requires a hexagonal lattice of size (91,91,1) or a multiple thereof") | [count unknown] |
| **InitCellLattice** | none | One single-node cell per lattice node of the global scope (a CA-style start) | [count unknown] |
| **Population `size`** | `size` (default 1 in code: `cp.pop_size=1`), `type` | `CellType::init` runs the population's initializers **in XML order**. If the initializers made fewer cells than `size` and the CPM is enabled, it **throws** **[Corrected 2026-10-01, initial-state-review.md §1b F1: the comparison is the CellType's cumulative `cell_ids.size()` against `pop_size` (default 1), so it bites only when `size` is set; the message's operands are swapped]**: "Spatial initializers created fewer cells than requested … This is considered a fatal error for spatial simulations since Morpheus v2.0" (`M:core/celltype.cpp`). Without a CPM it creates bare cells instead | all |
| **`Cell` children of Population** | `Nodes` lists | Explicit per-cell node lists (`cell->loadNodesFromXML`) (`M:core/celltype.cpp`) | [count unknown] |
| **AddCell** (runtime, not init) | `Count` (expr; fractional counts realised stochastically), `Distribution` (an expression, normalised), `overwrite` (default false), `Triggers` | One `createCell()` then `CPM::setNode` at **one** node. Position: `getRandomPos()` if the distribution is constant, otherwise by CDF. Up to `10·count` retries. A multi-node cell always blocks; with `overwrite` only single-node cells are replaced (`M:plugins/miscellaneous/add_cell.cpp`). Triggers fire on the new cell. InitProperty is **not** applied ([ref] InitProperty: "InitProperty is NOT called for cells created during simulation, e.g. using the AddCell plugin") | 4 (`morpheus-gaps.md` item 13) |
| **TIFFReader / CSVReader** | file-based | Out of scope (import) | 2 / 0 |

**Representative real usages.**

1. **One cell, one shape (a zygote).** `m9999` (blastocyst):
   ```xml
   <Population type="Zygote" size="1">
     <InitCellObjects mode="distance"><Arrangement displacements="1, 1, 1" repetitions="1, 1, 1">
       <Sphere radius="22.56" center="size.x/2, size.y/2, 0"/></Arrangement></InitCellObjects></Population>
   ```
2. **Repeated boxes as a grid, plus walls.** `m6696` (somitogenesis) builds three populations
   from `Box` templates:
   - `Wall`: `repetitions="2, size.y/wall, 0" displacements="cD*11, wall, 0"`;
   - `PSM`: `repetitions="10, 3, 0" displacements="cD, cD, 0"`;
   - `Source`: one row.

   `m0006` uses two InitCellObjects, each a single 150-wide `Box`, as the two cells of a
   "Lateral confinement" population. Their `mode`s differ, which makes no difference with
   one object each.
3. **Single nodes that grow to their target volume.**
   - `m0006`: `<InitRectangle random-offset="5" number-of-cells="400" mode="regular">`,
     with `target_volume = 326`.
   - `m2984`: `<InitCircle number-of-cells="500" mode="random">`.
   - `m9496` (APAP liver): two random InitCircles of 600 hepatocytes and 150 Kupffer cells in
     the same disc, followed by seven single-`Sphere` InitCellObjects for the veins.

   Seeding points and letting the Hamiltonian inflate them is the dominant Morpheus idiom.
4. **InitProperty for a population.** `m7671` (hiPSC):
   `<InitProperty symbol-ref="dc"><Expression>rand_uni(0,dt)</Expression></InitProperty>` in
   each of two populations. The element sits before InitRectangle in one population and after
   it in the other, which is harmless (see §2).
5. **Expression defaults for diversity.**
   - `m2984`: `maxCellSize = rand_norm(220,50)`, `initialId = cell.id`,
     `cellCycleTime = (-(ln(rand_uni(0,1)))*85*100)+2215`.
   - `m1703`: `g = max(g_min, rand_norm(mu_g,var_g))`.
   - `m9999`: `gamma = rand_uni(-0.1,0.1)`.
   - `m6696`: `mFgf = if((size.y-4*cD-cell.center.y>0)*(…), 4.4, …)`, a position-dependent
     cell value read from `cell.center`.

---

## 2. Morpheus property initialization

- **Property values are expressions.** Doxygen: "The initial value is given by the value
  attribute as a MathExpressions and may depend on the cell.center and contain stochasticity
  to create population diversity" (`M:core/property.h`, ~l.74–80).
- **Evaluation is per cell, lazy, and cycle-checked.** `Property::init(const SymbolFocus& f)`:
  ```cpp
  if (! initialized) {
      if (initializing) throw MorpheusException("Detected circular dependencies in evaluation of symbol '" …);
      else initializing = true;
      if (initializer) this->value = initializer->get(f);
      else             this->value = parent->getInitValue(f);
      initializing = false; initialized = true; }
  ```
  `PropertySymbol::safe_get` calls `p->init(f)` when the cell's instance is not yet
  initialized. So a property expression may read another property: it is initialized on
  demand (a lazy topological order), and a cycle is a **run-time** exception.
- **InitProperty overrides the default for one population.** `setInitializer` swaps the
  expression (`M:core/property.h`, ~l.209–211). [ref] InitProperty: "Expressions are
  evaluated separately for each cell, such that properties can become stochastic or
  dependent on cell-position." InitVectorProperty does the same for `PropertyVector`, with
  `orthogonal`, `radial` and other notations ([ref]).
- **Order inside `CellType::init`** (`M:core/celltype.cpp`):
  1. run the population initializers in XML order and collect the cell ids;
  2. check `size` (fatal in CPM models);
  3. bind the InitProperty initializers for every cell of the population;
  4. call `Cell::init()` for every cell.

  Properties are therefore evaluated **after** all of that population's nodes are placed, so
  `cell.center`, `cell.volume` and space symbols are valid. Where an InitProperty element sits
  relative to the initializers does not matter.
- **Order across populations.** No explicit cross-celltype sequencing appears in
  `celltype.cpp`; each `CellType::init` handles its own populations. Initializers write only
  empty nodes, so **the celltype initialized first wins contested nodes**. That order is
  ~~presumably the declaration order [unverified]~~ **[Confirmed 2026-10-01, initial-state-review.md §1c: the CellType definition order in `<CellTypes>`, not the order of Population elements (`cpm.cpp:213-234, 389-391`)]**.
- **Cells born later.**
  - AddCell cells do not get InitProperty, but the Property default still applies lazily on
    first read (`safe_get` → `parent->getInitValue`).
    - Daughter values at division are handled by CellDivision: copied from the mother unless
    Triggers reset them; both daughters are new ids **[Confirmed 2026-10-01, initial-state-review.md §1c: `cell_division.h:29-30`]**.
- **Symbols visible** in initial expressions **[Mostly confirmed 2026-10-01, initial-state-review.md §1c: `cell.center/volume/id/type/surface/length/orientation` are registered in core; `space` and `time` are user-chosen names (`SpaceSymbol`/`TimeSymbol` `symbol`, `simulation.cpp:617,647`), not fixed symbols; the `rand_*` functions were not checked]**: `cell.center`,
  `cell.volume`, `cell.id`, `cell.type`, `space` (`SpaceSymbol`), `size`/`lattice` vectors,
  `time`, `rand_uni`/`rand_norm`/`rand_gamma`/`rand_bool`, globals and other properties.
  Seen in real models: `cell.center.x`, `cell.center.y`, `cell.id`, `size.x`, `size.y`,
  `rand_uni`, `rand_norm`, `ln`, `time` (§1).
- **Fields** take an initial expression of `space` (the `initpdeexpression.xsd` schema), the
  site-scope analogue.

---

## 3. What Morpheus gets right and wrong

**Right (to copy):**
- **Shape × arrangement × mode** is a clean factorisation. A grid of boxes, one sphere, two
  walls and a staggered sheet are all one element. 17/50 published models use it.
- **Every attribute is an expression of `size`/parameters.** A model reads as "a sphere at the
  centre", not as hard-coded numbers.
- **Seeds plus fill (InitVoronoi), and seeds plus growth (single nodes inflated by the volume
  term)** are cheap, generic and realistic starts.
- **Properties are evaluated per cell, after placement,** with `cell.center` and randomness.
  This one mechanism removes most "set the state in a script" code.
- **The population `size` check is fatal (since 2.0).** A silent shortfall was judged to be a
  bug source. **[Corrected 2026-10-01, initial-state-review.md §1b F1: only when `size` is set (default 1), against the CellType's cumulative count.]**
- **Shape inside tests use Cartesian ("orth") coordinates,** so spheres are round on hex
  lattices.

**Wrong or weak (to avoid):**
- **Who wins is implicit.** It depends on XML order, on celltype initialization order and on
  "only empty nodes are written". You cannot *overwrite* (cut a hole, insert into a cell) at
  init except through AddCell's single-node `overwrite`. CC3D-style insertion (Akeeb) is
  inexpressible.
- **Miss reporting is inconsistent:**
  - InitRectangle and InitDistribute print "failed to create X cells";
  - InitCircle silently gives up after `4n` failures;
  - InitPoissonDisc drops points silently;
  - InitCellObjects removes empty objects with a warning;
  - the population `size` check then may or may not catch the shortfall (its default is 1).

  There is no machine-readable report.
- **`mode="order"` is documented as "object with lowest celltype.id"**, but the code is
  "first candidate in creation order". The documentation is misleading.
- **The `setNodes` cost is O(nodes × objects)** (every position tests every object, ~l.422ff).
  That is fine at Morpheus' typical sizes and poor for 3D tissues with 10⁴ objects.
- **InitVoronoi has no region or radius,** so it floods every reachable empty node. You must
  fence it with other populations or a Domain.
- **One-off plugins:** InitHexLattice hard-codes a 91×91 lattice multiple, and
  InitPoissonDisc is 2D square only. Both are the opposite of "family-general primitives".
- **The randomness is not addressable.** `getRandom01()` is the global stream, so adding an
  initializer changes the draws of later ones. Potts' per-layer seeds (D-057) are better.
- **Lazy property init detects cycles only at run time** (an exception). Potts can reject them
  at compile time (D-042 order).
- **InitProperty is not applied to AddCell cells,** while Property defaults are. Two rules for
  "value of a new cell".

**Contrast (brief)** **[Checked 2026-10-01, initial-state-review.md §1c: CC3D and Artistoo confirmed against source; Chaste as cited]**:
- **CC3D.** `UniformInitializer` is a box region with `Width` cubes and `Gap`, the `Types` list
  assigned to cells at random **[Confirmed 2026-10-01, initial-state-review.md §1c: `UniformFieldInitializer.cpp:143-150`. Also: CC3D places `ceil(boxDim/size)` boxes per axis and clips each box at the lattice edge, not at the region, so boxes overhang the region's upper side (`:88-93, 121-126`). Potts' `:clip` clips at region ∩ lattice and reproduces CC3D only when the region's upper bound is rounded up to whole boxes or equals the lattice edge]**. Spec 10 §2.3 cites it for the Akeeb slab
  (X:121–131, Width 3, Gap 0, last column clipped to 2×3). `BlobInitializer` is the same
  inside a sphere (`Center`, `Radius`). PIFF is the file seam.
- **Artistoo.** `GridManipulator` has `seedCell`, `seedCellAt`, `seedCellsInCircle(kind, n,
  center, radius)` (single pixels), `makePlane` and `assignCellPixels` **[Confirmed 2026-10-01, initial-state-review.md §1c: `GridManipulator.js:88,126,165,259,413`; it also has `makeBox`, `makeCircle` and `makeLine` (`:215-413`)]**.
- **Chaste.** `PottsMeshGenerator` builds a centred block of rectangular cells (spec 09 cites
  `PottsMeshGenerator.cpp:67–76`).

~~None of the three has Morpheus' shape/arrangement factorisation or property expressions.~~ **[Corrected 2026-10-01, initial-state-review.md §1c: Artistoo has pixel-set shape builders (`makeBox`, `makeCircle`, `makeLine`, `makePlane`). None of the three has Morpheus' arrangements or property expressions.]**

---

## 4. Gap table

Columns:
- **Morpheus capability**;
- **Potts today**: `src/layouts.jl` and PottsModels;
- **Needed by**: paper model, with its spec section;
- **Proposed Potts form**: §5.

| Morpheus capability | Potts today | Needed by (spec §) | Proposed Potts form |
|---|---|---|---|
| Box objects on a grid (Arrangement + Box) | `Tiling(size; spacing, region, kinds)`, whole boxes only (`layouts.jl:66–111`) | 08 SC1 620 5×5 cells (08 §2.1 "Initial conditions"); 09 OS 4×4 block (09 §3.2); 10 slab with a **clipped** column (10 §2.3) → today the custom `_AkeebSlab` (`akeeb.jl:107–123`); 12 square block (12 p.253) | `Tiling(...; partial = :clip)`; `Objects(shape, GridPoints(...))` for non-box templates |
| Staggered grid (InitCircle regular rings; hex) | none | 04 brick wall in common bond (04 §2.6 step 1); 09 PRE staggered bricks of varied widths (09 §8.2/§9 D3) | `Tiling(size; stagger = (8, 0))`, which replaces the planned `BrickWall` (P6.4d); `widths = Uniform(a:b)` for varied widths |
| Single Sphere / Box object at a point | `Tiling` with a 3×3×3 region as one cell (sketch 06 l.171) | 06 one cell at the centre (06 §2 "Initial condition"); 14 ball radius R tangent to the substrate + 6³ nucleus (14 §2.7, §2.9.1); 07 bud sphere (07 §2.7, sketch l.118); 05 bud (sketch l.141); 11 four cells, radius 24.3 µm (11 §2A) | `Objects(Sphere(...), [c])`; `Group` for cell + nucleus |
| Box as a wall, plane or region (m0006, m6696) | `Frame(kind; width)` (domain-aware, D-062) | 01 width-2 frozen frame (01 §5.4 of api-synthesis); 14 substrate + lid planes (14 §2.7) | `Frame` (kept); `Fill(kind; region = shape)` for planes and slabs (replaces the planned `Plane`, P6.5c) |
| Random single-node seeds in a region (InitCircle/InitRectangle random) | none (`Scattered` places boxes) | 01b de novo: 360 point seeds **with replacement** + 10 Eden rounds (01 §7.6); 01b sprout: 1 seed (01 §7.6) | `Objects(Site(), RandomPoints(n; region, replace = true))` then `Eden` |
| Random non-overlapping boxes | `Scattered(n, size; region, kinds, seed, gap)` (`layouts.jl:113–194`) | 01a 282 cells in 333² (01 §2.9); 07 ~30 tissue cells (sketch l.117) | `Scattered(n, shape; …)`, any shape, mask-based overlap |
| Voronoi fill of empty space from seeds (InitVoronoi) | `VoronoiBall` in PottsModels (Lloyd, ball only) (`graner_glazier.jl:95ff`), core move planned (P6.1a5) | 09 GG ≈1000-cell aggregate (09 §9.0, D-063); 11 four cells of 131 px (sketch 11 l.159) | `Voronoi(points; region, lloyd)`; `VoronoiBall` becomes sugar or is dropped (Q3) |
| Poisson disc points (InitPoissonDisc) | none | none of the 12 directly; useful for an even `Voronoi` start (lower area SD than D-063's 7.6) | `PoissonDisc(r; region)` points |
| Density-weighted placement (InitDistribute; AddCell `Distribution`) | none | none at init; AddCell at run time is R8 `@create` (05 recruitment, sketch 05 §233) | `WeightedPoints(n, density; region)` (points), reused by `@create at = Weighted(...)` |
| Ellipsoid / rotated box objects | none | 12 "weakly elongated, randomly oriented cells" in a square block (12 §"Initial condition") | `Objects(Ellipsoid(axes; rotation = RandomRotation()), GridPoints(...))` |
| Cylinder / rod objects | none | 05/07 collagen fibre bundles at discrete angles to a coverage fraction (05 §2.6; 07 §2.7); 13 straight rods of s segments (13 §2.7) | `InsertUntil(Rod(...); occupied = ρ, collective = true)` (replaces the planned `Fibres`, P6.8); `Chain(s, blob; …)` composite (P6.6) |
| (no Morpheus analogue) insertion into existing cells | `InsertUntil` (`layouts.jl:270–385`) | 10 leaders (10 §2.3, §5.3.6, D-068) | kept; plus `splits = :allow` to replace the NullLogger hack (`akeeb.jl:151–153`, D-082) |
| (no analogue) TST Eden growth, cell splitting | none | 01 sprout: Eden 50 rounds, 7 splits → 128 cells; 01b de novo (01 §7.6) | `Eden(layer; rounds)`, `Splits(layer, k)` (P6.3c) |
| Population per celltype; random type mix | `kinds` cycled; VoronoiBall cycles kinds over random generators | 09 random type assignment, reused pattern + new seed (09 §8.2 item 5, §9.0); 08 alternating types (08 §2.1) | `kinds = Mix(:dark => 1//2, :light => 1//2)` (exact or Bernoulli); `Relabel(layer, Mix(...); seed)` |
| Multi-compartment cells (cluster) | `cluster =>` given by hand in the op (sketch 14 l.116) | 14 cytoplasm + nucleus (14 §2.7); 13 rods (13 §2.1) | `Group(layers...)` emits `cluster`; `Chain` emits cluster, rank and links |
| Property `value="expr"` (cell.center, rand, cell.id) | numeric defaults only; host code in `akeeb_state` (`akeeb.jl:155–158`) | 10 clock/rate/cue (10 §2.3, §2.4); 04 `A = volume` after coarsening (04 §2.6, A-8); 05/07 `V_target = initial volume` (sketch 05 l.145, 07 F*); 14 `V_target` by compartment (sketch 14 l.116); 06 top-tier proteins on (06 §2) | D-075 expression defaults / `@initialization_equations` at `at_init` (R17, P6.4a); symbols in §5.7 |
| InitProperty (per-population override) | n/a | none of the 12 needs a per-layer override beyond `kind` (§5.7) | kind-conditional defaults; optional layer `values = (:x => c,)` constants |
| Field initial expression of space | numeric default; `cue` built on the host (`akeeb.jl:158`) | 10 cue `y − 1`; 08 SC2 O₂ levels by distance from the border (08 §2.1); 08 SC1-B hypoxic regions | `cue(site) = position[2] - 1` (D-075 §2.4) |
| Steady initial field | none | 05, 07 (`@initialization_equations 0 ~ …`) | R14 (not layout; P6.8) |
| Population `size` check / failure messages | `Scattered` throws on jam (`layouts.jl:185`); `InsertUntil` throws when sites run out; `layout_tally` covers InsertUntil only | 10 counted inventory (10 V-A1(a)); 01b seeds with replacement merge (01 §7.6), so the count is *expected* to fall short | per-layer `requested`/`painted`/`dropped`/`misses` report; `shortfall = :error/:warn/:allow` |

---

## 5. Proposed design

### 5.1 Principles

- **Values, not macros.** A layout is an immutable value: ~~`remake(l; seed)` works (SciML
  `remake` on a plain struct through ConstructionBase) [unverified: whether Potts already
  defines `remake` on layouts; api-synthesis §3.5 uses `remake(l; seed = …)`]~~ **[Corrected 2026-10-01, initial-state-review.md §1c: `SciMLBase.remake(Scattered(…); seed = 2)` throws a `MethodError` today. `ConstructionBase.setproperties` skips constructor validation and fails for `InsertUntil`, whose fields do not match its keywords. An explicit `SciMLBase.remake(::AbstractLayout; kw...)` that re-calls the keyword constructor is a P6.1a6 deliverable.]** Layouts are
  composed with `overlay`, `Group` and `Relabel`. No DSL section for layouts: initial
  *geometry* is problem data, like `u0` (D-057, D-073 "not DSL").
- **Family-general.** No model-named layers in core (memory: "models open mechanism
  families").
  - `BrickWall` is `Tiling` with `stagger`.
  - `Fibres` is `InsertUntil` of a `Rod` with `occupied`.
  - `Plane` is `Fill` with a slab region.
  - `Spheres` is `Objects` of a `Sphere`.
  - `VoronoiBall` is `Voronoi` over a `Sphere` region.

  `Tiling`, `Scattered`, `Frame` and `InsertUntil` stay, because they are general and shipped.
- **Explicit write rules,** a uniform report, seed-owned randomness and host-only painting.

### 5.2 Shapes

A shape answers "is this site inside?" in **Cartesian site coordinates**: the lattice index,
embedded with `embed(core_lattice(lat), x)`, so shapes are round on hex lattices as in
`VoronoiBall` and Morpheus' `orth_pos`.

Each shape is either **anchored** (absolute position) or a **template** (relative to an
anchor point). A template is translated to each point of a pattern. A shape given with
coordinates is anchored, and `Objects` takes templates whose reference point is the origin.

**Shape names.** D-056 rule: check them against Makie's exports. Verified on the installed
Makie 0.24.15 (`Makie/frKXt/src/Makie.jl:323–331`, `makielayout/MakieLayout.jl:47`):
- Makie exports `Box` (its layout block), `Sphere`, `Circle`, `Point`, `Vec` and `Rect*`.
- `Sphere`, `Circle`, `Point` and `Rect` are **GeometryBasics bindings** that Makie re-exports
  (GeometryBasics 0.5.13 `src/GeometryBasics.jl:29, 57–59`).

So:

| Shape | Source | Inside rule | Notes |
|---|---|---|---|
| `Rect(origin, widths)` | GeometryBasics (re-export the **same binding**: no ambiguity with Makie) | **half-open** `origin ≤ x < origin + widths` via Potts' own `inside`; `Base.in` is closed (`rectangles.jl:558`) and would give w+1 sites | axis-aligned; `Rect` with `rotation` → `Rotated(r, θ)` |
| `Sphere(center, r)` / `Circle` / `HyperSphere{N}` | GeometryBasics | `‖x − c‖ ≤ r` (as Morpheus `abs_sqr ≤ r²`, and GeometryBasics `spheres.jl:35`) | 2D disc or 3D ball; `Ball` is already a Potts relation (sketch 05 §233) |
| `Cylinder(a, b, r)` | GeometryBasics (3D only, `cylinders.jl:7`) | distance to segment `ab` ≤ r, projection in [0, 1] | Morpheus `Cylinder` |
| `Ellipsoid(axes; center, rotation)` | **Potts** (not exported by Makie or GeometryBasics: verified by grep) | `‖R⁻¹(x − c) ./ axes‖ ≤ 1` | Morpheus `Ellipsoid` |
| `Rod(length, width; angle)` | **Potts** | 2D rotated rectangle, i.e. a capsule-free bar | fibres, rods; `Cylinder` in 3D |
| `Site()` | **Potts** | the single site nearest the anchor | Morpheus `Point` and single-node initializers |
| `Mask(bits)` | **Potts** | `bits[x]` | the import seam for images (§5.9) |
| `Where(f)` | **Potts** | `f(x)::Bool` on Cartesian coordinates | any predicate region |
| `a ∩ b`, `a ∪ b`, `setdiff(a, b)` | Base generics on `AbstractShape` | combine | regions such as "the slab minus a margin" |
| `Rotated(shape, θ)`, `Rotated(shape, RandomRotation())` | **Potts** | rotation about the anchor; random rotations drawn from the layer's stream | 12 random orientations, 13 rods |

**Dependency.** GeometryBasics is already in the workspace Manifest through Makie
(`Manifest.toml:1075`), with dependencies StaticArrays and EarCut_jll. Potts should
**import and re-export only** `Rect`, `Sphere`, `Circle`, `HyperSphere`, `Cylinder` and
`Point`, never `using GeometryBasics`. GeometryBasics exports `volume`, `direction`, `area`,
`origin` and `radius` (`GeometryBasics.jl:56, 61`), which clash with Potts DSL symbols
(`volume`, the planned copy-scope `direction`).

**Alternative (Q1):** Potts-owned names in a `Shapes` submodule (`Shapes.Box`). They are
unambiguous but non-idiomatic next to Makie.

`region =` keywords (today a tuple of unit ranges, `layouts.jl:31–39`) accept any shape, and
a tuple of ranges keeps meaning an index box.

### 5.3 Point patterns

A point pattern yields the anchor points (Cartesian `SVector`s) of a layer's objects. Random
patterns own a `seed`.

| Pattern | Morpheus analogue | Semantics |
|---|---|---|
| `GridPoints(spacing; origin, count | region, stagger = 0, jitter = 0, seed)` | `Arrangement repetitions/displacements/random_displacement`; InitRectangle `regular`; InitCircle `regular` stagger | Column-major order (x fastest), as `Tiling` today. `stagger` offsets every other row (brick wall, hex packing). `jitter` adds a uniform displacement in ±jitter/2 (Morpheus `(rand−0.5)·d`) |
| `RandomPoints(n; region, replace = false, seed)` | InitCircle / InitRectangle `random` | Uniform over the region's in-domain sites. `replace = true` allows coincident points (TST `GrowInCells`, which merges seeds: 01 §7.6) |
| `PoissonDisc(r; region, n = nothing, seed)` | InitPoissonDisc | Bridson sampling at minimum distance `r` (any dimension, hex via the embedding). With `n`, the first `n` accepted points |
| `RingPoints(n; center, radius, rings = 1)` | InitCircle `regular` | Concentric rings with staggered phase |
| `WeightedPoints(n, density; region, seed)` | InitDistribute; AddCell `Distribution` | Inverse-CDF sampling of `density(x)` over the sites |
| `[c₁, c₂, …]` (a vector) | explicit `center` | Given points |
| `Center()` | `size.x/2, …` | The lattice centre `(dims .+ 1) ./ 2` (as `VoronoiBall`, `graner_glazier.jl`) |

**Lattice-relative coordinates.** Morpheus' `size.x/2` style comes from a do-block,
`layout(sys) do dims … end`, which calls the closure with `dims` and paints the result. This
is plain Julia: no `Frac`/`Rel` coordinate types. `Center()` is the only sentinel (Q8).

### 5.4 Layers

All layers are `<: AbstractLayout`. Every layer takes these common keywords:
- `kinds` (cycled vector, or `Mix`);
- `into` (§5.5);
- `shortfall` (§5.6);
- `splits = :warn | :allow`;
- `seed` (random layers).

| Layer | Purpose | Notes |
|---|---|---|
| `Tiling(size; spacing, region, kinds, partial = :skip | :clip, stagger, widths)` | **kept**; CC3D UniformInitializer, Chaste PottsMeshGenerator | `partial = :clip` keeps edge boxes cut by the region or lattice, which is the Akeeb slab exactly (§5.8). `stagger = (s, 0)` is the brick wall (04). `widths = 6:10` draws widths per box from the seed (09 PRE). On a periodic axis `partial = :wrap` wraps the last box **(Q4)** |
| `Scattered(n, shape; region, kinds, seed, gap = 1, orientation)` | **kept**, generalised from boxes to any template | Overlap test against an occupancy mask dilated by `gap` (Chebyshev, as D-057). `orientation = RandomRotation()` rotates each copy. The jam rule and the area bound stay |
| `Objects(shape, points; kinds, resolve = :first | :nearest | :last)` | **new**; Morpheus InitCellObjects | One cell per point, its shape translated there. A site claimed by several objects *of this layer* goes to the first (creation order; Morpheus `order`), the deepest (max normalised affinity; Morpheus `distance`) or the last |
| `Fill(kind; region)` | **new**; one cell owning a region | Planes, slabs, stroma background, ECM (sketch 07 `Fill(:fluid)`). Replaces the planned `Plane(kind; axis, at)`: `Fill(:lid; region = Slab(3, Lz))`, where `Slab(axis, range)` is an index-box shape |
| `Frame(kind; width)` | **kept** (D-057, D-062) | — |
| `Voronoi(seeds; region, lloyd = 0, into = Medium())` | **new**; Morpheus InitVoronoi with the missing `region` | `seeds` is a point pattern (new cells) or a layer (its cells grow). Each site of `region` that `into` allows goes to the nearest generator (Euclidean, embedded, minimum image on periodic axes). `lloyd` iterations move generators to region centroids (D-063). Stray pieces are reattached as in `VoronoiBall` (`graner_glazier.jl:102–108`) |
| `Eden(seeds; rounds, into = Medium())` | **new**; TST `GrowInCells` (01 §7.6), P6.3c | Synchronous rounds: a free site copies a uniformly drawn Moore(1)… neighbour that belongs to a growing cell. The neighbourhood is the lattice's, or `relation =` |
| `Splits(layer, k; along = ShortAxis())` | **new**; TST `DivideCells`, P6.3c | Each cell is split k times by the line through its centroid perpendicular to its long axis (01 §7.6). ~~Reuses the lifecycle division routine (api-synthesis §3.3) [unverified: that the routine can run on a host σ]~~ **[Corrected 2026-10-01, initial-state-review.md §1c: `run_lifecycle!` (`lib/CorePotts/src/lifecycle.jl:272ff`) needs a `CPMState` with trackers, `ctx`, `key` and backend launches; write a small host routine (centroid and inertia from σ, O(Σ volume)) that shares only the split geometry]** |
| `InsertUntil(kind_or_shape; into, number | fraction | occupied, misses, seed, region, orientation)` | **kept**, generalised | A shape template enables fibres and rods. `occupied = ρ` stops once ρ of the region is owned by this layer (05/07 coverage). `collective = true` makes all inserted objects one cell (05 p.14) |
| `Group(layers...)` | **new** (api-synthesis §3.3) | Every cell of the group shares one `cluster` id (14 cell + nucleus) |
| `Relabel(layer_or_state, kinds; seed)` | **new** (sketch 09 item 5) | Reassigns kinds of existing cells: `Mix`, a function `c -> kind` of the cell info, or a vector. Works on a layout or on a saved state (09's typed relaxed aggregate) |
| `Chain(n, blob; spacing, orientation, link = :chain)` (a shape) | **new**, P6.6 | A composite template: `n` blobs on a line. Each blob is a cell. Emits `cluster`, `rank` (1…n) and `add_link!(op, :chain, i, i+1)` |
| `Painted(labels, kinds)` | **new**, small | A given σ as a layer (§5.9) |
| `overlay(layers...)` | **kept** | — |

**Kinds.** `kinds = [:a, :b]` is cycled over cells in placement order (today).
`kinds = Mix(:a => 3//4, :b => 1//4; exact = true, seed)` is a random assignment: an exact
shuffle of rounded counts, or Bernoulli with `exact = false`. Its stream is the layer's seed
mixed with the stream id `:kinds` (P6.0w's mixer).

### 5.5 Composition and overlap rules

1. **Between layers: paint order.** `overlay(a, b, …)` paints in order, and ids follow
   layer order (D-057).
2. **Per-layer `into`** picks which current owners a layer may write:

   | `into` | Meaning |
   |---|---|
      | `Any()` **[Corrected 2026-10-01, initial-state-review.md §1b F10: cannot be defined, it shadows `Base.Any`; rename, e.g. `into = :all \| :medium \| [kinds…]`. `into` is deferred to the `Voronoi`/`Eden` rows]** | Overwrite anything. Default for `Tiling`, `Scattered`, `Objects`, `Fill` and `Frame`; it is today's behaviour |
   | `Medium()` | Write only medium. Default for `Voronoi` and `Eden`; it is Morpheus' rule everywhere |
   | `[:follower]` | Write only cells of those kinds that were painted before this layer. Default and required for `InsertUntil` (D-073) |

   This one keyword replaces Morpheus' implicit "only empty nodes" and CC3D's implicit
   "overwrite". Leaving room for cuts means overwriting stays the default.
3. **Within a layer: `resolve`** (`Objects` and `Scattered` with `gap = 0`). See §5.4. The
   default is `:first`, which is cheap and deterministic. `:nearest` needs one Float32 per
   site of the layer's bounding box.
4. **Dropped cells.** A cell left with no site, whether fully overwritten or never got one, is
   dropped and the ids stay consecutive (D-057). It is counted in the report's `dropped`.
   Morpheus removes such cells with a console warning.
5. **Splits.** A cell cut into several pieces by a later layer warns (today,
   `layouts.jl:431–489`). The cutting layer may say `splits = :allow` (Akeeb's leaders, by
   design), or the cut layer may be `collective = true` (fibres). Either removes the need
   for `with_logger(NullLogger())` in `akeeb_state` (`akeeb.jl:151–153`), which D-082 flags
   as hiding unrelated logs.
6. **Domain.** Shape-based layers paint only in-domain sites, so a shape is clipped to the
   domain and the clipped site count goes into the report. Today `_layout` throws when any
   cell covers an out-of-domain site (`layouts.jl:539–544`, D-057). Keep the throw for
   `Tiling` whole boxes (so `partial = :skip` still means whole) and clip for shapes **(Q5)**.
7. **Frozen kinds** are ordinary cells at layout time. Their `[frozen]` meaning is model
   content.

### 5.6 Fit failure and the report

**What each layer requests:**
- `Tiling`: boxes that fit;
- `Scattered`: `n`;
- `Objects`: `length(points)`;
- `RandomPoints`/`PoissonDisc` with `n`: `n`;
- `InsertUntil`: its stop rule;
- `Voronoi`/`Eden`: the generators.

**Realised:** cells that own at least one site after the whole overlay.

**`shortfall`:**
- `:error` (default, as Morpheus ≥ 2.0 and today's `Scattered`/`InsertUntil` throws): an
  `ArgumentError` naming the layer, the counts and a remedy; **[Corrected 2026-10-01, initial-state-review.md §1b F1: drop "as Morpheus ≥ 2.0" (its check is lenient by default); the keyword is deferred to P6.3c, while the report ships in P6.1a6]**
- `:warn`;
- `:allow`.

`RandomPoints(…; replace = true)` used for TST seeding (01b) implies `:allow`, because merging
is the published behaviour.

**Report.** `layout(l, sys; report = true) -> (op, report)` (api-synthesis §3.2 item 4,
ratified by D-075). `report` is a `Vector` of named tuples, one per leaf layer in paint order:

```julia
(; layer = 2, type = :InsertUntil, requested = 390, painted = 382, dropped = 0,
   misses = 8, counted = 390, clipped = 0, splits = 41)
```

- `layout_tally` (`layouts.jl:508–522`, D-073) is removed with no alias (D-028).
- `akeeb_layout`'s docstring example (`akeeb.jl:86–91`) becomes
  `only(r for r in last(layout(l, lat; report = true)) if r.type === :InsertUntil)`.
- A custom composite reports its children through `record!` (§5.10), which fixes today's
  "a composite of your own … reports no tallies" caveat (`layouts.jl:516–517`).

### 5.7 Per-cell and per-site initial values (reconciled with D-075 / R17)

**Rule.** Initial values are **model content**, written as expression defaults and
`@initialization_equations`. They are resolved by the Potts `at_init` host phase after the
lattice state (`ownership`, `kind`, `cluster`, links) is set (api-synthesis §2.4, §3.2; D-075
R17, first consumer P6.4a). This is exactly Morpheus' Property `value="expr"` with InitProperty
folded in. Layouts do not carry closures that compute values.

**Why model content.**
- `remake(prob; p = …)` re-runs `at_init` and re-draws (§3.2 item 3). A closure inside a
  layout value would not.
- Model content is fingerprinted.
- It works the same for `remake(u0 = sol[end])` (values not in `u0` re-initialize).

**Visible symbols** (cell scope unless noted). Morpheus parity is in brackets.

| Symbol | Meaning at init | Morpheus |
|---|---|---|
| `id` | cell id (`1:ncells`, layout order) | `cell.id` |
| `kind` | the cell's kind | `cell.type` |
| `volume`, `surface`, `centroid`, `major_length`, … | built-ins from the painted σ (host). `centroid` is allowed at init before R7 lands, because the host computes it once | `cell.volume`, `cell.center` |
| `cluster` | the `Group`/`Chain` id (D-036) | — |
| layout columns the model declares (`rank(cell)::Int = 0`, `chain` links) | values the layout emitted into the op (§5.10) | — |
| parameters; other variables | in D-042 dependency order; **a cycle is a compile-time error** | other properties, cycles found at run time |
| `rand()`, `randn()`, `rand(dist)` | from stream `Potts.init.<var>` keyed by (`seed`, `replica`, cell id, occurrence index), so a draw is independent of evaluation order and thread count, and two `rand()` in one expression are distinct **[the occurrence index is a proposal detail]** | `rand_uni`, `rand_norm`, … |
| `t` | 0 (or `tspan[1]`) | `time` |
| site scope: `position`, `owner`, `kind`, fields | for `cue(site) = position[2] - 1` | `space`, `l.x` |
| population folds (`count`, `sum`, `mean`) | over the initial state | `celltype.X.size`, Mappers |

**Per-population overrides (InitProperty).**
- **Kind (the usual case).** In every Morpheus InitProperty seen (m7671) and every paper model,
  the population that gets a different value *is a kind*. Write it with `ifelse(kind == …)`.
- **Layer-specific constants.** Two layers of one kind with different values, e.g. "left
  sheet `clone = 1`, right sheet `clone = 2`": a layer keyword `values = (:clone => 2,)`
  writes a constant column for that layer's cells into the op. Op values override defaults
  (D-075 §3.2 item 1). Only constants, so the logic stays in the model.
- **Expressions for all cells.** Symbolic op entries (`A => volume`) remain as ratified
  (§3.2 item 2), e.g. for 04's coarsen-then-reset.

**Cells born later.** Morpheus applies Property defaults to AddCell cells but not InitProperty.
Potts:
- `@divide`/`@create` set values explicitly (`clock => 0.0`).
- Whether expression defaults also apply to `@create`d (Fresh) cells is open **(Q6)**. The
  recommendation is yes, evaluated once per created cell at the creation phase.

### 5.8 The four starts, rewritten

#### (a) Merks 2006 (01) — `lib/PottsModels/src/merks.jl:78–94`

| Today (17 lines) | Proposed (1 expression) |
|---|---|
| `rng = MersenneTwister(seed)` | `Scattered(n, Rect(Vec(0, 0), Vec(side, side)); seed, gap = 1,` |
| `σ = zeros(Int32, lattice)` | `    region = Rect(Vec((lattice .- region) .÷ 2 .+ 2), Vec(region .- 2)),` |
| `off = (lattice .- region) .÷ 2`, `placed = 0` | `    kinds = [:endothelial])` |
| `for _ in 1:(1000n)` … draw `lo` in `2:(region-side)` … | (`Scattered`'s rejection loop) |
| `all(iszero, view(σ, box...)) \|\| continue` (a 1-site guard band = Chebyshev `gap = 1`) | `gap = 1` (D-057 semantics) |
| `σ[...] .= placed` | (painting) |
| `placed == n \|\| throw(...)` | `shortfall = :error` (default) |
| `return [ownership => σ, kind => fill(:endothelial, n)]` | `layout(l, sys)` |

Today `Scattered(282, (7, 7); region = …, kinds = [:endothelial], seed, gap = 1)` already
expresses this. The port predates it, so `merks_state` can become a one-line `merks_layout`.
Two consequences:
- **Statistics, not parity.** MersenneTwister becomes StableRNG, so the state changes but not
  its law. Spec-level tests apply (D-048, memory "ordinary tests over parity"). **[Corrected 2026-10-01, initial-state-review.md §1a C2, §1b F11: it is the same algorithm. Merks' loop on a shared `StableRNG(seed)` reproduces `Scattered`'s σ bitwise in 50/50 seeds (`/tmp/initstate-review/p2_merks.jl`); only the RNG changes. The gate's Merks case (`benchmark/gate.jl:30`), `mechanisms.jl:356` and the frozen `p6_0c_solver_placement.jl:160` use `merks_state`, so the port changes the gate's initial state and needs a gate re-check. Scheduled at P6.3d.]**
- **The rejection cost differs.** `merks_state` checks the box in σ (O(box) per draw), while
  `Scattered` checks every placed corner (O(placed) per draw, `layouts.jl:179`). §6 replaces
  the latter with a mask.

TST's actual seeding (01 §7.6) needs the new vocabulary:

```julia
sprout = overlay(Frame(:border; width = 2),
                 Splits(Eden(Objects(Site(), [Center()]; kinds = [:endothelial]); rounds = 50, seed = 1), 7))
denovo = overlay(Frame(:border; width = 2),
                 Eden(Objects(Site(), RandomPoints(360; region = interior, replace = true, seed = 1);
                              kinds = [:endothelial], shortfall = :allow); rounds = 10, seed = 2))
```

#### (b) Akeeb (10) — `lib/PottsModels/src/akeeb.jl:96–160`

| Today | Proposed |
|---|---|
| `struct _AkeebSlab <: AbstractLayout` + `Potts.paint!(σ, kinds, l, lat::Potts.LatticeSpec)` reading `lat.dims` (l.107–123, 17 lines; D-082: "because `Tiling` cannot express the clipped right column") **[Confirmed 2026-10-01, initial-state-review.md §1a C1: σ, kinds and tallies are byte-identical to an emulated `partial = :clip` (`p1_akeeb_clip.jl`). D-082's "with x-fastest ids" was never a `Tiling` gap; only the clip was]** | `Tiling((3, 3); region = (1:X, 1:(3cld(slab, 3))), kinds = [:follower], partial = :clip)`. Same σ and same ids: `Tiling` orders boxes column-major with x fastest (`layouts.jl:105`), as `_AkeebSlab`'s `for y …, x …` does (l.118) |
| `InsertUntil(:leader; into = [:follower], fraction = 1//4, seed, misses, region = (2:X, 2:(slab-1)))` | unchanged, plus `splits = :allow` |
| `with_logger(() -> layout(l, lattice), NullLogger())` (l.153) | `layout(l, sys)`, quiet by declaration |
| `rng = StableRNG(seed + 1)`; `clocks = [k === :leader \|\| rand(rng) > pp ? -1.0 : Float64(rand(rng, 0:74)) for k in kinds]` (l.155–156) | in the model: `clock(cell) = ifelse((kind == follower) & (rand() <= pp), floor(75rand()), -1.0)`, with `pp` a `@parameters` entry |
| `rates = [k === :leader ? 0.0 : 0.015 for k in kinds]` (l.157) | `rate(cell) = ifelse(kind == follower, 0.015, 0.0)` |
| `cue = [Float64(y - 1) for x in 1:X, y in 1:Y]` (l.158) | `cue(site) = position[2] - 1` |
| `return [ownership => σ, kind => kinds, :clock => clocks, :rate => rates, :cue => cue]` | `PottsProblem(AkeebInvasion(; name), layout(akeeb_layout(; lattice, seed), sys), tspan)` |
| counted inventory via `layout_tally` | `layout(l, sys; report = true)` |

Net: `_AkeebSlab` and `akeeb_state` disappear, and so does ~~PottsModels' only use of~~ a use of
`Potts.LatticeSpec` internals **[Corrected 2026-10-01, initial-state-review.md §1b F2: `VoronoiBall`'s `paint!` also reads `lat.domain` (`graner_glazier.jl:317`), so the P6.1a6 rewrite must cover it. `_AkeebSlab` goes at P6.1a6; `akeeb_state` only at P6.4a]**. `akeeb_layout` shrinks to the `overlay(Tiling, InsertUntil)`
expression.

Consequences:
- **Ratified re-baseline.** The clock draws move to `Potts.init.clock` and vary with
  `replica`. This is the ratified P6.4a re-baseline (D-075 amending D-068/D-071).
- **No-op for the slab change alone.** The slab replacement by itself is a σ-identical
  refactor that needs a test that σ is byte-identical, not a re-baseline.

#### (c) Jiang 2005 3D tumour (06) — sketch `06_jiang2005_tumor.md:169–171`

| Sketch today | Proposed |
|---|---|
| `c = sys.lattice.dims .÷ 2` | — |
| `layout(Tiling((3, 3, 3); region = map(i -> (i - 1):(i + 1), c), kinds = [:proliferating]), sys)` | `layout(Objects(Rect(Vec(-1, -1, -1), Vec(3, 3, 3)), [Center()]; kinds = [:proliferating]), sys)`, or the Morpheus-zygote form `Objects(Sphere(Point(0, 0, 0), r₀), [Center()]; …)` with `r₀` from `V_init` |
| proteins "top tier on" (06 §2): unspecified host code | network node defaults in the `@components` system (`E2F₊x = 1` …), plus `V_target(cell) = V_init` |

The Tiling form already works. The gains are `Center()` (no reach into `sys.lattice.dims`)
and a sphere that is round in 3D.

#### (d) Starruß myxobacteria (13) — sketch `13_starruss_myxobacteria.md:86–97`

| Sketch | Proposed |
|---|---|
| `rod = Chain(8; area = 12, spacing = sqrt(12), kinds = :segment, orientation = RandomDirection())` | `rod = Chain(8, Sphere(Point(0.0, 0.0), sqrt(12 / π)); spacing = sqrt(12), link = :chain)` |
| `fig6 = Scattered(100, rod; seed = 1)` ("overlap rule UNSPECIFIED") | `Scattered(100, rod; kinds = [:segment], orientation = RandomRotation(), gap = 1, seed = 1)`: no overlap with a 1-site gap, tested on painted masks (sketch 13 item 7, second bullet) |
| `fig8 = InsertUntil(rod; occupied = 0.30, seed = 1)` | `InsertUntil(rod; into = Medium(), occupied = 0.30, orientation = RandomRotation(), seed = 1)` |
| `op = layout(fig6, sys)` "ownership, kind, cluster, :ν, :prev, :next, :chain => pairs [NEW]" | `layout(fig6, sys)` returns `[ownership, kind, cluster, :rank => …, :chain => pairs]`. `prev`/`next` are derived from the ordered relationship (api-synthesis §5.3), so the "four copies of the rod order" (sketch item 1) collapse to one emitted link list plus `rank` |

On the hex lattice the `Sphere` blobs are round through the embedding. Areas are ≈12 but not
exactly 12 (Q7).

#### (e) Foam (04), for completeness

`Tiling((16, 16); stagger = (8, 0), kinds = [:bubble], partial = :wrap)` together with
`A(cell) = volume` in the model replaces the planned `BrickWall((16, 16); offset = 8)` (sketch
04 l.77) and the `A => volume` special case.

### 5.9 Room for import and export (out of scope, design only)

- **`Painted(labels, kinds)` is the seam.** A reader (`read_piff`, already in
  `lib/CorePotts/src/piff.jl:16`, M4.4) returns labels and kinds; `Painted` makes them a layer.
  It can then be `overlay`ed, `Relabel`ed and `Group`ed, and gets the same report and
  compaction.
- **`Mask(bits)`** takes image masks as regions. Morpheus' TIFFReader and Domain-from-image
  map onto these two values.
- **Exporters need nothing from layouts:** they act on states.
- **Constraint on this design:** layer outputs must stay plain arrays and op entries, never
  closures, so an imported state and a painted one are indistinguishable downstream.

### 5.10 Public extension points

**A custom shape** (most needs). Two required methods and one optional:

```julia
struct Annulus{N} <: Potts.AbstractShape
    r_in::Float64
    r_out::Float64
end
Potts.inside(a::Annulus, x) = a.r_in <= norm(x) <= a.r_out             # x: Cartesian SVector, template coordinates
Potts.bounds(a::Annulus{N}) where {N} = (fill(-a.r_out, N), fill(a.r_out, N))   # Cartesian bounding box
Potts.affinity(a::Annulus, x) = 1 - abs(norm(x) - (a.r_in + a.r_out) / 2) / ((a.r_out - a.r_in) / 2)  # optional, for resolve = :nearest

op = layout(Objects(Annulus{2}(4, 7), GridPoints((20, 20); region = Rect(Vec(1, 1), Vec(100, 100))); kinds = [:a]), sys)
```

`Objects`, `Scattered`, `InsertUntil`, `Fill`, `Voronoi(region = …)` and `region =` all accept
it.

**A custom layer** (new placement logic). One method,
`Potts.paint!(op::LayoutState, l, lat)`, using only:

| Function | Purpose |
|---|---|
| `size(lat)`, `ndims(lat)`, `isperiodic(lat, d)`, `indomain(lat, x)`, `embed(lat, x)`, `sites(lat)` | lattice queries (no `lat.dims`, `lat.boundary` field access) |
| `owner(op, x)`, `kindof(op, id)`, `ncells(op)` | read the state so far |
| `new_cell!(op, kind; cluster = nothing) -> id` | allocate |
| `assign!(op, x_or_sites_or_shape, id; into = Any())` | paint, honouring `into` and the domain; returns the number of sites written |
| `set_column!(op, :rank, id, v)`, `add_link!(op, :chain, a, b)` | structure (D-075 `LayoutState`) |
| `layer_rng(l.seed, stream::Symbol)` | StableRNG through the P6.0w mixer |
| `record!(op; requested, painted, misses = 0)` | a report row |

For example, the Akeeb slab as a custom layer if `Tiling` had no `partial`:

```julia
struct ClippedSlab <: AbstractLayout
    top::Int
    kind::Symbol
end
function Potts.paint!(op::LayoutState, l::ClippedSlab, lat)
    X = size(lat)[1]
    n = 0
    for y in 1:3:(l.top), x in 1:3:X
        assign!(op, (x:min(x + 2, X), y:(y + 2)), new_cell!(op, l.kind))
        n += 1
    end
    record!(op; requested = n, painted = n)
end
```

Compare with `akeeb.jl:113–123`, which reads `lat.dims`, pushes into a raw `kinds` vector and
writes `σ` directly. `paint!(σ, kinds, l, lat)` goes away ~~in the D-075 batch~~, with no alias
(D-028) **[Corrected 2026-10-01, initial-state-review.md §1b F3: D-075 amends D-057, but no ROADMAP row scheduled it; it is P6.1a6]**. `LatticeSpec` stays the argument type but is opaque in the docs.

### 5.11 Determinism

- **Per-layer seeds (D-057) and StableRNG (D-075).** A layer that needs several streams
  (points, orientations, kinds, widths) derives them with the **P6.0w mixer**
  (`layer_rng(seed, :points)`), not `seed + k`, which D-082 found shift-correlated.
- **Painting is single-threaded host code.** It is deterministic given the layout value and
  the lattice, and the order is the documented paint order.
- **Init draws** (`rand()` in defaults) come from the counter-based RNG keyed by
  (`seed`, `replica`, cell id), so they are reproducible and replica-varying under a fixed
  layout (api-synthesis §2.4).
- **Ensembles vary the layout** via `prob_func = (q, ctx) -> remake(q; u0 = layout(remake(l;
  seed = ctx.sim_id), sys))` (api-synthesis §3.5). The do-block form takes the seed as a
  closure argument.

### 5.12 2D, 3D and hex

- Shapes, points and fills are N-dimensional except `Rod` (2D) and `Cylinder` (3D).
- On a hex lattice:
  - shapes, distances and Voronoi use the Cartesian embedding;
  - `Tiling`, `Scattered` box gaps and `Frame` stay in axial index space, where a box is a
    rhombus (D-057; `layouts.jl:10`).

    ~~This mirrors Morpheus, which tests shapes in `orth` coordinates and places grid
  arrangements in lattice coordinates [unverified for Morpheus hex grids].~~ **[Corrected 2026-10-01, initial-state-review.md §1c: Morpheus places both shapes and arrangements in orth (Cartesian) coordinates (`init_cell_objects.cpp:81-85, 541-558`). Potts' axial-index `Tiling` is a deliberate difference (D-057), not a mirror.]**
- Periodic axes use minimum-image distances in `inside`, `Voronoi` and the `gap` test, as
  `Scattered` does today and Morpheus `orth_distance` does.

---

## 6. Performance notes

Painting runs once per problem (or once per ensemble member), on the host. Keep it simple,
but never O(sites × objects) or O(n²) at 3D sizes (200³ = 8·10⁶ sites, 10⁴–10⁵ cells).

| Operation | Today / Morpheus | Proposal | Cost |
|---|---|---|---|
| `Objects` painting | Morpheus `setNodes`: every node × every object | scan each object's bounding box; per-site winner buffer only for `resolve = :nearest` | O(Σ bbox volumes) |
| `Scattered` overlap test | every placed corner per draw (`layouts.jl:179`): O(n²) total | test the candidate's dilated mask against an occupancy `BitArray` | O(n · bbox) + O(sites) bits; 8·10⁶ bits = 1 MB at 200³ |
| `PoissonDisc` | Morpheus: 2D only | Bridson with a background grid of cell `r/√d`, 30 candidates per active point | O(n) |
| `Voronoi` assign | `VoronoiBall`: per-generator box scans with doubling `h` (`graner_glazier.jl`, `_voronoi_assign!`) | keep; it is already O(sites) per pass when generators are even. Bucket generators on a grid if Lloyd passes dominate | 30 Lloyd passes × 8·10⁶ sites ≈ 2.4·10⁸ distance evaluations, seconds **[estimate]** |
| `Eden` | — | frontier queue per round | O(rounds · frontier) |
| `Splits` | — | per-cell inertia then split | O(Σ volume · k) |
| `InsertUntil` | O(draws) (`layouts.jl:343–385`) | unchanged | — |
| split warning | O(sites) (`layouts.jl:431–489`) | unchanged; skipped for `splits = :allow` | — |
| report | `layout_tally` vector | per-layer row | O(layers) |
| init expressions | host loop in `akeeb_state` | `at_init` host phase, one pass per variable in dependency order | O(cells + sites) |

No device code is involved: the operating point is uploaded once (D-035 accounting
unchanged).

---

## 7. ROADMAP slicing and open questions

### 7.1 Proposed slicing

Each slice amends an existing row where one exists. No new step order: each lands with its
first consumer (model-first).

| Slice | Amends | Content | First consumer | Accept (sketch) |
|---|---|---|---|---|
| **S1. P6.1a6** (new, small, next) | D-057 → D-075's `LayoutState` | The `paint!(op::LayoutState, l, lat)` protocol; the public mutation API (§5.10); `record!` and `layout(…; report = true)`; remove `layout_tally`; `into`, `shortfall`, `splits` on the four shipped layers; `Tiling(…; partial = :clip)` | Akeeb: delete `_AkeebSlab`, delete the NullLogger hack | Akeeb σ and kinds **byte-identical** to today for the default seed; report rows equal the old tallies; a custom layer in a test uses no `LatticeSpec` field **[Amended 2026-10-01, initial-state-review.md §4 (adopted as P6.1a6): no `into`, `shortfall`, `set_column!` or `add_link!` (no consumer yet); add `remake`; re-freeze `acceptance/p6_2a_akeeb_analysis.jl` and `acceptance/p6_2a2_akeeb_inventory.jl` under a D-060-style entry; land before P6.0z. The mask-based `Scattered` is P6.1a7]** |
| **S2. P6.1a5** (amend) | P6.1a5 "move VoronoiBall" | Shapes (§5.2, with the GeometryBasics re-export decision Q1), `region = shape`, point patterns (`GridPoints`, `RandomPoints`, `PoissonDisc`, `Center`), `Objects`, `Voronoi(points; region, lloyd)`; `VoronoiBall` becomes `Voronoi` (or stays as sugar, Q3) | 09 GG aggregate, 11 four cells | `Voronoi` over a `Sphere` reproduces D-063's area statistics; the Poisson-disc minimum distance holds; 3D and hex tests |
| **S3. P6.0w** (unchanged, but before S2's random layers) | — | the mixer | all random layers | as written |
| **S4. P6.3c** (as written, named) | P6.3c "Eden + splits" | `Eden(seeds; rounds)`, `Splits(layer, k)`, `RandomPoints(…; replace = true)` + `shortfall = :allow` | 01 sprout/de novo (P6.3d) | 01 §7.6 geometry: ≈ 355 cells of ≈ 47 px de novo; 128 cells of 15–18 px sprout |
| **S5. P6.4a** (as written) | R17 | expression defaults with the §5.7 symbol set; compile-time cycle error; `rand()` occurrence indexing; Akeeb `clock`/`rate`/`cue` defaults, deleting `akeeb_state` | 04, 10 | the ratified Akeeb re-baseline |
| **S6. P6.4d** (amend) | `BrickWall` → `Tiling(…; stagger, widths, partial = :wrap)` | — | 04, 09 PRE bricks | the 04 §2.6 pattern on a periodic lattice; 09 varied widths, mean area 40 |
| **S7. P6.5c** (amend) | `Plane`, `Spheres` → `Fill(kind; region)`, `Objects(Sphere…)`, `Group` | — | 14 | the 14 code geometry: ball of radius R tangent to z = 1, 6³ nucleus, one cluster |
| **S8. P6.6** (amend R2 `Chains`) | — | `Chain` composite; `Scattered`/`InsertUntil` of templates with `orientation`; `occupied`; links and `rank` columns | 13 | 100 non-overlapping rods; occupancy 0.10/0.20/0.30 ± one rod |
| **S9. P6.8** (amend R2 `Fibres`) | — | `Rod`, `InsertUntil(Rod; occupied, collective = true)`, `Relabel` | 05, 07 | ρ within one bundle area of the target; the angle set honoured |
| **S10. P6.0z** | — | name audit of the new shapes and layers against Makie, SciMLBase, MTK and Graphs (D-056 rule) | — | — |

S1 is the only slice that is urgent, because it unblocks clean ports. The others ride their
model rows. 08 (`Tiling((5, 5))`, alternating kinds) and 12 (`Objects(Rotated(Ellipsoid…))`
in a block) need only S1 and S2.

### 7.2 Open questions for the user

1. **Shape names.**
   - **Option 1:** re-export GeometryBasics' `Rect`, `Sphere`, `Circle`, `Cylinder` and
     `Point` (the same bindings as Makie, so no ambiguity), with Potts-owned `Ellipsoid`,
     `Rod`, `Site`, `Mask`, `Where`.
   - **Option 2:** Potts-owned names in a `Shapes` submodule.
   - **Option 3:** Potts-owned top-level names. `Box` and `Sphere` would clash with Makie,
     so this is ruled out by D-056.

   The recommendation is option 1, with a half-open `inside` for `Rect`.
2. **`into` default.** Keep `Any()` (today, CC3D-like overwriting) or switch to `Medium()`
   (Morpheus)? The recommendation is to keep `Any()` for placing layers and use `Medium()`
   for filling layers (`Voronoi`, `Eden`).
3. **`VoronoiBall`.** Drop it in favour of `Voronoi(RandomPoints(n; region = Sphere(c, r));
   region = Sphere(c, r), lloyd = 30)`, or keep it as a documented convenience? The
   generators must stay distinct sites, as `VoronoiBall` draws them, to keep D-063's
   statistics. The recommendation is to drop it (one way to do it) and give the
   graner_glazier docstring the one-liner.
4. **Periodic `Tiling`.** Should `partial = :wrap` wrap boxes through a periodic edge? This
      is needed for 04 if the foam lattice is periodic (04 spec, lattice section) **[Confirmed 2026-10-01, initial-state-review.md §1c: 04 is periodic in x and closed in y (`04_foam.md:111-112`), so `:wrap` is needed at P6.4d. Akeeb is also periodic in x and wants `:clip`, so `partial` must be explicit, never inferred from periodicity]**.
5. **Domain clipping.** Should shape layers clip silently to the domain and report it, while
   `Tiling` keeps throwing? This amends D-057's "no cell may cover a site outside it" for
   shapes only.
6. **Expression defaults for created cells.** Should they apply to `@create` (Fresh) cells?
   Morpheus applies Property defaults but not InitProperty to AddCell cells. The
   recommendation is yes, defaults only.
7. **Exact versus approximate areas** for round blobs on lattices (13: area 12 on hex). Is
   "nearest achievable" acceptable for painting, with the volume term relaxing the rest
   (Morpheus' seed-and-grow idiom), or do layers need an `area = 12` mode (Eden to an exact
   count)? The recommendation is approximate, plus an optional `Eden(…; volume = A)` for
   exact counts.
8. **Lattice-relative coordinates.** Is the do-block `layout(sys) do dims … end` plus
   `Center()` enough, or do you want Morpheus-style relative coordinates (`Rel(0.5, 0.5)`)?
   The recommendation is the do-block only.
9. **Layer `values`.** Allow constant per-layer values (`values = (:clone => 2,)`) at all,
   or require a kind or a declared tag column? The recommendation is to allow constants
   only. No model of the 12 needs them, but Morpheus-style multi-population models do.
10. **Recount.** Worth a quick automated recount of InitCircle, InitRectangle, InitDistribute
    and InitPoissonDisc over the 50 published Morpheus models before freezing the point-pattern
    set? The prior count omitted them; this note's sample suggests InitCircle and
    InitRectangle are about as common as InitCellObjects.

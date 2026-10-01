> Coordinator's review of initial-state-vocabulary.md (2026-10-01). Adopted by the coordinator; ROADMAP rows P6.1a6 and P6.1a7 were filed from §4.

> **Review of `initial-state-vocabulary.md`** (coordinator's verifier, 2026-10-01). Probes are in `/tmp/initstate-review/` (`p1`–`p4`, plus the fetched Morpheus/CC3D/Artistoo sources in `morpheus/`, `uni.cpp`, `gm.js`). Nothing in the checkout was edited, staged or committed. Nothing ran on Metal.

# Adversarial review: `docs/design/research/initial-state-vocabulary.md`

Reviewer, 2026-10-01. Main checkout `PottsMonorepo` (working tree with the uncommitted P6.0k2 changes). Probes were run with `julia --project=test` from the monorepo root. Morpheus sources were fetched raw from `gitlab.com/morpheus.lab/morpheus` (project 895789, branch `main`) through the GitLab API, so the text is exact and not summarised. CC3D's `UniformFieldInitializer.cpp` and Artistoo's `GridManipulator.js` were fetched raw from GitHub.

## 0. Bottom line

**The direction is right. The note proposes far more than anything needs today.**
- The three load-bearing claims hold, measured:
  - `_AkeebSlab` is exactly a clipped `Tiling`.
  - `merks_state` is exactly `Scattered`.
  - `Scattered` is quadratic.
- The Morpheus reading is mostly accurate, but two "[unverified]" claims are refuted:
  - InitVoronoi does wrap periodically.
  - Morpheus places arrangements in Cartesian ("orth") coordinates, not lattice coordinates.
- Two stated facts are wrong:
  - The Morpheus ≥ 2.0 population check is lenient by default, so it does not support `shortfall = :error` as a precedent.
  - `remake(layout; seed)` does not work today.

**Adopt now: one amended slice, P6.1a6, plus one tiny performance row (P6.1a7).**
- P6.1a6 contents:
  - the D-075-ratified `paint!(op::LayoutState, l, lat)` rewrite;
  - `layout(…; report = true)`, replacing `layout_tally`;
  - `Tiling(…; partial = :clip)`;
  - a per-layer `splits = :allow`.
- P6.1a6 deletes `_AkeebSlab` and D-082's NullLogger. The probe shows the Akeeb σ, kinds and tallies are byte-identical (`p1`).
- P6.1a6 is well-formed only after three amendments:
  1. drop `into`, `shortfall` and the column/link mutators (no consumer yet);
  2. budget a re-freeze of two frozen acceptance files that call `layout_tally` and `paint!(σ, kinds, …)`;
  3. land it before P6.0z.

**Everything else rides its model row:** shapes, point patterns, `Objects`, `Voronoi`, `Eden`/`Splits`, `stagger`, `Fill`, `Chain`, `Rod`, Q1's GeometryBasics choice. Several items have no consumer among the 12 reference models and are deferred: `PoissonDisc`, `RingPoints`, `WeightedPoints`, `Mask`, `Where`, `Painted`, layer `values`, `resolve = :nearest`.

**Naming defect.** `into = Any()` cannot exist: it would shadow `Base.Any`. D-075 Q5's `clamp = Any()` has the same problem.

## 1. Verdict per claim

### 1a. The three claims the coordinator asked about

| # | Claim (report §) | Verdict | Evidence |
|---|---|---|---|
| C1 | `_AkeebSlab` ≡ `Tiling((3,3); region = (1:X, 1:3cld(slab,3)), kinds = [:follower], partial = :clip)`, σ- and id-identical, x fastest (§5.8b) | **Confirmed** | `p1_akeeb_clip.jl` emulates `:clip`: Tiling's starts run to `last(r)` and boxes are clipped at `last(r)`, iterated with `Iterators.product` exactly as `layouts.jl:105` does. `layout(_AkeebSlab)` and the emulation give identical σ and kinds for every case of X ∈ {99, 100, 101, 500} × Y ∈ {60, 300} × slab ∈ {19, 20, 21, 22}. The full `akeeb_layout` (the slab overlaid with the same `InsertUntil`) is identical in σ, kinds **and** `layout_tally` for 4 seeds × both seedings (default seed: 383 painted, 7 missed, 390 counted). `layout(l, (500,300))` (closed) equals `layout(l, sys)` (periodic x). The shipped Tiling without clip gives 1162 cells against the slab's 1169, and leaves columns 499:500 empty. Julia's `for y in …, x in …` runs x innermost, so D-082's "with x-fastest ids" was never a Tiling limitation; only the clip was |
| C2 | merks_state's loop is `Scattered(282, (7,7); region, kinds = [:endothelial], seed, gap = 1)`, with the same law but not bitwise (§5.8a) | **Confirmed, and stronger than claimed** | With `region = (off+2:off+R-1, …)` (here `85:415`), merks' draw range `off .+ (2:R-side)` equals Scattered's `first(r):last(r)-s+1`. merks' guard (the 1-dilated box is all zero) is exactly `_apart` with `gap = 1`. Running merks' loop on the *same* `StableRNG(seed)` reproduces Scattered's σ **bitwise in 50/50 seeds** (`p2_merks.jl`), so it is the same algorithm. Under the shipped MersenneTwister, 200 seeds each give mean nearest-neighbour distance 12.628 vs 12.628 (z = 0.02), centroid-x SD 94.30 vs 94.34 (z = −0.22) and mean centroid-x 250.07 vs 249.98 (z = 0.21). Only the attempt caps differ (merks: 1000n in total; Scattered: 10⁴ per box), which matters only when a placement jams |
| C3 | Scattered is O(placed) per draw (`layouts.jl:179`) | **Confirmed; it matters only at ≥ 10⁴ cells** | `p3_scattered_cost.jl`, warm times:<br>– 282 cells at 500²: 0.33 ms<br>– 2000 at 1000²: 7 ms<br>– 1500 cubes of 5³ at 100³: 18 ms<br>– 10⁴ cubes of 5³ at 200³: 465–488 ms<br>– 10⁴ squares of 7² at 1500²: 218 ms<br>– 4·10⁴ squares of 7² at 3000²: **3.5 s**<br>An occupancy-mask test with the same draws gives **the identical σ** (closed lattice) in 13.7 ms and 7.4 ms. At small n the mask is slower (1.8 ms vs 0.33 ms, from allocating the `BitArray`), which does not matter. Periodic axes need the dilation to wrap |

### 1b. Other facts in the report

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| F1 | Morpheus ≥ 2.0 makes a population shortfall fatal, cited as the precedent for `shortfall = :error` (§0 item 4, §5.6) | **Corrected** | `celltype.cpp:270-283` compares `cell_ids.size()`, the cumulative count of the **CellType** across all its populations, with `pop_size`. `pop_size` defaults to 1 (`celltype.cpp:420-421`), so the check only bites when `size` is set. The error message also has its operands swapped. Morpheus' effective default is therefore lenient. `:error` is still a reasonable Potts default on its own merits |
| F2 | "`_AkeebSlab` is PottsModels' only use of `LatticeSpec` internals" (§5.8b) | **Corrected** | `VoronoiBall`'s `paint!` reads `lat.domain` (`graner_glazier.jl:317`). The P6.1a6 rewrite must cover it too |
| F3 | "`paint!(σ, kinds, l, lat)` goes away in the D-075 batch" (§5.10) | **Corrected** | D-075 amends D-057 ("every layer is rewritten in the same change"), but its breaking-batch list (Q9) and every ROADMAP row omit it. No row schedules it. P6.1a6 would be that row |
| F4 | Morpheus `distance`-mode affinity is a "normalised depth" (§1 table) | **Partly** | Sphere and Cylinder use `1 − d/r` (normalised). Box and Hexagon use the raw signed depth `−d` in lattice units (`init_cell_objects.cpp:150-152, 418-424`). Ellipsoid uses `−(p − 1)`. Mixed shapes in one element compare unlike units. Potts' `affinity` should state its unit |
| F5 | Morpheus `mode="order"` is documented as the lowest celltype id; the code takes creation order (§3) | **Confirmed** | `init_cell_objects.h:29` against `.cpp:598-601` |
| F6 | `setNodes` is O(nodes × objects), writes only empty nodes, removes zero-size cells with a warning | **Confirmed** | `.cpp:568-635` (the triple loop over all nodes, then all objects; the `getEmptyState()` check) and `.cpp:522-528` |
| F7 | Makie exports `Box`, `Sphere`, `Circle`, `Rect`, `Point`, `Vec` | **Confirmed** | Probed on the installed Makie. Makie does **not** export `Cylinder`, `HyperSphere` or `Ellipsoid`. None of the proposed new names (`Objects`, `Fill`, `Voronoi`, `Group`, `Chain`, `Center`, `Medium`, …) is exported by Makie, MTK, SciMLBase or Graphs. Potts already has `sites` and `add_link!` |
| F8 | GeometryBasics 0.5.13 is in the workspace Manifest through Makie | **Confirmed, but not in Potts' tree** | It is reached only through CairoMakie, Makie, GridLayoutBase, MathTeXEngine, Packing, ShaderAbstractions and FreeTypeAbstraction (MakiePotts' side). Neither Potts nor CorePotts depends on it. Its deps are EarCut_jll (new to Potts), LinearAlgebra, PrecompileTools, Random and StaticArrays |
| F9 | Every Morpheus InitProperty use is per-kind | **Not checked** beyond m7671 | — |
| F10 | `into = Any()` as the default for placing layers (§5.5) | **Defect** | `Any` is `Base.Any`, so a Potts `Any()` cannot be defined without shadowing it. The same applies to D-075 Q5's `clamp = All() \| Any() \| Majority()` (not implemented yet; `api-synthesis.md:1662`). Flag both for P6.0z |
| F11 | Merks' rewrite is free | **Not quite** | `benchmark/gate.jl:30` builds the gate's Merks case from `merks_state(; lattice = (100,100), n = 50)`, and `mechanisms.jl:356` and the frozen `p6_0c_solver_placement.jl:160` use it too. Changing the stream changes the gate's initial state. It needs a gate re-check, not a re-baseline (D-048, D-029) |
| F12 | Akeeb's `clock`, `rate` and `cue` as expression defaults (§5.8b) | **Confirmed** as a transcription | `floor(75rand())` ∈ 0:74 matches `rand(rng, 0:74)`, and the follower/leader gating matches `akeeb.jl:155-158`. `pp` would become a model parameter, where today it is a keyword of `akeeb_state`. That is part of the ratified P6.4a re-baseline (D-075) |

### 1c. The "[unverified]" markers

The report has 10 tagged claims (lines 83, 84, 165, 169, 171, 225, 227, 231, 277, 373, 673 and 747), plus one "[estimate]" (l.689) and one "[proposal detail]" (l.477). The coordinator's count of 13 includes the latter two and the legend on l.8.

| Line | Claim | Verdict | Source |
|---|---|---|---|
| 83 | InitPoissonDisc is "likely Bridson-style" | **Confirmed** | `init_poisson_disc.h:27,32`: "using Robert Bridson's algorithm", from corporateshark/poisson-disk-generator. **New finding:** `DefaultPRNG()` seeds from `std::random_device` (`3rdparty/poisson-disc-generator/PoissonGenerator.h:52-57`), so InitPoissonDisc ignores Morpheus' seed and is **not reproducible**. This strengthens §3's "randomness is not addressable" point. Also, `aspect_ratio` is computed by integer division |
| 84 | InitVoronoi: "periodic wrap is not evident" | **Refuted** | The label sweep reads neighbours with `distanceMap->get(pos + neighbors[i])` (`init_voronoi.cpp:169-170`). `Lattice_Data_Layer::get` falls back to `_lattice->resolve(a)` (`lattice_data_layer.cpp:302-312`), which applies periodic wrap. So it wraps. Also, the distance is a **chamfer** transform (sums of order-5 neighbour step lengths), only approximately Euclidean |
| 165 | Across celltypes, the order is declaration order | **Confirmed, made precise** | `cpm.cpp:213-234` pushes celltypes in `<CellTypes>` order; `cpm.cpp:389-391` calls `init()` in that order. The order is that of the CellType definitions, not of the Population elements |
| 169 | Daughter values are copied from the mother unless Triggers reset them | **Confirmed** | `cell_division.h:29-30`. Both daughters are new ids |
| 171 | The symbols visible at init | **Mostly confirmed** | `cell.center/volume/id/type/surface/length/orientation` are registered in core. **Correction:** `space` and `time` are user-chosen names (`SpaceSymbol/@symbol` and `TimeSymbol/@symbol`, `simulation.cpp:617,647`), not fixed symbols. The `rand_*` functions (muParser setup) were not checked |
| 225 | The CC3D/Artistoo/Chaste contrast | **Partly refuted** | Artistoo *does* have pixel-set shape builders: `makeBox`, `makeCircle`, `makeLine` and `makePlane`, plus `assignCellPixels` (`GridManipulator.js:215-413`). "None of the three has … shape/arrangement factorisation" is overstated: Artistoo has shapes, but no arrangements or property expressions |
| 227 | UniformInitializer assigns types at random | **Confirmed** | `UniformFieldInitializer.cpp:143-150`. **New, relevant to `:clip`:** CC3D places `ceil(boxDim/size)` boxes per axis (`:88-93`) and clips each box at the **lattice** edge (`cellPt.x < dim.x`, `:121-126`), not at the region. Boxes therefore overhang the region on its upper side. That is why `akeeb_layout` rounds the slab up to `3cld(slab, 3)`. Potts' `:clip` clips at region ∩ lattice. It reproduces CC3D only when the region's upper bound is rounded up to whole boxes or equals the lattice edge. Document this |
| 231 | Artistoo method names | **Confirmed** | `GridManipulator.js:88,126,165,259,413` |
| 277 | `remake(l; seed)` works through ConstructionBase | **Refuted** | `SciMLBase.remake(Scattered(…); seed = 2)` throws a `MethodError` (no keyword constructor). `ConstructionBase.setproperties` works on positional fields, but skips constructor validation. `InsertUntil`'s fields (`number = -1`, `count_misses`) do not match its keywords (`number`, `misses`), so `setproperties(l; misses = :retry)` fails. It needs an explicit `SciMLBase.remake(::AbstractLayout; kw...)` that re-calls the keyword constructor. That is small, but it is a deliverable |
| 373 | `Splits` reuses the lifecycle division routine on a host σ | **Refuted as a cheap reuse** | `run_lifecycle!` (`lib/CorePotts/src/lifecycle.jl:272ff`) needs a `CPMState` with trackers, `ctx`, `key` and backend launches. `Splits` should be a small host routine (centroid and inertia from σ, then a cut through the centroid along the short axis, O(Σ volume)) that shares only the split geometry |
| 477 | `rand()` occurrence index | **Proposal detail**, not a fact | Check that D-031's key has a free slot for it at P6.4a |
| 673 | Morpheus places grid arrangements in lattice coordinates on hex | **Refuted** | Object centres are orth coordinates (`Sphere::init`: `_center = p_center + displacement`, then `from_orth(_center)`, `init_cell_objects.cpp:81-85`), and `arrangeObjectCombinatorial` adds `r*displacement` to them (`:541-558`). Morpheus places **both** shapes and arrangements in Cartesian coordinates. Potts' axial-index `Tiling` therefore *differs* from Morpheus. Keep it (D-057), but drop "this mirrors Morpheus" |
| 689 | Voronoi cost estimate | **Not checked** | — |
| 747 | 04's boundary | **Confirmed periodic in x, closed in y** | `model-specs/04_foam.md:111-112`. 256 / 16 = 16 bricks per row, so the rows offset by 8 must wrap through x: `partial = :wrap` (or wrap-aware `stagger`) is needed at P6.4d. Akeeb is also periodic in x and wants `:clip`. So `partial` must be explicit and never inferred from periodicity |

## 2. Verdict per recommendation

| Report item | Verdict | Reason |
|---|---|---|
| §0.1 Shapes × point patterns × layers as plain values | **Adopt as direction; build per consumer** | It is family-general and fits "models open mechanism families". Each piece lands with the first reference model that needs it (§4) |
| §0.2 `paint!(op::LayoutState, l, lat)` and the public mutation API | **Adopt-amended (P6.1a6)** | D-075 already ratified it; no row schedules it. Ship `LayoutState` (σ, kinds, report rows; the struct is opaque, so fields can be added without breaking anything), and as public accessors `new_cell!`, `assign!`, `owner`, `kindof`, `ncells`, `record!`, plus lattice queries replacing field access (`size`, `isperiodic`, `indomain`, `core_lattice`). **Defer** `set_column!` and `add_link!` to their first consumers (`Group`/cluster at P6.5c, links at P6.6) |
| §0.3 `into` and `resolve` | **Defer**, rename `Any()` | Only `InsertUntil` has `into` today, and keeps it. `Medium()` has no consumer until `Voronoi`/`Eden` (P6.1a5, P6.3c). `resolve = :nearest` has no consumer among the 12. Use symbols, e.g. `into = :all \| :medium \| [kinds…]`, or a non-Base name |
| §0.3 / §5.5.5 `splits = :allow` | **Adopt (P6.1a6)** | It removes D-082's NullLogger. `_warn_split` must track which layer cut a cell. Rule: a cell is exempt only if every layer that cut it allows splits. That is O(sites), the same as today |
| §0.4 `shortfall = :error \| :warn \| :allow` | **Defer the keyword; adopt the report** | Today's layers already throw on a shortfall. The first `:allow` consumer is 01b at P6.3c. The report rows (`requested`, `painted`, `dropped`, `misses`, `counted`, `clipped`) ship in P6.1a6. Drop the "Morpheus ≥ 2.0" justification (F1) |
| §0.5 Per-cell values as model content (R17) | **Adopt (already ratified at P6.4a)** | The §5.7 symbol table is useful acceptance input for P6.4a. Layer `values = (…)` constants: **defer** (no consumer, Q9) |
| §0.6 Sub-quadratic painting | **Adopt the `Scattered` mask (P6.1a7)**; the rest is by construction or deferred | The mask gives identical σ (C3). `Objects` scanning per-object bounding boxes is simply how it should be written at S2. Bridson and generator bucketing wait until a consumer exists |
| §5.8a `merks_state` → `Scattered` | **Adopt-amended: at P6.3d** (Merks split) | Same algorithm (C2). It changes the gate's Merks initial state (F11): re-check the gate and the `mechanisms.jl` seeds. Keep the tuple-of-ranges region, not `Rect` |
| §5.8a TST seeding (`Eden`, `Splits`, `RandomPoints(replace = true)`) | **Adopt at P6.3c** | `Splits` is a host routine (l.373 refuted) |
| §5.8b Akeeb rewrite | **Slab and NullLogger: adopt (P6.1a6). `clock`/`rate`/`cue`: P6.4a, as ratified** | `akeeb_state` disappears only at P6.4a. Note one lost check: `_AkeebSlab` validated `dims[1] == X`, and `Tiling(region = (1:X, …))` on a wider lattice would paint a partial slab silently. Keep a width check in `akeeb_layout` or document it |
| §5.8c `Objects(Sphere…, [Center()])` (06) | **Defer to 06's row** | `Tiling` already works there |
| §5.8d `Chain` and rods (13) | **Defer to P6.6** | — |
| §5.8e and S6: `Tiling(stagger, widths, partial = :wrap)` replaces `BrickWall` | **Adopt-amended at P6.4d** | More general. It amends the layer list of api-synthesis §3.3 ratified by D-075 (`BrickWall(size; offset, widths)`), so it needs the maintainer's ratification in the P6.4d DECISIONS entry |
| S7: `Fill` and `Objects(Sphere)` replace `Plane` and `Spheres` | **Adopt-amended at P6.5c** | Same: a D-075 §3.3 amendment |
| S2: shapes, points, `Objects`, `Voronoi` | **Adopt-amended at P6.1a5** | Scope it to what 09 and 11 need: `Sphere`, `RandomPoints`, `Voronoi(points; region, lloyd)`, `Center()`. `GridPoints` and `Ellipsoid`/`Rotated` arrive with 12. `PoissonDisc`, `RingPoints`, `WeightedPoints`, `Mask`, `Where`, `Painted` and `Relabel`-on-a-saved-state wait for consumers. `Painted` and `Mask` are import seams, which the user put on hold |
| S10: name audit | **Adopt as P6.0z input** | Include `Any()` (F10), and `Box` in `@create … at = Box(lo, hi)` (`api-synthesis.md:441`), which clashes with Makie's `Box` |
| §5.1 `remake(l; seed)` | **Adopt as a small deliverable of P6.1a6** | It does not work today (l.277) |

## 3. Answers to Q1–Q10

1. **Shape names and GeometryBasics.** Decide at P6.1a5, not now. Measured facts:
   - Neither Potts nor CorePotts depends on GeometryBasics.
   - Adding it costs **+0.20 s** load after Potts' 4.65 s (`p4_gb_load.jl`, about 4 %, well inside D-047's 15 s), plus the EarCut_jll artifact.
   - GeometryBasics exports `volume`, `area`, `direction`, `origin` and `radius`, so Potts must import names explicitly, never with `using`.
   - **Do not reuse `Rect` with a half-open `inside`.** `Base.in(::Point, ::Rect)` is closed: `Rect(Vec(1,1), Vec(3,3))` contains 16 lattice points. A Potts `inside` that disagrees with `p in rect` on the same object is a trap. If Potts reuses GeometryBasics types, use their own `in` (closed) as the membership rule, so `inside(s, x) ≡ Point(x) ∈ s`. Keep index boxes as tuples of unit ranges, as `region` already is: they are unambiguous and already shipped.
   - For round shapes (`Sphere`/`Circle`/`HyperSphere`, and `Cylinder`), the closed `‖x − c‖ ≤ r` matches the report's rule, so reuse is sound and is no type piracy, since `inside` is a Potts function.
   - Recommendation: option 1, restricted to `Sphere`, `Circle`, `HyperSphere`, `Cylinder` and `Point`, with closed membership. Index boxes stay ranges. `Rect` is used only if a Cartesian/rotated box consumer appears (12). Potts-owned `Ellipsoid`, `Rod` and `Site`.
2. **`into` default.** Moot until `Voronoi`/`Eden` land. The report's split is right (overwrite for placing layers, medium-only for filling layers), but rename `Any()`.
3. **`VoronoiBall`.** Drop it only if `Voronoi(RandomPoints(n; region = Sphere(c, r)); region = Sphere(c, r), lloyd = 30)` either reproduces `VoronoiBall`'s σ for the same seed (feasible: same draws, same Lloyd loop, same `_connect_pieces!`), or matches D-063's area statistics within tolerance. Otherwise keep it as sugar. Note that `VoronoiBall` clips rather than wraps on periodic axes, while the report's `Voronoi` uses the minimum image. That is a behaviour change, harmless for an interior ball.
4. **Periodic `Tiling`.** Yes: 04 is periodic in x (U-747), and 16 offset bricks per row must wrap. Make `partial` explicit (`:skip \| :clip \| :wrap`) and never inferred: Akeeb is periodic in x and wants `:clip`. P6.4d.
5. **Domain clipping for shapes.** Adopt-amended at P6.1a5: shape layers clip to the domain and report `clipped`; `Tiling` keeps D-057's throw. This is a D-057 amendment, recorded in that row's DECISIONS entry.
6. **Expression defaults for `@create`'d (Fresh) cells.** Consistent with D-075 in spirit: R17 covers t₀ only, and today's division copies the parent's columns unless a rule says otherwise, as in Morpheus. But this is **premature**: `@create`/`Fresh` exist only on paper (P6.5b/P6.9). Answer at that row:
   - numeric defaults: yes;
   - expression defaults: evaluated once at the creation phase, only for host-evaluable forms, inside D-075's "one host round trip per `@convert` firing" cost;
   - `rand()` keyed by D-066's birth serial, not the cell id, because ids are reused.
7. **Exact or approximate areas.** Approximate, using the Morpheus seed-and-grow idiom, which suits D-029. Defer `Eden(…; volume = A)` until 13 needs exactness.
8. **Lattice-relative coordinates.** The do-block is enough; `Center()` is optional sugar. Reject `Rel(…)`.
9. **Layer `values`.** Defer: no consumer among the 12.
10. **Recount.** Low value now. Point patterns are built only for consumers, so a recount changes nothing until someone proposes a pattern without a reference-model consumer. Defer.

## 4. Suggested ROADMAP rows

**P6.1a6 (new, step 1, after P6.2a2; land before P6.0z) — the layout protocol of D-075 (D-057 amendment): `paint!(op::LayoutState, l, lat)`, the layout report, `Tiling(partial)` and `splits`.**
- The public extension method becomes `paint!(op::LayoutState, l, lat)`. Every layer is rewritten in the same change: `Tiling`, `Scattered`, `Frame`, `InsertUntil`, `Overlay`, and PottsModels' `VoronoiBall`.
- New public names: `new_cell!`, `assign!`, `owner`, `kindof`, `ncells` and `record!`, plus lattice accessors so that no layer reads `LatticeSpec` fields. `paint!(σ, kinds, …)` and `layout_tally` are removed, with no alias (D-028).
- `layout(l, x; report = true) -> (op, report)`: one row per leaf layer, in paint order, with `requested`, `painted`, `dropped`, `misses`, `counted` and `splits`.
- `Tiling(…; partial = :skip | :clip)`. `:clip` keeps boxes cut by region ∩ lattice. The docstring states the CC3D difference (CC3D clips at the lattice only).
- `splits = :warn | :allow` on every layer. A cell is exempt from the split warning only if every layer that cut it allows splits.
- `SciMLBase.remake(::AbstractLayout; kw...)` re-runs the keyword constructor.
- `akeeb_layout` = `overlay(Tiling(…; partial = :clip), InsertUntil(…; splits = :allow))`. `_AkeebSlab` and the `NullLogger` in `akeeb_state` are deleted. A width check is kept.
- Acceptance:
  - Akeeb σ, kinds, and painted/misses/counted equal today's byte for byte, at 500×300 and 99×60, for both seedings and at least 4 seeds. Reviewer reproducer: `/tmp/initstate-review/p1_akeeb_clip.jl`.
  - `akeeb_state` emits no log record, and an unrelated `@warn` inside a layer still surfaces.
  - The custom layer in the test suite uses no `LatticeSpec` field.
  - `remake(Scattered(…); seed = 2)` and `remake(InsertUntil(…); misses = :retry)` work and validate their arguments.
  - Re-freeze, under a DECISIONS entry in the D-060 style, of `acceptance/p6_2a_akeeb_analysis.jl` (10 `layout_tally` uses) and `acceptance/p6_2a2_akeeb_inventory.jl` (`layout_tally` and the `P62a2Slab` oracle's `paint!(σ, kinds, …)`). Assertions are unchanged; only the API calls change. `siblings.jl:180` and `guardrails.jl:118` are updated.
  - The gate and every model fingerprint are unchanged.
  - Aqua, JET and ExplicitImports are clean.
- Not in this row: `into`, `shortfall`, `set_column!`, `add_link!`, shapes.

**P6.1a7 (new, small, after P6.1a6; serialise with it, same file) — `Scattered` overlap test against an occupancy mask.**
- Accept: σ is identical to the pre-change version over a seed grid, on closed and periodic lattices (the dilation wraps), in 2D, 3D and on hex.
- Accept: 10⁴ cubes of 5³ at 200³ take under 50 ms, against about 480 ms today (`p3_scattered_cost.jl`).

**Amendments to existing rows:**
- **P6.1a5:** shapes and points as scoped in §2, row S2; the Q1 decision; `Voronoi` with the VoronoiBall σ-or-statistics acceptance (Q3); domain clipping (Q5).
- **P6.3c:** `Eden`, a host-routine `Splits`, `RandomPoints(replace = true)`, and `shortfall` with its first `:allow` consumer.
- **P6.3d:** the `merks_state` → `Scattered` port, with a gate re-check.
- **P6.4d:** `Tiling(stagger, widths, partial = :wrap)` in place of `BrickWall`, ratifying the D-075 §3.3 amendment.
- **P6.5c:** `Fill`, `Objects(Sphere…)` and `Group` (with `set_column!`), in place of `Plane`/`Spheres`.
- **P6.6:** `Chain` with `add_link!`.
- **P6.8:** `Rod` and `InsertUntil(shape; occupied, collective)`.
- **P6.0z:** add `Any()` (layout `into`, D-075 Q5 clamp) and `Box` in `@create … at =`.

## 5. Inline corrections for the coordinator to mark in the report

1. §0 item 4 and §5.6: "Morpheus ≥ 2.0 also makes a population shortfall fatal". Add: "only when `size` is set (default 1), and against the CellType's cumulative cell count (`celltype.cpp:270-283, 420-421`)".
2. §1 InitPoissonDisc: replace "[unverified: likely Bridson-style]" with "Bridson (`init_poisson_disc.h:27`); its PRNG is seeded from `std::random_device`, so it ignores the simulation seed (`PoissonGenerator.h:52-57`)".
3. §1 InitVoronoi: "Periodic wrap is not evident [unverified]" becomes "wraps periodically through `Lattice_Data_Layer::get` → `Lattice::resolve` (`lattice_data_layer.cpp:302-312`)". Also, "Euclidean" becomes "chamfer (sums of order-5 step lengths), approximately Euclidean".
4. §1 InitCellObjects: "normalised depth" becomes "Sphere and Cylinder normalised; Box and Hexagon raw depth in lattice units; Ellipsoid `1 − p`".
5. §2: the cross-celltype order is "CellType definition order in `<CellTypes>` (`cpm.cpp:213-234, 389-391`)". Remove [unverified].
6. §2: the daughter-copy claim is confirmed (`cell_division.h:29-30`). Remove [unverified].
7. §2 symbols: "`space` and `time` are user-named (`SpaceSymbol`/`TimeSymbol` `symbol`, `simulation.cpp:617,647`)".
8. §3 contrast: UniformInitializer random types confirmed. Add: "it clips at the lattice, not the region; boxes overhang the region (`UniformFieldInitializer.cpp:88-93, 121-126`)". Artistoo also has `makeBox`/`makeCircle`/`makeLine`/`makePlane`, so "none of the three has the factorisation" becomes "none has arrangements or property expressions".
9. §5.1: "`remake(l; seed)` works" is false today: `SciMLBase.remake` throws a `MethodError`, and `setproperties` skips validation and fails for `InsertUntil`. It is a P6.1a6 deliverable.
10. §5.4 `Splits`: "reuses the lifecycle division routine" becomes "a host routine sharing only the split geometry; `run_lifecycle!` needs a `CPMState`".
11. §5.5 `into` table: `Any()` cannot be defined because it shadows `Base.Any`. Rename.
12. §5.8a: "statistics, not parity" becomes "the same algorithm: draw-for-draw identical under a shared StableRNG (`/tmp/initstate-review/p2_merks.jl`); only the RNG changes". Add that the gate's Merks case (`benchmark/gate.jl:30`) changes its initial state.
13. §5.8b: "PottsModels' only use of `LatticeSpec` internals" is wrong: `VoronoiBall` reads `lat.domain` (`graner_glazier.jl:317`). D-082's "x-fastest ids" was never a Tiling gap; only the clip was.
14. §5.10: "goes away in the D-075 batch" becomes "D-075 amends D-057, but no row schedules it (proposed P6.1a6)".
15. §5.12: "This mirrors Morpheus … [unverified for hex]" is refuted: Morpheus arranges objects in orth coordinates (`init_cell_objects.cpp:81-85, 541-558`). Potts' axial-index `Tiling` is a deliberate difference.
16. §7.2 Q4: remove "[unverified: 04's boundary]". 04 is periodic in x and closed in y (`04_foam.md:111-112`).
17. §7.1 S1: add the frozen-test re-freeze (`p6_2a`, `p6_2a2`), the "land before P6.0z" ordering, and the trimmed scope (no `into`, `shortfall` or column/link mutators).

## 6. Reviewer probes (`/tmp/initstate-review/`)

- `p1_akeeb_clip.jl`: `_AkeebSlab` against the emulated `:clip` (a grid of sizes, the full overlay, tallies, closed vs `sys`).
- `p2_merks.jl`: the merks loop on a shared StableRNG (bitwise), and MersenneTwister vs StableRNG statistics over 200 seeds.
- `p3_scattered_cost.jl`: Scattered timings, and a mask variant with σ equality.
- `p4_gb_load.jl`: GeometryBasics load cost, `Rect`/`Sphere` membership and export clashes.
- `morpheus/`: raw Morpheus sources (initialization plugins, `celltype.cpp`, `cpm.cpp`, `property.h`, `lattice_data_layer.*`, `cell_division.*`, `add_cell.cpp`, `PoissonGenerator.h`); `uni.cpp` (CC3D `UniformFieldInitializer.cpp`); `gm.js` (Artistoo `GridManipulator.js`).

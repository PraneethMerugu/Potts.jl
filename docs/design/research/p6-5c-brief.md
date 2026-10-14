# P6.5c test-author brief: initial-state vocabulary, predicate-sourced PDE, MSD / Fürth fits

2026-10-14. A spec for the P6.5c test author, written before any implementation. It is not
code. Written against `monorepo` at 99301437 (P6.0cd merge; P6.5a and P6.5b merged at
3d9d1ede, D-231, D-233).

Conventions:
- `file:line` cites existing code or design text. **[inference]** marks a conclusion of this
  brief that no source states. **[probe]** marks something checked by a small script on
  99301437 (scripts in the session scratchpad, not committed).
- Indices are Julia's, 1-based. The 14a code is 0-based: its substrate plane z = 0 is our
  z = 1, its lid plane z = L_z − 1 is our z = L_z, and its ball "tangent at z = 1" bottoms at
  our z = 2.

ROADMAP row (`docs/design/ROADMAP.md:728–729`): "R2 `Plane`, `Spheres`; R5
predicate-sourced PDE; R16 MSD / Fürth fits. Initial-state vocabulary … `Fill`,
`Objects(Sphere…)` and `Group` (with `set_column!`) in place of `Plane`/`Spheres`; amends
D-075 §3.3, user-approved 2026-10-01 (D-087); the docs show `Plane`/`Spheres` recipes."

First consumer: P6.5d, the Fortuna reproduction (spec `model-specs/14_nucleus_migration.md`,
sketch `model-specs/sketches/14_nucleus_migration.md`, both with the audit rulings of
2026-10-13).

---

## 0. Summary

| Part | Delivers | New public names | Engine change? |
|---|---|---|---|
| A. Initial state (R2) | `Interior(shape)` (strict membership), `Fill(kind; region)`, `Objects(shape[, points]; kinds)`, `Group(layers...)`, `set_column!`; `layout` emits `cluster` and extra columns | `Interior`, `Fill`, `Objects`, `Group` (exported); `set_column!` (public) | No. Host-only layout code (`src/layouts.jl`) |
| B. Predicate-sourced PDE (R5) | Nothing new to write: the form already compiles and runs on the CPU **[probe]**. P6.5c pins it with acceptance tests (CPU and device) and documents it. It fixes whatever the device run shows broken | none | Only if the device test fails |
| C. Analysis (R16) | `unwrap_track`, `msd`, `furth_fit` (S, D, P, D_fast, D_slow, v_eff), `furth_msd`, `natural_units` in `PottsModels.Analysis` | 5 functions in `PottsModels.Analysis` | No |

Deferred: the E7 helpers (`centroid(c, k)`, `minimum_image`, and the cluster sum `integral(x; over = cluster)`, formerly `cluster_integral`), which D-231
already assigned to a "P6.5a2" row that ROADMAP does not yet contain (§2, Q-3). Also every
item in §5.

---

## 1. Scope

### 1.A Initial-state vocabulary (R2)

**What exists** (`src/Potts.jl:74–80`, D-138, D-141): `Tiling`, `Scattered`, `Frame`,
`InsertUntil`, `Voronoi`, `Eden`, `Splits`, `overlay`, `layout`; shapes `HyperSphere`,
`Circle`, `Sphere`, `Point` (GeometryBasics bindings) and the patterns `Center()` and
`RandomPoints`; the extension protocol `paint!(op::LayoutState, l, lat)` with `new_cell!`,
`assign!`, `owner`, `kindof`, `ncells`, `record!`, `isperiodic`, `indomain` (D-091). Shape
membership is **closed** with a relative tolerance: `norm(center − embed(x)) ≤ r·(1 + 1e-12)`
(`src/layouts.jl:781`, D-138). `layout` returns only `[ownership => σ, kind => kinds]`
(`src/layouts.jl:1765–1767`). `cluster` is entered by hand in the operating point, with "any
ids; equal ids form one cluster" (`src/problem.jl:82–83`).

**What 14 needs** (spec 14 §2.9.1 l.159; §9 ruling l.627–631; sketch l.111–123):
- a cytoplasm ball with strict `|r − c| < R`, tangent to the substrate. The centre is at our
  z = R + 1, so the ball's lowest layer is z = 2 and the substrate plane z = 1 is never in it.
  The spec says a port "must use strict `<`" (l.159).
- a 6×6×6 nucleus cube at the integer centre, offsets −3…+2 per axis;
- a frozen substrate plane at z = 1 and a frozen lid plane at z = L_z;
- cytoplasm and nucleus in **one cluster**; the planes are not in it;
- no lamellipodium at t = 0;
- targets fixed from t = 0. They are model content through kind-conditional defaults (below),
  not operating-point vectors. The audited ruling sizes the ball to ≈ (1 − φ_n − φ_l)V + 216
  sites (l.629). Choosing that radius is P6.5d's arithmetic; P6.5c only has to support a
  non-integer radius and a non-integer centre.

**P6.5c delivers:**
1. **`Interior(s)`**: the open (strict) version of a round shape. The existing closed
   `Sphere` cannot express the code's strict test. At integer R with the centre at z = R + 1,
   the closed ball has one site **on the substrate plane** (z = 1) and one on the lid plane
   (z = L_z), and 150 more sites than the strict ball at R = 15 (§4.A6). D-087 names
   `Objects(Sphere(…))`. `Interior` is an addition, not a change to D-138's closed rule
   (§2, Q-1).
2. **`Fill(kind; region)`**: one cell owning every in-domain site of a region. Planes, slabs,
   backgrounds and the nucleus cube are all `Fill`s. It replaces `Plane(kind; axis, at)`
   (D-087).
3. **`Objects(shape[, points]; kinds)`**: one cell per object, the shape translated to each
   point. It replaces `Spheres` (D-087). Shapes: `HyperSphere` and `Interior(HyperSphere)`.
   Index boxes stay `Fill`/`Tiling` regions (D-138 kept `Rect` out).
4. **`Group(layers...)`**: every cell its children create forms one cluster; `layout` emits
   `cluster =>`. Many compartment cells are `overlay(Group(…), Group(…), …)`, one `Group` per
   cell, which plain Julia can build (`overlay((Group(...) for c in centres)...)`).
5. **`set_column!(op, name, id, value)`**: the public seam a custom layer uses to emit a
   per-cell column (`:cluster` or a model variable). `Group` is built on it.
6. **Docs** (D-087): `docs/src/manual/layouts.md` gains rows for the four names, plus
   "Plane" and "Spheres" recipes (§3.A8), and the Fortuna start written with them.

**Cluster and compartment emission.** A compartment cell is a `Group` of one cell per
compartment. The layout gives cluster labels, and `PottsProblem` picks the root
(`src/problem.jl:776–777`, `prefer = _cluster_kinds(c)`). The layout's ids are therefore
labels; tests check the **partition**, not root ids, at the problem level.

**Kind-conditional per-cell initial values: already exist, not in P6.5c.** P6.5b shipped
expression-valued, kind-conditional cell-variable defaults, evaluated per slot at problem
construction and for `@convert`-allocated slots (ergonomics E1; D-233 "E1" bullet and ruling 5;
frozen in `lib/PottsModels/test/acceptance/p6_5b_convert.jl:120–135` and its testset at
l.786–795, e.g. `V_target(cell) = ifelse(kind == nucleus, φ_n, …) * V_cell`). Fortuna's fixed
targets are written this way, so no `:V_target` vector goes in the op. The general R17 `at_init`
phase (`A(cell) = volume`, re-run on `remake(p = …)`) remains P6.4a
(`ROADMAP.md:644–649`), and 14 does not need it. Layer-level `values = (…)`: still deferred
(initial-state-review §3 Q9, l.128).

### 1.B Predicate-sourced PDE (R5)

Spec 14 Eq. 6 (l.73) with the code's source (§2.9.2, l.166): F-actin is produced only at
lamellipodium sites with a face neighbour in the substrate. In the model it is written

```julia
@equations D(F) ~ D_F * Δ(F) - k_decay * F +
                  k_source * (kind == lamellipodium) * any(kind[n] == substrate for n in VonNeumann(1)(site))
```

or, as the sketch and P6.5b do, with a model-local helper
`touches_substrate(s) = count(true for n in VonNeumann(1)(s) if kind[n] == substrate) > 0`.

**Status [probe].** On 99301437, a 6×6×4 model (Periodic, Periodic, Closed), with that rate
and with the helper form, builds and solves on the CPU. After one MCS from F = 0, F = 0.9
exactly at the lamellipodium sites touching the substrate and 0 everywhere else. This works
because field rates are lowered in the site environment with gather names
(`src/codegen.jl:798–800`). The `any(…)` and `count(…) > 0` spellings both compile.

**Unverified [inference]:**
- the same rate on a device backend (Metal Float32, ROCm), where it is a neighbour gather of
  `kind` inside the field kernel;
- the substep count for Fortuna's values (worked out in §4.B5);
- the position-gated variant (14b Eq 9 / 14c).

**P6.5c delivers:**
1. Acceptance tests that pin the form on the CPU and on the device (§4.B).
2. One AUTHORING/manual paragraph, "a source on a site predicate", in
   `docs/src/manual/equations.md`.
3. Fixes only if a test fails.

No new DSL name and no new keyword.

Phase order: by default fields run after `after_mcs` and before every `@convert`
(`src/codegen.jl:651`, D-145, D-233 "Schedule"). That is the code's order: sweep, then PDE,
then conversion (spec §2.9.6). P6.5c pins this order as it affects F (§4.B6).

### 1.C R16 analysis: MSD and modified Fürth

Home: `PottsModels.Analysis` (`lib/PottsModels/src/analysis/Analysis.jl`). D-139 item 3 says
fits and MSD live in the docs or in `PottsModels.Analysis`. These are reused by 14a, 14b,
14c, OpenVT-style motility pages and 13, so they go in the library, not one page
**[inference]**. They are plain Julia on vectors of points. No engine code, no
`Potts` dependency beyond what `Analysis` already imports.

Definitions (spec 14 §2.8, l.121–130; 14a-S1 §S1 p.2 and §S3 p.10):
- **Tracked point.** For 14 it is the nucleus centre of mass projected on xy and
  periodic-unwrapped (l.121). Extract it per saved state with the existing
  `Analysis.centroids(σ; periodic)` (`lib/PottsModels/src/analysis/graphs.jl:86–101`, which
  wraps into [1, L + 1)), then unwrap across frames with the new `unwrap_track`.
- **Eq. 1** (l.122–123): MSD(Δt) = 2D(Δt − P(1 − e^{−Δt/P})) + (2DS/(1−S))Δt, 0 ≤ S < 1.
- **Eq. 2** (l.124): τ = Δt/P, ρ² = MSD/(2DP/(1−S)), ρ² = τ − (1−S)(1 − e^{−τ}).
- **Derived** (l.125, l.130): D_fast = DS/(1−S), D_slow = D/(1−S) = D + D_fast,
  v_eff = √(D/P)/(1−S), S = D_fast/(D_fast + D).
- **Paper's fit procedure** (14a-S1 §S1, steps i–vii):
  1. compute the MSD;
  2. take its second time derivative;
  3. fit it to the second derivative of Eq. 1, (2D/P)e^{−Δt/P}, which gives D and P;
  4. subtract the S = 0 Fürth curve;
  5. fit a line to the residual, whose slope is 2D_fast;
  6. compare the result with the measured MSD;
  7. compute S = D_fast/(D_fast + D).

  The residual intercept is the localisation-error term (spec l.126; 14a-S1 §S3).

**P6.5c delivers** `unwrap_track`, `msd`, `furth_fit` with `method = :paper` (the S1
procedure, made concrete in §3.C) and `method = :lsq` (a global weighted least-squares fit of
Eq. 1), `furth_msd`, and `natural_units`. It also adds a short section to
`docs/src/manual/analysis.md`.

Deferred here: ψ_δ / velocity autocorrelation (Eqs 8–10), four-regime fits (14c Eq. 17),
polarization Π. See §5.

**MSD conventions [inference; S1 and S3 do not state them]:**
- overlapping windows (every start i ≤ n − ℓ);
- an equal-weight mean over replicas (Fig. S4: "averaged over 5 replicas").

§2, Q-4 asks the coordinator to confirm.

---

## 2. Design questions

### 2.1 initial-state-vocabulary §7.2 (l.729–770): recorded answers

| Q | Topic | Answer | Source |
|---|---|---|---|
| 1 | Shape names | GeometryBasics `HyperSphere`/`Circle`/`Sphere`/`Point`, exported. Closed membership with r·(1 + 1e-12). `Rect`, `Vec` and `Cylinder` are not imported. Index boxes stay tuples of unit ranges. **P6.5c follows it:** no `Rect`; boxes are `Fill`/`Tiling` regions | D-138 (`DECISIONS.md:2045`) |
| 2 | `into` default | No `into` until a consumer needs it. `Voronoi`/`Eden` fill medium only. Placing layers overwrite (today's behaviour). **P6.5c:** `Fill` and `Objects` overwrite earlier layers and take no `into` keyword. `Any()` is never defined | review §3 item 2 (`initial-state-review.md:118`); D-138; D-141 |
| 3 | `VoronoiBall` | Removed; `Voronoi` replaces it | D-138 |
| 4 | Periodic `Tiling` | `partial = :wrap` at P6.4d. Not P6.5c | review §3 item 4; ROADMAP P6.4d |
| 5 | Domain clipping | Shape layers clip to lattice ∩ domain and report `clipped`; `Tiling` keeps D-057's throw. **P6.5c:** `Fill` and `Objects` clip and report like `Voronoi` (box regions: out-of-domain box sites are `clipped`; a box outside the lattice throws) | D-138 "clipped" bullet and "Applied" |
| 6 | Expression defaults for created cells | Evaluated at init and for `@convert`-allocated slots. Division daughters copy the parent | D-233 ruling 5 |
| 7 | Exact vs approximate areas | Approximate (seed-and-grow idiom). 14 sizes its ball by radius; P6.5d computes r₀ | review §3 item 7 (l.126) |
| 8 | Lattice-relative coordinates | `Center()` plus explicit `Point`s; no `Rel` | D-138 bullet 2; review §3 item 8 |
| 9 | Layer `values` | Deferred (no consumer). `set_column!` is the custom-layer seam | review §3 item 9 |
| 10 | Recount | Deferred | review §3 item 10 |

### 2.2 New questions for a ruling (coordinator; none is a science question)

- **Q-1. The spelling of strict membership.** The options are a shape wrapper
  `Interior(s)` or a layer keyword (`Objects(…; open = true)`).
  - **Recommendation: `Interior(s)`.** Membership belongs to the shape, and every
    `region =`/shape argument (`Fill`, `Objects`, `RandomPoints`, `Voronoi`, `Eden`) takes it
    with no new keyword on five layers.
  - Name check **[probe]**: `Interior`, `Fill`, `Objects` and `Group` are exported by none of
    CairoMakie, Makie, GeometryBasics, ModelingToolkit, SciMLBase or Graphs. DomainSets was
    not loadable in the docs env and is unchecked (D-138 notes that it clashes on `Sphere`
    and `Point`).
- **Q-2. `furth_fit`'s default method.** The S1 procedure (`:paper`) leaves the
  differentiation scheme and the lag ranges unstated, and it is fragile on noisy MSDs: it
  fails outright on pure diffusion **[probe]**.
  - **Recommendation: default `method = :paper`.** This is faithful to the source, per
    "paper over code" and D-200.
  - `:lsq` is the documented cross-check, and the P6.5d page reports both.
  - Alternative: make `method` a required keyword.
- **Q-3. The E7 helpers** (`centroid(c, k)`, `minimum_image`, and the cluster sum, now `integral(x; over = cluster)`). D-231
  "Scope" assigns `centroid(c, k)`, `separation` and `minimum_image` to **P6.5a2**, but
  ROADMAP has no P6.5a2 row. The ergonomics review E7 says "P6.5b if small, else P6.5c".
  - **Recommendation:** file P6.5a2 now as a separate item before P6.5d, with
    `cluster_integral` for P6.7b. **Resolved 2026-10-14:** the P6.5a2 row is filed, and its tests pin the cluster sum (site scope). **Renamed 2026-10-14 (maintainer):** the cluster sum is spelled `integral(x; over = cluster)`, with plain `integral(x)` staying the cell sum; D-243 is amended and the section re-frozen. It lands before P6.5d.
  - Its write set (`src/vocabulary.jl`, codegen of cell-scope reads) is disjoint from
    P6.5c's, so the two run in parallel.
  - Not in this brief.
- **Q-4. MSD conventions.** **Recommendation:**
  - overlapping windows;
  - an equal-weight mean of per-replica time-averaged MSDs;
  - replicas of equal length (otherwise an `ArgumentError`).

  14a-S1 §S3's error estimate counts "(T − Δt)/Δt time intervals", the non-overlapping
  count. That is an error estimate, not the estimator **[inference]**.
- **Q-5. Incomplete user columns.** A custom layer may `set_column!` a model-variable column
  for only some cells. Since operating-point values override defaults, padding would silently
  override a default.
  - **Recommendation: `ArgumentError` at the end of `layout`** if any surviving cell lacks a
    value for a user column. `:cluster` is the exception: an unset cell is its own cluster.

Settled in this brief, with reasons (the reviewer may contest them):
- a nested `Group` is an error (§3.A4);
- `Group` adds no report column, since frozen row checks in `p6_1a6_layout_protocol.jl`
  compare whole rows **[inference from D-091's row schema]**;
- `layout` adds `cluster` only when some `Group`/`set_column!(…, :cluster, …)` was used, so
  every existing layout's output and every frozen pin is unchanged.

---

## 3. Public API to freeze

### 3.A Layouts (Potts; `src/layouts.jl`, exports in `src/Potts.jl`)

**A1. `Interior(s)`** (exported).
- `s` is a `HyperSphere{N}` (`Circle`, `Sphere`). Anything else is an `ArgumentError`:
  "Interior: a round shape (Circle, Sphere, HyperSphere) is required". The centre must be
  finite and the radius finite and ≥ 0, as `_shape_arg` checks (`src/layouts.jl:724–728`).
- **Membership.** Site x is inside iff `norm(center − embed(x)) < r·(1 − 1e-12)` for x or
  one of its periodic images. This mirrors D-138's closed tolerance: a site at exactly r
  (including hex sites with √3/2 rounding) is **out**. Wrapping through periodic edges,
  clipping at closed edges and the domain, the scan box, and the `clipped` count are exactly
  D-138's, with U = the index points strictly inside.
- Accepted wherever a shape is: the `Objects` shape; the `region =` of `Fill`,
  `RandomPoints`, `Voronoi` and `Eden`.
- `Interior(Interior(s))` is an `ArgumentError`.
- `r = 0` gives an empty set (`Fill` then throws, A2).

**A2. `Fill(kind; region = <whole lattice>, splits = :warn)`** (exported).
- **Paint.** It allocates one cell of `kind` and assigns it every in-domain lattice site of
  `region`, overwriting whatever earlier layers painted there. Cut cells follow the existing
  split check (D-057/D-091).
- `region`: `nothing` (every in-domain site), a shape (`HyperSphere` or `Interior`), or a
  tuple of unit ranges in lattice indices (axial on hex).
- **Report row** `:Fill`:
  - `requested = painted = 1`, `misses = 0`, `counted = 1`;
  - `clipped` follows D-138: the region's points that are not in-domain lattice sites;
  - `dropped = 1` if a later layer removes every site.
- **`ArgumentError`s:**
  - a region with **no** in-domain site: "Fill: the region has no site in the lattice's
    domain";
  - a box region outside the lattice (the existing `_region` message, `src/layouts.jl:269–276`);
  - a dimension mismatch;
  - a bad `splits`;
  - `kind` given as a vector (`Fill` paints one cell).
- `remake(f; region = …)` works.
- Deterministic and RNG-free.

**A3. `Objects(shape, points = nothing; kinds, splits = :warn)`** (exported).
- `shape` is a `HyperSphere` or an `Interior` of one.
- **Copies.**
  - Without `points`, there is one object: the shape where it is.
  - With `points` (`RandomPoints`, `Center()`, a `Point`, or a vector of `Point`s/`Center()`s,
    validated by the existing `_pattern_arg`, `src/layouts.jl:836–853`), copy k is the shape
    translated by the Cartesian vector of point k. Write templates centred at the origin.
- Ids follow copy order, and `kinds` is cycled over the copies.
- **Overlap.** It overwrites earlier layers. **Within the layer the first copy wins**: copy k
  paints only sites that no earlier copy of this layer owns (Morpheus `order`;
  initial-state-vocabulary §5.4 `resolve = :first`, l.371; no `resolve` keyword).
- **Report row** `:Objects`:
  - `requested = painted =` the number of copies; `misses = 0`; `counted = painted`;
  - `dropped` = copies left with no site after the whole layout;
  - `clipped` = Σ over copies of D-138's per-shape count. Sites lost to an earlier copy are
    not clipped.
- **`ArgumentError`s:** empty `kinds`; a shape that is not round; no points (an empty
  vector); a dimension mismatch (at `layout`); a bad `splits`.
- `remake(o; points = …)` works.
- Randomness comes only from a `RandomPoints` pattern's own seed.

**A4. `Group(layers...)`** (exported).
- It paints its children in order, exactly like `overlay`:
  - each child (nested `overlay`s flattened) is one leaf row of the report, in paint order;
  - `Group` adds no row and no column;
  - ids follow paint order.
- Every cell **allocated while one of its children paints** belongs to the group. After the
  whole layout, the group's surviving cells form one cluster.
- **Placement.** A `Group` may be the top-level layout or a member of a top-level `overlay`.
  Anywhere else is an `ArgumentError` naming the rule: inside another `Group` (directly or
  through an `overlay`), as the inner layer of `Splits`, or inside a custom layer's
  `paint!`. A custom layer groups cells with `set_column!(op, :cluster, …)`.
- `Group()` with no layers is an `ArgumentError`.
- `remake` of a `Group` is the existing "does not support remake" `ArgumentError`
  (`src/layouts.jl:1521–1522`).

**A5. `set_column!(op::LayoutState, name::Symbol, id::Integer, value)`** (public, not exported).
- It records `value` for cell `id` of the paint so far.
  - `id` must be allocated (`1:ncells(op)`). Otherwise the `ArgumentError` names the id and
    `ncells`.
  - `name ∈ (:ownership, :kind)` is an `ArgumentError`.
  - Setting a cell twice overwrites its value.
- **`:cluster`.** The value is a label compared with `isequal`. Cells with equal labels form
  one cluster. A `Group`'s label never equals any user label.
- **Other names.** They are cell columns for the operating point, emitted as `name => values`.
  This includes model cell variables such as `:V_target`, though 14 uses kind defaults
  instead.

**A6. `layout` output** (amends `src/layouts.jl:1699–1771`; reports unchanged).
`layout(l, x)` returns
`[ownership => σ, kind => kinds, (cluster => ids)?, (name => values)…]`:
- **`cluster`** is present iff some cell got a cluster label (by `Group` or `set_column!`).
  - `ids[c]` is the final id of the lowest-id surviving cell with the same label.
  - An unlabelled cell gets its own final id.
  - So `ids` are valid "any ids" for `PottsProblem` (`src/problem.jl:82–83`), and on a
    layout with one `Group` first, the group's cells read `1`.
- **User columns.** One entry per name, in order of first `set_column!`. Values are compacted
  with the cells, since dropped cells are removed (`src/layouts.jl:1793–1800`). Element type:
  `identity.` of the values. An incomplete column is the Q-5 `ArgumentError`, naming the
  column and the missing cells' final ids.
- A layout with neither returns exactly today's two entries, byte for byte.
- `report = true` returns `(point, rows)` with rows unchanged in schema.

**A7. Kinds check.** `_layer_kinds` (`src/layouts.jl:1752–1757`) covers `Fill`, `Objects`
and `Group`, so `layout(…, sys)` rejects a kind class (D-135) before painting.

**A8. Docs recipes (D-087)** in `docs/src/manual/layouts.md`. Both use the R = 15 values
L = 120, L_z = 31, c = (61, 61, 16):
- Plane: `Fill(:lid; region = (1:L, 1:L, Lz:Lz))`.
- Spheres: `Objects(Interior(Sphere(Point(0.0, 0.0, 0.0), r)), centres; kinds = [:cell])`, or
  `Sphere(…)` for the closed rule.
- The Fortuna start (code geometry, integer R):

```julia
c    = (L ÷ 2 + 1, L ÷ 2 + 1, R + 1)              # our z = R + 1 ⇒ bottom layer z = 2
body = Group(Objects(Interior(Sphere(Point(Float64.(c)...), Float64(R))); kinds = [:cytoplasm]),
             Fill(:nucleus; region = map(a -> (a - 3):(a + 2), c)))      # 6³, offsets −3…+2
op   = layout(overlay(body, Fill(:substrate; region = (1:L, 1:L, 1:1)),
                            Fill(:lid; region = (1:L, 1:L, Lz:Lz))), sys)
```

**Determinism, 2D/3D/hex (all of A).**
- Painting is host-only and single-threaded. It is deterministic in (layout value, lattice),
  whatever the backend.
- `Fill` and `Objects` are N-dimensional (1D–3D).
- Shapes use the Cartesian embedding and so are round on hex (D-138). Box regions are axial
  indices, a rhombus on hex.
- Periodic axes wrap shapes; closed edges and the domain clip them.

### 3.B Predicate-sourced PDE

No new API. The contract to pin:
- A field rate may multiply any term by a site predicate built from `kind`, neighbour folds
  over a relation of `site` (`any(… for n in R(site))`, `count(… for n in R(site) if …)`),
  site variables and model-local helper functions of `site`.
- The predicate is evaluated on the σ seen by the field phase at each substep. σ does not
  change between substeps, since fields run between sweeps.
- Out-of-lattice neighbours on closed axes are skipped, and periodic axes wrap, as for every
  gather.
- The source is not confined: diffusion and decay act on the whole lattice (spec l.175–176).
- Explicit Euler with n substeps of `dt/n` (`lib/CorePotts/src/fields.jl:207–222`).
  - The count is `max(requested, stable_substeps(D, dt, h, k))`, with k the bound on
    |∂rate/∂F| (`src/codegen.jl:1535–1565`).
  - With one substep the update is F ← F + D·ΔF − k_d·F + k_s·[pred], i.e. "diffuse + decay,
    then secrete" as in CC3D, so F → k_s/k_d at a persistent source (spec l.170–176).
- Device: the same rate runs on Metal (Float32) and ROCm in the generated field kernel, with
  no host round trip in a quiet MCS.

### 3.C Analysis (`PottsModels.Analysis`, exported from the submodule)

`T` below is `Float64`. A point is an `NTuple{N, <:Real}` (what `centroids` returns) or an
`AbstractVector` of length N.

**C1. `unwrap_track(points, dims; periodic) -> Vector{NTuple{N, Float64}}`.**
- `out[1] = points[1]`, and `out[k] = out[k−1] + w(points[k] − points[k−1])`. Here w is the
  identity on non-periodic axes and, on a periodic axis d, the minimum image in
  `[−dims[d]/2, dims[d]/2)` (ties to the lower image, D-141's convention).
- `periodic`: one `Bool` per axis, or one `Bool` for all.
- **Precondition (documented, not detected):** a true displacement between consecutive
  samples is below half the period. For 14, sampling every 50 MCS at ≤ 0.2 sites/MCS gives
  ≤ 10 sites, far below 60.
- **`ArgumentError`s:** an empty track; mixed point dimensions; `length(dims)` or
  `length(periodic)` ≠ N; a non-positive period.

**C2. `msd(tracks; lags = 1:(n − 1)) -> Vector{Float64}`.**
- `tracks` is one track (a vector of points) or a vector of tracks of equal length n.
- For each lag ℓ (in samples), MSD(ℓ) is the mean over tracks of
  (1/(n − ℓ)) Σ_{i=1}^{n−ℓ} |x_{i+ℓ} − x_i|², summed over all components of the points.
- Pass xy-projected points for 14.
- Times are `ℓ · Δt_sample`, applied by the caller.
- **`ArgumentError`s:** ℓ < 1 or ℓ ≥ n; unequal track lengths; no track; mixed dimensions.
- O(n·|lags|) per track.

**C3. `furth_msd(Δt; S, D, P)`.** Eq. 1, elementwise. `ArgumentError` unless 0 ≤ S < 1,
D ≥ 0, P > 0.

**C4. `natural_units(Δt, m, fit) -> (τ, ρ²)`.** τ = Δt/P and ρ² = m/(2DP/(1−S)) (Eq. 2).
`fit` is any object with fields `S`, `D`, `P` (a `furth_fit` result or a NamedTuple).

**C5. `furth_fit(Δt, m; method = :paper, range = nothing, short = nothing, offset = true)`**
returns a NamedTuple
`(; S, D, P, D_fast, D_slow, v_eff, offset, method)`.

Inputs: `Δt` (positive, strictly increasing) and the matching `m`. On all lags:
- an `ArgumentError` for length < 4, non-finite values, or a non-increasing `Δt`;
- `m ≤ 0` is allowed for `:paper` but is an `ArgumentError` for `:lsq`, which uses relative
  weights.

**`method = :paper`** (14a-S1 §S1; the scheme details are **[inference]**, stated so they can
be frozen):
1. `Δt` must be uniformly spaced, h = Δt₂ − Δt₁, within a relative 1e-9; otherwise an
   `ArgumentError`.
2. Second differences d_i = (m_{i+1} − 2m_i + m_{i−1})/h² at the interior lags. The default
   `range` is all interior lags; the keyword takes a `(lo, hi)` range of Δt values.
3. Keep the d_i > 0. An ordinary least-squares fit of log d_i = c₀ + c₁Δt_i gives
   P = −1/c₁ and D = e^{c₀}·P/2. With fewer than 3 positive d_i, or c₁ ≥ 0, it throws an
   `ArgumentError`: "furth_fit: no decaying second derivative (persistence not resolved);
   try method = :lsq".
4. The residual r_i = m_i − furth_msd(Δt_i; S = 0, D, P) over `short`. The default is
   Δt ≤ P (S1's "short Δt"), with at least 2 points; otherwise the first 2 lags.
5. An ordinary least-squares line r = 2D_fast·Δt + c (c = 0 when `offset = false`). This
   gives D_fast as it falls, unclamped, and `offset = c`.
6. S = D_fast/(D_fast + D), D_slow = D + D_fast, v_eff = √(D/P)/(1−S).

**`method = :lsq`:**
- For fixed P, Eq. 1 (+ c) is linear: m ≈ a·g(Δt; P) + b·Δt (+ c), with
  g = Δt − P(1 − e^{−Δt/P}).
- Solve min Σ ((model − m)/m)² with a ≥ 0 and b ≥ 0 (enumerate the active sets; c free).
- Over log P ∈ [log(Δt₁/10), log(100·Δt_end)]:
  - take a 200-point log grid;
  - refine the best bracket by golden section to a relative 1e-10;
  - ties go to the smaller P.
- Then D = a/2, D_fast = b/2, D_slow = (a + b)/2, and S = b/(a + b) (`NaN` if a + b = 0).
- **Report D_slow from (a + b)/2 directly.** Do not compute it as D/(1−S), which loses all
  precision as S → 1 **[probe]**.

Both methods are deterministic (no RNG).

**Units.** The functions are unit-agnostic. Table 2 reports D in R_cell²/MCS: the P6.5d page
divides positions by R before calling `msd`.

---

## 4. Acceptance criteria

Suggested frozen files:
- `lib/PottsModels/test/acceptance/p6_5c_initial_state.jl` (A);
- `p6_5c_predicate_source.jl` (B);
- `p6_5c_msd_furth.jl` (C).

Style and precision follow `p6_5b_convert.jl`: a header with the API as in §3, hand-checked
counts, and an oracle plus a negative control per mechanism (D-048). Per AUTONOMY §7.2 the
author runs every file against a stub of the promised shape and re-derives every count below
before freezing. The counts here were computed by **[probe]** scripts with the exact
membership rule of §3.A1.

### 4.A Initial state

**A1. Strict vs closed membership, hand counts** (centre on a site, lattice large enough,
closed):

| Case | `Interior` | closed shape (today) |
|---|---|---|
| 2D square, r = 1 | 1 | 5 |
| 2D square, r = 2 | 9 | 13 |
| 2D square, r = 3 | 25 | 29 |
| 2D square, r = 5 | 69 | 81 |
| 3D cubic, r = 1 | 1 | 7 |
| 3D cubic, r = 2 | 27 | 33 |
| 3D cubic, r = 3 | 93 | 123 |
| hex, r = 1 (centre = `embed` of a site) | 1 | 7 |
| hex, r = √3 | 7 | 13 |
| hex, r = 2 | 13 | 19 |

Negative control: the closed column must differ.

**A2. Clipping and wrap.**
- `Fill(:a; region = Circle(Point(1.0, 1.0), 2.0))` on a closed 5×5:
  - 6 sites, `clipped = 7`;
  - periodic 5×5: 13 sites, `clipped = 0`.
- The `Interior` version: 4 sites with `clipped = 5` closed; 9 sites with `clipped = 0`
  periodic.
- A domain-masked lattice: sites outside the domain are never painted and count as
  `clipped`.
- A box `Fill` reaching beyond the lattice throws (§3.A2).

**A3. `Fill` basics.**
- 2D 10×10: `Fill(:w; region = (1:10, 1:1))` gives one cell of 10 sites, row
  `(type = :Fill, requested = 1, painted = 1, dropped = 0, misses = 0, counted = 1, clipped = 0, splits = 0)`.
- `Fill(:bg)` with no region owns all 100 sites.
- `overlay(Fill(:bg), Fill(:w; region = (1:10, 1:1)))` gives the background 90 sites and
  id 2 = `:w`.
- Overwrite and split:
  - `overlay(Fill(:a; region = (1:10, 4:6)), Fill(:b; region = (5:5, 1:10)))` cuts `a` in
    two. It warns (the existing message) and the row `splits = 1`.
  - With `splits = :allow` on the `b` layer it does not warn.
- Errors: a region with no in-domain site; a `kind` vector; a bad `splits`.

**A4. `Objects` basics** (2D, closed, 10×8):
- `Objects(Interior(Circle(Point(0.0, 0.0), 2.0)), [Point(3.0, 3.0), Point(5.0, 3.0)]; kinds = [:a, :b])`:
  - cell 1 (`:a`) has 9 sites (the 3×3 block x 2:4, y 2:4);
  - cell 2 (`:b`) has 6 sites (x 5:6, y 2:4);
  - the shared column x = 4 stays with copy 1 (first wins);
  - row `requested = painted = 2`, `clipped = 0`.
- Swapping the points swaps the winner. Negative control: a last-wins implementation fails.
- The `Objects` layer overwrites an earlier `Fill(:bg)` on the 15 painted sites; the
  background keeps 65.
- No `points`: `Objects(Interior(Circle(Point(5.0, 5.0), 3.0)); kinds = [:c])` gives one cell
  of 25 sites.
- A copy entirely off a closed lattice is `dropped = 1`.
- Random points: `Objects(shape, RandomPoints(3; seed = 7); kinds)` is reproducible, and
  `remake(…; points = RandomPoints(3; seed = 8))` changes it.
- 3D: `Objects(Interior(Sphere(Point(0.0, 0.0, 0.0), 2.0)), [Point(5.0, 5.0, 5.0)]; kinds = [:s])`
  has 27 sites.
- Hex: an `Objects` disc of r = √3 at a site has 7 sites.

**A5. `Group` and `cluster`.**
- (a) On 2D 10×10:

  ```julia
  overlay(Group(Objects(Interior(Circle(Point(5.0, 5.0), 3.0)); kinds = [:cyto]),
                Fill(:nuc; region = (5:6, 5:6))),
          Fill(:wall; region = (1:10, 1:1)))
  ```

  - ids: `cyto` 1 (25 − 4 = **21** sites), `nuc` 2 (**4**), `wall` 3 (**10**);
  - `cluster => [1, 1, 3]`;
  - members are in declared order;
  - the report has 3 rows (`:Objects`, `:Fill`, `:Fill`) with unchanged schema.
- (b) `overlay(Fill(:wall; …), Group(…))` gives ids wall 1, cyto 2, nuc 3, and
  `cluster => [1, 2, 2]`.
- (c) Two groups, `overlay(Group(A1, B1), Group(A2, B2))` on disjoint regions:
  `cluster => [1, 1, 3, 3]`.
- (d) A group whose first member is fully overwritten. In
  `Group(Fill(:a; region = r), Fill(:b; region = r))`, `a` is dropped, `b` becomes id 1, and
  `cluster => [1]`.
- (e) A layout with no `Group` returns exactly two entries (regression: compare with today's
  output for one `Tiling` and one `Voronoi` case, byte for byte).
- (f) Errors: `Group()`; `Group(Group(…))`; `Group(overlay(Group(…)))`;
  `Splits(Group(…), 1)`; a `Group` inside a custom layer's `paint!`.
- (g) With a compartment model (any model with a `cluster[owner] == cluster[owner′]` contact
  term, as `P65bFortuna`, `p6_5b_convert.jl:735–764`):
  - `PottsProblem(sys, layout(…), tspan)` builds with no hand-written `cluster`;
  - the partition of cells into clusters equals the layout's;
  - the root ids may differ (`prefer`), so do not compare ids.

  With a model without compartments, the existing `ArgumentError`
  ("`cluster` in the operating point, but the model uses no compartments",
  `src/problem.jl:779`) is raised **[probe]**.
- (h) `set_column!`:
  - a custom layer setting `:cluster` labels `:x, :x, :y` on three cells gives
    `cluster => [1, 1, 3]`;
  - a custom layer setting `:V_target` on all its cells emits `:V_target => values`, and
    `PottsProblem` uses them over the kind default (as `p6_5b_convert.jl:791–792` shows for a
    hand op);
  - setting it on 2 of 3 cells is the Q-5 `ArgumentError`;
  - `set_column!(op, :kind, …)`, an unallocated id, and a call outside `paint!` are errors.

**A6. The 14 geometry case** (the code geometry, integer R; lattice (Periodic, Periodic,
Closed); the A8 recipe; layout order Group(cyto, nucleus), substrate, lid):

| Quantity | R = 10 (80×80×21) | R = 15 (120×120×31) |
|---|---|---|
| ball centre (ours) | (41, 41, 11) | (61, 61, 16) |
| `Interior` ball sites | **4139** | **13997** (= spec l.159) |
| ball z-range | 2:20 | 2:30 |
| ball sites at z = 2 (contact disc, x² + y² < 2R − 1) | **61** | **89** |
| nucleus box | (38:43, 38:43, 8:13) | (58:63, 58:63, 13:18) |
| nucleus sites (wholly inside the ball) | 216 | 216 |
| cytoplasm sites | **3923** | **13781** (= spec l.629) |
| substrate (z = 1) / lid (z = L_z) | 6400 / 6400 | 14400 / 14400 |
| cytoplasm sites at z = 1 or z = L_z | 0 | 0 |
| ids, kinds | 1 cytoplasm, 2 nucleus, 3 substrate, 4 lid | same |
| `cluster` | [1, 1, 3, 4] | [1, 1, 3, 4] |
| split warnings / `dropped` | none / 0 | none / 0 |

- **Negative control:** the closed `Sphere` in place of `Interior`:
  - R = 10: 4169 ball sites, with z-range 1:21 (one site each on the substrate and lid
    planes);
  - R = 15: 14147 ball sites, z-range 1:31;
  - after the planes overwrite them, cytoplasm 3951 (R = 10) and 13929 (R = 15);
  - so the cytoplasm count distinguishes the two rules.
- **Non-integer form** (the audited ruling's arithmetic, P6.5d's choice; include as one case
  so non-integer centres and radii are covered):
  - R = 15, φ_n = 0.15, φ_l = 0.05, V = (4π/3)·15³ = 14137.17;
  - r₀ = ∛((0.8V + 216)/(4π/3)) = 14.012856, centre (61, 61, r₀ + 1);
  - `Interior` ball **11512** sites, z-range 2:29, **89** sites at z = 2;
  - the closed rule gives 11513: it adds the one point at distance exactly r₀ on z = 1, which
    `Interior`'s tolerance excludes even though (r₀ + 1) − 1 ≠ r₀ in Float64;
  - for φ_l = 0.30: r₀ = 12.402584, 7980 sites, 69 at z = 2.
- **Kinds/targets.** Building `PottsProblem` on a Fortuna-shaped model (kinds `medium
  substrate[frozen] lid[frozen] cytoplasm lamellipodium nucleus`, `V_target` kind default as
  the sketch, l.47–48) from this layout alone gives:
  - cytoplasm `V_target` = (1 − φ_n − φ_l)·V;
  - nucleus `V_target` = φ_n·V;
  - no lamellipodium cell;
  - one cluster {cytoplasm, nucleus}.
- **Hex and 2D analogues.** A 2D "cell on a substrate line" (`Interior(Circle)` tangent to
  y = 1, `Fill` row y = 1) reproduces the strict count from the A1 table at the matching r.

**A7. Determinism and laziness.**
- Two `layout` calls give identical results.
- The result is independent of the thread count.
- No layer allocates per-site storage beyond σ for `Fill`/`Objects`. This is an
  informational check, not a timing check: `Objects` with 10⁴ copies of
  `Interior(Sphere(…, 2.0))` at `RandomPoints` on 200³ finishes. It scans per-copy bounding
  boxes, O(Σ bbox), not O(sites × copies) **[inference: cost]**.

### 4.B Predicate-sourced PDE

**Fixture P** (exact binary arithmetic, so CPU Float64, CPU Float32 and the device agree
bitwise):
- 6×6×4, boundary (Periodic, Periodic, Closed), `VonNeumann(1)`;
- kinds `medium substrate[frozen] lam`;
- σ: substrate = all of z = 1 (36 sites); `lam` = box (2:3, 2:3, 2:3) (8 sites, 4 at z = 2);
- copies are blocked by `@constraint mobile > 0.5` with `mobile = 0` (the P6.5b trick,
  `p6_5b_convert.jl:757`), so σ is constant;
- `@equations D(F) ~ D_F*Δ(F) - k_d*F + k_s*(kind == lam)*any(kind[n] == substrate for n in VonNeumann(1)(site))`;
- k_d = k_s = 0.5, F₀ = 0, `field_solver = ExplicitEuler(substeps = 1)`.

**B1. Gating, D_F = 0.**
- After n MCS, F = 1 − 0.5ⁿ at the 4 source sites (0.5, 0.75, 0.875) and exactly 0 at the
  other 4 `lam` sites, the medium and the substrate.
- ΣF = 4(1 − 0.5ⁿ).
- **[probe]** shows the analogue with 0.9 on this fixture shape.

**B2. Mass balance with diffusion.**
- D_F = 0.0625 (auto substeps: ceil((0.0625·12 + 0.5)/1.8) = 1). The total obeys
  ΣF_{n+1} = (1 − k_d)ΣF_n + k_s·N_src exactly, so ΣF = 4(1 − 0.5ⁿ) as in B1: diffusion
  conserves mass. This assumes that closed axes without `@boundary` are zero-flux
  **[inference; the test author confirms on the freeze base]**.
- The field is nonzero beyond the `lam` box (not confined).
- No F leaves through z = 1 or z = 4 (closed). Compare with a hand-rolled 7-point stencil
  oracle on the same arrays, bitwise.

**B3. Negative controls.**
- (a) `lam` moved to (2:3, 2:3, 3:4), so no site touches the substrate: ΣF ≡ 0 for all n.
- (b) The kind-only source `k_s*(kind == lam)` gives ΣF = 8(1 − 0.5ⁿ), so the predicate
  must matter.
- (c) Periodic z with `lam` at z = 4 only: the top layer touches the substrate through the
  wrap, giving ΣF = 4(1 − 0.5ⁿ). The same fixture with closed z gives 0.

**B4. Spellings.**
- The `count(…) > 0` helper form (`touches_substrate(s)`, as in `p6_5b_convert.jl:750`)
  gives fields identical to the `any` form.
- A position-gated source `k_s*(kind == lam)*(position[3] == 2)` gives the same field on
  Fixture P. This variant is expected to pass already; if `position` is not readable in a
  field rate, that is in scope **[inference]**.

**B5. Fortuna values** (D_F = 1e-4, k_d = k_s = 0.9, 3D, h = 1, dt = 1):
- `stable_substeps(1e-4, 1, (1,1,1), 0.9) = ceil(0.9012/1.8) = 1`, so the requested
  `substeps = 1` is honoured. Pin the substep count if it is publicly readable; otherwise pin
  its effect.
- A site that becomes a source with all-zero neighbours holds F = 0.9 after one MCS. Then
  0.99 and 0.999 with D_F = 0 (spec l.174).
- With D_F = 1e-4, F at an interior source site of a source sheet is within 1e-3 of
  0.9/(0.9 + k·D_F), k the number of non-source face neighbours (spec l.174: 0.99978 at
  k = 2).

**B6. Phase order with `@convert`.**
- Extend Fixture P with a compartment model: a `cyto` cell on z = 2 clustered with the
  `lam` cell, and a P6.5b-style `@convert … clusters(cyto)` with `to = sibling(lam)`,
  `at` = touches substrate, p = 1, and the default schedule.
- In the MCS where a site converts, its F at the end of that MCS is 0: fields ran before the
  conversion.
- After the next MCS it is 0.5, from k_s = 0.5.
- Moving the convert before `fields` in `@schedule` gives 0.5 in the converting MCS
  (negative control; D-145 placement).

**B7. Device** (`POTTS_GPU=metal|rocm`, the `p6_5b_convert.jl:890–927` pattern; Float32):
- Fixture P with B1, B2 and B3(a) on the device is **bitwise** equal to the CPU Float32 run
  after 5 MCS.
- A quiet MCS has 0 syncs, 0 transfers and 0 bytes.
- `@test_skip` without a device.

**B8. Fingerprints.** Models without a field keep their pinned fingerprints. No generated
sweep code changes (§4.D).

### 4.C MSD and Fürth

**C1. `unwrap_track`.**
- A 2D, 10-wide periodic x axis: points x = 8, 9, 10, 1, 2 (y fixed). They unwrap to
  8, 9, 10, 11, 12.
- The non-periodic axis is unchanged.
- Negative control: `periodic = false` gives 8, 9, 10, 1, 2.
- A half-period jump (+5 on width 10) maps to −5 (the `[−L/2, L/2)` convention).
- **Integration.** A σ series in which a 2×2 box cell moves +1 in x per frame for 15 frames
  on a 10-wide periodic lattice. `centroids(σ; periodic = (true, false))` then `unwrap_track`
  gives x increasing by exactly 15 in total.

**C2. `msd`, by hand.**
- Track (0,0), (1,0), (3,0), (6,0): MSD(1) = (1 + 4 + 9)/3 = 14/3, MSD(2) = (9 + 25)/2 = 17,
  MSD(3) = 36.
- Two tracks, that one and its mirror (0,0), (−1,0), (−3,0), (−6,0): the same values (equal
  weights).
- Ballistic x_k = (k, 0): MSD(ℓ) = ℓ² exactly.
- Errors: ℓ = 0, ℓ = n, unequal lengths.

**C3. Eq. 1/2 identities.**
- `natural_units` of `furth_msd` output satisfies ρ² = τ − (1−S)(1 − e^{−τ}) to 1e-12
  relative.
- From the returned fields, D_slow == D + D_fast and S == D_fast/(D_fast + D) to 1e-12.

**C4. Noise-free oracle**, Δt = 1:2000, S = 0.1, D = 0.5, P = 100, m = `furth_msd`:
- `:paper` recovers S, D and P to a relative 1e-3, with `|offset| < 1e-2`
  (**[probe]**: 2e-4, 2e-5, 2e-6, offset 1.4e-3).
- `:lsq` recovers them to a relative 1e-6. A 4001-point grid without refinement gave only
  1.5e-3 **[probe]**, so the refinement is load-bearing.
- **Ballistic** m = (0.3Δt)²:
  - `:lsq` gives S ≤ 1e-6 (a, b ≥ 0) and P at the upper bound (≥ 100·2000);
  - v_eff = 0.3 within 0.5 % (**[probe]** 0.085 %; S came out −1.6e-8 without b ≥ 0, so the
    constraint is load-bearing);
  - `:paper` also returns P ≥ 10·Δt_end, or throws; the test pins one of the two.
- **Pure diffusion** m = 1.4·Δt:
  - `:lsq` gives D_slow = 0.7 within 1e-6;
  - S and P are **not identifiable**, since a linear MSD is P → 0 or S → 1, so do not assert
    them. **[probe]**: D/(1−S) gave 0.729, which is why D_slow is (a + b)/2.
  - `:paper` throws the "persistence not resolved" `ArgumentError`. **[probe]**: without the
    check it returned P < 0.

**C5. Stochastic oracle** (D-048; tolerances provisional, to be calibrated by the test author
on a seed grid and recorded in the freeze entry):
- **Generator, 2D**, time unit = one sample, δ = 1. Per axis:
  - an Ornstein–Uhlenbeck velocity with variance D/(2P) and correlation time P (exact AR(1)
    update, coefficient e^{−1/P});
  - position x ← x + v·δ, plus independent Brownian increments of variance D_fast·δ;
  - D_fast = DS/(1−S);
  - so E[MSD] is Eq. 1 up to O(δ/P) = 1 %.
- S = 0.1, D = 0.5, P = 100 samples; 64 tracks of 2·10⁴ samples.
- **Targets:** `:lsq` over lags ≤ 400 recovers D and P within ±10 % and S within ±0.02;
  `:paper` within ±20 %, ±20 % and ±0.04.
- **Negative controls:** S = 0 data gives S < 0.02; shuffling the sample order destroys the
  fit (fitted P < 2·Δt_sample).
- `StableRNG` throughout.

**C6. Paper numbers sanity (not a target).** `natural_units` accepts any object with fields
`S`, `D`, `P`. With Table 2's R = 15, φ = 0.10, λ = 150 row (P = 6878, D = 2.83e−4,
S = 9.68e−3), it divides m by 2DP/(1−S) = 3.931 (to 4 digits) and gives τ = Δt/6878. The
printed last column is 1.98: that is the spec's B5 inconsistency (l.496). This guards the
formula, not the table.

### 4.D Cross-cutting and performance

- **Guardrails.** No new DSL name or keyword (`DSL_NAMES`/`DSL_KEYWORDS` unchanged; the
  snapshot test stays green). ExplicitImports, Aqua and JET are clean. New exports appear in
  `src/Potts.jl`. `set_column!` is `public`. `docs/make.jl` builds, and the API page lists the
  new names.
- **Docs check** (pinned, like D-176's wording tests):
  - `docs/src/manual/layouts.md` contains a `Fill(` plane recipe, an `Objects(` sphere
    recipe and a `Group(` compartment example;
  - its built-in-layers table lists `Fill`, `Objects` and `Group`;
  - `docs/src/manual/analysis.md` names `msd` and `furth_fit`.
- **Performance (D-242).** Parts A and C change no generated sweep code; they are front-end
  or analysis-only. So **no A/B**, only the suites and CI, and the frozen tests pin unchanged
  fingerprints. Part B: if it needs no code, no A/B. If the device test forces a change in
  field codegen, that is a device-code change confined to the field path, so a CPU **and**
  ROCm A/B on a short field-model case set (the Merks cases), batched per D-242.
  `benchmark/gate.jl` stays allocation-clean.
- **Load time.** `using Potts` is not measurably slower: no new dependency. Fürth fitting
  needs only LinearAlgebra in `PottsModels`, so nothing new is added (AUTONOMY §4 would
  allow it anyway).

---

## 5. Out of scope and later items

| Item | Where | Why |
|---|---|---|
| `centroid(c, k)`, `minimum_image`, `separation`, `integral(x; over = cluster)` (ergonomics E7; formerly `cluster_integral`) | **P6.5a2** (D-243, amended 2026-10-14), before P6.5d. The `sites(cluster)` fold later | DSL/codegen, a disjoint write set |
| Π_CN−N polarization (14b Eq 10), the lamellipodium–nucleus distance (14a Fig 12), `dcm_F_CN` | P6.5d page code on P6.5a2 helpers | model observables |
| ψ_δ / velocity autocorrelation (14a Eqs 8–10; B6's overlap with MDA-MB-231) | P6.5d page, or an R16 follow-up | not in the ROADMAP row |
| Four-regime MSD fit (14c Eq. 17), drift V_d, θ histograms | P6.7b | 14c |
| Hemisphere, annulus, one-voxel ring (14c-code IC), `Where(f)` predicate regions (as in the ergonomics E1 `region = z == 1`), `Rect`/`Rotated`/`Ellipsoid` | P6.7b / P6.6 / P6.8 per initial-state-review §4 | no 14a consumer; D-138 kept `Rect` out |
| `into`, `shortfall` on `Fill`/`Objects`, `resolve = :nearest`, layer `values` | later consumers | review §3 items 2, 9 |
| Exact-volume balls (`Eden(…; volume)`) | none | review §3 item 7 |
| Saving only a tracked point during a 10⁵-MCS run (full σ every 50 MCS at 120×120×31 is ≈ 1.8 MB × 2000 per run **[inference]**) | P6.5d (integrator loop reading a cell-scope `@observed` centroid), or P6.E8 "everyday observables" | I/O, not R16 math |
| Choosing r₀, the nucleus position for a non-integer centre, and L per R | P6.5d (spec l.627–631) | model arithmetic |
| `Splits`/custom layers inside `Group` | a later consumer (13's `Chain` emits cluster itself, P6.6) | §3.A4 |

---

## Appendix: design text that disagrees with spec 14's audited rulings

For the coordinator (not test content):
1. **api-synthesis's Fortuna example** (`api-synthesis.md:990–1023`). It uses `V = 4.19R^3`,
   a `Spheres` ball of radius R, cytoplasm `V_target = floor(0.85V) + 0.5`,
   `order = Shuffled()`, and the 1.5/1.0 `V_target` transfer. The audit (spec l.627–631)
   rules V = (4π/3)R³, fixed targets with no transfer, the paper p, and a ball sized to
   ≈ (1 − φ_n − φ_l)V + 216.
2. **initial-state-vocabulary §7.1 S7** (l.720). Its accept line reads "ball of radius R
   tangent to z = 1". The ruling sizes the ball to the cytoplasm target, so radius R is the
   code variant only.
3. **ergonomics-review E1/E3** (l.46, l.50, l.81).
   - The default `ifelse(kind == nucleus, φ_n, ifelse(kind == lamellipodium, 0.0, 1 − φ_n))`
     gives the cytoplasm (1 − φ_n)V and the lamellipodium 0. The ruling fixes them at
     (1 − φ_n − φ_l)V and φ_l·V from t = 0.
   - `p = c·(1 − volume[to]/V_target[to])` differs from the ruling's p with the parameter
     φ_l·V_cell (spec l.100, l.626).
   - `region = z == 1` needs `Where(f)`, which is deferred.
4. **D-138's closed shape membership** against spec l.159 ("a port's `Spheres` must use
   strict `<`"). This is not an error in D-138, but no existing shape can express the code
   ball, hence `Interior`.
5. **Spec 14 §8 table** (l.543): "**Sequential** conversion with running volume updates is
   required". This contradicts its own §9 ruling and D-233 for 14a. The row is about 14c's
   gate, which D-233 leaves open.
6. **AUTHORING.md:1265–1266** still lists "Spheres, … Plane" as planned named layers,
   contrary to D-087.

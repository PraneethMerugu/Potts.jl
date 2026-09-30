# Audit: edge cases, correctness and polish (2026-09-29, at a6b8995)

Five read-only reviews covered:
- CorePotts numerics;
- the Potts front end and compiler;
- lowering and codegen;
- problems, the SciML surface and units;
- docs, PottsModels, MakiePotts and coverage.

Every item has a repro script, except those marked *(read)*, which come from reading the code. The HIGH items were re-run independently before this file was written. Scratch scripts are in `/tmp/audit_{core,front,codegen,sciml,docs}/`; they are not in the repo.

Severity:
- **HIGH**: a silently wrong result, memory unsafety, or a documented core feature that does nothing.
- **MED**: a crash or misleading error on reachable input, or a feature gap with a workaround.
- **LOW**: polish.

IDs are stable, so fix commits cite them as `A-xx`.

---

## 1. Hexagonal lattices (2D): silently wrong today

Hex runs without error everywhere below. Nothing rejects these cases.

| ID | Where | Problem | Fix |
|----|-------|---------|-----|
| A-01 **HIGH** | `CorePotts/drives.jl:84-160` | `locally_connected` builds a 3×3 face-adjacency patch and `merks_connectivity` walks the 8-site `_MERKS_RING`. Both assume square geometry. On hex, `(1,1)` and `(-1,-1)` are counted as neighbours, and the adjacent pair `{(1,0),(0,1)}` is judged disconnected. Every `connectivity(...)` constraint is affected, including Akeeb and Merks-style models. | A per-geometry ring. On hex, walk the 6 neighbours in angular order and accept the copy iff the losing cell's sites form a single arc. `merks` uses the same arc rule. |
| A-02 **HIGH** | `lower.jl` `position`; gather anchor `coordinates` | `position` returns axial `(q, r)`, and anchors use raw coordinates. A drive `-χ*position[1]` or a radial cue is sheared by 60°. | Split them: `position` becomes Cartesian (`embed`), and a new `lattice_index` returns the integer coordinates. Anchors that compute distances embed. |
| A-03 **HIGH** | `CorePotts/relationships.jl:75-86`, `compartments.jl:213-216` | `_periodic_norm` takes the minimum image per axis in axial coordinates. On the skewed torus the true nearest image can be the diagonal one: `(8,8)` on 20² gives 13.86 instead of 10.58. This affects link distances, cluster bias and `centroid_distance`. | Minimise over the 3×3 (2D) image set after embedding. |
| A-04 MED | `CorePotts/fields.jl` | The hex `_laplacian` ignores Dirichlet `bc` values (it silently uses zero flux) and uses only `h[1]`. Potts doesn't expose `bc`, so only hand-written CorePotts models are affected. | Honour `bc` in `_HEX6`. Error if `h` is anisotropic on hex. |
| A-05 MED | `CorePotts/lattice.jl` domain predicates, `Weighted` | Domain predicates and `Weighted` weight functions receive axial offsets. `Weighted(Hex(1), 1/|o|)` gives 0.707 to two unit-distance neighbours, and a circular domain comes out elliptical: max embedded radius 9.5 against a boundary radius of 6. | Pass embedded coordinates, or document axial input and give an `embed` helper. Embedding is recommended. |
| A-06 MED | `CorePotts/piff.jl` | PIFF read/write has no geometry, so a hex state round-trips as square. | Write a geometry header, and reject a mismatch on read. |
| A-07 **HIGH** | `MakiePotts/src/potts_saved_state.jl:1-26` | Hex states are drawn as sheared squares with no warning, yet ROADMAP ticks M2.1b. | Hex glyph rendering via `embed`, or an error. Un-tick M2.1b until then. |
| A-08 | lowering/codegen | Everything else in codegen embeds correctly (§4). `position` is also unusable on every geometry (A-66). | |

### 1a. 3D hexagonal lattices: feature gap

Today `Lattice(...; geometry = Hexagonal())` with `N = 3` errors with "hexagonal lattices are 2D" (`lattice.jl:42`). What 3D hex touches:
- `embed` / `embed_covariance` for N = 3;
- relations and shells (`Hex(k)`, Ball, NeighborOrder);
- 3D `principal_axis` and shape embedding;
- `_periodic_norm` (the 3×3×3 image set);
- the Laplacian stencil;
- connectivity (A-01 in 3D);
- MakiePotts.

Candidate geometries:
- **Hexagonal prism** (hex layers stacked straight; 6 in-plane + 2 axial = 8 neighbours). Axial coordinates extend to `(q, r, z)`. Every relation is still one static offset list, and the Laplacian is `_HEX6` plus a 1D z-stencil. **Recommended first**: it is the cheapest, and it is what extruded-epithelium models want.
- **FCC** (12 neighbours, isotropic). It is a single static offset set in a sheared cubic index, so the architecture accepts it. Cost: new embed, new shells and a 12-point Laplacian. Recommended second, if isotropy is the goal.
- **HCP**: the neighbour offsets depend on layer parity, so one static `Relation` cannot describe it. It would need per-parity relations throughout the sweep and the checkerboard colouring. **Not recommended.**

Proposal: add `Hexagonal(; stacking = :prism)` (later `:fcc`), and keep the `N == 3` error for anything else.

---

## 2. CorePotts

| ID | Where | Problem | Fix |
|----|-------|---------|-----|
| A-10 **HIGH** | `phases.jl:116-128`, `lifecycle.jl:371-383` | `HistoryPush` writes out of bounds when a ring doesn't match its source: `with_capacity` grows cell arrays but not history rings. A (4,3) ring against a 50-long source segfaults. The generated Potts code sizes its rings correctly; hand-written models and `with_capacity` do not. | `with_capacity` grows the rings, and `HistoryPush`/preflight check the sizes. |
| A-11 **HIGH** | `model.jl:181-217` | An asymmetric `Stencil` contact/surface relation gives a ΔH that is not an energy difference (112/112 mismatches against brute force). | Reject non-symmetric contact/surface relations in `_preflight`. |
| A-12 **HIGH** | `lifecycle.jl:292-315` | Site-sum and site-min trackers aren't rebuilt after division: tracked `[2321, 2321]` against the true `[809, 1512]`. This affects every `integral`-like tracker in hand-written models; Potts `integral` recomputes and is unaffected. | Rebuild the trackers for the parent and daughter in the division commit, as moments already are. |
| A-13 MED | `drives.jl` `act_delta`, `_preflight` | `act_delta` reads a radius-2 footprint, but preflight checks only the max of the declared radii. | Declare the true reach. |
| A-14 MED | `problem.jl:159` | A scalar `saveat = 2` gives `UndefKeywordError: dims`. `saveat` points beyond `tspan` are dropped silently. With `save_start = false`, t0 is dropped even when it is in `saveat`. | Expand a number to `t0:Δ:t1`; warn on out-of-span points; SciML semantics for `save_start`. |
| A-15 MED | `checkpoint.jl:47-72` | `reinit!(integ, u0)`: fewer cells leave ghost cells (volume 16, no sites); more cells give a `BoundsError`. It also leaves the frozen mask and mobility stale, doesn't rerun `cb.initialize`, and a symbolic map gives a MethodError. | Validate sizes, recompute derived state, and route maps through `remake_state`. |
| A-16 MED | `lifecycle.jl` | Division on a 1D lattice gives a MethodError. | 1D split rule, or a clear error. |
| A-17 MED | `lifecycle.jl` | A cluster member's transition is lost when its cluster divides in the same MCS. | Apply transitions before the cluster split, or carry them over. |
| A-18 MED | `problem.jl:384` | `setu(integ, :x)(integ, 2.0)` on a Float32 Metal integrator gives `InvalidIRError`, because the Float64 value reaches the kernel. | `fill!(a, convert(eltype(a), v))`. |
| A-19 **HIGH** | `CorePotts` solution | `show(MIME"text/plain", sol)` gives `FieldError: … no field interp`, and `sol[i]`/`sol[end]` give a MethodError on `getindex(::CPMState)`. Displaying a solution in the REPL crashes. | Implement `show` and integer indexing (returning a saved state). |
| A-20 LOW | `problem.jl` `remake` | Doesn't accept `frozen`, `lattice`, `contact`, `relations` or `spacing`. | Extend it or document the limits. |
| A-21 LOW | `lattice.jl` | `NeighborOrder(0)` gives a BoundsError. | Validate `k ≥ 1`. |
| A-22 LOW | `checkpoint.jl` | A checkpoint restart reruns `at_init`. | Skip `at_init` on restore. |
| A-23 LOW | `CellReduce` | Float min/max with NaN are order-dependent. | Document it or use `nanmin`. |
| A-24 LOW | `HostPhase` | Writes back only `st.cell`. | Write back every mutated group, or document it. |
| A-25 LOW | `cell_entity` | Overflows for ids ≥ 2^24, and the generation wraps at 256. | Widen, or error at capacity. |
| A-26 LOW | `lifecycle.jl:380` | Free capacity slots carry `kind = 1`, so `sol[:kind]` arrays are capacity-long and `count(==(1), …)` miscounts. Population folds are correct. | Mark free slots with kind 0 (medium), or document it. |

Checked and fine: checkerboard colouring, aliasing, `init_moments` on the hex torus, the contact/surface/boundary helpers, random planes, the partition kernel.

---

## 3. Potts front end and compiler

| ID | Where | Problem | Fix |
|----|-------|---------|-----|
| A-30 **HIGH** | `macro.jl:63-72` | Declared names are silently rebound by the macro's built-ins. The preamble rebinds `B`, `t`, `D`, `Pre` and the `DSL` keys *after* the keyword arguments, so, for example: <ul><li>a parameter `distance = 3.0` becomes the built-in, and `mean` becomes `Potts.mean`;</li><li>`time`/`kind` crash at `PottsProblem`;</li><li>parameter `D` breaks `D(c)`;</li><li>a structural `t` fails;</li><li>`@kinds medium source` compiles `c[source]` as `c[1]`;</li><li>a variable `target` shadows the drive built-in;</li><li>parameter `a` next to kind `a` gives `cells(::Num)`.</li></ul> | At expansion, reject declared names in `BUILTIN_NAMES ∪ keys(DSL) ∪ {t, D, Pre, time}` and names that collide across kinds, parameters, variables and observed quantities. |
| A-31 **HIGH** | `compile.jl:179` | Duplicate `D(x)` equations: a field is integrated twice (1 → 0.81 instead of 0.9), and a duplicate cell or model ODE silently keeps one. | Single-writer check on the equation lhs. |
| A-32 **HIGH** | `macro.jl:66`, `compose.jl` | `rand()` streams collide under functional `extend(sys, base)`: both models number their draws from 1, so `x ~ rand()` equals `y ~ rand()`. `@extend` is fine. | Renumber the extension's draws in `extend`. |
| A-33 → A-65 *(arithmetic; race not observed)* | `compile.jl:279` | The checkerboard footprint undercounts source-anchored gathers when the proposal is wider than 1 (true reach 4, recorded 3), so the run races. A Potts user also can't reach the `footprint` advice given by preflight. | Record the source-gather radius separately and add `radius(proposal)` in preflight. |
| A-34 **HIGH** | `vocabulary.jl:63`, codegen | `clear_on_ownership_change = true` is documented (AUTHORING:213, :414) but does nothing: 21 sites changed owner and kept `act = 5.0`. Unknown variable options are accepted silently. | Implement it (an on-copy reset of the target site) and reject unknown options. |
| A-35 MED | `compile.jl:231,250` | Tracker detection misses some readers: `surface` in a divide rule or `@observed`, and `centroid` in the temperature, give a `FieldError`. Temperature errors carry no statement location. | Scan one shared set (updates, divide rules, observed, links, temperature) for every `uses_*` flag, and locate the temperature. |
| A-36 MED | codegen | `@on_copy Every(n)` is silently ignored (111 writes with `Every(1000)`), and `Every(0)` gives a runtime `DivideError`. | Reject `Every` on on-copy updates and require `n ≥ 1`. |
| A-37 MED | `compose.jl:49` | Vectors can't be bound through `@extend`: `lookup` sees only `d_1`, `d_2`. | Rebuild the `QuantityVector` from the tagged components. |
| A-38 MED | `macro.jl` `_nested` | An extension that inherits its base's lattice can't use `centroid()` or `displacement(c)`, because `_DIM` is restored to 0. | Set `_DIM` from the inherited lattice. |
| A-39 MED | `problem.jl` | Parameter defaults that depend on other parameters (`V2 = 2V₀`) and variable defaults that use parameters (`x(cell) = V₀`) give `Float64(::Num)`. With `b = 3a`, `remake(p = [:a => 10])` leaves `b = 6` (MTK gives 30), and `setp` does the same. | Substitute defaults to a fixpoint at build, remake and setp time for parameters that weren't set explicitly. |
| A-40 MED | `macro.jl` `rewrite` | Valid Julia in helper code breaks: `vals[end]` gives `UndefVarError: end`, and multi-iterator generators drop the second iterator (silently wrong if the name exists outside). | Leave `ref`s containing `end`/`begin` alone, and fall back to plain Julia for multi-iterator generators. |
| A-41 MED | AUTHORING §3 | `@relations proposal = Moore(1)` is documented but CorePotts rejects the name. | Map it to the algorithm's proposal, or fix the docs and reject it at expansion. |
| A-42 MED | `macro.jl:239` | A vector variable default given as a tuple, `p(cell)[1:2] = (1.0, 2.0)`, is parsed as options. | Treat it as options only when the second element is `:vect`. |
| A-43 LOW | | Wrong-length vector parameter overrides are truncated silently. | Validate the length. |
| A-44 LOW | `@kinds` | `@kinds medium a a` is accepted, and `medium[frozen]` is accepted but not enforced (volume 36 → 37). | Reject duplicates; reject `frozen` on medium or enforce it. |
| A-45 LOW | `@observed` | A name that collides with a variable gives a misleading error, and `@observed n(model) ~ volume` drops the scope. | Collision check (A-30); honour or reject scope annotations. |
| A-46 LOW | messages | Error messages are inconsistent: <ul><li>`time` is allowed in equations but rejected in updates;</li><li>a compound write across two blocks advises `+=` even though `+=` was used;</li><li>expansion errors lack the name and line.</li></ul> | Unify the messages. |
| A-47 note | `compose.jl` | Replacement is keyed on `(phase, target, every)`, so an extension's `x ~ …` doesn't replace a base's `Every(2) x ~ …` and both run. This was deliberate (Review 5), but AUTHORING says the extension "replaces the base's". | Clarify in AUTHORING, or key on `(phase, target)` and warn. |

## 4. Lowering and codegen

What is exact: the generated ΔH equals H(after) − H(before), to within 1e-11, for every model **without a population fold**. This was brute-forced on:
- hex `Hex(2)` with cell variables in contact and site terms;
- weighted `NeighborOrder(3)` contact fused with surface;
- a contact relation that differs from the surface relation;
- 3D `NeighborOrder(2)` in an irregular domain;
- clusters with mixed kinds and the death of a root cell.

No `double` appears in the Float32 LLVM of any generated function.

| ID | Where | Problem | Fix |
|----|-------|---------|-----|
| A-60 **HIGH** | `compile.jl:117-141` | Population folds are accepted in `@energy`, but ΔH treats them as constant. ΔH is off by 50 (`(volume - mean(volume for c in cells))^2`), 201 (a site count in a site term) and 16 (the same count in a cell term). | Reject populations in `@energy` (recommended), or derive their delta. |
| A-61 **HIGH** | `codegen.jl:312-446` `_ode_locals` | Cell and model ODEs substitute the current cell's local into population bodies. `D(h) ~ sum(h for c in cells)` becomes `ncells*h`, giving 17c instead of c + 136. This applies to fixed-step and `Adaptive`. | Don't substitute inside `population`: use a `filterer`, or bind the local only for `:__cell`. |
| A-62 **HIGH** | `compile.jl:283-298`, `codegen.jl:561-568` | Populations inside cell or site updates are evaluated in place (Gauss–Seidel), which races on threads/GPU. `a ~ sum(a for c in cells)` gives 16, 31, 61 … 491521 instead of 16 for every cell. The fold is also O(N²). | Hoist each population into a reduction phase that runs before the update (this also fixes the O(N²) cost). |
| A-63 **HIGH** | `codegen.jl:261` | Updates in one block are not synchronous across scopes. Scopes run as separate phases in string order (cell, model, site), so `Pre(m)` in a site update returns the *new* m, contradicting AUTHORING §6. Cadence groups within a scope are also sequential. | Evaluate every right-hand side of a block into scratch, then publish them together (Jacobi). |
| A-64 **HIGH** | `codegen.jl:280,571-582` | Auto field substeps are baked in from the build-time parameters. `remake(p=[:Dc=>5])` keeps 1 substep and c blows up to 5e16 with no status set; a fresh build uses 20. | Compute substeps from `p` at run time (the CFL bound is cheap). |
| A-65 MED | `compile.jl:274-281` | The checkerboard footprint undercounts (this subsumes A-33):<ul><li>source gathers in the temperature are skipped;</li><li>the proposal radius is assumed to be 1;</li><li>`@on_copy act[source]` leaves `write = 0`.</li></ul>Same-colour copies can overlap. | Footprint = proposal radius + relation radius, including the temperature and writes. |
| A-66 MED | `lower.jl:238-252,353` | `position` is unusable. `position[k]` fails with "cannot index `position`". Used as a gather anchor, it passes `mtkcompile`, then gives a MethodError at solve. So site updates can't gather around their own site. | Addressed by A-02: Cartesian `position[k]`, plus a `site` name for the current site, usable as an anchor. |
| A-67 MED | compile | An energy that reads a variable written `@on_copy` gets a ΔH that omits the update (a mismatch of 26). | Reject at `mtkcompile`, or document it. |
| A-68 MED | `codegen.jl:342` | The `Adaptive` cell env has no `key`, so `rand()` in an Adaptive ODE passes `mtkcompile`, then fails with a misleading message. | Reject `rand` in Adaptive ODEs at `mtkcompile`. |
| A-69 LOW | `codegen.jl:166-179` | On-copy updates read a mixed state: the owner is already new, but volumes and trackers are pre-copy (25 against 26). | Document it, or run the updates after the tracker commit. |
| A-6A LOW | `compile.jl:394` | `volume[id]` in a cell term gives "cannot index `-1 + volume`". | Better message. |
| A-6B LOW | `lower.jl:286,340` | `minimum`/`maximum` over an empty gather or population return ±Inf. | Document it. |

Hex in codegen: `centroid`, `displacement`, `distance`/`centroid_distance`, division `along`, the partition, `Ball`/`NeighborOrder` and the 6-point Δ/∇ all embed correctly. `_auto_substeps` uses the square CFL bound, which is conservative on hex. `per_length` doesn't exist yet. The raw-coordinate leaks are A-01, A-02 and A-05.

---

## 5. Problems, the SciML surface and units

| ID | Where | Problem | Fix |
|----|-------|---------|-----|
| A-50 **HIGH** | `problem.jl:109,195` | `:kind => [...]` with a Symbol key is silently ignored, so every cell gets kind 1. `:cluster` and `:ownership` are dropped too. | Map `:kind`, `:cluster` and `:ownership` in `_operating_point`. |
| A-51 **HIGH** | `problem.jl:197`, `lower.jl:227` | Out-of-range numeric kinds (`kind => [1, 9]`) are accepted, and `@inbounds p.J[...]` reads garbage (an out-of-bounds device read on Metal). | Check `1 ≤ k < length(kinds)`. Validate `σ ≥ 0` too (a negative label is a bare BoundsError). |
| A-52 **HIGH** | `problem.jl:332,251` | `remake(u0 = map)` with more cells than the old capacity leaves no room for division: 0 divisions and 100 deferred. | Capacity = `max(old, default(new ncell))`. |
| A-53 **HIGH** | `vocabulary.jl:573`, `CorePotts/problem.jl:410` | `setp` / `integ.ps[:J] = …` skip the symmetry and shape checks, so an asymmetric `J` is accepted. | Run `_check_kind_tables` and the symmetry check in `set_parameter`. |
| A-54 MED | `problem.jl:109` | Unknown operating-point keys (the typo `:lamda`, or a key from another model) are ignored; `remake` already rejects them. | Error on unmatched keys. |
| A-55 MED | `observed.jl:44` | Data race on the observed-function cache under `EnsembleThreads`: `UndefRefError` in 1–2 of 15 runs. | Lock the cache. |
| A-56 MED | `ext/PottsDynamicQuantitiesExt.jl` | Units false positives on published patterns: `when = clock >= 0` and the division rule `clock => 0.0` are flagged. Also, the lhs of `D(c) ~ rhs` is never compared, which is a design question since time is the unitless MCS. | Literal 0 takes any unit in comparisons and rules. Decide on the time units for `D`. |
| A-57 LOW | `problem.jl:182` | A scalar kind table `:J => 2.0` gives a MethodError. | Fill the table, or raise a clear error. |

Verified OK:
- fingerprints and integral names are stable across sessions;
- a checkpoint round-trip with lags, integrals and division;
- `setp`, `setu` and `sol[x]` on Metal;
- Float32 conversion of the operating point;
- `setu`/`setp` in callbacks;
- `remake` table-shape rejection;
- frozen masks recomputed on `remake(u0)`.

---

## 6. Documented but unsupported (AUTHORING drift)

These are claimed in the syntax table, the examples, §9 or as "implemented", and fail today:
- `@retire`, `@create`, `@transition` (§2, §7);
- `@on_copy … when =`;
- `rand(Normal(...))`, `rand(Bernoulli(...))`;
- `Copy()`, `Reset()`, `Redraw()`, `along = Normal(...)`;
- `∇`, `∇²`;
- `Wall(kind)`;
- `inverse_distance`;
- `Lattice(…; proposal = …)`;
- the bare fold `sum(act)`;
- `@kinds` DAE components;
- `plot(sol, 100)`;
- `sol[count(dark)]`;
- `u[volume]`, and `.ownership` (the field is `.σ`).

Wrong examples:
- `compose(...)` (§8, principle 2; D-039 declined it);
- `inertia`/`elongation`/`centroid` in energies (§4);
- `ode_solver = Tsit5()`, which should be `Adaptive(Tsit5())`;
- `mcs_duration = 30.0u"s"`, which asserts on dimensions;
- `EnsembleProblem(prob; trajectories)`;
- "no-extinction is the default", whereas D-037 makes it `@constraint no_extinction`;
- the deprecated `ODESystem` in §10.

The §10 listings don't match `lib/PottsModels` (Wortel size/V₀/geomean, Merks contacts, OpenVT growth, and Akeeb, which is a different model).

Stale docs:
- ROADMAP §12 table maps layouts (`UniformSeeds` etc.) to M2.1, which is ticked; they don't exist.
- ROADMAP:22-25 has the LocalMath acceptance, and ROADMAP:63 says "Akeeb parity pending".
- AUTHORING:390 and INTERNALS:60/156/182/193/304 still mention LocalMath.
- INTERNALS:217 and D-015 still say Unitful.
- D-037's "Deferred: `@sweep` law not propagated" is stale.

Implemented but undocumented:
- vector quantities with `dot`/`norm`/`normalize` (§12.2 still shows `::SVector`);
- `@sweep Barker`;
- `no_extinction`;
- `geomean_shifted`;
- the `Chemotaxis` keywords;
- the `PottsProblem` keywords `capacity`/`T`/`replica`;
- PIFF, `lookup`, `observe`, `energy_change`, checkpoints.

Planned and absent, which is correct (§12 untagged): `per_length`, `neighbors`/`contact`, `count(cells(k))`, `@boundary`, `@terminate`, `Homophilic` and motility, MorpheusML.

**Fix approach:** a doctest-style test that extracts every fenced `julia` block in AUTHORING tagged runnable and runs it. Blocks describing planned syntax get tagged `planned`.

---

## 7. PottsModels and parity power

| ID | Problem | Fix |
|----|---------|-----|
| A-70 **HIGH** | Wortel parity passes with `λ_act = 0`: both cells die in every seed, and all-zero pairs are skipped (9/20 comparisons run). | A viable configuration (cells survive); fail on all-zero; add a negative control (`λ_act = 0` must fail). |
| A-71 **HIGH** | Merks parity passes with `χ = 0`: KS on one cell, and `volume2 ≡ 0`. | Compare the chemotaxis-sensitive metrics; add a negative control. |
| A-72 MED | OpenVT's division trigger hard-codes `volume >= 8`, not V₀, and 0 divisions happened in 6/6 seeds. | Use V₀; make the parity config divide. |
| A-73 MED | The Merks/Wortel/OpenVT reference data come from legacy toy models, not the published ones. | Document the scope, or regenerate references from the published configs. |
| A-74 MED | Akeeb parity: 16 seeds are claimed but the legacy side has 8; 4/10 metrics (front positions) are constant at the lattice height. | Taller lattice or shorter run; drop the constant metrics. |
| A-75 MED | `akeeb.jl:77` hard-codes a 21-row slab (a BoundsError for heights ≤ 20). | Parameterise it. |
| A-76 MED *(read)* | `wortel_act.jl:33` activates only on extension into medium; the docstring says any gained site. | Check against the paper; fix the code or the doc. |
| A-77 MED | Akeeb never runs on Metal or in Float32; the other models get only a volume check on Metal. | Add them to the GPU group with distributional checks. |
| A-78 LOW | Unused Akeeb slots default to the leader kind; `graner_glazier_state` needs multiples of 72. | Polish. |

Every parity test should get a **negative control**: a perturbed science parameter must fail. Otherwise the parity tests have no demonstrated power.

---

## 8. MakiePotts

| ID | Problem |
|----|---------|
| A-07 **HIGH** | Hex rendering (see §1). |
| A-80 **HIGH** | `CellIdentityEncoding` collapses to two hues, by id parity (`encodings.jl:115,188`). |
| A-81 **HIGH** | Vector-valued channels crash: `Float64(::SVector)`. |
| A-82 MED | Full 3D: CairoMakie draws blank; `pottsboundaries`, `explore_potts`, `record_potts` and `potts_legend` raise MethodErrors. Slices work. |
| A-83 MED | Irregular-domain sites show as "Obstacle" from a solution but as Medium from a bare state. |
| A-84 MED | Clusters, links, site/model variables and model scope are never extracted (`available_channels == ()`). |
| A-85 MED | `dev/ci_telemetry.jl`, a legacy file, is load-bearing (included by `runtests.jl:9`). `docs/`, `examples/`, `test/backends/` and `benchmark/` Projects are outside the workspace with stale compat and can't resolve. |
| A-86 LOW | Legacy multi-repo files: `.github/workflows/ci.yml`, CONTRIBUTING, AGENTS, README, RELEASE_NOTES, CITATION, `docs/src` (`PottsSavedState`). |
| A-87 | Tests: nothing covers hex, domains, clusters, links, vectors, `PottsVolume` or colour distinctness. `visual_regression.jl` and `test/backends` never run, and several assertions only check the result type. |

---

## 9. Coverage gaps

- The `Barker` acceptance law is tested only in the CorePotts GPU group; a nonzero `offset` and the T ≤ 0 tie rule are untested.
- The symbolic tests have zero coverage of `clear_on_ownership_change`, `include_self`, `Stencil`, `Ball`, `major_axis`, the `Surface()` one-liner or `generation`.
- The PottsModels self-check runs 3 MCS with Moore(1) proposals only.
- Nothing displays or integer-indexes a solution (A-19).
- The AUTHORING examples are not executed (§6).

---

## 10. Proposed fix order

1. **Memory safety and silent physics.**
   - A-10, A-11, A-12, A-51 (bounds);
   - A-60, A-61, A-62, A-63, A-64 (codegen semantics);
   - A-01, A-03, A-02/A-66 (hex connectivity, the torus, `position`);
   - A-31, A-32, A-65, A-34, A-30.
   - Each fix lands with a regression test.
2. **Silent input loss.** A-50, A-54, A-39, A-52, A-53, A-15, A-36, A-43, A-44.
3. **Crashes on reachable input.**
   - A-19 (solution display), A-14, A-18, A-35, A-37, A-38, A-40, A-42;
   - A-55 (race), A-16, A-17, A-56.
4. **Model test power** (rescoped by D-048: no legacy parity). Ordinary tests with negative controls replace A-70…A-77.
5. **Hex completion.**
   - A-04, A-05, A-06;
   - A-07 plus MakiePotts A-80/A-81;
   - then **3D hex (prism first)** as a feature milestone.
6. **Docs.** Executable AUTHORING (doctest extraction); the §6 drift; ROADMAP/INTERNALS/DECISIONS staleness; MakiePotts legacy files.
7. **LOW polish.**

---

## 11. Paper-fidelity round (2026-09-29)

Five reviewers, one per published model, read the paper and its reference code and compared
our `@potts_model` term by term (D-048: the paper, not legacy code, is the reference). I
verified the load-bearing claims before recording them. Sources are cited in each model's
docstring.

| ID | Model | Finding | Class | Status |
|---|---|---|---|---|
| P-01 | Graner–Glazier | Energy, J, λ, V₀, T and the acceptance rule are the paper's | faithful | – |
| P-02 | Graner–Glazier | One MCS here is 1/16 of the paper's (N vs 16N attempts) | undocumented | docstring |
| P-03 | Graner–Glazier | The paper copies from 8 neighbours; `SequentialCPM()` defaults to 4, and a model cannot declare its proposal relation (`problem.jl:152`, although AUTHORING says it can) | API gap | **fixed (D-049 F-1)**: `@relations proposal = …` |
| P-04 | Graner–Glazier | The initial state uses a legacy recipe (6×6 cells, J = 8, hard extinction); PRE §II D3 relaxes area-40 cells with J_ll = 2, J_lM = 8, T = 5 for 400 paper MCS. `provenance.toml` said the paper gives no recipe | legacy | **fixed (D-049 F-2)**: `data/graner/generate.jl` |
| P-05 | Merks | No cell-length constraint `λ_L(l − L)²`, the paper's title claim; energies cannot read `major_length` yet (moment trackers exist) | missing core term | **fixed (D-049 F-3)**: `major_length` built-in |
| P-06 | Merks | No adhesion (paper J_cc = 40, J_cM = 20); chemotaxis on extensions only (the 2008 contact-inhibited form); decay everywhere (paper: medium only); legacy 8×8 defaults | legacy / reduced | **fixed (D-049 F-3)** |
| P-07 | Merks | The paper's D (≈ 0.75 per MCS) diverged silently with the fixed 2 substeps (max c = 8e65 by MCS 200) | bug | **fixed**: explicit substeps are a stability minimum |
| P-08 | Wortel Act | No Act term for retractions (the papers penalise retracting active sites); halves persistence at the paper's parameters | legacy deviation | **fixed (D-049 F-4)** |
| P-09 | Wortel Act | Shifted geometric mean; activation only on extension into the medium (D-034); connectivity always on; legacy 8×8 defaults | legacy deviation | **fixed (D-049 F-4)** |
| P-10 | OpenVT | Not the OpenVT growing-monolayer benchmark: no growth, one division at MCS 0, fixed plane, strong adhesion, no benchmark outputs. A faithful model is writable today (contact-inhibition type 2 needs neighbour reductions) | misnamed fixture | **fixed (D-049 F-5)**: `OpenVTGrowingMonolayer`; the fixture is `SingleDivisionFixture` |
| P-11 | Akeeb | Matches the authors' CC3D source except connectivity: CC3D 4.3.1 accepts one arc only; `:merks` adds a two-cell fallback (commented out in CC3D) that splits 4–6 cells per 200-MCS run on 99×60 and 60–73 on the full run, inflating singles. `rule = :local` is exactly CC3D's rule and splits none | legacy deviation | **fixed (D-049 F-6)** |
| P-12 | Akeeb | Divisions beyond `capacity` were deferred silently (0 divisions in a full-size run at capacity 1000) | bug | **fixed**: warns once per run |
| P-13 | Akeeb | Paper Table 1 is an image; λ_V and T must be checked by eye against the source (2, 10) | – | maintainer check |
| P-14 | Merks | The defaults mix variants: A = 50, λ = 25 are Merks 2008 (Dataset S1); L, λ_L and 282 cells in 333² are 2006. The TST v0.1.3 files for 2006 Fig. 4 give λ = 50, A = 100, λ_L = 5, L = 60 px, a soft connectivity penalty E₀ = 2000–5000 on the 8-ring, integer ΔH, 15 field substeps, an absorbing field boundary and 100 MCS of relaxation without the field (`model-specs/01_merks.md` §7–§8) | mixed variant | **pending maintainer sign-off** (per-model paper-vs-code decision) |
| P-15 | API hygiene | Model-named primitives remain: `rule = :merks`, `merks_connectivity`, `extension_only` (`src/vocabulary.jl`, `src/codegen.jl`) | naming | open: rename to descriptive names (group 7) |

Tests added (`lib/PottsModels/test/papers.jl`, all pass on the current models):
- **Graner–Glazier:**
  - engulfment, with partial sorting as the control;
  - checkerboard;
  - the logarithmic sorting law, frozen at T = 0;
  - the λ survival table (PRE Table III, exact);
  - light cells smaller, with symmetric J as the control;
  - layer reversal.
- **Act:**
  - speed–persistence coupling;
  - no persistence without Act;
  - weak Act stationary;
  - amoeboid vs keratocyte orientation and elongation.
- **Akeeb:**
  - motility grades invasion;
  - adhesion decides collective vs single-cell escape;
  - the published sample: 578 ± 50 divisions, with a leader at the front.

Decisions for the maintainer (all approved 2026-09-29 as D-049, implemented; see the fix log):
- **F-1:** let models declare a default proposal relation. `GranerGlazier` → `Moore(1)`.
- **F-2:** regenerate `graner_glazier_state` with the PRE §II D3 recipe.
- **F-3:** Merks:
  - add `major_length` to energies and the length constraint;
  - add adhesion;
  - decay in the medium only;
  - choose the chemotaxis scope (2006 all copies vs 2008 extensions);
  - adopt paper-scale defaults.
- **F-4:** WortelAct:
  - the retraction term;
  - the plain geometric mean;
  - activating every gained site;
  - optional connectivity;
  - Niculescu 2015 defaults.
- **F-5:** rename `OpenVTMonolayer` to what it is and add `OpenVTGrowingMonolayer`. Choose the Artistoo (A₀ = 25, τ = 84) or Morpheus (A₀ = 50, τ = 86) parameter set, and whether the division size is deterministic.
- **F-6:** switch `AkeebInvasion` to `rule = :local`. This supersedes the parity-based approval of `:merks`.

## Fix log

| Commit | IDs | Notes |
|--------|-----|-------|
| (group 1a) | A-10, A-11, A-12, A-14, A-19, A-50, A-51, A-52, A-54, A-60, A-61, A-62, A-63 | Mismatched history rings are a `DimensionMismatch` (rings are not resized by `with_capacity`). Asymmetric contact/surface relations are rejected. `Lifecycle(…; rebuild!)` hook for model trackers. `saveat = Δ`, solution `show`/`sol[i]`. Operating-point `:kind`/`:cluster`/`:ownership` Symbol keys, kind range and label sign checks, unknown keys are errors. `remake(u0)` keeps the old free slots. `src/schedule.jl`: D-041 energy snapshots, D-042 ordered stages with `x__pre` snapshots and hoisted folds (also for cell ODEs); vector components are one unit. |
| (group 1b) | A-01, A-03, A-05, A-02/A-66, A-31, A-32, A-47, A-64 | Hex 6-ring arc rule for `locally_connected`/`merks_connectivity`. Hex minimum image over neighbouring images (`_min_image`). Domain predicates and `Weighted` weights receive Cartesian positions (`OnIndices(f)` for lattice coordinates). `position` is Cartesian times spacing and indexable, `site` is the current site (gather anchor). One `D(x)` per variable. `extend` renumbers colliding draws. Replacement by `(phase, target)` with a warning on changed cadence (D-045). Field substeps are computed from the current parameters every MCS; a non-parameter diffusion coefficient needs explicit substeps. |
| (group 1c) | A-65, A-34 | `Footprint(; source_read, source_write)` and `reach(footprint, proposal)`: the checkerboard stride adds the proposal radius at run time (wider proposals need no manual footprint); temperature gathers count. `clear_on_ownership_change` resets the target to the default before on-copy writes; unknown variable options are errors. |
| (group 1d) | A-30, A-44 (duplicate kinds), A-45 (observed collisions) | Declared names (structural parameters, kinds, parameters, variables, relations, observed quantities, relationships, components) may not be a name the constructor binds (built-ins, DSL names, `t`, `D`, `Pre`, `name`) or repeat another declaration. |
| (group 1e) | A-67 | ΔH applies on-copy writes the energies read: cell terms at `x[new]`/`x[old]`, site terms at the target (`_oncopy_after`); other readers (contact, cluster, edge terms, other indices) are rejected at `mtkcompile`. Group 1 complete: all suites green on CPU and Metal, QA clean. |
| (group 2) | A-15, A-36, A-39, A-43, A-44, A-53, A-57 | Variable defaults may be parameter expressions; `remake`/`setp` re-derive expression-defined parameters not set in the same change (MTK), and `setp` runs the table checks (`CorePotts.set_parameter(sys, p, v, i)` hook). `reinit!` takes symbolic maps, checks shapes, resets frozen sites, reruns callback `initialize`. `Every` rejected on on-copy updates and `Every(0)`; vector lengths checked; a frozen medium rejected; scalar kind tables a clear error. |
| (group 3a) | A-37, A-38, A-40, A-42, A-55 | `lookup` rebuilds vector quantities; an extension inherits the base's dimension; `v[end]`/`begin` and multi-iterator generators stay plain Julia; a tuple default is a default unless followed by an options vector; the observed-function cache is locked. |
| (group 3b) | A-16, A-17, A-18, A-35, A-68 | 1D principal axis; a transitioning member of a dividing cluster keeps its transition (both halves); `setu` converts to the array's element type; every tracker flag scans the same statement set (observed, division rules, link rules, temperature); `rand()` in an `Adaptive` equation is rejected at `mtkcompile`. |
| (group 3c) | A-56 | Units: a literal zero in comparisons, rules and updates takes any unit; `D(x) ~ rhs` must have x's units, or x's units per unit of time (the MCS clock is unitless). |
| (group 4) | A-70…A-78 (rescoped, D-048) | Legacy parity is removed: `reference/`, the `Reference` group and test/parity's legacy comparisons are deleted; the hand-written ports stay in `test/ports`. New `lib/PottsModels/test/mechanisms.jl`, specification-level and independent of production code: per-proposal drive checks (chemotaxis, Act, Akeeb cue) and the Merks ring rule re-implemented; the Wortel on-copy write and after-MCS decay; Merks' field step recomputed exactly; OpenVT's division partition, mass split and trigger; Akeeb clocks and target-volume growth. Mechanisms with negative controls: sorting under differential J, none under equal J, mixing under reversed J; chemotaxis up, zero and down a static gradient; Act persistence against λ_act = 0; Akeeb invasion against μ = 0 and proliferation against pp = 0; H non-increasing at T → 0 for sequential and checkerboard. `test/oracle.jl`: the generated Graner–Glazier on a 3×3 torus against the exact chain (z = 1.6; the T = 5 mutant gives z = 21). A-72: OpenVT divides at `volume ≥ V₀`. A-75: `akeeb_state(; slab)` with a height check. A-76: the Wortel docstring now matches the code. A-77: Akeeb in Float32 on Metal against the CPU. A-73/A-74 are moot. |
| (D-049) | P-03…P-06, P-08…P-11 | F-1 model proposal relations (`CPMProblem.proposal`, algorithms default to it) and conditional sections in `@potts_model`. F-2 Graner–Glazier state regenerated per PRE §II D3 (`generate.jl`); two `papers.jl` observables re-set on it (partial sorting by dark–medium share alone; reversal at 4000 MCS). F-3 `major_length` built-in with exact ΔH (`CorePotts.major_length_after`); Merks as in 2006 with `merks_state` and a networks-vs-islands test (compactness 0.27 vs 0.58, elongation > 3 vs < 2). F-4 Wortel Artistoo semantics (retraction penalty tested). F-5 `OpenVTGrowingMonolayer` (doubling ≈ τ, contact inhibition, isotropic division) and `SingleDivisionFixture`. F-6 Akeeb one-arc connectivity (no split cells over 3 seeds). |

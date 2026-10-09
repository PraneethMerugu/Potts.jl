# Connectivity vocabulary: audit and recommended design

Status: research proposal (2026-10-08), not a decision. Written against `origin/monorepo`
at 5c787cec. It answers the maintainer's request: "is there a better vocabulary, or better
way to make this more compositional and easier for users to use", and "really audit this
idea and see how we can make it as powerful, compositional, robust, and easy to use for
everyone involved", plus the scope addition on coverage of the CPM literature (§5).

Sources: the code and design docs cited by path:line; the framework sources fetched on
2026-10-08 (CompuCell3D master, Morpheus main, Artistoo master, TST2.0, Chaste develop);
the literature cited in §4–§5. Where a claim rests on memory rather than a fetched source,
it says so.

---

## 1. Summary and recommendation

**Today.** Connectivity is four copy-scope built-in numbers (`local_components`,
`ring_arcs`, `ring_cells`, `ring_medium`), a `connectivity(kinds…; rule = :local |
:arc_or_pair)` constraint shorthand, a hand-written 90-character soft drive for Merks'
E₀, and a reserved `components(x; scope = Global())` that throws. Two of the four numbers
are the same number. The vocabulary describes the *kernel* (rings, arcs), not the
*question* a modeller asks ("may this copy break the cell?").

**Recommendation.** Keep one primitive, name rules as values, and put the scope inside the
rule rather than beside it:

| Layer | Surface | What it is |
|---|---|---|
| Rule values | `Local()`, `ArcOrPair()`, `Simple()`, `Global(; window)` | named, documented tests, each with a literature source and an exact definition (§8) |
| Statement helper | `connectivity(kinds…; rule = Local(), penalty = nothing)` | in `@constraint` it vetoes; in `@drive` it charges `penalty` to every copy the rule refuses |
| Expression | `connected(c; rule = Local())` | copy-scope Boolean, `true` for the medium; composes with `&`, `|`, `!`, kinds, volumes |
| Primitive fold | `pieces(… for n in shell(target) if pred(n))`, sugar `pieces(old, shell(target))` | number of face-connected pieces of a set of shell sites; works for cells, clusters, kind classes, the medium |
| Cell quantity | `pieces` (and `largest_piece`) in cell scope | exact global piece count of a cell, with an exact after-value, usable in energies (Bauer 2009, Jafari), observables and lifecycle rules (P6.9) |
| New fold | `distinct(… for n in rel(site) if …)` | number of distinct values; replaces `ring_cells`, and also gives foam sides and OpenVT neighbour counts |
| Relation | `shell` | the geometry's neighbour shell (8 square, 6 hex, 26 cubic), the relation every local rule reads |

The four old names stay as deprecated aliases that lower to byte-identical code, so every
frozen test and fingerprint is unchanged (§11).

Common cases, in the recommended surface:

```julia
@constraint connectivity(cell)                                          # CC3D-style hard local
@drive      connectivity(endothelial; rule = ArcOrPair(), penalty = E₀) # TST / Merks 2006 soft E₀
@constraint connectivity(leader, follower)                              # per kind (Akeeb)
@constraint connectivity(cell; rule = Global())                         # whole-cell, exact (P6.9)
@energy     cells(endothelial) => α * (pieces > 1)                      # Bauer 2009 state energy (P6.9)
@constraint connectivity(cell; rule = Simple())                         # no splits and no holes, both cells
```

**The most important weaknesses of the first-pass proposal** (full list in §7):

1. A free `region` in `pieces(c, region)` is not a connectivity test. Counting every piece
   inside a window larger than the shell rejects ordinary copies, because unrelated arms
   of the same cell enter the window. The adjacency (4 or 8 in 2D, 6 or 26 in 3D) is also
   unstated, and the answer depends on it.
2. `scope = Local() | Global()` beside `rule` is a false orthogonality. Most rule × scope
   pairs are undefined (what is `ArcOrPair` globally?). And the paper models that need
   global connectivity (Bauer 2009, Jafari) need a **state energy** α·[cell is in pieces],
   not a copy predicate. A drive `λ * splits(old)` never rewards a reconnecting copy, ignores
   the gaining cell, and does not enter `total_energy` (api-synthesis §2.5, R4 amendment).
3. A soft penalty written under `@constraint` breaks the taxonomy that the docs, `track =
   (:ΔH,)` and the `PottsSweepSpec` metadata rely on: constraints veto, drives add to ΔH.
4. The gaining cell is never checked. Under Moore or longer-range proposals (Merks 2006,
   WortelAct, Merks 2008's `NeighborOrder(4)`) a cell can gain a site that touches it only
   diagonally, or not at all. CompuCell3D, Morpheus and Durand & Guesnet 2016 all check the
   gaining side.
5. Holes are not expressible. A piece count of the cell cannot see a hole; the hole test
   needs the complement under the dual adjacency (4/8 in 2D, 6/26 in 3D). Digital topology's
   simple-point test is the right local primitive for "change nothing topological".
6. `@rule` is not needed. Plain function definitions inside the model body already work
   (`act_mean` in `wortel_act.jl:47`).
7. "`Connected()` = CC3D" is not accurate. CompuCell3D's local `Connectivity` also requires
   a face neighbour of the gaining cell, rejects a full ring, and in current source is a fixed
   soft penalty of 64, not a veto (§3). Rules should be named for their mechanism, with a
   mapping table to frameworks.

**Literature coverage** (§5): of 33 connectivity and topology forms found in CPM and
related lattice models, the recommendation expresses 20 exactly (today 9), 11
approximately, and 2 not at all (today 18 not at all). In papers the gain is modest: it is
the last missing piece for Bauer 2009 and Jafari (both also wait on other P6.9/P6.10
features) and, with P6.4b's proposal law, for Durand & Guesnet 2016 / Durand 2021. Most
of the value is fidelity to other frameworks' rules and robustness.

**Decisions needed** (§13): the rule names (Q1); whether `Local()` gains a gain-side option
(Q3); the default adjacency of `Global()` and `pieces` (Q4); closed edges in `ArcOrPair()`
(P6.0ae; the maintainer ruled "match TST" in D-156, but the core has not changed, Q5);
`components` → `pieces` (Q6); whether a custom shell is allowed in v1 (Q8).

---

## 2. Current state

### 2.1 Primitives (CorePotts)

- `lib/CorePotts/src/drives.jl:85-96` `local_components(σ, ctx, prop)`: face-connected
  pieces of `old`'s sites in the target's 3ᴺ−1 box, by bitmask flood fill
  (`drives.jl:188-215`); arcs of the 6-ring on hex (`:183-186`). Out-of-domain sites are not
  the cell. Zero for the medium, for the last site and for an isolated fragment.
- `drives.jl:98-103` `locally_connected` = `old == 0 || local_components == 1`.
- `drives.jl:105-116` `ring_arcs`: maximal runs of `old` on the 8-ring (2D) via `_arcs`
  (`:159-166`, returns 1 for a full ring); in 3D it *calls* `_local_components`. The
  docstring states `ring_arcs == local_components` on every geometry (true: on the 2D ring,
  consecutive sites are face neighbours and no other pair is).
- `drives.jl:118-133` `ring_cells` (distinct ids > 0) and `ring_medium` (owner 0); both read
  `_ring_owners` (`:142-149`), where an out-of-domain site reads −1 (neither medium nor a
  cell). Ring orders: `_MOORE_RING` clockwise, `_HEX_RING` angular, `_CUBIC_SHELL` ternary
  (`:135-140`).
- Cost notes: in 2D square `local_components` (used by `rule = :local`) runs the generic
  3×3 flood fill, not the cheaper `_arcs`. The 3D flood fill recomputes face-neighbour masks
  with integer `div`/`rem` inside the loop (`_face_neighbors`, `:220-229`). Each of
  `ring_arcs`, `ring_cells`, `ring_medium` re-reads the shell (three `_ring_owners` calls
  for the Merks soft drive; LLVM may merge the loads, but nothing guarantees it).

### 2.2 Symbolic layer (Potts)

- `src/vocabulary.jl:36-39` the four names are `BUILTIN_NAMES`; `src/macro.jl:70-72`
  reserves them; `src/compile.jl:68` lists them as proposal built-ins.
- `src/codegen.jl:121-126` `_proposal_env` lowers each to an `Int32(CorePotts.…)` call.
- `src/vocabulary.jl:548-584` `connectivity(kinds…; rule)`: `:local` → `local_components
  == 1`; `:arc_or_pair` → `(ring_arcs <= 1) | ((ring_cells == 2) & (ring_medium == 0))`.
  It returns a `Constraint(:connectivity, kinds, test)`; `src/codegen.jl:371-385` lowers it
  to `old == 0 || !(kind test) || test` inside the one constraint function.
- `src/vocabulary.jl:585-612` `Global(; window)` and `components(x; scope)`: reserved,
  always `ArgumentError` until P6.9 (D-140).
- Folds over relations exist: `count`, `sum`, `any`, `all`, `geomean`, … over
  `rel(site)` (`src/vocabulary.jl:376-421`, lowering `src/lower.jl:484-540`). A gather
  skips out-of-domain sites. There is no `distinct` fold.

### 2.3 Execution

- Sequential and BoundarySite evaluate the constraint **before** ΔH
  (`lib/CorePotts/src/sequential.jl:28`, `boundary_site.jl:224`); the acceptance draw is
  precomputed from the counter RNG (`sequential.jl:16`).
- Checkerboard: colour stride `read + write + 1` (`checkerboard.jl:3-7, 193`), read radius
  at least 1 (`src/compile.jl:404`). The shell has Chebyshev radius 1, so every local rule
  stays inside the colour footprint and needs no claim beyond `old` and `new`. A global BFS
  reads further, but only sites of a cell it claims (api-synthesis §8.1 Q6).

### 2.4 Models and tests

- `lib/PottsModels/src/merks.jl:75` `MerksVasculogenesis`: `connectivity(endothelial; rule =
  :local)`, Moore(1) proposals. `merks.jl:229-233` `Merks2006`: soft E₀ drive (default) or
  hard `:arc_or_pair`. `Merks2008` (`:277-316`) has no connectivity rule and
  `NeighborOrder(4)` proposals.
- `akeeb.jl:62` `connectivity(leader, follower)` + `no_extinction`, `VonNeumann(1)` proposals.
- `wortel_act.jl:51-53` `connectivity(cell; rule = :arc_or_pair)` when `connected = true`,
  Moore(1) proposals.
- Frozen or pinned behaviour: `lib/CorePotts/test/drives.jl:101-236` (values, flood-fill
  oracle, 3D); `lib/CorePotts/test/gpu.jl:173, 561`; `lib/CorePotts/test/audit.jl:81`;
  `acceptance/p6_0aa_arc_or_pair_medium.jl` (frozen, D-099); `acceptance/p6_3a_topology_track.jl`
  (frozen; asserts that `components(old; scope = Global())` throws, `:496-520`);
  `acceptance/p6_0bm_hamiltonian_metadata.jl:76-79` (built-in set, used as a filter only);
  `test/symbolic.jl:2005-2045`; `lib/PottsModels/test/siblings.jl:88`; the DSL surface
  snapshot `lib/PottsModels/test/guardrails.jl:143-155` (lists `:components => [:scope]`,
  `:connectivity => [:rule]`).

### 2.5 Decisions that bind this design

- D-074: `connectivity(k)` rejects anything but exactly one piece, so the last site cannot
  be taken (CC3D's `!= 1`).
- D-099: `:arc_or_pair` exempts a two-cell ring only without medium; out-of-domain sites
  are not medium.
- D-140: shell values on every geometry; the soft E₀ drive is an expression, not a name;
  `Global(; window)` reserved; `window` lives on `Global`/`components`, never on
  `connectivity`.
- D-075 Q6 / api-synthesis §8.1 Q6: global connectivity runs on the checkerboard through a
  deferred windowed BFS over a compacted list of local-test failures, rejecting
  conservatively (with a counter) on window overflow; sequential is exact.
- api-synthesis §2.5 (R4 amendment): Bauer 2009 Eq 1 and Jafari Eq 3 are **state
  energies**; `components` must be a cell-scope built-in with an exact after-value.
- D-051 item 5: global connectivity must work on the checkerboard.
- D-156: "At a closed edge the ring rule matches TST: out-of-domain sites count as a cell in
  `ring_cells` (P6.0ae)." **Not landed in the core**: `_distinct_cells` still counts only
  ids > 0 (`drives.jl:168-180`), the frozen `drives.jl:117` and `p6_0aa` pin that, and
  ROADMAP P6.0ae is open (`ROADMAP.md:286`). Both Merks models already match TST because
  their frame is a real frozen cell (D-153).
- D-159 / D-160: Potts is "built on ModelingToolkit"; constraints are in `constraints(sys)`
  and the `PottsSweepSpec` payload; the payload never enters code or fingerprints. The
  standing rule: stop and ask on major MTK friction or a major slowdown.
- D-171: performance is decided by the paired A/B (`benchmark/ab.jl`) with two same-commit
  controls; `benchmark/gate.jl` is the zero-allocation check.
- D-177: `BoundarySiteCPM` draws only boundary sites; it calls the same constraint function.

---

## 3. Framework survey

All sources fetched 2026-10-08. CC3D = `CompuCell3D/core/CompuCell3D/plugins/` on master
(https://github.com/CompuCell3D/CompuCell3D); Morpheus =
`morpheus/plugins/shape/connectivity_constraint.cpp` (https://gitlab.com/morpheus.lab/morpheus);
Artistoo = `src/hamiltonian/` (https://github.com/ingewortel/artistoo); TST =
`src/cellular_potts/ca.cpp` on branch TST2.0
(https://github.com/mathbioleiden/Tissue-Simulation-Toolkit); Chaste =
`cell_based/src/population/` (https://github.com/Chaste/Chaste).

| Framework, rule | Shell and adjacency | Test | Losing / gaining cell | Hard or soft | Medium, edges | Geometries | Known failure modes |
|---|---|---|---|---|---|---|---|
| CC3D `Connectivity` (`Connectivity/ConnectivityPlugin.cpp`) | clockwise 8-ring | (1) the gaining cell must own a face (4-) neighbour of the target, else 64; (2) the number of ring transitions involving `old` must be exactly 2 (one arc). Zero arcs and a full ring are both refused | both | **soft in code**: registered as an energy, returns a fixed 64; `<Penalty>` is ignored (`update()` empty). The docs call it a veto | medium as `old` exempt; out-of-domain neighbours keep a default point (0,0,0), apparently reading the site at the origin (inference) | 2D square only (throws otherwise) | soft 64 can be outweighed; edge reading looks wrong. The Akeeb CC3D 4.3.1 files set Penalty 1e5 (topology audit, l.157); whether 4.3.1 honoured it is unverified |
| CC3D `ConnectivityLocalFlex` | same | same | both | same 64; the per-cell strength only switches it on | same | 2D only | same |
| CC3D `ConnectivityGlobal` (legacy) | BFS with first-order (face) neighbours: 4 in 2D, 6 in 3D, 6 hex | after the copy `old` must still be one component (BFS from one face neighbour, `visited == volume − 1`) and `new` must be one component; a weak hole heuristic when `new` is medium; a precheck exempts cells that are already fragmented | both | **hard**: called only after Metropolis accepts (`Potts3D.cpp` ~l.615), any nonzero value rejects; per-type `Penalty` only switches on | medium exempt; holes "reduced, not eliminated" (source comment) | 2D, 3D, hex | O(V) BFS per accepted flip, plus the precheck BFS; last-pixel fast path looks undefined (liveness survey l.639) |
| CC3D `ConnectivityGlobal` `<FastAlgorithm/>` | cell sites in the order-2 (2D Moore 8) or order-3 (3D 26) shell; face BFS among them | `old`'s shell sites one piece; `new` must have a face neighbour at the target | both | hard | no hole check | 2D, 3D, hex | local, conservative |
| Morpheus `ConnectivityConstraint` | the surface neighbourhood (distance < 1.5 in 2D, ≤ 1.75 in 3D) | 2D: one section on the ring for both cells, plus first-order conditions: the losing cell may not lose a site all of whose face neighbours are its own (hole), the gaining cell needs a face neighbour; 3D: face-connected components of the shell = 1 plus the same first-order conditions | both | hard (update checker) | per CellType; medium exempt unless declared | 2D square/hex, 3D | relies on angular stencil order (a source TODO says so) |
| Artistoo `LocalConnectivityConstraint` | Moore neighbours; **Moore (8-)adjacency** among them | the losing cell's neighbours form exactly 1 Moore-connected component | losing | hard | medium exempt; no hole check | 2D, 3D | allows holes |
| Artistoo `ConnectivityConstraint` (experimental) | border pixels per cell | shortcut if fewer than 2 von Neumann neighbours differ; else Moore components of the cell's *border* pixels must not increase | losing | hard | — | 2D (shortcut), 2D/3D | border components are a proxy (a cell with a hole has 2) |
| Artistoo `SoftConnectivityConstraint` | border pixels | ΔH = λ[(1 − C′)² − (1 − C)²], C = Σ (V_piece/V)² over border components | losing | soft, state-like | — | 2D/3D | proxy as above |
| Artistoo `SoftLocalConnectivityConstraint` | `NBH_TYPE` Neumann by default (docs: Moore gives artefacts) | λ if the local same-cell neighbours form > 1 component | losing | soft | — | 2D only | — |
| TST `ConnectivityPreservedP` (`ca.cpp` ~l.2348) | cyclic 8-ring | refuse only if transitions > 2 **and** (distinct non-medium ids including `old` > 2, or medium on the ring); zero arcs pass | losing | soft threshold: `conn_diss` is a yield shift, accept if ΔH ≤ −s, else exp(−(ΔH+s)/T) | medium exempt; the frame is σ = −1, a distinct "cell" | 2D | allows splits at two-cell interfaces by design ("to prevent stalling"); allows holes |
| TST `ConnectivityPreservedPCluster` | same | the same test for clusters | losing | soft | — | 2D | — |
| Chaste CPM | — | none (plain Metropolis on Moore neighbours) | — | — | — | 2D/3D | — |
| Durand & Guesnet 2016, CPC 208:54, doi:10.1016/j.cpc.2016.07.030 | adjacency Na (VN-4 in 2D square, face-6 in 3D, 6 hex), connectivity domain Dc ⊇ Na (Moore-8 in 2D) | 3c: the losing cell must be locally connected (its Na sites connected within Dc); 4c: the gaining cell must **not** be locally connected (forbids handles, keeps cells simply connected); targets drawn among distinct neighbour values; Nt ⊆ Na makes gains connected by construction | both | hard | footnote: seeded growth from medium needs medium fragmentation allowed | 2D square/hex/triangular, 3D (asserted) | 3c too strict for multiply connected cells (their Fig. 5) |

Two later results matter for 3D and for Julia: Belousov et al. 2024 (*PRL* 132:248401,
doi:10.1103/PhysRevLett.132.248401, SM §3) show that Durand & Guesnet's 3D test lets one of
10 neighbourhood classes create a hole, and add a veto for it; CellularPotts.jl (Gregg &
Benos 2024, *Bioinformatics* 40:btad773, doi:10.1093/bioinformatics/btad773) forbids moves
at articulation points of a cell's site graph, an exact global test.

**Digital topology** (DOIs checked; the statements below are the standard results, to be
re-read before the paper cites them): Kong & Rosenfeld 1989 (CVGIP 48:357,
doi:10.1016/0734-189X(89)90147-3) pair adjacencies (4,8)/(8,4) in 2D and
(6,26)/(26,6) in 3D: the foreground and the background must use dual adjacencies, or
"connected" and "has a hole" stop meaning anything. Bertrand & Malandain 1994 (Pattern
Recogn. Lett. 15:169, doi:10.1016/0167-8655(94)90046-9): x is simple for X iff the topological numbers T(x, X) = 1 and T̄(x,
X̄) = 1, computed in the 26-shell (T6 in the geodesic 18-neighbourhood). Deleting or adding
a simple point changes neither the components, the holes (2D) nor the cavities and tunnels
(3D). The 2D test is a 256-entry table (Yokoi's connectivity number gives the same answer
branch-free); none of the surveyed CPM codes uses a table.

**How the Potts rules relate** (2D square, cell `old`, ring mask m of its 8 shell sites):

- `ring_arcs` = number of runs of m. Runs = 4-components of m inside the ring, **including
  corner pieces that do not touch the target**.
- Topological number T4 = 4-components of m that contain a face neighbour of the target.
  So `ring_arcs ≥ T4`: the arc count over-counts a lone corner piece and is therefore
  conservative.
- `ring_arcs == 1` and m ≠ full ⇒ the complement is one arc ⇒ T̄8 = 1 and T4 ≤ 1. So `Local()`
  never creates a hole when it deletes, *except* in the full-ring case, which `_arcs`
  counts as 1 and accepts. A full ring is reachable only when the source lies outside the
  shell (proposal radius > 1, e.g. `NeighborOrder(4)`).
- `ring_arcs == 1` is sufficient for both 4- and 8-connectivity of `old` to be kept.
  Artistoo's count (8-adjacency among ring sites) is T8 and is less conservative.
- Hex: the 6-ring is self-dual and every ring site touches the target, so `arcs == 1` and
  not full is exactly the simple-point test.
- 3D: `local_components` counts 6-components of the whole 26-shell, including edge and
  corner pieces that do not touch the target (conservative against T6), checks nothing on
  the background, and returns 1 for a full shell. So 3D copies can create cavities (only
  with proposal radius > 1) and **tunnels** (with any proposal), which no surveyed tool
  checks either.

---

## 4. Future-model needs

From `docs/design/research/model-specs/` and the shipped models.

| Model | What it needs | Covered by the recommendation? |
|---|---|---|
| 01 Merks 2006 | TST soft ring rule, E₀ = 5000 (D-050 M3), frame as a cell at edges | yes: `@drive connectivity(endothelial; rule = ArcOrPair(), penalty = E₀)`; frame semantics via P6.0ae (Q5) |
| 01 Merks 2008 | no rule (`conn_diss = 0`), `NeighborOrder(4)` proposals | nothing to add; the gain-side caveat (§8.4) belongs in its deviations table if fragments appear |
| 04 foam (dry) | no medium; bubble sides = distinct neighbours over `VonNeumann(1)` (spec l.154); no T2 | `distinct` fold gives sides; `Simple()` is available if bubbles must not split; `ArcOrPair()`'s pair clause behaves as TST with no medium |
| 05 Bauer 2009 | soft **state** energy α(1 − δ) per EC from an exact BFS, kT-dependent (spec l.65, G4); stroma as multiply connected collective cells with **no** rule | yes: `cells(endothelial) => α * (pieces > 1)` with `pieces` exact (P6.9); kind classes keep the stroma out |
| 06 Jiang 2005 (3D) | the necrotic core must **not** be constrained (spec l.351); 3D cost | yes: per-kind selection; the 3D kernel speed-up (§9) helps any 3D rule |
| 07 Bauer 2007 | optional local rule at kT = 0.01 | yes |
| 08 FBCA | connected domains stated, not enforced | optional `connectivity(cell)` |
| 09 cell sorting | connected components of the **cell graph** as observables (V-PRE5, 14, 15) | not a site-connectivity feature; an analysis function over contacts. Out of scope, listed in §5.3 |
| 10 Akeeb | CC3D local rule + `no_extinction` | yes, unchanged (`Local()`) |
| 11 Jafari | state energy α(1 − δ_{a,a′}), a′ = "number of continuous lattice sites" (spec l.51) | yes with `largest_piece`: `cells(k) => α * (largest_piece != volume)`; or `pieces > 1` if a′ is read as a component test (an author question) |
| 12 Zajac | none | — |
| 13 myxobacteria | segments form a connected row; no rule; V14 counts disconnected segments | `pieces` as an observable; cluster connectivity locally with the fold form if a variant wants it |
| 14 Fortuna (3D) | three compartments in one CC3D cluster, no Connectivity plugin; the nucleus stays inside by contact energies | nothing required; optional cluster rule `@constraint pieces(n for n in shell(target) if cluster[owner[n]] == cluster[old]) <= 1 | (cluster[new] == cluster[old])`; enclosure as a contact fold (§8.6) |
| 15 OpenVT monolayer | the CC3D legacy set has a Connectivity penalty 10⁵ (spec l.126); Q24 asks about crushed cells | yes: `@drive connectivity(cell; penalty = 1e5)` or the hard form |
| WortelAct | TST ring rule (`connected = true`) | yes: `ArcOrPair()` |

Nothing in the 15 specs needs a model-named connectivity path. Two needs are not met by the
first-pass proposal: the state energy (05, 11) and per-set pieces (clusters, 13/14). The
recommendation meets both with general primitives.

---

## 5. Connectivity in the CPM literature: coverage and what it unlocks

Method: framework source code (§3) plus papers read in full text through PMC or arXiv,
with DOIs checked against Crossref. **[unverified]** marks what could not be confirmed
from a primary source. "Today" is the vocabulary on `origin/monorepo`; "Recommended" is §8.

### 5.1 Forms of connectivity and topology constraint, and whether we can express them

| # | Form | Source (paper, code) | Today | Recommended | How, or the minimal general primitive that closes the gap |
|---|---|---|---|---|---|
| 1 | Local ring test with gain face-neighbour test, full ring refused, soft 64 | CC3D `Connectivity` (`plugins/Connectivity/ConnectivityPlugin.cpp`); docs https://pythonscriptingmanual.readthedocs.io/en/latest/connectivity.html | approx (no gain test; full ring accepted; veto, not 64) | **exact** for proposal radius 1 | `@drive connectivity(k; rule = Local(; gain = true), penalty = 64.0)`. With longer proposals the full-ring case still differs (Q10) |
| 2 | Per-cell switch of form 1 | CC3D `ConnectivityLocalFlex` | approx | **exact** | `@constraint (s[old] <= 0) \| connected(old; rule = Local(; gain = true))`, `s` a cell variable |
| 3 | Global BFS after acceptance, both cells, precheck exempts fragmented cells, weak hole heuristic | CC3D `ConnectivityGlobal` (`plugins/ConnectivityGlobal/…`, `Potts3D.cpp` ~l.615) | not | approx | `rule = Global()`: "does not increase pieces" reproduces the precheck's intent; the medium hole heuristic is not reproduced (`Simple()` is the principled replacement) |
| 4 | Local face-BFS among the cell's order-2/3 shell pixels, gain face test | CC3D `ConnectivityGlobal <FastAlgorithm/>` | not | approx | `Local(; gain = true)`; CC3D also requires the gaining cell's shell pixels plus the target to be one piece, which `Simple()` covers |
| 5 | One section on the ring for both cells, first-order hole and attachment guards (2D) | Morpheus `ConnectivityConstraint`; Starruß et al. 2014, *Bioinformatics* 30:1331, doi:10.1093/bioinformatics/btt772 | not | approx | `Simple()` is the exact topological version of the same intent |
| 6 | Same, 3D: one 6-component of the 26-shell plus guards, no background test | Morpheus | not | approx | `Simple()` is stricter (it also refuses tunnels) |
| 7 | Losing cell's ring sites one **8-connected** component | Artistoo `LocalConnectivityConstraint` (https://github.com/ingewortel/artistoo, `src/hamiltonian/`) | approx (we join ring sites by faces only) | approx; exact if Q4 adds `Local(; adjacency = :full)` | — |
| 8 | λ if locally disconnected, von Neumann neighbourhood by default | Artistoo `SoftLocalConnectivityConstraint` | approx | approx | `@drive connectivity(k; penalty = λ)`; Artistoo's component definition over the 4 VN sites differs in corner cases |
| 9 | Moore components of the cell's **border pixels** must not increase | Artistoo `ConnectivityConstraint` | not | approx | `Global()` counts cell components instead; they differ for cells with holes |
| 10 | λ[(1−C′)² − (1−C)²], C = Σ (V_piece/V)² over border components | Artistoo `SoftConnectivityConstraint` | not | approx | `cells(k) => λ * (1 - largest_piece / volume)^2` keeps the shape of the penalty; the exact form needs per-piece sizes, a primitive not worth adding for one framework |
| 11 | Ring rule with two-cell exemption, soft yield threshold `conn_diss` | TST `ConnectivityPreservedP` (https://github.com/mathbioleiden/Tissue-Simulation-Toolkit, `src/cellular_potts/ca.cpp`); Merks et al. 2006, *Dev Biol* 289:44, doi:10.1016/j.ydbio.2005.10.003 | exact except at closed edges (P6.0ae) | **exact** | `@drive connectivity(k; rule = ArcOrPair(), penalty = conn_diss)` |
| 12 | Ring rule for clusters | TST `ConnectivityPreservedPCluster` | not | **exact** | fold form: `pieces(n for n in shell(target) if cluster[owner[n]] == cluster[old]) <= 1 \| ((distinct(cluster[owner[n]] for n in shell(target) if owner[n] != 0) == 2) & (count(owner[n] == 0 for n in shell(target)) == 0))` |
| 13 | TST-derived constraint in later papers | Boas & Merks 2015, *BMC Syst Biol* 9:86, doi:10.1186/s12918-015-0230-7; Daub & Merks 2013, *Bull Math Biol* 75:1377, doi:10.1007/s11538-013-9826-5; Niculescu et al. 2015, *PLoS Comput Biol* 11:e1004280, doi:10.1371/journal.pcbi.1004280; Rens & Edelstein-Keshet 2019, *PLoS Comput Biol* 15:e1007459, doi:10.1371/journal.pcbi.1007459; Burger et al. 2022, *Front Cell Dev Biol* 10:854721, doi:10.3389/fcell.2022.854721 | exact | **exact** | `ArcOrPair()` |
| 14 | Losing cell locally connected (3c), gaining cell not locally connected (4c), targets drawn among distinct neighbour values | Durand & Guesnet 2016, *Comput Phys Commun* 208:54, doi:10.1016/j.cpc.2016.07.030; Durand 2021, *PLoS Comput Biol* 17:e1008576, doi:10.1371/journal.pcbi.1008576 | not | **exact** (the tests) | `Simple()` with `VonNeumann(1)` proposals. The distinct-value proposal law is a separate feature (P6.4b `ProposalLaw`) |
| 15 | 3D version of 14 with an extra veto: the original 3D test lets one of 10 neighbourhood classes create a hole | Belousov et al. 2024, *PRL* 132:248401, doi:10.1103/PhysRevLett.132.248401 (SM §3) | not | **exact**, to be confirmed by the 3D oracle | `Simple()` uses the topological numbers T6/T̄26, which are exact by theorem; the 3D oracle (§12) must include Belousov's Fig. S7h configuration |
| 16 | 15 with the ECM exempt ("allowed to fragment and vanish") | Moghe et al. 2025, *Nat Cell Biol*, doi:10.1038/s41556-025-01618-9 | not | **exact** (connectivity part) | per-kind selection: `connectivity(cells_not_ecm; rule = Simple())`; their time-continuous CPM is another missing feature |
| 17 | Moves at articulation points of a cell's site graph forbidden (Hopcroft–Tarjan) | CellularPotts.jl: Gregg & Benos 2024, *Bioinformatics* 40:btad773, doi:10.1093/bioinformatics/btad773 | not | **exact** | `Global()` (an articulation point is exactly a site whose removal increases the piece count) |
| 18 | Soft **state** energy α per fragmented cell, exact BFS | Bauer et al. 2009 (spec 05, Eq 1) | not | **exact** | `cells(k) => α * (pieces > 1)` |
| 19 | α(1 − δ_{a,a′}), a′ = connected sites | Jafari Nivlouei et al. (spec 11, Eq 3) | not | **exact** | `cells(k) => α * (largest_piece != volume)` |
| 20 | Euler characteristic or genus of a cell (proposed for planar graphs in CellularPotts.jl) | Gregg & Benos 2024 | not | **not** | minimal primitive: a cell-scope `euler` tracker. χ changes by an amount computable from the 3×3 (2D) or 3×3×3 (3D) neighbourhood (bit-quad / octant counting), so it is exact, local and cheap, and `holes = pieces − euler` in 2D follows. Not needed by any of our 15 models |
| 21 | Fragmentation discouraged indirectly by perimeter and adhesion | general; Durand 2021 estimates a fragment of size l costs ≈ γl | exact | **exact** | `Surface`, `contacts` |
| 22 | Local hole prevention | Durand & Guesnet 4c; Morpheus hole guard; CC3D full-ring refusal | not | **exact** | `Simple()` |
| 23 | 3D tunnels and cavities | Belousov 2024 (holes); no surveyed tool tests tunnels | not | **exact** | `Simple()` |
| 24 | Compartment cluster connectivity | CC3D compartments (no enforcement found); TST cluster rule (row 12) | not | approx | local: fold form (exact); a global cluster piece count would need cluster-scope `pieces` (`clusters(k) => α * (pieces > 1)`), the same BFS over the cluster's cells. Not needed by 13 or 14 |
| 25 | Nucleus kept inside by the contact-energy hierarchy, plus centroid springs between compartments | Fortuna et al. 2020, *Biophys J* 118:2801, doi:10.1016/j.bpj.2020.04.024; Kumar, Das & Sen 2018, *Mol Biol Cell* 29:1599, doi:10.1091/mbc.E17-05-0313 | exact | **exact** | `contacts => J[kind, kind′]`; springs as `edges(rel) => k * (distance - d)^2` (D-058) |
| 26 | Hard enclosure (a nucleus site never next to medium) | (a modelling choice; no paper found enforcing it) | exact | **exact** | contact fold in a constraint (§8.6) |
| 27 | Links between cells with length energies, formed on contact and broken beyond a distance | CC3D `FocalPointPlasticity` (docs: https://pythonscriptingmanual.readthedocs.io/en/latest/focal_point_plasticity.html) | exact | **exact** | `@relationship`, `@link`/`@unlink`, `edges(rel)` (D-058). Starruß et al. 2007 segment linkage: **[unverified]** |
| 28 | A shared lumen state whose number of components is the phenotype (multi-lumen) | Cerruti et al. 2013, *J Cell Biol* 203:359, doi:10.1083/jcb.201305044 | approx (hand analysis) | approx | an analysis function `connected_components(u; select, adjacency)` over a site set (§5.3); a lumen-preserving local rule is the fold form (exact) |
| 29 | Tissue-level connectivity as an observable or quality control | Merks 2006 (lacunae), Merks 2008 *PLoS Comput Biol* 4:e1000163 doi:10.1371/journal.pcbi.1000163 (islands vs network), Popławski et al. 2010 *PLoS ONE* 5:e10641 doi:10.1371/journal.pone.0010641, Morpheus `clustering_tracker`, Wortel et al. 2021 *Biophys J* 120:2609 doi:10.1016/j.bpj.2021.04.036 ("connectedness" QC; formula **[unverified]**), spec 09 V-PRE5/14/15 | approx (per-reproduction code) | approx | the analysis function above; Wortel's connectedness approximated by `largest_piece / volume` per cell |
| 30 | A cell is removed when its volume reaches 0 | Artistoo `CPM.js`; D-066 | exact | **exact** | — |
| 31 | "Remove fragments" / keep the largest piece | none found in the surveyed codes | not | **not** | minimal primitive: a site-scope Boolean `in_largest_piece` (from the P6.9 BFS) readable in a host-pass site update |
| 32 | Foam: T2 = a bubble reaching zero area; no splitting by low T | Glazier, Gross & Stavans 1987, *PRA* 36:306, doi:10.1103/PhysRevA.36.306; Glazier & Weaire 1992, *J Phys Condens Matter* 4:1867, doi:10.1088/0953-8984/4/8/004; Holm et al. 1991, *PRA* 43:2662, doi:10.1103/PhysRevA.43.2662 | exact | **exact** | liveness (D-066); optional `Simple()`; sides and T1 counts with `distinct` |
| 33 | Updates only at the cell periphery "because cells do not form spontaneous holes" | Albert & Schwarz 2014, *Biophys J* 106:2340, doi:10.1016/j.bpj.2014.04.036 | exact | **exact** | nearest-neighbour proposals make interior picks null moves (D-177) |

No dedicated perimeter-based fragmentation penalty was found (searched; row 21 is the
indirect form). Kabla 2012 (doi:10.1098/rsif.2012.0448), Vroomans et al. 2015
(doi:10.1371/journal.pcbi.1004092) and Szabó & Merks 2013 (doi:10.3389/fonc.2013.00087)
use no connectivity rule. Not checked: Marée et al. 2006 keratocyte
(doi:10.1007/s11538-006-9131-7), Guisoni et al. 2018, Scianna & Preziosi 2012
(doi:10.1137/100812951; enclosure mechanism **[unverified]**).

### 5.2 Tally

| | Today | Recommended |
|---|---|---|
| exact | 9 of 33 | 20 of 33 |
| approximately | 6 | 11 |
| not at all | 18 | 2 (rows 20, 31) |

Both remaining gaps close with one general primitive each (`euler`, `in_largest_piece`);
neither is needed by the 15 specs, so neither is recommended now.

### 5.3 Papers this would make reproducible or easier

"Connectivity only" means the connectivity part was the only missing piece; "other" lists
what else is missing.

| Paper | On our list? | Connectivity need | Other missing features | Value |
|---|---|---|---|---|
| Bauer et al. 2009 (spec 05) | yes | state energy `pieces > 1` | `@create`, branch/loop detection (P6.9) | high (paper model) |
| Jafari Nivlouei et al. (spec 11) | yes | `largest_piece` energy | Boolean networks, tables (P6.10) | high (paper model) |
| Merks et al. 2006 (spec 01) | yes, shipped | `ArcOrPair` soft | — | done; P6.0ae edges |
| OpenVT monolayer, CC3D set (spec 15) | yes | CC3D penalty 10⁵ | — | exact CC3D form via row 1 |
| Durand & Guesnet 2016; Durand 2021 | no | `Simple()` | distinct-value proposal law (P6.4b) | **high**: an algorithmic benchmark (fragment-free sorting, coarsening exponent 1/4) that tests the constraint directly |
| Burger et al. 2022 | no | `ArcOrPair` (already today) | none known (Act model exists: `WortelAct`) | **high**: the speed–density trend reverses with the constraint, a direct semantic test; reachable now |
| Boas & Merks 2015 | no | `ArcOrPair` (today) | per-cell Notch–Dll4 ODEs (components exist) | medium; reachable now |
| Daub & Merks 2013 | no | `ArcOrPair` (today) | ECM–cell feedback field (partly available) | medium |
| Wortel et al. 2021 (3D Act) | no | connectedness QC (`largest_piece`) | 3D Act at scale | medium |
| Belousov et al. 2024; Moghe et al. 2025 | no | `Simple()` 3D, per-kind exemption | time-continuous (rejection-free) CPM | **high** (PRL, Nat Cell Biol) but blocked on the time-continuous sweep |
| Cerruti et al. 2013 | no | lumen component analysis | 3D polarity model | medium |
| Kumar, Das & Sen 2018 | no | none (energies) | compartments exist (D-036) | low for this feature |
| Rens & Edelstein-Keshet 2019 | no | `ArcOrPair` (today) | force analysis | low for this feature |
| Rens & Merks 2017 | no | hard split veto (method unstated) | FEM substrate mechanics | blocked elsewhere |
| CellularPotts.jl models (Gregg & Benos 2024) | no | `Global()` | graph lattices | low; a natural comparison point in Julia |

### 5.4 Conclusion: does a compositional layer widen the reachable literature?

Modestly in papers, substantially in fidelity.

- **Forms:** exact coverage of the 33 surveyed forms rises from 9 to 20, and "not
  expressible" falls from 18 to 2.
- **Papers:** of the 15 papers in §5.3, the connectivity layer is the *last* missing piece
  for 2 on our list (Bauer 2009 and Jafari already wait on P6.9/P6.10 for other features),
  and for 1 outside it (Durand & Guesnet / Durand 2021, together with P6.4b's proposal law).
  Five TST-derived papers are already reachable today through `ArcOrPair`. Belousov 2024 and
  Moghe 2025 stay blocked on a time-continuous sweep.
- **Fidelity:** every major framework's rule (CC3D local, local-flex, global, fast; Morpheus;
  Artistoo four ways; TST and its cluster form; Durand & Guesnet; CellularPotts.jl) gets a
  documented one-line equivalent. Of the 16 framework and algorithm rules (rows 1–12 and
  14–17), 8 become exact (today 1, TST) and the other 8 approximate (today 4 are approximate and 11 not expressible). That matters for the CC3D and Morpheus corpora, where connectivity
  plugins are common. How common is unmeasured: a scan of the CC3D demo and Morpheus model
  repositories would give the number (proposed as part of P6.3g's docs work).
- So the case for the layer rests on robustness (holes, gain side, exactness labels) and on
  one obvious way to port any framework's rule, more than on new papers.

---

## 6. The questions behind the vocabulary

A connectivity feature answers one of four questions. Keeping them apart is most of the
design.

1. **May this copy break the losing cell?** A copy-scope Boolean (veto or penalty). Local
   tests answer it conservatively; a global BFS answers it exactly.
2. **Does this copy change the cell's topology at all?** (pieces, holes, tunnels; both
   cells). The simple-point test answers it locally and exactly for the (face, full)
   adjacency pair.
3. **How many pieces is the cell in now?** A cell-scope state quantity: energies (Bauer,
   Jafari), observables (V14), lifecycle rules ("kill fragments").
4. **What is around the target?** Raw local counts (`pieces` of any site set, `distinct`,
   `count`) from which modellers build their own rules.

The first-pass proposal merges (1) and (3) through `scope`, and has no answer to (2).

---

## 7. Audit of the first-pass proposal

Each item: the claim, what is wrong or missing, the fix.

**Item 1: one primitive `pieces(c, region)` with `around(target; relation)`.**

- W1. *A free region is not a test.* For the 8-ring, counting every piece works (and is
  what CC3D and TST count). In a larger window it counts pieces of the same cell that do
  not touch the target (a U-shaped cell's other arm) and refuses ordinary copies. A window
  test must count only the pieces that touch the target (topological number) and then show
  that those pieces meet inside the window. That is a BFS, not a fold. Fix: restrict the
  primitive to the shell in v1; windows exist only inside `Global(; window)`, where the
  device BFS needs them (D-075 Q6).
- W2. *Adjacency is unstated.* In 2D square the same mask gives 2 pieces under
  4-adjacency and 1 under 8 (edge sites (0,−1) and (−1,0) with an empty corner). Fix: define
  `pieces` under lattice face adjacency (today's meaning) and state it; give `Simple()` the
  dual pair.
- W3. *The argument `c` is a cell id.* That cannot say "this cluster", "endothelial cells as
  a class" or "the medium" (a lumen must stay open). Fix: make `pieces` a fold over a
  predicate, `pieces(n for n in shell(target) if pred(n))`, with `pieces(c, shell(target))`
  as sugar.
- W4. *"After the copy" is implicit.* The target is excluded from the shell, so shell owners
  are the same before and after; the definition must say so, and reject a relation that
  includes the target (`include_self`).
- W5. *`ring_cells → distinct(owner[s] for s in around(target))`.* There is no `distinct`
  fold today; it is a new fold (a useful one: foam sides, OpenVT neighbour counts). Folds
  skip out-of-domain sites, so the TST reading the maintainer ruled for closed edges (frame
  counts as a cell, D-156) cannot be written as a fold. Fix: add `distinct`; keep the TST
  edge semantics inside the `ArcOrPair()` value.

**Item 2: rules as values, `connectivity(k; rule = Connected(), penalty = E₀)`.**

- W6. *Soft under `@constraint`.* Constraints veto before ΔH (`sequential.jl:28`); drives
  are ΔH terms, summed by `track = (:ΔH,)` and listed by `drives(sys)` (D-160). A penalty in
  a constraint would be a ΔH term the docs, `track` and the metadata do not see. Fix: the
  same helper in both statements; `@constraint` without `penalty`, `@drive` with it, and a
  build error that points to the other statement.
- W7. *`Connected()` = CC3D.* CC3D's local plugin also requires a gaining face neighbour,
  refuses a full ring, and is a soft 64 in current source (§3). Potts' `:local` differs on
  all three (D-074 matched only the zero-piece case). Fix: name rules for what they test
  (`Local`, `ArcOrPair`, `Simple`, `Global`); put the framework mapping in a table.
- W8. *`ConnectedOrSeam()`.* "Seam" is undefined, and the TST pair clause does not keep
  cells connected: it accepts real splits where only two cells meet, by design. Calling it
  "Connected…" misleads users. Fix: `ArcOrPair()`, the name the docs already use.

**Item 3: `@rule splits(c) = …`.**

- W9. *Redundant.* A plain definition in the model body already works and is the
  documented idiom (`act_mean(s) = geomean(…)`, `wortel_act.jl:47`). A macro adds a DSL
  keyword and a guardrail entry for nothing. Fix: document the plain function.
- W10. *The name `splits` overclaims.* A local test says "might split". Under `Local()` the
  expression is true for some copies that split nothing. Fix: `connected(c; rule)` returns
  what the rule decides; the docstring of each rule says whether it is exact or
  conservative.

**Item 4: `scope = Local() | Global()`.**

- W11. *False orthogonality.* `ArcOrPair` × `Global` and `Simple` × `Global` have no
  meaning. Fix: `Global(; window)` is one more rule value.
- W12. *Wrong shape for the paper models.* Bauer 2009 and Jafari charge α while a cell
  *is* fragmented: a reconnecting copy earns −α, the gaining cell counts, and the term must
  be in `total_energy` and the self-check (api-synthesis §2.5). A copy drive cannot do this.
  Fix: a cell-scope `pieces` with an exact after-value (like `major_length`), usable in
  `@energy`.
- W13. *Global semantics unstated.* Which cells (losing only, or also gaining)? Refuse
  "≠ 1 piece after" (freezes already-fragmented cells, which CC3D's precheck exists to
  avoid) or "more pieces than before"? May a cell die? Fix: §8.2.

**Item 5: pattern-matched kernels, CSE, deprecated aliases.**

- W14. *CSE across functions does not exist.* The constraint and ΔH are separate generated
  functions (`codegen.jl:371`, `:168`), so a model with a hard rule and a soft drive reads
  the shell twice. Within one function, codegen should bind the shell owners once.
- W15. *"No slowdown" is about the cheap part.* The local kernels already cost little. The
  cost that matters is the global BFS. Two free wins are missing: evaluate an expensive
  constraint *after* the acceptance draw (bitwise identical under the counter RNG, §9.3),
  and stop the BFS when the smaller piece is exhausted.
- W16. *Aliases must lower to identical `Expr`s,* or fingerprints and code pins change
  (D-016, D-107). The DSL surface snapshot (`guardrails.jl:143-155`) changes by design and
  must be re-reviewed. The frozen `p6_3a` test asserts `components(old; scope = Global())`
  throws; keep `components` as an alias until P6.9 re-freezes it.

**Missing from the proposal entirely.**

- W17. *The gaining cell.* With Moore(1) proposals (Merks 2006, WortelAct) a cell can gain
  a site that touches it only at a corner; with `NeighborOrder(4)` (Merks 2008), a site that
  does not touch it at all. Losing-side tests never see this. CC3D, Morpheus and Durand &
  Guesnet test the gaining cell. Fix: `Simple()` checks both cells; `Local(; gain = true)`
  adds CC3D's face-neighbour test (Q3).
- W18. *Holes, cavities and tunnels.* Not expressible with any piece count of the cell.
  Fix: `Simple()`.
- W19. *Periodic axes shorter than 3* alias shell sites (on a length-2 axis, offsets −1 and
  +1 are the same site). Fix: a build-time `ArgumentError` for any shell rule.
- W20. *`components` clashes with MTK's `@components` and `ModelingToolkit.get_systems`.*
  Fix: `pieces` for both the local and the global count.

---

## 8. Recommended design and semantics

### 8.1 Definitions (all geometries)

A proposal copies `new = σ(source)` into `target = x`, whose owner was `old`.

- **Shell** `shell(x)`: the in-domain sites among the 8 sites of the 3×3 box around x
  (square 2D), the 6 neighbours (hex), the 26 sites of the 3×3×3 box (cubic 3D). Periodic
  axes wrap; an axis must have length ≥ 3. Out-of-domain sites (a `Closed()` face, a domain
  mask) are not in the shell for any fold. The shell is fixed whatever the model's
  `neighborhood` (as today, D-140). The copy never changes a shell site.
- **Face adjacency**: 4 in 2D square, 6 hex, 6 in 3D cubic.
- **`pieces(n for n in shell(target) if pred(n))`**: the number of connected components,
  under face adjacency, of the shell sites where `pred` holds. Sugar: `pieces(c,
  shell(target)) ≡ pieces(n for n in shell(target) if owner[n] == c)`; for `c = old` this is
  today's `local_components` and `ring_arcs`, exactly.
- **`connected(c; rule)`**, `c ∈ {old, new}`: the copy-scope Boolean "under `rule`, cell `c`
  stays connected through this copy". It is `true` when `c` is the medium.
- **`connectivity(kinds…; rule = Local(), penalty = nothing)`**: in `@constraint`,
  `(old == 0) | !(kind[old] ∈ kinds) | connected(old; rule)` (and the same for `new` when
  the rule tests the gaining cell); in `@drive`, `penalty * !(that)`. A `penalty` in
  `@constraint`, or no `penalty` in `@drive`, is an `ArgumentError` naming the other
  statement.
- **Cell scope `pieces`, `largest_piece`**: the number of face-connected components of the
  cell's sites, and the site count of the largest one, exact, with exact after-values for
  `old` and `new` (P6.9).
- **`distinct(body for n in rel(site) if cond)`**: the number of distinct values of `body`.

### 8.2 Rule values

| Rule | `connected(old)` is true iff | Gaining cell | Last site | Exact or conservative | Source |
|---|---|---|---|---|---|
| `Local()` | `pieces(old, shell(target)) == 1` | not tested (Q3: `gain = true` adds "`new` owns a face neighbour of x") | refused (D-074) | conservative for splitting; accepts the full-shell hole | CC3D `Connectivity` minus its gain test, full-ring test and soft 64; Artistoo local with face adjacency |
| `ArcOrPair()` | `pieces(old, shell) ≤ 1`, or exactly two distinct owners > 0 on the shell (frame counting per Q5) and no medium site there | not tested | allowed (zero arcs pass) | deliberately not a connectivity test: it allows splits at two-cell interfaces | TST `ConnectivityPreservedP`, Merks et al. 2006/2008, Niculescu et al. 2015 |
| `Simple()` | x is a simple point of `old`: T(x, old) = 1 and T̄(x, not old) = 1, with face adjacency for the cell and full adjacency (8, or 26) for the complement | x is a simple point of `new ∪ {x}` (same test on `new`'s shell sites) | refused (T = 0) | exact locally: the copy changes no cell's number of pieces, holes (2D), cavities or tunnels (3D) | Bertrand & Malandain 1994; Durand & Guesnet 2016 tests 3c/4c; Morpheus' first-order conditions |
| `Global(; window)` | the copy does not increase the number of pieces of `old` (global, face adjacency) | the copy does not increase the number of pieces of `new` | allowed (pieces fall to 0) | exact on Sequential and BoundarySite; on the checkerboard exact unless the window overflows, then refused and counted | CC3D `ConnectivityGlobal` (without its hole heuristic); Bauer 2009 |

Notes:

- "Does not increase" instead of "is exactly 1" keeps already-fragmented cells movable, as
  CC3D's precheck intends, without a precheck BFS.
- `Simple()` with medium as `new` tests that removing x from `old` creates no hole; with
  medium as `old`, only `new` is tested (medium may fragment, as Durand & Guesnet's footnote
  requires for growth from medium).
- On hex, `Local()` and `Simple()` differ only in the full ring and the gaining cell.
- 3D caution: Durand & Guesnet's own 3D local test misses one hole-creating class
  (Belousov et al. 2024). `Simple()` uses the topological numbers, which are exact by
  theorem, but its acceptance must include that configuration in the 3D oracle (§12).

### 8.3 Syntax for every common case

```julia
# CC3D-style hard local rule, every kind (medium exempt)
@constraint connectivity()
# per kind and per class (D-135 classes work wherever kinds do)
@constraint connectivity(leader, follower)
# TST / Merks 2006: soft E₀, the yield-threshold drive of D-140, unchanged in meaning
@drive connectivity(endothelial; rule = ArcOrPair(), penalty = E₀)
# CC3D's local plugin as it really behaves today (soft 64, gain test)
@drive connectivity(cell; rule = Local(; gain = true), penalty = 64.0)
# whole-cell hard rule (CC3D ConnectivityGlobal), P6.9
@constraint connectivity(endothelial; rule = Global())
@constraint connectivity(endothelial; rule = Global(; window = 12))   # device window
# Bauer 2009 / Jafari state energy, P6.9
@energy cells(endothelial) => α * (pieces > 1)
@energy cells(endothelial) => α * (largest_piece != volume)
# no splits and no holes for either cell (2D, hex, 3D)
@constraint connectivity(cell; rule = Simple())
# a custom predicate: a plain function in the model body, used hard and soft
breaks(c) = pieces(c, shell(target)) > 1
@constraint !(breaks(old) & (kind[old] ∈ epithelium))
@drive copy => λ * breaks(old)
# allow death but not splitting
@constraint connected(old) | (volume[old] == 1)
# cluster (compartment) connectivity: the cell's compartments together stay one piece
@constraint (cluster[new] == cluster[old]) |
            (pieces(n for n in shell(target) if cluster[owner[n]] == cluster[old]) <= 1)
# a lumen (medium) must not be split by a gaining cell
@constraint (old != 0) | (pieces(n for n in shell(target) if owner[n] == 0) <= 1)
# 3D: the same lines; the shell is the 26 sites
# dry foam: no medium kind, bubbles as cells; ArcOrPair's medium clause never fires
@constraint connectivity(bubble; rule = Simple())
# bubble sides (observable, 04): distinct neighbours over face adjacency
sides(s) = distinct(owner[n] for n in VonNeumann(1)(s) if owner[n] != owner[s])
```

### 8.4 Semantics per geometry, boundaries and corner cases

- **2D square.** Cells are face-connected (4) objects; the background (other cells and
  medium) is treated with 8-adjacency in `Simple()`. With Moore(1) proposals a gain can
  attach a site at a corner only; it is 8- but not 4-connected to the cell. `Local()` and
  `ArcOrPair()` do not see this; `Simple()`, `Global()` and `Local(; gain = true)` refuse
  it. The docs must say which proposal relation makes which guarantee (Durand & Guesnet:
  proposals ⊆ face neighbours make gains connected by construction).
- **Hex.** Self-dual; every shell site touches x; arcs are exact.
- **3D cubic.** Face (6) for the cell, 26 for the background. `Local()` is today's 26-shell
  face count (conservative; allows tunnels). `Simple()` computes T6 in the 18-neighbourhood
  and T̄26 in the 26-shell.
- **Periodic.** Wraps; build error if a periodic axis is shorter than 3 (W19).
- **Closed faces and masks.** Out-of-domain sites are never the cell, never medium, and not
  counted by `distinct`. For `Simple()`'s background count they count as background
  (open-boundary reading: a pocket against a wall is not a hole), recorded as Q7. For
  `ArcOrPair()` they count as one extra distinct owner if Q5 is answered "match TST".
- **Frames.** A `Frame` kind is a real frozen cell: it counts in `distinct` and in
  `ArcOrPair()`, and it never loses a site.
- **Medium.** As `old` it is exempt from every rule (all frameworks agree). It is a valid
  set for the fold form (lumen rules).
- **Last site.** `Local()` and `Simple()` refuse it; `ArcOrPair()` and `Global()` allow it.
  Each docstring says so; `no_extinction` composes with all of them.
- **Multiple constrained cells.** The rule evaluates `old` and, for gain-testing rules,
  `new`, each against its own kind filter.
- **Ill-defined combinations, refused at build with a message:** `pieces` over a relation
  other than `shell`; `shell` with `include_self`; `penalty` in `@constraint`; no `penalty`
  in `@drive connectivity`; `Global(; window)` with a window smaller than the shell; cell-scope
  `pieces` in a copy scope without an index (`pieces[old]` reads the before-value); a
  periodic axis < 3 with any shell rule; `Simple()` on a geometry without a table yet
  (prism or FCC 3D hex, D-044).

### 8.5 Interaction with the rest of the model

- **Drives and `track`.** The soft form is a drive, so `track = (:ΔH,)` sums it as D-140
  states; R18's per-term track can exclude it to mimic TST's SumDH.
- **Acceptance laws.** TST applies `conn_diss` as a yield shift: accept if ΔH ≤ −s. A drive
  `+E₀` under Metropolis with zero offset gives exactly that (D-140, spec 01 §7.3).
- **Bias.** Unaffected (D-140 excludes `bias` from `track`).
- **Lifecycle.** Division can produce fragments when the plane cuts a non-convex cell;
  a "kill fragments" or "keep the largest piece" policy reads cell-scope `pieces` and
  `largest_piece` in a lifecycle rule (P6.9 provides the values; the policy is a rule).
- **Kind classes** (D-135) work wherever kinds do.

### 8.6 Enclosure (nucleus inside a cell)

"The nucleus never touches the medium" is a contact rule, not a connectivity rule:
`@constraint !((kind[new] == nucleus) & any(owner[n] == 0 for n in VonNeumann(1)(target)))`
(and the mirror for the medium gaining a site next to a nucleus). It needs no new name.
"The nucleus lies inside its own cell" (cell-in-cell enclosure, genus) is not expressible
locally in general; Fortuna et al. do not enforce it (spec 14 §4).

---

## 9. Performance plan

### 9.1 Kernels

- **2D square shell.** Read the 8 owners once into an `NTuple{8, Int32}`; build an 8-bit
  mask per predicate. Pieces = runs = `count_ones(m & ~bitrotate(m, 1))` (1 if m = 0xff).
  This replaces the 3×3 flood fill that `rule = :local` runs today in 2D (§2.1).
  `Simple()`: a 256-entry `NTuple{256, UInt8}` table generated at load time from the
  brute-force definition, indexed by the mask (T and T̄ in one lookup).
- **Hex.** 6-bit mask, the same run count; a 64-entry table for `Simple()`.
- **3D.** 26-bit mask; flood fill over set bits with `trailing_zeros` and a constant
  `NTuple{27, UInt32}` table of face-neighbour masks, replacing the per-bit `div`/`rem`
  of `_face_neighbors` (integer division is slow on GPUs). `Simple()` in 3D: T6 by the
  same flood restricted to the 18-neighbourhood and seeded from face neighbours; T̄26 by a
  flood over the complement with a 26-adjacency mask table. No 2²⁶ table.
- **No `Float64`, no `throw`, no allocation** in any of these (INTERNALS §5): masks are
  `UInt32`, tables are constant tuples, counts are `Int32`.

### 9.2 Code generation

- One `shell_owners` binding per generated function when any shell quantity is used
  (pattern: `_PROP_LOCALS` gains `shell = CorePotts.shell_owners(st.σ, ctx, prop)` only
  then). Each `pieces`/`distinct`/`count` over `shell(target)` reads from it. Today's
  three reads become one.
- Pattern-match `pieces(n for n in shell(target) if owner[n] == c)` to the cell kernel and
  the generic predicate form to "evaluate `pred` on the 8/6/26 tuple, then the same mask
  kernel". Both are generic code; nothing is model-named.
- Rules lower to these expressions. `Local()` lowers to exactly today's
  `local_components == 1` expression first (§11), and the faster 2D kernel lands as a
  separate, measured change.
- Unused: no name, no code, no buffer (today's guarantee, D-058 item 4).

### 9.3 Global connectivity cost

- **Post-acceptance evaluation.** Split constraints into cheap (local, evaluated before ΔH
  as today) and expensive (`Global()`, evaluated only when the acceptance draw accepts).
  The draw comes from the counter RNG keyed by (mcs, attempt) (`sequential.jl:16`), so the
  trajectory is **bitwise identical** to evaluating it first. One edge case: a refused copy
  whose ΔH is non-finite now reports `STATUS_NONFINITE` instead of being skipped; evaluate
  the cheap local test first and keep the order "local → ΔH → draw → global". CC3D does the
  same (`Potts3D.cpp` ~l.615).
- **Local first, BFS on failure.** A local pass proves no new piece (given the shell rule
  is sufficient), so the BFS runs only on local failures (api-synthesis §2.5).
- **Interleaved BFS.** After removing x, run one BFS per touching shell piece in lockstep
  and stop when they meet or when one is exhausted (then the cell split). Cost
  O(size of the smaller piece) instead of O(volume).
- **Checkerboard.** The D-075 Q6 design stands: a compacted list of local failures, a
  deferred windowed-BFS kernel with an `MVector` stack proven non-allocating on the CPU by
  AllocCheck, conservative refusal with `stats.connectivity_deferred`, extra launches stated.
  The BFS reads only sites of `old`/`new`, both claimed, so claims stay correct.
- **State energy.** Cell-scope `pieces` is an exact tracker updated at commit from the
  computed after-value; ΔH = α([after(old) > 1] − [before(old) > 1]) + the same for `new`.
- **BoundarySiteCPM.** Calls the same constraint; it is host-side and exact like
  Sequential.

### 9.4 Gates

Per D-171: the paired A/B (`benchmark/ab.jl`) with two same-commit controls, CPU and ROCm
(Metal ±3 % after P6.0bi), plus `benchmark/gate.jl` zero warm allocations. Cases:
`Merks2006` (soft `ArcOrPair`), Akeeb (`Local`), `WortelAct(connected = true)`, one 3D
soft-connectivity case (the p6_3a sibling), and for P6.9 the late-state sprout benchmark
already specified. Acceptance: aliases at parity (code identical, so ≈ 1.00); the 2D and 3D
kernel rewrites must be ≤ 1.00 within the controls' spread; `Simple()` measured and reported,
not gated (new feature).

---

## 10. MTK fit

- Rule values are plain immutable Julia structs, like `Metropolis` and today's `Global`.
  They are build-time configuration; nothing about them is symbolic, so MTK never sees
  them.
- `connected(…)`, `pieces(…)`, `distinct(…)` become Potts symbolic operations, exactly like
  today's `gather` and `population` (`src/vocabulary.jl:376-421`). No `@register_symbolic`,
  no MTK pass, no change to `mtkcompile`.
- `constraints(sys)` keeps returning `Constraint`s; the payload (D-160) can carry the rule
  value for display, and `drives(sys)` lists the soft form as an ordinary drive expression.
  Neither enters code or fingerprints.
- Cell-scope `pieces` joins `major_length` as a built-in with an after-value. `hamiltonian(sys)`
  shows `α * (pieces > 1)` as written; `total_energy` evaluates it by a host BFS.
- **Friction risk: none found.** The only risk is a slowdown in Global (P6.9), already
  covered by D-075's benchmark and the post-acceptance evaluation.

---

## 11. Migration and deprecation

1. Add the new surface; lower `connectivity(k; rule = Local())` and `rule = ArcOrPair()` to
   **the same `Expr`s** as `:local`/`:arc_or_pair`. Accept the symbols as aliases.
2. Keep `local_components`, `ring_arcs`, `ring_cells`, `ring_medium` and `components` as
   built-ins that lower exactly as today; deprecation warning at build, naming the
   replacement. Remove only at a breaking release, after the frozen tests that name them
   have been re-frozen by decision.
3. Migrate the shipped models in the same item: `merks.jl:230` becomes `@drive
   connectivity(endothelial; rule = ArcOrPair(), penalty = E₀)`; `merks.jl:75, 232`,
   `akeeb.jl:62`, `wortel_act.jl:52` use rule values. Invariance check: generated code and
   fingerprints byte-identical before and after (the `generated_code` pins and fingerprint
   pins already exist).
4. Docs: one "Connectivity" manual page replaces the constraint.md section and the drive.md
   row, with the framework mapping table (§11.1) and the decision guide.
5. Update the reviewed DSL snapshot (`guardrails.jl`) with the new names and keywords; this
   is a deliberate surface change, reviewed as such.

### 11.1 Mapping table for users of other frameworks

| You used | Write |
|---|---|
| CC3D `Connectivity` / `ConnectivityLocalFlex` | `@constraint connectivity(k)`; exact current CC3D behaviour: `@drive connectivity(k; rule = Local(; gain = true), penalty = 64.0)` |
| CC3D `ConnectivityGlobal` | `@constraint connectivity(k; rule = Global())` |
| CC3D `ConnectivityGlobal <FastAlgorithm/>` | `@constraint connectivity(k; rule = Local(; gain = true))` |
| Morpheus `ConnectivityConstraint` | `@constraint connectivity(k; rule = Simple())` (close; Morpheus' 3D test is a face count plus first-order conditions) |
| Artistoo `LocalConnectivityConstraint` | `@constraint connectivity(k)` (Artistoo joins diagonal ring sites, so it is slightly less strict; Q4) |
| Artistoo `SoftLocalConnectivityConstraint` | `@drive connectivity(k; penalty = λ)` |
| Artistoo `ConnectivityConstraint` | `@constraint connectivity(k; rule = Global())` |
| Artistoo `SoftConnectivityConstraint` | approximately `@energy cells(k) => λ * (1 - largest_piece / volume)^2`; exact needs per-piece volumes (§5) |
| TST `ConnectivityPreservedP` + `conn_diss` | `@drive connectivity(k; rule = ArcOrPair(), penalty = conn_diss)` |
| Durand & Guesnet 2016 | `@constraint connectivity(k; rule = Simple())` with `VonNeumann(1)` proposals |

---

## 12. Test plan

- **Enumeration oracles.** All 2⁸ square rings, 2⁶ hex rings and a 10⁵-sample of the 2²⁶
  3D shells (plus every 3D shell with ≤ 4 or ≥ 22 cell sites): `pieces` against an
  independent BFS on the shell; `Simple()` against the definition (T and T̄ by BFS) **and**
  against a global oracle: embed the shell in random 7×7 (2D) and 5×5×5 (3D) images, apply
  the copy, and check that the global numbers of cell components, background components
  (2D holes) and, in 3D, the Euler characteristic are unchanged exactly when `Simple()` says
  so.
- **Conservativeness.** On the same embeddings: `Local()` true ⇒ the global piece count of
  `old` did not increase (soundness; except the full ring, which must be shown accepted and
  hole-creating as a documented case). Report the false-refusal rate as information.
- **Global.** Random small lattices: `Global()` against a brute-force recount before and
  after; Sequential = BoundarySite exactly; checkerboard equal when no overflow; the overflow
  counter non-zero on a constructed long thin sprout (negative control).
- **Frozen invariance.** All existing tests unchanged and passing: `drives.jl`, `gpu.jl`,
  `audit.jl`, `p6_0aa`, `p6_3a`, `symbolic.jl`, `siblings.jl`. Generated code and
  fingerprints of every published model byte-identical before and after the migration.
- **Mechanism tests with negative controls.** `Simple()` keeps a cell hole-free in a run
  where `Local()` with `NeighborOrder(2)` proposals develops a hole; `Local(; gain = true)`
  removes corner-only gains that `Local()` allows under Moore(1); the state energy rewards a
  reconnecting copy by −α (brute-force ΔH).
- **Build errors.** One test per refused combination in §8.4, each checking the message.
- **GPU.** Metal and ROCm equal the CPU for every local rule (as `gpu.jl:173, 561` do now).

---

## 13. Open questions for the maintainer

1. **Rule names.** `Local()`, `ArcOrPair()`, `Simple()`, `Global()`? *Recommended: yes.*
   Mechanism names, no framework or model names in core; the mapping table carries the
   provenance. (`Simple` is the digital-topology term; the docs explain it as "changes
   nothing about the cell's shape topology".)
2. **One helper in two statements.** `connectivity(…; penalty)` valid only in `@drive`,
   veto form only in `@constraint`? *Recommended: yes* (W6).
3. **Gain test on `Local()`.** Add `Local(; gain = false)` with `gain = true` matching CC3D's
   first rule? *Recommended: yes, default false* (frozen behaviour; Akeeb uses VN proposals
   where it is automatic).
4. **Default adjacency for `pieces` and `Global()`.** Face (4/6), as today's local count and
   CC3D's global BFS? *Recommended: face*, with an `adjacency = :full` keyword on `Local()`
   only if an Artistoo reproduction needs it (none of the 15 does).
5. **Closed edges in `ArcOrPair()` (P6.0ae).** D-156 ruled "match TST: out-of-domain sites
   count as a cell", but the core still reads them as neither, and two frozen tests pin
   that. *Recommended: implement the ruling inside `ArcOrPair()` only* (the raw folds keep
   "out of domain is nothing"), re-freezing `p6_0aa`'s edge testset as P6.0ae says. The
   shipped Merks models are unaffected (real frame).
6. **`components` → `pieces`.** *Recommended: yes*, `components` kept as an alias until
   P6.9 re-freezes `p6_3a` (W20).
7. **Out-of-domain sites in `Simple()`'s background.** Background (a wall pocket is not a
   hole) or nothing? *Recommended: background.*
8. **Custom shells in v1** (`pieces` over `Moore(2)` etc.)? *Recommended: no* (W1); windows
   only inside `Global(; window)`.
9. **`largest_piece`.** Add it with P6.9 for Jafari's a′ and for "keep the largest piece"
   division policies? *Recommended: yes*; it comes from the same BFS.
10. **Fix `Local()`'s full-ring acceptance?** Today a full shell counts as one piece and is
    accepted (a hole is created when the source is outside the shell). CC3D refuses it.
    *Recommended: leave `Local()` as frozen and document; users who care use `Simple()`.*
11. **CC3D's local plugin is soft (64) in current source.** D-074's "match CC3D" and
    Akeeb's CC3D 4.3.1 Penalty 1e5 should be checked against the 4.3.1 source. *Recommended:
    a one-hour source check before the Akeeb paper text claims "exactly CC3D".*
12. **Euler characteristic.** Add a cell-scope `euler` tracker (local, exact) so `holes`
    becomes expressible? *Recommended: not now*; no spec needs it (§5.1 row 20).

---

### 13.1 Maintainer rulings (2026-10-08)

| # | Ruling | Departs from the recommendation? |
|---|---|---|
| 1 | Rule names `Local()`, `ArcOrPair()`, `Simple()`, `Global()` | no |
| 2 | One helper in two statements: the veto form in `@constraint`, `penalty` in `@drive`; a misuse is a build error | no |
| 3 | `Local(; gain)` checks the gaining cell, **default on** | **yes**: recommended default off |
| 4 | **Both adjacencies**: `adjacency = :face` or `:full` on `Local()`, `Simple()`, `Global()` and `pieces`; **face is the default** | **yes**: `:full` is now general, not on demand |
| 5 | P6.0ae: closed edges are read as a cell inside `ArcOrPair()` only; the raw folds keep "out of domain is nothing" | no |
| 6 | `components` → `pieces`, **with no alias** | **yes**: recommended an alias until P6.9 |
| 7 | `Simple()` treats out-of-domain sites as background | no |
| 8 | No custom shells in v1; windows only inside `Global(; window)` | no |
| 9 | `largest_piece` with P6.9 | no |
| 10 | **Fix `Local()`**: a full shell of the losing cell is refused, as in CC3D | **yes**: recommended keeping the frozen behaviour |
| 11 | Check the CC3D 4.3.1 source before any "exactly CC3D" claim (Akeeb) | no |
| 12 | **Add the cell-scope Euler-characteristic tracker now**, so holes (and 3D tunnels) can be expressed as an observable or energy | **yes**: recommended not now |

**Consequences of rulings 3, 6, 10 and 12, for the coordinator to scope:**
- **Rulings 3 and 10 change `Local()`'s dynamics wherever they can bite.** That means every model using `Local()` with proposals reaching beyond the face neighbours, plus any frozen test that pins the old behaviour.
  - Akeeb uses face-neighbour proposals, where the gain test is automatic and the full-shell case cannot arise. Expect no change; confirm it with the A/B and the frozen record test.
  - `MerksVasculogenesis` (the legacy model, `rule = :local`) and every test pinning the full-shell acceptance need re-freezes.
  - Any FULL record whose dynamics change is re-run on the PC and reported under D-154.
- **Ruling 6:** `p6_3a` and every reference to `components` is renamed in the same change. `Global()` is not shipped, so no user model breaks.
- **Ruling 12** needs a design for the tracker: local χ updates per copy from the 2×2 (2D) / 2×2×2 (3D) cell configurations, exact. It also needs an oracle test (enumeration on small lattices) and an A/B showing zero cost for models that don't use it.

## 14. Proposed ROADMAP items

- **P6.3g Connectivity vocabulary (surface).** Rule values `Local(; gain)`, `ArcOrPair()`,
  `Simple()` (2D square and hex, 3D cubic), `connected(c; rule)`, `connectivity(…; rule,
  penalty)` in both statements, the `shell` relation, the `pieces` fold and the `distinct`
  fold; aliases for the old names; migrate the four shipped call sites; one docs page with
  the mapping table. *Accept:* enumeration oracles (§12) pass; generated code and
  fingerprints of every published model byte-identical; every frozen test unchanged; each
  build error tested; DSL snapshot updated by review; A/B at parity.
- **P6.3h Shell kernels.** One shell read per generated function; 2D run-count kernel for
  `Local()`; 3D table-driven flood fill. *Accept:* oracles unchanged; A/B ≤ 1.00 on the
  §9.4 cases within the controls' spread (D-171); zero warm allocations; Metal and ROCm
  equal the CPU.
- **P6.0ae (existing).** Answer Q5 inside `ArcOrPair()`; re-freeze `p6_0aa`'s edge testset;
  make the sentinel independent of σ's element type.
- **P6.9 (existing, amended).** `Global(; window)` as a rule value with "does not increase"
  semantics for `old` and `new`; post-acceptance evaluation; interleaved BFS; cell-scope
  `pieces` and `largest_piece` with exact after-values in energies; the D-075 device BFS.
  *Accept:* as written, plus the bitwise-identity test of post-acceptance evaluation and the
  Bauer/Jafari state energy against brute-force ΔH.
- **P6.3i Gain-side and topology mechanism tests** (may fold into P6.3g): the negative
  controls of §12 on Moore(1) and `NeighborOrder(2)` proposals.

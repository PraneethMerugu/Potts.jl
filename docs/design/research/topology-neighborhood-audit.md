# Topology and neighbourhood audit (2026-10-01)

Scope: every place a lattice topology or neighbourhood enters the five shipped models
(`lib/PottsModels/src/`), the 12 paper-model specs (`research/model-specs/`, with sketches),
the paper-run scripts (`PottsWorktrees/paper-runs/docs/paper_runs/*.jl`) and the tutorial
pages (`PottsWorktrees/docs-models/docs/models/*.jl`). This audit only reads; it changes no
code, tests or docs.

Each item was checked against three things:
- the papers in `docs/references/`;
- the authors' code: TST 0.1.3, Chaste 2017.1, Akeeb CC3D, Fortuna/Dal-Castel CC3D, the OpenVT
  repos;
- the engine sources: CC3D, Artistoo and Morpheus, read raw from GitHub/GitLab; TST and Chaste
  from the local copies.

Tags:
- [unverified]: not checked against a primary source.
- [sub]: read by a delegated reader, not re-read here. Remote line numbers are ±2.

Verdicts: CORRECT, WRONG, UNSTATED (the paper is silent; the row says whether our choice is
justified), UNVERIFIED.

---

## 1. Potts.jl semantics (verified in source and with a scratch run)

| Item | Meaning | Source |
|---|---|---|
| `Moore(k)` | Chebyshev ball. k=1 gives 8 (2D) or 26 (3D); k=2 gives 24 | `lib/CorePotts/src/lattice.jl:183-188,237` |
| `VonNeumann(k)` | Manhattan ball. k=1 gives 4 or 6 | `lattice.jl:190-195,240` |
| `NeighborOrder(k)` | Cumulative Euclidean shells. Square: 4, 8, 12, 20. Cubic: 6, 18, 26, 32. Hex: 6, 12, 18, 30. Offsets were printed in a scratch run; the counts equal CC3D and Morpheus | `lattice.jl:197-207,242-247,276-281` |
| `Hex(k)` | Hex-hop ball: 6, 18, 36. **`Hex(2)` = 18 ≠ "second-nearest" = 12** (that is `NeighborOrder(2)` on `Hexagonal()`) | `lattice.jl:255-272` |
| `Moore`/`VonNeumann` on hex | Both mean `Hex(k)` | `lattice.jl:272` |
| `Periodic()` / `Closed()` | Per axis. `Closed` means no neighbour across the face. That neighbour is absent from contacts and surface, and a proposal drawn across the face is a counted null attempt. Default `Periodic()` | `lattice.jl:3-7,41-51,143-153` |
| `neighborhood` | Sets the **contact and surface** relations (default `Moore(1)`) | `src/vocabulary.jl:580`; `src/compile.jl:359-360`; AUTHORING §3 |
| Proposal | Default `VonNeumann(1)`, else `@relations proposal = …` | `src/compile.jl:337` |
| Sampling | Uniform **target** among the mobile sites, then a uniform offset from the proposal relation gives the **source**. Out-of-lattice, frozen-source and same-owner picks consume the attempt. One MCS = N_mobile attempts | `lib/CorePotts/src/sequential.jl:3-35` |
| `contacts => J` | Each **unordered** unlike-owner pair once, so ΔH = Σ_n [J(new,n) − J(old,n)] | AUTHORING §4, §12.9 |
| `surface` | Unlike-neighbour pairs within the surface relation, no lattice factor. Pairs with medium count; a closed lattice edge does not | AUTHORING §12.9 |
| `connectivity(k)` (`:local`) | `local_components == 1`: face-connected pieces of the loser's sites in the target's 3ᴺ−1 box. In 2D these are exactly the arcs on the 8-ring, so this equals CC3D `Connectivity`'s "two collisions" | `lib/CorePotts/src/drives.jl:85-104,160-200` |
| `connectivity(k; rule = :arc_or_pair)` | `ring_arcs ≤ 1 ‖ ring_cells == 2`, where `ring_cells` excludes medium | `src/vocabulary.jl:428`; `drives.jl:106-150` |
| `Δ` | Square: 5-point (2D) or 7-point (3D), `(c₊ − 2c + c₋)/h_d²` per axis. Hex: 6-point `2/(3h²)Σ(c_n − c)`. Closed faces are zero-flux (the ghost mirrors the site); a per-face Dirichlet value is optional, but its DSL option is not exposed. **Fields share the cell lattice's boundary per axis** | `lib/CorePotts/src/fields.jl:5-50,64-82` |
| Metropolis | Accept if ΔH ≤ offset, else with probability exp(−ΔH/T). At T ≤ 0 a tie is accepted with probability ½ | `lib/CorePotts/src/algorithms.jl:5-46` |

**Doc nit (low).** AUTHORING §12.9 (l.1153) describes proposals as "uniform source site,
uniform target within the proposal relation". The code draws the target first.
- For symmetric relations away from edges the two draws give the same ordered-pair
  distribution.
- Fix the wording to "uniform mobile target, uniform source offset".

## 2. Engine semantics

### 2.1 Neighbourhood "order" → offsets

| Lattice | CC3D `NeighborOrder` (cumulative distance shells) | Morpheus `Order` (same shells) | TST `neighbours` (ca.cpp:59-62) | Artistoo | Chaste |
|---|---|---|---|---|---|
| 2D square | 4, 8, 12, 20, 24, 28, … | 4, 8, 12, 20, 24, 28, … | 1→4, 2→8, **3→20** (VN, diagonals, (±2,0), (±1,±2)), 4→24 (bug: repeats (±2,0)) | Moore 8 (`neighi`); VN 4 (`neighNeumanni`) | Moore 8, VN 4 |
| 3D cubic | 6, 18, 26, 32, 56, 80 | 6, 18, 26, 32, 56, 80 | – | Moore 26 only | Moore 26, VN 6 |
| 2D hex | 6, 12, 18, 30, 36 | 6, 12, 18, 30 | – | none | none |

Sources: CC3D `BoundaryStrategy.cpp` L890-949 (shells; hex parity offsets L1105) [sub];
Morpheus `core/lattice.cpp` ~L372/559/623 [sub].

### 2.2 Defaults per role

| Role | CC3D | Artistoo | Morpheus | TST | Chaste |
|---|---|---|---|---|---|
| Copy proposal | Potts `<NeighborOrder>` default **1** | Moore | `MonteCarloSampler/Neighborhood`, required | `n_nb` (default 8; Merks 2008 uses 20) | Moore, fixed |
| Contact | Contact `<NeighborOrder>` default **1**; published models often use 2 | Moore | = ShapeSurface neighbourhood | same `n_nb` | **VN** |
| Surface | SurfaceTracker order 1, times `lmf.surfaceMF` (1 on square, ≠ 1 on hex) | Moore unlike count | ShapeSurface; default `norm` (Magno) scaling | (none) | VN edges; **counts lattice-edge faces** |
| Connectivity | `Connectivity`: 2D Moore 8-ring, collisions = 2; `ConnectivityGlobal`: BFS | Local and global: Moore; soft: VN by default | fixed surface nbhd (square order 2) | 8-ring `ConnectivityPreservedP` with a **medium clause** (ca.cpp:1168-1225) | none |
| Chemotaxis | source and target pair only | target vs source | [unverified] | source and target | n/a |
| Laplacian | 5-point / 7-point; hex 6 (12 in 3D) | 5-point, 2D only | 5-point / 7-point; hex 6 | 5-point (pde.cpp:178-215) | n/a |

### 2.3 Sampling and MCS

| Engine | Draw | Attempts / MCS | Null picks consume? |
|---|---|---|---|
| CC3D `metropolisFast` | uniform **source** pixel, random neighbour **target** (Potts3D.cpp L786-827) [sub] | N·`Flip2DimRatio` (default 1) | yes: out-of-lattice, same-cell, frozen |
| Artistoo | uniform **target** from `borderpixels` (medium included), Moore source (CPM.js:326-334) [sub] | ≈ \|border\| | same-cell yes; out-of-lattice impossible (renormalised) |
| Morpheus `random` | uniform source, offset from the update neighbourhood [sub] | N | yes |
| TST | uniform interior **target**, one of `n_nb` as **source** (ca.cpp:385-397) | (X−2)(Y−2) | yes (border source, same σ) |
| Chaste | **target** node, Moore **source** among the existing neighbours (PottsBasedCellPopulation.cpp:241-336) | N per step | same-cell yes; edge renormalised |

All five draws are rate-equivalent to ours for symmetric relations: Artistoo's border-only
draw has the same expected number of border attempts per MCS.

### 2.4 Pair counting and boundaries

- **ΔH counts each (target, n) pair once in every engine.**
  - CC3D: ContactPlugin L127-163 [sub].
  - Artistoo: Adhesion.js:59-77 [sub].
  - TST: ca.cpp:206-245.
  - Chaste: AdhesionPottsUpdateRule.cpp:78-130.
  - Morpheus also counts once, **but divides ΔH by `boundaryLengthScaling`**. The default `norm` divides by about 3.07 at order 2 (interaction_energy.cpp ~L371-432) [sub].
- So CC3D, Artistoo, TST and Chaste J values map 1:1 to `contacts => J` **at the same relation**. Morpheus J must be divided by the norm factor of its ShapeSurface order. AUTHORING §12.9 ("Contact H: unordered pairs counted once") omits this.
- **Cell-lattice boundary defaults:**
  - CC3D: NoFlux.
  - Artistoo: **torus** (Grid2D.js:53).
  - Morpheus: noflux in code.
  - TST, non-periodic: **a 1-px frozen frame σ = −1 with `border_energy` per pair**.
  - Chaste: non-periodic.
- **Field boundary defaults:**
  - CC3D: inherits Potts; periodic stays periodic, otherwise zero derivative (DiffusionSolverFE.cpp:246-264, 1254-1286, 3.7.9 local).
  - TST, non-periodic: **absorbing c = 0 ring** (pde.cpp:189-194, 268-300).
  - Artistoo: per the field grid's torus setting.

---

## 3. Shipped models

### 3.1 `GranerGlazier` (graner_glazier.jl)

| # | Setting | Potts | Paper (09a PRL 1992, 09c PRE 1993) | Verdict |
|---|---|---|---|---|
| 1 | Lattice | 2D square, 72² (smoke) / `graner_glazier_aggregate` (247², or 383² at margin 60) | square; "about 1000 cells", size unstated (PRE p.2129) | CORRECT / size UNSTATED |
| 2 | Boundary | `Periodic()` (l.36) | not stated in PRL or PRE (searched the full text) | UNSTATED. Harmless for sorting with a margin. The paper run's margin 60 avoids the periodic image; dispersal runs need ≥ 60 |
| 3 | Contact | `Moore(1)` (8) | "second-nearest-neighbor square lattice" (PRE p.2129); "n = 8 in the next-nearest-neighbor lattice" (p.2132) | CORRECT |
| 4 | J scaling | once per pair | "T_dd = 16" with J_dd = 2 (p.2132), and "energy of a spin on a light-light boundary is at most 16" with J_ll = 2 (p.2133) give an isolated-spin flip cost n·J = 8J, i.e. once per pair | CORRECT |
| 5 | Proposal | `Moore(1)`, target uniform, source neighbour | "select a lattice site … convert its spin … to … one of the eight neighboring sites" (p.2130) | CORRECT (same draw order) |
| 6 | MCS | N attempts; 1 paper MCS = 16 MCS | "one MCS to be 16 times as many time steps as there are lattice sites" (p.2130) | CORRECT |
| 7 | T=0 anneal | not in the model; done on a copy in `test/papers.jl` and `reproductions/09` | 2 MCS at T=0 "on displayed data only" (p.2134) | CORRECT where implemented. Paper run and tutorial: raw states (documented) |
| 8 | Boundary-length observable | Moore pairs once | "number of mismatched bonds" (p.2133) | Fractions CORRECT. **Absolute length: our 1000-cell aggregate has 36,578 Moore pairs counted once** (scratch run, seed 1); **×2 = 73,156 against the paper's ≈ 66,850 (Fig. 13a)**. So GG very likely counted each bond from both sides [unverified; the paper aggregate is relaxed and smoother]. Spec 09 V-PRE4 should compare 2× our count, or report the ratio only |
| 9 | Adjacency for clusters/sides | Moore(1) bond | unstated | UNSTATED (fine) |

### 3.2 `MerksVasculogenesis` (merks.jl)

The default variant is Merks 2006 (TST `longcells.par`-family settings). With
`contact_inhibited = true` it is Merks 2008 (Dataset S1).

| # | Setting | Potts | Paper / TST code | Verdict |
|---|---|---|---|---|
| 1 | Lattice | 500², `Closed()` | 2006: 500² (incl. 1-px frame in TST); 2008 files: 200² incl. frame | CORRECT (±2 sites) |
| 2 | Cell boundary | free closed walls, no energy | **frozen border, J_cB = 100, J_MB = 0** (01a p.48; ca.cpp:97-105, 228-238). The border is reached through the whole `n_nb` stencil | **WRONG.** Already decided in D-050 M4 and documented. Walls are now *attractive* (no J_cM = 20 cost there) where the paper's are repulsive (100) |
| 3 | Field boundary | zero-flux (inherits `Closed`) | **absorbing c = 0 on the outer ring**, reset every substep (pde.cpp:189-194, 270-285) | **WRONG**, and **missing from the docstring and the tutorial deviations table** (docs-models merks.jl:229-240 says "rates … are the paper's"). D-050 M5 plans the fix |
| 4 | Contact, 2006 | `Moore(1)` | "the eight second-order neighbors" (01a p.47); `neighbours = 2` | CORRECT |
| 5 | Proposal, 2006 | `Moore(1)` | not stated; TST uses `n_nb` = 8 | UNSTATED, justified by code |
| 6 | **Contact and proposal, 2008 (`contact_inhibited = true`)** | `Moore(1)` | **20 neighbours, first to fourth nearest** (01b p.11; all 12 Dataset S1 `.par` files `neighbours = 3`; ca.cpp:62, 206, 389-397) | **WRONG.** The 2008 J and χ are tuned for 20 neighbours. Contact ΔH sums 8 instead of 20 pairs, and chemotaxis sources lie at ≤ √2 instead of ≤ √5 |
| 7 | MCS / draw | target uniform, source from the relation; N attempts | (X−2)(Y−2), target interior, source of `n_nb`; null picks count | CORRECT |
| 8 | Connectivity | `connectivity(endothelial; rule = :local)`, hard | TST `ConnectivityPreservedP` (8-ring; passes if arcs ≤ 1 OR (≤ 2 distinct non-zero σ on the ring AND no medium)) as soft E₀ = 2000/5000 (01a p.49; ca.cpp:442-448, 1168-1225) | Deviation, documented (D-050 M3 pending). `:local` is stricter: it rejects old+new-only multi-arc copies that TST allows. The docstring calls it "the CompuCell3D one-arc rule", which is accurate for the code but not the paper's |
| 9 | Laplacian | 5-point, Δx = 1 | FTCS 5-point (pde.cpp:178-219) | CORRECT |
| 10 | Secretion/decay sites | secrete on `endothelial`, decay on `medium` | Eq. 6; TST `Secrete` | CORRECT |
| 11 | Chemotaxis pair | `−χ(c[target] − c[source])` on every copy; CI: extensions only | Eq. 2 (Savill–Hogeweg) | CORRECT; the pair range follows row 6 |
| 12 | `major_length` | inertia over the cell's sites | Eq. 5 | CORRECT (topology-free) |

### 3.3 `AkeebInvasion` (akeeb.jl)

Authors' code: `codebases/10_.../Sample/*/Simulation/CCIecm.xml`, CC3D 4.3.1.

| # | Setting | Potts | Paper / code | Verdict |
|---|---|---|---|---|
| 1 | Lattice | 500×300 | Table 1 p.7; XML `Dimensions 500 300` | CORRECT |
| 2 | Boundary | `(Periodic(), Closed())` | periodic x (p.4, p.7); XML `Boundary_x Periodic`, y commented out → CC3D NoFlux default | CORRECT (y from code) |
| 3 | Contact | `Moore(1)` (8) | XML Contact `<NeighborOrder>2</NeighborOrder>` = 8 | CORRECT; J values map 1:1 |
| 4 | Proposal | `VonNeumann(1)` | XML Potts `<NeighborOrder>1</NeighborOrder>` = 4 | CORRECT |
| 5 | Draw / MCS | target-first, N | CC3D source-first, N | CORRECT (equivalent) |
| 6 | Connectivity | `connectivity(leader, follower)` = `:local` (one arc, zero pieces rejected) + `no_extinction` | `Connectivity` penalty 1e5: 8-ring collisions must be 2; zero collisions are penalised; the gaining cell must have a first-order neighbour at pt (automatic with VN(1)) | CORRECT (hard ≈ soft at T = 10) |
| 7 | Cue field | static `cue = y − 1`, no PDE | `mv[x,y] = y/g`, g = 1; D = 0, so the field BCs are inert | CORRECT |
| 8 | Chemotaxis pair | `−μ(cue[t] − cue[s])` if new or old is a leader | CC3D Merks algorithm `(c_src − c_tgt)·λ` | CORRECT |
| 9 | Observables (O1 adjacency) | spec: VN | CC3D `NeighborTracker` (order not verified); paper p.7 says VN | UNVERIFIED (open question 5 in spec 10) |

### 3.4 `WortelAct` (wortel_act.jl)

Sources: Niculescu 2015 PLoS CB (web) and Artistoo `ActivityConstraint.js`.

| # | Setting | Potts | Paper / reference code | Verdict |
|---|---|---|---|---|
| 1 | Lattice | 200², `Periodic()` | "wrapped lattice of size 200×200" (Methods) | CORRECT |
| 2 | Contact | `Moore(1)` | TST/Artistoo Moore | CORRECT |
| 3 | Perimeter | `surface` over Moore(1), P = 340 | "distinct interfaces (edges and corners)" = Moore unlike count; Artistoo PerimeterConstraint uses Moore, unscaled | CORRECT |
| 4 | Proposal | `Moore(1)` | Artistoo Moore source; 2015 TST `n_nb` [unverified value] | CORRECT for Artistoo |
| 5 | Act GM | `Moore(1; include_self = true)`, same owner as s | Paper: "V(u) the direct Moore neighborhood of u that belongs to the same cell". Artistoo `activityAtGeom`: `nN = 1` (self) plus same-cell `neighi` | CORRECT (matches Artistoo; the paper is ambiguous about self) |
| 6 | Act ΔH sign | `(λ/max)(GM(t) − GM(s))` | Artistoo `lambdaact*(activityAt(target) − activityAt(source))/maxact` | CORRECT |
| 7 | Connectivity (`connected = true`) | `:arc_or_pair` = arcs ≤ 1 OR ring_cells == 2 (medium allowed) | Paper: "the connectivity constraint described by Merks et al." = TST `ConnectivityPreservedP`, which needs **no medium on the ring** for the 2-cell exemption (ca.cpp:1218) | **WRONG** in multicell runs: it accepts multi-arc copies at cell–cell–medium junctions, which split cells. Single-cell runs are unaffected (ring_cells ≤ 1) |
| 8 | Implementation provenance | tutorial: "the authors' simulations" | paper: "implemented in the Tissue Simulation Toolkit"; Artistoo is Wortel 2021 | docs nit |

### 3.5 `OpenVTGrowingMonolayer` (openvt.jl)

Sources: gitlab `rvet/monolayergrowth` `implementations/Artistoo/monolayer.html`;
github `OpenVT/reference_models` `monolayer/CompuCell3D`.

| # | Setting | Potts | Artistoo reference | Verdict |
|---|---|---|---|---|
| 1 | Lattice | 400² (constructor), 800² (paper run) | `field_size: [1100, 1100]` | Size differs. OK while the colony stays clear of the walls; **400² cannot hold 10⁴ cells** (radius ≈ 340) |
| 2 | Boundary | `Closed()` | `torus: [false, false]` | CORRECT |
| 3 | Contact / proposal | `Moore(1)` / `Moore(1)` | Artistoo default Moore for both | CORRECT |
| 4 | Growth / CI | `A₀/τ` per MCS; volume ≥ βV_T | `ALPHA = 0.2976 = 25/84`; `areaRatio < beta` | CORRECT |
| 5 | Division threshold | deterministic 2A₀ | Artistoo file: `N(2, 0.4)·A₀`. Baseline spec (Vetter email, `OpenVT/reference_models/monolayer/summary-Oct-12-2024.md`): exactly 2A₀ | CORRECT by spec; differs from the Artistoo file |
| 6 | CC3D reference (not ours) | – | Potts NO 1, **Contact NO 4**, NoFlux 1024² | Not the set we port; record it if a CC3D variant is added |

---

## 4. Specs (01, 04–14)

Specs 01, 09 and 10 are covered above together with their shipped models. Their recorded
topology matches the code and papers, except for the following.

- **01**
  - 01 §2.6 correctly records the TST medium clause.
  - D-050 M3 says "ring-breaking". The implementation must use the TST predicate, **not** the existing `:arc_or_pair`.
- **09**
  - The Osborne variant needs `neighborhood = VonNeumann(1)` with `proposal = Moore(1)` (Chaste).
  - Chaste's perimeter counts lattice-edge faces; ours does not at a `Closed` edge. A frozen `Frame` kind with J = 0 reproduces it exactly, since `surface` counts pairs with the frame.
  - V-PRE4 absolute length: see §3.1 row 8.
- **10**: all CORRECT (§3.3).

| Spec | Item | Spec says | Source | Verdict |
|---|---|---|---|---|
| 04 foam | contact | `NeighborOrder(4)` = 20 | "fourth-nearest-neighbor interaction … anisotropy of 1.03" (04b p.5822) | CORRECT under the cumulative reading [unverified: Holm 1991 PRA 43:2662] |
| 04 | boundary | (Periodic x, Closed y), wall type A-2 | periodic x (p.5822); y unstated | CORRECT / UNSTATED, flagged |
| 04 | proposal | wall sites → unlike neighbour, set `NeighborOrder(4)` | p.5822 | quote CORRECT; set UNSTATED |
| 04 | sides n / T1 neighbour list | `Moore(1)` (sketch l.67, l.90) | "number of different neighbors" (p.5823) | UNSTATED. **Poor default**: diagonal-only contacts inflate n, μ₂(n) and the T1 counts. Prefer `VonNeumann(1)` (face sharing) [sub] |
| 05 Bauer 09 | proposal | sketch: default `VonNeumann(1)`, plain law | the cited 2007 lineage: "unlike second nearest" | **WRONG** (internally inconsistent) [sub] |
| 05 | cell y boundary | periodic (follows the VEGF field) | VEGF periodic in y (p.3) | UNSTATED; justified because fields share the cell boundary |
| 05 | citation | "p.14" ×8 | the quote is on p.13 | WRONG page (low) [sub] |
| 06 Jiang 05 | proposal | sketch l.163 plain Metropolis (VN(1)) | "one of its unlike neighbors" (p.3 [3886]) | **WRONG**: the timing calibration (4 MCS doubling) depends on it [sub] |
| 06 | contact, 3D | `Moore(1)` = 26, "UNSPECIFIED" | not stated | UNSTATED |
| 07 Bauer 07 | proposal | `NeighborOrder(2)` + `UnlikeNeighbor` | "unlike second nearest neighbors" (p.7 [3111]) | CORRECT (shells 1–2 vs shell 2 is flagged) |
| 05/07 | degradation rim | 05: Moore(1); 07: VonNeumann(1) | unstated | inconsistent; pick one [sub] |
| 08 FBCA | contact / proposal | Moore(1), ½Σ ordered = once | Eq 4–5 p.81-82; Table 1 "Moore neighborhood size 1" | CORRECT |
| 08 | 08b lattice | sketch l.115 `(175, 115)` | w = 115, h = 175 (vessel 11×115 spans the width, p.286) | **WRONG axis order** [sub] |
| 08 | SC1 initial layout | `Tiling((5,5); kinds=[ox, fe])` | Fig 2A appears a checkerboard; with x-fastest ids and 20 (even) columns, the Tiling gives **vertical stripes** | WRONG [sub; visual reading of Fig 2A] |
| 08 | periodic axis | "UNSPECIFIED" | derivable: x (the lower side is open) | can be upgraded |
| 11a JN 2021 | boundary | periodic | p.13 | CORRECT |
| 11a | contact / proposal | VN(1)/VN(1) (CC3D defaults) | not stated | UNSTATED; ask the authors |
| 11b Andasari | proposal | sketch l.180 VN(1) on 2D 64² | "pixels up to fourth nearest neighbour" (p.11) | **WRONG / undocumented** (conformance-only component) [sub] |
| 12 Zajac | contact range | Moore(1) placeholder | Fig 3c (12b p.250) draws couplings across edges only | UNSTATED; evidence favours `VonNeumann(1)` [sub] |
| 12 | pair counting | – | Eq 1 Σ_{i,j,k,l} over ordered pairs | flag: J_paper = J_ours/2 only if the code double-counts |
| 13 Starruß | contact | `Hex(2)` "12 sites" (sketch l.49, 124, 246; README Y3 l.438; api-synthesis.md:1188) | "Second-nearest neighbours" (p.275) = 12 | **WRONG**: `Hex(2)` = 18. Use `NeighborOrder(2)` on `Hexagonal()` (= 12, verified) |
| 13 | proposal | `Hex(1)` (6) | "one of its nearest neighbours" (p.274) | CORRECT |
| 13 | torus | rhombic (Potts hex) | box shape unstated | UNSTATED. CC3D and Morpheus use offset (rectangular) hex boxes |
| 13 | propulsion d·θ | lattice offsets | p.275 Eqs 9-10 | must be **embedded** Cartesian vectors on hex [sub] |
| 14 Fortuna | contact | `NeighborOrder(4)` = 32 (3D) | "fourth-neighbor range … (32 neighbors)" (14a p.2805); CellMig3D.py:163 | CORRECT |
| 14 | pair-counting text | l.59: "counts each pair twice … matches CC3D convention" | CC3D ΔE counts each pair **once** | **WRONG wording** (J values are used unchanged, which is right; do not halve) |
| 14 | proposal, boundary, Laplacian, secretion sites | VN(1); (P, P, Closed); 7-point; FRONT face-touching SUBS_A | code + CC3D 3.7.9 source | CORRECT. Field BC is verifiable from DiffusionSolverFE.cpp:246-264, 1254-1286 |
| 14 | MCS with frozen planes | N_mobile | CC3D N_all, frozen picks wasted | **CORRECT.** The sub-reader's claimed +5–10% bias is rejected: CC3D's N_all attempts include a fraction N_frozen/N_all of wasted picks, so the attempts on mobile sites per MCS equal ours |

---

## 5. Claims in the docs pages and paper runs

| File:line | Claim | Verdict |
|---|---|---|
| paper-runs `graner_glazier.jl:18,43` | "periodic lattice (paper unstated)", margin 60 | **CORRECT**: neither PRL nor PRE states the boundary. The 60-site margin keeps the aggregate off its image |
| docs-models `graner_glazier.jl:60-63,230,234` | Moore contacts and copies "as in the paper"; boundary "not stated" | CORRECT (PRE p.2129, 2130, 2132) |
| docs-models `graner_glazier.jl:199` | "every Moore bond once" | fine for fractions; absolute lengths are ×2 against the paper (§3.1 row 8) |
| docs-models `merks.jl:68` | "closed, with Moore contacts and copies, as in the paper" | contacts stated (8); copies from code; "closed" is a documented deviation |
| docs-models `merks.jl:229-240` | deviation table; "neighbourhoods … are the paper's" | **Incomplete**: it omits the **absorbing c = 0 field boundary** (TST) vs our zero-flux. It is true for 2006 only; the CI variant's 20-neighbourhood is not used |
| docs-models `merks.jl:136-138`; paper-run caption | hard one-arc veto instead of the E₀ penalty | accurate to the code |
| docs-models `wortel_act.jl:117-118` | "an 'arc or pair' rule … used by Niculescu et al." | **WRONG**: Niculescu cite Merks' TST rule, which has the no-medium clause; `:arc_or_pair` lacks it |
| docs-models `wortel_act.jl:212` | Implementation: "the authors' simulations" vs Artistoo | nit: the 2015 runs used TST (Methods) |
| docs-models `akeeb.jl:56-57,233-235` | 8-neighbour contacts, 4-neighbour copies, closed y, CC3D Connectivity | CORRECT |
| docs-models `openvt.jl:50,183` | "closed 400×400"; "None [differences] in the model: the lattice … are the benchmark's Artistoo set" | **WRONG on lattice**: Artistoo uses 1100². The division threshold is random N(2, 0.4)·A₀ in the Artistoo file (deterministic in the baseline spec) |
| paper-runs `openvt_monolayer.jl:8,42` | 800² because 400² cannot hold 10⁴ cells | correct reasoning; the colony diameter at 10⁴ is ≈ 690, leaving ≈ 55-site margins |
| paper-runs `wortel_act.jl:5` | "wrapped 200×200" | CORRECT |
| paper-runs `akeeb_invasion.jl:22` | VN(1) proposals = CC3D order 1 | CORRECT |

---

## 6. Discrepancies ranked by impact on reproduced results

1. **Merks 2008 variant uses 8 neighbours instead of 20 (high for any CI run).**
   - Fix in `lib/PottsModels/src/merks.jl:72-73`: use `neighborhood = contact_inhibited ? NeighborOrder(4) : Moore(1)` and `@relations proposal = contact_inhibited ? NeighborOrder(4) : Moore(1)`. Whether the macro accepts a structural conditional here is [unverified]; otherwise use two `if` branches. This folds into D-050 M1/M7 (separate 2008 set), which should state "20 neighbours for contacts and copies".
   - TST border contacts reach through the √5 stencil, so a `Frame` must be 2 px thick, or J_cB applied to off-lattice stencil sites (ca.cpp:228-230).
   - Frozen gates: none use `contact_inhibited = true` (`papers.jl` and the acceptance files use the default). `mechanisms.jl:296` is not frozen.
2. **Merks field boundary: zero-flux vs absorbing c = 0 ring (medium).**
   - The fix is already decided (D-050 M5; R5 `@boundary`). Until then, add the row to the docstring and the tutorial table.
   - CorePotts already supports per-face Dirichlet 0 (`fields.jl:14-19`), but it is not exposed.
   - Changing the default changes the Merks trajectories but no frozen file (`p6_0c`/`p6_0v` test placement and transfer counts, not values) [unverified for p6_0c].
3. **Merks walls free instead of a frozen border with J_cB = 100 (medium).**
   - Decided in D-050 M4. Adding a `[frozen]` kind makes Merks a mask-refresh model, so `p6_0v_transfer_counters.jl`'s frozen Merks quiet-MCS target (0/0/0 B) may change and would need a DECISIONS entry.
4. **`:arc_or_pair` is not TST `ConnectivityPreservedP` (medium for WortelAct `connected = true` multicell runs and for the planned Merks M3).**
   - Fix: `ring_arcs <= 1 || (ring_cells == 2 && ring_medium == 0)`. This needs a new copy-scope value `ring_medium`, the number of medium sites on the ring. TST counts its σ = −1 frame as a cell, so out-of-domain sites should not count as medium.
   - Edit `src/vocabulary.jl:428` and `lib/CorePotts/src/drives.jl`.
   - Fix the claims in AUTHORING §4 (rule table) and docs-models `wortel_act.jl:117-118`.
   - Frozen gates: none use `connected = true`. `runtests.jl:34` and `mechanisms.jl:397-399` are ordinary tests.
5. **Spec 13 `Hex(2)` = 18, not 12 (high for that port, which is not built yet).**
   - Replace with `NeighborOrder(2)` at sketch 13 l.49, l.124, l.246, README l.438 (Y3) and `api-synthesis.md:1188`.
6. **Spec 06/05 proposal laws (high/medium for those ports).**
   - Sketch 06 l.163: add the unlike-neighbour law (G8 in spec 06 l.355).
   - Sketch 05: add `proposal = Moore(1)` + `UnlikeNeighbor`, or document that VN(1) uniform is a deviation.
7. **Spec 08: 08b axis order, `(175, 115)` → `(115, 175)` (medium-high), and the SC1 checkerboard layout (medium; [sub], visual).**
8. **Spec 04 sides/T1 relation (medium).** Default `VonNeumann(1)`, with Moore(1) as the variant.
9. **Spec 11b sketch neighbourhood undocumented (low-medium).** Add `NeighborOrder(4)` or a deviation note.
10. **Spec 14 l.59 pair-counting wording (medium risk of a ×2 error).** Write "CC3D counts each pair once; use Table 1 J unchanged".
11. **OpenVT tutorial claim "no differences" (low).** List the 1100² lattice and the random N(2, 0.4) threshold of the Artistoo file. The constructor default of 400² cannot reach N = 10⁴.
12. **GG absolute boundary length ×2 (low; spec 09 V-PRE4 only).**
13. **Doc nits.**
    - AUTHORING §12.9 proposal wording (§1).
    - AUTHORING §12.9 omits Morpheus `boundaryLengthScaling` (§2.4) and CC3D's hex `surfaceMF`. These matter for the Morpheus corpus and hex ports.
    - Spec 05 page numbers.
    - Spec 14 p.3 → p.4.
    - Spec 12: note the Fig 3c evidence.

No discrepancy was found in `GranerGlazier`, `AkeebInvasion` or the default `WortelAct`
topology. **No proposed fix touches a frozen acceptance file**; item 3 may touch the
`p6_0v` counts.

## 7. J-scaling from pair-counting conventions

- **CC3D:** ΔE = Σ_n [J(new,n) − J(old,n)] over the Contact `NeighborOrder` set, each pair once. CC3D J maps 1:1 to `contacts => J` with `NeighborOrder(k)` of the same k.
  - Akeeb: order 2 = `Moore(1)` ✓.
  - Fortuna: order 4 (3D, 32) ✓.
  - The OpenVT CC3D implementation uses order 4 (20). It is not our port.
- **TST** (Merks): the same per-pair rule over `n_nb` (8 or 20). The 2006 values are ✓. The 2008 values are only valid with 20 (§6 item 1). `border_energy` is per border-neighbour pair.
- **Artistoo** (Act, OpenVT): Moore, once per pair ✓.
- **Chaste** (Osborne): VN, once per pair. Use `VonNeumann(1)` contacts or the J values are mis-scaled by roughly 2–3×.
- **Morpheus:** ΔH is divided by the norm of the ShapeSurface order (≈ 3.07 at order 2 on square). Potts J = J_Morpheus / norm. This is not yet in AUTHORING §12.9 and affects every Morpheus import [sub].
- **Papers that print H as a sum over ordered pairs** (GG Eq 2, Jiang 1999 Eq 1, Bauer, Zajac Eq 1, Fortuna Eq 4) without ½:
  - Where code or text pins the flip cost, it is once per pair: GG p.2132-2133 (n·J); Fortuna through CC3D.
  - For Jiang 1999, Jiang 2005, Bauer and Zajac it is UNSTATED. The relative scales J/λ and J/γ₀ would change by 2× if their codes double-counted. Ask the authors.
- **Surface terms:** `surface` uses the contact relation's count with no factor.
  - Artistoo (Moore count) matches ✓.
  - CC3D on hex multiplies by `surfaceMF`, and Morpheus normalises. Convert the targets and λ when porting from them.

## 8. Open questions for authors (topology only)

- **Graner/Glazier:**
  - Boundary conditions and lattice size of the PRL/PRE runs.
  - Is Fig 13(a)'s total boundary length counted from both sides (our ×2 is ≈ 73k vs 66.85k)?
  - Which adjacency underlies n in Tables I–III?
- **Merks:**
  - Which `conn_diss` (2000 or 5000) and `neighbours` produced 2006 Fig 4?
  - Confirm 20 neighbours for both copies and contacts in all 2008 figures.
- **Niculescu/de Boer:**
  - TST `neighbours` value for the 2015 runs.
  - Does V(u) in GM_Act include u (Artistoo includes it)?
  - Which Merks connectivity variant was used (with the medium clause)?
- **Akeeb/Jiang:** NeighborTracker adjacency order used for the main-tumour BFS and the singles.
- **Jiang 1999:**
  - Is "fourth-nearest" the cumulative 20-site set?
  - Was the same set used for the wall test and the neighbour choice?
  - Which set defines sides and T1?
  - Once- or twice-counted bonds?
  - The y-wall type.
- **Jiang 2005:** the 3D neighbour orders (6/18/26) for copies and contacts; the outer boundary.
- **Bauer 2007/2009:**
  - Is "second nearest" shells 1–2 or diagonals only?
  - The adhesion order.
  - The BFS adjacency.
  - y periodicity for cells.
  - The pixel size.
- **Jafari Nivlouei:** CC3D Potts and Contact `NeighborOrder`; `Connectivity` vs `ConnectivityGlobal`; the VEGF boundary.
- **Andasari:** the Contact order; the domain boundary; how contact area was computed (NeighborTracker, surface factor).
- **Zajac:** the neighbour order for contacts, for "boundary site" and for "nearby site"; ordered-pair double counting.
- **Starruß:**
  - Is "second-nearest" 12 neighbours?
  - Was the box rhombic or offset-rectangular?
  - The lattice size and the MCS definition.
  - Was a Morpheus-style surface normalisation applied?
- **FBCA:**
  - The top boundary.
  - Diagonal sites in the rim and in the redistribution.
  - The SC1 checkerboard.
- **Fortuna/Dal-Castel:** none topological beyond the CC3D frozen-pick accounting, which is equivalent anyway.

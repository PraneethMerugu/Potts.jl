# 10 — Akeeb, Marcus & Jiang 2026: leader–follower tumor invasion (paper-grounded spec)

## 1. Sources

| Prefix | Citation | DOI | PDF on disk |
|---|---|---|---|
| **10** | S. Akeeb, A.I. Marcus, Y. Jiang, "Clusters, fingers, and singles: A mechanical landscape of tumor invasion", *PLoS Comput Biol* **22**(9): e1014747 (published 8 Sep 2026) | 10.1371/journal.pcbi.1014747 | `docs/references/10_Akeeb2026_PLoSCB_tumor-invasion-fingering.pdf` (24 pp.; page numbers = PLoS "n / 24") |

**Code.** The paper gives **two different URLs**:
- Data-availability statement (10 p.2): `https://github.com/Jiang-Lab/Leader_Follower_Invasion_Model`.
- "Computational implementation" (10 p.7): `https://github.com/Jiang-Lab/Tumor_Invasion_Model`.

Both repositories exist (`git ls-remote`). `Tumor_Invasion_Model` HEAD is `69666f957447c29aab3d02500a4084c7c5b66482`; it was **not read**. The repository README gives a third URL (`SheriffACode/tumor-invasion-model`).

This spec uses `Leader_Follower_Invasion_Model` at commit **`0b9673faa736b2ee54bb200142546ade9e841093`** (HEAD, 21 Nov 2025). That is the commit audited in `SCDPotts/research/akeeb_source_audit.md`. Code citations use these abbreviations:
- `S:N` = `Implementation/Main_Simulation_Scan/cclc_math_path/Simulation/CCIecmSteppables.py:N`
- `X:N` = `…/Simulation/CCIecm.xml:N`
- `P:N` = `…/Simulation/CCIecm.py:N`
- Notebooks as `NB:<file> cell k`

CompuCell3D internals are cited from `CompuCell3D/CompuCell3D` tag **4.6.0** (commit `397f8b1dd3c7c9d78eb9cf43aa9779e006921f5d`). They are marked **external (not in our PDFs)**.

Local audit (read-only): `SCDPotts/research/akeeb_source_audit.md` (cited as "audit").

---

## 2. Mechanics

### 2.1 Energy

**Eq. (1), 10 p.4:**

H = Σ_{⟨i,j⟩} J(τ(σ_i), τ(σ_j))(1 − δ_{σ_i,σ_j}) + Σ_σ λ_V (V_σ − V_T,σ)² − Σ_x λ · c(x) · δ_{σ(x),LC}

- "Lower values of J correspond to stronger adhesion" (p.4).
- The third term "restricts this term to only those lattice sites occupied by leader cells" (p.4).
- **The code does not implement the third term as written** (D6). It uses CompuCell3D `Chemotaxis` with the default Merks algorithm. Per copy of site `pt` from source (flip neighbour) `s`:
  - ΔH_chem = λ·(c(s) − c(pt)), i.e. **−λ[c(target) − c(source)]**.
  - It is applied **once** if the copying cell (`newCell`) is a leader, **else** if the replaced cell (`oldCell`) is a leader.
  - Sources (external): CC3D 4.6.0 `ChemotaxisPlugin.cpp`. The constructor selects `merksChemotaxis`, which checks `newCell` then `oldCell`. `simpleChemotaxisFormula` returns `(_flipNeighborConc-_conc)*lambda`. The XML sets no `Algorithm` (X:66–73).
- Consequence: an absolute potential λ·c summed over leader sites (Eq. 1) would scale with y (up to 30 × 299). The code's ΔH is ±λ per unit step in y.

**Contact neighbourhood.**
- Code: `<Contact> … <NeighborOrder>2</NeighborOrder>` (X:59), i.e. 8 neighbours in 2D square (CC3D convention; external).
- Paper: not stated.

**Connectivity.**
- Code: `<Plugin Name="Connectivity"><Penalty>100000</Penalty>` (X:29–31). It applies to every non-medium cell losing a site.
- CC3D 4.6.0 rule (external; `ConnectivityPlugin.cpp` `changeEnergy`):
  - Returns 0 if `oldCell` is medium.
  - Returns the penalty if the copying cell has no first-order neighbour pixel at `pt`.
  - Returns the penalty unless the 8-pixel ring of `pt` has **exactly two** "collisions" (transitions touching `oldCell`), i.e. `oldCell`'s ring pixels form one contiguous arc.
  - A one-pixel cell has zero ring pixels (collisions = 0), so its last site is penalised. **The plugin therefore also prevents extinction of one-site cells.**
- Paper: **not mentioned.**

**Surface plugin.** `<Plugin Name="Surface"/>` with no parameters (X:43). It is assumed to track surface only, with no energy (external; unverified). Not in the paper.

### 2.2 Dynamics

**Acceptance, Eq. (2), 10 p.4.** P = 1 if ΔH ≤ 0, and e^{−ΔH/T} if ΔH > 0. T = 10 (Table 1 p.7; X:16).

**MCS.** "a number of attempted lattice-site copy events equal to the total number of lattice sites" (p.4).

**Proposal neighbourhood.**
- Code: `<NeighborOrder>1</NeighborOrder>` in `<Potts>` (X:17), i.e. 4 neighbours (CC3D; external).
- Paper: not stated ("to a neighboring site", p.4).

**Lattice / BCs.**
- 500 × 300 (p.4; Table 1 p.7; X:14).
- "periodic boundary conditions along the horizontal (x) direction" (p.4, p.7); `<Boundary_x>Periodic</Boundary_x>` (X:18).
- y is not periodic (`Boundary_y` commented out, X:19). This is the CC3D default no-flux wall (external).

**Duration.**
- Paper: "Simulations were run for 700 MCS" (p.4, p.7), with metrics "at the final time point (MCS = 700)" (p.7).
- Code: `<Steps>701</Steps>` (X:15), i.e. MCS 0…700. Metrics at MCS 700 follow 701 Metropolis sweeps if CC3D sweeps at MCS 0 (external; believed). See A-5.
- **Settled by the authors' data (audit, §5.3.2):** the MCS-0 snapshot follows one sweep. Before any sweep the slab top is flat at y = 20, so the invasive area would be exactly 0. In all 13,310 runs of `Data/Invasion_Metrics_By_MCS/invasion_metrics_0_mcs.csv` it is 465–1014 px² (mean 506.7). The authors' "MCS t" is therefore the state after t + 1 sweeps and t growth/mitosis rounds.

**Per-MCS order (code).** Steppables are registered as NeighborTracker (metrics, every 10 MCS; P:5), ConstraintInitializer (cell counts), Growth, Mitosis (P:11–26). CC3D runs them after each Metropolis sweep (external). So each MCS is:
1. Copy sweep.
2. Metrics every 10 MCS.
3. Cell-count log.
4. Growth.
5. Clock increment + division.

The paper does not state an order.

### 2.3 Initial condition

**Paper.**
- "a planar slab of follower cells … spanning the full width of 500 pixels and a height of 21 pixels (y = 0–21) … approximately 1167 follower cells" (p.5).
- "A random subset of 25% of these cells was then reassigned as leader cells" (p.5).
- Fig. 1 caption: leaders "25% of population", followers "75%" (p.5).

**Code.**
- `UniformInitializer` box x 0–500, y 0–21, `Width 3`, `Gap 0`, type FC (X:121–131). This gives 167 × 7 = **1169** followers of 3×3 sites. The last column is clipped to 2×3 (sample CSV row 0: 1169 followers).
- Then (S:64–75), until LC/(LC+FC) ≥ 0.25:
  1. Create a **new** leader cell.
  2. Draw x ∈ {1,…,499} (`randint(1, dim.x)`) and y ∈ {1,…,19} (`randint(1,20)`).
  3. If that pixel is a follower's, overwrite it with the new one-pixel leader.
- This produces **390 one-site leaders + 1169 followers = 1559 cells** (sample `CellCount_2_24_0.5.csv` row 0). This contradicts "reassigned" (D1).
- **Empty leaders (audit, §5.3.6).** `new_cell(self.LC)` runs on **every** draw (S:68), but the cell is painted only if the pixel is a follower's (S:73–74). A draw that lands on an existing leader leaves an unpainted, zero-site leader in the inventory, and `cell_list_by_type(self.LC)` counts it. The ratio is recomputed only after a hit (S:75). A seeding-only simulation (20,000 draws of the procedure) gives **7.9 ± 2.8 empty and 382.1 ± 2.7 painted leaders**. The inventory count is 390 in 96.1 % of runs, 391 in 3.7 % and 392 in 0.1 %. "390 leaders" in the CSVs is the inventory count.
- The sample copy uses `randint(1,499)`, i.e. x ∈ {1…498} (`Sample/Multimodal_invasion/Simulation/CCIecmSteppables.py`).
- Then every FC and LC gets `targetVolume = 10`, `lambdaVolume = 2.0` (S:86–88). Leaders therefore start at volume 1 with target 10.

**Field.**
- Paper: "c(x,y) = y/g, where g = 1" (p.6), "static, non-diffusing" (p.6).
- Code: `mv[x,y] = y/g`, g = 1, set once in `start` (S:78–83). `DiffusionSolverFE` has D = 0 and decay 0 (X:75–119). Its BC entries (ConstantValue 10/5 in x, ConstantDerivative 10/5 in y) are inert with D = 0.

**Parameter steering.** `J_LF` and chemotaxis λ are written into the XML in `start` (S:90–91). Their taking effect is **assumed** (CC3D steering; external).

### 2.4 Growth, clocks, division

**Paper.**
- "fgrow 0.015 MCS⁻¹" (Table 1 p.7).
- "a subset of size PP × N_FC … was designated as proliferation-competent" (p.6).
- Division "when their volume exceeded 20 pixels (twice the target volume) and their internal clock surpassed a division time drawn uniformly from 75 ± 50 MCS, i.e., U(25, 125) MCS, corresponding to a mean inter-division time of 75 MCS ≈ 3.1 h" (p.6).
- "bisected along random axes, and daughter cells inherited a proliferation-competent state with reset timers" (p.6). Leaders do not proliferate (p.6–7).

**Code.**

| Step | Code | Line |
|---|---|---|
| Growth | Every FC (competent **or not**): `if targetVolume < 20: targetVolume += 0.015` each MCS | S:111–115 (fgrow S:20) |
| Clock assignment (once, at start) | Each FC: `if rand() <= PP: clock = randint(0,75)` (integer 0…74), else `None` | S:124–134 |
| Clock tick + test (each MCS) | For FC with clock ≠ None: `clock += 1`; `vary = randint(0,50)` (0…49, **fresh every MCS**); divide if `volume > 20` (actual volume) **and** `clock > 75 + vary` | S:136–147 |
| Division | `divide_cell_random_orientation` | S:151 |
| Daughters | parent `targetVolume /= 2`; parent `clock = 0`; `clone_parent_2_child()` (child copies target, λ, dict incl. clock 0); child type FC | S:155–163 |
| Leader growth | none. `lgrow = 0.010` is defined but unused | S:21 |

The per-MCS test passes with probability (clock − 75)/50 for clock ∈ [76, 125], and certainly at clock ≥ 125. This is a hazard, **not** a single U(25,125) draw per cycle (D3).

### 2.5 Metrics (paper vs code)

| Metric | Paper definition | Code implementation | Agree? |
|---|---|---|---|
| Main tumor | Contact graph; BFS from all cells at "domain base (y = 1)"; neighbours = shared lattice edge (von Neumann) (p.7) | BFS over CC3D `NeighborTracker` neighbours, seeded from cells at `y = 1` for x ∈ 0…498 (`range(0, dim.x − 1)` skips x = 499) (S:493–500, S:458–488) | Mostly. The seed row excludes the last column. The NeighborTracker neighbour definition is not verified to be VN (external) |
| Invasive area | "summing the volumes of all cells belonging to the connected component anchored at y = 1" (p.7) | `trapz(main_top(x) − min_x main_top, x)`: area under the per-column top of the main tumour, above its lowest top point (S:617–657) | **No** (D12) |
| Infiltrative area | "area of the convex hull enclosing all tumor cells" (p.8) | `trapz(outermost_top(x) − min_x main_top, x)`, where outermost = highest non-medium site per column (S:617–657) | **No** (D13). **No spline** is used (D14) |
| Front profile | Per-column highest main-tumour site; "interpolated using cubic smoothing splines (SciPy)" (p.8) | Raw integer per-column maxima; columns lacking either a main or an outer cell are dropped (S:617–640) | **No spline** (D14) |
| Fingers | Peaks with prominence ≥ 10 px, separation ≥ 20 px, width at half-prominence ≥ 5 px; then peaks < 15 px apart merged, leftmost kept (p.8–9) | `find_peaks(main_top, prominence=10, distance=10, width=5)`, then keep a peak if `p − last > 15` (S:659–671) | **Partly** (D15: distance 10 vs 20; the width uses SciPy's default rel_height 0.5, which matches "half-prominence") |
| Singles | "individual cells (leader or follower) with no contact neighbors … located above the minimum y-coordinate of the main tumor" (p.9) | `Single Defects`: **leaders only** with zero NeighborTracker neighbours and `yCOM >` min yCOM of main-tumour cells (S:521–531). A separate `Detached Cells` = LC/FC not in and not adjacent to the main tumour, above that line (S:541–554) | **No** (D16). The paper's reported singles numbers match the leader-only column (§5) |
| Detached clusters | Groups ≥ 2 connected cells disconnected from the main tumour. BFS from "each follower cell outside the main tumor". Composition includes "leader-only satellites" (p.9) | BFS seeded from **FC only**, keep if ≥ 2 cells (S:559–612) | Seeding matches the paper's own procedure. **Leader-only clusters are never detected**, which contradicts "leader-only satellites" (D17) |
| Phenotype | No Invasion: invasive ≈ infiltrative, 0 fingers/defectors/clusters. Single-Cell: infiltrative > invasive, defectors > 0, no fingers/clusters. Bulk: fingers, no defectors/clusters. Multimodal: fingers + (defectors or clusters), infiltrative ≫ invasive (p.9). Thresholds robust to ±20% on prominence and area ratio (p.9, p.11) | Several variants in notebooks. The one producing `phenotype_probability_map.csv` uses fingers/singles/clusters only, no area ratio: No = fingers ∈ {0,1} & singles = 0 & clusters = 0. Single = fingers ∈ {0,1} & singles > 0 & clusters = 0. Bulk = fingers > 0 & singles = 0 & clusters = 0. Multimodal = fingers > 0 otherwise (NB:`Implementation/TumorInvasionAnalysis/Time_evolution.ipynb` cell 2; `New/ResultExtraction.ipynb` cell 21). An area-equality variant with exact `==` exists (NB:`ResultExtraction.ipynb` cell 3). **Audit (§5.3.5, V-A6):** Fig. 5B and the 22/1/23/54 % figures come from the area-equality variant (cell 3, first function → `phenotype_classification.csv` → NB:`Phenotypes.ipynb` cell 7). Fig. 5A comes from the fingers/singles/clusters variant (cell 3, second function → `phenotype_probability_map.csv` → NB:`Phenotypes.ipynb` cells 1, 3) | **No** (D18): no area-ratio threshold in either classifier. The area test is exact equality |

---

## 3. Parameter table

| Symbol | Value | Units | Meaning | Source | Stated/derived |
|---|---|---|---|---|---|
| Lattice | 500 × 300 | px (1 px ≈ 2.5 µm) | domain | 10 p.4, Table 1 p.7; X:14 | stated |
| BC x / y | periodic / wall | — | — | 10 p.4, p.7 (x only); X:18–19 | x stated; y code only |
| T | 10 | E | temperature | Table 1 p.7; X:16 | stated |
| Proposal nbhd | order 1 (4) | — | copy source | X:17 | code only |
| Contact nbhd | order 2 (8) | — | J sum | X:59 | code only |
| J_ML | 2 | E | medium–leader | Table 1; X:53 | stated |
| J_MF | 10 | E | medium–follower | Table 1; X:56 | stated |
| J_LL | 16 | E | leader–leader | Table 1; X:57 | stated |
| J_FF | 5 | E | follower–follower | Table 1; X:55 | stated |
| J_LF | [−5, 5], 11 levels | E | leader–follower (scanned) | p.6, Table 1; S:37 | stated |
| λ_V | 2.0 | E/L⁴ (Table says E/L²) | volume strength, all cells | p.6, Table 1; S:88 | stated |
| V₀ (initial target) | 10 | px | target volume | p.6, Table 1; S:87 | stated |
| λ (μ in code) | [0, 30], 11 levels = {0,3,…,30} | E/L | leader chemotaxis | p.6, Table 1; S:38 | stated (the step 3 grid is code only) |
| c(x,y) | y/g, g = 1 | — | static cue | p.6; S:78–83 | stated |
| Chemotaxis form | Merks: ΔH = −λ[c(tgt) − c(src)] if new or old cell is LC | — | — | CC3D 4.6.0 (external); X:66–73 | code; **paper Eq. 1 differs** |
| Connectivity penalty | 100000 | E | 8-ring single-arc rule | X:29–31 | code only |
| Leader fraction k | 25% (15%, 35% robustness) | — | LC/(LC+FC) at t = 0 | p.5, Table 1; S:15, S:64–75 | stated (mechanism differs, D1) |
| Initial followers | 1169 (3×3 tiles, y = 0…20) | cells | slab | p.5 says ≈ 1167; p.6 says N_FC ≈ 1200; X:121–131; sample CSV | code value; paper approximate |
| Initial leaders | 390 one-site cells | cells | inserted | S:64–75; sample CSV | code only |
| f_grow | 0.015 | px²/MCS | FC target growth while target < 20 | Table 1 p.7; S:20, S:111–115 | rate stated; cap and "all FC" code only |
| PP | [0, 1], 11 levels | — | P(follower competent), Bernoulli per FC | p.6, Table 1; S:39, S:131 | stated (paper: "subset of size PP×N_FC") |
| Initial clock | U{0,…,74} | MCS | competent FCs | S:132 | code only |
| Division gate | volume > 20 **and** clock > 75 + U{0,…,49} (redrawn each MCS) | px, MCS | — | S:143–146. Paper: "U(25,125)", "75 ± 50" (p.6) | **paper ≠ code** (D3) |
| Division | random orientation; target halved, both daughters; clock = 0 both | — | — | p.6; S:151–163 | stated + code |
| Duration | 700 MCS (Steps = 701) | MCS | — | p.4, p.7; X:15 | stated |
| Scale | 1 px ≈ 2.5 µm; 1 MCS ≈ 3.1 min | — | calibration | p.6 | stated |
| Replicates | 10 per combination | — | 13,310 runs | p.6 | stated; code uses `ITERATION % 1331` (S:32–46) |
| RNG seeds | "unique random seeds (0–9)" | — | — | p.6 | **code sets no seed** (X:20 commented; `np.random` unseeded) (D11) |

---

## 4. Verification of prior claims

| # | Prior claim | Verdict | Evidence / correction |
|---|---|---|---|
| 1 | lattice 500×300 | CONFIRMED | p.4; Table 1; X:14 |
| 2 | periodic x, closed y | CONFIRMED (y from code) | Periodic x stated p.4/p.7; X:18. y non-periodic only in code (X:19 commented) |
| 3 | 701 steps | CONFIRMED (code); paper says 700 MCS | X:15 `<Steps>701</Steps>`; 10 p.4 "700 MCS" |
| 4 | T = 10 | CONFIRMED | Table 1 p.7; X:16 |
| 5 | neighbour order 1 proposals, 2 contacts | CONFIRMED (code only) | X:17, X:59. NOT IN PAPER |
| 6 | initial slab of 3×3 followers to y = 21 | CONFIRMED | p.5 "height of 21 pixels (y = 0–21)"; X:124–129 (BoxMax y = 21, Width 3). Rows 0…20 |
| 7 | one-site leaders = 25% of cells | CONFIRMED (code); **paper differs** | S:64–75 inserts new one-pixel leaders. The paper says 25% of followers were "reassigned" (p.5) (D1) |
| 8 | J ML = 2, MF = 10, LL = 16, FF = 5, J_LF varied | CONFIRMED | Table 1 p.7; X:53–57; J_LF ∈ [−5, 5] p.6 |
| 9 | volume λ = 2, initial target 10 | CONFIRMED | p.6; Table 1; S:86–88 |
| 10 | leader chemotaxis on static field c = y with strength λ, CC3D Merks convention | CONFIRMED (code + CC3D) / paper Eq. 1 differs | c = y/g, g = 1 (p.6; S:83). Merks is the CC3D 4.6.0 default (external). Paper Eq. (1) writes an absolute potential −λ Σ c(x) δ_{σ(x),LC} (D6) |
| 11 | connectivity penalty 1e5 | CONFIRMED (code only) | X:29–31. NOT IN PAPER |
| 12 | followers grow target +0.015/MCS while < 20 | CONFIRMED (code); paper gives rate only | S:113–115; Table 1 "fgrow 0.015". The cap and "all followers (not only competent)" are code only |
| 13 | clocks assigned with prob PP | CONFIRMED (code); paper says a fixed-size subset | S:131 `rand() <= PP`; p.6 "a subset of size PP × N_FC" |
| 14 | clock start integer 0–74 | CONFIRMED (code only) | S:132 `randint(0, 75)` |
| 15 | divide when volume > 20 and clock > 75 + U{0..49} | CONFIRMED (code); **paper differs** | S:143–146. Paper: "drawn uniformly from 75 ± 50 MCS, i.e., U(25,125)" (p.6). Code redraws each MCS (D3) |
| 16 | random plane | CONFIRMED | p.6 "bisected along random axes"; S:151 |
| 17 | target halved | CONFIRMED | S:156 plus clone (S:158). The paper does not state target halving |
| 18 | order: copy sweep, growth, clock/division | CONFIRMED (code + CC3D convention) | P:5–26 registration order; metrics steppable runs first each 10 MCS |
| 19 | metrics fingers (peak separation ≥ 20 px, prominence 10, half-prominence width 5) | CONFIRMED (paper); code uses distance 10 + merge > 15 | p.8–9; S:662–669 (D15) |
| 20 | solitary defects | CONFIRMED with correction | Paper: leader **or** follower with no neighbours (p.9). Code "Single Defects" counts **leaders only** (S:521–531) (D16) |
| 21 | detached clusters | CONFIRMED | ≥ 2 connected cells off the main tumour (p.9; S:559–612). Code seeds BFS from followers only (D17) |
| 22 | infiltrative area: paper says convex hull; code integrates per-column envelope **with spline smoothing** | **CORRECTED** | Paper: convex hull (p.8). Code: trapezoid integral of the per-column outermost top **minus the lowest main-tumour top**, **without any spline** (S:652–657). The spline appears in the paper only for the front profile (p.8), and in code only in plotting notebooks (`make_interp_spline`, NB:`invasion_metrics.ipynb` cells 1, 3). Invasive area is likewise per-column in code, not a sum of cell volumes (D12) |
| 23 | reference sample (2,24,0.5): 1559 → 2137 cells at MCS 700 | CONFIRMED | `Sample/Multimodal_invasion/CellCount_2_24_0.5.csv` rows MCS 0 (390, 1169, 1559) and 700 (390, 1747, 2137) |
| 24 | 12 fingers, 218 solitary, 9 clusters | CONFIRMED | `Sample/Multimodal_invasion/Metrics_Data_2_24_0.5.csv` MCS 700: Invasive 13774.0, Infiltrative 44153.0, Fingers 12, Single Defects 218, Detached Cells 271, Clusters 9. This sample was run with the metrics steppable at frequency 100 (sample `CCIecm.py`). "218 solitary" is **leaders only** |

---

## 5. Validation targets

Policy: ensemble/statistical agreement (D-029), no trajectory parity. Areas below are in **px²** as output by the code. The paper's µm² values equal px² × 6.25 (1 px = 2.5 µm). Most of the paper's reported means reproduce from `Data/invasion_metrics.csv` with that factor, to within 1 % (§5.3.1 lists the exceptions).

The pre-registration audit in §5.3 supersedes the "Proposed acceptance" column of the original §5.2. §5.2 now carries the audited targets.

### 5.1 Ensemble reference from the authors' data (`Data/invasion_metrics.csv`, 13,310 rows, 5 blank)

This file has columns (J_LF, λ, PP, Invasive Area, Infiltrative Area, Singles, Fingers, Detached Cells, Clusters) at MCS 700, 10 replicates per point. The following were recomputed here:

| Point (J_LF, λ, PP) | Invasive px² | Infiltrative px² | Singles (LC only) | Fingers | Detached | Clusters | Phenotype (paper role) |
|---|---|---|---|---|---|---|---|
| (2, 24, 0.5) | 15734 ± 1362 | 44029 ± 1669 | 204.5 ± 9.3 | 12.0 ± 1.2 | 239.4 ± 11.1 | 5.5 ± 2.3 | multimodal (sample point) |
| (2, 30, 0.5) | 12903 ± 1185 | 50860 ± 1827 | 246.8 ± 9.8 | 10.4 ± 1.3 | 312.2 ± 14.1 | 11.2 ± 2.7 | multimodal (p.11 representative) |
| (−2, 15, 0.5) | 4897 ± 826 | = invasive | 0 | 4.2 ± 1.5 | 0 | 0 | bulk (p.11 representative) |
| (4, 12, 0.5) | 7938 ± 2170 | 23349 ± 2333 | 165.9 ± 8.1 | 7.6 ± 1.0 | 168.4 ± 10.0 | 0.2 ± 0.4 | (p.11 names λ = 10; not on grid) |
| (−2, 6, 0.5) | 2155 ± 261 | = invasive | 0 | 0.1 ± 0.3 | 0 | 0 | no invasion (p.11 names λ = 5; not on grid) |
| (−5, 0, 0) | 2479 ± 657 | = invasive | 0 | 0 | 0 | 0 | no invasion |

(Mean ± SD over 10 replicates.) The single sample run (2, 24, 0.5) = (13774, 44153, 218, 12, 271, 9) lies within about 1.5 SD on every metric, except clusters at +1.5 SD.

Audit: every entry above was recomputed with the `csv` module and is correct. The file has 13,310 rows. Five have empty metrics: (−4, 12, 0.5), (−3, 0, 0.4), (−3, 3, 0.6), (−3, 6, 0.8) and (−1, 3, 0.1), so those five points have n = 9. The full per-point reference used by the frozen tests is in §5.3.4.

### 5.2 Targets (audited 2026-09-30; see §5.3 for definitions, pass rules and status)

Every quantitative target uses the code's observable definitions (§5.3.1) and the time mapping in §5.3.2 (run 701 MCS, measure at the end). Pass rules R1–R3 are defined in §5.3.3. "Ours n" is the ensemble we run per point, with independent seeds.

| ID | Target | Source | Type | Acceptance (pre-registered) |
|---|---|---|---|---|
| V-A0 | One-sweep front: invasive area after the first sweep at (2, 24, 0.5) is 499.4 ± 5.3 px² (n = 10), infiltrative = invasive, all counts 0 | `Data/Invasion_Metrics_By_MCS/invasion_metrics_0_mcs.csv` | Quantitative (cheap) | R1, ours n = 10, one MCS each. A run that measures before any sweep gives 0 and fails |
| V-A1 | Initial layout and divisions at (2, 24, 0.5). (a) 1169 followers (3 × 3 tiles, last column 2 × 3). The leader quota counts 390 (inventory sense). (b) Leaders never divide and are never lost. (c) Divisions by the MCS-700 snapshot: 578 (= 2137 − 1559, one sample run) | sample `CellCount_2_24_0.5.csv`; S:64–75, S:124–163 | Quantitative | (a) Exact. "390" is the inventory count including empty leaders (MD-1 decided: emulate authors, §5.3.6). (b) Exact at every MCS. (c) \|mean − 578\| ≤ 55 with ours n = 10: 3 × 17.1 × √(1 + 1/10), where 17.1 is the binomial SD of the competent-follower count, Bin(1169, 0.5). Divisions do not depend on empty leaders |
| V-A2 | Per-point ensemble means of the six metrics at the eight points P1–P8 (§5.3.4) | `Data/invasion_metrics.csv` | Quantitative | R1 on each (point, metric), 48 tests, ours n = 10 per point |
| V-A3 | Marginal means over the PP = 0.5 slice (121 (J_LF, λ) points). Fingers: 7.20 ± 0.24 at J_LF ∈ [−1, 2], 9.78 ± 0.15 at λ ≥ 20, 3.99 ± 0.22 at J_LF ≤ −2, 6.08 ± 0.20 at J_LF > 2. Singles: 175.94 ± 6.60 at J_LF > 2, 1.46 ± 0.22 at J_LF ≤ −2, 52.94 ± 3.37 at J_LF ∈ [−1, 2]. Clusters: 1.63 ± 0.15 at J_LF ∈ [−1, 2], 1.77 ± 0.16 at J_LF > 2 (mean ± SE). The paper's full-sweep values are 7.11 / 9.74 / 4.03 / 6.11, 175.79 / 1.53 / 53.06 and 1.69 / 1.78 | CSV slice; 10 p.10–11 | Quantitative (FULL tier) | R2, ours n = 10 per (J_LF, λ), 1210 runs |
| V-A4 | Invasive area over the PP = 0.5 slice, px² (mean ± SE): J_LF ≤ −2: 5381 ± 206; J_LF ∈ [−1, 2]: 10301 ± 335; J_LF > 2: 6658 ± 192; λ ≥ 20: 12173 ± 275; λ < 10: 2866 ± 53 (ratio 4.25). Infiltrative: λ ≥ 20: 30351 ± 860; λ < 10: 3545 ± 133 (ratio 8.56). The paper's µm² values are 33,875 / 64,463 / 41,856 / 76,125 / 18,163 / 191,200 / 22,369 | CSV slice; 10 p.10 | Quantitative (FULL tier) | R2 on each of the seven means. The ordering [−1, 2] > (> 2) > (≤ −2) holds strictly. Both ratios are within ±15 % |
| V-A5 | Cluster incidence over the PP = 0.5 slice: 28.3 % of runs have clusters ≥ 1 (N = 1209). For λ ≥ 24: 71.5 % (N = 330), with a mean of 4.85 ± 0.24 clusters when present | CSV slice; 10 p.10–11 | Quantitative (FULL tier) | R3 on both incidences; R2 on the conditional mean |
| V-A6 | Phenotype fractions 22 / 1 / 23 / 54 % (No / Single / Bulk / Multimodal) | 10 p.13; Fig. 5B | Classifier-dependent | **PARKED** (author question 1). The evidence identifies the classifier (§5.3.5). If un-parked: the area-equality classifier on a full sweep, R3 per phenotype |
| V-A7 | Proliferation (PP) barely matters: the metrics at (2, 24, 0), (2, 24, 0.5) and (2, 24, 1.0) each match their own CSV reference | CSV; 10 p.10–11 (\|r\| < 0.03) | Quantitative | R1 at the three points; P1 and P7 are already in V-A2, and P9 = (2, 24, 1.0) adds 6 tests. The full-sweep \|r\| < 0.05 is FULL-sweep only and optional |
| V-A8 | Detached-cluster composition at MCS 700, pooled over the ensemble. (2, 24, 0.5): mean size 5.79 (per-cluster SD 3.75, 75 clusters in 12 runs), leader fraction 0.578. (2, 30, 0.5): 5.56 (SD 3.71, 143 clusters), 0.517 | `Data/NEW/cluster_data.csv` (the same runs as NEW `…_at_700_mcs.csv`) | Quantitative | Mean size by R1, with clusters as the sample units and a 10 % margin. Pooled leader fraction within ±0.10. The paper's "mean ≈ 7, 60–70 % leaders, median 4 L / 3 F" is **PARKED** (§5.3.5) |
| V-A9 | Leader speed 0.4 px/MCS at λ = 20 | 10 p.6 | — | **PARKED**: the observable is undefined, λ = 20 is off the grid, and no code or data exist |
| V-A10 | Morphology snapshots at 0, 350 and 700 MCS per phenotype | 10 Fig. 4 | Qualitative | Tutorial figure; not gating |
| V-A11 | Time course at (2, 24, 0.5), MCS 100 / 300 / 500 (six metrics, §5.3.4) | `Data/Invasion_Metrics_By_MCS/invasion_metrics_{100,300,500}_mcs.csv` | Quantitative | R1, 18 tests. Measure after t + 1 MCS. Ours n = 10: the same runs as V-A2 P1, snapshotted |
| V-C1 | Negative control, PP = 0: no division ever at (2, 24, 0); the live cell count is constant | S:131; samples `CellCount_-5_30_0.csv` and `CellCount_-5_0_0.csv` (1559 on all 701 rows) | Exact + R1 | Divisions = 0 in every run (exact). The metrics pass R1 against P7 |
| V-C2 | Negative control, λ = 0: no invasion at (2, 0, 0.5) | CSV. Over all 1209 λ = 0 runs: clusters = 0 in every run; fingers > 0 in 33 runs, singles > 0 in 6 (all at J_LF ≥ 3) | Exact + R1 | Clusters = 0 in every run (exact). Invasive area by R1 (1963 ± 300). Singles, fingers and detached have mean ≤ 1 (R1 floor) |

### 5.3 Pre-registration audit (for freezing)

The audit ran on 2026-09-30, before the coordinator freezes `reproductions/10_akeeb.jl` (ROADMAP P6.2b). Once frozen, changing a tolerance below needs a DECISIONS entry (D-053).

Method:
- Every number was recomputed from the authors' CSVs with Python's `csv` module (no pandas).
- Observable definitions were checked line by line against the metric code (`S:` = the scan copy of `CCIecmSteppables.py`, §1).
- Pass rules were calibrated on the authors' own independent ensembles.

#### 5.3.1 Reference data: three independent author ensembles

The release holds **three separate sweeps** (exact-row overlap ≤ 18 rows between any two, all at trivially identical λ = 0 values). They are not copies.

| Tag | File(s) | Runs | n per point | Snapshots | Used for |
|---|---|---|---|---|---|
| **A** | `Data/invasion_metrics.csv` | 13,305 (+ 5 blank) | 10 (9 at five points) | MCS 700 | V-A2, V-A3–A5, V-A7, V-C1–C2. The paper's text numbers come from A |
| **B** | `Data/Invasion_Metrics_By_MCS/invasion_metrics_{0..700}_mcs.csv` (built by NB:`ResultExtraction.ipynb` cell 1 from `Metrics_Data_*.csv`, every 100 MCS) | 13,259 at MCS 700 | 10 (some 8–9) | 0, 100, …, 700 | V-A0, V-A11; calibration |
| **C** | `Data/NEW/Invasion_Metrics_By_MCS/invasion_metrics_at_{t}_mcs.csv`, `Data/NEW/cluster_data.csv` | 15,963 at MCS 700 | 12 (11 at nine points) | 0, 100, …, 700 | V-A8 (cluster compositions: 75 clusters at (2, 24, 0.5) = ΣClusters over C's 12 runs); calibration |

**Paper vs A (µm² = px² × 6.25).** These match to rounding:
- 64,463 (A: 64,460), 41,856 (41,854), 18,163 (18,164), 22,369 (22,370) and 183,406 (183,408);
- fingers 7.11 / 9.74 / 6.11; singles 175.79 / 53.06; clusters 1.69 / 1.78;
- ratios 4.2 (4.18) and 8.5 (8.49);
- Pearson correlations λ–invasive 0.70 (0.700), λ–fingers 0.80 (0.795), J_LF–singles 0.67 (0.672), J_LF–infiltrative 0.57 (0.567); PP–fingers −0.000 (0.001), PP–clusters −0.002 (−0.002), PP–all \|r\| < 0.03 (max 0.026).

These do not match exactly, and all are within 1 % of A:
- 33,875 (A 33,984; C 33,873);
- 76,125 (75,867);
- 191,200 (189,954);
- fingers 4.03 (4.07);
- singles 1.53 (1.52);
- 3763 / 13,310 = 28.3 % (A 3805 / 13,305 = 28.6 %);
- 70.1 % and 5.00 (70.4 %, 4.94).

The paper probably mixed dataset versions; no single dataset matches every number.
- "Weak adhesion increased infiltrative area to 183,406 µm² … under high migration" (p.10) reproduces only as the **unconditional** J_LF > 2 marginal. Conditional on λ ≥ 20 it is 316,703.
- The paper's "intermediate" fingers 7.11 needs J_LF ∈ [−1, 2]. With [0, 2] it is 7.35.

Sweep-level targets use the **PP = 0.5 slice**, whose values are re-derived from A (V-A3–A5), not the paper's full-sweep numbers. The slice is within 1.5 % of the full sweep for areas, fingers and large counts. Running the slice, 121 × 10 runs, costs about 1.7 CPU-hours against about 18 for the full sweep.

#### 5.3.2 Time mapping and initial layout

- **CC3D step k (k = 0…700)** runs, in order:
  1. one Metropolis sweep;
  2. metrics, if k mod 10 = 0 (P:5; the samples use 100);
  3. the cell-count log (S:94–101);
  4. growth (S:111–115);
  5. clock, gate and division (S:136–163).

  The authors' "MCS t" snapshot is therefore **after t + 1 sweeps and t lifecycle rounds**. This is settled by data: the MCS-0 invasive area is never 0 (§2.2).
- **Our port** runs a sweep and then a lifecycle round each MCS. **Rule: to compare with the authors' MCS t, run t + 1 MCS and measure at the end.** This is README §4.7 A6: run 701 MCS for "700".
  - The extra lifecycle round adds 0.015 to the target volumes and a few divisions at most, since divisions saturate by MCS ≈ 450 in the sample.
  - A division splits a cell into two adjacent cells, so it changes no count below. This is negligible against every tolerance.
- **Layout.**
  - Followers: `UniformInitializer` 3 × 3 tiles over x 0…499 and y 0…20 (X:121–131). That is 167 × 7 = **1169** followers; the last column is 2 × 3.
  - Leaders: inserted at x ∈ 1…499 and y ∈ 1…19 (S:70–71), 9481 drawable pixels, until the inventory ratio reaches 0.25.
  - The inventory count is then **390 LC + 1169 FC = 1559**, and a follower is never erased (0 in 20,000 simulated seedings).
  - Clocks are Bernoulli(PP) per follower, U{0…74} (S:131–132).
  - Targets are 10 and λ_V = 2 for every cell (S:86–88).
  - Painted versus inventory leaders: §5.3.6.
- **Division time course** (sample, informative only; one run): 1559 until MCS 157; then 1599 (MCS 250), 1773 (300), 2106 (400), 2135 (500) and 2137 (700). Almost every competent follower divides once, between MCS 150 and 450.

#### 5.3.3 Pass rules and their calibration

- **R1 (per point; equivalence with a statistical floor).** Let the reference be (μ_A, s_A, n_A) and ours (μ_B, s_B, n_B). The test passes iff

  |μ_B − μ_A| ≤ max( 3·√(s_A²/n_A + s_B²/n_B), 0.10·|μ_A|, f_m ),

  where the floor f_m is 0 for areas and 1.0 for the counts (singles, fingers, detached, clusters). For a zero reference (s_A = 0), R1 reduces to a mean of at most 3·s_B/√n_B or 1.
- **R2 (marginal over a slice).** R1 with SE = SD_runs/√N for both sides. This is conservative for a fixed design, because the run-level SD includes between-point spread.
- **R3 (incidence).** |p_B − p_A| ≤ max( 3·√(p_A(1−p_A)/N_A + p_B(1−p_B)/N_B), 0.05 ).
- **Why the 10 % margin.** Pure 3·SE rules fail the authors against themselves: B versus A reaches |z| = 3.6 on singles at (2, 30, 0.5). The margin absorbs cross-engine systematics of the size the paper itself accepts (< 15 % between 2D and 3D, p.11).
- **Calibration: the rules pass the authors' independent ensembles.**
  - R1 on B versus A and C versus A at the eight V-A2 points: **96 / 96 pass** (max |z| = 3.6).
  - R1 on B versus C in the V-A0 / V-A11 time course (MCS 0 / 100 / 300 / 500): **24 / 24 pass**.
  - R2 on B and C versus A on the V-A3 / V-A4 slice marginals: **all pass**. The largest relative gap, clusters at J_LF > 2 (C +17 %), passes on 3·SE.
  - The frozen test should carry this self-check as a fixture test: rules against the reference CSV versus B/C. That is the D-060 lesson of testing the test.
- **Invariants that hold in every one of A, B and C, to assert per run:** infiltrative ≥ invasive, and detached ≥ singles.
- **Ensemble and cost.**
  - Ours n = 10 per point, with independent seeds (the authors set no seed, D11). CI tier: V-A0, V-A1, V-A2 (P1–P8), V-A7 (+P9), V-A8, V-A11, V-C1 and V-C2. That is 9 points × 10 runs × 701 MCS on 500 × 300, about 5 s/run sequential at the gate's 47 ns/site·MCS, so about 8 CPU-minutes.
  - FULL tier: V-A3–A5, 1210 runs, about 1.7 CPU-hours.
  - Family size at the CI tier is 48 + 6 + 18 + 1 + 2 + exact checks. The calibration above bounds the false-fail risk empirically.

**Observable definitions (code-exact).** Coordinates are 0-based (x, y), x periodic, y closed. Our port is 1-based: shift the seed row and nothing else. Every quantity below is translation-invariant or is compared within the same frame.

| # | Observable | Definition (implement exactly) | Code |
|---|---|---|---|
| O1 | Adjacency | Two distinct cells are neighbours iff they own first-order (von Neumann) lattice-neighbour sites, with x periodic. Medium is not a cell | S:475–487 (`get_cell_neighbor_data_list`, `if neighbor`). The NeighborTracker order is believed to be 1 (external; open q. 5; paper p.7 says von Neumann) |
| O2 | Main tumour M | Union of the O1-connected components of the cells owning a site in row y = 1 with x ∈ 0…498 | S:493–500 |
| O3 | Profiles | Per column x: top_main(x) = max y with σ ∈ M; top_out(x) = max y with σ ≠ medium (any cell). Keep a column only if both exist. The arrays are ordered by x. base = min of the kept top_main. (The `clustercells` exclusion in S:632 is vacuous, because the sets are disjoint) | S:617–647 |
| O4 | Invasive / infiltrative area | `numpy.trapz(top_main − base, x)` and `numpy.trapz(top_out − base, x)` over the kept columns, not periodic, in px² (×6.25 → µm²). This is **not** a volume sum or a convex hull (D12, D13), and **no spline** is used (D14) | S:652–657 |
| O5 | Fingers | SciPy 1.7 `find_peaks(top_main, prominence=10, distance=10, width=5)` on the **index** of the kept-column array. Reproduce SciPy's order: (1) local maxima, where a plateau yields its midpoint (floor) and the array ends are never peaks; (2) the distance filter **first**, removing peaks < 10 samples from a higher peak (height priority; ties follow `argsort`); (3) prominence ≥ 10 with no `wlen`; (4) width ≥ 5 at `rel_height` 0.5, by linear interpolation. Then merge: scan left to right and keep p iff p − (last kept) > 15. Fingers = the number kept | S:659–671; paper p.8–9 (D15) |
| O6 | Singles | **Leaders** with zero O1 neighbours and yCOM > min over c ∈ M of yCOM(c) (strict). yCOM is the mean y of the cell's sites | S:521–531 (D16) |
| O7 | Detached cells | Leaders or followers ∉ M with no neighbour in M and yCOM > min over M of yCOM | S:541–554 |
| O8 | Clusters | The number of O1-connected components that contain at least one **follower**, no cell of M, and at least 2 cells. Leader-only components are never counted (D17). There is no y condition. Composition is (#L, #F); the centroid is the mean of member COMs | S:559–612 |
| O9 | Sampling | Measure at the snapshots in §5.3.2 (t + 1 MCS for the authors' t) | P:5; S:192–289 |

#### 5.3.4 Per-point reference (dataset A, MCS 700; mean ± SD, n = 10)

| Pt | (J_LF, λ, PP) | Role | Invasive px² | Infiltrative px² | Singles | Fingers | Detached | Clusters |
|---|---|---|---|---|---|---|---|---|
| P1 | (2, 24, 0.5) | multimodal; reference sample | 15734 ± 1362 | 44029 ± 1669 | 204.5 ± 9.3 | 12.0 ± 1.2 | 239.4 ± 11.1 | 5.5 ± 2.3 |
| P2 | (2, 30, 0.5) | multimodal (p.11 representative) | 12903 ± 1185 | 50860 ± 1827 | 246.8 ± 9.8 | 10.4 ± 1.3 | 312.2 ± 14.1 | 11.2 ± 2.7 |
| P3 | (5, 30, 0.5) | weak adhesion, high λ (the D16/D17 regime) | 4771 ± 935 | 54495 ± 981 | 290.3 ± 6.7 | 4.5 ± 1.1 | 320.5 ± 12.2 | 1.4 ± 1.1 |
| P4 | (−2, 15, 0.5) | bulk (p.11 representative; 10/10 bulk) | 4897 ± 826 | = invasive | 0 | 4.2 ± 1.5 | 0 | 0 |
| P5 | (5, 3, 0.5) | single-cell (the best on-grid point; 5/10 single, 5/10 multimodal) | 2707 ± 282 | 2950 ± 289 | 6.7 ± 2.4 | 0.7 ± 0.8 | 6.7 ± 2.4 | 0 |
| P6 | (−2, 6, 0.5) | no invasion (the paper's λ = 5 is off-grid; 9/10 no invasion) | 2155 ± 261 | = invasive | 0 | 0.1 ± 0.3 | 0 | 0 |
| P7 | (2, 24, 0.0) | V-C1 (PP = 0) | 15319 ± 1873 | 46006 ± 1286 | 204.3 ± 7.9 | 11.1 ± 1.4 | 249.9 ± 16.1 | 7.0 ± 2.1 |
| P8 | (2, 0, 0.5) | V-C2 (λ = 0) | 1963 ± 300 | = invasive | 0 | 0 | 0 | 0 |
| P9 | (2, 24, 1.0) | V-A7 (PP = 1) | 16493 ± 2294 | 42656 ± 2888 | 201.8 ± 6.4 | 11.7 ± 1.9 | 228.4 ± 12.5 | 4.5 ± 1.8 |

*Correction 2026-10-05 (peer session):* P9's infiltrative SD was printed 2889; dataset A gives 2888.46 (sample SD, n = 10), so it is 2888. A recheck of every P1–P9 mean and SD against dataset A (sample SD, rounded to the printed digits) found no other difference.

The paper's single-cell representative (4, 10, 0.5) is off-grid. The nearest grid point, (4, 12, 0.5), has 7.6 ± 1.0 fingers and is 10/10 multimodal in the authors' own data, so it is **not** a single-cell point.

**Time course at P1 (dataset B, n = 10; V-A0, V-A11).**

| MCS | Invasive | Infiltrative | Singles | Fingers | Detached | Clusters |
|---|---|---|---|---|---|---|
| 0 | 499.4 ± 5.3 | = invasive | 0 | 0 | 0 | 0 |
| 100 | 3666 ± 515 | 3765 ± 499 | 3.2 ± 1.5 | 3.8 ± 1.1 | 3.2 ± 1.5 | 0 |
| 300 | 9261 ± 1576 | 12657 ± 1708 | 57.7 ± 4.5 | 9.3 ± 1.6 | 58.8 ± 5.3 | 0.1 ± 0.3 |
| 500 | 15108 ± 933 | 28345 ± 1187 | 139.2 ± 7.1 | 10.8 ± 1.3 | 148.1 ± 6.3 | 1.4 ± 0.5 |

#### 5.3.5 Audit table

| Target | Source (paper / CSV / code) | Observable definition | Parameter point(s) | Ours n | Pass rule | Tolerance | Status | Notes |
|---|---|---|---|---|---|---|---|---|
| V-A0 | CSV B MCS 0; S:192–289; X:15 | O3, O4 (+ O5–O8 = 0) | P1 | 10 × 1 MCS | R1 | ≈ ±50 px² (10 % margin) | **READY** (new) | Pins the one-sweep offset and the area code cheaply. Before any sweep the value is 0 |
| V-A1 | Sample `CellCount_2_24_0.5.csv`; S:64–75, S:124–163; X:121–131 | Cell inventory; divisions = live cells at the end − live cells at the start | P1 | 10 | (a), (b) exact; (c) \|mean − 578\| ≤ 55 | ±55 divisions | **FIX APPLIED** → READY (MD-1 decided, §5.3.6) | Was a final total ±5 % (±107) with no basis. Now based on the Bin(1169, 0.5) SD of 17.1. Divisions are invariant to empty leaders |
| V-A2 | CSV A | O1–O8 | P1–P8 | 10 per point | R1 | max(3·SE_Δ, 10 %, floor 1 for counts) | **FIX APPLIED** → READY | Was "2 SEM or ±15 %" at unspecified points. Now 8 named points, R1, calibrated 96/96 on the authors' own ensembles |
| V-A3 | Paper p.10–11; CSV A (PP = 0.5 slice) | O5, O6, O8 marginals | 121 (J_LF, λ) at PP = 0.5 | 10 per point (1210 runs) | R2 | max(3·SE_Δ, 10 %) | **FIX APPLIED** → READY (FULL tier) | Was ±10 % on the paper's full-sweep values. That fails the authors' own C ensemble (clusters at J_LF > 2, +17 %). The references are now slice-derived |
| V-A4 | Paper p.10; CSV A slice | O4 marginals | as V-A3 | as V-A3 | R2 + strict ordering + ratios ±15 % | as R2 | **FIX APPLIED** → READY (FULL) | Units are now px² for the test. The "183,406 under high migration" wording is unconditional (§5.3.1) |
| V-A5 | Paper p.10–11; CSV A slice | O8 (clusters ≥ 1) | as V-A3 | as V-A3 | R3; R2 on the conditional mean | ≥ 5 pp; ≥ 10 % | **FIX APPLIED** → READY (FULL) | The slice values are 28.3 % and 71.5 %, and 4.85 when present |
| V-A6 | Paper p.13, Fig. 5; NB:`ResultExtraction.ipynb` cell 3; NB:`Phenotypes.ipynb` cells 1, 3, 7 | Classifier on O4–O8 | full sweep | — | (R3 per phenotype if un-parked) | — | **PARKED** | See the evidence below |
| V-A7 | Paper p.10–11; CSV A | O1–O8 | P1, P7, P9 | 10 per point | R1 | as R1 | **FIX APPLIED** → READY | Was \|r\| < 0.05 over the full sweep, which is unrunnable at the CI tier. That form is optional at FULL |
| V-A8 | CSV C `NEW/cluster_data.csv`; paper p.14–17 | O8 composition, pooled | P1, P2 | 10 per point (about 55 / 110 clusters) | R1 (clusters as units) for the mean size; ±0.10 for the leader fraction | about ±2 cells; ±0.10 | **FIX APPLIED** → READY (CSV-anchored). The paper's values are **PARKED** | The old rule "leader fraction > 0.5 at (2, 30, 0.9)" was marginal (the CSV gives 0.507) |
| V-A9 | Paper p.6 | Undefined (net or path; which leaders; which window) | λ = 20 (off-grid) | — | — | — | **PARKED** | The release has no leader-speed code; only cluster velocities, in NB:`clusterAnalysis.ipynb` and `app1.py` |
| V-A10 | Fig. 4 | Visual | P1, P4, P5, P6 | 1 | — | — | READY (not gating) | Tutorial figure |
| V-A11 | CSV B MCS 100 / 300 / 500 | O1–O8 at t + 1 MCS | P1 | 10 (the same runs as P1) | R1 | as R1 | **READY** (new) | Catches kinetic errors, such as λ scaling or division timing, that the endpoint alone would hide |
| V-C1 | S:131; samples at PP = 0 (1559 on all 701 rows) | Division events; O1–O8 | P7 | 10 | Exact (0 divisions) + R1 | — | **READY** (new) | Deterministic given the code |
| V-C2 | CSV A: all 1209 runs at λ = 0 | O8 = 0; O4; O5–O7 | P8 | 10 | Clusters = 0 exactly; R1 on the rest | Floor 1 on counts | **READY** (new) | Not "all metrics exactly 0". At λ = 0, 33/1209 runs have 1–2 fingers and 6/1209 have singles (J_LF ≥ 3) |

**Counts.**
- 15 rows, of which 13 are gating or FULL. By status:
  - READY: 12 (V-A0, A1*, A2, A3, A4, A5, A7, A8-CSV, A10 not gating, A11, C1, C2);
  - PARKED: 3 (V-A6, V-A8 paper values, V-A9);
  - FIX APPLIED: 7 (V-A1, A2, A3, A4, A5, A7, A8).
- *V-A1 is READY in full; clause (a) follows MD-1 (decided: emulate authors).

**PARKED evidence.**
- **V-A6: the classifier is identified by evidence; the author question stays open.**
  - `phenotype_classification.csv` (13,263 rows) is exactly the area-equality classifier of NB:`ResultExtraction.ipynb` cell 3 (first `classify_phenotype`: `invasive == infiltrative`, fingers == 0 or > 0, singles and clusters tests) applied to A, with the 42 "Unclassified" rows dropped.
  - NB:`Phenotypes.ipynb` cell 7 (Fig. 5B: mean ± s.d. of per-replicate proportions) then gives **22.24 ± 0.66 / 1.08 ± 0.21 / 22.54 ± 0.67 / 54.14 ± 0.48 %** (No / Single / Bulk / Multimodal). This equals the paper's 22 / 1 / 23 / 54.
  - `phenotype_probability_map.csv` is the second, fingers/singles/clusters-only function of the same cell, applied to those 13,263 rows (0 mismatches in 1742 rows). It feeds Fig. 5A: NB:`Phenotypes.ipynb` cells 1 and 3 interpolate it on a 40³ grid and show P > 0.5. Its per-voxel mode gives 28.7 / 1.8 / 16.9 / 52.6 %, which does **not** match the text.
  - So **Fig. 5A and Fig. 5B use different classifiers**. Recommendation: narrow author question 1 to "confirm Fig. 5B/S1 Table = area-equality classifier, Fig. 5A = probability map from the fingers/singles/clusters classifier". Un-park V-A6 with the area-equality classifier if the maintainer accepts the evidence under D-050 ("default to whatever produced the published figures").
- **V-A8, the paper's values.** The released per-cluster data do not reproduce "mean ≈ 7 cells, 60–70 % leaders, median 4 L vs 3 F" (p.14–17).
  - `Data/Clusters/cluster_detailed.csv` (17,514 tracked clusters) gives a mean size of 4.55, a median of 4, 45 % of clusters with 4–8 cells, 3 above 30, median 2 L / 1 F, and a leader fraction of 0.547.
  - `NEW/cluster_data.csv` (19,784 clusters at MCS 700) gives 4.61, a median of 4, median 2 L / 1 F, and 0.553.
  - Restricting to J_LF ∈ [0, 2], λ ≥ 24 gives 5.49 and 0.567.
  - This is a new author question: which subset or weighting produced Figs 6–7?
- **V-A9.** There is no definition and no data. Ask the authors how 0.4 px/MCS was measured (author question 6).

#### 5.3.6 Maintainer decision MD-1: empty leaders at seeding (coordinator finding, verified)

> **DECIDED 2026-09-30 by the maintainer: "Emulate authors (Recommended)".** Default: a missed draw counts one leader toward the 390 quota without creating a cell (zero cost), reproducing the authors' CC3D seeding (≈ 382 painted leaders; inventory 390). Today's retry (390 painted leaders) is kept as a variant keyword. The frozen test `lib/PottsModels/test/papers.jl:142–163` must be re-baselined (DECISIONS entry required), including the two issues in §5.3.8 (±50 divisions on one run ≈ 4 % false-fail; `sim` helper defaulting to μ = 30). V-A1(a) is READY under this reading: the leader inventory counts 390 and painted leaders are 390 − (#empty). **Implemented** in `akeeb_state` (P6.2c): see `_seed_leaders!` in `lib/PottsModels/src/akeeb.jl`, which returns the counted inventory.

- **Verified in the authors' scan code.** In the `while i < k/100` loop (S:67), `lc = self.new_cell(self.LC)` runs on every draw (S:68). The pixel is painted only `if c1.type == 2` (FC; X:37–38 give LC = 1, FC = 2) (S:73–74). `i` is recomputed only inside that branch (S:75), and it counts every LC in the inventory, painted or not.
  - The same pattern is in the sample copies and in `DEMO/Main_Simulation/…/CCIecmSteppables.py:46–57` (liveness survey §5).
  - Empty leaders are inert: they never gain a site, and growth and mitosis touch only FC (S:113, S:140).
  - Their yCOM stays 0, so they are never singles or detached (O6, O7 need yCOM > min over M, about 1).
- **Quantified by a seeding-only simulation** (the exact procedure on the 500 × 21 slab, 20,000 replicates, Python):
  - empty leaders 7.9 ± 2.8 (5–95 %: 4–13);
  - painted leaders 382.1 ± 2.7;
  - inventory LC 390 (96.1 %), 391 (3.7 %), 392 (0.1 %);
  - no follower is ever fully erased;
  - analytic check: Σ_{n<390} n/9481 ≈ 8.0.
- **Sample cross-check.** The MCS-700 bookkeeping of `Sample/Multimodal_invasion` (`data_2_24_0.5.txt`, `PositionData_2_24_0.5/*`) runs as follows:
  1. The main tumour holds 136 L + 1728 F. Singles are 218 and cluster leaders 32.
  2. Detached cells number 271: the 218 singles, the 51 cluster cells, and 2 more.
  3. So 390 − 136 − 218 − 32 − 2 = **2 leaders** are neither in M nor above the baseline. Only yCOM = 0 empty cells fit that description.
  4. This is consistent with empty leaders existing, but 2 lies in the 1.3 % lower tail of the simulated distribution. Not run in CC3D; the inference comes from the code.
- **Effect on published metrics and V-targets.**
  - The CSV "Leader Cells" (390 on all 701 rows) and the totals 1559 → 2137 include the empty leaders. The divisions (578) do not depend on them.
  - Singles, detached cells, clusters and areas see about 2 % fewer real leaders than a 390-painted start. At P1 that is about 4 singles against a tolerance of 20.5. It is below every V-A tolerance, so **V-A0 and V-A2–A11 are unaffected**.
  - Only V-A1(a) changes meaning.
- **Options.** Recommendation: **emulate exactly as the default**, as it produced the published data (D-050 heuristic), and keep the current retry as the variant. This is a maintainer decision.
  - **(E) Emulate exactly: recommended default.** On a miss, count one leader toward the quota without creating or painting a cell (liveness survey §4 X2: no unpainted live cells). Stop after a hit once 4·counted ≥ counted + 1169. This costs nothing.
    - Painted leaders are then 390 − misses, distributed as in CC3D.
    - V-A1(a) asserts counted quota = 390 (occasionally 391 or 392, as in CC3D), 1169 followers, and painted = counted − misses.
    - V-A1(c) is unchanged, because divisions are invariant.
  - **(R) Keep the retry** (`akeeb_state` today, `lib/PottsModels/src/akeeb.jl:92–99`) **as a variant**, for example `leaders = :insert_retry`, next to README §4.7 A1's `:reassign`. It paints exactly 390, about 2 % more leaders than the published runs.
- **Consequences.**
  - Option (E) changes `akeeb_state`'s draws and the initial state. `akeeb_state` feeds the frozen `lib/PottsModels/test/papers.jl:142–163`, so the change **needs a DECISIONS entry** and a re-baseline of the performance gate's Akeeb case (liveness survey §5).
  - The papers.jl assertions should survive:
    - `divisions` uses n₀ = `length(kinds)`, which becomes the painted count, so divisions stay comparable with 578;
    - `150 ≤ singles ≤ 300` is wide.
  - Two things in that frozen test to note for the entry:
    - its ±50 divisions on a **single** run is about 2.1 σ (σ ≈ 17.1·√2 ≈ 24), which gives a false-fail risk of about 4 % per run;
    - its `sim` default is μ = 30. The 500 × 300 case passes μ = 24 explicitly.
  - New author question: "Did `new_cell` on missed draws leave zero-site leaders in the published runs?"

#### 5.3.7 Fixes applied to the existing targets (this audit)

1. **V-A1.** The "final total ±5 %" is now "divisions |mean − 578| ≤ 55 (n = 10)", based on the competent-count binomial SD. Leader constancy is restated for painted leaders, and the inventory-390 clause is tied to MD-1.
2. **V-A2.** The rule is now R1 (a 10 % margin with a 3·SE floor, instead of "2 SEM or 15 %"). The eight points and n = 10 are named, and the rule is calibrated on the authors' own ensembles B and C.
3. **V-A3 and V-A4.** The references are now PP = 0.5 slice values from A, with SEs, and the rule is R2. The paper's full-sweep numbers are kept for documentation. V-A4 is in px², with ratios ±15 %.
4. **V-A5.** The references are slice values and the rules are R3 and R2.
5. **V-A6.** PARKED, with the classifier identified by evidence (Fig. 5A and 5B differ).
6. **V-A7.** Reduced to three PP levels at the reference point (R1). The full-sweep \|r\| is optional at FULL.
7. **V-A8.** Re-anchored to `NEW/cluster_data.csv` at P1 and P2. The paper's cluster-size claims are PARKED as not reproducible. The old "(2, 30, 0.9) leader fraction > 0.5" is dropped (the CSV gives 0.507).
8. **V-A9.** PARKED: undefined and unreproducible.
9. **New targets:** V-A0 (one sweep), V-A11 (time course), V-C1 (PP = 0) and V-C2 (λ = 0).
10. **Time mapping and open question 4:** resolved by data (§2.2, §5.3.2).
11. **§2.3:** records the empty-leader mechanism. **§2.5:** records which classifier feeds Fig. 5A and which feeds Fig. 5B.

#### 5.3.8 For the coordinator before freezing

- **Implement O5 to SciPy 1.7 semantics exactly.** The distance filter runs *before* prominence and width, and plateaus give their midpoints. A peak finder that filters prominence first counts differently. Test O5 on hand-made profiles against recorded SciPy outputs; the fixture can be generated once where SciPy is available and stored.
- **Measure at t + 1 MCS** for the authors' t. That means 701 MCS for the MCS-700 targets, and 1 MCS for V-A0.
- **The per-point reference is dataset A.** The time course comes from B and cluster composition from C. Do not pool the datasets. Carry the B/C self-check (§5.3.3) as a test of the rules.
- **μ default = 24** (D-050 A5) must land before freezing, because P1 is the μ = 24 reference. Every point passes μ explicitly anyway.
- **MD-1 decided (emulate authors); implemented in P6.2c (D-068).** `akeeb_state(; seeding = :authors)` is the default and `seeding = :retry` keeps the old 390-painted start. Our 20,000-seed check of the seeding loop gives 382.14 ± 2.73 painted, 7.90 ± 2.74 empty, inventory 390 in 96.1 % (391: 3.7 %, 392: 0.1 %). The frozen papers.jl case is re-baselined: `sim` defaults to μ = 24, and divisions use the ensemble band 585.0 ± 3 × 16.4 (seeds 1:40), which holds 578.
- **Metric code must follow O1–O8.** The existing `lib/PottsModels/test/akeeb_metrics.jl` is not code-exact: `core_singles` counts all cells with no neighbours (leaders and followers), and it has no per-column areas, fingers or FC-seeded clusters. It must not be reused for V-A0–A11. This is ROADMAP P6.2a.


---

## 6. Required general features

| ID | Needed? | Use |
|---|---|---|
| **G1** @transition/@create/@retire + rand(Bernoulli) | **Yes** | Clock assignment with Bernoulli(PP). Per-MCS division gate with a fresh uniform draw. **Creation of new one-site leader cells at init** (@create at a site). Division = @create with a split |
| G2 shape descriptors | No | (Only volume.) Division needs a random-orientation plane through the COM, which is a lifecycle feature, not an energy |
| **G3** contact/copy-scope direction and position | **Yes** | Merks chemotaxis ΔH = −λ[c(tgt) − c(src)], gated on (kind[new] == L) ∨ (kind[old] == L). Needs the source/target roles and field values at both sites |
| **G4** generalized connectivity (local/soft/exact) | **Yes** | CC3D Connectivity: local 8-ring single-arc rule as a **soft** penalty (1e5; effectively hard at T = 10), plus the "copying cell must be a first-order neighbour" rule. A zero-arc ring (one-site cell) is penalised, which gives extinction protection |
| **G5** field BCs + solver | Minimal | Static analytic field c = y. No solver needed (D = 0). Only "initialise field from expression" |
| G6 secrete/uptake | No | — |
| G7 site conversion | No | — |
| **G8** pluggable proposal law | **Yes** | Proposal neighbourhood order 1 ≠ contact order 2 |
| **G9** per-cell component protocol | **Yes** | Per-cell state: target volume (grows by rate while < cap), integer clock (−1 = none), inherited on division with overrides (V_target halved, clock = 0) |
| **G10** cluster-scope quantities | **Yes (observables)** | Cell contact graph; BFS components from a seed set (base row); leader-only vs FC-seeded clusters; cluster composition and centroid |
| **G11** ordered relationships | No | — |
| **G12** observables library | **Yes** | Per-column top profile; trapezoid areas; `find_peaks` equivalent (prominence, distance, width at rel_height 0.5) + merge; convex hull (paper definition); singles/detached counts; cluster tracking across time (stable IDs, merge/split: S:814–900, not specified in paper main text) |
| **G13** initial layout generators | **Yes** | Uniform tiling of w×w cells in a box with edge clipping (CC3D UniformInitializer semantics); "insert one-site cells of kind K at random pixels of kind F until fraction ≥ k" |
| **G14 (new)** mid-run type-fraction/stop criteria at init ("repeat until ratio") | Folded into G13 | Listed for completeness; no new core feature |

---

## 7. Paper–code disagreements (D-list) and open questions

| # | Topic | Paper | Code | Impact |
|---|---|---|---|---|
| D1 | Leader creation | "A random subset of 25% of these cells was then reassigned as leader cells" (p.5) | New one-pixel leaders inserted into follower pixels until LC/(LC+FC) ≥ 0.25; followers keep their cells (S:64–75) | Total cells 1559, not ≈ 1167. Leaders start at volume 1 (target 10) inside followers |
| D2 | Follower count | ≈ 1167 (p.5); N_FC ≈ 1200 (p.6) | 1169 | Minor |
| D3 | Division timer | "U(25,125) MCS", "75 ± 50", "mean inter-division time of 75 MCS ≈ 3.1 h" (p.6) | Initial clock U{0..74}; divide when clock > 75 + U{0..49}, redrawn each MCS, and volume > 20 (S:132, S:143–146) | Earliest division at clock 76; mean > 75. Also 75 MCS × 3.1 min ≈ 3.9 h, not 3.1 h (internal arithmetic error in paper) |
| D4 | Competence | "a subset of size PP × N_FC" (p.6) | Bernoulli(PP) per follower (S:131) | Count fluctuates |
| D5 | Growth | Table 1 gives only f_grow = 0.015 MCS⁻¹ | All FCs (competent or not) grow target by 0.015/MCS while < 20 (S:113–115) | Non-competent followers also swell to about 20 |
| D6 | Chemotaxis | Eq. (1): −λ Σ_x c(x) δ_{σ(x),LC} (absolute potential over leader sites) (p.4) | CC3D Merks: ΔH = λ(c_src − c_tgt) once if new or old cell is LC (external) | Magnitudes differ by orders. **Code is authoritative for reproduction** |
| D7 | Connectivity | Not mentioned | Penalty 1e5 ring rule (X:29–31) | Keeps cells connected and one-site leaders alive |
| D8 | Neighbour orders | Not stated | Proposals 1, contacts 2 (X:17, X:59) | — |
| D9 | CC3D version | 4.6.0 (p.3, p.4; README) | XML header `Version="4.3.1"` (X:1) | Cosmetic; version semantics assumed = 4.6.0 |
| D10 | Code URL | Two different URLs (p.2 vs p.7) | README gives a third | Provenance |
| D11 | Seeds | "unique random seeds (0–9)" (p.6) | No seed set (X:20 commented; `np.random` global) | Replicates not reproducible bitwise (irrelevant under D-029). `param_map.txt` ordering (rep fastest) disagrees with the code's `ITERATION % 1331` mapping (PP fastest) |
| D12 | Invasive area | Sum of main-tumour cell volumes (p.7) | Per-column top area above the lowest top (S:652–657) | Different quantity. Paper numbers reproduce from the code quantity × 6.25, so **the paper reports the code's quantity** |
| D13 | Infiltrative area | Convex hull (p.8) | Per-column outermost area above the lowest main top (S:652–657) | As D12 |
| D14 | Smoothing | "cubic smoothing splines (SciPy)" on the profile (p.8) | None in metric code; spline only in plotting notebooks | Finger counts are from the raw profile |
| D15 | Finger separation | ≥ 20 px (p.8; Fig. 2 caption) | `distance = 10` then merge `p − last > 15` (S:662–669) | Effective min separation 16 px |
| D16 | Singles | Leader **or** follower (p.9) | Leaders only (S:521–531). A follower-inclusive count is the separate "Detached Cells" | Paper's singles numbers equal the leader-only column |
| D17 | Clusters | Composition includes "leader-only satellites" (p.9) | BFS seeded from FC only (S:567), so leader-only clusters are uncounted | Undercount at high λ / weak J_LF |
| D18 | Classifier | Area-ratio criterion with ±20% robustness (p.9, p.11) | The map classifier uses fingers/singles/clusters only; variants differ between notebooks | Phase fractions depend on variant |
| D19 | Main-tumour seed row | All cells at y = 1 (p.7) | x ∈ 0…498 only (S:496) | Negligible |

**Open questions for the authors.**
1. Which classifier variant generated Fig. 5 and S1 Table? The audit evidence (§5.3.5) says Fig. 5B / S1 = the area-equality classifier and Fig. 5A = the probability map from the fingers/singles/clusters classifier. Narrow the question to a confirmation.
2. Confirm that Eq. (1)'s third term is shorthand for the CC3D Merks ΔH.
3. Which repository/commit produced the 13,310 runs? The release holds three independent sweeps (§5.3.1), and no single one matches every number in the paper.
4. Does CC3D sweep at MCS 0, so metrics at "700" follow 701 sweeps? **Answered by data (§2.2): yes.** Drop this question.
5. Is NeighborTracker adjacency equal to the von Neumann criterion stated in the paper?
6. Were the λ = 5, 10, 20 runs used for the 2D/3D check and the speed calibration (not on the scan grid) separate runs? How was the 0.4 px/MCS leader speed measured?
7. (new) Did `new_cell` on missed seeding draws leave zero-site leaders in the published runs (§5.3.6)?
8. (new) Which subset or weighting of clusters gives "mean ≈ 7 cells, 60–70 % leaders, median 4 L / 3 F" (p.14–17)? The released cluster CSVs give 4.6 cells, 55 % and 2 L / 1 F (§5.3.5).

### 7.1 Discrepancies in our existing port `lib/PottsModels/src/akeeb.jl` (read-only review)

| # | Port | Source | Assessment |
|---|---|---|---|
| P1 | `μ = 30.0` default | Code sample μ = 24 (S:25), XML Lambda = 15 (X:71), reference sample (2, 24, 0.5) | Default differs from every source default. Suggest 24 so the default reproduces the reference sample |
| P2 | `@constraint connectivity(leader, follower)` as a **hard** constraint + `@constraint no_extinction` | CC3D soft penalty 1e5 (X:30). The zero-arc case is penalised, so no separate extinction rule exists in source | Hard ≈ soft at T = 10 (e^{−10⁴}). `no_extinction` is an addition, but it reproduces the plugin's one-site protection. Also check the "copying cell must have a first-order neighbour at pt" rule; it is automatic with VN(1) proposals |
| P3 | `@drive copy => ifelse(kind[new]==leader \|\| kind[old]==leader, −μ(cue[target]−cue[source]), 0)` | CC3D Merks (external) | Matches the code. Differs from paper Eq. (1) (D6). The docstring should say so |
| P4 | `cue = y − 1` (1-based) | c = y (0-based) (S:83) | Equivalent |
| P5 | `@divide … when = (clock ≥ 0) && (volume > V_max) && (clock > clock_min + clock_spread·rand())` | `clock > 75 + randint(0,50)` on integer clocks | Equivalent in distribution for integer clocks: P = (clock − 75)/50 either way |
| P6 | `@after_mcs`: V_target grows if `Pre(V_target) < V_max`; clock += 1 if ≥ 0; then `@divide` | Code order: growth, then clock += 1, then test, same MCS (S:111–147) | Matches, provided `@divide` is evaluated after `@after_mcs` in the same MCS (verify) |
| P7 | `rates = 0.015` for **all** followers | S:113 grows all FCs | Matches the code (and D5) |
| P8 | `akeeb_state`: leaders drawn with x ∈ 2:X, y ∈ 2:(slab−1) (1-based) until 4·leaders ≥ total | S:70–75 x ∈ 1…499, y ∈ 1…19 (0-based) | The draw ranges match the scan code (the Sample copy uses x ≤ 498). Miss handling: CC3D leaves an empty leader in the inventory, giving about 382 painted. **Resolved (MD-1, D-068)**: the port now counts a miss toward the quota without creating a cell (`seeding = :authors`, default); the old retry (390 painted) is `seeding = :retry` |
| P9 | Tiles `for y in 1:3:slab` with slab = 21, `x in 1:3:X` clipped | UniformInitializer box 0–500 × 0–21, width 3 | 1169 followers, matching |
| P10 | Clocks: `rand(rng) > pp ? −1 : rand(rng, 0:74)` | S:131–132 | Equivalent |
| P11 | Leader `rate = 0`, target 10 | S:86–88; leaders do not grow | Matches |
| P12 | Docstring: "the source runs 701" but the port counts 1 CC3D step = 1 MCS | X:15 | For the "MCS 700" snapshot, run 701 MCS and measure at the end. The authors' data settle open question 4 (§5.3.2) |
| P13 | No metrics in the model file | `test/akeeb_metrics.jl` exists (not reviewed here) | Metric definitions must follow the **code** (D12–D17) to compare with §5 |
| P14 | Docstring "Faithful to the authors' CompuCell3D model" | — | Accurate for mechanics. Should list D1/D3/D5/D6 as paper-vs-code items so users do not read the paper's Eq. (1) as implemented |

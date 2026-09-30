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
| Phenotype | No Invasion: invasive ≈ infiltrative, 0 fingers/defectors/clusters. Single-Cell: infiltrative > invasive, defectors > 0, no fingers/clusters. Bulk: fingers, no defectors/clusters. Multimodal: fingers + (defectors or clusters), infiltrative ≫ invasive (p.9). Thresholds robust to ±20% on prominence and area ratio (p.9, p.11) | Several variants in notebooks. The one producing `phenotype_probability_map.csv` uses fingers/singles/clusters only, no area ratio: No = fingers ∈ {0,1} & singles = 0 & clusters = 0. Single = fingers ∈ {0,1} & singles > 0 & clusters = 0. Bulk = fingers > 0 & singles = 0 & clusters = 0. Multimodal = fingers > 0 otherwise (NB:`Implementation/TumorInvasionAnalysis/Time_evolution.ipynb` cell 2; `New/ResultExtraction.ipynb` cell 21). An area-equality variant with exact `==` exists (NB:`ResultExtraction.ipynb` cell 3) | **No** (D18): no area-ratio threshold in the code used for the maps |

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

Policy: ensemble/statistical agreement (D-029), no trajectory parity. Areas below are in **px²** as output by the code. The paper's µm² values equal px² × 6.25 (1 px = 2.5 µm): the paper's reported means reproduce from `Data/invasion_metrics.csv` with that factor (checked below).

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

### 5.2 Targets

| ID | Target | Source | Type | Proposed acceptance |
|---|---|---|---|---|
| V-A1 | Cell count 1559 at MCS 0 (390 L + 1169 F) → ≈ 2137 at MCS 700 for (2, 24, 0.5). Leaders constant (390 throughout) | sample `CellCount_2_24_0.5.csv` | Quantitative | Initial counts exact (deterministic layout). Final total within ±5% (ensemble). Leader count must stay 390 (no leader loss) |
| V-A2 | Per-point ensemble means in §5.1 | `Data/invasion_metrics.csv` | Quantitative | Ensemble (n ≥ 10) mean within 2 SEM_combined, or ±15% (the paper's own 2D/3D tolerance, p.11), whichever is larger. Metrics computed **with the code's definitions** (per-column areas, leader-only singles, FC-seeded clusters, raw profile, find_peaks distance = 10, merge > 15) |
| V-A3 | Marginal means (reproduced from the CSV here). Fingers: 7.11 at "intermediate" J_LF (the paper's number reproduces only with J_LF ∈ [−1, 2]), 9.74 at λ ≥ 20, 4.03 (CSV 4.07) at J_LF ≤ −2, 6.11 at J_LF > 2. Singles: 175.79 (J_LF > 2), 1.53 (CSV 1.52; J_LF ≤ −2), 53.06 (J_LF ∈ [−1, 2]). Clusters: 1.69 (intermediate), 1.78 (weak) | 10 p.10–11; CSV | Quantitative (aggregate over a sweep) | Only for a full or subsampled sweep. Each marginal within ±10% |
| V-A4 | Invasive area 33,875 µm² (J_LF ≤ −2), 64,463 (intermediate = [−1, 2]), 41,856 (J_LF > 2). High/low λ: 76,125 vs 18,163 (4.2×). Infiltrative: 191,200 (λ ≥ 20) vs 22,369 (λ < 10) (8.5×) | 10 p.10 | Quantitative (sweep) | Ratios 4.2× and 8.5× within ±20%; the J_LF ordering intermediate > weak > strong |
| V-A5 | Detached clusters in 28.3% of sims (3763/13310; CSV gives 3805/13305). For λ ≥ 24: 70.1% with clusters, mean 5.00 when present (CSV: 70.4%, 4.94) | 10 p.10–11 | Quantitative (sweep) | ±5 percentage points; mean ±15% |
| V-A6 | Phase fractions: No Invasion ≈ 22%, Single-Cell ≈ 1%, Bulk ≈ 23%, Multimodal ≈ 54% of parameter space | 10 p.13; Fig. 5B p.15 | Quantitative (sweep, classifier-dependent) | Only with the authors' classifier variant (D18). ±5 pp |
| V-A7 | PP has negligible effect on fingers/clusters (Pearson r = −0.000, p = 0.985; r = −0.002, p = 0.815) and on all metrics (\|r\| < 0.03) | 10 p.10–11 | Qualitative / statistical | \|r\| < 0.05 over the sweep |
| V-A8 | Cluster sizes: mostly 4–8 cells, mean ≈ 7, rare > 30. Leaders ≈ 60–70% of cluster cells in the cluster-forming regime, median ≈ 4 L vs 3 F per cluster | 10 p.14–17; Figs 6–7 | Semi-quantitative | Mean size 5–9; leader fraction > 0.5 at (2, 30, 0.9) |
| V-A9 | Leader speed 0.4 px/MCS at λ = 20 | 10 p.6 | Quantitative (single statement, λ = 20 is off-grid) | Mean leader COM y-velocity in [0.3, 0.5] px/MCS at λ = 20 over MCS 100–400 |
| V-A10 | Morphology snapshots at 0, 350, 700 MCS per phenotype | 10 Fig. 4 p.14 | Qualitative | Visual |

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

**Open questions for the authors.** (1) Which classifier variant generated Fig. 5 and S1 Table? (2) Confirm that Eq. (1)'s third term is shorthand for the CC3D Merks ΔH. (3) Which repository/commit produced the 13,310 runs? (4) Does CC3D sweep at MCS 0, so metrics at "700" follow 701 sweeps? (5) Is NeighborTracker adjacency equal to the von Neumann criterion stated in the paper? (6) Were the λ = 5, 10, 20 runs used for the 2D/3D check and the speed calibration (not on the scan grid) separate runs?

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
| P8 | `akeeb_state`: leaders drawn with x ∈ 2:X, y ∈ 2:(slab−1) (1-based) until 4·leaders ≥ total | S:70–75 x ∈ 1…499, y ∈ 1…19 (0-based) | Matches the scan code (the Sample copy uses x ≤ 498) |
| P9 | Tiles `for y in 1:3:slab` with slab = 21, `x in 1:3:X` clipped | UniformInitializer box 0–500 × 0–21, width 3 | 1169 followers, matching |
| P10 | Clocks: `rand(rng) > pp ? −1 : rand(rng, 0:74)` | S:131–132 | Equivalent |
| P11 | Leader `rate = 0`, target 10 | S:86–88; leaders do not grow | Matches |
| P12 | Docstring: "the source runs 701" but the port counts 1 CC3D step = 1 MCS | X:15 | For the "MCS 700" snapshot, run 701 sweeps if CC3D sweeps at MCS 0 (open question 4) |
| P13 | No metrics in the model file | `test/akeeb_metrics.jl` exists (not reviewed here) | Metric definitions must follow the **code** (D12–D17) to compare with §5 |
| P14 | Docstring "Faithful to the authors' CompuCell3D model" | — | Accurate for mechanics. Should list D1/D3/D5/D6 as paper-vs-code items so users do not read the paper's Eq. (1) as implemented |

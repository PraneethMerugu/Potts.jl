# 11 — Multiscale CPM: intracellular ↔ cell ↔ extracellular

User's handwritten spec for item 11: *"2D multiscale: intracellular (ODEs / Boolean net) ↔ cell ↔
extracellular (ECM / PDE)"*. Two candidate papers are specified below, then compared (§8).
Every claim cites a PDF in `docs/references/`. Page numbers are the printed page numbers, which equal the PDF page numbers for both files.

## 1. Header

| Tag | Citation | DOI | File |
|---|---|---|---|
| **11a** | Jafari Nivlouei S, Soltani M, Carvalho J, Travasso R, Salimpour MR, Shirani E (2021). "Multiscale modeling of tumor growth and angiogenesis: Evaluation of tumor-targeted therapy." *PLoS Comput Biol* 17(6): e1009081. | 10.1371/journal.pcbi.1009081 | `11a_JafariNivlouei2021_PLoSCB_multiscale-tumor-angiogenesis.pdf` (37 pp) |
| **11b** | Andasari V, Roper RT, Swat MH, Chaplain MAJ (2012). "Integrating Intracellular Dynamics Using CompuCell3D and Bionetsolver: Applications to Multiscale Modelling of Cancer Cell Growth and Invasion." *PLoS ONE* 7(3): e33726. | 10.1371/journal.pone.0033726 | `11b_Andasari2012_PLoSONE_CC3D-Bionetsolver.pdf` (17 pp) |

**Code and data availability**
- **11a:** built on CompuCell3D (http://www.compucell3d.org/, 11a p.13). The Boolean network was analysed with "a MATLAB-based toolbox" (11a p.6).
  - Data statement: "All relevant data are within the manuscript and its Supporting information files" (11a p.1).
  - S1 Data is an XLSX of the plotted numbers for Figs 4, 5, 9, 10, 11, 13, 15, 17, 18, 19 (11a p.30).
  - **No model code or CC3D project is linked.**
  - S1 Data is now on disk as `docs/references/supplementary/11a_JafariNivlouei2021_S1Data.xlsx`. It is described sheet by sheet in §9 and drives the numeric targets in §5A.
- **11b:** CC3D + Bionetsolver, with code *excerpts* printed (11b p.14). Supporting Information S1 is a CC3D tutorial (DOCX) (11b p.16), not on disk. **No repository or SBML file is linked.** Manual URL "http://www.compucel3d.org/Manual" (sic, 11b p.13).

---

## 2A. Mechanics — 11a (Jafari Nivlouei 2021)

**Lattice, time, BCs**
- 2D CPM in CompuCell3D. Lattice 300 × 300 × 1, "equivalent to 1.44mm²" (11a p.13). That gives a 1.2 mm side, so 4 μm per pixel (derived). S1 Data supports this: every tumour area in sheets "Figure 9" and "Figure 18" is a whole multiple of 16 μm² (= 1 px at 4 μm) (§9.1).
- Average tumour cell ≈ 500 μm² (11a p.13). Initial tumour-cell volume "about 32 voxels" (Table 2 footnote, p.14). 32 × 16 μm² = 512 μm² (derived, consistent).
- **Periodic BCs** for the lattice and for the nutrient PDE (11a p.10, p.13).
- 1 MCS = 1 min, "based on the fastest cell cycle time for cell division ~24h" (11a p.13).
- Neighbour order for copies and adhesion: **UNSPECIFIED**.

**Entities (cell types).** Every lattice site is assigned a type index τ; "0 is assigned to all lattice sites that are filled by ECM" (11a p.7). The J matrix (Table 2, p.14) lists these types:
- EC (endothelial);
- M (migrating tumour);
- P (proliferating tumour);
- Q (quiescent tumour);
- N (necrotic);
- m (matrix/ECM).

Normal host cells are used in some runs (11a p.21–23), but **no J row or other parameters for normal cells are given** (UNSPECIFIED). ECs come in "two types of inactive ECs" plus activated ECs (11a p.22). **ECM is a lattice type (the medium), not a field.** There is no ECM density or MMP PDE. Haptotaxis "is essentially modeled through the adhesion energy" (11a p.9).

**Acceptance (11a p.7):** Metropolis. Downhill moves are always accepted; otherwise the copy is accepted with Boltzmann probability e^(−ΔH/T_m), T_m = 10 (Table 2). The extracted text shows "e ΔH=Tm". The sign is garbled in extraction, but standard Metropolis is described in the surrounding text.

**Hamiltonian (Eq 6, 11a p.10)**

  H = Σ_site J_{τ,τ′}(1 − δ_{σ,σ′}) + Σ_cell γ_e (a_σ − A^T_σ)² + Σ_cell α(1 − δ_{a_σ, a′_σ}) + Σ_cell χ_σ Δc

- **Eq 1, adhesion (p.9).** Sum over neighbouring pixels. Table 2 gives a 6 × 6 J matrix.
- **Eq 2, growth/area (p.9).** A^T is "double of the quiescent area for proliferating cells". γ_e is set per phenotype (all = 8).
- **Eq 3, continuity (p.9).** a′_σ is "the number of continuous lattice sites" of σ. The penalty is α = 300 whenever a_σ ≠ a′_σ, i.e. a hard-ish **connectivity** penalty. The paper does not define how a′ is computed (largest connected component?).
- **Eqs 4–5, chemotaxis (p.9).**
  - Migrating tumour cells use Δn (nutrient), **only cells "with migration phenotype"**.
  - Activated ECs use ΔV (VEGF).
  - χ_σ values are **UNSPECIFIED** (not in Table 2). The sign convention is also not stated; the text says "move towards higher concentration" (p.9).

**Extracellular PDEs**
- **Nutrient, Eq 7 (p.10):** ∂n/∂t = D_n ∇²n − B(x,y,n) + S_n.
  - Uptake: B = n if 0 ≤ n ≤ β, and β if n > β, **on cancer-cell sites**; 0 elsewhere. That is, **B = min(n, β)**.
  - β depends on phenotype: β_P (also used for migrating cells), β_Q, β_N = 0 (Table 2).
  - Normal cells "also consume nutrients, but with a different rate". Tumour uptake is "3 times the consumption rate for normal cells" (p.10, p.13).
  - Source: S_n = s_n on **endothelial-cell** sites, else 0.
  - BC/IC as printed: n(x,y,t)|_{ECs} = S_n (a Dirichlet clamp at EC sites); n(x,y,0) = S_0 = 4.6 pg/voxel; periodic (p.10).
  - Oxygen is the implied nutrient: D_n is "approximately half of the diffusion constant of oxygen in the water" (p.13).
- **VEGF, Eq 8 (p.10–11):** ∂V/∂t = D_V ∇²V − kV − E(x,y,V) + S_V.
  - Uptake E = min(V, e) on EC sites.
  - Source S_V = s_V on **hypoxic cancer cell** sites.
  - IC V(x,y,0) = 0 (p.11).
- **Solver, time step, and PDE–MCS coupling:** **UNSPECIFIED**. The text says only that "all the scales … are integrated simultaneously" (p.5) and that fields are "inputs for the next iteration (time step)" (p.12).
- Units are inconsistent (see §7): β in mol/cell/s, n in pg/voxel, V thresholds in pg/pixel.

**Intracellular Boolean network (11a p.6, p.11–12, Table 1 p.8, Fig 2 p.7, Fig 3 p.12)**
- Nodes and rules are given in Table 1 (p.8). Inputs are external signals: Integrin (integrin binding), RTK (VEGF binding for ECs; nutrient for tumour cells, see below), E-Cadherin (cadherin binding), Wnt (Frizzled), APC, NF1.
- Internal rules as printed:

| Node | Rule |
|---|---|
| β-Catenin | "Wnt Or Akt And Not cadherin AND Not APC" |
| Grb-2/Sos | "RTK And Scr" (sic; Src) |
| Src | FAK |
| FAK | ITG |
| Rho-A | FAK |
| ROCK | Rho-A |
| Rac-1 | PI3K And Not Rho-A |
| Ras | Grb-2/Sos And Not NF1 |
| Raf-1 | Ras |
| MEK1/2 | Raf-1 Or Rac-1 |
| ERK1/2 | MEK1/2 |
| RSK | ERK1/2 |
| TSC | Not RSK Or Not Akt |
| mTORC | Not TSC |
| MNK | ERK1/2 |
| eIF4E | MNK |
| MSK | ERK1/2 |
| Fos | MSK And RSK |
| Myc | ERK1/2 Or β-Catenin |
| PI3K | Ras |
| Akt | PI3K |
| eNOS | Akt |
| NO | eNOS |
| Caspase | Not NO |
| Mdm2 | Akt |
| p53 | Not Mdm2 |
| Actin | ROCK Or Rac-1 |
| SNAIL | β-Catenin |

- Output nodes: Cell growth = eIF4E Or mTORC; Cell Proliferation = Fos And Myc; Cell Apoptosis = Caspase Or p53; Cell Migration = Actin And SNAIL.
- Update: synchronous, x_i(t+1) = f_i(x_i1(t), …, x_ik(t)) (p.11). The network is run to its attractor, and an input→output table is derived (Fig 3).
- Robustness: "all possible 2^29 initial combinations of internal node states … converge to the same attractors" (p.15).
- **In the CPM the network is not simulated.** The model uses the **precomputed lookup table in Fig 3** ("determine the cell phenotype, according to the table in Fig 3", p.12).
- **Fig 3 truth table (p.12).** APC = NF1 = OFF (tumour suppressors deficient, p.13). Inputs are (Integrin, RTK, Wnt) plus Cadherin. Output codes: 1101 = growth + proliferation + migration; 0011 and 0010 = apoptosis; 1100 = growth + proliferation.

| ITG RTK Wnt | 111 | 101 | 011 | 001 | 110 | 100 | 010 | 000 |
|---|---|---|---|---|---|---|---|---|
| Cadherin OFF | 1101 | 0011 | 0010 | 0010 | 1101 | 0011 | 0010 | 0010 |
| Cadherin ON | 1101 | 0011 | 0010 | 0010 | **1100** | 0010 | 0010 | 0010 |

  Rule in words: apoptosis unless ITG = RTK = 1. Cadherin ON with Wnt OFF blocks migration (case 110) (p.14).
- **Quiescence** is **not** a Boolean output. Hypoxic, oxygen-starved cells "reach the quiescent state" and "stop growing" (p.14, p.18). The quiescence threshold is **UNSPECIFIED**.

**Input mapping (field/contact → Boolean inputs)**
- **RTK (tumour):** ON if the available nutrient ≥ T_RTK = 4.48×10⁻³ pg/pixel. Below it, apoptosis follows. The threshold is "defined from the rate of nutrients consumption normalized by the cell target area" (p.13). Sensitivity: T_RTK ≈ 0.005 separates survival and apoptosis (p.26).
- **RTK/activation (EC):** VEGF ≥ T_V = 0.00095 pg/pixel activates ECs (p.13, Table 2).
- **Integrin, Cadherin, Wnt:** strength is "estimate[d] … by assessing the cell-ECM and cell-cell contact, normalized by the cell's size" (p.12). Thresholds: T_ITG = 0.3, T_cadherin = 0.3, T_Wnt = 0.15 (Table 2).
  - Integrin ↔ cell–ECM contact fraction and cadherin ↔ cell–cell contact fraction are implied.
  - **Which contact measure drives Wnt is UNSPECIFIED.**
  - Whether "contact" means shared boundary length or neighbour-pixel count: UNSPECIFIED.

**Output mapping (phenotype → CPM)**
- The phenotype selects the cell type (M/P/Q/N, active EC) and thereby its J row, γ_e, β, and whether chemotaxis is on: "parameters are different for each phenotype" (p.12).
- Growth or proliferation sets A^T = 2× quiescent area (p.9).
- **Division:** "cells double their size before undergoing cell division". Daughters inherit the phenotype. One daughter keeps the parent ID (p.9). Activated EC daughters inherit type and target volume (p.22). The exact trigger (a_σ ≥ 2·A_Q?) and the cleavage plane are **UNSPECIFIED**.
- **Apoptosis:** how an apoptotic cell is removed (target → 0? instant deletion?) is **UNSPECIFIED**.
- **Necrosis:** quiescent cells become necrotic under continued deprivation (p.18; Fig 6F "after 20 hours on day 5"). The rule and threshold are **UNSPECIFIED**. Necrotic cells have β_N = 0 (Table 2).
- **VEGF secretion:** hypoxic (quiescent) tumour cells secrete at s_V (Eq 8). Apoptotic or blocked cells stop VEGF release under therapy (p.28).
- **EC contact inhibition:** "as the cell-cell adhesion junctions are increased, the cells' growth is blocked" (p.19). This goes through the cadherin input.

**Update order and cadence (11a p.12)**
- The flow per "time step" is: gather cues → Boolean table → phenotype → CPM (Eq 6) → new topology and fields → next iteration.
- "the process is repeated for each pixel, randomly chosen, in the cell lattice at each Monte-Carlo step" (p.12–13). This implies a per-MCS phenotype update. Whether that is every MCS or every CC3D steppable call with frequency > 1 is not stated.

**Initial conditions (11a p.10, p.13, p.17)**
- 4 proliferating tumour cells at the centre. Fig 5 caption gives an initial radius of 24.3 μm.
- "different tissue structures around them": pre-existing vessels (geometry only in figures; UNSPECIFIED numerically) and optionally normal cells.

**Therapy (11a p.27–29, Figs 18–19)**
- Signalling is "disrupted on days 3, 5 and 6". The blocking codes are cases where a receptor is deactivated: 101, 011, 001, 100, 010, 000 (p.28).
- **Which receptor was clamped in the reported runs is not stated.** The text discusses RTK (TKIs) and integrin (Volociximab) inhibition (p.27).

## 2B. Mechanics — 11b (Andasari 2012)

**Lattice and runs: all 3D (11b p.3, p.6, p.8)**
- (1) Epithelial-layer detachment: 264 × 224 × 60 pixels. A sheet of 30 × 25 × 1 cells, each initially a 7×7×7 cube with 1-pixel gaps.
- (2) Tumour from a layer: 120³. A 10 × 10 cell layer at the face x = 120. Linear chemoattractant gradient along x.
- (3) Multicellular tumour spheroid (MTS): 240³. One 7³ cell at the centre. Radial chemoattractant gradient increasing outward.
- 1 pixel = 2 μm (p.3, p.11). Initial target volume = 1.2 × cell volume, giving ≈410 pixels ≈ 3280 μm³ (p.3). Check: 1.2 × 343 = 411.6 (derived).
- MCS = one copy attempt per lattice site (p.11). **No MCS↔time conversion is adopted** (p.11).
- BCs: **UNSPECIFIED**.

**Acceptance (Eq 1, p.11):** P = 1 if ΔE ≤ 0, else exp(−ΔE/T_m). Source-pixel neighbours go "up to fourth nearest neighbour" (p.11). **T_m is UNSPECIFIED.**

**Hamiltonian (Eq 2, p.13)**

  H = Σ J(τ(σ(i)),τ(σ(j)))(1 − δ) + Σ λ_vol(τ)(v − V_t)² + Σ λ_surf(τ)(s − S_t)² + E_chemo

- Eq 3: J is symmetric. Eq 4: volume term. Eq 5: surface term.
- Eq 6: ΔE_chemo = −λ_chemo (c(j) − c(i)), where j is the target pixel and i the source.
- **All CPM parameter values (J, λ_vol, λ_surf, λ_chemo, T_m) are UNSPECIFIED.** Table 1 lists intracellular parameters only.
- The chemoattractant c is a **prescribed** static gradient, "linear" (p.7) or "radial" (p.9). **No diffusion equation is specified or solved.**
- The paper says CC3D and the centre-based model both "use continuum, reaction-diffusion equations to model extracellular chemical fields" (p.3). That is a statement about the methodologies, not this model.

**Intracellular ODE (Ramis-Conde 2008 [14]), per cell (Eqs 7–12, p.15–16)**
- Dimensionless system (Eq 12):
  - d[Ec]/dt = −c_i(t)[Ec] + d_i(t)[E/β]
  - d[E/β]/dt = A1 − d_i(t)[E/β]
  - d[β]/dt = A2 + d_i(t)[E/β] − k⁺[β](P_T − [C]) + k⁻[C] + k_m
  - d[C]/dt = k⁺[β](P_T − [C]) − k⁻[C] − k₂[C]
- A1 = ν(E_T − [Ec] − [E/β])[β] if [β] < c_T; A1 = −α[E/β] if [β] > c_T (Eq 8).
- A2 = −ν(E_T − [Ec] − [E/β])[β] if [β] < c_T; A2 = α[E/β] if [β] > c_T (Eq 9).
- **Contact-coupled coefficients (Eqs 10–11):**
  - c_i(t) = Σ_{new contacts} a_{c,j}(t) ρ_c, with a_{c,j} = ∂â_j/∂t when positive, else 0.
  - d_i(t) = Σ_{new detachments} a_{d,j}(t) ρ_d, with a_{d,j} = |∂â_j/∂t| when negative, else 0.
  - â_j is "the approximated contact area between cells i and j at time t divided by the surface area of cell i" (p.15).
  - **So the ODE needs per-neighbour contact areas and their time derivative.**
- Nondimensionalised with T = 1 min and E = 1 nM (p.16).
- **SBML implementation trick (p.4–5):** both branches of A1 and A2 live in one SBML model. The threshold switch is done by parameter swap:
  - below threshold: ν = 100, α = 0;
  - above threshold: ν = 0, α = 2.

**Threshold switching and cell-type change (p.5)**
- "We check the b-catenin concentration for every cell at each MCS".
- If a LowBetaCat cell has [β] > c_T (= 50), it becomes HighBetaCat and ν, α are swapped (EMT).
- If a HighBetaCat cell has [β] < c_T, it becomes LowBetaCat (MET).
- Bionetsolver templates are keyed by cell-type name (p.14).
- Physical effect as described (p.5): E-cad/β-cat complex formation stops and dissociation accelerates. This gives "a significantly reduced adhesion strength". **How adhesion is reduced is not specified.** The J values for LowBetaCat and HighBetaCat are UNSPECIFIED. Whether J is a function of [E/β] is UNSPECIFIED. Whether chemotaxis depends on type is UNSPECIFIED.

**Triggers and schedule**
- ODE integration starts at **20 MCS**, to avoid the initial shape transient (p.3).
- EMT trigger: **k⁺ (kz) reduced 1.5 → 1.0**
  - at **70 MCS** (layer, p.5);
  - "after 200 MCS" (tumour from layer, p.7);
  - at **400 MCS** (MTS, p.8–9).
- MTS: c_T raised to **70** during growth "to maintain tumour compactness" (p.8). Whether c_T returns to 50 afterwards is UNSPECIFIED.
- Invasiveness sweeps use k₂:
  - layer: 0.95, 1.0, 1.05 (p.8);
  - MTS: 0.95, 1.0, 1.02 (p.9, Fig 9).
- Bionetsolver step: "we set timestepBionetwork to 0.03 and if Bionetsolver gets called every MCS then 1 MCS corresponds to 0.03 hours". This is given as "a simple case for example" (p.11). The code excerpt calls `initializeBionetworks(0.05)` (p.14). **The Δt actually used for the figures is ambiguous.**

**Growth and division (p.5–6)**
- In growth phases, target volume and target surface are incremented each MCS by 0.02 × *current* volume and surface. Cell number doubles about every 40 MCS.
- Division when volume > 2 × initial volume, using the CC3D built-in mitosis. "we do not apply any intracellular pathway" (p.11).
- On mitosis the bionetwork is copied parent → child (`copyBionetworkFromParent`, p.14).
- Division cap: stop at > 500 cells (p.7). "maximum number of cells … is 500 for all simulations" (p.8).

**Removal:** cells that migrate 70 pixels from the tumour mass are removed and counted (p.8, p.9).

**No ECM, MMP, or nutrient fields; no death.** No apoptosis or necrosis is described.

---

## 3. Parameter tables

### 3A. 11a (all "stated" unless marked)

| Symbol | Value | Units | Meaning | Source |
|---|---|---|---|---|
| lattice | 300 × 300 × 1 | px | domain = 1.44 mm² | 11a p.13 |
| Δx | 4 | μm/px | derived from 1.44 mm² / 300² | derived |
| Δt | 1 MCS = 1 min | — | time scale | p.13 |
| BCs | periodic | — | lattice and PDE | p.10, p.13 |
| initial cell volume | ≈32 | voxels | tumour cell | Table 2 footnote p.14 |
| mean cell area | ≈500 | μm² | tumour cell | p.13 |
| D_n | 10³ | μm²/s | nutrient diffusion | Table 2 [12] |
| S_n (s_n) | 8.83×10⁻¹⁶ | mol/cell/s | vessel nutrient source | Table 2 [8] |
| β_P (= β_M) | 5.17×10⁻¹⁷ | mol/cell/s | uptake, proliferating and migrating | Table 2 [101] |
| β_Q | 2.41×10⁻¹⁷ | mol/cell/s | uptake, quiescent | Table 2 [101] |
| β_N | 0 | mol/cell/s | necrotic | Table 2 |
| β_normal | β_tumour / 3 | — | normal-cell uptake | p.13 (derived from "3 times") |
| S_0 | 4.6 | pg/voxel | initial nutrient | p.10 |
| T_RTK | 4.48×10⁻³ | pg/pixel | RTK (survival) threshold | Table 2 [102] |
| T_ITG | 0.3 | — (contact fraction) | integrin threshold | Table 2 (estimated) |
| T_cadherin | 0.3 | — | cadherin threshold | Table 2 (estimated) |
| T_Wnt | 0.15 | — | Wnt threshold | Table 2 (estimated) |
| D_V | 10 | μm²/s | VEGF diffusion | Table 2 [103] |
| k | 0.9375 | h⁻¹ | VEGF decay | Table 2 [103] |
| e | 0.001 | pg/cell/s | VEGF uptake cap (ECs) | Table 2 [104] |
| s_V | 0.035 | pg/pixel | VEGF source (hypoxic cells) | Table 2 [105] |
| T_V | 0.00095 | pg/pixel | EC activation threshold | Table 2 [26] |
| γ_eM, γ_eP, γ_eQ, γ_eEC | 8, 8, 8, 8 | — | area elasticity per phenotype | Table 2 |
| α | 300 | — | continuity penalty | Table 2 [26] |
| T_m | 10 | — | temperature | Table 2 (estimated) |
| J (rows/cols EC, M, P, Q, N, m) | EC: 5 30 30 30 30 12; M: 30 8 8 8 10 12; P: 30 8 8 8 10 12; Q: 30 8 8 8 10 12; N: 30 10 10 10 8 10; m: 12 12 12 12 10 66 | — | adhesion | Table 2 p.14 |
| χ_σ (tumour, EC) | UNSPECIFIED | — | chemotaxis strengths | — |
| normal-cell J, γ_e, uptake | UNSPECIFIED (only "3×" relation) | — | host tissue | — |
| quiescence (hypoxia) threshold | UNSPECIFIED | — | Q switch | — |
| necrosis rule | UNSPECIFIED | — | Q → N | — |
| neighbour order | UNSPECIFIED | — | CPM | — |
| PDE solver, sub-steps | UNSPECIFIED | — | coupling | — |
| therapy start | days 3, 5, 6 | day | blocking onset | p.28 |

Sensitivity ranges (stated, p.23–27):
- J_{M–M} ≤ 5 gives distorted cells; ≥ 15 gives separated cells.
- J_{EC–EC} ≤ 4 gives accumulation and rupture; ≥ 15 makes the tip EC detach.
- 12 ≤ J_{m–cell} ≤ 14 is the proper range.
- 8 ≤ γ_e ≤ 13 is insensitive; γ_e = 30 makes the tip detach.
- 0.2 ≤ T_ITG ≤ 0.3 works; < 0.2 gives small tumours; ≥ 0.35 disrupts growth.
- T_cadherin ≤ 0.2 inhibits proliferation.
- T_V ≲ 0.0015 is required for angiogenesis.
- T_RTK ≈ 0.005 is the survival boundary.

### 3B. 11b

| Symbol | Value | Units | Meaning | Source |
|---|---|---|---|---|
| lattice (layer) | 264 × 224 × 60 | px | EMT detachment waves | 11b p.3 |
| lattice (tumour from layer) | 120³ | px | growth and invasion | p.6 |
| lattice (MTS) | 240³ | px | spheroid | p.8 |
| Δx | 2 | μm/px | — | p.3, p.11 |
| initial cell | 7 × 7 × 7 cube, 1-px gaps | px | IC | p.3, p.7, p.8 |
| V_t initial | 1.2 × cell volume ≈ 410 | px | ≈3280 μm³ | p.3 |
| growth rate | 0.02 × current V (and S) per MCS | — | target increments | p.5 |
| division | V > 2 × initial V | — | CC3D mitosis | p.6 |
| cell cap | 500 | cells | stop division | p.7, p.8 |
| removal distance | 70 | px | counted as invaded | p.8, p.9 |
| neighbour range | up to 4th nearest | — | copy source | p.11 |
| T_m, J, λ_vol, λ_surf, λ_chemo | UNSPECIFIED | — | CPM | — |
| chemoattractant field | prescribed linear (x) / radial; magnitudes UNSPECIFIED | — | chemotaxis target | p.7, p.9 |
| ν | 100 (0 when above c_T) | dimensionless | E-cad–β-cat binding | Table 1 p.4, p.5 |
| k⁺ (kz) | 1.5 → 1.0 at trigger | dimensionless | β-cat–proteasome binding | Table 1 (estimated), p.5 |
| k⁻ | 19 | dimensionless | β-cat–proteasome dissociation | Table 1 |
| k₂ | 1 (sweeps 0.95, 1.0, 1.02, 1.05) | dimensionless | proteasomal degradation | Table 1*, p.8–9 |
| k_m | 14 | dimensionless | β-cat production | Table 1* |
| α | 2 (0 when below c_T) | dimensionless | complex dissociation | Table 1, p.5 |
| c_T | 50 (70 during MTS growth) | dimensionless | EMT/MET threshold | Table 1, p.8 |
| ρ_c (rc) | 200 | dimensionless | E-cad translocation to surface | Table 1 |
| ρ_d (rd) | 200 | dimensionless | E-cad translocation to cytoplasm | Table 1 |
| P_T | 21 | dimensionless | total proteasome | Table 1* |
| E_T | 100 | dimensionless | total E-cadherin | Table 1 |
| T, E (nondim.) | 1 min, 1 nM | — | reference scales | p.16 |
| ODE start | 20 | MCS | integration onset | p.3 |
| ODE Δt | 0.03 (text example) / 0.05 (code excerpt) | — | per-MCS step | p.11, p.14 |
| ODE initial conditions | UNSPECIFIED (SBML defaults) | — | — | p.14 |

\* marks values that "appear in the paper's correction" of [14] (Table 1 footnote).

---

## 4. Verification of prior claims

### 4A. Andasari 2012 (11b)

| # | Prior claim | Verdict | Evidence |
|---|---|---|---|
| 1 | 3D lattices 100×100×10 (epithelial layer) and 200³ (tumour/spheroid) | **CORRECTED** | 264×224×60 (layer), 120³ (tumour from layer), 240³ (MTS). Three runs, not two (p.3, p.6, p.8). |
| 2 | 1 px = 10 μm | **CORRECTED** | 1 px = 2 μm (p.3, p.11). |
| 3 | Adhesion + volume + surface + chemotaxis | **CONFIRMED** | Eq 2, p.13. |
| 4 | Chemotaxis to a prescribed linear/radial gradient | **CONFIRMED** | Linear along x (p.7); radial outward (p.9). |
| 5 | No PDE | **CONFIRMED** | No diffusion equation is specified or solved for this model. The gradient is "applied" (p.7, p.9). |
| 6 | Per-cell SBML E-cadherin/β-catenin ODE (Ramis-Conde 2008) via Bionetsolver | **CONFIRMED** | p.4–5, p.14–16. Eqs 7–12. Ref [14]. |
| 7 | Integrated once per MCS with Δt = 0.03 | **CORRECTED** (ambiguous) | 0.03 appears only as "a simple case for example" (p.11). The printed code uses 0.05 (p.14). The per-MCS threshold check is confirmed (p.5). The Δt used in the figures is not stated. |
| 8 | LowBetaCat ⇄ HighBetaCat switch on free β-catenin threshold (EMT and MET); type change alters J and chemotaxis | **CORRECTED** (partly NOT IN PAPER) | The switch at c_T = 50 in both directions, with ν/α swap, is confirmed (p.5). "Reduced adhesion strength" is stated (p.5), but J values, a J mapping, and any type-dependence of chemotaxis are **not in the paper**. |
| 9 | ODE integration begins at MCS 10 | **CORRECTED** | 20 MCS (p.3). |
| 10 | β-catenin rise triggered by changing k1 or degradation at a set MCS | **CORRECTED** | The trigger is k⁺ (kz) 1.5 → 1.0 at 70 MCS (layer), after 200 MCS (tumour from layer), and at 400 MCS (MTS) (p.5, p.7, p.8–9). k₂ is a fixed per-run sweep parameter, not a timed trigger. "k1" appears only in a generic SimpleModel code example (p.14). |
| 11 | Threshold lowered at MCS 400 in spheroid run | **CORRECTED** | c_T was **raised** to 70 during MTS growth. At 400 MCS it is **kz** that is decreased (p.8). |
| 12 | Target volume and surface grow each MCS | **CONFIRMED** | +0.02 × current volume and surface per MCS during growth phases (p.5). |
| 13 | Divide at 2× (or 2.5×?) initial volume | **CONFIRMED** (2×) | "exceeded 2 times its initial volume" (p.6). |
| 14 | Cap 200 cells | **CORRECTED** | 500 cells (p.7, p.8). |
| 15 | No MMP/ECM PDEs in this paper | **CONFIRMED** | None described anywhere. |
| 16 | ODE may take cell–cell contact input | **CONFIRMED** (stronger) | c_i(t) and d_i(t) are driven by the time-derivative of normalized per-neighbour contact area (Eqs 10–11, p.15). Concentrations "fluctuate in response to fluctuations in contact area" (p.5). |

11b counts: CONFIRMED 8 (claims 3, 4, 5, 6, 12, 13, 15, 16). CORRECTED 8 (claims 1, 2, 7, 8, 9, 10, 11, 14). NOT IN PAPER 0 as a whole claim (the J/chemotaxis part of claim 8 is not in the paper).

### 4B. Jafari Nivlouei 2021 (11a)

| # | Prior claim | Verdict | Evidence |
|---|---|---|---|
| 1 | 300×300 lattice, periodic | **CONFIRMED** | 300×300×1, periodic (p.13; PDE periodic p.10). |
| 2 | 1 MCS = 1 min | **CONFIRMED** | p.13. |
| 3 | Adhesion, area, connectivity penalty, chemotaxis | **CONFIRMED** | Eqs 1–6, p.9–10. α = 300. |
| 4 | Chemotaxis: tumour up nutrient, EC up VEGF | **CONFIRMED** (qualified) | Only tumour cells "with migration phenotype" chemotax up nutrient; activated ECs chemotax up VEGF (p.9–10). |
| 5 | Nutrient PDE uptake min(βn, n), sources at vessel sites | **CORRECTED** | Uptake is **min(n, β)** on cancer-cell sites (Eq 7, p.10). Normal cells uptake at a third of the tumour rate (p.13). Sources are s_n on **endothelial-cell** sites, plus a Dirichlet clamp n|ECs = S_n (p.10). |
| 6 | VEGF PDE: decay, secretion by hypoxic cells, uptake by ECs | **CONFIRMED** | Eq 8, p.10–11. E = min(V, e). V(0) = 0. |
| 7 | Boolean network maps thresholded inputs (RTK from nutrient, integrin, Wnt, cadherin from contacts) to growth/proliferation/migration/quiescence/apoptosis each MCS | **CORRECTED** (mostly confirmed) | Confirmed: inputs are thresholded; RTK comes from nutrient for tumour cells (p.13) and from VEGF for ECs (Table 1, p.13); ITG, cadherin and Wnt come from contact normalized by size (p.12). Outputs cover **growth/proliferation/migration/apoptosis only** (Fig 3). **Quiescence is a separate hypoxia rule**, not a Boolean output (p.14, p.18). The Wnt contact source is unspecified. In the CPM a precomputed Fig 3 lookup table is used. Cadence is "each time step" (p.12, p.29). |
| 8 | Divide at 2× target volume | **CORRECTED** | Cells "double their size before undergoing cell division". The *target* area of proliferating cells is 2× the quiescent area (p.9). So division is at ≈2× the quiescent area, not at 2× the target. The exact trigger is unspecified. |
| 9 | Apoptosis + necrosis | **CONFIRMED** | Apoptosis via the Boolean table or RTK off (p.13–14). Necrosis of hypoxic quiescent cells (p.18, Fig 6F). Rules for both are unspecified. |
| 10 | Therapy clamps RTK or integrin to 0 from day 3/5/6 | **CONFIRMED** (qualified) | Blocking starts on days 3, 5, 6. The blocking cases are 101, 011, 001, 100, 010, 000, i.e. any case with ITG or RTK off (p.28). The receptor clamped in each reported run is not identified. |
| 11 | No code released | **CONFIRMED** | Only an S1 Data XLSX of figure data (p.30). No code link. CompuCell3D is named (p.13). |
| 12 | Sprout speed 13–21 μm/h | **CORRECTED** | Table 3 (p.15). Simulation: initial 25 ± 3.7, in progress 11 ± 1.2, 10-h average 13 ± 1.6 μm/h. Experiment: 21 ± 4 initial, 10 ± 4 in progress [114]; 14 μm/h 10-h average [116]. 21 is the *experimental* initial speed, not a simulated one. |
| 13 | Hypoxic core ≈ day 4 | **CONFIRMED** (qualified) | "~day 4" with normal host cells (p.21). Without host cells the core forms at tumour diameter ≈200 μm (Fig 6D, p.18); growth is exponential for the first 4 days (p.19). |
| 14 | ≈80% shrinkage under therapy | **CONFIRMED** (refined) | First-day decrease ≈43%, ≈77%, ≈80% for starts on days 3, 5, 6. Median decrease 80% (mean area 5536 μm²) at day 7. **82% (range 78–83%) after 10 days** vs the ≈25000 μm² baseline. Minimum ≈84% at day 4 (p.29; Figs 18–19). Abstract: 82% (p.1). |
| 15 | ECM represented as a lattice component, not a dynamic field | **CONFIRMED** | τ = 0 for ECM sites; a matrix row in J (p.7, Table 2). No ECM equation. |

11a counts: CONFIRMED 11 (claims 1, 2, 3, 4, 6, 9, 10, 11, 13, 14, 15). CORRECTED 4 (claims 5, 7, 8, 12). NOT IN PAPER 0.

---

## 5. Validation targets

Policy: ensemble statistics, no bitwise parity.

### 5A. 11a

| ID | Target | Source | Type | Tolerance |
|---|---|---|---|---|
| V11a-1 | Boolean network: with APC = NF1 = OFF, every input combination gives the Fig 3 table; all 2^29 internal initial states converge to the same attractors | p.12, p.15, Fig 3, Table 1 | exact (logic) | exact match. This is a pure unit test of the G9 Boolean component; synchronous update. Note: β-Catenin rule precedence must be fixed first (§7) |
| V11a-2 | Sprout speed vs time, with signalling (n = 5). Key points: 37.9 (t = 0.2), 22.3 (1), 15.2 (2), 12.6 (4), 11.5 (6), 10.2 (8), 10.2 (10), 9.9 (12), 9.3 μm/h (14). Summaries: initial (mean of t = 0.2, 1, 2) 25.1; 10-h value 12.6 (the sheet takes the MEDIAN of t = 0.2–10); Table 3 gives initial 25 ± 3.7, in progress 11 ± 1.2, 10-h 13 ± 1.6. Time unit: see §9.3 item 1 | Table 3 p.15; Fig 4 p.16; S1 Data (supplementary/11a_JafariNivlouei2021_S1Data.xlsx, sheet "Figure 4", cells D3:E15) | quantitative | Ensemble mean (≥ 5 runs) within ±2 SD of the Table 3 value: initial 25.1 ± 7.4, in progress 11 ± 2.4, 10-h 12.6 ± 3.2 μm/h. Per-point: ±25% for t ≥ 4, ±40% for t ≤ 2 (the steep transient). Speed must decrease monotonically, allowing up to 1 μm/h of noise |
| V11a-2b | Ablation, no signalling: 32.2 (t = 0.2), 22.1 (2), 12.2 (4), 10.0 (6), 7.3 (8), 6.4 (10), 6.5 (12), 6.3 μm/h (14). Late speed is ≈35% below the with-signalling run | S1 Data (supplementary/11a_JafariNivlouei2021_S1Data.xlsx, sheet "Figure 4", cells G3:H12) | qualitative ordering | For t ≥ 8, the no-signalling mean is below the with-signalling mean in the ensemble (one-sided test, p < 0.05). Late plateau 6.4 ± 2 μm/h |
| V11a-3 | High T_V: 10-h sprout speed ≈3.65 μm/h | p.26 | quantitative | ±30% |
| V11a-4 | Avascular growth without host: diameter ≈51, 100, 142 μm on days 1, 2, 3; hypoxic core at ≈200 μm; necrosis ≈day 5 | Fig 6 caption p.18 | quantitative (sparse) | ±20% on diameters; core onset day ±1 |
| V11a-5 | Equivalent radius r = √(A/3.14) vs time (§9.3 item 2). Simulated key points: 25.8 μm (t = 0), 43.2 (1.5), 73.1 (2.5), 113.6 (4.5), 128.4 (6.0), 133.1 (7.6), 151.6 (9.5), 185.8 (10.8), 244.1 (12.9), 266.7 (13.6), 301.4 μm (14.3 d). The [119] Michaelis–Menten reference runs from 24.3 μm (t = 0) to 373.9 μm (t = 15.9) | Fig 5 p.17; S1 Data (supplementary/11a_JafariNivlouei2021_S1Data.xlsx, sheet "Figure 5", cells A3:F14) | quantitative | Ensemble-mean r within ±20% of the simulated key points for t ≤ 9.5 d, and within ±30% after (post-anastomosis timing spread). No SD is in the sheet, so the caption's "5-run SD bands" cannot be used |
| V11a-6 | Tumour area, one run, with and without angiogenesis. Area in μm² (no angio / with angio): day 0 2096 / 2096; day 1 3968 / 3968; day 2 7872 / 7888; day 3 15584 / 15504; day 4 30288 / 29952; day 5 41984 / 45424; day 8 50960 / 61856; day 12 73344 / 89408; day 13 83008 / 146416; day 15 99152 / 268048. Derived: days 0–4 exponential with doubling time 1.03 d (log-linear fit to 577 samples). With angiogenesis, days 12 → 13 add +64% in one day, vs +13% without. Final ratio with/without = 2.70 | p.19; Fig 9 p.20; S1 Data (supplementary/11a_JafariNivlouei2021_S1Data.xlsx, sheet "Figure 9", cells A4:B2165 and E4:F2165; key days at rows 5 + 144·day) | quantitative + timing | Ensemble mean: doubling time for days 0–4 1.03 d ± 25%; area ±25% for days 0–4 and ±35% for days 5–12. Anastomosis jump (first day with more than 40% daily area growth after day 8) on day 12 ± 2. Day-15 ratio with/without ≥ 1.5 |
| V11a-6b | Viable (non-necrotic) cell count, no angio / with angio: days 0–3 4, 6, 12, 24 (both); day 4 39 / 41.5; day 8 58.5 / 72.5; day 12 94 / 145; day 13 108 / 226.5; day 16 145.5 / 518.5 | Fig 10 p.21; S1 Data (supplementary/11a_JafariNivlouei2021_S1Data.xlsx, sheet "Figure 10", cells A4:B21 and E4:F21) | quantitative + timing | ±25% on counts for days 0–12, ±40% after. With-angio count exceeds no-angio from day 4 onward. Jump in growth rate at day 12 ± 2 |
| V11a-7 | Avascular, no vessels (inferred setup; §9.3 item 5). Without host: count doubles daily from day 1 (6) to day 8 (768), peaks at 1382.75 on day 9, then falls to 338.25 by day 11. With host: 44 (day 4), peak 54.25 (day 5), then a plateau of 45–48.5 through day 12 (mean of 4 runs) | p.21–22; Fig 11 p.21; S1 Data (supplementary/11a_JafariNivlouei2021_S1Data.xlsx, sheet "Figure 11", cells A4:B17 and E4:F17) | quantitative + timing | With host: plateau mean (days 6–12) 46 ± 25%, onset day 4–5 ± 1. Without host: peak day 9 ± 1, peak count ±30%, collapse of ≥ 50% within 2 days after the peak |
| V11a-8 | Vascular growth, no host / with host: day 3 32 / 19; day 6 62 / 64; day 8 76 / 210; day 10 99 / 396; day 11 105 / 622 (text: "~620 cells", ≈300 μm diameter). No-host continues to 614 on day 16. With-host days 12–16 are **excluded** (§9.3 item 4) | p.23; Fig 13 p.23; S1 Data (supplementary/11a_JafariNivlouei2021_S1Data.xlsx, sheet "Figure 13", cells A4:B21 and E4:F16) | quantitative | Count ±25% at days 8–11. With-host count exceeds no-host from day 6 onward (it is lower on days 2–5). Day-11 with-host count 622 ± 25% |
| V11a-9 | IVD d (%) vs "area (%)". Simulated d at the 12 experimental x points: 20.8 (x = 4.47), 61.3 (7.72), 74 (8.01), 75 (8.83), 75 (9.17), 90 (11.89), 94 (12.42), 93 (14.20), 91 (15.03), 85 (16.07), 83 (16.36), 86 (20.83). Experimental [128] d: 66.7–95.5, mean 84.0. The paper's own mean absolute error vs experiment is 10.2 pp (derived) | Fig 15 p.25; S1 Data (supplementary/11a_JafariNivlouei2021_S1Data.xlsx, sheet "Figure 15", cells A4:B16 and E4:F16) | quantitative (conditional on the x definition, §9.3 item 6) | Mean absolute error vs the paper's simulated d ≤ 15 pp over the 12 points. d ≥ 70% for x ≥ 8%. Rising trend from x = 4.5% to x = 8% |
| V11a-9b | IVD under signalling intervention: d = 5.2–13.6%, mean 11.0 (SD 2.2, n = 12 points), vs 66.7–95.5% experimental and untreated | Fig 17 p.28; S1 Data (supplementary/11a_JafariNivlouei2021_S1Data.xlsx, sheet "Figure 17", cells A4:B16 and E4:F16) | quantitative | Mean d 11 ± 5 pp. Every point ≤ 20%. Treated d below untreated d at every x |
| V11a-10 | Therapy area curves, one run per start day (3 / 5 / 6). Area at start: 12448 / 23536 / 36912 μm². Pre-therapy peak 13488 (t = 3.20) / 24816 (t = 5.10) / 36912 (t = 6.00). Day 7: 3696 / 5808 / 6320. Day 10: 3568 / 5536 / 5936. Day 12: 3456 / 5248 / 5616. Paper text (not reproducible from the sheet, §9.3 item 7): first-day drop ≈43 / 77 / 80%; "mean tumor area at day 7 is 5536 μm²" with a median decrease of 80% | p.28–29; Fig 18 p.28; S1 Data (supplementary/11a_JafariNivlouei2021_S1Data.xlsx, sheet "Figure 18", cells A4:J1734; day d at row 6 + 144·d) | quantitative | Plateau area (days 10–12 mean) within ±30% of 3.5k / 5.4k / 5.8k μm². Ordering: an earlier start gives a smaller plateau (in ≥ 80% of paired runs). Area falls to ≤ 30% of the pre-therapy peak within 2 days of start for the day-5 and day-6 starts, and to ≤ 35% within 3 days for the day-3 start |
| V11a-10b | Area reduction vs baseline, days after start: 73.8 (1), 76.8 (2), 79.9 (3), **83.6 (4, minimum)**, 80.6 (5), 78.2 (6), 81.6 (7), 81.8 (8), 82.5 (9), 82.9% (10). Text: 82% on average (78–83%) after 10 days; −73% after one day; minimum ≈84% at day 4 | p.29; Fig 19 p.29; S1 Data (supplementary/11a_JafariNivlouei2021_S1Data.xlsx, sheet "Figure 19", cells A4:B15) | quantitative | Per-day ensemble mean reduction within ±10 pp. Day-10 reduction 83 ± 10%. The minimum falls in days 3–6. Baseline definition: §9.3 item 8 |
| V11a-11 | Sensitivity phase boundaries (T_ITG, T_cadherin, T_V, T_RTK, J, γ_e ranges in §3A) | p.23–27 | qualitative | reproduce direction and approximate location (±30%) of each transition |

Tolerance policy for all S1-Data-backed rows: compare an **ensemble** of our runs (default n = 8, different seeds) with the paper's values. Most S1 series are single runs or small-n means with no SD in the sheet (§9.2), so tolerances are wide and fixed rather than SD-based. No trajectory or bitwise matching is attempted. The tolerances are proposals and may be relaxed once the first ensemble shows its intrinsic spread.

### 5B. 11b

| ID | Target | Source | Type | Tolerance |
|---|---|---|---|---|
| V11b-1 | Layer: kz drop at 70 MCS; first detachment at ≈130 MCS; spread by 200; all cells detached by ≈500 MCS; detachment is irregular (not a regular radial wave) | p.5, Fig 2 | qualitative + timing | ±30% on onset and completion MCS |
| V11b-2 | Single-cell traces: ≈3 EMT/MET cycles by 5000 MCS; β-cat fluctuates while in contact and is smooth while detached | p.5, Fig 3 | semi-quantitative | cycle count 2–4 |
| V11b-3 | Cells growing unconstrained double about every 40 MCS | p.5 | quantitative | ±20% |
| V11b-4 | Tumour from layer: outer-layer cells exceed c_T from ≈500 MCS; cross-section shows low β-cat inside and high at the surface | p.7–8, Figs 5–6 | qualitative | radial β-cat gradient sign |
| V11b-5 | Invasion assay: removed-cell count vs time ordered k₂ = 0.95 > 1.0 > 1.05 (exponential for 0.95) | p.8, Fig 7 | qualitative ordering | ordering holds in ≥ 90% of paired runs |
| V11b-6 | MTS radius ≈40 px; cell 1 plateaus at 40 px then leaves linearly at a k₂-dependent time | p.9, Fig 9 | quantitative | radius ±15% |
| V11b-7 | MTS removal ordering 0.95 > 1.0 > 1.02 | p.9, Fig 10 | qualitative | ordering |
| V11b-8 | MTS morphology at 900 MCS: diffuse radial invasion (k₂ = 0.95) vs sparse invasion (k₂ = 1.0) | Fig 11 | qualitative | visual |

---

## 6. Required general features

| ID | 11a (Jafari Nivlouei) | 11b (Andasari) |
|---|---|---|
| G1 | `@transition` phenotype/type changes (P/M/Q/N, EC inactive → active), driven by G9 outputs and thresholds; `@retire` for apoptosis; `@create` by division; necrosis as a type transition | `@transition` LowBetaCat ⇄ HighBetaCat on [β] vs c_T; `@create` by division; `@retire` beyond 70 px |
| G2 | Not required | Not required (surface is the standard term) |
| G3 | **Required:** per-cell contact fractions with ECM (τ = 0) and with other cells, normalized by cell size, as Boolean inputs | **Required:** per-neighbour contact area â_j (normalized by own surface) and its per-step change (lagged value); new-contact / new-detachment classification (Eqs 10–11). Needs **lagged per-neighbour** cell variables |
| G4 | **Required:** continuity energy α(1 − δ_{a,a′}) needs a′ = size of the connected part (Eq 3). A generalized connectivity constraint or penalty covers it | Not stated |
| G5 | **Required:** two 2D reaction–diffusion PDEs with periodic BCs, a site-type-masked min(·) uptake, source on EC sites, and a Dirichlet clamp on EC sites; VEGF decay. SteadyState not stated. The coarse grid is not needed | Prescribed static gradient fields (linear, radial). An initial-condition expression is enough; no solver |
| G6 | Per-cell uptake capped per phenotype (β in mol/cell/s, so it is per cell, not per site) and secretion by hypoxic cells. Conservative per-cell versions are preferred given the units | Not required |
| G7 | Not required. ECM is removed implicitly when cells copy into τ = 0 sites | Not required |
| G8 | Default Metropolis. Neighbour order is a parameter | Neighbour range up to 4th-nearest must be configurable |
| G9 | **Boolean component.** See the interface below | **ODE component (SBML).** See the interface below |
| G10 | Daughter keeps parent ID (p.9) | Parent → child state copy |
| G11 | Not required | Not required |
| G12 | Tumour area and diameter; viable cell count; counts by phenotype; sprout-tip displacement and speed; IVD = vessel area / tumour area; hypoxic core onset | Per-cell concentration traces; count of cells beyond a distance; single-cell radial position; β-cat cross-section |
| G13 | 4 tumour cells at centre; pre-existing vessel network; optional host-cell tissue fill | Cube tiling with gaps (sheet, layer on a face); single seed cell at centre |
| **G14** (as in 08) | Not required | Not required |
| **G16 (new)** | **Timed parameter and intervention schedule.** Clamp a Boolean input to 0 from day d (11a therapy) | Change kz at MCS t, c_T during a phase, ODE start at MCS 20, division cap at N = 500 (11b). Justification: both papers run protocols; this should be a general event schedule, not model hooks |
| **G17 (new)** | **Population-level gates.** Disable division once the total count exceeds N (11b cap of 500) | Could be an expression guard in G1 |

### G9 — per-cell component interface requirements

**11a (Boolean, lookup-table form)**
- **Inputs, each step:**
  - RTK = [local nutrient ≥ T_RTK] for tumour cells, or [local VEGF ≥ T_V] for ECs. "Local" (cell mean, cell sum, or per site) is UNSPECIFIED.
  - ITG = [ECM contact / size ≥ T_ITG].
  - Cadherin = [cell–cell contact / size ≥ T_cadherin].
  - Wnt = [(unspecified contact) ≥ T_Wnt].
  - APC and NF1 are constant OFF.
  - Therapy: an external override clamps an input to 0.
- **Internal model:** either the 29+ node synchronous Boolean network (Table 1), run to a fixed point, or the equivalent 16-row table (Fig 3). The interface should allow both. The paper uses the table at runtime.
- **Outputs:** 4 bits (growth, proliferation, migration, apoptosis). These map to cell type or phenotype, which selects the J row, γ_e, β, A^T = 2·A_Q, chemotaxis on/off, and apoptosis removal.
  - The hypoxia → quiescent rule and the quiescent → necrotic rule sit **outside** the network.
  - VEGF secretion depends on the hypoxic state.
- **Cadence:** every step, before the MCS sweep (p.12). The phenotype is held constant during the sweep.
- **Division:** daughters inherit the phenotype (p.9, p.22).
- **Death:** discard.

**11b (ODE, SBML)**
- **Inputs, each MCS:** c_i(t) and d_i(t) from per-neighbour contact-area changes (Eqs 10–11). Parameters that can be set at runtime per cell (ν, α, kz, k₂, c_T) by the threshold logic and the schedule (G16).
- **State:** [Ec], [E/β], [β], [C]. Initial values default to the SBML values (p.14); the actual values are unspecified.
- **Outputs:** [β], which is compared with c_T to switch the type (G1). [E/β] "increases the adhesiveness" (p.5), but no explicit coupling to J is given.
- **Cadence:** one integrator advance per MCS, with fixed Δt (0.03 or 0.05, ambiguous). The integrator is off until MCS 20.
- **Division:** copy the full parent state to the child (`copyBionetworkFromParent`, p.14). Whether the parent's state is also kept as is (not halved) is implied by "copied".
- **Death or removal:** discard.
- **Template:** one component model per cell *type*, with state that persists across type changes (the templates share one SBML model, p.14). The component must survive a type change with its state intact.

---

## 7. Ambiguities and open questions

**11a.** Status after reading S1 Data (§9). S1 Data contains only plotted outputs, with no parameter sheet, so no model parameter is resolved by it.
1. **STILL OPEN.** Nutrient units: n in pg/voxel, β and S_n in mol/cell/s. How is β converted to a per-voxel sink (divide by ≈32 voxels?)? Table 2 footnote hints at "an equivalent value used in our calculations". Partial lead from the PDF, not S1 Data: Table 4 (p.17) restates β_P = 0.0252 and β_Q = 0.0126 mol/m³/s. Dividing 5.17×10⁻¹⁷ mol/cell/s by 0.0252 mol/m³/s gives a cell volume of ≈2.05×10³ μm³. This is our inference; the paper does not state it, and the per-voxel conversion is still missing.
2. **STILL OPEN.** The nutrient source is both a term S_n in Eq 7 and a Dirichlet clamp n|ECs = S_n. Which was implemented? Do new (sprouted) ECs also become sources?
3. **STILL OPEN.** PDE solver, number of diffusion steps per MCS, and the Δt used for the physical D values. S1 Data holds no field data. Its only time information is the output cadence: 10 MCS (= 10 min) per sample (§9.1).
4. **STILL OPEN.** Which contact measure drives Wnt? How is "contact normalized by the cell's size" computed (boundary length / perimeter, or / area)?
5. **STILL OPEN.** Hypoxia (quiescence) threshold, necrosis rule and delay, and apoptosis implementation. S1 Data gives only outcome **timing** to calibrate against: avascular with host plateaus from day 4–5; without host it peaks on day 9 and collapses by day 11 (V11a-7). Any threshold fitted to these is a calibration choice, not a paper value.
6. **STILL OPEN** (rule). **Calibration target added** (data): the early doubling time is ≈1 d. Evidence: cell counts double daily (sheet "Figure 11" cells B6:B13; sheet "Figure 13" cells B5:B8), and the area doubling time over days 0–4 is 1.03 d (sheet "Figure 9"). This agrees with "cell cycle time … ~24h" (p.13). The division trigger and cleavage rule are still unspecified.
7. **STILL OPEN.** χ values and sign conventions for Eqs 4–5. Neighbour order. Sprout speeds (V11a-2) constrain χ_EC only jointly with J, T_V and the VEGF field. A fitted χ would be our calibration.
8. **STILL OPEN.** Normal host cells: J entries, γ_e, uptake, death rule under hypoxia (p.22). S1 Data has only with-host vs without-host cell counts (sheets "Figure 11", "Figure 13").
9. **STILL OPEN** (not a data question). β-Catenin rule precedence: "Wnt Or Akt And Not cadherin AND Not APC". Is it (Wnt ∨ Akt) ∧ ¬cad ∧ ¬APC, or Wnt ∨ (Akt ∧ ¬cad ∧ ¬APC)? The Fig 3 table should disambiguate. Also "RTK And Scr" should presumably read Src.
10. **STILL OPEN.** The therapy runs: which receptor(s) were clamped, and whether the clamp applies to all cells including ECs. Sheet "Figure 18" gives only area curves per start day.
11. **STILL OPEN.** Pre-existing vessel geometry (only shown in figures).
12. **Code: STILL OPEN** (not released; ask for the CC3D project). **S1 Data: RESOLVED.** Now on disk (supplementary/11a_JafariNivlouei2021_S1Data.xlsx, sheets "Figure 4" to "Figure 19").
13. **RESOLVED (supporting evidence): Δx = 4 μm.** All areas in sheets "Figure 9" (cells B5:B2165, F5:F2165) and "Figure 18" (cells B6:J1734) are whole multiples of 16 μm².
14. **NEW, OPEN.** The S1 Data inconsistencies listed in §9.3: the Fig 4 time unit, the Fig 5 replicate count, the Fig 13 extrapolated tail, the Fig 10 vs Fig 13 series, the Fig 15/17 x-axis definition, and the Fig 18/19 baseline definition. Ask the authors together with item 12.

**11b**
1. All CPM energies (J by type, λ_vol, λ_surf, λ_chemo, T_m) and the chemoattractant field values.
2. Bionetsolver Δt (0.03 vs 0.05) and whether 1 MCS ↔ 0.03 h was used.
3. Is adhesion (J) changed by LowBetaCat/HighBetaCat type, and by how much? Are both types chemotactic?
4. Is c_T reset to 50 after the MTS kz drop?
5. How contact area â_j and its time derivative are computed (per MCS difference?).
6. ODE initial conditions.
7. The text refers to "Eqs. (15)–(18)" and "Eqs. (11) and (12)" for A1 and A2 (p.3, p.4). The printed equations are Eqs 7–9 and 12. These are editorial numbering errors.
8. Layer sheet dimensions: 30 × 8 px = 480 μm matches the stated 0.48 mm, but 25 × 8 px = 400 μm, while 0.408 mm is stated (p.3). This is a minor inconsistency.

---

## 8. Recommendation for item 11

**Choose 11a (Jafari Nivlouei 2021).** Checked against the spec *"2D multiscale: intracellular (ODEs / Boolean net) ↔ cell ↔ extracellular (ECM / PDE)"*:

| Spec element | 11a | 11b |
|---|---|---|
| 2D | **Yes**: 300 × 300 × 1 (p.13) | **No**: all three runs are 3D (264×224×60, 120³, 240³; p.3, p.6, p.8) |
| Intracellular (ODE / Boolean) | **Boolean network**: ~30 nodes, Table 1, Fig 3 | **ODE**: 4-species SBML E-cad/β-cat, Eqs 7–12 |
| Extracellular PDE | **Yes**: nutrient (Eq 7) and VEGF (Eq 8) reaction–diffusion with uptake, decay, secretion | **No**: prescribed static gradient; no PDE (p.7, p.9) |
| ECM | **Yes, as a lattice type** (τ = 0, J row, integrin input from ECM contact; p.7, p.12, Table 2) | **None** |
| Two-way coupling | fields → RTK and VEGF inputs; contacts → ITG, cadherin, Wnt; phenotype → J, γ_e, β, chemotaxis, secretion → fields (p.12–13) | contacts → ODE; ODE → type → (unstated) adhesion; no field feedback |
| Parameters given | Most CPM and PDE values (Table 2). Missing: χ, normal-cell values, hypoxia and necrosis rules, solver | No CPM energies at all; only intracellular Table 1 |
| Quantitative validation | Sprout speeds (Table 3), growth curves, IVD, therapy percentages (+ S1 Data XLSX) | Mostly qualitative |

11a meets all four clauses of the spec: 2D, intracellular Boolean net, cell-level CPM, and extracellular PDEs with ECM as a lattice component. It has two-way coupling across all three scales. 11b fails "2D" and "PDE", and has no ECM. Its intracellular component is an ODE, which is the one element 11a lacks.

Suggestions:
- **Adopt 11a as item 11.**
- Keep 11b's contact-driven ODE (Eqs 10–12) as the **G9 ODE conformance test**. It is the cleanest paper-grounded case of an ODE component with per-neighbour contact-derivative inputs, parameter swap on a type transition, and state copy on division. A 2D port would be our own adaptation, not a reproduction.
- 11a's gaps (χ, hypoxia and necrosis rules, the nutrient unit conversion, the Wnt input, and the absent code) will need documented, flagged choices. They should be validated statistically against Table 3 and Figs 18–19 rather than reproduced exactly.

---

## 9. S1 Data (11a)

File: `docs/references/supplementary/11a_JafariNivlouei2021_S1Data.xlsx`. This is PLoS CB S1 Data for 10.1371/journal.pcbi.1009081, "the underlying numerical data for Figs 4, 5, 9, 10, 11, 13, 15, 17, 18 and 19" (11a p.30). Every sheet was parsed in full from the raw XML. Citations below use the form (supplementary/11a_JafariNivlouei2021_S1Data.xlsx, sheet X, cells …). Statements marked *inference* are our arithmetic on the data. The paper does not state them.

### 9.1 Workbook-level facts

- **Sheets.** There are 10 sheets, one per figure: "Figure 4", "Figure 5", "Figure 9", "Figure 10", "Figure 11", "Figure 13", "Figure 15", "Figure 17", "Figure 18", "Figure 19". None covers Table 3 or Figs 6–8, 12, 14, 16.
- **No parameters or replicate detail.** There is no parameter sheet, no field (PDE) data, no per-run columns, no SD or error-bar columns, and no seeds anywhere. The only formulas are the Fig 4 summaries (E14, E15) and day-index increments (e.g. sheet "Figure 10", cell A11 `=A10+1`).
- **Pixel size (inference).** Every area in sheets "Figure 9" and "Figure 18" is a whole multiple of 16 μm², i.e. 1 px = 16 μm². This supports Δx = 4 μm (§2A). The initial areas are 2096 μm² = 131 px (sheet "Figure 9", cell B5) and 2160 μm² = 135 px (sheet "Figure 18", cell B6) for 4 cells. That is ≈33 px per cell, consistent with "about 32 voxels" (Table 2 footnote).
- **Output cadence.** Time series in sheets "Figure 9" and "Figure 18" are sampled every 1/144 day = 10 min = 10 MCS (at 1 MCS = 1 min, p.13).
- **Single runs (inference).** Area series whose values are all multiples of 16 μm² are single trajectories, not ensemble means (a mean over runs would not generally land on multiples of 16). Count series with .5 or .25 values are means over 2 or 4 runs (or medians).

### 9.2 Sheet-by-sheet

| Sheet | Backs | Columns (units) | Rows / n | Replicates as indicated |
|---|---|---|---|---|
| "Figure 4" (cells A1:H15) | Fig 4, Table 3: sprout extension velocity | A–B: t, V (μm/h), Bauer et al. [26] reference, 9 points (A3:B12). D–E: with signalling, 9 points t = 0.2–14 (D3:E12). G–H: no signalling, 8 points (G3:H12). E14 `=MEDIAN(E4:E10)` = 12.649, labelled "mean 10h". E15 `=(E4+E6+E5)/3` = 25.130, labelled "mean (primitive)" | 9 / 9 / 8 time points | Caption: mean of n = 5 runs, error bars = SD (p.16). SDs are **not** in the sheet; Table 3 gives 3.7, 1.2 and 1.6 |
| "Figure 5" (cells A1:F14) | Fig 5: tumour radius vs [119] | A–B: t (day), r (mm), Taghibakhshi [119] Michaelis–Menten model, 10 points t = 0–15.9 (A3:B13). E–F: t (day), r (mm), this model, 11 points t = 0–14.3 (E3:F14) | 10 / 11 points | Caption: SD of 5 runs (p.17). No SD in the sheet, and see §9.3 item 2 |
| "Figure 9" (cells A1:J2165) | Fig 9: tumour area with and without angiogenesis | A–B: t (day), area (μm²), no angiogenesis (A4:B2165). E–F: same with angiogenesis (E4:F2165). t = 0–15 d every 10 min | 2161 samples per series | Not stated. Single run per series (inference, §9.1) |
| "Figure 10" (cells A1:H21) | Fig 10: viable (non-necrotic) tumour cell count | A–B: t (day), NOC (count), no angiogenesis. E–F: with angiogenesis. Daily, days 0–16 (A4:B21, E4:F21) | 17 points each | Not stated. Half-integer values imply a mean or median over an even number of runs (inference) |
| "Figure 11" (cells A1:K17) | Fig 11: avascular cell count, with and without host cells | A–B: t (day), NOC, no normal cells. E–F: with normal cells. Daily, days 0–12 (A4:B17, E4:F17). Columns G–K are empty | 13 points each | Caption: mean of 4 runs; bars = daily max−min (p.21). The bars are **not** in the sheet. Quarter values from day 9 are consistent with n = 4 |
| "Figure 13" (cells A1:F21) | Fig 13: vascular cell count, with and without host cells | A–B: t (day), NOC, no normal cells. E–F: with normal cells. Daily, days 0–16 (A4:B21, E4:F21) | 17 points each | Not stated. Integer counts through day 11. With-host days 12–16 are non-integer (§9.3 item 4) |
| "Figure 15" (cells A1:F16) | Fig 15: intratumoural vascularisation density (IVD) | A–B: area (%), d (%), experimental [128]. E–F: area (%), d (%), this model. The x values are identical in A and E (A4:B16, E4:F16) | 12 points | Not stated |
| "Figure 17" (cells A1:K16) | Fig 17: IVD under signalling intervention | A–B: experimental [128], as in Fig 15. E–F: this model, same x values (A4:B16, E4:F16). Columns G–K are empty | 12 points | Not stated |
| "Figure 18" (cells A1:J1734) | Fig 18: tumour area under therapy | A–B: t (day), area (μm²), therapy start day 3. E–F: start day 5. I–J: start day 6. t = 0–12 d every 10 min (A4:J1734) | 1729 samples per series | Not stated. Single run per series (inference, §9.1) |
| "Figure 19" (cells A1:B15) | Fig 19: area reduction during 10 days of treatment | A: t (day after therapy start), B: area reduction as a signed fraction (−0.7375 = −73.75%), days 0–10 (A4:B15) | 11 points | Not stated. Which start day, or pooled, is not stated |

The numeric targets taken from these sheets are in §5A (V11a-2, -2b, -5, -6, -6b, -7, -8, -9, -9b, -10, -10b).

### 9.3 Data-quality observations (all inference unless a cell is quoted)

1. **Fig 4 time unit.** The header reads "t (day)" (sheet "Figure 4", cells A3, D3). The values run 0.2–14, and the "mean 10h" summary covers t = 0.2–10 (cell E14). Table 3 averages "in 10h" and the text speaks of "the first two hours" (p.15). So t is in **hours**, and the header is a mislabel.
   - E14, labelled "mean", is actually a MEDIAN (12.65 → Table 3 "13").
   - E15, the mean of t = 0.2, 1, 2, is 25.13 (→ Table 3 "25").
   - Table 3's "in progress 11" matches the mean of t = 4–10 (E7:E10), which is 11.14. The sheet has no formula for this.
2. **Fig 5 radius is an equivalent-circle radius from the Fig 9 run.** F4 = √(2096 μm² / 3.14) exactly, i.e. π ≈ 3.14 was used.
   - At t = 0, 1.5, 6.0 and 9.5 d, F equals √(A/3.14) of the Fig 9 with-angiogenesis area at the same time to machine precision (sheet "Figure 5", cells F4, F5, F8, F10 vs sheet "Figure 9", cells F5, F221, F869, F1373).
   - The other 7 points differ by −5% to +21%.
   - So at least 4 of the 11 points come from that single run, not from the 5-run mean in the caption.
   - The caption's r₀ = 24.3 μm is the [119] reference start (sheet "Figure 5", cell B4 = 0.0243 mm). The simulation starts at 25.8 μm.
3. **Replicate structure.**
   - Fig 9: the with- and without-angiogenesis series differ from the first sample onward (t = 10 min). They are independent runs.
   - Fig 18: the three columns are identical until t = 1.0625 d (start-3 vs start-5 columns), and the start-5 and start-6 columns stay identical until t = 4.007 d.
   - The start-3 run therefore departs from the others 2 days **before** its therapy starts. The shared prefixes suggest shared seeds or restarts, but the runs are not controlled comparisons.
   - The Fig 18 initial area (2160) differs from Fig 9 (2096), so the Fig 18 runs are separate from Fig 9.
4. **Fig 13 with-host tail is extrapolated, not simulated.**
   - Days 12–16 are non-integer: 656.832, 810.74087424, 941.7566, 1192.8917, 1259.6936 (sheet "Figure 13", cells F17:F21).
   - Each is the previous value times a factor (1.056, 1.23432, 1.1616, 1.26667, 1.056). The factor 1.056 is also the day 9→10 ratio (F15/F14), and 1.26667 = 19/15 is the day 2→3 ratio (F8/F7).
   - Use only days 0–11 of this series as targets. Day 11 = 622 matches the text's "~620 cells" (p.23).
5. **Series that should agree do not.**
   - Vascular growth without host appears twice: sheet "Figure 10" (E5:F21) and sheet "Figure 13" (A5:B21). Values: day 1, 6 vs 8; day 10, 94 vs 99; day 16, 518.5 vs 614.
   - Avascular growth without host also appears twice: sheet "Figure 10" (A5:B21) and sheet "Figure 11" (A5:B17). Values: day 5, 46 vs 96; day 9, 63 vs 1382.75.
   - Our reading: Fig 10's "no angiogenesis" run keeps the pre-existing vessels (the Fig 6 setup, p.17–19), while Fig 11's setup is not described.
   - Fig 11 no-host doubles **exactly** every day from day 1 (6) to day 8 (768) (cells B6:B13). A mean of 4 stochastic runs would rarely do this, so the early phase is deterministic or idealised.
   - Treat each sheet as its own target. Do not cross-validate one sheet against another.
6. **The Fig 15/17 x-axis is undefined.** "area (%)" is not defined in the paper. IVD is defined as vessel area / tumour area (p.23), but what the x-axis area is normalised by is not stated. The simulated d values are listed at the experimental x values (the A and E columns are identical), so the model was not sampled independently along x. V11a-9 and V11a-9b are conditional on settling this definition.
7. **Fig 18 does not reproduce the text's numbers.**
   - First-day drop "~43%, ~77% and ~80%" (p.29): we recomputed it as the mean area over the first therapy day relative to the Fig 9 with-angiogenesis daily mean. That gives 45.8 / 55.4 / 80.2%; end-of-day points give 65 / 69 / 89%. Only the day-6 value matches.
   - "Mean tumor area at day 7 is 5536 μm²" (p.29): the value 5536 appears only as the start-day-5 area at **t = 10.0 d** (sheet "Figure 18", cell F1446), which is also the median of the three curves at t = 10. At t = 7 the curves read 3696 / 5808 / 6320 (cells B1014, F1014, J1014).
   - V11a-10 therefore targets the sheet values and records the text values without enforcing them.
8. **The Fig 19 baseline is not a constant 25000 μm².**
   - The values are exact fractions. (1 − reduction)·781 gives 205, 181.5, 157, 128, 151.5, 170 for days 1–6. (1 − reduction)·1785 gives 328, 325, 313, 306 for days 7–10 (sheet "Figure 19", cells B6:B15).
   - So the underlying quantity and baseline change between day 6 and day 7. Their units are unknown.
   - No Fig 18 curve gives these values as 1 − A/25000.
   - The text's "82% on average (range 78–83%)" matches the day 5–10 values (78.2–82.9%) and the day-10 value (82.9%). It does not match the day 1–10 mean (80.2%).

### 9.4 Parameters: what S1 Data does and does not reveal

| Unspecified item (§3A, §7) | S1 Data status |
|---|---|
| χ (tumour nutrient-chemotaxis, EC VEGF-chemotaxis) and sign | **STILL OPEN.** No sheet reports χ. Sprout speed (sheet "Figure 4") constrains χ_EC only jointly with J_EC-m, T_V and the VEGF field |
| Normal-cell J, γ_e, uptake, hypoxic death | **STILL OPEN.** Only with/without-host cell counts (sheets "Figure 11", "Figure 13") |
| Quiescence (hypoxia) threshold | **STILL OPEN.** No nutrient data. Timing targets only (V11a-4, V11a-7) |
| Necrosis rule and delay | **STILL OPEN.** Sheets "Figure 10", "Figure 11" count viable cells but do not report necrotic cells or thresholds |
| Apoptosis removal | **STILL OPEN.** The therapy decline rate (sheet "Figure 18") is a calibration target, not a parameter |
| PDE solver, sub-steps, Δt | **STILL OPEN.** No field data. Output cadence only (10 MCS per sample) |
| Division trigger | **STILL OPEN** (rule). Doubling time ≈1 d is a calibration target (§7 item 6) |
| Neighbour order | **STILL OPEN** |
| Therapy receptor clamped | **STILL OPEN** |
| Pre-existing vessel geometry | **STILL OPEN** |
| Δx = 4 μm | **RESOLVED** (supporting evidence): areas quantised at 16 μm² (§9.1) |
| Initial cell size ≈32 px | **RESOLVED** (consistent): 131–135 px for 4 cells (sheet "Figure 9", cell B5; sheet "Figure 18", cell B6) |

# 07 — Bauer, Jackson & Jiang 2007: cell-based model of sprouting angiogenesis

**Citation.** Bauer AL, Jackson TL, Jiang Y (2007). *A Cell-Based Model Exhibiting Branching and
Anastomosis during Tumor-Induced Angiogenesis.* Biophysical Journal 92(9): 3105–3121.
**DOI:** 10.1529/biophysj.106.101501
**PDF:** `docs/references/07_Bauer2007_BiophysJ_sprouting-angiogenesis.pdf` (17 pp.)

**Citation convention.** `(07 p.N [JJJJ], …)`: N = PDF page, JJJJ = printed journal page
(PDF p.1 = 3105, so JJJJ = 3104 + N). Tables, equations and figures were checked against page
images, because `pdftotext` garbles the minus signs, exponents and ± signs. For example, Table 1
D = "3.6 3 104" in the text extraction is 3.6 × 10⁻⁴ in the image. Values described as "read from
figure" are approximate.

**Relationship to Bauer 2009 (spec 05).** This is the parent model. The 2009 paper recalibrated
every parameter and changed the time scale, the chemotaxis rules and the energy terms. See §7.3.
They are **two different parameterisations and must be two reference models**.

---

## 1. Model summary

2D CPM coupled to a VEGF reaction–diffusion PDE. A single endothelial cell (EC) has budded from a
parent vessel at the left boundary. An avascular tumour beyond the right boundary supplies VEGF as a
line source. The stroma contains matrix fibres, interstitial fluid and immobile "tissue-specific
cells". Phenotypes:
- A **tip cell** migrates chemotactically and degrades matrix.
- **Proliferating** stalk cells grow and divide but do not move chemotactically.
- The remaining activated stalk cells move only by adhesion and fluctuation.

The experiments are:
- (H1) shallow vs steep VEGF gradients;
- (H2) location of the proliferating region;
- (H3) stroma composition (branching and anastomosis).

(07 p.3 [3107] hypotheses; p.5–8 [3109–3112] model.)

---

## 2. Mechanics

### 2.1 Lattice, domain, time
| Item | Paper content | Source |
|---|---|---|
| Dimension | 2D ("Using a two-dimensional domain provides a first approximation") | 07 p.5 [3109] §Model domain |
| Domain | Vessel-to-tumour distance "∼165 µm". Axes 0–166 µm (x) × 0–106 µm (y) in Figs 3, 4, 6. Fig 7 (five buds): 166 × 318 µm. | 07 p.5 [3109]; Figs 3–7 |
| Lattice spacing | **UNSPECIFIED** (S is in "pg/pixel", Table 1) | 07 p.6 [3110] Table 1 |
| Proposal | "a lattice site, x, is selected at random and assigned the σ from one of its unlike **second nearest neighbors**, x', which has also been randomly selected" | 07 p.7 [3111] |
| MCS | "A total of n proposed updates, where n is the number of sites on the lattice, constitutes one Monte Carlo step" | 07 p.7 [3111] |
| Time unit | "one Monte Carlo step is equivalent to 1 h", calibrated to the 18 h EC cycle | 07 p.8 [3112] §Parameters |
| Snapshot times | 16.6 days (Figs 3, 4d, 6, 7); 9.4 days (Fig 4b) | captions p.9–13 |
| Replicates | 12 simulations per condition (Fig 5 caption; Table 2 footnote) | 07 p.11 [3115]; p.13 [3117] |
| Mobile kinds | "Only endothelial cells are allowed to grow, move and invade; ECM, tissue-specific cells and interstitial fluid do not grow or actively invade each other or endothelial cells." | 07 p.7 [3111] |

### 2.2 Acceptance rule
P = 1 if ΔE < 0; P = e^{−ΔE/kT} if ΔE ≥ 0. kT = 0.01 (Table 1) (07 p.7 [3111], unnumbered).

### 2.3 Hamiltonian
**Eq. 2** (07 p.7 [3111]): E = Σ_sites J_{τ,τ'}(1 − δ_{σ,σ'}) + Σ_cells γ_τ (a_σ − A^T_σ)²
- τ ∈ {e, m, t, f}: endothelial cell, matrix fibre, tissue cell, interstitial fluid.
- "Matrix fibers and interstitial fluid are collectively identified by 1 and 0, respectively."
  Each EC (and, by implication, each tissue cell) has a unique σ (07 p.7 [3111]).
- A^T for a cell "undergoing mitosis … is designated as twice its initial volume" (07 p.7 [3111]).

**Eq. 3** (07 p.7 [3111]), the chemotaxis energy change: ΔE_Chemotaxis = μ_σ [V(x) − V(x')]
- μ_σ < 0 is the "effective chemical potential". x' and x are "the two neighboring lattice sites
  randomly selected during one trial update".
- Section 2.1 defines x as the site being overwritten and x' as the neighbour whose σ is copied.
  With μ < 0, copying into a higher-V site lowers E if the term is taken for the gaining cell.
  This is our reading, not explicit in the paper.
- Only the tip cell is chemotactic (§2.4), so μ_σ ≠ 0 only for the tip.

**No continuity term** appears in 2007. It was added in 2009.

Effective mechanical coupling: "Effective mechanical forces exerted on the ECM by endothelial cells
… are incorporated as a result of the matrix fibers' resistance to compression given by γ_m"
(07 p.7 [3111]). "Haptotaxis is naturally incorporated through this adhesion term" (07 p.8 [3112]).

### 2.4 Cell rules
| Rule | Paper content | Source |
|---|---|---|
| Initial condition | Single EC that has degraded the basement membrane, adjacent to the left boundary (Fig 2). Stroma: fibres + fluid + tissue cells. "all simulations used the same parameter set, initial configuration of matrix fibers and tissue cell distribution". Initial EC size is **UNSPECIFIED** (EC ∼10 µm diameter, p.6). | 07 p.5 [3109]; p.8 [3112]; Table 1 footnote |
| Activation | "VEGF must be present in quantities above a threshold level, v_a" | 07 p.8 [3112] |
| Phenotype decision | "Once activated, each individual endothelial cell decides whether it is a tip cell and will migrate and degrade the ECM, or if it is a proliferating cell, and will grow and divide" | 07 p.8 [3112] |
| Tip cell | "defined as the leading endothelial cell"; migrates chemotactically "using the matrix fibers for support"; degrades matrix fibres | 07 p.8 [3112] |
| Proliferating cells | "Proliferation occurs behind the tip cell … by allowing those stalk cells to proliferate". "if the cell is proliferating, it cannot move chemotactically … and vice versa." The baseline location of the region is not given numerically (see H2). The Discussion says "cell proliferation occurs only in one cell". | 07 p.8 [3112]; p.15 [3119] |
| Other stalk cells | "as long as they are VEGF-activated, only move in response to cell-cell and cell-matrix adhesion, and through random membrane fluctuation" | 07 p.8 [3112] |
| Cell clock and division | "Cell division occurs when a proliferating cell has doubled in size and has gone through one complete cell cycle, which we take to be 18 h". "one daughter cell keeps the cell ID of the parent and the other is assigned its own unique ID". The split geometry is **UNSPECIFIED**. | 07 p.8 [3112] |
| Death | "endothelial cell death is not considered" | 07 p.8 [3112] |
| Degradation | Tip cell "is also capable of degrading the matrix fibers, thereby establishing local adhesion gradients". **Rate, product state and site selection are UNSPECIFIED.** On in baseline (+5% speed vs without). | 07 p.8 [3112] |
| Tissue cells | "roughly the same size as an endothelial cell", "immobile", "more difficult to invade than matrix fibers and interstitial fluid". Number and placement are **UNSPECIFIED** in the text. Fig 2 shows 24 squares, ≈9.2 µm sides (16–17 px, ≈276 sites), on a jittered 4 × 6 grid, digitised (§8b Q9; audit 2026-10-13, replacing the earlier "≈30 squares ≈7–8 µm" reading). | 07 p.6 [3110]; Fig 2 p.5 |
| Deactivation (H1 only) | "If there is insufficient VEGF, a cell will deactivate and become inert." | 07 p.9 [3113] |
| VEGF-dependent proliferation (H1 only) | "an activated cell additionally decides whether there is enough VEGF present to stimulate proliferation, v_p". v_p is chosen to trigger proliferation ∼48 h after the initial cell starts migrating. | 07 p.9 [3113] |

### 2.5 Update order (§Hybridization, 07 p.8 [3112])
1. t = 0: the steady-state solution of Eq 1 sets the initial VEGF profile.
2. Each EC checks activation (v_a), then decides tip vs proliferating.
3. The CPM evolves one MCS (= 1 h).
4. B(x, y, V) is "rederived based on the new distribution of endothelial cells".
5. Eq 1 is solved for the next time step with the updated B.
6. "The lattice is then updated with the new VEGF profile."

The PDE scheme and step are **UNSPECIFIED**.

### 2.6 VEGF field — Eq. 1 (07 p.5 [3109])
∂V/∂t = D∇²V − λV − B(x, y, V)

- **B** (07 p.6 [3110], unnumbered):
  - B = β if β ≤ V and (x, y) ⊂ EC;
  - B = V if 0 ≤ V < β and (x, y) ⊂ EC;
  - B = 0 if (x, y) ⊄ EC.
  - "an endothelial cell instantly binds an amount of VEGF equal to the lesser of available
    chemical concentration V or the maximum amount … β."
- **β derivation** (07 p.5 [3109]): uses 311,200 VEGFR1+VEGFR2 receptors per cell, an
  internalization rate of 4.3 × 10⁻⁴ s⁻¹ and a VEGF165 molecular weight of 45 kDa, giving
  β = 0.06 pg/EC/h (Table 1).
- **Initial and boundary conditions** (07 p.6 [3110]):
  - V(x, y, 0) = 0;
  - V(0, y, t) = 0;
  - V(L₁, y, t) = S;
  - V(x, 0, t) = V(x, L₂, t), i.e. periodic in y.
  - The first condition conflicts with "the steady-state solution … as an initial condition" on
    the same page. The paper says the stroma reaches steady state quickly and uses the steady
    profile as the CPM's initial condition.
- **Source S**: estimated from hypoxic VEGF secretion rates (ref 4) and the number of quiescent
  cells in an avascular tumour from Jiang et al. 2005 (ref 46), treated as a line source at 165 µm
  (07 p.6 [3110]).
- **Steep-gradient variant** (H1): "we begin with the same initial VEGF profile but do not provide
  a source of VEGF as before", so VEGF depletes (07 p.9 [3113]). Whether the right-boundary
  condition becomes no-flux or V = 0 is **UNSPECIFIED**.

### 2.7 Stroma layout (07 p.6 [3110])
- 1.1 µm-thick fibre bundles are "randomly distributed … at randomly chosen discrete orientations
  ranging from 0 to 180° until 37% of the stroma was occupied".
- The discrete angle set and the bundle length are **UNSPECIFIED**.
- Tissue cells are placed as in Fig 2.

---

## 3. Parameters

### 3.1 Stated (Table 1, 07 p.6 [3110])
An asterisk marks parameters that the paper varies between experiments.

| Symbol | Value | Units (paper "Dimensions") | Meaning | Source |
|---|---|---|---|---|
| D | 3.6 × 10⁻⁴ | cm²/h (L²/T) | VEGF diffusion | Table 1 (ref 62) |
| λ | 0.6498 | h⁻¹ | VEGF decay | Table 1 |
| β | 0.06 | pg/EC/h (M/cell/T) | max uptake per EC | Table 1 |
| S | 0.035 | pg/pixel (M/L) | boundary VEGF | Table 1 |
| v_a | 0.0001 | pg | activation threshold | Table 1 |
| v_p | 0.005 | pg | proliferation threshold (H1 experiments) | Table 1 |
| J_ee | 1 | E/L | EC–EC | Table 1 |
| J_ef | 32 | E/L | EC–fluid | Table 1 |
| J_em | 16 | E/L | EC–matrix | Table 1 |
| J_et | 31 | E/L | EC–tissue | Table 1 |
| J_ff | 35 | E/L | fluid–fluid | Table 1 |
| J_fm | 35 | E/L | fluid–matrix | Table 1 |
| J_ft | 32 | E/L | fluid–tissue | Table 1 |
| J_mm | 5 | E/L | matrix–matrix | Table 1 |
| J_mt | 30 | E/L | matrix–tissue | Table 1 |
| J_tt | 2 | E/L | tissue–tissue | Table 1 |
| γ_e* | 1.0 | E/L⁴ | EC elasticity (0.7 in Figs 3, 5) | Table 1; Fig 3, 5 captions |
| γ_m | 0.4 | E/L⁴ | matrix | Table 1 |
| γ_f | 0.1 | E/L⁴ | fluid | Table 1 |
| γ_t* | 1.2 | E/L⁴ | tissue cell (0.8 in Figs 3, 5) | Table 1; Fig 3, 5 captions |
| μ* | −1.5 × 10⁵ | E/conc | chemotaxis (tip) | Table 1 |
| kT | 0.01 | E | temperature | Table 1 |
| cycle | 18 | h | EC cell cycle | 07 p.8 [3112] |
| A^T (mitotic) | 2 × initial volume | — | — | 07 p.7 [3111] |
| fibre bundle | 1.1 | µm | thickness | 07 p.6 [3110] |
| matrix fraction | ≈37% | — | of stroma | 07 p.6 [3110] |
| 1 MCS | 1 | h | time conversion | 07 p.8 [3112] |
| Receptors/EC | 311,200 | — | used for β | 07 p.5 [3109] |
| k_int | 4.3 × 10⁻⁴ | s⁻¹ | internalization | 07 p.5 [3109] |
| MW VEGF165 | 45 | kDa | used for β | 07 p.5 [3109] |

### 3.2 Derived
| Quantity | Value | Derivation |
|---|---|---|
| D per MCS | 3.6 × 10⁴ µm²/MCS | 3.6×10⁻⁴ cm²/h × 10⁸ µm²/cm² × 1 h/MCS |
| λ per MCS | 0.6498 | 1 MCS = 1 h |
| √(D/λ) | ≈235 µm | as in spec 05 |
| Cycle in MCS | 18 | 18 h / (1 h/MCS). Note how short this is: a cell doubles volume within 18 MCS. |
| Run length for 16.6 d snapshots | ≈398 MCS | 16.6 × 24 |
| Proliferating-region distances tested | Tip (0), 8.9 µm ("immediately behind"), 26.6 µm ("three cell lengths"), base | Fig 5 x-axis, p.11 [3115]. 26.6/3 ≈ 8.9 µm per cell length. |
| Exp 1 (tip) speed | ≈5.64 µm/day | 7.7 / 1.365 (p.11: 7.7 is "a 36.5% increase above the rate observed in Experiment 1") |
| Fastest of Exp 1–4 | ≈7.17 µm/day | 7.7 / 1.074 ("7.4% increase over the fastest") |

### 3.3 UNSPECIFIED
Pixel size; lattice type; whether "second nearest neighbors" means the 2nd shell only or shells
1–2; neighbourhood for adhesion energy; initial EC and tissue-cell sizes in pixels; tissue-cell
count and placement rule; fibre angle set and length; degradation rate, product and site choice;
how the tip is identified ("leading"); how the baseline proliferating cell(s) are chosen and how
many; B per-site vs per-cell; PDE solver and step; the steep-gradient right-boundary condition;
the target volumes of the matrix and fluid collectives; boundary conditions for the CPM; the total
run length (only snapshot times are given).

---

## 4. Verification of prior claims

| # | Prior claim | Verdict | Evidence |
|---|---|---|---|
| 1 | Same framework as 2009 without degradation | CORRECTED | 2007 **has** tip-cell ECM degradation, which raises speed by 5% (07 p.8 [3112]). 2007 also has tissue cells, no continuity term, tip-only chemotaxis, no parent-vessel recruitment, 1 MCS = 1 h, kT = 0.01 and entirely different J/γ/μ (Table 1). See §7.3. |
| 2 | VEGF from tumour boundary with different source profiles | CORRECTED | A single line source at the right boundary, V(L₁) = S (p.6 [3110]). The "profiles" compared are shallow (source on, soluble) vs steep (same initial profile, **no source**, depletion mimicking matrix-bound VEGF) (p.9 [3113], Fig 4). There are no alternative spatial source profiles. Parabolic profiles are mentioned only in 2009 as future work (05 p.16). |
| 3 | Uptake, decay | CONFIRMED | Eq 1 and the B function (p.5–6 [3109–3110]); λ = 0.6498 h⁻¹ |
| 4 | Activation threshold | CONFIRMED | v_a = 0.0001 pg (Table 1; p.8 [3112]). A second threshold, v_p = 0.005 pg, is used only in H1. |
| 5 | Only tip cell strongly chemotactic | CORRECTED | The tip cell is the **only** chemotactic cell. Non-proliferating stalk cells "only move in response to cell-cell and cell-matrix adhesion, and through random membrane fluctuation". Proliferating cells "cannot move chemotactically" (p.8 [3112]). A single μ appears in Table 1. |
| 6 | Proliferating region at a set distance behind the tip (studied variable) | CONFIRMED | Tip / immediately behind (8.9 µm) / three cell lengths (26.6 µm) / base (p.11 [3115], Fig 5). "the proliferating region is a fixed distance from the tip throughout the simulation" (p.14 [3118]). |
| 7 | Branching from fibres, fluid, resident tissue cells | CORRECTED | The branching mechanisms are matrix-fibre structure alone (Fig 6b) and resident tissue cells alone (Fig 6c). **No** branching in the homogeneous environment of fluid only (Fig 6d, p.12–13 [3116–3117]). Fluid is not a mechanism. |
| 8 | Sprout morphology depends on gradient profile | CONFIRMED | Fig 4, p.9–10 [3113–3114]: shallow gives swollen sprouts (≈60 µm diameter); steep gives narrow sprouts (≈20 µm) |
| 9 | Speed depends on proliferation-zone distance | CONFIRMED | Fig 5: speed increases with distance from the tip, then plateaus (p.11 [3115]) |
| 10 | Branching/anastomosis emerge | CONFIRMED | "no rules specifically incorporating branching or anastomosis are imposed" (p.4 [3108]). Fig 6a branch; Fig 7 anastomosis from five buds. |

**Tally (07): CONFIRMED 6, CORRECTED 4, NOT IN PAPER 0** (10 claims).

---

## 5. Validation targets

The comparisons are statistical over ensembles (the paper uses n = 12), with no bitwise parity.

*(audit 2026-10-13)* **Parameter set for W1–W5: Table 1 with γ_e = 0.7 and γ_t = 0.8.** Figs 3
and 5 state "Parameters used are given in the parameter table except γe = 0.7 and γt = 0.8"
(p.9, p.11). W1's 14.2 ± 2.44 µm (SD) and the Table 2 fibres + tissue diameter 14.20 ± 0.70 are
the same ensemble (0.70 × √12 = 2.42 ≈ 2.44), and Table 2's 6.84 µm/day equals the Fig 5
8.9 µm point, so Table 2 (W2, W3) is the 0.7/0.8 set as well. Conflict: the Fig 6 caption, whose
four panels are the Table 2 stromal compositions, says "Parameters are given in Table 1" (no
exception). The spec follows Figs 3/5 and the √12 arithmetic; see §7.1 item 6.

| ID | Target | Source | Type | Proposed tolerance |
|---|---|---|---|---|
| W1 | Sprout diameter 14.2 ± 2.44 µm (mean ± SD), 1–2 cells wide (baseline; γ_e = 0.7, γ_t = 0.8, audit 2026-10-13) | 07 p.9 [3113] | Quant | 11–18 µm |
| W2 | Table 2 speeds (µm/day, mean ± SD error; n = 12): no fibres/no tissue 5.33 ± 0.075; tissue only 5.41 ± 0.074; fibres only 6.33 ± 0.131; fibres + tissue 6.84 ± 0.131 | Table 2 p.13 [3117] | Quant | Each within ±15%. Ordering fibres+tissue > fibres only > {tissue only ≈ none}. "18–28% increase" with fibres. |
| W3 | Table 2 diameters (µm): 19.29 ± 0.26; 19.08 ± 0.46; 14.41 ± 0.26; 14.20 ± 0.70 | Table 2 | Quant | ±20%. No-fibre cases ≈ 1.35× wider. |
| W4 | Proliferating region vs speed (Fig 5, µm/day, read from figure): base ≈7.05; 26.6 µm ≈7.17; 8.9 µm ≈6.85; tip ≈5.64 (derived) | Fig 5 p.11 [3115]; p.11 text | Quant | Tip speed ≥15% below the others. Base ≈ 26.6 µm (no significant difference). Morphology unchanged. |
| W5 | Proliferation not exclusive with migration: 7.7 µm/day (+36.5% over Exp 1, +7.4% over the fastest) | p.11 [3115] | Quant | 7.7 ± 10%; must exceed all of Exp 1–4 |
| W6 | Tip degradation raises speed by 5% (small but significant) | p.8 [3112] | Quant | +2–10% |
| W7 | Shallow gradient (soluble): sprout ≈46% larger, average diameter ≈60 µm, lateral/backward migration, more proliferation; reaches the same distance in 9.4 d as the steep case in 16.6 d | p.9–10 [3113–3114]; p.15 [3119]; Fig 4b | Quant+Qual | Diameter 45–75 µm |
| W8 | Steep gradient (no source): diameter ≈20 µm, shrinking proliferating region, some cells inactivate | p.10 [3114]; Fig 4d | Quant+Qual | Diameter 15–26 µm |
| W9 | Branching with fibres only (Fig 6b), with tissue cells only (Fig 6c), none in a homogeneous stroma (Fig 6d, which is more linear, wider, slower and more persistent) | Fig 6 p.12 [3116]; p.13 [3117] | Qual | Branch frequency > 0 in (b), (c); ≈0 in (d) |
| W10 | Five buds, 166 × 318 µm: at least one anastomosis loop | Fig 7 p.13 [3117] | Qual | Loop present in some replicates (rate unreported) |
| W11 | Sensitivity: results insensitive to γ_f, γ_m, γ_t. Larger γ_e gives smaller cells; smaller J_em gives more elongated cells. μ × 10 gives larger, elongated cells and pervasive sprouts. μ ÷ 10³ gives rounder cells and stunted sprouts. kT × 10² gives cell break-up. | 07 p.14 [3118] | Qual | Each trend reproduced |
| W12 | Alternative random ECM realisations at the same density do not qualitatively change results | 07 p.14 [3118] | Qual | Across-seed consistency |

---

## 6. Required general features

| ID | Need | Specific use |
|---|---|---|
| G1 @transition/@create/@retire + Bernoulli | Activation (V > v_a), deactivation (V < v_a, H1), tip vs proliferating assignment, VEGF-dependent proliferation (v_p), division @create (daughter with new ID, parent keeps ID) | 07 p.8–9 [3112–3113] |
| G2 shape descriptors in energies | Not needed | — |
| G3 contact-scope direction/position | Eq 3 ΔE = μ_σ[V(x) − V(x')] per proposal, with phenotype-dependent μ (non-zero only for the tip) | 07 Eq 3 p.7 [3111] |
| G4 connectivity | None required by the paper (no continuity term). Optional local connectivity might be needed to avoid fragmentation at kT = 0.01; **not specified**. | — |
| G5 symbolic BCs + SteadyState + coarse grid | Dirichlet 0 / S at x-boundaries, periodic y. SteadyState for t = 0. Transient per MCS. Switchable source BC for the steep-gradient experiment. | 07 p.6 [3110]; p.9 [3113] |
| G6 conservative per-cell uptake | B = min(β, V) on EC sites. Removal must be conservative in the depletion (steep) experiment. | 07 p.6 [3110] |
| G7 @convert | Tip-cell matrix degradation (rate unspecified) | 07 p.8 [3112] |
| G8 pluggable proposal law | Second-nearest-neighbour source selection. **Kind-restricted copy sources**: "only endothelial cells are allowed to … invade" suggests proposals where only EC σ can be copied. Needs a per-kind source mask in the proposal law. | 07 p.7 [3111] |
| G9 per-cell component protocol | An 18 h clock per EC; nothing else intracellular | 07 p.8 [3112] |
| G10 cluster-scope quantities | "Leading" EC = tip (argmax along the gradient over the sprout cluster). The proliferating region is defined by distance/rank from the tip along the sprout (tip, next, three cell lengths, base). Matrix and fluid are collective IDs 1/0 (generalized cells, multiply connected). Under D-066 they are **ordinary cells** (no retained-empty state; losing every site through copies is implausible), with an optional zero-cost guard `@constraint no_extinction(matrix, fluid)` (`../liveness-survey.md` §5). | 07 p.7–8 [3111–3112]; p.11 [3115] |
| G11 ordered relationships | The proliferating region "three cell lengths behind" could be a chain rank from the tip; G10 distance suffices otherwise | 07 p.11 [3115] |
| G12 observables | Sprout length (initial EC COM to tip COM) / time; mean sprout diameter; branch and loop detection; proliferating-cell count; activation state map | 07 p.9 [3113]; Table 2 |
| G13 initial layouts | Fibre bundles (0–180°, 37%); tissue-cell grid with jitter; one or five EC buds on the left wall; tall domain (318 µm) for Fig 7 | 07 p.6 [3110]; Figs 2, 7 |
| G15 (proposed, see spec 05) | Operator-split schedule: 1 MCS ↔ 1 h PDE step ↔ rules | 07 p.8 [3112] |

---

## 8b. Reverse-engineering plan (2026-10-13, spec owner)

Goal: infer each unstated or conflicting item before asking, so that author questions become
"we inferred X from Y; please confirm". The lattice evidence is shared with 2009 and is set out
in full in spec 05 §8b (R1–R2). Figure readings come from the embedded 200 ppi rasters
(`pdfimages`; Fig 2 is 494 × 316 px for 166 × 106 µm, i.e. 0.336 µm per figure pixel).

**Cost basis (assumed, not measured).** A 300 × 192 lattice at ≈1 ms/MCS (no BFS term). One
16.6-day run is ≈400 MCS, so ≈0.4 s. Fig 7 (300 × ≈575) takes ≈1.2 s. A 12-replicate condition
costs ≈5 s.

### 8b.1 Verdict per item

| # | Item (§7 ref) | Status after this plan |
|---|---|---|
| Q1 | µm/pixel, lattice, proposal neighbourhood (§7.3 q1) | **Pinned** (shared with 05 §8b R1–R2) |
| Q2 | Adhesion neighbour order (§7.3 q1) | **Screen T1** |
| Q3 | 1 MCS = 1 h; run length (§7.3 q2) | **Stated** + digitisation check; confirm only |
| Q4 | Baseline proliferating cell and rule (§7.1 item 3; q3) | **Partly pinned** (16 px distance band); **screen T4** |
| Q5 | Tip identity (q3) | Borrow 05 R9; **author-confirm** |
| Q6 | Degradation rate, product, sites (q4) | **Rate bounded by arithmetic**; **screen T3** |
| Q7 | Eq 3 x/x′ and gain/loss (q5) | **Screen T5** |
| Q8 | Copy restriction / stroma (q6) | **Inferred** (substrate overlay, as 05 R7); confirm |
| Q9 | Tissue cells (q7) | **Pinned by digitisation** (24 squares, 16–17 px) |
| Q10 | Fibres (q8) | **Digitisation** (angles by Hough on Fig 2; length ≈6 px) |
| Q11 | PDE stepping, steep-run BC, initial V, β units (§7.1 items 1, 4; q9–q10) | **Physical stepping rejected by arithmetic**; **screen T2** |
| Q12 | What v_a, v_p compare against | **Pinned by arithmetic** (per-site V at the cell) |
| Q13 | Table 2 "± SD error" (§7.1 item 5) | **Inferred SEM** by arithmetic; confirm (low) |

### 8b.2 Evidence and arithmetic

**Q1 — lattice.**
- Figs 3, 4 and 6 use the same 0/82.8/166 and 0/52.9/106 ticks as 2009, so the same
  300 × 192 lattice at p = 0.5538 µm applies (05 §8b R1).
- The Fig 5 distances (p.11 [3115]) independently pin p. 8.9 µm and 26.6 µm are 16 px and 48 px
  only for p ∈ [0.553, 0.555]. At 0.55 they would print as 8.8 and 26.4.
- The vessel-to-tumour distance "∼165 µm" (p.5 [3109]) is 299 × 0.5538 = 165.6.
- Fig 7: 318 µm ≈ 575 rows, i.e. three stacked domains.
- Proposals are Moore-8. The 2nd-shell-only reading splits every cell into sublattices, which the
  solid cells in the figures rule out (05 §8b R2).
- Derived sizes: EC of 10 µm diameter = 256 sites; W1 14.2 µm = 26 px; W7 60 µm = 108 px;
  W8 20 µm = 36 px.

**Q3 — time.**
- 1 MCS = 1 h is stated (p.8 [3112]).
- Snapshots: 16.6 d = 398.4 MCS and 9.4 d = 225.6 MCS, so runs of ≈398–400 and ≈225 MCS.
- Check: tip displacement digitised from Figs 3 and 6, divided by the Table 2 speed, must give
  ≈16.6 d (±15 %).

**Q4 — proliferation.**
- Fig 5 uses exact pixel multiples (16 and 48 px = one and three "cell lengths"). The tested
  variable is therefore a geometric distance d behind the tip, not a rank. "a fixed distance from
  the tip" (p.14 [3118]) agrees.
- The baseline is d = 16 px, since Table 2's 6.84 µm/day equals the Fig 5 8.9 µm point (§7.1
  item 3), and "proliferation occurs only in one cell" (p.15 [3119]).
- Open: the band width, and how the first stalk cell arises when the run starts with one
  non-proliferating tip.

**Q6 — degradation.**
- Option A is the 2009 real-time rate, (0.55 µm)²/min = 60 sites/MCS at 1 h/MCS. Over 400 MCS that
  is 24,000 sites, more than all the matrix (0.37 × (57,600 − 24 × 276) ≈ 18,900 sites). That
  cannot give a "small" +5 % effect (p.8 [3112]), so option A is rejected.
- Option B is the per-MCS reading of the same code, 1 site/MCS. Over 400 MCS that is ≈120 µm², a
  ≈1 µm × 110 µm trail, consistent with +5 %.
- The product (fluid) and the scattered site choice are taken from 2009 Fig 7B (05 §8b R8), same
  lineage.

**Q8 — stroma.**
- The text bars matrix, tissue and fluid from invading (p.7 [3111]). Yet "backward migration" and
  "lateral" movement are reported (p.10 [3114]), and these need EC sites to be vacated.
- This matches the 2009 substrate-overlay reading (05 §8b R7).
- Check (digitisation, no runs): register Fig 2 (t = 0) with Figs 3 and 4b/4d (same initial
  stroma, p.9 [3113]). Away from the sprout, fibre and tissue pixels should be identical, which
  would mean no matrix/fluid/tissue copies.

**Q9 — tissue cells.**
- Fig 2: 24 filled squares, mean area ≈750 figure-px² = 85 µm², i.e. ≈9.2 µm sides = 16–17 px
  (≈276 sites). They lie on a jittered 4 × 6 grid. Fig 3 shows the same squares (bbox 28–30 figure
  px at 0.333 µm/px).
- This corrects the §2.4 "≈30 squares ≈7–8 µm" reading.
- Positions can be digitised directly, since the configuration is the same in all runs
  (p.9 [3113]).
- One ID each, with A_T = initial area, is implied by "compete for space" (p.6 [3110]).

**Q11 — field. This is the main new finding.**
- Fig 4a (p.10 [3114]) shows the shallow-run profile as a linear plane from 0 to 0.035. The steady
  sinh profile would have a 26 % slope change (05 §8b R6).
- Fig 4c (steep run, no source) still shows the full background plane at 16.6 days, with only a
  trench along the sprout.
- With physical D = 3.6 × 10⁴ µm²/h at 1 h/MCS, the slowest mode decays at Dπ²/L² ≈ 13 h⁻¹ (both
  ends at V = 0), or ≈3 h⁻¹ with a no-flux right end. λ alone e-folds in 1.5 MCS and takes V below
  v_a in ≈9 MCS. Either way the domain empties within hours.
- **So the PDE cannot have advanced 1 physical hour per MCS.** Explicit stepping would also need
  ≈4.7 × 10⁵ substeps per MCS (D = 1.17 × 10⁵ px²/MCS).
- Inference: one stability-limited step per MCS (or no diffusion/decay between solves) and a
  linear initial profile. Under this reading the steep-run right-boundary condition (q9) is moot.
- Uptake granularity:
  - **Per site:** β·1 h = 0.06 pg > V_max = 0.035, so every EC site empties in one MCS. In the
    steep run every cell would fall below v_a at once. This contradicts "some cells eventually
    became inactive" (p.10 [3114]).
  - **Per cell:** 0.06/256 ≈ 2.3 × 10⁻⁴ pg per site per MCS empties a 0.02 pg site in ≈85 MCS
    (≈3.5 d). *(audit 2026-10-13: divisor corrected from 276, the tissue-cell area, to the EC
    area of 256 sites, §8b Q1.)* That gives gradual inactivation, and a "very slight effect" in the shallow run
    (p.9 [3113]). → **per cell favoured**.

**Q12 — thresholds.**
- S is in "pg/pixel", and v_a and v_p are in pg. In the linear profile, V per site = v_p = 0.005
  at x = 23.7 µm (43 px), and v_a = 10⁻⁴ at x = 0.47 µm (all columns except column 0).
- Starting from COM ≈ 5 µm, the cell must travel ≈19 µm. In the shallow run (≈1.8× faster:
  "same distance" in 9.4 d vs 16.6 d) that takes ≈1.5–2 d, matching "∼48 h" (p.9 [3113]).
- ΣV over the cell (≈256 × V; audit 2026-10-13, EC area, was 276) or the bound amount min(β, ·) exceeds v_p immediately, which leaves
  no delay. Both are rejected.
- → **compare V at the cell (COM or mean over sites)**.

**Q13 — SD or SEM.** Table 2 gives speeds 5.33 ± 0.075 (1.4 % CV) and diameter 14.20 ± 0.70,
while W1 is 14.2 ± 2.44 (SD, 17 % CV). As SEM with n = 12, the speed SD would be 0.26 (4.9 %),
which is plausible. *(audit 2026-10-13)* Direct check: W1 and the Table 2 fibres + tissue
diameter are the same ensemble (both 14.2 µm, γ_e = 0.7/γ_t = 0.8, n = 12), and
0.70 × √12 = 2.42 ≈ 2.44 (equivalently 2.44/√12 = 0.704). → **Table 2 errors are SEM**. Fig 5
says SD.

### 8b.3 Pre-registered screens (no runs yet; rules fixed now)

**T1 — adhesion order (Q2).**
- Candidates: orders {1, 2, 3}. Fixed: p, square, Moore-8 proposals, Table 1 values with
  γ_e = 0.7 and γ_t = 0.8 for every W1–W5 target (Figs 3/5; audit 2026-10-13, see §5 note).
- Targets:
  - W1 diameter 11–18 µm;
  - W3 no-fibre/fibre diameter ratio ≈1.35 (±0.15);
  - W11 trends (smaller J_em → more elongated; larger γ_e → smaller cells);
  - EC–EC facet fraction at ±45° digitised from Figs 3 and 4b/d.
- Rule: reject candidates failing ≥ 2 quantitative targets, then rank by facet fraction. If
  unresolved, keep order 2 and ask (shared with 05 S1).
- 3 × (1 + 4 perturbations) × 12 replicates ≈ 1 min.

**T2 — field and uptake (Q11).**
- Candidates: stepping {physical 1 h (negative control); one explicit step/MCS; frozen field with
  uptake only} × uptake {per site, per cell} × steep BC {V = 0, no-flux}.
- Targets:
  - Fig 4c right-edge background ≥ 0.9 S at 16.6 d (no source);
  - trench confined to the sprout (≤ 2 px outside);
  - fraction of inactive ECs at 16.6 d in (0, 0.5);
  - W8 diameter 15–26 µm;
  - W7 diameter 45–75 µm and equal reach at 9.4 d vs 16.6 d (±20 %);
  - Q12 v_p onset 36–60 h.
- Rule: pass all. If several pass, prefer the fewest unstated mechanics and ask with the ranking.
- 12 cells × 12 replicates × 2 runs ≈ 2 min.

**T3 — degradation rate (Q6).**
- Candidates: {0, 0.5, 1, 2} sites/MCS, plus 60 as a negative control. Site rule = the 05 S4
  winner.
- Target: W6 speed gain of +2–10 %, significant at n = 12 (Welch, α = 0.05).
- Rule: the smallest rate passing W6. The prediction is 1.
- ≈30 s.

**T4 — proliferation rule (Q4).**
- Candidates: {cells with COM in a band [d ± 8 px] behind the tip COM; rank-k along the sprout}
  × bootstrap {tip divides until the band is occupied; initial bud of 2 cells}.
- Targets: W4 ordering tip < 16 px < 48 px ≈ base, each within ±15 %; W5 7.7 µm/day exceeds all;
  Table 2 W2 four stroma speeds.
- Rule: the candidate passing all wins. Otherwise ask with our best.
- 4 × 9 conditions × 12 replicates ≈ 3 min.

**T5 — Eq 3 form (Q7).**
- Candidates: {gaining cell only; gain − loss}.
- Targets: W11 μ × 10 gives larger elongated cells and pervasive sprouts; μ ÷ 10³ gives round
  cells and stunted sprouts; W2.
- Rule: pass both W11 trends and W2 within ±15 %.
- ≈1 min.

In total ≈10 min on this Mac.

### 8b.4 What remains for the authors (all "confirm our inference")

1. **B2:** shared with 05 §8b.4 item 1 (300 × 192 square lattice at ≈0.554 µm/px, Moore-8
   proposals; adhesion order?). The Fig 5 16/48 px distances are the 2007 evidence.
2. **Field:** "Fig 4c keeps the full background profile after 16.6 d without a source, which
   physical D and λ at 1 h/MCS would drain within hours. How was Eq 1 advanced per MCS? Was β
   applied per cell?"
3. **B9:** "Runs of ≈400 MCS? Baseline: one cell in a band 16 px behind the tip; how did the first
   such cell arise?"
4. Tip identity and stroma overlay: shared with 05 §8b.4 items 2–3.
5. Only if the screens are inconclusive: Eq 3 gain/loss (T5), degradation rate (T3).
6. Low: Table 2 errors are SEM? Code or input deck (q11)?

Dropped as answered by the figures or arithmetic: tissue-cell count, size and placement (Q9),
threshold quantity (Q12), the q9 boundary condition (moot under Q11), and the "60 sites/MCS"
degradation option.

---

## 7. Ambiguities, conflicts, questions

### 7.1 Internal
1. **V(x, y, 0) = 0** as an initial condition (p.6 [3110]) vs "the steady-state solution to Eq. 1
   defines the initial VEGF profile" (p.8 [3112]). The best reading: the PDE starts from 0 and is
   relaxed to steady state before the CPM starts.
2. **Time scale.** 1 MCS = 1 h with an 18 h cycle means 18 MCS per division. Snapshots at 16.6
   days are ≈400 MCS. Speeds are 5–7.7 µm/day, which the paper itself notes are "considerably
   slower" than the measured 0.1–0.3 mm/day (p.15 [3119]).
3. **Baseline proliferating region.** It is "behind the tip cell" (p.8 [3112]), but the
   Discussion says "cell proliferation occurs only in one cell" (p.15 [3119]). Exact baseline
   placement is not stated. The Table 2 baseline speed of 6.84 µm/day matches the Fig 5
   "8.9 µm (immediately behind)" point (≈6.85, read from figure). This suggests the baseline is
   the immediately-behind cell, but that is an **inference**.
4. **Units of β.** β is per EC per hour, but B is written per site.
5. Table 2 column header "mean ± SD error" is ambiguous: SD or SEM? The Fig 5 caption says
   "standard deviations". (Arithmetic favours SEM; §8b Q13.)
6. **Parameter set of Table 2 / Fig 6** *(audit 2026-10-13)*. Figs 3 and 5 use Table 1 "except
   γe = 0.7 and γt = 0.8". The Fig 6 caption, whose panels are the four Table 2 stromal
   compositions, says "Parameters are given in Table 1". Since W1 (14.2 ± 2.44, SD) and Table 2
   (14.20 ± 0.70) are the same ensemble (0.70 × √12 = 2.42), Table 2 is taken as the 0.7/0.8 set
   and the Fig 6 caption as an omission.

### 7.2 Conflicts with Bauer 2009
See spec 05 §7.3 for the full comparison table. Key differences:
- time scale (1 h vs 1 min per MCS);
- kT 0.01 vs 2.5;
- every J and γ value;
- chemotaxis: tip-only (−1.5×10⁵) vs all ECs (≈−1.6×10⁶);
- the continuity term: absent in 2007, α = 300 in 2009;
- tissue cells: present in 2007, absent in 2009;
- matrix: 37% at 0–180° vs ≈40% at −90..90°;
- recruitment: absent in 2007, present in 2009;
- degradation: baseline in 2007, experiment-only in 2009;
- proliferating cells: non-migrating in 2007, migrating in 2009;
- speed units: µm/day vs µm/h.

### 7.3 Questions for the authors (Yi Jiang)
1. Pixel size and lattice geometry? Does "second nearest neighbors" mean the Moore (8) neighbourhood,
   or only the diagonal/second shell? Which neighbourhood was used for the adhesion energy?
2. Is 1 MCS = 1 h correct (vs 1 min in 2009)? What was the total run length in MCS for the 16.6 d
   snapshots?
3. How was the "leading" tip cell identified, and could the tip role transfer? In the baseline,
   which cell(s) proliferated and how many? Was it exactly one cell immediately behind the tip?
4. Tip degradation: at what rate, which sites, and what did degraded matrix become?
5. In Eq 3, which site is x and which is x'? Was the term applied only when the tip cell gains a
   site, or also when it loses one?
6. Was copying restricted so that only EC σ values propagate? The text says ECM, tissue and fluid
   "do not … actively invade".
7. Tissue cells: count, size in pixels, placement algorithm (the figures look like a jittered
   grid), and whether each had its own ID and target volume.
8. Fibre generation: angle set within 0–180°, bundle length, overlap handling.
9. Steep-gradient experiment: what right-boundary condition replaced V = S (no-flux or V = 0)?
10. PDE scheme and time step. Was B applied per EC site with β per site or per cell?
11. Is the dissertation code or input deck available?

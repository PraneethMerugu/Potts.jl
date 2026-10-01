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
| Tissue cells | "roughly the same size as an endothelial cell", "immobile", "more difficult to invade than matrix fibers and interstitial fluid". Number and placement are **UNSPECIFIED** (Fig 2 shows ≈30 squares ≈7–8 µm on a jittered grid, read from figure). | 07 p.6 [3110]; Fig 2 p.5 |
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

| ID | Target | Source | Type | Proposed tolerance |
|---|---|---|---|---|
| W1 | Sprout diameter 14.2 ± 2.44 µm (mean ± SD), 1–2 cells wide (baseline) | 07 p.9 [3113] | Quant | 11–18 µm |
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
   "standard deviations".

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

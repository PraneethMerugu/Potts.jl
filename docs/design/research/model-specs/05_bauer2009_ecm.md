# 05 — Bauer, Jackson & Jiang 2009: ECM topography and sprouting angiogenesis

**Citation.** Bauer AL, Jackson TL, Jiang Y (2009). *Topography of Extracellular Matrix Mediates
Vascular Morphogenesis and Migration Speeds in Angiogenesis.* PLoS Comput Biol 5(7): e1000445.
**DOI:** 10.1371/journal.pcbi.1000445
**PDF:** `docs/references/05_Bauer2009_PLoSCB_ECM-topography-angiogenesis.pdf` (18 pp.)

**Citation convention.** `(05 p.N, …)` = PDF page N; for this PLoS paper the PDF page equals the
printed page number. Every value below was read from the PDF text (`pdftotext -layout`), and the
equations, Table 1 and Table 2 were checked against the page images (glyphs such as γ, χ, ±, −
come out garbled in the text extraction). Values described as "read from figure" are approximate
readings off plotted curves.

**Parent model.** This paper extends Bauer et al. 2007 (ref. [19]; spec `07_bauer2007_sprouting.md`)
and says all parameters were **recalibrated** (05 p.5, §Parameter calibration: "there are a different
number of parameters, which necessitates recalibration of all the parameters"). Do not mix the
2007 and 2009 parameter sets; see §7.3.

---

## 1. Model summary

2D cellular Potts model (CPM) of one capillary sprout growing from a parent vessel (left boundary)
toward a tumour-supplied VEGF line source (right boundary). The stroma is modelled explicitly as
matrix-fibre sites and interstitial-fluid sites. Endothelial cells (ECs) come in three phenotypes:
tip, stalk and proliferating. The model adds these features to the 2007 model: stalk-cell
chemotaxis, recruitment of cells from the parent vessel, a BFS continuity constraint, and optional
tip-cell matrix degradation (05 p.4 §Cellular model; p.11 §degradation). The studies vary fibre
density ρ, fibre alignment, patterned cords and degradation.

---

## 2. Mechanics

### 2.1 Lattice, domain, time
| Item | Paper content | Source |
|---|---|---|
| Dimension | "The model is two-dimensional." | 05 p.2 §Cellular model |
| Domain | 166 µm × 106 µm (x × y) | 05 p.3 Fig 1 caption and text above Eq 2; axis ticks 0/82.8/166 and 0/52.9/106 in Figs 1, 3, 5, 7 |
| Conflicting domain statement | "a domain 100 µm by 160 µm" | 05 p.6 §Model validation (see §7) |
| Lattice spacing (µm/pixel) | **UNSPECIFIED**. No pixel size is stated anywhere. VEGF source is in "pg/pixel" (Table 1). | 05 p.4 Table 1 |
| Lattice geometry | **UNSPECIFIED** (square vs hex is not stated). Fibre angles 0, ±30, ±45, ±60, 90° "most closely approximates a triangular lattice", but this describes the fibre network, not the CPM lattice. | 05 p.9 |
| Neighbourhood (copy targets / energy) | **UNSPECIFIED** in 2009. The 2007 parent uses "unlike second nearest neighbors" (07 p.7). | — |
| Time unit | "1 Monte Carlo step is equivalent to 1 minute", calibrated so that the 18 h cell cycle matches | 05 p.5 §Parameter calibration |
| MCS definition | Not restated in 2009. 2007: n proposals per MCS, n = number of lattice sites (07 p.7). | — |
| Run length | "over a 14 hour period" (validation); "approximately 14 hours" (density sweeps) → 840 MCS (derived) | 05 p.6, p.7 |
| Replicates | "an average of at least 10 independent simulations" (Fig 1A says "10") | 05 p.6; p.3 Fig 1 caption |

### 2.2 Acceptance rule
Metropolis: P = 1 if ΔE < 0; P = e^{−ΔE/kT} if ΔE ≥ 0 (unnumbered equation, 05 p.2). kT = 2.5 E
(Table 1, 05 p.4).

### 2.3 Hamiltonian — Eq. 1 (05 p.2)

E = Σ_sites J_{τ,τ'}(1 − δ_{σ,σ'}) + Σ_cells γ_τ (a_σ − A^T_σ)² + Σ_sites χ_σ ΔV + Σ_cells α(1 − δ_{a_σ, a'_σ})

| Term | Definition in paper | Source |
|---|---|---|
| Adhesion | J_{τ,τ'} is the binding energy between constituent types τ ∈ {e, m, f} (EC, matrix, fluid). (1 − δ_{σ,σ'}) means the energy "only accrues at cell surfaces". | 05 p.2 Eq 1 |
| Growth constraint | γ_τ = membrane elasticity; a_σ = current volume; A^T_σ = target volume. "For proliferating cells, the target volume is double the initial volume." | 05 p.2–3 |
| Chemotaxis | χ_σ < 0 is the "effective chemical potential"; the term is proportional to the local VEGF gradient ΔV and depends on phenotype. The 2009 paper gives no site-level formula for ΔV. 2007 Eq 3: ΔE_chem = μ_σ[V(x) − V(x')], where x' and x are "the two neighboring lattice sites randomly selected during one trial update" (07 p.7). | 05 p.3; 07 p.7 Eq 3 |
| Continuity | α penalty, applied when a'_σ ≠ a_σ. a'_σ is "a breadth first search count of the number of continuous lattice sites occupied by that endothelial cell". α = 300 E/L, "fixed". | 05 p.3; Table 1 p.4 |

Notes on the terms:
- **Continuity** is an energy term (a soft penalty) evaluated with an exact BFS. It is stated only
  for ECs ("that endothelial cell", 05 p.3). The paper does not say whether the BFS is run on the
  pre- or post-copy configuration or which connectivity (4 or 8) it uses. **UNSPECIFIED**.
- **Matrix and fluid** behave as generalized cells: "they are each collectively identified by the
  same ID and are therefore always like neighbors" (05 p.14 §Sensitivity). They have volume
  elasticities γ_m and γ_f (Table 1). The paper says results "do not depend on the compressibility
  properties of the matrix fibers or interstitial fluid … since the total mass of these ECM
  components is conserved" (05 p.14). The target volumes for the matrix and fluid collectives are
  **UNSPECIFIED**. The natural reading is that each target equals its initial total, but this is
  not stated.
- **J_mm, J_ff**: the adhesion term never fires inside a collective because every site carries the
  same ID. The paper marks both "I" (insensitive) for this reason (05 p.14). The text calls the
  fluid–fluid value "J_ss", but Table 1 names it J_ff.
- **Sign of chemotaxis**: χ_σ < 0 (05 p.3), and the phenotype values in Table 1 are −1.45χ, −1.42χ
  and −1.40χ with χ = 1.11·10⁶ > 0. Whether ΔV means V(target) − V(source) or the reverse is
  **UNSPECIFIED** in 2009. The 2007 Eq 3 form V(x) − V(x') with μ < 0 gives favourable energy when
  the copy moves up-gradient, if x is the target and x' the source (07 p.7).
- The paper does not say which of the two sites (or which cell) the chemotaxis term is evaluated
  for when an EC copies into matrix or fluid, or when matrix or fluid copies into an EC. The
  expression "Σ_sites χ_σ ΔV" is summed over sites with χ indexed by the cell. **UNSPECIFIED**.

### 2.4 Cell phenotypes and rules
| Rule | Paper content | Source |
|---|---|---|
| Initial condition | "a single activated endothelial cell ∼10 µm in diameter that has budded from the parent vessel located adjacent to the left hand boundary" | 05 p.4 |
| Activation | "once a cell senses a threshold concentration of VEGF, given by v_a, it becomes activated"; v_a = 0.0001 pg (fixed) | 05 p.5; Table 1 |
| Tip cell | "assign it the highest chemotactic coefficient"; "do not proliferate". Tip χ = −1.45χ. Identification rule (e.g. leading cell) is **UNSPECIFIED** in 2009. 2007 says "the leading endothelial cell" (07 p.8). | 05 p.5; Table 1 |
| Stalk cell | Non-proliferating migrating cells; "assigned a lower … chemotactic coefficient"; χ = −1.42χ | 05 p.5; Table 1 |
| Proliferating cell | "located behind the sprout tip and increase in size as they move through an 18 hour cell cycle clock"; can still migrate; χ = −1.40χ. They stop moving only in the final stage (mitosis rounding, from a personal communication). The paper does not implement or quantify that final stage. | 05 p.5; Table 1 |
| Which cells proliferate | **UNSPECIFIED**: no rule is given for which ECs are proliferating vs stalk. | — |
| Division | Implied by the target-volume doubling and the 18 h clock. No mechanics are stated in 2009. 2007: division when doubled in size and one complete cycle is done; one daughter keeps the parent ID (07 p.8). In the 14 h runs, "before any cells in the sprout complete their cell cycle" means **no division occurs**. | 05 p.3, p.5, p.6 |
| Cell-cycle clock init | Baseline: "cell cycle clock is set to zero for newly recruited cells". Variant: random init; "We observe no differences". | 05 p.6 |
| Apoptosis | "we do not model endothelial cell apoptosis" | 05 p.5 |
| Recruitment | "a new cell is added to the base of the sprout when and where the previous cell detaches from the parent vessel wall (left boundary of the simulation domain)". It is cell–cell-adhesion dependent. 15–20 cells are typically recruited. The detachment criterion, the new cell's size and shape, and whether it starts as stalk are **UNSPECIFIED**. | 05 p.4–5; p.6 |
| Matrix degradation (only in the §Degradation experiments) | "allowing the tip cell to degrade ∼(0.55 µm)² of matrix each minute"; "a cell will degrade matrix only if matrix is present". What degraded matrix becomes (fluid?) and which matrix sites are chosen are **UNSPECIFIED**. | 05 p.11 |
| ECM | Static: "we do not model ECM rearrangement or dynamic matrix fiber cross-linking" | 05 p.4 |
| Update order | "At every time step, the discrete and continuous models feedback on each other" (05 p.2). "During the simulation, the VEGF field is updated iteratively with cell uptake information" (05 p.4). The exact per-MCS order is in 2007 (07 p.8, §Hybridization): 1 MCS of CPM, then recompute B, then solve Eq, then update lattice. Its application to 2009 is inferred. | 05 p.2, p.4 |

### 2.5 VEGF field — Eq. 2 (05 p.3)
∂V/∂t = D∇²V − λV − B(x, y, V)

| Item | Paper content | Source |
|---|---|---|
| BCs | V = 0 at left, V = S at right, periodic in y | 05 p.3 |
| Initial field | "We initialize the simulation by establishing the steady state solution to Eq. 2" | 05 p.3 |
| Uptake B | "A complete description … has been previously published [19]". Not restated. 2007 form (07 p.6): B = β if β ≤ V and (x,y) ⊂ EC; B = V if 0 ≤ V < β and (x,y) ⊂ EC; 0 otherwise. | 05 p.3; 07 p.6 |
| D | Constant; ECM effects on diffusion are neglected on purpose (see Discussion p.16) | 05 p.3 |
| Numerical scheme, grid, dt, sub-steps per MCS | **UNSPECIFIED** | — |
| Cell sensing | "VEGF data is processed by the cells at the cell membrane" | 05 p.4 |

### 2.6 Initial matrix layouts
| Layout | Paper content | Source |
|---|---|---|
| Random fibres (baseline) | "randomly distributing 1.1 µm thick bundles of individual collagen fibrils at random discrete orientations between −90 and 90 degrees". The discrete set is 0°, ±30°, ±45°, ±60°, 90°. Default ρ ≈ 0.40 ("approximately 40% of the total stroma"), heterogeneous. Bundle length is **UNSPECIFIED**. | 05 p.5; p.9 |
| Density ρ | "ratio of the interstitium occupied by matrix molecules to total tissue space, 0 ≤ ρ ≤ 1" | 05 p.5 |
| Aligned matrices | 0° (parallel to gradient), 90° (perpendicular), "0 & 90°" (horizontal+vertical) at ρ ∈ {0.2, 0.4, 0.6} | 05 p.9–10, Fig 4 |
| Patterned cords | (A) random fibres + horizontal cords 7.2 µm thick; (B) horizontal 7.2 µm cords only; (C) horizontal 2.2 µm; (D) vertical 2.2 µm; (E) crosshatched ±45°. Cord spacing is **UNSPECIFIED** (visible only in Fig 5). | 05 p.11, Fig 5 p.12 |
| Topographical-only test | Fig S2: no chemotaxis, no cell–cell contact (supplement, not in our PDF) | 05 p.7, p.17 |

---

## 3. Parameters

### 3.1 Stated (Table 1, 05 p.4, unless noted)
| Symbol | Value | Units | Meaning | Range / sensitivity | Source |
|---|---|---|---|---|---|
| D | 3.6×10⁻⁴ | cm²/h | VEGF diffusion | — | Table 1 (ref [58]) |
| λ | 0.6498 | h⁻¹ | VEGF decay | — | Table 1 |
| β | 0.06 | pg/EC/hr | VEGF uptake (max per EC per time) | — | Table 1 |
| S | 0.035 | pg/pixel | VEGF at right boundary | — | Table 1 |
| v_a | 0.0001 | pg | Activation threshold | fixed | Table 1 |
| J_ee | 30 | E/L | EC–EC | [10, 50] | Table 1 |
| J_ef | 76 | E/L | EC–fluid | I | Table 1 |
| J_em | 66 | E/L | EC–matrix | [46, 76] | Table 1 |
| J_ff | 71 | E/L | fluid–fluid | I | Table 1 |
| J_fm | 85 | E/L | fluid–matrix | I | Table 1 |
| J_mm | 85 | E/L | matrix–matrix | I | Table 1 |
| γ_e | 0.8 | E/L⁴ | EC elasticity | [0.3, 3] | Table 1 |
| γ_m | 0.5 | E/L⁴ | matrix elasticity | I | Table 1 |
| γ_f | 0.5 | E/L⁴ | fluid elasticity | I | Table 1 |
| χ | 1.11·10⁶ | E/conc | chemotactic sensitivity (base) | [10⁴, 10⁷] | Table 1 |
| χ_tip | −1.45 χ | E/conc | tip-cell potential | — | Table 1 |
| χ_stalk | −1.42 χ | E/conc | stalk-cell potential | — | Table 1 |
| χ_prolif | −1.40 χ | E/conc | proliferating-cell potential | — | Table 1 |
| α | 300 | E/L | continuity penalty | fixed | Table 1 |
| kT | 2.5 | E | Boltzmann temperature | [0.25, 11] | Table 1 |
| cell cycle | 18 | h | EC cycle duration | — | 05 p.5 |
| A^T (proliferating) | 2 × initial volume | L² | target volume | — | 05 p.2–3 |
| initial EC diameter | ∼10 | µm | initial cell size | — | 05 p.4 |
| fibre bundle thickness | 1.1 | µm | — | — | 05 p.5 |
| ρ (default) | ≈0.40 | — | matrix fraction | swept 0.05–0.975 | 05 p.5 |
| degradation rate | ∼(0.55 µm)² per min | µm²/min | tip-cell matrix removal | — | 05 p.11 |
| 1 MCS | 1 | min | time conversion | — | 05 p.5 |
| run length | ≈14 | h | — | — | 05 p.6–7 |
| Fig S1 variant | J_{ee,em,ef} = {42, 76, 66}, χ_tip = 1.55χ, χ_{stalk,prolif} = 1.45χ (signs as printed) | — | elongated-cell variant | — | 05 p.17 Fig S1 legend |

### 3.2 Derived (not stated; derivation shown)
| Quantity | Value | Derivation |
|---|---|---|
| D in model-friendly units | 600 µm²/min | 3.6×10⁻⁴ cm²/h × 10⁸ µm²/cm² ÷ 60 min/h |
| λ per MCS | 1.083×10⁻² min⁻¹ | 0.6498 h⁻¹ ÷ 60 |
| VEGF decay length √(D/λ) | ≈235 µm | √(3.6×10⁻⁴/0.6498) cm = 0.0235 cm. It exceeds the 166 µm domain, so the steady profile is near-linear, consistent with Fig 1B (0 → ~0.032 pg across the domain). |
| Absolute tip χ | −1.61×10⁶ E/conc | −1.45 × 1.11×10⁶ |
| Absolute stalk χ | −1.58×10⁶ | −1.42 × 1.11×10⁶ |
| Absolute prolif χ | −1.55×10⁶ | −1.40 × 1.11×10⁶ |
| Run length in MCS | ≈840 | 14 h × 60 MCS/h |
| Cycle length in MCS | 1080 | 18 h × 60. It exceeds the run length, so no division happens (consistent with p.6). |
| Degradation area | ≈0.3025 µm²/min | (0.55)². Converting to sites/MCS needs the pixel size, which is UNSPECIFIED. |

Note: the tip |χ| (1.61×10⁶) sits at the stated break-up threshold "χ > 1.6·10⁶ cells are pulled
apart" (Table 3, p.15). The Table 3 thresholds evidently refer to the base χ, not the scaled
value. See §7.

### 3.3 UNSPECIFIED (needed for reproduction)
Pixel size; lattice type and neighbourhood order; energy/copy neighbourhood; MCS sweep definition;
target volume/area of ECs in pixels (only "∼10 µm diameter"); target volumes of the matrix and fluid
collectives; tip/stalk/proliferating assignment rule; recruitment trigger and new-cell geometry;
PDE discretisation and time step; B(x, y, V) per-site vs per-cell application; fibre bundle
length(s); the random fibre placement algorithm (overlap rules); degradation site-selection and
the product state; how ρ is measured; the seed/ensemble generator; boundary handling for the CPM
(periodic in y for cells? walls at x?).

---

## 4. Verification of prior claims

| # | Prior claim | Verdict | Evidence |
|---|---|---|---|
| 1 | 2D | CONFIRMED | 05 p.2 |
| 2 | 166×106 µm | CONFIRMED | 05 p.3 Fig 1 caption. Note the conflicting "100 µm by 160 µm" on p.6. |
| 3 | ~1 µm/pixel | NOT IN PAPER | No pixel size stated anywhere. |
| 4 | 1 MCS = 1 min | CONFIRMED | 05 p.5 |
| 5 | 14 h runs | CONFIRMED | 05 p.6, p.7 |
| 6 | T = 2.5 | CONFIRMED (as kT = 2.5 E) | Table 1 p.4 |
| 7 | Kinds EC (tip/stalk/proliferating), matrix fibre, interstitial fluid | CONFIRMED | 05 p.3–5 |
| 8 | Matrix and fluid as generalized cells with volume elasticities 0.5 | CONFIRMED | γ_m = γ_f = 0.5 (Table 1); "collectively identified by the same ID" (p.14) |
| 9 | H = ΣJ(1−δ) + Σc_τ(a−A_T)² + χ_σΔV + α[a′≠a] | CORRECTED (notation) | Eq 1 p.2 uses γ_τ (not c_τ). The chemotaxis term is Σ_sites χ_σΔV and the continuity term is Σ_cells α(1 − δ_{a_σ,a'_σ}). Structure confirmed. |
| 10 | BFS connected-component continuity | CONFIRMED | "breadth first search count", p.3 |
| 11 | α = 300 | CONFIRMED | Table 1 (300 E/L, fixed) |
| 12 | J_ee=30, J_ef=76, J_em=66, J_ff=71, J_fm=85, J_mm=85 | CONFIRMED | Table 1 p.4 |
| 13 | c_e = 0.8 | CONFIRMED (as γ_e = 0.8 E/L⁴) | Table 1 |
| 14 | χ = 1.11e6 scaled per phenotype | CONFIRMED | Tip −1.45χ, stalk −1.42χ, proliferating −1.40χ (Table 1) |
| 15 | ∂V/∂t = D∇²V − λV − B(x,y,V) | CONFIRMED | Eq 2 p.3 |
| 16 | Dirichlet V=0 left, V=S right, periodic y | CONFIRMED | p.3 |
| 17 | Activation threshold v_a | CONFIRMED | 0.0001 pg, p.5, Table 1 |
| 18 | Fibres 1.1 µm bundles at discrete angles, density ρ | CONFIRMED | p.5, p.9 (0, ±30, ±45, ±60, 90°) |
| 19 | Proliferating 18 h clock, target volume doubles then divide | CORRECTED (partly) | 18 h clock and doubling confirmed (p.2–3, p.5). The division rule is not described in 2009, and no cell divides in the 14 h runs (p.6). The division mechanics come from 2007 (07 p.8). |
| 20 | Recruitment from parent vessel | CONFIRMED | p.4–5 |
| 21 | Tip cells degrade ~(0.55 µm)²/min matrix → fluid | CORRECTED (partly) | The rate is confirmed (p.11). Conversion "→ fluid" is NOT IN PAPER; the product of degradation is never stated. Degradation is active only in the degradation experiments. |
| 22 | Speed ~16 µm/h vs 10–21 measured | CONFIRMED (with caveat) | Table 2 p.6: 16.0 ± .6 µm/hr "averaged over 14 hours" vs 10.4–20.8 ± 4.2 µm/hr [39]; also 10.4 ± .2 µm/hr at 10 h vs 14 µm/hr [26]. This is internally inconsistent with Fig 1A (≈10 µm/hr at 14 h) and with "160 µm in ≈15.6 h" (≈10.3 µm/h, p.6). See §7. |
| 23 | Biphasic peak at ρ ≈ 0.3–0.4 | CONFIRMED | Fig 2A caption and p.9: peak at ρ = 0.35 |
| 24 | Branching/anastomosis at intermediate ρ | CORRECTED (refined) | Branching in 0.20–0.30 (p.9, Fig 2B); anastomosis "only seen at" ρ = 0.25 (p.9); no branching above ρ = 0.35 (p.9, p.13). Degradation induces branching at ρ = 0.4 (Fig 7C). |
| 25 | Degradation raises speed at high ρ, lowers at low ρ (±37%) | CORRECTED | +≈37% at ρ = 0.7 and 0.975 at 14 h (p.11). The slow-down at ρ = 0.2 is not quantified as 37% (Fig 6: ≈8.5 → ≈8.3 µm/h, read from figure). At ρ = 0.4 the effect is significant only at 0–5 h. Fig 6 caption: anti-angiogenic for ρ ≤ 0.25, pro-angiogenic above 0.4. |

**Tally (05): CONFIRMED 19, CORRECTED 5, NOT IN PAPER 1** (25 claims). Claim 21 is partly NOT IN
PAPER (the "→ fluid" product) and is counted as CORRECTED.

---

## 5. Validation targets

Policy: the targets are ensemble and statistical, with no bitwise parity. Use ≥10 replicates per
condition (the paper uses ≥10, p.6). "Qual" means qualitative (a pattern must appear); "Quant"
means a numeric match within the tolerance.

| ID | Target | Source | Type | Proposed tolerance |
|---|---|---|---|---|
| V1 | Mean extension-speed vs time curve decreasing from ≈30 µm/h (first 2 h) to ≈10 µm/h at 14 h; ≈10.4 µm/h at 10 h | Fig 1A p.3; p.6 text; Table 2 | Quant | Mean speed at 10 h and at 14 h within ±25% (7.8–13 µm/h at 10 h). Monotone decrease after 1 h. |
| V2 | Sprout ≈ one cell diameter wide at 7.8 h; thickness 16.2 ± 2.4 µm | p.6; Table 2 | Quant | 12–21 µm |
| V3 | EC count in sprout: ≈3 at 2 h, 5–6 at 4 h; 15–20 recruited over the run | p.6 | Quant | 2 h: 2–4; 4 h: 4–7; total recruited 12–23 |
| V4 | Cell size 15–40 µm | Table 2 | Quant | Cell length within 10–45 µm |
| V5 | Sprout reaches the right boundary in ≈15.6 h (160 µm) | p.6 | Quant | 12–20 h |
| V6 | Speed vs ρ (Fig 2A) at 2, 5, 10, 14 h: maximum at ρ = 0.35 (≈16 µm/h at 2 h; ≈10.2 µm/h at 14 h, read from figure); reduced above 0.6; no speeds reported for ρ < 0.1 or > 0.8 | Fig 2A p.7; p.9 | Quant+Qual | Argmax over the grid {0.1…0.8} in [0.3, 0.4]. Ratio speed(0.35)/speed(0.8) at 14 h > 1.3 (figure: ≈10.2/6.3 ≈ 1.6). |
| V7 | Branching incidence vs ρ (Fig 2B): "Likely" peak near ρ = 0.2; rare/absent at ρ ≥ 0.4 | Fig 2B p.7; p.9 | Qual (semi-quant) | Branch frequency (Kearney definition: bud ≥10 µm from the main body) highest in [0.15, 0.30] and ≈0 for ρ ≥ 0.4 |
| V8 | Sprout thickness vs ρ: ρ < 0.15 thin (<1 cell); intermediate 10–15 µm; ρ = 0.7 20–25 µm | p.9; Fig 2B | Quant | ±30% per band |
| V9 | Morphology panel at 14 h: ρ = 0.05 unstable/elongated; 0.2 branch; 0.25 loop; 0.6 linear; 0.7 wide and slow; 0.975 no invasion | Fig 3 p.8 | Qual | Presence of each phenotype in a majority of replicates |
| V10 | Alignment (Fig 4): at ρ = 0.4 and 0.6, speed 0° > random ≳ 0&90° > 90°; at ρ = 0.4, 90° ≈5.5 µm/h vs ≈10 µm/h for 0° at 14 h (read from figure); at ρ = 0.2, no strong effect | Fig 4 p.10 | Quant+Qual | Ordering must hold (0° vs 90°) with p < 0.05. 90°/0° speed ratio at ρ = 0.4 and 14 h in 0.4–0.75. |
| V11 | Patterned cords: cells elongate along cords; recruited counts A 15, B 11, C 3, D 19, E 19; sprout in E ≈2 cells thick | p.11; Fig 5 p.12 | Quant (counts) + Qual | Rank order C < B < A < D ≈ E, each count within ±40% |
| V12 | Degradation (Fig 6): +≈37% speed at 14 h for ρ = 0.7 and 0.975; ρ = 0.2 slightly slower with degradation; ρ = 0.4 effect only at 0–5 h | p.11; Fig 6 p.13 | Quant | Relative increase at ρ ∈ {0.7, 0.975} in 20–55%. Sign negative at ρ = 0.2. |
| V13 | ρ = 0.975 + degradation: tunnel forms and a sprout develops (vs full inhibition without) | Fig 7A,B p.14; Fig 3F | Qual | Sprout length > 40 µm with degradation and < 10 µm without |
| V14 | ρ = 0.4 + degradation: a branch emerges | Fig 7C p.14 | Qual | Branching in ≥ some replicates (the paper shows one example) |
| V15 | χ sweep (Fig 8): speed ≈1–2 µm/h for χ ≤ 5.5×10⁵, rising steeply to ≈10–11 µm/h at 1.1–1.5×10⁶; no migration below 10⁴; break-up above 1.6×10⁶ | Fig 8 p.15; Table 3 | Quant+Qual | Sigmoidal shape; midpoint in [7, 10]×10⁵ |
| V16 | Sensitivity table (Table 3): J_ee < 10 unrealistic shapes; J_ee > 50 cells migrate away; J_em ≤ 46 distorted; J_em = 200 immobile; γ_e = 3 tip detachment; kT < 0.25 dissociation | Table 3 p.15; p.13–14 | Qual | Each qualitative regime reproduced |
| V17 | VEGF field at 7.8 h: 0 → ≈0.032 pg across x; gradient ≈1–2×10⁻⁴ pg with larger values at the tip and leading edges | Fig 1B,C p.3 | Quant | Boundary values exact (BCs). Max gradient location at the sprout leading edge. |
| V18 | Cell-cycle clock init (0 vs random) has no effect on speed, morphology or recruitment | p.6 | Qual | Difference not significant |

---

## 6. Required general features

| ID | Need in this model | Specific use |
|---|---|---|
| G1 @transition/@create/@retire + rand(Bernoulli) | Phenotype switching (inactive → activated at v_a; tip / stalk / proliferating); @create for recruitment of a new EC at the parent-vessel boundary; @create for division (2007 mechanics); random clock init (uniform, not Bernoulli) | 05 p.4–6 |
| G2 shape descriptors in energies | Not needed in energies. Cell orientation (axis of elongation) is an observable only (→ G12). | 05 p.11 |
| G3 contact-scope direction/position + lagged vector vars | Chemotaxis term needs the field at both source and target sites and the phenotype of the moving cell: ΔE = χ_σ[V(x) − V(x')] | 05 Eq 1; 07 Eq 3 |
| G4 generalized connectivity (local/soft/exact-BFS) | **Soft, exact-BFS** penalty α(1 − δ_{a,a'}) per EC. Must be a soft energy (not a hard reject) because kT < 0.25 behaviour depends on it (Table 3). | 05 Eq 1 p.3 |
| G5 symbolic field BCs + SteadyState solver + coarse grid | Dirichlet left/right, periodic y. SteadyState solve for t = 0. Transient step per MCS thereafter. | 05 Eq 2 p.3 |
| G6 conservative per-cell secrete/uptake | B(x, y, V) = min(β, V) on EC sites (2007 form). Needs per-cell or per-site semantics (see §7). | 05 p.3; 07 p.6 |
| G7 site conversion @convert | Tip-cell matrix degradation: matrix sites converted (product unspecified) at a budget of (0.55 µm)²/min, only where matrix is present. Needs a per-cell rate budget. | 05 p.11 |
| G8 pluggable proposal law + time in scope | Standard Metropolis; neighbourhood order must be configurable (2007 uses 2nd-nearest). Optional mask so that only ECs act as copy sources, if adopted from 2007 (07 p.7). | 05 p.2 |
| G9 per-cell component protocol | Minimal: an 18 h cell-cycle clock per EC (a scalar counter). No intracellular ODE. | 05 p.5 |
| G10 cluster-scope quantities / sibling / retain_empty | (a) Matrix and fluid as **collective generalized cells** (one ID each, multiply-connected, with a volume constraint on the total). They need retain_empty-like persistence and no connectivity constraint. (b) Identify the "leading" cell (tip) = sprout-cluster extremum. (c) Distance of the sprout base to the tip for the speed metric. | 05 p.14; p.6 |
| G11 ordered relationships + angle energies | Not needed | — |
| G12 observables | Tip displacement from the sprout base / time; sprout thickness (width profile); branch detection (bud ≥10 µm from the main body, Kearney definition p.7); loop (anastomosis) detection; recruited-cell count; per-cell elongation axis; local ECM density under the sprout (p.11–12); fibre-network percolation (parent vessel → source connectivity, p.9); VEGF gradient maps | 05 p.6–12 |
| G13 initial layout generators | Random fibre bundles (thickness 1.1 µm, discrete angle set, fill to ρ); aligned-only sets (0°, 90°, 0&90°); patterned cords (thickness, spacing, orientation, crosshatch); a single initial EC bud at the left wall | 05 p.5, p.9–11 |
| G15 (proposed) coupled operator-split schedule | Interleave N MCS of CPM with a PDE transient step of physical Δt and per-cell rule evaluation, with explicit unit conversion (1 MCS = 1 min here). Also required by Jiang 2005 (1/4 MCS + 45 min). Justification: two of the three models need a configurable sub-MCS schedule. Fold it into G8 if the time-in-scope work already covers it. | 05 p.2, p.4 |

---

## 7. Ambiguities, conflicts, questions

### 7.1 Internal inconsistencies in the 2009 paper
1. **Domain:** 166 × 106 µm (Fig 1 caption and axes) vs "100 µm by 160 µm" (p.6).
2. **Speed averaged over 14 h:** Table 2 gives 16.0 ± .6 µm/hr. Fig 1A plots ≈10 µm/hr at 14 h,
   and p.6 says 160 µm in ≈15.6 h (≈10.3 µm/h). One of these is either a different averaging
   (for example the mean of instantaneous speeds) or an error.
3. **Replicates:** "at least 10" (p.6) vs "10" (Fig 1 caption). Minor.
4. **χ range:** Table 1 gives [10⁴, 10⁷]. Table 3, Fig 8 and the text give dissociation above
   1.6·10⁶. The text on p.15 also writes "10⁴ ≤ J_em ≤ 1.6·10⁶", which is evidently a typo for χ.
5. **Table 3 "0.3 ≤ γ_e → large cells"** is evidently a typo for γ_e ≤ 0.3.
6. **kT direction:** p.15 says "Increasing kT decreases the probability that an update adding to
   system energy will be accepted". That contradicts P = e^{−ΔE/kT}, where increasing kT
   *increases* acceptance. The observed effect (faster sprouts with larger kT) is stated anyway.
7. **Phenotype χ vs break-up threshold:** tip |χ| = 1.61×10⁶ already exceeds the stated "pulled
   apart" threshold 1.6×10⁶. So the threshold must refer to the base χ multiplier. This needs
   confirmation.
8. **Fig S1 legend** lists χ_tip = 1.55χ, which is written without a minus sign, unlike Table 1.

### 7.2 Underspecified mechanics (blocking exact reproduction)
- Pixel size and lattice geometry. The degradation rate "(0.55 µm)²" and bundle thickness 1.1 µm
  (= 2 × 0.55) would fit a 0.55 µm pixel. That is only a hypothesis and **must not be adopted
  without author confirmation**.
- Neighbourhood order for copy attempts, adhesion energy and the BFS.
- How the tip, stalk and proliferating roles are assigned during a run (leading cell? fixed at
  creation?). Can the tip role move to another cell?
- Recruitment trigger ("detaches from the parent vessel wall"): what counts as detached, where the
  new cell is placed, and its initial size.
- Degradation: which matrix sites are removed (adjacent to the tip? random?), what they become
  (fluid?), and whether the fluid/matrix target volumes are adjusted afterwards.
- Target volumes of the matrix and fluid collectives, and whether they change with degradation.
- B(x, y, V) granularity: β is "per EC per hr" but is applied on sites (2007 formula). Per-site
  application would multiply uptake by the cell area.
- PDE solver, grid and number of PDE steps per MCS.
- CPM boundary conditions (periodic in y for cells as well as the field? walls?).

### 7.3 Conflicts between Bauer 2007 and Bauer 2009
| Aspect | 2007 | 2009 |
|---|---|---|
| Time scale | 1 MCS = 1 h (07 p.8) | 1 MCS = 1 min (05 p.5) |
| kT | 0.01 | 2.5 |
| J values | J_ee=1, J_ef=32, J_em=16, J_ff=35, J_fm=35, J_mm=5 (+ tissue-cell J) | J_ee=30, J_ef=76, J_em=66, J_ff=71, J_fm=85, J_mm=85 |
| Elasticities | γ_e=1.0 (0.7 in figs), γ_m=0.4, γ_f=0.1, γ_t=1.2 | γ_e=0.8, γ_m=γ_f=0.5 |
| Chemotaxis | Tip only, μ = −1.5×10⁵ | Tip, stalk and proliferating all chemotactic, ≈−1.6×10⁶ |
| Continuity term | Absent | α = 300 BFS |
| Tissue cells | Present | Absent |
| Fibre fraction / angles | 37%, 0–180° | ≈40%, −90…90° (0, ±30, ±45, ±60, 90) |
| Recruitment | Absent (proliferation behind tip) | Present |
| Proliferating cells | Non-chemotactic, non-migrating | Can migrate |
| Speeds | ≈5–7.7 µm/**day** | ≈10–16 µm/**hour** |
| Degradation | Always on in baseline (+5%) | Only in dedicated experiments |

### 7.4 Questions for the authors (Yi Jiang)
1. What was the lattice spacing (µm per pixel), and was the lattice square or hexagonal? Which
   neighbourhood order was used for copy proposals, for adhesion, and for the BFS continuity check?
2. Which is the correct domain size: 166 × 106 µm or 100 × 160 µm? How many pixels?
3. Table 2 gives "16.0 ± .6 µm/hr averaged over 14 hours", but Fig 1A shows ≈10 µm/hr at 14 h. How
   was each computed?
4. How was the tip cell designated and updated (the leading EC by max x of centre of mass?)? How
   were cells assigned to stalk vs proliferating?
5. Recruitment: what exact condition triggered adding a new EC at the left wall, with what initial
   volume and shape, and with what phenotype?
6. Degradation: were degraded matrix sites relabelled as interstitial fluid? Which sites (contact
   with the tip)? How was (0.55 µm)²/min converted to sites per MCS? Were the matrix and fluid
   target volumes updated?
7. What were the target volumes and volume constraints for the matrix and fluid collectives? Were
   they one ID each for the whole domain?
8. Is χ_σΔV evaluated as χ_σ(V_target − V_source) for the cell gaining the site only, or also for
   the cell losing it? Was it applied when matrix or fluid gains a site from an EC?
9. Was B(x, y, V) applied per lattice site of an EC, or per EC (β per cell per hour)? What PDE
   scheme and step size were used, and how many PDE steps per MCS?
10. How were fibre bundles generated: bundle length, overlaps allowed, and how ρ was measured
    (site fraction)?
11. Do the Table 3 χ thresholds refer to the base χ (before the 1.40–1.45 multipliers)?
12. Is the source code (or a parameter file) from the dissertation still available?

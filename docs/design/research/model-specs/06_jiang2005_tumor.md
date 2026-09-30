# 06 — Jiang, Pjesivac-Grbovic, Cantrell & Freyer 2005: multiscale avascular tumour

**Citation.** Jiang Y, Pjesivac-Grbovic J, Cantrell C, Freyer JP (2005). *A Multiscale Model for
Avascular Tumor Growth.* Biophysical Journal 89(6): 3884–3894.
**DOI:** 10.1529/biophysj.105.060640
**PDF:** `docs/references/06_Jiang2005_BiophysJ_multiscale-avascular-tumor.pdf` (11 pp.)
**External erratum (not in our PDFs):** Biophys J 2006 91(2):775, PMC1483097. Table 1 glucose
metabolic rate for proliferating cells should be **216**, not 162. We record it as supplied by the
task brief; the erratum text itself was not read. See §3.4.

**Citation convention.** `(06 p.N [JJJJ], …)`: N = PDF page, JJJJ = journal page
(PDF p.1 = 3884, so JJJJ = 3883 + N). Eq 4, Fig 2 (network), Fig 3 (flow chart), Table 1 and the
Appendix equations were read from page images rendered at 300–600 dpi. Values described as "read
from figure" are approximate.

---

## 1. Model summary

A three-scale model of EMT6/Ro multicellular tumour spheroids.

| Scale | Model | Scope |
|---|---|---|
| Cellular | 3D large-Q Potts model | Growth, division, death, adhesion |
| Subcellular | Boolean protein network | Controls G1→S arrest |
| Extracellular | Five reaction–diffusion equations | O₂, glucose, lactate, generic growth promoter, generic inhibitor |

Runs start from one cell. The paper calibrates to growth at 0.08 mM O₂ / 5.5 mM glucose and then
predicts growth at 0.28 mM / 16.5 mM (06 p.1 abstract; p.3 [3886] §Multiscale cellular model).

---

## 2. Mechanics

### 2.1 Lattice, units, time
| Item | Paper content | Source |
|---|---|---|
| Dimension | "partitions the three-dimensional space into domains of cells and cell medium" | 06 p.3 [3886] |
| Cell size | "A typical cell occupies 27 lattice sites". Maximal cell volume: "4 × 4 × 4 voxels = 1.2 × 10³ µm³". | 06 p.3 [3886]; p.5 [3888] |
| Lattice extent | **UNSPECIFIED** in voxels. Fig 4 axes run to ≈1300 µm (read from figure). Fig 8 discussion: the tumour can reach "a size comparable to the total lattice size". | 06 p.6 [3889] Fig 4; p.8 [3891] |
| Neighbourhood | "changed to the value of one of its unlike neighbors' ID". Order is **UNSPECIFIED**. | 06 p.3 [3886] |
| MCS | "as many trial lattice updates as the total number of lattice sites" | 06 p.3 [3886] |
| Time conversion | "4 MCS = 12 h … one MCS is equal to 3 h". The cell cycle has 16 stages; each stage is 1/4 MCS ≈ 3/4 h. | 06 p.5 [3888]; p.4 [3887] §Simulation |
| ECM | "The extracellular matrix in the spheroids is neglected." | 06 p.3 [3886] |

### 2.2 Acceptance — Eq. 2 (06 p.3 [3886])
p = 1 if ΔH < 0; p = e^{−ΔH/(k_b T)} if ΔH ≥ 0. T is the "effective cell temperature". The value
of T (or k_bT) is **UNSPECIFIED**.

### 2.3 Hamiltonian — Eq. 1 (06 p.3 [3886])
H = Σ_{lattice sites} J_{τ(S₁)τ(S₂)} [1 − δ(S₁, S₂)] + Σ_cells γ (v − V^T)²

Details stated in the paper:
- Types τ are proliferating (P), quiescent (Q), necrotic (N) and medium (M). "our cell type refers
  to the proliferating status of the cell … not the tissue type" (06 p.3 [3886]).
- There is **no surface or perimeter term**.
- Medium: "Medium does not have a target volume" (06 p.3 [3886]).
- Necrotic: it "has a target volume set to its current volume, and a large γ-value corresponding
  to a rigid body". "Every time a cell dies, its volume is added to the target volume of the
  necrotic core". The necrotic core is a "special cell with ID 0" (06 p.3 [3886]; p.4 [3887]).
- Quiescent: "once a cell turns quiescent, we set the target volume to its current volume and
  increase its volume constraint to four times its current value" (06 p.6 [3889]).
- Proliferating: "We set the target volume to be twice the initial cell volume". γ "usually had
  value between 1 and 3" (06 p.3 [3886]; p.6 [3889]).
- J values: J_PP = J_PQ = 28, J_PN = 24, J_PM = 16, J_QN = 22, J_QM = 14, J_NM = 12 (06 p.6 [3889]).
  J_QQ and J_NN are **UNSPECIFIED**. J_NN is moot if the necrotic core is a single ID.
- "The tumor growth results would not be different if we used one single value for all coupling
  coefficients" (06 p.6 [3889]).

### 2.4 Cell cycle, protein network and state rules

**Cell cycle** (06 p.4 [3887] §Simulation):
- 16 stages: G1 = 6 stages, S = 6 stages, G2+M = 4 stages combined.
- The cycle is "∼12 h in an exponentially growing monolayer culture".
- "cells typically double their volume in four Monte Carlo steps".

**Boolean network — Fig 2** (06 p.4 [3887]), read from the 600-dpi image:
- Nodes: GSK3b, TGFb, SCF (top tier); SMAD (SMAD3+SMAD4); P15 (stands for p15/p16/p18/p19);
  P27 (includes p57); P21; CyCD·CDK4; CyCE·CDK2; Rb; E2F.
- Edges (→ stimulatory, ⊣ inhibitory, as drawn):
  - TGFb → SMAD
  - SMAD → P15
  - SMAD → P27
  - SCF → P27
  - SCF → P21
  - GSK3b ⊣ CyCD·CDK4
  - P15 ⊣ CyCD·CDK4
  - P27 ⊣ CyCD·CDK4
  - P27 ⊣ CyCE·CDK2
  - P21 ⊣ CyCE·CDK2
  - CyCD·CDK4 ⊣ Rb
  - CyCE·CDK2 ⊣ Rb
  - **Rb → E2F** (drawn with an arrowhead)
  - E2F → S phase
- The caption says "The G1 phase consists of six stages (six levels of grayscale)". The six tiers
  are {GSK3b, TGFb, SCF}, {SMAD}, {P15, P27, P21}, {CyCD·CDK4, CyCE·CDK2}, {Rb}, {E2F}. Our
  reading (an **inference**) is that one tier is evaluated per G1 stage.

**Factor level — Eq. 4** (06 p.4 [3887]), verified from the image:
Factor level = (1 + e^{−α((gF − ihF)/initGF − θ)})^{−1}
- gF and ihF are the local growth and inhibitory factor concentrations.
- initGF is the growth factor concentration in the surrounding medium.
- θ is the "factor level threshold". α is "a free parameter".
- The values of α and θ are **UNSPECIFIED**.

**Node update rule** (06 p.4 [3887]):
- "If the factor level is above the threshold, the protein is turned on under two circumstances:
  if all the links pointing to it are stimulatory and all the proteins at the beginning of the
  links are on; or if all the links are prohibitory and the proteins at the beginning of the links
  are off. All other situations would turn off the protein."
- "If the factor level is below the threshold, this factor level is the probability that a protein
  will be turned on or off."
- "If the outcome of this Boolean regulatory network is zero, i.e., protein E2F is off, the cell
  undergoes cell-cycle arrest or turns quiescent."
- Initial condition: "a single tumor cell in the center of the lattice with its first set of
  proteins turned on (top tier in Fig. 2)" (06 p.4 [3887]).
- Top-tier node states in later cycles and in daughters (who "inherit all properties") are
  **UNSPECIFIED**.

**Per-iteration loop** (Fig 3 flow chart, 06 p.5 [3888]; text 06 p.4 [3887]):
1. "Update cell numbers on cellular lattice for ¼ MCS".
2. "Solve chemical equations for 45 minutes".
3. "Factors determine protein expression levels for 1 step" (for cells in G1).
4. Decision diamonds, in this order:
   - **E2F = 1?** No → cell becomes quiescent. Yes → next.
   - **Chemicals favorable?**
     - No → "Cell proliferating?" Yes → **Cell dies**. No → **Cell becomes quiescent**. (Flow chart
       as drawn. The text says the opposite; see §7.1.)
     - Yes → next.
   - **Volume check?** No → quiescent. Yes → next.
   - **Time to divide?** Yes → next. The No branch is not drawn; presumably the cell continues to
     the next stage.
   - **Cell on surface?** Yes → **Cell shedding**. No → **Division into 2 cells**.
   - Loop back to step 1.
5. Text version of the same loop: "First, it checks the local chemical environment: a proliferating
   cell decides whether to proceed to the next stage … or become quiescent, while a quiescent cell
   decides whether to become necrotic because of hostile environment. Second, it checks the current
   cell volume … Finally, a proliferating cell checks whether it has fulfilled the requirements to
   divide" (06 p.4 [3887]).

**Other state rules:**

| Rule | Paper content | Source |
|---|---|---|
| Volume checkpoints | "check points at the end of each phase … If the cell does not increase its volume proportional to the time it has spent in that and previous phases, it will become quiescent". The tolerance is **UNSPECIFIED**. | 06 p.4 [3887] |
| Division | "Only when the cell clock reaches the cell-cycle duration and the cell volume reaches the target volume". "Cell division is simply reassigning half of the volume to a new cell ID. The daughter cells inherit all properties of their parent." The split geometry is **UNSPECIFIED**. | 06 p.3 [3886] |
| Necrosis thresholds | "oxygen concentration below 0.02 mM, glucose concentration below 0.06 mM, and lactate concentration above 8 mM are conditions for cell necrosis". Whether they combine with AND or OR is **UNSPECIFIED** (see §7). | 06 p.6 [3889]; p.8 [3891] |
| Quiescence effects | "When a cell turns quiescent, it reduces its metabolism and stops its growth." Re-entry into proliferation is **UNSPECIFIED**. | 06 p.4 [3887] |
| Necrotic secretion | "For a short period of time (24 h) after the cell dies via necrosis, the cell produces inhibitory factors and some waste." Appendix: "secretes inhibitory factors at the rate of 0.1 ml/h and waste at the rate of 10 mM/h." | 06 p.4 [3887]; p.10 [3893] |
| Shedding | "if a proliferating cell is at the surface of a spheroid of radius >0.03 cm, it can shed away with a 20% shedding probability. Shed cells disappear". Per Fig 3 this is evaluated at division time. The experimental rate is "∼218 cells per square millimeter of spheroid surface per hour". | 06 p.4–5 [3887–3888] |
| Apoptosis | Not modelled | 06 p.3 [3886] |

### 2.5 Extracellular fields
**Eq. 3** (06 p.3 [3886]): ∂u/∂t = D∇²u + f(x, y, z), with f depending on the state of the cell.

**Appendix** (06 p.9 [3892]):
- The five equations:
  - ∂u_O2/∂t = D_O2∇²u_O2 + a
  - ∂u_n/∂t = D_n∇²u_n + b
  - ∂u_w/∂t = D_w∇²u_w + c
  - ∂u_gf/∂t = D_gf∇²u_gf + d
  - ∂u_if/∂t = D_if∇²u_if + e
- Rate modulation after each solve:
  - a = a₀ (u_O2 − u^T_O2)/(u^O_O2 − u^T_O2)
  - b = b₀ (u_n − u^T_n)/(u^O_n − u^T_n)
  - c = C₀ (a/a₀ + b/b₀)/2
  - u^O is the optimal concentration: 0.28 mM for O₂, 5.5 mM for glucose.
  - u^T is the threshold concentration, "determined iteratively" (i.e. the necrosis thresholds of
    §2.4, 0.02 / 0.06 mM, by our reading).
- Boundary conditions at the tumour–medium interface: u_O2 = u⁰_O2, u_n = u⁰_n, u_w = 0,
  u_gf = 1, u_if = 0.
- "At time zero, no chemical is present inside the tumor (single cell)."
- Coarse grid: "coarse-graining the cell lattice by a factor of 4 … the concentration within an
  individual cell is the average of the concentrations on the grid points within that cell"
  (06 p.10 [3893]).
- Diffusion constants are uniform inside the spheroid (06 p.4 [3887]).
- The solver is not described beyond "a fast three-dimensional PDE solver" credited in the
  Acknowledgments (06 p.10 [3893]). **Method UNSPECIFIED.**
- Coupling: this is a **transient** solve of 45 min per 1/4 MCS, not a quasi-steady state
  (Fig 3; 06 p.4 [3887]).
- Physical conversion: "we take into account the space occupied by extracellular matrix that is
  omitted". The correction factor is **UNSPECIFIED** (06 p.5 [3888]).
- Growth and inhibitory factors are on a relative scale: "the medium supplies 100% of required
  growth factors, and no inhibitory factors are present outside" (06 p.5 [3888]).
- Lactate production is 1.5 × glucose consumption. Quiescent metabolic rates are ≈ half of
  proliferating rates (06 p.5 [3888]).

---

## 3. Parameters

### 3.1 Stated
| Symbol | Value | Units | Meaning | Source |
|---|---|---|---|---|
| a₀ (P) | 108 | "mM/h/cm³" (as printed) | O₂ consumption, proliferating | Table 1 p.5 [3888] |
| a₀ (Q) | 50 | same | O₂, quiescent | Table 1 |
| a₀ (N) | 0 | same | O₂, necrotic | Table 1 |
| b₀ (P) | 162 (**216 per external erratum**) | same | glucose, proliferating | Table 1; erratum |
| b₀ (Q) | 80 | same | glucose, quiescent | Table 1 |
| b₀ (N) | 0 | same | glucose, necrotic | Table 1 |
| C₀ (P) | 240 | same | waste (lactate) production, proliferating | Table 1 |
| C₀ (Q) | 110 | same | waste, quiescent | Table 1 |
| C₀ (N) | 0 | same | waste, necrotic (but see necrotic secretion) | Table 1 |
| d (P / Q / N) | 1 / 0.5 / 0 | %/h/cm³ | growth factor rate | Table 1 |
| e (P / Q / N) | 0 / 1 / 2 | %/h/cm³ | inhibitory factor rate | Table 1 |
| D_O2 | 5.94 × 10⁻² | cm²/h | | Table 1 |
| D_n (glucose) | 1.52 × 10⁻³ | cm²/h | | Table 1 |
| D_w (lactate) | 2.124 × 10⁻³ | cm²/h | | Table 1 |
| D_gf | 10⁻⁶ | cm²/h | | Table 1 |
| D_if | 10⁻⁶ | cm²/h | | Table 1 |
| J_PP, J_PQ | 28 | — | | 06 p.6 [3889] |
| J_PN | 24 | — | | same |
| J_PM | 16 | — | | same |
| J_QN | 22 | — | | same |
| J_QM | 14 | — | | same |
| J_NM | 12 | — | | same |
| γ (P) | 1–3 ("usually") | — | volume constraint | 06 p.6 [3889] |
| γ (Q) | 4 × its prior value | — | | 06 p.6 [3889] |
| γ (N) | "large" | — | rigid | 06 p.3 [3886] |
| V^T (P) | 2 × initial volume | voxels | | 06 p.3 [3886] |
| V^T (Q) | current volume at the transition | voxels | | 06 p.6 [3889] |
| typical cell | 27 | voxels | | 06 p.3 [3886] |
| max cell volume | 4×4×4 = 64 voxels = 1.2 × 10³ µm³ | | length conversion | 06 p.5 [3888] |
| 1 MCS | 3 | h | | 06 p.5 [3888] |
| stage | 1/4 MCS ≈ 3/4 h | | | 06 p.4 [3887] |
| cycle | 16 stages (G1 6, S 6, G2/M 4) ≈ 12 h | | | 06 p.4 [3887] |
| PDE interval | 45 | min per iteration | | Fig 3 |
| necrosis O₂ | < 0.02 | mM | | 06 p.6 [3889] |
| necrosis glucose | < 0.06 | mM | | same |
| necrosis lactate | > 8 | mM | | same |
| u^O_O2, u^O_n | 0.28, 5.5 | mM | optimal concentrations | 06 p.9 [3892] |
| shedding | 20% probability for a proliferating surface cell when R > 0.03 cm | | | 06 p.5 [3888] |
| necrotic secretion window | 24 | h | | 06 p.4 [3887] |
| necrotic IF secretion | 0.1 | "ml/h" (as printed) | | 06 p.10 [3893] |
| necrotic waste secretion | 10 | mM/h | | 06 p.10 [3893] |
| coarse-grain factor | 4 | — | PDE grid | 06 p.10 [3893] |
| medium BCs (calibration) | O₂ 0.08 mM, glucose 5.5 mM | | | 06 p.6 [3889] Fig 5 |
| medium BCs (prediction) | O₂ 0.28 mM, glucose 16.5 mM | | | 06 p.7 [3890] Fig 8 |
| u_gf, u_if at the surface | 1, 0 | relative | | 06 p.9 [3892] |
| experimental O₂ / glucose ranges | 0.08–0.28 mM; 1.6–16.5 mM | | culture | 06 p.2 [3885] |

### 3.2 Derived
| Quantity | Value | Derivation |
|---|---|---|
| Voxel edge | ≈2.66 µm | (1.2×10³ µm³ / 64)^{1/3} = 18.75^{1/3} |
| Voxel volume | 18.75 µm³ | 1200 / 64 |
| Coarse PDE spacing | ≈10.6 µm | 4 × 2.66 µm |
| Shedding radius in voxels | ≈113 | 300 µm / 2.66 µm |
| D_O2 in lattice units | ≈2.5 × 10⁶ voxel²/MCS | 5.94×10⁻² cm²/h × 10⁸ µm²/cm² × 3 h/MCS = 1.78×10⁷ µm²/MCS; ÷ (2.66 µm)² = 7.08 µm² per voxel² gives ≈2.5×10⁶ voxel²/MCS. The O₂ field is therefore effectively quasi-static on the 45 min step, which is why an implicit or fast solver is needed; the paper still integrates it transiently. |
| Chemical time per MCS | 3 h (4 × 45 min) | Fig 3 |
| Stoichiometry check | 1.5 × 162 = 243 ≈ 240 (waste, P); 1.5 × 80 = 120 vs 110 (Q) | Table 1 values and the stated 1.5 ratio. **With the erratum (216) the waste value would be 324, not 240.** See §7. |
| Quiescent/proliferating ratio | O₂ 50/108 = 0.46; glucose 80/162 = 0.49 (80/216 = 0.37 with the erratum) | the stated "approximately equal to half" |

### 3.3 UNSPECIFIED (blocking)
T (temperature); α and θ in Eq 4; lattice extent; neighbourhood order; J_QQ and J_NN; exact γ for
P; the value of "large" γ for N; initial cell volume (27? 32?); the volume-checkpoint tolerance;
whether the necrosis conditions combine with AND or OR; quiescence reversibility; the definition of
"surface cell"; the division split plane; the PDE scheme and time step; ECM volume-correction factor
in the unit conversion; signs of Table 1 rates (consumption vs production; inferred below); the
growth factor rate units (%/h/cm³) and their mapping to the PDE source term; necrotic inhibitor
secretion ("0.1 ml/h") vs Table 1 (2 %/h/cm³); how a cell's rate a is applied to the coarse-grid
nodes it covers.

Inferred sign convention (not explicit): O₂, glucose and GF are consumed (a, b, d < 0 in Eq 3).
Waste and IF are produced (c, e > 0). The basis is the text on p.4 [3887] and p.5 [3888] ("glucose
consumed", "waste produced", "quiescent cells produce a small amount of inhibitory factors").

### 3.4 External erratum
Biophys J 2006 91(2):775, PMC1483097 (external, not in our PDFs): Table 1 glucose rate for
proliferating cells = **216**, not 162. We did not read the erratum text, so any other corrections
it contains are unknown. The reference model should use 216 and keep a flag that switches back to
162 for replicating the published figures. Which value produced the published Figs 5–8 is unknown;
see §7.

---

## 4. Verification of prior claims

| # | Prior claim | Verdict | Evidence |
|---|---|---|---|
| 1 | 3D lattice | CONFIRMED | 06 p.3 [3886] |
| 2 | H = J + λ_v(v−V_T)² + λ_s(s−S_T)² | CORRECTED | Eq 1 has adhesion + volume only; **no surface term** (06 p.3 [3886]) |
| 3 | States proliferating/quiescent/necrotic/medium | CONFIRMED | 06 p.3 [3886] |
| 4 | Boolean G1/S network (growth promoter, inhibitor → cyclin/Rb/E2F-like nodes) decides arrest | CORRECTED | The network (Fig 2) is GSK3b, TGFb, SCF → SMAD → P15/P27/P21 ⊣ CyCD·CDK4 / CyCE·CDK2 ⊣ Rb → E2F. The growth and inhibitory factors are **not nodes**: they enter through the sigmoidal factor level (Eq 4), which gates deterministic vs stochastic node updates. E2F off → arrest/quiescence (06 p.4 [3887]). |
| 5 | Reaction–diffusion for O₂, glucose, waste, promoter, inhibitor | CONFIRMED | Eq 3; Appendix (06 p.9 [3892]) |
| 6 | Quasi-steady relative to the cell cycle | CORRECTED | Transient: "Solve chemical equations for 45 minutes" after every 1/4 MCS (Fig 3; 06 p.4 [3887]) |
| 7 | State-dependent consumption | CONFIRMED | Table 1 plus concentration-dependent scaling (Appendix) |
| 8 | Necrosis on a nutrient/metabolic threshold | CONFIRMED | O₂ < 0.02 mM, glucose < 0.06 mM, lactate > 8 mM (06 p.6 [3889]) |
| 9 | Necrotic cells shrink | CORRECTED | Necrotic cells are **rigid**: target = current volume and large γ. Dead cells join the necrotic core (ID 0), whose target volume grows by the dead cell's volume (06 p.3 [3886]; p.6 [3889]). No shrinkage is described. |
| 10 | 20% shedding at the surface once R > 0.03 cm | CONFIRMED | For proliferating surface cells; at division per Fig 3 (06 p.5 [3888]) |
| 11 | Fitted to EMT6/Ro spheroids at 0.08 mM O₂ and 5.5 mM glucose | CONFIRMED | 06 p.6 [3889]; p.7 [3890] |
| 12 | Validation: growth curve (Gompertz) | CONFIRMED | Figs 5, 8; y = y₀ exp(a(1 − exp(−bt))) (06 p.6 [3889]) |
| 13 | Viable rim thickness | CONFIRMED | Fig 7 |
| 14 | Necrotic onset | CONFIRMED | Fig 7; "initial rapid expansion of necrotic core" (06 p.7 [3890]) |
| 15 | Phase fractions | CONFIRMED | Fig 6 |
| 16 | Other O₂/glucose conditions | CONFIRMED | Fig 8: 0.28 mM O₂ / 16.5 mM glucose (one example condition shown) |
| E | Erratum: glucose P rate 216, not 162 | RECORDED (external) | Not in our PDF (the PDF shows 162); external erratum Biophys J 2006 91(2):775, PMC1483097 |

**Tally (06): CONFIRMED 12, CORRECTED 4, NOT IN PAPER 0** (16 claims; the erratum is recorded
separately).

---

## 5. Validation targets

The paper's simulation curves are **single runs** (06 p.8 [3891]: "the simulation shows the values
for an individual spheroid"). Our reference should use an ensemble (≥10 seeds, random initial
cell-cycle stage as the authors suggest) and compare ensemble means with the experimental points
and the published simulation.

| ID | Target | Source | Type | Proposed tolerance |
|---|---|---|---|---|
| T1 | Layered structure P / Q / N at 2, 10, 18 d: 2 d proliferating aggregate; 10 d quiescent core; 18 d necrotic core | Fig 4 p.6 [3889] | Qual | Onset of quiescence before 10 d; necrotic core present by 18 d |
| T2 | Growth at 0.08 mM O₂ / 5.5 mM glucose: exponential for ≈5–7 d, saturation after ≈28–30 d | 06 p.6 [3889]; Fig 5 | Quant | Transition time within ±2 d |
| T3 | Gompertz initial doubling time: sim vs experiment differ by < 1 h, both in 8.6–9.5 h | 06 p.6 [3889] | Quant | Fitted doubling time 8–10.5 h |
| T4 | Saturation size: the published sim overestimates experiment by ≈2× (cells) and ≈2.5× (volume). Experimental saturation ≈3–4×10⁴ cells, volume ≈3×10⁸ µm³ (read from Fig 5) | 06 p.6 [3889]; Fig 5 | Quant | Within a factor of 3 of experiment (match the published sim within ±50%) |
| T5 | Cell number at 20 d ≈ 8×10⁴ (sim, Fig 5a, read from figure) | Fig 5a | Quant | ±50% |
| T6 | Cell-cycle fractions vs time: G1 rises from ≈30–50% to ≈75% (sim ≈78%, read from figure); S falls to ≈20%; G2 ≈ constant (≈5–10%) | Fig 6 p.7 [3890]; p.6 [3889] | Quant | G1 fraction at ≥15 d in 65–85%; S at ≥15 d in 12–28% |
| T7 | Viable rim vs diameter: after onset, rim ≈ constant at ≈140–150 µm (sim) vs ≈125–160 µm (exp). Necrosis onset near 550–600 µm diameter with an initial rapid necrotic-core expansion (rim ≈275 µm at onset, read from figure) | Fig 7 p.7 [3890]; p.7 text | Quant | Plateau rim 110–180 µm; necrosis-onset diameter 450–700 µm |
| T8 | Necrotic core grows at ≈ the same rate as the spheroid late in growth | 06 p.7 [3890] | Qual | d(R_N)/d(R) → ≈1 |
| T9 | Prediction at 0.28 mM O₂ / 16.5 mM glucose with no retuning: growth curves track experiment to ≈15 d; sim saturates early (≈5×10⁴ cells vs experiment rising to ≈2×10⁵ at 24 d), attributed to a lattice-size artefact | Fig 8 p.8 [3891]; p.8 text | Quant+Qual | Match the experiment within a factor of 2 to 15 d. Do **not** try to reproduce the lattice-size artefact; use a larger lattice. |
| T10 | Predicted GF/IF diffusivities 10⁻⁷ / 10⁻⁶ cm²/h give the best fit | 06 p.8 [3891] vs Table 1 | Qual | Sensitivity sweep should show the fit degrading outside 10⁻⁷–10⁻⁶ |
| T11 | Adhesion insensitivity: a single J for all pairs gives the same growth | 06 p.6 [3889] | Qual | Growth curves within the ensemble spread |
| T12 | O₂ profiles consistent with microelectrode measurements (ref 30); no numbers given | 06 p.9 [3892] | Qual | Not usable without ref 30 data |

---

## 6. Required general features

| ID | Need | Specific use |
|---|---|---|
| G1 @transition/@create/@retire + rand(Bernoulli) | P→Q (E2F off, volume check, unfavourable chemistry), Q→N (hostile chemistry), @create for division (half volume, inherits properties), @retire for shedding with Bernoulli(0.2) | 06 p.4–5 [3887–3888] |
| G2 shape descriptors | Not needed | — |
| G3 contact-scope | Not needed (no chemotaxis). A "surface cell" test needs contact-with-medium → G10/G12. | — |
| G4 connectivity | Not required. The necrotic core is a single ID that is **allowed to be disconnected**, so the core must *not* enforce connectivity on it. | 06 p.3 [3886] |
| G5 BCs + solver + coarse grid | Dirichlet on medium-kind sites (a **region/kind-defined, moving** boundary: the tumour–medium interface); coarse grid with factor 4; transient solve of 45 min per 1/4 MCS (not SteadyState); five coupled fields | Appendix p.9–10 [3892–3893] |
| G6 per-cell uptake/secretion | State-dependent and concentration-scaled rates (a, b, c formulas); per-cell averaging of grid values; time-windowed necrotic secretion (24 h) | Appendix |
| G7 @convert | Not needed as site conversion (death relabels a whole cell → G14) | — |
| G8 proposal law + time in scope | Fractional-MCS sweeps (1/4 MCS) interleaved with the PDE solve and rule evaluation | Fig 3 |
| G9 per-cell component protocol | **Boolean network** with 11 nodes (Fig 2), staged tier updates in G1, stochastic updates gated by the Eq 4 factor level; a 16-stage cycle clock | 06 p.4 [3887] |
| G10 cluster-scope / sibling / retain_empty | Sibling: division halves the volume and copies all state. retain_empty: the necrotic core ID 0 must exist before any death (or be created on first death). Spheroid radius (cluster scope) for the shedding gate R > 0.03 cm. | 06 p.3–5 |
| G11 ordered relationships | Not needed | — |
| G12 observables | Counts by state; spheroid volume and radius; necrotic-core radius; viable-rim thickness; cell-cycle phase fractions (G1/S/G2M from stage); Gompertz fit; radial concentration profiles | Figs 4–8 |
| G13 initial layout | One cell at the lattice centre, top-tier proteins on | 06 p.4 [3887] |
| **G14 (new) absorb/merge-retire** | Retire a cell by relabelling its sites into an **existing collective cell** (necrotic core, ID 0) and adding its volume to the collective's target volume. Justification: not expressible as @retire-to-medium (the sites must stay occupied and rigid) or as @convert (whole-cell, target-volume bookkeeping). It is general enough for any "graveyard/clot/scar" collective. | 06 p.3 [3886] |
| G15 (proposed, see spec 05) | Operator-split scheduling: 1/4 MCS ↔ 45 min PDE ↔ rules | Fig 3 |

---

## 7. Ambiguities, conflicts, questions

### 7.1 Internal conflicts
1. **Unfavourable chemistry, P vs Q branch.** Fig 3 routes a *proliferating* cell to "Cell dies"
   and a non-proliferating (quiescent) cell to "becomes quiescent". The text (06 p.4 [3887]) says a
   proliferating cell may become quiescent while a quiescent cell may become necrotic. The text is
   biologically coherent; the flow-chart labels look swapped.
2. **Rb → E2F polarity.** Fig 2 draws Rb → E2F as stimulatory. Combined with the stated update
   rule, E2F would then be on only when both cyclin complexes are *off*, i.e. when the CKIs are on.
   That is the opposite of the biology, where cyclin/CDK phosphorylates Rb and releases E2F. Either
   the Rb node means "active (hypophosphorylated) Rb" and the arrow should be a bar, or a node
   polarity was inverted in the figure. This blocks a faithful implementation.
3. **GF/IF diffusivities.** Table 1 gives 10⁻⁶ for both. The Discussion (06 p.8 [3891]) says
   "10⁻⁷ and 10⁻⁶ cm²/h, respectively" (growth, inhibitor). The same page cites an 80–90 kDa
   *inhibitor* with ≈1×10⁻⁷ cm²/h, which would put the inhibitor, not the promoter, at 10⁻⁷.
4. **Erratum vs stoichiometry.** With b₀ = 216 (erratum), C₀ = 240 no longer equals 1.5 × b₀
   (= 324), and Q/P ≈ 0.37 is no longer "approximately half". Either the waste value was also
   derived from 162, or the erratum changes only the printed value and not the simulations.
5. **Necrotic inhibitor secretion.** Table 1 gives 2 %/h/cm³; the Appendix gives "0.1 ml/h". The
   units are incompatible.
6. **Initial and typical cell volume.** A typical cell is 27 voxels and the maximal cell is 64
   voxels. "Target volume … twice the initial cell volume" implies an initial volume of 32, not 27.
7. **Consumption above optimal.** a = a₀(u − u^T)/(u^O − u^T) exceeds a₀ when u > u^O (for example
   glucose at 16.5 mM > 5.5 mM in Fig 8 gives b ≈ 3 b₀). The paper does not say whether this is
   capped.
8. Table 1 metabolic units "mM/h/cm³" are dimensionally odd (mM is already per volume). We need the
   intended units (probably per 10⁸ cells, or mmol/h/cm³ of cells).

### 7.2 Underspecified
- T, α, θ, J_QQ, the γ values, lattice size, neighbourhood order.
- Semantics of the below-threshold stochastic update ("probability that a protein will be turned
  on or off"): is it the probability of applying the Boolean rule, of flipping the node, or of
  turning it on?
- When the E2F check happens (every G1 stage, or only at the end of G1?).
- Top-tier node states (GSK3b, TGFb, SCF) after the first cycle.
- Necrosis conditions: AND or OR.
- Whether quiescence is reversible.
- The "surface" criterion for shedding; the timing of shedding (at division, per Fig 3).
- Mapping of the coarse grid onto cells for consumption; PDE solver and time step; the ECM
  correction factor in unit conversion.

### 7.3 Questions for the authors (Yi Jiang)
1. Values of T, α, θ, and the γ used for proliferating cells? The necrotic "large" γ? Lattice size
   in voxels?
2. Fig 2: should Rb → E2F be inhibitory? What exactly does each node's on-state mean? How are the
   top-tier nodes (GSK3b, TGFb, SCF) set after the first cycle and in daughters?
3. Eq 4 below threshold: is the factor level the probability of the node taking its rule output,
   of being on, or of flipping? Is the E2F check made every step or at the end of G1?
4. Fig 3 vs text: which state dies under unfavourable chemistry, P or Q? Are the three necrosis
   conditions combined with OR?
5. Erratum: did the published simulations use 162 or 216 for glucose? Should waste (240) and the
   quiescent glucose rate (80) change accordingly? What are the true units in Table 1?
6. Which GF/IF diffusivities produced Figs 5–8 (Table 1 gives 10⁻⁶ for both; the text gives 10⁻⁷
   for one)?
7. Necrotic secretion: 2 %/h/cm³ (Table 1) or 0.1 ml/h (Appendix)? How does it map to the PDE?
8. Volume checkpoint tolerance: what counts as "not grown proportional to the time"?
9. How was "a cell at the surface" defined (contact with medium)? Is shedding evaluated only at
   division?
10. Were a, b capped at a₀, b₀ for concentrations above optimal?
11. What PDE scheme (Toivanen & Dyadechko solver), time step and ECM-volume correction factor were
    used?
12. Is the 2005 code (or the later CompuCell/Bionet reimplementations) available for
    cross-checking?

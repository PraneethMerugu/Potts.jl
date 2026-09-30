# Questions for Sahar Jafari Nivlouei, Madjid Soltani and Rui Travasso: Jafari Nivlouei et al. 2021 (PLoS Comput Biol 17:e1009081)

Batch 1 — **draft, not sent.** The maintainer sends this personally. Citations point to
`docs/design/research/model-specs/11_multiscale.md` ("spec 11 §x"; 11a = this paper) and the
specs README ("specs README §4 N<n>").

---

Dear Dr. Jafari Nivlouei, Prof. Soltani and Prof. Travasso,

I am [Maintainer name], and I work on Potts.jl, an open-source Julia ecosystem for cellular
Potts models. We chose your multiscale tumour-growth and angiogenesis model as our reference
for coupling an intracellular Boolean network, the CPM and extracellular fields, and we are
reproducing it with full provenance: every equation and parameter is traced to a page, figure
or data cell, and every choice we make is listed in a public tutorial.

S1 Data has been very useful as a validation source. What we are missing is mainly on the
model side. Questions 1–6 block a reproduction; 7 is quick. We would be glad to reach an exact
reproduction together with you.

With thanks,
[Maintainer name]

---

## Blocking questions

### Q1 [B] The CompuCell3D project

- **Context.** The model is built on CompuCell3D (p.13), but no project files are linked; S1
  Data contains only plotted outputs (spec 11 §1, §7 item 12).
- **Question.** Could you share the CC3D project (XML and Python) used for the paper?
- **Our assumption.** Where the paper is silent we make documented, flagged choices.
- **What changes.** It would settle Q2–Q6 at once.

### Q2 [B] Chemotaxis strengths and neighbour order

- **Context.** Eqs 4–5 (p.9) give chemotaxis for migrating tumour cells (nutrient) and activated
  ECs (VEGF), but χ values are not in Table 2 and the sign convention is only "move towards
  higher concentration". The neighbour order for copies and adhesion is not stated (spec 11 §2A,
  §7 item 7).
- **Question.** What χ values and sign convention were used, and which neighbour order?
- **Our assumption.** χ_EC is calibrated to the sprout-speed curve (S1 Data, Fig 4) and
  χ_tumour to the equivalent-radius growth curve, both labelled as calibrations (specs README §4
  N3; spec 11 §5A V11a-2, V11a-5).
- **What changes.** Calibrated values become stated ones.

### Q3 [B] Hypoxia, necrosis and apoptosis rules

- **Context.** Hypoxic cells "reach the quiescent state", quiescent cells later become necrotic
  (p.14, p.18; Fig 6F), and apoptosis follows the Boolean output, but the quiescence threshold,
  the necrosis rule and delay, and how apoptotic cells are removed are not given (spec 11 §2A,
  §7 item 5).
- **Question.** What were these rules and thresholds?
- **Our assumption.** None fixed; S1 Data gives only outcome timing to calibrate against (spec 11
  §7 item 5).
- **What changes.** Tumour growth curves and the necrotic core.

### Q4 [B] Nutrient unit conversion

- **Context.** n is in pg/voxel while β and S_n are in mol/cell/s (Table 2). Table 4 restates
  β_P = 0.0252 mol/m³/s; the ratio implies a cell volume of ≈2.05 × 10³ μm³, which is our
  inference (spec 11 §7 item 1).
- **Question.** How was β converted to a per-voxel sink (for example divided by the voxels of a
  cell)?
- **Our assumption.** Per-cell conservative uptake, converted with the inferred cell volume,
  flagged (specs README §4 N2).
- **What changes.** The uptake magnitude, and so the hypoxic region and RTK switching.

### Q5 [B] Nutrient source: term or clamp?

- **Context.** Eq 7 (p.10) has a source term S_n on EC sites and also states a Dirichlet
  condition n|ECs = S_n (spec 11 §2A).
- **Question.** Which was implemented, and do new (sprouted) ECs also become sources (spec 11
  §7 item 2)?
- **Our assumption.** Clamp by default, source term as a variant (specs README §4 N1).
- **What changes.** Nutrient delivery by new vessels and the response to angiogenesis.

### Q6 [B] PDE solver

- **Context.** The solver, the number of diffusion steps per MCS and the Δt used with the
  physical D values are not stated; S1 Data gives only a 10-MCS (= 10 min) output cadence
  (spec 11 §2A, §7 item 3).
- **Question.** Which solver and time stepping were used?
- **Our assumption.** None fixed yet.
- **What changes.** Field dynamics between MCS, and so the timing of hypoxia and VEGF release.

## Quick question (non-blocking)

**Q7. β-catenin rule.** Does "Wnt Or Akt And Not cadherin AND Not APC" mean (Wnt ∨ Akt) ∧ ¬cad ∧
¬APC, or Wnt ∨ (Akt ∧ ¬cad ∧ ¬APC)? And should "RTK And Scr" read Src (spec 11 §7 item 9)? *We
use the Fig 3 lookup table at runtime and the full network only as a unit test, pending this
answer (specs README §4 N4).*

## Tutorial to share once public

`lib/PottsModels/reproductions/11_multiscale.jl` (planned, build step 10, following
TUTORIAL_TEMPLATE). Each answer becomes a dated changelog entry and a row of its deviations
table.

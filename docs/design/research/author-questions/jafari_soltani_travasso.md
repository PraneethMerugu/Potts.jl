# Questions for Sahar Jafari Nivlouei, Madjid Soltani and Rui Travasso: Jafari Nivlouei et al. 2021 (PLoS Comput Biol 17:e1009081)

Batch 1 — **draft, not sent.** The maintainer sends this personally. Internal traceability
is in the comment block at the end of the file.

---

Dear Dr. Jafari Nivlouei, Prof. Soltani and Prof. Travasso,

I am [Maintainer name], and I work on Potts.jl, an open-source Julia ecosystem for cellular
Potts models. We chose your multiscale tumour-growth and angiogenesis model as our reference
for coupling an intracellular Boolean network, the CPM and extracellular fields. We are
reproducing it with full provenance: every equation and parameter is traced to a page, figure
or data cell, and every choice we make will be listed in a tutorial that we will publish and
share with you.

S1 Data has been very useful for comparison. What we are missing is mainly on the model side.
Questions 1–6 block a reproduction; 7 is a quick confirmation. We would be glad to reach an
exact reproduction together with you.

## Blocking questions

### Q1 [B] The CompuCell3D project

- **Context.** The model is built on CompuCell3D (p.13), but no project files are linked; S1
  Data contains only plotted outputs.
- **Question.** Could you share the CC3D project (XML and Python) used for the paper?
- **Our assumption.** Where the paper is silent we make documented, flagged choices.
- **What changes.** It would settle Q2–Q6 at once.

### Q2 [B] Chemotaxis strengths and neighbour order

- **Context.** Eqs 4–5 (p.9) give chemotaxis for migrating tumour cells (nutrient) and activated
  ECs (VEGF), but the χ values are not in Table 2, and the sign convention is only "move towards
  higher concentration". The neighbour order for copies and adhesion is not stated.
- **Question.** What χ values and sign convention were used, and which neighbour order?
- **Our assumption.** χ_EC is calibrated to the sprout-speed curve (Fig 4 in S1 Data) and
  χ_tumour to the equivalent-radius growth curve, both labelled as calibrations.
- **What changes.** Calibrated values become stated ones.

### Q3 [B] Hypoxia, necrosis and apoptosis rules

- **Context.** Hypoxic cells "reach the quiescent state", quiescent cells later become necrotic
  (p.14, p.18; Fig 6F), and apoptosis follows the Boolean output. The quiescence threshold, the
  necrosis rule and delay, and how apoptotic cells are removed are not given.
- **Question.** What were these rules and thresholds?
- **Our assumption.** None fixed; S1 Data gives only the timing of outcomes to calibrate against.
- **What changes.** Tumour growth curves and the necrotic core.

### Q4 [B] Nutrient unit conversion

- **Context.** n is in pg/voxel, while β and S_n are in mol/cell/s (Table 2). Table 4 (p.17)
  restates β_P = 0.0252 mol/m³/s; the ratio implies a cell volume of ≈ 2.05 × 10³ μm³, which is
  our inference.
- **Question.** How was β converted to a per-voxel sink (for example, divided by the voxels of a
  cell)?
- **Our assumption.** Per-cell uptake that conserves mass, converted with the inferred cell
  volume, flagged.
- **What changes.** The uptake magnitude, and so the hypoxic region and RTK switching.

### Q5 [B] Nutrient source: term or clamp?

- **Context.** Eq 7 (p.10) has a source term S_n on EC sites and also states a Dirichlet
  condition n|ECs = S_n.
- **Question.** Which was implemented, and do new (sprouted) ECs also become sources?
- **Our assumption.** The clamp by default, the source term as a variant.
- **What changes.** Nutrient delivery by new vessels and the tumour's response to angiogenesis.

### Q6 [B] PDE solver

- **Context.** The solver, the number of diffusion steps per MCS and the Δt used with the
  physical D values are not stated; S1 Data gives only a 10-MCS (10 min) output interval.
- **Question.** Which solver and time stepping were used?
- **Our assumption.** None fixed yet.
- **What changes.** Field dynamics between MCS, and so the timing of hypoxia and VEGF release.

## Quick question (non-blocking)

**Q7. β-catenin rule.** Your Fig 3 table implies that "Wnt Or Akt And Not cadherin AND Not APC"
means Wnt ∨ (Akt ∧ ¬cadherin ∧ ¬APC). Is that right, and should "Scr" in "RTK And Scr" read
Src?

Once the reproduction is published, we will send you the tutorial. Each of your answers will be
recorded there with a dated entry.

With thanks,
[Maintainer name]

<!-- trace:
Q1: spec 11 §1, §7 item 12; README §5 Jafari item 1
Q2: spec 11 §2A (Eqs 4–5), §5A V11a-2, V11a-5, §7 item 7; specs README §4 N3; README §5 Jafari item 2
Q3: spec 11 §2A, §7 item 5; README §5 Jafari item 2
Q4: spec 11 §3A, §7 item 1; specs README §4 N2; README §5 Jafari item 3
Q5: spec 11 §2A (Eq 7), §7 item 2; specs README §4 N1; README §5 Jafari item 3
Q6: spec 11 §2A, §7 item 3, §9.1; README §5 Jafari item 3
Q7: spec 11 §7 item 9; specs README §4 N4; reading from the paper's Fig 3 table per review round 1; README §5 Jafari item 4
Tutorial (planned): 11_multiscale.jl, step 10
-->

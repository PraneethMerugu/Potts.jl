# Questions for Chiara Damiani, Alex Graudenzi and Davide Maspero: FBCA (J Cell Automata 15:75) and its diffusion extension (Fundam Inform 171:279)

Batch 1 — **draft, not sent.** The maintainer sends this personally. Internal traceability
is in the comment block at the end of the file. **Q2 is on HOLD**: the ACRI 2018 paper is closed
access and has no repository copy (see the pre-send checklist in README.md). Q1 was narrowed
after reading the Di Filippo 2016 supplementary model file.

---

Dear Dr. Damiani, Dr. Graudenzi and Dr. Maspero,

I am [Maintainer name], and I work on Potts.jl, an open-source Julia ecosystem for cellular
Potts models. We are reproducing FBCA — a CPM with a flux-balance problem solved for each cell
every MCS — with full provenance: every equation and parameter is traced to a page or figure,
and every choice we make will be listed in a tutorial that we will publish and share with you.
FBCA is the most ambitious coupling in our set, and we would like the reproduction to be exact.

Questions 1–5 block a reproduction; 6–9 are quick. We would be glad to work on this together
with you.

## Blocking questions

### Q1 [B] Code and the metabolic model

- **Context.** Both papers use MATLAB with the COBRA Toolbox (J Cell Automata 15, p.82; Fundam
  Inform 171, p.288) on HMR CORE (Di Filippo et al. 2016), with 272 reactions and 240
  metabolites. Neither paper links code or a model file. The core model in the Di Filippo et al.
  supplementary (the first spreadsheet, `mmc1.xls`, with the `biomass_synthesis` objective)
  has 274 reactions (28 of them exchange reactions) and 252 metabolites (15 of them
  extracellular), so it does not match those counts as we read it.
- **Question.** Which reactions and metabolites did you add, remove or merge relative to that
  file, and did any bounds or the biomass reaction change? Could you share the model file you
  used, and the MATLAB sources?
- **Our assumption.** The published `mmc1.xls` model, unchanged, with the count difference
  flagged.
- **What changes.** The per-cell linear programme itself, and so every metabolic phenotype.

### Q2 [B] [HOLD] Parameters taken from the ACRI 2018 paper

- **Context.** The Fundamenta Informaticae paper takes its defaults "as in [18]" (p.285), i.e.
  Graudenzi et al., ACRI 2018 (LNCS 11115), which we have not yet been able to consult.
- **Question.** What values of λ, k_BT, attempts per MCS and initial field values were used in
  the Fundamenta Informaticae simulations?
- **Our assumption.** None yet.
- **What changes.** The CPM layer and the initial nutrient fields of every scenario.

### Q3 [B] Starvation death

- **Context.** "cellular death by starving is the only way to remove cells" (Fundam Inform 171,
  p.282, p.285), but no criterion is given.
- **Question.** What triggers death: a threshold on v_b, an infeasible LP, a decrease of biomass,
  or something else?
- **Our assumption.** None yet.
- **What changes.** Population size and composition over time in all tissue scenarios.

### Q4 [B] The Eq 6 averaging operator

- **Context.** Diffusion is neighbourhood averaging, [N(l_i)] ← (D/|I|) Σ_{j∈I} [N(l_j)]
  (Fundam Inform 171, Eq 6, p.284). D is "chosen based on the nutrient species" but not given,
  the number of sweeps per MCS is not given, and for D ≠ 1 the operator does not conserve mass.
- **Question.** What D was used for each species, how many sweeps per MCS, and is D < 1 meant as
  a decay?
- **Our assumption.** The operator as written, with D a calibration parameter.
- **What changes.** Nutrient gradients around the vessels, hence the spatial phenotype maps.

### Q5 [B] Edge efflux

- **Context.** Unconsumed nutrients "are removed … through a constant flux value" at the lattice
  edges (Fundam Inform 171, p.286); the value is not given.
- **Question.** What is the value, and does it apply to all four edges?
- **Our assumption.** None yet.
- **What changes.** The nutrient balance of the closed tissue scenarios.

## Quick questions (non-blocking)

**Q6. Lattice spacing.** Table 1 of the J Cell Automata paper gives 1 lattice site = 1 μm. With
1 μm spacing a 25-site cell is 5 μm across (25 μm²), small for crypt epithelium. Is the spacing
really 1 μm, or does a site represent a larger length?

**Q7. ρ in the J Cell Automata paper.** Is ρ = B/|C|, as in the Fundamenta Informaticae paper?

**Q8. Biomass at division.** Is B halved between the daughters or split by area? *We halve.*

**Q9. Degenerate optima.** Was pFBA or another secondary objective used to choose among
solutions with equal v_b? It matters for the lactate phenotypes of Fundamenta Informaticae
Fig 6. *We use pFBA.*

Once the reproduction is published, we will send you the tutorial. Each of your answers will be
recorded there with a dated entry.

With thanks,
[Maintainer name]

<!-- trace:
Q1: spec 08 §1 (HMR core counts), §2.2, §7 item 13; specs README §4 X5; README §5 Damiani item 1. HOLD lifted 2026-09-30: Di Filippo 2016 mmc1.xls on disk, 274 rxn × 252 met vs stated 272 × 240; question narrowed
Q2: spec 08 §1, §7 item 12; README §5 Damiani item 1. HOLD: ACRI 2018 paper (LNCS 11115, doi 10.1007/978-3-319-99813-8_2) not obtained: closed access, no repository copy (checked 2026-09-30)
Q3: spec 08 §2.2, §7 item 10; README §5 Damiani item 2
Q4: spec 08 §2.2, §7 item 8; specs README §4 X3; README §5 Damiani item 2
Q5: spec 08 §2.2, §7 item 9; README §5 Damiani item 2
Q6: spec 08 §7 item 1; README §5 Damiani item 3
Q7: spec 08 §7 item 3; README §5 Damiani item 3
Q8: spec 08 §7 item 4; specs README §4 X4; README §5 Damiani item 3
Q9: spec 08 §7 item 5; specs README §4 X1; README §5 Damiani item 3
Tutorial (planned): 08_fbca.jl, step 12
-->

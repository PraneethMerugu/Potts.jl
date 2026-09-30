# Questions for Chiara Damiani, Alex Graudenzi and Davide Maspero: FBCA (J Cell Automata 15:75) and its diffusion extension (Fundam Inform 171:279)

Batch 1 — **draft, not sent.** The maintainer sends this personally. Citations point to
`docs/design/research/model-specs/08_fbca.md` ("spec 08 §x"; 08a = J Cell Automata paper,
08b = Fundamenta Informaticae paper) and the specs README ("specs README §4 X<n>").

---

Dear Dr. Damiani, Dr. Graudenzi and Dr. Maspero,

I am [Maintainer name], and I work on Potts.jl, an open-source Julia ecosystem for cellular
Potts models. We are reproducing FBCA — a CPM with a flux-balance problem solved per cell every
MCS — with full provenance: every equation and parameter is traced to a page or figure, and
every choice we make is listed in a public tutorial. FBCA is the most ambitious coupling in our
set, and we would like the reproduction to be exact.

Neither paper links code or the metabolic model file, and 08b takes its defaults "as in [18]",
the ACRI 2018 paper, which we do not have. Questions 1–5 block a reproduction; 6–9 are quick.
We would be glad to work on this together with you.

With thanks,
[Maintainer name]

---

## Blocking questions

### Q1 [B] Code and the HMR CORE model file

- **Context.** Both papers say the implementation is MATLAB with the COBRA Toolbox (08a p.82;
  08b p.288), on HMR CORE (Di Filippo et al. 2016; 272 reactions, 240 metabolites) (spec 08 §1,
  §2.2). No repository or SBML/MAT file is linked (spec 08 §7 item 13).
- **Question.** Could you share the MATLAB sources and the exact HMR CORE file used?
- **Our assumption.** None possible: the metabolic model is a blocking gate (specs README §4 X5).
- **What changes.** Everything; without it there is no per-cell LP to solve.

### Q2 [B] The ACRI 2018 parameters used in 08b

- **Context.** 08b's defaults are "as in [18]" (08b p.285), i.e. Graudenzi et al., ACRI 2018
  (LNCS 11115), which we do not have (spec 08 §1).
- **Question.** What values of λ, k_BT, attempts per MCS and the initial field values were used
  in 08b (spec 08 §7 item 12)?
- **Our assumption.** None yet.
- **What changes.** The CPM layer and the initial nutrient fields of every 08b scenario.

### Q3 [B] Starvation death

- **Context.** "cellular death by starving is the only way to remove cells" (08b p.282, p.285), but
  no criterion is given (spec 08 §2.2).
- **Question.** What triggers death: a threshold on v_b, an infeasible LP, a biomass decrease,
  or something else (spec 08 §7 item 10)?
- **Our assumption.** None yet.
- **What changes.** Population size and composition over time in all 08b tissue scenarios.

### Q4 [B] The Eq 6 averaging operator

- **Context.** Diffusion is neighbourhood averaging, [N(l_i)] ← (D/|I|) Σ_{j∈I} [N(l_j)]
  (08b Eq 6, p.284). D is "chosen based on the nutrient species" but not given, the number of
  sweeps per MCS is not given, and for D ≠ 1 the operator does not conserve mass (spec 08 §2.2).
- **Question.** What D per species, how many sweeps per MCS, and is D < 1 intended as a decay
  (spec 08 §7 item 8)?
- **Our assumption.** The operator as written, with D a calibration parameter (specs README §4
  X3).
- **What changes.** Nutrient gradients around the vessels, hence the spatial phenotype maps.

### Q5 [B] Edge efflux

- **Context.** Unconsumed nutrients "are removed … through a constant flux value" at the lattice
  edges (08b p.286); the value is not given (spec 08 §2.2).
- **Question.** What is the value, and does it apply to all four edges (spec 08 §7 item 9)?
- **Our assumption.** None yet.
- **What changes.** The nutrient balance of the closed tissue scenarios.

## Quick questions (non-blocking)

**Q6. Units.** 08a Table 1 has "1 lattice site = 1 μm". Is that a 1 μm edge, or 1 μm² per site?
A 25 μm² cell would be small for crypt epithelium (spec 08 §7 item 1).

**Q7. ρ in 08a.** Is ρ = B/|C| as in 08b (spec 08 §7 item 3)?

**Q8. Biomass at division.** Is B halved between daughters or split by area (spec 08 §7 item 4)?
*We halve (specs README §4 X4).*

**Q9. Degenerate optima.** Was pFBA or another secondary objective used to pick among equal-v_b
solutions? It matters for the lactate phenotypes of 08b Fig 6 (spec 08 §7 item 5). *We use pFBA
(specs README §4 X1).*

## Tutorial to share once public

`lib/PottsModels/reproductions/08_fbca.jl` (planned, build step 12, following
TUTORIAL_TEMPLATE). Each answer becomes a dated changelog entry and a row of its deviations
table.

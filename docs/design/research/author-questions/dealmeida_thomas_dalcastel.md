# Questions for Rita de Almeida, Gilberto Thomas and Pedro Dal-Castel: Fortuna 2020, Thomas 2022, Dal-Castel 2025

Batch 1 — **draft, not sent.** The maintainer sends this personally. Citations point to
`docs/design/research/model-specs/14_nucleus_migration.md` ("spec 14 §x") and the specs README
("specs README §4 C<n>"). Q2 is also asked of James Glazier; the first answer settles it.

---

Dear Prof. de Almeida, Dr. Thomas and Dr. Dal-Castel,

I am [Maintainer name], and I work on Potts.jl, an open-source Julia ecosystem for cellular
Potts models. We are reproducing your compartmentalised crawling-cell model — the Fortuna et
al. 2020 base model, the Thomas et al. 2022 polarization study and the Dal-Castel et al.
chemotaxis variant — with full provenance: every equation and parameter is traced to a page,
figure or code line, and every choice we make is listed in a public tutorial.

Your released code (`SF1_Code.zip` and `Single_Cell_Chemotaxis_2.3`) answered most of our
questions; thank you for publishing it. Questions 1–2 still block a quantitative reproduction;
3–5 are quick. We would be glad to reach an exact reproduction together with you.

With thanks,
[Maintainer name]

---

## Blocking questions

### Q1 [B] J between cytoplasm and lamellipodium: 20 or 10?

- **Context.** Fortuna et al. 2020 Table 1 gives J_cyto–lamellipodium = 20. Both released codes
  use 10: `CellMig3D.py:230` (ContactInternal CYTO–FRONT = J₀/2) and the chemotaxis code
  (`SCellSign.py:120, 139`) (spec 14 §2.9.7 item 1, §9 item 3).
- **Question.** Which value produced the published 2020 figures?
- **Our assumption.** 10 (both codes agree), with `J_CL = 20` as a variant (specs README §4 C1).
- **What changes.** The default, and whether the Table 1 value is recorded as a typo.

### Q2 [B] F-actin magnitude at source sites

- **Context.** In `SF1_Code.zip` the F-actin field uses `DiffusionSolverFE` with decay 0.9 and a
  `SecretionOnContact` source of 0.9 on lamellipodium sites touching the adherent substrate
  (`CellMig3D.py:244–253`; spec 14 §2.9.2). If decay runs before secretion within a solver call,
  F ≈ 1 at a source site; if secretion runs first, F ≈ 0.1 during the next Potts sweep. That is up
  to a 10× difference in the protrusion term λ_F-actin[F(v) − F(r)] (Eq 7) (spec 14 §9 item 15).
- **Question.** In the CC3D version you used (the files mention 3.7.9, 3.7.5 and 3.5.1), what
  was the order, and does `SecretionOnContact` test only face neighbours?
  (`Instructions_To_Run.pdf`, which we do not have, may also say.)
- **Our assumption.** None yet: this is a blocking gate for quantitative results, and we
  calibrate against Table 2 meanwhile (specs README §4 C4).
- **What changes.** The effective protrusion strength, and therefore speeds and the Table 2
  Fürth-fit targets.

## Quick questions (non-blocking)

**Q3. Chemotaxis gate details (Dal-Castel).** For the Eq 6 memory switch: (a) which δ was used
for the paper figures (the code default is 0; the README suggests 0.01)? (b) strict "<" (the
paper's sign function) or "≤" (the code)? (c) is the current MCS included in the 100-MCS mean?
(spec 14 §9 item 10) *We follow the code: δ = 0, "≤", current MCS included (specs README §4
C6).*

**Q4. Fig 8 caption (Dal-Castel).** The caption names the non-fitting set as λ = 125,
φ_f = 0.05, but Fig 6 and Table S2 point to φ_f = 0.20. Is 0.20 correct (spec 14 §9 item 12)?
*We read it as 0.20.*

**Q5. Polarization measure (Fortuna Fig 12).** Fig 12 uses the "lamellipodium–nucleus"
centre-of-mass distance, while the code logs `dcm_F_CN`, the xy distance between the
lamellipodium (FRONT) COM and the "CN" COM (`CellMig3D_Steppables.py:359–369`). Which
quantity is plotted (spec 14 §2.9.7 item 12)?

## Tutorial to share once public

`lib/PottsModels/reproductions/14_nucleus_migration.jl` (planned: base model in build step 5,
chemotaxis variant in step 7b; follows TUTORIAL_TEMPLATE). Each answer becomes a dated
changelog entry and a row of its deviations table.

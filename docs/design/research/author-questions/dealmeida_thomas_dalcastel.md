# Questions for Rita de Almeida, Gilberto Thomas and Pedro Dal-Castel: Fortuna 2020, Thomas 2022, Dal-Castel 2025

Batch 1 — **draft, not sent.** The maintainer sends this personally. Internal traceability
is in the comment block at the end of the file.
- cc James Glazier (co-author of Fortuna et al. 2020). Add Ismael Fortuna as addressee if he
  can be reached.
- **All six questions (Q1–Q6) are on HOLD** until the pre-send checks in README.md are done.
  Q1, Q3 and Q6 may be settled by the Biophys J 2020 Document S1 and the nanoHUB code.

---

Dear Prof. de Almeida, Dr. Thomas and Dr. Dal-Castel,

I am [Maintainer name], and I work on Potts.jl, an open-source Julia ecosystem for cellular
Potts models. We are reproducing your compartmentalised crawling-cell model — the Fortuna et
al. 2020 base model, the Thomas et al. 2022 polarization study and the Dal-Castel et al.
chemotaxis variant — with full provenance: every equation and parameter is traced to a page,
figure or code line, and every choice we make will be listed in a tutorial that we will publish
and share with you.

Your released code (`SF1_Code.zip` and `Single_Cell_Chemotaxis_2.3`) answered most of our
questions; thank you for publishing it. Questions 1–3 still matter for a quantitative
reproduction; 4–6 are quick. We would be glad to reach an exact reproduction together with you.

## Blocking questions

### Q1 [B] [HOLD] J between cytoplasm and lamellipodium: 20 or 10?

- **Context.** Fortuna et al., Biophys J 118 (2020), Table 1 (p.2807) gives
  J_cyto–lamellipodium = 20. Both released codes use 10: `CellMig3D.py:230` (ContactInternal
  CYTO–FRONT = J₀/2) and `SCellSign.py:120, 139`.
- **Question.** Which value produced the published 2020 figures?
- **Our assumption.** 10, because both codes agree, with 20 as a variant.
- **What changes.** The default, and whether Table 1 is noted as a typo.

### Q2 [B] [HOLD] F-actin magnitude at source sites

- **Context.** In `SF1_Code.zip` the F-actin field uses `DiffusionSolverFE` with decay 0.9 and a
  `SecretionOnContact` source of 0.9 on lamellipodium sites touching the adherent substrate
  (`CellMig3D.py:244–253`). If decay runs before secretion within a solver call, F ≈ 1 at a
  source site; if secretion runs first, F ≈ 0.1 during the next Potts sweep. That is up to a 10×
  difference in the protrusion term λ_F-actin[F(v) − F(r)] (Eq 7, p.2806).
- **Question.** In the CC3D version you used (the files mention 3.7.9, 3.7.5 and 3.5.1), in
  which order were secretion and decay applied, and does `SecretionOnContact` test only face
  neighbours? James Glazier is in copy; an answer from any of you settles it.
- **Our assumption.** None yet; until this is settled we calibrate against Table 2.
- **What changes.** The effective protrusion strength, and therefore speeds and the Table 2
  Fürth fits.

### Q3 [B] [HOLD] Did `SF1_Code.zip` produce the 2020 figures?

- **Context.** The code header says it was "written between 2014-2015" (`CellMig3D.py:9`). The
  Python and XML files in the zip are dated 2021-08, i.e. repackaged after publication, and the
  CC3D version tags disagree: 3.7.9 (`CellMig3D.py:13`), 3.7.5 (the XML, `CellMig3D.py:94`) and
  3.5.1 (`CellMig3D.cc3d:1`).
- **Question.** Is this the exact code, with the exact settings, behind the published figures?
- **Our assumption.** Yes; we treat it as the source of the figures.
- **What changes.** Whether the two paper–code differences that matter most (J_cyto–lamellipodium
  20 vs 10, Q1; the lamellipodium conversion law written on target rather than current volumes)
  are paper facts or code artefacts.

## Quick questions (non-blocking)

**Q4. [HOLD] Chemotaxis gate details (Dal-Castel).** For the Eq 6 memory switch: (a) which δ was
used for the paper figures (the code default is 0; the repository README suggests 0.01)?
(b) strict "<" (the paper's sign function) or "≤" (the code)? (c) is the current MCS included in
the 100-MCS mean? *We follow the code: δ = 0, "≤", current MCS included.*

**Q5. [HOLD] Fig 8 caption (Dal-Castel).** The caption names the non-fitting set as λ = 125,
φ_f = 0.05, but the Fig 6 caption and Table S2 give φ_f = 0.20. Is 0.20 correct? *We read it
as 0.20.*

**Q6. [HOLD] Polarization measure (Fortuna Fig 12).** Fig 12 uses the "lamellipodium–nucleus"
centre-of-mass distance, while the code logs `dcm_F_CN`, the xy distance between the
lamellipodium (FRONT) centre of mass and the volume-weighted centre of mass of cytoplasm plus
nucleus ("CN") (`CellMig3D_Steppables.py:359–369`). Which quantity is plotted?

Once the reproduction is published, we will send you the tutorial. Each of your answers will be
recorded there with a dated entry.

With thanks,
[Maintainer name]

<!-- trace:
Q1: spec 14 §2.9.7 item 1, §9 item 3; specs README §4 C1; README §5 de Almeida item 1. HOLD: Biophys J 2020 Document S1 (mmc1.pdf, with Table S1) and nanoHUB gltcellcrawl (DOI 10.21981/YXKM-4E26), diffed against SF1_Code.zip
Q2: spec 14 §2.9.2, §9 item 15; specs README §4 C4; README §5 de Almeida item 2 / Glazier item 3. HOLD: CC3D 3.7.9 DiffusionSolverFE source; Instructions_To_Run.pdf from the SF1 directory
Q3: spec 14 §1 (14a-code row), §2.9.7 items 1, 2, 16, §9 item 17; README §5 Glazier item 3 (moved here in review round 1). HOLD: same Document S1 / nanoHUB diff; if the codes match, rewrite as whether the same settings were used for Figs 5–12
Q4: spec 14 §9 item 10; specs README §4 C6; README §5 de Almeida item 3. HOLD: diff arXiv v1 against the 2025 Physica A version of record
Q5: spec 14 §9 item 12; README §5 de Almeida item 4. HOLD: same diff
Q6: spec 14 §2.9.1 (output row), §2.9.7 item 12; README §5 de Almeida item 5. HOLD: same Document S1 / nanoHUB diff
Tutorial (planned): 14_nucleus_migration.jl, steps 5 and 7b
-->

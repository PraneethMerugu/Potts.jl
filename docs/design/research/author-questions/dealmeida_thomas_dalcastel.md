# Questions for Rita de Almeida, Gilberto Thomas and Pedro Dal-Castel: Fortuna 2020, Thomas 2022, Dal-Castel 2025

Batch 1 — **draft, not sent.** The maintainer sends this personally. Internal traceability
is in the comment block at the end of the file.
- cc James Glazier (co-author of Fortuna et al. 2020). Add Ismael Fortuna as addressee if he
  can be reached.
- **Q3 and Q4 are on HOLD** until the 2025 Physica A version of record can be compared with
  arXiv v1 (closed access; see the pre-send checklist in README.md). The other checks are done:
  the former solver-order question was answered by the CompuCell3D source and dropped, and the
  remaining questions were narrowed.

---

Dear Prof. de Almeida, Dr. Thomas and Dr. Dal-Castel,

I am [Maintainer name], and I work on Potts.jl, an open-source Julia ecosystem for cellular
Potts models. We are reproducing your compartmentalised crawling-cell model — the Fortuna et
al. 2020 base model, the Thomas et al. 2022 polarization study and the Dal-Castel et al.
chemotaxis variant — with full provenance: every equation and parameter is traced to a page,
figure or code line, and every choice we make will be listed in a tutorial that we will publish
and share with you.

Your released code and documents (`SF1_Code.zip` with its run instructions, Document S1 of
the 2020 paper and `Single_Cell_Chemotaxis_2.3`), together with the nanoHUB port, answered most
of our questions; thank you for publishing them. Reading the CompuCell3D source settled the
order of secretion and decay in the F-actin solver, so we no longer need to ask about it.
Questions 1–2 still matter for a quantitative reproduction; 3–5 are quick. We would be glad to
reach an exact reproduction together with you.

## Blocking questions

### Q1 [B] J between cytoplasm and lamellipodium: 20 or 10?

- **Context.** Fortuna et al., Biophys J 118 (2020), Table 1 (p.2807) gives
  J_cyto–lamellipodium = 20. Every released version of the code uses 10: `CellMig3D.py:230`
  (ContactInternal CYTO–FRONT = J₀/2), the nanoHUB port (`CellMig3D_P3.py:139`) and
  `SCellSign.py:120, 139`. Document S1 does not list the contact energies.
- **Question.** Which value produced the published 2020 figures?
- **Our assumption.** 10, because all the codes agree, with 20 as a variant.
- **What changes.** The default, and whether Table 1 is noted as a typo.

### Q2 [B] Were the released settings used for Figs 5–12, and with which CompuCell3D version?

- **Context.** `SF1_Code.zip` agrees with the lattice rule and output files that Document S1
  describes, and the nanoHUB port has the same energies, field and conversion rule. Three
  settings differ from the paper text, and no document says which settings the figures used:
  1. J_cyto–lamellipodium = 10 (Q1).
  2. The lamellipodium conversion law is written on target volumes
     (`CellMig3D_Steppables.py:132–139`, p = 0.1 (1 − V_l^target/(φ_l V^target))), so conversion
     stops once the lamellipodium target is reached. The paper writes it on the current volume
     (p.2806).
  3. The F-actin protrusion term also acts on retraction. With no `Algorithm` element,
     CompuCell3D's `Chemotaxis` plugin uses its default algorithm, which applies the
     `ChemotaxisByType` term both when the lamellipodium extends into medium and when medium
     overwrites a lamellipodium site (we checked the 3.6.2 and 3.7.9 sources). Eq 7 (p.2806)
     and the code comment (`CellMig3D.py:6`) describe extension only. The same holds for
     `SCellSign.py:147–149`.

  Document S1 (p.2) says the published runs used CompuCell3D 3.5.1; `Instructions_To_Run.pdf`
  (p.1) says 3.6.2.
- **Question.** Were Figs 5–12 produced with these released settings (J = 10, the
  target-volume conversion law, and the protrusion term acting on retraction too)? And which
  CompuCell3D version was used, 3.5.1 or 3.6.2?
- **Our assumption.** Yes to all three. For the solver and the protrusion term we rely on the
  3.6.2 and 3.7.9 sources, which behave the same.
- **What changes.** Whether these paper–code differences are paper facts or code artefacts,
  and so the defaults of our base model.

## Quick questions (non-blocking)

**Q3. [HOLD] Chemotaxis gate details (Dal-Castel).** For the Eq 6 memory switch: (a) which δ was
used for the paper figures (the code default is 0; the repository README suggests 0.01)?
(b) strict "<" (the paper's sign function) or "≤" (the code)? (c) is the current MCS included in
the 100-MCS mean? *We follow the code: δ = 0, "≤", current MCS included.*

**Q4. [HOLD] Fig 8 caption (Dal-Castel).** The caption names the non-fitting set as λ = 125,
φ_f = 0.05, but the Fig 6 caption and Table S2 give φ_f = 0.20. Is 0.20 correct? *We read it
as 0.20.*

**Q5. Polarization measure (Fortuna Fig 12).** Fig 12 uses the "lamellipodium–nucleus"
centre-of-mass distance. Document S1 (p.4) describes column 2 of the `_SBAn.dat` file as the
distance from the lamellipodium centre of mass to the combined cytoplasm-plus-nucleus centre of
mass, which the code computes in the xy plane and divides by R (`dcm_F_CN`,
`CellMig3D_Steppables.py:359–369`). The `_Displacement.dat` file also holds the separate
lamellipodium and nucleus centres. Was Fig 12 plotted from the `_SBAn.dat` column, or from the
lamellipodium–nucleus distance computed from `_Displacement.dat`? *We use the `_SBAn.dat`
column.*

Once the reproduction is published, we will send you the tutorial. Each of your answers will be
recorded there with a dated entry.

With thanks,
[Maintainer name]

<!-- trace:
Q1: spec 14 §2.9.7 item 1, §2.9.8, §9 item 3; specs README §4 C1; README §5 de Almeida item 1. HOLD lifted 2026-09-30: Document S1 lists no J; nanoHUB port uses 10 (nH:P3:139)
Q2 (was Q3, rewritten 2026-09-30; retraction term added in review round 1): spec 14 §2.9 (provenance evidence), §2.9.4, §2.9.5, §2.9.7 items 1, 2, 16, 19, §9 item 16 (D-067), specs README §4 C7, §2.9.8, §9 item 17; README §5 Glazier item 3 (moved here in review round 1). Codes match (Document S1 by content, nanoHUB by diff), so rewritten as "same settings for Figs 5–12" plus the 3.5.1 vs 3.6.2 version conflict
Former Q2 (F-actin solver order): DROPPED 2026-09-30, answered by CC3D 3.6.2/3.7.9 source (spec 14 §2.9.2, §9 item 15; specs README §4 C4); see README "Resolved, not asked"
Q3 (was Q4): spec 14 §9 item 10; specs README §4 C6; README §5 de Almeida item 3. HOLD: diff arXiv v1 against the 2025 Physica A version of record (closed access; arXiv has only v1)
Q4 (was Q5): spec 14 §9 item 12; README §5 de Almeida item 4. HOLD: same diff
Q5 (was Q6, narrowed 2026-09-30): spec 14 §2.9.1 (output row), §2.9.7 item 12, §9 item 19; README §5 de Almeida item 5
Tutorial (planned): 14_nucleus_migration.jl, steps 5 and 7b
-->

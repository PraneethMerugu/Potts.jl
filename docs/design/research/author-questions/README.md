# Author questions

Draft letters to the authors of the reference models, one file per author group. They are
built from `../model-specs/README.md` §5 ("Questions for the authors (invitations to
collaborate)") and the model specs it cites (ROADMAP Phase 6 step 0, item P6.0i).

The reproductions and their tutorials are meant as invitations to collaborate. Each letter
says who we are, asks precise questions, says what we assume meanwhile and what the answer
changes. The aim is to reach an exact reproduction together with the original authors.

**Nothing here has been sent.** The maintainer reviews, personalises and sends each letter
personally. The drafts contain no contact details; `[Maintainer name]` marks the signature.

## Conventions

- **Send version.** The letter body (from "Dear …" to the signature) is the text to be sent,
  but it is not send-ready as it stands: first work through the pre-send checklist, which
  includes removing the **[HOLD]** tags from the body. It cites only the papers' own pages,
  equations, figures and the authors' released files. The short header above the body holds
  routing notes (cc, HOLD) for the maintainer and is not sent.
- **Traceability.** An HTML comment `<!-- trace: … -->` at the end of each file maps every
  question to its spec section ("spec NN §x" = `../model-specs/NN_*.md`), to the decision row
  in `../model-specs/README.md` §4 that holds our current assumption, and to its README §5
  item. It also names the planned tutorial file and build step.
- **Form.** Blocking questions are marked **[B]** and come first. Each has context, the
  question, our current assumption and what changes with the answer. Quick questions are one
  paragraph each. **[HOLD]** marks a question that public material we have not yet read may
  answer; see the pre-send checklist.
- Tutorials are not public yet. Each letter promises to send the tutorial once it is published.

## Batch plan

- **Batch 1 (this batch).** Every **[B]** question of README §5 for every author group, plus a
  few non-blocking ones that are cheap to answer alongside: yes/no confirmations, one value, or
  a request for code or files that would settle many questions at once.
- **Batch 2.** The remaining non-blocking questions (listed below), revised in the light of the
  batch-1 answers. Many will disappear if code or input files come back.
- **When an answer arrives:** mark the spec item RESOLVED with the date and "author
  communication"; update the decision row in `../model-specs/README.md` §4; add a
  deviations-table row and a dated changelog entry in the tutorial (TUTORIAL_TEMPLATE §6–§7).

## Status

| Group | File | Models (spec) | Questions | Blocking | HOLD | Status |
|---|---|---|---|---|---|---|
| Yi Jiang (with co-authors) | [jiang.md](jiang.md) | 04, 05, 06, 07, 10 | 12 | 6 | – | draft — not sent |
| James A. Glazier (cc/co-addressee F. Graner for Q7) | [glazier.md](glazier.md) | 12, 09, 04 | 7 | 5 | – | draft — not sent |
| Roeland Merks | [merks.md](merks.md) | 01 | 5 | 2 | Q1 | draft — not sent |
| Rita de Almeida, Gilberto Thomas, Pedro Dal-Castel (cc J.A. Glazier; add Ismael Fortuna if reachable) | [dealmeida_thomas_dalcastel.md](dealmeida_thomas_dalcastel.md) | 14 | 5 | 2 | Q3, Q4 | draft — not sent |
| James Osborne, Alexander Fletcher | [osborne_fletcher.md](osborne_fletcher.md) | 09 | 4 | 1 | – | draft — not sent |
| Andreas Deutsch, Jörn Starruß | [deutsch_starruss.md](deutsch_starruss.md) | 13 | 8 (Q0–Q7) | 3 | – | draft — not sent |
| Chiara Damiani, Alex Graudenzi, Davide Maspero | [damiani_graudenzi_maspero.md](damiani_graudenzi_maspero.md) | 08 | 9 | 5 | Q2 | draft — not sent |
| Sahar Jafari Nivlouei, Madjid Soltani, Rui Travasso | [jafari_soltani_travasso.md](jafari_soltani_travasso.md) | 11 | 7 | 6 | – | draft — not sent |
| **Total** | | | **57** | **30** | **4** | |

- **The foam question.** One blocking question, the Eq 2 shear term, appears in two letters
  (jiang.md Q6 = glazier.md Q5), so there are 29 distinct blocking questions. **Recommendation:
  send it once, jointly to Yi Jiang and James Glazier.** Both letters say that either answer
  settles it.
- **Fortuna questions.** They now go only to the de Almeida/Thomas letter, with Glazier in cc.
- **Length.** `jiang.md` exceeds the two-page aim because it covers five papers; it can be split
  per paper before sending.

## Pre-send checklist (HOLD questions)

Do each check before sending. If the check answers a question, drop the question or narrow it,
and record the answer in the spec. Then, for every letter:

1. **Revise the intro/context sentence if the check succeeds.** Two sentences assume a source is
   still unread: merks.md intro ("we have not yet been able to consult its supplementary
   methods", tied to Q1/Q2) and damiani_graudenzi_maspero.md Q2 context ("which we have not yet
   been able to consult", the ACRI 2018 paper). Reword or delete them once the source is read.
   *Status 2026-09-30:* the merks.md intro was reworded (it now names the sources read and says
   the 2006 supplementary methods could not be found online); revise it again if that file turns
   up. The damiani Q2 sentence stays, because the ACRI paper was not obtained.
2. **Remove the [HOLD] tags from the body before sending.** They are internal markers and appear
   in the question headings of the letter bodies. *Status 2026-09-30:* four tags remain —
   merks.md Q1, dealmeida_thomas_dalcastel.md Q3 and Q4, damiani_graudenzi_maspero.md Q2. If a
   source stays unobtainable, the maintainer can also send the question as it stands and just
   delete the tag.
3. **Still to obtain by hand** (not reachable by script, or paywalled): the 2006 Merks
   "Supplementary methods" (ScienceDirect, Dev Biol 289:44, Appendix A); the Dal-Castel et al.
   2025 version of record (Physica A 666:130524); Graudenzi et al., ACRI 2018 (LNCS 11115:16–29).

Checks run on 2026-09-30. Downloads, with source URL, size and sha256, are listed in the local
`docs/references/codebases/SOURCES.md`. Question numbers below are the numbers before the
checks; the letters have been renumbered where a question was dropped.

| Done | Letter / question | Check that decides it | Result |
|---|---|---|---|
| ☑ | dealmeida_thomas_dalcastel Q1 (J cyto–lamellipodium), Q2, Q3 (SF1 provenance), Q6 (polarization measure) | Obtain Biophys J 2020 Document S1 (mmc1.pdf) and the nanoHUB gltcellcrawl code; diff them against SF1_Code.zip; settle or drop Q1/Q2/Q3/Q6. If the codes match, rewrite Q3 as whether the same settings (J cyto–lamellipodium, conversion rule) were used for Figs 5–12. (The paper, Biophys J 118:2801, PMC7264849, says its CC3D code and run instructions are in Document S1, with Table S1; nanoHUB DOI 10.21981/YXKM-4E26.) | Both obtained. Document S1 holds run instructions, not code, and lists no J values; it names CC3D 3.5.1 for the paper's runs. The nanoHUB tool is a 2022 CC3D 4.2.2 port with the same energies (J = 10), field and conversion rule, plus one extra secretion source on the top plate. Q1: HOLD removed, context extended. Q3: rewritten as planned (now Q2), plus the 3.5.1 vs 3.6.2 version conflict. Q6: narrowed (now Q5), HOLD removed. Spec 14 §1, §2.9, §2.9.8, §9 items 3, 17, 19 |
| ☑ | dealmeida_thomas_dalcastel Q2 (F-actin secretion/decay order) | Read the CC3D 3.7.9 `DiffusionSolverFE` source (and `SecretionOnContact` neighbour test). Obtain `Instructions_To_Run.pdf` from the same directory as `SF1_Code.zip`. | Answered by the CC3D 3.7.9 and 3.6.2 source: one solver call per MCS, diffusion + decay before secretion, so F ≈ 1 at source sites; face neighbours only; one secretion per site. `Instructions_To_Run.pdf` (already on disk) names 3.6.2. **Q2 dropped.** Also resolved spec 14 §9 item 16 (chemotaxis acts on retraction too) from the CC3D `Chemotaxis` source. Spec 14 §2.9.2, §2.9.4, §9 items 15, 16 |
| ☐ blocked | dealmeida_thomas_dalcastel Q4 (Eq 6 gate details), Q5 (Fig 8 caption) (now Q3, Q4) | Diff arXiv:2312.00776v1 against the 2025 Physica A version of record. | Not possible: arXiv has only v1, and the version of record (Physica A 666 (2025) 130524, doi 10.1016/j.physa.2025.130524) is closed access. **Still HOLD.** Spec 14 §1, §9 item 13 |
| ☑ | damiani_graudenzi_maspero Q1 (metabolic model) | Obtain the HMR CORE file from the Di Filippo et al. 2016 supplementary (Comput Biol Chem 62:60) and compare with 272 reactions / 240 metabolites. | Obtained (mmc1–mmc4.xls). The core model (mmc1) has 274 reactions and 252 metabolites, not 272 × 240. **Q1 narrowed**, HOLD removed. Spec 08 §1, §7 item 13 |
| ☐ blocked | damiani_graudenzi_maspero Q2 (ACRI 2018 parameters) | Obtain Graudenzi et al., ACRI 2018 (LNCS 11115, doi 10.1007/978-3-319-99813-8_2). Revise the Q2 context sentence if it is obtained (step 1). | Not obtained: closed access; the Milano-Bicocca repository record has no file. **Still HOLD**; the context sentence stays. Spec 08 §1, §7 item 12 |
| ☑ | osborne_fletcher Q4 (2017 contact neighbourhood) | Read Chaste `release_2017.1` `AdhesionPottsUpdateRule.cpp` and `PottsMesh.cpp`. | `release_2017.1` and the paper's own tag `paper/CellBasedComparison` (2016) have the same Potts rules as develop: VN contacts and perimeter, Moore proposals. **Q4 dropped.** Spec 09 §1, §7 A-OS4 |
| ☑ (partly) | merks Q1 (2006 L, E₀, seeding), Q2 (2008 relaxation) | Check the 2006 ScienceDirect supplementary data, the PMC author manuscript, and the TST tutorial chapter (Methods Mol Biol 1214, 2015). Revise the intro sentence if the 2006 supplementary is found (step 1). | PMC manuscript (same text as the journal), the 2006 supplementary movie and the TST chapter (CWI preprint) obtained; none settles Q1 or Q2. The 2006 "Supplementary methods" file was not found. Q1 narrowed, **still HOLD** for that file; Q2 HOLD removed. Intro sentence revised. Spec 01 §1, §8 A-1, A-15, A-19 |
| ☐ | jiang Q12 (Akeeb et al. 2026) | Confirm Akeeb's first-name spelling; the body uses "S. Akeeb" until then. | Not part of this round. |

## Resolved, not asked

README §5 items that the specs have since answered:

- **Graner–Glazier set-up (Glazier item 5).** Glazier & Graner 1993 (PRE 47:2128) is now on disk
  (spec 09 §8). It resolves A-GG1 (target area 40 for both types), A-GG2 (Moore(1) proposals,
  p.2130), most of A-GG3 (unweighted mismatched-bond counts) and A-GG4 (T = 0 annealing on a
  copy, p.2134, in paper MCS). From A-GG5 it resolves the relaxation parameters (p.2135), the
  cell count (≈1000, p.2129) and the initial aggregate shape (spec 09 §8.4). Only the lattice
  size, boundary conditions and type fraction remain (glazier.md Q7).
- **Merks lattices (Merks item 5, A-10), in part.** Dataset S1 fixes 200 × 200 px with 128 cells
  for Figs 5–11 (spec 01 §8 A-10). The paper answers the Fig 10 1024-cell lattice: "1,024-cell
  clusters (dashed-dotted curve) on 400×400-pixel lattices (∼800 µm×800 µm)" (Merks et al. 2008,
  PLoS Comput Biol 4:e1000163, p.9; spec 01 §3.3 row 10, §8 A-10). Only the Fig 2 enclosing
  lattice is asked (merks.md Q5); Fig 12 was dropped in review.
- **Merks compactness convention (Merks item 3, A-14), in part.** The released `Compactness()`
  settles the hull convention (spec 01 §8 A-14). merks.md Q3 asks only for the figure scripts.
- **J_cyto–lamellipodium (de Almeida item 1).** Resolved for the code, since every code uses 10,
  including the nanoHUB port (spec 14 §9 item 3). Document S1 lists no J. Still asked,
  narrowed to which value produced the 2020 figures (dealmeida_thomas_dalcastel.md Q1).
- **F-actin solver order (de Almeida item 2 / Glazier item 3; former dealmeida Q2).** Answered
  by the CompuCell3D 3.6.2 and 3.7.9 source (2026-09-30): diffusion + decay run before
  secretion in the one solver call per MCS, so F ≈ 1 at source sites, and `SecretionOnContact`
  tests face neighbours only (spec 14 §2.9.2, §9 item 15). Dropped.
- **Chemotaxis plugin on retraction (de Almeida item 16, batch 2).** Answered by the
  CompuCell3D 3.7.9 `Chemotaxis` source: the FRONT term also applies when Medium overwrites
  FRONT (spec 14 §2.9.4, §9 item 16). Removed from batch 2.
- **2017 Chaste contact neighbourhood (Osborne item 3, first half; former osborne_fletcher Q4).**
  The paper's Chaste tag and `release_2017.1` match develop (spec 09 §1, §7 A-OS4). Dropped.

## Deferred to batch 2

Non-blocking README §5 items not in batch 1:

- **Jiang.** Foam A-8, A-14, A-15, A-16 (spec 04 §7); Bauer 2009 q3, q6–q11 (spec 05 §7.4);
  Bauer 2007 q4–q10 (spec 07 §7.3); Jiang 2005 q3, q6–q11 (spec 06 §7.3). Most would be settled
  by the code requested in jiang.md Q7.
- **de Almeida group.** Items 11 (Table S1 S column) and 13 (arXiv v1 vs the 2025 version of
  record; now a pre-send check instead, blocked by closed access) (spec 14 §9). Item 16 was
  resolved from the CompuCell3D source (see "Resolved, not asked").
- **Deutsch/Starruß.** Items 7–11 (spec 13 §7).
- **Damiani group.** Items 2, 6, 7, 11 (spec 08 §7).
- **Jafari Nivlouei group.** Items 4, 8, 10, 11, 14 (spec 11 §7). Most would be settled by the
  CC3D project requested in jafari_soltani_travasso.md Q1.
- Glazier, Merks and Osborne/Fletcher: nothing deferred.

## Notes on README §5 for the maintainer

- Glazier item 5, and `../model-specs/README.md` §4 S1 and §1 (row 9), still say the PRE 1993
  paper is not on disk; spec 09 §8 now uses it. glazier.md Q7(d) asks for the "type-type
  correlation" definition, which comes from spec 09 §8.4 and the `09_cell_sorting.jl`
  tutorial §6 rather than from README §5.
- The foam questions appear in both the Jiang and Glazier lists (Glazier item 6). The blocking
  one is in both letters; the quick ones are only in jiang.md.
- Glazier item 3 (Fortuna solver order and SF1 provenance) went to the de Almeida/Thomas
  letter, with Glazier in cc. The solver-order half was answered from the CompuCell3D source and
  dropped; the provenance half is dealmeida_thomas_dalcastel.md Q2.
- Jiang item 1 asks for "the BFS" neighbourhood for both Bauer papers; only the 2009 model has
  the continuity (BFS) term (spec 07 §2.3).
- Merks item 4 asks for files for Figs 5 and 7–10, which `../model-specs/README.md` §1 (row 1)
  says Dataset S1 covers. Dataset S1 has only the baseline set and its T, extension-only and
  VE-cadherin variants (spec 01 §7.1), so merks.md Q4 asks for the sweep values.
- Deutsch/Starruß item 1 marked the Eq 7 sign as blocking; it is now a one-line, non-blocking
  confirmation (deutsch_starruss.md Q4). Q0 (the model file) is new and not in README §5.

## Notes for the spec owner

- **Spec 06 §3.4** must record the text of the Jiang 2005 erratum (Biophys J 91 (2006) 775,
  PMC1483097): the glucose rate for proliferating cells should read 216 (not 162), and the unit
  [mM/h/cm3] should read [mM/h]. jiang.md Q5 relies on this.
- **Spec 11 §7 item 9** (β-catenin precedence) can be resolved from the paper's Fig 3 table:
  Wnt ∨ (Akt ∧ ¬cadherin ∧ ¬APC). jafari_soltani_travasso.md Q7 asks only for confirmation.

# Author questions

Draft letters to the authors of the reference models, one file per author group. They are
built from `../model-specs/README.md` §5 ("Questions for the authors (invitations to
collaborate)") and the model specs it cites (ROADMAP Phase 6 step 0, item P6.0i).

The reproductions and their tutorials are meant as invitations to collaborate: each letter
says who we are, asks precise questions, says what we assume meanwhile, and says what the answer
changes in the reproduction. The aim is to reach an exact reproduction together with the
original authors.

**Nothing here has been sent.** The maintainer reviews, personalises and sends each letter
personally. The drafts contain no contact details; `[Maintainer name]` marks the signature.

## Conventions

- Every factual statement cites its source inline: "spec NN §x" is
  `../model-specs/NN_*.md`; "specs README §4 <id>" is a row of the decision tables in
  `../model-specs/README.md` §4, which records our current assumption.
- Blocking questions are marked **[B]** and come first. Each has four parts: context (paper,
  page, equation or figure), the question, our current assumption, and what changes with the
  answer. Quick questions are one paragraph each.
- Each letter ends with the tutorial(s) that will be shared once public
  (`lib/PottsModels/reproductions/<nn>_<model>.jl`, TUTORIAL_TEMPLATE naming; build step from
  `../model-specs/README.md` §6).

## Batch plan

- **Batch 1 (this batch).** Every **[B]** question of README §5 for every author group, plus a
  few non-blocking ones that are cheap to answer alongside: yes/no confirmations, one value,
  or a request for code or files that would settle many questions at once.
- **Batch 2.** The remaining non-blocking questions (listed below), revised in the light of the
  batch-1 answers. Many will disappear if code or input files come back.
- When an answer arrives: record it in the model spec (mark the item RESOLVED with the date and
  "author communication"), update the decision row in specs README §4, and add a deviations-table
  row and a dated changelog entry in the tutorial (TUTORIAL_TEMPLATE §6–§7).

## Status

| Group | File | Models (spec) | Questions | Blocking | Status |
|---|---|---|---|---|---|
| Yi Jiang (with co-authors) | [jiang.md](jiang.md) | 04, 05, 06, 07, 10 | 12 | 6 | draft — not sent |
| James A. Glazier | [glazier.md](glazier.md) | 12, 14, 09, 04 | 8 | 6 | draft — not sent |
| Roeland Merks | [merks.md](merks.md) | 01 | 5 | 2 | draft — not sent |
| Rita de Almeida, Gilberto Thomas, Pedro Dal-Castel | [dealmeida_thomas_dalcastel.md](dealmeida_thomas_dalcastel.md) | 14 | 5 | 2 | draft — not sent |
| James Osborne, Alexander Fletcher | [osborne_fletcher.md](osborne_fletcher.md) | 09 | 5 | 1 | draft — not sent |
| Andreas Deutsch, Jörn Starruß | [deutsch_starruss.md](deutsch_starruss.md) | 13 | 7 | 4 | draft — not sent |
| Chiara Damiani, Alex Graudenzi, Davide Maspero | [damiani_graudenzi_maspero.md](damiani_graudenzi_maspero.md) | 08 | 9 | 5 | draft — not sent |
| Sahar Jafari Nivlouei, Madjid Soltani, Rui Travasso | [jafari_soltani_travasso.md](jafari_soltani_travasso.md) | 11 | 7 | 6 | draft — not sent |
| **Total** | | | **58** | **32** | |

Two blocking questions are deliberately sent to two groups, so there are 30 distinct blocking
questions:
- the foam Eq 2 shear term (jiang.md Q6 = glazier.md Q6; spec 04 §7 A-1);
- the F-actin secretion/decay order in CC3D (glazier.md Q5 = dealmeida_thomas_dalcastel.md Q2;
  spec 14 §9 item 15).

The first answer settles each; tell the other group.

`jiang.md` is longer than the two-page aim because it covers five papers; it can be split per
paper before sending.

## Resolved, not asked

README §5 items that the specs have since answered:

- **Graner–Glazier set-up (Glazier item 5).** The PRE 47:2128 (1993) paper is now on disk (spec
  09 §8) and resolves A-GG1 (target area 40 for both types), A-GG2 (Moore(1) proposals, p.2130),
  A-GG3 (unweighted mismatched-bond counts, mostly), A-GG4 (T = 0 annealing on a copy: "We anneal
  the displayed data only", p.2134) and its unit (paper MCS), and from A-GG5 the relaxation
  parameters (p.2135), the cell count (≈1000, p.2129) and the initial aggregate shape (spec 09
  §8.4). Only the lattice size, boundary conditions and type fraction remain; they are asked in
  glazier.md Q8.
- **Merks lattices (Merks item 5, A-10), in part.** Dataset S1 fixes 200 × 200 px with 128 cells
  for Figs 5–11 (spec 01 §8 A-10). Only Figs 10 (1024 cells) and 12 are asked (merks.md Q5).
- **Merks compactness convention (Merks item 3, A-14), in part.** The released `Compactness()`
  settles the hull convention (spec 01 §8 A-14); merks.md Q3 asks only whether the figures used it.
- **J_cyto–lamellipodium (de Almeida item 1).** Resolved for the code (both codes use 10; spec 14
  §9 item 3). Still asked, narrowed to which value produced the 2020 figures.

## Deferred to batch 2

Non-blocking README §5 items not in batch 1:

- **Jiang.** Foam A-8, A-14, A-15, A-16 (spec 04 §7). Bauer 2009 q3, q6–q11 (spec 05 §7.4).
  Bauer 2007 q4–q10 (spec 07 §7.3). Jiang 2005 q3, q6–q11 (spec 06 §7.3). Most would be settled
  by the code asked for in jiang.md Q7.
- **de Almeida group.** Items 11 (Table S1 S column), 13 (arXiv v1 vs the 2025 version of
  record) and 16 (chemotaxis plugin on retraction) (spec 14 §9).
- **Deutsch/Starruß.** Items 7–11 (spec 13 §7).
- **Damiani group.** Items 2, 6, 7, 11 (spec 08 §7).
- **Jafari Nivlouei group.** Items 4, 8, 10, 11, 14 (spec 11 §7). Most would be settled by the CC3D
  project asked for in jafari_soltani_travasso.md Q1.
- Glazier, Merks and Osborne/Fletcher: nothing deferred.

## Notes on README §5 for the maintainer

- Glazier item 5 and specs README §4 S1 and §1 (row 9) still say the PRE 1993 paper is not on
  disk; spec 09 §8 now uses it. glazier.md Q8 also asks for the "type-type correlation"
  definition, which comes from spec 09 §8.4 and the `09_cell_sorting.jl` tutorial §6 rather than
  from README §5.
- The foam questions appear in both the Jiang and Glazier lists (Glazier item 6). The blocking
  one is in both letters; the quick ones are only in jiang.md.
- The SF1 code-provenance question (spec 14 §9 item 17) is in the Glazier list only, although the
  code was written by Fortuna and Thomas; the de Almeida group may be better placed to answer it.
- Jiang item 1 asks for "the BFS" neighbourhood for both Bauer papers; only the 2009 model has
  the continuity (BFS) term (spec 07 §2.3).
- Merks item 4 asks for files for Figs 5 and 7–10, which the specs README table (row 1) says
  Dataset S1 covers. Dataset S1 has only the baseline set and its T, extension-only and CI
  variants (spec 01 §7.1), so merks.md Q4 asks for the sweep values.
- Deutsch/Starruß item 1 marks the Eq 7 sign as blocking, although the spec already treats it as
  a near-certain typesetting slip (spec 13 §2.5). It is kept as [B] and should be a one-word
  answer.

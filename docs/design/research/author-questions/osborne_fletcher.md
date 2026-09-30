# Questions for James Osborne and Alexander Fletcher: Osborne et al. 2017 (PLoS Comput Biol 13:e1005387), cellular Potts sorting benchmark

Batch 1 — **draft, not sent.** The maintainer sends this personally. Citations point to
`docs/design/research/model-specs/09_cell_sorting.md` ("spec 09 §x") and the specs README
("specs README §4 S<n>").

---

Dear Dr. Osborne and Dr. Fletcher,

I am [Maintainer name], and I work on Potts.jl, an open-source Julia ecosystem for cellular
Potts models. We are reproducing the cellular Potts cell-sorting benchmark from your 2017
comparison paper with full provenance: every equation and parameter is traced to a page,
figure or code line, and every choice we make is listed in a public tutorial. The
`CellBasedComparison2017` code made this unusually easy; thank you for releasing it.

One question affects how we describe the result; the others are small. Short answers are
plenty, and we would be glad to show you the reproduction once it is public.

With thanks,
[Maintainer name]

---

## Blocking question

### Q1 [B] Which type is engulfed?

- **Context.** p.9 sets γ(A,A) = γ(B,B) < γ(A,B) and γ(A,void) < γ(B,void) "to drive type-A cells
  to engulf type-B cells"; Table 2, the S1 Movie caption ("Engulfment of type-B cells") and Fig 2
  (green B inside) agree. The p.11 sentence says "type-A cells are eventually completely
  engulfed", and the Fig 3 dashed-line caption describes 200 type-A cells surrounded by type B
  (spec 09 §7 A-OS1).
- **Question.** Is the p.11 wording a slip, i.e. are type-B (labelled) cells engulfed?
- **Our assumption.** A engulfs B, with B = labelled (specs README §4 S3).
- **What changes.** The sorted-state description and the reference configuration for the
  Fig 3 dashed line.

## Quick questions (non-blocking)

**Q2. Time labels in Figs 2 and 4.** Fig 2 is labelled t = 0, 100, 1000, 10000. Read as hours
they exceed the 100-h run; read as time steps (0.01 h) they contradict the sorted state and
Fig 3. What unit are they in (spec 09 §7 A-OS2)? *We use Fig 3, which is in hours, as the
quantitative target.*

**Q3. Fig 3 time origin and normalisation.** The code equilibrates unlabelled cells for 10 h,
then labels them and runs on. Is t = 0 in Fig 3 the labelling instant, and could you share the
post-processing that divides by the t = 0 boundary length (not in the repository) (A-OS3)? *We
set t = 0 at labelling (specs README §4 S6).*

**Q4. Contacts in the 2017 Chaste core.** We read the update rules at Chaste develop (2026):
von Neumann contacts and perimeter, Moore proposals. Did the 2017 release used for the paper do
the same (A-OS4)? *We follow the code, flagged (specs README §4 S4).*

**Q5. Fluctuation smoother.** The Fig 3 fluctuation metric uses "a 10 hour smoothing range"
(p.12). Which smoother was it — moving average, LOESS, other (A-OS6)?

## Tutorial to share once public

The Osborne CP benchmark tutorial is planned for build step 1 alongside
`lib/PottsModels/reproductions/09_cell_sorting.jl` (which covers Graner–Glazier and does not
yet reproduce your benchmark). Each answer becomes a dated changelog entry and a row of its
deviations table.

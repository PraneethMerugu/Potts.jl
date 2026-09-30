# Questions for James Osborne and Alexander Fletcher: Osborne et al. 2017 (PLoS Comput Biol 13:e1005387), cellular Potts sorting benchmark

Batch 1 — **draft, not sent.** The maintainer sends this personally. Internal traceability
is in the comment block at the end of the file. **Q4 is on HOLD** until the pre-send check in
README.md is done.

---

Dear Dr. Osborne and Dr. Fletcher,

I am [Maintainer name], and I work on Potts.jl, an open-source Julia ecosystem for cellular
Potts models. We are reproducing the cellular Potts cell-sorting benchmark from your 2017
comparison paper with full provenance: every equation and parameter is traced to a page,
figure or code line, and every choice we make will be listed in a tutorial that we will publish
and share with you. The `CellBasedComparison2017` code was invaluable; thank you for releasing
it.

One question affects how we describe the result; the others are small. Short answers are
plenty.

## Blocking question

### Q1 [B] Which type is engulfed?

- **Context.** p.9 sets γ(A,A) = γ(B,B) < γ(A,B) and γ(A,void) < γ(B,void) "to drive type-A cells
  to engulf type-B cells". Table 2, the S1 Movie caption ("Engulfment of type-B cells") and
  Fig 2 (green B inside) agree. The p.11 sentence says "type-A cells are eventually completely
  engulfed", and the Fig 3 dashed-line caption describes a circular region of 200 type-A cells
  surrounded by type-B cells.
- **Question.** Is the p.11 wording a slip, i.e. are type-B (labelled) cells engulfed?
- **Our assumption.** A engulfs B, with B = labelled.
- **What changes.** The sorted-state description and the reference configuration for the Fig 3
  dashed line.

## Quick questions (non-blocking)

**Q2. Time labels in Figs 2 and 4.** Fig 2 is labelled t = 0, 100, 1000, 10000. Read as hours
they exceed the 100-h run; read as time steps (0.01 h) they contradict the sorted state shown and
Fig 3. What unit are they in? *We use Fig 3, which is in hours, as the quantitative target.*

**Q3. Fig 3 time origin and normalisation.** The code equilibrates unlabelled cells for 10 h,
then labels them and continues. Is t = 0 in Fig 3 the labelling instant, and could you share the
post-processing that divides by the t = 0 boundary length (it is not in the repository)? *We
set t = 0 at labelling.*

**Q4. [HOLD] Contacts in the 2017 Chaste core.** We read the update rules in current Chaste:
von Neumann contacts and perimeter, Moore proposals. Did the 2017 release used for the paper do
the same? *We follow the code, flagged.*

**Q5. Fluctuation smoother.** The Fig 3 fluctuation metric uses "a 10 hour smoothing range"
(p.12). Which smoother was it — moving average, LOESS or other?

Once the reproduction is published, we will send you the tutorial. Each of your answers will be
recorded there with a dated entry.

With thanks,
[Maintainer name]

<!-- trace:
Q1: spec 09 §2.2 (labels vs paper types), §7 A-OS1; specs README §4 S3; README §5 Osborne item 1
Q2: spec 09 §7 A-OS2; README §5 Osborne item 2
Q3: spec 09 §2.2 (protocol, metric), §7 A-OS3; specs README §4 S6; README §5 Osborne item 2
Q4: spec 09 §1 (Chaste develop 44724eb caveat), §2.2, §7 A-OS4; specs README §4 S4; README §5 Osborne item 3. HOLD: check Chaste release_2017.1 AdhesionPottsUpdateRule.cpp and PottsMesh.cpp
Q5: spec 09 §2.2 (fluctuation metric), §7 A-OS6; README §5 Osborne item 3
Tutorial (planned): Osborne CP benchmark, step 1, alongside 09_cell_sorting.jl (Graner–Glazier only)
-->

# Questions for Yi Jiang (with co-authors): foam 1999, Bauer 2007/2009, Jiang 2005, Akeeb 2026

Batch 1 — **draft, not sent.** The maintainer sends this personally. Sources for every
statement: `docs/design/research/model-specs/` (cited as "spec NN §x") and README §4/§5 of
that directory (cited as "specs README §4 <id>").

This letter covers five papers, so it is longer than the others. It can be split per paper.
The foam questions (Q6, Q11) also go to James Glazier as co-author (see `glazier.md`).

---

Dear Prof. Jiang,

As you know, we are building Potts.jl, an open-source Julia ecosystem for cellular Potts
models. For each of the lab's reference papers we are writing a reproduction with full
provenance: every equation and parameter is traced to a page, figure or code line, and every
place where we had to choose is listed openly in a public tutorial. We would like these
reproductions to be exact, and to reach that point together with the original authors.

For five of your papers a few details are not in the published text. Questions 1–6 block a
faithful reproduction; questions 7–12 are quick and can be answered alongside. For each
question we say what we assume in the meantime and what your answer changes. Short answers,
old input files or notes are all very welcome.

With thanks,
[Maintainer name]

---

## Blocking questions

### Q1 [B] Bauer 2007 and 2009: pixel size, lattice geometry and neighbourhoods

- **Context.** Neither paper states the µm per pixel or the lattice geometry; the VEGF source is
  given in "pg/pixel" (spec 05 §2.1; spec 07 §2.1). Bauer 2007 copies from "one of its unlike
  second nearest neighbors" (07 p.7); Bauer 2009 does not restate the neighbourhood (spec 05 §2.1).
- **Question.** (a) What was the lattice spacing, and was the lattice square or hexagonal?
  (b) In 2007, does "second nearest neighbors" mean the Moore (8) neighbourhood or only the
  second shell? (c) Which neighbourhood order was used for copy proposals, for adhesion, and (2009
  only) for the breadth-first continuity search? (spec 05 §7.4 q1; spec 07 §7.3 q1)
- **Our assumption.** We develop with 0.55 µm/pixel, labelled as a hypothesis: the 2009
  degradation rate "(0.55 µm)²" per minute and the 1.1 µm bundle thickness would fit it
  (spec 05 §7.2). The spec says this must not be adopted without your confirmation, so both
  Bauer tutorials are blocked on this answer (specs README §4 B2).
- **What changes.** Every length in both tutorials (domain in pixels, cell size, fibre bundles,
  sprout speed in µm/h or µm/day) and the neighbourhood settings of the model.

### Q2 [B] Bauer 2009: recruitment and phenotype assignment

- **Context.** "a new cell is added to the base of the sprout when and where the previous cell
  detaches from the parent vessel wall" (05 p.4–5). The detachment criterion, the new cell's
  size and shape, and its phenotype are unspecified; so is how tip, stalk and proliferating roles
  are assigned during a run (spec 05 §2.4).
- **Question.** (a) What exact condition triggered adding a new EC at the left wall, with what
  initial volume, shape and phenotype? (b) How was the tip cell designated and updated (for
  example the EC with the largest centre-of-mass x), and could the tip role move to another cell?
  (c) How were cells assigned to stalk vs proliferating? (spec 05 §7.4 q4–q5)
- **Our assumption.** None yet. Our only lead for the tip is Bauer 2007's "the leading
  endothelial cell" (07 p.8; spec 05 §2.4).
- **What changes.** Recruitment and role assignment drive sprout length, thickness and the
  15–20 recruited cells reported (05 p.6); these are the model's main validation targets.

### Q3 [B] Jiang 2005: the Rb → E2F edge in Fig 2 and node meanings

- **Context.** Fig 2 draws Rb → E2F as stimulatory (06 p.4). With the stated update rule, E2F
  would then be on only when both cyclin–CDK complexes are off, i.e. when the CKIs are on — the
  reverse of the biology (spec 06 §7.1 item 2).
- **Question.** Should Rb → E2F be inhibitory? What exactly does each node's on-state mean (for
  example, is "Rb on" active, hypophosphorylated Rb)? (spec 06 §7.3 q2)
- **Our assumption.** Inhibitory, flagged as provisional (specs README §4 J3).
- **What changes.** Whether cells pass the G1 check at all; this is the step-11 gate of our
  build plan and decides every growth curve.

### Q4 [B] Jiang 2005: T, α, θ, γ and lattice size

- **Context.** The temperature T (Eq 2), α and θ in the factor-level sigmoid (Eq 4, 06 p.4), the
  γ used for proliferating cells ("usually … between 1 and 3", 06 p.6), the "large" γ of the
  necrotic core (06 p.3) and the lattice size in voxels are not given (spec 06 §3.3).
- **Question.** What values were used for T, α, θ, γ(P) and γ(N), and how many voxels was the
  lattice? (spec 06 §7.3 q1)
- **Our assumption.** None; without them these would be calibrated, which makes the tutorial a
  reconstruction rather than a reproduction (specs README §1, grade C).
- **What changes.** Replaces calibrated values by stated ones in the parameter table.

### Q5 [B] Jiang 2005: glucose rate 162 vs 216, and Table 1 units

- **Context.** Table 1 gives b₀(P) = 162; the 2006 erratum (Biophys J 91:775) gives 216 (spec 06
  §3.4). With 162, C₀ = 240 ≈ 1.5 × 162 and the quiescent/proliferating ratio ≈ ½ as the text
  says; with 216 neither holds (spec 06 §7.1 item 4). Table 1's metabolic units "mM/h/cm³" are
  dimensionally unclear (spec 06 §7.1 item 8).
- **Question.** Did the published Figs 5–8 use 162 or 216? Should the waste (240) and quiescent
  glucose (80) rates change with it? What are the intended units of Table 1? (spec 06 §7.3 q5)
- **Our assumption.** 162 by default, with an `erratum = true` switch to 216 (specs README §4 J1).
- **What changes.** Which value is the default, and the conversion of all Table 1 rates into
  the field equations.

### Q6 [B] Foam 1999: the shear term in Eq 2 and the γ₀ scale

- **Context.** Eq 2, H′ = H + Σᵢ γ(yᵢ,t) xᵢ (1 − δ_{σᵢσⱼ}) (PRE 59, p.5821), sums over i with j
  free, but the text says it acts "to the wall between neighboring bubbles". Read literally, the
  per-bond cost grows with x up to 256 and is ill-posed on a periodic x axis. The Fig 3(c) regime
  boundaries are straight lines through the origin in (J, γ₀), which points to a
  position-independent per-flip bias of order γ₀ (spec 04 §7 A-1, A-10).
- **Question.** What was the exact per-bond form of the shear term as implemented, and in what
  units is γ₀? (specs README §5, Jiang item 5)
- **Our assumption.** A copy of σⱼ into site i adds γ(yᵢ,t)·(xᵢ − xⱼ) with the minimum-image
  displacement, and γ₀ is calibrated against the Fig 3 regime transition (γ₀/J ≈ 1.9). The
  literal form is kept as a variant (specs README §4 F1). Until this is answered the foam
  tutorial is provisional (build step 4).
- **What changes.** The driving term itself, and whether γ₀ can be taken from the paper instead
  of calibrated.

## Quick questions (non-blocking)

**Q7. Code.** Is the Bauer dissertation code or an input deck still available (spec 05 §7.4
q12; spec 07 §7.3 q11)? Is the 2005 tumour code, or a later CompuCell/Bionet reimplementation,
available for cross-checking (spec 06 §7.3 q12)? *Any of these would settle most of the
questions deferred to batch 2.*

**Q8. Bauer 2007 time scale and baseline proliferation.** Is 1 MCS = 1 h correct (1 min in 2009),
and how many MCS were run for the 16.6-day snapshots (spec 07 §7.3 q2)? In the baseline, was
exactly one cell proliferating, the one immediately behind the tip (spec 07 §7.3 q3)? *We
assume 1 h and adopt "immediately behind" as a flagged inference, because Table 2's baseline
speed matches the Fig 5 "8.9 µm" point (specs README §4 B9).*

**Q9. Bauer 2009 domain.** 166 × 106 µm (Fig 1 caption and axes) or "100 µm by 160 µm" (05 p.6),
and how many pixels (spec 05 §7.4 q2)? *We use 166 × 106 (specs README §4 B3).*

**Q10. Jiang 2005 death branch.** Under unfavourable chemistry, the Fig 3 flow chart kills
proliferating cells, but the text has P → quiescent and Q → necrotic. Which is right, and are
the three necrosis conditions (O₂ < 0.02 mM, glucose < 0.06 mM, lactate > 8 mM) combined with
OR (spec 06 §7.3 q4)? *We follow the text and OR, flagged (specs README §4 J2, J4).*

**Q11. Foam walls and the T = 0 tie.** What were the top and bottom walls (frozen spins, hard
edge, special J; spec 04 §7 A-2)? At T = 0, was a flip with ΔH′ = 0 accepted (Eq 3 puts it in
the exponential branch; A-6)? *We choose the wall whose relaxed ordered foam gives μ₂(n) ≈ 0.44,
and accept ties (specs README §4 F2, F4).*

**Q12. Akeeb et al. 2026 (for Sherif Akeeb).** (1) Which classifier variant generated Fig 5 and
S1 Table? (2) Is the third term of Eq (1) shorthand for the CC3D Merks chemotaxis ΔH that the code
uses? (3) Which repository and commit produced the 13,310 runs (the paper gives two URLs, the
README a third)? (4) Does CC3D sweep at MCS 0, so that metrics at "700" follow 701 sweeps?
(5) Is NeighborTracker adjacency the von Neumann criterion stated in the paper? (6) Were the
λ = 5, 10, 20 runs (2D/3D check, speed calibration) separate from the scan grid? (spec 10 §7,
open questions 1–6) *We follow the released code throughout (specs README §4 A1–A6).*

## Tutorials to share once public

`lib/PottsModels/reproductions/` (TUTORIAL_TEMPLATE naming; all planned): `04_foam.jl` (step 4),
`05_bauer2009_ecm.jl` (step 9), `07_bauer2007_sprouting.jl` (step 8),
`06_jiang2005_tumor.jl` (step 11), `10_akeeb_invasion.jl` (step 2). Each §6 repeats these
questions, and each answer becomes a dated changelog entry and a row of its deviations table.

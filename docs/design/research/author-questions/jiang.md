# Questions for Yi Jiang (with co-authors): foam 1999, Bauer 2007/2009, Jiang 2005, Akeeb 2026

Batch 1 — **draft, not sent.** The maintainer sends this personally. Internal traceability
is in the comment block at the end of the file. This letter covers five papers and can be
split per paper. Q6 (foam) is also asked of James Glazier.

---

Dear Prof. Jiang,

As you know, we are building Potts.jl, an open-source Julia ecosystem for cellular Potts
models. For each of the lab's reference papers we are writing a reproduction with full
provenance: every equation and parameter is traced to a page, figure or code line, and every
choice we make will be listed in a tutorial that we will publish and share with you. We would
like these reproductions to be exact, and to reach that point together with the original
authors.

For five of your papers a few details are not in the published text. Questions 1–6 block a
faithful reproduction; questions 7–12 are quick and can be answered alongside. For each
question we say what we assume in the meantime and what your answer changes. Short answers,
old input files or notes are all very welcome.

## Blocking questions

### Q1 [B] Bauer 2007 and 2009: pixel size, lattice geometry and neighbourhoods

- **Context.** Neither paper states the µm per pixel or the lattice geometry; the VEGF source is
  given in "pg/pixel" (Biophys J 92 (2007) Table 1, p.3110; PLoS Comput Biol 5 (2009) Table 1,
  p.4). The 2007 paper copies from "one of its unlike second nearest neighbors" (p.3111); the
  2009 paper does not restate the neighbourhood.
- **Question.** (a) What was the lattice spacing, and was the lattice square or hexagonal?
  (b) In 2007, does "second nearest neighbors" mean the Moore (8) neighbourhood or only the
  second shell? (c) Which neighbourhood order was used for copy proposals and for adhesion, and
  (2009 only) for the breadth-first continuity search?
- **Our assumption.** We develop with 0.55 µm per pixel, labelled as a hypothesis: the 2009
  degradation rate of "(0.55 µm)²" per minute (p.11) and a 1.1 µm bundle thickness would fit
  it. We will not adopt it without your confirmation, so both Bauer reproductions wait on this
  answer.
- **What changes.** Every length in both reproductions (domain in pixels, cell size, fibre
  bundles, sprout speed) and the neighbourhood settings.

### Q2 [B] Bauer 2009: recruitment and phenotype assignment

- **Context.** "a new cell is added to the base of the sprout when and where the previous cell
  detaches from the parent vessel wall" (p.4–5). The detachment criterion, the new cell's size,
  shape and phenotype, and how tip, stalk and proliferating roles are assigned during a run are
  not stated.
- **Question.** (a) What exact condition triggered adding a new EC at the left wall, with what
  initial volume, shape and phenotype? (b) How was the tip cell designated and updated (for
  example the EC with the largest centre-of-mass x), and could the tip role move to another
  cell? (c) How were cells assigned to stalk vs proliferating?
- **Our assumption.** None yet. Our only lead for the tip is "the leading endothelial cell"
  in the 2007 paper (p.3112).
- **What changes.** Recruitment and role assignment drive sprout length and thickness and the
  15–20 recruited cells reported (p.6), which are the main comparison targets.

### Q3 [B] Jiang 2005: the Rb → E2F edge in Fig 2 and node meanings

- **Context.** Fig 2 (Biophys J 89 (2005) p.3887) draws Rb → E2F as stimulatory. With the stated
  update rule, E2F would then be on only when both cyclin–CDK complexes are off, i.e. when the
  CKIs are on — the reverse of the biology.
- **Question.** Should Rb → E2F be inhibitory? What does each node's on-state mean (for example,
  is "Rb on" active, hypophosphorylated Rb)?
- **Our assumption.** Inhibitory, flagged as provisional.
- **What changes.** Whether cells pass the G1 check at all; every growth curve depends on it.

### Q4 [B] Jiang 2005: T, α, θ, γ and lattice size

- **Context.** The temperature T (Eq 2), α and θ in the factor-level sigmoid (Eq 4, p.3887), the
  γ for proliferating cells ("usually … between 1 and 3", p.3889), the "large" γ of the necrotic
  core (p.3886) and the lattice size in voxels are not given.
- **Question.** What values were used for T, α, θ, γ(P) and γ(N), and how many voxels was the
  lattice?
- **Our assumption.** None; without them these would be calibrated, which makes the result a
  reconstruction rather than a reproduction.
- **What changes.** Calibrated values become stated ones.

### Q5 [B] Jiang 2005: glucose rate 162 vs 216, and how rates are applied

- **Context.** Table 1 (p.3888) gives b₀(P) = 162; the erratum (Biophys J 91 (2006) 775) says it
  should read 216. The erratum also corrects the Table 1 unit to mM/h. With 162, C₀ = 240 ≈ 1.5 ×
  162 and the quiescent-to-proliferating glucose-rate ratio 80/162 ≈ ½, as the text says; with
  216 neither holds.
- **Question.** Did Figs 5–8 use 162 or 216, and should C₀ = 240 and b₀(Q) = 80 change with it?
  How is a rate in mM/h applied to the coarse-grid nodes a cell covers (per cell, or per cell
  volume)?
- **Our assumption.** 162 by default, with a switch to 216.
- **What changes.** The default glucose rate, and the source terms of all Table 1 rates in the
  field equations.

### Q6 [B] Foam 1999: the shear term in Eq 2 and the γ₀ scale

- **Context.** Eq 2, H′ = H + Σᵢ γ(yᵢ,t) xᵢ (1 − δ_{σᵢσⱼ}) (Phys Rev E 59 (1999) p.5821), sums
  over i with j free, but the text applies it "to the wall between neighboring bubbles". Read
  literally, the per-bond cost grows with x and is ill-posed on a periodic x axis. The Fig 3(c)
  regime boundaries are straight lines through the origin in (J, γ₀), which suggests a
  position-independent per-flip bias of order γ₀.
- **Question.** What was the exact per-bond form of the shear term as implemented, and in what
  units is γ₀? I have asked James Glazier the same question; either answer settles it.
- **Our assumption.** A copy of σⱼ into site i adds γ(yᵢ,t)·(xᵢ − xⱼ) with the minimum-image
  displacement, and γ₀ is calibrated to the Fig 3 regime transition (γ₀/J ≈ 1.9). The literal
  form is kept as a variant.
- **What changes.** The driving term itself, and whether γ₀ can be taken from the paper.

## Quick questions (non-blocking)

**Q7. Code.** Is the Bauer dissertation code or an input deck still available? Is the 2005
tumour code, or a later CompuCell or BionetSolver reimplementation, available for
cross-checking? *Either would settle most of our remaining questions.*

**Q8. Bauer 2007 time scale and baseline proliferation.** Is 1 MCS = 1 h correct (1 min in
2009), and how many MCS were run for the 16.6-day snapshots? In the baseline, was exactly one
cell proliferating, the one immediately behind the tip? *We assume 1 h and "immediately behind",
because Table 2's baseline speed matches the Fig 5 "8.9 µm" point.*

**Q9. Bauer 2009 domain.** 166 × 106 µm (Fig 1 caption and axes) or "100 µm by 160 µm" (p.6),
and how many pixels? *We use 166 × 106.*

**Q10. Jiang 2005 death branch.** Under unfavourable chemistry, the Fig 3 flow chart kills
proliferating cells, but the text (p.3887) has P → quiescent and Q → necrotic. Which is right,
and are the three necrosis conditions (O₂ < 0.02 mM, glucose < 0.06 mM, lactate > 8 mM) combined
with OR? *We follow the text and OR.*

**Q11. Foam walls and the T = 0 tie.** What were the top and bottom walls (frozen spins, hard
edge, special J)? At T = 0, was a flip with ΔH′ = 0 accepted (Eq 3 puts it in the exponential
branch)? *We choose the wall whose relaxed ordered foam gives μ₂(n) ≈ 0.44, and accept ties.*

**Q12. Akeeb et al. 2026 (for Sherif Akeeb).** (1) Which classifier variant generated Fig 5 and
S1 Table? (2) Is the third term of Eq (1) shorthand for the CC3D form ΔH = λ(c_source −
c_target), applied once when either cell is a leader? (3) Which repository and commit produced
the 13,310 runs (the paper gives two URLs, the repository README a third)? (4) Does CC3D sweep at
MCS 0, so that metrics at "700" follow 701 sweeps? (5) Is NeighborTracker adjacency the von
Neumann criterion stated in the paper? (6) Were the λ = 5, 10, 20 runs (2D/3D check, speed
calibration) separate from the scan grid? *We follow the released code throughout.*

Once the reproductions of these five papers are published, we will send you the tutorials. Each
of your answers will be recorded there, with a dated entry.

With thanks,
[Maintainer name]

<!-- trace:
Q1: spec 05 §2.1, §7.2, §7.4 q1; spec 07 §2.1, §7.3 q1; specs README §4 B2; README §5 Jiang item 1
Q2: spec 05 §2.4, §7.4 q4–q5; README §5 Jiang item 6
Q3: spec 06 §2.4, §7.1 item 2, §7.3 q2; specs README §4 J3; README §5 Jiang item 2
Q4: spec 06 §2.2, §3.3, §7.3 q1; specs README §1 (grade C); README §5 Jiang item 3
Q5: spec 06 §3.2, §3.4, §7.1 items 4 and 8, §7.3 q5; specs README §4 J1; erratum unit correction per review round 1 (spec 06 §3.4 does not yet record the erratum text); README §5 Jiang item 4
Q6: spec 04 §2.2, §7 A-1, A-10; specs README §4 F1; README §5 Jiang item 5 / Glazier item 6
Q7: spec 05 §7.4 q12; spec 07 §7.3 q11; spec 06 §7.3 q12
Q8: spec 07 §7.1 item 3, §7.3 q2–q3; specs README §4 B9
Q9: spec 05 §7.1 item 1, §7.4 q2; specs README §4 B3
Q10: spec 06 §7.1 item 1, §7.3 q4; specs README §4 J2, J4
Q11: spec 04 §7 A-2, A-6; specs README §4 F2, F4
Q12: spec 10 §2.1, §7 open questions 1–6; specs README §4 A1–A6
Tutorials (planned): 04_foam.jl (step 4), 07_bauer2007_sprouting.jl (step 8), 05_bauer2009_ecm.jl (step 9), 06_jiang2005_tumor.jl (step 11), 10_akeeb_invasion.jl (step 2)
-->

# Questions for Andreas Deutsch and Jörn Starruß: Starruß et al. 2007 (J Stat Phys 128:269), myxobacteria

Batch 1 — **draft, not sent.** The maintainer sends this personally. Citations point to
`docs/design/research/model-specs/13_starruss_myxobacteria.md` ("spec 13 §x") and the specs
README ("specs README §4 Y<n>").

---

Dear Prof. Deutsch and Dr. Starruß,

I am [Maintainer name], and I work on Potts.jl, an open-source Julia ecosystem for cellular
Potts models. We are reproducing your segmented-rod model of *Myxococcus xanthus* collective
migration with full provenance: every equation and parameter is traced to a page or figure,
and every choice we make is listed in a public tutorial.

Table I gives every energy parameter, which makes the model an excellent reproduction target.
A few details of the propulsion term and the simulation protocol are not in the text.
Questions 1–4 block a quantitative reproduction of Ψ̄(κ); 5–7 are quick. We would very much
like to reach an exact reproduction together with you.

With thanks,
[Maintainer name]

---

## Blocking questions

### Q1 [B] Eq 9: is θ a unit vector?

- **Context.** For interior segments, θ_{µ,ν} = ||S_{µ,ν−1} − S_{µ,ν+1}|| (Eq 9, p.275). Double
  bars usually denote a scalar norm, which cannot be a direction (spec 13 §2.4).
- **Question.** Is θ the normalised chord (unit vector) or the raw chord vector?
- **Our assumption.** Unit vector; raw chord as a variant (specs README §4 Y1).
- **What changes.** The propulsion scale by a factor of about 2D ≈ 7, and so the meaning of
  ω = 0.5 E relative to kT = 0.8 E (spec 13 §7 item 1).

### Q2 [B] Eq 7: the sign of the exponent

- **Context.** On the page image the exponent of Eq 7 (p.274) reads ΔH′/kT with no visible minus
  sign; +ΔH′/kT would give p > 1 for every ΔH′ > 0 (spec 13 §2.5).
- **Question.** Is it the standard exp(−ΔH′/kT)?
- **Our assumption.** Yes (spec 13 §7 item 2).
- **What changes.** Nothing if confirmed; we would then record it as a typesetting slip.

### Q3 [B] Eq 10: the term for the losing segment

- **Context.** ΔD(σ(i) → σ(j)) = −ω(d·θ_{σ(i)} + d·θ_{σ(j)}) with d = i − j (p.275). The
  d·θ_{σ(i)} term, for the segment whose node i is overwritten, favours that segment retreating
  *along* d, although losing i moves its centre of mass away from i (spec 13 §7 item 3).
- **Question.** Is Eq 10 exactly what was implemented, including the sign of the loser's term?
- **Our assumption.** As printed (specs README §4 Y4).
- **What changes.** The net propulsion per copy, and hence velocities and cluster formation.

### Q4 [B] Lattice size, MCS and the Ψ̄ protocol

- **Context.** The lattice size, the number of attempts per MCS, the warm-up before sampling,
  the sampling interval and the run lengths behind Ψ̄ (the time-averaged largest-cluster
  fraction, p.282) are not stated (spec 13 §2.5, §2.6, §2.9).
- **Question.** What were they for Figs 5 and 8?
- **Our assumption.** One attempt per lattice site per MCS, as in Graner–Glazier (spec 13 §2.5);
  the rest is our choice and is flagged.
- **What changes.** Finite-size effects on Ψ̄ and the time axis of velocities; without these,
  Ψ̄(κ) can only be compared in shape, not in value (spec 13 §7 item 5).

## Quick questions (non-blocking)

**Q5. "Second-nearest neighbours" for J** (p.275): the first and second hexagonal shells together
(12 sites), or the second shell only (spec 13 §7 item 4)? *We use shells 1+2 (specs README §4
Y3).*

**Q6. κ and the number of segments.** How does κ depend on s? The Fig 5/8 abscissae fit
κ ≈ 0.86 s, and κ ≈ 6 for the *M. xanthus* set (p.282), yet Fig 6 states κ ≈ 10 with that set.
Was s changed for Fig 6 (spec 13 §2.8, §7 item 6)? *We use s = 8 and treat κ ≈ 0.86 s as a
labelled hypothesis (specs README §4 Y6).*

**Q7. Same-cell, non-adjacent contacts.** By Eq 6, two non-adjacent segments of the same cell
that touch pay J_CC. Is that intended, or should it be J_SS or 0 (spec 13 §2.3, §7 item 12)?
*We implement it as printed (specs README §4 Y5).*

## Tutorial to share once public

`lib/PottsModels/reproductions/13_starruss_myxobacteria.jl` (planned, build step 6, following
TUTORIAL_TEMPLATE). Each answer becomes a dated changelog entry and a row of its deviations
table.

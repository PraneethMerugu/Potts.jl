# Questions for Andreas Deutsch and Jörn Starruß: Starruß et al. 2007 (J Stat Phys 128:269), myxobacteria

Batch 1 — **draft, not sent.** The maintainer sends this personally. Internal traceability
is in the comment block at the end of the file.

---

Dear Prof. Deutsch and Dr. Starruß,

I am [Maintainer name], and I work on Potts.jl, an open-source Julia ecosystem for cellular
Potts models. We are reproducing your segmented-rod model of *Myxococcus xanthus* collective
migration with full provenance: every equation and parameter is traced to a page or figure,
and every choice we make will be listed in a tutorial that we will publish and share with you.

Table I gives every energy parameter, which makes the model an excellent reproduction target.
A few details of the propulsion term and the simulation protocol are not in the text. If a model
file exists (Q0), it would answer most of them at once. Otherwise questions 1–3 block a
quantitative reproduction of Ψ̄(κ), and 4–7 are quick. We would very much like to reach an
exact reproduction together with you.

## First, a request

**Q0. Model file.** Is the Morpheus (or pre-Morpheus) model file for the 2007 simulations
available? It would settle Q1–Q4.

## Blocking questions

### Q1 [B] Eq 9: is θ a unit vector?

- **Context.** For interior segments, θ_{µ,ν} = ||S_{µ,ν−1} − S_{µ,ν+1}|| (Eq 9, p.275). Double
  bars usually denote a scalar norm, which cannot be a direction.
- **Question.** Is θ the normalised chord (a unit vector) or the raw chord vector?
- **Our assumption.** Unit vector; the raw chord is kept as a variant.
- **What changes.** The propulsion scale, by a factor of about 2D ≈ 7, and so the meaning of
  ω = 0.5 E relative to kT = 0.8 E.

### Q2 [B] Eq 10: the term for the losing segment

- **Context.** ΔD(σ(i) → σ(j)) = −ω(d·θ_{σ(i)} + d·θ_{σ(j)}) with d = i − j (p.275). The
  d·θ_{σ(i)} term, for the segment whose node i is overwritten, favours that segment retreating
  *along* d, although losing i moves its centre of mass away from i.
- **Question.** Is Eq 10 exactly what was implemented, including the sign of the loser's term?
- **Our assumption.** As printed.
- **What changes.** The net propulsion per copy, and hence velocities and cluster formation.

### Q3 [B] Lattice size, MCS and the Ψ̄ protocol

- **Context.** The lattice size, the number of attempts per MCS, the warm-up before sampling,
  the sampling interval and the run lengths behind Ψ̄ (the time-averaged largest-cluster
  fraction, p.282) are not stated.
- **Question.** What were they for Figs 5 and 8?
- **Our assumption.** One attempt per lattice site per MCS, as in Graner and Glazier; the rest is
  our choice and is flagged.
- **What changes.** Finite-size effects on Ψ̄ and the time axis of velocities. Without these,
  Ψ̄(κ) can be compared only in shape, not in value.

## Quick questions (non-blocking)

**Q4. Eq 7 sign.** The exponent in Eq 7 (p.274) prints without a minus sign; we read it as
exp(−ΔH′/kT). Is that right?

**Q5. "Second-nearest neighbours" for J** (p.275): the first and second hexagonal shells
together (12 sites), or the second shell only? *We use shells 1 and 2.*

**Q6. κ and the number of segments.** How does κ depend on s? The Fig 5 and 8 abscissae fit
κ ≈ 0.86 s, and κ ≈ 6 for the *M. xanthus* set (p.282), yet Fig 6 states κ ≈ 10 with that set.
Was s changed for Fig 6? *We use s = 8 and treat κ ≈ 0.86 s as a labelled hypothesis.*

**Q7. Same-cell, non-adjacent contacts.** By Eq 6, two non-adjacent segments of the same cell
that touch pay J_CC. Is that intended, or should it be J_SS or 0? *We implement it as printed.*

Once the reproduction is published, we will send you the tutorial. Each of your answers will be
recorded there with a dated entry.

With thanks,
[Maintainer name]

<!-- trace:
Q0: added in review round 1 (not in README §5)
Q1: spec 13 §2.4, §7 item 1; specs README §4 Y1; README §5 Deutsch item 1
Q2: spec 13 §2.4, §7 item 3; specs README §4 Y4; README §5 Deutsch item 1
Q3: spec 13 §2.5, §2.6, §2.9, §7 item 5; README §5 Deutsch item 2
Q4: spec 13 §2.5, §7 item 2; README §5 Deutsch item 1 (made non-blocking in review round 1)
Q5: spec 13 §2.2, §2.5, §7 item 4; specs README §4 Y3; README §5 Deutsch item 3
Q6: spec 13 §2.8, §7 item 6; specs README §4 Y6; README §5 Deutsch item 3
Q7: spec 13 §2.3, §7 item 12; specs README §4 Y5; README §5 Deutsch item 3
Tutorial (planned): 13_starruss_myxobacteria.jl, step 6
-->

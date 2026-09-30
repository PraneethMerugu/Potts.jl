# Questions for James A. Glazier: Zajac 2003, Graner & Glazier 1992 (PRL) and Glazier & Graner 1993 (PRE), foam 1999

Batch 1 — **draft, not sent.** The maintainer sends this personally. Internal traceability
is in the comment block at the end of the file.
- Q7 (Graner & Glazier 1992 (PRL) and Glazier & Graner 1993 (PRE)): add François Graner as
  co-addressee or cc.
- Q5 (foam) is also asked of Yi Jiang; the README recommends sending it once, jointly.
- The Fortuna et al. 2020 questions are in the letter to the de Almeida/Thomas group, with
  Prof. Glazier in cc.

---

Dear Prof. Glazier,

I am [Maintainer name], and I work on Potts.jl, an open-source Julia ecosystem for cellular
Potts models. We are reproducing a set of published CPM models, several of them yours, with
full provenance: each equation and parameter is traced to a page, figure or code line, and
every choice we make will be listed in a tutorial that we will publish and share with you. We
would like these reproductions to be exact, and we would much rather get there with the
original authors than guess.

Questions 1–5 block a faithful reproduction; 6–7 are quick. Each says what we assume
meanwhile and what your answer changes. A short reply, a pointer to the thesis, or old input
files would all help a great deal.

## Blocking questions

### Q1 [B] Zajac et al. 2003: numerical parameters

- **Context.** J. Theor. Biol. 222 (2003) gives no values for J (cell–cell, cell–medium), α, λ, κ,
  A∘, a, b, T, the lattice size, the cell count or the neighbour ranges. Only acceptance rates
  (≈46% works, p.255) and relative anisotropies (57% gives two columns, p.254) are stated. The
  paper refers to Zajac's 2002 Notre Dame PhD thesis for details (p.250, p.254).
- **Question.** Is the thesis, or the parameter set behind Fig 5, available?
- **Our assumption.** T is calibrated to ≈46% acceptance and α to 57% anisotropy under a
  definition we state (Q2), and the result is labelled a reconstruction.
- **What changes.** Calibrated values become stated ones, and the result can be called a
  reproduction.

### Q2 [B] Zajac: definition of "57% anisotropy"

- **Context.** "a relative difference of 57% between binding for aligned and unaligned cells"
  (J. Theor. Biol. 222 (2003) p.254) is not defined in terms of Eq 2, J(r,r′) = J_ττ′ −
  Δ(r)Δ(r′) with Δ(r) = α ε r sin θ (p.251).
- **Question.** Is it α²ε²rr′/J_ττ′ at a representative side contact, (J_max − J_min)/J_max over
  contact segments, or something else?
- **Our assumption.** None fixed; α is calibrated under whichever definition we state.
- **What changes.** The α that reproduces the < 35%, 57% and > 65% regimes (p.254).

### Q3 [B] Zajac: contact segments

- **Context.** The simulations "replace individual site coordinates r and θ with average values
  for segments of contact between adjacent cells" (J. Theor. Biol. 222 (2003) p.252).
- **Question.** What is one segment (a maximal run of boundary links between one cell pair, or
  all links of the pair)? Are r and θ averaged, or r sin θ? Is the segment's J multiplied by its
  link count? Which neighbour order defines a link?
- **Our assumption.** Per pair: J = J_ττ′ − α²εε′⟨r sin θ⟩⟨r′ sin θ′⟩ × length.
- **What changes.** The core energy term of the model.

### Q4 [B] Zajac: trial-energy evaluation order

- **Context.** Centroid and orientation change with every copy, so the coupling changes on every
  contact of both cells (J. Theor. Biol. 222 (2003) p.252–253). The paper does not say whether
  the ΔE of a trial copy uses both cells' axes and ε after the trial copy.
- **Question.** Were the post-copy axes of both cells used in the trial ΔE?
- **Our assumption.** Yes: exact per-copy re-evaluation is our reference. A faster variant that
  updates each cell's axis once per MCS is offered only if it gives the same results.
- **What changes.** Whether our reference scheme is the paper's, or itself a deviation.

### Q5 [B] Foam 1999 (with Yi Jiang): the Eq 2 shear term

- **Context.** Eq 2, H′ = H + Σᵢ γ(yᵢ,t) xᵢ (1 − δ_{σᵢσⱼ}) (Phys Rev E 59 (1999) p.5821), sums
  over i with j free, while the text applies it "to the wall between neighboring bubbles".
  Literally, the cost grows with x and is ill-posed on a periodic x axis; the Fig 3(c) regime
  boundaries are lines through the origin in (J, γ₀).
- **Question.** What was the implemented per-bond form, and in what units is γ₀? I have asked
  Yi Jiang the same question; either answer settles it.
- **Our assumption.** ΔH = γ(yᵢ,t)·(xᵢ − xⱼ) per copy (minimum image), with γ₀ calibrated to the
  γ₀/J ≈ 1.9 transition; the literal form is kept as a variant.
- **What changes.** The driving term, and whether γ₀ can be taken from the paper.

## Quick questions (non-blocking)

**Q6. Zajac, three details.** (a) Is the Fig 5 "Extension" λ_b/λ_a (a ratio of second moments,
Appendix A) or a length aspect ratio (≈ √6 ≈ 2.4 if the former reads 6)? (b) Is I in the shape
constraint κ(I − I∘)² the polar moment I_xx + I_yy? (c) How far away can the "randomly selected
nearby site" of a proposal be? *We assume λ_b/λ_a as in Appendix A, and the polar moment.*

**Q7. Graner & Glazier 1992 (PRL) and Glazier & Graner 1993 (PRE), what remains open.** The PRE
answers most of our questions about the set-up. Still open: (a) the lattice size; (b) the
boundary conditions; (c) the paper says types were randomly selected (p.2135) — was each cell
light with probability ½, or were exactly equal numbers assigned? (d) how is the "type-type
correlation" in Figs 13(d) and 21(b) defined? *We use a periodic lattice of our choosing and
equal numbers placed at random, both flagged.*

The remaining foam questions (wall type, T = 0 ties) are in the letter to Yi Jiang; either
author's answer is welcome. Once the reproductions are published, we will send you the
tutorials, and each of your answers will be recorded there with a dated entry.

With thanks,
[Maintainer name]

<!-- trace:
Q1: spec 12 §1, §3, §7 A-Z2; specs README §4 Z2; README §5 Glazier item 1
Q2: spec 12 §2.2, §5 V-Z3, §7 A-Z3; README §5 Glazier item 2
Q3: spec 12 §2.2, §6 G14, §7 A-Z4; README §5 Glazier item 2
Q4: spec 12 §2.2 verdict, §5 lagged-director test, §7 A-Z8; specs README §4 Z1; README §5 Glazier item 2
Q5: spec 04 §2.2, §7 A-1, A-10; specs README §4 F1; README §5 Glazier item 6 / Jiang item 5
Q6: spec 12 §5 metric definitions, §7 A-Z5, A-Z7, A-Z9; specs README §4 Z3; README §5 Glazier item 4
Q7: spec 09 §8.4 (A-GG5 residuals, type-type correlation); tutorial 09_cell_sorting.jl §3, §6; README §5 Glazier item 5
Moved to dealmeida_thomas_dalcastel.md (review round 1): former Q5 (spec 14 §9 items 15, 17; README §5 Glazier item 3)
Tutorials: 09_cell_sorting.jl (exists, pilot); 12_zajac_convergent_extension.jl (planned, step 7); 04_foam.jl (planned, step 4)
-->

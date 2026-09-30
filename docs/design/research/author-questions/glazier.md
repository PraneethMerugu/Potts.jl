# Questions for James A. Glazier: Zajac 2003, Fortuna 2020, Graner–Glazier 1992/1993, foam 1999

Batch 1 — **draft, not sent.** The maintainer sends this personally. Citations point to
`docs/design/research/model-specs/` ("spec NN §x") and its README ("specs README §4 <id>").
Q5 is also asked of the de Almeida group, and Q6 of Yi Jiang; the first answer settles it.

---

Dear Prof. Glazier,

I am [Maintainer name], and I work on Potts.jl, an open-source Julia ecosystem for cellular
Potts models. We are reproducing a set of published CPM models, several of them yours, with
full provenance: each equation and parameter is traced to a page, figure or code line, and
every choice we had to make is listed openly in a public tutorial. We would like these
reproductions to be exact, and we would much rather get there with the original authors than
guess.

Questions 1–6 block a faithful reproduction; 7–8 are quick. Each says what we assume meanwhile
and what your answer changes. A short reply, a pointer to the thesis, or old input files would
all help a great deal.

With thanks,
[Maintainer name]

---

## Blocking questions

### Q1 [B] Zajac et al. 2003: numerical parameters

- **Context.** J. Theor. Biol. 222:247 gives no values for J (cell–cell, cell–medium), α, λ, κ,
  A∘, a, b, T, the lattice size, the cell count or the neighbour ranges; only acceptance rates
  (≈46% works) and relative anisotropies (57% gives two columns) are stated. The paper refers to
  Zajac's 2002 Notre Dame PhD thesis for details (spec 12 §1, §3, §7 A-Z2).
- **Question.** Is the thesis, or the parameter set behind Fig 5, available?
- **Our assumption.** T is calibrated to ≈46% acceptance and α to 57% anisotropy under a stated
  definition (Q2); the tutorial is labelled a reconstruction (specs README §4 Z2).
- **What changes.** Calibrated values become stated ones and the tutorial can drop the
  "reconstruction" label.

### Q2 [B] Zajac: definition of "57% anisotropy"

- **Context.** "a relative difference of 57% between binding for aligned and unaligned cells"
  (12b p.254) is not defined in terms of Eq 2, J(r,r′) = J_ττ′ − Δ(r)Δ(r′) with
  Δ(r) = α ε r sin θ (spec 12 §2.2, §7 A-Z3).
- **Question.** Is it α²ε²rr′/J_ττ′ at a representative side contact, (J_max − J_min)/J_max over
  contact segments, or something else?
- **Our assumption.** None fixed; α is calibrated under whichever definition we state.
- **What changes.** The α that reproduces the 35% / 57% / 65% regimes (spec 12 §5 V-Z3).

### Q3 [B] Zajac: contact segments

- **Context.** The simulations "replace individual site coordinates r and θ with average values
  for segments of contact between adjacent cells" (12b p.252).
- **Question.** What is one segment (a maximal run of boundary links between one cell pair, or all
  links of the pair)? Are r and θ averaged, or r sin θ? Is the segment's J multiplied by its link
  count? Which neighbour order defines a link? (spec 12 §7 A-Z4)
- **Our assumption.** Per pair: J = J_ττ′ − α²εε′⟨r sin θ⟩⟨r′ sin θ′⟩ × length (spec 12 §6 G14).
- **What changes.** The core energy term of the model.

### Q4 [B] Zajac: trial-energy evaluation order

- **Context.** Centroid and orientation change with every copy, so coupling changes on every
  contact of both cells (12b p.252–253). The paper does not say whether ΔE for a trial copy uses
  both cells' axes and ε after the trial copy (spec 12 §7 A-Z8).
- **Question.** Were the post-copy axes of both cells used in the trial ΔE?
- **Our assumption.** Yes (exact per-copy re-evaluation) as the reference; a lagged per-MCS
  director ships only if it passes a pre-registered test (specs README §4 Z1; spec 12 §5).
- **What changes.** Whether the exact scheme is the paper's, or itself a deviation.

### Q5 [B] Fortuna et al. 2020: F-actin at source sites, and the code's provenance

- **Context.** In `SF1_Code.zip`, F-actin is a CC3D `DiffusionSolverFE` field with decay 0.9 and a
  `SecretionOnContact` source 0.9 (spec 14 §2.9.2). Decay-then-secretion gives F ≈ 1 at a source
  site; secretion-then-decay gives F ≈ 0.1 during the next Potts sweep — up to a 10× difference
  in protrusion strength (spec 14 §9 item 15). The Python/XML files are dated 2021-08, after
  publication, and their CC3D version tags disagree (3.7.9 / 3.7.5 / 3.5.1) (spec 14 §9 item 17).
- **Question.** (a) In CC3D 3.7.9, in which order does `DiffusionSolverFE` apply secretion and
  decay, and does `SecretionOnContact` test only face neighbours? (b) Did this exact code produce
  the published figures?
- **Our assumption.** None for (a): this is a blocking gate for quantitative results, and we
  calibrate against Table 2 meanwhile (specs README §4 C4). For (b) we treat the code as the
  figures' source.
- **What changes.** The protrusion scale λ_F-actin·F, hence speeds and Table 2 Fürth fits; for (b),
  whether the two paper–code differences that matter (J_cyto–lamellipodium 20 vs 10; the
  conversion law) become paper facts or code artefacts (spec 14 §9 item 17).

### Q6 [B] Foam 1999 (with Yi Jiang): the Eq 2 shear term

- **Context.** Eq 2, H′ = H + Σᵢ γ(yᵢ,t) xᵢ (1 − δ_{σᵢσⱼ}) (PRE 59, p.5821), sums over i with j
  free while the text applies it "to the wall between neighboring bubbles". Literally, the cost
  grows with x and is ill-posed on periodic x; Fig 3(c) boundaries are lines through the origin
  in (J, γ₀) (spec 04 §7 A-1, A-10).
- **Question.** What was the implemented per-bond form, and in what units is γ₀?
- **Our assumption.** ΔH = γ(yᵢ,t)·(xᵢ − xⱼ) per copy (minimum image), γ₀ calibrated to the
  γ₀/J ≈ 1.9 transition; literal form as a variant (specs README §4 F1).
- **What changes.** The driving term, and whether γ₀ is taken from the paper.

## Quick questions (non-blocking)

**Q7. Zajac, three details.** (a) Is the Fig 5 "Extension" λ_b/λ_a (a ratio of second moments)
or a length aspect ratio (≈√6 ≈ 2.4 if the former reads 6) (A-Z5)? (b) Is I in the shape
constraint κ(I − I∘)² the polar moment I_xx + I_yy (A-Z7)? (c) How far is the "randomly selected
nearby site" for proposals (A-Z9)? (spec 12 §7) *We assume λ_b/λ_a as defined in Appendix A,
and the polar moment (specs README §4 Z3).*

**Q8. Graner & Glazier PRE 1993, what remains open.** Most of our earlier questions are answered
by PRE 47:2128 (spec 09 §8.4). Still open: (a) the lattice size, (b) the boundary conditions,
(c) the dark/light fraction and how it was drawn, and (d) the definition of the "type-type
correlation" in Figs 13(d) and 21(b). *We use a periodic lattice of our choosing and equal
numbers of dark and light cells placed at random, both flagged (tutorial `09_cell_sorting.jl` §3, §6).*

The remaining foam questions (wall type, T = 0 ties) are in the letter to Yi Jiang; either
author's answer is welcome.

## Tutorials to share once public

`lib/PottsModels/reproductions/09_cell_sorting.jl` (Graner–Glazier; exists as a pilot),
`12_zajac_convergent_extension.jl` (step 7), `14_nucleus_migration.jl` (steps 5 and 7b) and
`04_foam.jl` (step 4), all following TUTORIAL_TEMPLATE. Each answer becomes a dated changelog
entry and a row of the deviations table.

# Paper audit, 2026-10-13: "dumb mistakes" across the reproductions

The maintainer asked: "are there other dumb mistakes in the other models". I (the spec owner) ran one reviewer per model against the primary papers, and verified the high-severity items myself where marked ✔. Nothing was edited by the reviewers and nothing was run.

Each finding is routed to an owner:
- **[spec]**: spec owner (this chat);
- **[coord]**: coordinator (code, tests, docs pages);
- **[maint]**: needs the maintainer's decision.

## Foam (04): the trigger for this audit
- ✔ **[spec] My own misread.** In the high-T README I matched Fig 11(a)'s yield strains to the wrong β. The points are at 0.001, 0.005, 0.01, **0.02** and 0.05. Fixed in dabbfdf1.
- **[spec] T1 neighbour relation.** We detect T1s with `VonNeumann(1)`, while the paper's energy and φ use the 20-site shell. Under test now (spec 04 §5.6).
- **[spec] The β = 10⁻³ consistency time is our extrapolation.** It comes from Eq 5 (ε ∝ t) and is not a printed number; the paper's yield strain is a measured displacement (§VI). It does not change any verdict on its own (T = 3 is not "low T"), but it should be noted.

## Implemented models

### 15 OpenVT (submitted)
- ✔ **[maint] False provenance line in the submitted package.** The line "Our precomputed measurements were produced with metrics.cpp built with GCC 13 on Linux" appears in `openvt_package.jl:1040` and `openvt-manuscript-section.md:121` (from D-219). It is not true: every Potts value comes from the Julia port `openvt_metrics`, and the packaging never runs `metrics.cpp`. The port has been checked against `metrics.cpp` only on the consortium's frames, not on ours.
  - Cheap fix: run GCC 13 `metrics.cpp` on our O1 files on the PC and diff the output against `measurements_s*.csv`.
  - If they match, the line is true after the fact. If not, the correction goes to Roman.
- **[coord] Table 1 "nearest sample" wording.** The code takes the nearer end of the first bracketing pair (`15_openvt_sweeps.jl:36–46`). For example, β at 1.1× gives 0.625 where the global-nearest sample would be 0.65. No verdict changes. Reword the notes.
- **[coord] O1 inhibition code is computed after the growth increment** (`openvt_reference.jl:124, 150`), while the model decides on the pre-growth area. The window is about 0.05 px, so the effect is negligible. Note it only.

### 09 Cell sorting
- ✔ **[spec+coord] False deviation on the published page.** V-PRE7's "T = 40 plateaus ≈ 0.1" is a misread from a 110-dpi render.
  - PRE Fig 15(a): the T = 40 curve (solid squares) reads ≈ 0.20 at 300–500, ≈ 0.15 at 10³ and ≈ 0.16 at 2×10³, and **ends at 2×10³**.
  - Ours: 0.162 and 0.135. That matches.
  - The page's "T = 40 keeps falling" deviation (`reproductions/09_cell_sorting.jl:198, 319, 814, 1048`; test header l.5–7) is wrong.
  - Re-target: plateau ≈ 0.15, window [10³, 2×10³]. The 0.07 bar does not separate regimes either (T = 10 and T = 20 both clear it).
- **[spec] T = 0 and T = 15 attributions.** Fig 15 has no T = 0 curve; that rule is text-derived. The T = 15 curve ends near 10³, not 10⁴.

### 01 Merks
- **[spec+coord] V-C4 target at J_cc = 40.** We use 0.3 ± 0.1. 01b Fig 7 reads ≈ 0.40 there, and our own digitisation (`01_merks_01b.jl`) has 0.401. A faithful run sits on the band edge. Ours passed at 0.378.
  - Fix: target 0.40 at J = 40, or drop J = 40 from the plateau set.
- **[spec+coord] V-C5 CI at χ = 500.** The target is 0.35; Fig 8 reads ≈ 0.40 (our digitisation 0.396). Re-centre the target.
- **[coord] `MerksVasculogenesis` docstring** (`merks.jl:11–12, 24–25`). It calls `contact_inhibited = true` "the 2008 model", but the code is the extension-only Eq 4 variant (Figs 11–13). The 2008 standard is extension–retraction, so reword.
- **[spec] Eq 5 sign.** The spec silently corrects the paper's typo; say so.
- **[coord] Tutorial.** "The 2008 paper states N = 200²" should say that number comes from the parameter files.

### 10 Akeeb
- **[coord] Tutorial overstates fidelity.** It calls P1, P5 and P6 "phenotype points of the paper's Fig 4" (`reproductions/10_akeeb.jl:111, 190, 425, 622`). Fig 4 gives no parameters; only P4 matches a named paper point (p.11).
- **[coord] Model docstring** (`akeeb.jl:16–17`) says only clocked followers grow, but the code grows every follower (correct per the authors' code). Fix the wording.
- **[spec] Finger merge boundary.** Peaks exactly 15 px apart are merged (authors' code); the paper's "less than 15" would keep them. Add this to D15.
- **[coord] Test.** `akeeb_observables(prob.u0) == o` cannot catch a leader/follower swap. Test on a swept state instead.
- **[coord] Tutorial.** Two citations (X:55 / X:57) are swapped at `reproductions/10_akeeb.jl:388`.

## Spec-only models (fix before code is written)

### 06 Jiang 2005
- ✔ **[spec] §3.2 uses the old 2.66 µm voxel** (shedding radius 113 voxels, coarse grid 10.6 µm, D_O2 conversion). §8b adopts 4.4 µm, which gives 68 voxels. §8b also never says which Δx the PDE uses, and that choice decides f.
- ✔ **[spec] A3's "zero-parameter" ECM candidates point the wrong way.** Lactate needs (q/D)_eff ≈ 1.8–3.2× the Table value. The geometric ratios 2.7 (area) and 4.5 (volume), applied the natural ways (production diluted by ECM volume; D converted with the smaller voxel), *reduce* q/D. Only a hindered-diffusion (tortuosity) reading gives f > 1, and it predicts neither number.
  - Remove the candidates.
  - Reword author question 4 to ask the direction of the ECM correction.
- **[spec] Fig 8 target.** Only the cell number (8a) saturates early; the volume (8b) tracks the experiment to about 20 d. Fix S6 and T9 (and the plateau value, ≈ 8×10⁴).
- **[spec] A2 excludes lagged rates without quoting p.9.** The paper says "After we calculate chemical concentrations, we adjust the cells' consumption rate". Lagging at the solver's inner step fits that text. Reword the pin.
- **[spec] Clamp.** a, b ≥ 0 below u^T.
- **[spec] Arithmetic.** e⁻¹⁶·10⁷ ≈ 1.1, not ≪ 1. Use 20T.
- **[spec] J1 default.** Paper-over-code (and the erratum) favour 216 as the default, with 162 as the variant.
- **[spec] T6.** The G2 range quotes the experiment, not the simulation.

### 05 / 07 Bauer
- **[spec] 05: the kT < 0.25 "dissociation" check (V16, S1(e), G4) contradicts the p.15 text** ("the continuity constraint circumvents this effect"). Under Metropolis, low kT freezes the lattice. S1(e) fails for every candidate. Drop it, and use "speed rises with kT".
- **[spec] 05: V12 (+20–55 % at ρ = 0.975) and V13/V9 (no invasion at 0.975) cannot both hold.** The paper contradicts itself between Fig 6 and Fig 3F, the Fig 7 caption and p.13. Add this to §7.1 and pick one.
- **[spec] 07: the W1–W5 targets use γ_e/γ_t = 0.7/0.8** (Figs 3/5). W1's SD 2.44 equals Table 2's 0.70 × √12, so they are the same ensemble. This also settles Q13 (SEM). State it, and note the conflict with the Fig 6 caption.
- **[spec] 05 R14.** χ = 1.11×10⁶ is not on the Fig 8 plateau (≈ 10.2 vs 11.2 µm/h). Restate the argument.
- **[spec] 05 V11 snapshot time.** Fig 5 is at 12.5 h, i.e. ≈ 750 MCS, not 840.
- **[spec] 05 V5.** Runs must reach ≈ 15.6 h; stop at boundary contact or about 1200 MCS.
- **[spec] 05 R6.** The uptake-dip formula is dimensionally wrong and the number is about 3× too high. The conclusion stands.
- **[spec] 07.** §2.4's tissue cell (≈ 30 squares, 7–8 µm) contradicts Q9 (24 squares, 9.2 µm). Q11 uses the tissue-cell area for ECs.

### 14 Fortuna (in implementation: P6.5c/d)
- **[spec] The MSD tracks the nucleus centre of mass in xy** (14a-S1 p.10). The spec never states this, and it changes the fitted S, D and P (B5, B6, B8). Also fix the stale "S1/S2 not on disk" lines (l.115, 124).
- **[spec+coord] Starting state under the fixed-target ruling is undefined.** The paper's targets are fixed (V₁ᵗ = φ_n V, V₃ᵗ = φ_l V), so cytoplasm = (1 − φ_n − φ_l)V. The code's starting ball begins about φ_l·V over target (about 4200 sites at R = 15), so the cell would deflate at once.
  - The ruling must also fix the starting cytoplasm size (or keep a transfer).
  - This goes to the P6.5d test author.
- **[spec] Two Table 2 targets are internally inconsistent in the paper.** For R = 15, φ = 0.10, λ = 150, 2DP/(1 − S) is 3.93 vs 1.98 printed. For φ = 0.30, λ = 160 it is 1.92 vs 2.77. Flag B5 and F21; the S = 0.02 headline is safe.
- **[coord] The fixture's p can be NaN.** `p = c*(1 - volume[to]/V_target[to])` is 0/0 when the lamellipodium is absent and V_target(medium) = 0. Write φ_l·V_cell directly.
- **[spec] The starting ball has no z = 0 point** (strict < Rad). Check what `Spheres` does at the boundary.

### 12 Zajac
- **[spec] "Attempt" has two meanings.** Acceptance is per boundary-site attempt (P-Z4), but the sweep is N_sites attempts (l.125, 204) and the cost basis assumes boundary attempts (l.298). The paper uses one word for both. Per-sweep dynamics shift by about 27×, which moves every Fig 5 time target, and the cost rises about 25×.
  - Pick one reading everywhere.
  - Run a 10-kSweep pilot of each against the Fig 5 inset.
- **[spec] S-Z5 D3 is mislabelled.** p = α²εε′ ≈ 0.61α², not α².
- **[spec] §5 still uses λ_b/λ_a and pre-P-Z7 numbers.** Also, Fig 5 starts at about 1.1 and has an unmentioned plateau at about 3.5 (400–470 kSweeps).
- **[spec] G14 formula needs brackets.**

### 13 Starruß
- **[spec] P-S6** (20 % density) is not unique: 30 % at κ ≈ 4 also gives Ψ̄ ≈ 0.63. Downgrade it, or screen both.
- **[spec] The Fig 2 starting energy** differs between V1 (120) and P-S8 (130).

### 11 Multiscale (Jafari Nivlouei 2021)
- **[spec] The implied ITG mapping (cell–ECM contact ≥ 0.3) kills every interior cell.** Fig 3 maps ITG = 0 to apoptosis, but the paper shows a compact tumour with a quiescent core (about 620 cells). Make it an open ambiguity.
- **[spec] Contact inhibition routed through cadherin cannot block growth.** Cadherin ON only turns migration off. It needs its own rule.
- **[spec] Day-1 diameter.** V11a-4 (51 µm on day 1) conflicts with the S1 data (71 µm); 51 µm is the day-0 size.
- **[spec] PDE stability.** D·Δt/Δx² = 3750 for nutrient, so the solver must be steady-state or implicit.
- **[spec] Per-site uptake** (Eq 7) is the paper's form. G6's per-cell preference contradicts it.
- **[spec] Initial cells** are proliferating *and migrating* (code 1101).

### 08 FBCA
- **[spec] Mass conservation.** The Eq 6 operator is non-conservative even at D = 1 when |I| varies. The V08b-5 test must not assert conservation.
- **[spec] C_E definition.** The paper is contradictory (p.284 vs p.287); add it to §7.
- **[spec] SC2-B** is a continuation from SC2-A end states, to MCS 4000.

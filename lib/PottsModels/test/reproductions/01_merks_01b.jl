# P6.3f (ROADMAP Phase 6, step 3; D-156 "Merks"): reproduction 01, the digitised figure
# targets of Merks, Perryn, Shirinifard & Glazier, PLoS Comput Biol 4:e1000163 (2008) ("01b"),
# Figs 5, 7, 8, 9, 10, 12 and 13, through the continuous-χ superset (D-050 M7). Frozen
# (AUTONOMY §7.3). This file is the 01b section of the frozen reproduction-01 test: it adds
# rows and leaves `01_merks.jl` (D-153, D-200) and every one of its rows and verdicts
# unchanged. It is a separate file because the page test (`01_merks_page.jl`, D-184/D-200)
# pins the sha256 of `01_merks.jl` to the FULL record's D-200 amendment.
#
# The paper is the target; the released code is evidence only (D-200). Digitised values are
# in `data/01b/fig*.tsv` (method, pages and uncertainty in `data/01b/README.md`); the
# targets below are copied from them, and the always tier checks that they still agree.
#
# Model and start. `Merks2008` (`mode = :extension_retraction` unless stated), started from
# `merks2008_sprout(; rounds, divisions, seed)` inside its 2-site frame, `SequentialCPM()`,
# `field_solver = ExplicitEuler(substeps = 15)`, solver seed = layout seed = the job's seed,
# exactly as the frozen 01 test's `p63d_run08`.
# Time is the frozen 01 convention: "N MCS" is our state after N MCS from the start of the
# run, which includes the 100 relaxation MCS (TST's loop counter). Fig 12 supports this
# reading: its curves change during the first ≈ 100 MCS, before any chemoattractant exists.
# Sweeps also record N + 100 (the relaxation-end clock, D-156), not gating.
# Observable: O1 compactness (as `p63d_compactness`), and for Fig 13 Σ ΔH over the accepted
# copies, `track = (:ΔH,)` (energy plus the chemotaxis drive, as TST's SumDH; D-17).
#
# | Fig | Curves (paper → ours) | Lattice, start | Grid (targets) | n per point | N (MCS) | Seeds |
# |---|---|---|---|---|---|---|
# | 5 | CI: χcc = r·χcM | 202², rounds 50, divisions 7 (128 cells) | r = 0.05:0.05:0.95 ∪ {0.52, 0.54, 0.56, 0.58} | 10 (caption) | 10⁴ | 310 000 + 100k + i |
# | 7 | CI; no CI = χcc = χcM | as Fig 5 | J_cc (J_cM = 20): CI 2, 10, 20, …, 80; no CI 2, 4, 6, 8, 10, 15, 20, 40, 60, 80 | 10 (inferred) | 5000 | 320 000 / 325 000 + 100k + i |
# | 8 | CI: χcM = x; no CI: χcc = χcM = x | as Fig 5 | CI 0, 200, 500, 1000, 2000, …, 5000; no CI 250, 500, 1000, 2000, …, 5000 | 10 (inferred) | 5000 | 330 000 / 335 000 + 100k + i |
# | 9 | CI: s = x; no CI: s = x, χcc = χcM | as Fig 5 | CI 0, 0.02, 0.03, 0.05, 0.07, …, 0.13, 0.15, 0.2, 0.25; no CI 0:0.05:0.25 | 10 (inferred) | 5000 | 340 000 / 345 000 + 100k + i |
# | 10 | CI128, no CI 128 (χcc = χcM); CI1024 | 128: as Fig 5; 1024: 402², rounds 141, divisions 10 | D (10⁻¹³ m²/s; Dc = 0.75 D): CI128 0.2, 0.5, 1, …, 5; CI1024 0.2, 0.5, 1, 1.5, 2, 3, 4, 4.5, 5; no CI 0.5, 1, 2, 3, 4, 5 | 10 (inferred) | 5000 | 350 000 / 355 000 / 360 000 + 100k + i |
# | 12, 13 | ER50: T = 50; ER200: T = 200; EO200: T = 200, `mode = :extension_only` | 502², rounds 71, divisions 8 (256 cells) | t = 0:50:5100 saved; targets at 100, 250, 500, 750, 1000, 1500, 2000, 3000, 4000, 5000 | 100 (caption) | 5100 | 370 000 / 371 000 / 372 000 + i |
#
# k is the 1-based position of the point in its curve's rows of P63F1B_TARGETS; i = 1:n.
#
# Inferred parameters (D-154/D-155: provisional defaults; each gets a deviations row on the
# page while it stands):
#   I1 Figs 12–13 start: 256 cells as `rounds = 71, divisions = 8` (50·√2 rounds keep TST's
#      ≈ 16 sites per cell at the split; Dataset S1 has no Fig 12 file, D-2).
#   I2 Fig 10's 1024-cell start: `rounds = 141, divisions = 10` (50·√8) on 402² (the caption's
#      "400×400-pixel lattices" plus our 2-site frame; no file, D-2, A-10).
#   I3 n = 10 for Figs 7–10 (their captions give no n; Fig 5's does).
#   I4 "No contact inhibition" is χcc = χcM (TST's `vecadherinknockout`), in every figure.
#   I5 Fig 13's H − H0 is Σ ΔH over the accepted copies including the chemotaxis term (D-17),
#      in Float64; TST truncates each term to an integer (D-7), so only sign, order and
#      magnitude to within √10 are pinned.
#   I6 The time axis includes the 100 relaxation MCS (A-19; Fig 12's early rise supports it).
#   I7 The Fig 10 legend draws the 1024-cell curve solid; the caption says dashed-dotted. The
#      flatter solid curve is read as 1024 cells (the text: 1024-cell clusters sprout for
#      D > 3·10⁻¹³, 128-cell clusters do not).
#
# Bands. Each point's band is the wider of the paper's spread and our digitisation
# uncertainty, rounded up to 0.005:
#   Fig 5: the median error-bar half-length (one SD over 10 runs) of the bars within ±0.02;
#   Figs 7–10: the grey ±1 SD curve read at that x; Fig 12: the grey SD curve, read as 0.03 at
#   1000 MCS and 0.02–0.025 at 5000, so 0.03 for t ≤ 1500 and 0.025 after.
# A ±1 SD band on a mean of n replicates is wide (about 2.2 standard errors of a difference of
# two n = 10 means), so a curve passes when at most max(1, ⌊0.1 n_points⌋) of its points fall
# outside their bands; every point's verdict is still recorded.
#
# | Row | Statistic | Paper | Pass |
# |---|---|---|---|
# | F5.CI, F7.CI, F7.noCI, F8.CI, F8.noCI, F9.CI, F9.noCI, F10.CI128, F10.CI1024, F10.noCI128, F12.ER50, F12.ER200, F12.EO200 | mean C at each target point | P63F1B_TARGETS | ≤ max(1, ⌊0.1 n⌋) points outside paper ± band |
# | F5.mid | crossing of (low + high)/2; low = mean C over r ≤ 0.2, high over r ≥ 0.7 | 0.530 | [0.50, 0.56] (grid 0.02 + SE) |
# | F7.gap | C_noCI(20) − C_CI(20) | 0.545 | ± (SD + SD) = [0.49, 0.60] |
# | F7.rise | C_noCI(15) − C_noCI(2) | 0.499 | [0.419, 0.579] |
# | F8.dropCI | C_CI(0) − C_CI(500) | 0.519 | [0.464, 0.574] |
# | F8.dropNoCI | C_noCI(250) − C_noCI(5000) | 0.270 | [0.19, 0.35] |
# | F9.mid | CI crossing of (low + high)/2; low = s ≤ 0.05, high = s ≥ 0.15 | 0.1066 | [0.0966, 0.1166] (grid 0.01) |
# | F10.size | mean over D ∈ {4, 4.5, 5} of C_CI128 − C_CI1024 | 0.242 | [0.197, 0.287] |
# | F12.order | EO200 > ER200 > ER50 at t = 1500, 2000, 3000, 4000, 5000 | yes | all |
# | F12.rate.<arm> | C(5000) − C(2500) | −0.063, −0.070, −0.081 | ± 0.025 (the SD at 5000) |
# | F13.sign | sign of Σ ΔH at 5000 | ER50 −, ER200 −, EO200 + | all three |
# | F13.order | ER200 < ER50 < 0 < EO200 at t = 2000, 3000, 4000, 5000 | yes | all |
# | F13.mag.<arm> | Σ ΔH(5000) / paper | −3.20, −4.03, +1.19 (10⁸) | ratio in [10^−0.5, 10^0.5] |
#
# Negative controls (D-048), each pre-registered to FAIL its rule on the record:
#   NC-F5   our Fig 5 curve at r = 0.05…0.85 against the paper's value at r + 0.1;
#   NC-F7   our CI curve against the paper's no-CI curve (J_cc 2, 10, 20, 40, 60, 80);
#   NC-F8   our CI curve against the paper's no-CI curve (χcM 500…5000);
#   NC-F9   our CI curve against the paper's no-CI curve (s 0:0.05:0.25);
#   NC-F10  our 1024-cell curve against the paper's 128-cell curve;
#   NC-F12  our ER50 curve against the paper's EO200 curve;
#   NC-F13  the magnitude rule against ten times the paper's values.
# The always tier also runs every rule on the paper's own numbers: rows pass, controls fail.
#
# Not pinned (listed): Fig 6 (V-C12 covers 6E; 6F's velocity and the trajectory panels are
# not digitised); Fig 11 (V-C9 covers it); every inset; Fig 5 at r = 0 and 1 (hidden by the
# frame; V-C3 pins them); Fig 10 below D = 0.2·10⁻¹³ (CI) and 0.5·10⁻¹³ (no CI), where the
# curves are near-vertical; Fig 12 before 100 MCS (the start geometry, I1, dominates); Fig 13's
# magnitude beyond √10 (I5: the model has no integer ΔH truncation; D-7).
#
# Tiers.
# - always: the digitised files, the target table and its bands; the rules on the paper's own
#   numbers (pass) and on perturbed and control comparisons (fail); the job list.
# - SMOKE (PottsModels suite, light): the job functions on 62² with 8 cells for ≤ 300 MCS; the
#   two modes are identical through the relaxation; the D conversion and a run at the
#   explicit-Euler limit (D = 5·10⁻¹³, Dc = 3.75); the 256- and 1024-cell starts.
# - FULL record (always, cheap): reads `reproductions/data/01/full-01b-*` (D-146): `sweeps.tsv`,
#   `series.tsv`, `verdicts.tsv`, `provenance.toml`, optional `deviations.tsv`. It requires
#   exactly the job list once each and recomputes every row and control. A failing row must be
#   in `deviations.tsv` (D-154) and is then `@test_broken`. Until a record exists the tier is
#   `@test_broken`.
# - FULL (POTTS_FULL_REPRODUCTION=true or REPRO=full; offline on the PC, D-156/D-157): runs
#   the 1330 jobs and applies the same rules. Cost from the 2026-10-08 record's walls (107 s
#   per 202² × 5000 MCS job): ≈ 103 thread-hours, ≈ 4.3 h at the 24-thread cap; Figs 12–13
#   (300 runs on 502²) are ≈ 55 of them.
#
# Record schema (tab-separated, one header line):
# - sweeps.tsv: key, fig, curve, x, seed, C_N, C_N100
# - series.tsv: key, arm, seed, t, C, dH            (t = 0:50:5100)
# - verdicts.tsv: row, check, ours, rule, result (PASS | FAIL), control (true | false)
# - deviations.tsv: row, check, suspected_cause, author_question
using Potts, PottsModels, Test, TOML, SHA
using Statistics: mean

const P63F1B_FULL = get(ENV, "POTTS_FULL_REPRODUCTION", "false") == "true" ||
                    get(ENV, "REPRO", "") == "full"
const P63F1B_SOLVER = ExplicitEuler(substeps = 15)
const P63F1B_DIGI = joinpath(@__DIR__, "data", "01b")
const P63F1B_DATA = joinpath(@__DIR__, "..", "..", "reproductions", "data", "01")

# ---------------------------------------------------------------------------------------------
# Targets: (fig, curve, x, paper mean, band). x: Fig 5 χcc/χcM; 7 J_cc; 8 χcM; 9 s;
# 10 D in 10⁻¹³ m²/s; 12 t in MCS.
# ---------------------------------------------------------------------------------------------
const P63F1B_TARGETS = [
    ("F5", "CI", 0.05, 0.346, 0.035),
    ("F5", "CI", 0.1, 0.352, 0.045),
    ("F5", "CI", 0.15, 0.359, 0.035),
    ("F5", "CI", 0.2, 0.346, 0.04),
    ("F5", "CI", 0.25, 0.387, 0.045),
    ("F5", "CI", 0.3, 0.407, 0.04),
    ("F5", "CI", 0.35, 0.411, 0.03),
    ("F5", "CI", 0.4, 0.423, 0.035),
    ("F5", "CI", 0.45, 0.459, 0.03),
    ("F5", "CI", 0.5, 0.541, 0.045),
    ("F5", "CI", 0.52, 0.608, 0.07),
    ("F5", "CI", 0.54, 0.657, 0.075),
    ("F5", "CI", 0.55, 0.669, 0.07),
    ("F5", "CI", 0.56, 0.733, 0.07),
    ("F5", "CI", 0.58, 0.779, 0.065),
    ("F5", "CI", 0.6, 0.846, 0.035),
    ("F5", "CI", 0.65, 0.9, 0.015),
    ("F5", "CI", 0.7, 0.907, 0.015),
    ("F5", "CI", 0.75, 0.92, 0.015),
    ("F5", "CI", 0.8, 0.911, 0.015),
    ("F5", "CI", 0.85, 0.92, 0.015),
    ("F5", "CI", 0.9, 0.92, 0.015),
    ("F5", "CI", 0.95, 0.918, 0.015),
    ("F7", "CI", 2.0, 0.275, 0.05),
    ("F7", "CI", 10.0, 0.3, 0.06),
    ("F7", "CI", 20.0, 0.291, 0.035),
    ("F7", "CI", 30.0, 0.308, 0.035),
    ("F7", "CI", 40.0, 0.401, 0.055),
    ("F7", "CI", 50.0, 0.486, 0.04),
    ("F7", "CI", 60.0, 0.573, 0.04),
    ("F7", "CI", 70.0, 0.731, 0.045),
    ("F7", "CI", 80.0, 0.85, 0.025),
    ("F7", "noCI", 2.0, 0.327, 0.06),
    ("F7", "noCI", 4.0, 0.373, 0.06),
    ("F7", "noCI", 6.0, 0.46, 0.06),
    ("F7", "noCI", 8.0, 0.575, 0.1),
    ("F7", "noCI", 10.0, 0.735, 0.07),
    ("F7", "noCI", 15.0, 0.826, 0.02),
    ("F7", "noCI", 20.0, 0.836, 0.02),
    ("F7", "noCI", 40.0, 0.829, 0.02),
    ("F7", "noCI", 60.0, 0.816, 0.02),
    ("F7", "noCI", 80.0, 0.8, 0.03),
    ("F8", "CI", 0.0, 0.915, 0.015),
    ("F8", "CI", 200.0, 0.549, 0.05),
    ("F8", "CI", 500.0, 0.396, 0.04),
    ("F8", "CI", 1000.0, 0.305, 0.03),
    ("F8", "CI", 2000.0, 0.23, 0.02),
    ("F8", "CI", 3000.0, 0.207, 0.015),
    ("F8", "CI", 4000.0, 0.197, 0.02),
    ("F8", "CI", 5000.0, 0.19, 0.02),
    ("F8", "noCI", 250.0, 0.945, 0.01),
    ("F8", "noCI", 500.0, 0.921, 0.015),
    ("F8", "noCI", 1000.0, 0.864, 0.025),
    ("F8", "noCI", 2000.0, 0.811, 0.04),
    ("F8", "noCI", 3000.0, 0.759, 0.05),
    ("F8", "noCI", 4000.0, 0.71, 0.06),
    ("F8", "noCI", 5000.0, 0.675, 0.07),
    ("F9", "CI", 0.0, 0.378, 0.04),
    ("F9", "CI", 0.02, 0.402, 0.04),
    ("F9", "CI", 0.03, 0.374, 0.04),
    ("F9", "CI", 0.05, 0.404, 0.04),
    ("F9", "CI", 0.07, 0.418, 0.05),
    ("F9", "CI", 0.08, 0.443, 0.06),
    ("F9", "CI", 0.09, 0.517, 0.06),
    ("F9", "CI", 0.1, 0.576, 0.1),
    ("F9", "CI", 0.11, 0.717, 0.1),
    ("F9", "CI", 0.12, 0.856, 0.06),
    ("F9", "CI", 0.13, 0.905, 0.035),
    ("F9", "CI", 0.15, 0.938, 0.01),
    ("F9", "CI", 0.2, 0.952, 0.01),
    ("F9", "CI", 0.25, 0.958, 0.01),
    ("F9", "noCI", 0.0, 0.92, 0.01),
    ("F9", "noCI", 0.05, 0.946, 0.01),
    ("F9", "noCI", 0.1, 0.959, 0.01),
    ("F9", "noCI", 0.15, 0.963, 0.01),
    ("F9", "noCI", 0.2, 0.967, 0.01),
    ("F9", "noCI", 0.25, 0.964, 0.01),
    ("F10", "CI128", 0.2, 0.199, 0.03),
    ("F10", "CI128", 0.5, 0.308, 0.03),
    ("F10", "CI128", 1.0, 0.394, 0.05),
    ("F10", "CI128", 1.5, 0.462, 0.04),
    ("F10", "CI128", 2.0, 0.51, 0.04),
    ("F10", "CI128", 2.5, 0.615, 0.045),
    ("F10", "CI128", 3.0, 0.743, 0.05),
    ("F10", "CI128", 3.5, 0.821, 0.04),
    ("F10", "CI128", 4.0, 0.887, 0.03),
    ("F10", "CI128", 4.5, 0.908, 0.03),
    ("F10", "CI128", 5.0, 0.907, 0.03),
    ("F10", "CI1024", 0.2, 0.3, 0.02),
    ("F10", "CI1024", 0.5, 0.378, 0.02),
    ("F10", "CI1024", 1.0, 0.465, 0.015),
    ("F10", "CI1024", 1.5, 0.495, 0.015),
    ("F10", "CI1024", 2.0, 0.522, 0.02),
    ("F10", "CI1024", 3.0, 0.583, 0.015),
    ("F10", "CI1024", 4.0, 0.633, 0.015),
    ("F10", "CI1024", 4.5, 0.66, 0.015),
    ("F10", "CI1024", 5.0, 0.683, 0.015),
    ("F10", "noCI128", 0.5, 0.833, 0.03),
    ("F10", "noCI128", 1.0, 0.92, 0.015),
    ("F10", "noCI128", 2.0, 0.953, 0.01),
    ("F10", "noCI128", 3.0, 0.961, 0.01),
    ("F10", "noCI128", 4.0, 0.963, 0.01),
    ("F10", "noCI128", 5.0, 0.963, 0.01),
    ("F12", "ER50", 100.0, 0.962, 0.03),
    ("F12", "ER50", 250.0, 0.939, 0.03),
    ("F12", "ER50", 500.0, 0.862, 0.03),
    ("F12", "ER50", 750.0, 0.718, 0.03),
    ("F12", "ER50", 1000.0, 0.601, 0.03),
    ("F12", "ER50", 1500.0, 0.517, 0.03),
    ("F12", "ER50", 2000.0, 0.483, 0.025),
    ("F12", "ER50", 3000.0, 0.443, 0.025),
    ("F12", "ER50", 4000.0, 0.416, 0.025),
    ("F12", "ER50", 5000.0, 0.397, 0.025),
    ("F12", "ER200", 100.0, 0.92, 0.03),
    ("F12", "ER200", 250.0, 0.888, 0.03),
    ("F12", "ER200", 500.0, 0.818, 0.03),
    ("F12", "ER200", 750.0, 0.739, 0.03),
    ("F12", "ER200", 1000.0, 0.66, 0.03),
    ("F12", "ER200", 1500.0, 0.566, 0.03),
    ("F12", "ER200", 2000.0, 0.524, 0.025),
    ("F12", "ER200", 3000.0, 0.48, 0.025),
    ("F12", "ER200", 4000.0, 0.449, 0.025),
    ("F12", "ER200", 5000.0, 0.429, 0.025),
    ("F12", "EO200", 100.0, 0.92, 0.03),
    ("F12", "EO200", 250.0, 0.903, 0.03),
    ("F12", "EO200", 500.0, 0.874, 0.03),
    ("F12", "EO200", 750.0, 0.838, 0.03),
    ("F12", "EO200", 1000.0, 0.789, 0.03),
    ("F12", "EO200", 1500.0, 0.68, 0.03),
    ("F12", "EO200", 2000.0, 0.601, 0.025),
    ("F12", "EO200", 3000.0, 0.536, 0.025),
    ("F12", "EO200", 4000.0, 0.504, 0.025),
    ("F12", "EO200", 5000.0, 0.481, 0.025)
]
# Fig 13 (10⁸ energy units, at 5000 MCS; read at 4950 and extended by the local slope)
const P63F1B_F13 = Dict("ER50" => -3.20, "ER200" => -4.03, "EO200" => 1.19)
const P63F1B_ARMS = Dict("ER50" => (T = 50.0, mode = :extension_retraction),
    "ER200" => (T = 200.0, mode = :extension_retraction), "EO200" =>
        (T = 200.0, mode = :extension_only))
const P63F1B_BASE = Dict(
    ("F5", "CI") => 310_000, ("F7", "CI") => 320_000, ("F7", "noCI") => 325_000,
    ("F8", "CI") => 330_000, ("F8", "noCI") => 335_000, ("F9", "CI") => 340_000, (
        "F9", "noCI") => 345_000,
    ("F10", "CI128") => 350_000, ("F10", "noCI128") => 355_000, ("F10", "CI1024") =>
        360_000,
    ("F12", "ER50") => 370_000, ("F12", "ER200") => 371_000, ("F12", "EO200") => 372_000)
const P63F1B_N_SWEEP = 10
const P63F1B_N_SERIES = 100
const P63F1B_SERIES_T = 0:50:5100

p63f1b_curves() = unique([(t[1], t[2]) for t in P63F1B_TARGETS])
p63f1b_points(fig, curve) = [t for t in P63F1B_TARGETS if t[1] == fig && t[2] == curve]
function p63f1b_target(fig, curve, x)
    only(t for t in P63F1B_TARGETS if t[1] == fig && t[2] == curve && t[3] == x)
end
p63f1b_allowed(n) = max(1, floor(Int, 0.1n))
"""
D (10⁻¹³ m²/s) → `Dc` (lattice units per MCS): D · 30 s / (2 µm)² = 0.75 D.
"""
p63f1b_Dc(D) = 0.75 * D

# ---------------------------------------------------------------------------------------------
# Observable (the frozen 01 test's O1, restated so this file stands alone)
# ---------------------------------------------------------------------------------------------
p63f1b_cross(o, a, b) = (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
function p63f1b_hull_area(pts)
    P = sort(unique(pts))
    length(P) < 3 && return 0.0
    chain(Q) = foldl(Q; init = eltype(Q)[]) do h, q
        while length(h) >= 2 && p63f1b_cross(h[end - 1], h[end], q) <= 0
            pop!(h)
        end
        push!(h, q)
    end
    h = [chain(P)[1:(end - 1)]; chain(reverse(P))[1:(end - 1)]]
    length(h) < 3 && return 0.0
    return abs(sum(
        k -> h[k][1] * h[mod1(k + 1, end)][2] -
             h[mod1(k + 1, end)][1] * h[k][2], eachindex(h))) / 2
end
"""
O1: endothelial sites (σ ≥ 2) over the convex-hull area of their centres.
"""
function p63f1b_compactness(σ)
    (pts = [(I[1], I[2]) for I in findall(>=(2), σ)]; length(pts) / p63f1b_hull_area(pts))
end
function p63f1b_crossing(xs, ys, level)
    for k in 1:(length(xs) - 1)
        a, b = ys[k] - level, ys[k + 1] - level
        a == 0 && return xs[k]
        a * b < 0 && return xs[k] + (xs[k + 1] - xs[k]) * a / (a - b)
    end
    return nothing
end

# ---------------------------------------------------------------------------------------------
# Protocol
# ---------------------------------------------------------------------------------------------
p63f1b_J(Jcc) = [0.0 20.0 0.0; 20.0 Jcc 100.0; 0.0 100.0 0.0]
"""
The set-up of one sweep point: parameters, lattice, start and N.
"""
function p63f1b_setup(fig, curve, x)
    lattice, rounds, divisions, N = (202, 202), 50, 7, 5000
    p = Pair{Symbol, Any}[]
    if fig == "F5"
        push!(p, :χcc => 500.0 * x)
        N = 10_000
    elseif fig == "F7"
        push!(p, :J => p63f1b_J(x))
        curve == "noCI" && push!(p, :χcc => 500.0)
    elseif fig == "F8"
        push!(p, :χcM => x)
        curve == "noCI" && push!(p, :χcc => x)
    elseif fig == "F9"
        push!(p, :s => x)
        curve == "noCI" && push!(p, :χcc => 500.0)
    elseif fig == "F10"
        push!(p, :Dc => p63f1b_Dc(x))
        curve == "noCI128" && push!(p, :χcc => 500.0)
        curve == "CI1024" && ((lattice, rounds, divisions) = ((402, 402), 141, 10))
    else
        throw(ArgumentError("not a sweep: $fig"))
    end
    return (; p, lattice, rounds, divisions, N, mode = :extension_retraction)
end
"""
The set-up of one Fig 12/13 arm.
"""
function p63f1b_arm_setup(arm; lattice = (502, 502), rounds = 71, divisions = 8)
    (; p = Pair{Symbol, Any}[:T => P63F1B_ARMS[arm].T],
        lattice, rounds, divisions, mode = P63F1B_ARMS[arm].mode)
end

"""
Run one start to `maximum(saves)`; at each save record (C, Σ ΔH or nothing). Returns the
records and the integrator.
"""
function p63f1b_run(seed, set, saves; track = false)
    op = layout(merks2008_sprout(; rounds = set.rounds, divisions = set.divisions, seed), set.lattice)
    tend = maximum(saves)
    prob = PottsProblem(Merks2008(; name = :m8b, lattice = set.lattice, mode = set.mode),
        [op; set.p...], (0, tend);
        field_solver = P63F1B_SOLVER, seed, track = track ? (:ΔH,) : ())
    integ = init(prob, SequentialCPM(); save_start = false, save_end = false)
    out = Dict{Int, Tuple{Float64, Union{Nothing, Float64}}}()
    record!(t) = (out[t] = (p63f1b_compactness(Array(integ.u.σ)), integ.stats.accepted_ΔH))
    0 in saves && record!(0)
    while integ.t < tend
        step!(integ)
        t = round(Int, integ.t)
        t in saves && record!(t)
    end
    return out, integ
end

"""
The pre-registered job list: sweep jobs (fig, curve, x, seed) and series jobs (arm, seed).
"""
function p63f1b_jobs()
    sweeps = NamedTuple{(:fig, :curve, :x, :seed), Tuple{String, String, Float64, Int}}[]
    series = NamedTuple{(:arm, :seed), Tuple{String, Int}}[]
    for (fig, curve) in p63f1b_curves()
        fig == "F12" && continue
        for (k, t) in enumerate(p63f1b_points(fig, curve)), i in 1:P63F1B_N_SWEEP

            push!(sweeps, (;
                fig, curve, x = t[3], seed = P63F1B_BASE[(fig, curve)] + 100k + i))
        end
    end
    for arm in ("ER50", "ER200", "EO200"), i in 1:P63F1B_N_SERIES

        push!(series, (; arm, seed = P63F1B_BASE[("F12", arm)] + i))
    end
    return (; sweeps, series)
end
function p63f1b_key(j::NamedTuple{(:fig, :curve, :x, :seed)})
    "$(j.fig)_$(j.curve)_$(j.x)_s$(j.seed)"
end
p63f1b_key(j::NamedTuple{(:arm, :seed)}) = "F12_$(j.arm)_s$(j.seed)"

"""
One sweep job: (C at N, C at N + 100).
"""
function p63f1b_sweep_job(j)
    set = p63f1b_setup(j.fig, j.curve, j.x)
    out, _ = p63f1b_run(j.seed, set, (set.N, set.N + 100))
    return (C_N = out[set.N][1], C_N100 = out[set.N + 100][1])
end
"""
One series job: [(t, C, ΣΔH)] at P63F1B_SERIES_T.
"""
function p63f1b_series_job(j; set = p63f1b_arm_setup(j.arm), saves = P63F1B_SERIES_T)
    out, _ = p63f1b_run(j.seed, set, saves; track = true)
    return [(t = t, C = out[t][1], dH = out[t][2]) for t in saves]
end

# ---------------------------------------------------------------------------------------------
# Rules. msweep[(fig, curve, x)] = mean C at N; mseries[(arm, t)] = (C = mean C, dH = mean ΣΔH).
# Returns [(row, check, ours, rule, ok, control)].
# ---------------------------------------------------------------------------------------------
function p63f1b_points_rule(ours, refs)
    # refs: [(label, key of ours, paper, band)]
    out = [(label = r[1], ours = ours(r[2]), paper = r[3], band = r[4]) for r in refs]
    nout = count(o -> !(abs(o.ours - o.paper) <= o.band), out)
    return (; ok = nout <= p63f1b_allowed(length(out)), nout, n = length(out), out)
end
p63f1b_fmt(x) = string(round(x; sigdigits = 4))

function p63f1b_verdicts(msweep, mseries)
    V = NamedTuple{(:row, :check, :ours, :rule, :ok, :control),
        Tuple{String, String, String, String, Bool, Bool}}[]
    add!(row, check, ours, rule, ok; control = false) = push!(V, (;
        row, check, ours, rule, ok, control))
    S(fig, curve, x) = msweep[(fig, curve, Float64(x))]
    C12(arm, t) = mseries[(arm, Int(t))].C
    H13(arm, t) = mseries[(arm, Int(t))].dH / 1e8
    # point rows
    for (fig, curve) in p63f1b_curves()
        pts = p63f1b_points(fig, curve)
        ours = fig == "F12" ? (k -> C12(curve, k)) : (k -> S(fig, curve, k))
        r = p63f1b_points_rule(ours, [(string(t[3]), t[3], t[4], t[5]) for t in pts])
        for o in r.out
            add!("$fig.$curve", "point $(o.label)", p63f1b_fmt(o.ours),
                "|C − $(o.paper)| ≤ $(o.band)", abs(o.ours - o.paper) <= o.band;
                control = false)
        end
        add!("$fig.$curve", "points outside band",
            "$(r.nout)/$(r.n)", "≤ $(p63f1b_allowed(r.n))", r.ok)
    end
    inrange(v, lo, hi) = lo <= v <= hi
    # F5.mid
    f5 = p63f1b_points("F5", "CI")
    xs = [t[3] for t in f5]
    ys = [S("F5", "CI", x) for x in xs]
    low = mean(S("F5", "CI", x) for x in (0.05, 0.1, 0.15, 0.2))
    high = mean(S("F5", "CI", x) for x in (0.7, 0.75, 0.8, 0.85, 0.9, 0.95))
    mid = p63f1b_crossing(xs, ys, (low + high) / 2)
    add!("F5.mid", "midpoint of the transition",
        mid === nothing ? "none" : p63f1b_fmt(mid), "in [0.50, 0.56]",
        mid !== nothing && inrange(mid, 0.50, 0.56))
    v = S("F7", "noCI", 20) - S("F7", "CI", 20)
    add!("F7.gap", "C_noCI(20) − C_CI(20)", p63f1b_fmt(v),
        "in [0.49, 0.60]", inrange(v, 0.49, 0.60))
    v = S("F7", "noCI", 15) - S("F7", "noCI", 2)
    add!("F7.rise", "C_noCI(15) − C_noCI(2)", p63f1b_fmt(v),
        "in [0.419, 0.579]", inrange(v, 0.419, 0.579))
    v = S("F8", "CI", 0) - S("F8", "CI", 500)
    add!("F8.dropCI", "C_CI(0) − C_CI(500)", p63f1b_fmt(v),
        "in [0.464, 0.574]", inrange(v, 0.464, 0.574))
    v = S("F8", "noCI", 250) - S("F8", "noCI", 5000)
    add!("F8.dropNoCI", "C_noCI(250) − C_noCI(5000)",
        p63f1b_fmt(v), "in [0.19, 0.35]", inrange(v, 0.19, 0.35))
    f9 = p63f1b_points("F9", "CI")
    xs = [t[3] for t in f9]
    ys = [S("F9", "CI", x) for x in xs]
    low = mean(S("F9", "CI", x) for x in (0.0, 0.02, 0.03, 0.05))
    high = mean(S("F9", "CI", x) for x in (0.15, 0.2, 0.25))
    mid = p63f1b_crossing(xs, ys, (low + high) / 2)
    add!("F9.mid", "CI midpoint in s",
        mid === nothing ? "none" : p63f1b_fmt(mid), "in [0.0966, 0.1166]",
        mid !== nothing && inrange(mid, 0.0966, 0.1166))
    v = mean(S("F10", "CI128", D) - S("F10", "CI1024", D) for D in (4.0, 4.5, 5.0))
    add!("F10.size", "mean C_CI128 − C_CI1024 at D = 4, 4.5, 5",
        p63f1b_fmt(v), "in [0.197, 0.287]", inrange(v, 0.197, 0.287))
    ok = all(t -> C12("EO200", t) > C12("ER200", t) > C12("ER50", t), (
        1500, 2000, 3000, 4000, 5000))
    add!("F12.order", "EO200 > ER200 > ER50 at 1500–5000", string(ok), "true", ok)
    for (arm, paper) in (("ER50", -0.063), ("ER200", -0.070), ("EO200", -0.081))
        v = C12(arm, 5000) - C12(arm, 2500)
        add!("F12.rate.$arm", "C(5000) − C(2500)", p63f1b_fmt(v),
            "$paper ± 0.025", abs(v - paper) <= 0.025)
    end
    ok = H13("ER50", 5000) < 0 && H13("ER200", 5000) < 0 && H13("EO200", 5000) > 0
    add!("F13.sign", "signs of ΣΔH at 5000",
        join(p63f1b_fmt.(H13.(("ER50", "ER200", "EO200"), 5000)), ", "), "−, −, +", ok)
    ok = all(t -> H13("ER200", t) < H13("ER50", t) < 0 < H13("EO200", t), (
        2000, 3000, 4000, 5000))
    add!("F13.order", "ER200 < ER50 < 0 < EO200 at 2000–5000", string(ok), "true", ok)
    lo, hi = 10^-0.5, 10^0.5
    for arm in ("ER50", "ER200", "EO200")
        q = H13(arm, 5000) / P63F1B_F13[arm]
        add!("F13.mag.$arm", "ΣΔH(5000) / paper", p63f1b_fmt(q),
            "in [0.316, 3.16]", inrange(q, lo, hi))
    end
    # negative controls (each must fail)
    ctl!(row, r) = add!(row, "points outside band", "$(r.nout)/$(r.n)",
        "≤ $(p63f1b_allowed(r.n)) (must fail)", r.ok; control = true)
    sh = [t for t in f5 if t[3] <= 0.85 + 1e-9 && isinteger(round(t[3] / 0.05; digits = 6))]       # r = 0.05:0.05:0.85
    ctl!("NC-F5",
        p63f1b_points_rule(x -> S("F5", "CI", x),
            [(string(t[3]), t[3], only(u[4] for u in f5 if u[3] ≈ t[3] + 0.1), t[5])
             for t in sh]))
    for (row, fig, a, b, xs) in ((
        "NC-F7", "F7", "CI", "noCI", (2.0, 10.0, 20.0, 40.0, 60.0, 80.0)),
        ("NC-F8", "F8", "CI", "noCI", (500.0, 1000.0, 2000.0, 3000.0, 4000.0, 5000.0)),
        ("NC-F9", "F9", "CI", "noCI", (0.0, 0.05, 0.1, 0.15, 0.2, 0.25)),
        ("NC-F10", "F10", "CI1024", "CI128", (0.2, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 4.5, 5.0)))
        ctl!(row,
            p63f1b_points_rule(x -> S(fig, a, x),
                [(string(x), x, p63f1b_target(fig, b, x)[4], p63f1b_target(fig, a, x)[5])
                 for x in xs]))
    end
    ctl!("NC-F12",
        p63f1b_points_rule(t -> C12("ER50", t),
            [(string(t[3]), t[3], p63f1b_target("F12", "EO200", t[3])[4], t[5])
             for t in p63f1b_points("F12", "ER50")]))
    ok = all(arm -> inrange(H13(arm, 5000) / (10 * P63F1B_F13[arm]), lo, hi), (
        "ER50", "ER200", "EO200"))
    add!("NC-F13", "ΣΔH(5000) / (10 × paper) in [0.316, 3.16] for all arms",
        string(ok), "true (must fail)", ok; control = true)
    return V
end
"""
Means of the paper's own numbers, in the shape the rules read.
"""
function p63f1b_paper_means()
    msweep = Dict((t[1], t[2], t[3]) => t[4] for t in P63F1B_TARGETS if t[1] != "F12")
    mseries = Dict{Tuple{String, Int}, NamedTuple{(:C, :dH), Tuple{Float64, Float64}}}()
    f13 = p63f1b_tsv(joinpath(P63F1B_DIGI, "fig13.tsv"))
    for t in P63F1B_TARGETS
        t[1] == "F12" || continue
        mseries[(t[2], Int(t[3]))] = (C = t[4], dH = NaN)
    end
    for arm in ("ER50", "ER200", "EO200"), tt in (2500,)

        f12 = p63f1b_tsv(joinpath(P63F1B_DIGI, "fig12.tsv"))
        r = only(r for r in f12 if r["curve"] == arm && r["x"] == string(tt))
        mseries[(arm, tt)] = (C = parse(Float64, r["y"]), dH = NaN)
    end
    for r in f13
        k = (r["curve"], parse(Int, r["x"]))
        c = haskey(mseries, k) ? mseries[k].C : NaN
        mseries[k] = (C = c, dH = parse(Float64, r["y"]) * 1e8)
    end
    return msweep, mseries
end

function p63f1b_tsv(path)
    lines = filter(!isempty, split(read(path, String), '\n'))
    h = split(lines[1], '\t')
    return [Dict(zip(h, split(l, '\t'))) for l in lines[2:end]]
end
p63f1b_up(v; q = 0.005) = ceil(round(v / q; digits = 6)) * q

# ---------------------------------------------------------------------------------------------
# Always: the digitised data, the targets, the rules, the job list
# ---------------------------------------------------------------------------------------------
@testset "01b digitised data and targets" begin
    figs = Dict("F5" => "fig05.tsv", "F7" => "fig07.tsv", "F8" => "fig08.tsv",
        "F9" => "fig09.tsv", "F10" => "fig10.tsv",
        "F12" => "fig12.tsv")
    cols = ["figure", "page", "panel", "curve", "x_name", "x", "x_unit",
        "y_name", "y", "y_unit", "sd", "sd_source", "unc_x",
        "unc_y", "note"]
    for f in [collect(values(figs)); "fig13.tsv"]
        @test isfile(joinpath(P63F1B_DIGI, f))
        @test split(first(eachline(joinpath(P63F1B_DIGI, f))), '\t') == cols
    end
    @test isfile(joinpath(P63F1B_DIGI, "README.md"))
    @test length(P63F1B_TARGETS) == 133 &&
          allunique([(t[1], t[2], t[3]) for t in P63F1B_TARGETS])
    for t in P63F1B_TARGETS
        rows = p63f1b_tsv(joinpath(P63F1B_DIGI, figs[t[1]]))
        r = [r for r in rows if r["curve"] == t[2] && parse(Float64, r["x"]) == t[3]]
        @test length(r) == 1
        length(r) == 1 || continue
        r = only(r)
        @test parse(Float64, r["y"]) == t[4]
        unc = parse(Float64, r["unc_y"])
        if t[1] == "F5"                   # median bar SD within ±0.02
            sds = [parse(Float64, q["sd"])
                   for q in rows if abs(parse(Float64, q["x"]) - t[3]) <= 0.02 + 1e-9]
            sort!(sds)
            med = isodd(length(sds)) ? sds[(end + 1) ÷ 2] :
                  (sds[end ÷ 2] + sds[end ÷ 2 + 1]) / 2
            @test t[5] ≈ p63f1b_up(max(med, unc)) atol = 1e-9
        elseif t[1] == "F12"
            @test t[5] ≈ p63f1b_up(max(t[3] <= 1500 ? 0.03 : 0.025, unc)) atol = 1e-9
        else
            @test t[5] ≈ p63f1b_up(max(parse(Float64, r["sd"]), unc)) atol = 1e-9
        end
    end
    f13 = p63f1b_tsv(joinpath(P63F1B_DIGI, "fig13.tsv"))
    for (arm, v) in P63F1B_F13
        @test parse(Float64, only(r
        for r in f13 if r["curve"] == arm && r["x"] == "5000")["y"]) == v
    end
    # the observable on hand-built states (as the frozen 01 test)
    σ = zeros(Int32, 20, 20);
    σ[5:14, 5:14] .= 2
    @test p63f1b_compactness(σ) ≈ 100 / 81
    σ = zeros(Int32, 20, 20);
    σ[10, 3:17] .= 2;
    σ[3:17, 10] .= 3
    @test p63f1b_compactness(σ) ≈ 29 / 98
    isdefined(Main, :p63d_compactness) &&
        @test p63f1b_compactness(σ) == Main.p63d_compactness(σ)
    # the D conversion: 10⁻¹³ m²/s × 30 s / (2·10⁻⁶ m)² = 0.75, the model's default Dc
    @test p63f1b_Dc(1.0) == 0.75 && p63f1b_Dc(5.0) == 3.75
end

@testset "01b rules on the paper's own numbers" begin
    msweep, mseries = p63f1b_paper_means()
    V = p63f1b_verdicts(msweep, mseries)
    rows = filter(v -> !v.control && !startswith(v.check, "point "), V)
    @test length(rows) == 13 + 7 + 1 + 3 + 2 + 3                          # point rows, shape rows, F12, F13
    for v in rows
        @test v.ok
    end
    ctls = filter(v -> v.control, V)
    @test length(ctls) == 7
    @test all(v -> !v.ok, ctls)                                           # every control fails
    # a curve moved by twice its bands fails; a single point moved still passes (≤ 1 allowed)
    m2 = copy(msweep)
    for t in p63f1b_points("F7", "CI")
        m2[(t[1], t[2], t[3])] = t[4] + 2t[5]
    end
    @test !only(v
    for v in p63f1b_verdicts(m2, mseries)
    if v.row == "F7.CI" && v.check == "points outside band").ok
    m3 = copy(msweep)
    t = first(p63f1b_points("F8", "CI"))
    m3[(t[1], t[2], t[3])] = t[4] + 2t[5]
    @test only(v
    for v in p63f1b_verdicts(m3, mseries)
    if v.row == "F8.CI" && v.check == "points outside band").ok
    # the magnitude rule: a factor 4 fails, a factor 2 passes
    s4 = copy(mseries)
    s4[("ER50", 5000)] = (C = s4[("ER50", 5000)].C, dH = 4 * s4[("ER50", 5000)].dH)
    @test !only(v for v in p63f1b_verdicts(msweep, s4) if v.row == "F13.mag.ER50").ok
    s4[("ER50", 5000)] = (C = s4[("ER50", 5000)].C, dH = s4[("ER50", 5000)].dH / 2)
    @test only(v for v in p63f1b_verdicts(msweep, s4) if v.row == "F13.mag.ER50").ok
end

@testset "01b job list" begin
    J = p63f1b_jobs()
    @test length(J.sweeps) == 10 * count(t -> t[1] != "F12", P63F1B_TARGETS) == 1030
    @test length(J.series) == 300
    keys_ = [p63f1b_key.(J.sweeps); p63f1b_key.(J.series)]
    @test allunique(keys_)
    seeds = [[j.seed for j in J.sweeps]; [j.seed for j in J.series]]
    @test allunique(seeds) && minimum(seeds) > 300_000                    # disjoint from the frozen 01 seeds
    @test p63f1b_setup("F10", "CI1024", 2.0).lattice == (402, 402)
    @test p63f1b_setup("F5", "CI", 0.5).N == 10_000 &&
          p63f1b_setup("F9", "noCI", 0.1).N == 5000
end

# ---------------------------------------------------------------------------------------------
# SMOKE: the protocol at toy size
# ---------------------------------------------------------------------------------------------
@testset "01b SMOKE: protocol on 62², 8 cells" begin
    small(arm) = p63f1b_arm_setup(arm; lattice = (62, 62), rounds = 12, divisions = 3)
    saves = (0, 100, 200, 300)
    er = p63f1b_series_job((arm = "ER200", seed = 90_101); set = small("ER200"), saves)
    eo = p63f1b_series_job((arm = "EO200", seed = 90_101); set = small("EO200"), saves)
    @info "01b SMOKE series (t, C, ΣΔH)" er eo
    @test [r.t for r in er] == collect(saves)
    @test er[1].dH == 0.0 && eo[1].dH == 0.0
    @test all(r -> isfinite(r.C) && r.C > 0 && isfinite(r.dH), [er; eo])
    # no field during the relaxation, so the two modes are the same dynamics through MCS 100
    @test er[2].dH == eo[2].dH && er[2].C == eo[2].C
    @test er[2].dH < 0                                                    # the cells inflate towards A = 50
    @test er[4].dH != eo[4].dH                                            # the modes differ once the field is on
    # a sweep job at the explicit-Euler limit: D = 5·10⁻¹³ → Dc = 3.75, 15 substeps
    set = p63f1b_setup("F10", "CI128", 5.0)
    set = merge(set, (lattice = (62, 62), rounds = 12, divisions = 3))
    out, integ = p63f1b_run(90_102, set, (150, 250))
    c = Array(integ.u.site.c)
    @test all(isfinite, c) && minimum(c) >= 0 && maximum(c) > 0
    @test isfinite(out[250][1]) && out[250][2] === nothing
    # the inferred starts: 256 cells (Figs 12–13) and 1024 cells (Fig 10)
    for (rounds, divisions, G, n) in ((71, 8, (502, 502), 256), (141, 10, (402, 402), 1024))
        σ = layout(merks2008_sprout(; rounds, divisions, seed = 90_103), G)[1].second
        @test length(unique(σ[σ .>= 2])) == n
    end
end

# ---------------------------------------------------------------------------------------------
# FULL record (always; cheap): reproductions/data/01/full-01b-*
# ---------------------------------------------------------------------------------------------
function p63f1b_means(sweeps, series)
    acc = Dict{Tuple{String, String, Float64}, Vector{Float64}}()
    for r in sweeps
        push!(get!(acc, (r["fig"], r["curve"], parse(Float64, r["x"])), Float64[]), parse(Float64, r["C_N"]))
    end
    msweep = Dict(k => mean(v) for (k, v) in acc)
    acc2 = Dict{Tuple{String, Int}, Vector{NTuple{2, Float64}}}()
    for r in series
        push!(get!(acc2, (r["arm"], parse(Int, r["t"])), NTuple{2, Float64}[]),
            (parse(Float64, r["C"]), parse(Float64, r["dH"])))
    end
    mseries = Dict(k => (C = mean(first.(v)), dH = mean(last.(v))) for (k, v) in acc2)
    return msweep, mseries
end
function p63f1b_check(V, devs)
    for v in V
        startswith(v.check, "point ") && continue
        if v.control
            @test !v.ok
        elseif v.ok
            @test v.ok
        else
            listed = any(d -> d["row"] == v.row && d["check"] == v.check, devs)
            @test listed
            listed && @test_broken v.ok
        end
    end
end

@testset "01b FULL record" begin
    dirs = isdir(P63F1B_DATA) ?
           filter(d -> startswith(d, "full-01b-") && isdir(joinpath(P63F1B_DATA, d)), readdir(P63F1B_DATA)) :
           String[]
    if isempty(dirs)
        @info "01b: no FULL record yet (expected reproductions/data/01/full-01b-*)"
        @test_broken !isempty(dirs)
    else
        @test length(dirs) == 1
        D = joinpath(P63F1B_DATA, first(dirs))
        for f in ("sweeps.tsv", "series.tsv", "verdicts.tsv", "provenance.toml")
            @test isfile(joinpath(D, f))
        end
        prov = TOML.parsefile(joinpath(D, "provenance.toml"))
        @test get(prov, "item", "") == "P6.3f"
        @test occursin(r"^[0-9a-f]{40}$", string(get(prov, "commit", ""))) &&
              get(prov, "dirty", true) === false
        @test get(prov, "frozen_test_sha256", "") == bytes2hex(open(sha256, @__FILE__))
        sweeps = p63f1b_tsv(joinpath(D, "sweeps.tsv"))
        series = p63f1b_tsv(joinpath(D, "series.tsv"))
        J = p63f1b_jobs()
        # the record is the job list, once each
        @test sort([r["key"] for r in sweeps]) == sort(p63f1b_key.(J.sweeps))
        @test sort(unique([r["key"] for r in series])) == sort(p63f1b_key.(J.series))
        @test length(series) == length(J.series) * length(P63F1B_SERIES_T)
        @test all(
            r -> parse(Int, r["seed"]) == parse(Int, last(split(r["key"], "_s"))), [sweeps;
                                                                                    series])
        msweep, mseries = p63f1b_means(sweeps, series)
        V = p63f1b_verdicts(msweep, mseries)
        @info "01b FULL record" [(v.row, v.check, v.ours, v.ok)
                                 for v in V if !startswith(v.check, "point ")]
        dev_f = joinpath(D, "deviations.tsv")
        p63f1b_check(V, isfile(dev_f) ? p63f1b_tsv(dev_f) : Dict{String, String}[])
        vt = p63f1b_tsv(joinpath(D, "verdicts.tsv"))
        for v in V
            rr = [r for r in vt if r["row"] == v.row && r["check"] == v.check]
            @test length(rr) == 1 && only(rr)["result"] == (v.ok ? "PASS" : "FAIL")
        end
    end
end

# ---------------------------------------------------------------------------------------------
# FULL (offline, on the PC): run the 1330 jobs and apply the rules
# ---------------------------------------------------------------------------------------------
if P63F1B_FULL
    @testset "01b FULL: Figs 5, 7–10, 12, 13" begin
        J = p63f1b_jobs()
        sw = Vector{Any}(undef, length(J.sweeps))
        se = Vector{Any}(undef, length(J.series))
        Threads.@threads :greedy for k in 1:(length(sw) + length(se))
            if k <= length(sw)
                sw[k] = p63f1b_sweep_job(J.sweeps[k])
            else
                se[k - length(sw)] = p63f1b_series_job(J.series[k - length(sw)])
            end
        end
        sweeps = [Dict("fig" => j.fig, "curve" => j.curve, "x" => string(j.x), "C_N" =>
                      string(r.C_N)) for (j, r) in zip(J.sweeps, sw)]
        series = [Dict("arm" => j.arm, "t" => string(q.t), "C" => string(q.C), "dH" =>
                      string(q.dH)) for (j, r) in zip(J.series, se) for q in r]
        V = p63f1b_verdicts(p63f1b_means(sweeps, series)...)
        @info "01b FULL" [(v.row, v.check, v.ours, v.ok)
                          for v in V if !startswith(v.check, "point ")]
        for v in V
            startswith(v.check, "point ") && continue
            v.control ? (@test !v.ok) : (@test v.ok)
        end
    end
end

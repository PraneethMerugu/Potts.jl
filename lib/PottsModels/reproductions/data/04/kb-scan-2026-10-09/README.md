# Reproduction 04: κ_b scan, 2026-10-09 (a negative result)

This is the pre-registered scan of a separate bulk scale κ_b for the foam's bulk-shear drive (D-203, protocol frozen in D-205). The record was made by `../run_kb_scan.jl` at commit 8b5d8afd, using the frozen test `test/reproductions/04_foam_kb_scan.jl`.

- **Grid:** 23 values of κ_b, from 0.156 to 319.6 in √2 steps.
- **β:** five values, from 1e-4 to 0.05.
- **Runs:** ordered foams 1–3, with 3 replicates each, for 345 runs in total.
- **Files:**
  - `scan.tsv` holds one row per run.
  - `decision.toml` holds the result of the pre-registered decision rule.
  - `provenance.toml` holds the run details.
  - The algorithm is recorded under its old name, `BoundarySiteCPM()`, which is now `SequentialCPM(; skip_interior = true)` (D-198).

**Result: the decision rule returns no κ_b (`pinning_cliff`).**

In the table, t_first is the first T1 in paper MCS (−1 means no yield within the cap) and T1 is the total T1 count. Both are medians over the 3 replicates.

| κ_b | β = 1e-4 | β = 1e-3 | β = 5e-3 | β = 0.01 | β = 0.05 |
|---|---|---|---|---|---|
| 0.156 | −1 / 0 | −1 / 0 | −1 / 0 | −1 / 0 | −1 / 0 |
| 0.221 | −1 / 0 | −1 / 0 | −1 / 0 | −1 / 0 | −1 / 0 |
| 0.312 | −1 / 0 | −1 / 0 | −1 / 0 | −1 / 0 | −1 / 0 |
| 0.441 | −1 / 0 | −1 / 0 | −1 / 0 | −1 / 0 | 593 / 21 |
| 0.624 | −1 / 0 | −1 / 0 | −1 / 0 | −1 / 0 | 238 / 48 |
| 0.883 | −1 / 0 | −1 / 0 | −1 / 0 | −1 / 0 | 161 / 220 |
| 1.248 | −1 / 0 | −1 / 0 | −1 / 0 | −1 / 0 | 101 / 415 |
| 1.766 | −1 / 0 | −1 / 0 | −1 / 0 | 1691 / 3 | 86 / 568 |
| 2.497 | −1 / 0 | −1 / 0 | −1 / 0 | 451 / 38 | 39 / 922 |
| 3.531 | −1 / 0 | −1 / 0 | 1682 / 2 | 229 / 130 | 13 / 1694 |
| 4.994 | −1 / 0 | −1 / 0 | 480 / 42 | 114 / 283 | 3 / 2598 |
| 7.062 | −1 / 0 | −1 / 0 | 229 / 121 | 106 / 552 | 2 / 3686 |
| 9.987 | −1 / 0 | −1 / 0 | 123 / 256 | 59 / 678 | 3 / 5264 |
| 14.12 | −1 / 0 | 23892 / 2 | 102 / 530 | 27 / 1180 | 3 / 7926 |
| 19.97 | −1 / 0 | 616 / 14 | 59 / 760 | 12 / 2030 | 2 / 10690 |
| 28.25 | −1 / 0 | 292 / 46 | 48 / 1268 | 6 / 2944 | 1 / 12826 |
| 39.95 | −1 / 0 | 177 / 169 | 8 / 1990 | 3 / 4151 | 2 / 14185 |
| 56.50 | −1 / 0 | 144 / 413 | 5 / 2888 | 3 / 6011 | 1 / 15168 |
| 79.90 | −1 / 0 | 97 / 404 | 4 / 4096 | 2 / 9059 | 2 / 16030 |
| 113.0 | −1 / 0 | 54 / 796 | 2 / 6239 | 1 / 11444 | 2 / 16869 |
| 159.8 | 4159 / 2 | 9 / 1553 | 3 / 8891 | 1 / 13320 | 1 / 17403 |
| 226.0 | 565 / 25 | 13 / 2284 | 1 / 11549 | 1 / 14896 | 1 / 17716 |
| 319.6 | 207 / 56 | 4 / 3282 | 2 / 13528 | 1 / 15525 | 1 / 17694 |

The fit targets come from spec §3.2: about 4300 paper MCS at β = 0.01 and about 420 at β = 0.05, each within ±25 %. The consistency check asks for T1s at β = 10⁻³.

- **The harness check holds.** At D-190's setting, κ_b = 2.497, β = 0.01 gives 451 and β = 0.05 gives 39. The first record (`../full-2026-10-09/`) has 455 and 40.
- **The β = 0.01 target is unreachable.** t_first jumps from no yield at κ_b = 1.248 to 1691 at κ_b = 1.766. No grid value gives about 4300; that value sits inside a pinning cliff.
- **The β = 0.05 target is reachable at κ_b ≈ 0.5, but β = 0.01 never yields there.** T1s at β = 10⁻³ need κ_b ≳ 14–20, where β = 0.05 yields within 1–3 MCS. The fit and the consistency check cannot both hold at one κ_b.
- **Only part of the shape matches.** Where both β values yield, the time ratio t(0.01)/t(0.05) is 11.6 at κ_b = 2.497; the paper's ratio is about 10.2. The overall scale is off by about 10×. The low-β onset is a sharp depinning threshold, not the smooth ε_y ≈ c·β·t.

**What follows (D-203 (d), D-210).**
- The Eq 2 form under bulk shear is in question. The 04 record stays provisional.
- The question is on our open question list as F1.
- No further foam runs are made until it is answered.

The interpretation is in spec 04 §7 A-1. At T = 0, any position-independent per-flip bias competes against integer J barriers, so it depins at a threshold.

# Reproduction 09: V-PRE7 temperature regimes (P6.1h)

This is the FULL record for V-PRE7, kept as D-146 requires. The 09 page and its test
(`lib/PottsModels/test/reproductions/09_cell_sorting.jl`) read their V-PRE7 verdicts from
here; the page's other full-run rows stay in `full-2026-10-05/`.

**Target** (spec 09 §9.1 V-PRE7, verbatim): F_dl vs t for T ∈ {0, 2, 5, 10, 15, 20, 40, 80},
≥ 5 replicates per T, FULL.
- T = 0: |F_dl(2000) − F_dl(100)| < 0.02.
- Order at 10³: F_dl(T=2) > F_dl(T=5) > F_dl(T=10).
- T = 40: F_dl > 0.07 at every save in [10³, 10⁴].
- T = 80: more than 50% of cells gone (volume 0) by 500.

**Fixture.**
- Each replicate is the page's FULL replicate, `graner_glazier_aggregate(1000; seed = start, margin = 60)`, 347². It runs the published `GranerGlazier` with only T changed, under `SequentialCPM(; proposal = Moore(1))` with problem seed `run`.
- 1 paper MCS = 16 MCS. Saves follow the page's FULL grid to 10⁴ paper MCS (38 saves).
- There are 10 replicates per T, with start seeds 3001–3010 and run seeds 13001–13010. The same seeds serve every T, so comparisons between temperatures are paired.
- Measurement is the page's. Each save is measured on a copy annealed 2 paper MCS at T = 0 with the run's J, λ and V₀ (seed 1). Moore bonds are counted once, and all mismatched bonds form the denominator.
- "Gone" means volume 0 on the raw state. A save with no mismatched bond left counts as F = 0.
- The ensemble statistic is the mean over replicates (spec §9.0).

## Verdicts (`verdicts.tsv`)

| Criterion | Ours (n = 10 per T) | Rule | Result |
|---|---|---|---|
| T = 0 frozen | \|F_dl(2000) − F_dl(100)\| = 0.0000 | < 0.02 | PASS |
| Order at 10³ | T = 2: 0.349, T = 5: 0.191, T = 10: 0.135 | T2 > T5 > T10 | PASS |
| T = 40 plateau | minimum over [10³, 10⁴] = 0.098 (at 10⁴) | > 0.07 at every save | PASS |
| T = 80 disintegration | 0.076 of cells gone at 500 | > 0.5 | **FAIL** |

The isolation guard held at every save of every run.

## Heterotypic fraction F_dl (mean ± SE) and share of cells gone (`summary.tsv`)

| T | 100 | 10³ | 2000 | 10⁴ | gone @ 500 | gone @ 10⁴ |
|---|---|---|---|---|---|---|
| 0 | 0.449 ± 0.003 | 0.449 ± 0.003 | 0.449 ± 0.003 | 0.449 ± 0.003 | 0 | 0 |
| 2 | 0.393 ± 0.003 | 0.349 ± 0.002 | 0.332 ± 0.002 | 0.295 ± 0.002 | 0 | 0 |
| 5 | 0.299 ± 0.002 | 0.191 ± 0.003 | 0.166 ± 0.004 | 0.124 ± 0.004 | 0 | 0 |
| 10 | 0.248 ± 0.003 | 0.135 ± 0.003 | 0.111 ± 0.003 | 0.072 ± 0.003 | 0 | 0 |
| 15 | 0.232 ± 0.002 | 0.125 ± 0.003 | 0.103 ± 0.003 | 0.068 ± 0.004 | 0 | 0 |
| 20 | 0.234 ± 0.002 | 0.124 ± 0.002 | 0.105 ± 0.002 | 0.072 ± 0.003 | 0 | 0 |
| 40 | 0.251 ± 0.003 | 0.162 ± 0.004 | 0.135 ± 0.003 | 0.098 ± 0.003 | 0 | 0.0001 (one cell) |
| 80 | 0.300 ± 0.003 | 0.243 ± 0.003 | 0.205 ± 0.006 | 0.007 ± 0.001 | 0.076 | 0.499 (all light) |

Paper (PRE Fig. 15 and p.2144; spec §9.1, read at 110 dpi):
- T = 0 freezes.
- T = 2 gives ≈ 0.3 at 3×10³. Ours gives 0.321 at 3200, so it matches.
- T = 10–20 reach ≈ 0.05 at 10⁴. Ours read 0.068–0.072, the gap already recorded as the late-coarsening deviation (D-151).
- T = 40 plateaus near 0.1 and forms the monolayer by ≈ 50.
- At T = 80 all cells disappear and F_dl reaches 0 by ≈ 100.

## Reading

- **Three rows pass.** T = 0 is frozen (the T = 0 rule with ties at ½ does not move a relaxed aggregate). The order at 10³ holds with wide margins, and T = 2 matches the paper's ≈ 0.3.
- **The T = 40 bar is weak.** Our T = 40 curve does not level off: it falls from 0.162 at 10³ to 0.098 at 10⁴. It passes the 0.07 bar, but T = 10 passes that bar too (its minimum over [10³, 10⁴] is 0.072 at 10⁴). The pre-registered row therefore does not tell T = 40 from T = 10 in our model. That is a lesson for future specs, not an amendment.
- **T = 80 fails.**
  - At 500, 7.6% of cells are gone, against the target of more than half. The paper has all cells gone by ≈ 100.
  - Every lost cell is light: by 10⁴ all 500 light cells are gone and every dark cell survives (gone = 0.499).
  - F_dl reaches 0 only at 10⁴, once the light cells are gone.

## Post-hoc diagnostic (`diagnostic_timeseries.tsv`; not a verdict)

These runs were added after the T = 80 failure. They use 5 of the same paired replicates (start seeds 3001–3005) at T = 120, 160 and 240, to 10³.

| T | gone @ 100 | gone @ 200 | gone @ 500 | F_dl @ 100 | F_dl @ 200 | F_dl @ 500 |
|---|---|---|---|---|---|---|
| 80 (main, n = 10) | 0.012 | 0.028 | 0.076 | 0.300 | 0.276 | 0.264 |
| 120 | 0.136 | 0.271 | 0.485 | 0.315 | 0.268 | 0.055 |
| 160 | 0.325 | 0.495 | 0.610 | 0.256 | 0.092 | 0.000 |
| 240 | 0.565 | 0.749 | 0.976 | 0.140 | 0.003 | 0.000 |

The paper's T = 80 behaviour (all cells gone, F_dl → 0 by ≈ 100) needs our T ≈ 160–240, a factor of about 2–3. The direction matches P6.1g, where T ≥ 14 brought our late coarsening closer to the paper's.

The mechanism is not identified. The energy (PRE Eq. (2)), the Moore(1) bond set counted once, and the Metropolis rule (Eq. (3)) are as the page states them. Three things would hide a factor of 2–3:
- a factor in k;
- each bond counted from both sides in the paper's H, which would make the paper's effective T lower, the wrong direction;
- a different ΔH convention.

The page records this as a deviations row, with a question proposed for the open question list. No target changed.

## Files

| File | Contents |
|---|---|
| `timeseries.tsv` | 80 runs × 38 saves: seeds, T, the five annealed fractions and bond counts, the mismatched-bond total, alive and initial cell counts per kind, isolation guard, run wall time |
| `summary.tsv` | per T and save: n, mean and SE of the five fractions, mean and SE of the share gone, guard |
| `verdicts.tsv` | the four criteria (written by `scripts/collect.jl`; the page and the test recompute them from `timeseries.tsv`) |
| `diagnostic_timeseries.tsv` | the post-hoc T = 120, 160, 240 runs, same columns, to 10³ |
| `provenance.toml` | commits, machine, scope and pinning, wall times, seeds, the rerun note |
| `scripts/` | `replicate.jl`, `run_all.sh`, `jobs.txt`, `jobs_diag.txt`, `collect.jl`, `render_video.jl` |

**Video.** `scripts/render_video.jl` re-solves replicate 1 (seeds 3001 / 13001) at the eight temperatures with 100 log-spaced frames. It draws them as a 2 × 4 grid with no cell outlines, and checks every frame that is also a recorded save against `timeseries.tsv`. The video and stills are kept locally and are not committed; hosting is the coordinator's step (D-161: a new dated pre-release).

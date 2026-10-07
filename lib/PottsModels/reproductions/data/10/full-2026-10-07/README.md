# Reproduction 10 (Akeeb, Marcus & Jiang 2026): FULL runs of 2026-10-07 (P6.2d, D-156)

The offline record required by D-146. Both runs were made on the PC (praneeth-NucBox-EVO-X2, AMD Ryzen AI Max+ 395, Julia 1.12.6, 12 threads pinned to `taskset -c 0-11,16-27`) at commit `246427f1`.

## Runs

1. **The page at FULL.** `lib/PottsModels/reproductions/10_akeeb.jl` (frozen, sha256 `db4b7027…`) with `POTTS_FULL_REPRODUCTION=true`, through `run_wrapper.jl`: nine points × 10 runs, 10 one-MCS V-A0 runs, and the PP = 0.5 slice (121 × 10 runs). 676 s wall time.
   - The executed text differs from the frozen page in one place, recorded in `provenance.toml`: the videos are drawn with `boundaries = false` instead of `true` (D-156: no cell outlines). This is rendering only; the page re-solves replicate 1 for each video and asserts that it equals the ensemble's replicate 1.
2. **The full sweep.** `sweep.jl`: all 11 J_LF × 11 λ × 11 PP points × 10 runs (13,310 runs) at the authors' MCS 700, seeds 2 000 000 + 100 j + i (disjoint from the page's). `analyse.jl` turns it into `verdicts_sweep.tsv` and `10_akeeb_phenotypes.png`.
   - The sweep is written one PP level at a time and resumes at the first missing level. PP = 0.0 and 0.1 were written by a first session; the run was then restarted under a memory cap (`systemd-run --user --scope -p MemoryMax=12G`), which wrote PP = 0.2–1.0 in 3491 s. Runs are deterministic in their seed, so the restart does not change any row.

| File | Contents |
|---|---|
| `verdicts.tsv` | the page's pass/fail table at FULL (one row per target) |
| `timeseries.tsv` | P1–P9 and V-A0: per run and save (authors' MCS 0, 100, 300, 500, 700), the six metrics and the division count |
| `slice.tsv` | the page's PP = 0.5 slice: per run, the six metrics at MCS 700 |
| `clusters.tsv` | P1 and P2: leaders and followers of every counted cluster at MCS 700 (V-A8) |
| `page_meta.toml`, `provenance.toml` | the page run's seeds, saves, threads, and its commit, page hash, machine and wall time |
| `sweep.tsv`, `sweep_provenance.toml` | the full sweep: per run, the metrics, the division count and the `akeeb_phenotype` class |
| `verdicts_sweep.tsv` | V-A6, V-A7 (full-sweep \|r\|) and reported cross-checks |
| `deviations.tsv` | the D-154 deviations rows for the page (our value, paper's value, suspected cause, author-question status) |
| `10_akeeb_phenotypes.png` | Fig. 5B side by side, and the dominant phenotype over (J_LF, λ) at PP = 0.5 (authors, ours) |
| `run_wrapper.jl`, `sweep.jl`, `analyse.jl` | the scripts |

**Videos** (replicate 1 at P1, P4, P5, P6, every 10 MCS, no outlines): video pending. They are kept locally until the coordinator publishes them in a dated `reproductions-YYYY-MM-DD` pre-release; the release `reproductions-2026-10` is immutable.

## Result

- **Page at FULL:** 114 PASS, 2 FAIL, 3 PARKED, 1 reported. Every V-A3, V-A4 and V-A5 row passes. V-A7 at P9 passes, and so do V-A1, V-A8 (dataset C), V-A11, V-C1 and V-C2.
  - The 2 FAIL rows are one deviation: V-A2 P6 (−2, 6, 0.5), invasive = infiltrative, 2642 ± 392 against 2155 ± 261 (tolerance ± 447). The authors' reference at that cell is low against their own data: dataset A pooled over PP at (−2, 6) gives 2381 ± 383 (n = 110). Our sweep at the same point gives 2426 ± 487, which is inside the rule, and ours pooled over PP gives 2487 ± 426 (n = 110). Read as reference sampling; see `deviations.tsv`.
- **V-A6 (area-equality classifier, R3), PASS on all four classes:** No invasion 22.34 % (A 22.24), Single-cell 1.03 % (1.08), Bulk 22.34 % (22.54), Multimodal 54.29 % (54.14). Our Fig. 5B per-replicate SDs are 0.40, 0.18, 0.58 and 0.39 % (A: 0.66, 0.21, 0.67, 0.48). 42 of 13,310 runs are unclassified (A: 42 of 13,305).
- **V-A7, full-sweep \|r(PP, metric)\| < 0.05, PASS on all six metrics:** −0.027, −0.026, −0.004, 0.002, −0.007 and 0.005 (A: −0.025, −0.026, −0.004, 0.001, −0.007, −0.002). All are also under the paper's 0.03.
- **Reported:**
  - The paper's other correlations: λ–invasive 0.701 (paper 0.70), λ–fingers 0.793 (0.80), J–singles 0.672 (0.67) and J–infiltrative 0.567 (0.57).
  - The paper's full-sweep marginals are all within 10 %, except clusters at J_LF > 2: 2.00 against 1.78 (+12 %, inside the count floor of 1).
  - The sweep's own PP = 0.5 slice repeats V-A3 and V-A4 in band.

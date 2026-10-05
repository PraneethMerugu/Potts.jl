# Reproduction 09: FULL run of 2026-10-05 (P6.1f, D-144)

This is the offline record required by D-146.

- **Run.** Page `lib/PottsModels/reproductions/09_cell_sorting.jl`, sha256 72ede40b…, at commit 0eb1ea72, with `POTTS_FULL_REPRODUCTION=true`.
- **Setup.** 10 replicates on a 347² lattice with margin 60, 6 threads, 5052 s wall time on an Apple M1 Pro.

| File | Contents |
|---|---|
| `verdicts.tsv` | the page's pass/fail table, one row per target |
| `timeseries.tsv` | per replicate and per save (paper MCS): the five bond fractions, the total mismatched-bond count, and the isolation-guard flag |
| `clusters.tsv` | per replicate, the dark-cluster count and the largest dark-cluster fraction at 10, 10², 10³ and 10⁴ |
| `page_meta.toml` | replicates, seeds, margin, save times, threads |
| `provenance.toml` | commit, page hash, environment, Julia, machine, start/finish, wall time |
| `run_wrapper.jl` | the run wrapper (Literate with an appended export chunk; the page itself runs unchanged) |

The replicate-1 video is published as a release asset (pending maintainer confirmation) and linked from the docs page.

**Result.** Every binding row passes except V-PRE5 "one dark cluster @ 10⁴": the largest dark-cluster fraction is 0.815 against ≥ 0.90. P6.1d read 0.905 at margin 10. V-PRE3 (b), which failed in P6.1d, now passes (t_p = 320). The isolation guard held at every save of every replicate.

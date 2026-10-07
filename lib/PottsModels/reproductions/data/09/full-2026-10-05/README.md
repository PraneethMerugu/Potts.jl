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
| `render_video.jl` | the outline-free re-render of the replicate-1 video (P6.0bf), with a trajectory check against `timeseries.tsv` |
| `render_provenance.toml` | that render's commit, machine, wall times and check |

The replicate-1 video is the release asset [`09_cell_sorting_full-2026-10-05_replicate1.mp4`](https://github.com/PraneethMerugu/Potts.jl/releases/download/reproductions-2026-10/09_cell_sorting_full-2026-10-05_replicate1.mp4) (release `reproductions-2026-10`). It was re-rendered on 2026-10-07 without cell outlines (D-156, P6.0bf). No states were saved by the run, so `render_video.jl` re-solves replicate 1 with the recorded seed and settings on the PC (AMD Ryzen AI Max+ 395, CPU backend, one thread, at commit d6d1aed1). The trajectory is the recorded one: the annealed bond fractions and the total mismatched-bond count of the end state equal replicate 1 of `timeseries.tsv` at 2×10⁴ exactly. `render_provenance.toml` records the render. The first render (2026-10-05) drew cell outlines and is replaced.

**Result.** Every binding row passes except V-PRE5 "one dark cluster @ 10⁴": the largest dark-cluster fraction is 0.815 against ≥ 0.90. P6.1d read 0.905 at margin 10. V-PRE3 (b), which failed in P6.1d, now passes (t_p = 320). The isolation guard held at every save of every replicate.

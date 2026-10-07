# Review probes for P6.1h (exploratory; not verdicts)

These files are the reviewer's probes from the P6.1h review (2026-10-07), copied unchanged from the PC (`~/p61h_review_*`). They are kept so that the page's "review diagnostic" is on record (D-146). They are exploratory: one or two replicates per point, not pre-registered, and no verdict reads them.

| File | Contents |
|---|---|
| `p61h_review_probe.jl` | the script; modes `units` (a hand check of H), `lambda` and `hot` |
| `p61h_review_lambda.log` | `lambda` mode: T = 5, λ ∈ {0.1, 0.2, 0.5}, starts 3001 and 3002 with margin 30, run seeds start + 10000. Output is the alive (dark, light) cells at 50–1000 paper MCS |
| `p61h_review_hot.log` | `hot` mode: one replicate (start 3001, margin 60, seed 13001) at (T, λ) = (40, 1), (80, 1), (160, 1) and (80, 0.5). Output per save: raw and annealed alive counts, annealed F_dl and a fragmentation measure |

The warning at the top of each log comes from the `units` block of the script; it does not affect the other modes. The `units` output itself was not kept.

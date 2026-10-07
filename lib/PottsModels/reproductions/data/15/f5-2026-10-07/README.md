# Reproduction 15: F5 "100 runs of 1000 cells" (case (b)) and its negative control, FULL run of 2026-10-07 (P6.15e)

This is the offline record required by D-146.

- **Run.** `run_f5.jl` at commit `3af81ae8` on the PC (praneeth-NucBox-EVO-X2, AMD Ryzen AI Max+ 395, Julia 1.12.6, 12 threads pinned to `taskset -c 0-11,16-27`, under a 24 GB memory cap). Wall time 468 s; the 120 runs took 3304 CPU-s. The workspace Manifest's sha256 is in `provenance.toml`.
- **Same computation as the frozen test.** `lib/PottsModels/test/reproductions/15_openvt_f5.jl` (sha256 `92eee663…`) pre-registers V4 as seven rows (V4.1–V4.7) with pass bands, the peak rule, the seeds, the lattice and the γ = 10⁻⁴ negative control. The runner restates them, and the test recomputes every verdict from `runs.tsv` and `hist.tsv` with its own rules.
- **Re-freeze after the run.** The record falsified one premise of the first freeze: bin 0 of f holds 26 cells with 0 < f < 0.01, besides the 88,803 cells with f = 0. The test was re-frozen, now sha256 `0f38ec2a…`. V4.2 now drops exactly the f = 0 cells, and the premise check became `hf[1] ≥ n_f0`. No band, seed or run changed, and every verdict below is the same under both rules. The runner, as committed and hashed in `provenance.toml`, still drops all of bin 0 for its own `verdicts.tsv`; the test recomputes the verdicts with the re-frozen rule.
- **Protocol.** `OpenVTReferenceMonolayer` at Table S1 (β = γ = 0, σ_X = 0.4), one disc cell at the centre, a closed 400 × 400 lattice with `edge_guard(5; terminate = true)`, `SequentialCPM(; proposal = Moore(1))`, stopped at the end of the first MCS with ≥ 1000 cells. Seeds 15001–15100 (case (b)) and 15501–15520 (control, γ = 10⁻⁴).
  - Every run stopped on the cell count (`Terminated`). The closest any cell came to the lattice edge was 34 sites (case (b)) and 33 (control).
  - **Lattice: a reading.** Spec §2.5 lists "≥ 1400², closed + guard" for Potts. That row is sized for the 10⁴-cell cases. Here we read M's "unbounded 2D plane" (§2.1) as any closed lattice the 1000-cell colony never approaches. The edge guard enforces this, and every run kept ≥ 33 sites of medium to the edge. One MCS is one attempt per site, so a boundary site is tried once per MCS whatever the lattice size, and medium-only sites never change.
  - Time to 1000 cells: 10.36 cycles on average (9.73–11.04; 1 cycle = 775 MCS) for case (b), and 20.69 (20.37–21.70) for the control.

| File | Contents |
|---|---|
| `verdicts.tsv` | V4.1–V4.7 per case, the overall V4 verdict and the control row |
| `deviations.tsv` | the D-154 table for every failing case (b) row: our value, the paper's value, the suspected cause, the author-question status |
| `runs.tsv` | one row per run: seed, γ, lattice, return code, stop MCS and cycles, N, the f = 0 count, the f and a sums, the f and a extremes, the largest distance from the centre (R), the closest approach to the edge, wall time |
| `hist.tsv` | cell counts in bins of width 0.01 for f and a, per case and per distance bin (5 equal bins from 0 to 1.05 × the case's max distance from the initial cell's centre, in R; spec C11, C12) |
| `extremes.tsv` | every cell outside the consortium's ranges (f > 0.56, a < 0.42 or a > 1.09): f, a, volume, A_star, distance and its number of 4-connected pieces |
| `meta.toml`, `provenance.toml` | parameters, seeds, distance-bin edges, threads; commit, test and runner hashes, Manifest hash, machine, start/finish and wall time |
| `run_f5.jl` | the runner |
| `plot_f5.jl`, `fig5.png` | M Fig 5's four columns (PDF and CDF of f, PDF and CDF of a; raw counts, stacked by distance bin, `viridis_r` / `inferno_r`), one row for case (b) and one for the control; Potts only |
| `video_f5.jl` | renders case (b) run 1 and control run 1 every 39 MCS, cells coloured by area, no outlines; the videos are not committed |
| `probe_causes.jl` | the cause probe for the failing rows (below) |

The O2 files (`x,y,r,f,a` per cell, lengths in R from the lattice centre; spec §3.1), one per run, in `Potts.jl_5T_MonolayerGrowth_1000_Data/cell_data_no_inhibition_<k>.csv` and `…_gamma1e-4/`, are written by the runner to `F5_O2_DIR`. They are 9.4 MB (4.4 MB gzipped) and are not committed; they belong to the submission package (P6.15j). The consortium data (G) were not on disk, so no consortium row is drawn and no G file entered git.

## Result

**V4 fails for case (b) on three of seven rows. The negative control behaves as pre-registered.**

| Row | Consortium (V4) | Potts.jl, case (b) | Band | Verdict | Control (γ = 10⁻⁴) |
|---|---|---|---|---|---|
| V4.1 fraction with f = 0 | ≈ 0.89 | 0.888 | [0.86, 0.92] | PASS | 0.863 |
| V4.2 peak of nonzero f | 0.25–0.35 | 0.425 | [0.22, 0.38] | **FAIL** | 0.185 |
| V4.3 max f | ≤ 0.56 | 0.847 | ≤ 0.61 | **FAIL** | 1.0 |
| V4.4 peak of a | 0.85–0.90 | 0.865 | [0.82, 0.93] | PASS | 0.965 (fails) |
| V4.5 range of a | 0.42–1.09 | 0.066–1.130 | ⊂ [0.32, 1.19] | **FAIL** | 0.557–1.159 |
| V4.6 mean a | 0.85–0.86 | 0.849 | [0.82, 0.89] | PASS | 0.957 (fails) |
| V4.7 mean f | ≈ 0.03 | 0.0388 | [0.02, 0.04] | PASS | 0.0484 |

- **Audit of the bands.** The V4 bands were set from spec 15's V4 text only, not audited against the G files (TST_5T, Morpheus_5T); G was not on disk when the test was frozen. The causes below are therefore provisional until the frozen rules are run on TST_5T.
- **The bulk agrees.** The f = 0 fraction, the a peak and mean a match the consortium. Mean f passes but sits at the band's upper end (0.039 against ≈ 0.03).
  - V4.1 does not separate the control from case (b): the control's f = 0 fraction, 0.863, is also inside the band.
- **Provisional: our rim cells appear to carry more free surface than the consortium's.**
  - **Consistency check.** The consortium's f0 ≈ 0.89 and mean f ≈ 0.03 imply a mean nonzero f of about 0.03 / 0.11 ≈ 0.27. Ours is 0.346, with the median in the bin 0.35–0.36.
  - In 0.05 bins, the nonzero-f histogram is flat-topped over 0.30–0.45 (1387, 1497 and 1579 cells).
  - **Window sweep for V4.2.** Running-mean windows of 1, 3, 5, 7, 9 and 11 bins put the peak at 0.425, 0.435, 0.425, 0.415, 0.395 and 0.395. All are outside the consortium's 0.25–0.35, so the failure does not depend on the frozen 5-bin window.
  - 606 of 11,226 rim cells (5.4 %) have f > 0.56.
- **The low end of a: squeezed young daughters (cause unresolved).**
  - 30 of 100,029 cells have a < 0.42. All 30 are interior (f = 0) cells of 2–18 px with A_star 23–43, so they were born recently.
  - 10 of them are 5 sister pairs, with identical A_star within one run (runs 19, 27, 31, 70, 76). 3 are in two or more pieces.
  - For context, the low quantiles of a are 0.38 (0.01 %), 0.47 (0.1 %), 0.60 (1 %) and 0.69 (5 %).
- **The negative control fails V4,** as pre-registered, on V4.4 and V4.6. Arrested interior cells relax to their reference area, so mean a is 0.957 and the a peak is 0.965.
  - The control also fails V4.2, V4.3 and V4.7.
  - It takes twice as long to reach 1000 cells.
- **Cause probe** (`probe_causes.jl`; 20 runs each, seeds 15001–15020, not part of the verdicts). The same-seed baseline is the record's runs 1–20: max f 0.821, 5 cells with a < 0.42, min a 0.066.

  | Variant | max f | nonzero f > 0.56 | min a | cells with a < 0.42 | mean a |
  |---|---|---|---|---|---|
  | record, runs 1–20 (random plane, no connectivity) | 0.821 | — | 0.066 | 5 | — |
  | TST's minor-axis division | 0.822 | 6.3 % | 0.231 | 12 | 0.849 |
  | random plane + connectivity constraint | 0.815 | 5.9 % | 0.289 | 8 | 0.852 |

  - Both variants' nonzero-f histograms peak at 0.35–0.45, as in the record. So neither the division axis nor connectivity explains V4.2–V4.3.
  - Connectivity raises the minimum of a but does not reduce the number of cells below 0.42.
  - The remaining candidates are in `deviations.tsv`:
    - the pooled V4 band mixes TST's pair-count f with Morpheus's length-scaled f, and the Morpheus runs may predate Table S1 (spec 15 §2.5, Q12);
    - TST divides on target area (C13, Q20);
    - Morpheus draws X with σ = 0.16 (C17, Q21).
  - New questions Q23 (the f definition and data behind V4) and Q24 (crushed cells) are on our open question list in spec 15 §7.
- **Pilot (12 + 6 + 6 runs, seeds 1001–1012 and 2101–2206, 450² lattice, before the freeze; script not kept).**
  - Case (b): f0 0.887, nonzero-f peak 0.325, max f 0.764, a peak 0.875, a range 0.227–1.116, mean a 0.849, mean f 0.039.
  - γ = 10⁻⁴ and γ = 0.2: mean a 0.957 and 0.958, a peak 0.965 and 0.975.
  - It set the throughput estimate (28 s per run) and the choice of control. The V4 bands in the test were written before its output was read.
- **Distance bins.** The figure labels, floored as in M's notebook, are 0–8, 8–17, 17–26, 26–35 and 35–44 R (control 0–8 … 34–43). The edges are 0, 8.99, 17.98, 26.96, 35.95 and 44.94 R, and the furthest cell is 42.8 R from the initial centre. M's legend reads 0–7 … 31–39, a 1.05 × max d of about 39.5 R (spec C11, Q15).
- **Figure range.** `fig5.png` draws a from 0.3, so the 3 case (b) cells with a < 0.30 (0.066, 0.261 and 0.297) lie left of the axis. Every f value is in range.

**Videos** are published as assets of the pre-release [`reproductions-2026-10-07-openvt-f5`](https://github.com/PraneethMerugu/Potts.jl/releases/tag/reproductions-2026-10-07-openvt-f5): `15_openvt_f5_b_run1_seed15001.mp4` and `15_openvt_f5_control_gamma1e-4_run1_seed15501.mp4`. Both are rendered by `video_f5.jl`, with cells coloured by area from blue (20 px) to red (120 px) and no outlines.

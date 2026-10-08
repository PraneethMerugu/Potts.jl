# Reproduction 15: F3 "Comparing monolayer growth over time" (cases (f), (b)) and F8 / V5 (cases (a), (e)), FULL run of 2026-10-08 (P6.15f)

This is the offline record required by D-146, pre-registered by D-173.

- **Run.** `run_f3_f8.jl` at commit `a64ae188` on the PC (praneeth-NucBox-EVO-X2, AMD Ryzen AI Max+ 395, Julia 1.12.6). It ran with 12 threads pinned to `taskset -c 0-11,16-27`, under a 24 GB memory cap (`systemd-run --user --scope -p MemoryMax=24G`). Wall time was 2790 s, and the 240 runs took 33,171 CPU-s (9.2 core-hours). The D-173 estimate was 3.3 core-hours. Each 10⁴-cell run costs 20–29 min on one thread, and those 20 runs are 85 % of the total. `provenance.toml` holds the workspace Manifest's sha256.
  - A first launch used `Threads.@threads :dynamic`. That scheduler splits the job list into 12 contiguous chunks, so all 20 large runs landed on one thread. It was stopped after 20 min and relaunched with `:greedy`. No output of the first launch was kept. Scheduling does not change a run (each run's RNG is its seed).
- **Same computation as the frozen test.** The runner loads every top-level `P615F_*` constant and `p615f_*` function of `lib/PottsModels/test/reproductions/15_openvt_f3_f8.jl` (sha256 `da7d145f…`) verbatim, by evaluating that file's source without its testsets and tiers. It then runs the test's recorder (`p615f_run`) and rules (`p615f_verdicts`). The test's record tier recomputes every verdict from `runs.tsv`, `timeseries.tsv` and `neighbors.tsv`. The runner also checked that the verdicts from the written TSVs equal those from the in-memory series.
- **Protocol** (D-173).
  - Model: `OpenVTReferenceMonolayer` at Table S1, starting from one disc cell at the centre.
  - Algorithm: `SequentialCPM(; proposal = Moore(1))`.
  - Lattice: closed, with `edge_guard(5; terminate = true)`. The run stops at the end of the first MCS with at least the stop count of cells.
  - Saves: MCS 0, every 39 MCS, and the stop. Each save records N and the `openvt_metrics` r, A, C, w and g of the centroids.

  | Case | Parameters | Lattice | Stop | Runs | Seeds |
  |---|---|---|---|---|---|
  | (f) | σ_X = 0 (X ≡ 2) | 400² | 1000 | 100 | 15201–15300 |
  | (b) | defaults (σ_X = 0.4) | 400² | 1000 | 100 | 15001–15100 |
  | control | γ = 10⁻⁴ | 400² | 1000 | 20 | 15501–15520 |
  | (a) | defaults | 1400² | 10⁴ | 10 | 15701–15710 |
  | (e) | β = 0.8 | 1400² | 10⁴ | 10 | 15801–15810 |

  - Every run stopped on the cell count (`Terminated`). The closest any cell came to the lattice edge was 50 sites in case (f), 34 in (b), 33 in the control, 250 in (a) and 290 in (e).
  - Cases (b) and control repeat P6.15e's seeds and protocol with a recorder added. All 120 runs stop at the same MCS as in the F5 record (`../f5-2026-10-07/runs.tsv`), so adding the recorder callback does not change a run.
  - Time to the stop count, in cycles (775 MCS): case (f) 9.91–10.05 (mean 9.97), (b) 9.73–11.04 (10.36), control 20.37–21.70 (20.69), (a) 14.92–15.49 (15.17), (e) 15.78–16.55 (16.26).

| File | Contents |
|---|---|
| `verdicts.tsv` | one line per pre-registered (row, case) pair and control pair: the consortium reference, our value, the band, PASS / FAIL; then the Fig 3, V5 and Fig 8 summaries and the control line |
| `deviations.tsv` | the D-154 table (header only: no row fails) |
| `runs.tsv` | one row per run: case, k, seed, β, γ, σ_X, lattice, return code, stop MCS, N, cycles, number of saves, closest approach to the edge, wall time |
| `timeseries.tsv` | every save of every run (55,222 rows): case, seed, MCS, N, r, A, C, w, g (R units, full Float64 precision; `nan` for N < 3). 4.9 MB, the frozen schema's minimum |
| `neighbors.tsv` | the final neighbour-number histogram (n = distinct Moore(1) neighbour cells, `PottsModels.openvt_frame`) per run, cases (a) and (e) |
| `meta.toml`, `provenance.toml` | parameters, seeds, the ensemble statistics of each case (L, r̄, Ā, t̄_s, r̄_e, Ā_e, sync, slope, offset); commit, test and runner hashes, Manifest hash, machine, timing |
| `run_f3_f8.jl` | the runner |
| `plot_f3.jl`, `fig3.png` | M Fig 3's three panels (N, r [R], A [R²] against time [T], log y). In each row: one thick blue deterministic run, thin red stochastic runs, and the dashed bulk law. The rows are TST No_CI (consortium; drawn only with `F3F8_G_OUT`) and Potts.jl (case (f) run 1 and the 100 case (b) runs) |
| `plot_f8.jl`, `fig8.png` | M Fig 8's seven panels (a–g) for case (a) and case (e), with the draft Fig 8's CompuCell3D and Morpheus lattice curves (with `F3F8_G_OUT`; legacy β = 0.8 runs in legacy cycles, lengths converted from px to R, footnoted) |
| `consortium_on_g.jl` | writes the overlay rows from a local G clone (54f375f) to `F3F8_G_OUT`: TST No_CI per-run N, r and A by the test's readers, and the legacy Fig 8 curves converted to R. Information only. Its outputs are not committed |
| `video_f3_f8.jl` | renders run 1 of cases (f), (b), (a) and (e) every 39 MCS: one categorical colour per cell, no outlines, no colour bar. The videos are not committed |

No G file entered git. The G-derived content in git is:

- the rendered consortium row of `fig3.png` and the legacy curves of `fig8.png`;
- the frozen consortium constants restated in `verdicts.tsv`;
- the small statistics quoted below.

## Result

**Every pre-registered row passes. Fig 3, V5 and Fig 8 pass, and both negative controls fail as pre-registered.**

| Row | Case | Statistic | Consortium (G, frozen) | Potts.jl | Band | Verdict |
|---|---|---|---|---|---|---|
| F3.1 | (f) | max \|L − L_TST\|, t = 0.5:1:8.5 | TST det. L = 0, 1, …, 8 | 0.000 (L = 0, 1, …, 8) | ≤ 0.3 | PASS |
| F3.2 | (f) | t̄_s / t̄_s,TST | 10.012 cycles | 0.995 (9.966) | [0.95, 1.05] | PASS |
| F3.3 | (f) | max \|r̄/r̄_TST − 1\| | r̄ 3.82…17.46, r̄_e 0.927 | 0.069 | ≤ 0.10 | PASS |
| F3.4 | (f) | max \|Ā/Ā_TST − 1\| | Ā 39.2…957.8, Ā_e 2.702 | 0.143 | ≤ 0.20 | PASS |
| F3.5 | (f) | min sync(k), k = 0:3 | 1, 1, 1, 1 | 1.00 (1, 1, 1, 1) | ≥ 0.9 | PASS |
| F3.1 | (b) | max \|L − L_TST\| | TST stoch. L = 0.09 … 8.16 | 0.134 | ≤ 0.3 | PASS |
| F3.2 | (b) | t̄_s / t̄_s,TST | 10.235 cycles | 1.012 (10.361) | [0.95, 1.05] | PASS |
| F3.3 | (b) | max \|r̄/r̄_TST − 1\| | r̄ 3.93…18.33, r̄_e 1.057 | 0.045 | ≤ 0.10 | PASS |
| F3.4 | (b) | max \|Ā/Ā_TST − 1\| | Ā 42.2…1068, Ā_e 3.522 | 0.092 | ≤ 0.20 | PASS |
| V5.1 | (a) | slope of L, t = 4.5:1:8.5 | TST 1.000 (det.), 1.013 (stoch.) | 1.022 | [0.9, 1.1] | PASS |
| V5.2 | (a) | max \|L − t\|, t = 0.5:1:8.5 | TST 0.50, 0.45 | 0.601 | ≤ 1.0 | PASS |
| V5.1 | (e) | slope of L | as above | 1.009 | [0.9, 1.1] | PASS |
| V5.2 | (e) | max \|L − t\| | as above | 0.492 | ≤ 1.0 | PASS |
| F8.1 | (a) | min g over every save | 1 (β = γ = 0) | 1 | == 1 | PASS |
| F8.2 | (a) | min C/(2√(πA)); min w | isoperimetric | 1.059; 0.062 | ≥ 1 − 1e-9; ≥ 0 | PASS |
| F8.2 | (e) | min C/(2√(πA)); min w | isoperimetric | 1.073; 0.016 | ≥ 1 − 1e-9; ≥ 0 | PASS |
| F8.3 | (a) | mean n, pooled final histogram | legacy CC3D 5.842, Morpheus 6.480 | 5.970 (100,016 cells) | [5.542, 6.780] | PASS |
| F8.4 | (e) | mean g at the 10⁴-cell stop | legacy CC3D 0.499, Morpheus 0.350 | 0.297 | [0.250, 0.599] | PASS |

| Control (pre-registered to fail) | Potts.jl | Band | Result |
|---|---|---|---|
| F3.1, control (γ = 10⁻⁴) | 1.426 | ≤ 0.3 | FAIL, as required |
| F3.2, control | 2.021 (t̄_s 20.69 cycles) | [0.95, 1.05] | FAIL, as required (> 1.05) |
| V5.1, control | 0.647 | [0.9, 1.1] | FAIL, as required (< 0.9) |
| F3.5, case (b) | 0.19 (sync 0.92, 0.68, 0.41, 0.19; TST stoch. 0.91, 0.62, 0.42, 0.17) | ≥ 0.9 | FAIL, as required |

- **The expected deviation did not occur.** D-173 named a risk: Potts divides on actual area and TST on target area (C13, Q20), so case (f)'s F3.2–F3.5 could fail. All four pass.
  - The difference is visible in the colony area instead. Case (f)'s Ā is 8.6 % above TST deterministic at t = 4.5 and rises to +14.3 % at t = 8.5 (1095 against 958 R²). Its Ā_e is +11.3 % (3.01 against 2.70 R² per cell). This is the largest margin used, F3.4 at 0.143 of 0.20.
  - Case (b)'s area is within 9.2 % throughout.
  - Information only: actual-area division (C13, Q20) is also the leading candidate for the F5 record's rim-cell deviations (`../f5-2026-10-07/deviations.tsv`).
- **Deterministic synchrony.** With X ≡ 2, every case (f) run has exactly 2^k cells at t = k + 0.5 for k = 0..8 (L = 0, 1, …, 8 on the whole grid), as TST does.
  - Our runs reach 1000 cells at 9.91–10.05 cycles, with N = 1000–1006 at the stop. TST's synchronous run jumps from 512 to 1024 at MCS 7761 (t = 10.01).
  - The last doubling, from the first save above 512 cells to the first with ≥ 1000, takes 0.23–0.41 cycles (mean 0.29) in Potts. Each cell divides when its actual area reaches 2A₀, so the 512 cells of a generation do not divide in the same MCS. TST divides on target area, every 770 MCS.
- **Stochastic case (b)** follows TST stochastic closely: L within 0.134 log₂ units, t̄_s 1.2 % later, r̄ within 4.5 % and Ā within 9.2 %. The synchrony decay, 0.92/0.68/0.41/0.19, matches TST's 0.91/0.62/0.42/0.17.
- **V5.** Cases (a) and (e) both follow the bulk law 2^t until a few hundred cells, then bend toward boundary-limited growth (`fig8.png` a–c).
  - On the pre-registered window the slopes are 1.022 and 1.009, and the offsets 0.60 and 0.49.
  - The control (γ = 10⁻⁴: interior cells arrest) bends early: slope 0.647, L = 6.74 at t = 8.5.
- **F8.3 and F8.4 against the legacy curves** (information on units: those curves are legacy β = 0.8 runs in legacy cycles, D4, Q7).
  - Case (a)'s mean neighbour number is 5.970, between CompuCell3D's 5.842 and Morpheus's 6.480. Case (e)'s is 5.976.
  - Case (e)'s final g is 0.297, below Morpheus's 0.350 and CompuCell3D's 0.499, inside the band.
  - The legacy curves' time axis is each framework's legacy cycle, not 775 MCS, so only the 10⁴-cell value of g is compared.

**Videos** are coloured per cell: each cell gets its own categorical colour from MakiePotts' identity palette (`CellIdentityEncoding`, with the D-172 fix). The medium is dark grey on a black frame, with no outlines and no colour bar, and the view zooms out with the colony. `video_f3_f8.jl` renders them from run 1 of each case, one frame every 39 MCS to the stop: (f) seed 15201, (b) seed 15001, (a) seed 15701 and (e) seed 15801. Each video stops at the same MCS as the record's run (7714, 8154, 11600 and 12550). They are not committed.

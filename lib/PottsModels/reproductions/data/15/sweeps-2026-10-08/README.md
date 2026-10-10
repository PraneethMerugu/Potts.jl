# Reproduction 15: F6 "time to 10⁴ cells" against β and γ, Table 1 (inhibition thresholds) and F7 (10⁴-cell colonies at the T1 γ values), FULL run of 2026-10-08 (P6.15g)

This is the offline record required by D-146. It was pre-registered by D-174, and its amendment switched the sweep to `BoundarySiteCPM` (D-177).

`BoundarySiteCPM` is now `SequentialCPM(; skip_interior = true)` (D-198), with the same semantics; the provenance names it as run.

- **Run.** `run_sweeps.jl` at commit `41fb2ba6` on the PC (praneeth-NucBox-EVO-X2, AMD Ryzen AI Max+ 395, Julia 1.12.6).
  - **Threads.** 12 threads, pinned to `taskset -c 6-11,22-27`, under `systemd-run --user --scope -p MemoryMax=40G`. That is the coordinator's core plan for the night, which shares the PC with a Merks FULL run on 0–5 and 16–21. Cores 12–15 were left free.
  - **Time.** The run started at 15:53 and finished at 22:42, a wall time of 24,548 s (6.8 h). The 160 runs took 247,487 CPU-s (68.7 core-hours).
  - **Estimate.** D-174's amended estimate was about 45 core-hours, for one uncontended thread per run. Here both SMT siblings of each of the 6 cores ran a job, so a run's wall time includes the sibling's share.
  - **Launches.** There was one launch, with no resume and no rerun. `provenance.toml` holds the workspace Manifest's sha256.
- **Dry run before the record.** One dry run, on the Mac on 2026-10-08 (12:58–12:59), not committed. It used `P615G_DRY=true`: 200² lattices, a 30-cell stop and a 6000-MCS cap, through the same `p615g_job`.
  - It checked the four protocol stages, the writers, a resume (every output byte-identical on the second launch), and the record tier's replay, O3, f7 and verdict-agreement paths.
  - It changed only the dry settings (from 60 cells and 4000 MCS, at which every run was capped). It is the runner's own mode; no band, rule, seed or protocol is involved.
- **Same computation as the frozen test.** The runner loads every top-level `P615G_*` constant and `p615g_*` function of `lib/PottsModels/test/reproductions/15_openvt_sweeps.jl` (sha256 `474c10c1…`, the D-174-amendment freeze) verbatim, by evaluating that file's source.
  - It then calls `p615g_protocol` with an `exec` that runs every job through the test's `p615g_job` and `p615g_o5`.
  - It replays the protocol on the written `runs.tsv` and requires the same log, then computes the verdicts with `p615g_verdicts`.
  - The test's record tier repeats all of this from the committed files. On the Mac it gives 1117 pass and 4 broken: the three deviations below, and the G tier skipped.
- **Resumable.** Each finished run went to disk at once (`$P615G_WORK/runs/<sweep>_<q>_<k>.toml`, outside the repo), and a launch reads those files back instead of rerunning. A run is a pure function of its seed, so the scheduling order (longest first, `:greedy`) does not change any result.
- **Protocol** (D-174).
  - **Model.** `OpenVTReferenceMonolayer` at Table S1 (σ_X = 0.4), with β and γ per point, from one disc cell at the centre.
  - **Algorithm.** `BoundarySiteCPM(; proposal = Moore(1))`, which is equal in law to `SequentialCPM` (D-177).
  - **Lattice.** Closed, with `edge_guard(5; terminate = true)`.
  - **Stop.** The end of the first MCS with ≥ 10⁴ cells, or the 20× cap of 210,335 MCS (t = Inf).
  - **Sweeps.** The β sweep runs on 1400² and the γ sweep on 1800². Seeds are 160 000 000 or 170 000 000 + 100 q + k.
  - **Sampling.** Grid (74 runs: 10 at β = 0, 5 at the V2b points and at γ = 10⁻⁴, 1 elsewhere), two bisection steps (16 runs), then both final bracket ends topped up to 6 replicates (70 runs). That is 160 runs, 6 of them capped.
  - **Edge.** Every run stopped on the cell count or at the cap. The closest any cell came to the lattice edge was 171 sites.
  - **Information: cost per run.** 4–5 min to 10⁴ cells at β ≤ 0.6; 28–30 min at β = 1.0; 42–114 min for the γ ≥ 0.7 runs on 1800².

| File | Contents |
|---|---|
| `verdicts.tsv` | one line per pre-registered row and control: the consortium reference, our value, the band, PASS / FAIL |
| `deviations.tsv` | the D-154 table: V1, V2.1.1x and V3b |
| `runs.tsv` | the frozen schema: sweep, q, k, seed, stage, β, γ, lattice, return code, stop MCS, N, capped, closest approach to the edge, wall time |
| `points.tsv` | per sampled point: replicates, capped count, t̄, min and max (cycles) |
| `table1.tsv` | the T1 row: final brackets with their means and replicate counts, the threshold (M's nearest rule), the log-linear interpolation, the threshold relative to Potts' own t̄(β = 0), TST's and Artistoo's thresholds (frozen constants), the spread and the band |
| `Potts.jl_time_to_10k_vs_beta.csv`, `…_vs_gamma.csv` | O3, one row per run (`nan` MCS when capped), as the consortium submission requires |
| `f7/` | O5 for the five Fig 7 panels: replicate 1 at γ = 0, 10⁻⁴, 0.1625, 0.5375 and 0.7625 |
| `meta.toml`, `provenance.toml` | protocol, run counts, final brackets, information values (relative and interpolated thresholds); commit, test and runner hashes, Manifest hash, machine, timing |
| `run_sweeps.jl` | the runner |
| `plot_f6.jl`, `fig6.png` | M Fig 6's two panels: every run, the point means, the Potts T1 thresholds (rings), and TST's and Artistoo's Table 1 thresholds and V2b references from the test's frozen constants |
| `plot_f7.jl`, `fig7.png`, `fig7_cells.png` | M Fig 7's five panels, labelled "γ=…, T=…". `fig7.png` is M's form, from O5: filled discs, growing blue and inhibited orange, no strokes. `fig7_cells.png` shows the same five final states as lattice stills, one categorical colour per cell (`CellIdentityEncoding`, D-172), white medium, no cell outlines. It is rendered on the PC from the runner's serialized states, which are not committed |

No G file was read or entered git. The only consortium content is the frozen constants of the test, restated in `verdicts.tsv`, `table1.tsv` and `fig6.png`.

## Result

**Of the 18 pre-registered rows, 15 pass and 3 fail: V1, V2.1.1x and V3b, recorded as D-154 deviations in `deviations.tsv`.** All three negative controls fail, as pre-registered. No band, rule or protocol was changed.

### Table 1 (T1): thresholds at multiples of M's uninhibited time 13.57 × 5T

| | 1.1× (14.927) | 2× (27.14) | 5× (67.85) | 10× (135.7) | 20× (271.4) |
|---|---|---|---|---|---|
| β, Potts.jl (M's rule) | **0.625** (FAIL) | 0.9375 | 0.9875 | 1.007 | 1.0212 |
| β, interpolated (info) | 0.629 | 0.939 | 0.988 | 1.007 | — (hi end capped) |
| β, relative to own t̄ = 14.945 (info) | 0.80 | 0.95 | 0.99 | 1.01 | 1.02 |
| β, TST / Artistoo | 0.7037 / 0.6982 | 0.9361 / 0.9377 | 0.9867 / 0.9876 | 1.006 / 1.0059 | 1.02 / 1.0209 |
| β band | [0.667, 0.724] | [0.916, 0.963] | [0.9817, 0.9966] | [1.001, 1.016] | [1.015, 1.029] |
| γ, Potts.jl (M's rule) | — | — | 0.1625 | 0.5375 | 0.7625 |
| γ, interpolated (info) | | | 0.158 | 0.538 | — |
| γ, relative to own t̄ (info) | — | — | 0.20 | 0.60 | 0.75 |
| γ, TST / Artistoo | — / — | — / — | 0.12 / 0.0756 | 0.5 / 0.4502 | 0.75 / 0.7150 |
| γ band | "—" | "—" | [0.026, 0.17] | [0.40, 0.55] | [0.665, 0.81] |

### Every row

| Row | Statistic | Consortium (frozen) | Potts.jl | Band | Verdict |
|---|---|---|---|---|---|
| V1 | t̄ at β = γ = 0, 10 runs | 13.57 (TST plateau 13.77, Artistoo 13.856) | 14.945 (14.48–15.31) | [12.213, 14.927] | **FAIL** (deviation) |
| V2.1.1x | β threshold, 1.1× | spread 0.687–0.704 | 0.625 | [0.667, 0.724] | **FAIL** (deviation) |
| V2.2x | β threshold, 2× | 0.936–0.943 | 0.9375 | [0.916, 0.963] | PASS |
| V2.5x | β threshold, 5× | 0.9867–0.9916 | 0.9875 | [0.9817, 0.9966] | PASS |
| V2.10x | β threshold, 10× | 1.006–1.011 | 1.007 | [1.001, 1.016] | PASS |
| V2.20x | β threshold, 20× | 1.020–1.024 | 1.0212 | [1.015, 1.029] | PASS |
| V2b.0.8727 | t̄ / Artistoo 18.59 | | 0.997 (18.54) | [0.75, 1.25] | PASS |
| V2b.0.9 | t̄ / TST 20.40 | | 1.013 (20.66) | [0.75, 1.25] | PASS |
| V2b.0.9334 | t̄ / Artistoo 25.59 | | 1.007 (25.77) | [0.75, 1.25] | PASS |
| V2b.0.95 | t̄ / TST 32.11 | | 0.971 (31.19) | [0.75, 1.25] | PASS |
| V2b.1.0 | t̄ / TST 105.76 | | 0.962 (101.7) | [0.75, 1.25] | PASS |
| V3.1.1x, V3.2x | γ threshold, 1.1× and 2× | "—" (the γ → 0⁺ jump) | "—" | "—" | PASS |
| V3.5x | γ threshold, 5× | 0.076–0.12 | 0.1625 | [0.026, 0.17] | PASS |
| V3.10x | γ threshold, 10× | 0.45–0.50 | 0.5375 | [0.40, 0.55] | PASS |
| V3.20x | γ threshold, 20× | 0.715–0.76 | 0.7625 | [0.665, 0.81] | PASS |
| V3b | t̄ at γ = 10⁻⁴, 5 runs | TST 61.37, Artistoo 63.09 | 58.755 (58.42–59.11) | [61, 70] | **FAIL** (deviation) |
| F7.1 | min inhibited fraction at the T1 γ (replicate 1) | TST 0.961, 0.978, 0.990 | 0.962 (0.962, 0.980, 0.987) | ≥ 0.90 | PASS |

| Control (pre-registered to fail) | Potts.jl | Band | Result |
|---|---|---|---|
| NC1: V3b rule at γ = 0 | 14.945 | [61, 70] | FAIL, as required |
| NC2: V2b at a β offset of 0.05 | 1.529, 3.167 | both in [0.75, 1.25] | FAIL, as required |
| NC3: V1 rule at γ = 10⁻⁴ | 58.755 | [12.213, 14.927] | FAIL, as required |

### Notes

- **V1 fails by 0.12 %.** It was expected (D-173, D-174).
  - 14.945 cycles is 10.1 % above M's 13.57, just past the + 10 % edge (14.927).
  - Potts' uninhibited time is flat at 14.7–15.1 for β ≤ 0.65, against TST's 13.6–13.9.
  - The leading candidate, as in D-173 and the F5 record, is division on actual area against TST's target area (C13, Q20).
  - **Information.** D-173 measured 15.17 for the same case with `SequentialCPM` on other seeds. The difference, 0.22 cycles, is about 1.9 standard errors, in line with D-177's equivalence.
- **V2.1.1x follows from V1, as D-174 anticipated.**
  - τ₁.₁ = 14.927 lies on the flat plateau, so the first crossing is set by run-to-run noise (sd 0.27 cycles): bracket 0.625 / 0.6375 at 14.83 / 15.12.
  - Against Potts' own t̄(β = 0), the same rule gives 0.80 (information). Every β threshold from 2× up is inside its band and within 0.002 of TST.
- **The steep β end matches TST closely.** V2b ratios are 0.96–1.01, and the 5×, 10× and 20× β thresholds are 0.9875, 1.007 and 1.0212, against TST's 0.9867, 1.006 and 1.02.
- **V3b fails by 3.7 %.**
  - The γ → 0⁺ jump is reproduced: 14.9 → 58.8 cycles from γ = 0 to 10⁻⁴, a factor of 3.9; TST's is 4.5. That puts the 1.1× and 2× γ rows at "—", as for every lattice framework.
  - The jump plateau is lower than TST's: 58.3–59.5 cycles for γ ≤ 0.05.
  - So Potts is slower than TST at γ = 0 but faster when only rim cells grow. A plain rate offset cannot cause both. See `deviations.tsv`; the cause is unverified.
- **The γ thresholds pass.** 5× is at 0.1625, near the top of the [0.026, 0.17] band; 10× is 0.5375 and 20× is 0.7625. The Potts γ curve lies 4–11 % below TST's samples along the whole sweep (62.4 at γ = 0.1, 121.8 at 0.5 and 257.9 at 0.75, against TST's 68.34 at 0.12, 132.14 at 0.5 and 278.78 at 0.75), the same direction as V3b.
  - At γ = 0.8 the run is capped (8876 cells at 271.4 cycles). At γ = 0.7625 it is 259.9 cycles.
  - The interiors are fully arrested: 95.7–98.7 % of cells are inhibited in the F7 panels, against TST's 96.1–99.0 %.
- **Colony shape** (`fig7_cells.png`, information). At high γ the colonies become ragged and porous, as in TST's F7 row. Growth is confined to cells with free surface, so the rim roughens.

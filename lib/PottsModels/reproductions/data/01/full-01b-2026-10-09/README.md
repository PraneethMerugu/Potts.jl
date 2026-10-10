# Reproduction 01b (Merks et al. 2008, digitised figures): FULL record, 2026-10-09

The frozen FULL tier of `lib/PottsModels/test/reproductions/01_merks_01b.jl` (D-202, sha256 `62b60427…`), run by `lib/PottsModels/reproductions/data/01/run_full_01b.jl` (sha256 `12dcf0a7…`) at commit 784e1548 (clean tree) on the PC (D-157). The targets are 133 points digitised from 01b Figs 5, 7–10 and 12, Fig 13's Σ ΔH, and 16 shape rows; the digitised files are in `lib/PottsModels/test/reproductions/data/01b/`. The frozen test's record tier recomputes every row from `sweeps.tsv` and `series.tsv`. Shipped as provisional under D-154.

## Provenance

- Commit 784e15488dc76745bac46506002fc159e671f7ef; Julia 1.12.6; 24 threads, one job per thread.
- Machine: AMD Ryzen AI Max+ 395 w/ Radeon 8060S (x86_64, Linux), CPU.
- `SequentialCPM()`, `field_solver = ExplicitEuler(substeps = 15)`.
- One launch at 2026-10-09T12:51; jobs finished 13:03–17:34 (about 4.7 h). Job walls sum to 407 083 s (113 thread-hours; longest job 759 s), in `job_walls.tsv`.
- Jobs: 1330. There are 1030 sweep jobs (Figs 5, 7–10; n = 10 per point; C at N and N + 100). There are 300 series jobs (Figs 12–13; 100 per arm; C and Σ ΔH every 50 MCS to 5100). Seeds are pre-registered in the frozen test and listed per job.

## Files

- `sweeps.tsv`, `series.tsv`: the record, in the frozen test's schema.
- `verdicts.tsv`: every point, row and negative control as the runner judged it (169 lines).
- `job_walls.tsv`: wall time per job.
- `provenance.toml`: commit, test and runner sha256, machine, threads, seeds, job counts.
- `deviations.tsv`: one line per FAIL (D-154): id, row, check, target, ours, paper, suspected cause and author-question status. It was added after the run. The frozen test marks a listed failing row `@test_broken`, and page 01's deviations table reads the cause and status from it.

The per-job files and the launch log stay on the PC.

## Tally

- **Rows: 27 of 29 pass.** The 29 rows are 13 curve rows and 16 shape rows.
- **Negative controls: 7 of 7 fail, as required.**
- **Points: 126 of 133 pass.** The 7 misses are six in F7.noCI and F8.CI at χcM = 0. The F8.CI miss is inside that curve's allowance, so F8.CI passes (1 of 8 points outside).

The two failing rows have one cause (details in `deviations.tsv`):

- **F7.noCI** (6 of 10 points outside) and **F7.gap** (0.616 against [0.49, 0.60]).
  - Our no-CI plateau in Fig 7 is about 0.92, against the paper's about 0.83.
  - However, the paper's own Figs 8 and 9 give 0.921 and 0.920 for no CI at the same default point (J_cc = 40, χcM = 500, s = 0). Fig 7 gives 0.829 there.
  - Ours is 0.918–0.923 in all three sweeps. So we match Figs 8 and 9 and miss Fig 7: the paper is inconsistent with itself at that point.
  - Our CI arm matches Fig 7 (0 of 9 points outside). F7.gap fails only because the no-CI arm is high.
  - The N + 100 clock (I6) does not change this.
  - Under review. Not yet on the open question list.

Every other figure passes. That covers Fig 5 and its midpoint, Figs 8–10 and their shape rows, Fig 12's three arms with order and rates, and Fig 13's sign, order and magnitudes. Fig 13's ratios to the paper are 1.03, 1.00 and 1.05.

The inferred set-ups I1–I7 (D-202) remain provisional defaults. Each is a row of page 01's deviations table.

## Reproducing

From the checkout root, at commit 784e1548 or any commit with the same frozen test:

```sh
julia --project=lib/PottsModels/test lib/PottsModels/reproductions/data/01/run_full_01b.jl \
    --out <dir outside reproductions/data/01> --threads 24
```

The runner is resumable. When every job is done, it writes `<dir>/full-01b-<date>/`. To check a committed record, run the frozen test. Its record tier reads the single `reproductions/data/01/full-01b-*` directory with no environment variable:

```sh
julia --project=lib/PottsModels/test lib/PottsModels/test/reproductions/01_merks_01b.jl
```

Each job is single-threaded, and its seed fixes both its start and its solver.

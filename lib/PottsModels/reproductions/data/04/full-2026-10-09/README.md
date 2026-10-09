# Reproduction 04 (Jiang et al. 1999, sheared 2D foam): FULL record, 2026-10-09

The frozen FULL tier of `lib/PottsModels/test/reproductions/04_foam.jl` (D-190, sha256 `b043d3e2…`), written by the runner `lib/PottsModels/reproductions/data/04/run_full.jl` at commit 0ca8cdd7 (clean tree). The frozen test's record tier re-derives τ, κ and every row from these TSVs. Shipped as provisional under D-154.

## Provenance

- Commit 0ca8cdd76e30cd37d6b76d5dfbc82895eae2067b; Julia 1.12.6; 24 threads.
- Machine: AMD Ryzen AI Max+ 395 w/ Radeon 8060S (x86_64-linux-gnu), CPU.
- Started 2026-10-09T01:49, finished 2026-10-09T11:31; wall time 34 922 s (9.7 h).
- Jobs: 40 foams, 165 calibration loops, 530 loops, 15 steady runs, 200 bulk runs. Seeds in `provenance.toml`.
- Calibrations: τ = 3.447 our MCS per paper MCS (A-5), r\* = 4.827, κ = 2.497 (A-1).
- Algorithm: the run used `BoundarySiteCPM()` with `NeighborOrder(4)` proposals (DV1). Under D-198 this algorithm is now `SequentialCPM(; skip_interior = true)` (same semantics); the provenance names it as run.

## Files

- `foams.tsv`, `calibration.tsv`, `loops.tsv`, `steady.tsv`, `bulk.tsv`, `windows.tsv`, `spectra.tsv`: the record, in the frozen test's schema (`P64R_SCHEMA`).
- `provenance.toml`: commit, machine, threads, seeds, wall time, job counts.
- `verdicts.tsv`: every row as the runner judged it.
- `deviations.tsv`: one row per FAIL (D-154): id, target, ours, paper, suspected cause, author-question status. Added after the run; the frozen test marks a listed failing row `@test_broken`.

## Tally

52 lines in `verdicts.tsv`: 28 PASS, 24 FAIL. The PASS lines are 18 of the 42 pre-registered rows, all 4 negative controls (C-V1, C-V9, C-V12, C-V16) and 6 info lines (κ, r\*, τ, V3t, V6c, V15e). `provenance.toml` counts controls with rows (22 pass, 24 fail).

The 24 failing rows fall in three groups (details in `deviations.tsv`):

- **Pinning at low β (V11a, V11c, V12 at β = 0.001, V14a, V14b, V15a, V15c, V15d, part of V13a).** The provisional displacement-form drive (F1) has a pinning threshold at low β; under review. Model β = κ × 0.001 ≈ 0.0025 gives a per-copy bias of about 0.64, below the integer ΔH barriers, so there are no T1s at β ≤ 0.001, and none in the ordered foam at β = 0.005. Ordered β·t_first is 0.105 against the paper's ≈ 48.
- **Window length (V18).** The fixed 100 paper-MCS window saturates in steady flow at β ≥ 0.02.
- **Disagreements under review.** V2ii, V3b, V4 and V5b (a cliff in the κ calibration curve), V6b (T not scaled with κ), V7i, V7ii and V20 (no shear localisation), V7iii, V9, V10a and V11b (a strong T1 spectral peak near 6.7 × 10⁻³), V13a and V13b (φ spectra steeper than 1/f), V14c (the 320² foams' N̄ not rescaled for L).

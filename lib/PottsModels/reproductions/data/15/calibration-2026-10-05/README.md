# Reproduction 15: F2 / Table S5 chain calibration, FULL run of 2026-10-05 (P6.15b, D-148)

This is the offline record required by D-146.

- **Run.** `run_calibration.jl` at commit 30c39601. It reruns the FULL tier of the frozen test `lib/PottsModels/test/reproductions/15_openvt_calibration.jl` (sha256 f42bc57a…), through the public API only.
- **Same computation as the test.** The seeds are 1000λ + i for the 11-chain and 21000 + i for the 21-chain, 100 runs each. The runs last 7·T_S5(λ) and 10·T(2) MCS after the release, with `SequentialCPM(; proposal = Moore(1))` and `openvt_release(100)`. The observables and pass bands are the test's.
  - The one difference: the runner also saves the 100-MCS burn-in (spec P6), so the time series start at t = −100.
  - A separate check, not committed, ran the test's own `p615b_runs` next to the runner's. All 4 + 1 width matrices (t ≥ 0) and the area matrices are bitwise identical.
  - The frozen test with `POTTS_FULL_REPRODUCTION=true` also passes (213 pass; the 2 broken are the skipped G rows).
- **Setup.** 4 threads, Apple M1 Pro, Julia 1.12.6. Wall time 13.9 s, of which 11.2 s is simulation.

| File | Contents |
|---|---|
| `verdicts.tsv` | the pass/fail table: V6 (T per λ, monotone), V7 (5T coverage, MSE per λ; w₁₁ at 0.5T and 2T at λ = 2), V8 (w₂₁ and inner w₁₁ at 1/5/10 T, plateau end), plus reported rows (per-run crossings, P12) |
| `timeseries_11chain.tsv` | per λ and per MCS (t = −100 … 7·T_S5): the replicate mean and SD of w₁₁, and t/T(λ) |
| `crossings.tsv` | per λ and seed: the run's own crossing time (P8) and the compressed cells' mean area at t = 0 and at the end |
| `timeseries_21chain.tsv` | per MCS (t = −100 … 10·T(2)): the mean and SD of w₂₁ and of the inner w₁₁ |
| `reference.tsv` | the spring–dashpot w(t) (`spring_dashpot_width`, free ends) on t = 0:0.1:5 T |
| `meta.toml` | seeds, λ, lattices, run lengths, CD, burn-in, algorithm, threads, T |
| `provenance.toml` | commit, test and runner hashes, environment, Julia, machine, start/finish, wall time |
| `run_calibration.jl` | the runner |
| `plot_calibration.jl`, `fig2_bde.png` | M Fig 2b/2d/2e layout from the TSVs, Potts only (`julia --project=docs`) |

There is no video. The consortium (G) curves are not in this record, and never enter git.

**Result.** Every V6–V8 row passes.

- **V6.** T = 297, 156, 111 and 77 MCS for λ = 1, 2, 3 and 5. That is 1.02–1.03× Table S5, and T strictly decreases in λ.
- **V7.** MSE/S5 = 1.69, 0.38, 0.92 and 0.76, against a bound of 3. At λ = 2, w₁₁(0.5T) = 7.859 and w₁₁(2T) = 9.794.
- **V8** at T = 156, with no refit:
  - w₂₁ = 15.96, 19.28 and 19.89 at 1, 5 and 10 T;
  - the inner w₁₁ = 7.24, 9.51 and 9.93;
  - the plateau ends at 0.173 T.
- **The two lowest V8 values.** w₂₁(10T) = 19.889 is just under the lattice spread of 19.90–19.96, but inside the ± 0.15 band. The inner w₁₁(1T) = 7.241 is near the spread's low end.

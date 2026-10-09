# Reproduction 01 (Merks 2006, 2008): FULL record, 2026-10-08

The frozen FULL tier of `lib/PottsModels/test/reproductions/01_merks.jl` (D-153), one replicate per job, 590 jobs, run on the PC (praneeth-NucBox-EVO-X2, AMD Ryzen AI Max+ 395, CPU, 12 threads; D-156). The page test `01_merks_page.jl` (D-184) re-derives every verdict from `replicates.tsv`.

- `run_full.jl`: the runner. Launch 1 (3f1c441a) ran every simulation and wrote each job's σ snapshots. A sort bug in `observe` then failed 570 of the 590 jobs before their rows were written. Launch 2 (4f3a210e) rebuilt those rows from the snapshots, with no simulation. See `provenance.toml` and `job_walls.tsv` (walls taken from the run log).
- `evaluate.jl`: applies the frozen FULL rules. It wrote `verdicts.tsv` (37 checks; 36 PASS, V-C12 FAIL at 1.26 from MCS 100; now 37 PASS, see below), `points.tsv` (2008 sweep means at N and N + 100) and `replicates.tsv` (full precision).
- `deviations.tsv`: the diagnosis of each failing check, shown in the page's deviations table.
- `snap/`: the σ snapshots of two jobs (E5_L10_s1201, C3_r0_s3101), for the page test's oracle. All 570 snapshots (238 MB) stay on the PC at `~/potts-ci/p6-3f-out/snap`.
- `videos.toml`: two replicates rerun with dense saves and rendered one colour per cell, without outlines. Each was checked against its snapshot. They are release assets of `reproductions-2026-10-08-merks`.
- `figures.jl` → `sweeps_2008.png`: the 2008 sweeps at both clocks.
- The run log (`~/potts-ci/p6-3f-run.log`) stays on the PC.
- 2026-10-09 (D-200 item 1): V-C12 now measures displacement from MCS 0, as 01b Fig. 6E does, instead of MCS 100 (frozen test amended; band unchanged). `vc12_mcs0.jl` re-read the stored V-C12 snapshots with no new dynamics and wrote `vc12_mcs0.tsv`; the ratio is 2.017 (82.8 / 41.1 µm), so V-C12 passes and its deviations row is removed.

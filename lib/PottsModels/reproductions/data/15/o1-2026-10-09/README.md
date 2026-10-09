# Reproduction 15: O1 per-cell time series of cases (a), (b), (e), (f) and the O2 files (P6.15j)

The D-146 offline record of the OpenVT O1 output (spec 15 §3.1 O1, §4.0 A3, §4.0.1),
required by D-204 and pinned by D-206. It holds manifests only: the O1 files (about
320 MB zipped with the O2 files) are too large for git and live in the bulk directory
`OPENVT_PACKAGE_BULK`, outside git. `PottsModels.openvt_submission_package` refuses a bulk
directory whose files differ from the sha256s pinned here.

- **Runs.** Cases (a), (b), (e) and (f) of the P6.15f record (`../f3-f8-2026-10-08/`), re-run
  from its recorded seeds with its protocol: `run_o1.jl` loads the frozen F3/F8 test's
  constants and functions verbatim, and its recorder `p615f_run` with one change, an O1 file
  written at every save. Every run's saves (MCS, N, r, A, C, w, g), stop MCS, final N and
  final neighbour histogram are checked to equal the P6.15f record before any file is
  written here.
- **O1 files.** One per run and save, `centroids/<case>/potts_<case>_s<seed>_<MCS:06d>.csv`,
  header `x,y,i,n`, one row per live cell (`PottsModels.openvt_frame`: centroid in R from the
  lattice centre, inhibition code, number of neighbour cells), packed per case into
  `Potts.jl_centroids_<case>.zip` (sorted members, no directory entries, no extra
  attributes).
- **O2 files.** `Potts.jl_5T_MonolayerGrowth_1000_Data/cell_data_no_inhibition_<k>.csv`,
  case (b), k = 1:100: the P6.15e runner's files when they agree with this re-run's stop
  states, else written from them; `provenance.toml` (`o2_source`) says which.

| File | Contents |
|---|---|
| `runs.tsv` | one row per re-run: case, k, seed, stop MCS, N, saves (equal to the P6.15f `runs.tsv`) |
| `o1_manifest.tsv` | one row per O1 file, sorted by file: case, seed, MCS, file, rows, bytes, the counts of the inhibition codes i0–i3, sha256 |
| `archives.tsv` | one row per case: the archive, its member count, size and sha256 |
| `o2_manifest.tsv` | one row per O2 file: k, file, rows, bytes, sha256 |
| `provenance.toml` | commit, test and runner hashes, Manifest hash, machine, threads, timing, file counts and sizes |
| `run_o1.jl` | the runner (its header has the command) |

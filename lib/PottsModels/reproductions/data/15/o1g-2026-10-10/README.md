# Reproduction 15: the O1 and O2 files in the consortium scripts' form (P6.15l)

The D-146 record of the D-215 post-processing of the P6.15j record (`../o1-2026-10-09/`).
Nothing was re-run: `post_o1.jl` rewrote the P6.15j files in the bulk directory
`OPENVT_PACKAGE_BULK` (outside git) into the form the consortium repository's scripts read,
and wrote the new zips next to the old ones. Like the P6.15j record, this one holds
manifests only. `PottsModels.openvt_submission_package` refuses a bulk directory whose new
zips differ from the sha256s pinned here.

- **O1** (D-215 (1), (5)). Every P6.15j O1 file gains the column `g` (g = 1 if i == 0, else
  0), which `metrics.cpp` requires: header `x,y,i,n,g`, each file exactly 2 (rows + 1) bytes
  larger. Files are packed per case into a descriptively named zip, with members
  `<stem>/s<seed>/potts_<case>_s<seed>_<MCS:06d>.csv`:

  | Case | Zip |
  |---|---|
  | (a) β = γ = 0, to 10⁴ cells | `Potts.jl_beta0.0_gamma0.0.zip` |
  | (b) stochastic, to 10³ cells | `Potts.jl_No_CI_stochastic.zip` |
  | (e) β = 0.8, to 10⁴ cells | `Potts.jl_beta0.8_gamma0.0.zip` |
  | (f) deterministic, to 10³ cells | `Potts.jl_No_CI_deterministic.zip` |

- **O2** (D-215 (3)). The 100 case (b) files renumbered k = 0…99 (P6.15j file k + 1, bytes
  unchanged), zipped with their folder inside: `Potts.jl_5T_MonolayerGrowth_1000_Data.zip`.
- **Deterministic.** Sorted members, mtime 1980-01-01 00:00 UTC, `zip -X -D -9` under
  TZ=UTC: the same P6.15j files give the same zip bytes.

| File | Contents |
|---|---|
| `o1_manifest.tsv` | one row per O1 file, sorted by file: case, seed, MCS, file, rows, bytes, the counts of the inhibition codes i0–i3, sha256 |
| `archives.tsv` | one row per O1 zip and one (case `O2`) for the O2 zip: members, size, sha256 |
| `o2_manifest.tsv` | one row per O2 file: k, file, rows, bytes, sha256 |
| `provenance.toml` | the source record, commit, runner hash, machine and timing |
| `post_o1.jl` | the runner (its header has the command) |

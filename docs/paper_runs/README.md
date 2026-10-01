# Paper runs

One script per published model in `lib/PottsModels`. Each runs the model as its paper ran it
(the paper's lattice, initial state, parameters and run length, with a fixed seed) and records
a video for the docs:

| Script | Model | Paper run |
|---|---|---|
| `graner_glazier.jl` | `GranerGlazier` | Graner & Glazier (1992, 1993): ~1000-cell aggregate, 10⁴ paper MCS (160 000 MCS) |
| `wortel_act.jl` | `WortelAct` | Niculescu et al. (2015): one amoeboid cell, 200×200 torus, 30 000 MCS; cell and Act field |
| `openvt_monolayer.jl` | `OpenVTGrowingMonolayer` | OpenVT monolayer benchmark: one cell grown to 10⁴ cells |
| `akeeb_invasion.jl` | `AkeebInvasion` | Akeeb, Marcus & Jiang (2026): multimodal sample (J_LF = 2, μ = 24, PP = 0.5), 500×300, 701 MCS |
| `merks_vasculogenesis.jl` | `MerksVasculogenesis` | Merks et al. (2006): 282 cells on 500×500, 6000 MCS (50 h) |

Each script writes two files to `docs/src/assets/paper_runs/`, and both are committed:

- `<model>.mp4`: the video (H.264). Files over 5 MB are re-encoded with ffmpeg
  (`-crf 28 -preset slow -pix_fmt yuv420p`).
- `<model>.toml`: the record of the run. It holds the caption shown in the docs, the paper and
  figure, lattice, MCS, seed, algorithm, backend, solve and recording wall times, the git
  commit, and the deviations from the paper.

These scripts are **not** run by the docs build (`docs/make.jl`). The docs pages embed the
committed videos. To regenerate one, run it from the repository root:

```bash
julia --project=docs docs/paper_runs/graner_glazier.jl
```

The run is deterministic for a given seed, commit and Julia version. All runs use the CPU
`SequentialCPM` with the model's declared proposal neighbourhood. `common.jl` holds the shared
solve, record and sidecar code. ffmpeg must be at `/opt/homebrew/bin/ffmpeg` only for the
re-encode step. Wall times are for a shared 8-core Apple Silicon machine:

| Script | Wall time (approx.) |
|---|---|
| `wortel_act.jl` | ~1 min solve |
| `akeeb_invasion.jl` | ~15 s solve |
| `merks_vasculogenesis.jl` | a few min solve |
| `openvt_monolayer.jl` | ~5 min solve |
| `graner_glazier.jl` | ~10–20 min solve |

Recording takes 1–5 min more per video. The `.toml` sidecars hold the measured times.

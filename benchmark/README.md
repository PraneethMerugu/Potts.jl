# Benchmarks

- `graner.jl` — fresh-process timing of Graner–Glazier (load, problem build, first MCS,
  first MCS after `remake`, warm throughput):
  `julia -t auto --project=benchmark benchmark/graner.jl [seq|cpu|metal] [mcs] [scale]`
- `benchmarks.jl` — BenchmarkTools `SUITE` (AirspeedVelocity-compatible) of the warm MCS.
- `data/graner/` — the pre-equilibrated 72² SCDPotts baseline (64 cells) and its provenance
  (`provenance.toml`, legacy `metrics.tsv`).

Legacy comparison: `julia --project=reference reference/graner.jl [mcs] [seed]`.

## 2026-09-29, Apple M1 Pro, Julia 1.12.6, 8 threads (MCS = N attempts)

| run | first MCS | remake + first MCS | warm | ns/attempt |
|---|---|---|---|---|
| legacy Potts 427dc2e2, sequential 72², 320 MCS | — (build 5.9 s, solve 27.4 s incl. compile) | | | |
| sequential 72² Float64 | 0.19 s | 0.018 s | 6130 MCS/s | 31 (24.8 BenchmarkTools median) |
| checkerboard CPU 72² Float64 | 0.9 s | 0.02 s | 5690 MCS/s | 34 |
| checkerboard CPU 576² Float64 | 0.9 s | 0.02 s | 296 MCS/s | 10.2 |
| checkerboard Metal 72² Float32 | 3.1 s | 0.03 s | 4470 MCS/s | 43 (launch-bound) |
| checkerboard Metal 576² Float32 | 3.1 s | 0.03 s | 926 MCS/s | 3.25 |

The reference environment's precompile alone takes 491 s; the workspace's CorePotts 1.9 s.

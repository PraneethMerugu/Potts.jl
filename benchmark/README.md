# Benchmarks

- `graner.jl` — fresh-process timing of Graner–Glazier (load, problem build, first MCS,
  first MCS after `remake`, warm throughput):
  `julia -t auto --project=benchmark benchmark/graner.jl [seq|cpu|metal] [mcs] [scale]`
- `benchmarks.jl` — BenchmarkTools `SUITE` (AirspeedVelocity-compatible) of the warm MCS.
- `lib/PottsModels/data/graner/` — the pre-equilibrated 72² initial condition (64 cells).

The legacy rows below were measured with the since-removed `reference/` pin (D-048).

## 2026-09-29, Apple M1 Pro, Julia 1.12.6, 8 threads (MCS = N attempts)

| run | first MCS | remake + first MCS | warm | ns/attempt |
|---|---|---|---|---|
| legacy Potts 427dc2e2, sequential 72², 320 MCS | — (build 5.9 s, solve 27.4 s incl. compile) | | | |
| sequential 72² Float64 | 0.19 s | 0.018 s | 6130 MCS/s | 31 (24.8 BenchmarkTools median) |
| checkerboard CPU 72² Float64 | 0.9 s | 0.02 s | 5690 MCS/s | 34 |
| checkerboard CPU 576² Float64 | 0.9 s | 0.02 s | 296 MCS/s | 10.2 |
| checkerboard Metal 72² Float32 | 3.1 s | 0.03 s | 4470 MCS/s | 43 (launch-bound) |
| checkerboard Metal 576² Float32 | 3.1 s | 0.03 s | 926 MCS/s | 3.25 |

The legacy environment's precompile alone took 491 s; the workspace's CorePotts 1.9 s.

### After audit group 1 and CPU `_launch` (2026-09-29, same machine, `-t auto` = 6 threads)

| run | first MCS | remake + first MCS | warm | ns/attempt |
|---|---|---|---|---|
| sequential 72² Float64 | 0.30 s | 0.020 s | 7207 MCS/s | 26.8 |
| checkerboard CPU 72² Float64 | 0.88 s | 0.021 s | 6652 MCS/s | 29.0 |
| checkerboard CPU 576² Float64 | 1.02 s | 0.023 s | 412 MCS/s | 7.3 |
| checkerboard Metal 72² Float32 | 3.2 s | 0.032 s | 5551 MCS/s | 34.8 |
| checkerboard Metal 576² Float32 (2000 MCS) | 3.5 s | 0.036 s | 956 MCS/s | 3.15 |

Warm throughput is at or above the table above everywhere. Metal 576² needs 2000 MCS to
settle (500 MCS read 785 MCS/s). A warm MCS of every published model allocates 0 bytes,
sequential and checkerboard, now gated in the QA group.

### Generated (symbolic) vs hand-written Graner–Glazier, warm MCS (2026-09-29)

`PottsModels.GranerGlazier` through `PottsProblem` vs the hand-written CorePotts port,
BenchmarkTools median ns per site per MCS, Apple M1 Pro:

| run | hand-written | generated |
|---|---|---|
| sequential 72² | 24.4 | 25.8 |
| sequential 288² | 24.9 | 26.3 |
| checkerboard CPU 72² | 26.4 | 28.9 |
| checkerboard CPU 288² | 19.1 | 17.4 |

The generated ΔH is one fused contact loop plus the expanded volume delta. The remaining
~6% on small lattices is within per-call overhead and has not been chased further.

### Time to first MCS per published model (fresh process, warm package cache, 2026-09-29)

`julia --project=lib/PottsModels/test /tmp/ttfx_models.jl <model>` (build = `PottsProblem`
from the `@potts_model` constructor, including `mtkcompile` and code generation):

| model | `using Potts, PottsModels` | build | first sequential MCS | first checkerboard MCS |
|---|---|---|---|---|
| Graner–Glazier 72² | 4.6 s | 2.9 s | 0.5 s | 0.7 s |
| Wortel Act 150² | 4.8 s | 3.0 s | 1.0 s | 0.7 s |
| Merks 100² | 4.8 s | 2.6 s | 1.0 s | 1.0 s |
| OpenVT monolayer | 4.8 s | 3.3 s | 2.1 s | 1.0 s |
| Akeeb invasion 99×60 | 4.6 s | 3.7 s | 2.2 s | 1.2 s |

Re-measured after audit group 1 and CPU `_launch` (same command):

| model | `using Potts, PottsModels` | build | first sequential MCS | first checkerboard MCS |
|---|---|---|---|---|
| Graner–Glazier 72² | 4.9–6.5 s | 1.8 s | 0.9 s | 1.0 s |
| Wortel Act 150² | 5.0 s | 1.6 s | 1.2 s | 1.0 s |
| Merks 100² | 4.9 s | 1.3 s | 1.1 s | 1.0 s |
| OpenVT monolayer | 4.9 s | 1.9 s | 2.8 s | 1.3 s |
| Akeeb invasion 99×60 | 5.1 s | 2.6 s | 2.9 s | 1.4 s |

Build dropped by 1.1–1.4 s: the Potts precompile workload now covers `generated_code` and
`PottsProblem`. The first sequential MCS rose by 0.1–0.7 s; the cause is not isolated (Graner, which has
no phases, rose too, so it is not only group 1's new snapshot phases). Build plus first MCS is equal or lower for
every model; all are well under the 15 s target. The 6.5 s `using` was the first process
after a rebuild.

Legacy Graner–Glazier: build 5.9 s, first 320-MCS solve 27.4 s (mostly compilation).

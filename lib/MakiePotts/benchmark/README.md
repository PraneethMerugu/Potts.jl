# MakiePotts benchmarks

Run the non-gating smoke benchmarks with:

```sh
julia --project=lib/MakiePotts/benchmark \
  lib/MakiePotts/benchmark/benchmarks.jl
```

Set `MAKIEPOTTS_BENCHMARK_REPORT` to write a TOML report containing median
nanoseconds, GC nanoseconds, memory bytes, and allocation counts for every
operation. Wall-clock results are evidence, not CI pass/fail thresholds.

Deterministic warmed allocation ceilings for the 256×256 fixture live in the
normal MakiePotts test suite. Do not commit a benchmark `Manifest.toml`; the
environment is intended to resolve against the declared compatibility bounds.

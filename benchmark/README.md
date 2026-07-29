# Potts.jl Benchmark Project

This project is the permanent correctness-qualified JuliaGPU benchmark suite. Results use the
versioned schema in `schema.md` and are generated under the ignored `results/` directory.

Set up the base environment:

```sh
julia --project=benchmark benchmark/setup.jl
```

GPU packages live in separate environments under `backends/`. Stack the selected backend environment
ahead of the base benchmark project so only one GPU stack is loaded:

```sh
JULIA_LOAD_PATH="benchmark/backends/metal:benchmark:@stdlib" \
  julia --project=benchmark/backends/metal benchmark/performance_worker.jl \
  --backend=metal --profile=smoke
```

GPU samples synchronize the active KernelAbstractions backend inside the timed region. performance comparison
performance decisions use the lean `benchmark/performance_worker.jl` through `repeat.jl`, or the
`Benchmarks` GitHub workflow. `benchmark/matrix.jl` remains a correctness/qualification diagnostic
and no longer executes the deleted historical engine benchmark. GPU jobs run only on explicitly
enabled, trusted, backend-labeled self-hosted runners.

Launch independent fresh Julia processes with `benchmark/repeat.jl`. One process is diagnostic,
three full processes are the minimum regression evidence, and five full processes qualify a paper
candidate:

```sh
julia --project=benchmark benchmark/repeat.jl \
  --backend=cpu --profile=full --repetitions=3
```

`full` retains the five-family small/medium latency and regression matrix. `throughput` uses the same
scientific families and algorithm compatibility rules on 256² and 64³ lattices so GPU throughput is
not inferred from launch-dominated toy domains. They are separate comparison identities and neither
profile may compensate for a regression in the other. Throughput records use ten independently
synchronized one-MCS samples per workload; the full profile uses five MCS per sample.

performance comparison comparisons consume repeated fresh-process schema `3.0.0` records. The comparator refuses
different hardware, precision, algorithm, model fingerprint, workload shape, or measurement-contract
versions before calculating a performance ratio:

CPU workflow records distinguish `Float32` and `Float64` and accept `1`, `2`, `4`, `8`, or all
physical cores. The Linux runner pins one logical CPU per physical core with `taskset`; the ARM64
Darwin runner records a fixed thread count and its scheduler-managed affinity limitation. GPU
performance qualification remains `Float32` with one Julia host thread.

```sh
julia --project=benchmark benchmark/compare.jl \
  --baseline=baseline-run-1.toml --baseline=baseline-run-2.toml \
  --baseline=baseline-run-3.toml \
  --candidate=candidate-run-1.toml --candidate=candidate-run-2.toml \
  --candidate=candidate-run-3.toml --output=comparison.toml
```

Use `--kind=cold` for algorithm-specific fresh-process records and `--kind=precompile` for
fresh-depot tier-1 records. `warm` is the default.

Smoke diagnostics may explicitly pass `--minimum-processes=1`; such output is not regression or
paper evidence.

Warm regression evidence is collected with the `paired performance comparison` workflow. It checks out
the immutable baseline and candidate separately, then alternates them inside each fresh-process
pair (`baseline/candidate`, `candidate/baseline`, ...). This counterbalances host-frequency and
thermal drift without changing the fixed scientific seed or workload. The resulting process IDs
carry the pair subject, index, and ordinal; only these paired warm records make a release verdict.
Subject-only `Benchmarks` workflow records remain authoritative for the independent cold-start and
offline-precompile tiers.

Both paired subjects execute the workflow revision's single immutable benchmark harness while their
path-pinned projects load the baseline or candidate implementation checkout. Records therefore
retain separate harness and implementation commits and reject either a dirty subject or dirty
harness; analysis-only harness evolution does not make scientific implementation revisions
incomparable.

performance comparison.CPU dispatches that paired workflow independently at `1`, `2`, `4`, `8`, and `physical`
threads where the requested count exists on the runner. A thread-count result is never compared as
if it were the same comparison identity as another count; scaling summaries are derived only after
each fixed-thread baseline/candidate gate has been evaluated independently.

All records in one CPU scaling curve use the same profile and workload matrix. The scaling analyzer
also requires identical final-state checksums, cell counts, and complete last-MCS accounting across
every process and thread count; timing speedup is not reportable when cross-thread replay differs.

Cold latency is measured in independent fresh processes and never inferred from the order-dependent
first workload in a warm matrix. The cold workload uses the same conservative differential-adhesion
model for all four compatible algorithms:

```sh
julia --project=benchmark benchmark/cold_repeat.jl \
  --backend=cpu --repetitions=3
```

Tier-1 precompilation is measured offline in a fresh writable depot stacked over the already
instantiated runner depot. This excludes package downloads while retaining both elapsed time and
the resulting cache size:

```sh
julia --project=benchmark benchmark/precompile_repeat.jl \
  --backend=cpu --repetitions=3
```

Backend-native profiling is a separate workflow because resource evidence is not portable across
GPU families. `profile_metal.jl` captures GPUCompiler device code plus Metal's integrated
chronological host/device trace. `profile_amdgpu.jl` captures GPUCompiler GCN and is run under
`rocprofv3 --hip-trace --hsa-trace --kernel-trace`. Both cover the four scientific algorithms on
the same differential-adhesion fixture and retain unavailable resource fields as unavailable rather
than estimating register pressure from occupancy.

The Metal capture first executes one untimed, synchronized step so KernelAbstractions compiles its
launches through the ordinary execution path. GPUCompiler reflection then captures a second
resident step, followed by the separately timed trace. This keeps compilation priming outside both
the device-code artifact and the warm-profile timing while still requiring nonempty native code for
every algorithm.

Every matrix now writes a versioned `phase10-reference-suite` TOML record in addition to the
historical baselines. That record covers all five mandatory reference families, separates Level 2
host stages from initialization and warm execution, and retains actual proposal accounting,
residency, observation, checkpoint, and direct-CorePotts evidence. `smoke` is the CI gate; `full`
uses paper-scalable problem sizes and longer synchronized samples.

The benchmark and refactor contracts target Julia 1.12.6 exclusively. Older-version compatibility is deferred
until dedicated compatibility CI lanes are established during final release qualification.

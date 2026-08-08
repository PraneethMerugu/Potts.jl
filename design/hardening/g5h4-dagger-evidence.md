# G5H-4 Dagger disposition

Status: measured defer

Date: 2026-08-08

Exact implementation candidate: `901faa546d0b21acca5dd56ecfd42f1ffae8dd64`

Exact tree: `e935bf919e59c86baa3f23a394d1eb06d497bc61`

This record answers only whether Dagger should become part of PottsToolkit's trajectory-execution
authority. It does not qualify a new public backend or change the semantics of a Potts trajectory.

## Decision

Dagger is deferred as a package integration. SciML's `EnsembleProblem` plus
`EnsembleSerial`, `EnsembleThreads`, and `EnsembleDistributed` remain the sole whole-trajectory
ensemble interface. Dagger may still be used by applications outside PottsToolkit to schedule
coarse independent work, but it does not own MCS ordering, coupled-component visibility,
lifecycle publication, RNG identity, retry identity, or checkpoint meaning.

The decision is based on semantic fit as well as timing. PottsToolkit already supplies a real
SciML ensemble problem with deterministic `replica`/`repeat` addressing and SciML callback,
reduction, and failure behavior. An internal Dagger layer would duplicate scheduler authority and
would require a second serialization, cancellation, error, and checkpoint contract without adding
a capability unavailable through the admitted SciML lanes.

## Reproduction environment

- Apple Mac target, Julia 1.12.1, four Julia threads
- Dagger 0.21.0
- isolated environment: `benchmark/dagger/Project.toml` and `benchmark/dagger/Manifest.toml`
- fixture: eight independent 48 x 48 periodic CPM trajectories, 20 MCS each, `Float32`, one
  addressed replica per trajectory
- warmup: two trajectories through each of serial SciML, threaded SciML, and Dagger task paths
- sample: one post-warmup `@timed` execution per path, including scheduler and solution retention
- correctness guard: every final ownership array must agree for the same replica across all paths

Command:

```sh
/Applications/Julia-1.12.app/Contents/Resources/julia/bin/julia \
  --project=benchmark/dagger --startup-file=no --threads=4 \
  benchmark/dagger/ensemble_comparison.jl
```

## Measurement

| Path | Seconds | Allocated bytes | GC seconds | Speedup over serial |
|:--|--:|--:|--:|--:|
| SciML `EnsembleSerial` | 2.744703 | 466,691,904 | 0.038345 | 1.000x |
| SciML `EnsembleThreads` | 0.699338 | 469,383,888 | 0.021707 | 3.925x |
| Dagger tasks | 1.013743 | 467,354,144 | 0.021304 | 2.707x |

All final ownership arrays agreed exactly. On this representative independent-trajectory workload,
Dagger was 45.0% slower than the existing threaded SciML lane (`1.013743 / 0.699338`). The single
sample is a disposition measurement, not a general performance claim about Dagger.

## Claim boundary

This result does not reject Dagger for user-owned workflows and does not compare distributed
clusters, heterogeneous accelerators, or task graphs with meaningful dependencies. Such use cases
can compose around PottsToolkit's standard SciML problems and solutions without an extension.
Reconsidering an internal extension requires a concrete workload where Dagger supplies a measured
capability that SciML/stdlib execution does not, while preserving the existing ensemble identities
and failure/checkpoint contract exactly.

# Benchmark Result Schemas

## performance comparison performance schema

Schema version: `3.0.0`

Each `phase12-performance-run` record represents one fresh process. Three independent full records
per baseline or candidate are required for an engineering regression decision, and five are required
for a paper candidate. Samples within one process remain nested in that process and are not treated
as independent process repetitions.

The `full` profile is the required five-family latency/regression matrix. The separate `throughput`
profile uses 256² and 64³ realized domains to exercise publication-scale parallel work. Profile is a
comparison-identity field: latency and throughput results are never pooled or used to compensate for
one another. Each throughput process records ten independently synchronized one-MCS samples per
workload; large-domain work is not multiplied by the full profile's five-MCS sampling block.

Before comparing numbers, the comparator requires equality of the benchmark-contract and workload-set
versions, backend, authoritative hardware identity, Julia version, architecture, operating system,
Julia thread count, precision, profile, tuning policy, workload inventory, algorithm, semantic model
fingerprint, dimension, shape, and site count. A mismatch produces `INCOMPARABLE`, not a ratio.
CPU artifacts additionally record the affinity policy. Linux headline and scaling runs bind one
logical CPU from each selected physical core; Darwin fixes the physical-core count but labels the
configuration scheduler-managed because macOS exposes no supported process-affinity contract.

The warm comparison independently gates steady MCS time, backend-resident memory, and warm residency
counters. Its per-workload `first_mcs_seconds` is explicitly an order-dependent diagnostic and is not
a cold gate. Fresh-depot `phase12-precompile-run` records measure offline base/backend precompilation
and resulting cache bytes. Fresh-process `phase12-cold-run` records independently gate backend import, package
import, authoring stages, initialization, and first synchronized MCS for each algorithm. A faster
steady result cannot compensate for a failed cold, memory,
allocation, transfer, or synchronization gate. Each scientific algorithm has its own steady-time
geometric mean evaluated in ratio space; scientifically different algorithms never share an
unlabeled mean. Every algorithm mean must not regress. The default per-workload regression and memory
threshold is 5%.

Implementation provenance is distinct from harness provenance. Benchmark-only changes may improve
measurement without pretending that the scientific implementation changed. Historical schema
`2.1.0` remains readable evidence and is never rewritten as schema `3.0.0`.

Backend-native `phase12-backend-profile` records use their own `1.0.0` evidence schema. They retain
the synchronized differential-adhesion workload identity, implementation provenance, backend
package version, per-algorithm GPUCompiler device-code inventory, native-code byte counts, and only
the resource metadata present in the backend's authoritative output. Metal records its integrated
chronological GPU trace; ROCm records a `rocprofv3` HIP/HSA/kernel Perfetto trace and GCN metadata.
An absent metric remains explicitly unavailable: register counts are never inferred from occupancy.

The warm and cold harness identities hash measurement code, not dependency lockfiles. Exact
benchmark `Project.toml` and `Manifest.toml` contents are retained separately as
`benchmark_environment_sha256` provenance. This permits a dependency or precompilation optimization
to be measured as part of the candidate implementation without pretending that the timing procedure
changed; reviewers can still detect and audit every environment difference.

## Reference-suite schema

Schema version: `2.1.0`

Each `phase10-reference-suite` TOML record is a self-contained artifact containing:

- exact source, Julia, operating-system, architecture, thread, backend, device, and pinned
  KernelIntrinsics provenance;
- CPU/Metal/ROCm qualification for the Level 2 replacement slice and every mandatory reference
  workload;
- separate reusable-model construction and normalization, problem-field binding, bound-model
  normalization, lowering, problem construction, initialization, first-MCS, and synchronized
  warm-MCS timings;
- raw and summary MCS/s samples plus actual scheduler, activated-attempt, realized-proposal, and
  accepted-copy throughput from `ScientificMCSReport`;
- host allocations, device allocations, launches, transfers, engine synchronization, explicit
  observation cost, scientific-state bytes, adapted component-array bytes, lifecycle workspace
  bytes, and total backend-resident bytes;
- the matched direct-CorePotts comparison and canonical checkpoint capture/restore measurements;
- explicit kernel-resource status. Kernel compilation and rejection of dynamic device invocation
  are required by the reference-suite contract. Numeric register counts are deliberately not fabricated: current
  KernelAbstractions has no portable register-count interface, so backend-native register/spill and
  occupancy profiling belongs to performance comparison.

Smoke records are CI qualification evidence. Full records use paper-scalable configurations and
more samples, but they are not publication claims until hardware, environment, repetition count,
and regression budgets are frozen. GPU samples always synchronize the active backend inside the
timed region. Diagnostic report and snapshot observations are measured separately from warm
execution. A lifecycle capacity-failure observation is part of the monolayer step itself, so its
declared synchronization and GPU transfer remain inside the timed region and are reported rather
than hidden.

Version `2.1.0` adds an explicit problem-binding stage to every reference workload. Workloads with
reusable `Field` declarations record distinct reusable and problem-bound semantic fingerprints;
workloads without problem-owned bindings use an identity stage and must retain the same fingerprint.
This keeps prescribed field values in the problem while allowing lowering performance to be measured
against the exact realized model that enters execution.

## Historical pre-refactor baseline schema

Schema version: `1.0.0`

Each TOML record contains:

- Exact Git commit, dirty-tree flag, implementation checksum, and derived baseline ID
- Julia, OS, architecture, thread, backend, and device information
- Workload dimensions, class, initial cells, and logical initial-state checksum
- Legacy algorithm type and proposal-budget controls
- Initial and final state invariants and checksums
- Workload construction, backend adaptation, initialization, first-MCS, and steady-state timing
- Raw synchronized samples and summary statistics
- Host allocation observations reported by BenchmarkTools
- Known measurement limitations

The schema deliberately labels expected attempts rather than actual attempts because the current
engine exposes no proposal/acceptance counters. Future instrumentation may add launches,
synchronizations, transfers, device allocation, actual proposals, acceptances, conflicts, and scratch
memory without silently changing the meaning of existing fields.

Changing the meaning or units of a field requires a schema-version change. Adding an optional field
requires documenting the version in which it first appears.

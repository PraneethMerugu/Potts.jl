# ProcessBigraphs Phase 14.PB0 Implementation and Closure Audit

Status: PB0 bounded foundation passed; Phase 15 internal alpha remains open

Date: 2026-07-26

## Scope

This audit evaluates only Phase 14.PB0 in the development roadmap. It does not
claim full Process-Bigraph parity, internal alpha, dynamic hierarchy, a
CorePotts adapter, device execution, or public-release readiness.

The implementation is an independently valid Julia 1.12.6 package at
`lib/ProcessBigraphs/`, with UUID
`efcc6515-205e-41e3-b553-f38f05ad529c`. Its runtime dependency set contains
only the Julia `SHA` standard library. Aqua and Test are package test extras.
There is no CorePotts or PottsToolkit dependency.

## Deliverable audit

| PB0 deliverable | Evidence | Result |
|---|---|---|
| Exact authority pins and package-local registry | `lib/ProcessBigraphs/parity-registry.toml` | Passed |
| Independent project, source, tests, compatibility, and internal docs | `lib/ProcessBigraphs/Project.toml`, `src/`, `test/`, `docs/src/internal.md` | Passed |
| Canonical typed paths | `src/paths.jl`, path tests | Passed |
| Exact normalized integer time | `src/time.jl`, time tests | Passed |
| Structural schemas and hierarchical snapshot projections | `src/schemas.jl`, `src/store.jl`, schema/store tests | Passed |
| Typed ports and static validation | `src/declarations.jl`, `src/composites.jl`, composite tests | Passed |
| Typed deltas and small update algebra | `src/effects.jl`, reconciliation tests | Passed |
| Canonical encoding | `src/canonical.jl`, order/fingerprint tests | Passed as encoding foundation |
| Capability/residency and hidden-transfer preflight | `src/capabilities.jl`, device-boundary declaration tests | Passed as declaration foundation |
| Non-Potts serial microfixtures | `src/runtime.jl`, `test_serial_microfixtures.jl` | Passed in bounded PB0 scope |
| Settled checkpoint/replay foundation | `src/checkpoint.jl`, replay test | Passed in-memory; persisted codec remains open |
| Honest status and limitations | package registry and PB0 evidence | Passed |
| No package-local manifest | `.gitignore`, PB0 checker | Passed |

## Semantic results

The bounded serial runner demonstrates:

- imminent-event selection for interval-one and interval-two processes;
- one immutable same-time snapshot independent of declaration order;
- deterministic delta sorting and atomic reconciliation;
- actual elapsed duration for a forced final partial interval;
- rejection of unsupported partial completion before the call mutates state;
- distinct temporal Process declarations and zero-time Step DAG layers;
- fork/join layer visibility and cycle rejection;
- no process-batch publication when one invocation fails; and
- exact in-memory replay from a settled checkpoint in the same package/backend.

The runner intentionally supports fixed schedules and static composition only.
It exists so PB0 primitives are executable together; it is not evidence that
the Phase 15 serial executor or internal-alpha gate has closed.

## Qualification result

Julia 1.12.6 package qualification passed:

- 77 PB0 unit and semantic microfixture checks;
- 10 Aqua package-quality checks; and
- package precompilation without method-overwrite warnings.

The environment could not refresh the public package registry. Tests used
already installed exact dependencies through a read-only fallback depot; this
did not weaken package execution or assertions. The generated package-local
manifest was removed after testing, as required for an independent library.

Machine-readable results are in
`design/evidence/process-bigraph-pb0-evidence-v1.toml`.

## Unimplemented boundaries

PB0 does not implement or qualify:

- wildcard paths, nested composites, executable bridges, or separate
  place/link topology;
- adaptive deadlines, explicit iteration, reactive quiescence, semantic RNG,
  observers, or structural transactions;
- canonical persisted checkpoint decoding/migration;
- transfer execution or measurement, GPU kernels, Threads, or Dagger;
- pinned upstream Python differential oracles;
- scientific adapters, whole-cell fixtures, or a CorePotts adapter; or
- any public package release.

Those omissions are later-phase work and are not silently represented as
passing.

## Root integration requests

The integration owner should make shared-file changes outside this agent's
ownership:

1. add a root CI lane that runs the independent package suite and
   `scripts/process-bigraph-pb0-check.jl`;
2. update shared parity-registry rows from `specified` to `implemented` only
   where the machine-readable PB0 evidence marks `implemented_direct_rows`;
3. keep partial rows below `oracle_passing`, and keep every pinned upstream
   oracle `not_started`;
4. link this audit/evidence from the shared conformance index and roadmap
   status; and
5. do not add ProcessBigraphs to root Potts package dependencies during PB0.

## Decision

Phase 14.PB0 passes its bounded foundation gate. The package is independently
loadable and testable, its domain-neutral primitives execute together, and its
claims do not exceed direct evidence. Phase 15 internal alpha remains open.

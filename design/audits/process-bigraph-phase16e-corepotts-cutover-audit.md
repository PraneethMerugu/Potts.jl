# ProcessBigraphs Phase 16.E CorePotts Cutover Audit

Date: 2026-07-27

Status: qualified

## Claim

The first CorePotts strangler slice is cut over. ProcessBigraphs owns the native-field logical
clock, invocation reason and identity, immutable forcing projection, resource authorization,
candidate validation, publication boundary, fail-stop state, and checkpoint authorization.
CorePotts retains its optimized native arrays, execution plan, kernels, synchronization, staging
buffers, and constant-time publication swap. The adapter returns an opaque candidate token rather
than exposing a future-state array.

The existing direct native-field advance remains an internal kernel convenience and frozen
differential oracle; it is not exported and is not a second scheduler. The managed cutover has no
fallback switch, catch-and-run-old-path branch, or dual publication authority.

## Typed domain structure without per-cell ACSet rows

The solver-neutral `DomainStructuralIdentity` and `DomainStructuralRequest` envelope carries a
domain namespace, typed identity and generation, source epoch, bounded stable operation, logical
payload, dependencies, and priority. ProcessBigraphs performs order-independent dependency,
conflict, and capacity selection. The CorePotts helper lowers cell IDs and generations into this
envelope but cannot allocate identities or publish topology.

This preserves the accepted split: the ProcessBigraph ACSet is orchestration topology, while
CorePotts cells, sites, and relationships remain optimized domain topology.

## V3 logical checkpoint and conversion

The V3 checkpoint is captured only from a settled serial runtime and settled managed engines. It
contains the V2 runtime payload, reconstructible orchestration topology, structural epoch,
identities, generations, lineage, capacities, managed-engine declaration and logical state,
identity maps, per-component checksums, and weakest replay class. Structural restore is
prototype-free. Schema, component, topology, declaration, payload-byte, and envelope integrity
failures are validated before a destination is mutated.

CorePotts canonical and coupled checkpoint converters validate their existing checksums first,
normalize logical content into versioned V3 components, fingerprint the source before and after
conversion, and reject source mutation. The old canonical, coupled, HDF5, and Zarr readers remain
present and pass the complete CorePotts package suite.

## Differential and failure evidence

The frozen direct native-field oracle and managed path produce exactly equal Float64 state,
native time, and publication epochs over four scheduled forcing intervals. Restart at cuts 0, 1,
2, and 3 produces the same remaining trajectory. Runtime authorization rejection and native
candidate failure leave published state, logical time, forcing, and publication epoch unchanged;
the managed runtime enters explicit fail-stop state and cannot silently retry.

The focused suites pass 42 ProcessBigraphs and 45 CorePotts assertions. Clean package environments
pass ProcessBigraphs 1,061/1,061 and CorePotts 3,772/3,772 assertions. The repository dependency
guard and all prior Phase 16 checkers remain green.

Phase 16.C remains independently open for trusted exact-head Metal and ROCm artifacts. Phase 16.F
solver plurality and both bounded model assemblies also remain open; no E evidence substitutes for
those gates.

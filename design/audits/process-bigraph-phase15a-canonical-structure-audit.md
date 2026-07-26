# ProcessBigraphs Phase 15.A Canonical-Structure Audit

Status: Phase 15.A passed

Date: 2026-07-26

Scope: bounded canonical-structure migration only; complete Phase 15 internal alpha remains open

## Result

Phase 15.A replaces PB0's provisional structural authority without changing its established
runtime behavior. The package now has one Canonical ProcessBigraph ACSet, one validation and
normalization path for ordinary typed and direct ACSet authoring, and one compiled runtime
boundary. The exact PB0 model fingerprint, initial snapshot fingerprint, final snapshot
fingerprint, materialized state, and event trace remain frozen and passing.

The closure implements exactly two parity-registry rows:

- `canonical-process-bigraph-acset`
- `compiled-structural-epoch`

No `oracle_passing`, `qualified`, complete-internal-alpha, device, parallel-executor, adapter, or
public-release claim follows from this result.

## Canonical ProcessBigraph ACSet

`lib/ProcessBigraphs/src/algebraic_structure.jl` defines schema version `1.0.0` over composites,
store nodes and containment, actors, processes, steps, ports, bindings, and step dependencies.
Every semantic entity has a stable string identity. Store paths and schema payloads are carried
without treating ACSet row numbers as identity.

`lib/ProcessBigraphs/src/lowering.jl` provides both authoring paths:

- `StaticComposite` remains the ordinary ergonomic façade and lowers into the ACSet.
- Direct `ProcessBigraphACSet` authoring supplies runtime law and continuation payloads and enters
  the same `CanonicalModel` validator.

Both paths reconstruct one normalized semantic composite, validate identity and relational
integrity, and compile through the same function. Equivalent declaration order and true ACSet row
renumbering preserve the structural fingerprint, runtime model fingerprint, provenance, and
execution trace. The public API does not expose the test-only insertion-order control.

Phase 15.A deliberately admits one static root composite. It rejects nested composite structure
rather than assigning premature semantics before structured-cospan composition is implemented.

## Compiled structural epoch

Compilation creates a `StructuralEpoch` containing a private canonical structural copy and an
`ExecutionPlan` containing deterministic process and step entries, layer indices, resolved input
and output routes, and exact stable-ID-to-index provenance. Public structure access returns
detached copies, and post-compilation mutation of an authoring ACSet cannot change the compiled
model or trace.

`CompiledComposite` no longer contains a `StaticComposite` declaration. The runtime and checkpoint
implementations consume indexed plan entries and contain no ACSets reference, canonical-structure
lookup, or authoring-façade traversal. This is the Phase 15.A evidence for the no-structural-
traversal boundary. It is not a claim that all runtime work allocates zero bytes.

## Dependency and package boundary

`ProcessBigraphs` version `0.2.0` directly depends on:

- `ACSets` 0.2.29
- `Catlab` 0.17.6
- Julia standard-library `SHA`

The package still has no dependency on CorePotts or PottsToolkit. `AlgebraicRewriting` and
`AlgebraicDynamics` are absent because their accepted roles begin in Phases 16 and 17.

## Executable evidence

The package suite contains 116 passing ProcessBigraphs tests and 10 passing Aqua checks. The
Phase 15.A cases prove:

- schema shape and canonical entity counts;
- typed-to-ACSet and direct-ACSet compilation equivalence;
- actual row renumbering and declaration-order invariance;
- structural, runtime-fingerprint, provenance, and trace invariance;
- exact compiled routes and structural provenance;
- absence of `StaticComposite` and ACSet data from the execution-plan type boundary;
- fail-closed invalid semantic-law metadata;
- mutation isolation before and after compilation; and
- unchanged exact PB0 fingerprints, state, event count, failure atomicity, and settled replay.

The dedicated `scripts/process-bigraph-phase15a-check.jl` binds dependency versions, source
topology, tests, registries, this audit, and the machine-readable evidence record. The broader
`scripts/check_process_bigraph_platform.jl` preserves the source-pin, authority, package-boundary,
and no-upstream-Python policies.

## Requirement disposition

| Phase 15 structural requirement | Disposition |
| --- | --- |
| ACSets and Catlab direct dependencies with bounded compatibility | Passed |
| One versioned canonical ACSet | Passed |
| Ordinary typed façade lowers to canonical ACSet | Passed |
| Direct ACSet authoring enters the same semantic validator | Passed |
| Row numbers and declaration order are nonsemantic | Passed |
| Immutable structural epoch and indexed execution plan | Passed |
| Exact provenance from semantic IDs to compiled indices | Passed |
| Runtime/checkpoint do not traverse authoring structure | Passed |
| PB0 fingerprints and traces preserved | Passed |
| Structured-cospan open composition | Not in Phase 15.A |
| Derived directed wiring view | Not in Phase 15.A |
| Independent Julia specification oracle | Not in Phase 15.A |
| Complete internal-alpha fixture matrix | Not in Phase 15.A |

## Remaining Phase 15 work

The complete Phase 15 internal-alpha gate still requires structured-cospan open composition,
derived directed wiring diagrams, nested/open composite fixtures and parenthesization invariance,
the independent checked Julia specification oracle, semantic RNG and observer contracts, and the
remaining multirate biochemical, update-law, failure-injection, and checkpoint/replay evidence.
Those capabilities must extend the canonical structure and compiled-plan boundary established here;
they must not restore a parallel structural model or make runtime semantics depend on ACSet storage
order.

Phase 16 remains responsible for AlgebraicRewriting-backed dynamic topology and the first Potts
adapter cutover. Phase 17 remains responsible for AlgebraicDynamics/scientific adapters. Later
device and Dagger qualification cannot redefine the serial semantic authority.

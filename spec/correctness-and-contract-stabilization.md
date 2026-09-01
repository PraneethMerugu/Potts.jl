# Correctness and contract stabilization

Status: Accepted

## Purpose

This decision aligns current public documentation, examples, live package
environments, and ordinary tests with the sole production authorities after
the LocalMath cutover. It does not rewrite historical evidence or add a second
qualification process.

## Current claims

- Functional execution, exact replay, checkpoint portability, deterministic
  conflict resolution, and performance are separate guarantees.
- Native ODE and DAE execution may be functionally supported without sharing
  checkpoint eligibility. The current serial DAE row is functional only.
- The hosted workflow has no Apple Metal executor. The repository's real-Metal
  runner is the authority for hardware-tested Metal semantics and must include
  every active, non-performance Metal witness.
- CUDA, ROCm, and AMDGPU are not current public PottsToolkit backends. Retained
  development environments do not create a support guarantee.
- Exported names and unexported `public` names are distinct inventories.
  Documentation and tests must classify each set with the corresponding Julia
  reflection operation.
- Public help must be attached to the documented binding and must state a real
  accepted signature. Help presence alone is insufficient.

## Scientific and execution contracts

The sole semantic RNG contract for current compiled programs is
`Philox4x32x10V2`. Its counter/key layout includes the complete bounded V2
address—contract stream, MCS, operation, entity, draw, replica, and repeat—so
trajectory and rerun identities cannot alias ordinary draws. Integer-to-real
uniform conversion uses the documented open interval where a transform cannot
admit zero; endpoint behavior is tested with known-answer vectors. A new
layout requires a new durable RNG contract type, not a compatibility branch.

The packed proposal address assigns 32 bits to the entity, 12 to the operation,
4 to the stream, 3 to the entity kind, and 10 to the draw. MCS, subround, and
bounded-rejection invocation occupy the other counter word; generation is
domain-separated into the Philox key. Trajectory keys are derived by applying
Philox to the complete `(seed, replica, repeat)` tuple with a fixed domain tag.
This is a deterministic derivation contract, not a claim of mathematical
injectivity. `Float32` and `Float64` open uniforms use the midpoints of the
23-bit and 52-bit grids respectively, and therefore exclude both endpoints.

Descriptor state is part of the logical program state. A failed lifecycle or
relationship transaction publishes neither ownership/tracker changes nor any
descriptor-state bank. Successful publication is one semantic atomic commit,
including checkpoint-visible state.

Relationship create/remove/retune requests use generation-qualified endpoint
identity and exact payload equality. Repeating an already-applied request is
idempotent only when its complete relationship identity and payload match;
payload disagreement is a conflict, not a successful duplicate.

Backend admission names the exact executable mechanism. A provider being able
to allocate or launch a kernel does not admit a checkerboard, lifecycle,
relationship, native-solve, collection, or fold mechanism that lacks its own
ordinary conformance witness. CPU and GPU remain lowerings of the same
KernelAbstractions semantic path.

For compacted collections, `count(collection)` is the number of selected live
records, not an occupied-key extent. Grouped consumers iterate the declared
key space or an explicit dense occupied-key mapping. A selected source-position
lane identifies the producer position for that exact emitted lane; planning
rejects an absent projection or a lane beyond the producer's static width.

`Space` products and `ProductRelation` are public mathematical declarations.
Their mixed-radix ordering, extent, factor order, and bounds are semantic;
prepared storage views and workspace slots remain private physical details.

Inspection and compilation reports normalize names, ordering, and lifecycle
facts from production authorities. A prepared compilation report exposes
prepared launch types, selected callback `Method` records, parameter layout,
dependency arity, and provider/device facts. It does not promise
`MethodInstance`s, a kernel argument ABI, predicted timing, or a second
compiler representation.

`CorePotts.CompilerSPI` is the complete downstream compiler boundary. Every
PottsToolkit lowering needed by a real consumer must use its public handles,
layouts, descriptors, evaluator/context contracts, lifecycle plans, and report
accessors. Reaching through CorePotts private fields is not a supported
completion shortcut.

## Cutover boundary

This stabilization is a direct cutover. Retired RNG layouts, descriptor or
relationship commit paths, backend selectors, LocalWorksets-era spellings,
private downstream accesses, and obsolete notebook APIs receive no aliases,
deprecations, feature flags, or dual representations. Historical records may
describe them but current source, tests, examples, docs, and environments do
not execute them.

## Environment integrity

Every live checked-in environment that records a local path package must agree
with that package's current `Project.toml` name, UUID, version, and direct
dependency names. A matching top-level manifest `project_hash` is insufficient
because it does not validate transitive path-package metadata.

The root package-quality suite checks this closure for current environments.
Exact replay retains its pinned Julia and dependency graph because the stronger
claim depends on them. Historical environments under `design/` remain frozen
records and are excluded from current-environment checks.

## Executable surfaces

Current examples must load and execute against current public interfaces.
Obsolete notebooks are replaced by bounded Julia programs rather than retained
as apparently runnable examples. Documentation examples that present an API
inventory or signature must execute that exact distinction or call.

Test runners own explicit inventories and verify that ordinary test files are
included. Standalone hardware-performance measurements remain separate from
semantic runners.

## Ordinary validation matrix

Validation uses normal Julia workflows: LocalMath, CorePotts, PottsToolkit,
and MakiePotts package suites; root path-manifest and runner inventories;
cross-package integration families; exact replay under its pinned environment;
strict Documenter doctests/examples/export checks; bounded current examples;
platform installation smokes; and the real-Metal semantic runner when Apple
GPU hardware is available. Focused CPU/GPU parity and reproducible benchmarks
support the mechanism or performance claims they directly exercise. There are
no milestone gates, evidence hashes, or substitute policy scripts.

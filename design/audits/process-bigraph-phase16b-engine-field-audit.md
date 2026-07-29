# ProcessBigraphs Phase 16.B Engine and Field Protocol Audit

Status: Qualified

Date: 2026-07-27

Authority: Decision 0039 and the Phase 16 normative specification

## Scope

Phase 16.B implements the solver-neutral boundary shared by native, SciML, and independently
authored engines. It does not implement or qualify a production numerical solver.

The implementation separates:

- immutable, fingerprinted engine declarations from lineage-owned mutable instances;
- exact logical operations from solver-selected internal steps;
- encoded immutable input projections from engine-owned candidate memory;
- staging and asynchronous completion from runtime validation, authorization, and publication;
- typed successful candidates, early returns, global-impact event requests, and failures; and
- canonical typed continuations from reconstructible caches and opaque solver workspaces.

The field contract covers Cartesian 2D/3D cell-centered geometry, named species and units, every
low/high face, periodic/Dirichlet/Neumann/mixed boundaries, physical-coordinate sampling and
deposition, conservative exchange accounting, exact field clocks, named split operations, and
explicit bounded algebraic-feedback regions.

## Ownership checks

`execute_engine!` owns the outer transaction:

`stage -> complete -> validate -> authorize -> publish`

Any failure before successful publication invokes candidate discard. The adapter owns the heavy
stage and completion work. Successful interval candidates must reach the exact authorized target;
early returns and global-impact events are typed and remain unpublished. Resource authorization is
checked against the declaration's backend, precision, and residency envelope before staging.

Published logical field state and engine inputs do not share mutable arrays with callers. Engine
candidate payloads remain opaque. The test adapter publishes by pointer swap with zero measured
publication allocation after warm-up.

## Direct evidence

The Phase 16.B microfixtures cover:

- a third-party test adapter implemented only with the solver-neutral dispatch points;
- successful, unauthorized, invalid-time, structured-failure, stage-failure, completion-failure,
  publication-failure, and secondary-discard-failure paths;
- exact target and typed early/event return behavior;
- immutable encoded projections and capability rejection;
- typed continuation encode/decode, invalidation actions, replay aggregation, and every restart cut
  in a three-operation bounded trajectory;
- periodic and nonperiodic field boundaries, nearest/linear sampling, functional deposition,
  multi-consumer insufficiency, positivity, conservation, and accounting;
- named field splitting, exact clocks, undeclared-loop rejection, and explicit bounded feedback.

## Limits

- Native diffusion/reaction kernels and analytic PDE refinement evidence are Phase 16.C.
- Stable public export of the engine protocol remains gated until the native and independent custom
  CPU adapters pass the same protocol in Phase 16.F.
- Dynamic structural requests are Phase 16.D.
- SciML objects, CorePotts topology, device buffers, and solver caches remain outside the core API.
- No GPU, model-assembly, internal-beta, or public-release claim is made.

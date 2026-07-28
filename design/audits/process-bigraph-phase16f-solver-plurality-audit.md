# ProcessBigraphs Phase 16.F Solver Plurality Audit

Date: 2026-07-27

Status: qualified

Implementation commit: `9f9daf19e34c5430361cb98c8002f025a74d217a`

Implementation tree: `e371867f85c0dd646dc77ba781bd2a746fd4b097`

## Claim

Phase 16.F qualifies one bounded CPU SciML field adapter, one deliberately independent
external-style CPU custom adapter, and native/SciML/custom comparison evidence for the periodic
Cartesian diffusion-decay envelope. This is a per-envelope claim, not universal solver or solver
GPU support.

The consolidation repair is complete. ProcessBigraphs does not define a numerical method for a
SciML problem and does not return a home-grown SciML solution. The extension receives an explicit
`Tsit5()` algorithm and canonical options, constructs a real `SciMLBase.ODEProblem`, initializes
the solver through `CommonSolve.init`, advances to the authorized target through
`CommonSolve.step!(integrator, duration, true)`, and interprets completion through
`SciMLBase.check_error` and `SciMLBase.successful_retcode`.

## Ownership and continuation

ProcessBigraphs still owns the exact logical interval, immutable forcing projection, resource
authorization, validation, publication, failure, checkpoint, and replay classification.
OrdinaryDiffEq owns adaptive internal steps, error control, stages, and caches.

Each invocation reconstructs a fresh problem and integrator from the last published canonical
field state. Solver work occurs on copied candidate arrays. The checkpoint stores only canonical
field state, forcing, logical time, publication epoch, declaration fingerprint, and the
`reconstruct_each_invocation` policy. The declared replay class is numerical. No live integrator,
cache, `deepcopy`, or Julia-serialization continuation is claimed.

## Independent custom proof

The custom adapter is no longer production code in `src/`. It lives in
`lib/ProcessBigraphs/test/fixtures/independent_custom_field_adapter.jl`, imports only
ProcessBigraphs, and implements classical RK4 with its own periodic stencil and transaction
methods. It imports no SciML package and shares no numerical stepping helper with the SciML
extension.

The production core replacement is the 102-line solver-neutral
`BoundedCartesianFieldProblem`. Algorithm choices and substeps were removed from the problem
description.

## Scientific and failure evidence

The focused ProcessBigraphs suite passes 88 assertions:

- explicit algorithm, package UUID/version, normalized option, and fingerprint evidence;
- rejection of implicit algorithm selection and undeclared callback options;
- exact-target and standard return-code paths;
- analytic constant-decay accuracy with tighter tolerances reducing error;
- fourth-order custom refinement with each halving reducing error by more than eightfold;
- a positive periodic Fourier manufactured solution against the semi-discrete analytic solution;
- authorization rejection and invalid-candidate rollback;
- numerical V3 checkpoint classification; and
- restart at cuts 0, 1, 2, and 3 for both adapters.

The focused CorePotts suite passes 14 assertions for Float64 2D and Float32 3D. Native explicit
Euler, adaptive `Tsit5`, and independent RK4 advance the same scheduled problem. Each is compared
to the manufactured solution; the solver and custom paths satisfy their declared tolerances, and
all three agree on logical time and publication version.

Clean package-test environments pass ProcessBigraphs 1,150/1,150 and CorePotts 3,786/3,786
assertions, including Aqua and all prior Phase 16 tests.

## API and dependency boundary

`OrdinaryDiffEqTsit5` is a test-only dependency in both packages. ProcessBigraphs production
dependencies remain ACSets, AlgebraicRewriting, Catlab, and SHA; SciMLBase and CommonSolve remain
weak extension triggers. The admitted public surface is the bounded engine/field adapter-author
protocol and the qualified SciML declaration constructors. Concrete instances, integrators,
candidates, caches, custom fixture types, and structural implementation details remain internal.

## Open work

Phase 16.C remains open for trusted exact-head Metal and ROCm artifacts. Phase 16.G and 16.H may
now begin. Internal beta, complete reconciliation, and public release remain open.

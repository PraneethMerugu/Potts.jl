# Sequential Reference Engine

Semantic status: Accepted

Implementation maturity: Reference implemented for the Phase 4 vertical slice

## Purpose

CorePotts MUST provide a small ordinary Julia sequential engine that is the executable definition of
the conventional cellular Potts transition law. Its priority is inspectable correctness. It is an
oracle for optimized CPU and GPU engines, not a performance claim or a fallback that silently runs
when a requested backend is unsupported.

## Phase 4 Reference Model

The first required vertical slice is deliberately narrow:

- a two-dimensional Cartesian lattice;
- one conceptual medium domain and finite cells;
- periodic von Neumann copy-proposal neighbors;
- quadratic volume energy and symmetric unordered contact energy;
- uniform recipient-site and neighbor-direction selection;
- conventional modified Metropolis acceptance;
- exactly `N = length(lattice)` candidate attempts per MCS;
- deterministic semantically addressed random draws;
- immediate volume reconstruction and validation after accepted copies;
- valid extinction with slot reuse deferred until the next integer-MCS boundary; and
- observation of the logical state and an attempt-accounting report after each MCS.

Additional dimensions, relations, components, algorithms, and optimized storage are later vertical
slices. Their absence does not weaken the definitions they already have elsewhere in this
specification.

## One Candidate Attempt

For candidate-attempt index `a` in MCS `m`, the engine MUST:

1. derive the recipient, neighbor direction, and acceptance draw from distinct semantic RNG
   addresses containing the master seed, algorithm identity, `m`, `a`, and draw role;
2. select one recipient uniformly from all `N` sites and one direction uniformly from the canonical
   proposal relation;
3. count an invalid-boundary or same-owner selection as a no-op candidate attempt;
4. construct a complete immutable copy proposal for a different-owner selection;
5. evaluate hard constraints against the pre-attempt state;
6. sum conservative local energy changes and nonconservative log biases separately;
7. apply the named conventional modified Metropolis law at the configured temperature; and
8. atomically commit an accepted copy, its derived-volume update, and any extinction retirement.

Rejected and no-op attempts still consume their addressed draw roles. Control-flow differences MUST
NOT shift the addresses of later attempts.

## MCS Boundary

`step!` or its functional equivalent always advances exactly one integer MCS. It MUST report at
least candidate attempts, no-op attempts, constraint rejections, energy rejections, accepted copies,
and retired cells. These counts MUST partition the `N` candidate attempts.

Slots retired during MCS `m` become reusable only at the boundary before MCS `m + 1`. Lifecycle
events scheduled for an integer MCS execute at their specified boundary, outside the candidate-copy
transaction sequence, and receive their own semantic RNG address domain.

## Reference Correctness

The engine MUST validate logical state invariants at construction and at each completed MCS in its
checked mode. Component local deltas MUST be testable against complete Hamiltonian recomputation.
The same seed, model, initial logical state, algorithm contract version, and Julia 1.12.6 reference
environment MUST reproduce the same candidate addresses and canonical logical snapshots.

Optimized algorithms need not reproduce the sequential trajectory unless their named guarantee says
so. They MUST satisfy their declared exact, deterministic, numerical, or statistical conformance
class against this engine and the literature-specific tests.

## Phase 4 Exit Evidence

Phase 4 closes when this slice:

1. runs through public CorePotts logical-state and scientific protocols;
2. passes deterministic replay, attempt accounting, energy-delta, extinction, invariant, and
   observation tests;
3. is constructible from one public Potts volume-plus-contact model spelling; and
4. has type inference and allocation behavior measured and recorded without claiming production
   performance.

Migration of historical optimized kernels to compiled state, GPU device qualification, zero-sync
steady-state execution, and performance comparison belong to subsequent execution and component
phases.

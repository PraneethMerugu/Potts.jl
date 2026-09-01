# LM-1 C3 CorePotts checkerboard boundary

## Disposition

The checkerboard proposal, claim, acceptance, and accepted relationship
recurrence remain CorePotts scientific authorities and execute through one
KernelAbstractions CPU/GPU path. Their deleted LocalWorksets wrappers and
execution selectors are not retained. This is a direct ownership cut, not a
compatibility state.

Proposal adoption is blocked only by the explicit LM-6 compiler dependency:
CorePotts `ResourceAccess` descriptors and affected-footprint proofs must lower
to typed `Field`/`Relation` accesses and a bounded gathered context while
preserving Hamiltonian order and semantic RNG addresses. An opaque captured
science object or precomputed proposal packet is not an admissible substitute.

Accepted relationship publication uses canonical packed storage throughout
the warm path. It copies live storage to a staged bank, resets and fills the
ordered event workspace, sorts by `(order_key, order_identity)`, applies the
exact existing relationship recurrence, and conditionally publishes staged
storage. `BoundedWrites` and `FoldStep` are retained only as domain-neutral
typed update values; planning, sorting, recurrence, gating, and publication
are one Core-owned KA algorithm.

## Structured Stage storage qualification

The reviewed storage capability admits an immutable structured value only
when the bounded record profile accepts its layout and every scalar leaf has
an exact centrally qualified backend load/store representation. Enum leaves
lower to their exact unsigned storage type. Unsupported `Int64` leaves remain
rejected, and CPU qualification of `Float64` does not imply GPU qualification.
This admits storage-safe `StageEvaluation{Float64}` field reads without a
general arbitrary-record escape hatch.

## Focused evidence

- Fresh `using CorePotts` with compiled modules disabled: pass.
- LocalWorksets Stage preparation and ABI qualification: 42/42 assertions.
- Accepted-copy relationship publication oracle: 25/25 assertions, including
  canonical event order, packed staged/live isolation, failure gating, and
  exact transaction results.
- Earlier checkerboard execution oracle: 16,495 assertions.
- Accepted-copy production scan: no deleted LocalWorksets authoring,
  preparation, execution, inspection, event, or workspace authority.
- Updated checkerboard oracle scan: no `.workplan` compatibility property and
  no `wait(event)` assumption for Core KA operations returning `nothing`.
- All retained kernels are KernelAbstractions kernels; this boundary adds no
  raw Metal path and no backend scientific branch.

## Gate status

PASS for the proposal/accepted-copy ownership deletion and the structured
storage capability boundary. This does not claim LM-6 proposal adoption: that
credit requires the typed `ResourceAccess` gathered-context compiler and must
delete the Core proposal machinery rather than wrap it.

# [Runtime boundary](@id runtime-boundary)

Status: target contract under pre-G6 hardening

PottsToolkit and CorePotts have one downward numerical boundary:

- PottsToolkit produces a scheduled symbolic system, runtime schemas, and an immutable private
  lowering request.
- CorePotts initializes and advances CPM state for an explicit algorithm/backend profile.
- CorePotts returns settled observations, checkpoints, capability reports, and generation-safe
  lifecycle receipts.
- PottsToolkit coordinates any native SciML component integrators outside copy-attempt kernels.

Runtime state is materialized once per `init`. A public executable is not a required authoring
stage, and an extension cannot introduce another model authority, scheduler, lifecycle engine,
parameter store, or checkpoint format.

## Native component boundary

A component declares scope, IO, cadence, duration per MCS, split order, solver policy,
initialization, events, lifecycle transfer, and required capabilities. Unsupported combinations
fail during preflight. GPU profiles cannot satisfy this contract through host fallback, scalar
device indexing, or hidden transfers.

Global component state and per-cell component pools use the same explicit publication boundary.
Per-cell pools are fixed-capacity and generation safe; creation, deletion, division, and transition
are applied from CorePotts lifecycle receipts.

## Documentation boundary

During G5H, only this narrow status manual is active. Legacy authoring pages are drafts and are not
support claims. Stable tutorials and API pages return only after they execute against the final
public surface in the strict documentation build.

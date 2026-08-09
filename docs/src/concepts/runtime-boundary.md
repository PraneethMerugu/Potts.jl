# [Runtime boundary](@id runtime-boundary)

Status: qualified G5H runtime contract

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

`CPMThenComponents()` stages one complete CPM step, then gives every due native island the same
staged Core snapshot. Native outputs are collected without mutating that snapshot and publish only
after every due solve succeeds. Islands therefore use simultaneous (Jacobi) coupling within a
boundary: declaration or scheduling order cannot let one island observe another island's new
output early.

G5H-3 retains native MTK continuous and discrete events through upstream structural compilation,
but admits only event-free coupled runtime profiles. The pinned public API exposes recursive event
collections but no stable public accessors for classifying every affect, initialization/finalization
effect, and reinitialization policy. Nonempty event sets or a structural event-count change therefore
fail preflight rather than relying on callback struct fields or private helpers.

The first executable native row is deliberately narrow: global scalar ODE islands in the audited
algebraic/differential expression family, on sequential `Float64` CPU execution, with the public
default `Tsit5()` instance and reviewed fixed-step options. Exact restart additionally binds the
scheduled-system fingerprint, logical state schema, native solver profile, complete MTK/SciML/Julia
stack, outer-event mode, and save/observation mode. A standard MTK `DAEProblem` can be constructed
and initialized from a retained scheduled DAE, but coupled DAE execution remains unsupported until
it has an exact continuation row.

Native execution is available only through the composed `init`/`step!`/`solve!` boundary. Extension
hooks for native problem construction, initialization, advance, and value extraction are private
implementation SPI and are not a public bypass around capability admission. Likewise, an outer
SciML discrete callback is a Functional-only in-process host protocol: its code and captures receive
a process-local identity, but it has no state codec and therefore cannot be checkpointed. Native
islands currently reject outer callbacks altogether.

## Capability boundary

Structural compilation, successful storage adaptation, or a working profile
for another algorithm, component scope, scalar type, or device is not runtime
evidence. Consult [Capability status](@ref capability-status) before choosing
an execution profile.

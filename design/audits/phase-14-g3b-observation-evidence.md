# Phase 14.1 G3-B Bounded Observation Evidence

Status: generic isolated CPU and KernelAbstractions CPU observation substrate accepted; assembled
Wang order and real GPU qualification remain open

Date: 2026-07-25

## Implemented generic substrate

The implementation adds two paper-independent observation primitives:

- a bounded per-cell table over arbitrary typed named cell-property bindings, with a coordinate
  tuple whose arity exactly matches the compiled moment dimension; and
- a lossless ownership snapshot that preserves the full N-dimensional owner lattice, cell
  activity/generation/type envelope, domain dimensions, spacing, and boundary semantics.

The cell table is indexed by bounded persistent cell-slot capacity. Active row count is recorded
separately, inactive holes are excluded from publication, and published rows retain ascending
persistent identity. Device workspaces, status, coordinate columns, and property columns adapt as
one tree. Host publication occurs only at the requested observation boundary.

Observation publication records target MCS, derived source MCS, publication epoch, model
fingerprint, execution profile, semantic seed, capacity, schema fingerprint, and typed cell
generation. Required failures publish neither a record nor a schedule/epoch advance. Completed-MCS
checkpoint state retains last-publication positions and epochs so restart neither duplicates nor
skips a record.

## Focused evidence

The command

```text
julia --project=. --startup-file=no -e 'using Test, CorePotts, SciMLBase, KernelAbstractions; include("test/test_phase14_bounded_observations.jl")'
```

from `lib/CorePotts` passes 107/107 assertions:

- 45 exact table schema, ordering, metadata, adaptation, and read-only assertions;
- 23 capacity/nonfinite failure-atomicity assertions;
- 15 exact, independent, shape-preserving ownership assertions;
- 11 genuine three-dimensional table and ownership assertions; and
- 13 completed-MCS restart continuity assertions.

The two-dimensional fixture binds the exact fourteen Wang source columns without embedding those
names in runtime code. The three-dimensional fixture binds a different one-column model and proves
that coordinate names become `x`, `y`, and `z` and that ownership arrays retain their `(3,3,3)`
shape.

The complete CorePotts package suite then passes 3,518/3,518 assertions on Julia 1.12.6 with the
observation, persistence, relationship, polarity, force, field, exchange, and prior regression
fixtures included.

## Claim boundary

This evidence supports generic declaration, isolated sequential CPU behavior, the
KernelAbstractions CPU execution view, failure/overflow atomicity, and completed-MCS persistence.
The assembled Wang order and real GPU qualification remain open. This evidence does not yet
support assembled sequential Wang behavior, order/boundary visibility, whole-plan steady-state
allocation, real Metal or ROCm execution, or paper reproduction.

# [Architecture](@id architecture)

Status: target architecture under pre-G6 hardening

Potts.jl separates symbolic model authority, numerical execution, and presentation:

```text
PottsToolkit
  PottsSystem + native MTK component islands
          │ complete / structural mtkcompile
          v
  scheduled PottsSystem + coupling schemas
          │ PottsProblem / init / solve
          v
CorePotts CPM runtime <-> native SciML component integrators
          │ settled observations and solutions
          v
MakiePotts / analysis
```

## PottsToolkit

PottsToolkit owns the public symbolic and SciML-facing product:

- typed Potts statements, names, hierarchy, units, parameters, and observations;
- composition, completion, validation, source-located diagnostics, and inspection;
- structural `mtkcompile` and explicit component IO, time, scope, and coupling schedules;
- `PottsProblem`, late private lowering, integrator/solution integration, and symbolic indexing.

An external ModelingToolkit system remains native through structural compilation. PottsToolkit
does not recreate that system by copying equations, unknowns, parameters, defaults, events, or
hierarchy into a parallel Potts representation.

## CorePotts

CorePotts is the independently testable numerical kernel. It owns CPM state and invariants,
proposal and acceptance semantics, trackers, relationships, generation-safe lifecycle,
counter-based randomness, checkpoints, and backend execution. It has no ModelingToolkit dependency
and does not execute an external numerical solver.

CorePotts publishes settled coupling arrays and lifecycle receipts. PottsToolkit uses those public
boundaries to coordinate native component integrators.

## Time

The completed integer Monte Carlo step is the master CPM clock and lifecycle boundary. Each native
time-dependent component declares a physical duration per MCS and a named split policy. MTK clock
objects are not the master scheduler.

## MakiePotts

MakiePotts consumes explicit public observations and solutions. It cannot mutate simulation state,
advance time, trigger synchronization implicitly, or redefine scientific semantics.

This page describes the accepted target boundary, not a claim that every part has completed
qualification. See [Capability status](@ref capability-status).

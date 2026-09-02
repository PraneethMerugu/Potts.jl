# [Architecture](@id architecture)

Potts.jl separates symbolic model authority, numerical execution, and presentation:

```text
Potts
  PottsSystem + native MTK component islands
          │ complete / structural mtkcompile
          v
  scheduled PottsSystem + coupling schemas
          │ PottsProblem / init / solve
          v
CorePotts CPM runtime <-> native SciML component integrators
     │ uses                    │ publishes settled observations
     v                         v
LocalMath              MakiePotts / analysis
     │ portable launches
     v
KernelAbstractions
```

## Potts

Potts owns the public symbolic and SciML-facing product:

- typed Potts statements, names, hierarchy, units, parameters, and observations;
- composition, completion, validation, source-located diagnostics, and inspection;
- structural `mtkcompile` and explicit component IO, time, scope, and coupling schedules;
- `PottsProblem`, late private lowering, integrator/solution integration, and symbolic indexing.

An external ModelingToolkit system remains native through structural compilation. Potts
does not recreate that system by copying equations, unknowns, parameters, defaults, events, or
hierarchy into a parallel Potts representation.

## CorePotts

CorePotts is the independently testable numerical kernel. It owns CPM state and invariants,
proposal and acceptance semantics, trackers, relationships, generation-safe lifecycle,
counter-based randomness, checkpoints, and backend execution. It has no ModelingToolkit dependency
and does not execute an external numerical solver.

CorePotts publishes settled coupling arrays and lifecycle receipts. Potts uses those public
boundaries to coordinate native component integrators.

## LocalMath

LocalMath is an independently testable execution substrate beneath
CorePotts. It owns validated local topology, declared reads and destinations,
bounded workspace, independent/combined/resolved output mechanisms, lifetime,
inspection, and central lowering to KernelAbstractions kernels. It relies on
KernelAbstractions implicit ordering and does not implement a scheduler.
Every package-owned spatial kernel uses that same KernelAbstractions path;
backend extensions adapt storage and report concrete device support but do not own raw
vendor kernel, launch, or synchronization implementations.

LocalMath does not own CPM physics, clocks, randomness, acceptance,
Hamiltonian folding, lifecycle transactions, checkpoints, or solver behavior.
Those remain domain responsibilities. Hardware-neutral kernel source is also
distinct from runtime support: the currently tested execution paths
are CPU and real Metal, not untested CUDA or ROCm claims.

## Time

The completed integer Monte Carlo step is the master CPM clock and lifecycle boundary. Each native
time-dependent component declares a physical duration per MCS and a named split policy. MTK clock
objects are not the master scheduler.

## MakiePotts

MakiePotts consumes explicit public observations and solutions. It cannot mutate simulation state,
advance time, trigger synchronization implicitly, or redefine scientific semantics.

See [Capability status](@ref capability-status) for the exact admitted
conjunctions. Architecture does not broaden a backend or solver claim.

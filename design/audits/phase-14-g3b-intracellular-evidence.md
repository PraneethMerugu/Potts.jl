# Phase 14.1 G3-B Intracellular Evidence

Status: generic sequential CPU and portable KernelAbstractions CPU increment accepted; RoadRunner
oracle, assembled Wang closure, and real GPU qualification remain open

Date: 2026-07-25

## Scope

This record covers the generic cell-owned affine state and initialization substrate required by
the Wang intracellular law. It does not claim G3-B completion, source-runtime equivalence, or
Metal/ROCm qualification.

The implementation provides:

- a generic `AffineCellAdvance` whose property roles are type parameters rather than Wang names;
- exact advancement of `dx/dt = constant + input - decay*x`, including the zero-decay branch;
- a generic semantic-RNG `UniformCellInitialization` with explicit namespace identity;
- structure-of-arrays state and semantic time with preallocated candidate/status workspace;
- sequential CPU validation, candidate-only execution, conditional publication, failing slot, and
  publication epoch;
- descriptor-free KernelAbstractions initialization, advance, and commit kernels;
- one coupled runtime whose checkpoint payload contains the authoritative publication epoch but
  omits candidate/status workspace;
- candidate/snapshot isolation in the canonical phase executor; and
- `Adapt` support for all runtime workspace arrays.

For Wang, the generic law is instantiated as `drac/dt = a+s-0.1rac`, duration 2880, `a=1`, with
`rac` initialized uniformly on `[0,30)` from the registered semantic RNG namespace. One
source-`start()` advance occurs before finalized target MCS 0. Scheduled advances begin at target
122 and continue through target 500.

## Executed evidence

The focused Phase 14 run passes 50/50 intracellular assertions. They prove:

- exact CPU and portable semantic-RNG initialization agreement and the `[0,30)` range;
- the registered startup advance;
- source 210/target 211 equilibrium 10 when the ODE reads signal zero;
- source 211/target 212 equilibrium 50 when the ODE reads same-MCS signal four;
- a short-duration analytic solution;
- exact `PeriodicMCS(122,1; stop=500)` scheduling;
- CPU and portable agreement for the affine closed form;
- three ordered portable launches and zero unobserved transfers;
- zero warmed sequential CPU allocations;
- nonfinite-input failure with unchanged state, semantic time, and publication epoch;
- coupled candidate/snapshot isolation; and
- publication-epoch checkpoint restore without persisting execution workspace.

The complete focused command also passed 740 scientific-Hamiltonian, 125 normalized-kernel, 8
fixed-domain/obstacle, 10 fixed-exterior, 136 general continuous/field-coupling, and 45
delay/event/mapping/adapter assertions.

The complete CorePotts package suite then passed 3,209/3,209 assertions on Julia 1.12.6. The G3-B
entry, G3-A, Phase 14.0, Phase 13 API-inventory, and repository-structure gates also pass. This is
a working-tree implementation baseline; the final closure packet still requires the exact clean
commit and artifact hashes registered by the current closure contract.

## Explicitly open

G3-B still requires:

1. the pinned libRoadRunner integrator/tolerance/raw-output oracle;
2. comparison of controlled RoadRunner traces under a preregistered source-profile rule;
3. the relationship, alignment/force, observation, and canonical Wang assembly rows;
4. completed-MCS assembled restart at the registered boundaries; and
5. a clean-commit full regression/evidence manifest.

Real Metal and ROCm execution is G3-C. The KernelAbstractions CPU result proves the portable
execution shape and conditional-publication ABI only.

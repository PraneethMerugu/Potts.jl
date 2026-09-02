# Auxiliary Constraints and Mechanical State

Status: Accepted for stable volume and surface mechanics; equilibrium real-HST support is rejected

## Purpose

Auxiliary state is a first-class scientific capability of Potts.jl. It is not an optional field
coupling layered onto a completed CPM clock. This document distinguishes equilibrium constraints
from fluctuating mechanical models and defines their state, execution, randomness, backend, and
lifecycle obligations.

First-class status does not grandfather the historical `HST...Penalty` implementations or their
detailed-balance claims. Stable support follows the laws derived here.

## Scientific Categories

### Equilibrium Auxiliary Constraints

An equilibrium auxiliary constraint introduces positive, real, sampleable state with an explicit
joint distribution. The implementation MUST provide:

- the joint density over lattice and auxiliary state;
- an auditable marginalization establishing the claimed lattice model;
- the fixed-auxiliary copy-attempt contribution;
- an auxiliary transition preserving the declared conditional distribution; and
- the equilibrium and kinetic interpretation of the composed process.

The word `Hubbard-Stratonovich` MUST appear in a public type or guarantee only when the implemented
identity is a valid Hubbard-Stratonovich transformation. No such stable family is currently
accepted.

### Fluctuating Mechanical State

A fluctuating pressure, tension, or related mechanical variable defines its own stochastic or
deterministic dynamics. It MUST declare its constitutive mean, relaxation law, noise law, coupling to
copy attempts, and kinetic interpretation. It MUST NOT inherit equilibrium, marginal-equivalence,
or detailed-balance claims from an auxiliary constraint with superficially similar storage.

Equilibrium and mechanical families MAY both be stable when their separate claims are satisfied.
They MUST NOT share one ambiguous public algorithm or component name.

## Stable Volume and Surface Laws

### Classical Equilibrium Constraints

The stable equilibrium volume and surface constraints remain the ordinary real Hamiltonians

```text
H_O = lambda * (O - O_target)^2,
```

where `O` is finite-cell volume or the declared surface metric. Their copy deltas are evaluated
exactly, including the `lambda * (delta O)^2` term. These components require no auxiliary state and
are the reference equilibrium formulations. A parallel algorithm acquires an equilibrium claim only
through its own whole-round invariant-distribution evidence; the component does not confer that
claim by itself.

### Fluctuating Pressure and Tension Mechanics

The stable stateful families are `FluctuatingVolumePressure` and
`FluctuatingSurfaceTension`. For each active finite cell, let

```text
x = O - O_target
dq = eta * (2 * lambda * x - q) * d tau
     + sqrt(4 * eta * lambda * Theta) * dW.
```

`q` is pressure for volume and tension for surface, `eta > 0` is its MCS-rate relaxation,
`lambda >= 0` is the constitutive stiffness, and `Theta >= 0` is the explicitly selected mechanical
noise scale. `Theta` defaults to the algorithm temperature only through a visible constructor
default recorded in provenance; it is not an identity between thermodynamic and active mechanical
noise.

With `x` frozen over a semantic interval `h`, the exact update is

```text
alpha = exp(-eta * h)
q' = alpha * q + (1 - alpha) * 2 * lambda * x
     + sqrt(2 * lambda * Theta * (1 - alpha^2)) * normal(0, 1).
```

At a fixed mechanical snapshot, a copy contributes

```text
W_mechanical = sum(q_cell * delta O_cell)
```

over its finite losing and gaining cells. Volume uses exact `-1` and `+1` changes; surface uses the
same declared metric and exact tracker deltas as the corresponding surface Hamiltonian. Positive
pressure therefore opposes volume gain, and positive tension opposes surface gain.

This is a coupled stochastic mechanical process. It is not a sampler for the classical quadratic
Hamiltonian, does not claim detailed balance, and does not become the exact quadratic copy delta by
setting `q = 2 * lambda * x`, because the finite-copy `lambda * (delta O)^2` contribution is absent.
Mechanical work is reported separately from conservative `delta_h` even when the acceptance law
uses their sum.

### Why the Historical HST Claim Is Rejected

For positive `a`, the Gaussian identity for a repulsive quadratic is

```text
exp(-a * x^2) proportional to
    integral exp(-phi^2 / (4a) - imaginary_unit * phi * x) d phi.
```

The linear coupling is imaginary. Replacing it with a real coupling changes the sign of the
quadratic after marginalization. More directly, a real joint term

```text
q^2 / (4 * lambda) - q * x
```

has conditional mean `+2 * lambda * x` but fixed-`q` copy work `-q * delta O`; changing the coupling
sign to obtain the historical `+q * delta O` changes the conditional mean to
`-2 * lambda * x`. The historical implementation used both the positive mean and positive work, so
it cannot be one real Gibbs joint law.

Potts.jl therefore removes the public `HST...` names and their detailed-balance claims. A future
equilibrium augmentation must provide a positive sampleable joint density and useful execution
benefit before becoming stable. A complex or signed-weight Hubbard-Stratonovich representation is
outside the CPM probability-kernel contract.

## Required Component Scope

The stable paper scope MUST support:

- per-cell fluctuating volume pressure; and
- per-cell fluctuating surface tension.

Length and focal-point state remain Experimental and do not justify a universal auxiliary framework
in Phase 7. They become first-class only after their geometry, periodic behavior, mechanical law,
and lifecycle semantics pass their own evidence gates. Generic storage does not transfer a
scientific proof from one observable to another.

## Potts Authoring

Potts authoring is organized by scientific concern. Conceptual spellings include a classical
quadratic volume or surface constraint and a separately named fluctuating-pressure or
fluctuating-tension mechanical component. There is no stable equilibrium-auxiliary spelling. Exact
Level 1 constructors are `Volume`, `Surface`, `FluctuatingVolumePressure`, and
`FluctuatingSurfaceTension`. The fluctuating families are first-class mechanical components, not
alternative implementations of the equilibrium constraints. Public `HST...` names are removed.
Users MUST NOT construct device buffers, RNG coordinates, or update kernels directly.

Mechanical noise uses an explicit typed value such as `IndependentNoise(theta)` or
`AcceptanceTemperature()`. There is no invisible numerical default coupling mechanical noise to the
acceptance law. `AcceptanceTemperature()` is a deferred semantic reference resolved and recorded
during model--algorithm preflight.

`explain` MUST report the category, state variable, target or constitutive law, time interpretation,
algorithm compatibility, backend support, lifecycle support, and evidence level.

## State Ownership

Cell mechanical state belongs to a cell slot and generation. Medium has no finite-cell mechanical
slot. Inactive and retired slots contain canonical cleared state. Reusing a numerical slot creates a
new generation and new auxiliary random identity. Multiple instances of one family receive distinct
stable component identities.

Compiled storage remains backend resident and follows the accepted descriptor/storage separation.
The component declares its state schema, read and write scope, initialization law, update law,
checkpoint representation, and capability requirements through ordinary CorePotts component
protocols. It does not introduce a special simulator or parallel inheritance hierarchy.

## Initialization

A future equilibrium auxiliary constraint samples its exact conditional distribution given the
realized initial lattice and properties by default. An explicitly selected deterministic
conditional-mean initializer MAY be provided and MUST be recorded in provenance. Initialization
uses a dedicated semantic stream and does not shift evolution draws.

The stable pressure and tension mechanics accept an explicit initial value, the constitutive mean
`2 * lambda * (O - O_target)`, or a draw from the frozen-observable stationary normal law. The
constitutive mean is the default. The selected initializer is recorded in provenance. An arbitrary
silent zero is prohibited unless zero is explicitly requested.

## Normalized Time and Randomness

Mechanical evolution uses MCS units and scientifically defined subintervals `delta_tau`; raw sweep
or kernel-launch count is never time. The stable mechanics use symmetric composition over each
algorithm-defined semantic sub-round:

```text
advance mechanical state by delta_tau / 2
execute proposal transactions for delta_tau
advance mechanical state by delta_tau / 2
```

`delta_tau` values across all sub-rounds in one completed MCS MUST sum exactly to one. Sequential
execution uses one `delta_tau = 1` sub-round, checkerboard uses each realized color's mutable-site
fraction, and lottery uses `1 / (Delta + 1)` for each of its `Delta + 1` topology-derived rounds.
Ineligible lottery sites still undergo their cell-wide mechanical clock through the round update;
the update is not conditioned on proposal activation. Two compositions that change observable
kinetics are different coupling algorithms.

Evolution draws use `AuxiliaryEvolutionStream` and stable addresses containing component identity,
cell generation, MCS, semantic subinterval, update phase, and draw identity. Initialization uses
`AuxiliaryInitializationStream`. State and evolution remain on CPU, Metal, or ROCm according to the
current backend contract, with no incidental steady-state host synchronization.

## Algorithm Compatibility and Conflicts

Every named algorithm publishes mechanical-component capabilities. An unsupported combination fails
during initialization with the incompatible component, violated guarantee, and compatible
alternatives. There is no silent host fallback or silent replacement with a classical penalty.

Parallel conflict derivation includes every mechanical read and write. Proposals involving the same
cell conflict unless the component supplies an auditable joint-transaction law. The stable pressure
and tension families use the existing exclusive finite-cell claims: a proposal commits only if it
owns every finite-cell claim. Atomics or linear-looking local code alone do not establish scientific
independence. Bounded-stale or relaxed mechanical algorithms require separately visible names and
guarantee profiles.

## Lifecycle and Continuation

Mechanical state participates in snapshots when scientifically observable and in checkpoints
whenever it can affect continuation. Checkpoints include the mechanical contract and RNG versions.

Division, transition, extinction, and slot reuse follow the accepted transaction law in
`lifecycle.md`. Mechanical inheritance or conservation is family specific. Missing lifecycle
semantics make the operation unsupported rather than selecting a generic fallback. Every stable
family explicitly declares initialization, division, transition, progressive-death, immediate-
death, extinction, retirement, and reuse behavior where applicable. A policy may explicitly reject
an operation; omission is not an implicit reset.

The family plans lifecycle updates from the common pre-lifecycle snapshot and commits through the
same property transaction used by ordinary state. A GPU-qualified family lowers each supported
policy to concrete bounded device behavior. It MUST NOT rely on a family enum, parallel inheritance
hierarchy, arbitrary callback, per-event allocation, or host intervention.

For an equilibrium auxiliary family, every state-creating or identity-changing operation requires a
derived post-operation joint conditional distribution and validation evidence. A mechanical family
instead states its physical conservation, transformation, initialization, or reset meaning and does
not inherit an equilibrium claim merely by using the same storage protocol.

### Stable pressure and tension division

Pressure and tension are intensive generalized forces. They are not extensive conserved quantities:
binary division MUST NOT halve them or preserve their sum across descendants.

The default division policy is **constitutive reset**. After lattice partition, descendant types,
target and strength policies, and derived volume or surface observables have committed, each
descendant receives

```text
q_r = 2 * lambda_r * (O_r - O_target_r).
```

This deterministic default introduces no division noise and makes no claim that pre-mitotic
mechanical memory survives division.

Two explicit alternatives are stable:

- **Intensive preservation** copies the pre-division `q` to both descendants. This preserves
  mechanical memory but is not conservation; each value subsequently relaxes toward its own mean.
- **Stationary redraw** independently samples each descendant from
  `Normal(2 * lambda_r * (O_r - O_target_r), 2 * lambda_r * Theta_r)` after post-division state is
  final.

Stationary-redraw addresses include the lifecycle RNG contract, division event identity, MCS,
component instance, parent identity and generation, descendant role, child generation where
applicable, and draw identity. They do not consume initialization or ordinary evolution addresses.
General correlated daughter noise is unsupported until a separately named policy supplies a
positive covariance law and conformance evidence.

### Growth, transition, death, and reuse

Growth, target changes, progressive shrink death, and a type transition that retains the same
compatible mechanical component preserve `q` continuously. Changed target, strength, noise, or type
parameters affect subsequent OU evolution, allowing the accepted relaxation law to approach its new
constitutive mean without an unrequested instantaneous jump.

An explicit transition MAY instead request constitutive reset or stationary redraw. Adding a
mechanical component invokes its declared initializer after destination state is valid. Removing a
component clears its state in the type-transition transaction.

Immediate death and stochastic extinction clear pressure and tension atomically with retirement.
Progressive shrink death preserves and evolves them until terminal removal. Reusing a numerical slot
creates a new generation and invokes ordinary mechanical initialization; preserving retired state is
always invalid.

### Independent biological policies

Mechanical-state lifecycle policy does not determine target or strength inheritance. Target volume
MAY use an explicit conservative split, including exact-total stochastic rounding where required.
Strength, relaxation, and noise parameters follow their own schema or component/type policies.

Surface target is not an extensive quantity and MUST NOT receive an undocumented halving default. A
named similar-shape policy MAY scale a target by `f^((D - 1) / D)` for daughter volume fraction `f`,
but it must declare its geometric and surface-metric assumptions. Otherwise the model supplies an
explicit surface-target policy or division with that component is unsupported.

Pressure or tension division behavior is evaluated only after these independent biological policies
and derived observables are final.

## Lean Conformance Gate

A stable family needs:

- the exact OU transition against deterministic and statistical reference values;
- constitutive-mean and stationary-normal initialization evidence;
- a reference mechanical-work calculation and semantic RNG evidence;
- algorithm-level transaction and normalized-time tests;
- constitutive-reset, intensive-preservation, stationary-redraw, transition-continuity, death-clear,
  and slot-reuse lifecycle tests;
- statistical CPU, Metal, and ROCm evidence in required dimensions; and
- no incidental steady-state host synchronization.

This contract does not require speculative generic covariance machinery, unit-bearing device
kernels, or a universal non-Gaussian auxiliary protocol. Such facilities are added only when a
concrete scientific family requires them.

## Literature Basis

- [Hubbard, Calculation of Partition Functions (1959)](https://doi.org/10.1103/PhysRevLett.3.77)
- [Graner and Glazier, Simulation of Biological Cell Sorting Using a Two-Dimensional Extended Potts Model (1992)](https://doi.org/10.1103/PhysRevLett.69.2013)
- [Magno, Grieneisen, and Marée, The biophysical nature of cells: potential cell behaviours revealed by analytical and computational studies of cell surface mechanics (2015)](https://doi.org/10.1186/s13628-015-0022-x)

# Time and Monte Carlo Steps

Status: Accepted except where marked otherwise

## Public Time Unit

The public unit of simulation time is the Monte Carlo step (MCS).

Let `N` be the number of mutable ownership sites in the realized domain. One reference MCS consists
of exactly `N` independent copy attempts. Recipient sites are sampled uniformly from those sites
with replacement. Exterior ghosts and excluded obstacle storage are not sites and do not contribute
to `N`. Ordinary mutable medium sites do contribute.

`step!(integrator)` MUST advance the simulation by exactly one MCS. Fractional public steps are not
part of specification version `0.2-draft`.

## Copy-Attempt Accounting

One reference copy attempt consists of:

1. Uniformly selecting one recipient site.
2. Uniformly selecting one direction from the proposal neighborhood.
3. Resolving the donor site or determining that the direction is invalid.
4. Producing a no-op or evaluating a proposal.

The following count toward the `N` attempts:

- A donor and recipient with the same owner
- A selected no-flux direction whose donor coordinate lies outside the domain
- A proposal rejected by the acceptance rule

Same-owner and invalid no-flux attempts MUST be no-ops and MUST NOT evaluate or commit tracker or
energy mutations.

At a no-flux boundary, invalid directions MUST become no-ops. Implementations MUST NOT clamp an
invalid coordinate onto a boundary site or silently renormalize over remaining directions.

## Removed Public Controls

`sweeps_per_step` is not part of the intended public semantics and SHOULD be removed.

`active_fraction` MUST NOT control public simulation time. An optimized algorithm MAY use an internal
activation fraction, but it MUST normalize its work to one MCS and MUST report its attempt accounting.

## Internal Rounds

An optimized algorithm MAY divide one MCS into internal rounds. Internal rounds are execution details
and MUST NOT be exposed as independent simulation time.

Every internal round MUST account for a defined MCS fraction `delta_tau`, with:

```text
sum(delta_tau for all rounds in one step) = 1 MCS
```

Algorithm kernel-launch count MUST NOT define time.

## Lottery Normalization

The lottery algorithm uses expected proposal-budget normalization. Its internal topology-dependent
activation fraction and round count MUST be calculated by the algorithm rather than supplied as
user-facing time controls.

An **activated attempt** is a topology-lottery winner that has received one copy-attempt
opportunity. Sites that participate only by drawing a ticket are scheduler work, not copy attempts.
Once activated, an attempt consumes the MCS budget even when it becomes a same-owner or invalid-
boundary no-op, loses a dynamic semantic conflict, is rejected, or is accepted. A dynamic conflict
loser MUST NOT be retried or replaced by extra work in the same MCS.

Every mutable recipient site MUST receive one activated attempt per MCS in expectation. A global
expectation of `N` is necessary but insufficient: boundary or low-conflict-degree sites MUST NOT be
systematically over-activated. Qualification MUST measure per-site and boundary-class activation,
waiting-time distributions, repeated activation, and spatial correlation against the sequential
reference process.

Activation probabilities, full-round count, and residual expected work MUST be derived solely from
the compiled realized topology and conflict relation. They MUST NOT respond to the current number or
shape of cells, acceptance rate, observed conflict rate, or other evolving model state. A topology
for which this calibration has not been established is unsupported by stable `LotteryCPM`; model
initialization MUST fail with the reason and compatible alternatives rather than silently using a
biased schedule.

Compilation MAY construct full rounds plus one residual round. The expected round contributions
MUST sum to one MCS. Any residual placement and any semantically meaningful full-round order MUST be
randomized per MCS through addressed algorithm streams so that one permanently special final round
does not define the kinetics. Kernel count still does not define time.

The first stable Cartesian calibration uses the realized compiled conflict graph. If site `i` has
degree `d_i` and the graph has maximum degree `Delta`, one MCS contains `Delta + 1` randomly ordered
rounds. In each round site `i` is independently eligible with exact rational probability
`(d_i + 1) / (Delta + 1)` and is activated only when its collision-free 128-bit semantic ticket is
the strict maximum over itself and its realized neighbors. The local-maximum probability is
`1 / (d_i + 1)`, hence every site has round activation probability `1 / (Delta + 1)` and exactly one
activated opportunity per MCS in expectation. Ineligible sites still draw tickets and can block an
eligible neighbor; this scheduler work is intentional and is not an activated attempt.

Actual activated-attempt and proposal counts MAY fluctuate. The algorithm MUST report at least:

- Ticket participants or scheduler candidates
- Activated attempts
- Dynamic conflict losers
- Same-owner and invalid-boundary no-ops
- Constraint and acceptance rejections
- Accepted moves

Required accounting does not make host-visible reporting part of an unobserved MCS. An algorithm
MAY retain bounded counters or per-attempt dispositions in its backend-resident workspace and
aggregate the latest completed MCS only when `current_mcs_report` is requested. That observation
MAY add a reduction launch and one declared host-observation boundary; ordinary stepping MUST NOT
materialize or eagerly reduce diagnostic accounting that no consumer requested. Deferred reporting
MUST return exactly the same partition for the latest completed MCS as eager accounting would and
MUST NOT alter proposal, acceptance, commit, lifecycle, RNG, or time semantics.

The equilibrium and kinetic consequences of expected normalization remain under investigation and
MUST be documented in the algorithm's guarantee profile.

## Checkerboard Sweep Scheduling

The stable site-sweep family is named `CheckerboardSweepCPM`. Every mutable site is scheduled exactly
once per MCS without replacement. Its color classes execute sequentially, and a later color observes
mutations committed by earlier colors in the same MCS.

Color order MUST be randomized once per MCS using a dedicated RNG stream. Proposals within one color
pass observe one common logical snapshot and commit together through the algorithm's transaction
law.

The existence of a conflict-free lattice coloring does not by itself establish reference kinetic or
equilibrium equivalence because nonadjacent sites may modify shared cell-wide state. A deterministic
site sweep has a more regular waiting-time law than recipient sampling with replacement and MUST NOT
be presented as ordinary sequential CPM kinetics.

## Algorithm Comparability

All public algorithms MUST express time in normalized MCS units. Each algorithm MUST expose, where
applicable:

- Equilibrium guarantee
- Kinetic guarantee
- Attempt-normalization guarantee
- Reproducibility guarantee
- Supported topology and dimensionality
- Backend capability requirements
- Evidence category: proof, reference equivalence, statistical validation, or experimental

The unqualified term "exact" MUST NOT serve as an algorithm guarantee.

### Stable Phase 7 Capability Matrix

Algorithm stability does not require every component to run under every scheduler. The accepted
paper capability boundary is:

| Capability | Sequential families | `CheckerboardSweepCPM` | `LotteryCPM` |
| --- | --- | --- | --- |
| Local/cell-wide Hamiltonians, fields, drives, and rate modifiers | Supported subject to the selected equilibrium profile | Supported with declared snapshot access | Supported with declared snapshot access |
| Fluctuating volume pressure and surface tension | `SequentialCPM` only | Supported | Supported |
| Exact connectivity constraint with proposal-private traversal | Supported | Rejected at initialization | Rejected at initialization |
| Unwrapped moments and focal-point links | Supported | Rejected at initialization | Rejected at initialization |

These rejections are valid stable capabilities, not silent fallbacks or incomplete clocks.
Fragmentation is valid model behavior unless a user selects the connectivity constraint; users who
select it can use the sequential family. Parallel connectivity or focal coupling becomes a separate
optimization task only when a concrete paper workload requires it and its transaction law is
derived. It does not block qualification of the current parallel processes.

## Event Time

Stable events are scheduled at integer MCS boundaries. Each event owns its own schedule. A global
system-wide check interval is not part of the intended semantics.

MCS `0` is the finalized initial condition, not an ordinary lifecycle boundary. Stable lifecycle
schedules begin at positive integer MCS values; initialization behavior is expressed through the
initialization protocol. Periodic schedules use an inclusive positive start, positive period, and
optional inclusive stop as specified in [Lifecycle](lifecycle.md).

## Parameter Time Scale

Temperature, penalty parameters, growth rates, event schedules, auxiliary relaxation rates, and
other temporal model parameters MUST be interpreted in MCS units independently of the chosen
execution algorithm.

An algorithm whose kinetics are not reference-equivalent MUST document the limitation and any
calibration. Routine runtime warnings are not required.

## Auxiliary Time Integration

Auxiliary physics MAY update between scientifically defined internal subintervals, but MUST NOT use
raw kernel launches as a time scale.

If one MCS is partitioned into auxiliary intervals `delta_tau_r`, then:

```text
sum(delta_tau_r) = 1 MCS
```

For stochastic internal-round counts, auxiliary time SHOULD use expected normalized work rather than
the realized random proposal count, so contention does not make the physical clock stochastic.

A symmetric operator-splitting strategy is the accepted default composition for first-class
auxiliary constraint or mechanical state when the component's mathematics does not require another
invariant composition:

```text
advance auxiliary state by delta_tau / 2
execute normalized proposal work for delta_tau
advance auxiliary state by delta_tau / 2
```

Every such component MUST define its augmented or mechanical state law, update over `delta_tau`, RNG
addressing, algorithm compatibility, and claimed invariant or kinetic interpretation. A derived
invariant composition overrides the symmetric default. PDE and other external-field evolution
remain separately selected SciML couplings and are not implied by this rule.

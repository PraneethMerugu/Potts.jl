# Energy, Proposals, Acceptance, and Trackers

Status: Accepted, except where explicitly marked Under Investigation

## Purpose

This document defines copy terminology, scientific component categories, conservative energy,
nonconservative drives, hard constraints, proposal laws, acceptance laws, tracker invariants,
interface metrics, parameter scaling, compatibility claims, and required validation.

Conventional Cellular Potts dynamics and equilibrium sampling are both first-class. They are
separately named and MUST NOT inherit each other's scientific claims.

## Copy Terminology

A copy proposal has:

- A **recipient site**, which may be overwritten
- A **donor site**, whose owner identity is proposed for copying
- A **losing identity**, the current recipient owner
- A **gaining identity**, the donor owner

The copy direction is donor to recipient. Public and normative APIs MUST NOT use ambiguous `source`
and `target` names without defining which site is overwritten.

## Scientific Component Categories

Every state-evolution component belongs to exactly one semantic category:

- Hamiltonian term
- Nonconservative drive
- Hard constraint
- Derived tracker
- Equilibrium auxiliary constraint
- Fluctuating mechanical state
- Lifecycle operation

The implementation MAY share lower-level machinery, but a catch-all "penalty" classification MUST
NOT obscure whether a component contributes to global energy or invalidates equilibrium claims.

### Hamiltonian Terms

A Hamiltonian term defines a finite scalar `energy(component, state)` on every valid state in its
declared domain. For every legal single-site proposal:

```text
delta_energy(component, state, proposal)
    = energy(component, apply(state, proposal)) - energy(component, state)
```

This identity is normative, including medium interactions, boundaries, flexible parameters, tracker
dependencies, and 2D/3D behavior.

The total conservative energy is:

```text
H(state)  = sum(term.energy(state) for term in Hamiltonian terms)
delta_H   = sum(term.delta_energy(state, proposal) for term in Hamiltonian terms)
```

Component summation uses a stable canonical order belonging to the numerical contract.

A component that cannot define such a scalar is not a Hamiltonian term. NaN or infinity from an
ordinary Hamiltonian evaluation is a model error rather than a hard-constraint signal.

### Nonconservative Drives

A drive contributes directional work or a dimensionless log bias without becoming part of `H`.
Drives MAY depend on copy direction, cell properties, fields, or history.

The acceptance report keeps conservative energy and every drive contribution separate. Energy-unit
drives are converted through their declared effective temperature; general active processes MAY
directly provide dimensionless log bias.

Chemotaxis MUST be classified as either a globally integrable field-coupling Hamiltonian or a
nonconservative drive. Familiar CPM chemotaxis syntax MAY lower to a drive, but provenance MUST state
that the resulting dynamics do not sample the conservative Hamiltonian.

### Hard Constraints

A hard constraint is a pure allowed/forbidden predicate over a snapshot and proposal. It MUST NOT
mutate lattice state, trackers, or properties while evaluating admissibility.

Hard constraints MUST NOT encode rejection by returning infinity, `typemax`, or NaN as energy. An
implementation MAY short-circuit constraint evaluation, while debug mode MAY report every failed
constraint.

An equilibrium claim is permitted only when constraints define a fixed admissible state space and
preserve reverse support. Connectivity is optional; fragmentation remains valid in its absence.
General fragmentation prevention and rigorously symmetric simple-connectivity restriction are
separately characterized constraints.

## Contact Hamiltonian

The conservative contact energy is an unordered-pair sum:

```text
H_contact = sum(
    weight(i, j) * J(type(owner(i)), type(owner(j)))
    for each unordered valid coupling edge {i, j}
    when owner(i) != owner(j)
)
```

Consequences:

- Each logical edge is counted once globally.
- Sites of the same owner have no interface energy.
- Distinct cells of the same type interact through `J[type,type]`.
- Distinct medium types interact when the model defines that contact.
- Disconnected regions of one conceptual medium type remain one owner.
- A copy delta changes only valid coupling edges incident to the recipient.
- Coupling weights satisfy `weight(offset) == weight(-offset)`.

A Hamiltonian contact matrix MUST be finite and symmetric under the declared numerical contract.
Truly asymmetric contact behavior is a directed drive. Missing pairs require an explicit default or
a complete specification.

## Proposal Families

Proposal and acceptance laws are independently represented, but only validated combinations receive
scientific guarantee profiles. The proposal object computes complete forward and reverse
probabilities.

### Neighbor-Site Copy

The conventional reference proposal is:

```text
recipient ~ Uniform(all N mutable ownership sites)
direction ~ Uniform(all proposal-neighborhood directions)
donor     = neighbor(recipient, direction)
```

Same-owner and invalid no-flux selections are no-op attempts and count in the `N`-attempt reference
MCS.

When multiple donor directions carry the same gaining identity, they produce the same destination
state. For uniform target-and-direction selection:

```text
q_forward proportional to the number of donor-neighborhood sites
                     owned by the gaining identity
q_reverse proportional to the number owned by the losing identity
                     after the proposed copy
```

The implementation MUST derive these multiplicities with unambiguous names. A generated proposal
with `q_forward = 0` is an internal error. Under Metropolis-Hastings, `q_reverse = 0` produces certain
rejection.

### Distinct-Neighbor Copy

A proposal selecting uniformly among distinct neighboring owner identities is under `SEM-ENG-004`.
It MUST NOT claim symmetric selection until reverse support, extinction, and connectivity conditions
are derived.

### Border-List and Thinned Proposals

Border or edge-list proposals are separately named proposal/time algorithms. They MAY reproduce an
embedded transition chain or expected clock after derivation, but do not silently replace the fixed
`N` recipient-selection reference process. Their state-dependent proposal probabilities and time
mapping are part of their guarantee profile.

## Acceptance Laws

Positive-temperature acceptance is evaluated from a total log ratio:

```text
log_R = -delta_H / T
        + log(q_reverse) - log(q_forward)
        + sum(drive_log_bias)
        + kinetic_modifier
```

Terms not applicable to a named law are explicitly zero. Acceptance probability is
`min(1, exp(log_R))`, evaluated stably in the log domain. An addressed uniform variate on `(0,1)` is
compared using one documented strict inequality. Exact probability-zero and probability-one cases
MAY skip evaluating the draw.

### Conventional Modified Metropolis CPM

The literature-compatible neighbor-copy law ignores proposal asymmetry:

```text
A(x -> y) = 1                    when delta_H <= 0
            exp(-delta_H / T)    when delta_H > 0
```

It is conventional modified-Metropolis CPM dynamics. It MUST NOT claim a Boltzmann stationary
distribution merely because its acceptance contains a Boltzmann factor. It MAY accept transitions
with no reverse proposal support.

### Metropolis-Hastings CPM

The equilibrium-targeting law is:

```text
A(x -> y) = min(1, exp(-delta_H / T) * q_reverse / q_forward)
```

This claim requires finite positive `T`, correct proposal probabilities, reversible support,
reciprocal constraints, no unintegrated drives or kinetic modifiers, fixed applicable population, and
a proof for the complete named algorithm.

### Zero Temperature

At `T = 0`, conventional modified Metropolis accepts downhill and neutral proposals and rejects
uphill proposals.

At `T = 0`, Metropolis-Hastings accepts downhill proposals only with reverse support, rejects uphill
proposals, and accepts neutral proposals with `min(1, q_reverse/q_forward)`. This is limiting dynamics,
not a finite-temperature Boltzmann ensemble.

A drive MUST define an explicit zero-temperature rule to be used at `T = 0`.

### Other Acceptance Laws

Barker acceptance is separately named and uses `A = R/(1+R)` with stable logistic evaluation.
Neutral `1/2` acceptance is not silently mixed into ordinary Metropolis.

Custom laws receive a structured proposal report and declare their equilibrium, numerical,
temperature, and zero-temperature capabilities.

## Kinetic Modifiers and Temperature

Morpheus-style positive yield is a named dissipative barrier:

```text
A = min(1, exp(-(delta_H + Y)/T))
```

CompuCell3D-style offset and Boltzmann-factor behavior are versioned compatibility modifiers. They
MUST reproduce the declared source convention rather than aliasing yield unless their formulas and
edge cases match.

Yield and offset are transition-level quantities and MUST NOT enter global `H`. Their use removes the
ordinary Boltzmann-equilibrium claim unless a separate invariant distribution is derived.

Core semantics absorb the Boltzmann constant into temperature. Importers MAY translate `(k,T)` to an
effective temperature while preserving source metadata.

A heterogeneous fluctuation-amplitude model explicitly defines a symmetric combining rule and medium
values. Symmetry alone does not establish one global thermodynamic temperature.

## Population and Lifecycle

Conventional lifecycle dynamics retire a finite cell that loses its last site according to the
lifecycle specification.

An equilibrium sampler with fixed cell population rejects a last-site loss when the proposal kernel
has no reversible cell-birth move. Growth, division, programmed death, transition, and ID retirement
make the overall model nonequilibrium unless embedded in an explicitly derived reversible ensemble.

## Derived Tracker Contract

Lattice ownership is authoritative. Volume, surface, centers of mass, inertia, neighbor relations,
and similar quantities are derived cached trackers and are read-only to users. Writable biological
variables use separate schema properties.

After every committed sequential proposal or parallel subround:

```text
cached_tracker(state) == recompute_tracker_from_lattice(state)
```

Equality follows the tracker's numerical profile. Every incremental tracker MUST have an independent
full recomputation oracle.

Tracker deltas are pure functions of the common snapshot and proposal. They are computed before
energy evaluation and applied transactionally exactly once only when the copy commits. Rejected,
forbidden, same-owner, and conflict-lost proposals do not mutate trackers.

Hamiltonian terms and drives access current, proposed, and delta tracker values through a semantic
proposal view rather than tuple position. Compilation deduplicates semantically identical tracker
requirements and rejects conflicting definitions.

Tracker drift discovered by strict/debug validation is an error with entity, MCS, and transaction
diagnostics. It MUST NOT be silently repaired. Representable bounds are validated and integer trackers
MUST NOT wrap.

Parallel proposals writing the same tracker entity conflict unless a proven joint transaction is
consistent with their acceptance law. Associative integer atomics do not make stale independent
energy evaluations correct.

Derived trackers MAY be checkpointed and verified or deterministically recomputed on load.

## Surface and Interface Metrics

Unweighted per-cell lattice surface is:

```text
lattice_surface(cell) = number of valid metric edges with exactly one endpoint owned by cell
```

A cell-cell edge contributes once to each cell's surface. A cell-medium edge contributes once to the
finite cell.

Global interface measure is a separate unordered-edge sum in which each unlike-owner edge contributes
once globally.

The following are distinct metrics:

- Lattice surface
- Weighted lattice surface
- Normalized geometric perimeter or surface
- Physical perimeter or surface with units

A target-surface component explicitly selects its metric and metric neighborhood. Integer metrics use
exact integer accumulation; weighted/geometric metrics declare floating accumulation.

The ordinary conservative surface law is `lambda * (S - S_target)^2`, with metric semantics defined
in [Cartesian Surface, Queries, and Fields](cartesian-surface-queries-and-fields.md). Equilibrium
auxiliary surface constraints and fluctuating surface-tension mechanics are separately identified
first-class families. They MUST NOT be silently substituted for the ordinary quadratic formulation.

Invalid no-flux directions are absent realized edges. They contribute nothing to energy, surface,
moments, reverse-edge multiplicities, or tracker deltas. A conventional bulk-direction proposal MAY
still draw such a direction and record a null attempt, as defined by its proposal law. Periodic
domains that alias a stencil direction onto the source or alias distinct directions onto one
neighbor are invalid unless an explicitly named multigraph relation is selected.

Proposal, coupling, tracker, spatial-query, adjacency, conflict, and connectivity-test neighborhoods
are independent semantic roles.

## Native Parameter Semantics

A bare parameter has one fixed meaning and MUST NOT silently change with topology or backend.

Native lattice-unit components explicitly use site count, unlike-edge count, weighted lattice metric,
or another declared discrete metric. Changing topology preserves their numeric values and SHOULD warn
that physical mechanics changed.

Normalized surface-mechanics components compile physical or continuous parameters to lattice
coefficients through a documented conversion. Changing topology recompiles those coefficients and
records the conversion.

If all energies are rescaled by `c`, compatibility conversion MUST also rescale temperature, yield,
offsets, and energy-unit drives by `c` to preserve acceptance probabilities.

Potts SHOULD accept dimensioned host-side quantities and validate units before lowering them
to device-compatible numbers. Lattice volume is site count; physical volume includes lattice spacing
and dimensionality.

Conventional compatibility presets default to source-appropriate lattice parameters. Physics-oriented
cross-topology examples SHOULD prefer normalized mechanics.

## Cross-Simulator Compatibility

Compatibility presets are versioned and control proposal, acceptance, time interpretation,
neighborhood roles, contact/surface counting, medium convention, temperature modifiers, extinction,
constraints, parameter scaling, and defaults.

Compatibility does not imply identical RNG sequences or trajectories. Each translated feature is
classified as:

- Exact semantic translation
- Exact after documented conversion
- Statistical behavioral compatibility
- Approximate translation
- Syntax-only import
- Unsupported

There is no unqualified simulator-compatibility claim. Reports name the simulator version and
supported subset.

Importers preserve source simulator, version, file checksum, original values, units/scaling, numeric
type IDs, and every conversion. Unsupported features error by default. Permissive import MAY retain
an untranslated placeholder but MUST NOT execute it silently.

Morpheus `norm`, `none`, and `classic` scaling remain distinct. CC3D acceptance variants and
fluctuation-amplitude rules are versioned. Artistoo border stepping maps to a separately named clock
and proposal. Asymmetric tables are translated according to documented source semantics or become a
drive.

Native extensions to a compatibility preset produce an explicitly reported hybrid model. Round-trip
export is promised only for a validated common subset.

## Compile-Time Scientific Claims

Constructors express intent; compiled capability checks earn guarantees.

An equilibrium request MUST fail when the compiled model contains an uncorrected asymmetric
proposal, irreversible lifecycle, nonintegrable drive, yield/offset modifier, asymmetric constraint,
heterogeneous temperature without a proof, missing global energy, or any other invalidating feature.

A compatibility request validates every feature against the versioned supported subset. The compiler
SHOULD generate a model report containing the Hamiltonian, drives, constraints, proposal and
acceptance equations, neighborhood roles, tracker metrics, units and conversions, equilibrium and
kinetic status, compatibility status, and reproducibility profile.

The historical ambiguous `MetropolisSampler` MUST be removed or renamed. Migration requires users to
choose conventional modified Metropolis or corrected Metropolis-Hastings explicitly.

## Diagnostics

Debug proposal traces include:

- Proposal family and semantic identity
- Donor, recipient, losing identity, and gaining identity
- Forward and reverse probabilities or multiplicities
- Forward and reverse support
- Constraint outcomes
- Current, proposed, and delta tracker values
- Per-term conservative energy deltas
- Per-drive log biases
- Temperature and combining rule
- Yield or offset contribution
- Total log acceptance ratio and probability
- Acceptance draw and final outcome

Public reports use qualified language such as "conventional modified-Metropolis CPM dynamics",
"detailed balance proven on the declared admissible state space", "driven nonequilibrium dynamics",
or "stationary distribution under investigation".

## Conformance Evidence

Every Hamiltonian term requires randomized local-versus-global delta tests covering finite cells,
media, same-type distinct cells, boundaries, 2D/3D, metrics, flexible parameters, and legal edge
cases.

Every proposal requires independent enumeration of all paths producing a destination state and
verification of reported forward and reverse probabilities.

Equilibrium claims require small-state transition matrices testing pairwise detailed balance when
claimed, invariant distribution, irreducibility, aperiodicity, and constraint-induced communicating
classes. Parallel claims test a whole color pass or lottery round rather than isolated proposals.

Compatibility validation uses hand-auditable energy fixtures, source-simulator proposal fixtures,
and ensemble comparisons. A neutral cross-simulator trace format records state, proposal, parameters,
expected deltas, proposal probabilities, and an acceptance result for a supplied uniform variate.

Importers require a curated corpus of real published models. Cross-simulator ensemble comparisons use
predefined margins for energy, volume, surface, acceptance, sorting, motility, and event observables.

Compatibility marketing is prohibited until its fixture corpus and conversion report pass on CPU and
all first-class GPU backends.

## Literature and Software Basis

- [CompuCell3D acceptance and fluctuation amplitudes](https://compucell3ddevelopersmanual.readthedocs.io/en/stable/intro_to_core_cc3d_objects.html)
- [Morpheus modified Metropolis, yield, neighborhoods, and kinetic terms](https://gitlab.com/morpheus.lab/morpheus/-/wikis/formalisms/diff?version_id=f4f2ba93b9378615f1bde4b48090a121b8f748b2&view=parallel&w=0)
- [Artistoo CPM implementation](https://raw.githubusercontent.com/ingewortel/artistoo/master/src/models/CPM.js)
- [Durand and Guesnet on proposal asymmetry, connectivity, and detailed balance](https://arxiv.org/abs/1609.03832)
- [Critical analysis of modified-Metropolis CPM](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0042852)
- [Poissonian CPM and nonequilibrium kinetics](https://arxiv.org/abs/2306.04443)
- [Morpheus cross-simulator surface-mechanics conversion](https://morpheus.gitlab.io/post/2023/06/12/cell-surface-mechanics/)
